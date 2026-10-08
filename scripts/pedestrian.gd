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
var _graphics: Node3D
const Actor = preload("res://scripts/authored_actor.gd")


func _ready() -> void:
	floor_snap_length = 0.25
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.72
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 0.87
	add_child(collision)
	_graphics = Actor.new()
	_graphics.clothes = clothes
	_graphics.skin = skin
	add_child(_graphics)


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
	_graphics.set_motion(travelled / maxf(delta, 0.001))


func _advance() -> void:
	_index = (_index + _direction + route.size()) % route.size()

func set_simulation_active(active: bool) -> void:
	set_physics_process(active)
	if is_instance_valid(_graphics): _graphics.set_simulation_active(active)
