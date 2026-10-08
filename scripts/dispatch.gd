class_name DispatchLedger
extends RefCounted
## One live radio incident, deterministic time and JSON-safe random state.
## Only noise/traffic are generated in M1. Fire is a valid future incident type.

const SCHEMA := 2
const Legacy = preload("res://scripts/dispatch_v1.gd")
const ACCEPTED_WINDOW := 600.0
const FIRST_REPORT := 20.0
const REST_INTERVAL := 30.0
const RESPONSE_WINDOW := 90.0
const MAX_MESSAGES := 8
const MAX_TIME := 1_000_000_000.0
const MAX_TICK := 3600.0
const MAX_SERIAL := 10_000_000
const RANDOM_MODULUS := 2_147_483_647
const LOCATIONS := [[14, 0, 30], [-20, 0, 17], [42, 0, -28]]
const KINDS := ["noise", "traffic", "fire"]
const PHASES := ["offered", "accepted", "expired", "handed_over", "resolved"]
const LIVE_PHASES := ["offered", "accepted"]

var role := "police"
var incident: Dictionary = {}
var duty_time := 0.0
var next_report := FIRST_REPORT
var serial := 0
var completed := 0
var missed := 0
var messages: Array = []
var _random_state := 1

func start(seed_value: int, duty_role: String = "police") -> void:
	role = "fire" if duty_role == "fire" else "police"
	incident = {}
	duty_time = 0.0
	next_report = FIRST_REPORT
	serial = 0
	completed = 0
	missed = 0
	messages = []
	# Avoid abs(INT64_MIN) and save only an exactly JSON-representable seed.
	_random_state = ((seed_value % (RANDOM_MODULUS - 1)) + (RANDOM_MODULUS - 1)) % (RANDOM_MODULUS - 1) + 1
	_message("Meldkamer verbonden. Meldingen volgen tijdens je dienst.")

func tick(delta: float) -> bool:
	if not is_finite(delta) or delta <= 0.0 or delta > MAX_TICK or duty_time + delta > MAX_TIME:
		return false
	var target := duty_time + delta
	var changed := false
	# Process event times, not frames: one large tick equals many smaller ticks.
	while true:
		if _is_live():
			if float(incident.deadline) > target:
				break
			duty_time = float(incident.deadline)
			incident.phase = "expired"
			incident.closed_at = duty_time
			missed += 1
			next_report = duty_time + REST_INTERVAL
			_message("Melding %d verlopen; een andere eenheid neemt de nasleep over." % serial)
			changed = true
		elif next_report <= target and serial < MAX_SERIAL:
			duty_time = next_report
			_offer()
			changed = true
		else:
			break
	duty_time = target
	return changed

func accept() -> bool:
	if incident.is_empty() or incident.phase != "offered" or duty_time >= float(incident.deadline):
		return false
	incident.phase = "accepted"
	incident.response_window = ACCEPTED_WINDOW
	incident.deadline = float(incident.reported_at) + ACCEPTED_WINDOW
	next_report = float(incident.deadline) + REST_INTERVAL
	_message("Melding %d aangenomen. Ga naar de aangegeven locatie." % serial)
	return true

func hand_over() -> bool:
	if not _is_live() or duty_time >= float(incident.deadline):
		return false
	incident.phase = "handed_over"
	incident.closed_at = duty_time
	next_report = duty_time + REST_INTERVAL
	_message("Melding %d doorgegeven. Je kunt de surveillance voortzetten." % serial)
	return true

func resolve(quality: int) -> bool:
	if incident.is_empty() or incident.phase != "accepted" or quality < 0 or quality > 100:
		return false
	if duty_time >= float(incident.deadline):
		return false
	incident.phase = "resolved"
	incident.quality = quality
	incident.closed_at = duty_time
	completed += 1
	next_report = duty_time + REST_INTERVAL
	_message("Melding %d afgehandeld. Zorgvuldigheid: %d/100." % [serial, quality])
	return true

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "role": role, "incident": incident.duplicate(true),
		"duty_time": duty_time, "next_report": next_report, "serial": serial,
		"completed": completed, "missed": missed, "messages": messages.duplicate(true),
		"rng_state": _random_state}

