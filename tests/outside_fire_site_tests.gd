extends SceneTree
const Case = preload("res://scripts/outside_fire_case.gd")
const Site = preload("res://scripts/outside_fire_site.gd")
const Controller = preload("res://scripts/outside_fire_controller.gd")
class District:
	extends Node3D
	var objects := {}
	var _titles := {}
	var atmosphere: Node3D
class Officer:
	extends CharacterBody3D
	var camera: Camera3D
class AudioProbe:
	extends Node
	var context := {}
	var spraying := false
	func update_outside_fire(next: Dictionary, _at: Vector3, flow: bool) -> bool:
		context = next.duplicate(true); spraying = flow; return true
class AppProbe:
	extends Node3D
	var district: Node3D
	var officer: CharacterBody3D
	var state := {"equipment": true, "radio_checked": true, "occupied_vehicle": ""}
	var active := true
	var paused := false
	var hud: Control
	var objective: Label
	var duty_label: Label
	var route_label: Label
	var prompt: Label
	var current_target := {}
	var audio: Node
	func _controlled_position() -> Vector3: return officer.global_position
	func _label(text: String, _size: int, _color: Color) -> Label:
		var label := Label.new(); label.text = text; return label
	func _notify(_message: String) -> void: pass
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var district := District.new(); root.add_child(district)
	var ground := StaticBody3D.new(); var floor_shape := CollisionShape3D.new(); var floor_box := BoxShape3D.new(); floor_box.size = Vector3(50, 0.2, 50); floor_shape.shape = floor_box; ground.position.y = -0.1; ground.add_child(floor_shape); district.add_child(ground)
	var floor_mesh := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(50, 50); floor_mesh.mesh = plane; var floor_mat := StandardMaterial3D.new(); floor_mat.albedo_color = Color("686f66"); floor_mesh.material_override = floor_mat; district.add_child(floor_mesh)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-55, -30, 0); sun.shadow_enabled = true; district.add_child(sun)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color("8daaba"); environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color("b8c9cf"); environment.environment.ambient_light_energy = 0.65; district.add_child(environment)
	var officer := Officer.new(); officer.position = Vector3(0, 0, -4)
	var capsule := CollisionShape3D.new(); var capsule_shape := CapsuleShape3D.new(); capsule_shape.radius = 0.31; capsule_shape.height = 1.8; capsule.shape = capsule_shape; capsule.position.y = 0.9; officer.add_child(capsule); district.add_child(officer)
	officer.camera = Camera3D.new(); district.add_child(officer.camera); officer.camera.current = true
	var model := Case.new(); model.begin(2, 0, Vector3.ZERO)
	var site := Site.new(); site.attach_to(district); site.set_carrier(officer); site.setup(model)
	check(district.objects.size() == 4 and site._targets.size() == 3, "three physical targets and four registered spatial interactions")
	check(Controller.new() != null, "actual controller script compiles")
	for step in Case.BASICS: model.complete_step(step)
	model.check_recon("exterior"); model.check_recon("surroundings"); model.connect_water(); model.choose_tactic("defensive"); model.add_hose_point(Vector3(0, 0, -4))
	site.set_simulation_active(true); site.update_state(model)
	await physics_frame; await process_frame; await physics_frame
	check(site._hose.get_child_count() == 1, "real hose mesh follows source and endpoint")
	officer.camera.global_position = Vector3(0, 2.3, -7); officer.camera.look_at(Vector3(0, 0.8, 0))
	await process_frame
	check(site.raycast_target(officer.camera, officer) == "center", "camera ray plus real nozzle visibility acquires center cell")
	var wall := StaticBody3D.new(); wall.position = Vector3(0, 1.0, -2)
	var wall_shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(4, 2, 0.3); wall_shape.shape = box; wall.add_child(wall_shape); district.add_child(wall)
	await physics_frame; await process_frame; await physics_frame
	check(site.raycast_target(officer.camera, officer).is_empty(), "solid obstruction prevents through-wall target")
	district.remove_child(wall); wall.queue_free()
	await physics_frame; await process_frame
	officer.global_position = Vector3(0, 0, -3.2)
	check(site.get_interaction(officer).get("id") == "outside_exterior", "nearest actual exterior interaction resolved")
	officer.global_position = Vector3(20, 0, -20)
	check(site.get_interaction(officer).is_empty(), "remote interaction unavailable")
	officer.global_position = Vector3(0, 0, -4)
	site.show_jet("center", true)
	await process_frame
	check(site._effects._stream_requested, "actual stream starts")
	site.set_simulation_active(false)
	var clock_before: float = site._effects._clock
	for frame in range(3): await process_frame
	check(site._effects._clock == clock_before and not site._effects._stream_requested, "pause freezes flame clock and closes water stream")
	site.set_simulation_active(true)
	for frame in range(30): await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://evidence/outside-crates.png") == OK, "fresh actual renderer screenshot")
	for variant in [1, 2]:
		model.begin(variant + 3, variant, Vector3(4, 0, 3)); site.setup(model); site.set_simulation_active(true)
		await physics_frame; await process_frame
		check(site._targets.size() == 3 and district.objects.size() == 4, "variant rebuild removes previous geometry and IDs")
		officer.camera.global_position = Vector3(8, 3.1, -5); officer.camera.look_at(Vector3(4, 0.7, 3))
		for frame in range(25): await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://evidence/outside-variant-%d.png" % variant) == OK, "fresh variant renderer screenshot")
	# Controller proof uses actual held mouse input, rays and fixed stepping.
	model.begin(20, 0, Vector3.ZERO)
	for step in Case.BASICS: model.complete_step(step)
	model.check_recon("exterior"); model.check_recon("surroundings"); model.connect_water(); model.choose_tactic("defensive"); model.add_hose_point(Vector3(0, 0, -4))
	officer.position = Vector3(0, 0, -4); officer.camera.position = Vector3(0, 2.3, -7); officer.camera.look_at(Vector3(0, 0.8, 0))
	var app := AppProbe.new(); root.add_child(app); app.district = district; app.officer = officer
	var truck := Node3D.new(); district.add_child(truck); district.objects.fire_truck = truck
	app.hud = Control.new(); app.add_child(app.hud)
	app.objective = Label.new(); app.duty_label = Label.new(); app.route_label = Label.new(); app.prompt = Label.new()
	for label in [app.objective, app.duty_label, app.route_label, app.prompt]: app.hud.add_child(label)
	app.audio = AudioProbe.new(); app.add_child(app.audio)
	var controller := Controller.new(); controller.setup(app, model, site)
	await physics_frame; await process_frame; await physics_frame
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.use_accumulated_input = false
	var mouse := InputEventMouseButton.new(); mouse.button_index = MOUSE_BUTTON_LEFT; mouse.button_mask = MOUSE_BUTTON_MASK_LEFT; mouse.pressed = true; Input.parse_input_event(mouse)
	await process_frame
	var heat_before: float = model.cells[0].heat
	for frame in range(60): controller.tick(0.03 if frame % 2 == 0 else 0.02)
	print("OUTSIDE_CONTROLLER_TRACE clock=", model.clock, " water=", model.water_used, " heat=", model.cells[0].heat, " target=", site.raycast_target(officer.camera, officer), " held=", Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	check(absf(model.clock - 1.5) < 0.000001 and model.water_used > 0 and float(model.cells[0].heat) < heat_before, "variable render delta drives real targeted fixed-step water and heat")
	check(model.simulation.size() < 5, "fixed-step controller keeps replay journal compact")
	check(app.audio.context.size() == 6 and app.audio.context.cells[0].keys().size() == 3 and app.audio.context.has("withdrew"), "audio receives exact small world-cell DTO without save journal")
	app.paused = true
	var paused_state: Dictionary = model.to_dict()
	for frame in range(10): controller.tick(0.4)
	check(model.to_dict() == paused_state and app.audio.context == {"mode": "none"} and not app.audio.spraying, "pause neither advances model nor banks time and clears audio")
	app.paused = false; var release := InputEventMouseButton.new(); release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false; Input.parse_input_event(release)
	controller.tick(0.01)
	check(model.to_dict() == paused_state, "resume does not replay paused wall time")
	app.active = false; controller.tick(0.5)
	check(app.audio.context == {"mode": "none"}, "inactive app clears audio context every frame")
	controller = null; app.queue_free(); district.objects.erase("fire_truck")
	site.clear()
	check(district.objects.is_empty() and site._owned == null, "clear removes owned objects and resets visuals")
	district.queue_free()
	for frame in range(6): await process_frame
	print("OUTSIDE_FIRE_SITE_TESTS ", checks, " checks / ", failures, " failures")
	quit(0 if failures == 0 else 1)
