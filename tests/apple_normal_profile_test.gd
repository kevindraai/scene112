extends SceneTree
const Scene=preload("res://scenes/main.tscn")
const Validation=preload("res://scripts/graphics_validation.gd")
func _initialize():call_deferred("run")
func run():
	var app:=Scene.instantiate();root.add_child(app);app.test_mode=true;await process_frame
	var atmosphere:Node=app.district.atmosphere
	if atmosphere.apple_software_basic or atmosphere._apple_materials!=null:push_error("NORMAL_PROFILE unexpectedly enabled Apple material overrides");quit(1);return
	var validation:=Validation.new();validation.app=app
	if not validation._inspect_models():return
	app._test_finished=true
	print("SCENE112_NORMAL_MATERIAL_PROFILE_OK source_pbr_checks=",validation.checks)
	await app.quit_game(0)
