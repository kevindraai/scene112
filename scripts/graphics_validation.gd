extends RefCounted
## Integrated source and standalone-export assertions; screenshots require rendering.
## Pose fixtures are disclosed. Motion, animation, camera, wheels and save/load use root code.
const SAVE := "user://validation-visual-street.json"
const MODEL_PBR := {
	"characters/officer": 5, "characters/civilian": 5, "street/dutch_terrace": 3,
	"street/street_bench": 1, "street/street_lamp": 0, "street/dutch_bicycle": 0,
	"vehicles/police_car": 5, "vehicles/fire_truck": 5,
	"vegetation/street_tree": 3,
}
var app: Node3D
var checks := 0
var report := {"scope": "integrated runtime; initial pose/equipment fixtures", "models": {}, "conditions": []}

func run(root_app: Node3D) -> void:
	app = root_app
	app._test_timeout(420)
	_cleanup()
	_stage("initial_draw")
	await app._test_frames(2)
	print("SCENE112_GRAPHICS_BACKEND=", JSON.stringify(_backend()))
	_stage("start_new")
	app.start_new("police")
	app.state.equipment = true
	app.state.radio_checked = true
	if not _check(app.state.SCHEMA == 4 and app.state.condition == "day" and app.state.graphics_quality == "portable", "schema4 and safe visual defaults"): return
	app._apply_visual_settings()
	if not _check(is_instance_valid(app.district.atmosphere), "atmosphere actually attached to root district"): return
	_stage("models_and_rigs")
	if not _inspect_models(): return
	if not _inspect_actor(app.officer._graphics, "officer"): return
	if not _check(app.district._pedestrians.size() >= 3, "existing live civilians remain in district"): return
	for npc: CharacterBody3D in app.district._pedestrians:
		if not _inspect_actor(npc._graphics, str(npc.name)): return
	_stage("roof_camera")
	if not await _max_pitch_roof_camera(): return
	_stage("walk_and_pause")
	if not await _walk_camera_and_pause(): return
	_stage("vehicle")
	if not await _drive(): return
	_stage("connected_street")
	if not await _frontage_drive(): return
	_stage("conditions_and_save")
	if not await _conditions_and_save(): return
	report["checks"] = checks
	report["engine"] = Engine.get_version_info()
	report["display"] = DisplayServer.get_name()
	report["driver"] = RenderingServer.get_current_rendering_driver_name()
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["api"] = RenderingServer.get_video_adapter_api_version()
	report["viewport"] = [app.get_viewport().get_visible_rect().size.x, app.get_viewport().get_visible_rect().size.y]
	report["limits"] = "No physical target GPU or audible quality claim; screenshots absent in headless. Godot monitors may lag. Existing M2 police/native flags remain separate mandatory regressions."
	var file := FileAccess.open("user://visual-runtime.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	_cleanup()
	print("SCENE112_VISUAL_OK checks=", checks, " renderer=", report.renderer, " driver=", report.driver, " adapter=", report.adapter, " screenshots=", DisplayServer.get_name() != "headless", " fixtures=initial positions and equipment; actual walk>10m drive>20m reverse/steering/brake/exit, imported PBR/rig/wheel/camera/pause, conditions and root save/load")
	app._test_finished = true
	await app.quit_game(0)

func _stage(value: String) -> void:
	print("SCENE112_GRAPHICS_STAGE=", value, " elapsed_ms=", Time.get_ticks_msec(), " checks=", checks)

func _inspect_models() -> bool:
	var roots := {}
	for node: Node in _nodes(app):
		if node.scene_file_path.begins_with("res://assets/models/"):
			var key := node.scene_file_path.trim_prefix("res://assets/models/").trim_suffix(".glb")
			if not roots.has(key): roots[key] = node
	for key: String in MODEL_PBR:
		if not _check(roots.has(key), "actual imported GLB connected to root scene: " + key): return false
		var materials := {}
		var full_pbr := 0
		var skin_meshes := 0
		var meshes := 0
		for child: Node in _nodes(roots[key]):
			if not child is MeshInstance3D: continue
			meshes += 1
			if child.skin != null and child.get_node_or_null(child.skeleton) is Skeleton3D: skin_meshes += 1
			for surface in range(child.mesh.get_surface_count()):
				var material := child.get_active_material(surface) as StandardMaterial3D
				if material == null or materials.has(material.get_instance_id()): continue
				materials[material.get_instance_id()] = true
				if material.albedo_texture == null or material.roughness_texture == null or not material.normal_enabled or material.normal_texture == null: continue
				for texture: Texture2D in [material.albedo_texture, material.roughness_texture, material.normal_texture]:
					if not _check(texture.get_width() >= 256 and texture.get_height() >= 256, "loaded usable PBR maps: " + key): return false
				full_pbr += 1
		if not _check(meshes > 0 and full_pbr >= MODEL_PBR[key], "actual albedo/normal/roughness material coverage: " + key): return false
		if key.begins_with("characters/") and not _check(skin_meshes > 0, "mesh bound to actual skeleton: " + key): return false
		report.models[key] = {"meshes": meshes, "materials": materials.size(), "full_pbr": full_pbr, "skin_meshes": skin_meshes}
	for i in range(5):
		var wrapper := app.district.get_node_or_null("Woning%d" % (24 + i)) as Node3D
		if not _check(wrapper != null and wrapper.position.distance_to(Vector3(-2 + 8 * i, 0, 48)) < 0.01, "existing house wrapper footprint retained"): return false
	for id: String in ["police_car", "fire_truck"]:
		var vehicle: CharacterBody3D = app.district.objects[id]
		if not _check(is_instance_valid(vehicle.imported_model) and vehicle.named_wheels.size() == 4, "imported service vehicle and four actual wheel pivots: " + id): return false
		var bounds := _model_bounds(vehicle.imported_model, vehicle)
		var shape := vehicle._collision.shape as BoxShape3D
		if not _check(bounds.size.x <= shape.size.x + 0.12 and bounds.size.y <= shape.size.y + 0.12 and bounds.size.z <= shape.size.z + 0.12, "collider covers authored service vehicle dimensions: " + id): return false
		report.models["vehicles/" + id]["render_bounds"] = [bounds.size.x, bounds.size.y, bounds.size.z]
		report.models["vehicles/" + id]["collision_bounds"] = [shape.size.x, shape.size.y, shape.size.z]
	return true

func _inspect_actor(actor: Node3D, label: String) -> bool:
	var data: Dictionary = actor.diagnostics()
	if not _check(data.loaded and data.bones == 18 and actor.animation != null, "actual 18-bone authored actor: " + label): return false
	for clip: String in ["idle", "walk", "run", "carry"]:
		if not _check(actor.animation.has_animation(clip) and actor.animation.get_animation(clip).get_track_count() > 0, "actual keyed actor clip " + label + "/" + clip): return false
	return true

func _max_pitch_roof_camera() -> bool:
	# This reachable maximum-pitch case previously entered the imported eave
	# despite passing the old footprint-box test. Check actual facade triangles.
	_fixture_foot(Vector3(-2, 0.1, 41.5), 0, -0.23)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(0, 0.72 / app.officer.sensitivity)
	app.officer._unhandled_input(motion)
	await app._test_frames(8)
	var origin: Vector3 = app.officer._pivot.global_position
	var camera_at: Vector3 = app.officer.camera.global_position
	var triangles := 0
	var hits := 0
	var facade: Node3D = app.district.get_node("Woning24/AuthoredFacade")
	for node: Node in _nodes(facade):
		if not node is MeshInstance3D: continue
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for i in range(0, count - 2, 3):
				var a: Vector3 = node.global_transform * vertices[indices[i] if not indices.is_empty() else i]
				var b: Vector3 = node.global_transform * vertices[indices[i + 1] if not indices.is_empty() else i + 1]
				var c: Vector3 = node.global_transform * vertices[indices[i + 2] if not indices.is_empty() else i + 2]
				triangles += 1
				if Geometry3D.segment_intersects_triangle(origin, camera_at, a, b, c) is Vector3: hits += 1
	report["roof_camera"] = {"pitch": app.officer._pitch, "arm_hit_length": app.officer._arm.get_hit_length(),
		"camera": [camera_at.x, camera_at.y, camera_at.z], "facade_triangles_checked": triangles, "intersections": hits}
	if not _check(is_equal_approx(app.officer._pitch, -0.95) and app.officer._arm.get_hit_length() < app.officer._arm.spring_length, "actual mouse reaches maximum pitch and SpringArm catches authored roof shell"): return false
	return _check(triangles > 1000 and hits == 0, "maximum-pitch camera segment does not enter actual imported facade/eave triangles")

func _walk_camera_and_pause() -> bool:
	_fixture_foot(Vector3(-2, 0.1, 43.5), 0, -0.1)
	await app._test_frames(8)
	var camera := app.officer.camera as Camera3D
	var sphere := SphereShape3D.new()
	sphere.radius = 0.15
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, camera.global_position)
	query.exclude = [app.officer.get_rid()]
	if not _check(app.officer._arm.get_hit_length() < 2 and app.officer.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "SpringArm shortens at actual house wall and camera remains outside collider"): return false
	app.officer._pivot.rotation.y = PI
	Input.action_press("move_forward")
	await app.get_tree().create_timer(1.0).timeout
	_release()
	if not _check(app.officer.position.z > 43.6 and app.officer.position.z < 44.3, "real W stops at original house facade collision"): return false
	var start: Vector3 = app.officer.position
	Input.action_press("move_left")
	if not await app._wait_for(func(): return app.officer._graphics.diagnostics().clip == "walk", "visual walk clip follows physical input", 10): return false
	var skeleton := app.officer._graphics.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var poses := _poses(skeleton)
	var changed := false
	for i in range(6):
		await app.get_tree().process_frame
		changed = changed or _poses_changed(poses, _poses(skeleton))
	if not _check(changed, "walking actually deforms bound skeleton bones"): return false
	if not await app._wait_for(func(): return app.officer.position.distance_to(start) > 10, "actual >10m camera-relative walking", 30): return false
	_release()
	report["walk_metres"] = app.officer.position.distance_to(start)
	await app._test_frames(2)
	app._freeze()
	var actors: Array[Node3D] = [app.officer._graphics]
	var bodies: Array[Node3D] = [app.officer]
	for npc: Node3D in app.district._pedestrians:
		actors.append(npc._graphics)
		bodies.append(npc)
	var cursors: Array[float] = []
	var positions: Array[Vector3] = []
	for actor in actors: cursors.append(actor.animation.current_animation_position)
	for body in bodies: positions.append(body.global_position)
	await app.get_tree().create_timer(0.35).timeout
	for i in range(actors.size()):
		if not _check(not actors[i].animation.active and is_equal_approx(cursors[i], actors[i].animation.current_animation_position) and bodies[i].global_position.distance_to(positions[i]) < 0.001, "pause freezes real actor body and animation cursor"): return false
	app._resume()
	await app._test_frames(2)
	for actor in actors:
		if not _check(actor.animation.active, "resume reactivates imported animation player"): return false
	return true

