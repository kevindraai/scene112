class_name FingerprintTask
extends Control
## Physical alignment and sustained contact; no key instantly registers a print.

signal captured(quality: int)
signal finished

var accepted_count := 0
var pointer := 0.28
var target := 0.62
var progress := 0.0
var last_quality := 0
var _clock := 0.0
var _held := false
var _awaiting := false
var _error_sum := 0.0
var _sample_time := 0.0
var _status: Label
var _next: Button
var _retry: Button


func _ready() -> void:
	custom_minimum_size = Vector2(420, 285)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_status = Label.new()
	_status.position = Vector2(8, 154)
	_status.size = Vector2(400, 34)
	_status.add_theme_font_size_override("font_size", 16)
	_status.text = "Positioneer de vinger en houd links ingedrukt."
	add_child(_status)
	_next = Button.new()
	_next.text = "Volgende vinger"
	_next.position = Vector2(8, 194)
	_next.size = Vector2(400, 37)
	_next.disabled = true
	_next.pressed.connect(func():
		if accepted_count >= 3: finished.emit()
		else: _reset_capture())
	add_child(_next)
	_retry = Button.new()
	_retry.text = "Opnieuw positioneren"
	_retry.position = Vector2(8, 239)
	_retry.size = Vector2(400, 37)
	_retry.disabled = true
	_retry.pressed.connect(_reset_capture)
	add_child(_retry)
	grab_focus()


func accept_capture(accepted: bool) -> void:
	if accepted:
		accepted_count += 1
		_status.text = "Kwaliteit %d/100 · %d van 3 bruikbaar." % [last_quality, accepted_count]
		_next.text = "Registratie afronden" if accepted_count >= 3 else "Volgende vinger"
		_next.disabled = false
		_retry.disabled = true
	else:
		_status.text = "Kwaliteit %d/100 · positioneer opnieuw." % last_quality
		_retry.disabled = false
		_next.disabled = true


func _reset_capture() -> void:
	progress = 0
	_error_sum = 0
	_sample_time = 0
	_awaiting = false
	_held = false
	pointer = 0.25 if accepted_count % 2 == 0 else 0.75
	_next.disabled = true
	_retry.disabled = true
	_status.text = "Vinger %d · uitlijnen en 1 seconde contact houden." % (accepted_count + 1)
	grab_focus()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.position.y < 150:
		pointer = clampf((event.position.x - 32) / maxf(1, size.x - 64), 0, 1)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_held = event.pressed and event.position.y < 150
		if _held: grab_focus()
		accept_event()
	elif event is InputEventKey and event.physical_keycode == KEY_SPACE:
		# Space provides contact while this surface owns keyboard focus; it
		# cannot also activate a previously focused Next or Cancel button.
		accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_held = false


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		_held = false
		return
	if _awaiting:
		queue_redraw()
		return
	_clock += delta
	target = 0.52 + sin(_clock * 1.25 + accepted_count * 1.7) * 0.14
	if InputMap.has_action("move_left") and InputMap.has_action("move_right"):
		pointer = clampf(pointer + Input.get_axis("move_left", "move_right") * delta * 0.55, 0, 1)
	var contact := _held or (InputMap.has_action("brake") and Input.is_action_pressed("brake"))
	var error := absf(pointer - target)
	if contact:
		_error_sum += error * delta
		_sample_time += delta
		progress = clampf(progress + delta if error < 0.08 else progress - delta * 1.5, 0, 1)
	else:
		progress = maxf(0, progress - delta * 0.5)
	if progress >= 1.0:
		_awaiting = true
		_held = false
		var quality := clampi(roundi(100 - _error_sum / maxf(0.01, _sample_time) * 380), 0, 100)
		last_quality = quality
		captured.emit(quality)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, size.x, 145), Color("20333e"))
	var width := maxf(1, size.x - 64)
	var target_x := 32 + target * width
	var pointer_x := 32 + pointer * width
	draw_line(Vector2(32, 100), Vector2(size.x - 32, 100), Color("506571"), 2)
	draw_rect(Rect2(target_x - 24, 48, 48, 84), Color("68d0b3"), false, 3)
	draw_circle(Vector2(pointer_x, 76), 14, Color("dab191"))
	draw_rect(Rect2(pointer_x - 14, 76, 28, 54), Color("dab191"))
	draw_rect(Rect2(8, 135, size.x - 16, 6), Color("425563"))
	draw_rect(Rect2(8, 135, (size.x - 16) * progress, 6), Color("68d0b3"))
	draw_string(ThemeDB.fallback_font, Vector2(12, 24), "Muis of A/D: uitlijnen · linkermuis of Spatie: contact", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("edf1eb"))
