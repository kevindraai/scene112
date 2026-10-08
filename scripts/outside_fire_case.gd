class_name OutsideFireCase
extends RefCounted
## Original fictional outdoor exercise; no interior, rescue or training claim.

const SCHEMA := 1
const MAX_INCIDENT_ID := 10_000_000
const BASICS := ["gear", "radio", "enter", "drive", "exit"]
const MATERIALS := ["houten kratten", "droge snoeiresten", "kartonstapel"]
const CELL_DATA := [
	{"id": "center", "pos": [0.0, 0.55, 0.0], "fuel": 1.0, "heat": 0.72},
	{"id": "left", "pos": [-1.8, 0.55, 0.7], "fuel": 0.8, "heat": 0.25},
	{"id": "right", "pos": [1.8, 0.55, 0.7], "fuel": 0.6, "heat": 0.02}]
const KEYS := ["schema", "incident_id", "variant", "origin", "mode", "phase", "clock", "basics", "recon", "tactic", "hydrant_connected", "hose_points", "water_liters", "water_used", "hit_water", "cells", "victim", "unsafe_seconds", "actions", "simulation", "withdrew", "report_score", "result"]
var incident_id := -1
var variant := 0
var origin := Vector3.ZERO
var mode := "none"
var phase := "briefing"
var clock := 0.0
var basics: Dictionary = {}
var recon: Dictionary = {}
var tactic := ""
var hydrant_connected := false
var hose_points: Array = []
var water_liters := 0.0
var water_used := 0.0
var hit_water := 0.0
var cells: Array = []
var victim := {"status": "none", "exposure": 0.0}
var unsafe_seconds := 0.0
var actions: Array = []
var simulation: Array = []
var _replaying := false
var _operation_count := 0
var withdrew := false
var report_score: Dictionary = {}
var result := "incomplete"

func _init() -> void:
	_reset()

func begin(id: int, material_variant: int, site: Vector3) -> bool:
	if id < 1 or id > MAX_INCIDENT_ID or material_variant not in range(3) or not _point(site) or absf(site.x) > 490 or absf(site.z) > 490 or absf(site.y) > 0.5: return false
	_reset()
	incident_id = id
	variant = material_variant
	origin = Vector3(site.x, 0, site.z)
	for cell in cells:
		var position := origin + _vector(cell.pos)
		cell.pos = [position.x, position.y, position.z]
	mode = "free"
	return true

func _reset() -> void:
	incident_id = -1; variant = 0; origin = Vector3.ZERO; mode = "none"; phase = "briefing"; clock = 0
	basics = {"gear": false, "radio": false, "enter": false, "drive": false, "exit": false}
	recon = {"exterior": false, "surroundings": false}
	tactic = ""; hydrant_connected = false; hose_points = []; water_liters = 0; water_used = 0; hit_water = 0
	cells = []
	for item in CELL_DATA:
		var cell: Dictionary = item.duplicate(true)
		var position := _vector(cell.pos)
		cell.pos = [position.x, position.y, position.z]
		cell.burned = 0.0; cell.wet = 0.0
		cells.append(cell)
	victim = {"status": "none", "exposure": 0.0}; unsafe_seconds = 0; actions = []; simulation = []; _operation_count = 0; withdrew = false; report_score = {}; result = "incomplete"

func complete_step(id: String) -> bool:
	if mode != "free" or phase != "briefing" or id not in BASICS or basics[id]: return false
	for step in BASICS:
		if not basics[step]:
			if step != id: return false
			basics[id] = true; _log("preparation_" + id)
			return true
	return false

func check_recon(id: String) -> bool:
	if phase != "briefing" or not basics.exit or not recon.has(id) or recon[id]: return false
	recon[id] = true; _log("recon_" + id)
	return true

func water_source() -> Vector3:
	return origin + Vector3(6, 0, -5)

func target_position(id: String) -> Vector3:
	for cell in cells:
		if cell.id == id: return _vector(cell.pos)
	return Vector3.INF

func connect_water() -> bool:
	if phase != "briefing" or not recon.exterior or hydrant_connected: return false
	hydrant_connected = true; water_liters = 220; hose_points = [[water_source().x, 0.0, water_source().z]]
	_log("water_connected")
	return true

func choose_tactic(value: String) -> bool:
	if phase != "briefing" or value != "defensive" or not recon.exterior or not recon.surroundings or not hydrant_connected: return false
	tactic = value; phase = "active"; _log("tactic_defensive")
	return true

