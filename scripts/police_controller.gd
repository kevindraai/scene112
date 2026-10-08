class_name PoliceController
extends RefCounted
## Owns the academy, case interactions and editable PV presentation.

signal completed(mode: String, score: Dictionary)

const FingerTask = preload("res://scripts/fingerprint_task.gd")
const CATEGORIES := ["", "observation", "declaration", "action", "conclusion"]
const CATEGORY_LABELS := ["Kies soort inhoud", "Eigen waarneming", "Verklaring", "Verrichte handeling", "Conclusie"]

var _app: Node3D
var _model: RefCounted
var _site: Node3D
var _draft: Array[Dictionary] = []
var _mode := "none"
var _practice := false
var _drive_start := Vector3(2, 0, 9)
var _task: Control


func setup(app: Node3D, model: RefCounted, site: Node3D) -> void:
	if is_instance_valid(_task): _task.queue_free()
	_task = null
	_draft.clear()
	_practice = false
	_drive_start = Vector3(2, 0, 9)
	_app = app
	_model = model
	_site = site
	_mode = ""
	_sync_site()
	_site.set_simulation_active(_app.active and not _app.paused)


func show_academy() -> void:
	_modal("Academie", "Oefen echte handelingen. De begeleider beoordeelt wat je doet en hoe je dat vastlegt.")
	_app._button("Les 1 · Basisdienst op straat", _start_lesson.bind("basis", false))
	_app._button("Les 2 · Arrestant en rapportage", _start_lesson.bind("intake", false))
	_app._button("Les 3 · Brandweer basisinzet", _app.fire_ui.start_lesson)
	_app._button("Basisdienst zelfstandig oefenen", _start_lesson.bind("basis", true))
	_app._button("Terug naar mijn dienst", _return_to_app)


func _return_to_app() -> void:
	if _app.active: _app._resume()
	else: _app._show_main()


func start_campaign() -> void:
	_app.start_new("police")
	_begin("campaign", false)
	_app._notify("De eerste dienst: controleer uitrusting en radio. Je rijdt daarna naar een verkeersincident bij de kruising.")


func _start_lesson(mode: String, practice: bool) -> void:
	_app.start_training("police")
	_begin(mode, practice)
	if mode == "intake":
		_app.officer.position = Vector3(-6.5, 0.1, -5.5)
		_app._notify("Les 2: een volwassen oefenarrestant is al volgens het fictieve scenario overgedragen. Werk zorgvuldig aan uitleg, rechten en registratie.")
	else:
		_app._notify("Les 1: neem uitrusting mee, meld je aan, stap in en rijd naar de kruising. Daar zet je met Q zelf drie veilige afzetpunten neer.")


func _begin(mode: String, practice: bool) -> void:
	_model.begin(mode)
	_practice = practice
	_draft.clear()
	_drive_start = _app.district.objects.police_car.global_position
	_sync_site()
	_site.show_guidance(mode == "basis" and not practice)
	_app._resume()


func _sync_site() -> void:
	var data: Dictionary = _model.to_dict()
	if str(data.mode) != _mode:
		_mode = str(data.mode)
		_site.set_mode(_mode)
		if _practice: _site.show_guidance(false)
	_site.sync_cones(data.cones)
	if _model.mode == "free": _site.set_people(_model.person_data())


func tick(delta: float) -> void:
	_sync_site()
	_site.set_simulation_active(_app.active and not _app.paused)
	if not _app.active or _app.paused: return
	if _model.mode == "none": return
	_model.tick(delta)
	if _model.mode in ["basis", "campaign", "free"]:
		var data: Dictionary = _model.to_dict()
		var basics: Dictionary = data.basics
		if _app.state.equipment and not basics.equipment: _model.mark_basics("equipment")
		if _app.state.radio_checked and not basics.radio: _model.mark_basics("radio")
		var seated: String = _app.state.occupied_vehicle
		if seated == "police_car":
			if not basics.enter: _model.mark_basics("enter")
			var car: Node3D = _app.district.objects.police_car
			if car.global_position.distance_to(_drive_start) >= 20.0 and car.global_position.distance_to(Vector3(-18, 0, 18)) < 16.0 and not basics.drive:
				_model.mark_basics("drive")
		elif basics.drive and not basics.exit and _app.officer.global_position.distance_to(Vector3(-18, 0, 18)) < 16.0:
			_model.mark_basics("exit")
	_app.objective.text = _model.objective()
	if _model.mode in ["basis", "campaign", "free"]:
		var position: Vector3 = _app._controlled_position()
		_app.route_label.text = "Kruising · %.0f m · Q: afzetten · E: waarnemen/spreken" % Vector2(position.x + 18, position.z - 18).length()
	else:
		_app.route_label.text = "Intake in bureau · E: uitleg, rechten en registratie"


