class_name FireCase
extends RefCounted
## Bounded fictional team exercise; no operational training or CFD claim.

const SCHEMA := 1
const MODES := ["none", "campaign", "lesson", "free"]
const SITE := Vector3(-2, 0, 48)
const HYDRANT := Vector3(7, 0, 44)
const SAFE_AREA := Vector3(8, 0, 40)
const BASICS := ["equipment", "radio", "enter", "drive", "exit"]
const CELL_DATA := [
	{"id": "front", "pos": [0.0, 0.55, -1.6], "fuel": 0.8, "heat": 0.62},
	{"id": "origin", "pos": [-1.8, 0.55, 1.8], "fuel": 1.0, "heat": 0.82},
	{"id": "side", "pos": [1.8, 0.55, 1.7], "fuel": 0.9, "heat": 0.18}]
const SNAPSHOT_KEYS := ["schema", "mode", "phase", "clock", "basics", "recon", "tactic", "hydrant_connected", "hose_points", "water_liters", "water_used", "cells", "victim", "oxygen", "unsafe_seconds", "actions", "report_score", "result"]
var mode := "none"
var phase := "briefing"
var clock := 0.0
var basics: Dictionary = {}
var recon := {"exterior": false, "door": false}
var tactic := ""
var hydrant_connected := false
var hose_points: Array = []
var water_liters := 0.0
var water_used := 0.0
var cells: Array = []
var victim := {"status": "waiting", "exposure": 0.0}
var oxygen := 100.0
var unsafe_seconds := 0.0
var actions: Array = []
var report_score: Dictionary = {}
var result := "incomplete"

func _init() -> void:
	begin("none")

func begin(next_mode: String) -> bool:
	if next_mode not in MODES: return false
	mode = next_mode
	phase = "briefing"
	clock = 0.0
	basics = {"equipment": false, "radio": false, "enter": false, "drive": false, "exit": false}
	recon = {"exterior": false, "door": false}
	tactic = ""
	hydrant_connected = false
	hose_points = []
	water_liters = 0.0
	water_used = 0.0
	cells = []
	for item in CELL_DATA:
		var cell: Dictionary = item.duplicate(true)
		cell.burned = 0.0
		cell.wet = 0.0
		cells.append(cell)
	victim = {"status": "waiting", "exposure": 0.0}
	oxygen = 100.0
	unsafe_seconds = 0.0
	actions = []
	report_score = {}
	result = "incomplete"
	return true

func complete_step(id: String) -> bool:
	if mode == "none" or phase == "completed" or id not in BASICS or basics[id]: return false
	for step in BASICS:
		if not basics[step]:
			if step != id: return false
			basics[id] = true
			_log("preparation_" + id)
			return true
	return false

func check_recon(id: String) -> bool:
	if not basics.exit or phase == "completed" or not recon.has(id) or recon[id]: return false
	recon[id] = true
	_log("recon_" + id)
	return true

func connect_water() -> bool:
	if not basics.exit or not recon.exterior or phase == "completed" or hydrant_connected: return false
	hydrant_connected = true
	water_liters = 220.0
	hose_points = [[HYDRANT.x, HYDRANT.y, HYDRANT.z]]
	_log("water_connected")
	return true

func choose_tactic(value: String) -> bool:
	if phase != "briefing" or not recon.exterior or not recon.door or not hydrant_connected or value not in ["defensive", "interior"]: return false
	tactic = value
	phase = "active"
	_log("tactic_" + value)
	return true

func add_hose_point(point: Vector3) -> bool:
	if not hydrant_connected or phase == "completed" or hose_points.size() >= 8 or not _finite_vector(point) or absf(point.y) > 0.5: return false
	var last := _vector(hose_points.back())
	if point.distance_to(last) > 7.5 or point.distance_to(last) < 0.7: return false
	if hose_length() + point.distance_to(last) > 35.0: return false
	hose_points.append([point.x, 0.04, point.z])
	_log("hose_laid")
	return true

func hose_length() -> float:
	var length := 0.0
	for index in range(1, hose_points.size()): length += _vector(hose_points[index]).distance_to(_vector(hose_points[index - 1]))
	return length

