class_name InvestigationCase
extends RefCounted
## Durable investigation journal. No hidden truth scan or confession-only victory.
const Fire = preload("res://scripts/fire_case.gd")
const SCHEMA := 2
const MODES := ["none", "campaign", "practice"]
const DATA_PATH := "res://data/cases/house24_investigation.json"
var mode := "none"
var phase := "scene"
var clock := 0.0
var incident := {}
var events: Array = []
var evidence := {}
var photographs := {}
var witnesses := {}
var links: Array = []
var lab_requested := -1.0
var lab_result := false
var hypothesis := "unknown"
var report := {}
var draft_selection: Array = []
var _data := {}

func _init() -> void:
	_data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	_reset()

func _reset() -> void:
	phase = "scene"
	clock = 0
	events.clear()
	evidence.clear()
	photographs.clear()
	links.clear()
	lab_requested = -1
	lab_result = false
	hypothesis = "unknown"
	report.clear()
	draft_selection.clear()
	witnesses = {}
	for id: String in _data.witnesses:
		witnesses[id] = {"asked": [], "statements": [], "suggestions": 0, "contradiction": false,
			"stopped": false, "refused": false, "suspect": false, "explanation": false, "cautie": false, "lawyer": false}

func begin(value: String, snapshot: Dictionary = {}) -> bool:
	if value not in MODES: return false
	if value != "none":
		var fire := Fire.new()
		if not fire.restore(snapshot) or fire.mode != "campaign" or fire.phase != "completed": return false
	if value == "none" and not snapshot.is_empty(): return false
	mode = value
	incident = snapshot.duplicate(true)
	_reset()
	return true

func tick(delta: float) -> bool:
	if mode == "none" or phase == "completed" or not is_finite(delta) or delta <= 0 or delta > 5 or clock + delta > 100000: return false
	clock += delta
	return true

func photograph(id: String, quality: float) -> bool:
	if not _data.evidence.has(id) or not is_finite(quality) or quality < 0.0 or quality > 1.0 or quality <= float(photographs.get(id, {}).get("quality", -1)): return false
	return _event("photo", {"id": id, "quality": quality})

func collect(id: String) -> bool:
	if not _data.evidence.has(id) or evidence.has(id): return false
	if id in ["origin", "connection", "living"] and float(photographs.get(id, {}).get("quality", 0)) < 0.65: return false
	return _event("collect", {"id": id})

func question(person: String, choice: String) -> bool:
	if not witnesses.has(person) or choice not in ["open", "timeline", "repair", "suggestive", "show_entry", "clarify"]: return false
	var witness: Dictionary = witnesses[person]
	if witness.stopped or (witness.suspect and not (witness.explanation and witness.cautie and witness.lawyer)): return false
	if choice in witness.asked and choice != "suggestive": return false
	if choice == "show_entry" and (person != "lars" or not evidence.has("entry_record") or "open" not in witness.asked): return false
	if choice == "clarify" and "suggestive" not in witness.asked: return false
	return _event("question", {"person": person, "choice": choice})

func interview_action(person: String, choice: String) -> bool:
	if not witnesses.has(person) or choice not in ["stop", "suspect", "explanation", "cautie", "lawyer", "resume_voluntary"]: return false
	var witness: Dictionary = witnesses[person]
	if choice == "suspect" and (not evidence.has("connection") or "repair" not in witness.asked): return false
	if choice == "explanation" and (not witness.suspect or witness.explanation): return false
	if choice == "cautie" and (not witness.explanation or witness.cautie): return false
	if choice == "lawyer" and (not witness.cautie or witness.lawyer): return false
	if choice == "resume_voluntary" and (not witness.stopped or (witness.suspect and not witness.lawyer)): return false
	return _event("interview", {"person": person, "choice": choice})

func link_evidence(id: String) -> bool:
	if not _data.links.has(id) or id in links: return false
	for required: String in _data.links[id].requires:
		if not evidence.has(required): return false
	if id == "entry_contradiction" and not witnesses.lars.contradiction: return false
	return _event("link", {"id": id})

func request_lab() -> bool:
	if not evidence.has("connection") or lab_requested >= 0: return false
	return _event("lab_request", {})

func receive_lab() -> bool:
	if lab_requested < 0 or clock - lab_requested < 20 or lab_result: return false
	return _event("lab_receive", {})

func choose_hypothesis(id: String) -> bool:
	if not _data.hypotheses.has(id): return false
	return _event("hypothesis", {"id": id})

func set_draft(selected: Array) -> bool:
	if mode == "none" or phase == "completed": return false
	if not _valid_selection(selected): return false
	draft_selection = selected.duplicate()
	return true

func _valid_selection(selected: Array) -> bool:
	var unique := {}
	for id: Variant in selected:
		if not id is String or not report_cards().has(id) or unique.has(id): return false
		unique[id] = true
	return true

func finalize_report() -> bool:
	if phase != "report" or report.get("outcome") not in ["incomplete", "wrong"]: return false
	return _event("close", {})

