class_name OutsideFireController
extends RefCounted
## Bounded controller for accepted free-fire calls; root owns dispatch lifecycle.
signal completed(score: Dictionary)
var _app: Node3D
var _model: RefCounted
var _site: Node3D
var _crosshair: Label
var _drive_start := Vector3.ZERO
var _warning_cooldown := 0.0
var _simulation_accumulator := 0.0
var _spraying := false

func setup(app: Node3D, model: RefCounted, site: Node3D) -> void:
	_app = app; _model = model; _site = site
	_simulation_accumulator = 0.0; _spraying = false
	_site.set_carrier(app.officer)
	_site.setup(model)
	_drive_start = app.district.objects.fire_truck.global_position
	if not is_instance_valid(_crosshair):
		_crosshair = app._label("+", 28, Color("bbe1e0"))
		_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_crosshair.position = Vector2(-12, -20); _crosshair.size = Vector2(24, 40)
		_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		app.hud.add_child(_crosshair)
	_crosshair.hide()

func start(incident_id: int, variant: int, origin: Vector3) -> bool:
	if not _model.begin(incident_id, variant, origin): return false
	_drive_start = _app.district.objects.fire_truck.global_position
	_site.setup(_model)
	_update_basics()
	return true

func tick(delta: float) -> void:
	var active: bool = _app.active and not _app.paused and _model.mode != "none"
	_site.set_simulation_active(active)
	_crosshair.visible = active and _model.phase == "active" and _app.state.occupied_vehicle.is_empty()
	if not active:
		_simulation_accumulator = 0.0; _spraying = false
		_site.show_jet("", false)
		_audio_context(false)
		return
	if _model.phase == "completed":
		_site.update_state(_model); _audio_context(true); return
	if _app.state.occupied_vehicle.is_empty():
		var nearby: Dictionary = _site.get_interaction(_app.officer)
		if not nearby.is_empty():
			_app.current_target = nearby
			_app.prompt.text = "[E] " + str(nearby.title)
	_warning_cooldown = maxf(0, _warning_cooldown - delta)
	_update_basics()
	var target := ""
	var request_water := false
	if _model.phase == "active" and _app.state.occupied_vehicle.is_empty():
		target = _site.raycast_target(_app.officer.camera, _app.officer)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if not _model.has_nozzle_at(_app.officer.global_position): _warn("Leg de slang met Q tot bij je veilige werkplek; houd afstand van de brand.")
			else: request_water = true
		_crosshair.text = "+" if target.is_empty() else "⊕"
	if not request_water: _spraying = false
	# Fixed 20 Hz preserves identical replay operations across renderer speeds.
	# Cap catch-up after a long stalled frame; pause never banks simulation time.
	_simulation_accumulator = minf(0.25, _simulation_accumulator + maxf(0, delta))
	while _simulation_accumulator >= 0.05:
		_simulation_accumulator -= 0.05
		_model.tick(0.05, _app._controlled_position())
		if request_water:
			_spraying = _model.spray(target, 0.05)
			if not _spraying: _warn("De straal krijgt onvoldoende water. Laat de toevoer de tank aanvullen.")
	_site.show_jet(target, _spraying)
	_site.update_state(_model)
	_audio_context(true)
	_app.objective.text = _model.objective()
	_app.duty_label.text = "Brandweer · Buitenbrand · Water %.0f l · Slang %.1f m" % [_model.water_liters, _model.hose_length()]
	_app.route_label.text = "Buitenbrand · %.0f m · Q: slang · links: gerichte straal · R: inzet" % _app._controlled_position().distance_to(_model.origin)

func _audio_context(active: bool) -> void:
	if not is_instance_valid(_app.audio) or not _app.audio.has_method("update_outside_fire"): return
	var context := {"mode": "none"}
	if active:
		var cells: Array = []
		for cell: Dictionary in _model.cells: cells.append({"id": cell.id, "pos": cell.pos.duplicate(), "heat": cell.heat})
		context = {"mode": _model.mode, "phase": _model.phase, "clock": _model.clock,
			"water_liters": _model.water_liters, "cells": cells, "withdrew": _model.withdrew}
	_app.audio.update_outside_fire(context, _app.officer.global_position, _spraying if active else false)

func _update_basics() -> void:
	if _model.mode == "none" or _model.phase != "briefing": return
	if _app.state.equipment and not _model.basics.gear: _model.complete_step("gear")
	if _app.state.radio_checked and not _model.basics.radio: _model.complete_step("radio")
	if _app.state.occupied_vehicle == "fire_truck":
		if not _model.basics.enter: _model.complete_step("enter")
		var truck: Node3D = _app.district.objects.fire_truck
		if not _model.basics.drive and truck.global_position.distance_to(_drive_start) > 20 and truck.global_position.distance_to(_model.origin) < 17: _model.complete_step("drive")
	elif _model.basics.drive and not _model.basics.exit and _app.officer.global_position.distance_to(_model.origin) < 17: _model.complete_step("exit")

