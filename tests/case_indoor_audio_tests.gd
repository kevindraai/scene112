extends SceneTree
## Context stubs isolate weather routing; this is not a product playthrough.
const Director = preload("res://scripts/audio_director.gd")
const FireModel = preload("res://scripts/fire_case.gd")
var failures := 0

class WeatherVehicleStub extends Node3D:
	var speed := 0.0

class WeatherDistrictStub extends Node3D:
	var objects: Dictionary = {}

class WeatherContext extends Node3D:
	var active := true
	var paused := false
	var state := {"condition": "day", "occupied_vehicle": ""}
	var police_model := {"mode": "none", "observations": []}
	var menu_items := VBoxContainer.new()
	var officer := CharacterBody3D.new()
	var district := WeatherDistrictStub.new()
	var at := Vector3(4, 0, 31)
	func _ready() -> void:
		add_child(officer)
		add_child(district)
		add_child(menu_items)
		for id: String in ["police_car", "fire_truck"]:
			var car := WeatherVehicleStub.new()
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
	director.settings_path = "user://isolated-case-indoor-audio.json"
	app.add_child(director)
	director.setup(app)
	await process_frame
	director.set_process(false)
	app.state.condition = "rain"
	app.at = Vector3(-2, 0, 48)
	var rain: AudioStreamPlayer3D = director._ambience.rain
	director._process(0.5)
	check(rain.playing and rain.volume_db > -20, "Huis 24 exterior still routes outdoor rain")
	var model := FireModel.new()
	model.begin("campaign")
	director.update_fire(model.to_dict(), app.at, true, false)
	director._process(0.5)
	check(rain.volume_db < -30, "actual fresh fire-controller inside flag attenuates Huis 24 rain")
	var rain_id: int = rain.get_stream_playback().get_instance_id()
	director.update_fire(model.to_dict(), app.at, false, false)
	director._process(0.5)
	check(rain.volume_db > -20 and rain.get_stream_playback().get_instance_id() == rain_id, "leaving fire interior restores gain without restarting rain")
	director.update_fire({"mode": "none"}, app.at, false, false)
	director.update_investigation("scene", false, app.at, true)
	director._process(0.5)
	check(rain.volume_db < -30, "inside evidence context attenuates house rain without a fixed coordinate box")
	director.update_investigation("scene", false, app.at)
	director._process(0.5)
	check(rain.volume_db > -20, "backward-compatible three-argument scene call uses outdoor context")
	director.update_investigation("office", false, app.at)
	director._process(0.5)
	check(rain.volume_db < -30, "explicit office context is indoors outside original station coordinates")
	director.update_investigation("none", false, app.at)
	director._process(0.5)
	check(rain.volume_db > -20, "inactive case clears indoor context instead of retaining obsolete room state")
	await director.shutdown()
	app.queue_free()
	await process_frame
	await process_frame
	print("SCENE112_CASE_INDOOR_AUDIO_TESTS_", "OK" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
