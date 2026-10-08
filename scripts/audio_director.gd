class_name AudioDirector
extends Node
## Original offline score and positional world audio. One director per game.
## Source app is read-only; explicit UI/radio/outcome hooks call cue().

const BUSES := ["Master", "Music", "Ambience", "SFX", "Vehicle", "Radio", "Voice", "UI"]
const DEFAULT_VOLUMES := {"Master": 0.85, "Music": 0.5, "Ambience": 0.6, "SFX": 0.7, "Vehicle": 0.6, "Radio": 0.8, "Voice": 0.85, "UI": 0.55}
const MAX_ONESHOTS := 10
const THEMES := ["menu", "surveillance_a", "surveillance_b", "academy", "investigation", "urgency", "silent", "fire_sparse", "fire_risk"]
const CUES := {"ui": "ui", "interaction": "interaction", "radio_call": "radio_tone",
	"radio_crackle": "crackle", "success": "success", "partial": "partial", "error": "error", "logo": "sonic_logo", "nozzle_lever": "nozzle_lever", "rescue": "rescue", "withdraw": "withdraw", "handover": "handover", "evidence_paper": "evidence_paper", "evidence_bag": "evidence_bag", "evidence_camera": "evidence_camera", "office_chair": "office_chair"}
const FILES := ["music_menu", "music_surveillance_a", "music_surveillance_b", "music_academy", "music_investigation",
	"sonic_logo", "urgency", "radio_tone", "ui", "interaction", "success", "partial", "error",
	"wind", "room", "rain", "traffic", "harbour", "engine", "crackle", "step_asphalt", "step_wood", "birds", "siren", "fire_loop", "water_loop", "air_breathing", "nozzle_lever", "music_fire_sparse", "music_fire_risk", "rescue", "withdraw", "handover", "evidence_paper", "evidence_bag", "evidence_camera", "office_chair", "office_clock_loop", "street_murmur", "civilian_passby"]

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
var _shutdown_complete := false
var _shutdown_mixes := 0
var _shutdown_synchronized := false
const FIRE_SITE := Vector3(-2, 0, 48)
const FIRE_IDS := ["front", "origin", "side"]
var _fire_sources: Array[AudioStreamPlayer3D] = []
var _water_source: AudioStreamPlayer3D
var _breath_source: AudioStreamPlayer3D
var _fire: Dictionary = {"mode": "none"}
var _fire_at := Vector3.ZERO
var _fire_inside := false
var _fire_spraying := false
var _fire_age := 0.0
var _fire_danger := 0.0
var _fire_high := false
var _fire_clock := -1.0
var _nozzle_cooldown := 0.0
var _fire_live := false
var _fire_outside := false
var _investigation_context := "none"
var _investigation_at := Vector3.ZERO
var _interview := false
var _investigation_age := 0.0
var _investigation_live := false
var _investigation_used := false
var _investigation_inside := false
var _office_clock: AudioStreamPlayer3D
const MAX_FREE_SOURCES := 2
var _free_context := {"active": false, "kind": "none", "at": Vector3.ZERO, "conversation": false, "settled": false, "traffic": []}
var _free_sources: Array[AudioStreamPlayer3D] = []
var _free_age := 0.0
var _free_live := false
var _free_focus := false


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
	_create_ambience("rain", Vector3(8, 3, 31), "rain", 12, 35, -17)
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
	if name == _theme and _quiet_until == 0: return true
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
	if _theme.begins_with("surveillance") or _theme.begins_with("fire_"):
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

