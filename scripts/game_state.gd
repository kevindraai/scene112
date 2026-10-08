class_name GameState
extends RefCounted

const SCHEMA := 7
const OutsideFire = preload("res://scripts/outside_fire_case.gd")
const PublicOrder = preload("res://scripts/noise_case.gd")
const Investigation = preload("res://scripts/investigation_case.gd")
const Fire = preload("res://scripts/fire_case.gd")
const Police = preload("res://scripts/police_case.gd")
const Ledger = preload("res://scripts/dispatch.gd")
const SAVE_PATH := "user://dienst.json"
var equipment := false
var radio_checked := false
var academy_visits := 0
var player_position := Vector3(0, 0.1, 6)
var sensitivity := 0.003
var save_error := ""
var role := "police"
var occupied_vehicle := ""
var vehicles := {"police_car": {"position": [2.0, 0.05, 9.0], "yaw": PI},
    "fire_truck": {"position": [28.0, 0.05, 5.0], "yaw": PI}}
var dispatch := {}
var police := {}
var police_campaign := {}
var fire := {}
var fire_campaign := {}
var investigation := {}
var research_campaign := {}
var noise := {}
var outside_fire := {}
var police_draft: Array = []
var police_practice := false
var campaign_stage := 0
var course_passes: Array = []
var condition := "day"
var graphics_quality := "portable"

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "equipment": equipment, "radio_checked": radio_checked,
		"academy_visits": academy_visits,
		"position": [player_position.x, player_position.y, player_position.z],
		"sensitivity": sensitivity, "role": role, "occupied_vehicle": occupied_vehicle,
		"vehicles": vehicles.duplicate(true), "dispatch": dispatch.duplicate(true), "police": police.duplicate(true), "police_campaign": police_campaign.duplicate(true),
		"fire": fire.duplicate(true), "fire_campaign": fire_campaign.duplicate(true), "investigation": investigation.duplicate(true), "research_campaign": research_campaign.duplicate(true), "noise": noise.duplicate(true), "outside_fire": outside_fire.duplicate(true),
		"police_draft": police_draft.duplicate(true), "police_practice": police_practice,
		"campaign_stage": campaign_stage, "course_passes": course_passes.duplicate(),
		"condition": condition, "graphics_quality": graphics_quality}

