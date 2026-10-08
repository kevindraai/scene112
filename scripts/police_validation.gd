extends RefCounted
## Runtime integration checks remain active in release exports.
## Pose fixtures shorten travel between interactions. Driving, SpringArm camera,
## cone raycasts, GUI choices and fingerprint grades use the actual app handlers.

var _app: Node3D
const TEST_SAVE := "user://validation-police-m2.json"
const TEST_AUDIO_SAVE := "user://validation-audio-m2.json"

func run(app: Node3D) -> void:
	_app = app
	app._test_timeout(120)
	_cleanup()
	await app._test_frames(2)
	if not _check_menu_bounds("main"): return
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var main_image: Error = app.get_viewport().get_texture().get_image().save_png("user://m2-main-menu.png")
		if not app._check(main_image == OK, "M2 rendered branded main menu screenshot"): return
	if not await _check_audio(): return
	if not app._press_menu("Academie · lessen"): return
	await app._test_frames(2)
	if not _check_menu_bounds("academy"): return
	if not app._press_menu("Terug naar mijn dienst"): return
	if not app._check(app._menu_title_is("SCÈNE 112") and not app.active, "academy cancel returns to main menu"): return
	if not app._press_menu("Nieuwe campagne · De eerste dienst"): return
	if not app._check(app.police_model.mode == "campaign" and app.active, "campaign starts actual police case"): return
	if not await _road_loop(): return
	if not await _open_report(): return
	if not _edit_categories(true): return
	if not app._press_menu("Rapport ter beoordeling indienen"): return
	if not app._check(app.police_model.result == "wrong" and app.state.campaign_stage == 0, "unfounded report cannot advance campaign"): return
	if not app._press_menu("Concept verbeteren"): return
	if not _edit_categories(false): return
	if not _move_row(0, 1): return
	var draft: Array = app.police_ui.capture_draft()
	app.save_game(TEST_SAVE)
	if not app._check(FileAccess.file_exists(TEST_SAVE), "draft saved through root state callback"): return
	var changed_rows := _editor_rows()
	var changed_include: CheckBox = changed_rows.get_child(0).get_child(2).get_child(0)
	changed_include.button_pressed = not changed_include.button_pressed
	if not _move_row(0, 1): return
	if not app._check(app.police_ui.capture_draft() != draft, "draft changed after saving before actual load"): return
	app.load_game(TEST_SAVE)
	if not app._check(app.police_ui.capture_draft() == draft and app.state.police_draft == draft, "load preserves category, inclusion and player-defined card order"): return
	if not await _open_report(): return
	if not _order_cards(): return
	if not app._press_menu("Rapport ter beoordeling indienen"): return
	if not app._check(app.police_model.result == "careful" and app.state.campaign_stage == 1, "careful campaign PV advances root campaign stage"): return
	var accepted: Dictionary = app.police_model.report_score.duplicate(true)
	if not _check_archive(accepted): return
	app.save_game(TEST_SAVE)
	if not app._press_menu("Oefening opnieuw beginnen"): return
	if not app._check(app.police_model.result == "incomplete" and app.state.campaign_stage == 0, "actual campaign replay resets the current case before load"): return
	app.load_game(TEST_SAVE)
	if not await _open_report("Rapportbeoordeling"): return
	if not _check_archive(accepted): return
	if not app._check(app.state.police_campaign.mode == "campaign" and app.state.police_campaign.result == "careful", "accepted campaign dossier survives actual save/load"): return
	if not app._press_menu("Dienst vervolgen"): return
	if not await _academy("Les 1 · Basisdienst op straat"): return
	if not app._check(app.state.campaign_stage == 1 and app.police_model.mode == "basis", "academy preserves existing campaign chapter"): return
	if not await _road_loop(): return
	if not await _open_report(): return
	if not _edit_categories(false) or not _order_cards(): return
	if not app._press_menu("Rapport ter beoordeling indienen"): return
	if not app._check("basis" in app.state.course_passes and app.state.campaign_stage == 1, "repeated physical basis lesson records root course pass"): return
	if not app._press_menu("Dienst vervolgen"): return
	if not await _academy("Les 2 · Arrestant en rapportage"): return
	if not app._check(app.police_model.mode == "intake" and "basis" in app.state.course_passes, "intake lesson preserves earlier academy progress"): return
	app.officer.position = app.police_site._intake.global_position + Vector3(0, 0.1, 1.5)
	app.officer.velocity = Vector3.ZERO
	if not await app._wait_for(func(): return app.current_target.get("id") == "pc_intake", "actual intake proximity"): return
	if not await app._tap_action("interact", func(): return app._menu_title_is("Academie · intake"), "intake interaction"): return
	if not app._press_menu("Uitleg: aanleiding en registratie"): return
	if not app._press_menu("Cautie: u hoeft niet te antwoorden"): return
	if not app._press_menu("Consultatie en rechtsbijstand regelen"): return
	if not app._press_menu("Vingerafdrukken positioneren"): return
	var task: Control = app.police_ui._task
	if not app._check(task != null and task.has_focus(), "real fingerprint control receives focus"): return
	_contact(task, 0.0)
	var bad_until := Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < bad_until:
		if app._test_finished: return
		await app.get_tree().process_frame
	if not app._check(app.police_model.print_qualities.is_empty() and task.progress == 0, "misaligned held contact cannot instantly register a print"): return
	if not await _follow_finger(task): return
	if not app._check(task.accepted_count == 0 and not task._retry.disabled and app.police_model.print_qualities.size() == 1 and float(app.police_model.print_qualities[0]) < 0.7, "actual misalignment produces a rejected grade and retry"): return
	task._retry.pressed.emit()
	for index in range(3):
		if not await _follow_finger(task): return
		if not app._check(task.accepted_count == index + 1, "actual sustained finger alignment accepted"): return
		if index < 2: task._next.pressed.emit()
	if not app._check(app.police_model.can_report(), "three measured usable fingerprints unlock intake PV"): return
	for quality in app.police_model.print_qualities:
		if not app._check(float(quality) >= 0.7, "saved finger quality meets readability threshold"): return
	task._next.pressed.emit()
	if not app._press_menu("Proces-verbaal opstellen"): return
	if not _edit_categories(false) or not _order_cards(): return
	if not app._press_menu("Rapport ter beoordeling indienen"): return
	if not app._check(app.police_model.result == "careful" and "intake" in app.state.course_passes and "basis" in app.state.course_passes, "intake rights, real prints and PV record both course passes"): return
	var intake_score: Dictionary = app.police_model.report_score.duplicate(true)
	app.save_game(TEST_SAVE)
	if not app._press_menu("Oefening opnieuw beginnen"): return
	if not app._check(app.police_model.print_qualities.is_empty() and app.state.campaign_stage == 1 and app.state.course_passes.size() == 2, "actual academy replay clears the exercise and keeps campaign/course progress"): return
	app.load_game(TEST_SAVE)
	if not app._check(app.police_model.mode == "intake" and app.police_model.result == "careful" and app.police_model.print_qualities.size() == 3, "intake case and prints survive root save/load"): return
	if not app._check(app.state.campaign_stage == 1 and app.state.police_campaign.mode == "campaign" and app.state.police_campaign.result == "careful" and app.state.course_passes.size() == 2, "academy save retains accepted campaign dossier and chapter"): return
	if not await _open_report("Rapportbeoordeling"): return
	if not _check_archive(intake_score): return
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var saved_image: Error = app.get_viewport().get_texture().get_image().save_png("user://m2-playthrough.png")
		if not app._check(saved_image == OK, "M2 graphical report screenshot"): return
		print("SCENE112_POLICE_SCREENSHOT=", OS.get_user_data_dir())
	_cleanup()
	print("SCENE112_POLICE_OK actual root campaign and two academy lessons; true drive>20m, officer SpringArm mouse aiming and Q raycasts, sourced observations/conversations, PV wrong/correction/order/draft save, accepted archive, rights, sustained GUI fingerprint alignment/retry, root saves and campaign/course persistence; controlled position fixtures used")
	app._test_finished = true
	await app.quit_game(0)