func update_fire(state: Dictionary, at: Vector3, inside: bool, spraying: bool) -> bool:
	# Consume the controller's actual model result; never alter incident gameplay.
	if _stopping or not _valid_at(at) or not _valid_fire(state): return false
	if state.mode == "none":
		_fire_outside = false
		_fire = {"mode": "none"}
		_fire_inside = false
		_fire_spraying = false
		_fire_clock = -1
		_fire_age = 0
		return true
	_create_fire_sources()
	var fresh: bool = _fire_outside or _fire.mode == "none" or _fire.mode != state.mode or float(state.clock) < _fire_clock
	if not fresh:
		if _fire.victim.status != "rescued" and state.victim.status == "rescued":
			cue("rescue", at)
			begin_voice(2.0)
		if _fire.phase != "completed" and state.phase == "completed":
			var last: String = str(state.actions.back().kind) if not state.actions.is_empty() else "handover"
			cue("withdraw" if last == "withdraw" else "handover", at)
			begin_voice(2.4)
	if spraying and not _fire_spraying and _nozzle_cooldown <= 0:
		cue("nozzle_lever", at)
		_nozzle_cooldown = 0.18
	_fire_outside = false
	_fire = {"mode": state.mode, "phase": state.phase, "cells": state.cells.duplicate(true),
		"victim": state.victim.duplicate(true), "oxygen": state.oxygen, "water_liters": state.water_liters}
	_fire_clock = float(state.clock)
	_fire_at = at
	_fire_inside = inside
	_fire_spraying = spraying and state.phase == "active" and float(state.water_liters) > 0 and state.victim.status != "carried"
	_fire_age = 0
	return true

func _valid_at(at: Vector3) -> bool:
	return is_finite(at.x) and is_finite(at.y) and is_finite(at.z) and absf(at.x) < 500 and absf(at.y) < 100 and absf(at.z) < 500

func _audio_number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func _valid_fire(state: Dictionary) -> bool:
	if state.get("mode") not in ["none", "campaign", "lesson", "free"]: return false
	if state.mode == "none": return true
	if state.get("phase") not in ["briefing", "active", "completed"] or not _audio_number(state.get("clock"), 0, 100000): return false
	if not _audio_number(state.get("oxygen"), 0, 100) or not _audio_number(state.get("water_liters"), 0, 320): return false
	var victim: Variant = state.get("victim")
	if not victim is Dictionary or victim.get("status") not in ["waiting", "carried", "rescued", "lost"] or not _audio_number(victim.get("exposure"), 0, 100): return false
	var cells: Variant = state.get("cells")
	if not cells is Array or cells.size() != 3: return false
	for index in range(3):
		var cell: Variant = cells[index]
		if not cell is Dictionary or cell.get("id") != FIRE_IDS[index] or not _audio_number(cell.get("heat"), 0, 1): return false
		var pos: Variant = cell.get("pos")
		if not pos is Array or pos.size() != 3: return false
		for value in pos:
			if not _audio_number(value, -10, 10): return false
	var actions: Variant = state.get("actions")
	if not actions is Array or actions.size() > 64: return false
	for action in actions:
		if not action is Dictionary or not action.get("kind") is String or not _audio_number(action.get("time"), 0, float(state.clock)): return false
	return true

func _create_fire_sources() -> void:
	if not _fire_sources.is_empty(): return
	for index in range(3):
		var source := _spatial_loop("fire_loop", "Ambience", 5, 22, -18)
		source.pitch_scale = 0.93 + index * 0.07
		_fire_sources.append(source)
	_water_source = _spatial_loop("water_loop", "SFX", 5, 22, -12)
	_breath_source = _spatial_loop("air_breathing", "SFX", 2, 8, -16)