func restore(data: Variant) -> bool:
	if data is Dictionary and _integer(data.get("schema"), 1, 1):
		var legacy := Legacy.new()
		if not legacy.restore(data): return false
		data = legacy.to_dict()
		data.schema = SCHEMA
		data["role"] = "police"
		if not data.incident.is_empty():
			data.incident["response_window"] = RESPONSE_WINDOW
			data.incident.position = location_for(str(data.incident.kind), int(data.incident.variant))
	# Every candidate is validated before any member of the active ledger changes.
	if not data is Dictionary or not _integer(data.get("schema"), SCHEMA, SCHEMA):
		return false
	if not _exact_keys(data, ["schema", "role", "incident", "duty_time", "next_report", "serial", "completed", "missed", "messages", "rng_state"]):
		return false
	if data.get("role") not in ["police", "fire"]: return false
	if not _number(data.duty_time, 0.0, MAX_TIME) or not _number(data.next_report, 0.0, MAX_TIME + ACCEPTED_WINDOW + REST_INTERVAL):
		return false
	if not _integer(data.serial, 0, MAX_SERIAL) or not _integer(data.completed, 0, MAX_SERIAL) or not _integer(data.missed, 0, MAX_SERIAL):
		return false
	if int(data.completed) + int(data.missed) > int(data.serial) or not _integer(data.rng_state, 1, RANDOM_MODULUS - 1):
		return false
	if not data.messages is Array or data.messages.size() > MAX_MESSAGES:
		return false
	for message in data.messages:
		if not message is String or message.is_empty() or message.length() > 256:
			return false
	if not data.incident is Dictionary:
		return false
	if int(data.serial) == 0:
		if not data.incident.is_empty() or int(data.completed) != 0 or int(data.missed) != 0:
			return false
		if not _same(float(data.next_report), FIRST_REPORT) or float(data.duty_time) >= FIRST_REPORT:
			return false
	elif not _valid_incident(data.incident, data):
		return false
	incident = data.incident.duplicate(true)
	# JSON.parse returns floating-point integers; keep the public interface typed.
	if not incident.is_empty():
		incident.id = int(incident.id)
		incident.variant = int(incident.variant)
		incident.quality = int(incident.quality)
		incident.position = location_for(str(incident.kind), int(incident.variant))
	role = str(data.role)
	duty_time = float(data.duty_time)
	next_report = float(data.next_report)
	serial = int(data.serial)
	completed = int(data.completed)
	missed = int(data.missed)
	messages = data.messages.duplicate(true)
	_random_state = int(data.rng_state)
	return true

func _offer() -> void:
	_random_state = (_random_state * 48_271) % RANDOM_MODULUS
	var variant := _random_state % LOCATIONS.size()
	if not incident.is_empty() and variant == int(incident.variant):
		variant = (variant + 1) % LOCATIONS.size()
	serial += 1
	# Alternate the two playable M1 families; the seed varies their locations.
	var kind: String = "fire" if role == "fire" else ("noise" if serial % 2 == 1 else "traffic")
	incident = {"id": serial, "kind": kind, "title": _title(kind, variant),
		"position": location_for(kind, variant), "phase": "offered",
		"reported_at": duty_time, "deadline": duty_time + RESPONSE_WINDOW,
		"variant": variant, "closed_at": -1.0, "quality": -1, "response_window": RESPONSE_WINDOW}
	next_report = float(incident.deadline) + REST_INTERVAL
	_message("Melding %d: %s. Aannemen of doorgeven via de radio." % [serial, incident.title])

func _is_live() -> bool:
	return not incident.is_empty() and incident.phase in LIVE_PHASES

func _message(text: String) -> void:
	messages.append(text)
	while messages.size() > MAX_MESSAGES:
		messages.pop_front()

func _title(kind: String, variant: int) -> String:
	match kind:
		"noise":
			return ["Ruzie bij het plein", "Onrust bij de kruising", "Geluidsoverlast bij de werkplaats"][variant]
		"traffic":
			return ["Aanrijding bij het plein", "Stilstaand voertuig op de kruising", "Verkeershinder bij de werkplaats"][variant]
		_:
			return ["Rookmelding bij het plein", "Buitenbrand bij de kruising", "Rook bij de werkplaats"][variant]

