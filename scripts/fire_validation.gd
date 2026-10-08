extends RefCounted
## Actual app handlers, collision, aiming, held nozzle and carried rescue.
## Declared position fixtures shorten travel; no fire completion state is forged.
var app: Node3D
const SAVE := "user://validation-fire-m3.json"

func run(root: Node3D) -> void:
	app = root
	var graphics = preload("res://scripts/graphics_validation.gd").new()
	graphics.app = app
	print("SCENE112_GRAPHICS_BACKEND=", JSON.stringify(graphics._backend()))
	app._test_timeout(420)
	if not await _play_case("lesson"): return
	if not await _play_case("campaign"): return
	print("SCENE112_FIRE_OK actual lesson3 and campaignCase2; PPE/drive/hose/nozzle/local fire/carry/rescue/all cells/scoring/archive/save/pause")
	app._test_finished = true
	await app.quit_game(0)

func _play_case(mode: String) -> bool:
	await app._test_frames(3)
	app._show_main()
	if mode == "lesson":
		if not app._press_menu("Academie · lessen"): return false
		if not app._press_menu("Les 3 · Brandweer basisinzet"): return false
	else:
		# Entry callback fixture: M2's actual accepted PV is checked separately.
		# The complete campaign fire itself uses the same real gameplay handlers.
		app.fire_ui.start_campaign()
	if not app._check(app.fire_model.mode == mode and app.state.role == "fire", "Actual fire case/role transition " + mode): return false
	if not app._press_menu("Dienst beginnen"): return false
	if not app._check(app.officer._graphics.firefighter and app.officer._graphics.diagnostics().bones == 18, "Real fire PPE rig replaces police avatar"): return false
	if not await _interact("fire_equipment"): return false
	if not await _interact("fire_radio"): return false
	var truck: Node3D = app.district.objects.fire_truck
	# Clear existing approach fixture; actual W travels to Huis24 from here.
	truck.position = Vector3(-11, 0.05, 18)
	truck.rotation.y = PI
	truck.stop()
	_fixture(truck.position + Vector3(2.0, 0.1, 0))
	if not await app._wait_for(func(): return app.current_target.get("id") == "fire_truck", "Actual truck proximity", 10): return false
	if not await app._tap_action("interact", func(): return app.state.occupied_vehicle == "fire_truck", "Actual truck entry"): return false
	var start: Vector3 = truck.global_position
	Input.action_press("move_forward")
	var arrived: bool = await app._wait_for(func(): return truck.position.z > 36.5, "Actual controlled approach drive", 20)
	Input.action_release("move_forward")
	if not arrived: return false
	Input.action_press("brake")
	var stopped: bool = await app._wait_for(func(): return absf(truck.speed) < 0.05, "Actual truck braking", 10)
	Input.action_release("brake")
	if not stopped: return false
	if not app._check(truck.global_position.distance_to(start) > 18 and app.fire_model.basics.drive, "Observed drive reaches incident without direct quest mutation"): return false
	if not await app._tap_action("interact", func(): return app.state.occupied_vehicle.is_empty(), "Actual safe truck exit"): return false
	if not await _interact("fire_exterior"): return false
	if not await _interact("fire_door"): return false
	if not await _interact("fire_hydrant"): return false
	if not app._check(app.fire_model.hydrant_connected and app.fire_model.hose_points.size() == 1, "Actual hydrant starts spatial hose"): return false
	# Hose placement goes through the real Q camera/ground raycast.
	_fixture(Vector3(6, 0.1, 42))
	await _aim(Vector3(2, 0.02, 39))
	if not await _lay_hose(2): return false
	if not app._check(app.fire_model.hose_length() > 0.7, "Actual Q lays finite ground hose segment"): return false
	_fixture(Vector3(-2, 0.1, 41.5))
	await _aim(Vector3(-2, 0.02, 43))
	if not await _lay_hose(3): return false
	if not await app._tap_action("radio", func(): return app._menu_title_is("Ploeg · inzetplan"), "Actual crew plan menu"): return false
	if not app._press_menu("Binneninzet voorbereiden · toegang bewaken"): return false
	if not app._check(app.fire_model.phase == "active" and app.fire_model.tactic == "interior", "Chosen tactic starts actual evolving fire"): return false
	_fixture(Vector3(-2, 0.1, 43.5))
	await _aim(app.fire_site.HOUSE + Vector3(0, 1.15, -1.6))
	if not await app._wait_for(func(): return app.fire_site.raycast_target(app.officer.camera, app.officer) == "front", "Actual nozzle sees front cell through open door", 10): return false
	await _capture("fire-active")
	_mouse(true)
	var cooled: bool = await app._wait_for(func(): return float(app.fire_model.cells[0].heat) < 0.12, "Held actual nozzle locally cools front cell", 15)
	_mouse(false)
	if not cooled: return false
	if not app._check(float(app.fire_model.cells[1].heat) > 0.5 and app.fire_model.water_used > 10 and app.fire_model.cells[0].wet > 0.3, "Targeted water leaves other cell burning and persists wetness/consumption"): return false
	app._pause()
	var frozen: Dictionary = app.fire_model.to_dict()
	var clock: float = app.fire_site._effects.diagnostics().clock
	await app.get_tree().create_timer(0.25).timeout
	if not app._check(app.fire_model.to_dict() == frozen and app.fire_site._effects.diagnostics().clock == clock, "Pause freezes model and shader/particles"): return false
	app._resume()
	app.save_game(SAVE)
	var saved: Dictionary = app.fire_model.to_dict()
	app.fire_model.tick(2, true)
	app.load_game(SAVE)
	if not app._check(_same_snapshot(app.fire_model.to_dict(), saved) and app.fire_site._active, "Real root save/load restores live house and evolving incident"): return false
	_fixture(Vector3(-2, 0.1, 43.5))
	await _aim(app.fire_site.VICTIM + Vector3(0, 1, 0))
	Input.action_press("move_forward")
	var entered: bool = await app._wait_for(func(): return app.current_target.get("id") == "fire_victim", "Actual protected door passage and victim approach", 10)
	Input.action_release("move_forward")
	if not entered: return false
	if not await _interact("fire_victim", false): return false
	if not app._check(app.fire_model.victim.status == "carried" and app.officer.speed_scale == 0.6, "Actual rescue pickup changes carried pose and pace"): return false
	print("FIRE_STAGE=carried_exit at=", app.officer.global_position)
	await _capture("fire-rescue")
	var carried_start: Vector3 = app.officer.global_position
	if not await _walk_to(Vector3(-2, 0, 43), 0.4, 15): return false
	if not await _walk_to(app.fire_site.SAFE_AREA, 0.8, 20): return false
	if not app._check(app.officer.global_position.distance_to(carried_start) > 8 and app.fire_model.victim.status == "carried", "Actual slowed physical rescue route"): return false
	if not await _interact("fire_safe", false): return false
	if not app._check(app.fire_model.victim.status == "rescued" and app.officer.speed_scale == 1, "Actual handover releases carried pose and restores pace"): return false
	print("FIRE_STAGE=rescue_handover at=",app.officer.global_position)
	# Suppression continues from an explicit clear interior aiming fixture.
	_fixture(app.fire_site.HOUSE + Vector3(0, 0.1, -3.0))
	for id: String in ["front", "origin", "side"]:
		await _aim(app.fire_site._cells[id].target.global_position)
		if not await app._wait_for(func(): return app.fire_site.raycast_target(app.officer.camera, app.officer) == id, "Real aimed separate cell " + id, 10): return false
		_mouse(true)
		var cold: bool = await app._wait_for(func(): return app.fire_model.cells[{"front":0, "origin":1, "side":2}[id]].heat < 0.02, "Sustained actual suppression " + id, 15)
		_mouse(false)
		if not cold: return false
	if not app._check(app.fire_model.all_cold() and app.fire_model.water_used > 50 and app.fire_model.oxygen < 100, "All cells independently cooled with water/air accounting"): return false
	print("FIRE_STAGE=suppression_complete at=",app.officer.global_position)
	if not await _walk_to(Vector3(-2, 0, 43), 0.4, 15): return false
	if not await app._tap_action("radio", func(): return app._menu_title_is("Ploeg · inzetplan"), "Actual completed crew review"): return false
	if not app._press_menu("Nasmeulcontrole en overdracht"): return false
	if not app._check(app.fire_model.result == "careful" and "fire" in app.state.course_passes, "Actual careful handover retains fire academy pass"): return false
	if mode == "campaign":
		if not app._check(app.state.campaign_stage == 2 and app.state.fire_campaign.mode == "campaign" and app.state.fire_campaign.phase == "completed", "Actual Case2 completion archives the incident and advances campaign"): return false
	app.save_game(SAVE)
	var grade: Dictionary = app.fire_model.report_score.duplicate(true)
	if not app._press_menu("Inzet opnieuw proberen"): return false
	app.load_game(SAVE)
	if not app._check(app.fire_model.phase == "completed" and app.fire_model.result == "careful" and app.fire_model._scores_equal(app.fire_model.report_score, grade), "Actual completed lesson save survives replay/load"): return false
	await _capture("fire-completed")
	DirAccess.remove_absolute(SAVE)
	DirAccess.remove_absolute(SAVE + ".bak")
	return true

