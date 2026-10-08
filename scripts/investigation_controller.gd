class_name InvestigationController
extends RefCounted
## Spatial evidence capture, source-aware conversations and cited report construction.
signal completed(mode: String, score: Dictionary)
var _app: Node3D
var _model: RefCounted
var _site: Node3D
var _crosshair: Label
var _rows := {}
var _witness := ""

func setup(app: Node3D, model: RefCounted, site: Node3D) -> void:
	_app = app
	_model = model
	_site = site
	_site.setup(app.district, app.fire_site, model)
	if not is_instance_valid(_crosshair):
		_crosshair = _app._label("+", 28, Color("d7cab0"))
		_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crosshair.position = Vector2(628, 340)
		_crosshair.size = Vector2(24, 40)
		_app.hud.add_child(_crosshair)

func start_campaign() -> void:
	var previous: Dictionary = _app.state.fire_campaign.duplicate(true)
	if _app.fire_model.mode == "campaign": previous = _app.fire_model.to_dict()
	if previous.is_empty() or previous.get("phase") != "completed":
		_app._notify("Rond eerst de woningbrand af. Het onderzoek gebruikt jouw bewaarde inzet.")
		return
	_app.start_training("research")
	_model.begin("campaign", previous)
	_site.setup(_app.district, _app.fire_site, _model)
	_modal("Sporen in de as", str(_model._data.setting))
	var text: Label = _app._label("Onderzoek hetzelfde pand. F fotografeert een werkelijk gericht spoor; E legt het vast. Praat met Saar en Lars, controleer bronnen, laat het object onderzoeken bij het bureau en bouw een onderbouwd rapport. Meerdere brandplekken en een tegenstrijdige verklaring bewijzen geen opzet.", 19)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(420, 170)
	_app.menu_items.add_child(text)
	_app._button("Onderzoek beginnen", _app._resume)

func tick(delta: float) -> void:
	_crosshair.visible = _app.active and not _app.paused and _model.mode != "none" and _app.state.occupied_vehicle.is_empty()
	_site.set_simulation_active(_app.active and not _app.paused)
	if _model.mode == "none":
		if is_instance_valid(_app.audio): _app.audio.update_investigation("none", false, _app.officer.global_position)
		return
	var inside: bool = _app.fire_site.is_inside(_app.officer.global_position)
	var context := "office" if _app.officer.position.z < 0 else "scene"
	if _app.paused and _app._menu_title_is("Onderzoeksbord"): context = "board"
	_app.audio.update_investigation(context if _app.active else "none", _witness != "", _app.officer.global_position, inside)
	if not _app.active or _app.paused: return
	_witness = ""
	_model.tick(delta)
	var aimed: String = _site.aimed_evidence(_app.officer.camera, _app.officer) if _app.state.occupied_vehicle.is_empty() else ""
	_crosshair.text = "⊕" if not aimed.is_empty() else "+"
	if not aimed.is_empty():
		_app.current_target = {"id": "ev_" + aimed, "title": "F: foto · E: vastleggen · " + str(_model._data.evidence[aimed].title)}
		_app.prompt.text = str(_app.current_target.title)
	elif _app.current_target.get("id") == "board":
		_app.current_target = {"id": "research_board", "title": "Onderzoeksbord · bronnen en rapport"}
		_app.prompt.text = "[E] Onderzoeksbord · bronnen en rapport"
	_app.objective.text = "Vergelijk bronnen, ontstaansgebied en alternatieven." if _model.phase != "completed" else "Onderzoeksrapport bewaard. De zaak is afgerond."
	_app.duty_label.text = "Brandonderzoek / recherche · %d bronnen · %d verbanden" % [_model.evidence.size(), _model.links.size()]
	_app.route_label.text = "Huis 24 · F: gericht fotograferen · E: vastleggen/spreken · R: onderzoeksbord · M: kaart"

func handle_input(event: InputEvent) -> bool:
	if _model.mode == "none" or not _app.active or _app.paused: return false
	if event.is_action_pressed("radio"):
		show_board()
		return true
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		if not _app.state.occupied_vehicle.is_empty(): return true
		var id: String = _site.aimed_evidence(_app.officer.camera, _app.officer)
		if id.is_empty():
			_app._notify("Richt de camera op een bereikbaar spoor dichtbij je. Een muur blokkeert de opname.")
		elif _model.photograph(id, 0.85):
			_app.audio.cue("evidence_camera", _app.officer.global_position)
			_app._notify("Foto met plaats en tijd geregistreerd. E legt de bron of het object vast.")
		return true
	return false

