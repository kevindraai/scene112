class_name FireSite
extends Node3D
## Original accessible Huis 24; the same cell positions survive into M4.

const HOUSE := Vector3(-2, 0, 48)
const HYDRANT := Vector3(7, 0, 44)
const ENTRANCE := Vector3(-2, 0, 44)
const SAFE_AREA := Vector3(8, 0, 40)
const VICTIM := HOUSE + Vector3(-0.8, 0, -1.8)
const TARGET_LAYER := 4
const Model = preload("res://scripts/fire_case.gd")
const VFX = preload("res://scripts/fire_cell_vfx.gd")
const Actor = preload("res://scripts/authored_actor.gd")
var point_positions := {"fire_exterior": Vector3(-5.5, 0, 42), "fire_door": ENTRANCE,
	"fire_hydrant": HYDRANT, "fire_plan": Vector3(1, 0, 41),
	"fire_safe": SAFE_AREA, "fire_victim": VICTIM}
var _district: Node3D
var _original: Node3D
var _house: Node3D
var _props: Node3D
var _hose: Node3D
var _victim: Node3D
var _door: Node3D
var _entry_bar: Node3D
var _carrier: Node3D
var _effects: Node3D
var _fuel_materials := {}
var _nozzle: MeshInstance3D
var _points: Dictionary = {}
var _cells: Dictionary = {}
var _materials: Dictionary = {}
var _active := false
var _simulation_active := false
var _mode := "none"
var _retreat_granted := false
var _clock := 0.0
var _hose_signature := ""


func attach_to(district: Node3D) -> void:
	_district = district
	district.add_child(self)


func set_carrier(officer: Node3D) -> void:
	_carrier = officer


func set_simulation_active(active: bool) -> void:
	_simulation_active = active and _active
	if is_instance_valid(_effects): _effects.set_simulation_active(_simulation_active)
	if is_instance_valid(_props):
		for node: Node in _descendants(_props):
			if node is AuthoredActor: node.set_simulation_active(_simulation_active)


func _ready() -> void:
	name = "FireSite"
	_original = _district.get_node_or_null("Woning24")
	_house = Node3D.new()
	_house.position = HOUSE
	add_child(_house)
	_props = Node3D.new()
	add_child(_props)
	_hose = Node3D.new()
	_props.add_child(_hose)
	_build_house()
	_build_response()
	_effects = VFX.new()
	_effects.setup_cells(_house, Model.CELL_DATA)
	_nozzle = _box(_props, Vector3.ZERO, Vector3(0.14, 0.14, 0.4), Color("566778")) as MeshInstance3D
	_nozzle.hide()
	set_mode("none")
	if is_instance_valid(_district.atmosphere): _district.atmosphere.refresh_materials()


func set_mode(mode: String) -> void:
	_mode = mode
	if mode == "none": _retreat_granted = false
	_active = mode != "none"
	_set_active(_house, _active)
	_set_active(_props, _active)
	if is_instance_valid(_original): _set_original_active(_original, not _active)
	if is_instance_valid(_effects): _effects.set_enabled(_active)
	for id: String in _points:
		if _active:
			_district.objects[id] = _points[id].node
			_district._titles[id] = _points[id].title
		else:
			_district.objects.erase(id)
			_district._titles.erase(id)
	if not _active:
		_simulation_active = false
		_effects.set_water_stream(Vector3.ZERO, Vector3.ZERO, false)
		_nozzle.hide()
		_victim.hide()


func is_inside(at: Vector3) -> bool:
	var local := at - HOUSE
	return absf(local.x) < 3.15 and absf(local.z) < 3.35 and local.y >= -0.2 and local.y < 2.755


