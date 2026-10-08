class_name IncidentAftermath
extends Node3D
## Static, reversible PBR response to saved cells; owns neither physics nor evidence.
const SURFACE_SHADER := preload("res://shaders/incident_surface.gdshader")
const MASK := preload("res://assets/textures/aftermath/incident_mask.png")
const CELL_POS := {"front":Vector3(0,.55,-1.6),"origin":Vector3(-1.8,.55,1.8),"side":Vector3(1.8,.55,1.7)}
const CELL_FUEL := {"front":.8,"origin":1.0,"side":.9}
const TARGETS := ["InteriorLiningSurface","GroundFloorCeiling","WalkableFloor",
	"FuelFrontSurface","FuelOriginSurface","FuelSideSurface","LivingSofaSurface",
	"KitchenUnitsSurface","KitchenFridgeSurface","LivingSideboardSurface"]
var _house: Node3D
var _entries: Array[Dictionary]=[]
var _materials: Dictionary={}
var _shaders: Dictionary={}
var _cells: Array=[]
var _simulation_active := false
var _mesh_count := 0

func setup(house: Node3D) -> bool:
	if not is_instance_valid(house) or not house.is_inside_tree() or house==self or is_ancestor_of(house):return false
	if house.find_child("WalkableFloor",true,false)==null:return false
	clear()
	if get_parent()==null:house.add_child(self)
	elif get_parent()!=house:reparent(house,false)
	_house=house
	name="IncidentAftermath";transform=Transform3D.IDENTITY
	# No process/physics clocks: pausing leaves every material exactly still.
	set_process(false);set_physics_process(false)
	for node: Node in _descendants(house):
		if not node is MeshInstance3D or str(node.name) not in TARGETS:continue
		var mesh:=node as MeshInstance3D
		if mesh.material_override!=null:continue
		var applied := false
		for index in mesh.mesh.get_surface_count():
			var original:=mesh.get_active_material(index) as StandardMaterial3D
			if original==null or original.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:continue
			var key:=original.get_instance_id()
			if not _materials.has(key):_materials[key]=_material(original)
			var shader: ShaderMaterial=_materials[key]
			_entries.append({"mesh":mesh,"index":index,"previous":mesh.get_surface_override_material(index),"shader":shader,"source":original})
			mesh.set_surface_override_material(index,shader);applied=true
		if applied:_mesh_count+=1
	_update_house_transform()
	return not _entries.is_empty()

func apply_incident(cells: Variant) -> bool:
	if not is_instance_valid(_house):return false
	var checked: Variant=_validate(cells)
	if not checked is Array:return false
	_cells=checked
	_update_house_transform()
	for material: ShaderMaterial in _materials.values():
		for cell: Dictionary in _cells:
			var point: Vector3=CELL_POS[cell.id]
			material.set_shader_parameter("cell_"+str(cell.id),Vector4(point.x,point.z,float(cell.burned),float(cell.wet)))
	return true

func set_simulation_active(active: bool) -> void:
	_simulation_active=active # No temporal animation; explicit fresh snapshots remain allowed.

func capture_snapshot() -> Array:
	return _cells.duplicate(true)

func clear() -> void:
	for entry: Dictionary in _entries:
		var mesh: MeshInstance3D=entry.mesh
		if is_instance_valid(mesh) and mesh.get_surface_override_material(int(entry.index))==entry.shader:
			mesh.set_surface_override_material(int(entry.index),entry.previous)
	_entries.clear();_materials.clear();_shaders.clear();_cells.clear()
	_house=null;_mesh_count=0;_simulation_active=false

func diagnostics() -> Dictionary:
	return {"meshes":_mesh_count,"slots":_entries.size(),"materials":_materials.size(),
		"new_geometry":0,"new_colliders":0,"mask_pixels":[512,512],"simulation_active":_simulation_active,
		"cells":capture_snapshot(),"animated":false}

func _update_house_transform() -> void:
	if not is_instance_valid(_house):return
	for material: ShaderMaterial in _materials.values():
		material.set_shader_parameter("house_inverse",_house.global_transform.affine_inverse())

func _material(source: StandardMaterial3D) -> ShaderMaterial:
	var cull: int=source.cull_mode
	if not _shaders.has(cull):
		var shader:=Shader.new()
		var mode: String="cull_front" if cull==BaseMaterial3D.CULL_FRONT else("cull_disabled" if cull==BaseMaterial3D.CULL_DISABLED else "cull_back")
		shader.code=SURFACE_SHADER.code.replace("cull_back",mode);_shaders[cull]=shader
	var material:=ShaderMaterial.new();material.shader=_shaders[cull];material.resource_name="Incident/"+source.resource_name
	material.set_shader_parameter("incident_mask",MASK)
	material.set_shader_parameter("base_colour",source.albedo_color)
	material.set_shader_parameter("dry_roughness",source.roughness)
	material.set_shader_parameter("dry_metallic",source.metallic)
	material.set_shader_parameter("normal_depth",source.normal_scale)
	material.set_shader_parameter("roughness_channel",source.roughness_texture_channel)
	material.set_shader_parameter("metallic_channel",source.metallic_texture_channel)
	material.set_shader_parameter("uv_scale",Vector2(source.uv1_scale.x,source.uv1_scale.y))
	material.set_shader_parameter("uv_offset",Vector2(source.uv1_offset.x,source.uv1_offset.y))
	material.set_shader_parameter("use_vertex_colour",source.vertex_color_use_as_albedo)
	for parameter: String in ["albedo","roughness","metallic","normal"]:
		var texture: Texture2D=source.get(parameter+"_texture")
		material.set_shader_parameter("has_"+parameter,texture!=null)
		if texture!=null:material.set_shader_parameter("base_"+parameter,texture)
	return material

func _validate(value: Variant) -> Variant:
	if not value is Array or value.size()!=3:return null
	var seen: Dictionary={};var result: Array=[]
	for item: Variant in value:
		if not item is Dictionary or not item.get("id") is String or not CELL_POS.has(item.id) or seen.has(item.id):return null
		var point: Variant=_vector(item.get("pos"))
		if not point is Vector3 or point.distance_to(CELL_POS[item.id])>.0001:return null
		if not _number(item.get("burned"),0,float(CELL_FUEL[item.id])) or not _number(item.get("wet"),0,1):return null
		seen[item.id]=true
		result.append({"id":str(item.id),"pos":[point.x,point.y,point.z],"burned":float(item.burned),"wet":float(item.wet)})
	result.sort_custom(func(a:Dictionary,b:Dictionary):return str(a.id)<str(b.id))
	return result

func _vector(value: Variant) -> Variant:
	if value is Vector3:return value if value.is_finite() else null
	if not value is Array or value.size()!=3:return null
	for coordinate: Variant in value:
		if not _number(coordinate,-10,10):return null
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _number(value: Variant,low: float,high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node]=[]
	for child: Node in node.get_children():result.append(child);result.append_array(_descendants(child))
	return result


func _exit_tree() -> void:
	clear()
