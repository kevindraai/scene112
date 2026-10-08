extends Node3D

const State = preload("res://scripts/game_state.gd")
const World = preload("res://scripts/world.gd")
const Player = preload("res://scripts/player.gd")
var state := State.new()
var district: Node3D
var officer: CharacterBody3D
var canvas: CanvasLayer
var menu: PanelContainer
var menu_items: VBoxContainer
var hud: Control
var objective: Label
var prompt: Label
var notice: Label
var active := false
var paused := false
var current_target := {}
var notice_time := 0.0
var test_mode := false

func _ready() -> void:
	_bind_inputs()
	district = World.new()
	add_child(district)
	officer = Player.new()
	add_child(officer)
	officer.position = state.player_position
	officer.enable_input = false
	district.interacted.connect(_interact)
	_build_ui()
	_show_main()
	var args := OS.get_cmdline_user_args()
	test_mode = "--smoke-test" in args or "--playthrough" in args
	if "--smoke-test" in args:
		_smoke_test.call_deferred()
	elif "--playthrough" in args:
		_playthrough.call_deferred()

func _bind_inputs() -> void:
	var keys := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A,
		"move_right": KEY_D, "sprint": KEY_SHIFT, "interact": KEY_E, "pause": KEY_ESCAPE,
		"save_game": KEY_F5, "load_game": KEY_F9, "map": KEY_M}
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
	top.custom_minimum_size = Vector2(490, 112)
	top.add_theme_stylebox_override("panel", _panel(Color(0.055, 0.12, 0.16, 0.94)))
	hud.add_child(top)
	var box := VBoxContainer.new()
	top.add_child(box)
	box.add_child(_label("SCÈNE 112  /  NOORDERKADE", 23, Color(0.42, 0.87, 0.83)))
	objective = _label("", 18)
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(objective)
	prompt = _label("", 22, Color(1, 0.81, 0.39))
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.position = Vector2(-300, -108)
	prompt.size = Vector2(600, 50)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(prompt)
	var controls := _label("WASD  lopen  ·  Shift  sprint  ·  E  handelen  ·  M  wijkkaart  ·  Esc  pauze", 17)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.position = Vector2(24, -40)
	hud.add_child(controls)
	notice = _label("", 18, Color(1, 0.86, 0.6))
	notice.position = Vector2(24, 162)
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
	active = false
	paused = true
	officer.enable_input = false
	hud.hide()
	_clear_menu("SCÈNE 112", "Een nieuwe dienst begint aan de Noorderkade.\nOntwikkelbuild M0 · Nederlandstalig · 14+")
	var candidate := State.new()
	_button("Doorgaan", load_game, not candidate.load_from())
	_button("Nieuwe dienst", start_new).grab_focus()
	_button("Bediening en wijkkaart", show_help)
	_button("Instellingen", show_settings)
	_button("Licenties", show_credits)
	_button("Afsluiten", func(): get_tree().quit())

func start_new() -> void:
	state = State.new()
	officer.position = state.player_position
	officer.velocity = Vector3.ZERO
	officer.sensitivity = state.sensitivity
	active = true
	_resume()
	_notify("Welkom. Loop naar de uitrusting bij het bureau. Druk E wanneer je dichtbij staat.")

func _resume() -> void:
	paused = false
	menu.hide()
	hud.show()
	officer.enable_input = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_objective()

func _pause() -> void:
	paused = true
	officer.enable_input = false
	_clear_menu("Dienstpauze", "Je dienst blijft bewaard in dit venster. F5 slaat op; F9 laadt je laatste opslag.")
	_button("Dienst hervatten", _resume).grab_focus()
	_button("Dienst opslaan", save_game)
	var candidate := State.new()
	_button("Laatste opslag laden", load_game, not candidate.load_from())
	_button("Bediening en wijkkaart", show_help)
	_button("Instellingen", show_settings)
	_button("Naar hoofdmenu", _show_main)

