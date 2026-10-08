class_name FireController
extends RefCounted
## Spatial hose/nozzle/rescue gameplay for a bounded fictional crew scenario.

signal completed(mode: String, score: Dictionary)
var _app: Node3D
var _model: RefCounted
var _site: Node3D
var _crosshair: Label
var _mode := ""
var _warning_cooldown := 0.0
var _drive_start := Vector3(28, 0, 5)


func setup(app: Node3D, model: RefCounted, site: Node3D) -> void:
	_app = app
	_model = model
	_site = site
	_site.set_carrier(app.officer)
	_site.reset_entry_access()
	_mode = ""
	if not is_instance_valid(_crosshair):
		_crosshair = _app._label("+", 28, Color("bbe1e0"))
		_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_crosshair.position = Vector2(-12, -20)
		_crosshair.size = Vector2(24, 40)
		_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_app.hud.add_child(_crosshair)
	_sync()


func start_campaign() -> void:
	_start("campaign")


func start_lesson() -> void:
	_start("lesson")


func start_free_incident() -> void:
	_start("free")


func _start(mode: String) -> void:
	_app.start_training("fire")
	_model.begin(mode)
	_drive_start = _app.district.objects.fire_truck.global_position
	_sync()
	_modal("De woningbrand", "Huis 24 · Begrensd fictief scenario. Ploeg, PBM en ademlucht zijn gesimuleerd. Dit spel geeft geen operationele instructie.")
	var text: Label = _app._label("Controleer uitrusting en radio, rijd naar Huis 24 en verken buiten. Sluit water aan, leg zelf de slang en koel gericht met de straal. De toegang opent pas bij de beschermde spelconditie; draag het slachtoffer daarna zelf naar de opvang.", 19)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(420, 180)
	_app.menu_items.add_child(text)
	_app._button("Dienst beginnen", _app._resume)
	_app._button("Terug naar hoofdmenu", _app._show_main)


func _sync() -> void:
	if _mode != str(_model.mode):
		_mode = str(_model.mode)
		_site.set_mode(_mode)
	_site.update_state(_model)
	if _app.state.occupied_vehicle.is_empty(): _app.officer.collision_mask = 9 if _model.mode != "none" else 1
	var carrying: bool = _model.mode != "none" and _model.victim.status == "carried"
	if "speed_scale" in _app.officer: _app.officer.speed_scale = 0.6 if carrying else 1.0
	_crosshair.visible = _model.mode != "none" and _model.phase == "active" and not _app.paused and not carrying and _app.state.occupied_vehicle.is_empty()


func tick(delta: float) -> void:
	_sync()
	_site.set_simulation_active(_app.active and not _app.paused)
	if not _app.active or _app.paused or _model.mode == "none":
		_site.show_jet("", false)
		if is_instance_valid(_app.audio):
			var context: Dictionary = _model.to_dict() if _app.active else {"mode": "none"}
			_app.audio.update_fire(context, _app.officer.global_position, _site.is_inside(_app.officer.global_position) if _app.active else false, false)
		return
	_warning_cooldown = maxf(0, _warning_cooldown - delta)
	var basics: Dictionary = _model.basics
	if _app.state.equipment and not basics.equipment: _model.complete_step("equipment")
	if _app.state.radio_checked and not basics.radio: _model.complete_step("radio")
	if _app.state.occupied_vehicle == "fire_truck":
		if not basics.enter: _model.complete_step("enter")
		var truck: Node3D = _app.district.objects.fire_truck
		if not basics.drive and truck.global_position.distance_to(_drive_start) > 20 and truck.global_position.distance_to(_site.HOUSE) < 17:
			_model.complete_step("drive")
	elif basics.drive and not basics.exit and _app.officer.global_position.distance_to(_site.HOUSE) < 17:
		_model.complete_step("exit")
	var inside: bool = _site.is_inside(_app.officer.global_position)
	_model.tick(delta, inside)
	var target := ""
	var spraying := false
	if _model.phase == "active" and _app.state.occupied_vehicle.is_empty() and _model.victim.status != "carried":
		target = _site.raycast_target(_app.officer.camera, _app.officer)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if not _model.has_nozzle_at(_app.officer.global_position):
				_warn("De slang moet tot bij je werkplek liggen. Verleng de route met Q.")
			else:
				spraying = _model.spray(target, delta)
				if not spraying: _warn("Controleer water en toevoer; de straal heeft nu onvoldoende water.")
		_crosshair.text = "+" if target.is_empty() else "⊕"
	_site.show_jet(target, spraying)
	_app.audio.update_fire(_model.to_dict(), _app.officer.global_position, inside, spraying)
	_site.update_state(_model)
	if inside and not _model.can_enter() and _model.phase == "active": _warn("Spelconditie verslechterd: trek terug en koel vanuit een veilige plek.")
	_app.objective.text = _model.objective()
	_app.duty_label.text = "Brandweer · Water %.0f l · Ademlucht %.0f%% · Slang %.1f m" % [_model.water_liters, _model.oxygen, _model.hose_length()]
	var distance: float = _app._controlled_position().distance_to(_site.HOUSE)
	_app.route_label.text = "Huis 24 · %.0f m · Q: slang · Muis: richten · links: water · R: inzet" % distance
	if _model.victim.status == "carried": _app.route_label.text = "Slachtoffer gedragen · loop naar de veilige opvang · E: overdracht"