func _tick_fire(delta: float) -> void:
	_fire_age += delta
	_nozzle_cooldown = maxf(0, _nozzle_cooldown - delta)
	var live: bool = _fire.mode != "none" and _fire_age < 1.0
	if is_instance_valid(_app): live = live and _app.active and not _app.paused
	_fire_live = live and _fire.phase == "active" if _fire.mode != "none" else false
	if _fire_sources.is_empty(): return
	var target_danger := 0.0
	if live:
		var mean := 0.0
		for cell in _fire.cells: mean += float(cell.heat) / 3.0
		if _fire_outside:
			target_danger = clampf(mean * 0.65, 0, 1)
		else:
			target_danger = clampf(mean * 0.65 + float(_fire.victim.exposure) * 0.002 + (1 - float(_fire.oxygen) / 100) * (0.35 if _fire_inside else 0.0) + (0.08 if _fire.victim.status == "carried" else 0.0), 0, 1)
	_fire_danger = lerpf(_fire_danger, target_danger, 1 - exp(-delta * 2))
	if _fire_danger > 0.72: _fire_high = true
	elif _fire_danger < 0.52: _fire_high = false
	for index in range(3):
		var source := _fire_sources[index]
		var heat: float = float(_fire.cells[index].heat) if live else 0.0
		if live:
			var point: Array = _fire.cells[index].pos
			source.global_position = (Vector3.ZERO if _fire_outside else FIRE_SITE) + Vector3(float(point[0]), float(point[1]), float(point[2]))
		source.set_meta("base_gain_db", -28 + heat * 17)
		_gate(source, live and _fire.phase != "completed" and heat > 0.04, delta)
	_water_source.global_position = _fire_at + Vector3(0.3, 1.2, -0.1)
	_breath_source.global_position = _fire_at + Vector3(0, 1.4, 0)
	_breath_source.pitch_scale = lerpf(_breath_source.pitch_scale, 1 + _fire_danger * 0.22, minf(1, delta * 3))
	_gate(_water_source, live and _fire_spraying, delta)
	_gate(_breath_source, live and _fire_inside and _fire.phase == "active", delta)

func update_investigation(context: String, witness_interview: bool, at: Vector3, inside: bool = false) -> bool:
	# Controller context only: no reliability, guilt or truth input exists here.
	if _stopping or context not in ["none", "scene", "board", "office"] or not _valid_at(at): return false
	_investigation_context = context
	_investigation_inside = context != "none" and (inside or context == "office")
	_investigation_used = _investigation_used or context != "none"
	_investigation_at = at
	_interview = witness_interview and context != "none"
	_investigation_age = 0
	if context == "office" and _office_clock == null:
		_office_clock = _spatial_loop("office_clock_loop", "Ambience", 3, 12, -31)
	return true

func _tick_investigation(delta: float) -> void:
	_investigation_age += delta
	_investigation_live = _investigation_context != "none" and _investigation_age < 1.0
	if is_instance_valid(_app):
		_investigation_live = _investigation_live and _app.active and (not _app.paused or _interview)
	if _investigation_live and _interview:
		# Focus ducking for subtitled dialogue; no recorded or synthetic speech.
		_voice_seconds = maxf(_voice_seconds, 0.3)
	if _office_clock != null:
		_office_clock.global_position = _investigation_at + Vector3(1.4, 1.8, 0)
		_gate(_office_clock, _investigation_live and _investigation_context == "office" and not _interview, delta)

func update_free_context(data: Dictionary) -> bool:
	# Physical scene context only; no truth/reliability/score input is accepted.
	if _stopping or not _valid_free_context(data): return false
	_free_context = data.duplicate(true)
	_free_age = 0
	if data.active and (data.kind == "noise" or not data.traffic.is_empty()):
		_create_free_sources()
	return true

func _valid_free_context(data: Dictionary) -> bool:
	if data.size() != 6 or not data.get("active") is bool or not data.get("conversation") is bool or not data.get("settled") is bool: return false
	if data.get("kind") not in ["none", "noise", "traffic", "fire"] or not data.get("at") is Vector3: return false
	if not _valid_at(data.at): return false
	var traffic: Variant = data.get("traffic")
	if not traffic is Array or traffic.size() > 16: return false
	for item: Variant in traffic:
		if not item is Dictionary or item.size() != 2 or not item.get("at") is Vector3: return false
		if not _valid_at(item.at) or not _audio_number(item.get("speed"), -20, 20): return false
	return true

func _create_free_sources() -> void:
	if not _free_sources.is_empty(): return
	for index in range(MAX_FREE_SOURCES):
		var source := AudioStreamPlayer3D.new()
		source.name = "FreeDutySource%d" % index
		source.unit_size = 6
		source.max_distance = 48
		source.volume_db = -70
		source.set_meta("free_file", "")
		source.set_meta("base_gain_db", -25)
		add_child(source)
		_free_sources.append(source)

