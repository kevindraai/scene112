extends Node3D

const State = preload("res://scripts/game_state.gd")
const World = preload("res://scripts/world.gd")
const Player = preload("res://scripts/player.gd")
const Ledger = preload("res://scripts/dispatch.gd")
var state := State.new()
var ledger := Ledger.new()
var district: Node3D
var officer: CharacterBody3D
var canvas: CanvasLayer
var menu: PanelContainer
var menu_items: VBoxContainer
var hud: Control
var objective: Label
var prompt: Label
var notice: Label
var duty_label: Label
var route_label: Label
var incident_marker: Label3D
var active := false
var paused := false
var current_target := {}
var notice_time := 0.0
var test_mode := false
var _test_finished := false

func _ready() -> void:
	DisplayServer.window_set_title("SCÈNE 112")
	_bind_inputs()
	district = World.new()
	add_child(district)
	officer = Player.new()
	add_child(officer)
	officer.position = state.player_position
	officer.enable_input = false
	district.interacted.connect(_interact)
	incident_marker = Label3D.new()
	incident_marker.font_size = 42
	incident_marker.pixel_size = 0.009
	incident_marker.modulate = Color("f4bf65")
	incident_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	incident_marker.hide()
	add_child(incident_marker)
	_build_ui()
	_show_main()
	var args := OS.get_cmdline_user_args()
	test_mode = "--smoke-test" in args or "--playthrough" in args or "--duty-playthrough" in args
	if "--smoke-test" in args:
		_smoke_test.call_deferred()
	elif "--playthrough" in args:
		_playthrough.call_deferred()
	elif "--duty-playthrough" in args:
		_duty_playthrough.call_deferred()

func _bind_inputs() -> void:
	var keys := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A,
		"move_right": KEY_D, "sprint": KEY_SHIFT, "interact": KEY_E, "pause": KEY_ESCAPE,
		"save_game": KEY_F5, "load_game": KEY_F9, "map": KEY_M,
		"brake": KEY_SPACE, "radio": KEY_R}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		InputMap.action_add_event(action, event)

func _build_ui() -> void:
	canvas = CanvasLayer.new()
	add_child(canvas)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud)
	var top := PanelContainer.new()
	top.position = Vector2(24, 24)
	top.custom_minimum_size = Vector2(540, 170)
	top.add_theme_stylebox_override("panel", _panel(Color(0.055, 0.12, 0.16, 0.94)))
	hud.add_child(top)
	var box := VBoxContainer.new()
	top.add_child(box)
	box.add_child(_label("SCÈNE 112  /  NOORDERKADE", 23, Color(0.42, 0.87, 0.83)))
	objective = _label("", 18)
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(objective)
	duty_label = _label("", 16, Color("acd4da"))
	box.add_child(duty_label)
	route_label = _label("", 16, Color("f4bf65"))
	route_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(route_label)
	prompt = _label("", 22, Color(1, 0.81, 0.39))
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.position = Vector2(-300, -108)
	prompt.size = Vector2(600, 50)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(prompt)
	var controls := _label("WASD  lopen/rijden  ·  Shift  sprint  ·  Spatie  rem  ·  E  handelen/in-uit  ·  R  radio  ·  M  kaart  ·  Esc  pauze", 16)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.position = Vector2(24, -40)
	hud.add_child(controls)
	notice = _label("", 18, Color(1, 0.86, 0.6))
	notice.position = Vector2(24, 224)
	notice.size = Vector2(660, 100)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(notice)
	menu = PanelContainer.new()
	menu.position = Vector2(50, 55)
	menu.custom_minimum_size = Vector2(470, 590)
	menu.add_theme_stylebox_override("panel", _panel(Color(0.035, 0.085, 0.12, 0.97)))
	canvas.add_child(menu)
	menu_items = VBoxContainer.new()
	menu_items.add_theme_constant_override("separation", 11)
	menu.add_child(menu_items)

