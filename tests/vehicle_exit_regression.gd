extends SceneTree
## Actual menu/E/W/brake/E handlers on both vehicles. Clear-lane initial and
## later foot placement are declared travel fixtures, no mission completion set.
const Scene = preload("res://scenes/main.tscn")
var app: Node3D
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func verify(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("EXIT_REGRESSION " + label)

func run() -> void:
	app = Scene.instantiate(); root.add_child(app)
	await process_frame
	app.test_mode = true; app._test_timeout(110)
	for fire in [true, false]:
		if not await exercise(fire): return
	print("SCENE112_VEHICLE_EXIT_OK checks=", checks, " failures=", failures,
		" actual menus/PPE/radio/two drives/brakes/E exits; physical pose, stationary vehicle, capsule and camera verified")
	app._test_finished = true
	await app.quit_game(0 if failures == 0 else 1)

func exercise(fire: bool) -> bool:
	app._show_main()
	if not app._press_menu("Vrije brandweerdienst" if fire else "Vrije politiedienst"): return false
	if not await app._test_station("fire_equipment" if fire else "equipment"): return false
	if not await app._test_station("fire_radio" if fire else "radio"): return false
	var id := "fire_truck" if fire else "police_car"
	var vehicle: CharacterBody3D = app.district.objects[id]
	vehicle.position = Vector3(-11, 0.05, 19)
	vehicle.rotation.y = -PI / 2
	vehicle.stop()
	app.officer.position = vehicle.position + Vector3(0, 0.1, -2.2)
	app.officer.velocity = Vector3.ZERO
	if not await app._wait_for(func(): return app.current_target.get("id") == id, "Actual exit-test vehicle proximity"): return false
	if not await app._tap_action("interact", func(): return app.state.occupied_vehicle == id, "Actual exit-test E entry"): return false
	var drive_start := vehicle.global_position
	Input.action_press("move_forward")
	var driven: bool = await app._wait_for(func(): return vehicle.global_position.distance_to(drive_start) > 22, "Actual exit-test controlled drive >22m", 25)
	Input.action_release("move_forward")
	if not driven: return false
	Input.action_press("brake")
	var stopped: bool = await app._wait_for(func(): return absf(vehicle.speed) < 0.05, "Actual exit-test braking", 12)
	Input.action_release("brake")
	if not stopped: return false
	var parked := vehicle.global_position
	verify(absf(parked.y) < 0.1, id + " physically parked on road before exit")
	if not await app._tap_action("interact", func(): return app.state.occupied_vehicle.is_empty(), "Actual exit-test E exit"): return false
	var physical_pose: Transform3D = PhysicsServer3D.body_get_state(app.officer.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	verify(physical_pose.origin.distance_to(app.officer.global_position) < 0.1 and physical_pose.origin.distance_to(parked) > 1.8, id + " physical capsule is at clear exit rather than old seat")
	await frames(35)
	verify(absf(vehicle.global_position.y) < 0.1 and vehicle.global_position.distance_to(parked) < 0.12, id + " truck/car stays grounded and stationary after exit")
	verify(app.officer.collision_layer == 1 and app.officer.collision_mask == 1 and app.officer.is_physics_processing() and app.officer.visible and app.officer.camera.current, id + " normal solid foot controls and camera restored")
	verify(vehicle.collision_mask == 1 and vehicle.collision_layer == 1, id + " solid vehicle mask retained")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = vehicle._collision.shape
	query.transform = vehicle.global_transform * vehicle._collision.transform
	query.transform.origin.y += 0.05
	query.exclude = [vehicle.get_rid()]
	var overlaps := vehicle.get_world_3d().direct_space_state.intersect_shape(query)
	verify(not overlaps.any(func(hit): return hit.collider == app.officer), id + " restored capsule does not overlap vehicle")
	# This explicit travel fixture exposes an inherited platform velocity from
	# the old seat. The car must stay parked while the foot actor moves away.
	app.officer.position = Vector3(17, 0.1, 24.6)
	app.officer.velocity = Vector3.ZERO
	app.officer._pivot.rotation = Vector3(-0.15, PI, 0)
	app.officer._pitch = -0.15
	await frames(35)
	verify(vehicle.global_position.distance_to(parked) < 0.12, id + " parked vehicle never follows relocated foot actor")
	verify(app.officer._arm.get_hit_length() > 3.0, id + " approach retains useful spring-arm length")
	var foot_start: Vector3 = app.officer.global_position
	Input.action_press("move_forward")
	var walked: bool = await app._wait_for(func(): return app.officer.global_position.distance_to(foot_start) > 0.8, "Actual exit-test on-foot movement", 5)
	Input.action_release("move_forward")
	if not walked: return false
	await frames(4)
	verify(vehicle.global_position.distance_to(parked) < 0.12, id + " actual foot walking does not carry parked vehicle")
	print("VEHICLE_EXIT_POSES=", JSON.stringify({"vehicle":id,"parked":str(parked),"after":str(vehicle.global_position),"officer":str(app.officer.global_position),"arm":app.officer._arm.get_hit_length()}))
	return true

func frames(count: int) -> void:
	for i in count: await physics_frame
