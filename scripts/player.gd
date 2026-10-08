class_name Officer
extends CharacterBody3D
## Camera-relative third-person movement; visuals never rotate the collision body.

var enable_input := true
var sensitivity := 0.003
var camera: Camera3D
var _pivot: Node3D
var _arm: SpringArm3D
var _graphics: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _stride := 0.0
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
	var sprinting := enable_input and Input.is_action_pressed("sprint")
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
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
	_stride += horizontal_speed * delta * 2.0
	var swing := sin(_stride) * minf(horizontal_speed / 7.0, 1.0) * 0.65
	_left_leg.rotation.x = swing
	_right_leg.rotation.x = -swing
	_left_arm.rotation.x = -swing * 0.65
	_right_arm.rotation.x = swing * 0.65
	_graphics.position.y = absf(sin(_stride)) * minf(horizontal_speed, 7.0) * 0.005


func _avatar() -> void:
	_graphics = Node3D.new()
	_graphics.name = "Uniform"
	add_child(_graphics)
	var navy := Color("203851")
	var trousers := Color("314b61")
	var skin := Color("d3a17c")
	var yellow := Color("e4d265")
	_part(_graphics, Vector3(0, 1.12, 0), Vector3(0.54, 0.62, 0.32), navy)
	_part(_graphics, Vector3(0, 1.23, -0.17), Vector3(0.5, 0.27, 0.04), Color("586774"))
	_part(_graphics, Vector3(0, 1.27, -0.197), Vector3(0.42, 0.035, 0.02), yellow)
	_part(_graphics, Vector3(0, 0.89, 0), Vector3(0.57, 0.1, 0.36), Color("202b36"))
	_part(_graphics, Vector3(0.21, 1.02, -0.21), Vector3(0.09, 0.14, 0.06), Color("253643"))
	_part(_graphics, Vector3(-0.16, 1.35, -0.195), Vector3(0.055, 0.07, 0.02), yellow)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.23
	head_mesh.height = 0.47
	head_mesh.radial_segments = 12
	head_mesh.rings = 8
	head.mesh = head_mesh
	head.position = Vector3(0, 1.64, 0)
	head.material_override = _material(skin)
	_graphics.add_child(head)
	_part(_graphics, Vector3(0, 1.83, 0), Vector3(0.45, 0.13, 0.41), navy)
	_part(_graphics, Vector3(0, 1.79, -0.24), Vector3(0.44, 0.045, 0.18), navy)
	_part(_graphics, Vector3(0, 1.84, -0.213), Vector3(0.045, 0.055, 0.015), yellow)
	for x in [-0.079, 0.079]:
		_part(_graphics, Vector3(x, 1.68, -0.212), Vector3(0.035, 0.023, 0.024), Color("293b43"))
	_left_leg = _limb(Vector3(-0.14, 0.86, 0), Vector3(0.2, 0.69, 0.25), trousers)
	_right_leg = _limb(Vector3(0.14, 0.86, 0), Vector3(0.2, 0.69, 0.25), trousers)
	for leg in [_left_leg, _right_leg]:
		_part(leg, Vector3(0, -0.72, -0.065), Vector3(0.23, 0.19, 0.38), Color("23303a"))
	_left_arm = _limb(Vector3(-0.36, 1.4, 0), Vector3(0.16, 0.51, 0.21), navy)
	_right_arm = _limb(Vector3(0.36, 1.4, 0), Vector3(0.16, 0.51, 0.21), navy)
	for arm in [_left_arm, _right_arm]:
		_part(arm, Vector3(0, -0.54, 0), Vector3(0.14, 0.16, 0.17), skin)
		_part(arm, Vector3(0, -0.16, -0.115), Vector3(0.15, 0.045, 0.02), yellow)


func _limb(at: Vector3, size: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	_graphics.add_child(pivot)
	_part(pivot, Vector3(0, -size.y / 2.0, 0), size, color)
	return pivot


func _part(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = _material(color)
	instance.position = at
	parent.add_child(instance)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	return material