func on_interact(id: String) -> bool:
	if id == "academy":
		show_academy()
		return true
	if _model.mode == "none": return false
	match id:
		"pc_damage", "pc_tracks", "pc_signal":
			var recorded: bool = _model.record_observation(id)
			if recorded:
				var key: String = {"pc_damage": "damage", "pc_tracks": "marks", "pc_signal": "road"}[id]
				_app._notify(str(_model.observations[key].text) + " Bron: eigen waarneming bij de kruising; diensttijd vastgelegd.")
			else:
				_app._notify("Zet eerst veilig af; elke waarneming leg je één keer vast.")
			return true
		"pc_lotte", "pc_bram":
			_conversation("lotte" if id == "pc_lotte" else "bram")
			return true
		"pc_intake", "pc_trainee":
			_show_intake()
			return true
		"board", "pc_report":
			_show_report()
			return true
	return false


func handle_input(event: InputEvent) -> bool:
	if not _app.active or _app.paused or _model.mode not in ["basis", "campaign", "free"]:
		return false
	if _model.mode == "free" and event.is_action_pressed("radio"):
		_modal(_model.case_title(), "Zet veilig af, verzamel eigen waarnemingen en beide verklaringen, en maak een onderbouwd PV.")
		_app._button("Proces-verbaal opstellen", _show_report, not _model.can_report())
		_app._button("Meldkamer · doorgeven", _app.show_radio)
		_app._button("Terug naar de locatie", _app._resume)
		return true
	var requested: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q
	if InputMap.has_action("place_cone") and event.is_action_pressed("place_cone"): requested = true
	if not requested: return false
	if not _app.state.occupied_vehicle.is_empty():
		_app._notify("Parkeer en stap eerst veilig uit om het incident af te zetten.")
		return true
	var camera: Camera3D = _app.officer.camera
	var center := camera.get_viewport().get_visible_rect().size / 2.0
	var origin := camera.project_ray_origin(center)
	var direction := camera.project_ray_normal(center)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 8.0, 1, [_app.officer.get_rid()])
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < 0.9 or absf(hit.position.y) > 0.15 or _app.officer.global_position.distance_to(hit.position) > 8.0:
		_app._notify("Richt het midden van je camera op vrij wegdek dichtbij je. Q plaatst daar één afzetkegel.")
		return true
	var result: Dictionary = _model.place_cone(hit.position)
	_feedback(result)
	if not result.get("ok", false): _site.show_guidance(true)
	_sync_site()
	return true


func _modal(title: String, subtitle: String) -> void:
	_app._freeze()
	_site.set_simulation_active(false)
	_app.prompt.text = ""
	_app.current_target = {}
	_app._clear_menu(title, subtitle)


func _feedback(result: Dictionary) -> void:
	_app._notify(str(result.get("message", "Handeling vastgelegd.")))


func _conversation(person: String) -> void:
	var title := str(_model.person_data(person).source)
	_modal(title, "Vraag wat iemand zelf zag of deed. Houd verklaringen apart van je eigen waarnemingen.")
	_app._button("Open vraag: vertel wat er gebeurde", _speak.bind(person, "open"))
	_app._button("Suggestie: u reed vast te hard?", _speak.bind(person, "suggestive"))
	_app._button("Gesprek later voortzetten", _app._resume)


func _speak(person: String, approach: String) -> void:
	var result: Dictionary = _model.speak(person, approach)
	_modal("Verklaring", str(result.get("message", "Geen verklaring beschikbaar.")))
	if result.has("text"):
		var text: Label = _app._label(str(result.text), 19)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(420, 120)
		_app.menu_items.add_child(text)
	if approach == "suggestive":
		_site.show_guidance(true)
		_app._notify("Een suggestieve vraag kan een verklaring kleuren. Laat iemand eerst zelf vertellen; je mag zorgvuldig herstellen.")
	_app._button("Opnieuw open vragen", _conversation.bind(person))
	_app._button("Terug naar de locatie", _app._resume)


