extends RefCounted
## Runtime instance overrides for Apple's CPU OpenGL interpreter only.
## Keep original resources alive and restore only the overrides this object owns.
const GroundShader = preload("res://shaders/apple_software_ground.gdshader")
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
	if source.uv1_triplanar and source.uv1_world_triplanar:
		var ground := ShaderMaterial.new()
		ground.resource_name = source.resource_name + " · Apple vertex ground"
		ground.shader = GroundShader
		ground.set_shader_parameter("base_color", source.albedo_color)
		ground.set_shader_parameter("albedo_texture", source.albedo_texture)
		ground.set_shader_parameter("planar_scale", Vector2(source.uv1_scale.x, source.uv1_scale.z))
		ground.set_shader_parameter("planar_offset", Vector2(source.uv1_offset.x, source.uv1_offset.z))
		ground.set_shader_parameter("vertex_color_albedo", source.vertex_color_use_as_albedo)
		return ground
	var simple := source.duplicate() as StandardMaterial3D
	simple.resource_name = source.resource_name + " · Apple vertex albedo"
	if source.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		simple.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	simple.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	simple.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	simple.metallic = 0.0
	simple.metallic_specular = 0.0
	simple.roughness = 1.0
	# Preserve albedo/alpha, vertex paint, UVs, culling and skinning; remove the
	# additional fragment samples/lobes. Emissive signals keep their solid color.
	for feature in BaseMaterial3D.FEATURE_MAX:
		if feature != BaseMaterial3D.FEATURE_EMISSION: simple.set_feature(feature, false)
	for texture in BaseMaterial3D.TEXTURE_MAX:
		if texture != BaseMaterial3D.TEXTURE_ALBEDO: simple.set_texture(texture, null)
	simple.uv1_triplanar = false
	simple.uv2_triplanar = false
	simple.next_pass = null
	return simple

func original_material(mesh: MeshInstance3D, surface: int) -> Material:
	var key := "%d:%d" % [mesh.get_instance_id(), -1 if mesh.material_override != null else surface]
	if _entries.has(key):
		var entry: Dictionary = _entries[key]
		if mesh.get_active_material(surface) == entry.replacement: return entry.source
	return mesh.get_active_material(surface)

func diagnostics() -> Dictionary:
	var standard := 0
	var planar := 0
	for entry: Dictionary in _entries.values():
		if not is_instance_valid(entry.mesh): continue
		if entry.replacement is ShaderMaterial: planar += 1
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
	_root = null
	_tree = null

func _set_override(mesh: MeshInstance3D, surface: int, material: Material) -> void:
	if surface == -1: mesh.material_override = material
	else: mesh.set_surface_override_material(surface, material)
