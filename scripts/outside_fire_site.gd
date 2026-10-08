class_name OutsideFireSite
extends Node3D
## Physical, original outdoor props; all effects read the persistent model.
class OutdoorEffects:
	extends "res://scripts/fire_cell_vfx.gd"
	func _sync_bounds() -> void:
		if not is_instance_valid(_house) or not _house.is_inside_tree(): return
		for view: Dictionary in _views.values():
			for kind: String in view.materials:
				var material: ShaderMaterial = view.materials[kind]
				material.set_shader_parameter("floor_y", 0.035)
				material.set_shader_parameter("ceiling_y", 12.0)
				if kind in ["smoke", "steam"]: material.set_shader_parameter("room_clip", false)

const TARGET_LAYER := 32
var _district: Node3D
var _carrier: CharacterBody3D
var _model: RefCounted
var _owned: Node3D
var _effects: Node3D
var _hose: Node3D
var _nozzle: MeshInstance3D
var _points: Dictionary = {}
var _targets: Dictionary = {}
var _fuel: Dictionary = {}
var _materials: Array[StandardMaterial3D] = []
var _hose_signature := ""
var _active := false

func attach_to(district: Node3D) -> void:
	_district = district
	district.add_child(self)

func set_carrier(officer: CharacterBody3D) -> void:
	_carrier = officer

func setup(model: RefCounted) -> void:
	clear()
	_model = model
	if model.mode == "none": return
	_owned = Node3D.new()
	add_child(_owned)
	_hose = Node3D.new()
	_owned.add_child(_hose)
	var points := {"outside_exterior": [Vector3(0, 0, -3.3), "Buitenbrand · materiaal en afstand beoordelen"],
		"outside_surroundings": [Vector3(-3, 0, -4), "Omgeving · vrije terugweg controleren"],
		"outside_plan": [Vector3(-2, 0, -5.4), "Ploeg · inzet en overdracht"],
		"outside_water": [Vector3(6, 0, -5), "Waterwinning · aansluiten"]}
	for id: String in points:
		var point := Node3D.new()
		point.position = model.origin + points[id][0]
		_owned.add_child(point)
		_points[id] = {"node": point, "title": points[id][1]}
		_district.objects[id] = point
		_district._titles[id] = points[id][1]
	var water: Vector3 = model.water_source()
	_cylinder(water + Vector3(0, 0.38, 0), 0.14, 0.76, _plain(Color("a14135")), true)
	_box(water + Vector3(0, 0.5, 0), Vector3(0.5, 0.12, 0.14), _plain(Color("b66042")))
	_box(model.origin + Vector3(0, 0.031, -5.1), Vector3(6.0, 0.008, 0.06), _plain(Color("c5b979")))
	for cell: Dictionary in model.cells: _build_fuel(cell, int(model.variant))
	_effects = OutdoorEffects.new()
	_effects.setup_cells(_owned, model.cells)
	_nozzle = _box(Vector3.ZERO, Vector3(0.10, 0.12, 0.4), _plain(Color("687783")))
	_nozzle.hide()
	update_state(model)

func clear() -> void:
	for id: String in _points:
		if is_instance_valid(_district) and _district.objects.get(id) == _points[id].node:
			_district.objects.erase(id)
			_district._titles.erase(id)
	_points.clear(); _targets.clear(); _fuel.clear(); _materials.clear()
	_hose_signature = ""; _active = false
	if is_instance_valid(_effects): _effects.clear()
	if is_instance_valid(_owned):
		remove_child(_owned)
		_owned.queue_free()
	_owned = null; _effects = null; _hose = null; _nozzle = null

func _exit_tree() -> void:
	clear()

func set_simulation_active(enabled: bool) -> void:
	_active = enabled and is_instance_valid(_model) and _model.mode != "none" and _model.phase != "completed"
	if is_instance_valid(_effects): _effects.set_simulation_active(_active)
	if not _active and is_instance_valid(_effects): _effects.set_water_stream(Vector3.ZERO, Vector3.ZERO, false)