func _drive() -> bool:
	var car: CharacterBody3D = app.district.objects.police_car
	car.stop()
	car.global_position = Vector3(-20, 0.05, -15)
	car.rotation.y = PI
	_fixture_foot(Vector3(-18.2, 0.1, -15), PI, -0.23)
	await app._test_frames(3)
	app._enter_vehicle("police_car")
	if not _check(app.state.occupied_vehicle == "police_car" and not app.officer._graphics.animation.active, "production vehicle entry freezes hidden officer animation"): return false
	var centres := _wheel_centres(car)
	var before := _wheel_rotations(car)
	var start := car.global_position
	Input.action_press("move_forward")
	if not await app._wait_for(func(): return car.global_position.distance_to(start) > 20, "actual authored vehicle >20m drive", 40): return false
	if not _check(_wheel_motion(before, _wheel_rotations(car)), "actual forward movement rotates all imported wheels"): return false
	if not _check(_wheel_centres_same(centres, _wheel_centres(car)), "rolling keeps wheel axle centres fixed in vehicle coordinates"): return false
	var yaw: float = car.rotation.y
	Input.action_press("move_left")
	await app.get_tree().create_timer(0.3).timeout
	Input.action_release("move_left")
	if not _check(absf(angle_difference(yaw, car.rotation.y)) > 0.02 and _wheel_centres_same(centres, _wheel_centres(car)), "actual steering turns vehicle without wheel orbit"): return false
	_release()
	Input.action_press("brake")
	if not await app._wait_for(func(): return absf(car.speed) < 0.05, "actual vehicle brake", 8): return false
	_release()
	report["drive_metres"] = car.global_position.distance_to(start)
	before = _wheel_rotations(car)
	var reverse_start := car.global_position
	Input.action_press("move_back")
	if not await app._wait_for(func(): return car.global_position.distance_to(reverse_start) > 0.6, "actual reverse drive", 8): return false
	if not _check(car.speed < 0 and _wheel_motion(before, _wheel_rotations(car)) and _wheel_centres_same(centres, _wheel_centres(car)), "reverse physically moves and rotates centred authored wheels"): return false
	_release()
	Input.action_press("brake")
	if not await app._wait_for(func(): return absf(car.speed) < 0.05, "reverse brake", 8): return false
	_release()
	app._exit_vehicle()
	return _check(app.state.occupied_vehicle.is_empty() and app.officer.visible and app.officer._graphics.animation.active, "actual collision-safe exit restores officer rig and control")

