extends SceneTree
const A=preload("res://scripts/street_atmosphere.gd")
func _initialize():call_deferred("run")
func run():
	var district:=Node3D.new();root.add_child(district)
	var world:=WorldEnvironment.new();world.environment=Environment.new();district.add_child(world)
	var sun:=DirectionalLight3D.new();district.add_child(sun)
	var original_scale:float=root.scaling_3d_scale;var original_mode:int=root.scaling_3d_mode;var original_lod:float=root.mesh_lod_threshold
	var atmosphere:=A.new();atmosphere.setup(district)
	# Headless fixture: exercise the actual helper/restore code, no backend claim.
	atmosphere.software_gl=true;atmosphere.apple_software_basic=true
	atmosphere._original_render_scale=original_scale;atmosphere._original_scaling_mode=original_mode;atmosphere._original_mesh_lod_threshold=original_lod
	atmosphere._apply_software_viewport()
	if root.scaling_3d_scale!=.25 or root.mesh_lod_threshold!=8.0:push_error("Basic viewport setters failed");quit(1);return
	atmosphere.restore_original()
	if root.scaling_3d_scale!=original_scale or root.scaling_3d_mode!=original_mode or root.mesh_lod_threshold!=original_lod:push_error("Original viewport fields not restored");quit(1);return
	print("SCENE112_VIEWPORT_RESTORE_OK actual_scale=",root.scaling_3d_scale," actual_lod=",root.mesh_lod_threshold," scope=helper setter/restore fixture")
	district.queue_free();await process_frame;await process_frame;quit()
