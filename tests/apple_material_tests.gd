extends SceneTree
const Profile=preload("res://scripts/apple_software_materials.gd")
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func check(value:bool,label:String):
	if not value:push_error("APPLE_MATERIAL_FAIL "+label);failures+=1
	checks+=1
func run():
	var app:=Node3D.new();root.add_child(app)
	var world:=Node3D.new();app.add_child(world)
	var mesh:=MeshInstance3D.new();mesh.mesh=BoxMesh.new()
	var source:=StandardMaterial3D.new();source.resource_name="test source"
	source.normal_enabled=true;source.clearcoat_enabled=true;source.albedo_color=Color("428bd1")
	var image:=Image.create(2,2,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE)
	var texture:=ImageTexture.create_from_image(image)
	source.albedo_texture=texture;source.normal_texture=texture;source.roughness_texture=texture
	mesh.mesh.material=source;world.add_child(mesh)
	var p:=Profile.new();p.setup(app)
	var simple:=mesh.get_active_material(0) as StandardMaterial3D
	check(simple!=source and simple.shading_mode==BaseMaterial3D.SHADING_MODE_PER_VERTEX,"vertex shading on instance")
	check(not simple.normal_enabled and simple.normal_texture==null and simple.roughness_texture==null and not simple.clearcoat_enabled and simple.specular_mode==BaseMaterial3D.SPECULAR_DISABLED,"remove expensive fragment features")
	check(simple.albedo_texture==texture and simple.albedo_color==source.albedo_color,"retain real albedo")
	check(source.normal_enabled and source.normal_texture==texture and source.clearcoat_enabled,"cached source untouched")
	check(p.original_material(mesh,0)==source,"strong source retained for PBR validation")
	p.refresh();check(mesh.get_active_material(0)==simple,"stable identity on repeated refresh")
	var player:=MeshInstance3D.new();player.mesh=mesh.mesh;app.add_child(player)
	await process_frame;await process_frame
	check(player.get_active_material(0)!=source,"later player outside District included")
	var foreign:=StandardMaterial3D.new();foreign.albedo_color=Color.RED
	mesh.set_surface_override_material(0,foreign)
	p.restore()
	check(mesh.get_surface_override_material(0)==foreign,"restore preserves newer external override")
	check(player.get_surface_override_material(0)==null,"restore only own override to original null")
	p.setup(app);var active:=mesh.get_active_material(0)
	check(p.original_material(mesh,0)==foreign and active!=foreign,"adopt newer owner on refresh")
	mesh.material_override=source;p.refresh()
	check(p.original_material(mesh,0)==source and mesh.material_override!=source,"material override supersedes per-surface correctly")
	p.restore();check(mesh.material_override==source and mesh.get_surface_override_material(0)==foreign,"restore both owned slots")
	# Simulate a cached actor resource being reused after its first owner exits.
	mesh.material_override=null;p.setup(app);player.queue_free();await process_frame;p.refresh();p.restore()
	check(mesh.mesh.material==source and source.normal_texture==texture,"freed actor leaves cached asset valid")
	mesh.material_override=StandardMaterial3D.new()
	var retained: WeakRef = weakref(mesh.material_override)
	p.setup(app)
	check(retained.get_ref()!=null,"original override survives replacement through strong ownership")
	p.restore();check(mesh.material_override==retained.get_ref(),"live original override restored after all other references dropped")
	app.queue_free();await process_frame;p=null;simple=null;active=null;source=null;texture=null;image=null;foreign=null
	if failures==0:print("SCENE112_APPLE_MATERIAL_TESTS_OK checks=",checks)
	quit(1 if failures else 0)