func update_state(model: RefCounted) -> void:
	var data: Dictionary = model.to_dict()
	if str(data.mode) != _mode: set_mode(str(data.mode))
	if not _active: return
	for cell: Dictionary in data.cells:
		if not _cells.has(cell.id): _build_cell(cell)
		var view: Dictionary = _cells[cell.id]
		var heat := clampf(float(cell.heat), 0, 1)
		view.target.collision_layer = TARGET_LAYER if heat > 0.035 else 0
		for entry: Dictionary in _fuel_materials.get(str(cell.id), []):
			var material: StandardMaterial3D = entry.material
			var scorch := clampf(float(cell.burned) * 18, 0, 1)
			material.albedo_color = entry.color.lerp(Color("292b2b"), scorch * 0.82)
			material.roughness = lerpf(float(entry.roughness), 0.3, clampf(float(cell.wet), 0, 1))
			if is_instance_valid(_district.atmosphere):
				_district.atmosphere.sync_incident_albedo(entry.mesh, int(entry.surface), material)
	_effects.update_state(data.cells, _simulation_active)
	if is_instance_valid(_district.atmosphere): _effects.set_quality(_district.atmosphere.quality)
	var door_open: bool = data.recon.door
	_door.rotation.y = -PI / 2.0 if door_open else 0
	var may_enter: bool = model.can_enter() or (data.phase == "completed" and model.all_cold())
	# An unsafe threshold stops fresh entry but always leaves retreat possible.
	var local_carrier: Vector3 = _carrier.global_position - HOUSE if is_instance_valid(_carrier) else Vector3(100, 100, 100)
	if is_instance_valid(_carrier) and is_inside(_carrier.global_position): _retreat_granted = true
	if local_carrier.z < -4.1 or absf(local_carrier.x) > 3.5 or local_carrier.z > 3.7: _retreat_granted = false
	_set_active(_entry_bar, not may_enter and not _retreat_granted)
	_sync_hose(data.hose_points)
	_sync_victim(str(data.victim.status))
	_nozzle.visible = data.hydrant_connected and data.hose_points.size() >= 2 and data.phase == "active" and data.victim.status != "carried"
	if _nozzle.visible and is_instance_valid(_carrier):
		_nozzle.position = _carrier.global_position + Vector3(0.3, 1.2, -0.1)


func raycast_target(camera: Camera3D, officer: CharacterBody3D) -> String:
	var center := camera.get_viewport().get_visible_rect().size / 2.0
	var origin := camera.project_ray_origin(center)
	var direction := camera.project_ray_normal(center)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 24, 1 | TARGET_LAYER, [officer.get_rid()])
	query.collide_with_areas = true
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(query)
	if hit.is_empty() or not hit.collider.has_meta("fire_cell"): return ""
	if officer.global_position.distance_to(hit.position) > 8.0: return ""
	# Third-person visibility alone is insufficient: the actual nozzle line
	# must also clear the walls from the firefighter's position.
	var nozzle := officer.global_position + Vector3(0, 1.3, 0)
	var obstruction := space.intersect_ray(PhysicsRayQueryParameters3D.create(nozzle, hit.position, 1, [officer.get_rid()]))
	if not obstruction.is_empty(): return ""
	return str(hit.collider.get_meta("fire_cell"))


func show_jet(target_id: String, spraying: bool) -> void:
	if not is_instance_valid(_carrier) or not is_instance_valid(_effects): return
	var start := _carrier.global_position + Vector3(0.25, 1.25, 0)
	var camera := _carrier.get("camera") as Camera3D
	var finish: Vector3 = _cells[target_id].target.global_position if _cells.has(target_id) else start - camera.global_basis.z * 6.0
	# Misses end on the first real wall/prop rather than visually passing through.
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, finish, 1, [_carrier.get_rid()]))
	if not hit.is_empty(): finish = hit.position
	_effects.set_water_stream(start, finish, spraying and _simulation_active)
	if spraying and start.distance_to(finish) > 0.05: _nozzle.look_at(finish)

func _sync_hose(points: Array) -> void:
	var signature := JSON.stringify(points)
	if signature == _hose_signature: return
	_hose_signature = signature
	for child in _hose.get_children():
		_hose.remove_child(child)
		child.queue_free()
	for i in range(1, points.size()):
		var a := Vector3(float(points[i - 1][0]), 0.06, float(points[i - 1][2]))
		var b := Vector3(float(points[i][0]), 0.06, float(points[i][2]))
		var segment := _box(_hose, (a + b) / 2.0, Vector3(0.1, 0.1, a.distance_to(b)), Color("cabc6c"))
		segment.look_at(b)