func on_interact(id: String) -> bool:
	if _model.mode == "none": return false
	if id in ["board", "research_board"]:
		show_board()
		return true
	if id == "research_lab":
		_lab()
		return true
	if id.begins_with("witness_"):
		if _site.can_reach(id, _app.officer): _conversation(id.trim_prefix("witness_"))
		else: _app._notify("Benader deze persoon via een vrije zichtlijn.")
		return true
	if not id.begins_with("ev_"): return false
	var evidence_id := id.trim_prefix("ev_")
	if not _site.can_reach(id, _app.officer):
		_app._notify("Benader het spoor in dezelfde ruimte; je kunt niet door een muur vastleggen.")
	elif _model.collect(evidence_id):
		_app.audio.cue("evidence_bag" if evidence_id == "connection" else "evidence_paper", _app.officer.global_position)
		_app._notify(str(_model._data.evidence[evidence_id].text))
	elif _model.evidence.has(evidence_id): _app._notify("Deze bron staat al in je dossier.")
	else: _app._notify("Leg eerst een bruikbare foto vast met F terwijl het spoor in je vizier staat.")
	return true

func _modal(title: String, subtitle: String) -> void:
	_app._freeze()
	_app._clear_menu(title, subtitle)

func _conversation(person: String) -> void:
	_witness = person
	var data: Dictionary = _model._data.witnesses[person]
	_modal(str(data.name), str(data.interest))
	var state: Dictionary = _model.witnesses[person]
	if _model.phase == "completed":
		var notes: Array[String] = []
		for statement: Dictionary in state.statements: notes.append(str(statement.text))
		if state.refused: notes.append("Onderbreking / weigering vastgelegd; geen schuldindicatie.")
		var saved: Label = _app._label("\n\n".join(notes) if not notes.is_empty() else "Er is geen verklaring opgenomen.", 18)
		saved.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		saved.custom_minimum_size = Vector2(420, 200)
		_app.menu_items.add_child(saved)
		_app._button("Terug naar onderzoek", _app._resume)
		return
	if state.suspect and not state.lawyer:
		_app._button("Recherche · aanleiding uitleggen", _interview.bind(person, "explanation"), state.explanation)
		_app._button("Cautie geven · zwijgrecht uitleggen", _interview.bind(person, "cautie"), not state.explanation or state.cautie)
		_app._button("Advies en rechtsbijstand regelen", _interview.bind(person, "lawyer"), not state.cautie or state.lawyer)
	elif state.stopped:
		var text: Label = _app._label(str(data.get("silence", "Dit gesprek is onderbroken. Een verklaring is vrijwillig.")), 19)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(420, 75)
		_app.menu_items.add_child(text)
		_app._button("Vragen of gesprek vrijwillig kan doorgaan", _interview.bind(person, "resume_voluntary"), state.suspect and not state.lawyer)
	else:
		for choice: String in ["open", "timeline", "repair", "show_entry", "clarify", "suggestive"]:
			if choice == "show_entry" and (person != "lars" or not _model.evidence.has("entry_record") or "open" not in state.asked): continue
			if choice == "clarify" and "suggestive" not in state.asked: continue
			var labels := {"open": "Open vraag · vertel wat je zelf meemaakte", "timeline": "Doorvragen · controleer de volgorde", "repair": "Gerichte vraag · wat is aan de aansluiting gedaan?", "show_entry": "Selectief bewijs · leg de cameraregistratie voor", "clarify": "Herstellen · opnieuw in eigen woorden", "suggestive": "Suggestie · Lars heeft dit vast expres gedaan?"}
			_app._button(labels[choice], _ask.bind(person, choice), choice in state.asked and choice != "suggestive")
		_app._button("Gesprek op verzoek onderbreken", _interview.bind(person, "stop"))
		if person == "lars" and _model.evidence.has("connection") and "repair" in state.asked and not state.suspect:
			_app._button("Afzonderlijke recherchefase · rechten waarborgen", _interview.bind(person, "suspect"))
	_app._button("Terug naar onderzoek", _app._resume)

func _ask(person: String, choice: String) -> void:
	if not _model.question(person, choice):
		_app._notify("Deze vraag is nu niet passend; respecteer de onderbreking en benodigde bijstand.")
		return
	_witness = person
	_modal("Verklaring · " + str(_model._data.witnesses[person].name), "Bron en tijd blijven bij de verklaring; deze tekst is geen eigen waarneming.")
	var statement: Dictionary = _model.witnesses[person].statements.back()
	var text: Label = _app._label(str(statement.text), 19)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(420, 175)
	_app.menu_items.add_child(text)
	_app._button("Verder vragen", _conversation.bind(person))
	_app._button("Terug naar locatie", _app._resume)

func _interview(person: String, choice: String) -> void:
	_model.interview_action(person, choice)
	_conversation(person)

func _lab() -> void:
	_modal("Sporenbalie", "Gelabeld objectonderzoek is een afzonderlijke stap; het resultaat geeft ook beperkingen aan.")
	if _model.lab_result:
		var finding: Dictionary = _model.expert_report()
		var text: Label = _app._label(str(finding.source) + "\n\n" + str(finding.text), 19)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(420, 175)
		_app.menu_items.add_child(text)
	elif _model.lab_requested < 0:
		_app._button("Object met bronlabel overdragen", _request_lab, not _model.evidence.has("connection"))
	else:
		_app._button("Deskundigenresultaat ophalen", _receive_lab, _model.clock - _model.lab_requested < 20)
	_app._button("Verder onderzoeken", _app._resume)

func _request_lab() -> void:
	_model.request_lab()
	_app.audio.cue("evidence_bag", _app.officer.global_position)
	_lab()

