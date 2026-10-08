extends RefCounted
## Original fictional adult training scenario, not professional instruction.
## Controller confirms proximity, real driving and player-performed actions.

const SCHEMA := 1
const MODES := ["none", "campaign", "basis", "intake"]
const BASIC_STEPS := ["equipment", "radio", "enter", "drive", "exit"]
const RIGHTS_STEPS := ["explanation", "cautie", "lawyer"]
const CATEGORIES := ["observation", "declaration", "action", "conclusion"]
const PRINT_MINIMUM := 0.7
const MAX_TIME := 1_000_000.0
const SITE := Vector3(-20, 0, 17)
const CONE_TARGETS := [Vector3(-26, 0, 15), Vector3(-28, 0, 17), Vector3(-26, 0, 19)]
const OBSERVATION_DATA := {
	"damage": {"position": [-18.0, 0.0, 18.0], "text": "Ik zag schade aan de rechtervoorzijde van de auto."},
	"marks": {"position": [-20.0, 0.0, 15.0], "text": "Ik zag korte donkere bandensporen; een snelheid is hieruit niet vastgesteld."},
	"road": {"position": [-20.0, 0.0, 19.2], "text": "Ik zag een nat wegdek en een vrije doorgang voor de overige rijbaan."}
}
const PEOPLE := {
	"lotte": {"source": "Lotte, bestuurder", "position": [-19.0, 0.0, 21.0],
		"open": "Ik remde toen ik een fietser opmerkte. Hoe hard ik precies reed weet ik niet.",
		"suggestive": "Als u zegt dat ik te hard reed... Ik weet mijn snelheid niet meer zeker."},
	"bram": {"source": "Bram, getuige", "position": [-16.0, 0.0, 14.5],
		"open": "Ik hoorde remmen. Toen ik omkeek stond de auto stil; de botsing zelf zag ik niet.",
		"suggestive": "U zegt dat zij hard reed. Dat zal dan wel, maar ik zag de botsing niet."}
}
const INTAKE_EXPLANATION := "Academie: een volwassen figurant speelt een verdachte uit een fictieve vernielingszaak. Directe waarneming, aanhoudingsreden en registratiegrond zijn vooraf door de begeleider in het oefendossier gecontroleerd. Leg deze reden, rechten en opname uit; je beslist geen echte bevoegdheid. Registratieafdrukken bewijzen geen schuld."
const SNAPSHOT_KEYS := ["schema", "mode", "elapsed", "basics", "basic_times", "cones", "cone_times", "observations", "statements", "intake_rights", "rights_times", "print_qualities", "print_times", "submitted_cards", "report_score", "result"]

var mode := "none"
var elapsed := 0.0
var basics := {"equipment": false, "radio": false, "enter": false, "drive": false, "exit": false}
var basic_times: Dictionary = {}
var cones: Array = []
var cone_times: Array = []
var observations: Dictionary = {}
var statements: Dictionary = {}
var intake_rights := {"explanation": false, "cautie": false, "lawyer": false}
var rights_times: Dictionary = {}
var print_qualities: Array = []
var print_times: Array = []
var submitted_cards: Array = []
var report_score: Dictionary = {}
var result := "incomplete"
var phase: String:
	get:
		if mode == "none": return "none"
		if result == "careful": return "completed"
		return "report" if can_report() else "active"

func begin(new_mode: String) -> bool:
	if new_mode not in MODES: return false
	mode = new_mode
	elapsed = 0.0
	basics = {"equipment": false, "radio": false, "enter": false, "drive": false, "exit": false}
	basic_times = {}
	cones = []
	cone_times = []
	observations = {}
	statements = {}
	intake_rights = {"explanation": false, "cautie": false, "lawyer": false}
	rights_times = {}
	print_qualities = []
	print_times = []
	submitted_cards = []
	report_score = {}
	result = "incomplete"
	return true

func tick(delta: float) -> bool:
	if mode == "none" or not report_score.is_empty() or not is_finite(delta) or delta <= 0 or delta > 3600 or elapsed + delta > MAX_TIME: return false
	elapsed += delta
	return true

