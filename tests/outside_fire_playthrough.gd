extends SceneTree
## Actual whole-app free-fire loop. Queue and between-station placement fixtures
## shorten travel; driving, E/Q/radio, ray aiming, held water and F5/F9 are real.
const Scene = preload("res://scenes/main.tscn")
var app: Node3D
var movement: RefCounted
var first_variant := -1
var saved_fire := {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	app = Scene.instantiate()
	root.add_child(app)
	await process_frame
	app.test_mode = true
	app._test_timeout(420)
	movement = load("res://scripts/fire_validation.gd").new()
	movement.app = app
	if not app._press_menu("Vrije brandweerdienst"): return
	if not await app._test_station("fire_equipment"): return
	if not await app._test_station("fire_radio"): return
	app.ledger.start(2, "fire")
	app.ledger.tick(20)
	if not await _accept_and_arrive(): return
	first_variant = int(app.outside_model.variant)
	if not await _prepare_site(): return
	var origin: Vector3 = app.outside_model.origin
	if not await _work_position(): return
	await movement._aim(origin + Vector3(-5, 1.5, -8))
	if not app._check(app.outside_site.raycast_target(app.officer.camera, app.officer).is_empty(), "Real aimed miss has no target"): return
	var before_miss: float = app.outside_model.water_used
	_mouse(true)
	var missed: bool = await app._wait_for(func(): return app.outside_model.water_used >= before_miss + 2.0, "Held actual miss spends water", 10)
	_mouse(false)
	if not missed: return
	if not app._check(app.outside_model.hit_water == 0, "A miss never counts as local suppression"): return
	if not await _cool("center", 0.19): return
	if not app._check(app.outside_model.cells[1].heat > 0.2 and app.outside_model.cells[0].wet > 0.2, "Targeted water cools one cell while another remains hot"): return
	if not await _save_restore_live(): return
	origin = app.outside_model.origin
	if not await _work_position(): return
	for id: String in ["center", "left", "right"]:
		if not await _cool(id, 0.035): return
	if not app._check(app.outside_model.all_cold() and app.outside_model.water_used > 35, "Every real cell cooled with finite water use"): return
	if not await app._tap_action("radio", func(): return app._menu_title_is("Buitenbrand · inzet"), "Real cold handover plan"): return
	if not app._press_menu("Nasmeulcontrole en overdracht"): return
	if not app._check(app.outside_model.report_score.result == "careful" and app.ledger.incident.phase == "resolved" and app.ledger.completed == 1 and app.ledger.incident.quality == app.outside_model.report_score.total, "Careful physical free fire closes actual dispatch with matching score"): return
	await movement._capture("free-fire-completed")
	if not await _save_restore_completed(): return
	# Advance only the quiet queue interval; the next incident is a fresh actual
	# generated variant, then accepted and approached with another real drive.
	app.ledger.tick(maxf(0.01, app.ledger.next_report - app.ledger.duty_time + 0.01))
	if not await app._wait_for(func(): return app.outside_model.mode == "none" and app.ledger.incident.phase == "offered", "Next generated call clears previous owned site", 10): return
	if not await _accept_and_arrive(): return
	if not app._check(app.outside_model.variant != first_variant and app.outside_model.incident_id == 2, "Repeat call is a different material and location with fresh identity"): return
	if not await _prepare_site(): return
	origin = app.outside_model.origin
	if not await _work_position(): return
	if not await _cool("center", 0.5): return
	if not await app._tap_action("radio", func(): return app._menu_title_is("Buitenbrand · inzet"), "Real second-variant plan"): return
	if not app._press_menu("Veilig terugtrekken en doorgeven"): return
	if not app._check(app.outside_model.report_score.result == "partial" and app.outside_model.withdrew and not app.outside_model.all_cold() and app.ledger.completed == 2 and app.ledger.incident.phase == "resolved", "Actual early handover preserves hot cells and a partial consequence"): return
	await movement._capture("free-fire-repeat-partial")
	if not app._press_menu("Vrije dienst vervolgen"): return
	if not await app._tap_action("radio", func(): return app._menu_title_is("Meldkamer"), "Radio is available again after repeated closure"): return
	print("SCENE112_OUTSIDE_FIRE_PLAY_OK actual fire-duty menu/PPE/radio/two20mDrives/Erecon/water/Qhose/heldMiss+threeCells/pause/F5F9/carefulDispatch/differentRepeatPartial; queue and short travel fixtures declared")
	app._test_finished = true
	await app.quit_game(0)

func _accept_and_arrive() -> bool:
	print("OUTSIDE_STAGE=accept serial=", app.ledger.serial, " variant=", app.ledger.incident.variant)
	var variant := int(app.ledger.incident.variant)
	var truck: Node3D = app.district.objects.fire_truck
	# Existing eastbound lane, outside the incident footprint. No distance or
	# drive objective is assigned: held W must move this physical truck >20m.
	var start := Vector3(-11, 0.05, 19) if variant == 0 else Vector3(-38, 0.05, 19)
	truck.position = start; truck.rotation.y = -PI / 2; truck.stop()
	if not await app._tap_action("radio", func(): return app._menu_title_is("Meldkamer"), "Actual free-fire radio acceptance"): return false
	if not app._press_menu("Melding aannemen"): return false
	if not app._check(app.outside_model.mode == "free" and app.ledger.incident.phase == "accepted" and app.ledger.incident.response_window == 600, "Accepted call creates the actual outside model"): return false
	movement._fixture(truck.global_position + Vector3(0, 0.1, -2.2))
	if not await app._wait_for(func(): return app.current_target.get("id") == "fire_truck", "Actual free-fire truck proximity", 10): return false
	if not await app._tap_action("interact", func(): return app.state.occupied_vehicle == "fire_truck", "Actual free-fire truck entry"): return false
	Input.action_press("move_forward")
	var driven: bool = await app._wait_for(func(): return truck.global_position.distance_to(start) > 22 and app.outside_model.basics.drive, "Actual free-fire approach drive >20m", 25)
	Input.action_release("move_forward")
	if not driven: return false
	Input.action_press("brake")
	var stopped: bool = await app._wait_for(func(): return absf(truck.speed) < 0.05, "Actual free-fire braking", 12)
	Input.action_release("brake")
	if not stopped: return false
	if not await app._tap_action("interact", func(): return app.state.occupied_vehicle.is_empty(), "Actual free-fire truck exit"): return false
	if not await app._wait_for(func(): return app.outside_model.basics.exit, "Actual arrival and safe exit acknowledged", 8): return false
	return app._check(app.outside_model.basics.gear and app.outside_model.basics.radio and truck.global_position.distance_to(start) > 22, "Existing PPE/radio plus real drive retained")

func _prepare_site() -> bool:
	print("OUTSIDE_STAGE=prepare at=", app.outside_model.origin)
	for id: String in ["outside_exterior", "outside_surroundings", "outside_water"]:
		var point: Node3D = app.outside_site._points[id].node
		var offset := Vector3(0, 0.1, 0.15) if id != "outside_water" else Vector3(0.6, 0.1, -0.8)
		movement._fixture(point.global_position + offset)
		if not await app._wait_for(func(): return app.current_target.get("id") == id, "Physical outdoor point " + id, 10): return false
		var acknowledged := func():
			if id == "outside_water": return app.outside_model.hydrant_connected
			return bool(app.outside_model.recon[id.trim_prefix("outside_")])
		if not await app._tap_action("interact", acknowledged, "Actual E outdoor point " + id): return false
	var origin: Vector3 = app.outside_model.origin
	if not await _work_position(): return false
	await movement._aim(origin + Vector3(3, 0.02, -3.8))
	var camera: Camera3D = app.officer.camera
	var center := camera.get_viewport().get_visible_rect().size / 2
	var ray_start := camera.project_ray_origin(center)
	var ray_end := ray_start + camera.project_ray_normal(center) * 18
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(ray_start, ray_end, 1, [app.officer.get_rid()]))
	print("OUTSIDE_HOSE_RAY camera=", camera.global_position, " hit=", hit, " source=", app.outside_model.water_source(), " phase=", app.outside_model.phase)
	if not await _key(KEY_Q, func(): return app.outside_model.hose_points.size() == 2, "Actual Q ground-ray lays outside hose"): return false
	if not app._check(app.outside_model.hose_length() > 3 and app.outside_model.has_nozzle_at(app.officer.global_position), "Actual source-to-ground hose reaches the officer"): return false
	if not await app._tap_action("radio", func(): return app._menu_title_is("Buitenbrand · inzet"), "Actual exterior tactic plan"): return false
	if not app._press_menu("Defensieve buiteninzet beginnen"): return false
	return app._check(app.outside_model.phase == "active", "Actual plan starts the outdoor simulation")