func _check_menu_bounds(label: String) -> bool:
	var visible := _app.get_viewport().get_visible_rect()
	var count := 0
	for child in _app.menu_items.get_children():
		if child is Button:
			count += 1
			var rectangle: Rect2 = child.get_global_rect()
			if not _app._check(rectangle.position.x >= visible.position.x and rectangle.position.y >= visible.position.y and rectangle.end.x <= visible.end.x and rectangle.end.y <= visible.end.y, label + " menu button fits actual viewport: " + child.text): return false
	return _app._check(count > 0 and _app.menu.visible, label + " menu exposes visible choices")

func _check_audio() -> bool:
	var audio: Node = _app.audio
	if not _app._check(is_instance_valid(audio), "actual root audio director exists"): return false
	var status: Dictionary = audio.status()
	if not _app._check(status.waves_loaded == 24 and status.missing.is_empty() and status.theme == "menu", "native imported score and all 24 original audio resources load"): return false
	if not _app._check(status.driver is String and not status.driver.is_empty() and status.no_device == (status.driver == "Dummy"), "audio reports device or silent Dummy fallback without gameplay failure"): return false
	for bus: String in audio.BUSES:
		if not _app._check(AudioServer.get_bus_index(bus) >= 0, "native audio mixer bus exists: " + bus): return false
	var previous_path: String = audio.settings_path
	var previous: Dictionary = audio.get_settings()
	audio.settings_path = TEST_AUDIO_SAVE
	if not _app._press_menu("Instellingen"): return false
	var options := _editor_rows()
	if not _app._check(options != null, "actual settings scroll contains audio controls"): return false
	var music: HSlider
	for child in options.get_children():
		if child is HSlider and child.tooltip_text.begins_with("Muziek"):
			music = child
	if not _app._check(music != null, "actual music slider exists"): return false
	music.value = 0.25 if absf(float(previous.volumes.Music) - 0.25) > 0.01 else 0.6
	var saved: Dictionary = audio.get_settings()
	if not _app._check(saved != previous and FileAccess.file_exists(TEST_AUDIO_SAVE), "real UI slider changes and persists audio mix"): return false
	audio.set_volume("Music", 0.9, false)
	if not _app._check(audio.load_settings() and audio.get_settings() == saved, "native audio settings reload after in-memory change"): return false
	if not _app._check(audio.apply_settings(previous, false), "validation restores user's original audio mix"): return false
	audio.settings_path = previous_path
	if not _app._press_menu("Terug"): return false
	_cleanup_audio()
	print("SCENE112_AUDIO_RUNTIME_OK waves=", status.waves_loaded, " driver=", status.driver, " actual settings slider/save/reload; audible quality requires a playback device")
	return _app._check(_app._menu_title_is("SCÈNE 112"), "settings returns to actual main menu")