func complete_step(id: String) -> bool:
	if not _road_mode() or result == "careful" or id not in BASIC_STEPS or basics[id]: return false
	for step: String in BASIC_STEPS:
		if not basics[step]:
			if step != id: return false
			_invalidate_report()
			basics[step] = true
			basic_times[step] = elapsed
			return true
	return false

func mark_basics(action: String) -> Dictionary:
	var ok := complete_step(action)
	return {"ok": ok, "message": "Diensthandeling vastgelegd." if ok else "Voer eerst de vorige diensthandeling werkelijk uit."}

func place_cone(at: Vector3) -> Dictionary:
	if not _road_mode() or result == "careful" or not basics.exit:
		return {"ok": false, "message": "Neem uitrusting, meld je aan en rijd eerst naar de casus; stap veilig uit."}
	var slot := _cone_slot([at.x, at.y, at.z])
	if slot < 0: return {"ok": false, "message": "Gebruik een veilige westelijke afzetzone; houd de andere rijbaan vrij."}
	for saved in cones:
		if _cone_slot(saved) == slot: return {"ok": false, "message": "Deze afzetzone heeft al een pion."}
	_invalidate_report()
	cones.append([at.x, at.y, at.z])
	cone_times.append(elapsed)
	return {"ok": true, "message": "Pion %d/3 geplaatst." % cones.size()}

func record_observation(id: String) -> bool:
	id = {"pc_damage": "damage", "pc_tracks": "marks", "pc_signal": "road"}.get(id, id)
	if not _road_mode() or result == "careful" or cones.size() != 3 or id not in OBSERVATION_DATA or observations.has(id): return false
	var item: Dictionary = OBSERVATION_DATA[id]
	_invalidate_report()
	observations[id] = {"source": "eigen waarneming", "time": elapsed, "location": item.position.duplicate(), "text": item.text}
	return true

func speak(person: String, approach: String) -> Dictionary:
	person = {"driver": "lotte", "witness": "bram"}.get(person, person)
	if approach == "leading": approach = "suggestive"
	if not _road_mode() or result == "careful" or cones.size() != 3 or person not in PEOPLE or approach not in ["open", "suggestive"]:
		return {"ok": false, "message": "Zorg eerst voor een veilige afzetting en kies een open of suggestieve vraag."}
	var item: Dictionary = PEOPLE[person]
	_invalidate_report()
	var reliability := 1.0 if approach == "open" else 0.3
	statements[person] = {"source": item.source, "time": elapsed, "location": item.position.duplicate(), "text": item[approach], "approach": approach, "reliability": reliability}
	return {"ok": true, "message": item[approach], "source": item.source, "reliability": reliability,
		"feedback": "Een verklaring blijft informatie van deze persoon." if approach == "open" else "De vraag beïnvloedde het antwoord. Vraag opnieuw open."}

func rights(action: String) -> bool:
	if mode != "intake" or result == "careful" or action not in RIGHTS_STEPS or intake_rights[action]: return false
	for step: String in RIGHTS_STEPS:
		if not intake_rights[step]:
			if step != action: return false
			_invalidate_report()
			intake_rights[step] = true
			rights_times[step] = elapsed
			return true
	return false

func register_print(quality: float) -> bool:
	if mode != "intake" or result == "careful" or not intake_rights.lawyer or not is_finite(quality) or quality < 0 or quality > 1: return false
	if print_qualities.size() < 3:
		_invalidate_report()
		print_qualities.append(quality)
		print_times.append(elapsed)
		return true
	var weakest := 0
	for index in range(1, 3):
		if float(print_qualities[index]) < float(print_qualities[weakest]): weakest = index
	if quality <= float(print_qualities[weakest]): return false
	_invalidate_report()
	print_qualities[weakest] = quality
	print_times[weakest] = elapsed
	return true

func can_report() -> bool:
	if _road_mode(): return basics.exit and cones.size() == 3 and observations.size() == 3 and statements.size() == 2
	if mode == "intake": return intake_rights.lawyer and print_qualities.size() == 3 and _prints_good()
	return false

