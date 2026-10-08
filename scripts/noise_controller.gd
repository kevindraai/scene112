extends RefCounted
signal completed(score: Dictionary)
var _app: Node3D
var _model: RefCounted
var _site: Node3D
var _rows := {}
var conversation := false

func setup(app: Node3D, model: RefCounted, site: Node3D, at: Vector3) -> void:
	conversation = false
	_app = app
	_model = model
	_site = site
	_site.setup(app.district, model, at)

func tick(_delta: float) -> void:
	if _model.phase == "none": return
	_site.update_model(_model, _app.active and not _app.paused)
	if not _app.active or _app.paused: return
	_model.tick(_delta)
	if _model.phase != "active": return
	if _app.state.occupied_vehicle.is_empty():
		var nearby: Dictionary = _site.get_interaction(_app.officer)
		if not nearby.is_empty():
			_app.current_target = nearby
			_app.prompt.text = "[E] " + str(nearby.title)
	_app.objective.text = "Luister naar beide betrokkenen, bekijk de situatie en toets een werkbare afspraak."
	_app.route_label.text = "Overlast · E: waarnemen/spreken · R: afhandeling · fysieke afstand vóór afronden"

func handle_input(event: InputEvent) -> bool:
	if _model.phase != "active" or not _app.active or _app.paused: return false
	if event.is_action_pressed("radio"):
		_app._freeze()
		_app._clear_menu("Afhandeling overlast", "Een afspraak telt pas wanneer de situatie werkelijk verandert.")
		_app._button("Rapport met bronnen opstellen", show_report)
		_app._button("Meldkamer · doorgeven", _app.show_radio)
		_app._button("Verder op locatie", _app._resume)
		return true
	return false

func on_interact(id: String) -> bool:
	if not id.begins_with("noise_") or _model.phase != "active": return false
	if not _site.can_reach(id, _app.officer):
		_app._notify("Benader deze persoon of waarneming via een vrije zichtlijn.")
		return true
	if id in ["noise_activity", "noise_access"]:
		var source := id.trim_prefix("noise_")
		if _model.observe(source): _app._notify(str(_model.DATA.VARIANTS[_model.variant][source]) + " Bron: eigen waarneming.")
		else: _app._notify("Deze eigen waarneming is al in je dossier opgenomen.")
	else: _conversation(id.trim_prefix("noise_"))
	return true

func _conversation(person: String) -> void:
	conversation = true
	_app._freeze()
	var data: Dictionary = _model.DATA.VARIANTS[_model.variant][person]
	var state: Dictionary = _model.people[person]
	_app._clear_menu(str(data.name), "Leg deze verklaring vast als informatie van een betrokkene.")
	_app._button("Open vragen en luisteren", _speak.bind(person, "open"), state.heard)
	_app._button("Samen een concrete afspraak maken", _speak.bind(person, "agree"), not _model.people.reporter.heard or not _model.people.participant.heard or state.agreement)
	_app._button("Vooraf schuld aanwijzen", _speak.bind(person, "accuse"))
	if state.accusations > 0 and not state.recovered: _app._button("Herstellen · oordeel terugnemen en opnieuw luisteren", _speak.bind(person, "recover"))
	_app._button("Terug naar de locatie", _app._resume)

func _speak(person: String, approach: String) -> void:
	if not _model.speak(person, approach): return
	_app.audio.begin_voice(2.5)
	_app._clear_menu("Verklaring · " + str(_model.DATA.VARIANTS[_model.variant][person].name), "Bron en diensttijd blijven bij deze verklaring.")
	var text: Label = _app._label(str(_model.people[person].statements.back().text), 19)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(420, 140)
	_app.menu_items.add_child(text)
	_app._button("Verder spreken", _conversation.bind(person))
	_app._button("Terug naar de locatie", _app._resume)

func show_report() -> void:
	conversation = false
	_app._freeze()
	_app._clear_menu("Dienstrapport · overlast", "Neem eigen waarnemingen, beide verklaringen, afspraken en de echte afloop op.")
	_rows.clear()
	for source: String in _model.cards():
		var row := CheckBox.new()
		row.text = {"activity": "Eigen waarneming · activiteit", "access": "Eigen waarneming · veilige doorgang", "statement_reporter": "Verklaring · melder", "statement_participant": "Verklaring · andere betrokkene", "agreements": "Verrichte handeling · afgesproken oplossing", "separation": "Eigen waarneming · afspraak uitgevoerd, partijen op afstand"}[source]
		_app.menu_items.add_child(row)
		_rows[source] = row
	_app._button("Afhandeling afronden", _submit)
	_app._button("Verder onderzoeken", _app._resume)

func _submit() -> void:
	var selected: Array = []
	for source: String in _rows:
		if _rows[source].button_pressed: selected.append(source)
	if not _model.submit(selected): return
	completed.emit(_model.report.duplicate(true))
	_app._clear_menu("Dienstbeoordeling", "De waargenomen afloop en gebruikte bronnen zijn vastgelegd.")
	var text: Label = _app._label("%d/100 · %s\n%s" % [_model.report.total, "zorgvuldig" if _model.report.result == "careful" else "onvolledig / onzorgvuldig", "De afspraken zijn daadwerkelijk uitgevoerd." if _model.report.result == "careful" else "Er ontbreken bronnen, herstel of een aantoonbaar uitgevoerde oplossing."], 19)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(420, 150)
	_app.menu_items.add_child(text)
	_app._button("Verder surveilleren", _app._resume)
