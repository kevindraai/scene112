class_name Officer
extends CharacterBody3D
## Camera-relative third-person movement; visuals never rotate the collision body.

var enable_input := true
var sensitivity := 0.003
var camera: Camera3D
var _pivot: Node3D
var _arm: SpringArm3D
var _graphics: Node3D
var speed_scale := 1.0
const Actor = preload("res://scripts/authored_actor.gd")
var _pitch := -0.23

const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.1
const ACCELERATION := 22.0
const GRAVITY := 22.0


func _ready() -> void:
	name = "Officer"
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(48)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.31
	capsule.height = 1.8
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 0.91
	add_child(collision)
	_avatar()
	_pivot = Node3D.new()
	_pivot.name = "CameraPivot"
	_pivot.position = Vector3(0, 1.55, 0)
	_pivot.rotation.x = _pitch
	add_child(_pivot)
	_arm = SpringArm3D.new()
	_arm.name = "CameraArm"
	_arm.spring_length = 5.5
	_arm.margin = 0.18
	_arm.collision_mask = 3
	var camera_shape := SphereShape3D.new()
	camera_shape.radius = 0.2
	_arm.shape = camera_shape
	_arm.add_excluded_object(get_rid())
	_pivot.add_child(_arm)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 66.0
	camera.near = 0.08
	camera.far = 190.0
	camera.current = true
	_arm.add_child(camera)


func _unhandled_input(event: InputEvent) -> void:
	if enable_input and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless") and event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_pivot.rotation.y -= motion.relative.x * sensitivity
		_pitch = clampf(_pitch - motion.relative.y * sensitivity, -0.95, 0.32)
		_pivot.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	var movement := Vector2.ZERO
	if enable_input:
		movement = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := _pivot.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	var right := _pivot.global_basis.x
	right.y = 0
	right = right.normalized()
	var direction := right * movement.x + forward * movement.y
	var sprinting := enable_input and speed_scale >= 0.99 and Input.is_action_pressed("sprint")
	var speed := (SPRINT_SPEED if sprinting else WALK_SPEED) * speed_scale
	velocity.x = move_toward(velocity.x, direction.x * speed, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, ACCELERATION * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	if global_position.y < -8:
		global_position = Vector3(0, 0.1, 6)
		velocity = Vector3.ZERO
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if direction.length_squared() > 0.01:
		_graphics.rotation.y = lerp_angle(_graphics.rotation.y, atan2(-direction.x, -direction.z), 12.0 * delta)
	_graphics.set_motion(horizontal_speed, sprinting, speed_scale < 0.99)


func _avatar() -> void:
	_graphics = Actor.new()
	_graphics.name = "Uniform"
	_graphics.uniform = true
	add_child(_graphics)

func set_simulation_active(active: bool) -> void:
	set_physics_process(active)
	if is_instance_valid(_graphics): _graphics.set_simulation_active(active)
