class_name AudioDirector
extends Node
## Original offline score and positional world audio. One director per game.
## Source app is read-only; explicit UI/radio/outcome hooks call cue().

const BUSES := ["Master", "Music", "Ambience", "SFX", "Vehicle", "Radio", "Voice", "UI"]
const DEFAULT_VOLUMES := {"Master": 0.85, "Music": 0.5, "Ambience": 0.6, "SFX": 0.7, "Vehicle": 0.6, "Radio": 0.8, "Voice": 0.85, "UI": 0.55}
const MAX_ONESHOTS := 10
const THEMES := ["menu", "surveillance_a", "surveillance_b", "academy", "investigation", "urgency", "silent"]
const CUES := {"ui": "ui", "interaction": "interaction", "radio_call": "radio_tone",
	"radio_crackle": "crackle", "success": "success", "partial": "partial", "error": "error", "logo": "sonic_logo"}
const FILES := ["music_menu", "music_surveillance_a", "music_surveillance_b", "music_academy", "music_investigation",
	"sonic_logo", "urgency", "radio_tone", "ui", "interaction", "success", "partial", "error",
	"wind", "room", "rain", "traffic", "harbour", "engine", "crackle", "step_asphalt", "step_wood", "birds", "siren"]

var asset_root := "res://assets/audio"
var settings_path := "user://audio-settings.json"
var _app: Node3D
var _volumes: Dictionary = DEFAULT_VOLUMES.duplicate()
var _muted := false
var _streams: Dictionary = {}
var _missing: Array[String] = []
var _music: Array[AudioStreamPlayer] = []
var _oneshots: Array[Node] = []
var _ambience: Dictionary = {}
var _engines: Dictionary = {}
var _sirens: Dictionary = {}
var _siren_enabled: Dictionary = {}
var _theme := "silent"
var _context := ""
var _target_music := -1
var _crossfade := 1.0
var _clock := 0.0
var _quiet_until := 0.0
var _playlist_counter := 0
var _voice_seconds := 0.0
var _duck_db := 0.0
var _step_clock := 0.0
var _last_listener := Vector3.ZERO
var _stopping := false

func _ready() -> void:
	_create_buses()
	load_settings()
	for file: String in FILES: _load_stream(file)
	for index in range(2):
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		player.volume_db = -70
		add_child(player)
		player.finished.connect(_music_finished.bind(index))
		_music.append(player)
	_create_ambience("wind", Vector3(8, 2, 31), "wind", 22, 80, -15)
	_create_ambience("birds", Vector3(-4, 3, 34), "birds", 15, 55, -8)
	_create_ambience("traffic", Vector3(-20, 0.5, 17), "traffic", 18, 65, -10)
	_create_ambience("harbour", Vector3(42, 1, -32), "harbour", 18, 55, -9)
	_create_ambience("bureau", Vector3(0, 1, -5), "room", 8, 18, -7)
	_create_ambience("kazerne", Vector3(29, 1, -6), "room", 9, 20, -7)
	for id: String in ["police_car", "fire_truck"]:
		_engines[id] = _spatial_loop("engine", "Vehicle", 12, 50, -22)
		_sirens[id] = _spatial_loop("siren", "Vehicle", 22, 100, -4)
		_siren_enabled[id] = false
	set_theme("menu")
	_apply_bus_levels()

func setup(app: Node3D) -> void:
	_app = app
	_context = ""

func _create_buses() -> void:
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
		if bus != "Master": AudioServer.set_bus_send(AudioServer.get_bus_index(bus), "Master")
	var radio := AudioServer.get_bus_index("Radio")
	if AudioServer.get_bus_effect_count(radio) == 0:
		var eq := AudioEffectEQ6.new()
		eq.set_band_gain_db(0, -16)
		eq.set_band_gain_db(1, -7)
		eq.set_band_gain_db(5, -12)
		AudioServer.add_bus_effect(radio, eq)
		var compressor := AudioEffectCompressor.new()
		compressor.threshold = -18
		compressor.ratio = 2
		compressor.attack_us = 4000
		compressor.release_ms = 100
		AudioServer.add_bus_effect(radio, compressor)