func _road_loop() -> bool:
	if not await _app._test_station("equipment"): return false
	if not await _app._test_station("radio"): return false
	var car: Node3D = _app.district.objects.police_car
	car.rotation.y = PI / 2.0
	_app.officer.position = car.to_global(Vector3(1.8, 0.1, 0))
	_app.officer.velocity = Vector3.ZERO
	if not await _app._wait_for(func(): return _app.current_target.get("id") == "police_car", "police vehicle proximity"): return false
	if not await _app._tap_action("interact", func(): return _app.state.occupied_vehicle == "police_car", "actual case vehicle entry"): return false
	var start := car.position
	Input.action_press("move_forward")
	var arrived: bool = await _app._wait_for(func(): return car.position.x < -23.0, "actual case driving beyond twenty metres", 9)
	Input.action_release("move_forward")
	if not arrived: return false
	Input.action_press("brake")
	var stopped: bool = await _app._wait_for(func(): return absf(float(car.speed)) < 0.1, "brake before case exit")
	Input.action_release("brake")
	if not stopped or not _app._check(car.position.distance_to(start) > 20, "body actually travelled twenty metres"): return false
	if not await _app._tap_action("interact", func(): return _app.state.occupied_vehicle.is_empty(), "actual safe exit at case"): return false
	if not await _app._wait_for(func(): return _app.police_model.basics.exit, "root controller confirms preparation and driving"): return false
	for zone: Vector3 in _app.police_site.CONE_ZONES:
		_app.officer.position = zone + Vector3(0, 0.1, 1.5)
		_app.officer.velocity = Vector3.ZERO
		if not await _aim_at_ground(zone): return false
		var count: int = _app.police_model.cones.size()
		if not await _app._tap_action("place_cone", func(): return _app.police_model.cones.size() == count + 1, "Q uses actual officer-camera raycast"): return false
	var points := {"pc_damage": Vector3(-15.4, 0.1, 18), "pc_tracks": Vector3(-20, 0.1, 13.7), "pc_signal": Vector3(-21.5, 0.1, 19.2)}
	for id: String in points:
		_app.officer.position = points[id]
		_app.officer.velocity = Vector3.ZERO
		if not await _app._wait_for(func(): return _app.current_target.get("id") == id, "observation proximity " + id): return false
		var count: int = _app.police_model.observations.size()
		if not await _app._tap_action("interact", func(): return _app.police_model.observations.size() == count + 1, "actual E observation " + id): return false
	for id: String in ["pc_lotte", "pc_bram"]:
		_app.officer.position = _app.district.objects[id].global_position + Vector3(0, 0.1, 1.5)
		_app.officer.velocity = Vector3.ZERO
		if not await _app._wait_for(func(): return _app.current_target.get("id") == id, "person proximity " + id): return false
		if not await _app._tap_action("interact", func(): return _app.paused, "actual conversation opens"): return false
		if not _app._press_menu("Open vraag: vertel wat er gebeurde"): return false
		if not _app._press_menu("Terug naar de locatie"): return false
	return _app._check(_app.police_model.can_report(), "actual scene actions unlock report")