func _valid_incident(candidate: Dictionary, ledger: Dictionary) -> bool:
	if not _exact_keys(candidate, ["id", "kind", "title", "position", "phase", "reported_at", "deadline", "variant", "closed_at", "quality", "response_window"]):
		return false
	if not _integer(candidate.id, 1, MAX_SERIAL) or int(candidate.id) != int(ledger.serial):
		return false
	if not candidate.kind is String or candidate.kind not in KINDS or not candidate.phase is String or candidate.phase not in PHASES:
		return false
	if ledger.role == "fire" and candidate.phase in LIVE_PHASES and candidate.kind != "fire": return false
	if not _integer(candidate.variant, 0, LOCATIONS.size() - 1):
		return false
	var variant := int(candidate.variant)
	if not candidate.title is String or candidate.title.is_empty() or candidate.title.length() > 160:
		return false
	if not candidate.position is Array or candidate.position.size() != 3:
		return false
	for index in range(3):
		if not _number(candidate.position[index], -500.0, 500.0) or not _same(float(candidate.position[index]), float(location_for(str(candidate.kind), variant)[index])):
			return false
	if not _number(candidate.reported_at, FIRST_REPORT, MAX_TIME) or not _number(candidate.deadline, FIRST_REPORT, MAX_TIME + ACCEPTED_WINDOW):
		return false
	if not _number(candidate.response_window, RESPONSE_WINDOW, ACCEPTED_WINDOW) or float(candidate.response_window) not in [RESPONSE_WINDOW, ACCEPTED_WINDOW]: return false
	if candidate.phase == "offered" and float(candidate.response_window) != RESPONSE_WINDOW: return false
	if float(candidate.reported_at) > float(ledger.duty_time) or not _same(float(candidate.deadline), float(candidate.reported_at) + float(candidate.response_window)):
		return false
	if float(candidate.reported_at) < FIRST_REPORT + (int(ledger.serial) - 1) * REST_INTERVAL:
		return false
	if not _integer(candidate.quality, -1, 100) or not _number(candidate.closed_at, -1.0, MAX_TIME):
		return false
	var accounted := int(ledger.completed) + int(ledger.missed)
	if candidate.phase in LIVE_PHASES:
		if float(ledger.duty_time) >= float(candidate.deadline) or candidate.closed_at != -1 or candidate.quality != -1:
			return false
		if accounted >= int(ledger.serial) or not _same(float(ledger.next_report), float(candidate.deadline) + REST_INTERVAL):
			return false
	else:
		if float(candidate.closed_at) < float(candidate.reported_at) or float(candidate.closed_at) > float(ledger.duty_time):
			return false
		if not _same(float(ledger.next_report), float(candidate.closed_at) + REST_INTERVAL):
			return false
		# An exhausted serial counter leaves the final terminal result visible.
		if float(ledger.duty_time) >= float(ledger.next_report) and int(ledger.serial) < MAX_SERIAL:
			return false
		match candidate.phase:
			"resolved":
				if int(ledger.completed) < 1 or int(candidate.quality) < 0 or float(candidate.closed_at) >= float(candidate.deadline):
					return false
			"expired":
				if int(ledger.missed) < 1 or candidate.quality != -1 or not _same(float(candidate.closed_at), float(candidate.deadline)):
					return false
			"handed_over":
				if candidate.quality != -1 or accounted >= int(ledger.serial) or float(candidate.closed_at) >= float(candidate.deadline):
					return false
	return true

func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, minimum, maximum) and float(value) == floorf(float(value))

func _same(first: float, second: float) -> bool:
	return absf(first - second) < 0.000001

func _exact_keys(data: Dictionary, keys: Array) -> bool:
	if data.size() != keys.size():
		return false
	for key in keys:
		if not data.has(key):
			return false
	return true

static func location_for(kind: String, variant: int) -> Array:
	if kind == "traffic": return [-20, 0, 17] # Actual shared traffic scene; narrative/rain vary.
	if kind == "noise": return [[14, 0, 30], [-7, 0, 23.5], [29, 0, -36]][variant].duplicate()
	return [[14, 0, 30], [-7, 0, 25], [42, 0, -34]][variant].duplicate()
