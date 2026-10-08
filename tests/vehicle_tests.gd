extends SceneTree
## Actual district physics; independent of menus, campaign and player save files.

const World = preload("res://scripts/world.gd")
const ACTIONS := ["move_left", "move_right", "move_forward", "move_back", "brake"]

var failures := 0
var _world: Node3D
var _obstacles: Array[StaticBody3D] = []
var _created_actions: Array[String] = []
var _finishing := false

func check(condition: bool, label: String) -> bool:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
	return condition

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():
		if not _finishing:
			check(false, "vehicle physics suite completed within its timeout")
			_finish())
	_run.call_deferred()

func _run() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			_created_actions.append(action)
	_world = World.new()
	root.add_child(_world)
	for frame in range(10):
		await physics_frame
	if not check(_world.objects.has("police_car") and _world.objects.has("fire_truck") and _world.objects.has("npc_0"), "district exposes both service vehicles and a civilian"):
		_finish()
		return
	var car: CharacterBody3D = _world.objects.police_car
	var truck: CharacterBody3D = _world.objects.fire_truck
	var civilian: CharacterBody3D = _world.objects.npc_0
	check(car.get_exit_position() is Vector3 and truck.get_exit_position() is Vector3, "both parked vehicles have a grounded clear exit")
	var civilian_start := civilian.global_position
	var start := car.global_position
	car.enabled_input = true
	Input.action_press("move_forward")
	for frame in range(100):
		await physics_frame
	Input.action_release("move_forward")
	check(car.global_position.distance_to(start) > 3.0, "police car moves through actual district physics")
	check(car.get_exit_position() == null, "player cannot exit a moving vehicle")
	car.stop()
	var exit_point: Variant = car.get_exit_position()
	check(exit_point is Vector3, "stopped car offers an exit beside its body")
	if exit_point is Vector3:
		check(exit_point.distance_to(car.global_position) > car.body_width / 2.0, "exit clears the parked vehicle body")
	check(civilian.global_position.distance_to(civilian_start) > 0.8, "civilian patrol runs while the player drives")
	var reverse_start := car.global_position
	Input.action_press("move_back")
	for frame in range(45):
		await physics_frame
	Input.action_release("move_back")
	check(car.speed < -1.0 and (car.global_position - reverse_start).dot(-car.global_basis.z) < -0.5, "reverse input moves the body backwards")
	Input.action_press("brake")
	for frame in range(30):
		await physics_frame
	Input.action_release("brake")
	check(absf(car.speed) < 0.1, "brake removes reverse momentum")
	var yaw_start := car.rotation.y
	Input.action_press("move_forward")
	Input.action_press("move_right")
	for frame in range(50):
		await physics_frame
	Input.action_release("move_forward")
	Input.action_release("move_right")
	check(absf(car.rotation.y - yaw_start) > 0.1, "steering changes vehicle heading while driving")
	car.stop()
	var heading := -car.global_basis.z
	var wall_at := car.global_position + heading * 4.0
	var wall := _obstacle(wall_at + Vector3(0, 1.5, 0), Vector3(8, 3, 0.4))
	wall.rotation.y = car.rotation.y
	for frame in range(3):
		await physics_frame
	var wall_start := car.global_position
	Input.action_press("move_forward")
	for frame in range(100):
		await physics_frame
	Input.action_release("move_forward")
	check((car.global_position - wall_start).dot(heading) < 2.0, "vehicle body stops before passing through a wall")
	check(absf(car.speed) < 0.2, "holding throttle against a wall cannot accumulate hidden speed")
	car.stop()
	# Occupy every potential door/rear exit with an actual collision shape.
	var side: float = car.body_width / 2.0 + 0.82
	for local in [Vector3(-side, 0, -0.35), Vector3(side, 0, -0.35), Vector3(-side, 0, 0.7), Vector3(side, 0, 0.7), Vector3(0, 0, car.body_length / 2.0 + 0.9)]:
		_obstacle(car.to_global(local) + Vector3(0, 1, 0), Vector3(0.8, 2, 0.8))
	for frame in range(3):
		await physics_frame
	check(car.get_exit_position() == null, "blocked doors cannot place the player inside obstacles")
	car.enabled_input = false
	var truck_start := truck.global_position
	truck.enabled_input = true
	Input.action_press("move_forward")
	for frame in range(90):
		await physics_frame
	Input.action_release("move_forward")
	check(truck.global_position.distance_to(truck_start) > 3.0, "fire appliance also drives as an actual collision body")
	truck.stop()
	check(truck.get_exit_position() is Vector3, "fire appliance retains a clear grounded exit after driving")
	# Conversation pause lets the player talk, then returns the NPC to its route.
	civilian.pause_for(0.8)
	for frame in range(18):
		await physics_frame
	var conversation_position := civilian.global_position
	for frame in range(10):
		await physics_frame
	check(civilian.global_position.distance_to(conversation_position) < 0.002, "civilian settles and waits during a conversation")
	for frame in range(60):
		await physics_frame
	check(civilian.global_position.distance_to(conversation_position) > 0.2, "civilian resumes its route after the conversation")
	_world.set_simulation_active(false)
	var paused_civilian := civilian.global_position
	var paused_truck := truck.global_position
	var paused_car := car.global_position
	Input.action_press("move_forward")
	for frame in range(15):
		await physics_frame
	Input.action_release("move_forward")
	check(civilian.global_position == paused_civilian and truck.global_position == paused_truck and car.global_position == paused_car, "paused district freezes vehicles and civilians despite held driving input")
	_world.set_simulation_active(true)
	Input.action_press("move_forward")
	for frame in range(45):
		await physics_frame
	Input.action_release("move_forward")
	check(truck.global_position.distance_to(paused_truck) > 0.5, "resume restores service vehicle physics")
	truck.stop()
	_finish()

func _obstacle(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	_obstacles.append(body)
	return body

func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	if is_instance_valid(_world):
		_world.set_simulation_active(false)
	for action: String in ACTIONS:
		Input.action_release(action)
	if is_instance_valid(_world):
		_world.queue_free()
	for obstacle in _obstacles:
		if is_instance_valid(obstacle):
			obstacle.queue_free()
	await process_frame
	await process_frame
	for action in _created_actions:
		InputMap.erase_action(action)
	print("SCENE112_VEHICLE_TESTS_", "OK" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
