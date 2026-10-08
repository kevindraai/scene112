class_name PoliceSite
extends Node3D
## The first-service traffic scene and an independent academy intake station.

const CivilianScript = preload("res://scripts/pedestrian.gd")
const CONE_ZONES := [Vector3(-26, 0, 15), Vector3(-28, 0, 17), Vector3(-26, 0, 19)]

var _district: Node3D
var _traffic: Node3D
var _intake: Node3D
var _guidance: Node3D
var _cones: Node3D
var _points: Dictionary = {}
var _people: Array[CharacterBody3D] = []
var _trainee: CharacterBody3D
var _materials: Dictionary = {}
var _mode := "none"
var _simulation_active := false
var _clock := 0.0
var _cone_signature := ""


func attach_to(district: Node3D) -> void:
	_district = district
	district.add_child(self)


func _ready() -> void:
	name = "PoliceSite"
	_traffic = Node3D.new()
	_traffic.name = "Verkeersincident"
	add_child(_traffic)
	_cones = Node3D.new()
	_traffic.add_child(_cones)
	_guidance = Node3D.new()
	_traffic.add_child(_guidance)
	_build_wreck()
	_person("pc_lotte", "Spreken · Lotte (bestuurder)", Vector3(-19, 0.02, 21), Color("c3a26d"))
	_person("pc_bram", "Spreken · Bram (getuige)", Vector3(-16, 0.02, 14.5), Color("6d90a3"))
	_point("pc_damage", "Waarnemen · schade aan voertuig", Vector3(-18, 0, 18), _traffic)
	_point("pc_tracks", "Waarnemen · remsporen", Vector3(-20, 0, 15), _traffic)
	_point("pc_signal", "Waarnemen · verkeerssituatie", Vector3(-20, 0, 19.2), _traffic)
	var wet := _box(_traffic, Vector3(-20, 0.041, 19.2), Vector3(3.7, 0.014, 3.7), Color("465e69")) as MeshInstance3D
	var wet_material := StandardMaterial3D.new()
	wet_material.albedo_color = Color("465e69")
	wet_material.roughness = 0.12
	wet_material.metallic = 0.15
	wet.material_override = wet_material
	for x in [-20.35, -19.75]:
		_box(_traffic, Vector3(x, 0.03, 15.9), Vector3(0.08, 0.01, 2.2), Color("25313a"))
	for i in range(CONE_ZONES.size()):
		var zone: Vector3 = CONE_ZONES[i]
		_cylinder(_guidance, zone + Vector3(0, 0.045, 0), 0.58, 0.015, Color("d7b75b"))
		_label(_guidance, "AFZETPUNT %d" % (i + 1), zone + Vector3(0, 0.5, 0), 0.0035)
	_intake = Node3D.new()
	_intake.name = "AcademieIntake"
	_intake.position = Vector3(-6.5, 0, -7)
	add_child(_intake)
	_box(_intake, Vector3(0, 0.6, -0.65), Vector3(2.4, 1.2, 0.8), Color("35516a"), true)
	_box(_intake, Vector3(0, 1.31, -0.55), Vector3(0.8, 0.2, 0.55), Color("859faa"))
	_box(_intake, Vector3(0, 1.42, -0.55), Vector3(0.55, 0.03, 0.35), Color("8bd3c5"))
	_label(_intake, "REGISTRATIE  /  ACADEMIE", Vector3(0, 2, -0.6), 0.0035)
	_points.pc_intake = {"node": _intake, "title": "Intake · academie-arrestant"}
	_trainee = CivilianScript.new()
	_trainee.name = "OefenarrestantJoris"
	_trainee.position = Vector3(-1.7, 0.02, -0.2)
	_trainee.clothes = Color("8b826a")
	_intake.add_child(_trainee)
	_points.pc_trainee = {"node": _trainee, "title": "Joris · volwassen oefenarrestant"}
	_label(_intake, "JORIS · OEFENFIGURANT", Vector3(-1.7, 2.0, -0.2), 0.0025)
	var report := Node3D.new()
	report.position = Vector3(0, 0, -6.8)
	add_child(report)
	_points.pc_report = {"node": report, "title": "Dossier · proces-verbaal opstellen"}
	set_mode("none")


func set_mode(mode: String) -> void:
	_mode = mode
	var traffic_active := mode in ["basis", "campaign"]
	var intake_active := mode == "intake"
	_set_active(_traffic, traffic_active)
	_set_active(_intake, intake_active)
	show_guidance(mode == "basis")
	for id: String in _points:
		var enabled := intake_active if id in ["pc_intake", "pc_trainee"] else traffic_active
		if id == "pc_report": enabled = traffic_active or intake_active
		if enabled:
			_district.objects[id] = _points[id].node
			_district._titles[id] = _points[id].title
		else:
			_district.objects.erase(id)
			_district._titles.erase(id)
	set_simulation_active(traffic_active)


