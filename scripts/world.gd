class_name District
extends Node3D
## Original procedural Dutch district. All meshes and materials are made at runtime.

signal interacted(id: String)

var objects: Dictionary = {}
var _titles: Dictionary = {}
var _materials: Dictionary = {}

const NAVY := Color("193655")
const BLUE := Color("2885a8")
const BRICK := Color("a46450")
const CREAM := Color("e9d9bb")
const RED := Color("bd413e")
const GLASS := Color("81b5c2")
const GRASS := Color("5d8770")
const ASPHALT := Color("3a4650")
const PAVING := Color("c5beb0")


func _ready() -> void:
	name = "District"
	_lighting()
	_streets()
	_police_station()
	_fire_station()
	_houses()
	_square()
	_industry()
	_street_details()
	_vehicle("police_car", "Dienstauto · politie", Vector3(2, 0, 9), false)
	_vehicle("fire_truck", "Tankautospuit · brandweer", Vector3(29, 0, 5), true)


func get_interaction(at: Vector3) -> Dictionary:
	var nearest := 3.0
	var result: Dictionary = {}
	for id: String in objects:
		var object: Node3D = objects[id]
		var distance := Vector2(at.x, at.z).distance_to(Vector2(object.global_position.x, object.global_position.z))
		if distance < nearest:
			nearest = distance
			result = {"id": id, "title": _titles[id], "position": object.global_position}
	return result


func interact(id: String) -> void:
	if objects.has(id):
		interacted.emit(id)


func _lighting() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("739db8")
	sky_material.sky_horizon_color = Color("dce7e4")
	sky_material.ground_bottom_color = Color("5f7371")
	sky_material.ground_horizon_color = Color("dce7e4")
	sky.sky_material = sky_material
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c1d4de")
	settings.ambient_light_energy = 0.35
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.fog_enabled = true
	settings.fog_light_color = Color("beced0")
	settings.fog_density = 0.0025
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "AfternoonSun"
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_color = Color("ffebcd")
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90
	add_child(sun)


func _streets() -> void:
	_box("Ground", Vector3(0, -0.2, 0), Vector3(144, 0.4, 144), GRASS)
	_box("Hoofdstraat", Vector3(0, 0.004, 17), Vector3(140, 0.012, 10), ASPHALT, false)
	_box("Stationslaan", Vector3(-20, 0.007, 0), Vector3(9, 0.012, 140), ASPHALT, false)
	_box("Industrieweg", Vector3(14, 0.004, -28), Vector3(68, 0.012, 8), ASPHALT, false)
	_box("NorthSidewalk", Vector3(0, 0.014, 10.7), Vector3(138, 0.025, 2.5), PAVING, false)
	_box("SouthSidewalk", Vector3(0, 0.014, 23.3), Vector3(138, 0.025, 2.5), PAVING, false)
	_box("BureauForecourt", Vector3(0, 0.012, 3), Vector3(23, 0.023, 14), PAVING, false)
	_box("KazerneForecourt", Vector3(29, 0.012, 1), Vector3(21, 0.023, 16), PAVING, false)
	_box("WestFootpath", Vector3(-26.3, 0.014, 0), Vector3(2.5, 0.025, 136), PAVING, false)
	_box("EastFootpath", Vector3(-13.7, 0.014, 0), Vector3(2.5, 0.025, 136), PAVING, false)
	for x in range(-64, 68, 8):
		if x < -25 or x > -15:
			_box("LaneMark", Vector3(x, 0.025, 17), Vector3(3.7, 0.006, 0.12), CREAM, false)
	for z in range(-64, 68, 8):
		if z < 11 or z > 23:
			_box("LaneMark", Vector3(-20, 0.027, z), Vector3(0.12, 0.006, 3.7), CREAM, false)
	for i in range(7):
		_box("Zebra", Vector3(-7.0 + i * 0.9, 0.029, 17), Vector3(0.48, 0.007, 8.4), CREAM, false)
	for i in range(3):
		_box("ParkingLine", Vector3(-3 + i * 4, 0.029, 7.6), Vector3(0.08, 0.007, 4.7), CREAM, false)
	# Low perimeter hedges bound the compact map without invisible collisions.
	for x in [-70.0, 70.0]:
		_box("BoundaryHedge", Vector3(x, 0.7, 0), Vector3(1.4, 1.4, 140), Color("46674e"))
	for z in [-70.0, 70.0]:
		_box("BoundaryHedge", Vector3(0, 0.7, z), Vector3(140, 1.4, 1.4), Color("46674e"))


