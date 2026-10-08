extends SceneTree
## Five real minutes of agent-controlled navigation; initial gear setup is placed.
var app: Node
var route: Array[Vector3] = []
var last_offer := 0
var patrol_index := 0
var last_log := 0.0
var failures := 0
var log_file: FileAccess
var finished := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.start_new("police")
	log_file = FileAccess.open("user://m1-realtime.log", FileAccess.WRITE)
	if not await app._test_station("equipment"): return
	if not await app._test_station("radio"): return
	if not await app._test_vehicle("police_car"): return
	await app._tap_action("interact", func(): return app.state.occupied_vehicle.is_empty(), "realtime initial exit")
	if not app.state.occupied_vehicle.is_empty():
		_fail("Safe initial exit failed")
		return
	# Clear the parked body's footprint before entering the north traffic lane.
	route = [Vector3(6, 0, app.officer.position.z), Vector3(6, 0, 16)]
	var started := Time.get_ticks_msec()
	var stuck_time := 0.0
	var previous: Vector3 = app.officer.position
	var seconds := 0.0
	while seconds < 300.0:
		seconds = (Time.get_ticks_msec() - started) / 1000.0
		var incident: Dictionary = app.ledger.incident
		if not incident.is_empty() and incident.phase == "offered" and int(incident.id) != last_offer:
			last_offer = int(incident.id)
			_release()
			app.show_radio()
			if not app._press_menu("Melding aannemen"):
				_fail("Radio acceptance button missing")
				return
			route = _route_to(app.officer.position, app._incident_position())
			_record("accepted incident=%d kind=%s" % [last_offer, incident.kind])
		if app._accepted_incident() and app._at_incident():
			_release()
			app._show_response()
			var choice := "Rustig luisteren en afspraken maken" if app.ledger.incident.kind == "noise" else "Locatie beveiligen en betrokkenen spreken"
			if not app._press_menu(choice):
				_fail("Response button missing")
				return
			_record("resolved incident=%d quality=%d" % [last_offer, app.ledger.incident.quality])
			route = _route_to(app.officer.position, Vector3(-20, 0, 17))
		if route.is_empty():
			patrol_index += 1
			route = _route_to(app.officer.position, Vector3(14, 0, 30) if patrol_index % 2 else Vector3(-20, 0, 17))
		var offset: Vector3 = route[0] - app.officer.position
		offset.y = 0
		if offset.length() < 1.6:
			route.pop_front()
			_release()
		else:
			_walk(offset.normalized())
		var at: Vector3 = app.officer.position
		var moved := Vector2(at.x - previous.x, at.z - previous.z).length()
		stuck_time = stuck_time + 0.1 if moved < 0.04 and not route.is_empty() else 0.0
		previous = at
		if stuck_time > 5.0:
			await _capture("m1-realtime-stuck.png")
			_fail("Navigation blocked at %s toward %s" % [at, route[0]])
			return
		if seconds >= last_log + 30.0:
			last_log = seconds
			_record("wall_seconds=%.1f duty_seconds=%.1f completed=%d missed=%d position=%s" % [seconds, app.ledger.duty_time, app.ledger.completed, app.ledger.missed, at])
			if DisplayServer.get_name() != "headless": await _capture("m1-realtime-%03d.png" % int(seconds))
		await create_timer(0.1).timeout
	_release()
	if app.ledger.completed < 4 or app.ledger.missed != 0:
		_fail("Expected at least four actual navigated incident responses")
		return
	app.save_game("user://m1-realtime-save.json")
	app.load_game("user://m1-realtime-save.json")
	if app.ledger.completed < 4:
		_fail("Real duty save/load failed")
		return
	_record("SCENE112_REALTIME_OK wall_seconds=%.1f completed=%d; initial gear/car setup placed, subsequent walking/navigation/radio/responses in realtime" % [seconds, app.ledger.completed])
	log_file.close()
	finished = true
	app.queue_free()
	await process_frame
	quit(0)

func _route_to(start: Vector3, target: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if start.z < -12:
		points.append(Vector3(-20, 0, -28))
		if target.z >= -12: points.append(Vector3(-20, 0, 16))
	else:
		points.append(Vector3(start.x, 0, 16))
		if target.z < -12:
			points.append(Vector3(-20, 0, 16))
			points.append(Vector3(-20, 0, -28))
	if target.z < -12:
		points.append(target)
	else:
		points.append(Vector3(target.x, 0, 16))
		points.append(target)
	return points

func _walk(direction: Vector3) -> void:
	_release()
	var pivot: Node3D = app.officer.get_node("CameraPivot")
	var right := pivot.global_basis.x
	var forward := -pivot.global_basis.z
	right.y = 0
	forward.y = 0
	var horizontal := direction.dot(right.normalized())
	var vertical := direction.dot(forward.normalized())
	if absf(horizontal) > 0.04: Input.action_press("move_right" if horizontal > 0 else "move_left", absf(horizontal))
	if absf(vertical) > 0.04: Input.action_press("move_forward" if vertical > 0 else "move_back", absf(vertical))
	Input.action_press("sprint")

func _release() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "brake"]:
		Input.action_release(action)

func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://" + filename)

func _record(message: String) -> void:
	print(message)
	if log_file:
		log_file.store_line(message)
		log_file.flush()

func _fail(message: String) -> void:
	_release()
	_record("REALTIME_FAIL " + message)
	push_error(message)
	quit(1)
