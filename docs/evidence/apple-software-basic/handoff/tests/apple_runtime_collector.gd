extends "res://scripts/graphics_validation.gd"
## Read-only frame samples around unchanged real walking/driving validation.
func _stage(value:String) -> void:
	super._stage(value)
	if not report.has("frame_samples"):report.frame_samples=[]
	if not is_instance_valid(app):return
	var viewport:Viewport=app.get_viewport()
	report.frame_samples.append({"stage":value,"scale":viewport.scaling_3d_scale,"mesh_lod_threshold":viewport.mesh_lod_threshold,
		"primitives":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"objects":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
		"actual_adapter":RenderingServer.get_video_adapter_name()})
