extends SceneTree
## Repeatable runtime route. Only initial officer and optional car setup are placed.
var app: Node
var evidence_dir: String
var tag: String
var overlay: Label
var samples: Array[Dictionary] = []
var checkpoints: Array[Dictionary] = []
var current_phase := "ready"
var previous_phase := ""
var started := 0
var previous_frame := 0
var load_seconds := 0.0
var car_start := Vector3.ZERO
var entered := false
var exited := false
var braking_started := false
var walk_start := Vector3.ZERO
var failed := false
var camera_anchor := {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	evidence_dir = OS.get_environment("SCENE112_EVIDENCE_DIR")
	tag = OS.get_environment("SCENE112_EVIDENCE_TAG")
	if evidence_dir.is_empty() or DisplayServer.get_name() == "headless":
		_fail("Actual graphical display and evidence directory required")
		return
	var load_started := Time.get_ticks_usec()
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.start_new("police")
	var condition := OS.get_environment("SCENE112_EVIDENCE_CONDITION")
	if condition.is_empty(): condition = "day"
	if condition not in ["day", "dusk", "rain"]:
		_fail("Unknown requested capture condition")
		return
	if app.state.get("condition") is String:
		app.state.condition = condition
		app._apply_visual_settings()
	elif condition != "day":
		_fail("Legacy baseline only supports its original fixed daylight")
		return
	# Disclosed fixtures: ready equipment/radio, initial on-foot camera anchor.
	app.state.equipment = true
	app.state.radio_checked = true
	app.officer.global_position = Vector3(-2, 0.1, 38)
	app.officer.velocity = Vector3.ZERO
	app.officer._pitch = -0.1
	app.officer._pivot.rotation = Vector3(-0.1, PI, 0)
	app._update_objective()
	_make_overlay()
	await physics_frame
	await RenderingServer.frame_post_draw
	load_seconds = (Time.get_ticks_usec() - load_started) / 1000000.0
	walk_start = app.officer.global_position
	camera_anchor = {"officer": _xyz(walk_start), "pivot_yaw": PI, "pivot_pitch": -0.1,
		"camera_position": _xyz(app.officer.camera.global_position), "camera_fov": app.officer.camera.fov}
	overlay.text = "%s | LIVE runtime 1280 x 720\nReady: fixed south street camera" % tag
	for i in range(8): await RenderingServer.frame_post_draw
	await _capture("anchor.png")
	_write_json("ready.json", {"load_seconds": load_seconds, "anchor": camera_anchor})
	var handshake_deadline := Time.get_ticks_msec() + 15000
	while not FileAccess.file_exists(evidence_dir.path_join("recording")):
		await process_frame
		if Time.get_ticks_msec() > handshake_deadline:
			_fail("Recorder handshake timeout")
			return
	started = Time.get_ticks_usec()
	previous_frame = started
	while (Time.get_ticks_usec() - started) / 1000000.0 < 22.0 or not exited:
		await process_frame
		var now := Time.get_ticks_usec()
		var seconds := (now - started) / 1000000.0
		if seconds > 45.0:
			_fail("Actual movement/brake/exit did not finish inside45sec bound")
			return
		var interval_ms := (now - previous_frame) / 1000.0
		previous_frame = now
		var monitor := _monitors()
		monitor["wall_seconds"] = seconds
		monitor["frame_interval_ms"] = interval_ms
		monitor["phase"] = current_phase
		samples.append(monitor)
		if seconds < 2.0: current_phase = "walk forward W"
		elif seconds < 7.0: current_phase = "walk left A"
		elif seconds < 12.0: current_phase = "walk right D"
		elif seconds < 14.0: current_phase = "street pause"
		elif not entered: current_phase = "vehicle W"
		elif not braking_started:
			var forward_metres: float = (app.district.objects.police_car.global_position - car_start).dot(Vector3(0, 0, 1))
			current_phase = "vehicle brake" if forward_metres >= 1.5 else "vehicle W"
		elif not exited:
			current_phase = "exit and street pause" if absf(app.district.objects.police_car.speed) <= 0.05 else "vehicle brake"
		else: current_phase = "exit and street pause"
		if current_phase != previous_phase:
			_release()
			_checkpoint(seconds, current_phase)
			if current_phase == "walk forward W": Input.action_press("move_forward")
			elif current_phase == "walk left A": Input.action_press("move_left")
			elif current_phase == "walk right D": Input.action_press("move_right")
			elif current_phase == "vehicle W":
				# The second disclosed fixture places a stationary car and officer nearby.
				var vehicle: Node3D = app.district.objects.police_car
				vehicle.stop()
				vehicle.global_position = Vector3(2, 0.05, 36)
				vehicle.rotation.y = PI
				vehicle._pivot.rotation = Vector3(-0.24, 0, 0)
				vehicle._camera_pitch = -0.24
				app.officer.global_position = Vector3(3.8, 0.1, 36)
				app.officer.velocity = Vector3.ZERO
				car_start = vehicle.global_position
				app._enter_vehicle("police_car")
				entered = app.state.occupied_vehicle == "police_car"
				if not entered:
					_fail("Production vehicle entry rejected fixture")
					return
				Input.action_press("move_forward")
			elif current_phase == "vehicle brake":
				braking_started = true
				Input.action_press("brake")
			elif current_phase == "exit and street pause":
				app._exit_vehicle()
				exited = app.state.occupied_vehicle.is_empty()
				if not exited:
					_fail("Production safe vehicle exit failed")
					return
			previous_phase = current_phase
			if current_phase == "street pause" or current_phase == "exit and street pause":
				_capture("street-%02d.png" % int(seconds))
		if samples.size() % 10 == 0:
			overlay.text = "%s | LIVE %.1fs | %s\nFrame interval %.1f ms | p95 %.1f ms\nProcess %.2f ms | physics %.2f ms\nDraw calls %d | primitives %d | video %.1f MiB" % [tag, seconds, current_phase, interval_ms, _percentile(0.95), monitor.process_ms, monitor.physics_ms, int(monitor.draw_calls), int(monitor.primitives), monitor.video_bytes / 1048576.0]
	_release()
	_checkpoint((Time.get_ticks_usec() - started) / 1000000.0, "complete")
	var wall_seconds := (Time.get_ticks_usec() - started) / 1000000.0
	var actual_car_distance: float = app.district.objects.police_car.global_position.distance_to(car_start)
	if not entered or not exited or actual_car_distance < 0.5:
		_fail("Expected actual vehicle movement and safe exit")
		return
	_write_json("metrics.json", {"condition_requested": condition, "condition_active": app.state.get("condition"), "quality_active": app.state.get("graphics_quality"), "pre_record_draw_settling": 8, "tag": tag, "engine": Engine.get_version_info(), "display": DisplayServer.get_name(),
		"renderer_config": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"renderer_live": _rendering_metadata(), "audio_driver": AudioServer.get_driver_name(), "viewport": _xy(root.get_visible_rect().size),
		"load_to_first_street_draw_seconds": load_seconds, "wall_seconds": wall_seconds, "frame_count": samples.size(),
		"frame_interval_p50_ms": _percentile(0.50), "frame_interval_p95_ms": _percentile(0.95), "frame_interval_p99_ms": _percentile(0.99),
		"car_distance_metres": actual_car_distance, "driving_control": "W until1.5m observed forward motion; brake untilspeed<=.05; actual safe exit;22sec minimum/45sec bound", "initial_camera_anchor": camera_anchor, "checkpoints": checkpoints,
		"last_monitors": _monitors(), "samples": samples,
		"measurement_limits": "Software Linux X11 runner with live screen recorder; process-frame wall intervals include scheduling/capture/readback. Encoded 30fps is not measured game FPS. Godot monitors may update with up to 1sec delay; source debug build, not release/target hardware."})
	await _capture("final.png")
	print("SCENE112_QUALITY_ROUTE_OK wall_seconds=", wall_seconds, " frames=", samples.size(), " p95_ms=", _percentile(0.95), " car_metres=", actual_car_distance)
	_write_json("done.json", {"wall_seconds": wall_seconds})
	await app.quit_game()

func _make_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 99
	root.add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(800, 18)
	panel.size = Vector2(462, 125)
	layer.add_child(panel)
	overlay = Label.new()
	overlay.add_theme_font_size_override("font_size", 16)
	overlay.add_theme_color_override("font_color", Color.WHITE)
	overlay.add_theme_constant_override("outline_size", 4)
	overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	panel.add_child(overlay)

func _monitors() -> Dictionary:
	return {"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"reported_fps": Performance.get_monitor(Performance.TIME_FPS),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects_drawn": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"video_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"physics_collision_pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)}