func _fixture(at: Vector3) -> void:
	app.officer.position = at
	app.officer.velocity = Vector3.ZERO
	app.officer._pivot.rotation = Vector3(-0.1, PI, 0)
	app.officer._pitch = -0.1

func _interact(id: String, place: bool = true) -> bool:
	if place: _fixture(app.district.objects[id].global_position + Vector3(0, 0.1, 1))
	if not await app._wait_for(func(): return app.current_target.get("id") == id, "Real proximity " + id, 10): return false
	var acknowledged := func():
		match id:
			"fire_equipment": return app.state.equipment
			"fire_radio": return app.state.radio_checked
			"fire_exterior": return app.fire_model.recon.exterior
			"fire_door": return app.fire_model.recon.door
			"fire_hydrant": return app.fire_model.hydrant_connected
			"fire_victim": return app.fire_model.victim.status == "carried"
			"fire_safe": return app.fire_model.victim.status == "rescued"
		return false
	return await app._tap_action("interact", acknowledged, "Actual interaction " + id)

func _aim(at: Vector3) -> void:
	# Reachable camera yaw/pitch set as an explicit aiming fixture, rays are real.
	app.officer._pivot.look_at(at)
	app.officer._pitch = clampf(app.officer._pivot.rotation.x, -0.95, 0.32)
	app.officer._pivot.rotation.x = app.officer._pitch
	await app._test_frames(10)

