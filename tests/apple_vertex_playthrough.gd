extends SceneTree
const Scene=preload("res://scenes/main.tscn")
const Atmosphere=preload("res://tests/forced_vertex_atmosphere.gd")
const Validation=preload("res://scripts/graphics_validation.gd")
func _initialize():call_deferred("run")
func run():
	var app:=Scene.instantiate();root.add_child(app);app.test_mode=true;await process_frame
	var original:Node=app.district.atmosphere
	original.restore_original();app.district.remove_child(original);original.free()
	app.district.atmosphere=Atmosphere.new();app.district.atmosphere.setup(app.district)
	print("SCENE112_APPLE_VERTEX_FIXTURE=",JSON.stringify({"actual_adapter":RenderingServer.get_video_adapter_name(),"forced":true,"native_claim":false,"diagnostics":app.district.atmosphere.diagnostics()}))
	var test:=Validation.new();await test.run(app)
