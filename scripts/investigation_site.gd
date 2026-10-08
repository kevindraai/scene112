class_name InvestigationSite
extends Node3D
## Original incident visuals reused after a declared crew handover; archive is immutable.
const Aftermath = preload("res://scripts/incident_aftermath.gd")
var _aftermath: Node3D
const Actor = preload("res://scripts/authored_actor.gd")
const TARGET_LAYER := 16
var _district: Node3D
var _fire_site: Node3D
var _owned: Node3D
var _points := {}
var _actors: Array[Node3D] = []
var _active := false
var _view: RefCounted

class ColdView extends RefCounted:
	var data: Dictionary
	func _init(snapshot: Dictionary) -> void:
		data = snapshot.duplicate(true)
		data.mode = "research"
		data.phase = "completed"
		data.victim.status = "lost" # Visual omission only; never write archive fate.
		for cell: Dictionary in data.cells: cell.heat = 0
	func to_dict() -> Dictionary: return data.duplicate(true)
	func can_enter() -> bool: return true
	func all_cold() -> bool: return true

func setup(district: Node3D, fire_site: Node3D, model: RefCounted) -> void:
	_district = district
	_fire_site = fire_site
	if get_parent() == null: district.add_child(self)
	clear()
	if model.mode == "none": return
	_active = true
	_view = ColdView.new(model.incident)
	_fire_site.update_state(_view)
	_aftermath = Aftermath.new()
	add_child(_aftermath)
	_aftermath.setup(_fire_site._house)
	_aftermath.apply_incident(model.incident.cells)
	_fire_site.reset_entry_access()
	# Fire duties do not mask investigation prompts in the same house.
	for id: String in _fire_site._points:
		_district.objects.erase(id)
		_district._titles.erase(id)
	_owned = Node3D.new()
	add_child(_owned)
	for id: String in model._data.evidence:
		var source: Dictionary = model._data.evidence[id]
		var values: Array = source.position
		var point := Area3D.new()
		point.name = "Evidence_" + id
		point.position = Vector3(float(values[0]), float(values[1]), float(values[2]))
		point.collision_layer = TARGET_LAYER
		point.collision_mask = 0
		point.set_meta("evidence_id", id)
		var shape := SphereShape3D.new()
		shape.radius = 0.23 if id == "connection" else 0.42
		var collision := CollisionShape3D.new()
		collision.shape = shape
		point.add_child(collision)
		_owned.add_child(point)
		_register("ev_" + id, point, "Onderzoeken · " + source.title)
	_actor("saar", Vector3(5, 0.02, 41), Color("748b84"))
	_actor("lars", Vector3(12, 0.02, 41), Color("718398"))
	var board := Node3D.new()
	board.position = Vector3(0, 1.0, -7.35)
	_owned.add_child(board)
	_register("research_board", board, "Onderzoeksbord · bronnen, hypotheses en rapport")
	var lab := Node3D.new()
	lab.position = Vector3(-6.5, 1.0, -6.4)
	_owned.add_child(lab)
	_register("research_lab", lab, "Sporenbalie · overdracht en deskundigenresultaat")

func _register(id: String, node: Node3D, title: String) -> void:
	_points[id] = node
	_district.objects[id] = node
	_district._titles[id] = title

func _actor(id: String, at: Vector3, clothes: Color) -> void:
	var person := StaticBody3D.new()
	person.position = at
	var shape := CapsuleShape3D.new()
	shape.radius = 0.31
	shape.height = 1.8
	var collision := CollisionShape3D.new()
	collision.position.y = 0.9
	collision.shape = shape
	person.add_child(collision)
	var actor := Actor.new()
	actor.clothes = clothes
	person.add_child(actor)
	_owned.add_child(person)
	_actors.append(actor)
	_register("witness_" + id, person, "Gesprek · " + ("Saar, bewoner" if id == "saar" else "Lars, kennis"))
	var label := Label3D.new()
	label.text = "SAAR · BEWONER" if id == "saar" else "LARS · KENNIS"
	label.position.y = 2.1
	label.font_size = 30
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	person.add_child(label)

func aimed_evidence(camera: Camera3D, officer: CharacterBody3D) -> String:
	if not _active: return ""
	var center := camera.get_viewport().get_visible_rect().size / 2.0
	var from := camera.project_ray_origin(center)
	var to := from + camera.project_ray_normal(center) * 24
	var excluded: Array[RID] = [officer.get_rid()]
	# Evidence areas identify reachable objects; their invisible wide edges must
	# not occlude another source. Require a deliberate centre aim and continue
	# past off-axis identification areas. Actual masonry/furniture still blocks.
	for attempt in _points.size():
		var query := PhysicsRayQueryParameters3D.create(from, to, 1 | TARGET_LAYER, excluded)
		query.collide_with_areas = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or not hit.collider.has_meta("evidence_id"): return ""
		var point := hit.collider as Area3D
		var direction := (to - from).normalized()
		var along := (point.global_position - from).dot(direction)
		var off_axis := point.global_position.distance_to(from + direction * along)
		if off_axis > 0.15:
			excluded.append(point.get_rid())
			continue
		if officer.global_position.distance_to(hit.position) > 3.5: return ""
		var id := str(point.get_meta("evidence_id"))
		if id in ["origin", "connection", "living", "overview"] and not _fire_site.is_inside(officer.global_position): return ""
		return id
	return ""

func can_reach(id: String, officer: CharacterBody3D) -> bool:
	var node: Node3D = _points.get(id)
	if node == null or officer.global_position.distance_to(node.global_position) > 3.5: return false
	var from := officer.global_position + Vector3(0, 1.3, 0)
	var to := node.global_position + Vector3(0, 0.8, 0) if id.begins_with("witness_") else node.global_position
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1, [officer.get_rid()]))
	return hit.is_empty() or hit.collider == node

func set_simulation_active(active: bool) -> void:
	for actor in _actors:
		if is_instance_valid(actor): actor.set_simulation_active(active and _active)

func clear() -> void:
	if is_instance_valid(_aftermath):
		_aftermath.clear()
		if _aftermath.get_parent() != null: _aftermath.get_parent().remove_child(_aftermath)
		_aftermath.queue_free()
	_aftermath = null
	if is_instance_valid(_district):
		for id: String in _points:
			_district.objects.erase(id)
			_district._titles.erase(id)
	_points.clear()
	_actors.clear()
	if is_instance_valid(_owned):
		remove_child(_owned)
		_owned.queue_free()
	_owned = null
	_view = null
	_active = false
