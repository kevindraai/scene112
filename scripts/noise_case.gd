class_name NoiseCase
extends RefCounted
## A repeatable public-order incident: real observations, two perspectives,
## agreements and observed physical separation, followed by a sourced report.
const SCHEMA := 1
const DATA = preload("res://data/noise_variants.gd")
var id := 0
var variant := 0
var clock := 0.0
var phase := "none"
var events: Array = []
var observations: Array = []
var people := {}
var separated := false
var pressure := 0
var report := {}

func begin(serial: int, choice: int) -> bool:
	if serial < 1 or serial > 10000000 or choice < 0 or choice >= DATA.VARIANTS.size(): return false
	id = serial
	variant = choice
	clock = 0
	phase = "active"
	events.clear()
	observations.clear()
	people = {"reporter": {"heard": false, "agreement": false, "accusations": 0, "recovered": false, "statements": []}, "participant": {"heard": false, "agreement": false, "accusations": 0, "recovered": false, "statements": []}}
	separated = false
	pressure = 0
	report.clear()
	return true

func tick(delta: float) -> void:
	if phase == "active" and is_finite(delta) and delta > 0 and delta <= 5 and clock + delta <= 86400: clock += delta

func observe(source: String) -> bool:
	if source not in ["activity", "access"] or source in observations: return false
	return _event("observe", {"source": source})

func speak(person: String, approach: String) -> bool:
	if not people.has(person) or approach not in ["open", "accuse", "agree", "recover"]: return false
	if approach == "open" and people[person].heard: return false
	if approach == "agree" and (not people.reporter.heard or not people.participant.heard or people[person].agreement): return false
	if approach == "recover" and (people[person].accusations == 0 or people[person].recovered): return false
	return _event("speak", {"person": person, "approach": approach})

func record_separation(distance: float) -> bool:
	if phase != "active": return false
	if separated or not people.reporter.agreement or not people.participant.agreement or not is_finite(distance) or distance < 3 or distance > 30: return false
	return _event("separate", {"distance": distance})

func cards() -> Array:
	if phase == "none": return []
	var result: Array = observations.duplicate()
	for person: String in people:
		if people[person].heard: result.append("statement_" + person)
	if people.reporter.agreement and people.participant.agreement: result.append("agreements")
	if separated: result.append("separation")
	return result

func submit(selected: Array) -> bool:
	var unique := {}
	for source: Variant in selected:
		if not source is String or source not in cards() or unique.has(source): return false
		unique[source] = true
	return _event("report", {"selected": selected.duplicate()})

func _event(kind: String, args: Dictionary) -> bool:
	if phase != "active" or events.size() >= 64: return false
	var event := {"kind": kind, "time": clock, "args": args.duplicate(true)}
	events.append(event)
	_apply(event)
	return true

func _apply(event: Dictionary) -> void:
	var args: Dictionary = event.args
	match str(event.kind):
		"observe": observations.append(args.source)
		"speak":
			var person: Dictionary = people[args.person]
			if args.approach == "accuse":
				pressure += 1
				person.accusations += 1
				person.recovered = false
			elif args.approach == "recover": person.recovered = true
			elif args.approach == "agree": person.agreement = true
			else: person.heard = true
			person.statements.append({"time": event.time, "source": "Persoon · " + str(DATA.VARIANTS[variant][args.person].name), "text": "Dank dat u het zonder vooraf ingevuld oordeel opnieuw vraagt." if args.approach == "recover" else str(DATA.VARIANTS[variant][args.person][args.approach])})
		"separate": separated = true
		"report":
			var total := 0
			for source: String in args.selected:
				total += 20 if source.begins_with("statement_") else (20 if source == "agreements" else (10 if source == "separation" else 15))
			total = clampi(total - pressure * 15, 0, 100)
			var supported := true
			for source: String in ["activity", "access", "statement_reporter", "statement_participant", "agreements", "separation"]: supported = supported and source in args.selected
			for person: Dictionary in people.values(): supported = supported and (person.accusations == 0 or person.recovered)
			report = {"total": total, "result": "careful" if total >= 80 and separated and supported else "partial", "selected": args.selected.duplicate(), "pressure": pressure}
			phase = "completed"

func to_dict() -> Dictionary:
	if phase == "none": return {}
	return {"schema": SCHEMA, "id": id, "variant": variant, "clock": clock, "events": events.duplicate(true)}

func restore(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 5: return false
	for key: String in ["schema", "id", "variant"]:
		var number: Variant = value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or floorf(float(number)) != float(number): return false
	if float(value.schema) != SCHEMA or not (value.get("clock") is int or value.get("clock") is float) or not is_finite(float(value.clock)) or value.clock < 0 or value.clock > 86400: return false
	if not value.get("events") is Array or value.events.size() > 64: return false
	var candidate := NoiseCase.new()
	if not candidate.begin(int(value.id), int(value.variant)): return false
	var last := 0.0
	for event: Variant in value.events:
		if not event is Dictionary or event.size() != 3 or not event.get("args") is Dictionary: return false
		if not (event.get("time") is int or event.get("time") is float) or not is_finite(float(event.time)) or event.time < last or event.time > value.clock: return false
		candidate.clock = float(event.time)
		var args: Dictionary = event.args
		var ok := false
		match str(event.get("kind", "")):
			"observe":
				if args.size() != 1 or not args.get("source") is String: return false
				ok = candidate.observe(args.source)
			"speak":
				if args.size() != 2 or not args.get("person") is String or not args.get("approach") is String: return false
				ok = candidate.speak(args.person, args.approach)
			"separate":
				if args.size() != 1 or not (args.get("distance") is int or args.get("distance") is float): return false
				ok = candidate.record_separation(float(args.distance))
			"report":
				if args.size() != 1 or not args.get("selected") is Array: return false
				ok = candidate.submit(args.selected)
			_: return false
		if not ok: return false
		last = float(event.time)
	candidate.clock = float(value.clock)
	for key: String in ["id", "variant", "clock", "phase", "events", "observations", "people", "separated", "pressure", "report"]:
		var data: Variant = candidate.get(key)
		set(key, data.duplicate(true) if data is Dictionary or data is Array else data)
	return true
