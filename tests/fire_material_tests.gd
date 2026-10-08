extends SceneTree
## Explicit CPU-profile fixture; this is not native Apple rendering evidence.
const Main = preload("res://scenes/main.tscn")
var checks := 0
var failures := 0
var app: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FIRE_MATERIAL_FAIL " + label)

func run() -> void:
	app = Main.instantiate()
	root.add_child(app)
	await process_frame
	app.test_mode = true
	app._test_timeout(30)
	app.fire_ui.start_lesson()
	app.set_process(false)
	var atmosphere: Node3D = app.district.atmosphere
	atmosphere.apple_software_basic = true
	atmosphere.apply_conditions("day")
	for i in app.fire_model.cells.size():
		app.fire_model.cells[i].burned = 0.08
		app.fire_model.cells[i].wet = 0.8
	app.fire_site.update_state(app.fire_model)
	_verify_fuel(true)
	# Switching conditions restores then reconstructs the owned material profile.
	atmosphere.apply_conditions("rain")
	app.fire_site.update_state(app.fire_model)
	_verify_fuel(true)
	# A new lesson restores unburned colors rather than stale prior overrides.
	app.fire_ui.start_lesson()
	app.set_process(false)
	app.fire_site.update_state(app.fire_model)
	_verify_fuel(false)
	if failures == 0: print("SCENE112_FIRE_MATERIAL_TESTS_OK checks=", checks)
	app._test_finished = true
	await app.quit_game(1 if failures else 0)

func _verify_fuel(burned: bool) -> void:
	for entries: Array in app.fire_site._fuel_materials.values():
		for entry: Dictionary in entries:
			var source: StandardMaterial3D = entry.material
			var active: ShaderMaterial = entry.mesh.get_active_material(int(entry.surface))
			check(source != active and source.albedo_color.is_equal_approx(active.get_shader_parameter("base_color")), "current source color reaches simplified fuel")
			check(not active.shader.code.contains("ROUGHNESS"), "CPU profile keeps inexpensive dry diffuse")
			check(not source.albedo_color.is_equal_approx(entry.color) if burned else source.albedo_color.is_equal_approx(entry.color), "incident color follows current lesson state")