func _panel(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	return style

func _label(value: String, size: int = 18, color: Color = Color(0.89, 0.94, 0.95)) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.025, 0.055, 0.075, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _clear_menu(title: String, subtitle: String) -> void:
	for child in menu_items.get_children():
		menu_items.remove_child(child)
		child.queue_free()
	menu_items.add_child(_label(title, 38, Color(0.42, 0.87, 0.83)))
	var label := _label(subtitle, 18)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 72)
	menu_items.add_child(label)
	menu.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _button(title: String, action: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 43
	button.add_theme_font_size_override("font_size", 19)
	button.disabled = disabled
	button.pressed.connect(action)
	menu_items.add_child(button)
	return button

func _show_main() -> void:
	_freeze()
	active = false
	hud.hide()
	_clear_menu("SCÈNE 112", "Een nieuwe dienst begint aan de Noorderkade.\nVrije dienst · Ontwikkelbuild M1 · Nederlandstalig · 14+")
	var candidate := State.new()
	_button("Doorgaan", load_game, not candidate.load_from())
	_button("Vrije politiedienst", start_new.bind("police")).grab_focus()
	_button("Vrije brandweerdienst", start_new.bind("fire"))
	_button("Bediening en wijkkaart", show_help)
	_button("Instellingen", show_settings)
	_button("Licenties", show_credits)
	_button("Afsluiten", func(): get_tree().quit())

func start_new(role: String = "police") -> void:
	_freeze()
	state = State.new()
	state.role = role
	state.player_position = Vector3(28, 0.1, 0) if role == "fire" else Vector3(0, 0.1, 6)
	ledger = Ledger.new()
	ledger.start(112)
	_restore_vehicles()
	_restore_on_foot(state.player_position)
	officer.sensitivity = state.sensitivity
	active = true
	_resume()
	_notify("Welkom bij de kazerne. Controleer je PBM en meld je bij de kazerneradio." if role == "fire" else "Welkom. Neem je uitrusting en meld je bij de radio. Daarna kun je op surveillance.")

func _freeze() -> void:
	paused = true
	officer.enable_input = false
	officer.set_physics_process(false)
	district.set_simulation_active(false)
	for id in ["police_car", "fire_truck"]:
		district.objects[id].enabled_input = false

func _resume() -> void:
	if not active:
		return
	paused = false
	menu.hide()
	hud.show()
	district.set_simulation_active(true)
	for id in ["police_car", "fire_truck"]:
		district.objects[id].enabled_input = id == state.occupied_vehicle
		district.objects[id].camera.current = false
	if state.occupied_vehicle.is_empty():
		officer.enable_input = true
		officer.set_physics_process(true)
		officer.camera.current = true
	else:
		officer.enable_input = false
		officer.set_physics_process(false)
		officer.camera.current = false
		district.objects[state.occupied_vehicle].camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_objective()

func _pause() -> void:
	_freeze()
	_clear_menu("Dienstpauze", "Je dienst blijft bewaard in dit venster. F5 slaat op; F9 laadt je laatste opslag.")
	_button("Dienst hervatten", _resume).grab_focus()
	_button("Dienst opslaan", save_game)
	var candidate := State.new()
	_button("Laatste opslag laden", load_game, not candidate.load_from())
	_button("Bediening en wijkkaart", show_help)
	_button("Instellingen", show_settings)
	_button("Naar hoofdmenu", _show_main)

func show_help() -> void:
	_freeze()
	_clear_menu("Noorderkade", "WASD: lopen/rijden · Muis: kijken · Spatie: rem\nE: handelen/in-uit · R: radio · F5/F9: opslaan/laden")
	var map := Control.new()
	map.custom_minimum_size = Vector2(420, 230)
	map.draw.connect(func(): _draw_map(map))
	menu_items.add_child(map)
	var text := _label(_navigation_text() + "\n\nNeem uitrusting en radio mee. Meldingen neem je aan met R. Parkeer veilig, stap uit en handel ter plaatse. Na afloop vervolg je de dienst.", 18)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(420, 108)
	menu_items.add_child(text)
	_button("Terug", _back).grab_focus()

func show_settings() -> void:
	_freeze()
	_clear_menu("Instellingen", "Pas het cameragevoel aan. De instelling wordt met je dienst opgeslagen.")
	menu_items.add_child(_label("Muisgevoeligheid"))
	var slider := HSlider.new()
	slider.min_value = 0.001
	slider.max_value = 0.008
	slider.step = 0.0005
	slider.value = state.sensitivity
	slider.value_changed.connect(func(value):
		state.sensitivity = value
		officer.sensitivity = value
		for id in ["police_car", "fire_truck"]:
			district.objects[id].sensitivity = value)
	menu_items.add_child(slider)
	_button("Volledig scherm aan/uit", func():
		var mode := DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN))
	_button("Terug", _back).grab_focus()