func on_interact(id: String) -> bool:
	if _model.mode == "none": return false
	match id:
		"fire_exterior":
			var ok: bool = _model.check_recon("exterior")
			_app._notify("Buitenverkenning: rook in woning, slachtoffer voorin; vluchtweg en opvang liggen buiten." if ok else _model.objective())
		"fire_door":
			var ok: bool = _model.check_recon("door")
			_app._notify("Deur gecontroleerd. Eerst zichtbaar vuur koelen; binnengaan wacht op de beschermde spelconditie." if ok else _model.objective())
		"fire_hydrant":
			var ok: bool = _model.connect_water()
			_app._notify("Waterwinning aangesloten. Leg de slang zelf met Q in korte segmenten naar de toegang." if ok else _model.objective())
		"fire_plan":
			_show_plan()
		"fire_victim":
			if not _site.is_inside(_app.officer.global_position) or _app.officer.global_position.distance_to(_site.VICTIM) > 2.0:
				_app._notify("Benader het slachtoffer via de beoordeelde toegang.")
			elif _model.pickup_victim():
				_sync()
				_app._notify("Je draagt het slachtoffer. Loop zelf naar de groene opvangplaats buiten; E draagt over aan de gesimuleerde hulpverlening.")
			else: _app._notify("De toegang of je ademlucht is nog onveilig. Koel gericht en beoordeel opnieuw.")
		"fire_safe":
			if _app.officer.global_position.distance_to(_site.SAFE_AREA) < 3 and _model.rescue_victim():
				_sync()
				_app._notify("Slachtoffer overgedragen aan de gesimuleerde hulpverlening. Controleer resterende haarden.")
			else: _app._notify("Dit is de veilige opvang. Breng een gedragen slachtoffer hierheen.")
		_: return false
	_sync()
	return true


func handle_input(event: InputEvent) -> bool:
	if _model.mode == "none" or not _app.active or _app.paused: return false
	if event.is_action_pressed("radio"):
		_show_plan()
		return true
	var requested: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q
	if InputMap.has_action("lay_hose") and event.is_action_pressed("lay_hose"): requested = true
	if not requested: return false
	if not _app.state.occupied_vehicle.is_empty() or _model.victim.status == "carried":
		_app._notify("Parkeer en leg de slang vóór je een slachtoffer draagt.")
		return true
	var camera: Camera3D = _app.officer.camera
	var center := camera.get_viewport().get_visible_rect().size / 2.0
	var origin := camera.project_ray_origin(center)
	var direction := camera.project_ray_normal(center)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 18, 1, [_app.officer.get_rid()])
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < 0.9 or absf(hit.position.y) > 0.15 or _app.officer.global_position.distance_to(hit.position) > 8:
		_app._notify("Richt op vrij wegdek dichtbij je. Q legt daar één nieuw slangsegment.")
	elif _model.add_hose_point(hit.position):
		_app._notify("Slangsegment gelegd · %.1f m totaal. Blijf binnen het bereik van de straalpijp." % _model.hose_length())
	else: _app._notify("Sluit eerst water aan. Leg segmenten van 0,7–7,5 m en maximaal 35 m totaal.")
	_sync()
	return true