func _police_station() -> void:
	_box("BureauRear", Vector3(0, 2.4, -9), Vector3(19, 4.8, 0.4), BRICK)
	_box("BureauWest", Vector3(-9.3, 2.4, -4.5), Vector3(0.4, 4.8, 9), BRICK)
	_box("BureauEast", Vector3(9.3, 2.4, -4.5), Vector3(0.4, 4.8, 9), BRICK)
	_box("BureauFrontLeft", Vector3(-5.8, 2.4, 0), Vector3(7, 4.8, 0.4), BRICK)
	_box("BureauFrontRight", Vector3(5.8, 2.4, 0), Vector3(7, 4.8, 0.4), BRICK)
	_box("BureauLintel", Vector3(0, 3.85, 0), Vector3(4.6, 1.9, 0.4), NAVY)
	_box("BureauRoof", Vector3(0, 4.9, -4.5), Vector3(19.5, 0.3, 9.5), Color("596672"))
	_box("BureauFloor", Vector3(0, 0.018, -4.5), Vector3(18, 0.025, 8.5), Color("d3d3c9"), false)
	_sign("SCÈNE 112  /  BUREAU", Vector3(0, 4.0, 0.24), 0.12, CREAM)
	_sign("NOORDERKADE", Vector3(0, 3.3, 0.25), 0.07, CREAM)
	for x in [-6.4, -4.2, 4.2, 6.4]:
		_box("BureauWindow", Vector3(x, 2.45, 0.23), Vector3(1.65, 1.7, 0.05), GLASS, false)
		_box("WindowFrame", Vector3(x, 2.45, 0.265), Vector3(0.055, 1.7, 0.04), CREAM, false)
		_box("WindowFrame", Vector3(x, 2.45, 0.265), Vector3(1.65, 0.055, 0.04), CREAM, false)
	_box("ReceptionDesk", Vector3(5.1, 0.6, -3.9), Vector3(3.0, 1.2, 1.0), NAVY)
	_box("DeskTop", Vector3(5.1, 1.22, -3.9), Vector3(3.15, 0.1, 1.1), CREAM, false)
	var radio := _station("radio", "Meldkamer · radio", Vector3(4.1, 0, -2.8))
	_box("Radio", Vector3(0, 1.37, -0.9), Vector3(0.55, 0.23, 0.4), Color("252f37"), false, radio)
	_box("RadioScreen", Vector3(0, 1.38, -0.69), Vector3(0.33, 0.09, 0.02), Color("75d1b5"), false, radio)
	_box("Antenna", Vector3(0.2, 1.75, -0.9), Vector3(0.025, 0.6, 0.025), NAVY, false, radio)
	var equipment := _station("equipment", "Uitrusting · dienst starten", Vector3(-5.4, 0, -3))
	for x in [-1.05, 0.0, 1.05]:
		_box("Locker", Vector3(x, 1.05, -0.45), Vector3(0.92, 2.1, 0.7), BLUE, true, equipment)
		_box("LockerVent", Vector3(x, 1.65, -0.088), Vector3(0.55, 0.18, 0.02), NAVY, false, equipment)
		_box("LockerHandle", Vector3(x + 0.26, 1.0, -0.07), Vector3(0.055, 0.2, 0.05), CREAM, false, equipment)
	_sign("UITRUSTING", Vector3(-5.4, 2.6, -2.55), 0.09, NAVY)
	var board := _station("board", "Briefing · onderzoeksbord", Vector3(0, 0, -7.35))
	_box("BriefingBoard", Vector3(0, 1.7, -0.6), Vector3(4.8, 2.25, 0.18), NAVY, true, board)
	_sign("DIENSTBRIEFING  /  NOORDERKADE", Vector3(0, 2.5, -7.84), 0.073, CREAM)
	for i in range(3):
		_box("BriefingPaper", Vector3(-1.5 + i * 1.5, 1.5, -0.495), Vector3(0.9, 0.95, 0.03), CREAM, false, board)
	var academy := _station("academy", "Academie · oefenen", Vector3(-5.5, 0, 2.1))
	_box("AcademyStand", Vector3(0, 0.6, 0), Vector3(0.18, 1.2, 0.18), NAVY, true, academy)
	_box("AcademyPanel", Vector3(0, 1.45, 0), Vector3(2.6, 1.1, 0.18), NAVY, true, academy)
	_sign("ACADEMIE", Vector3(-5.5, 1.66, 2.22), 0.11, CREAM)
	_sign("Leren door te doen", Vector3(-5.5, 1.22, 2.22), 0.055, Color("acd5dc"))
	_sign("Welkom bij je eerste dienst", Vector3(0, 2.4, -3.6), 0.065, NAVY)