func update_state(model: RefCounted) -> void:
	if not is_instance_valid(_owned): return
	for cell: Dictionary in model.cells:
		_targets[cell.id].collision_layer = TARGET_LAYER if float(cell.heat) > 0.035 else 0
		var material: StandardMaterial3D = _fuel[cell.id].material
		material.albedo_color = _fuel[cell.id].base.lerp(Color("222426"), minf(1, float(cell.burned) * 15))
		material.roughness = lerpf(0.86, 0.28, float(cell.wet))
	_effects.update_state(model.cells, _active)
	if is_instance_valid(_district.atmosphere): _effects.set_quality(_district.atmosphere.quality)
	_sync_hose(model.hose_points)
	_nozzle.visible = model.phase == "active" and model.has_nozzle_at(_carrier.global_position) if is_instance_valid(_carrier) else false
	if _nozzle.visible: _nozzle.global_position = _carrier.global_position + Vector3(0.25, 1.25, 0)

func can_reach(id: String, officer: CharacterBody3D) -> bool:
	if not _points.has(id): return false
	var point: Node3D = _points[id].node
	if officer.global_position.distance_to(point.global_position) > 3: return false
	var query := PhysicsRayQueryParameters3D.create(officer.global_position + Vector3(0, 1.2, 0), point.global_position + Vector3(0, 1.2, 0), 1, [officer.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func get_interaction(officer: CharacterBody3D) -> Dictionary:
	var selected := {}; var nearest := 3.1
	for id: String in _points:
		var point: Node3D = _points[id].node
		var distance := officer.global_position.distance_to(point.global_position)
		if distance > 3.0 or distance >= nearest: continue
		var query := PhysicsRayQueryParameters3D.create(officer.global_position + Vector3(0, 1.2, 0), point.global_position + Vector3(0, 1.2, 0), 1, [officer.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
		selected = {"id": id, "title": _points[id].title, "node": point}
		nearest = distance
	return selected

func raycast_target(camera: Camera3D, officer: CharacterBody3D) -> String:
	var center := camera.get_viewport().get_visible_rect().size / 2.0
	var start := camera.project_ray_origin(center)
	var direction := camera.project_ray_normal(center)
	var query := PhysicsRayQueryParameters3D.create(start, start + direction * 24, 1 | TARGET_LAYER, [officer.get_rid()])
	query.collide_with_areas = true
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(query)
	if hit.is_empty() or not hit.collider.has_meta("outside_cell") or officer.global_position.distance_to(hit.position) > 8: return ""
	var nozzle := officer.global_position + Vector3(0.25, 1.25, 0)
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(nozzle, hit.position, 1, [officer.get_rid()])).is_empty(): return ""
	return str(hit.collider.get_meta("outside_cell"))

func show_jet(target_id: String, spraying: bool) -> void:
	if not is_instance_valid(_carrier) or not is_instance_valid(_effects): return
	var start := _carrier.global_position + Vector3(0.25, 1.25, 0)
	var camera: Camera3D = _carrier.camera
	var finish: Vector3 = _targets[target_id].global_position if _targets.has(target_id) else start - camera.global_basis.z * 6
	var query := PhysicsRayQueryParameters3D.create(start, finish, 1, [_carrier.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): finish = hit.position
	_effects.set_water_stream(start, finish, spraying and _active)
	if spraying and start.distance_to(finish) > 0.05: _nozzle.look_at(finish)

func _sync_hose(points: Array) -> void:
	var signature := JSON.stringify(points)
	if signature == _hose_signature: return
	_hose_signature = signature
	for child in _hose.get_children():
		_hose.remove_child(child); child.queue_free()
	for index in range(1, points.size()):
		var a := Vector3(float(points[index - 1][0]), 0.07, float(points[index - 1][2]))
		var b := Vector3(float(points[index][0]), 0.07, float(points[index][2]))
		var mesh := CylinderMesh.new(); mesh.top_radius = 0.045; mesh.bottom_radius = 0.045; mesh.height = a.distance_to(b); mesh.radial_segments = 10
		var segment := MeshInstance3D.new(); segment.mesh = mesh; segment.material_override = _plain(Color("c6b767"))
		_hose.add_child(segment); segment.position = (a + b) / 2; segment.quaternion = Quaternion(Vector3.UP, (b - a).normalized())

func _build_fuel(cell: Dictionary, variant: int) -> void:
	var at := Vector3(float(cell.pos[0]), 0, float(cell.pos[2]))
	var material := _plain([Color("a28a69"), Color("77694f"), Color("b69d79")][variant])
	var prefix := "res://assets/textures/vegetation/street_bark" if variant == 1 else "res://assets/textures/street/wood"
	material.albedo_texture = load(prefix + "_albedo.png")
	material.normal_enabled = true; material.normal_texture = load(prefix + "_normal.png")
	material.roughness_texture = load(prefix + "_roughness.png")
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_fuel[cell.id] = {"material": material, "base": material.albedo_color}
	if variant == 0:
		for level in range(2):
			for side in [-1.0, 1.0]:
				for slat in range(4):
					_box(at + Vector3(side * 0.54, 0.11 + level * 0.48 + slat * 0.10, 0), Vector3(0.055, 0.075, 0.96), material)
					_box(at + Vector3(0, 0.11 + level * 0.48 + slat * 0.10, side * 0.47), Vector3(1.10, 0.075, 0.055), material)
			for corner_x in [-0.5, 0.5]:
				for corner_z in [-0.43, 0.43]: _box(at + Vector3(corner_x, 0.28 + level * 0.48, corner_z), Vector3(0.06, 0.48, 0.06), material)
	elif variant == 1:
		for index in range(14):
			var log := _cylinder(at + Vector3((index % 4 - 1.5) * 0.22, 0.1 + (index / 4) * 0.15, sin(index * 2.2) * 0.12), 0.055 + (index % 3) * 0.012, 1.0 + (index % 4) * 0.08, material)
			log.rotation = Vector3(PI / 2, (index % 3 - 1) * 0.28, 0)
	else:
		for index in range(5):
			var box := _box(at + Vector3((index % 2 - 0.5) * 0.5, 0.17 + (index / 2) * 0.28, cos(index) * 0.12), Vector3(0.6, 0.32, 0.65), material)
			box.rotation.y = (index % 3 - 1) * 0.13
			_box(box.position + Vector3(0, 0.164, 0), Vector3(0.065, 0.009, 0.65), _plain(Color("d4be91")))
	var body := StaticBody3D.new(); body.position = at + Vector3(0, 0.4, 0)
	var collider := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = Vector3(1.14, 0.8, 1.05); collider.shape = shape; body.add_child(collider); _owned.add_child(body)
	var target := Area3D.new(); target.position = at + Vector3(0, 0.8, -0.08); target.collision_layer = TARGET_LAYER; target.collision_mask = 0; target.set_meta("outside_cell", str(cell.id))
	var target_shape := CollisionShape3D.new(); var sphere := SphereShape3D.new(); sphere.radius = 0.68; target_shape.shape = sphere; target.add_child(target_shape); _owned.add_child(target)
	_targets[cell.id] = target

func _plain(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new(); material.albedo_color = color; material.roughness = 0.86
	_materials.append(material)
	return material

func _box(at: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new(); mesh.size = size
	var instance := MeshInstance3D.new(); instance.mesh = mesh; instance.material_override = material; instance.position = at
	_owned.add_child(instance)
	return instance

func _cylinder(at: Vector3, radius: float, height: float, material: StandardMaterial3D, solid: bool = false) -> MeshInstance3D:
	var mesh := CylinderMesh.new(); mesh.top_radius = radius; mesh.bottom_radius = radius; mesh.height = height; mesh.radial_segments = 12
	var instance := MeshInstance3D.new(); instance.mesh = mesh; instance.material_override = material; instance.position = at; _owned.add_child(instance)
	if solid:
		var body := StaticBody3D.new(); var collision := CollisionShape3D.new(); var shape := CylinderShape3D.new(); shape.radius = radius; shape.height = height; collision.shape = shape; body.add_child(collision); instance.add_child(body)
	return instance