func safe_approach(point: Vector3) -> bool:
	var local := point - origin
	return _point(point) and absf(local.y) <= 0.5 and local.z <= -2.5 and local.length() <= 8

func _unsafe_position(point: Vector3) -> bool:
	return point.distance_to(origin) <= 8 and not safe_approach(point)

func add_hose_point(point: Vector3) -> bool:
	if not hydrant_connected or phase == "completed" or hose_points.size() >= 6 or not safe_approach(point): return false
	var grounded := Vector3(point.x, 0, point.z)
	var segment := grounded.distance_to(_vector(hose_points.back()))
	if segment < 0.7 or segment > 7.5 or hose_length() + segment > 35: return false
	hose_points.append([point.x, 0.0, point.z]); _log("hose_laid")
	return true

func hose_length() -> float:
	var length := 0.0
	for index in range(1, hose_points.size()): length += _vector(hose_points[index]).distance_to(_vector(hose_points[index - 1]))
	return length

func has_nozzle_at(point: Vector3) -> bool:
	return hose_points.size() >= 2 and safe_approach(point) and _vector(hose_points.back()).distance_to(point) <= 2.5

func spray(target_id: String, delta: float) -> bool:
	if not _can_record() or phase != "active" or not _delta(delta) or hose_points.size() < 2 or water_liters < delta * 14: return false
	var match_cell: Dictionary = {}
	for cell in cells:
		if cell.id == target_id: match_cell = cell
	if target_id != "" and match_cell.is_empty(): return false
	water_liters = maxf(0, water_liters - delta * 14); water_used += delta * 14
	if not match_cell.is_empty():
		hit_water += delta * 14
		match_cell.heat = maxf(0, float(match_cell.heat) - delta * 0.27)
		match_cell.wet = minf(1, float(match_cell.wet) + delta * 0.25)
	_record_simulation(["spray", delta, target_id])
	return true

func tick(delta: float, operator_position: Vector3 = Vector3.INF) -> bool:
	if not _can_record() or phase != "active" or not _delta(delta) or clock + delta > 3600 or (operator_position != Vector3.INF and not _point(operator_position)): return false
	clock += delta
	if operator_position != Vector3.INF and _unsafe_position(operator_position): unsafe_seconds += delta
	if hydrant_connected: water_liters = minf(220, water_liters + delta * 6)
	var previous: Array = cells.duplicate(true)
	var rate: float = [1.0, 1.2, 0.8][variant]
	for index in range(3):
		var cell: Dictionary = cells[index]
		var spread := 0.0
		for other in previous:
			if other.id != cell.id and float(other.heat) > 0.65: spread += 0.012
		var fuel := float(cell.fuel)
		var heat := float(cell.heat)
		var wet := float(cell.wet)
		if fuel > 0.001 and (heat > 0.04 or (spread > 0 and wet < 0.4)):
			cell.heat = clampf(heat + delta * ((0.014 * rate if heat > 0.04 else 0) + spread - wet * 0.05), 0, 1)
			var consumed := minf(fuel, delta * heat * 0.004 * rate)
			cell.fuel = fuel - consumed; cell.burned = float(cell.burned) + consumed
		else: cell.heat = maxf(0, heat - delta * 0.08)
		cell.wet = maxf(0, wet - delta * 0.002)
	_record_simulation(["tick", delta, operator_position != Vector3.INF and _unsafe_position(operator_position)])
	return true

func average_heat() -> float:
	return (float(cells[0].heat) + float(cells[1].heat) + float(cells[2].heat)) / 3

func all_cold() -> bool:
	for cell in cells:
		if float(cell.heat) > 0.06: return false
	return true

func can_enter() -> bool:
	return false

func finish(withdraw: bool = false) -> Dictionary:
	if phase == "completed": return report_score.duplicate(true)
	if phase != "active" or (not withdraw and not all_cold()): return {}
	withdrew = withdraw; phase = "completed"; _log("withdraw" if withdraw else "handover")
	report_score = _score(); result = report_score.result
	return report_score.duplicate(true)

