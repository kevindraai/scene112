extends RefCounted
## Runtime instance overrides for Apple's CPU OpenGL interpreter only.
## Keep original resources alive and restore only the overrides this object owns.
const SurfaceShader = preload("res://shaders/apple_software_surface.gdshader")
var _shader_variants: Dictionary = {}
var _lighting: Dictionary = {}
var _root: Node
var _tree: SceneTree
var _entries: Dictionary = {}
var _pending := false
var _active := false
var unsupported := 0

func setup(scope: Node) -> void:
	_root = scope
	_tree = scope.get_tree()
	_active = true
	_tree.node_added.connect(_node_added)
	refresh()

func _node_added(node: Node) -> void:
	if not _active or not node is MeshInstance3D or _pending: return
	_pending = true
	call_deferred("_refresh_deferred")

func _refresh_deferred() -> void:
	_pending = false
	if _active: refresh()

func refresh() -> void:
	if not _active or not is_instance_valid(_root): return
	unsupported = 0
	for key: String in _entries.keys():
		if not is_instance_valid(_entries[key].mesh): _entries.erase(key)
	_scan(_root)

func _scan(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var mesh := node as MeshInstance3D
		if mesh.material_override != null: _apply(mesh, -1)
		else:
			for surface in mesh.mesh.get_surface_count(): _apply(mesh, surface)
	for child: Node in node.get_children(): _scan(child)

func _apply(mesh: MeshInstance3D, surface: int) -> void:
	var key := "%d:%d" % [mesh.get_instance_id(), surface]
	var active: Material = mesh.material_override if surface == -1 else mesh.get_active_material(surface)
	if _entries.has(key):
		var entry: Dictionary = _entries[key]
		if active == entry.replacement: return
		# Weather/tint owners supplied a new material. Never restore a stale one.
		_entries.erase(key)
	if active == null: return
	if not active is StandardMaterial3D:
		unsupported += 1
		return
	var source := active as StandardMaterial3D
	var replacement := _simplify(source)
	_entries[key] = {"mesh":mesh, "surface":surface, "source":source,
		"original_override":mesh.material_override if surface == -1 else mesh.get_surface_override_material(surface),
		"replacement":replacement}
	_set_override(mesh, surface, replacement)

func _simplify(source: StandardMaterial3D) -> Material:
	# Labels/signals and camera-facing particles already use the short unlit path.
	if source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or source.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		var simple := source.duplicate() as StandardMaterial3D
		simple.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		simple.disable_fog = true
		for feature in BaseMaterial3D.FEATURE_MAX:
			if feature != BaseMaterial3D.FEATURE_EMISSION: simple.set_feature(feature, false)
		for texture in BaseMaterial3D.TEXTURE_MAX:
			if texture != BaseMaterial3D.TEXTURE_ALBEDO: simple.set_texture(texture, null)
		simple.next_pass = null
		return simple
	var alpha_mode: int = source.transparency
	var key := "%d:%d" % [source.cull_mode, alpha_mode]
	if not _shader_variants.has(key):
		var shader := Shader.new()
		var cull := "cull_front" if source.cull_mode == BaseMaterial3D.CULL_FRONT else ("cull_disabled" if source.cull_mode == BaseMaterial3D.CULL_DISABLED else "cull_back")
		var code: String = SurfaceShader.code.replace("cull_back", cull)
		if alpha_mode != BaseMaterial3D.TRANSPARENCY_DISABLED:
			var alpha := "ALPHA = surface.a;"
			if alpha_mode == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or alpha_mode == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
				alpha += " ALPHA_SCISSOR_THRESHOLD = alpha_threshold;"
			code = code.replace("// ALPHA_OUTPUT", alpha)
			code = code.replace("uniform vec4 base_color", "uniform float alpha_threshold = 0.5;\nuniform vec4 base_color")
		shader.code = code
		_shader_variants[key] = shader
	var material := ShaderMaterial.new()
	material.shader = _shader_variants[key]
	material.resource_name = source.resource_name + " · Apple CPU vertex diffuse"
	material.set_meta("scene112_apple_vertex", true)
	material.set_shader_parameter("base_color", source.albedo_color)
	material.set_shader_parameter("albedo_texture", source.albedo_texture)
	var planar: bool = source.uv1_triplanar and source.uv1_world_triplanar
	material.set_shader_parameter("planar_world", planar)
	material.set_shader_parameter("uv_scale", Vector2(source.uv1_scale.x, source.uv1_scale.z if planar else source.uv1_scale.y))
	material.set_shader_parameter("uv_offset", Vector2(source.uv1_offset.x, source.uv1_offset.z if planar else source.uv1_offset.y))
	material.set_shader_parameter("vertex_color_albedo", source.vertex_color_use_as_albedo)
	material.set_shader_parameter("emission_color", source.emission)
	material.set_shader_parameter("emission_energy", source.emission_energy_multiplier if source.emission_enabled else 0.0)
	if alpha_mode != BaseMaterial3D.TRANSPARENCY_DISABLED: material.set_shader_parameter("alpha_threshold", source.alpha_scissor_threshold)
	for uniform: String in _lighting: material.set_shader_parameter(uniform, _lighting[uniform])
	return material

func set_lighting(sun: DirectionalLight3D, environment: Environment, lamps: Array) -> void:
	_lighting = {"sun_direction":sun.global_basis.z.normalized(), "sun_color":sun.light_color,
		"sun_energy":sun.light_energy, "ambient_color":environment.ambient_light_color,
		"ambient_energy":environment.ambient_light_energy, "haze_color":environment.fog_light_color,
		"haze_density":environment.fog_density if environment.fog_enabled else 0.0}
	for i in 2:
		var lamp: SpotLight3D = lamps[i * 2]
		var at := lamp.global_position
		_lighting["lamp%d" % i] = Vector4(at.x, at.y, at.z, lamp.light_energy if lamp.visible else 0.0)
	_lighting["lamp_color"] = lamps[0].light_color
	_lighting["lamp_range"] = lamps[0].spot_range
	for entry: Dictionary in _entries.values():
		if not is_instance_valid(entry.mesh) or not entry.replacement is ShaderMaterial: continue
		for uniform: String in _lighting: entry.replacement.set_shader_parameter(uniform, _lighting[uniform])

func original_material(mesh: MeshInstance3D, surface: int) -> Material:
	var key := "%d:%d" % [mesh.get_instance_id(), -1 if mesh.material_override != null else surface]
	if _entries.has(key):
		var entry: Dictionary = _entries[key]
		if mesh.get_active_material(surface) == entry.replacement: return entry.source
	return mesh.get_active_material(surface)

func sync_albedo(mesh: MeshInstance3D, surface: int, source: StandardMaterial3D) -> bool:
	# Incident owners mutate their retained source directly. BaseMaterial3D color
	# setters do not emit Resource.changed; synchronize only the owned live slot.
	if not _active or not is_instance_valid(mesh): return false
	var key := "%d:%d" % [mesh.get_instance_id(), surface]
	if not _entries.has(key): return false
	var entry: Dictionary = _entries[key]
	var current: Material = mesh.material_override if surface == -1 else mesh.get_active_material(surface)
	if entry.source != source or current != entry.replacement: return false
	if entry.replacement is ShaderMaterial:
		entry.replacement.set_shader_parameter("base_color", source.albedo_color)
	else:
		entry.replacement.albedo_color = source.albedo_color
	return true

func diagnostics() -> Dictionary:
	var standard := 0
	var planar := 0
	for entry: Dictionary in _entries.values():
		if not is_instance_valid(entry.mesh): continue
		if entry.replacement is ShaderMaterial and entry.replacement.get_shader_parameter("planar_world"): planar += 1
		else: standard += 1
	return {"enabled":_active, "vertex_albedo_surfaces":standard, "vertex_planar_surfaces":planar, "unsupported_surfaces":unsupported}

func restore() -> void:
	_active = false
	if is_instance_valid(_tree) and _tree.node_added.is_connected(_node_added): _tree.node_added.disconnect(_node_added)
	for entry: Dictionary in _entries.values():
		if not is_instance_valid(entry.mesh): continue
		var current: Material = entry.mesh.material_override if entry.surface == -1 else entry.mesh.get_surface_override_material(entry.surface)
		if current == entry.replacement: _set_override(entry.mesh, entry.surface, entry.original_override)
	_entries.clear()
	_shader_variants.clear()
	_lighting.clear()
	_root = null
	_tree = null

func _set_override(mesh: MeshInstance3D, surface: int, material: Material) -> void:
	if surface == -1: mesh.material_override = material
	else: mesh.set_surface_override_material(surface, material)
