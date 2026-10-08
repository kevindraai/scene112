extends RefCounted
## Spatial/input integration. Completed M3 is an explicit entry fixture; no
## evidence, statement, hypothesis, report or research completion is injected.
const Fire = preload("res://scripts/fire_case.gd")
const SAVE := "user://validation-research-m4.json"
var app: Node3D
var _movement: RefCounted

func run(root: Node3D) -> void:
	app = root
	var graphics = preload("res://scripts/graphics_validation.gd").new()
	graphics.app = app
	print("SCENE112_GRAPHICS_BACKEND=", JSON.stringify(graphics._backend()))
	app._test_timeout(300)
	_movement = load("res://scripts/fire_validation.gd").new()
	_movement.app = app
	await app._test_frames(3)
	var fire := Fire.new()
	fire.begin("campaign")
	for step: String in Fire.BASICS: fire.complete_step(step)
	fire.check_recon("exterior")
	fire.check_recon("door")
	fire.connect_water()
	fire.add_hose_point(Vector3(2, 0, 44))
	fire.choose_tactic("interior")
	for id: String in ["front", "origin", "side"]:
		for index in 8:
			fire.spray(id, 0.5)
			fire.tick(0.5)
	fire.pickup_victim()
	fire.rescue_victim()
	fire.finish()
	app.state.fire_campaign = fire.to_dict()
	var original: Dictionary = JSON.parse_string(JSON.stringify(app.state.fire_campaign, "", true, true))
	app.research_ui.start_campaign()
	if not _press("Onderzoek beginnen"): return
	if not app._check(app.research_model.mode == "campaign" and app.state.role == "research", "Case3 uses completed M3 entry fixture and actual role callback"): return
	_fixture(Vector3(-2, 0.1, 42.5))
	await _aim(Vector3(-4.9, 1, 50.2))
	_key(KEY_F, true)
	await app._test_frames(5)
	_key(KEY_F, false)
	if not app._check(app.research_model.photographs.is_empty(), "Exterior wall/range cannot reveal indoor evidence"): return
	if not await _movement._walk_to(Vector3(-2, 0, 45.2), 0.35, 15): return
	if not app._check(app.fire_site.is_inside(app.officer.position), "Actual safe door passage to the same authored house"): return
	print("RESEARCH_STAGE=inside at=", app.officer.position)
	var fixtures := {
		"overview": Vector3(-2, 0.1, 45.0),
		"living": Vector3(-2.8, 0.1, 46.5),
		"origin": Vector3(-2.0, 0.1, 48.6),
		"connection": Vector3(-3.0, 0.1, 49.0),
		"entry_record": Vector3(-2, 0.1, 25.2),
		"dispatch_record": Vector3(1, 0.1, -5.9),
	}
	for id: String in ["overview", "living", "origin", "connection", "entry_record", "dispatch_record"]:
		if not await _collect(id, fixtures[id]): return
		print("RESEARCH_STAGE=source id=", id)
		if id == "connection": await _movement._capture("research-scene")
	if not app._check(app.research_model.evidence.size() == 6 and _movement._same_snapshot(app.research_model.incident, original), "Six actual spatial sources and immutable fire aftermath"): return
	for person: String in ["saar", "lars"]:
		_fixture(app.research_site._points["witness_" + person].global_position + Vector3(0, 0.1, 1.4))
		if not await app._wait_for(func(): return app.current_target.get("id") == "witness_" + person, "Real witness proximity " + person, 10): return
		if not await app._tap_action("interact", func(): return app.paused and app._menu_title_is(str(app.research_model._data.witnesses[person].name)), "Actual E starts source conversation " + person): return
		for prefix: String in ["Open vraag", "Doorvragen"]:
			if not _press(prefix): return
			if not _press("Verder vragen"): return
		if person == "lars":
			if not _press("Selectief bewijs"): return
			if not app._check(app.research_model.witnesses.lars.contradiction, "Actual source confrontation records presence contradiction"): return
			await _movement._capture("research-interview")
			if not _press("Verder vragen"): return
		if not _press("Terug naar onderzoek"): return
	_fixture(Vector3(-6.5, 0.1, -4.9))
	if not await app._wait_for(func(): return app.current_target.get("id") == "research_lab", "Actual bureau evidence desk", 10): return
	if not await app._tap_action("interact", func(): return app._menu_title_is("Sporenbalie"), "Actual E lab transfer"): return
	if not _press("Object met bronlabel overdragen"): return
	if not _press("Verder onderzoeken"): return
	# Observe twenty actual in-world simulation seconds. Slow software rendering
	# may advance simulation slower than wall time; no result/clock injection.
	if not await app._wait_for(func(): return app.research_model.clock - app.research_model.lab_requested >= 20, "Separate observed simulation-time expert follow-up delay", 90): return
	if not await app._tap_action("interact", func(): return app._menu_title_is("Sporenbalie"), "Actual lab return"): return
	if not _press("Deskundigenresultaat ophalen"): return
	if not app._check(app.research_model.lab_result and not app.research_model.expert_report().is_empty(), "Actual object result with source and limits"): return
	if not _press("Verder onderzoeken"): return
	if not await app._tap_action("radio", func(): return app._menu_title_is("Onderzoeksbord"), "Actual R source board"): return
	for prefix: String in ["Koppelen · Ontstaansgebied", "Koppelen · Aanwezigheidsverklaring", "Koppelen · Woonkamerhypothese", "Koppelen · Inzet"]:
		if not _press(prefix): return
	if not _press("○ Vermoedelijke opzettelijke"): return
	if not _press("Brongebonden rapport opstellen"): return
	# Checkbox signal edits the real persisted draft, no direct source selection.
	for row: CheckBox in app.research_ui._rows.values(): row.button_pressed = true
	app.save_game(SAVE)
	var draft: Array = app.research_model.draft_selection.duplicate()
	app.load_game(SAVE)
	app.research_ui.show_report()
	if not app._check(app.research_model.draft_selection == draft and app.research_ui._rows.connection.button_pressed, "Actual report widgets/draft survive F5/F9 and reopening"): return
	if not _press("Rapport beoordelen"): return
	if not app._check(app.research_model.report.outcome == "wrong" and app.research_model.phase == "report", "Unsupported intent is wrong and can be corrected"): return
	if not _press("Onderbouwing verbeteren"): return
	if not _press("Concept later voortzetten"): return
	if not await app._tap_action("radio", func(): return app._menu_title_is("Onderzoeksbord"), "Actual return to hypothesis board"): return
	if not _press("○ Waarschijnlijk elektrisch"): return
	if not _press("Brongebonden rapport opstellen"): return
	# Demonstrate that uncited evidence is not counted, then repair actual draft.
	for row: CheckBox in app.research_ui._rows.values(): row.button_pressed = false
	for id: String in ["limits", "statement_saar", "statement_lars"]: app.research_ui._rows[id].button_pressed = true
	if not _press("Rapport beoordelen"): return
	if not app._check(app.research_model.report.outcome == "incomplete", "Collected but uncited facts cannot support the chosen cause"): return
	if not _press("Onderbouwing verbeteren"): return
	for row: CheckBox in app.research_ui._rows.values(): row.button_pressed = true
	if not _press("Rapport beoordelen"): return
	if not app._check(app.research_model.report.outcome == "careful" and app.state.campaign_stage == 3 and app.state.research_campaign.mode == "campaign", "Actual cited report closes Case3 without confession"): return
	await _movement._capture("research-completed")
	app.save_game(SAVE)
	var archived: Dictionary = app.state.research_campaign.duplicate(true)
	app.start_training("police")
	if not app._check(app.state.research_campaign == archived, "Completed investigation persists when starting a free duty"): return
	app.load_game(SAVE)
	if not app._check(app.research_model.phase == "completed" and app.research_model.report.outcome == "careful" and _movement._same_snapshot(app.research_model.incident, original), "Actual completed save restores result and original aftermath"): return
	DirAccess.remove_absolute(SAVE)
	DirAccess.remove_absolute(SAVE + ".bak")
	print("SCENE112_RESEARCH_OK actual F/E spatial evidence; two witnesses/contradiction; delayed expert; source board; wrong/incomplete/corrected report; draft/save/archive")
	app._test_finished = true
	await app.quit_game(0)

