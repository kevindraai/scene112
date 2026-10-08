class_name Civilian
extends CharacterBody3D
## Deterministic short patrols, collision-aware walking and readable silhouettes.

var route := PackedVector3Array()
var walking_speed := 1.2
var clothes := Color("648f83")
var skin := Color("cfa681")
var _index := 1
var _direction := 1
var _wait := 0.0
var _stuck := 0.0
var _phase := 0.0
var _graphics: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []


func _ready() -> void:
	floor_snap_length = 0.25
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.72
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 0.87
	add_child(collision)
	_graphics = Node3D.new()
	add_child(_graphics)
	_part(_graphics, Vector3(0, 1.11, 0), Vector3(0.49, 0.6, 0.3), clothes)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.21
	sphere.height = 0.43
	sphere.radial_segments = 12
	sphere.rings = 6
	head.mesh = sphere
	head.material_override = _material(skin)
	head.position = Vector3(0, 1.6, 0)
	_graphics.add_child(head)
	_part(_graphics, Vector3(0, 1.77, 0.01), Vector3(0.4, 0.12, 0.35), Color("5a4b3c"))
	for x in [-0.125, 0.125]:
		var leg := _limb(Vector3(x, 0.84, 0), Vector3(0.18, 0.67, 0.23), Color("4a5763"))
		_part(leg, Vector3(0, -0.71, -0.06), Vector3(0.21, 0.16, 0.34), Color("34383d"))
		_legs.append(leg)
	for x in [-0.32, 0.32]:
		var arm := _limb(Vector3(x, 1.37, 0), Vector3(0.14, 0.48, 0.18), clothes)
		_part(arm, Vector3(0, -0.52, 0), Vector3(0.13, 0.15, 0.16), skin)
		_arms.append(arm)


func pause_for(seconds: float = 5.0) -> void:
	_wait = maxf(_wait, seconds)


func _physics_process(delta: float) -> void:
	_wait = maxf(0, _wait - delta)
	var direction := Vector3.ZERO
	if route.size() > 1 and _wait <= 0:
		var target := route[_index]
		var offset := target - global_position
		offset.y = 0
		if offset.length() < 0.45:
			_advance()
			_wait = 0.8
		else:
			direction = offset.normalized()
	velocity.x = move_toward(velocity.x, direction.x * walking_speed, 5.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * walking_speed, 5.0 * delta)
	velocity.y = -0.4 if is_on_floor() else velocity.y - 20.0 * delta
	var previous := global_position
	move_and_slide()
	var travelled := Vector2(global_position.x - previous.x, global_position.z - previous.z).length()
	if direction.length_squared() > 0.1 and travelled < walking_speed * delta * 0.15:
		_stuck += delta
		if _stuck > 2.0:
			_direction *= -1
			_advance()
			_wait = 1.3
			_stuck = 0
	else:
		_stuck = 0
	if direction.length_squared() > 0.1:
		_graphics.rotation.y = lerp_angle(_graphics.rotation.y, atan2(-direction.x, -direction.z), delta * 7.0)
	_phase += travelled * 5.2
	var swing := sin(_phase) * minf(travelled / maxf(delta, 0.001), walking_speed) * 0.32
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	_arms[0].rotation.x = -swing * 0.7
	_arms[1].rotation.x = swing * 0.7


func _advance() -> void:
	_index = (_index + _direction + route.size()) % route.size()


func _limb(at: Vector3, size: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	_graphics.add_child(pivot)
	_part(pivot, Vector3(0, -size.y / 2.0, 0), size, color)
	return pivot


func _part(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	instance.mesh = shape
	instance.material_override = _material(color)
	instance.position = at
	parent.add_child(instance)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material