func _modal(title: String, subtitle: String) -> void:
	_app._freeze()
	_site.set_simulation_active(false)
	_site.show_jet("", false)
	_crosshair.hide()
	_app.prompt.text = ""
	_app.current_target = {}
	_app._clear_menu(title, subtitle)


func _show_plan() -> void:
	if _model.phase == "completed":
		_show_report(_model.report_score)
		return
	_modal("Ploeg · inzetplan", "Verkenning, water en een vrije terugweg bepalen je aanpak. De kamer is een beschermde fictieve oefenruimte.")
	if _model.phase == "briefing":
		var ready: bool = _model.recon.exterior and _model.recon.door and _model.hydrant_connected
		_app._button("Buiten beginnen · eerst gericht koelen", _choose.bind("defensive"), not ready)
		_app._button("Binneninzet voorbereiden · toegang bewaken", _choose.bind("interior"), not ready)
		if not ready:
			var text: Label = _app._label(_model.objective(), 19)
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.custom_minimum_size = Vector2(420, 100)
			_app.menu_items.add_child(text)
	else:
		_app._button("Nasmeulcontrole en overdracht", _finish.bind(false), not _model.all_cold() or _model.victim.status in ["waiting", "carried"])
		_app._button("Veilig terugtrekken · inzet doorgeven", _finish.bind(true), _model.victim.status == "carried")
		if _model.victim.status == "carried":
			var guidance: Label = _app._label("Je draagt een slachtoffer. Breng deze eerst zelf naar de opvang; daarna kun je de inzet doorgeven.", 19)
			guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			guidance.custom_minimum_size = Vector2(420, 90)
			_app.menu_items.add_child(guidance)
	_app._button("Terug naar de werkplek", _app._resume)


func _choose(tactic: String) -> void:
	if _model.choose_tactic(tactic):
		_app._resume()
		_app._notify("Inzet gestart. Richt op afzonderlijke zichtbare haarden en houd links ingedrukt; één druk blust nooit de hele woning.")
	else: _app._notify(_model.objective())


func _finish(withdraw: bool) -> void:
	var score: Dictionary = _model.finish(withdraw)
	if score.is_empty():
		_app._notify(_model.objective())
		return
	_sync()
	completed.emit(str(_model.mode), score.duplicate(true))
	_show_report(score)


func _show_report(score: Dictionary) -> void:
	_modal("Inzetbeoordeling", "De brandlocatie, celtoestand en inzetgegevens blijven bewaard voor het latere brandonderzoek.")
	var text: Label = _app._label("Resultaat: %s · %d/100\nVeiligheid: %d/35 · Redding: %d/35\nBlussing: %d/20 · Middelen: %d/10\nWater gebruikt: %.0f l · Ademlucht: %.0f%%" % ["zorgvuldig" if score.result == "careful" else "gedeeltelijk / overgedragen", score.total, score.safety, score.rescue, score.suppression, score.conservation, score.water_used, _model.oxygen], 19)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(420, 170)
	_app.menu_items.add_child(text)
	if _model.mode == "campaign": _app._button("Volgende zaak · Sporen in de as", _app.research_ui.start_campaign)
	_app._button("Inzet opnieuw proberen", start_campaign if _model.mode == "campaign" else start_lesson)
	_app._button("Dienst vervolgen", _app._resume)


func _warn(message: String) -> void:
	if _warning_cooldown <= 0:
		_app._notify(message)
		_warning_cooldown = 4.0
