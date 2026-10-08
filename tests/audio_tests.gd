extends SceneTree
## Playback/mixer logic runs on Dummy too; this does not prove audible quality.
const Director = preload("res://scripts/audio_director.gd")
var failures := 0
var director: Node
const TEST_PATH := "user://unit-audio-settings.json"

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(TEST_PATH + suffix)
	director = Director.new()
	director.settings_path = TEST_PATH
	root.add_child(director)
	await process_frame
	director.set_process(false)
	check(director.status().missing.is_empty() and director.status().waves_loaded == Director.FILES.size(), "all original audio assets import and load")
	for bus: String in Director.BUSES:
		check(AudioServer.get_bus_index(bus) >= 0, "mixer bus exists: " + bus)
	var maximum_peak := 0.0
	var every_wave_valid := true
	for name: String in Director.FILES:
		var stream: AudioStreamWAV = director._streams.get(name)
		if stream == null:
			every_wave_valid = false
			continue
		every_wave_valid = every_wave_valid and stream.mix_rate == 22050 and is_finite(stream.get_length()) and stream.get_length() >= 0.1
		var raw := AudioStreamWAV.load_from_file("res://assets/audio/" + name + ".wav")
		if raw != null and raw.format == AudioStreamWAV.FORMAT_16_BITS:
			# Import may use QOA; verify original PCM separately from successful
			# imported-resource loading. Composer verifies every source sample.
			var samples := raw.data
			for offset in range(0, samples.size() - 1, 514):
				var sample := samples.decode_s16(offset) / 32768.0
				every_wave_valid = every_wave_valid and is_finite(sample)
				maximum_peak = maxf(maximum_peak, absf(sample))
	check(every_wave_valid and maximum_peak > 0.05 and maximum_peak <= 0.73, "imported wave metadata and source PCM sampled peaks are finite, nonempty and unclipped")
	var before: Dictionary = director.get_settings()
	var invalid := before.duplicate(true)
	invalid.volumes.Music = NAN
	check(not director.apply_settings(invalid, false) and director.get_settings() == before, "invalid volume update is atomic")
	invalid = before.duplicate(true)
	invalid.volumes.erase("Vehicle")
	check(not director.apply_settings(invalid, false), "incomplete bus settings cannot replace current mix")
	invalid = before.duplicate(true)
	invalid.schema = true
	check(not director.apply_settings(invalid, false), "schema is numeric rather than a boolean")
	check(not director.set_volume("invented", 0.5, false) and not director.set_volume("Music", INF, false), "unknown buses and nonfinite levels are rejected")
	check(director.set_volume("Music", 0.27) and director.set_volume("Ambience", 0.36), "user mixer values are saved")
	var stored: Dictionary = director.get_settings()
	director.set_volume("Music", 0.9, false)
	check(director.load_settings() and director.get_settings() == stored, "audio settings reload across a changed in-memory mix")
	check(FileAccess.file_exists(TEST_PATH + ".bak"), "previous validated audio settings have a recovery copy")
	director.set_muted(true, false)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "global mute reaches actual mixer")
	director.set_muted(false, false)
	director.set_volume("SFX", 0, false)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "zero channel volume is actually silent")
	director.set_volume("SFX", 0.7, false)
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "restored channel value unmutes without changing the master preference")
	check(not director.begin_voice(NAN) and director.begin_voice(1), "foreground duck timing is finite and bounded")
	director._process(0.25)
	check(director.status().duck_db < -5, "foreground speech/radio smoothly ducks background buses")
	director._process(3)
	check(director.status().voice_seconds == 0 and absf(float(director.status().duck_db)) < 0.1, "background mix recovers after foreground cue")
	for theme: String in ["menu", "surveillance_a", "surveillance_b", "academy", "investigation", "urgency", "silent"]:
		check(director.set_theme(theme), "actual score asset supports " + theme)
		# AudioServer mixes on another thread; each selection is a real transition.
		await create_timer(0.06).timeout
	check(not director.set_theme("unlicensed") and not director.cue("unknown"), "undefined themes and cues fail gracefully")
	director.set_theme("surveillance_a")
	director._music_finished(director._target_music)
	check(director.status().quiet_until > 20, "surveillance schedules a substantial score-free passage")
	director._process(40)
	check(director.status().theme == "surveillance_b", "next surveillance passage uses the second original variation")
	var accepted := 0
	for index in range(30):
		if director.cue("ui"): accepted += 1
	check(accepted == Director.MAX_ONESHOTS and director.status().oneshots == Director.MAX_ONESHOTS, "cue bursts play up to the cap without cutting active voices")
	check(not director.set_siren(true, "invented") and director.set_siren(true, "police_car"), "siren routing recognizes actual service vehicles")
	check(director.status().driver is String and not director.status().driver.is_empty(), "current audio driver is reported without requiring hardware")
	director.set_muted(false, false)
	# Let the actual short WAV finish before checking that voice slots recover.
	await create_timer(0.25).timeout
	director._prune_oneshots()
	check(director.status().oneshots == 0, "completed voices release their slots for subsequent cues")
	var released_loop: WeakRef = weakref(director._streams.wind)
	# Start positional voices immediately before quit to exercise their queued
	# physics-frame start, including the native headless failure condition.
	director._ambience.wind.play()
	director._ambience.traffic.play()
	director.cue("interaction", Vector3.ZERO)
	await director.shutdown()
	check(director.status().shutdown_synchronized and director.status().shutdown_mixes >= 2, "shutdown observes two real mixer transitions before completion")
	check(released_loop.get_ref() == null, "queued positional loop and its AudioServer playback release their WAV")
	check(not director.cue("ui") and not director.set_theme("urgency") and not director.begin_voice(1) and not director.set_siren(true, "police_car") and director.status().waves_loaded == 0, "shutdown refuses late events and leaves assets released")
	var repeated_at := Time.get_ticks_msec()
	await director.shutdown()
	check(Time.get_ticks_msec() - repeated_at < 100, "completed shutdown can be called again without waiting for more mixes")
	director.queue_free()
	await process_frame
	await process_frame
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(TEST_PATH + suffix)
	print("SCENE112_AUDIO_TESTS_", "OK" if failures == 0 else "FAIL", " failures=", failures, " sampled_peak=", maximum_peak)
	quit(0 if failures == 0 else 1)