func _sync_victim(status: String) -> void:
	if status == "carried" and is_instance_valid(_carrier):
		var graphics: Node3D = _carrier.get("_graphics")
		var facing := graphics.global_basis if is_instance_valid(graphics) else _carrier.global_basis
		_victim.global_position = _carrier.global_position + facing * Vector3(0.4, 1.15, -0.55)
		_victim.rotation = Vector3(0, facing.get_euler().y, PI / 2.0)
	elif status == "rescued":
		_victim.position = SAFE_AREA + Vector3(1.2, 0.15, 0.5)
		_victim.rotation = Vector3.ZERO
	else:
		_victim.position = VICTIM
		_victim.rotation = Vector3.ZERO
	_victim.visible = status != "lost"
	if status in ["carried", "rescued", "lost"]:
		_district.objects.erase("fire_victim")
	else:
		_district.objects.fire_victim = _victim


func _process(_delta: float) -> void:
	if _active and is_instance_valid(_victim):
		for child in _victim.get_children():
			if child is AuthoredActor:
				child.set_simulation_active(_simulation_active)
				child.set_motion(0, false, _victim.rotation.z != 0)

func _build_house() -> void:
	var scene := load("res://assets/models/house24/burning_house24.glb") as PackedScene
	var model := scene.instantiate() as Node3D
	_house.add_child(model)
	_door = model.find_child("DoorPivot", true, false)
	for node: Node in _descendants(model):
		if not node is MeshInstance3D: continue
		var mesh := node as MeshInstance3D
		# Interior materials respond only to incident water, not exterior weather.
		if mesh.name != "MasonryShellSurface" and mesh.name != "WindowLeaf": mesh.set_meta("street_surface", "interior")
		if str(mesh.name) in ["MasonryShellSurface", "WindowLeaf", "WalkableFloor", "GroundFloorCeiling", "InteriorLiningSurface", "DoorLeaf", "LivingSofaSurface", "LivingSideboardSurface", "KitchenUnitsSurface", "KitchenFridgeSurface", "FuelSideSurface", "FuelOriginSurface", "FuelFrontSurface"]:
			var body := StaticBody3D.new()
			var collision := CollisionShape3D.new()
			collision.shape = mesh.mesh.create_trimesh_shape()
			body.add_child(collision)
			mesh.add_child(body)
		for id: String in ["front", "origin", "side"]:
			if str(mesh.name) != "Fuel" + id.capitalize() + "Surface": continue
			_fuel_materials[id] = []
			for index in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(index).duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(index, material)
				_fuel_materials[id].append({"mesh": mesh, "surface": index, "material": material, "color": material.albedo_color, "roughness": material.roughness})
	# Invisible safety boundary gates new entry while leaving retreat available.
	_entry_bar = StaticBody3D.new()
	_entry_bar.position = Vector3(0, 1.1, -3.55)
	_entry_bar.collision_layer = 8
	_entry_bar.collision_mask = 1
	var gate := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.215, 2.2, 0.08)
	gate.shape = shape
	_entry_bar.add_child(gate)
	_house.add_child(_entry_bar)
	_label(_house, "24 · TOEGANG BEOORDELEN", Vector3(0, 2.5, -3.7), 0.002)

