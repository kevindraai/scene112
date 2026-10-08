class_name FireCellVFX
extends Node3D
## Read-only, bounded rendering of FireCase cells. No input, physics or game rules.

const FLAME_SHADER := preload("res://shaders/fire_wisp.gdshader")
const AEROSOL_SHADER := preload("res://shaders/fire_aerosol.gdshader")
const FLAME_TEXTURE := preload("res://assets/vfx/textures/flame_wisp.png")
const SMOKE_TEXTURE := preload("res://assets/vfx/textures/smoke_curl.png")
const STEAM_TEXTURE := preload("res://assets/vfx/textures/steam_veil.png")
const WATER_TEXTURE := preload("res://assets/vfx/textures/water_drop.png")
const MAX_CELLS := 3
const WATER_COUNT := 48
const COUNTS := {"wisps": 36, "core": 14, "smoke": 22, "steam": 14}
const MAX_PARTICLES := 306
const MAX_DRAWS := 13
const MAX_WATER_RANGE := 8.0
const FIXED_SEED := 1122026

var _house: Node3D
var _owned: Node3D
var _views: Dictionary = {}
var _water: CPUParticles3D
var _water_material: ShaderMaterial
var _light: OmniLight3D
var _simulation_active := false
var _enabled := true
var _clock := 0.0
var _quality := "portable"
var _stream_requested := false
var _stream_range := 0.0
var _origin_id := ""


func _ready() -> void:
	name = "FireCellVFX"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	visibility_changed.connect(_sync_pause)


func setup_cells(house: Node3D, cell_data: Array) -> bool:
	# Validate before replacing an existing effect, including on load/replay.
	if not is_instance_valid(house) or house == self or is_ancestor_of(house): return false
	if cell_data.is_empty() or cell_data.size() > MAX_CELLS: return false
	var ids: Dictionary = {}
	for value: Variant in cell_data:
		if not value is Dictionary: return false
		var id: String = str(value.get("id", ""))
		if id.is_empty() or id.length() > 32 or ids.has(id): return false
		if not _valid_position(value.get("pos", null)): return false
		ids[id] = true
	clear()
	_house = house
	if get_parent() == null:
		house.add_child(self)
	elif get_parent() != house:
		reparent(house, false)
	transform = Transform3D.IDENTITY
	_owned = Node3D.new()
	_owned.name = "OwnedFireEffects"
	add_child(_owned)
	for index in range(cell_data.size()):
		_build_cell(cell_data[index], index)
	_origin_id = "origin" if _views.has("origin") else str(cell_data[0].id)
	_light = OmniLight3D.new()
	_light.name = "SingleFireBounce"
	_light.position = _views[_origin_id].root.position + Vector3(0, 0.3, 0)
	_light.light_color = Color(1.0, 0.36, 0.075)
	_light.omni_range = 4.0
	_light.omni_attenuation = 1.6
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_owned.add_child(_light)
	_water_material = _aerosol(WATER_TEXTURE, Color(0.60, 0.79, 0.90, 0.54))
	_water_material.set_shader_parameter("room_clip", false)
	_water_material.set_shader_parameter("align_to_stream", true)
	_water = _emitter(_owned, "AimedWater", WATER_COUNT, 0.06, 0.18,
		_water_material, FIXED_SEED + 900, 0.4, Vector3(0, 0, -1), 0.0)
	_water.local_coords = false
	_water.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_water.emission_sphere_radius = 0.012
	_water.spread = 1.25
	_water.gravity = Vector3.ZERO
	_water.visibility_aabb = AABB(Vector3(-9, -9, -9), Vector3(18, 18, 18))
	_enabled = true
	set_quality(_quality)
	_sync_bounds()
	_sync_pause()
	set_process(true)
	return true