func set_simulation_active(active: bool) -> void:
	_simulation_active = active and _mode in ["basis", "campaign"]
	for person in _people:
		person.set_physics_process(_simulation_active)
	if is_instance_valid(_trainee): _trainee.set_physics_process(active and _mode == "intake")


func show_guidance(enabled: bool) -> void:
	_guidance.visible = enabled and _mode in ["basis", "campaign"]


func sync_cones(positions: Array) -> void:
	var signature := JSON.stringify(positions)
	if signature == _cone_signature: return
	_cone_signature = signature
	for child in _cones.get_children():
		_cones.remove_child(child)
		child.queue_free()
	for point: Array in positions:
		var at := Vector3(float(point[0]), float(point[1]), float(point[2]))
		var cone := Node3D.new()
		cone.position = at
		_cones.add_child(cone)
		_box(cone, Vector3(0, 0.04, 0), Vector3(0.5, 0.08, 0.5), Color("2b3a44"))
		var shape := CylinderMesh.new()
		shape.top_radius = 0.035
		shape.bottom_radius = 0.2
		shape.height = 0.65
		_mesh(cone, Vector3(0, 0.4, 0), shape, Color("e39a42"), false)
		_cylinder(cone, Vector3(0, 0.42, 0), 0.13, 0.11, Color("eee8d5"))


func _process(delta: float) -> void:
	if not _simulation_active: return
	_clock += delta
	for i in range(_people.size()):
		var graphics: Node3D = _people[i].get("_graphics")
		if graphics != null:
			graphics.scale.y = 1.0 + sin(_clock * 1.4 + i) * 0.008


func _set_active(node: Node, enabled: bool) -> void:
	if node is Node3D: node.visible = enabled
	if node is CollisionObject3D:
		if not node.has_meta("original_layer"):
			node.set_meta("original_layer", node.collision_layer)
			node.set_meta("original_mask", node.collision_mask)
		node.collision_layer = int(node.get_meta("original_layer")) if enabled else 0
		node.collision_mask = int(node.get_meta("original_mask")) if enabled else 0
	for child in node.get_children(): _set_active(child, enabled)


func _build_wreck() -> void:
	var wreck := Node3D.new()
	wreck.position = Vector3(-18, 0, 18)
	wreck.rotation.y = -PI / 2.0
	_traffic.add_child(wreck)
	_box(wreck, Vector3(0, 0.72, 0), Vector3(1.8, 0.68, 4.2), Color("78957f"), true)
	_box(wreck, Vector3(0, 1.3, 0.2), Vector3(1.68, 0.7, 2.2), Color("78957f"), true)
	_box(wreck, Vector3(0, 1.35, -0.92), Vector3(1.5, 0.46, 0.06), Color("729bab"))
	_box(wreck, Vector3(0.35, 0.73, -2.13), Vector3(1, 0.35, 0.18), Color("505c5a"))
	for x in [-0.94, 0.94]:
		_box(wreck, Vector3(x, 1.37, 0.1), Vector3(0.035, 0.42, 1.85), Color("729bab"))
		for z in [-1.3, 1.3]:
			var wheel := _cylinder(wreck, Vector3(x, 0.42, z), 0.41, 0.18, Color("293541"))
			wheel.rotation.z = PI / 2.0
	_label(_traffic, "VERKEERSINCIDENT", Vector3(-18, 2.8, 18), 0.0035)


func _person(id: String, title: String, at: Vector3, clothes: Color) -> void:
	var person := CivilianScript.new()
	person.position = at
	person.clothes = clothes
	person.rotation.y = PI / 2.0
	_traffic.add_child(person)
	_people.append(person)
	_points[id] = {"node": person, "title": title}
	_label(_traffic, title.trim_prefix("Spreken · "), at + Vector3(0, 2.1, 0), 0.003)


func _point(id: String, title: String, at: Vector3, parent: Node3D) -> void:
	var point := Node3D.new()
	point.position = at
	parent.add_child(point)
	_points[id] = {"node": point, "title": title}
	_label(parent, title.trim_prefix("Waarnemen · "), at + Vector3(0, 0.75, 0), 0.0028)


func _label(parent: Node3D, text: String, at: Vector3, pixel_size: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = 40
	label.pixel_size = pixel_size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("f1dcc0")
	parent.add_child(label)


func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color, solid: bool = false) -> Node3D:
	var shape := BoxMesh.new()
	shape.size = size
	return _mesh(parent, at, shape, color, solid)


func _cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: Color) -> Node3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 12
	return _mesh(parent, at, shape, color, false)


func _mesh(parent: Node3D, at: Vector3, shape: PrimitiveMesh, color: Color, solid: bool) -> Node3D:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.86
		_materials[key] = material
	instance.material_override = _materials[key]
	var result: Node3D = instance
	if solid:
		var body := StaticBody3D.new()
		body.add_child(instance)
		var collision := CollisionShape3D.new()
		collision.shape = shape.create_convex_shape()
		body.add_child(collision)
		result = body
	result.position = at
	parent.add_child(result)
	return result
