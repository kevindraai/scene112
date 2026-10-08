extends SceneTree
## No game assets or external files. Reproduces duplicated/replaced Sky lifetime.
var original: Environment
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		push_error("SKY_COPY_EVIDENCE requires actual Compatibility rendering")
		quit(1)
		return
	var deep := "deep" in OS.get_cmdline_user_args()
	var world := Node3D.new()
	root.add_child(world)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.material_override = StandardMaterial3D.new()
	world.add_child(mesh)
	var light := DirectionalLight3D.new()
	light.rotation_degrees.x = -45
	world.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1, 4)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	original = Environment.new()
	original.background_mode = Environment.BG_SKY
	original.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var initial_sky := Sky.new()
	initial_sky.sky_material = ProceduralSkyMaterial.new()
	original.sky = initial_sky
	var holder := WorldEnvironment.new()
	holder.environment = original
	world.add_child(holder)
	var replacement := original.duplicate(deep) as Environment
	holder.environment = replacement
	var new_sky := Sky.new()
	new_sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	new_sky.radiance_size = Sky.RADIANCE_SIZE_128
	new_sky.sky_material = ProceduralSkyMaterial.new()
	replacement.sky = new_sky
	for i in range(16): await RenderingServer.frame_post_draw
	print("SCENE112_SKY_COPY_RENDERED deep=", deep, " original_size=", original.sky.radiance_size,
		" new_size=", replacement.sky.radiance_size, " renderer=", RenderingServer.get_current_rendering_method(),
		" driver=", RenderingServer.get_current_rendering_driver_name(), " adapter=", RenderingServer.get_video_adapter_name())
	quit()