func has_nozzle_at(point: Vector3) -> bool:
	return hydrant_connected and hose_points.size() >= 2 and _finite_vector(point) and _vector(hose_points.back()).distance_to(point) <= 5.5

func spray(cell_id: String, delta: float) -> bool:
	if phase != "active" or not _delta_valid(delta) or hose_points.size() < 2 or water_liters < delta * 14.0: return false
	var matched := cell_id.is_empty()
	for cell in cells: matched = matched or cell.id == cell_id
	if not matched: return false
	# Opening a connected nozzle consumes water even when the actual ray misses.
	water_liters -= delta * 14.0
	water_used += delta * 14.0
	for cell in cells:
		if cell.id != cell_id: continue
		cell.heat = maxf(0, float(cell.heat) - delta * 0.27)
		cell.wet = minf(1, float(cell.wet) + delta * 0.25)
		return true
	return true

func tick(delta: float, inside: bool = false) -> bool:
	if phase != "active" or not _delta_valid(delta) or clock + delta > 100000: return false
	clock += delta
	water_liters = minf(320, water_liters + delta * 6.0) if hydrant_connected else water_liters
	var previous: Array = cells.duplicate(true)
	for index in range(cells.size()):
		var cell: Dictionary = cells[index]
		var hot := float(cell.heat)
		var remaining := float(cell.fuel)
		var wet := float(cell.wet)
		var spread := 0.0
		for other in previous:
			if other.id != cell.id and float(other.heat) > 0.65: spread += 0.006
		if remaining > 0.01 and hot > 0.05:
			cell.heat = clampf(hot + delta * (0.010 + spread - wet * 0.030), 0, 1)
			var consumed := minf(remaining, delta * hot * 0.0018)
			cell.fuel = remaining - consumed
			cell.burned = minf(float(CELL_DATA[index].fuel), float(cell.burned) + consumed)
		elif remaining > 0.01 and wet < 0.4 and spread > 0:
			cell.heat = minf(1, hot + delta * spread)
		else: cell.heat = maxf(0, hot - delta * 0.025)
		cell.wet = maxf(0, wet - delta * 0.001)
	if victim.status == "waiting":
		victim.exposure = minf(100, float(victim.exposure) + delta * average_heat() * 0.22)
		if float(victim.exposure) >= 100:
			victim.status = "lost"
			_log("victim_lost")
	if inside:
		oxygen = maxf(0, oxygen - delta * 0.35)
		if not can_enter(): unsafe_seconds += delta
	if oxygen < 15 and victim.status == "carried": unsafe_seconds += delta
	return true

func average_heat() -> float:
	var total := 0.0
	for cell in cells: total += float(cell.heat)
	return total / maxf(1, cells.size())

func can_enter() -> bool:
	if phase != "active" or tactic not in ["defensive", "interior"] or not hydrant_connected or hose_points.size() < 2 or oxygen <= 15: return false
	# Distinct fictional crew plans: defensive cooling delays the protected
	# search until the room is cooler; interior prioritises earlier rescue.
	var room_limit := 0.40 if tactic == "defensive" else 0.62
	var entry_limit := 0.28 if tactic == "defensive" else 0.58
	return average_heat() < room_limit and float(cells[0].heat) < entry_limit

func pickup_victim() -> bool:
	if victim.status != "waiting" or not can_enter(): return false
	victim.status = "carried"
	_log("victim_carried")
	return true

func rescue_victim() -> bool:
	if phase != "active" or victim.status != "carried": return false
	victim.status = "rescued"
	_log("victim_rescued")
	return true

func all_cold() -> bool:
	for cell in cells:
		if float(cell.heat) > 0.06: return false
	return true

func finish(withdraw: bool = false) -> Dictionary:
	if phase == "completed": return report_score.duplicate(true)
	if phase != "active" or victim.status == "carried" or (not withdraw and (not all_cold() or victim.status == "waiting")): return {}
	result = "partial" if withdraw or victim.status != "rescued" else "careful"
	_log("withdraw" if withdraw else "handover")
	phase = "completed"
	report_score = _score()
	result = report_score.result
	return report_score.duplicate(true)

