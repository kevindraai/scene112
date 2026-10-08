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
	ledger.start(112)
	ledger.tick(25.0)
	ledger.accept()
	var driving := State.new()
	driving.role = "fire"
	driving.occupied_vehicle = "fire_truck"
	driving.vehicles.fire_truck = {"position": [42.0, 0.1, -28.0], "yaw": -1.2}
	driving.dispatch = ledger.to_dict()
	var seated := State.new()
	check(seated.restore(driving.to_dict()) and seated.occupied_vehicle == "fire_truck", "restore seated role and vehicle state")
	check(seated.dispatch.incident.phase == "accepted", "restore accepted incident and chronology")
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