func show_help() -> void:
	paused = true
	officer.enable_input = false
	_clear_menu("Noorderkade", "WASD: lopen · Shift: sprint · Muis: rondkijken\nE: dichtbij handelen · F5/F9: opslaan/laden · Esc: pauze")
	var text := _label("BUREAU  →  uitrusting en radio\nACADEMIE  →  oefenplek naast het bureau\nKAZERNE  →  aan de overzijde van de hoofdweg\nPLEIN  →  winkels en woningen\n\nM0: neem uitrusting, meld je bij de radio en bezoek de academie. Sla op en hervat je dienst. Voertuigen en incidenten volgen na de platformpoort.", 19)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(420, 280)
	menu_items.add_child(text)
	_button("Terug", _back).grab_focus()

func show_settings() -> void:
	paused = true
	officer.enable_input = false
	_clear_menu("Instellingen", "Pas het cameragevoel aan. De instelling wordt met je dienst opgeslagen.")
	menu_items.add_child(_label("Muisgevoeligheid"))
	var slider := HSlider.new()
	slider.min_value = 0.001
	slider.max_value = 0.008
	slider.step = 0.0005
	slider.value = state.sensitivity
	slider.value_changed.connect(func(value):
		state.sensitivity = value
		if "sensitivity" in officer: officer.sensitivity = value)
	menu_items.add_child(slider)
	_button("Volledig scherm aan/uit", func():
		var mode := DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN))
	_button("Terug", _back).grab_focus()

func show_credits() -> void:
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
		if event.is_action_pressed("interact") and not current_target.is_empty():
			district.interact(current_target.id)
		elif event.is_action_pressed("map"): show_help()

func _process(delta: float) -> void:
	if not active or paused:
		return
	current_target = district.get_interaction(officer.global_position)
	prompt.text = "[E] " + str(current_target.title) if not current_target.is_empty() else ""
	if notice_time > 0:
		notice_time -= delta
		if notice_time <= 0: notice.text = ""

func _interact(id: String) -> void:
	match id:
		"equipment":
			state.equipment = true
			_notify("Uitrusting gecontroleerd: portofoon, notitieboek en veiligheidsvest. Meld je bij de radio.")
		"radio":
			if not state.equipment:
				_notify("Neem eerst je uitrusting mee. Een veilige dienst begint voorbereid.")
			else:
				state.radio_checked = true
				_notify("Meldkamer: eenheid 112 aangemeld. Verken de wijk en bezoek de academie.")
		"academy":
			if not state.radio_checked:
				_notify("Controleer eerst uitrusting en radio bij het bureau.")
			else:
				state.academy_visits += 1
				_notify("Oefenplek bereikt. Basisronde afgerond. Sla je dienst op met F5; hervat met F9.")
		"board": show_help()
		_: _notify("Dit materieel staat klaar voor de volgende speelmijlpaal.")
	_update_objective()

func _update_objective() -> void:
	if not state.equipment: objective.text = "01  Neem je uitrusting bij het bureau."
	elif not state.radio_checked: objective.text = "02  Meld je aan bij de portofoon/radio."
	elif state.academy_visits == 0: objective.text = "03  Bezoek de academie naast het bureau."
	else: objective.text = "Dienst gereed voor verkenning  ·  F5 opslaan"

func _notify(message: String) -> void:
	notice.text = message
	notice_time = 9.0

func save_game() -> void:
	state.player_position = officer.position
	if state.save_to(): _notify("Dienst opgeslagen. Positie en voortgang zijn bewaard.")
	else: _notify(state.save_error)

func load_game() -> void:
	var loaded := State.new()
	if not loaded.load_from():
		_notify("Geen geldige opslag gevonden. Begin een nieuwe dienst; je bestand blijft behouden.")
		return
	state = loaded
	officer.position = state.player_position
	officer.velocity = Vector3.ZERO
	if "sensitivity" in officer: officer.sensitivity = state.sensitivity
	active = true
	_resume()
	_notify("Dienst hervat vanaf je laatste opslag.")

func _smoke_test() -> void:
	start_new()
	for i in range(12): await get_tree().physics_frame
	if not is_instance_valid(officer.camera) or district.objects.size() < 5:
		push_error("SMOKE_FAIL world/player initialization")
		get_tree().quit(1)
		return
	print("SCENE112_SMOKE_OK engine=", Engine.get_version_info().string, " objects=", district.objects.size())
	get_tree().quit(0)

func _playthrough() -> void:
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
	get_tree().quit(0)