func objective() -> String:
	if mode == "none": return "Kies een academieles of De eerste dienst."
	if result == "careful": return "Zorgvuldig afgerond. Herhaal de les of vervolg je dienst."
	if _road_mode():
		for step: String in BASIC_STEPS:
			if not basics[step]:
				return {"equipment": "Neem je uitrusting op het bureau.", "radio": "Meld je aan bij de meldkamer.", "enter": "Stap in de dienstauto.", "drive": "Rijd werkelijk naar de kruising; volg de route.", "exit": "Stop bij de casus en stap veilig uit."}[step]
		if cones.size() < 3: return "Plaats drie pionnen in verschillende westelijke afzetzones."
		if observations.size() < 3: return "Bekijk voertuigschade, bandensporen en wegdek op de locatie."
		if statements.size() < 2: return "Spreek met Lotte (bestuurder) en Bram (getuige)."
	else:
		for step: String in RIGHTS_STEPS:
			if not intake_rights[step]:
				return {"explanation": INTAKE_EXPLANATION, "cautie": "Bespreek het zwijgrecht; antwoorden is niet verplicht.", "lawyer": "Regel consultatie en bijstand vóór de registratie."}[step]
		if print_qualities.size() < 3 or not _prints_good(): return "Maak drie bruikbare oefenafdrukken (minimaal 70%); herhaal de zwakste opname."
	return "Stel het PV samen: onderscheid bron en categorie, orden de tijdlijn en trek geen onbewezen conclusie."

func progress() -> Dictionary:
	return {"mode": mode, "phase": phase, "elapsed": elapsed, "basics": basics.duplicate(), "intake_rights": intake_rights.duplicate(), "print_qualities": print_qualities.duplicate(), "cone_count": cones.size(), "observation_count": observations.size(), "statement_count": statements.size(), "can_report": can_report(), "objective": objective(), "result": result}

func report_cards() -> Array:
	var cards: Array = []
	if _road_mode():
		if basics.exit: cards.append(_card("action_preparation", "Ik nam uitrusting mee, meldde mij aan en reed naar de casus.", "action", "eigen handelingen", float(basic_times.exit)))
		if cones.size() == 3: cards.append(_card("action_safety", "Ik zette drie pionnen in veilige zones en hield de overige rijbaan vrij.", "action", "eigen handelingen", float(cone_times.back())))
		for id: String in observations:
			var item: Dictionary = observations[id]
			cards.append(_card("observation_" + id, item.text, "observation", item.source, float(item.time)))
		for person: String in statements:
			var item: Dictionary = statements[person]
			cards.append(_card("declaration_" + person, item.source + " verklaarde: " + item.text, "declaration", item.source, float(item.time)))
		if can_report():
			cards.append(_card("conclusion_unknown", "Oorzaak en eventuele verwijtbaarheid zijn met deze gegevens niet vastgesteld.", "conclusion", "beoordeling dossier", elapsed))
			cards.append(_card("conclusion_guilt", "De bestuurder is schuldig; de schade bewijst een te hoge snelheid.", "conclusion", "onbewezen gevolgtrekking", elapsed))
	elif mode == "intake":
		for step: String in RIGHTS_STEPS:
			if intake_rights[step]:
				cards.append(_card("action_" + step, {"explanation": "Ik legde fictieve oefengrond, rechten en registratie uit.", "cautie": "Ik deelde mee dat antwoorden niet verplicht is.", "lawyer": "Consultatie en bijstand waren geregeld vóór de registratie."}[step], "action", "eigen handelingen", float(rights_times[step])))
		for index in range(print_qualities.size()):
			cards.append(_card("print_%d" % index, "Oefenafdruk %d: kwaliteit %d%%, voor registratie en niet als schuldbewijs." % [index + 1, roundi(float(print_qualities[index]) * 100)], "action", "registratiehandeling", float(print_times[index])))
		if can_report():
			cards.append(_card("conclusion_training", "Drie bruikbare registratieafdrukken zijn opgenomen; hiermee is geen delict bewezen.", "conclusion", "beoordeling opnamekwaliteit", elapsed))
			cards.append(_card("conclusion_guilt", "De opgenomen afdrukken bewijzen de schuld van de figurant.", "conclusion", "onbewezen gevolgtrekking", elapsed))
	return cards