func _score() -> Dictionary:
	var safety := maxi(0, 35 - int(unsafe_seconds * 3))
	var rescue := 35 if victim.status == "rescued" else 0
	var consumed := 0.0
	var capacity := 0.0
	for index in cells.size():
		consumed += float(cells[index].burned)
		capacity += float(CELL_DATA[index].fuel)
	var damage := clampf(consumed / capacity, 0, 1)
	# Cold after burning out is not successful suppression. Preserve that
	# partial incident for investigation, while rewarding damage limitation.
	var suppression := roundi(20 * (1 - average_heat()) * (1 - damage))
	var conservation := 10 if water_used < 600 else 5
	var grade := safety + rescue + suppression + conservation
	var careful: bool = grade >= 80 and victim.status == "rescued" and all_cold() and unsafe_seconds < 3 and damage <= 0.35
	return {"total": grade, "safety": safety, "rescue": rescue, "suppression": suppression, "conservation": conservation, "result": "careful" if careful else "partial", "victim": victim.status, "clock": clock, "water_used": water_used, "unsafe_seconds": unsafe_seconds}

func objective() -> String:
	if mode == "none": return "Kies de woningbrand of de brandweerles."
	if phase == "completed": return "Inzet overgedragen. Incidentstaat en inzetgegevens zijn bewaard voor brandonderzoek."
	for id in BASICS:
		if not basics[id]: return {"equipment": "Controleer PBM en ademlucht bij de kazerne.", "radio": "Meld je bij de kazerneradio.", "enter": "Stap in de tankautospuit.", "drive": "Rijd naar Huis 24 aan de Noorderkade.", "exit": "Parkeer veilig en stap uit."}[id]
	if not recon.exterior: return "Verken de buitenzijde: rook, slachtofferlocatie en vrije vluchtweg."
	if not recon.door: return "Beoordeel de toegang. Binnen is het nog te heet; koel eerst gericht."
	if not hydrant_connected: return "Sluit de waterwinning bij de hydrant aan."
	if tactic.is_empty(): return "Kies een inzetplan op basis van je verkenning."
	if hose_points.size() < 2: return "Leg de slang met Q in korte segmenten richting de toegang (maximaal 35 m)."
	if victim.status == "carried": return "Breng het slachtoffer naar de opvangplaats buiten."
	if victim.status == "waiting": return "Richt de straal met de muis en houd links ingedrukt. Maak de toegang veilig; red daarna het slachtoffer."
	if not all_cold(): return "Blus afzonderlijke haarden gericht; bewaak ademlucht en water."
	return "Controleer de nasmeulende ruimte en draag de inzet over."

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "mode": mode, "phase": phase, "clock": clock, "basics": basics.duplicate(true), "recon": recon.duplicate(true), "tactic": tactic, "hydrant_connected": hydrant_connected, "hose_points": hose_points.duplicate(true), "water_liters": water_liters, "water_used": water_used, "cells": cells.duplicate(true), "victim": victim.duplicate(true), "oxygen": oxygen, "unsafe_seconds": unsafe_seconds, "actions": actions.duplicate(true), "report_score": report_score.duplicate(true), "result": result}