func _load_stream(name: String) -> AudioStreamWAV:
	if _streams.has(name): return _streams[name]
	var path := asset_root.path_join(name + ".wav")
	var stream: AudioStreamWAV
	if path.begins_with("res://"):
		if ResourceLoader.exists(path): stream = load(path) as AudioStreamWAV
	else:
		if FileAccess.file_exists(path): stream = AudioStreamWAV.load_from_file(path)
	if stream == null:
		if name not in _missing: _missing.append(name)
		return null
	_streams[name] = stream
	return stream

func _loop_stream(name: String) -> AudioStreamWAV:
	var stream := _load_stream(name)
	if stream != null:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream

func _spatial_loop(name: String, bus: String, unit: float, maximum: float, gain: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = _loop_stream(name)
	player.bus = bus
	player.unit_size = unit
	player.max_distance = maximum
	player.volume_db = -70
	player.set_meta("base_gain_db", gain)
	add_child(player)
	return player

func _create_ambience(id: String, at: Vector3, name: String, unit: float, maximum: float, gain: float) -> void:
	var player := _spatial_loop(name, "Ambience", unit, maximum, gain)
	player.global_position = at
	_ambience[id] = player

func set_theme(name: String) -> bool:
	if _stopping or name not in THEMES or _music.size() != 2: return false
	if name == _theme: return true
	_theme = name
	_quiet_until = 0
	_crossfade = 0
	if name == "silent":
		_target_music = -1
		return true
	var file := "urgency" if name == "urgency" else "music_" + name
	var stream := _load_stream(file)
	if stream == null:
		_target_music = -1
		return false
	if name in ["menu", "academy"]: stream = _loop_stream(file)
	else: stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_target_music = 1 if _target_music == 0 else 0
	var player := _music[_target_music]
	player.stop()
	player.stream = stream
	player.volume_db = -70
	player.play()
	return true

func _music_finished(index: int) -> void:
	if index != _target_music: return
	if _theme.begins_with("surveillance"):
		_playlist_counter += 1
		_quiet_until = _clock + 20.0 + (_playlist_counter % 3) * 8.0
	elif _theme in ["urgency", "investigation"]:
		_target_music = -1
		# Investigation deliberately falls silent after its sparse phrase.
		if _theme == "urgency": _context = ""

func begin_voice(seconds: float) -> bool:
	if _stopping or not is_finite(seconds) or seconds < 0 or seconds > 60: return false
	_voice_seconds = maxf(_voice_seconds, seconds)
	return true

func cue(name: String, position: Variant = null) -> bool:
	if _stopping or not CUES.has(name): return false
	if name in ["radio_call", "radio_crackle"]: begin_voice(1.1)
	var bus := "Radio" if name in ["radio_call", "radio_crackle"] else ("UI" if name == "ui" else "SFX")
	return _one_shot(CUES[name], bus, position)

func _one_shot(file: String, bus: String, position: Variant = null) -> bool:
	if _stopping: return false
	_prune_oneshots()
	# Refuse surplus cues; never cut an existing voice in its middle.
	if _oneshots.size() >= MAX_ONESHOTS: return false
	var stream := _load_stream(file)
	if stream == null: return false
	var player: Node
	if position is Vector3:
		if not is_finite(position.x) or not is_finite(position.y) or not is_finite(position.z): return false
		var spatial := AudioStreamPlayer3D.new()
		spatial.unit_size = 8
		spatial.max_distance = 28
		spatial.stream = stream
		spatial.bus = bus
		player = spatial
		add_child(player)
		spatial.global_position = position
	else:
		var flat := AudioStreamPlayer.new()
		flat.stream = stream
		flat.bus = bus
		player = flat
		add_child(player)
	player.finished.connect(player.queue_free)
	_oneshots.append(player)
	player.play()
	return true

func set_siren(enabled: bool, vehicle_id: String = "police_car") -> bool:
	if _stopping or vehicle_id not in _sirens: return false
	_siren_enabled[vehicle_id] = enabled
	return true

func _process(delta: float) -> void:
	if _stopping or not is_finite(delta) or delta < 0: return
	_clock += delta
	_voice_seconds = maxf(0, _voice_seconds - delta)
	_duck_db = lerpf(_duck_db, -10.0 if _voice_seconds > 0 else 0.0, 1 - exp(-delta * 7))
	_apply_bus_levels()
	_crossfade = minf(1, _crossfade + delta / 1.8)
	for index in range(_music.size()):
		var target := 0.0 if index == _target_music else -70.0
		_music[index].volume_db = lerpf(_music[index].volume_db, target, 1 - exp(-delta * 4))
		if index != _target_music and _crossfade >= 1: _music[index].stop()
	if _quiet_until > 0 and _clock >= _quiet_until:
		set_theme("surveillance_b" if _playlist_counter % 2 == 1 else "surveillance_a")
	_prune_oneshots()
	if is_instance_valid(_app): _update_world(delta)

func _update_world(delta: float) -> void:
	var tag := "menu"
	if _app.active:
		tag = "surveillance"
		if _app.police_model.mode in ["basis", "intake"]: tag = "academy"
		elif _app.police_model.mode == "campaign" and not _app.police_model.observations.is_empty(): tag = "investigation"
		if _app.paused and _app.menu_items.get_child_count() > 0:
			var title := str(_app.menu_items.get_child(0).text)
			if title.begins_with("Lotte") or title.begins_with("Bram") or title == "Verklaring": tag = "silent"
	if tag != _context:
		_context = tag
		set_theme("surveillance_a" if tag == "surveillance" else tag)
	var listener: Vector3 = _app._controlled_position()
	var indoors := (absf(listener.x) < 10 and listener.z < 0 and listener.z > -10) or (listener.x > 18 and listener.x < 40 and listener.z < -1 and listener.z > -12)
	for id: String in _ambience:
		var player: AudioStreamPlayer3D = _ambience[id]
		var wanted: bool = _app.active and not _app.paused
		if id in ["bureau", "kazerne"]: wanted = wanted and indoors
		else: wanted = wanted and not indoors
		_gate(player, wanted, delta)
	for id: String in _engines:
		var vehicle: Node3D = _app.district.objects[id]
		var engine: AudioStreamPlayer3D = _engines[id]
		engine.global_position = vehicle.global_position + Vector3(0, 0.5, 0)
		var driving: bool = _app.active and not _app.paused and _app.state.occupied_vehicle == id
		var ratio := clampf(absf(float(vehicle.speed)) / (11.5 if id == "fire_truck" else 14.0), 0, 1)
		engine.pitch_scale = lerpf(engine.pitch_scale, 0.68 + ratio * 0.9, minf(1, delta * 4))
		engine.set_meta("base_gain_db", -20 + ratio * 10)
		_gate(engine, driving, delta)
		var siren: AudioStreamPlayer3D = _sirens[id]
		siren.global_position = engine.global_position
		_gate(siren, driving and _siren_enabled[id], delta)
	if _app.active and not _app.paused and _app.state.occupied_vehicle.is_empty():
		var speed := Vector2(_app.officer.velocity.x, _app.officer.velocity.z).length()
		if speed > 0.4:
			_step_clock += delta
			if _step_clock > clampf(1.8 / speed, 0.28, 0.65):
				_step_clock = 0
				_one_shot("step_wood" if indoors else "step_asphalt", "SFX", listener + Vector3(0, 0.05, 0))
		else: _step_clock = 0
	_last_listener = listener

func _gate(player: AudioStreamPlayer3D, enabled: bool, delta: float) -> void:
	if enabled and not player.playing and player.stream != null:
		player.volume_db = -70
		player.play()
	var target: float = float(player.get_meta("base_gain_db", -15)) if enabled else -70.0
	player.volume_db = lerpf(player.volume_db, target, 1 - exp(-delta * 7))
	if not enabled and player.volume_db < -60: player.stop()

func _prune_oneshots() -> void:
	for index in range(_oneshots.size() - 1, -1, -1):
		var player: Node = _oneshots[index]
		if not is_instance_valid(player) or not player.playing:
			if is_instance_valid(player): player.queue_free()
			_oneshots.remove_at(index)

func get_settings() -> Dictionary:
	return {"schema": 1, "muted": _muted, "volumes": _volumes.duplicate()}

func apply_settings(data: Variant, persist: bool = true) -> bool:
	if not _valid_settings(data): return false
	_muted = data.muted
	_volumes = data.volumes.duplicate()
	_apply_bus_levels()
	return save_settings() if persist else true

func set_volume(bus: String, value: float, persist: bool = true) -> bool:
	if bus not in BUSES or not is_finite(value) or value < 0 or value > 1: return false
	_volumes[bus] = value
	_apply_bus_levels()
	return save_settings() if persist else true

func set_muted(muted: bool, persist: bool = true) -> bool:
	_muted = muted
	_apply_bus_levels()
	return save_settings() if persist else true

func _valid_settings(data: Variant) -> bool:
	if not data is Dictionary or data.size() != 3 or not data.get("muted") is bool: return false
	var schema: Variant = data.get("schema")
	if not (schema is int or schema is float) or schema != 1: return false
	var volumes: Variant = data.get("volumes")
	if not volumes is Dictionary or volumes.size() != BUSES.size(): return false
	for bus: String in BUSES:
		var value: Variant = volumes.get(bus)
		if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0 or float(value) > 1: return false
	return true

func _apply_bus_levels() -> void:
	for bus: String in BUSES:
		var index := AudioServer.get_bus_index(bus)
		if index < 0: continue
		var volume := float(_volumes[bus])
		AudioServer.set_bus_mute(index, (bus == "Master" and _muted) or volume == 0)
		var duck := _duck_db if bus in ["Music", "Ambience"] else 0.0
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, volume)) + duck)