func _fire_station() -> void:
	_box("KazerneRear", Vector3(29, 2.8, -11.5), Vector3(20, 5.6, 0.4), BRICK)
	for x in [19.0, 39.0]:
		_box("KazerneSide", Vector3(x, 2.8, -6.4), Vector3(0.4, 5.6, 10.2), BRICK)
	_box("KazerneFront", Vector3(29, 4.95, -1.5), Vector3(20.4, 1.3, 0.4), RED)
	for x in [19.0, 26.0, 33.0, 39.0]:
		_box("GarageColumn", Vector3(x, 2.15, -1.5), Vector3(0.45, 4.3, 0.45), CREAM)
	_box("KazerneRoof", Vector3(29, 5.8, -6.4), Vector3(21, 0.3, 11), Color("596672"))
	_box("GarageFloor", Vector3(29, 0.018, -6.4), Vector3(19.5, 0.025, 10), Color("a3abb0"), false)
	_sign("BRANDWEER  /  NOORDERKADE", Vector3(29, 5.05, -1.25), 0.13, CREAM)
	_sign("Veilig uit. Samen thuis.", Vector3(29, 3.2, -11.25), 0.09, CREAM)
	for x in [22.0, 36.0]:
		_box("KitCabinet", Vector3(x, 1.0, -9), Vector3(2.1, 2.0, 0.7), RED)
		for y in [0.8, 1.35]:
			_box("KitStripe", Vector3(x, y, -8.63), Vector3(1.7, 0.09, 0.04), Color("e6d26c"), false)
	_box("TrainingApron", Vector3(46, 0.014, -3), Vector3(10, 0.025, 20), PAVING, false)
	for z in [-9.0, -3.0, 3.0]:
		_cone(Vector3(44, 0, z))
		_cone(Vector3(48, 0, z))
	_tree(Vector3(43, 0, 10))


func _houses() -> void:
	var palettes := [BRICK, Color("b67957"), Color("96726a"), Color("ccaa84")]
	for i in range(6):
		_house(Vector3(-39, 0, -44 + i * 8), palettes[i % palettes.size()], true, i + 12)
	for i in range(5):
		_house(Vector3(-2 + i * 8, 0, 48), palettes[(i + 1) % palettes.size()], false, i + 24)
	_box("HousingPath", Vector3(-31, 0.014, -24), Vector3(3, 0.025, 53), PAVING, false)
	_box("SouthHousingPath", Vector3(14, 0.014, 41.5), Vector3(44, 0.025, 2.5), PAVING, false)