func _work_position() -> bool:
	var origin: Vector3 = app.outside_model.origin
	# Clear of the existing plaza bench and of the parked truck's spring-arm
	# volume. A short genuine step also turns the actual avatar toward the fire.
	movement._fixture(origin + Vector3(3, 0.1, -5.4))
	await movement._aim(origin + Vector3(3, 1.3, 3))
	Input.action_press("move_forward")
	var walked: bool = await app._wait_for(func(): return app.officer.position.z >= origin.z - 4.7, "Actual short approach turns the PPE avatar toward the fire", 8)
	Input.action_release("move_forward")
	await app._test_frames(4)
	return walked

func _cool(id: String, threshold: float) -> bool:
	var index: int = {"center": 0, "left": 1, "right": 2}[id]
	if float(app.outside_model.cells[index].heat) <= threshold: return true
	await movement._aim(app.outside_site._targets[id].global_position)
	if not await app._wait_for(func(): return app.outside_site.raycast_target(app.officer.camera, app.officer) == id, "Actual separate outside target " + id, 10): return false
	_mouse(true)
	var cooled: bool = await app._wait_for(func(): return float(app.outside_model.cells[index].heat) <= threshold, "Held actual outside suppression " + id, 20)
	_mouse(false)
	if not cooled: return false
	return true