func submit_report(selected: Array) -> Dictionary:
	if mode == "none" or phase == "completed": return {}
	if not _valid_selection(selected): return {}
	if not _event("report", {"selected": selected.duplicate()}): return {}
	return report.duplicate(true)

func report_cards() -> Dictionary:
	var cards := {}
	for id: String in evidence: cards[id] = _data.evidence[id].title
	for id: String in witnesses:
		if witnesses[id].refused: cards["refusal_" + id] = _data.witnesses[id].name + " · weigering / onderbreking, geen schuldindicatie"
		if not witnesses[id].statements.is_empty(): cards["statement_" + id] = _data.witnesses[id].name + " · verklaring"
	if lab_result: cards["lab"] = "Fictief deskundigenonderzoek · bevindingen en beperkingen"
	if witnesses.lars.contradiction: cards["contradiction"] = "Aanwezigheid tegengesproken; geen bewijs van opzet"
	cards["limits"] = "Beperkingen door brandverloop, water en onzekerheid"
	return cards

func damage() -> float:
	if incident.is_empty(): return 0
	var total := 0.0
	var capacity := 0.0
	for index in incident.cells.size():
		total += float(incident.cells[index].burned)
		capacity += float(Fire.CELL_DATA[index].fuel)
	return total / capacity

func evidence_quality(id: String) -> float:
	if id not in ["origin", "connection", "living"]: return 1.0
	var cell: Dictionary = incident.cells[{"origin": 1, "connection": 1, "living": 0}[id]]
	var remaining := clampf(1 - float(cell.burned) / float(Fire.CELL_DATA[1 if id != "living" else 0].fuel), 0, 1)
	return clampf(remaining * (1 - float(cell.wet) * 0.20), 0, 1)

func _event(kind: String, args: Dictionary) -> bool:
	if mode == "none" or phase == "completed" or events.size() >= 128: return false
	var event := {"kind": kind, "time": clock, "args": args.duplicate(true)}
	events.append(event)
	_apply(event)
	return true

func _apply(event: Dictionary) -> void:
	var args: Dictionary = event.args
	match str(event.kind):
		"photo": photographs[args.id] = {"quality": args.quality, "time": event.time}
		"collect":
			evidence[args.id] = {"source": _data.evidence[args.id].source, "time": event.time, "quality": evidence_quality(args.id)}
		"question":
			var witness: Dictionary = witnesses[args.person]
			witness.asked.append(args.choice)
			var text: String = str(_data.witnesses[args.person].get(args.choice, ""))
			if args.choice == "show_entry":
				witness.contradiction = true
				text = _data.witnesses.lars.corrected
			elif args.choice == "clarify": text = _data.witnesses[args.person].open
			elif args.choice == "suggestive":
				witness.suggestions += 1
				if args.person == "lars": witness.stopped = true; witness.refused = true
			witness.statements.append({"choice": args.choice, "text": text, "time": event.time})
		"interview":
			var witness: Dictionary = witnesses[args.person]
			match str(args.choice):
				"stop": witness.stopped = true; witness.refused = true
				"suspect": witness.suspect = true; witness.explanation = false; witness.cautie = false; witness.lawyer = false
				"resume_voluntary": witness.stopped = false
				_: witness[args.choice] = true
		"link": links.append(args.id)
		"lab_request": lab_requested = float(event.time)
		"lab_receive": lab_result = true
		"hypothesis": hypothesis = args.id
		"close":
			draft_selection = report.selected.duplicate()
			phase = "completed"
		"report":
			draft_selection = args.selected.duplicate()
			report = _score(args.selected)
			phase = "completed" if report.outcome == "careful" else "report"