func _score() -> Dictionary:
	var damage := (float(cells[0].burned) + float(cells[1].burned) + float(cells[2].burned)) / 2.4
	# Credit actual cooling from the initial fire, not the initially cold
	# portion of the scene. One short burst must not earn near-full suppression.
	var initial_heat := 0.0
	var remaining_heat := 0.0
	for index in range(cells.size()):
		initial_heat += maxf(0.0, float(CELL_DATA[index].heat) - 0.06)
		remaining_heat += maxf(0.0, float(cells[index].heat) - 0.06)
	var cooled := clampf(1.0 - remaining_heat / initial_heat, 0.0, 1.0)
	var suppression := roundi(40 * cooled * (1 - damage)) if hit_water > 0 else 0
	var accuracy := roundi(15 * hit_water / water_used * minf(1, 120 / water_used)) if water_used > 0 else 0
	var safety := maxi(0, 10 - int(unsafe_seconds * 3))
	var total := 25 + (10 if hose_points.size() >= 2 else 0) + suppression + accuracy + safety
	var careful := not withdrew and all_cold() and hit_water >= 12 and accuracy >= 8 and damage <= 0.35 and unsafe_seconds < 2 and total >= 80
	return {"total": total, "suppression": suppression, "accuracy": accuracy, "safety": safety, "damage": damage, "water_used": water_used, "clock": clock, "result": "careful" if careful else "partial", "victim": "none"}

func objective() -> String:
	if mode == "none": return "Neem een buitenbrandmelding aan."
	if phase == "completed": return "Buitenbrand overgedragen; " + ("nasmeulen en schade blijven in de incidentstaat." if result == "partial" else "alle brandhaarden zijn zorgvuldig gekoeld.")
	for id in BASICS:
		if not basics[id]: return {"gear": "Controleer PBM bij de kazerne.", "radio": "Meld je bij de kazerneradio.", "enter": "Stap in de tankautospuit.", "drive": "Rijd naar de buitenbrandmelding.", "exit": "Parkeer veilig en stap uit."}[id]
	if not recon.exterior: return "Verken van buiten: brandend materiaal en veilige afstand."
	if not recon.surroundings: return "Controleer de omgeving en vrije terugweg; er zijn geen slachtoffers."
	if not hydrant_connected: return "Sluit de waterbron aan; de tank bevat maximaal 220 liter."
	if tactic.is_empty(): return "Kies een defensieve buiteninzet. Binneninzet is hier uitgesloten."
	if hose_points.size() < 2: return "Leg met Q de slang in de gemarkeerde veilige buitenzone."
	return "Koel afzonderlijke haarden met een gerichte straal; MISS verbruikt ook water. Draag over of trek terug."

