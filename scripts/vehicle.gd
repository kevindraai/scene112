class_name ServiceVehicle
extends CharacterBody3D
## Deliberately controllable arcade driving, with actual world collisions.

var enabled_input := false
var camera: Camera3D
var speed := 0.0
var vehicle_id := ""
var fire := false
var sensitivity := 0.003
var body_width := 1.75
var body_length := 4.25
var _collision: CollisionShape3D
var _pivot: Node3D
var _camera_pitch := -0.24
var _home := Vector3.ZERO
var _home_yaw := PI


func setup(id: String, is_fire: bool) -> void:
	vehicle_id = id
	fire = is_fire
	body_width = 2.15 if fire else 1.75
	body_length = 5.2 if fire else 4.25


func _ready() -> void:
	_home = global_position
	_home_yaw = rotation.y
	floor_snap_length = 0.35
	safe_margin = 0.015
	var shape := BoxShape3D.new()
	var height := 2.2 if fire else 1.7
	shape.size = Vector3(body_width + 0.3, height, body_length)
	_collision = CollisionShape3D.new()
	_collision.name = "VehicleCollision"
	_collision.shape = shape
	_collision.position.y = height / 2.0
	add_child(_collision)
	_pivot = Node3D.new()
	_pivot.name = "ChasePivot"
	_pivot.position = Vector3(0, 2.3 if fire else 1.8, 0)
	_pivot.rotation.x = _camera_pitch
	add_child(_pivot)
	var arm := SpringArm3D.new()
	arm.name = "ChaseArm"
	arm.spring_length = 9.0 if fire else 7.5
	arm.margin = 0.22
	var camera_shape := SphereShape3D.new()
	camera_shape.radius = 0.24
	arm.shape = camera_shape
	arm.add_excluded_object(get_rid())
	_pivot.add_child(arm)
	camera = Camera3D.new()
	camera.fov = 68
	camera.near = 0.08
	camera.far = 190
	camera.current = false
	arm.add_child(camera)


func _unhandled_input(event: InputEvent) -> void:
	if enabled_input and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless") and event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_pivot.rotation.y -= motion.relative.x * sensitivity
		_camera_pitch = clampf(_camera_pitch - motion.relative.y * sensitivity, -0.8, 0.15)
		_pivot.rotation.x = _camera_pitch


func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steering := 0.0
	var braking := false
	if enabled_input:
		throttle = Input.get_axis("move_back", "move_forward")
		steering = Input.get_axis("move_left", "move_right")
		braking = InputMap.has_action("brake") and Input.is_action_pressed("brake")
	var acceleration := 4.5 if fire else 6.0
	var maximum := 11.5 if fire else 14.0
	if braking or (throttle * speed < -0.1):
		speed = move_toward(speed, 0.0, 13.0 * delta)
	elif throttle > 0:
		speed = move_toward(speed, maximum, acceleration * delta)
	elif throttle < 0:
		speed = move_toward(speed, -4.2, acceleration * 0.65 * delta)
	else:
		speed = move_toward(speed, 0.0, 3.2 * delta)
	if absf(speed) > 0.12 and absf(steering) > 0.01:
		var turning_rate := 1.25 * clampf(absf(speed) / 4.0, 0.0, 1.0)
		turning_rate *= lerpf(1.0, 0.55, clampf(absf(speed) / maximum, 0.0, 1.0))
		var yaw := -steering * signf(speed) * turning_rate * delta
		if _turn_is_clear(yaw):
			rotation.y += yaw
	var forward := -global_basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	velocity.y = -0.5 if is_on_floor() else velocity.y - 22.0 * delta
	move_and_slide()
	# A wall removes momentum; holding W cannot build up hidden speed.
	speed = Vector2(velocity.x, velocity.z).dot(Vector2(forward.x, forward.z))
	if global_position.y < -8:
		global_position = _home
		rotation.y = _home_yaw
		velocity = Vector3.ZERO
		speed = 0


func _turn_is_clear(yaw: float) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _collision.shape
	var transform_at := global_transform.rotated_local(Vector3.UP, yaw)
	query.transform = transform_at * _collision.transform
	# The compact district is flat. Lift the test just above the supporting floor.
	query.transform.origin.y += 0.05
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func get_exit_position() -> Variant:
	if not is_inside_tree() or absf(speed) > 0.8:
		return null
	var side := body_width / 2.0 + 0.82
	var front_door := -1.35 if fire else -0.35
	var candidates := [Vector3(-side, 0, front_door), Vector3(side, 0, front_door),
		Vector3(-side, 0, 0.7), Vector3(side, 0, 0.7),
		Vector3(0, 0, body_length / 2.0 + 0.9)]
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	var space := get_world_3d().direct_space_state
	for local: Vector3 in candidates:
		var candidate := to_global(local)
		var ray := PhysicsRayQueryParameters3D.create(candidate + Vector3(0, 2.0, 0), candidate - Vector3(0, 1.5, 0), collision_mask, [get_rid()])
		var ground := space.intersect_ray(ray)
		if ground.is_empty():
			continue
		var ground_position: Vector3 = ground.position
		var normal: Vector3 = ground.normal
		if normal.y < 0.85 or absf(ground_position.y - global_position.y) > 0.45:
			continue
		candidate.y = ground_position.y + 0.04
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, candidate + Vector3(0, 0.91, 0))
		query.collision_mask = collision_mask
		# Include the vehicle itself: a candidate must also clear its complete body.
		if space.intersect_shape(query, 1).is_empty():
			return candidate
	return null


func stop() -> void:
	speed = 0.0
	velocity = Vector3.ZERO
