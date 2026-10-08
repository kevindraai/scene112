class_name StreetAtmosphere
extends Node3D
## Bounded Dutch street lighting. Geometry/PBR assets remain the primary image.
## Attach after District._ready/assets; no gameplay input or mission state owned here.

const WetPaving = preload("res://shaders/wet_paving.gdshader")
const CONDITIONS := ["day", "dusk", "rain"]
const QUALITIES := ["portable", "balanced", "high"]
const LAMP_POINTS := [Vector3(-5,4.30,40.2),Vector3(7,4.30,40.2),Vector3(19,4.30,40.2),Vector3(31,4.30,40.2)]

var conditions := "day"
var quality := "balanced"
var renderer := ""
var _district: Node3D
var _world: WorldEnvironment
var _environment: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _sun_pose := Vector3(-48,-28,0)
var _lamps: Array[SpotLight3D] = []
var _reflection: ReflectionProbe
var _rain: CPUParticles3D
var _variants: Dictionary = {}
var _surfaces: Array[Dictionary] = []
var _tracked: Dictionary = {}
var _original_environment: Environment
var _original_sun: Dictionary = {}
var _paused := false
var _probe_revision := 0


func setup(district: Node3D) -> bool:
	if not is_instance_valid(district): return false
	var existing := district.get_node_or_null("StreetAtmosphere")
	if existing != null and existing != self: return false
	if is_instance_valid(_district):
		if _district != district: return false
		refresh_materials()
		return true
	_world = _find_world(district)
	_sun = _find_sun(district)
	if _world == null or _sun == null or _world.environment == null: return false
	_district = district
	name = "StreetAtmosphere"
	process_priority = 20 # Legacy District sun drift runs first; selected condition stays stable.
	if get_parent() == null: district.add_child(self)
	_original_environment = _world.environment
	_original_sun = {"rotation":_sun.rotation_degrees,"color":_sun.light_color,"energy":_sun.light_energy,
		"shadow":_sun.shadow_enabled,"distance":_sun.directional_shadow_max_distance}
	# Copy scalar settings; build a unique sky below. Deep duplication followed
	# by replacement leaks the cloned sky's GL textures in Godot 4.7.2.
	_environment = _original_environment.duplicate(false) as Environment
	_world.environment = _environment
	var sky := Sky.new()
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	_sky = ProceduralSkyMaterial.new()
	sky.sky_material = _sky
	_environment.sky = sky
	_environment.background_mode = Environment.BG_SKY
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_sky_contribution = .35
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.tonemap_exposure = 1.0
	_environment.tonemap_white = 4.0
	_environment.adjustment_enabled = false
	_environment.volumetric_fog_enabled = false
	_environment.sdfgi_enabled = false
	_environment.ssil_enabled = false
	renderer = str(RenderingServer.get_current_rendering_method())
	_create_lamps()
	_create_reflection()
	_create_rain()
	refresh_materials()
	return apply_conditions(conditions)


func apply_conditions(value: String) -> bool:
	if value not in CONDITIONS or _environment == null: return false
	conditions = value
	var dusk := value == "dusk"
	var rainy := value == "rain"
	_sun_pose = Vector3(-9,-55,0) if dusk else Vector3(-48,-28,0)
	_sun.rotation_degrees = _sun_pose
	_sun.light_color = Color("ffc792") if dusk else (Color("dce7ee") if rainy else Color("fff1dd"))
	_sun.light_energy = .24 if dusk else (.42 if rainy else 1.05)
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality == "portable" else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 75.0 if quality == "portable" else 95.0
	_sky.sky_top_color = Color("344e70") if dusk else (Color("81939f") if rainy else Color("658fad"))
	_sky.sky_horizon_color = Color("bf9981") if dusk else (Color("c6d0d1") if rainy else Color("d1dee1"))
	_sky.ground_horizon_color = _sky.sky_horizon_color
	_sky.ground_bottom_color = Color("384044") if dusk else Color("4b5658")
	_sky.sky_energy_multiplier = .70 if dusk else (.88 if rainy else 1.0)
	_sky.ground_energy_multiplier = .7
	_sky.sun_angle_max = 5.0
	_environment.ambient_light_color = Color("8fa3c2") if dusk else (Color("c1cdd1") if rainy else Color("c6d8e0"))
	_environment.ambient_light_energy = .26 if dusk else (.42 if rainy else .32)
	_environment.fog_enabled = true
	_environment.fog_light_color = Color("9a95a0") if dusk else (Color("a9bbc4") if rainy else Color("b9cbd5"))
	_environment.fog_density = .003 if dusk else (.0042 if rainy else .0013)
	_environment.fog_sky_affect = .12
	_environment.glow_enabled = quality != "portable" and dusk
	_environment.glow_intensity = .12
	_environment.glow_bloom = 0.0
	_environment.glow_hdr_threshold = 1.25
	_environment.ssao_enabled = quality != "portable" and renderer in ["gl_compatibility","forward_plus"]
	_environment.ssao_radius = .65
	_environment.ssao_intensity = .65
	_environment.ssao_power = 1.35
	_environment.ssao_light_affect = .1
	_environment.ssr_enabled = quality == "high" and renderer == "forward_plus" and rainy
	_environment.ssr_max_steps = 32
	_environment.ssr_depth_tolerance = .15
	for i in range(_lamps.size()):
		var lamp := _lamps[i]
		lamp.visible = dusk or rainy
		lamp.light_energy = 2.2 if dusk else .55
		lamp.shadow_enabled = quality != "portable" and i in [0,2]
		if quality == "portable" and i in [1,3]: lamp.visible = false
	_set_material_condition(rainy)
	_rain.visible = rainy
	_rain.emitting = rainy
	_rain.speed_scale = 0.0 if _paused else 1.0
	_refresh_reflection()
	return true