func score_report(cards: Array) -> Dictionary:
	var available: Dictionary = {}
	for card in report_cards(): available[card.id] = card
	if not _valid_rows(cards, available): return _score(1, 0, 0, 0, 0, "wrong", ["Selecteer bestaande kaarten met een geldige categorie; geen duplicaten."], [])
	var required := _required_cards()
	var chosen: Dictionary = {}
	var objectivity := 25
	var consistency := 25
	var proportionality := 25
	var feedback: Array = []
	var previous_time := -1.0
	var mistakes := 0
	var serious := false
	for row in cards:
		var actual: Dictionary = available[row.id]
		chosen[row.id] = true
		if row.category != actual.category:
			objectivity = maxi(0, objectivity - 8)
			mistakes += 1
			serious = serious or (actual.category == "declaration" and row.category == "observation")
			feedback.append("Controleer de soort informatie bij bron: " + str(actual.source) + ".")
		if float(actual.time) < previous_time:
			consistency = maxi(0, consistency - 8)
			mistakes += 1
			feedback.append("Een latere handeling staat vóór een eerder vastgelegd feit.")
		previous_time = float(actual.time)
		if row.id == "conclusion_guilt":
			serious = true
			objectivity = 0
			proportionality = 0
			feedback.append("Deze schuldconclusie volgt niet uit het dossier; herstel de conclusie.")
	var missing: Array = []
	for id: String in required:
		if not chosen.has(id): missing.append(id)
	var completeness := roundi(25.0 * float(required.size() - missing.size()) / maxf(1, required.size()))
	var reliable := true
	for statement in statements.values():
		if statement.approach != "open":
			reliable = false
			objectivity = maxi(0, objectivity - 6)
			proportionality = maxi(0, proportionality - 6)
			feedback.append("Een antwoord was door suggestie beïnvloed; herhaal de vraag open.")
	if mode == "intake" and not print_qualities.is_empty():
		var sum := 0.0
		for quality in print_qualities: sum += float(quality)
		proportionality = mini(proportionality, roundi(25 * sum / print_qualities.size()))
	var total := clampi(objectivity + completeness + proportionality + consistency, 1, 100)
	var outcome := "incomplete"
	if serious or mistakes >= 2: outcome = "wrong"
	elif can_report() and missing.is_empty() and mistakes == 0 and reliable and total >= 80: outcome = "careful"
	if not can_report():
		outcome = "incomplete"
		total = mini(total, 49)
		feedback.append("Voer eerst de ontbrekende handelingen op de locatie uit.")
	if not missing.is_empty(): feedback.append("Het verslag mist bronnen, handelingen of een onderbouwde conclusie.")
	if outcome == "careful": feedback.append("Bronnen, chronologie en voorzichtige conclusie zijn zorgvuldig vastgelegd.")
	return _score(total, objectivity, completeness, proportionality, consistency, outcome, feedback, missing)

func submit_report(cards: Array) -> Dictionary:
	var score := score_report(cards)
	var available: Dictionary = {}
	for card in report_cards(): available[card.id] = card
	if not can_report() or result == "careful" or not _valid_rows(cards, available): return score
	submitted_cards = cards.duplicate(true)
	report_score = score.duplicate(true)
	result = score.result
	return score

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "mode": mode, "elapsed": elapsed, "basics": basics.duplicate(), "basic_times": basic_times.duplicate(), "cones": cones.duplicate(true), "cone_times": cone_times.duplicate(), "observations": observations.duplicate(true), "statements": statements.duplicate(true), "intake_rights": intake_rights.duplicate(), "rights_times": rights_times.duplicate(), "print_qualities": print_qualities.duplicate(), "print_times": print_times.duplicate(), "submitted_cards": submitted_cards.duplicate(true), "report_score": report_score.duplicate(true), "result": result}

func restore(data: Variant) -> bool:
	if not data is Dictionary or not _valid_snapshot(data): return false
	var probe = get_script().new()
	probe._apply(data)
	var canonical_score: Dictionary = {}
	if not data.report_score.is_empty():
		if not probe.can_report(): return false
		var available: Dictionary = {}
		for card in probe.report_cards(): available[card.id] = card
		if not probe._valid_rows(probe.submitted_cards, available): return false
		canonical_score = probe.score_report(probe.submitted_cards)
		if not _equal_score(data.report_score, canonical_score) or data.result != canonical_score.result: return false
	elif not data.submitted_cards.is_empty() or data.result != "incomplete": return false
	_apply(data)
	report_score = canonical_score
	return true

