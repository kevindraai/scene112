extends SceneTree
const State = preload("res://scripts/game_state.gd")
const Fire = preload("res://scripts/fire_case.gd")
var checks := 0
var errors: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: errors.append(label); push_error(label)
func run() -> void:
	var state := State.new()
	state.role = "fire"
	var incident := Fire.new()
	incident.begin("campaign")
	for step: String in Fire.BASICS: incident.complete_step(step)
	incident.check_recon("exterior")
	incident.check_recon("door")
	incident.connect_water()
	incident.add_hose_point(Vector3(3, 0.06, 44))
	incident.choose_tactic("interior")
	incident.spray("front", 1.5)
	incident.tick(4, true)
	state.fire = incident.to_dict()
	state.fire_campaign = incident.to_dict()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict(), "", true, true))
	var loaded := State.new()
	check(loaded.restore(saved), "Actual schema5 JSON brand/save roundtrip")
	check(loaded.fire.cells == saved.fire.cells and loaded.fire.hose_points == saved.fire.hose_points, "Heat/burned/wet and real hose route retained")
	check(loaded.fire.victim == saved.fire.victim and loaded.fire.oxygen == saved.fire.oxygen and loaded.fire.water_used == saved.fire.water_used, "Victim/air/water conserved")
	check(loaded.fire_campaign == saved.fire_campaign, "Campaign incident independent from repeated lesson")
	var baseline := loaded.to_dict()
	var bad: Dictionary = saved.duplicate(true)
	bad.fire.cells[0].fuel = 99
	check(not loaded.restore(bad), "Impossible fuel refused")
	check(loaded.to_dict() == baseline, "Rejected fire snapshot never partially overwrites state")
	bad = saved.duplicate(true)
	bad.role = "police"
	check(not loaded.restore(bad), "Active fire phase cannot attach to police avatar")
	bad = saved.duplicate(true)
	bad.fire_campaign.mode = "lesson"
	check(not loaded.restore(bad), "Lesson cannot replace campaign incident archive")
	for revision in [1, 2, 3, 4]:
		var old := State.new().to_dict()
		old.schema = revision
		old.erase("fire")
		old.erase("fire_campaign")
		check(loaded.restore(JSON.parse_string(JSON.stringify(old))), "Prior save schema%d migrates with empty fire" % revision)
		check(loaded.fire.is_empty() and loaded.fire_campaign.is_empty(), "Prior save starts without invented incident")
	var path := "user://validation-fire-state.json"
	check(state.save_to(path), "Atomic actual fire file")
	check(loaded.load_from(path), "Actual fire file reload")
	check(loaded.fire == saved.fire, "Persisted exact changing fire snapshot")
	check(state.save_to(path), "Validated fire recovery backup")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	check(loaded.load_from(path), "Damaged primary uses validated fire backup")
	check(loaded.fire == saved.fire, "Backup retains burned/wet incident")
	var prepared: Dictionary = state.fire.duplicate(true)
	for outcome: String in ["careful", "partial"]:
		var finished := Fire.new()
		finished.restore(prepared)
		if outcome == "careful":
			for id: String in ["front", "origin", "side"]:
				for index in range(8):
					finished.spray(id, 0.5)
					finished.tick(0.5)
			finished.pickup_victim()
			finished.rescue_victim()
		finished.finish(outcome == "partial")
		state.fire = finished.to_dict()
		state.fire_campaign = finished.to_dict()
		check(finished.result == outcome, "Actual completed " + outcome)
		check(state.save_to(path), "Completed " + outcome + " actual full-precision file")
		check(loaded.load_from(path), "Completed " + outcome + " score survives JSON int-to-float conversion")
		var restored := Fire.new()
		check(restored.restore(loaded.fire) and restored.result == outcome, "Completed " + outcome + " model/score restore")
		check(state.save_to(path), "Completed " + outcome + " validated backup")
		file = FileAccess.open(path, FileAccess.WRITE)
		file.store_string("{broken")
		file.close()
		check(loaded.load_from(path) and loaded.fire.result == outcome, "Completed " + outcome + " damaged primary recovery")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")
	print("SCENE112_FIRE_STATE_OK checks=", checks) if errors.is_empty() else print("SCENE112_FIRE_STATE_FAIL ", errors)
	quit(0 if errors.is_empty() else 1)
