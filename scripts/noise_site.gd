extends Node3D
const Actor = preload("res://scripts/authored_actor.gd")
const Bicycle = preload("res://assets/models/street/dutch_bicycle.glb")
var _district: Node3D
var _owned: Node3D
var _nodes := {}
var _people := {}
var _active := false

class Party extends CharacterBody3D:
	var actor: Node3D
	var destination: Vector3
	var moving := false
	var simulation_active := false
	func _physics_process(delta: float) -> void:
		if not simulation_active: return
		var offset := destination - global_position
		offset.y = 0
		var direction := offset.normalized() if moving and offset.length() > 0.2 else Vector3.ZERO
		velocity.x = move_toward(velocity.x, direction.x * 1.3, delta * 8)
		velocity.z = move_toward(velocity.z, direction.z * 1.3, delta * 8)
		velocity.y = -0.5 if is_on_floor() else velocity.y - delta * 22
		move_and_slide()
		if direction.length() > 0.01: actor.rotation.y = lerp_angle(actor.rotation.y, atan2(-direction.x, -direction.z), delta * 8)
		actor.set_motion(Vector2(velocity.x, velocity.z).length(), false)

func setup(district: Node3D, model: RefCounted, at: Vector3) -> void:
	_district = district
	if get_parent() == null: district.add_child(self)
	clear()
	if model.phase == "none": return
	_owned = Node3D.new()
	add_child(_owned)
	if model.variant in [0, 1]:
		var bicycle: Node3D = Bicycle.instantiate()
		bicycle.name = "IncidentBicycle"
		bicycle.position = at + (Vector3(0.3, 0, -2.7) if model.variant == 0 else Vector3(4.2, 0, 1.2))
		bicycle.rotation.z = -0.12
		_owned.add_child(bicycle)
		var body := StaticBody3D.new()
		body.position = bicycle.position + Vector3(0, 0.54, 0)
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.85, 1.08, 0.45)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		_owned.add_child(body)
	for index in 2:
		var side := "reporter" if index == 0 else "participant"
		var person := Party.new()
		person.position = at + Vector3(-0.65 if index == 0 else 0.65, 0.1, 0)
		person.destination = at + Vector3(-2.4 if index == 0 else 2.4, 0.1, 1.2)
		if model.separated: person.position = person.destination
		person.floor_snap_length = 0.3
		var collision := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.height = 1.8
		shape.radius = 0.31
		collision.position.y = 0.91
		collision.shape = shape
		person.add_child(collision)
		person.actor = Actor.new()
		person.actor.clothes = Color("648695") if index == 0 else Color("90744f")
		person.add_child(person.actor)
		_owned.add_child(person)
		_people[side] = person
		_register("noise_" + side, person, "Gesprek · " + str(model.DATA.VARIANTS[model.variant][side].name))
	var activity := Node3D.new()
	activity.position = at + Vector3(0, 0.8, -1.7)
	_owned.add_child(activity)
	_register("noise_activity", activity, "Eigen waarneming · activiteit en geluid")
	var access := Node3D.new()
	access.position = at + Vector3(0, 0.8, 2.6)
	_owned.add_child(access)
	_register("noise_access", access, "Eigen waarneming · doorgang en veiligheid")

func _register(id: String, point: Node3D, title: String) -> void:
	_nodes[id] = point
	_district.objects[id] = point
	_district._titles[id] = title

func update_model(model: RefCounted, active: bool) -> void:
	_active = active
	for side: String in _people:
		var person: Party = _people[side]
		person.moving = model.people[side].agreement
		person.simulation_active = active
		person.actor.set_simulation_active(active)
	if active and model.phase == "active" and model.people.reporter.agreement and model.people.participant.agreement:
		var reporter: Party = _people.reporter
		var participant: Party = _people.participant
		if reporter.global_position.distance_to(reporter.destination) < 0.35 and participant.global_position.distance_to(participant.destination) < 0.35:
			model.record_separation(reporter.global_position.distance_to(participant.global_position))

func set_simulation_active(active: bool) -> void:
	_active = active
	for person: Party in _people.values():
		person.simulation_active = active
		person.actor.set_simulation_active(active)

func can_reach(id: String, officer: CharacterBody3D) -> bool:
	var point: Node3D = _nodes.get(id)
	if point == null or officer.position.distance_to(point.global_position) > 3: return false
	var end := point.global_position + Vector3(0, 1, 0) if point is CharacterBody3D else point.global_position
	var query := PhysicsRayQueryParameters3D.create(officer.global_position + Vector3(0, 1.3, 0), end, 1, [officer.get_rid()])
	var hit := officer.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == point

func clear() -> void:
	if is_instance_valid(_district):
		for id: String in _nodes:
			_district.objects.erase(id)
			_district._titles.erase(id)
	_nodes.clear()
	_people.clear()
	if is_instance_valid(_owned):
		remove_child(_owned)
		_owned.queue_free()
	_owned = null

func get_interaction(officer: CharacterBody3D) -> Dictionary:
	var best := 3.0
	var found := {}
	for id: String in _nodes:
		var point: Node3D = _nodes[id]
		var offset := officer.global_position - point.global_position
		var distance := Vector2(offset.x, offset.z).length()
		if distance < best and can_reach(id, officer):
			best = distance
			found = {"id": id, "title": _district._titles[id]}
	return found