func _apply(data: Dictionary) -> void:
	mode = data.mode
	elapsed = float(data.elapsed)
	basics = data.basics.duplicate()
	basic_times = data.basic_times.duplicate()
	cones = data.cones.duplicate(true)
	cone_times = data.cone_times.duplicate()
	observations = data.observations.duplicate(true)
	statements = data.statements.duplicate(true)
	intake_rights = data.intake_rights.duplicate()
	rights_times = data.rights_times.duplicate()
	print_qualities = data.print_qualities.duplicate()
	print_times = data.print_times.duplicate()
	submitted_cards = data.submitted_cards.duplicate(true)
	report_score = data.report_score.duplicate(true)
	result = data.result

func _valid_snapshot(data: Dictionary) -> bool:
	if not _keys(data, SNAPSHOT_KEYS) or not _number(data.schema, 1, 1) or not data.mode is String or data.mode not in MODES or not _number(data.elapsed, 0, MAX_TIME): return false
	if not data.result is String or data.result not in ["incomplete", "careful", "wrong"]: return false
	if not _sequence(data.basics, data.basic_times, BASIC_STEPS, float(data.elapsed)) or not _sequence(data.intake_rights, data.rights_times, RIGHTS_STEPS, float(data.elapsed)): return false
	if not data.cones is Array or data.cones.size() > 3 or not _times(data.cone_times, data.cones.size(), float(data.elapsed)): return false
	var slots: Array = []
	for point in data.cones:
		var slot := _cone_slot(point)
		if slot < 0 or slot in slots: return false
		slots.append(slot)
	for index in range(1, data.cone_times.size()):
		if float(data.cone_times[index]) < float(data.cone_times[index - 1]): return false
	if not data.print_qualities is Array or data.print_qualities.size() > 3 or not _times(data.print_times, data.print_qualities.size(), float(data.elapsed)): return false
	for quality in data.print_qualities:
		if not _number(quality, 0, 1): return false
	if not data.observations is Dictionary or data.observations.size() > 3 or not data.statements is Dictionary or data.statements.size() > 2: return false
	for id in data.observations:
		if id not in OBSERVATION_DATA: return false
		var item: Variant = data.observations[id]
		if not _record(item, float(data.elapsed), false) or item.source != "eigen waarneming" or item.text != OBSERVATION_DATA[id].text or not _position_equal(item.location, OBSERVATION_DATA[id].position): return false
	for person in data.statements:
		if person not in PEOPLE: return false
		var item: Variant = data.statements[person]
		if not _record(item, float(data.elapsed), true) or not item.approach is String or item.approach not in ["open", "suggestive"]: return false
		if item.source != PEOPLE[person].source or item.text != PEOPLE[person][item.approach] or not _position_equal(item.location, PEOPLE[person].position): return false
		if not _number(item.reliability, 0, 1) or not is_equal_approx(float(item.reliability), 1.0 if item.approach == "open" else 0.3): return false
	if not data.submitted_cards is Array or not data.report_score is Dictionary: return false
	if data.mode in ["campaign", "basis"]:
		if not data.rights_times.is_empty() or not data.print_qualities.is_empty(): return false
		if not data.cones.is_empty() and not data.basics.exit: return false
		if (not data.observations.is_empty() or not data.statements.is_empty()) and data.cones.size() != 3: return false
		var last_basic := float(data.basic_times.get("exit", 0.0))
		for time in data.cone_times:
			if float(time) < last_basic: return false
		var safe_time := float(data.cone_times.back()) if data.cones.size() == 3 else 0.0
		for item in data.observations.values() + data.statements.values():
			if float(item.time) < safe_time: return false
	elif data.mode == "intake":
		if not data.basic_times.is_empty() or not data.cones.is_empty() or not data.observations.is_empty() or not data.statements.is_empty(): return false
		if not data.print_qualities.is_empty() and not data.intake_rights.lawyer: return false
		for time in data.print_times:
			if float(time) < float(data.rights_times.get("lawyer", 0.0)): return false
	else:
		if float(data.elapsed) != 0 or not data.basic_times.is_empty() or not data.rights_times.is_empty() or not data.cones.is_empty() or not data.observations.is_empty() or not data.statements.is_empty() or not data.print_qualities.is_empty() or not data.report_score.is_empty(): return false
	return true

