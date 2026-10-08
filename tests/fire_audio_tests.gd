extends SceneTree
## Audio input fixtures isolate finite state/routing; they are not gameplay grades.
const Director = preload("res://scripts/audio_director.gd")
const Fire = preload("res://scripts/fire_case.gd")
var failures := 0
var director: Node
const TEST_SETTINGS := "user://fire-audio-unit.json"

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	director = Director.new()
	director.settings_path = TEST_SETTINGS
	root.add_child(director)
	await process_frame
	director.set_process(false)
	check(director.status().waves_loaded == Director.FILES.size() and Director.FILES.size() == 40 and director.status().missing.is_empty(), "all 40 original M2–M5 resources import")
	check(director.status().fire_sources == 0, "ordinary M2 startup allocates no fire sources")
	var model := Fire.new()
	model.begin("campaign")
	var at := Vector3(-2, 0.1, 44)
	var state: Dictionary = model.to_dict()
	check(director.update_fire(state, at, false, false), "real FireCase snapshot is accepted")
	check(director.status().fire_sources == 3 and director.get_child_count() == 18, "only three fire sources plus nozzle and breathing are allocated")
	var count: int = director.get_child_count()
	for index in range(50): director.update_fire(state, at, false, false)
	check(director.get_child_count() == count, "repeated state updates do not accumulate audio nodes")
	var before: Dictionary = director._fire.duplicate(true)
	var bad := state.duplicate(true)
	bad.cells[1].heat = NAN
	check(not director.update_fire(bad, at, true, true) and director._fire == before, "nonfinite heat cannot partially change routing")
	bad = state.duplicate(true)
	bad.cells[0].pos = [INF, 0, 0]
	check(not director.update_fire(bad, at, false, false), "nonfinite source coordinates are rejected")
	bad = state.duplicate(true)
	bad.cells.pop_back()
	check(not director.update_fire(bad, at, false, false), "wrong cell count cannot expand spatial voices")
	bad = state.duplicate(true)
	bad.cells[1].id = "front"
	check(not director.update_fire(bad, at, false, false), "duplicate cell identity is rejected")
	bad = state.duplicate(true)
	bad.oxygen = -1
	check(not director.update_fire(bad, at, false, false), "negative oxygen is rejected")
	bad = state.duplicate(true)
	bad.water_liters = 321
	check(not director.update_fire(bad, at, false, false), "out-of-range water is rejected")
	bad = state.duplicate(true)
	bad.victim.exposure = INF
	check(not director.update_fire(bad, at, false, false), "nonfinite victim exposure is rejected")
	check(not director.update_fire(state, Vector3(NAN, 0, 0), false, false), "nonfinite live listener/nozzle pose is rejected")
	# Prepare the actual case through its APIs before using its active snapshot.
	for step in Fire.BASICS: model.complete_step(step)
	model.check_recon("exterior")
	model.check_recon("door")
	model.connect_water()
	model.choose_tactic("defensive")
	model.add_hose_point(Vector3(4, 0.04, 44))
	state = model.to_dict()
	check(director.update_fire(state, at, true, true), "active real case routes nozzle and protected breathing")
	director._process(0.1)
	check(director._water_source.playing and director._breath_source.playing, "actual water and breathing WAV players start")
	for index in range(3):
		var pos: Array = state.cells[index].pos
		var wanted := Director.FIRE_SITE + Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		check(director._fire_sources[index].global_position == wanted, "fire source follows persistent cell world position " + str(index))
	var shots: int = director.status().oneshots
	for index in range(30): director.update_fire(state, at, true, true)
	check(director.status().oneshots == shots, "held spraying does not spam lever cues")
	var water_gain: float = director._water_source.volume_db
	director.update_fire(state, at, false, false)
	director._process(0.1)
	check(director._water_source.volume_db < water_gain and director._water_source.playing, "stopping a nozzle begins a short fade rather than a hard cut")
	for index in range(8):
		director.update_fire(state, at, false, false)
		director._process(0.1)
	check(not director._water_source.playing and not director._breath_source.playing, "water and breathing cease after their fades")
	var low_risk: float = director.status().fire_danger
	var risk := state.duplicate(true)
	for cell in risk.cells: cell.heat = 1.0
	risk.oxygen = 10
	risk.victim.exposure = 90
	for index in range(20):
		director.update_fire(risk, at, true, false)
		director._process(0.15)
	check(director.status().fire_danger > low_risk + 0.4 and director.status().theme == "fire_risk", "heat, victim exposure and low oxygen raise musical risk")
	var quiet := state.duplicate(true)
	for cell in quiet.cells: cell.heat = 0.1
	quiet.victim.exposure = 0
	quiet.oxygen = 100
	for index in range(20):
		director.update_fire(quiet, at, false, false)
		director._process(0.15)
	check(director.status().theme == "fire_sparse" and director.status().fire_danger < 0.15, "safe cooler conditions return to sparse musical variation")
	director._music_finished(director._target_music)
	check(director.status().quiet_until > director._clock + 20, "fire score includes a substantial additional silent passage")
	await create_timer(0.08).timeout
	var rescued := quiet.duplicate(true)
	rescued.victim.status = "rescued"
	shots = director.status().oneshots
	director.update_fire(rescued, at, false, false)
	check(director.status().oneshots == shots + 1, "a new rescue transition creates one original outcome cue")
	for index in range(15): director.update_fire(rescued, at, false, false)
	check(director.status().oneshots == shots + 1, "same rescue snapshot does not repeat its cue")
	var done := rescued.duplicate(true)
	done.phase = "completed"
	done.actions.append({"kind": "handover", "time": done.clock})
	shots = director.status().oneshots
	director.update_fire(done, at, false, false)
	check(director.status().oneshots == shots + 1, "handover is derived from a completed model transition")
	director._process(0.3)
	check(not director.status().fire_live, "completed incident ends adaptive fire score")
	director.update_fire({"mode": "none"}, at, false, false)
	shots = director.status().oneshots
	director.update_fire(done, at, false, false)
	check(director.status().oneshots == shots, "loading a completed dossier emits no historic success cue")
	director.update_fire({"mode": "none"}, at, false, false)
	director.update_fire(quiet, at, false, false)
	var withdrawn := quiet.duplicate(true)
	withdrawn.phase = "completed"
	withdrawn.actions.append({"kind": "withdraw", "time": withdrawn.clock})
	director.update_fire(withdrawn, at, false, false)
	check(director._oneshots.back().stream == director._streams.withdraw, "safe withdrawal selects its own measured cue instead of the rescue cue")
	director.update_fire(quiet, at, false, false)
	director._process(1.1)
	check(not director.status().fire_live, "missing controller updates safely fade stale incident audio")
	await create_timer(0.1).timeout
	var released_fire: WeakRef = weakref(director._streams.fire_loop)
	var released_water: WeakRef = weakref(director._streams.water_loop)
	var released_breath: WeakRef = weakref(director._streams.air_breathing)
	await director.shutdown()
	check(director.status().shutdown_synchronized and director.status().shutdown_mixes >= 2, "future extension preserves reviewed mix-aware native shutdown")
	check(not director.update_fire(state, at, true, true) and director.status().waves_loaded == 0, "shutdown rejects late fire events and releases all streams")
	director.queue_free()
	await process_frame
	await process_frame
	check(released_fire.get_ref() == null and released_water.get_ref() == null and released_breath.get_ref() == null, "fire, nozzle and breathing WAVs release after synchronized shutdown and owner disposal")
	print("SCENE112_FIRE_AUDIO_TESTS_", "OK" if failures == 0 else "FAIL", " failures=", failures, " driver=", AudioServer.get_driver_name())
	quit(0 if failures == 0 else 1)