func _show_intake() -> void:
	if _model.mode != "intake":
		_app._notify("Deze registratie is beschikbaar in academieles 2.")
		return
	var data: Dictionary = _model.to_dict()
	var rights: Dictionary = data.intake_rights
	_modal("Academie · intake", "Fictieve volwassen oefenarrestant. De grond voor verwerking is in deze oefening vooraf vastgesteld. Registratieafdrukken zijn geen delictsporen.")
	_app._button("Uitleg: aanleiding en registratie", _rights.bind("explanation"), rights.explanation)
	_app._button("Cautie: u hoeft niet te antwoorden", _rights.bind("cautie"), not rights.explanation or rights.cautie)
	_app._button("Consultatie en rechtsbijstand regelen", _rights.bind("lawyer"), not rights.cautie or rights.lawyer)
	_app._button("Vingerafdrukken positioneren", _show_fingerprints, not rights.lawyer or _model.can_report())
	_app._button("Proces-verbaal opstellen", _show_report, not _model.can_report())
	_app._button("Verder in het bureau", _app._resume)


func _rights(action: String) -> void:
	var accepted: bool = _model.rights(action)
	_show_intake()
	if not accepted:
		_app._notify("Volg de passende volgorde: uitleg, cautie en consultatie vóór registratie.")
	else:
		var messages := {"explanation": "Je legt de vooraf beoordeelde aanleiding en de registratie uit. Betrokkene begrijpt het doel.", "cautie": "Je deelt mee dat antwoorden niet verplicht zijn. Zwijgen levert geen bewijs van schuld op.", "lawyer": "Een consultatiemoment heeft plaatsgevonden en rechtsbijstand is geregeld. Inhoudelijke vragen wachten op dit moment."}
		var feedback: Label = _app._label(messages[action], 17, Color("acd4da"))
		feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		feedback.custom_minimum_size = Vector2(420, 66)
		_app.menu_items.add_child(feedback)
		_app.menu_items.move_child(feedback, 2)


func _show_fingerprints() -> void:
	var data: Dictionary = _model.to_dict()
	if not data.intake_rights.lawyer:
		_app._notify("Regel eerst uitleg en rechten.")
		return
	_modal("Dactyloscopie", "Positioneer drie vingers één voor één. Blijf uitgelijnd tijdens de registratie. Een onleesbare afdruk neem je opnieuw op.")
	_task = FingerTask.new()
	for quality in data.print_qualities:
		if float(quality) >= 0.7: _task.accepted_count += 1
	_task.captured.connect(func(quality: int):
		var registered: bool = _model.register_print(quality / 100.0)
		var accepted := registered and quality >= 70
		_task.accept_capture(accepted)
		_app._notify("Registratiekwaliteit %d/100 · %s" % [quality, "leesbaar" if accepted else "opnieuw opnemen"]))
	_task.finished.connect(_show_intake)
	_app.menu_items.add_child(_task)
	_app._button("Onderbreken · goede afdrukken blijven bewaard", _show_intake)


func _show_report() -> void:
	if not _model.can_report():
		_app._notify(_model.objective())
		return
	if _model.phase == "completed":
		_show_review(_model.to_dict().report_score)
		return
	var available: Array = _model.report_cards()
	if _draft.is_empty():
		for card: Dictionary in available:
			_draft.append({"id": card.id, "text": card.text, "source": card.source, "time": card.time, "category": "", "included": true})
	else:
		# Repeated open questions may improve a source after an initial report.
		# Preserve the player's choices while displaying the current statement.
		for row: Dictionary in _draft:
			for card: Dictionary in available:
				if card.id == row.id:
					row.text = card.text
					row.source = card.source
					row.time = card.time
	_modal("Proces-verbaal", "Kies inhoud, benoem de juiste soort informatie en orden de tijdlijn. Je kunt je rapport na beoordeling verbeteren.")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 235)
	_app.menu_items.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.custom_minimum_size.x = 395
	rows.add_theme_constant_override("separation", 12)
	scroll.add_child(rows)
	for i in range(_draft.size()): _report_row(rows, i)
	_app._button("Rapport ter beoordeling indienen", _submit_report)
	_app._button("Concept bewaren · terug naar dienst", _app._resume)


func _report_row(parent: VBoxContainer, index: int) -> void:
	var card: Dictionary = _draft[index]
	var row := VBoxContainer.new()
	parent.add_child(row)
	var text: Label = _app._label(str(card.text), 17)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 390
	row.add_child(text)
	row.add_child(_app._label("Bron: %s · diensttijd %.1f s" % [card.source, float(card.time)], 14, Color("acd4da")))
	var choices := HBoxContainer.new()
	row.add_child(choices)
	var include := CheckBox.new()
	include.text = "Opnemen"
	include.button_pressed = card.included
	include.toggled.connect(func(value: bool): card.included = value)
	choices.add_child(include)
	var category := OptionButton.new()
	for label: String in CATEGORY_LABELS: category.add_item(label)
	category.selected = maxi(0, CATEGORIES.find(card.category))
	category.item_selected.connect(func(value: int): card.category = CATEGORIES[value])
	choices.add_child(category)
	for direction in [-1, 1]:
		var order := Button.new()
		order.text = "↑" if direction == -1 else "↓"
		order.disabled = index + direction < 0 or index + direction >= _draft.size()
		order.pressed.connect(_move_card.bind(index, direction))
		choices.add_child(order)