func _frontage_drive() -> bool:
	# A second disclosed initial fixture checks access from the existing main
	# road to the authored frontage using actual throttle, steering and brakes.
	var car: CharacterBody3D = app.district.objects.police_car
	car.stop()
	car.global_position = Vector3(-11, 0.05, 18)
	car.rotation.y = PI
	_fixture_foot(Vector3(-9.2, 0.1, 18), PI, -0.23)
	await app._test_frames(3)
	app._enter_vehicle("police_car")
	if not _check(app.state.occupied_vehicle == "police_car", "normal vehicle entry for frontage access route"): return false
	var start := car.global_position
	Input.action_press("move_forward")
	if not await app._wait_for(func(): return car.global_position.z > 28, "actual drive through frontage access", 20): return false
	_release()
	Input.action_press("brake")
	if not await app._wait_for(func(): return absf(car.speed) < 0.05, "brake before frontage turn", 8): return false
	_release()
	var deadline := Time.get_ticks_msec() + 20000
	Input.action_press("move_left")
	while absf(angle_difference(PI, car.rotation.y)) < 1.52:
		if car.speed < 3.4: Input.action_press("move_forward")
		else: Input.action_release("move_forward")
		await app.get_tree().physics_frame
		if Time.get_ticks_msec() > deadline:
			return _check(false, "actual slow steering reaches authored street without obstruction")
	_release()
	if not _check(car.global_position.z > 31 and car.global_position.z < 40, "real turn reaches the authored frontage road"): return false
	Input.action_press("move_forward")
	if not await app._wait_for(func(): return car.global_position.x > 20, "actual >30m connected street route", 30): return false
	_release()
	Input.action_press("brake")
	if not await _diagnose_frontage_brake(car): return false
	_release()
	report["frontage_drive_metres"] = car.global_position.distance_to(start)
	if not _check(report.frontage_drive_metres > 30 and car.global_position.z < 40, "authored street is genuinely connected and drivable"): return false
	app._exit_vehicle()
	return _check(app.state.occupied_vehicle.is_empty() and app.officer.visible, "safe production exit on authored street")