func _aim_at_ground(zone: Vector3) -> bool:
	# Camera direction changes through the same mouse event as player input.
	await _app._test_frames(3)
	var officer: Node3D = _app.officer
	var offset := zone - officer.global_position
	var yaw := atan2(-offset.x, -offset.z)
	var height: float = officer._pivot.global_position.y - zone.y
	var pitch := -atan2(height, Vector2(offset.x, offset.z).length())
	if not _app._check(pitch >= -0.95 and pitch <= 0.32, "cone is reachable within actual officer pitch limits"): return false
	# Viewport scaling can transform a synthetic motion. Small actual events
	# converge using camera feedback, rather than assigning camera transforms.
	for attempt in range(40):
		var yaw_error := wrapf(float(officer._pivot.rotation.y) - yaw, -PI, PI)
		var pitch_error: float = float(officer._pitch) - pitch
		if absf(yaw_error) < 0.01 and absf(pitch_error) < 0.01: break
		var motion := InputEventMouseMotion.new()
		var step := Vector2(yaw_error, pitch_error) * 0.25 / float(officer.sensitivity)
		motion.relative = Vector2(clampf(step.x, -15, 15), clampf(step.y, -15, 15))
		_app.get_viewport().push_input(motion, true)
		await _app._test_frames(1)
	await _app._test_frames(2)
	print("POLICE_CAMERA_DIAGNOSTIC viewport=", _app.get_viewport().get_visible_rect().size, " actual_pitch=", officer._pitch, " target_pitch=", pitch, " actual_yaw=", officer._pivot.rotation.y, " target_yaw=", yaw)
	return _app._check(officer.camera.current and absf(float(officer._pitch) - pitch) < 0.02 and absf(wrapf(float(officer._pivot.rotation.y) - yaw, -PI, PI)) < 0.02, "real mouse motion aims the active SpringArm camera")

func _open_report(title: String = "Proces-verbaal") -> bool:
	_app.officer.position = _app.district.objects.pc_report.global_position + Vector3(0, 0.1, 1.5)
	_app.officer.velocity = Vector3.ZERO
	if not await _app._wait_for(func(): return _app.current_target.get("id") == "pc_report", "report desk proximity"): return false
	return await _app._tap_action("interact", func(): return _app._menu_title_is(title), "actual report desk interaction")