func update_state(cells: Array, simulation_active: bool) -> bool:
	if not is_instance_valid(_owned) or cells.size() != _views.size(): return false
	var next: Dictionary = {}
	for value: Variant in cells:
		if not value is Dictionary: return false
		var id: String = str(value.get("id", ""))
		if not _views.has(id) or next.has(id): return false
		for key in ["heat", "fuel", "wet", "burned"]:
			if not _unit_number(value.get(key, null)): return false
		next[id] = value
	# Read values only; never append visual state to the model's dictionaries.
	for id: String in next:
		var cell: Dictionary = next[id]
		var view: Dictionary = _views[id]
		view.heat = float(cell.heat)
		view.fuel = float(cell.fuel)
		view.wet = float(cell.wet)
		view.burned = float(cell.burned)
		_update_cell(view)
	set_simulation_active(simulation_active)
	_sync_light()
	return true


func set_simulation_active(active: bool) -> void:
	_simulation_active = active
	_sync_pause()


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled
	_sync_pause()


func set_quality(quality: String) -> bool:
	if quality not in ["portable", "balanced", "high"]: return false
	_quality = quality
	if is_instance_valid(_light):
		# The portable path has no fire shadow map; high is guarded Forward+.
		_light.shadow_enabled = quality == "high" and RenderingServer.get_current_rendering_method() == "forward_plus"
	return true


func set_water_stream(from: Vector3, to: Vector3, spraying: bool) -> bool:
	# Caller owns targeting/range/obstruction rules. This second rendering bound
	# prevents an invalid visual request from spanning the entire district.
	if not is_instance_valid(_water): return false
	if not spraying:
		_stream_requested = false
		_water.emitting = false
		return true
	var distance := from.distance_to(to)
	if not from.is_finite() or not to.is_finite() or not is_finite(distance) or distance < 0.1 or distance > MAX_WATER_RANGE:
		_stream_requested = false
		_water.emitting = false
		return false
	if not is_inside_tree(): return false
	_water.global_position = from
	_water.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.95 else Vector3.RIGHT)
	_water.initial_velocity_min = 12.0
	_water.initial_velocity_max = 12.0
	_water.lifetime = distance / 12.0
	_water.lifetime_randomness = 0.0
	_water_material.set_shader_parameter("intensity", 1.0)
	_water_material.set_shader_parameter("stream_direction", (to - from).normalized())
	_stream_range = distance
	_stream_requested = true
	_water.emitting = _enabled
	_sync_pause()
	return true


func diagnostics() -> Dictionary:
	var cells: Dictionary = {}
	var particle_count := WATER_COUNT if is_instance_valid(_water) else 0
	var emitting_count := 1 if is_instance_valid(_water) and _water.emitting else 0
	for id: String in _views:
		var view: Dictionary = _views[id]
		var emitters: Dictionary = {}
		for kind: String in COUNTS:
			var emitter: CPUParticles3D = view[kind]
			particle_count += emitter.amount
			if emitter.emitting: emitting_count += 1
			emitters[kind] = {"amount": emitter.amount, "emitting": emitter.emitting,
				"speed_scale": emitter.speed_scale, "seed": emitter.seed,
				"fixed_seed": emitter.use_fixed_seed, "lifetime": emitter.lifetime,
				"weight": view.materials[kind].get_shader_parameter("intensity")}
		cells[id] = {"heat": view.heat, "fuel": view.fuel, "wet": view.wet,
			"burned": view.burned, "position": view.root.position, "emitters": emitters}
	return {"cells": cells, "clock": _clock, "simulation_active": _simulation_active,
		"effective_active": _running(), "enabled": _enabled, "quality": _quality,
		"renderer": RenderingServer.get_current_rendering_method(),
		"particles": particle_count, "max_particles": MAX_PARTICLES,
		"draws": _views.size() * COUNTS.size() + (1 if is_instance_valid(_water) else 0),
		"max_draws": MAX_DRAWS, "emitting": emitting_count,
		"light_count": 1 if is_instance_valid(_light) else 0,
		"light_energy": _light.light_energy if is_instance_valid(_light) else 0.0,
		"light_shadow": _light.shadow_enabled if is_instance_valid(_light) else false,
		"water_requested": _stream_requested, "water_range": _stream_range,
		"water_speed_scale": _water.speed_scale if is_instance_valid(_water) else 0.0}