func save_settings() -> bool:
	var stream := FileAccess.open(settings_path + ".tmp", FileAccess.WRITE)
	if stream == null: return false
	stream.store_string(JSON.stringify(get_settings()))
	stream.flush()
	var error := stream.get_error()
	stream.close()
	if error != OK: return false
	var old: Variant = _read_settings(settings_path)
	if _valid_settings(old) and DirAccess.copy_absolute(settings_path, settings_path + ".bak") != OK: return false
	return DirAccess.rename_absolute(settings_path + ".tmp", settings_path) == OK

func load_settings() -> bool:
	var data: Variant = _read_settings(settings_path)
	if not _valid_settings(data): data = _read_settings(settings_path + ".bak")
	return apply_settings(data, false) if _valid_settings(data) else false

func _read_settings(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func status() -> Dictionary:
	return {"theme": _theme, "driver": AudioServer.get_driver_name(), "no_device": AudioServer.get_driver_name() == "Dummy",
		"duck_db": _duck_db, "voice_seconds": _voice_seconds, "quiet_until": _quiet_until,
		"oneshots": _oneshots.size(), "voice_cap": MAX_ONESHOTS, "waves_loaded": _streams.size(), "missing": _missing.duplicate(),
		"settings": get_settings()}

func stop_all() -> void:
	_stopping = true
	set_process(false)
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null
	_streams.clear()

func shutdown() -> void:
	# AudioServer releases stopped playback references on its next mix. Keep
	# the tree alive briefly instead of exiting with active WAV playbacks.
	stop_all()
	if is_inside_tree():
		var settling := clampf(AudioServer.get_output_latency() * 2 + 0.05, 0.12, 0.5)
		await get_tree().create_timer(settling).timeout

func _exit_tree() -> void:
	stop_all()
