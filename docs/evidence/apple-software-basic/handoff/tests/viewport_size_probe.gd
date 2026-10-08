extends SceneTree
## Temporary independent diagnostic quad, never a production material replacement.
var results:Array=[]
func _initialize():call_deferred("run")
func run():
	for scale:float in [1.0,.5,.25]:
		var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720)
		viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		viewport.scaling_3d_mode=Viewport.SCALING_3D_MODE_BILINEAR;viewport.scaling_3d_scale=scale
		root.add_child(viewport)
		var camera:=Camera3D.new();camera.current=true;camera.position.z=2;viewport.add_child(camera)
		var mesh:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(2,2);mesh.mesh=quad
		var shader:=Shader.new();shader.code="""
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
void vertex(){POSITION=vec4(VERTEX.xy,0.0,1.0);}
void fragment(){
 int stripe=int(clamp(floor(UV.x*34.0),0.0,33.0));
 float value=0.0;
 if(stripe==1){value=1.0;}
 else if(stripe>=2){int bit=stripe-2;int dimension=int(VIEWPORT_SIZE.x);if(bit>=16){dimension=int(VIEWPORT_SIZE.y);bit-=16;}value=((dimension & (1<<bit))!=0)?1.0:0.0;}
 ALBEDO=vec3(value);
}
"""
		var material:=ShaderMaterial.new();material.shader=shader;mesh.material_override=material;viewport.add_child(mesh)
		for n in 3:await process_frame;await RenderingServer.frame_post_draw
		var image:=viewport.get_texture().get_image()
		var y:=image.get_height()/2
		var black:=image.get_pixel(int(.5*1280/34),y).r;var white:=image.get_pixel(int(1.5*1280/34),y).r
		if white-black<.25:
			push_error("Invalid viewport diagnostic contrast: quad not rendered");quit(1);return
		var threshold:float=(black+white)/2
		var width:=0;var height:=0
		for bit in 32:
			var pixel:=image.get_pixel(int((bit+2.5)*1280/34),y)
			if pixel.r>threshold:
				if bit<16:width|=1<<bit
				else:height|=1<<(bit-16)
		var value:Dictionary={"scope":"independent binary shader VIEWPORT_SIZE readback; real backend",
			"scale_getter":viewport.scaling_3d_scale,"output_texture_size":[image.get_width(),image.get_height()],
			"shader_viewport_size":[width,height],"black_reference":black,"white_reference":white,
			"actual_adapter":RenderingServer.get_video_adapter_name(),"actual_renderer":RenderingServer.get_current_rendering_method()}
		print("SCENE112_VIEWPORT_SIZE=",JSON.stringify(value));results.append(value)
		viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;viewport.queue_free();await process_frame;await process_frame
	var file:=FileAccess.open("res://validation/viewport-size-readback.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
	quit()
