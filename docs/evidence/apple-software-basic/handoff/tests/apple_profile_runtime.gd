extends SceneTree
const SCENE=preload("res://scenes/main.tscn")
const COLLECTOR=preload("res://tests/apple_runtime_collector.gd")
const FORCED=preload("res://tests/forced_apple_atmosphere.gd")
var app:Node3D
var forced:=false
var start_ms:=0
func _initialize():call_deferred("run")
func run():
	start_ms=Time.get_ticks_msec()
	forced=OS.get_environment("SCENE112_FORCED_APPLE_PROFILE_FIXTURE")=="1"
	app=SCENE.instantiate();root.add_child(app);await process_frame
	if forced:
		# Select only the proposed profile on the existing real backend/node.
		# No adapter spoofing, replacement sky, or different scene resources.
		app.district.atmosphere.apple_software_basic=true
		app.district.atmosphere._apply_software_viewport()
		app.district.atmosphere.apply_conditions(app.district.atmosphere.conditions)
	var metadata:Dictionary={"forced_apple_profile_fixture":forced,"actual_adapter":RenderingServer.get_video_adapter_name(),
		"actual_renderer":RenderingServer.get_current_rendering_method(),"no_native_claim":true,"profile":app.district.atmosphere.diagnostics(),
		"source_geometry":_geometry_sources()}
	var file:=FileAccess.open("user://apple-profile-start.json",FileAccess.WRITE);file.store_string(JSON.stringify(metadata,"  "));file.close()
	print("SCENE112_PROFILE_FIXTURE=",JSON.stringify({"forced":forced,"actual_adapter":metadata.actual_adapter,"scale_getter":root.scaling_3d_scale,"lod_getter":root.mesh_lod_threshold}))
	var collector:=COLLECTOR.new();collector.report.profile_fixture=metadata
	await collector.run(app)

func _geometry_sources() -> Dictionary:
	var unique:Dictionary={};var result:Dictionary={"unique_meshes":0,"surface_count":0,"lod_surfaces":0,"lod_levels":0,"source_vertices":0,"source_indices":0,"glb_paths":[],"rigs":[],"collision_objects":0}
	for node:Node in _nodes(app):
		if node.scene_file_path.begins_with("res://assets/models/") and node.scene_file_path not in result.glb_paths:result.glb_paths.append(node.scene_file_path)
		if node is Skeleton3D:result.rigs.append({"name":node.name,"bones":node.get_bone_count()})
		if node is CollisionObject3D:result.collision_objects+=1
		if not node is MeshInstance3D or node.mesh==null or unique.has(node.mesh.get_instance_id()):continue
		unique[node.mesh.get_instance_id()]=true;result.unique_meshes+=1
		for index in node.mesh.get_surface_count():
			var surface:Dictionary=RenderingServer.mesh_get_surface(node.mesh.get_rid(),index)
			result.surface_count+=1;result.source_vertices+=int(surface.get("vertex_count",0));result.source_indices+=int(surface.get("index_count",0))
			var lods:Variant=surface.get("lods",[])
			if lods is Array and not lods.is_empty():result.lod_surfaces+=1;result.lod_levels+=lods.size()
	return result
func _nodes(root_node:Node) -> Array[Node]:
	var result:Array[Node]=[root_node]
	for child:Node in root_node.get_children():result.append_array(_nodes(child))
	return result