func _house(at: Vector3, color: Color, side: bool, number: int) -> void:
	var house := Node3D.new()
	house.name = "Woning%d" % number
	house.position = at
	if side:
		house.rotation.y = -PI / 2.0
	add_child(house)
	_box("House", Vector3(0, 2.7, 0), Vector3(6.8, 5.4, 7), color, true, house)
	_box("Roof", Vector3(0, 5.5, 0), Vector3(7.2, 0.35, 7.5), Color("52616b"), false, house)
	_box("Chimney", Vector3(2, 6.0, -1.8), Vector3(0.7, 1.2, 0.7), color, false, house)
	for x in [-1.7, 1.7]:
		for y in [1.8, 4.05]:
			_box("WindowFrame", Vector3(x, y, -3.54), Vector3(1.7, 1.5, 0.09), CREAM, false, house)
			_box("Window", Vector3(x, y, -3.6), Vector3(1.5, 1.3, 0.045), GLASS, false, house)
			_box("WindowMullion", Vector3(x, y, -3.64), Vector3(0.055, 1.3, 0.035), CREAM, false, house)
	_box("Door", Vector3(0, 1.0, -3.56), Vector3(0.85, 2.0, 0.07), NAVY, false, house)
	_box("DoorHandle", Vector3(0.28, 1.0, -3.62), Vector3(0.06, 0.11, 0.045), CREAM, false, house)
	_box("FrontGarden", Vector3(0, 0.01, -5.0), Vector3(6.4, 0.018, 2.2), Color("719076"), false, house)
	_box("DoorPath", Vector3(0, 0.025, -4.8), Vector3(1.1, 0.018, 2.6), PAVING, false, house)
	var label := Label3D.new()
	label.text = str(number)
	label.position = Vector3(0.74, 1.72, -3.62)
	label.rotation.y = PI
	label.font_size = 38
	label.pixel_size = 0.003
	label.modulate = CREAM
	house.add_child(label)


func _square() -> void:
	_box("Noordplein", Vector3(8, 0.015, 31), Vector3(28, 0.025, 12), Color("b6aa94"), false)
	for x in [-4.0, 2.0, 8.0, 14.0, 20.0]:
		_box("PlazaPaving", Vector3(x, 0.035, 31), Vector3(0.05, 0.005, 11.5), Color("ded0b7"), false)
	for z in [26.0, 31.0, 36.0]:
		_box("PlazaPaving", Vector3(8, 0.035, z), Vector3(27.5, 0.005, 0.05), Color("ded0b7"), false)
	for at in [Vector3(-3, 0, 28), Vector3(19, 0, 28), Vector3(-3, 0, 35), Vector3(19, 0, 35)]:
		_tree(at)
		_box("TreePlanter", at + Vector3(0, 0.28, 0), Vector3(2, 0.56, 2), Color("9a9588"))
	_bench(Vector3(4, 0, 35))
	_bench(Vector3(13, 0, 35))
	_cylinder("FountainBase", Vector3(8, 0.32, 30), 1.6, 0.64, Color("ddd4c5"), true)
	_cylinder("FountainWater", Vector3(8, 0.65, 30), 1.38, 0.06, Color("67b4c1"), false)
	_cylinder("FountainColumn", Vector3(8, 1.15, 30), 0.27, 1.0, Color("d7ccbc"), true)
	_box("Bakery", Vector3(46, 2.0, 31), Vector3(13, 4, 9), Color("cead83"))
	_box("ShopWindow", Vector3(46, 1.8, 26.46), Vector3(9, 2.2, 0.06), GLASS, false)
	_box("ShopAwning", Vector3(46, 3.5, 25.85), Vector3(12, 0.18, 2), Color("44777a"), false)
	var bakery_sign := _sign("BAKKERIJ  /  DE KADE", Vector3(46, 3.1, 26.38), 0.10, CREAM)
	bakery_sign.rotation.y = PI
	_tree(Vector3(36, 0, 32))
	_tree(Vector3(56, 0, 32))


func _industry() -> void:
	_box("Warehouse", Vector3(24, 3.8, -44), Vector3(24, 7.6, 16), Color("81969a"))
	_box("WarehouseRoof", Vector3(24, 7.7, -44), Vector3(25, 0.3, 17), NAVY, false)
	_box("LoadingDoor", Vector3(23, 2.3, -35.95), Vector3(7, 4.6, 0.06), Color("b3bbb5"), false)
	for y in [0.8, 1.6, 2.4, 3.2, 4.0]:
		_box("LoadingDoorSeam", Vector3(23, y, -35.90), Vector3(7, 0.04, 0.03), Color("71878e"), false)
	_sign("NOORDERKADE  /  WERKPLAATSEN", Vector3(24, 6.3, -35.9), 0.1, CREAM)
	_box("IndustryApron", Vector3(24, 0.015, -32), Vector3(28, 0.025, 7), PAVING, false)
	for i in range(3):
		_box("Crate", Vector3(38 + i * 1.8, 0.65, -38), Vector3(1.4, 1.3, 1.4), Color("a18760"))