func to_dict() -> Dictionary:
	var data := {"schema": SCHEMA, "origin": [origin.x, 0.0, origin.z]}
	for key in KEYS:
		if key in ["schema", "origin"]: continue
		var value: Variant = get(key)
		data[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return data

func restore(data: Variant) -> bool:
	if not data is Dictionary or data.size() != KEYS.size(): return false
	for key in KEYS:
		if not data.has(key): return false
	if not _integer(data.schema, 1, 1) or not _integer(data.incident_id, -1, MAX_INCIDENT_ID) or not _integer(data.variant, 0, 2) or not _array_point(data.origin) or float(data.origin[1]) != 0 or absf(float(data.origin[0])) > 490 or absf(float(data.origin[2])) > 490: return false
	if data.mode not in ["none", "free"] or data.phase not in ["briefing", "active", "completed"] or data.tactic not in ["", "defensive"] or not data.hydrant_connected is bool or not data.withdrew is bool: return false
	for pair in [["clock", 3600], ["water_liters", 220], ["water_used", 21820], ["hit_water", 21820], ["unsafe_seconds", 3600]]:
		if not _number(data[pair[0]], 0, pair[1]): return false
	if float(data.unsafe_seconds) > float(data.clock) or float(data.hit_water) > float(data.water_used) or float(data.water_liters) + float(data.water_used) > 220 + 6 * float(data.clock) + 0.0001 or (data.hydrant_connected and float(data.water_liters) < maxf(0, 220 - float(data.water_used)) - 0.0001): return false
	if not data.basics is Dictionary or data.basics.size() != 5 or not data.recon is Dictionary or data.recon.size() != 2 or not data.victim is Dictionary or data.victim.size() != 2 or data.victim.get("status") != "none" or not _number(data.victim.get("exposure"), 0, 0): return false
	var missing := false
	for id in BASICS:
		if not data.basics.get(id) is bool: return false
		if not data.basics[id]: missing = true
		elif missing: return false
	for id in ["exterior", "surroundings"]:
		if not data.recon.get(id) is bool: return false
	if not data.actions is Array or not data.simulation is Array: return false
	if not data.cells is Array or data.cells.size() != 3 or not data.hose_points is Array or data.hose_points.size() > 6 or not data.report_score is Dictionary or data.result not in ["incomplete", "careful", "partial"]: return false
	for index in range(3):
		var cell: Variant = data.cells[index]
		var position := _vector(data.origin) + _vector(CELL_DATA[index].pos)
		if not cell is Dictionary or cell.size() != 6 or cell.get("id") != CELL_DATA[index].id or not _equal(cell.get("pos"), [position.x, position.y, position.z]): return false
		for key in ["fuel", "heat", "burned", "wet"]:
			if not _number(cell.get(key), 0, 1): return false
		if absf(float(cell.fuel) + float(cell.burned) - float(CELL_DATA[index].fuel)) > 0.000001: return false
		if float(cell.burned) > float(data.clock) * 0.004 * float([1.0, 1.2, 0.8][int(data.variant)]) + 0.000001 or float(cell.wet) > float(data.hit_water) / 56 + 0.000001: return false
	var candidate := OutsideFireCase.new()
	for key in KEYS:
		if key not in ["schema", "origin"]: candidate.set(key, data[key].duplicate(true) if data[key] is Array or data[key] is Dictionary else data[key])
	candidate.origin = _vector(data.origin)
	for index in range(data.hose_points.size()):
		if not _array_point(data.hose_points[index]) or float(data.hose_points[index][1]) != 0: return false
		var point := _vector(data.hose_points[index])
		if index == 0:
			if point.distance_to(candidate.water_source()) > 0.000001: return false
		elif not candidate.safe_approach(point) or point.distance_to(_vector(data.hose_points[index - 1])) < 0.7 or point.distance_to(_vector(data.hose_points[index - 1])) > 7.5: return false
	if candidate.hose_length() > 35 or data.hydrant_connected != (not data.hose_points.is_empty()) or (data.hydrant_connected and not data.recon.exterior): return false
	if (data.recon.exterior or data.recon.surroundings) and not data.basics.exit: return false
	if data.phase != "briefing" and (data.tactic != "defensive" or not data.recon.exterior or not data.recon.surroundings or not data.hydrant_connected): return false
	if data.phase == "briefing" and (data.tactic != "" or data.clock != 0 or data.water_used != 0 or data.unsafe_seconds != 0 or not _equal(data.cells, _initial_cells(candidate.origin)) or data.water_liters != (220 if data.hydrant_connected else 0)): return false
	if data.mode == "none" and not _equal(data, OutsideFireCase.new().to_dict()): return false
	if data.mode == "free" and data.incident_id < 0: return false
	if not _valid_replay(candidate): return false
	if data.phase != "completed" and (data.result != "incomplete" or not data.report_score.is_empty() or data.withdrew): return false
	if data.phase == "completed" and ((not data.withdrew and not candidate.all_cold()) or not _equal(data.report_score, candidate._score()) or data.result != candidate._score().result): return false
	for key in KEYS:
		if key != "schema": set(key, candidate.get(key))
	_operation_count = candidate._operation_count
	return true

static func _initial_cells(site: Vector3) -> Array:
	var initial := OutsideFireCase.new()
	initial.begin(1, 0, site)
	return initial.cells

func _can_record() -> bool:
	return _replaying or (_operation_count < 500000 and simulation.size() < 32768)

func _record_simulation(operation: Array) -> void:
	if _replaying: return
	_operation_count += 1
	var after := actions.size()
	if not simulation.is_empty() and simulation.back().after == after and simulation.back().pattern == [operation]:
		simulation.back().count += 1
		return
	simulation.append({"after": after, "pattern": [operation], "count": 1})
	# The normal physics loop alternates tick/spray. Compact repeated pairs
	# losslessly; varying dt or target remains a distinct operation.
	var size := simulation.size()
	if size >= 3:
		var run: Dictionary = simulation[size - 3]
		var first: Dictionary = simulation[size - 2]
		var second: Dictionary = simulation[size - 1]
		if run.after == after and first.after == after and run.pattern.size() == 2 and first.count == 1 and second.count == 1 and run.pattern == [first.pattern[0], second.pattern[0]]:
			run.count += 1
			simulation.resize(size - 2)
			return
	if size >= 4:
		var run: Dictionary = simulation[size - 4]
		var second: Dictionary = simulation[size - 3]
		var third: Dictionary = simulation[size - 2]
		var fourth: Dictionary = simulation[size - 1]
		if run.after == after and second.after == after and third.after == after and run.count == 1 and second.count == 1 and third.count == 1 and fourth.count == 1 and run.pattern == third.pattern and second.pattern == fourth.pattern:
			run.pattern = [run.pattern[0], second.pattern[0]]
			run.count = 2
			simulation.resize(size - 3)

static func _valid_replay(state: OutsideFireCase) -> bool:
	if not state.actions is Array or state.actions.size() > 16 or not state.simulation is Array or state.simulation.size() > 32768: return false
	var replay := OutsideFireCase.new()
	replay._replaying = true
	if state.mode == "free": replay.begin(state.incident_id, state.variant, state.origin)
	var hose_index := 1
	var row_index := 0
	var operation_count := 0
	for action_index in range(state.actions.size() + 1):
		while row_index < state.simulation.size():
			var row: Variant = state.simulation[row_index]
			if not row is Dictionary or row.size() != 3 or not _integer(row.get("after"), action_index, state.actions.size()) or not _integer(row.get("count"), 1, 500000) or not row.get("pattern") is Array or row.pattern.size() not in [1, 2]: return false
			if int(row.after) != action_index: break
			operation_count += int(row.count) * row.pattern.size()
			if operation_count > 500000: return false
			for operation in row.pattern:
				if not operation is Array or operation.size() != 3 or not operation[0] is String or (not _number(operation[1], 0, 5) or float(operation[1]) <= 0): return false
				if operation[0] == "tick":
					if not operation[2] is bool: return false
				elif operation[0] == "spray":
					if operation[2] not in ["", "center", "left", "right"]: return false
				else: return false
			for repeat in range(int(row.count)):
				for operation in row.pattern:
					var accepted: bool = replay.tick(float(operation[1]), replay.origin if operation[2] else replay.origin + Vector3(0, 0, -4)) if operation[0] == "tick" else replay.spray(str(operation[2]), float(operation[1]))
					if not accepted: return false
			row_index += 1
		if action_index == state.actions.size(): break
		var action: Variant = state.actions[action_index]
		if not action is Dictionary or action.size() != 2 or not action.get("kind") is String or not _number(action.get("time"), 0, state.clock) or not _equal(action.time, replay.clock): return false
		var accepted := false
		if action.kind.begins_with("preparation_"): accepted = replay.complete_step(action.kind.trim_prefix("preparation_"))
		elif action.kind.begins_with("recon_"): accepted = replay.check_recon(action.kind.trim_prefix("recon_"))
		elif action.kind == "water_connected": accepted = replay.connect_water()
		elif action.kind == "tactic_defensive": accepted = replay.choose_tactic("defensive")
		elif action.kind == "hose_laid" and hose_index < state.hose_points.size():
			accepted = replay.add_hose_point(_vector(state.hose_points[hose_index])); hose_index += 1
		elif action.kind in ["handover", "withdraw"]: accepted = not replay.finish(action.kind == "withdraw").is_empty()
		if not accepted: return false
	if row_index != state.simulation.size(): return false
	replay.simulation = state.simulation.duplicate(true)
	if not _equal(replay.to_dict(), state.to_dict()): return false
	state._operation_count = operation_count
	return true

func _log(kind: String) -> void:
	actions.append({"kind": kind, "time": clock})

static func _vector(point: Array) -> Vector3:
	return Vector3(float(point[0]), float(point[1]), float(point[2]))

static func _point(point: Vector3) -> bool:
	return point.is_finite() and absf(point.x) <= 500 and absf(point.z) <= 500

static func _array_point(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for coordinate in value:
		if not _number(coordinate, -500, 500): return false
	return true

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, minimum, maximum) and float(value) == floorf(float(value))

static func _delta(value: float) -> bool:
	return is_finite(value) and value > 0 and value <= 5

static func _equal(actual: Variant, expected: Variant) -> bool:
	if actual is Array and expected is Array:
		if actual.size() != expected.size(): return false
		for index in range(expected.size()):
			if not _equal(actual[index], expected[index]): return false
		return true
	if actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size(): return false
		for key in expected:
			if not actual.has(key) or not _equal(actual[key], expected[key]): return false
		return true
	if expected is int: return _number(actual, -MAX_INCIDENT_ID, MAX_INCIDENT_ID) and float(actual) == float(expected)
	if expected is float: return _number(actual, -1000000, 1000000) and absf(float(actual) - float(expected)) <= maxf(0.000000001, absf(float(expected)) * 0.000000000001)
	return typeof(actual) == typeof(expected) and actual == expected
