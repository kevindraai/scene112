extends SceneTree

const State = preload("res://scripts/game_state.gd")
var failures := 0

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	else: print("PASS: " + label)

func _initialize() -> void:
	var state := State.new()
	var old_save := {"schema": 1, "equipment": true, "radio_checked": true,
		"academy_visits": 1, "position": [0.0, 0.1, 6.0], "sensitivity": 0.003}
	var migrated := State.new()
	check(migrated.restore(old_save) and migrated.role == "police", "M0 save migrates to default police duty")
	check(migrated.vehicles.size() == 2 and migrated.occupied_vehicle == "", "migration supplies parked vehicles")
	check(not state.equipment and not state.radio_checked, "new duty starts unprepared")
	state.equipment = true
	state.radio_checked = true
	state.academy_visits = 2
	state.player_position = Vector3(8, 0.2, -4)
	var path := "user://unit-test-save.json"
	check(state.save_to(path), "write versioned save")
	var restored := State.new()
	check(restored.load_from(path), "read versioned save")
	check(restored.to_dict() == state.to_dict(), "save roundtrip preserves position and progress")
	var original := restored.to_dict()
	var inconsistent := state.to_dict()
	inconsistent.equipment = false
	check(not restored.restore(inconsistent), "reject radio progress without equipment")
	inconsistent = state.to_dict()
	inconsistent.radio_checked = false
	check(not restored.restore(inconsistent), "reject academy progress without radio readiness")
	var invalid_vehicle := state.to_dict()
	invalid_vehicle.vehicles.police_car.position = [NAN, 0, 0]
	check(not restored.restore(invalid_vehicle), "reject nonfinite vehicle position")
	invalid_vehicle = state.to_dict()
	invalid_vehicle.vehicles.police_car.yaw = INF
	check(not restored.restore(invalid_vehicle), "reject nonfinite vehicle rotation")
	invalid_vehicle = state.to_dict()
	invalid_vehicle.occupied_vehicle = "unknown"
	check(not restored.restore(invalid_vehicle), "reject unknown occupied vehicle")
	invalid_vehicle = state.to_dict()
	invalid_vehicle.dispatch = {"schema": 99}
	check(not restored.restore(invalid_vehicle), "reject invalid incident save")
	check(restored.to_dict() == original, "vehicle/incident rejection leaves duty untouched")
	var ledger := preload("res://scripts/dispatch.gd").new()
	ledger.start(112, "fire")
	ledger.tick(25.0)
	ledger.accept()
	var driving := State.new()
	driving.role = "fire"
	driving.occupied_vehicle = "fire_truck"
	driving.vehicles.fire_truck = {"position": [42.0, 0.1, -28.0], "yaw": -1.2}
	driving.dispatch = ledger.to_dict()
	var outside := preload("res://scripts/outside_fire_case.gd").new()
	var fire_at: Array = ledger.incident.position
	outside.begin(ledger.serial, int(ledger.incident.variant), Vector3(fire_at[0], fire_at[1], fire_at[2]))
	driving.outside_fire = outside.to_dict()
	var seated := State.new()
	check(seated.restore(driving.to_dict()) and seated.occupied_vehicle == "fire_truck", "restore seated role and vehicle state")
	check(seated.dispatch.incident.phase == "accepted", "restore accepted incident and chronology")
	var schema_two := state.to_dict()
	schema_two.schema = 2
	for key in ["police", "police_campaign", "police_draft", "police_practice", "campaign_stage", "course_passes"]: schema_two.erase(key)
	var upgrade := State.new()
	check(upgrade.restore(schema_two) and upgrade.police.is_empty(), "M1 save migrates to current schema without phantom case")
	var schema_three := state.to_dict()
	schema_three.schema = 3
	schema_three.erase("condition")
	schema_three.erase("graphics_quality")
	check(upgrade.restore(schema_three) and upgrade.condition == "day" and upgrade.graphics_quality == "portable", "M2 save migrates with deterministic portable day settings")
	var visual_state := state.to_dict()
	visual_state.condition = "rain"
	visual_state.graphics_quality = "high"
	check(upgrade.restore(visual_state) and upgrade.condition == "rain" and upgrade.graphics_quality == "high", "world conditions and quality restore with gameplay")
	var visual_before := upgrade.to_dict()
	visual_state.condition = "invalid"
	check(not upgrade.restore(visual_state) and upgrade.to_dict() == visual_before, "unknown condition rejected atomically")
	visual_state.condition = "day"
	visual_state.graphics_quality = "invalid"
	check(not upgrade.restore(visual_state) and upgrade.to_dict() == visual_before, "unknown quality rejected atomically")
	var case_model := preload("res://scripts/police_case.gd").new()
	case_model.begin("campaign")
	for action in ["equipment", "radio", "enter", "drive", "exit"]:
		case_model.tick(1.0)
		case_model.complete_step(action)
	for cone in [Vector3(-26, 0, 15), Vector3(-28, 0, 17), Vector3(-26, 0, 19)]: case_model.place_cone(cone)
	for observation in ["damage", "marks", "road"]: case_model.record_observation(observation)
	case_model.speak("lotte", "open")
	case_model.speak("bram", "open")
	var correct_cards: Array = []
	var draft_rows: Array = []
	for card in case_model.report_cards():
		if card.id != "conclusion_guilt": correct_cards.append({"id": card.id, "category": card.category})
		draft_rows.append({"id": card.id, "category": card.category, "included": card.id != "conclusion_guilt"})
	case_model.submit_report(correct_cards)
	var nested := State.new()
	nested.police = case_model.to_dict()
	nested.police_campaign = nested.police.duplicate(true)
	nested.police_draft = draft_rows
	nested.campaign_stage = 1
	nested.course_passes = ["basis", "intake"]
	var nested_restore := State.new()
	check(nested_restore.restore(nested.to_dict()) and nested_restore.campaign_stage == 1, "restore police chapter, sources and PV draft")
	check(nested_restore.police_draft == draft_rows and nested_restore.police_campaign.mode == "campaign", "draft classifications and campaign dossier survive")
	var invalid_case := nested.to_dict()
	invalid_case.police.report_score.score = 100000
	check(not nested_restore.restore(invalid_case), "reject forged case assessment")
	invalid_case = nested.to_dict()
	invalid_case.police_draft[0].id = "fabricated"
	check(not nested_restore.restore(invalid_case), "reject PV draft referencing missing evidence")
	invalid_case = nested.to_dict()
	invalid_case.course_passes = ["basis", "basis"]
	check(not nested_restore.restore(invalid_case), "reject duplicate course completion")
	invalid_case = nested.to_dict()
	invalid_case.campaign_stage = NAN
	check(not nested_restore.restore(invalid_case), "reject nonfinite campaign progress")
	check(not restored.restore({"schema": 99}), "reject unsupported save version")
	check(restored.to_dict() == original, "failed restore does not partially mutate state")
	var malformed := state.to_dict()
	malformed.position = ["x", 0, 0]
	check(not restored.restore(malformed), "reject nonnumeric coordinates")
	malformed.position = [INF, 0, 0]
	check(not restored.restore(malformed), "reject nonfinite coordinates")
	malformed.position = [0, 0, 9000]
	check(not restored.restore(malformed), "reject out-of-world coordinates")
	malformed = state.to_dict()
	malformed.academy_visits = NAN
	check(not restored.restore(malformed), "reject nonfinite progress")
	malformed.academy_visits = 0.5
	check(not restored.restore(malformed), "reject fractional progress")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Test directory is not writable")
		quit(1)
		return
	file.store_string("{broken json")
	file.close()
	check(not restored.load_from(path), "corrupt save fails safely")
	check(restored.to_dict() == original, "corruption leaves active state intact")
	check(not restored.load_from("user://does-not-exist.json"), "missing save fails safely")
	check(state.save_to(path), "replace corrupt primary without promoting it to backup")
	state.academy_visits = 3
	check(state.save_to(path), "overwrite retains validated previous slot")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("broken primary")
	file.close()
	check(restored.load_from(path) and restored.academy_visits == 2, "recover previous slot after corrupt primary")
	DirAccess.remove_absolute(path)
	check(restored.load_from(path) and restored.academy_visits == 2, "recover previous slot after missing primary")
	DirAccess.remove_absolute(path + ".bak")
	DirAccess.remove_absolute(path)
	print("SCENE112_TESTS_", "OK" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
