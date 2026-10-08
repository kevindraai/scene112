extends SceneTree
## Context stubs isolate weather routing; this is not a product playthrough.
const Director = preload("res://scripts/audio_director.gd")
var failures := 0

class WeatherVehicleFixture extends Node3D:
	var speed := 0.0

class WeatherDistrictFixture extends Node3D:
	var objects: Dictionary = {}

class WeatherContext extends Node3D:
	var active := true
	var paused := false
	var state := {"condition": "day", "occupied_vehicle": ""}
	var police_model := {"mode": "none", "observations": []}
	var menu_items := VBoxContainer.new()
	var officer := CharacterBody3D.new()
	var district := WeatherDistrictFixture.new()
	var at := Vector3(4, 0, 31)
	func _ready() -> void:
		add_child(officer)
		add_child(district)
		add_child(menu_items)
		for id: String in ["police_car", "fire_truck"]:
			var car := WeatherVehicleFixture.new()
			district.add_child(car)
			district.objects[id] = car
	func _controlled_position() -> Vector3:
		return at

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var app := WeatherContext.new()
	root.add_child(app)
	var director := Director.new()
	director.settings_path = "user://isolated-weather-audio.json"
	app.add_child(director)
	director.setup(app)
	await process_frame
	director.set_process(false)
	check(director.status().waves_loaded == 24 and director.status().missing.is_empty(), "weather uses existing complete original audio set")
	var rain: AudioStreamPlayer3D = director._ambience.rain
	var birds: AudioStreamPlayer3D = director._ambience.birds
	check(director.get_child_count() == 13, "weather adds only one bounded positional loop")
	director._process(0.5)
	await create_timer(0.06).timeout
	check(not rain.playing and birds.playing, "day outdoors has birds and no rain")
	var day_volume := birds.volume_db
	var theme: String = director.status().theme
	var music_id: int = director._music[director._target_music].get_stream_playback().get_instance_id()
	app.state.condition = "dusk"
	director._process(0.5)
	check(birds.playing and birds.volume_db < day_volume - 5, "dusk lowers actual bird loop through existing fade")
	check(director.status().theme == theme and director._music[director._target_music].get_stream_playback().get_instance_id() == music_id, "weather does not restart the current soundtrack")
	app.state.condition = "rain"
	director._process(0.1)
	check(rain.playing and rain.volume_db > -70 and rain.volume_db < -17, "rain begins with a short gain fade")
	for index in range(10): director._process(0.1)
	await create_timer(0.08).timeout
	check(not birds.playing and rain.playing, "rain condition fades birds out and keeps the actual rain WAV loop")
	check(rain.global_position == app.at + Vector3(0, 3, 0), "surrounding rain follows actual controlled position")
	var outside_volume := rain.volume_db
	var rain_id: int = rain.get_stream_playback().get_instance_id()
	app.at = Vector3(0, 0, -5)
	director._process(0.5)
	check(rain.playing and rain.volume_db < outside_volume - 10, "inside bureau attenuates existing outdoor rain")
	check(rain.get_stream_playback().get_instance_id() == rain_id, "crossing a doorway changes gain without resetting the rain loop")
	app.at = Vector3(25, 0, -5)
	director._process(0.5)
	check(rain.volume_db < -30, "kazerne interior also attenuates rain")
	app.at = Vector3(4, 0, 31)
	director._process(0.5)
	check(rain.volume_db > -20, "return outdoors restores surrounding rain smoothly")
	app.paused = true
	for index in range(15): director._process(0.1)
	check(not rain.playing, "pausing fades and stops weather loop")
	app.paused = false
	director._process(0.2)
	check(rain.playing, "resume restarts saved rain condition")
	app.state.condition = "day"
	for index in range(15): director._process(0.1)
	check(not rain.playing and birds.playing, "day restored from current state ends rain and returns birds")
	app.state.erase("condition")
	director._process(0.2)
	check(not rain.playing, "missing legacy weather field defaults to quiet rain state")
	await create_timer(0.1).timeout
	await director.shutdown()
	check(director.status().shutdown_synchronized and director.status().shutdown_mixes >= 2, "native mix-aware shutdown is retained")
	app.queue_free()
	await process_frame
	await process_frame
	print("SCENE112_WEATHER_AUDIO_TESTS_", "OK" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