func _sequence(flags: Variant, times: Variant, steps: Array, clock: float) -> bool:
	if not flags is Dictionary or not _keys(flags, steps) or not times is Dictionary: return false
	var waiting := false
	var count := 0
	var previous := -1.0
	for step: String in steps:
		if not flags[step] is bool: return false
		if flags[step]:
			if waiting or not times.has(step) or not _number(times[step], 0, clock) or float(times[step]) < previous: return false
			previous = float(times[step])
			count += 1
		else: waiting = true
	return times.size() == count

func _record(item: Variant, clock: float, statement: bool) -> bool:
	var keys := ["source", "time", "location", "text"]
	if statement: keys.append_array(["approach", "reliability"])
	return item is Dictionary and _keys(item, keys) and item.source is String and item.text is String and _number(item.time, 0, clock) and _position(item.location)

func _times(values: Variant, count: int, clock: float) -> bool:
	if not values is Array or values.size() != count: return false
	for value in values:
		if not _number(value, 0, clock): return false
	return true

func _cone_slot(point: Variant) -> int:
	if not _position(point) or absf(float(point[1])) > 0.4: return -1
	for index in range(CONE_TARGETS.size()):
		var target: Vector3 = CONE_TARGETS[index]
		if Vector2(float(point[0]), float(point[2])).distance_to(Vector2(target.x, target.z)) <= 1.1: return index
	return -1

func _position(point: Variant) -> bool:
	if not point is Array or point.size() != 3: return false
	for value in point:
		if not _number(value, -500, 500): return false
	return true

func _position_equal(first: Array, second: Array) -> bool:
	for index in range(3):
		if not is_equal_approx(float(first[index]), float(second[index])): return false
	return true

func _valid_rows(rows: Array, available: Dictionary) -> bool:
	if rows.size() > 16: return false
	var seen: Dictionary = {}
	for row in rows:
		if not row is Dictionary or not _keys(row, ["id", "category"]) or not row.id is String or not row.category is String: return false
		if row.id not in available or row.category not in CATEGORIES or seen.has(row.id): return false
		seen[row.id] = true
	return true

func _required_cards() -> Array:
	if _road_mode(): return ["action_preparation", "action_safety", "observation_damage", "observation_marks", "observation_road", "declaration_lotte", "declaration_bram", "conclusion_unknown"]
	return ["action_explanation", "action_cautie", "action_lawyer", "print_0", "print_1", "print_2", "conclusion_training"]

func _card(id: String, text: String, category: String, source: String, time: float) -> Dictionary:
	# Controller hides expected category; player chooses category and order.
	return {"id": id, "text": text, "category": category, "source": source, "time": time}

func _score(total: int, objectivity: int, completeness: int, proportionality: int, consistency: int, outcome: String, feedback: Array, missing: Array) -> Dictionary:
	return {"score": total, "objectivity": objectivity, "completeness": completeness, "proportionality": proportionality, "consistency": consistency, "result": outcome, "feedback": feedback, "missing": missing}

func _equal_score(saved: Dictionary, expected: Dictionary) -> bool:
	if not _keys(saved, expected.keys()): return false
	for key in ["score", "objectivity", "completeness", "proportionality", "consistency"]:
		if not _number(saved[key], 0, 100) or float(saved[key]) != int(expected[key]): return false
	return saved.result == expected.result and saved.feedback == expected.feedback and saved.missing == expected.missing

func _prints_good() -> bool:
	for quality in print_qualities:
		if float(quality) < PRINT_MINIMUM: return false
	return true

func _road_mode() -> bool:
	return mode in ["campaign", "basis"]

func _invalidate_report() -> void:
	submitted_cards = []
	report_score = {}
	result = "incomplete"

func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func _keys(data: Dictionary, keys: Array) -> bool:
	if data.size() != keys.size(): return false
	for key in keys:
		if not data.has(key): return false
	return true