func show_credits() -> void:
	_freeze()
	_clear_menu("Licenties", "Originele procedurele wereld en code voor SCÈNE 112.\nGodot 4.7.2 · MIT · godotengine.org/license")
	var text := TextEdit.new()
	text.text = Engine.get_license_text() + "\n\n" + str(Engine.get_license_info())
	text.editable = false
	text.custom_minimum_size = Vector2(420, 310)
	menu_items.add_child(text)
	_button("Terug", _back).grab_focus()

func _back() -> void:
	if active: _pause()
	else: _show_main()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if active:
			if paused: _resume()
			else: _pause()
	elif active and event.is_action_pressed("save_game"):
		save_game()
	elif active and event.is_action_pressed("load_game"):
		load_game()
	elif active and not paused:
		if event.is_action_pressed("interact"):
			if not state.occupied_vehicle.is_empty():
				_exit_vehicle()
			elif not current_target.is_empty():
				if current_target.id == "incident_response": _show_response()
				else: district.interact(current_target.id)
		elif event.is_action_pressed("map"): show_help()
		elif event.is_action_pressed("radio"): show_radio()

func _process(delta: float) -> void:
	if not active or paused:
		return
	if state.radio_checked and ledger.tick(delta):
		_notify(str(ledger.messages.back()))
	if not state.occupied_vehicle.is_empty():
		var vehicle: Node3D = district.objects[state.occupied_vehicle]
		officer.global_position = vehicle.global_position
		current_target = {}
		prompt.text = "[E] Veilig uitstappen" if absf(vehicle.speed) <= 0.8 else "[Spatie] Remmen vóór uitstappen"
	else:
		current_target = district.get_interaction(officer.global_position)
		if _at_incident():
			current_target = {"id": "incident_response", "title": "Melding ter plaatse afhandelen"}
		prompt.text = "[E] " + str(current_target.title) if not current_target.is_empty() else ""
	_update_objective()
	if notice_time > 0:
		notice_time -= delta
		if notice_time <= 0: notice.text = ""

func _interact(id: String) -> void:
	match id:
		"equipment", "fire_equipment":
			if (id == "fire_equipment") != (state.role == "fire"):
				_notify("Neem de uitrusting voor je gekozen dienst bij " + ("de kazerne." if state.role == "fire" else "het bureau."))
				return
			state.equipment = true
			_notify("PBM gecontroleerd: beschermende kleding en portofoon. Meld je bij de kazerneradio." if state.role == "fire" else "Uitrusting gecontroleerd: portofoon, notitieboek en veiligheidsvest. Meld je bij de radio.")
		"radio", "fire_radio":
			if not state.equipment:
				_notify("Neem eerst je uitrusting mee. Een veilige dienst begint voorbereid.")
			elif (id == "fire_radio") != (state.role == "fire"):
				_notify("Meld je bij de radio van je eigen dienst.")
			else:
				state.radio_checked = true
				_notify("Meldkamer: eenheid 112 aangemeld. Je kunt op surveillance. R opent de meldkamer.")
		"academy":
			if not state.radio_checked:
				_notify("Controleer eerst uitrusting en radio bij het bureau.")
			else:
				state.academy_visits += 1
				_notify("Oefenplek bereikt. Basisronde afgerond. Sla je dienst op met F5; hervat met F9.")
		"board": show_help()
		"police_car", "fire_truck": _enter_vehicle(id)
		_:
			if district.npc_lines.has(id): _notify(district.npc_lines[id])
	_update_objective()

func _update_objective() -> void:
	if not state.equipment: objective.text = "01  Controleer je PBM in de kazerne." if state.role == "fire" else "01  Neem je uitrusting bij het bureau."
	elif not state.radio_checked: objective.text = "02  Meld je aan bij de portofoon/radio."
	elif _accepted_incident(): objective.text = "Ter plaatse: " + str(ledger.incident.title)
	elif not ledger.incident.is_empty() and ledger.incident.phase == "offered": objective.text = "Nieuwe melding  ·  R voor aannemen of doorgeven"
	else: objective.text = "Surveillance  ·  Verken de wijk en spreek bewoners"
	var duty_seconds := int(ledger.duty_time)
	var duty := "Brandweer" if state.role == "fire" else "Politie"
	var speed := 0.0 if state.occupied_vehicle.is_empty() else absf(district.objects[state.occupied_vehicle].speed) * 3.6
	duty_label.text = "%s  ·  Dienst %02d:%02d  ·  %d afgehandeld" % [duty, duty_seconds / 60, duty_seconds % 60, ledger.completed]
	if not state.occupied_vehicle.is_empty(): duty_label.text += "  ·  %.0f km/h" % speed
	route_label.text = _navigation_text()
	incident_marker.visible = _accepted_incident()
	if incident_marker.visible:
		incident_marker.position = _incident_position() + Vector3(0, 3.8, 0)
		incident_marker.text = "MELDING %d\n%s" % [ledger.serial, ledger.incident.title]