func restore(data: Variant) -> bool:
	if not data is Dictionary or data.size() != SNAPSHOT_KEYS.size(): return false
	for key in SNAPSHOT_KEYS:
		if not data.has(key): return false
	if data.schema != SCHEMA or data.mode not in MODES or data.phase not in ["briefing", "active", "completed"] or data.tactic not in ["", "defensive", "interior"] or not data.hydrant_connected is bool: return false
	for pair in [["clock", 100000], ["water_liters", 320], ["water_used", 1500000], ["oxygen", 100], ["unsafe_seconds", 100000]]:
		if not _number(data[pair[0]], 0, pair[1]): return false
	if not data.basics is Dictionary or data.basics.size() != 5 or not data.recon is Dictionary or data.recon.size() != 2: return false
	var missing := false
	for id in BASICS:
		if not data.basics.get(id) is bool: return false
		if not data.basics[id]: missing = true
		elif missing: return false
	for id in ["exterior", "door"]:
		if not data.recon.get(id) is bool: return false
	if not data.cells is Array or data.cells.size() != 3: return false
	for index in range(3):
		var item: Variant = data.cells[index]
		if not item is Dictionary or item.size() != 6 or item.get("id") != CELL_DATA[index].id or item.get("pos") != CELL_DATA[index].pos: return false
		for key in ["fuel", "heat", "burned", "wet"]:
			if not _number(item.get(key), 0, 1): return false
		if absf(float(item.fuel) + float(item.burned) - float(CELL_DATA[index].fuel)) > 0.0001: return false
	if not data.victim is Dictionary or data.victim.size() != 2 or data.victim.get("status") not in ["waiting", "carried", "rescued", "lost"] or not _number(data.victim.get("exposure"), 0, 100): return false
	if data.victim.status == "lost" and float(data.victim.exposure) < 100: return false
	if not data.hose_points is Array or data.hose_points.size() > 8 or not data.actions is Array or data.actions.size() > 64 or not data.report_score is Dictionary: return false
	var line_length := 0.0
	for index in range(data.hose_points.size()):
		var point: Variant = data.hose_points[index]
		if not point is Array or point.size() != 3: return false
		for coordinate in point:
			if not _number(coordinate, -500, 500): return false
		if absf(float(point[1])) > 0.5: return false
		if index == 0 and _vector(point).distance_to(HYDRANT) > 0.01: return false
		if index > 0:
			var segment := _vector(point).distance_to(_vector(data.hose_points[index - 1]))
			if segment > 7.5 or segment < 0.7: return false
			line_length += segment
	if line_length > 35: return false
	var last_time := 0.0
	for action in data.actions:
		if not action is Dictionary or action.size() != 2 or not action.get("kind") is String or not _number(action.get("time"), last_time, data.clock): return false
		last_time = float(action.time)
	if (data.recon.exterior or data.recon.door) and not data.basics.exit: return false
	if data.hydrant_connected != (not data.hose_points.is_empty()) or (data.hydrant_connected and not data.recon.exterior): return false
	if data.phase != "briefing" and (data.tactic.is_empty() or not data.recon.door or not data.recon.exterior or not data.hydrant_connected): return false
	if data.phase == "briefing" and (not data.tactic.is_empty() or float(data.clock) != 0 or data.victim.status != "waiting"): return false
	if data.victim.status in ["carried", "rescued"] and (data.phase == "briefing" or data.hose_points.size() < 2): return false
	if data.result not in ["incomplete", "careful", "partial"]: return false
	if data.phase == "completed" and data.victim.status == "carried": return false
	if data.phase != "completed" and (data.result != "incomplete" or not data.report_score.is_empty()): return false
	var candidate := FireCase.new()
	for key in SNAPSHOT_KEYS:
		if key != "schema": candidate.set(key, data[key].duplicate(true) if data[key] is Array or data[key] is Dictionary else data[key])
	if data.phase == "completed" and (not _scores_equal(data.report_score, candidate._score()) or data.result != candidate._score().result): return false
	for key in SNAPSHOT_KEYS:
		if key != "schema": set(key, candidate.get(key))
	return true

func _log(kind: String) -> void:
	if actions.size() < 64: actions.append({"kind": kind, "time": clock})

static func _vector(point: Array) -> Vector3:
	return Vector3(float(point[0]), float(point[1]), float(point[2]))

static func _finite_vector(point: Vector3) -> bool:
	return is_finite(point.x) and is_finite(point.y) and is_finite(point.z) and absf(point.x) < 500 and absf(point.z) < 500

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _delta_valid(delta: float) -> bool:
	return is_finite(delta) and delta > 0 and delta <= 5.0


static func _scores_equal(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size(): return false
	for key: String in expected:
		if not actual.has(key): return false
		var value: Variant = expected[key]
		if value is String:
			if not actual[key] is String or actual[key] != value: return false
		else:
			if not (actual[key] is int or actual[key] is float) or not is_finite(float(actual[key])): return false
			if value is int:
				if float(actual[key]) != float(value): return false
			elif absf(float(actual[key]) - float(value)) > maxf(0.000000001, absf(float(value)) * 0.000000000001): return false
	return true