func _street_details() -> void:
	for x in range(-60, 65, 15):
		_lamp(Vector3(x, 0, 10.6))
		if x != -15:
			_tree(Vector3(x + 4, 0, 26))
	for z in [-53.0, -33.0, -13.0, 34.0, 54.0]:
		_lamp(Vector3(-13.7, 0, z))
	for at in [Vector3(-10, 0, 4), Vector3(11, 0, 4), Vector3(-8, 0, -13), Vector3(7, 0, -14), Vector3(52, 0, -20), Vector3(54, 0, 47), Vector3(-51, 0, 22), Vector3(-52, 0, -27)]:
		_tree(at)
	var street_sign := _sign("NOORDERKADE", Vector3(-11.5, 2.1, 12), 0.08, CREAM)
	_box("StreetSign", Vector3(-11.5, 2.1, 11.9), Vector3(2.6, 0.5, 0.1), BLUE, false)
	street_sign.position.z = 12.01
	_cylinder("Signpost", Vector3(-11.5, 1.0, 11.9), 0.05, 2.0, NAVY, true)
	for x in [10.0, 11.0, 12.0]:
		_box("BikeRack", Vector3(x, 0.5, 1.3), Vector3(0.06, 1, 0.8), NAVY)


func _vehicle(id: String, title: String, at: Vector3, fire: bool) -> void:
	var vehicle := _station(id, title, at)
	var length := 5.2 if fire else 4.25
	var width := 2.15 if fire else 1.75
	var color := RED if fire else Color("e8ede8")
	_box("VehicleChassis", Vector3(0, 0.66, 0), Vector3(width, 0.68, length), color, true, vehicle)
	_box("Cab", Vector3(0, 1.3, -0.25), Vector3(width * 0.92, 0.74, 2.35), color, false, vehicle)
	_box("Windscreen", Vector3(0, 1.38, -1.44), Vector3(width * 0.83, 0.47, 0.05), GLASS, false, vehicle)
	_box("RearWindow", Vector3(0, 1.38, 0.955), Vector3(width * 0.83, 0.45, 0.05), GLASS, false, vehicle)
	for x in [-width * 0.465, width * 0.465]:
		_box("SideWindow", Vector3(x, 1.38, -0.3), Vector3(0.035, 0.46, 1.85), GLASS, false, vehicle)
		_box("VehicleStripe", Vector3(x * 1.078, 0.86, 0), Vector3(0.035, 0.2, length * 0.94), Color("e9d767") if fire else BLUE, false, vehicle)
		for z in [-length * 0.31, length * 0.31]:
			var wheel := _cylinder("Wheel", Vector3(x * 1.05, 0.42, z), 0.43, 0.2, Color("24313a"), false, vehicle)
			wheel.rotation.z = PI / 2.0
			var hub := _cylinder("WheelHub", Vector3(x * 1.18, 0.42, z), 0.2, 0.025, Color("93a5b0"), false, vehicle)
			hub.rotation.z = PI / 2.0
	for x in [-0.6, 0.6]:
		_box("Headlight", Vector3(x, 0.8, -length / 2.0 - 0.015), Vector3(0.35, 0.17, 0.035), Color("ffe4a1"), false, vehicle)
		_box("TailLight", Vector3(x, 0.8, length / 2.0 + 0.015), Vector3(0.32, 0.15, 0.035), RED, false, vehicle)
	_box("Lightbar", Vector3(0, 1.73, -0.45), Vector3(1.2, 0.17, 0.25), NAVY, false, vehicle)
	for x in [-0.42, 0.42]:
		_box("Beacon", Vector3(x, 1.77, -0.45), Vector3(0.34, 0.13, 0.24), Color("40b4df"), false, vehicle)
	if fire:
		_box("ApplianceBody", Vector3(0, 1.5, 1.1), Vector3(2.08, 1.1, 2.6), RED, false, vehicle)
		for x in [-1.055, 1.055]:
			_box("RollerShutter", Vector3(x, 1.4, 1.1), Vector3(0.035, 0.72, 2.1), Color("bac4c6"), false, vehicle)
		_box("RoofLadder", Vector3(0, 2.12, 0.8), Vector3(0.68, 0.1, 3.2), CREAM, false, vehicle)
	else:
		_box("BonnetStripe", Vector3(0, 1.01, -1.6), Vector3(1.1, 0.02, 0.55), BLUE, false, vehicle)