func on_interact(id: String) -> bool:
	if _model.mode == "none" or not id.begins_with("outside_"): return false
	if not _site.can_reach(id, _app.officer):
		_app._notify("Benader deze verkenning of waterbron via een vrije zichtlijn."); return true
	match id:
		"outside_exterior":
			var ok: bool = _model.check_recon("exterior")
			_app._notify("Verkend: %s branden in drie afzonderlijke haarden. Blijf buiten en werk vanaf de vrije zijde." % _model.MATERIALS[_model.variant] if ok else _model.objective())
		"outside_surroundings":
			var ok: bool = _model.check_recon("surroundings")
			_app._notify("Omgeving gecontroleerd: geen slachtoffers; de vrije terugweg ligt aan de gemarkeerde zijde." if ok else _model.objective())
		"outside_water":
			var ok: bool = _model.connect_water()
			_app._notify("Watertoevoer aangesloten. Richt Q op de grond aan de veilige zijde om de slang te leggen." if ok else _model.objective())
		"outside_plan": _show_plan()
		_: return false
	_site.update_state(_model)
	return true

func handle_input(event: InputEvent) -> bool:
	if _model.mode == "none" or _model.phase == "completed" or not _app.active or _app.paused: return false
	if event.is_action_pressed("radio"):
		_show_plan(); return true
	if not (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q): return false
	if not _app.state.occupied_vehicle.is_empty():
		_app._notify("Parkeer en stap uit om de slang te leggen."); return true
	var camera: Camera3D = _app.officer.camera
	var center := camera.get_viewport().get_visible_rect().size / 2
	var origin := camera.project_ray_origin(center)
	var direction := camera.project_ray_normal(center)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 18, 1, [_app.officer.get_rid()])
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < 0.9 or absf(hit.position.y) > 0.15 or _app.officer.global_position.distance_to(hit.position) > 8:
		_app._notify("Richt Q op vrij wegdek dichtbij je, aan de gemarkeerde zijde van de brand.")
	elif _model.add_hose_point(hit.position): _app._notify("Slang gelegd · %.1f m totaal." % _model.hose_length())
	else: _app._notify("Sluit eerst water aan. Houd veilige afstand en leg segmenten van 0,7–7,5 m, maximaal 35 m totaal.")
	_site.update_state(_model)
	return true

func _modal(title: String, subtitle: String) -> void:
	_app._freeze(); _site.set_simulation_active(false); _site.show_jet("", false); _crosshair.hide()
	_audio_context(false)
	_app.prompt.text = ""; _app.current_target = {}; _app._clear_menu(title, subtitle)

func _show_plan() -> void:
	if _model.phase == "completed":
		_show_report(_model.report_score); return
	_modal("Buitenbrand · inzet", "Begrensde fictieve buiteninzet. Verken, sluit water aan en koel de zichtbare haarden afzonderlijk.")
	if _model.phase == "briefing":
		var ready: bool = _model.recon.exterior and _model.recon.surroundings and _model.hydrant_connected
		_app._button("Defensieve buiteninzet beginnen", _choose, not ready)
		var text: Label = _app._label(_model.objective(), 19); text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; text.custom_minimum_size = Vector2(420, 110); _app.menu_items.add_child(text)
	else:
		_app._button("Nasmeulcontrole en overdracht", _finish.bind(false), not _model.all_cold())
		_app._button("Veilig terugtrekken en doorgeven", _finish.bind(true))
	_app._button("Meldkamer · doorgeven", _app.show_radio)
	_app._button("Terug naar de werkplek", _app._resume)

func _choose() -> void:
	if _model.choose_tactic("defensive"):
		_app._resume(); _app._notify("Buiteninzet gestart. Richt de straal op één zichtbare haard; missen verbruikt ook water.")
	else: _app._notify(_model.objective())

func _finish(withdraw: bool) -> void:
	var score: Dictionary = _model.finish(withdraw)
	if score.is_empty():
		_app._notify(_model.objective()); return
	_site.update_state(_model); _audio_context(true); completed.emit(score.duplicate(true)); _show_report(score)

func _show_report(score: Dictionary) -> void:
	_modal("Buitenbrand · overdracht", "De kwaliteit van de inzet volgt uit je werkelijke handelingen en de overgebleven incidentstaat.")
	var text: Label = _app._label("%s · %d/100\nBlussing %d/40 · Watergebruik %d/15 · Veiligheid %d/10\nVerbruik %.0f liter · Verbrande fractie %.0f%%" % ["Zorgvuldig afgehandeld" if score.result == "careful" else "Gedeeltelijk / overgedragen", score.total, score.suppression, score.accuracy, score.safety, score.water_used, float(score.damage) * 100], 19)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; text.custom_minimum_size = Vector2(420, 160); _app.menu_items.add_child(text)
	_app._button("Vrije dienst vervolgen", _app._resume)

func _warn(message: String) -> void:
	if _warning_cooldown <= 0:
		_app._notify(message); _warning_cooldown = 4.0