func set_quality(value: String) -> bool:
	if value not in QUALITIES: return false
	quality = value
	if _environment != null: apply_conditions(conditions)
	return true


func set_simulation_active(active: bool) -> void:
	_paused = not active
	if is_instance_valid(_rain): _rain.speed_scale = 1.0 if active else 0.0


func _process(_delta: float) -> void:
	if not is_instance_valid(_district): return
	if _sun.rotation_degrees != _sun_pose: _sun.rotation_degrees = _sun_pose
	var active: Variant = _district.get("simulation_active")
	if active is bool and _paused == active: set_simulation_active(active)


func refresh_materials() -> int:
	if not is_instance_valid(_district): return 0
	var count := 0
	for node: Node in _descendants(_district):
		if not (node is MeshInstance3D): continue
		var mesh := node as MeshInstance3D
		if _tracked.has(mesh.get_instance_id()) or mesh.mesh == null: continue
		var entries := 0
		if mesh.material_override != null:
			var original := mesh.material_override as StandardMaterial3D
			if original != null:
				var kind := _classify(mesh,original)
				if not kind.is_empty():
					var key := _variant_for(original,kind)
					_surfaces.append({"mesh":mesh,"surface":-1,"original_override":original,"key":key})
					entries = 1
		else:
			for surface in mesh.mesh.get_surface_count():
				var original := mesh.get_active_material(surface) as StandardMaterial3D
				if original == null: continue
				var kind := _classify(mesh,original)
				if kind.is_empty(): continue
				var key := _variant_for(original,kind)
				_surfaces.append({"mesh":mesh,"surface":surface,"original_override":mesh.get_surface_override_material(surface),"key":key})
				entries += 1
		if entries > 0:
			_tracked[mesh.get_instance_id()] = true
			count += entries
	_set_material_condition(conditions == "rain")
	return count


func register_ground(mesh: MeshInstance3D) -> bool:
	if mesh == null or _tracked.has(mesh.get_instance_id()): return false
	mesh.set_meta("street_surface","ground")
	return refresh_materials() > 0


func _classify(mesh: MeshInstance3D, original: StandardMaterial3D) -> String:
	var explicit := str(mesh.get_meta("street_surface",""))
	if explicit in ["ground","exterior","glass"]: return explicit
	var tag := original.resource_name.to_lower()
	if tag.contains("painted timber frames") and _is_lamp_mesh(mesh): return "luminaire"
	if tag.contains("automotive_glass") or tag.contains("window reflection") or tag == "window glass": return "glass"
	if _contains_any(tag,["fabric","cloth","linen","skin","seat","tyre","rubber"]): return ""
	if _contains_any(tag,["asphalt","paving","pavement","klinker"]): return "ground"
	var node_name := str(mesh.name).to_lower()
	if _contains_any(node_name,["hoofdstraat","stationslaan","industrieweg","sidewalk","footpath","streetroad","streetpavement","rijbaan"]): return "ground"
	if _contains_any(tag,["brick","roof","paint","powder","alloy","oak","timber","concrete","vehicle_pearl","vehicle_navy","appliance_vermilion"]): return "exterior"
	return ""