func _rendering_metadata() -> Dictionary:
	var info := {}
	for method: String in ["get_current_rendering_method", "get_current_rendering_driver_name", "get_video_adapter_name", "get_video_adapter_vendor", "get_video_adapter_api_version"]:
		if RenderingServer.has_method(method): info[method] = RenderingServer.call(method)
	return info

func _percentile(quantile: float) -> float:
	if samples.is_empty(): return 0
	var times: Array[float] = []
	for sample in samples: times.append(sample.frame_interval_ms)
	times.sort()
	return times[clampi(int(ceil(quantile * times.size())) - 1, 0, times.size() - 1)]

func _checkpoint(seconds: float, phase: String) -> void:
	var entry := {"wall_seconds": seconds, "phase": phase, "officer": _xyz(app.officer.global_position),
		"car": _xyz(app.district.objects.police_car.global_position), "seated": app.state.occupied_vehicle}
	checkpoints.append(entry)
	print("QUALITY_CHECKPOINT ", JSON.stringify(entry))

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(evidence_dir.path_join(filename))
	if error != OK: push_error("QUALITY_IMAGE_SAVE " + str(error))

func _write_json(filename: String, value: Dictionary) -> void:
	var file := FileAccess.open(evidence_dir.path_join(filename), FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))
	file.close()

func _release() -> void:
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "sprint", "brake"]:
		if InputMap.has_action(action): Input.action_release(action)

func _xyz(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _xy(value: Vector2) -> Array:
	return [value.x, value.y]

func _fail(message: String) -> void:
	_release()
	push_error("QUALITY_ROUTE_FAIL " + message)
	failed = true
	if is_instance_valid(app): await app.quit_game(1)
	else: quit(1)
