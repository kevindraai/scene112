extends SceneTree
const Scene = preload("res://scenes/main.tscn")
const Fire = preload("res://scripts/fire_case.gd")
var app: Node3D
var errors := 0
func check(ok: bool, label: String) -> void:
	if not ok: errors += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	app = Scene.instantiate()
	root.add_child(app)
	await process_frame
	var fire := Fire.new()
	fire.begin("campaign")
	for step: String in Fire.BASICS: fire.complete_step(step)
	fire.check_recon("exterior"); fire.check_recon("door"); fire.connect_water()
	fire.add_hose_point(Vector3(2, 0, 44)); fire.choose_tactic("interior")
	for id: String in ["front", "origin", "side"]:
		for index in 8: fire.spray(id, 0.5); fire.tick(0.5)
	fire.pickup_victim(); fire.rescue_victim(); fire.finish()
	app.state.fire_campaign = fire.to_dict() # Declared completed-M3 fixture; fire gameplay has its own full test.
	app.research_ui.start_campaign()
	check(app.research_model.mode == "campaign" and app.state.role == "research", "Actual research campaign callback")
	check(app.research_site._active and app.fire_site._active, "Same authored incident reused cold")
	check(app.fire_site._door.rotation.y < -1 and app.fire_site._entry_bar.collision_layer == 0, "Declared safe handover opens actual house")
	app._press_menu("Onderzoek beginnen")
	await process_frame
	app.research_ui.show_board()
	check(app._menu_title_is("Onderzoeksbord"), "Actual source hypothesis board")
	app.research_ui.show_report()
	check(app._menu_title_is("Onderzoeksrapport"), "Actual cited report editor")
	app.research_ui._conversation("saar")
	check(app._menu_title_is("Saar · bewoner"), "Actual adult witness conversation")
	app.research_ui._ask("saar", "open")
	check(app.research_model.witnesses.saar.statements.size() == 1, "Actual question records source statement")
	app.research_ui._conversation("lars")
	app.research_ui._ask("lars", "open")
	check(app.research_model.witnesses.lars.statements.size() == 1, "Second actual adult source statement")
	var original: Dictionary = JSON.parse_string(JSON.stringify(app.state.fire_campaign, "", true, true))
	var path := "user://research-scene-smoke.json"
	app.save_game(path)
	app.start_training("police")
	app.load_game(path)
	check(app.research_model.mode == "campaign" and app.research_site._active, "Actual research save/load reuses incident")
	check(app.state.fire_campaign == original, "Prior fire archive remains immutable")
	DirAccess.remove_absolute(path); DirAccess.remove_absolute(path + ".bak")
	print("SCENE112_RESEARCH_SCENE_OK errors=", errors)
	await app.audio.shutdown()
	quit(0 if errors == 0 else 1)