func _score(selected: Array) -> Dictionary:
	var coherent: bool = hypothesis == "electrical" and lab_result and evidence_quality("connection") >= 0.35 and "origin_connection" in links and "alternative_tested" in links
	var uncertain: bool = hypothesis == "unknown"
	var unsupported: bool = hypothesis in ["intentional", "open_flame"] or (hypothesis == "electrical" and not coherent)
	var cited_evidence := 0
	for id: String in evidence:
		if id in selected: cited_evidence += 1
	var source_points := mini(30, cited_evidence * 5)
	var statement_points := 0
	var suggestion_penalty := 0
	for id: String in witnesses:
		if witnesses[id].refused and "refusal_" + id in selected: statement_points += 8
		elif "statement_" + id in selected:
			if "open" in witnesses[id].asked: statement_points += 8
			if "timeline" in witnesses[id].asked: statement_points += 4
		suggestion_penalty += mini(10, int(witnesses[id].suggestions) * 5)
	var cited_links := 0
	for id: String in links:
		var all_cited := true
		for needed: String in _data.links[id].requires: all_cited = all_cited and needed in selected
		if id == "entry_contradiction": all_cited = all_cited and "contradiction" in selected and "statement_lars" in selected
		if all_cited: cited_links += 1
	var reasoning_points := mini(20, cited_links * 5)
	var limits_points := 10 if "limits" in selected else 0
	var selection_points := mini(16, selected.size() * 2)
	var grade := clampi(source_points + statement_points + reasoning_points + limits_points + selection_points - suggestion_penalty, 0, 100)
	if unsupported: grade = mini(grade, 35)
	var enough: bool = cited_evidence >= 4 and ("open" in witnesses.saar.asked or witnesses.saar.refused) and ("open" in witnesses.lars.asked or witnesses.lars.refused) and "limits" in selected and ("statement_saar" in selected or (witnesses.saar.refused and "refusal_saar" in selected)) and ("statement_lars" in selected or (witnesses.lars.refused and "refusal_lars" in selected))
	var cited_cause: bool = coherent and "lab" in selected and "origin" in selected and "connection" in selected and "living" in selected and "overview" in selected
	var essential_limit: bool = damage() > 0.65 or evidence_quality("connection") < 0.35 or evidence_quality("origin") < 0.35
	var cited_uncertainty: bool = uncertain and essential_limit and "origin" in selected and "connection" in selected and "overview" in selected and "dispatch_record" in selected and (not lab_result or "lab" in selected)
	var outcome := "wrong" if unsupported else ("careful" if enough and grade >= 75 and (cited_cause or cited_uncertainty) else "incomplete")
	return {"total": grade, "outcome": outcome, "hypothesis": hypothesis, "damage": damage(), "evidence_count": evidence.size(), "suggestion_penalty": suggestion_penalty, "selected": selected.duplicate()}

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "mode": mode, "clock": clock, "incident": incident.duplicate(true), "events": events.duplicate(true), "draft": draft_selection.duplicate()}

func restore(value: Variant) -> bool:
	if not value is Dictionary or value.get("mode") not in MODES: return false
	var revision: Variant = value.get("schema")
	if not (revision is int or revision is float) or not is_finite(float(revision)) or float(revision) not in [1.0, 2.0]: return false
	if value.size() != (5 if float(revision) == 1 else 6): return false
	if float(revision) == 2 and not value.get("draft") is Array: return false
	if not value.get("incident") is Dictionary or not value.get("events") is Array or value.events.size() > 128: return false
	if not (value.get("clock") is int or value.get("clock") is float) or not is_finite(float(value.clock)) or value.clock < 0 or value.clock > 100000: return false
	var candidate := InvestigationCase.new()
	if not candidate.begin(value.mode, value.incident): return false
	var last := 0.0
	for event: Variant in value.events:
		if not event is Dictionary or event.size() != 3 or not event.get("args") is Dictionary or not (event.get("time") is int or event.get("time") is float): return false
		if not is_finite(float(event.time)) or event.time < last or event.time > value.clock: return false
		candidate.clock = float(event.time)
		var args: Dictionary = event.args
		var applied := false
		match str(event.get("kind", "")):
			"photo":
				if args.size() != 2 or not args.get("id") is String or not (args.get("quality") is int or args.get("quality") is float): return false
				applied = candidate.photograph(args.id, float(args.quality))
			"collect", "link", "hypothesis":
				if args.size() != 1 or not args.get("id") is String: return false
				match str(event.kind):
					"collect": applied = candidate.collect(args.id)
					"link": applied = candidate.link_evidence(args.id)
					_: applied = candidate.choose_hypothesis(args.id)
			"question", "interview":
				if args.size() != 2 or not args.get("person") is String or not args.get("choice") is String: return false
				applied = candidate.question(args.person, args.choice) if event.kind == "question" else candidate.interview_action(args.person, args.choice)
			"lab_request", "lab_receive":
				if not args.is_empty(): return false
				applied = candidate.request_lab() if event.kind == "lab_request" else candidate.receive_lab()
			"close":
				if not args.is_empty(): return false
				applied = candidate.finalize_report()
			"report":
				if args.size() != 1 or not args.get("selected") is Array: return false
				applied = not candidate.submit_report(args.selected).is_empty()
			_: return false
		if not applied: return false
		last = float(event.time)
	candidate.clock = float(value.clock)
	if float(revision) == 2:
		if candidate.phase == "completed":
			if value.draft != candidate.draft_selection: return false
		elif candidate.mode == "none":
			if not value.draft.is_empty(): return false
		elif not candidate.set_draft(value.draft): return false
	for key: String in ["mode", "phase", "clock", "incident", "events", "evidence", "photographs", "witnesses", "links", "lab_requested", "lab_result", "hypothesis", "report", "draft_selection"]:
		var data: Variant = candidate.get(key)
		set(key, data.duplicate(true) if data is Dictionary or data is Array else data)
	return true


func expert_report() -> Dictionary:
	if not lab_result: return {}
	var quality := evidence_quality("connection")
	var ready_time := lab_requested + 20
	for event: Dictionary in events:
		if event.kind == "lab_receive": ready_time = float(event.time)
	return {"source": _data.expert_report.source, "time": ready_time, "quality": quality,
		"finding": "supports_electrical" if quality >= 0.35 else "inconclusive",
		"text": _data.expert_report.supported if quality >= 0.35 else _data.expert_report.inconclusive}