func _collect(id: String, at: Vector3) -> bool:
	_fixture(at)
	await _aim(app.research_site._points["ev_" + id].global_position)
	if not await app._wait_for(func(): return app.research_site.aimed_evidence(app.officer.camera, app.officer) == id, "Actual unobstructed camera source " + id, 8):
		print("RESEARCH_AIM_FAIL id=", id, " officer=", app.officer.position, " camera=", app.officer.camera.position)
		var camera: Camera3D = app.officer.camera
		var center: Vector2 = camera.get_viewport().get_visible_rect().size / 2.0
		var start: Vector3 = camera.project_ray_origin(center)
		var query := PhysicsRayQueryParameters3D.create(start, start + camera.project_ray_normal(center) * 24, 1 | 16, [app.officer.get_rid()])
		query.collide_with_areas = true
		var hit: Dictionary = app.officer.get_world_3d().direct_space_state.intersect_ray(query)
		print("RESEARCH_AIM_RAY=", hit)

		return false
	_key(KEY_F, true)
	var recorded: bool = await app._wait_for(func(): return app.research_model.photographs.has(id), "Actual F records source photograph " + id, 8)
	_key(KEY_F, false)
	if not recorded: return false
	return await app._tap_action("interact", func(): return app.research_model.evidence.has(id), "Actual E collects photographed source " + id)

func _fixture(at: Vector3) -> void:
	_movement._fixture(at)

func _aim(at: Vector3) -> void:
	await _movement._aim(at)

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _press(title: String) -> bool:
	var pending: Array[Node] = [app.menu_items]
	var matches: Array[Button] = []
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Button and not node.disabled:
			if node.text == title:
				node.pressed.emit()
				return true
			if node.text.begins_with(title): matches.append(node)
		for child: Node in node.get_children(): pending.append(child)
	if matches.size() != 1: return app._check(false, "Unique reachable research menu action: " + title)
	matches[0].pressed.emit()
	return true