func _tick_free_context(delta: float) -> void:
	_free_age += delta
	var fresh: bool = _free_context.active and _free_age < 1.0
	if is_instance_valid(_app): fresh = fresh and _app.active
	_free_focus = fresh and _free_context.conversation
	_free_live = fresh and (not _app.paused if is_instance_valid(_app) else true)
	# Dialogue can pause movement while its subtitled reading stays focused.
	if _free_focus: _voice_seconds = maxf(_voice_seconds, delta + 0.2)
	if _free_sources.is_empty(): return
	var listener: Vector3 = _app._controlled_position() if is_instance_valid(_app) else _free_context.at
	var noise: bool = _free_live and _free_context.kind == "noise" and not _free_context.settled and not _free_focus
	var candidates: Array = _free_context.traffic.duplicate(true) if _free_live else []
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return listener.distance_squared_to(a.at) < listener.distance_squared_to(b.at))
	for index in range(MAX_FREE_SOURCES):
		var source := _free_sources[index]
		var target := {"file": "", "at": Vector3.ZERO, "speed": 0.0}
		if index == 0 and noise:
			target = {"file": "street_murmur", "at": _free_context.at, "speed": 0.0}
		elif not candidates.is_empty():
			var selected := 0
			# Keep the previous physical car until another is distinctly nearer.
			# No actor identity is inferred from story choices or statement content.
			if source.get_meta("free_file", "") == "civilian_passby" and source.playing:
				var prior := -1
				var prior_distance := 64.0
				for item_index in range(candidates.size()):
					var movement: float = source.global_position.distance_squared_to(candidates[item_index].at + Vector3(0, 0.5, 0))
					if movement < prior_distance: prior = item_index; prior_distance = movement
				if prior >= 0 and listener.distance_to(candidates[prior].at) <= listener.distance_to(candidates[0].at) + 6.0: selected = prior
			var item: Dictionary = candidates.pop_at(selected)
			target = {"file": "civilian_passby", "at": item.at, "speed": item.speed}
		_route_free_source(source, target, listener, delta)

func _route_free_source(source: AudioStreamPlayer3D, target: Dictionary, listener: Vector3, delta: float) -> void:
	var file: String = target.file
	if file.is_empty():
		_gate(source, false, delta)
		return
	var at: Vector3 = target.at + Vector3(0, 1.2 if file == "street_murmur" else 0.5, 0)
	var changed: bool = source.get_meta("free_file", "") != file
	var jumped: bool = source.global_position.distance_squared_to(at) > 100.0
	if source.playing and (changed or jumped):
		# Fade fully before switching a stream or jumping to a different car.
		_gate(source, false, delta)
		return
	if changed:
		source.stream = _loop_stream(file)
		source.bus = "Ambience" if file == "street_murmur" else "Vehicle"
		source.set_meta("free_file", file)
	if not source.playing: source.global_position = at
	else: source.global_position = source.global_position.lerp(at, 1 - exp(-delta * 6))
	var moving := absf(float(target.speed))
	var wanted := _free_live
	if file == "street_murmur":
		source.set_meta("base_gain_db", -25.0)
		wanted = wanted and listener.distance_to(at) < (28 if source.playing else 24)
	else:
		var ratio := clampf(moving / 8, 0, 1)
		source.pitch_scale = lerpf(source.pitch_scale, 0.8 + ratio * 0.8, 1 - exp(-delta * 4))
		source.set_meta("base_gain_db", -25 + ratio * 5 - (10 if _free_focus else 0))
		wanted = wanted and moving > (0.15 if source.playing else 0.35) and listener.distance_to(at) < (44 if source.playing else 38)
	_gate(source, wanted, delta)