func _academy(lesson: String) -> bool:
	if not await _app._tap_action("pause", func(): return _app._menu_title_is("Dienstpauze"), "pause to academy menu"): return false
	if not _app._press_menu("Naar hoofdmenu"): return false
	if not _app._press_menu("Academie · lessen"): return false
	return _app._press_menu(lesson)

func _editor_rows() -> Node:
	for child in _app.menu_items.get_children():
		if child is ScrollContainer and child.get_child_count() > 0 and child.get_child(0) is VBoxContainer:
			return child.get_child(0)
	return null

func _edit_categories(include_bad: bool) -> bool:
	var rows := _editor_rows()
	if not _app._check(rows != null, "real report editor rows exist"): return false
	var available: Dictionary = {}
	for card in _app.police_model.report_cards(): available[card.id] = card
	var draft: Array = _app.police_ui.capture_draft()
	for index in range(draft.size()):
		var row: Dictionary = draft[index]
		var choices: Node = rows.get_child(index).get_child(2)
		var include: CheckBox = choices.get_child(0)
		var selected: bool = row.id != "conclusion_guilt" or include_bad
		include.button_pressed = selected
		var category: OptionButton = choices.get_child(1)
		var correct: int = _app.police_ui.CATEGORIES.find(available[row.id].category)
		category.select(correct)
		category.item_selected.emit(correct)
	return _app._check(_app.police_ui.capture_draft().size() == draft.size(), "checkbox and category controls preserve report content")

func _move_row(index: int, direction: int) -> bool:
	var rows := _editor_rows()
	if not _app._check(rows != null, "report order widgets exist"): return false
	var button: Button = rows.get_child(index).get_child(2).get_child(2 if direction < 0 else 3)
	if not _app._check(not button.disabled, "requested report reorder is enabled"): return false
	button.pressed.emit()
	return true

func _order_cards() -> bool:
	var available: Dictionary = {}
	for card in _app.police_model.report_cards(): available[card.id] = card
	var draft: Array = _app.police_ui.capture_draft()
	var wanted: Array = draft.duplicate(true)
	wanted.sort_custom(func(first, second): return float(available[first.id].time) < float(available[second.id].time))
	for target in range(wanted.size()):
		draft = _app.police_ui.capture_draft()
		var index := target
		while index < draft.size() and draft[index].id != wanted[target].id: index += 1
		if not _app._check(index < draft.size(), "report card still exists during reordering"): return false
		while index > target:
			if not _move_row(index, -1): return false
			index -= 1
	return _app._check(_app.police_ui.capture_draft() == wanted, "actual order buttons produce chronological draft")

func _has_button(title: String) -> bool:
	for child in _app.menu_items.get_children():
		if child is Button and child.text == title: return true
	return false

func _check_archive(expected: Dictionary) -> bool:
	if not _app._check(_app._menu_title_is("Rapportbeoordeling") and not _has_button("Concept verbeteren"), "accepted dossier exposes readonly review"): return false
	if not _app._check(_app.police_model.report_score == expected, "accepted score remains unchanged when viewed"): return false
	var rows := _editor_rows()
	return _app._check(rows != null and rows.get_child_count() >= 7 and rows.get_child(0) is Label, "readonly archive displays sourced report rows")

func _contact(task: Control, position: float) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(32 + position * (task.size.x - 64), 85)
	task._gui_input(motion)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = motion.position
	press.pressed = true
	task._gui_input(press)

func _follow_finger(task: Control) -> bool:
	_contact(task, float(task.target))
	var deadline := Time.get_ticks_msec() + 4000
	while not task._awaiting:
		if _app._test_finished: return false
		if Time.get_ticks_msec() > deadline: return _app._check(false, "finger sustained contact timeout")
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(32 + float(task.target) * (task.size.x - 64), 85)
		task._gui_input(motion)
		await _app.get_tree().process_frame
	return true

func _cleanup() -> void:
	_cleanup_audio()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TEST_SAVE + suffix): DirAccess.remove_absolute(TEST_SAVE + suffix)

func _cleanup_audio() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TEST_AUDIO_SAVE + suffix): DirAccess.remove_absolute(TEST_AUDIO_SAVE + suffix)