func restore(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var revision: Variant = data.get("schema")
	if not (revision is int or revision is float) or not is_finite(float(revision)) or float(revision) != floorf(float(revision)) or int(revision) not in [1, 2, 3, 4, 5, 6, SCHEMA]:
		return false
	var p: Variant = data.get("position")
	if not p is Array or p.size() != 3:
		return false
	for value in p:
		if not (value is float or value is int) or not is_finite(float(value)) or abs(float(value)) > 500:
			return false
	if not data.get("equipment") is bool or not data.get("radio_checked") is bool:
		return false
	var visits: Variant = data.get("academy_visits")
	if not (visits is int or visits is float) or not is_finite(float(visits)):
		return false
	if float(visits) < 0 or float(visits) > 100000 or float(visits) != floorf(float(visits)):
		return false
	if (data.radio_checked and not data.equipment) or (float(visits) > 0 and not data.radio_checked):
		return false
	var next_role: Variant = data.get("role", "police")
	var seated: Variant = data.get("occupied_vehicle", "")
	if next_role not in ["police", "fire", "research"] or seated not in ["", "police_car", "fire_truck"]:
		return false
	var saved_vehicles: Variant = data.get("vehicles", vehicles.duplicate(true))
	if not saved_vehicles is Dictionary or saved_vehicles.size() != 2:
		return false
	for id in ["police_car", "fire_truck"]:
		var vehicle: Variant = saved_vehicles.get(id)
		if not vehicle is Dictionary or not valid_position(vehicle.get("position")):
			return false
		var yaw: Variant = vehicle.get("yaw")
		if not (yaw is float or yaw is int) or not is_finite(float(yaw)) or absf(float(yaw)) > 10000:
			return false
	var saved_dispatch: Variant = data.get("dispatch", {})
	if not saved_dispatch is Dictionary:
		return false
	if not saved_dispatch.is_empty():
		var ledger := Ledger.new()
		if not ledger.restore(saved_dispatch):
			return false
		var expected_role := "fire" if next_role == "fire" else "police"
		if ledger.role != expected_role:
			# Pre-M5 fire duties shared the police dispatch generator. Preserve
			# clock/history, hand over its live call, then migrate the duty profile.
			if int(revision) >= SCHEMA or saved_dispatch.get("schema") != 1: return false
			ledger.hand_over()
			ledger.role = expected_role
		saved_dispatch = ledger.to_dict()
	var police_save: Variant = data.get("police", {})
	if not police_save is Dictionary:
		return false
	if not police_save.is_empty():
		var scenario := Police.new()
		if not scenario.restore(police_save):
			return false
		police_save = scenario.to_dict()
		if scenario.mode == "free":
			if next_role != "police" or saved_dispatch.is_empty(): return false
			var call: Dictionary = saved_dispatch.incident
			if call.get("kind") != "traffic" or call.get("id") != scenario.incident_id or call.get("variant") != scenario.variant: return false
			if scenario.phase == "completed":
				if call.get("phase") != "resolved" or call.get("quality") != scenario.report_score.score: return false
			elif call.get("phase") != "accepted": return false
	var campaign_save: Variant = data.get("police_campaign", {})
	if not campaign_save is Dictionary:
		return false
	if not campaign_save.is_empty():
		var campaign_case := Police.new()
		if not campaign_case.restore(campaign_save) or campaign_case.mode != "campaign":
			return false
	var fire_save: Variant = data.get("fire", {})
	var fire_archive: Variant = data.get("fire_campaign", {})
	if not fire_save is Dictionary or not fire_archive is Dictionary: return false
	for snapshot: Dictionary in [fire_save, fire_archive]:
		if snapshot.is_empty(): continue
		var incident := Fire.new()
		if not incident.restore(snapshot): return false
	if not fire_archive.is_empty() and fire_archive.mode != "campaign": return false
	if not fire_save.is_empty() and fire_save.mode != "none":
		if fire_save.victim.status == "carried" and seated != "": return false
		if next_role != "fire" or (not police_save.is_empty() and police_save.mode != "none"): return false
	var research_save: Variant = data.get("investigation", {})
	if not research_save is Dictionary: return false
	if not research_save.is_empty():
		var research := Investigation.new()
		if not research.restore(research_save): return false
		if research.mode != "none":
			if next_role != "research" or (not fire_save.is_empty() and fire_save.mode != "none") or (not police_save.is_empty() and police_save.mode != "none"): return false
	var research_archive: Variant = data.get("research_campaign", {})
	if not research_archive is Dictionary: return false
	if not research_archive.is_empty():
		var archive_case := Investigation.new()
		if not archive_case.restore(research_archive) or archive_case.mode != "campaign" or archive_case.phase != "completed": return false
	var noise_save: Variant = data.get("noise", {})
	if not noise_save is Dictionary: return false
	if not noise_save.is_empty():
		var public_order := PublicOrder.new()
		if not public_order.restore(noise_save) or next_role != "police": return false
		var radio_incident := Ledger.new()
		if saved_dispatch.is_empty() or not radio_incident.restore(saved_dispatch): return false
		if radio_incident.incident.get("kind") != "noise" or radio_incident.incident.get("id") != public_order.id or radio_incident.incident.get("variant") != public_order.variant: return false
		if public_order.phase == "active" and radio_incident.incident.phase != "accepted": return false
		if public_order.phase == "completed" and (radio_incident.incident.phase != "resolved" or radio_incident.incident.quality != public_order.report.total): return false

		if (not police_save.is_empty() and police_save.mode != "none") or (not fire_save.is_empty() and fire_save.mode != "none") or (not research_save.is_empty() and research_save.mode != "none"): return false
	var outside_save: Variant = data.get("outside_fire", {})
	if not outside_save is Dictionary: return false
	if not outside_save.is_empty():
		var outside := OutsideFire.new()
		if not outside.restore(outside_save) or outside.mode != "free" or next_role != "fire" or saved_dispatch.is_empty(): return false
		var call: Dictionary = saved_dispatch.incident
		if call.get("kind") != "fire" or call.get("id") != outside.incident_id or call.get("variant") != outside.variant: return false
		if not valid_position(call.get("position")) or not outside.origin.is_equal_approx(Vector3(call.position[0], call.position[1], call.position[2])): return false
		if outside.phase == "completed":
			if call.get("phase") != "resolved" or call.get("quality") != outside.report_score.total: return false
		elif call.get("phase") != "accepted": return false
		if not noise_save.is_empty() or (not police_save.is_empty() and police_save.mode != "none") or (not fire_save.is_empty() and fire_save.mode != "none") or (not research_save.is_empty() and research_save.mode != "none"): return false
	if not saved_dispatch.is_empty() and saved_dispatch.incident.get("phase") == "accepted":
		var has_free_case: bool = not noise_save.is_empty() or not outside_save.is_empty() or police_save.get("mode") == "free"
		if not has_free_case:
			# Older duties used a one-click assessment. Hand its pending call
			# over without inventing evidence, keeping the duty and archive.
			if int(revision) >= SCHEMA: return false
			var legacy_duty := Ledger.new()
			if not legacy_duty.restore(saved_dispatch) or not legacy_duty.hand_over(): return false
			saved_dispatch = legacy_duty.to_dict()
	var draft: Variant = data.get("police_draft", [])
	if not draft is Array or draft.size() > 32:
		return false
	var available := {}
	if not police_save.is_empty():
		var draft_case := Police.new()
		draft_case.restore(police_save)
		for card in draft_case.report_cards(): available[card.id] = true
	var used := {}
	for row in draft:
		if not row is Dictionary or row.size() != 3 or not row.get("included") is bool:
			return false
		if not available.has(row.get("id")) or used.has(row.get("id")) or row.get("category") not in ["", "observation", "declaration", "action", "conclusion"]:
			return false
		used[row.id] = true
	var practice: Variant = data.get("police_practice", false)
	if not practice is bool:
		return false
	var stage: Variant = data.get("campaign_stage", 0)
	if not (stage is int or stage is float) or not is_finite(float(stage)) or float(stage) != floorf(float(stage)) or float(stage) < 0 or float(stage) > 3:
		return false
	var courses: Variant = data.get("course_passes", [])
	if not courses is Array or courses.size() > 3:
		return false
	var unique := {}
	for course in courses:
		if course not in ["basis", "intake", "fire"] or unique.has(course):
			return false
		unique[course] = true
	var saved_condition: Variant = data.get("condition", "day")
	var saved_quality: Variant = data.get("graphics_quality", "portable")
	if saved_condition not in ["day", "dusk", "rain"] or saved_quality not in ["portable", "balanced", "high"]:
		return false
	outside_fire = outside_save.duplicate(true)
	noise = noise_save.duplicate(true)
	research_campaign = research_archive.duplicate(true)
	investigation = research_save.duplicate(true)
	fire = fire_save.duplicate(true)
	fire_campaign = fire_archive.duplicate(true)
	police = police_save.duplicate(true)
	police_campaign = campaign_save.duplicate(true)
	police_draft = draft.duplicate(true)
	police_practice = practice
	campaign_stage = int(stage)
	course_passes = courses.duplicate()
	condition = saved_condition
	graphics_quality = saved_quality
	role = next_role
	occupied_vehicle = seated
	vehicles = saved_vehicles.duplicate(true)
	dispatch = saved_dispatch.duplicate(true)
	equipment = data.equipment
	radio_checked = data.radio_checked
	academy_visits = int(visits)
	player_position = Vector3(float(p[0]), clampf(float(p[1]), 0.1, 20.0), float(p[2]))
	var candidate: Variant = data.get("sensitivity", 0.003)
	if candidate is float or candidate is int:
		sensitivity = clampf(float(candidate), 0.001, 0.008) if is_finite(float(candidate)) else 0.003
	return true

func save_to(path: String = SAVE_PATH) -> bool:
	save_error = ""
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		save_error = "Opslaan mislukt: " + error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(to_dict(), "", true, true))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		save_error = "Opslaan mislukt: " + error_string(write_error)
		return false
	# Windows rename may delete the destination first. Keep the last validated
	# slot as recovery before replacing it; a corrupt primary must not replace it.
	var previous := GameState.new()
	if previous._load_file(path):
		var backup_error := DirAccess.copy_absolute(path, path + ".bak")
		if backup_error != OK:
			save_error = "Vorige opslag kon niet veilig worden bewaard."
			return false
	var result := DirAccess.rename_absolute(path + ".tmp", path)
	if result != OK:
		save_error = "Opslaan mislukt: " + error_string(result)
	return result == OK

func load_from(path: String = SAVE_PATH) -> bool:
	return _load_file(path) or _load_file(path + ".bak")

func _load_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return false
	return restore(parser.data)

static func valid_position(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for coordinate in value:
		if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)) or absf(float(coordinate)) > 500:
			return false
	return true