func _process(delta: float) -> void:
	if _stopping or not is_finite(delta) or delta < 0: return
	_clock += delta
	_tick_free_context(delta)
	_voice_seconds = maxf(0, _voice_seconds - delta)
	_duck_db = lerpf(_duck_db, -10.0 if _voice_seconds > 0 else 0.0, 1 - exp(-delta * 7))
	_apply_bus_levels()
	_crossfade = minf(1, _crossfade + delta / 1.8)
	for index in range(_music.size()):
		var target: float = (-8.0 + _fire_danger * 4.0 if _theme.begins_with("fire_") else 0.0) if index == _target_music else -70.0
		_music[index].volume_db = lerpf(_music[index].volume_db, target, 1 - exp(-delta * 4))
		if index != _target_music and _crossfade >= 1: _music[index].stop()
	if _quiet_until > 0 and _clock >= _quiet_until:
		set_theme(("fire_risk" if _fire_high else "fire_sparse") if _theme.begins_with("fire_") else ("surveillance_b" if _playlist_counter % 2 == 1 else "surveillance_a"))
	_prune_oneshots()
	_tick_fire(delta)
	_tick_investigation(delta)
	if is_instance_valid(_app): _update_world(delta)
	elif not _fire_sources.is_empty() or _investigation_used:
		var wanted := "silent"
		if _investigation_live and not _interview: wanted = "investigation"
		if _fire_live: wanted = "fire_risk" if _fire_high else "fire_sparse"
		if wanted != _theme: set_theme(wanted)

func _update_world(delta: float) -> void:
	var tag := "menu"
	if _app.active:
		tag = "surveillance"
		if _app.police_model.mode in ["basis", "intake"]: tag = "academy"
		elif _app.police_model.mode == "campaign" and not _app.police_model.observations.is_empty(): tag = "investigation"
		if _app.paused and _app.menu_items.get_child_count() > 0:
			var title := str(_app.menu_items.get_child(0).text)
			if title.begins_with("Lotte") or title.begins_with("Bram") or title == "Verklaring": tag = "silent"
	if _investigation_live: tag = "silent" if _interview else "investigation"
	if _fire_live: tag = "fire_risk" if _fire_high else "fire_sparse"
	if tag != _context:
		_context = tag
		set_theme("surveillance_a" if tag == "surveillance" else tag)
	var listener: Vector3 = _app._controlled_position()
	var indoors := (absf(listener.x) < 10 and listener.z < 0 and listener.z > -10) or (listener.x > 18 and listener.x < 40 and listener.z < -1 and listener.z > -12)
	# The controller supplies actual house-entry state; no new hardcoded room box.
	indoors = indoors or (_fire.mode != "none" and _fire_age < 1.0 and _fire_inside)
	indoors = indoors or (_investigation_live and _investigation_inside)
	var condition := str(_app.state.get("condition"))
	for id: String in _ambience:
		var player: AudioStreamPlayer3D = _ambience[id]
		var wanted: bool = _app.active and not _app.paused
		if id == "rain":
			wanted = wanted and condition == "rain"
			player.global_position = listener + Vector3(0, 3, 0)
			player.set_meta("base_gain_db", -32 if indoors else -17)
		elif id in ["bureau", "kazerne"]: wanted = wanted and indoors
		else:
			wanted = wanted and not indoors
			if id == "birds":
				wanted = wanted and condition != "rain"
				player.set_meta("base_gain_db", -18 if condition == "dusk" else -8)
			elif id == "wind":
				player.set_meta("base_gain_db", -12 if condition == "rain" else -15)
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
		"settings": get_settings(), "shutdown_mixes": _shutdown_mixes, "shutdown_synchronized": _shutdown_synchronized, "fire_danger": _fire_danger, "fire_live": _fire_live, "fire_sources": _fire_sources.size(), "spraying": _fire_spraying, "investigation_context": _investigation_context, "interview": _interview, "investigation_live": _investigation_live, "free_context_live": _free_live, "free_focus": _free_focus, "free_sources": _free_sources.size(), "free_kind": _free_context.kind, "free_age": _free_age}

func stop_all() -> void:
	_stopping = true
	set_process(false)
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null
	_streams.clear()

