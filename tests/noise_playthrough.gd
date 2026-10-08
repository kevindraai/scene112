extends SceneTree
const Scene = preload("res://scenes/main.tscn")
var app: Node3D
var movement: RefCounted
func _initialize() -> void: call_deferred("run")
func run() -> void:
	app = Scene.instantiate()
	root.add_child(app)
	await process_frame
	app.test_mode = true
	app._test_timeout(120)
	app.start_new("police")
	movement = load("res://scripts/fire_validation.gd").new()
	movement.app = app
	if not await app._test_station("equipment"): return
	if not await app._test_station("radio"): return
	# Deterministic queue/time fixture only; incident acceptance and every
	# observation/conversation/movement/report action below use real handlers.
	app.ledger.start(2, "police")
	app.ledger.tick(20)
	if not await app._tap_action("radio", func(): return app._menu_title_is("Meldkamer"), "Real duty radio"): return
	if not app._press_menu("Melding aannemen"): return
	if not app._check(app.noise_model.phase == "active" and app.ledger.incident.response_window == 600, "Actual accepted repeatable overlast and practical response time"): return
	for source: String in ["activity", "access"]:
		var point: Node3D = app.noise_site._nodes["noise_" + source]
		movement._fixture(point.global_position + Vector3(1.0, -point.global_position.y + 0.1, 0.4))
		if not await app._wait_for(func(): return app.current_target.get("id") == "noise_" + source, "Physical source proximity " + source, 8): return
		if not await app._tap_action("interact", func(): return source in app.noise_model.observations, "Actual E source observation " + source):
			print("NOISE_SOURCE_FAILURE at=", app.officer.global_position, " target=", app.current_target, " reachable=", app.noise_site.can_reach("noise_" + source, app.officer), " notice=", app.notice.text, " paused=", app.paused)
			return
	for side: String in ["reporter", "participant"]:
		if not await _approach(side): return
		if not app._press_menu("Open vragen en luisteren"): return
		if not app._press_menu("Terug naar de locatie"): return
	if not await _approach("reporter"): return
	if not app._press_menu("Vooraf schuld aanwijzen"): return
	if not app._press_menu("Verder spreken"): return
	if not app._press_menu("Herstellen · oordeel terugnemen en opnieuw luisteren"): return
	if not app._press_menu("Verder spreken"): return
	if not app._press_menu("Samen een concrete afspraak maken"): return
	if not app._press_menu("Terug naar de locatie"): return
	print("NOISE_TRACE=save at=", app.officer.position)
	app.save_game("user://validation-noise.json")
	var before: Dictionary = app.noise_model.to_dict()
	print("NOISE_TRACE=training_fire")
	app.start_training("fire")
	print("NOISE_TRACE=load")
	app.load_game("user://validation-noise.json")
	if not app._check(movement._same_snapshot(before, app.noise_model.to_dict()) and app.noise_site._people.size() == 2, "Actual in-progress save/load restores source history and both people"): return
	if not await _approach("participant"): return
	if not app._press_menu("Samen een concrete afspraak maken"): return
	if not app._press_menu("Terug naar de locatie"): return
	var start_a: Vector3 = app.noise_site._people.reporter.position
	var start_b: Vector3 = app.noise_site._people.participant.position
	if not await app._wait_for(func(): return app.noise_model.separated, "Both real CharacterBody parties move and fulfil the agreement", 15): return
	if not app._check(app.noise_site._people.reporter.position.distance_to(start_a) > 0.7 and app.noise_site._people.participant.position.distance_to(start_b) > 0.7, "Observed physical movement of both parties"): return
	if not await app._tap_action("radio", func(): return app._menu_title_is("Afhandeling overlast"), "Actual closure plan"): return
	if not app._press_menu("Rapport met bronnen opstellen"): return
	for row: CheckBox in app.noise_ui._rows.values(): row.button_pressed = true
	if not app._press_menu("Afhandeling afronden"): return
	if not app._check(app.noise_model.report.result == "careful" and app.noise_model.report.total == 85 and app.ledger.incident.phase == "resolved" and app.ledger.completed == 1, "Recovered blame keeps consequence; source-supported physical resolution closes actual dispatch"): return
	print("NOISE_TRACE=save at=", app.officer.position)
	app.save_game("user://validation-noise.json")
	print("NOISE_TRACE=load")
	app.load_game("user://validation-noise.json")
	if not app._check(app.noise_model.phase == "completed" and app.noise_model.report.total == 85 and app.noise_model.pressure == 1, "Completed source/score history survives root save/load"): return
	if DisplayServer.get_name() != "headless": await movement._capture("free-noise-completed")
	DirAccess.remove_absolute("user://validation-noise.json")
	DirAccess.remove_absolute("user://validation-noise.json.bak")
	print("SCENE112_NOISE_PLAY_OK real sources/two-party dialogue/recovery/physical separation/cited report/dispatch/save/load; shortened queue/travel fixtures")
	app._test_finished = true
	await app.quit_game(0)

func _approach(side: String) -> bool:
	var person: CharacterBody3D = app.noise_site._people[side]
	movement._fixture(person.global_position + Vector3(-1.2 if side == "reporter" else 1.2, 0.1, 0))
	if not await app._wait_for(func(): return app.current_target.get("id") == "noise_" + side, "Actual reachable party " + side, 8): return false
	return await app._tap_action("interact", func(): return app.paused and app._menu_title_is(str(app.noise_model.DATA.VARIANTS[app.noise_model.variant][side].name)), "Actual E person dialog " + side)