func _save_restore_live() -> bool:
	app._pause()
	var snapshot: Dictionary = app.outside_model.to_dict()
	var flame_clock: float = app.outside_site._effects.diagnostics().clock
	await app.get_tree().create_timer(0.2).timeout
	if not app._check(app.outside_model.to_dict() == snapshot and app.outside_site._effects.diagnostics().clock == flame_clock, "Actual pause freezes outside fire, water and effects"): return false
	if not await _key(KEY_F5, func(): return app.notice.text.begins_with("Dienst opgeslagen"), "Actual F5 stores live outside fire"): return false
	saved_fire = app.state.outside_fire.duplicate(true)
	if not app._check(movement._same_snapshot(saved_fire, snapshot), "Root captures exact active simulation journal"): return false
	app.start_training("police")
	if not app._check(app.outside_model.mode == "none" and app.outside_site._owned == null, "New role clears actual old outside site"): return false
	if not await _key(KEY_F9, func(): return app.state.role == "fire" and app.outside_model.mode == "free", "Actual F9 restores live outside case and role"): return false
	app._pause()
	print("OUTSIDE_RESTORE_PROOF state=", movement._same_snapshot(app.state.outside_fire, saved_fire), " hose=", movement._same_snapshot(app.outside_model.hose_points, saved_fire.hose_points), " targets=", app.outside_site._targets.size(), " phase=", app.outside_model.phase)
	if not app._check(movement._same_snapshot(app.state.outside_fire, saved_fire) and movement._same_snapshot(app.outside_model.hose_points, saved_fire.hose_points) and app.outside_site._targets.size() == 3 and app.outside_model.phase == "active", "F9 recreates real three-cell site and journal-backed hose"): return false
	app._resume()
	if not await _work_position(): return false
	await movement._aim(app.outside_site._targets.center.global_position)
	await movement._capture("free-fire-live-restored")
	return true

func _save_restore_completed() -> bool:
	if not await _key(KEY_F5, func(): return app.notice.text.begins_with("Dienst opgeslagen"), "Actual F5 stores completed fire and dispatch"): return false
	var grade: Dictionary = app.outside_model.report_score.duplicate(true)
	app.start_training("police")
	if not await _key(KEY_F9, func(): return app.outside_model.phase == "completed" and app.state.role == "fire", "Actual F9 restores completed fire"): return false
	return app._check(movement._same_snapshot(app.outside_model.report_score, grade) and app.ledger.completed == 1 and app.ledger.incident.phase == "resolved", "Completed outcome and dispatch survive actual key-driven save/load")

func _key(code: Key, acknowledged: Callable, label: String) -> bool:
	var event := InputEventKey.new(); event.physical_keycode = code; event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	print("OUTSIDE_KEY=", code, " immediate_notice=", app.notice.text, " hose=", app.outside_model.hose_points)
	var result: bool = await app._wait_for(acknowledged, label, 15)
	event = InputEventKey.new(); event.physical_keycode = code; event.pressed = false
	Input.parse_input_event(event)
	if not result: print("OUTSIDE_INPUT_FAILURE label=", label, " notice=", app.notice.text, " target=", app.current_target, " at=", app.officer.position)
	return result

func _mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)
