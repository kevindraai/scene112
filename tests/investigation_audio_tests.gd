extends SceneTree
## Real resource/mixer tests with isolated context inputs; no voiced dialogue claim.
const Director = preload("res://scripts/audio_director.gd")
var failures := 0

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var director := Director.new()
	director.settings_path = "user://isolated-investigation-audio.json"
	root.add_child(director)
	await process_frame
	director.set_process(false)
	check(director.status().waves_loaded == 40 and director.status().missing.is_empty(), "all 40 original sounds load with investigation routing")
	check(director._office_clock == null and director.get_child_count() == 13, "ordinary play allocates no investigation clock or fire nodes")
	var at := Vector3(0, 0, -5)
	check(director.update_investigation("scene", false, at), "investigation scene context is accepted")
	director._process(0.1)
	check(director.status().theme == "investigation", "existing sparse investigation score is reused")
	var target: int = director._target_music
	var playback: int = director._music[target].get_stream_playback().get_instance_id()
	for index in range(30):
		director.update_investigation("scene", false, at)
		director._process(0.01)
	check(director._target_music == target and director._music[target].get_stream_playback().get_instance_id() == playback, "repeated scene updates never restart the score")
	var before: Dictionary = director.status()
	check(not director.update_investigation("guilty", false, at) and director.status() == before, "truth/guilt category cannot change audio state")
	check(not director.update_investigation("office", true, Vector3(NAN, 0, 0)) and director.status() == before, "nonfinite location is rejected atomically")
	check(director.update_investigation("board", false, at), "board shares minimal investigation mood")
	director._process(0.1)
	check(director._target_music == target, "case board is not a new cinematic or truth cue")
	director.update_investigation("office", false, at)
	director._process(0.1)
	check(director._office_clock != null and director._office_clock.playing and director.get_child_count() == 14, "office starts exactly one subtle positional clock")
	check(director._office_clock.volume_db < -31, "clock fades in below quiet authored gain")
	var clock_node_id: int = director._office_clock.get_instance_id()
	for index in range(20): director.update_investigation("office", false, at)
	check(director.get_child_count() == 14 and director._office_clock.get_instance_id() == clock_node_id, "office updates keep bounded loop capacity")
	await create_timer(0.08).timeout
	for cue: String in ["evidence_paper", "evidence_bag", "evidence_camera", "office_chair"]:
		check(director.cue(cue, at), "actual original object cue plays: " + cue)
	check(director.status().oneshots == 4, "object interactions create finite spatial voices")
	director.update_investigation("office", true, at)
	director._process(0.1)
	check(director.status().theme == "silent", "interview silences music without any reliability or confession input")
	for index in range(20):
		director.update_investigation("office", true, at)
		director._process(0.1)
	check(director.status().duck_db < -8 and not director._office_clock.playing, "interview focus ducks ambience and fades clock distraction")
	check(not director.cue("truth") and not director.cue("lie") and not director.cue("voice"), "no truth signal or nonexistent speech cue is exposed")
	director.update_investigation("office", false, at + Vector3(2, 0, 0))
	director._process(0.1)
	check(director._office_clock.playing and director._office_clock.global_position == at + Vector3(3.4, 1.8, 0), "office resume routes real loop to supplied position")
	await create_timer(0.1).timeout
	director.update_investigation("none", false, at)
	for index in range(15): director._process(0.1)
	check(not director._office_clock.playing and director.status().theme == "silent", "explicit inactive context fades investigation layer")
	director.update_investigation("scene", false, at)
	director._process(1.1)
	check(not director.status().investigation_live and director.status().theme == "silent", "stale context falls silent without a controller update")
	await create_timer(0.1).timeout
	var released_clock: WeakRef = weakref(director._streams.office_clock_loop)
	director.update_investigation("office", false, at)
	director._process(0.01)
	await director.shutdown()
	check(released_clock.get_ref() == null and director.status().shutdown_synchronized, "queued clock/WAV is released by preserved native mix-aware shutdown")
	check(not director.update_investigation("office", true, at) and not director.cue("evidence_camera", at), "late investigation/object events cannot restart shutdown audio")
	director.queue_free()
	await process_frame
	await process_frame
	print("SCENE112_INVESTIGATION_AUDIO_TESTS_", "OK" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