func _move_card(index: int, direction: int) -> void:
	var other := index + direction
	var card := _draft[index]
	_draft[index] = _draft[other]
	_draft[other] = card
	_show_report()


func capture_draft() -> Array:
	var rows: Array = []
	for card: Dictionary in _draft:
		rows.append({"id": card.id, "category": card.category, "included": card.included})
	return rows


func restore_draft(rows: Variant) -> bool:
	if not rows is Array or rows.size() > 16: return false
	var available: Dictionary = {}
	for card: Dictionary in _model.report_cards(): available[card.id] = card
	var restored: Array[Dictionary] = []
	var seen: Dictionary = {}
	for row in rows:
		if not row is Dictionary or row.size() != 3 or not row.has_all(["id", "category", "included"]): return false
		if not row.id is String or not row.category is String or not row.included is bool: return false
		if not available.has(row.id) or seen.has(row.id) or row.category not in CATEGORIES: return false
		seen[row.id] = true
		var card: Dictionary = available[row.id]
		restored.append({"id": row.id, "text": card.text, "source": card.source, "time": card.time, "category": row.category, "included": row.included})
	_draft = restored
	return true


func _submit_report() -> void:
	var cards: Array = []
	for card: Dictionary in _draft:
		if card.included: cards.append({"id": card.id, "category": card.category})
	var result: Dictionary = _model.submit_report(cards)
	if result.result == "careful" and _model.phase == "completed":
		completed.emit(str(_model.mode), result.duplicate(true))
	_show_review(result)


func _show_review(result: Dictionary) -> void:
	_modal("Rapportbeoordeling", "Bekijk de beoordeling en de feedback. Een concept kun je herstellen; een afgerond PV blijft bewaard.")
	var feedback_scroll := ScrollContainer.new()
	feedback_scroll.custom_minimum_size = Vector2(420, 100)
	_app.menu_items.add_child(feedback_scroll)
	var feedback: Label = _app._label("\n".join(result.get("feedback", ["Je rapport is beoordeeld."])), 17)
	feedback.custom_minimum_size.x = 400
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_scroll.add_child(feedback)
	var score := result
	if not score.is_empty():
		var summary: Label = _app._label("Zorgvuldigheid: %d/100\nObjectiviteit: %d/25 · Volledigheid: %d/25\nProportionaliteit: %d/25 · Consistentie: %d/25" % [int(score.score), int(score.objectivity), int(score.completeness), int(score.proportionality), int(score.consistency)], 19)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.custom_minimum_size = Vector2(420, 100)
		_app.menu_items.add_child(summary)
	if _model.phase == "completed": _show_archived_rows()
	if _model.phase != "completed": _app._button("Concept verbeteren", _show_report)
	if _model.mode == "free":
		if _model.phase != "completed" and not result.is_empty():
			_app._button("Afsluiten met deze tekortkomingen", _finalize_free)
	else:
		var replay: Callable = start_campaign if _model.mode == "campaign" else _start_lesson.bind(str(_model.mode), _practice)
		_app._button("Oefening opnieuw beginnen", replay)
	if _model.mode == "campaign" and _model.phase == "completed":
		_app._button("Volgende zaak · De woningbrand", _app.fire_ui.start_campaign)
	_app._button("Dienst vervolgen", _app._resume)


func _show_archived_rows() -> void:
	var available: Dictionary = {}
	for card: Dictionary in _model.report_cards(): available[card.id] = card
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 125)
	_app.menu_items.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.custom_minimum_size.x = 395
	rows.add_theme_constant_override("separation", 10)
	scroll.add_child(rows)
	for row: Dictionary in _model.to_dict().submitted_cards:
		var card: Dictionary = available[row.id]
		var category: String = CATEGORY_LABELS[CATEGORIES.find(row.category)]
		var text: Label = _app._label("%s · %s\nBron: %s · diensttijd %.1f s" % [category, card.text, card.source, float(card.time)], 15)
		text.custom_minimum_size.x = 390
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(text)

func _finalize_free() -> void:
	var result: Dictionary = _model.finalize_report()
	if not result.get("ok", false): return
	completed.emit("free", result.score.duplicate(true))
	_show_review(result.score)