func _receive_lab() -> void:
	_model.receive_lab()
	_lab()

func show_board() -> void:
	_modal("Onderzoeksbord", "Leg controleerbare verbanden; een aanwezigheid of verklaring is geen automatische schuldconclusie.")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 270)
	var items := VBoxContainer.new()
	items.custom_minimum_size.x = 400
	scroll.add_child(items)
	_app.menu_items.add_child(scroll)
	for id: String in _model._data.links:
		var button := Button.new()
		button.text = ("✓ " if id in _model.links else "Koppelen · ") + str(_model._data.links[id].title)
		button.disabled = _model.phase == "completed" or id in _model.links
		button.pressed.connect(_link.bind(id))
		items.add_child(button)
	for id: String in _model._data.hypotheses:
		var button := Button.new()
		button.text = ("● " if id == _model.hypothesis else "○ ") + str(_model._data.hypotheses[id])
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(400, 64)
		button.disabled = _model.phase == "completed"
		button.pressed.connect(_hypothesis.bind(id))
		items.add_child(button)
	_app._button("Brongebonden rapport opstellen", show_report)
	_app._button("Verder op locatie", _app._resume)

func _link(id: String) -> void:
	if not _model.link_evidence(id): _app._notify("Deze koppeling vraagt de betrokken bronnen of een vastgelegde tegenstrijdigheid.")
	show_board()

func _hypothesis(id: String) -> void:
	_model.choose_hypothesis(id)
	show_board()

func show_report() -> void:
	_modal("Onderzoeksrapport", "Selecteer wat je daadwerkelijk aanhaalt. Bewaard materiaal telt niet automatisch als onderbouwing.")
	_rows.clear()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 270)
	var items := VBoxContainer.new()
	scroll.add_child(items)
	_app.menu_items.add_child(scroll)
	for id: String in _model.report_cards():
		var row := CheckBox.new()
		row.text = str(_model.report_cards()[id])
		row.button_pressed = id in _model.draft_selection
		row.disabled = _model.phase == "completed"
		row.toggled.connect(_draft_changed)
		row.custom_minimum_size = Vector2(400, 36)
		_rows[id] = row
		items.add_child(row)
	if _model.phase == "completed":
		var result: Label = _app._label("Bewaard resultaat: %d/100 · %s. Dit dossier is afgesloten." % [_model.report.total, {"careful": "zorgvuldig", "incomplete": "onvolledig", "wrong": "verkeerde conclusie"}[_model.report.outcome]], 17)
		result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		result.custom_minimum_size = Vector2(420, 65)
		_app.menu_items.add_child(result)
		_app._button("Terug naar de wijk", _app._resume)
	else:
		_app._button("Rapport beoordelen", _submit)
		_app._button("Concept later voortzetten", _app._resume)

func _draft_changed(_pressed: bool) -> void:
	var selected: Array = []
	for id: String in _rows:
		if is_instance_valid(_rows[id]) and _rows[id].button_pressed: selected.append(id)
	_model.set_draft(selected)

func _finalize() -> void:
	if not _model.finalize_report(): return
	completed.emit(str(_model.mode), _model.report.duplicate(true))
	_modal("Sporen in de as · afsluiting", "De gekozen conclusie en jouw bronnen blijven bewaard.")
	var ending := "Het dossier is onvolledig gesloten. Het team kan geen betrouwbare oorzaak vaststellen; de open vragen blijven in het rapport." if _model.report.outcome == "incomplete" else "De stellige conclusie wordt bij dossiercontrole niet gedragen door de bronnen. De zaak eindigt met een afgewezen oorzaakconclusie; de aanwezige persoon is daarmee niet schuldig verklaard."
	var text: Label = _app._label(ending, 19)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(420, 160)
	_app.menu_items.add_child(text)
	_app._button("Terug naar de wijk", _app._resume)

func _submit() -> void:
	var selected: Array = []
	for id: String in _rows:
		if _rows[id].button_pressed: selected.append(id)
	var grade: Dictionary = _model.submit_report(selected)
	if grade.is_empty(): return
	if grade.outcome == "careful": completed.emit(str(_model.mode), grade.duplicate(true))
	_modal("Onderzoeksbeoordeling", "Je eigen waarnemingen, verklaringen en deskundigeninformatie hebben afzonderlijke bronnen.")
	var text: Label = _app._label("%d/100 · %s\nHypothese: %s\nBronnen: %d · Brandstofschade in de inzet: %.0f%%\nSuggestieve vraagstelling: −%d" % [grade.total, {"careful": "zorgvuldig", "incomplete": "onvolledig", "wrong": "onvoldoende / verkeerde conclusie"}[grade.outcome], _model._data.hypotheses[grade.hypothesis], grade.evidence_count, grade.damage * 100, grade.suggestion_penalty], 19)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(420, 150)
	_app.menu_items.add_child(text)
	if grade.outcome != "careful":
		_app._button("Onderbouwing verbeteren", show_report)
		_app._button("Zaak afsluiten met dit resultaat", _finalize)
	_app._button("Terug naar de wijk", _app._resume)