func _station(id: String, title: String, at: Vector3) -> Node3D:
	var station := Node3D.new()
	station.name = id
	station.position = at
	add_child(station)
	objects[id] = station
	_titles[id] = title
	return station


func _tree(at: Vector3) -> void:
	_cylinder("TreeTrunk", at + Vector3(0, 1.5, 0), 0.2, 3.0, Color("76634e"), true)
	for offset in [Vector3(-0.65, 3.8, 0.1), Vector3(0.65, 3.8, -0.15), Vector3(0, 4.8, 0)]:
		var foliage := SphereMesh.new()
		foliage.radius = 1.55
		foliage.height = 3.1
		foliage.radial_segments = 10
		foliage.rings = 5
		_mesh("TreeCrown", at + offset, foliage, Color("51775b"), false)


func _lamp(at: Vector3) -> void:
	_cylinder("LampPost", at + Vector3(0, 2.2, 0), 0.08, 4.4, NAVY, true)
	_box("LampCap", at + Vector3(0, 4.42, 0), Vector3(0.62, 0.15, 0.62), NAVY, false)
	_box("LampGlass", at + Vector3(0, 4.23, 0), Vector3(0.38, 0.3, 0.38), Color("ffe6b4"), false)


func _bench(at: Vector3) -> void:
	_box("BenchSeat", at + Vector3(0, 0.5, 0), Vector3(2.5, 0.12, 0.65), Color("987958"))
	_box("BenchBack", at + Vector3(0, 0.95, 0.3), Vector3(2.5, 0.6, 0.1), Color("987958"))
	for x in [-0.95, 0.95]:
		_box("BenchLeg", at + Vector3(x, 0.23, 0), Vector3(0.12, 0.46, 0.55), NAVY, false)


func _cone(at: Vector3) -> void:
	_box("ConeBase", at + Vector3(0, 0.04, 0), Vector3(0.58, 0.08, 0.58), NAVY, false)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.035
	cone.bottom_radius = 0.22
	cone.height = 0.65
	_mesh("TrainingCone", at + Vector3(0, 0.39, 0), cone, Color("e39a46"), false)
	_cylinder("ConeStripe", at + Vector3(0, 0.38, 0), 0.15, 0.13, CREAM, false)


func _sign(text: String, at: Vector3, pixel_scale: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = 48
	label.pixel_size = pixel_scale / 20.0
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	add_child(label)
	return label


func _box(node_name: String, at: Vector3, size: Vector3, color: Color, solid: bool = true, parent: Node3D = null) -> Node3D:
	var shape := BoxMesh.new()
	shape.size = size
	return _mesh(node_name, at, shape, color, solid, parent)


func _cylinder(node_name: String, at: Vector3, radius: float, height: float, color: Color, solid: bool, parent: Node3D = null) -> Node3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 12
	return _mesh(node_name, at, shape, color, solid, parent)


func _mesh(node_name: String, at: Vector3, shape: PrimitiveMesh, color: Color, solid: bool, parent: Node3D = null) -> Node3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = shape
	instance.material_override = _material(color)
	var result: Node3D = instance
	if solid:
		var body := StaticBody3D.new()
		body.name = node_name
		body.add_child(instance)
		var collision := CollisionShape3D.new()
		collision.shape = shape.create_convex_shape()
		body.add_child(collision)
		result = body
	result.position = at
	(parent if parent != null else self).add_child(result)
	return result


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.82
		_materials[key] = material
	return _materials[key]
