extends SceneTree
const SCENE=preload("res://scenes/main.tscn")
var app:Node3D
func _initialize():call_deferred("run")
func run():
	app=SCENE.instantiate();root.add_child(app);await process_frame
	app.start_new("police");app.officer.global_position=Vector3(-2,.1,38)
	app.officer._pivot.rotation.y=PI;app.officer._pitch=-.1;app.officer._pivot.rotation.x=-.1
	for n in 6:await physics_frame
	app._freeze()
	var original_scale:float=root.scaling_3d_scale;var original_lod:float=root.mesh_lod_threshold
	var results:Array=[]
	for pair:Array in [[.5,1.0],[.25,1.0],[.25,8.0],[.25,16.0]]:
		root.scaling_3d_scale=float(pair[0]);root.mesh_lod_threshold=float(pair[1])
		for n in 8:await process_frame
		var samples:Array=[];var primitives:Array=[];var draws:Array=[]
		var before:=Time.get_ticks_usec()
		for n in 24:
			await process_frame
			var now:=Time.get_ticks_usec();samples.append((now-before)/1000.0);before=now
			primitives.append(root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
			draws.append(root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		samples.sort();primitives.sort();draws.sort()
		var info:Dictionary={"scope":"static actual street, paused via production app; explicit scale/LOD axis fixtures",
			"actual_adapter":RenderingServer.get_video_adapter_name(),"actual_renderer":RenderingServer.get_current_rendering_method(),
			"scale_getter":root.scaling_3d_scale,"lod_getter":root.mesh_lod_threshold,
			"frame_interval_p50_ms":samples[12],"frame_interval_p95_ms":samples[22],
			"visible_primitives_median":primitives[12],"visible_draw_calls_median":draws[12],"sample_count":24,"no_native_claim":true}
		print("SCENE112_LOD_SCALE=",JSON.stringify(info));results.append(info)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://validation/scale-"+str(pair[0])+"-lod-"+str(pair[1])+".png")
	root.scaling_3d_scale=original_scale;root.mesh_lod_threshold=original_lod
	var output:=FileAccess.open("res://validation/lod-scale.json",FileAccess.WRITE);output.store_string(JSON.stringify(results,"  "));output.close()
	await app.quit_game()