func _notify(message: String) -> void:
	notice.text = message
	notice_time = 9.0

func save_game(path: String = State.SAVE_PATH) -> void:
	_capture_state()
	if state.save_to(path): _notify("Dienst opgeslagen. Voertuigen, melding en voortgang zijn bewaard.")
	else: _notify(state.save_error)

func load_game(path: String = State.SAVE_PATH) -> void:
	var loaded := State.new()
	if not loaded.load_from(path):
		_notify("Geen geldige opslag gevonden. Begin een nieuwe dienst; je bestand blijft behouden.")
		return
	_freeze()
	state = loaded
	ledger = Ledger.new()
	if state.dispatch.is_empty(): ledger.start(112)
	else: ledger.restore(state.dispatch)
	var seated: String = state.occupied_vehicle
	_restore_vehicles()
	_restore_on_foot(state.player_position)
	officer.sensitivity = state.sensitivity
	if not seated.is_empty(): _enter_vehicle(seated, true)
	active = true
	_resume()
	_notify("Dienst hervat vanaf je laatste opslag.")

func _restore_vehicles() -> void:
	for id in ["police_car", "fire_truck"]:
		var vehicle: Node3D = district.objects[id]
		var pose: Dictionary = state.vehicles[id]
		vehicle.position = Vector3(float(pose.position[0]), float(pose.position[1]), float(pose.position[2]))
		vehicle.rotation.y = float(pose.yaw)
		vehicle.stop()
		vehicle.enabled_input = false
		vehicle.sensitivity = state.sensitivity
		vehicle.camera.current = false

func _restore_on_foot(at: Vector3) -> void:
	state.occupied_vehicle = ""
	officer.show()
	officer.position = at
	officer.velocity = Vector3.ZERO
	officer.collision_layer = 1
	officer.collision_mask = 1
	officer.enable_input = false
	officer.set_physics_process(false)
	officer.camera.current = true

func _enter_vehicle(id: String, restoring: bool = false) -> void:
	if not restoring:
		if not state.equipment or not state.radio_checked:
			_notify("Controleer eerst je uitrusting en meld je aan bij de radio.")
			return
		var expected := "fire_truck" if state.role == "fire" else "police_car"
		if id != expected:
			_notify("Gebruik het voertuig van je gekozen dienst.")
			return
		if officer.global_position.distance_to(district.objects[id].global_position) > 3.1:
			return
	var vehicle: Node3D = district.objects[id]
	state.occupied_vehicle = id
	officer.enable_input = false
	officer.hide()
	officer.collision_layer = 0
	officer.collision_mask = 0
	officer.velocity = Vector3.ZERO
	officer.set_physics_process(false)
	officer.global_position = vehicle.global_position
	officer.camera.current = false
	vehicle.camera.current = true
	vehicle.enabled_input = active and not paused
	_notify("WASD: rijden en sturen. Spatie: remmen. E: veilig uitstappen. R: meldkamer.")

func _exit_vehicle() -> void:
	var vehicle: Node3D = district.objects[state.occupied_vehicle]
	var exit: Variant = vehicle.get_exit_position()
	if exit == null:
		_notify("Kom eerst tot stilstand en zorg voor een vrije uitstapruimte.")
		return
	vehicle.stop()
	vehicle.enabled_input = false
	vehicle.camera.current = false
	_restore_on_foot(exit)
	_resume()
	_notify("Veilig uitgestapt. Je kunt de melding te voet benaderen.")

func _capture_state() -> void:
	state.player_position = _controlled_position() + Vector3(0, 0.1, 0) if not state.occupied_vehicle.is_empty() else officer.position
	for id in ["police_car", "fire_truck"]:
		var vehicle: Node3D = district.objects[id]
		state.vehicles[id] = {"position": [vehicle.position.x, vehicle.position.y, vehicle.position.z], "yaw": vehicle.rotation.y}
	state.dispatch = ledger.to_dict()

func _controlled_position() -> Vector3:
	return officer.global_position if state.occupied_vehicle.is_empty() else district.objects[state.occupied_vehicle].global_position