func shutdown() -> void:
	if _shutdown_complete: return
	_stopping = true
	set_process(false)
	if not is_inside_tree():
		stop_all()
		_shutdown_complete = true
		return
	# AudioStreamPlayer3D can queue its start until the next physics frame.
	# Freeze new cues, let those starts reach AudioServer, then stop them.
	await get_tree().physics_frame
	await get_tree().process_frame
	await _wait_for_audio_mixes(1)
	stop_all()
	# Dummy reports zero output latency but mixes 4096 frames at a time.
	# Observe real mixes instead of assuming a fixed delay is sufficient.
	_shutdown_mixes = await _wait_for_audio_mixes(2)
	_shutdown_synchronized = _shutdown_mixes >= 2
	# Playback deletion is deferred from the audio thread to main-thread cleanup.
	await get_tree().process_frame
	await get_tree().process_frame
	_shutdown_complete = true
	print("SCENE112_AUDIO_STOP driver=", AudioServer.get_driver_name(), " mixes=", _shutdown_mixes, " synchronized=", _shutdown_synchronized)
	if not _shutdown_synchronized: push_error("AUDIO_SHUTDOWN_TIMEOUT: audio mixer did not settle within bounded shutdown")

func _wait_for_audio_mixes(wanted: int) -> int:
	var observed := 0
	var previous := _audio_mix_timestamp()
	var deadline := Time.get_ticks_msec() + 1500
	while observed < wanted and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var current := _audio_mix_timestamp()
		# The timestamp is inferred from two clocks; tolerate microsecond rounding
		# and call overhead instead of counting it as an audio-thread transition.
		if current - previous > 2000:
			observed += 1
			previous = current
	return observed

func _audio_mix_timestamp() -> int:
	var elapsed := AudioServer.get_time_since_last_mix()
	return Time.get_ticks_usec() - int(elapsed * 1000000)

func _exit_tree() -> void:
	stop_all()

func update_outside_fire(context: Dictionary, at: Vector3, spraying: bool) -> bool:
	# Explicit world-space outdoor contract: no invented victim or breathing air.
	if _stopping or not _valid_at(at) or not _valid_outside_fire(context): return false
	if context.mode == "none":
		if _fire_outside: return update_fire({"mode": "none"}, at, false, false)
		return true
	_create_fire_sources()
	var fresh: bool = not _fire_outside or _fire.mode == "none" or float(context.clock) < _fire_clock
	if not fresh and _fire.phase != "completed" and context.phase == "completed":
		cue("withdraw" if context.withdrew else "handover", at)
		begin_voice(2.4)
	if spraying and not _fire_spraying and _nozzle_cooldown <= 0:
		cue("nozzle_lever", at)
		_nozzle_cooldown = 0.18
	_fire = {"mode": "free", "phase": context.phase, "cells": context.cells.duplicate(true), "water_liters": context.water_liters}
	_fire_outside = true
	_fire_at = at
	_fire_inside = false
	_fire_spraying = spraying and context.phase == "active" and float(context.water_liters) > 0
	_fire_clock = float(context.clock)
	_fire_age = 0
	return true

func _valid_outside_fire(context: Dictionary) -> bool:
	if context.get("mode") == "none": return context.size() == 1
	if context.size() != 6 or context.get("mode") != "free": return false
	if context.get("phase") not in ["briefing", "active", "completed"] or not context.get("withdrew") is bool: return false
	if not _audio_number(context.get("clock"), 0, 3600) or not _audio_number(context.get("water_liters"), 0, 220): return false
	var cells: Variant = context.get("cells")
	if not cells is Array or cells.size() != 3: return false
	for index in 3:
		var cell: Variant = cells[index]
		if not cell is Dictionary or cell.size() != 3 or cell.get("id") != ["center", "left", "right"][index]: return false
		if not _audio_number(cell.get("heat"), 0, 1): return false
		var pos: Variant = cell.get("pos")
		if not pos is Array or pos.size() != 3: return false
		for value in pos:
			if not _audio_number(value, -490, 490): return false
		if not _valid_at(Vector3(float(pos[0]), float(pos[1]), float(pos[2]))): return false
	return true
