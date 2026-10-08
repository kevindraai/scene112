class_name AuthoredActor
extends Node3D
## Imported, source-authored metric mesh and deformation rig. Gameplay stays on
## the owning CharacterBody3D; animation has no root-motion/collision authority.

var uniform := false
var firefighter := false
var clothes := Color.WHITE
var skin := Color.WHITE
var model: Node3D
var animation: AnimationPlayer
var _clip := ""
var _tint_bindings: Array[Dictionary] = []

func _ready() -> void:
	var path := "res://assets/models/characters/officer.glb" if uniform else "res://assets/models/characters/civilian.glb"
	if firefighter: path = "res://assets/models/characters/fire_officer.glb"
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("AUTHORED_ACTOR_MISSING: " + path)
		return
	model = packed.instantiate()
	add_child(model)
	animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation == null:
		push_error("AUTHORED_ACTOR_RIG_MISSING")
		return
	for name: String in ["idle", "walk", "run", "carry"]:
		if not animation.has_animation(name):
			push_error("AUTHORED_ACTOR_CLIP_MISSING: " + name)
			continue
		animation.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	_tint(model)
	set_motion(0, false, false)

func _tint(node: Node) -> void:
	if node is MeshInstance3D:
		node.visibility_range_end = 90
		node.visibility_range_end_margin = 8
		for index in range(node.mesh.get_surface_count()):
			var original := node.get_active_material(index) as StandardMaterial3D
			if original == null: continue
			var tint := Color.WHITE
			if "skin" in original.resource_name.to_lower(): tint = Color.WHITE.lerp(skin, 0.25)
			elif not uniform and "cloth" in original.resource_name.to_lower(): tint = Color.WHITE.lerp(clothes, 0.35)
			if tint != Color.WHITE:
				var material := original.duplicate() as StandardMaterial3D
				material.albedo_color *= tint
				var previous: Material = node.get_surface_override_material(index)
				node.set_surface_override_material(index, material)
				_tint_bindings.append({"mesh": node, "surface": index, "material": material, "previous": previous})
	for child in node.get_children(): _tint(child)

func set_motion(speed: float, sprinting: bool = false, carrying: bool = false) -> void:
	if not is_instance_valid(animation): return
	var next := "carry" if carrying else ("idle" if speed < 0.12 else ("run" if sprinting else "walk"))
	if next != _clip:
		_clip = next
		animation.play(next, 0.16)
	if next == "idle": animation.speed_scale = 1
	elif carrying: animation.speed_scale = clampf(speed * 1.6 / 2.8, 0, 1.7)
	elif next == "run": animation.speed_scale = clampf(speed * 0.8 / 3.8, 0.6, 1.8)
	else: animation.speed_scale = clampf(speed * 1.6 / 2.5, 0.35, 2.8)

func diagnostics() -> Dictionary:
	var bones := 0
	if is_instance_valid(model):
		var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
		if skeleton != null: bones = skeleton.get_bone_count()
	return {"loaded": is_instance_valid(model), "clip": _clip, "bones": bones, "speed_scale": animation.speed_scale if is_instance_valid(animation) else 0.0}

func set_simulation_active(active: bool) -> void:
	if is_instance_valid(animation): animation.active = active

func _exit_tree() -> void:
	# Clear only our own overrides while their materials remain alive. A cached
	# imported mesh can outlive this actor; stale renderer material RIDs must not.
	for binding: Dictionary in _tint_bindings:
		var mesh := binding.mesh as MeshInstance3D
		if not is_instance_valid(mesh) or mesh.mesh == null: continue
		var surface: int = binding.surface
		if surface < mesh.mesh.get_surface_count() and mesh.get_surface_override_material(surface) == binding.material:
			mesh.set_surface_override_material(surface, binding.previous)
	_tint_bindings.clear()
