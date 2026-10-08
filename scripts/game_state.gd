class_name GameState
extends RefCounted

const SCHEMA := 1
const SAVE_PATH := "user://dienst.json"
var equipment := false
var radio_checked := false
var academy_visits := 0
var player_position := Vector3(0, 0.1, 6)
var sensitivity := 0.003
var save_error := ""

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "equipment": equipment, "radio_checked": radio_checked,
		"academy_visits": academy_visits,
		"position": [player_position.x, player_position.y, player_position.z],
		"sensitivity": sensitivity}

func restore(data: Variant) -> bool:
	if not data is Dictionary or data.get("schema") != SCHEMA:
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
	file.store_string(JSON.stringify(to_dict()))
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