func clear() -> void:
	_simulation_active = false
	_stream_requested = false
	_stream_range = 0.0
	_clock = 0.0
	if is_instance_valid(_owned):
		for particle in _owned.find_children("*", "CPUParticles3D", true, false):
			particle.emitting = false
			particle.speed_scale = 0.0
		remove_child(_owned)
		_owned.queue_free()
	_owned = null
	_house = null
	_water = null
	_water_material = null
	_light = null
	_origin_id = ""
	_views.clear()
	set_process(false)


func _process(delta: float) -> void:
	_sync_pause()
	if not _running(): return
	_clock += minf(delta, 0.1)
	_sync_bounds()
	for view: Dictionary in _views.values():
		for kind in ["wisps", "core"]:
			view.materials[kind].set_shader_parameter("sim_clock", _clock)
	_sync_light()


func _running() -> bool:
	return _simulation_active and _enabled and is_inside_tree() and is_visible_in_tree() and not get_tree().paused


func _sync_pause() -> void:
	var speed := 1.0 if _running() else 0.0
	for view: Dictionary in _views.values():
		for kind: String in COUNTS:
			view[kind].speed_scale = speed
	if is_instance_valid(_water): _water.speed_scale = speed


func _sync_bounds() -> void:
	if not is_instance_valid(_house) or not _house.is_inside_tree(): return
	var floor_y := _house.global_position.y + 0.035
	var ceiling_y := _house.global_position.y + 2.72
	for view: Dictionary in _views.values():
		for material: ShaderMaterial in view.materials.values():
			material.set_shader_parameter("floor_y", floor_y)
			material.set_shader_parameter("ceiling_y", ceiling_y)


func _sync_light() -> void:
	if not is_instance_valid(_light) or not _views.has(_origin_id): return
	var intensity: float = _views[_origin_id].materials.wisps.get_shader_parameter("intensity")
	_light.light_energy = intensity * (1.45 + sin(_clock * 8.1) * 0.09 + sin(_clock * 13.7) * 0.045)
	_light.visible = _enabled and intensity > 0.025


func _build_cell(cell: Dictionary, index: int) -> void:
	var root := Node3D.new()
	root.name = "Cell_" + str(cell.id)
	root.position = Vector3(float(cell.pos[0]), float(cell.pos[1]), float(cell.pos[2]))
	_owned.add_child(root)
	var materials := {
		"wisps": _flame(0.0, float(index) * 1.7),
		"core": _flame(0.86, float(index) * 1.7 + 2.0),
		"smoke": _aerosol(SMOKE_TEXTURE, Color(0.26, 0.25, 0.235, 0.22)),
		"steam": _aerosol(STEAM_TEXTURE, Color(0.83, 0.86, 0.84, 0.19))}
	var view: Dictionary = {"root": root, "materials": materials,
		"heat": 0.0, "fuel": 0.0, "wet": 0.0, "burned": 0.0}
	view.wisps = _emitter(root, "FlameWisps", COUNTS.wisps, 0.43, 0.78,
		materials.wisps, FIXED_SEED + index * 100, 0.95, Vector3.UP, 0.54)
	view.core = _emitter(root, "FlameCore", COUNTS.core, 0.23, 0.44,
		materials.core, FIXED_SEED + index * 100 + 1, 0.56, Vector3.UP, 0.37)
	view.smoke = _emitter(root, "SmokeCurls", COUNTS.smoke, 0.85, 0.82,
		materials.smoke, FIXED_SEED + index * 100 + 2, 3.15, Vector3.UP, 0.31)
	view.smoke.position.y = 0.48
	view.smoke.gravity = Vector3(0.025, 0.025, 0.015)
	view.smoke.spread = 17.0
	view.smoke.scale_amount_min = 0.54
	view.smoke.scale_amount_max = 1.0
	view.steam = _emitter(root, "CoolingSteam", COUNTS.steam, 0.53, 0.64,
		materials.steam, FIXED_SEED + index * 100 + 3, 1.75, Vector3.UP, 0.46)
	view.steam.position.y = 0.18
	view.steam.spread = 24.0
	_views[str(cell.id)] = view