func _mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)


func _same_snapshot(actual: Variant, expected: Variant) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary or actual.size() != expected.size(): return false
		for key in expected:
			if not actual.has(key) or not _same_snapshot(actual[key], expected[key]): return false
		return true
	if expected is Array:
		if not actual is Array or actual.size() != expected.size(): return false
		for index in expected.size():
			if not _same_snapshot(actual[index], expected[index]): return false
		return true
	if expected is int or expected is float:
		return (actual is int or actual is float) and is_finite(float(actual)) and absf(float(actual) - float(expected)) < 0.000000001
	return actual == expected


func _walk_to(at: Vector3, radius: float, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Vector2(app.officer.position.x - at.x, app.officer.position.z - at.z).length() > radius:
		var offset: Vector3 = at - app.officer.global_position
		var yaw := atan2(-offset.x, -offset.z)
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(angle_difference(yaw, app.officer._pivot.rotation.y) / app.officer.sensitivity, 0)
		app.officer._unhandled_input(motion)
		Input.action_press("move_forward")
		await app.get_tree().physics_frame
		if Time.get_ticks_msec() > deadline:
			Input.action_release("move_forward")
			print("FIRE_WALK_STALL at=",app.officer.global_position," yaw=",app.officer._pivot.rotation.y," velocity=",app.officer.velocity," heat=",app.fire_model.average_heat()," gate=",app.fire_site._entry_bar.collision_layer)
			for index in app.officer.get_slide_collision_count(): print("FIRE_COLLISION=",app.officer.get_slide_collision(index).get_collider().get_path())
			return app._check(false, "Actual walking route unobstructed to " + str(at))
	Input.action_release("move_forward")
	await app._test_frames(3)
	return true


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for frame in range(4): await RenderingServer.frame_post_draw
	app._check(app.get_viewport().get_texture().get_image().save_png("user://" + label + ".png") == OK, "Actual rendered " + label)


func _lay_hose(expected: int) -> bool:
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.pressed = true
	Input.parse_input_event(q)
	var observed: bool = await app._wait_for(func(): return app.fire_model.hose_points.size() == expected, "Actual ground-ray Q segment " + str(expected), 15)
	q = InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.pressed = false
	Input.parse_input_event(q)
	if not observed: print("FIRE_HOSE_FAILURE notice=", app.notice.text, " camera=", app.officer.camera.global_position)
	return observed