func _is_lamp_mesh(mesh: MeshInstance3D) -> bool:
	var parent_at: Node = mesh.get_parent()
	while parent_at != null and parent_at != _district:
		var label := str(parent_at.name).to_lower()
		if label.contains("street_lamp") or label.contains("streetlamp"): return true
		parent_at = parent_at.get_parent()
	return false


func _variant_for(original: StandardMaterial3D, kind: String) -> String:
	var key := "%d:%s" % [original.get_instance_id(),kind]
	if not _variants.has(key):
		var dry: Material = _glass(original) if kind == "glass" else (original.duplicate() if kind == "luminaire" else original)
		var wet: Material = _wet_ground(original) if kind == "ground" else _wet_surface(dry as StandardMaterial3D,kind == "glass")
		_variants[key] = {"dry":dry,"wet":wet,"kind":kind}
	return key


func diagnostics() -> Dictionary:
	var shadows := 0
	var enabled := 0
	for lamp: SpotLight3D in _lamps:
		if lamp.visible:
			enabled += 1
			if lamp.shadow_enabled: shadows += 1
	return {"conditions":conditions,"quality":quality,"renderer":renderer,"lamps":enabled,"local_shadows":shadows,
		"reflection_probes":1 if is_instance_valid(_reflection) else 0,"probe_revision":_probe_revision,
		"ssao":_environment.ssao_enabled if _environment else false,"glow":_environment.glow_enabled if _environment else false,
		"ssr":_environment.ssr_enabled if _environment else false,"particles":_rain.amount if _rain and _rain.visible else 0,
		"particles_paused":_paused,"material_variants":_variants.size(),"managed_surfaces":_surfaces.size()}


func restore_original() -> void:
	for entry: Dictionary in _surfaces:
		if is_instance_valid(entry.mesh):
			if entry.surface == -1: entry.mesh.material_override = entry.original_override
			else: entry.mesh.set_surface_override_material(entry.surface,entry.original_override)
	if is_instance_valid(_world): _world.environment = _original_environment
	if is_instance_valid(_sun) and not _original_sun.is_empty():
		_sun.rotation_degrees = _original_sun.rotation
		_sun.light_color = _original_sun.color
		_sun.light_energy = _original_sun.energy
		_sun.shadow_enabled = _original_sun.shadow
		_sun.directional_shadow_max_distance = _original_sun.distance
	set_process(false)
	for light: SpotLight3D in _lamps: light.visible = false
	if is_instance_valid(_reflection): _reflection.visible = false
	if is_instance_valid(_rain): _rain.emitting = false; _rain.visible = false


func _glass(original: StandardMaterial3D) -> StandardMaterial3D:
	var material := original.duplicate() as StandardMaterial3D
	material.resource_name = original.resource_name + " · clear street glazing"
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(.82,.92,.96,.20)
	material.roughness = .09
	material.metallic = .05
	material.metallic_specular = .55
	material.clearcoat_enabled = true
	material.clearcoat = .30
	material.clearcoat_roughness = .10
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.refraction_enabled = false # No per-window screen read/refraction overdraw.
	return material


func _wet_surface(original: StandardMaterial3D, glass: bool) -> StandardMaterial3D:
	var material := original.duplicate() as StandardMaterial3D
	material.resource_name = original.resource_name + " · wet"
	material.roughness = .07 if glass else maxf(.16,original.roughness * .43)
	if not glass:
		material.albedo_color *= Color(.85,.85,.85,1)
		material.clearcoat_enabled = true
		material.clearcoat = .38
		material.clearcoat_roughness = .12
	return material