func _accepted_incident() -> bool:
	return not ledger.incident.is_empty() and ledger.incident.phase == "accepted"

func _incident_position() -> Vector3:
	var point: Array = ledger.incident.position
	return Vector3(float(point[0]), float(point[1]), float(point[2]))

func _at_incident() -> bool:
	return _accepted_incident() and state.occupied_vehicle.is_empty() and officer.global_position.distance_to(_incident_position()) < 4.0

func _navigation_text() -> String:
	if not _accepted_incident(): return "Geen actieve route  ·  R meldkamer  ·  M wijkkaart"
	var offset := _incident_position() - _controlled_position()
	var north_south := "noord" if offset.z < 0 else "zuid"
	var east_west := "oost" if offset.x > 0 else "west"
	var direction := north_south if absf(offset.z) > absf(offset.x) * 2.0 else east_west
	if absf(offset.x) > absf(offset.z) * 0.5 and absf(offset.z) > absf(offset.x) * 0.5:
		direction = north_south + east_west
	return "GPS  %.0f m · %s  |  Nog %.0f s" % [Vector2(offset.x, offset.z).length(), direction, maxf(0, float(ledger.incident.deadline) - ledger.duty_time)]

func _draw_map(map: Control) -> void:
	var center := Vector2(210, 115)
	var scale := 2.1
	map.draw_rect(Rect2(0, 0, 420, 230), Color("24413d"))
	map.draw_line(center + Vector2(-145, 17 * scale), center + Vector2(145, 17 * scale), Color("596670"), 18)
	map.draw_line(center + Vector2(-20 * scale, -110), center + Vector2(-20 * scale, 110), Color("596670"), 16)
	map.draw_line(center + Vector2(-20 * scale, -28 * scale), center + Vector2(49 * scale, -28 * scale), Color("596670"), 12)
	var landmarks := {"Bureau": Vector2(0, -4), "Kazerne": Vector2(29, -6), "Plein": Vector2(8, 31), "Werkplaats": Vector2(24, -44), "Woningen": Vector2(-39, -22)}
	for text: String in landmarks:
		var at: Vector2 = center + landmarks[text] * scale
		map.draw_circle(at, 4, Color("c7b99e"))
		map.draw_string(ThemeDB.fallback_font, at + Vector2(6, -3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("ede7d9"))
	var player_at := _controlled_position()
	map.draw_circle(center + Vector2(player_at.x, player_at.z) * scale, 5, Color("57dfd0"))
	if _accepted_incident():
		var target := _incident_position()
		map.draw_circle(center + Vector2(target.x, target.z) * scale, 6, Color("f4bf65"))
	map.draw_string(ThemeDB.fallback_font, Vector2(14, 22), "N ↑   Turkoois: jij   Geel: aangenomen melding", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("ede7d9"))

func show_radio() -> void:
	if not state.radio_checked:
		_notify("Meld je eerst aan bij de radio van je bureau of kazerne.")
		return
	_freeze()
	_clear_menu("Meldkamer", "Eenheid 112 · " + ("brandweerdienst" if state.role == "fire" else "politiedienst"))
	if ledger.incident.is_empty():
		menu_items.add_child(_label("Geen open melding. Vervolg je surveillance.", 18))
	else:
		var details := _label(str(ledger.incident.title) + "\nStatus: " + _phase_title(str(ledger.incident.phase)), 20)
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		menu_items.add_child(details)
		if ledger.incident.phase == "offered":
			_button("Melding aannemen", _accept_call)
		if ledger.incident.phase in ["offered", "accepted"]:
			_button("Doorgeven aan andere eenheid", _hand_over_call)
	var history := _label("\n".join(ledger.messages.slice(maxi(0, ledger.messages.size() - 3))), 17, Color("acd4da"))
	history.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	history.custom_minimum_size = Vector2(420, 110)
	menu_items.add_child(history)
	_button("Verder surveilleren", _resume).grab_focus()

func _phase_title(phase: String) -> String:
	return {"offered": "beschikbaar", "accepted": "aangenomen", "resolved": "afgehandeld", "handed_over": "doorgegeven", "expired": "verlopen"}.get(phase, phase)

func _accept_call() -> void:
	if ledger.accept(): _notify("Melding aangenomen. Volg de GPS-route; stap ter plaatse veilig uit.")
	_resume()

func _hand_over_call() -> void:
	if ledger.hand_over(): _notify("Meldkamer: andere eenheid neemt over. Vervolg de dienst.")
	_resume()

func _show_response() -> void:
	if not _at_incident(): return
	_freeze()
	_clear_menu("Ter plaatse", str(ledger.incident.title) + "\nKies hoe je deze eerste beoordeling uitvoert.")
	if ledger.incident.kind == "noise":
		var context := _label("Twee bewoners ruziën over lawaai. Ze staan op afstand van elkaar. Er is geen zichtbaar acuut gevaar. Hoe begin je?", 20)
		context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		menu_items.add_child(context)
		_button("Rustig luisteren en afspraken maken", _resolve_call.bind(90))
		_button("Schreeuwen en meteen schuld aanwijzen", _resolve_call.bind(25))
	else:
		var context := _label("Een voertuig blokkeert de doorgang. Betrokkenen zijn aanspreekbaar; achteropkomend verkeer nadert. Wat krijgt prioriteit?", 20)
		context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		menu_items.add_child(context)
		_button("Locatie beveiligen en betrokkenen spreken", _resolve_call.bind(95))
		_button("Snel afmelden zonder veiligstellen", _resolve_call.bind(30))
	_button("Terug naar de locatie", _resume)

func _resolve_call(quality: int) -> void:
	if not _at_incident():
		_resume()
		return
	if ledger.resolve(quality):
		_notify("Afgehandeld · zorgvuldigheid %d/100. %s" % [quality, "Rust en veiligheid zijn behouden. Je kunt verder surveilleren." if quality >= 80 else "Je aanpak liet risico's of onduidelijkheid bestaan. Neem volgende keer tijd voor luisteren en veiligheid."])
	_resume()

func _smoke_test() -> void:
	_test_timeout(30)
	start_new()
	for i in range(12): await get_tree().physics_frame
	if not is_instance_valid(officer.camera) or district.objects.size() < 5:
		push_error("SMOKE_FAIL world/player initialization")
		get_tree().quit(1)
		return
	print("SCENE112_SMOKE_OK engine=", Engine.get_version_info().string, " objects=", district.objects.size())
	_test_finished = true
	get_tree().quit(0)

func _playthrough() -> void:
	_test_timeout(40)
	start_new()
	for i in range(20): await get_tree().physics_frame
	var start_position := officer.position
	Input.action_press("move_forward")
	for i in range(90): await get_tree().physics_frame
	Input.action_release("move_forward")
	if officer.position.distance_to(start_position) < 1.0:
		push_error("PLAYTHROUGH_FAIL movement")
		get_tree().quit(1)
		return
	for id in ["equipment", "radio", "academy"]:
		var point: Node3D = district.objects[id]
		officer.position = point.global_position + Vector3(0, 0.1, 1.5)
		for i in range(3): await get_tree().physics_frame
		var target: Dictionary = district.get_interaction(officer.position)
		if target.get("id", "") != id:
			push_error("PLAYTHROUGH_FAIL proximity: " + id)
			get_tree().quit(1)
			return
		district.interact(id)
	var test_path := "user://playthrough-test.json"
	state.player_position = officer.position
	if not state.save_to(test_path):
		get_tree().quit(1)
		return
	var resumed := State.new()
	if not resumed.load_from(test_path) or not resumed.equipment or not resumed.radio_checked or resumed.academy_visits != 1:
		push_error("PLAYTHROUGH_FAIL save/load")
		get_tree().quit(1)
		return
	officer.position = Vector3(0, 0.1, 6)
	for i in range(5): await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://m0-playthrough.png")
	DirAccess.remove_absolute(test_path)
	DirAccess.remove_absolute(test_path + ".bak")
	print("SCENE112_PLAYTHROUGH_OK walking, proximity, equipment, radio, academy, save/load; screenshot=", OS.get_user_data_dir())
	_test_finished = true
	get_tree().quit(0)

func _test_timeout(seconds: float) -> void:
	get_tree().create_timer(seconds).timeout.connect(func():
		if not _test_finished:
			push_error("SCENE112_TEST_TIMEOUT")
			get_tree().quit(1))

func _check(condition: bool, description: String) -> bool:
	if condition: return true
	_test_finished = true
	push_error("DUTY_FAIL " + description)
	get_tree().quit(1)
	return false

func _press_menu(title: String) -> bool:
	for child in menu_items.get_children():
		if child is Button and child.text == title and not child.disabled:
			child.pressed.emit()
			return true
	return _check(false, "missing menu action: " + title)

func _test_frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame

func _wait_for(condition: Callable, description: String, seconds: float = 4.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call():
		if _test_finished: return false
		if Time.get_ticks_msec() >= deadline:
			return _check(false, "timeout waiting for " + description)
		# Proximity prompts update in _process, independently of physics ticks.
		# Waiting for the observed result works with both slow GPU frames and
		# headless rendering; extra physics ticks are not evidence of UI progress.
		await get_tree().process_frame
	return true

func _menu_title_is(title: String) -> bool:
	return menu.visible and menu_items.get_child_count() > 0 and menu_items.get_child(0) is Label and menu_items.get_child(0).text == title

func _tap_action(action: String, acknowledged: Callable, description: String) -> bool:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	var observed: bool = await _wait_for(acknowledged, description)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	return observed

func _test_station(id: String) -> bool:
	var point: Node3D = district.objects[id]
	officer.global_position = point.global_position + Vector3(0, 0.1, 1.5)
	officer.velocity = Vector3.ZERO
	if not await _wait_for(func(): return current_target.get("id", "") == id, "station proximity " + id): return false
	var previous_visits: int = state.academy_visits
	var acknowledged := func():
		match id:
			"equipment", "fire_equipment": return state.equipment
			"radio", "fire_radio": return state.radio_checked
			"academy": return state.academy_visits > previous_visits
		return false
	return await _tap_action("interact", acknowledged, "station interaction " + id)

func _test_vehicle(id: String) -> bool:
	var vehicle: Node3D = district.objects[id]
	officer.global_position = vehicle.global_position + Vector3(1.8, 0.1, 0)
	officer.velocity = Vector3.ZERO
	if not await _wait_for(func(): return current_target.get("id", "") == id, "vehicle proximity " + id): return false
	if not await _tap_action("interact", func(): return state.occupied_vehicle == id, "vehicle entry " + id): return false
	if not _check(state.occupied_vehicle == id and not officer.visible and not officer.is_physics_processing() and officer.collision_layer == 0 and vehicle.camera.current, "seating " + id): return false
	var start: Vector3 = vehicle.global_position
	Input.action_press("move_forward")
	await _test_frames(90)
	Input.action_release("move_forward")
	if not _check(vehicle.global_position.distance_to(start) > 3.0, "driving " + id): return false
	if not await _tap_action("interact", func(): return notice.text.begins_with("Kom eerst tot stilstand"), "moving exit rejected " + id): return false
	if not _check(state.occupied_vehicle == id, "exit while moving rejected " + id): return false
	Input.action_press("brake")
	await _test_frames(60)
	Input.action_release("brake")
	return _check(absf(vehicle.speed) < 0.1, "braking " + id)

func _duty_playthrough() -> void:
	_test_timeout(55)
	if not _press_menu("Vrije politiedienst"): return
	await _test_frames(8)
	if not _check(active and not paused and state.role == "police", "police menu transition"): return
	if not await _test_station("equipment"): return
	if not await _test_station("radio"): return
	if not await _test_station("academy"): return
	var npc_start: Vector3 = district.objects.npc_0.global_position
	if not await _test_vehicle("police_car"): return
	if not _check(district.objects.npc_0.global_position.distance_to(npc_start) > 0.5, "civilian movement"): return
	var test_path := "user://duty-playthrough-test.json"
	save_game(test_path)
	save_game(test_path)
	if not _check(FileAccess.file_exists(test_path + ".bak"), "seated backup created"): return
	var saved_position: Vector3 = district.objects.police_car.global_position
	_show_main()
	load_game(test_path)
	if not _check(state.occupied_vehicle == "police_car" and district.objects.police_car.camera.current and not officer.visible, "seated load transition"): return
	if not _check(district.objects.police_car.global_position.distance_to(saved_position) < 0.1, "vehicle pose round trip"): return
	var corrupt := FileAccess.open(test_path, FileAccess.WRITE)
	if not _check(corrupt != null, "corrupt test slot open"): return
	corrupt.store_string("{broken")
	corrupt.close()
	load_game(test_path)
	if not _check(state.occupied_vehicle == "police_car", "seated backup recovery"): return
	if not await _tap_action("interact", func(): return state.occupied_vehicle.is_empty(), "exit after loaded seating"): return
	if not _check(state.occupied_vehicle.is_empty() and officer.visible and officer.camera.current and officer.is_physics_processing(), "exit restores officer"): return
	await _test_frames(10)
	_pause()
	var frozen_npc: Vector3 = district.objects.npc_0.global_position
	var frozen_time: float = ledger.duty_time
	await _test_frames(20)
	if not _check(district.objects.npc_0.global_position == frozen_npc and ledger.duty_time == frozen_time, "pause freezes simulation"): return
	if not _press_menu("Dienst hervatten"): return
	ledger.tick(maxf(0.01, 20.1 - ledger.duty_time))
	if not await _tap_action("radio", func(): return paused and _menu_title_is("Meldkamer"), "radio panel opens"): return
	if not _check(paused and ledger.incident.phase == "offered", "radio offered panel"): return
	if not _press_menu("Melding aannemen"): return
	if not _check(_accepted_incident() and incident_marker.visible, "accepted route marker"): return
	officer.global_position = _incident_position() + Vector3(0, 0.1, 1)
	officer.velocity = Vector3.ZERO
	if not await _wait_for(func(): return current_target.get("id", "") == "incident_response", "noise arrival prompt"): return
	if not await _tap_action("interact", func(): return paused and _menu_title_is("Ter plaatse"), "noise response panel"): return
	if not _press_menu("Rustig luisteren en afspraken maken"): return
	if not _check(ledger.incident.phase == "resolved" and ledger.incident.quality == 90 and not incident_marker.visible, "noise response quality and marker"): return
	ledger.tick(30.1)
	if not await _tap_action("radio", func(): return paused and _menu_title_is("Meldkamer"), "repeat radio panel"): return
	if not _press_menu("Melding aannemen"): return
	if not _check(ledger.incident.kind == "traffic", "repeat incident variation"): return
	officer.global_position = _incident_position() + Vector3(0, 0.1, 1)
	officer.velocity = Vector3.ZERO
	if not await _wait_for(func(): return current_target.get("id", "") == "incident_response", "traffic arrival prompt"): return
	if not await _tap_action("interact", func(): return paused and _menu_title_is("Ter plaatse"), "traffic response panel"): return
	if not _press_menu("Snel afmelden zonder veiligstellen"): return
	if not _check(ledger.incident.phase == "resolved" and ledger.incident.quality == 30 and ledger.completed == 2, "poor response consequence"): return
	ledger.tick(30.1)
	if not await _tap_action("radio", func(): return paused and _menu_title_is("Meldkamer"), "handover radio panel"): return
	if not _press_menu("Doorgeven aan andere eenheid"): return
	if not _check(ledger.incident.phase == "handed_over" and not incident_marker.visible, "handover and continue"): return
	ledger.tick(30.1)
	ledger.tick(90.1)
	_update_objective()
	if not _check(ledger.incident.phase == "expired" and ledger.missed > 0 and not incident_marker.visible, "unanswered incident expires"): return
	# This is a deterministic five-minute clock soak, not a human playthrough.
	ledger.tick(maxf(0, 300.0 - ledger.duty_time))
	var automated_seconds: float = ledger.duty_time
	_capture_state()
	var round_trip := State.new()
	if not _check(automated_seconds >= 300 and round_trip.restore(state.to_dict()), "300 second automated duty soak and save validation"): return
	_show_main()
	if not _press_menu("Vrije brandweerdienst"): return
	await _test_frames(8)
	if not _check(state.role == "fire" and officer.position.distance_to(Vector3(28, 0.1, 0)) < 0.2 and ledger.serial == 0, "fire menu resets duty"): return
	if not await _test_station("fire_equipment"): return
	if not await _test_station("fire_radio"): return
	if not await _test_vehicle("fire_truck"): return
	if not await _tap_action("interact", func(): return state.occupied_vehicle.is_empty(), "fire vehicle exit"): return
	if not _check(state.occupied_vehicle.is_empty() and state.equipment and state.radio_checked, "fire duty and exit"): return
	await _test_frames(5)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var screenshot_result := get_viewport().get_texture().get_image().save_png("user://m1-playthrough.png")
		if not _check(screenshot_result == OK, "graphical screenshot"): return
	DirAccess.remove_absolute(test_path)
	DirAccess.remove_absolute(test_path + ".bak")
	print("SCENE112_DUTY_OK both duty menus, driving/braking, enter/exit, seated save/load+backup, NPC movement/pause, dispatch accept/resolve/repeat/handover/expire; automated_duty_seconds=", automated_seconds)
	_test_finished = true
	get_tree().quit(0)