func _update_cell(view: Dictionary) -> void:
	var heat: float = view.heat
	var fuel: float = view.fuel
	var wet: float = view.wet
	var flame := clampf((heat - 0.055) / 0.75, 0.0, 1.0) * minf(1.0, fuel * 3.0) * (1.0 - wet * 0.62)
	var smoke := clampf((heat - 0.035) * (0.9 + float(view.burned) * 0.12), 0.0, 0.85)
	var steam := clampf((heat - 0.035) * wet * 1.6, 0.0, 0.75)
	for kind: String in COUNTS:
		var weight := flame if kind in ["wisps", "core"] else (smoke if kind == "smoke" else steam)
		view.materials[kind].set_shader_parameter("intensity", weight)
		view[kind].emitting = weight > 0.025
	# Particle count remains fixed. Heat changes the flame's rise and size.
	for kind in ["wisps", "core"]:
		var emitter: CPUParticles3D = view[kind]
		emitter.initial_velocity_min = 0.22 + heat * 0.54
		emitter.initial_velocity_max = 0.34 + heat * 0.63
		emitter.scale_amount_min = 0.32 + heat * 0.45
		emitter.scale_amount_max = 0.52 + heat * 0.57


func _flame(core_mix: float, phase_offset: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FLAME_SHADER
	material.set_shader_parameter("wisp_texture", FLAME_TEXTURE)
	material.set_shader_parameter("core_mix", core_mix)
	material.set_shader_parameter("phase_offset", phase_offset)
	return material


func _aerosol(texture: Texture2D, tint: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = AEROSOL_SHADER
	material.set_shader_parameter("field_texture", texture)
	material.set_shader_parameter("tint", tint)
	return material


func _emitter(parent: Node3D, emitter_name: String, count: int, width: float,
		height: float, material: ShaderMaterial, fixed_seed: int, lifetime: float,
		direction: Vector3, velocity: float) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.name = emitter_name
	emitter.amount = count
	emitter.lifetime = lifetime
	emitter.lifetime_randomness = 0.18
	emitter.emitting = false
	emitter.speed_scale = 0.0
	emitter.local_coords = true
	emitter.use_fixed_seed = true
	emitter.seed = fixed_seed
	emitter.fixed_fps = 30
	emitter.fract_delta = true
	emitter.direction = direction
	emitter.spread = 13.0
	emitter.gravity = Vector3(0, 0.075, 0)
	emitter.initial_velocity_min = velocity * 0.7
	emitter.initial_velocity_max = velocity
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emitter.emission_box_extents = Vector3(0.28, 0.06, 0.22)
	emitter.visibility_aabb = AABB(Vector3(-1.4, -0.8, -1.4), Vector3(2.8, 3.7, 2.8))
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.62, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color(1, 1, 1, 0.72), Color(1, 1, 1, 0)])
	emitter.color_ramp = ramp
	var growth := Curve.new()
	growth.add_point(Vector2(0, 0.4))
	growth.add_point(Vector2(0.3, 0.85))
	growth.add_point(Vector2(1, 1.0))
	emitter.scale_amount_curve = growth
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	quad.material = material
	emitter.mesh = quad
	parent.add_child(emitter)
	return emitter


func _unit_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 1.0


func _valid_position(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for coordinate: Variant in value:
		if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)): return false
	return true