func _conditions_and_save() -> bool:
	_fixture_foot(Vector3(-2, 0.1, 38), PI, -0.1)
	app.state.graphics_quality = "balanced"
	for condition: String in ["day", "dusk", "rain"]:
		_stage("condition_" + condition)
		app.state.condition = condition
		app._apply_visual_settings()
		await app._test_frames(2)
		var atmosphere: Node3D = app.district.atmosphere
		var info: Dictionary = atmosphere.diagnostics()
		if not _check(info.conditions == condition and info.quality == "balanced" and info.lamps <= 4 and info.local_shadows <= 2 and info.reflection_probes == (0 if info.software_gl else 1) and info.particles <= 280, "bounded root scene condition: " + condition): return false
		if info.software_gl:
			if not _check(info.requested_quality == "balanced" and info.effective_quality == "software_portable" and info.render_scale == .5 and info.sky_radiance_size == 32 and not info.ssao and not info.glow and not info.ssr and not info.sun_shadows and info.local_shadows == 0, "actual software-only fallback is explicit and bounded"): return false
		else:
			if not _check(info.effective_quality == "balanced", "hardware quality remains unchanged"): return false
		if not _check(info.managed_surfaces > 35 and info.material_variants > 10, "condition manages actual authored surfaces"): return false
		if condition == "rain":
			if not _check(info.particles > 0 and atmosphere._rain.emitting, "actual outdoor rain particles active"): return false
			# Weather audio updates on process frames, then queues its 3D start;
			# two catch-up physics ticks need not include a process/audio update.
			if not await app._wait_for(func(): return app.audio._ambience.rain.playing, "actual root positional rain playback", 10): return false
			if not _check(app.audio._ambience.rain.stream == app.audio._streams.rain, "actual root weather state starts the original positional rain WAV"): return false
			app._freeze()
			await app._test_frames(2)
			if not _check(atmosphere._rain.speed_scale == 0 and atmosphere.diagnostics().particles_paused, "pause stops actual rain simulation"): return false
			app._resume()
		if DisplayServer.get_name() != "headless":
			for i in range(8): await RenderingServer.frame_post_draw
			var code: Error = app.get_viewport().get_texture().get_image().save_png("user://visual-street-%s.png" % condition)
			if not _check(code == OK, "actual rendered condition screenshot: " + condition): return false
			info["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			info["primitives"] = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			info["video_bytes"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
		report.conditions.append(info)
	_stage("high_rain")
	app.state.graphics_quality = "high"
	app._apply_visual_settings()
	var high: Dictionary = app.district.atmosphere.diagnostics()
	if not _check(high.ssr == (high.renderer == "forward_plus" and not high.software_gl), "rain SSR only active on high Forward+"): return false
	report["high_rain"] = high
	if high.software_gl:
		if not _check(high.requested_quality == "high" and high.effective_quality == "software_portable" and not high.ssao and not high.glow and not high.ssr and high.local_shadows == 0, "requested high is truthfully reported as software fallback"): return false
	if DisplayServer.get_name() != "headless":
		for frame in range(4): await RenderingServer.frame_post_draw
		if not _check(app.get_viewport().get_texture().get_image().save_png("user://visual-street-high-rain.png") == OK, "actual rain shader rendering with effective profile recorded"): return false
	app.save_game(SAVE)
	app.state.condition = "day"
	app.state.graphics_quality = "portable"
	app._apply_visual_settings()
	app.load_game(SAVE)
	if not _check(app.state.condition == "rain" and app.state.graphics_quality == "high" and app.district.atmosphere.conditions == "rain" and app.district.atmosphere.quality == "high", "root save/load applies actual visual settings after changing memory and world"): return false
	var legacy: Dictionary = app.state.to_dict()
	legacy["schema"] = 3
	legacy.erase("condition")
	legacy.erase("graphics_quality")
	var migrated = app.state.get_script().new()
	if not _check(migrated.restore(legacy) and migrated.condition == "day" and migrated.graphics_quality == "portable", "schema3 save migrates safe visual defaults"): return false
	var invalid: Dictionary = app.state.to_dict()
	invalid["condition"] = "snow"
	if not _check(not migrated.restore(invalid), "unknown persisted condition rejected"): return false
	invalid = app.state.to_dict()
	invalid["graphics_quality"] = "unbounded"
	if not _check(not migrated.restore(invalid), "unknown persisted quality rejected"): return false
	app.state.condition = "day"
	app.state.graphics_quality = "portable"
	app._apply_visual_settings()
	return true

func _fixture_foot(at: Vector3, yaw: float, pitch: float) -> void:
	_release()
	app.officer.global_position = at
	app.officer.velocity = Vector3.ZERO
	app.officer._pitch = pitch
	app.officer._pivot.rotation = Vector3(pitch, yaw, 0)

func _backend() -> Dictionary:
	return {"renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "vendor": RenderingServer.get_video_adapter_vendor(),
		"adapter_type": RenderingServer.get_video_adapter_type(), "api": RenderingServer.get_video_adapter_api_version(),
		"display": DisplayServer.get_name(), "user_data_dir": OS.get_user_data_dir()}

func _check(condition: bool, description: String) -> bool:
	checks += 1
	if not condition: _release()
	return app._check(condition, "VISUAL " + description)

func _nodes(parent: Node) -> Array[Node]:
	var result: Array[Node] = [parent]
	for child in parent.get_children(): result.append_array(_nodes(child))
	return result

func _poses(skeleton: Skeleton3D) -> Array[Quaternion]:
	var result: Array[Quaternion] = []
	for i in skeleton.get_bone_count(): result.append(skeleton.get_bone_pose_rotation(i))
	return result

func _poses_changed(before: Array[Quaternion], after: Array[Quaternion]) -> bool:
	for i in before.size():
		if absf(before[i].dot(after[i])) < 0.99999: return true
	return false

func _wheel_centres(car: Node3D) -> Dictionary:
	var result := {}
	for key: String in car.named_wheels: result[key] = car.to_local(car.named_wheels[key].global_position)
	return result

func _wheel_rotations(car: Node3D) -> Dictionary:
	var result := {}
	for key: String in car.named_wheels: result[key] = car.named_wheels[key].quaternion
	return result

func _wheel_motion(before: Dictionary, after: Dictionary) -> bool:
	for key: String in before:
		if absf(before[key].dot(after[key])) > 0.99999: return false
	return true

func _wheel_centres_same(before: Dictionary, after: Dictionary) -> bool:
	for key: String in before:
		if before[key].distance_to(after[key]) > 0.001: return false
	return true

func _model_bounds(model: Node3D, vehicle: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node: Node in _nodes(model):
		if not node is MeshInstance3D: continue
		var bounds: AABB = vehicle.global_transform.affine_inverse() * node.global_transform * node.get_aabb()
		result = bounds if first else result.merge(bounds)
		first = false
	return result

func _release() -> void:
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "sprint", "brake"]:
		if InputMap.has_action(action): Input.action_release(action)

func _cleanup() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(SAVE + suffix): DirAccess.remove_absolute(SAVE + suffix)

func _diagnose_frontage_brake(car: Node3D) -> bool:
	# Observe the actual physics clock: max 14m/s and 13m/s² require <1.1s
	# to stop. Two simulated seconds retain margin on slow software renderers.
	# The final speed and a separate 60s wall watchdog remain mandatory.
	var began := Time.get_ticks_msec()
	var first_tick := Engine.get_physics_frames()
	var samples: Array = []
	var observed_tick := [-1]
	var condition := func() -> bool:
		var tick := Engine.get_physics_frames()
		if tick != observed_tick[0] and samples.size() < 32:
			observed_tick[0] = tick
			samples.append({"wall_ms": Time.get_ticks_msec() - began,
				"physics_ticks": tick - first_tick, "speed": car.speed,
				"brake_held": Input.is_action_pressed("brake"), "enabled_input": car.enabled_input,
				"position": [car.global_position.x, car.global_position.y, car.global_position.z]})
		return absf(car.speed) < 0.05 or tick - first_tick >= Engine.physics_ticks_per_second * 2
	var observed: bool = await app._wait_for(condition, "brake on authored frontage", 60)
	var elapsed_wall := Time.get_ticks_msec() - began
	var elapsed_physics := Engine.get_physics_frames() - first_tick
	var ok: bool = observed and absf(car.speed) < 0.05 and elapsed_physics <= Engine.physics_ticks_per_second * 2 and elapsed_wall <= 60000
	print("SCENE112_BRAKE_DIAGNOSTICS=", JSON.stringify({"wall_ms": elapsed_wall,
		"physics_ticks": elapsed_physics, "final_speed": car.speed,
		"passed": ok, "samples": samples}))
	return _check(ok, "actual frontage brake stops within two simulated seconds")