func _wet_ground(original: StandardMaterial3D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WetPaving
	material.resource_name = original.resource_name + " · rain patches"
	material.set_shader_parameter("base_color",original.albedo_color)
	material.set_shader_parameter("dry_roughness",original.roughness)
	material.set_shader_parameter("uv_scale",Vector2(original.uv1_scale.x,original.uv1_scale.y))
	material.set_shader_parameter("uv_offset",Vector2(original.uv1_offset.x,original.uv1_offset.y))
	material.set_shader_parameter("planar_world", original.uv1_triplanar and original.uv1_world_triplanar)
	material.set_shader_parameter("planar_scale", original.uv1_scale.x)
	material.set_shader_parameter("normal_strength",original.normal_scale)
	material.set_shader_parameter("has_normal",original.normal_enabled and original.normal_texture != null)
	material.set_shader_parameter("roughness_channel",original.roughness_texture_channel)
	if original.albedo_texture: material.set_shader_parameter("albedo_texture",original.albedo_texture)
	if original.roughness_texture: material.set_shader_parameter("roughness_texture",original.roughness_texture)
	if original.normal_texture: material.set_shader_parameter("normal_texture",original.normal_texture)
	return material


func _set_material_condition(wet: bool) -> void:
	var key := "wet" if wet else "dry"
	for variant: Dictionary in _variants.values():
		if variant.kind != "luminaire": continue
		for state: String in ["dry","wet"]:
			var diffuser := variant[state] as StandardMaterial3D
			diffuser.emission_enabled = conditions in ["dusk","rain"]
			diffuser.emission = Color("ffe2b9")
			diffuser.emission_energy_multiplier = 1.5 if conditions == "dusk" else .45
	for entry: Dictionary in _surfaces:
		if is_instance_valid(entry.mesh):
			if entry.surface == -1: entry.mesh.material_override = _variants[entry.key][key]
			else: entry.mesh.set_surface_override_material(entry.surface,_variants[entry.key][key])


func _create_lamps() -> void:
	for i in range(4):
		var lamp := SpotLight3D.new()
		lamp.name = "StreetLight%d" % i
		lamp.position = LAMP_POINTS[i]
		lamp.rotation_degrees.x = -90
		lamp.light_color = Color("ffe2b9")
		lamp.spot_range = 10
		lamp.spot_angle = 61
		lamp.spot_attenuation = 1.05
		lamp.light_specular = .85
		lamp.shadow_bias = .025
		lamp.shadow_normal_bias = .4
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = 35
		lamp.distance_fade_length = 15
		add_child(lamp)
		_lamps.append(lamp)


func set_lamp_positions(points: Array[Vector3]) -> bool:
	if points.size() != 4 or _lamps.size() != 4: return false
	for i in range(4):
		if not points[i].is_finite(): return false
	for i in range(4): _lamps[i].global_position = points[i]
	_refresh_reflection()
	return true


func _create_reflection() -> void:
	_reflection = ReflectionProbe.new()
	_reflection.name = "NoorderkadeStreetReflection"
	_reflection.position = Vector3(12,4,40)
	_reflection.size = Vector3(52,12,32)
	_reflection.max_distance = 45
	_reflection.box_projection = true
	_reflection.intensity = .8
	_reflection.enable_shadows = false
	_reflection.update_mode = ReflectionProbe.UPDATE_ONCE
	_reflection.mesh_lod_threshold = 2
	_reflection.cull_mask = 1 # Rain streaks on layer 2 are excluded from the cube capture.
	add_child(_reflection)


func _refresh_reflection() -> void:
	if not is_instance_valid(_reflection): return
	_probe_revision += 1
	_reflection.position.x = 12.0 + float(_probe_revision % 2) * .002


func _create_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.name = "LightStreetRain"
	_rain.position = Vector3(12,7,35)
	_rain.amount = 280
	_rain.lifetime = .70
	_rain.preprocess = .7
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(25,.8,8)
	_rain.direction = Vector3(-.07,-1,.035).normalized()
	_rain.spread = 1
	_rain.initial_velocity_min = 8.0
	_rain.initial_velocity_max = 9.5
	_rain.gravity = Vector3(0,-.25,0)
	_rain.use_fixed_seed = true
	_rain.seed = 112
	_rain.layers = 2
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.visibility_aabb = AABB(Vector3(-27,-8,-10),Vector3(54,10,20))
	var streak := QuadMesh.new()
	streak.size = Vector2(.008,.20)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(.64,.78,.85,.23)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	streak.material = material
	_rain.mesh = streak
	_rain.emitting = false
	_rain.visible = false
	add_child(_rain)


func _find_world(node: Node) -> WorldEnvironment:
	for child: Node in node.get_children():
		if child is WorldEnvironment: return child
		var found := _find_world(child)
		if found != null: return found
	return null


func _find_sun(node: Node) -> DirectionalLight3D:
	for child: Node in node.get_children():
		if child is DirectionalLight3D: return child
		var found := _find_sun(child)
		if found != null: return found
	return null


func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


func _contains_any(value: String, tags: Array) -> bool:
	for tag: String in tags:
		if value.contains(tag): return true
	return false
