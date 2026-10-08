extends SceneTree
const Director = preload("res://scripts/audio_director.gd")
var failures := 0
var checks := 0
class VehicleStub extends Node3D:
	var speed := 0.0
class DistrictStub extends Node3D:
	var objects: Dictionary = {}
class FreeApp extends Node3D:
	var active := true
	var paused := false
	var state := {"condition":"day", "occupied_vehicle":""}
	var police_model := {"mode":"none", "observations":[]}
	var menu_items := VBoxContainer.new()
	var officer := CharacterBody3D.new()
	var district := DistrictStub.new()
	var at := Vector3(4,0,31)
	func _ready() -> void:
		add_child(officer); add_child(district); add_child(menu_items)
		for id in ["police_car","fire_truck"]:
			var car := VehicleStub.new(); district.add_child(car); district.objects[id] = car
	func _controlled_position() -> Vector3: return at
func check(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: " + label)
func context(at: Vector3, kind := "noise", traffic: Array = [], conversation := false, settled := false, active := true) -> Dictionary:
	return {"active":active,"kind":kind,"at":at,"conversation":conversation,"settled":settled,"traffic":traffic}
func step(director: Node, data: Dictionary, seconds := 0.1, count := 1) -> void:
	var accepted := true
	for index in range(count):
		accepted = director.update_free_context(data) and accepted
		director._process(seconds)
	check(accepted,"finite context remains accepted through sequence")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var app := FreeApp.new(); root.add_child(app)
	var director := Director.new(); director.settings_path = "user://m5-test-settings.json"
	app.add_child(director); director.setup(app)
	await process_frame; director.set_process(false)
	check(director.status().waves_loaded == 40 and director.status().missing.is_empty(),"40 original WAVs import without missing resources")
	check(Director.BUSES.size() == 8 and Director.MAX_ONESHOTS == 10,"bus settings and original one-shot cap retained")
	check(director.get_child_count() == 13 and director._free_sources.is_empty(),"no free-duty source allocated before physical context")
	check(director.update_free_context(context(app.at,"none",[],false,false,false)),"explicit inactive context")
	check(director._free_sources.is_empty(),"inactive context stays allocation free")
	var invalids: Array = []
	for field in ["active","conversation","settled"]:
		var bad := context(app.at);bad[field]=1;invalids.append(bad)
	var bad := context(Vector3(NAN,0,0));invalids.append(bad)
	bad=context(app.at,"guilty");invalids.append(bad)
	bad=context(app.at);bad["reliability"]=1;invalids.append(bad)
	bad=context(app.at,"traffic",[{"at":app.at,"speed":INF}]);invalids.append(bad)
	bad=context(app.at,"traffic",[{"at":app.at,"speed":2.0},{"at":Vector3(0,NAN,0),"speed":2.0}]);invalids.append(bad)
	bad=context(app.at,"traffic",[{"at":app.at,"speed":2.0,"id":"extra"}]);invalids.append(bad)
	var excessive: Array=[]
	for index in range(17):excessive.append({"at":app.at,"speed":2.0})
	invalids.append(context(app.at,"traffic",excessive))
	for item in invalids:
		var before: Dictionary=director.status()
		check(not director.update_free_context(item) and before == director.status() and director._free_sources.is_empty(),"malformed context rejected without partial mutation")
	var noise := context(app.at)
	step(director,noise)
	await create_timer(0.12).timeout
	check(director._free_sources.size()==2 and director.get_child_count()==15,"exact two lazy spatial sources for free layer")
	var sound: AudioStreamPlayer3D=director._free_sources[0]
	check(sound.stream==director._streams.street_murmur and sound.bus=="Ambience" and sound.playing,"actual original nonvocal gathering stream routes positional ambience")
	check(sound.volume_db < -25 and sound.volume_db > -70,"quiet gathering fades in instead of hard gain jump")
	var identity: int=sound.get_instance_id()
	var playback: int=sound.get_stream_playback().get_instance_id()
	var music: int=director._music[director._target_music].get_stream_playback().get_instance_id()
	for index in range(80):
		director.update_free_context(noise);director._process(0.01)
	check(sound.get_instance_id()==identity and sound.get_stream_playback().get_instance_id()==playback and director.get_child_count()==15,"repeated updates retain nodes and continuous playback")
	check(director._music[director._target_music].get_stream_playback().get_instance_id()==music,"free context never resets surveillance score")
	var live_before: Dictionary=director._free_context.duplicate(true)
	var invalid_live := noise.duplicate(true)
	invalid_live.traffic=[{"at":app.at,"speed":4.0},{"at":Vector3(INF,0,0),"speed":4.0}]
	check(not director.update_free_context(invalid_live) and director._free_context==live_before and sound.get_stream_playback().get_instance_id()==playback,"malformed mixed payload cannot replace a live context or playback")
	step(director,context(app.at,"noise",[],true),0.1,8)
	check(not sound.playing and director.status().free_focus,"conversation fades out gathering ambience instead of covering dialogue")
	step(director,noise,0.1,3)
	await create_timer(0.1).timeout
	check(sound.playing and sound.stream==director._streams.street_murmur,"ending dialogue restores unchanged physical gathering context")
	var cars := [{"at":app.at+Vector3(10,0,0),"speed":4.0},{"at":app.at+Vector3(12,0,0),"speed":3.0},{"at":app.at+Vector3(80,0,0),"speed":8.0}]
	step(director,context(app.at,"noise",cars),0.1,4)
	await create_timer(0.1).timeout
	check(director._free_sources[1].stream==director._streams.civilian_passby and director._free_sources[1].bus=="Vehicle","passing civilian car uses original motor/tyre stream")
	check(director._free_sources[1].global_position.distance_to(cars[0].at+Vector3(0,.5,0))<0.1,"nearest traffic selected with noise still present")
	var moving_car: AudioStreamPlayer3D=director._free_sources[1]
	var low_pitch: float=moving_car.pitch_scale
	cars[0].speed=8.0
	step(director,context(app.at,"noise",cars),0.1,3)
	check(moving_car.pitch_scale>low_pitch and moving_car.pitch_scale<=1.6,"actual bounded traffic speed changes motor pitch smoothly")
	step(director,context(app.at,"noise",cars,false,true),0.1,8)
	await create_timer(0.1).timeout
	check(director._free_sources.size()==2 and sound.stream==director._streams.civilian_passby,"settled incident reuses pool for traffic without retaining noise")
	check(director._free_sources.all(func(source):return source.playing and source.bus=="Vehicle"),"at most two real passing cars after noise settles")
	var positions: Array=[]
	for source in director._free_sources:positions.append(source.global_position)
	cars.reverse()
	step(director,context(app.at,"traffic",cars),0.1,2)
	check(director._free_sources[0].global_position.distance_to(positions[0])<0.2 and director._free_sources[1].global_position.distance_to(positions[1])<0.2,"input array reordering does not swap audible car locations")
	var car_playback: int=director._free_sources[0].get_stream_playback().get_instance_id()
	step(director,context(app.at,"traffic",cars,true),0.1,5)
	check(director.status().free_focus and director.status().duck_db < -8,"conversation renews existing music/ambience focus duck without speech")
	check(director._free_sources[0].get_stream_playback().get_instance_id()==car_playback and director._free_sources[0].volume_db < -28,"talk lowers passing car gain without restarting it")
	app.paused=true
	step(director,context(app.at,"noise",cars,true),0.1,8)
	check(not director.status().free_context_live and director._free_sources.all(func(source):return not source.playing),"pause fades all free spatial loops")
	check(director.status().free_focus and director.status().duck_db < -8,"paused subtitled conversation keeps focus duck while world is quiet")
	app.paused=false
	step(director,context(app.at,"traffic",cars),0.1,5)
	await create_timer(0.1).timeout
	check(director._free_sources.all(func(source):return source.playing),"resume uses refreshed real traffic context")
	app.active=false
	step(director,context(app.at,"noise",cars,true),0.1,8)
	check(not director.status().free_focus and director._free_sources.all(func(source):return not source.playing),"inactive application cannot retain street noise or conversation focus")
	app.active=true
	step(director,context(app.at,"traffic",cars),0.1,2)
	await create_timer(0.1).timeout
	director._process(1.2)
	check(not director.status().free_context_live and not director.status().free_focus and director._free_sources.all(func(source):return not source.playing),"stale controller context expires and falls silent")
	var near_car := [{"at":app.at+Vector3(4,0,0),"speed":0.2}]
	step(director,context(app.at,"traffic",near_car),0.1,4)
	check(director._free_sources.all(func(source):return not source.playing),"nearly stationary car cannot start a new passing loop")
	near_car[0].speed=0.4
	step(director,context(app.at,"traffic",near_car),0.1,4)
	await create_timer(0.1).timeout
	var idle_car: AudioStreamPlayer3D=director._free_sources[0]
	check(idle_car.playing,"crossing start-speed threshold begins actual passing playback")
	var idle_playback: int=idle_car.get_stream_playback().get_instance_id()
	near_car[0].speed=0.2
	step(director,context(app.at,"traffic",near_car),0.1,5)
	check(idle_car.playing and idle_car.get_stream_playback().get_instance_id()==idle_playback,"speed hysteresis retains existing playback during slow movement")
	near_car[0].speed=0.1
	step(director,context(app.at,"traffic",near_car),0.1,8)
	check(not idle_car.playing,"stopping the car completes its short fade")
	near_car[0]={"at":app.at+Vector3(39,0,0),"speed":4.0}
	step(director,context(app.at,"traffic",near_car),0.1,4)
	check(not idle_car.playing,"car outside start radius does not start a distant loop")
	near_car[0].at=app.at+Vector3(37,0,0)
	step(director,context(app.at,"traffic",near_car),0.1,4)
	await create_timer(0.1).timeout
	check(idle_car.playing,"car entering audible radius starts without adding nodes")
	var distant_playback: int=idle_car.get_stream_playback().get_instance_id()
	near_car[0].at=app.at+Vector3(40,0,0)
	step(director,context(app.at,"traffic",near_car),0.1,5)
	check(idle_car.playing and idle_car.get_stream_playback().get_instance_id()==distant_playback,"distance hysteresis retains a receding nearby car")
	var before_jump := idle_car.global_position
	near_car[0].at=app.at-Vector3(20,0,0)
	step(director,context(app.at,"traffic",near_car),0.1,1)
	check(idle_car.global_position==before_jump and idle_car.playing,"replacing a distant car first fades old position without an audible teleport")
	step(director,context(app.at,"traffic",near_car),0.1,8)
	await create_timer(0.1).timeout
	check(idle_car.global_position.distance_to(near_car[0].at+Vector3(0,.5,0))<0.1 and idle_car.playing,"new physical car position starts after the prior fade")
	check(director.get_child_count()==15 and director._free_sources.all(func(source):return is_finite(source.volume_db) and is_finite(source.pitch_scale) and source.pitch_scale>0),"hysteresis never expands sources or produces nonfinite playback parameters")
	check(not director.cue("truth") and not director.cue("lie") and not director.cue("voice"),"no truth/guilt/person voice cue added")
	step(director,context(app.at,"traffic",cars),0.1,2)
	await create_timer(0.1).timeout
	var released: WeakRef=weakref(director._streams.civilian_passby)
	await director.shutdown()
	check(director.status().shutdown_synchronized and director.status().shutdown_mixes>=2,"unchanged mix-aware shutdown observes two real mixes")
	check(released.get_ref()==null and director._free_sources.all(func(source):return source.stream==null and not source.playing),"free WAV/playback resources released during native shutdown")
	check(not director.update_free_context(noise),"late free updates cannot restart stopped director")
	director.queue_free();app.queue_free()
	await process_frame;await process_frame
	for suffix in ["",".tmp",".bak"]:
		var path="user://m5-test-settings.json"+suffix
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	print("SCENE112_FREE_AUDIO_TESTS_", "OK" if failures==0 else "FAIL", " checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