func _build_response() -> void:
	var titles := {"fire_exterior": "Verkennen · buitenzijde Huis 24", "fire_door": "Verkennen · toegang en deurcontrole",
		"fire_hydrant": "Waterwinning · hydrant aansluiten", "fire_plan": "Ploeg · inzetplan en overdracht",
		"fire_safe": "Opvang · slachtoffer overdragen"}
	for id: String in titles:
		var point := Node3D.new()
		point.position = point_positions[id]
		_props.add_child(point)
		_points[id] = {"node": point, "title": titles[id]}
	_cylinder(_props, HYDRANT + Vector3(0, 0.4, 0), 0.16, 0.8, Color("9d3a38"), true)
	_box(_props, HYDRANT + Vector3(0, 0.42, 0), Vector3(0.55, 0.15, 0.16), Color("ac4c45"))
	_label(_props, "WATERWINNING", HYDRANT + Vector3(0, 1.4, 0), 0.003)
	_box(_props, SAFE_AREA + Vector3(0, 0.025, 0), Vector3(4, 0.025, 3), Color("79a39a"))
	_label(_props, "VEILIGE OPVANG  /  PLOEG", SAFE_AREA + Vector3(0, 2.4, 0), 0.003)
	_person(_props, SAFE_AREA + Vector3(-1.2, 0, 0.5), Color("495f72"), true)
	_person(_props, SAFE_AREA + Vector3(1.6, 0, -0.7), Color("77a48b"), false)
	_victim = _person(_props, VICTIM, Color("b58b68"), false)
	_points.fire_victim = {"node": _victim, "title": "Slachtoffer · zoeken en dragen"}


func _build_cell(cell: Dictionary) -> void:
	var root := Node3D.new()
	root.position = Vector3(float(cell.pos[0]), float(cell.pos[1]), float(cell.pos[2]))
	_house.add_child(root)
	var target := Area3D.new()
	target.position.y = 0.6
	target.collision_layer = TARGET_LAYER
	target.collision_mask = 0
	target.set_meta("fire_cell", str(cell.id))
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.66
	collision.shape = shape
	target.add_child(collision)
	root.add_child(target)
	_cells[cell.id] = {"target": target}

func _person(parent: Node3D, at: Vector3, color: Color, firefighter: bool) -> Node3D:
	var person := Node3D.new()
	person.position = at
	parent.add_child(person)
	var actor := Actor.new()
	actor.uniform = firefighter
	actor.firefighter = firefighter
	actor.clothes = color
	person.add_child(actor)
	return person

func _set_active(node: Node, enabled: bool) -> void:
	if node is Node3D: node.visible = enabled
	if node is CollisionObject3D:
		if not node.has_meta("layer"):
			node.set_meta("layer", node.collision_layer)
			node.set_meta("mask", node.collision_mask)
		node.collision_layer = int(node.get_meta("layer")) if enabled else 0
		node.collision_mask = int(node.get_meta("mask")) if enabled else 0
	for child in node.get_children(): _set_active(child, enabled)


func _label(parent: Node3D, text: String, at: Vector3, pixel: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = 38
	label.pixel_size = pixel
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)


func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color, solid: bool = false) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, at, mesh, color, solid)


func _cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: Color, solid: bool = false) -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	return _mesh(parent, at, mesh, color, solid)


func _mesh(parent: Node3D, at: Vector3, mesh: PrimitiveMesh, color: Color, solid: bool) -> Node3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color)
	var result: Node3D = instance
	if solid:
		var body := StaticBody3D.new()
		body.add_child(instance)
		var collision := CollisionShape3D.new()
		collision.shape = mesh.create_convex_shape()
		body.add_child(collision)
		result = body
	result.position = at
	parent.add_child(result)
	return result


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.85
		_materials[key] = material
	return _materials[key]


func _set_original_active(node: Node, enabled: bool) -> void:
	if node is Node3D:
		if not node.has_meta("fire_original_visible"): node.set_meta("fire_original_visible", node.visible)
		node.visible = bool(node.get_meta("fire_original_visible")) if enabled else false
	if node is CollisionObject3D:
		if not node.has_meta("fire_original_layer"):
			node.set_meta("fire_original_layer", node.collision_layer)
			node.set_meta("fire_original_mask", node.collision_mask)
		node.collision_layer = int(node.get_meta("fire_original_layer")) if enabled else 0
		node.collision_mask = int(node.get_meta("fire_original_mask")) if enabled else 0
	for child in node.get_children(): _set_original_active(child, enabled)

func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children(): result.append_array(_descendants(child))
	return result


func reset_entry_access() -> void:
	_retreat_granted = false
