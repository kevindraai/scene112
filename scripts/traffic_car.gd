class_name TrafficCar
extends CharacterBody3D
## Bounded ambient traffic; physics/observation, never player input.

const BASE_MODEL := preload("res://assets/models/traffic/civilian_hatchback.glb")
const LOD_MODEL := preload("res://assets/models/traffic/civilian_hatchback_lod.glb")
const BODY_SIZE := Vector3(2.06,1.57,3.73)
const WHEEL_RADIUS := 0.315
const ACCELERATION := 2.4
const BRAKING := 5.2
const KEEP_GAP := 1.6
const MAX_PROBE := 11.0
const FADE_SECONDS := 0.55
const PHASES := ["moving","blocked","yielding","end_hold","fade_out","fade_in"]

var traffic_id := ""
var route: Dictionary = {}
var speed := 0.0
var distance_travelled := 0.0
var obstacle_gap := MAX_PROBE
var phase := "moving"
var cycles := 0
var wheel_phase := 0.0
var steering := 0.0
var director: Node3D
var _active := false
var _yield_hold := 0.0
var _fade_elapsed := 0.0
var _opacity := 1.0
var _direction := Vector3.ZERO
var _length := 0.0
var _collision: CollisionShape3D
var _sensor: BoxShape3D
var _models: Array[Node3D] = []
var _wheels: Array[Dictionary] = []
var _steer_pivots: Array[Array] = []
var _materials: Dictionary = {}
var _original_alpha: Dictionary = {}
var _original_transparency: Dictionary = {}
var _lod := 0


func configure(plan: Dictionary,owner_node: Node3D) -> void:
	route=plan.duplicate(true);traffic_id=str(route.id);director=owner_node
	_direction=(Vector3(route.end[0],route.end[1],route.end[2])-Vector3(route.start[0],route.start[1],route.start[2])).normalized()
	_length=start_position().distance_to(end_position())


func _ready() -> void:
	name="Traffic_"+traffic_id
	process_mode=Node.PROCESS_MODE_PAUSABLE
	collision_layer=1;collision_mask=1;safe_margin=.012;floor_snap_length=.3
	global_position=start_position();rotation.y=route_yaw()
	var shape:=BoxShape3D.new();shape.size=BODY_SIZE
	_collision=CollisionShape3D.new();_collision.shape=shape;_collision.position.y=BODY_SIZE.y/2
	add_child(_collision)
	_sensor=BoxShape3D.new();_sensor.size=Vector3(2.14,1.12,3.85)
	_load_model(BASE_MODEL);_load_model(LOD_MODEL)
	set_active(false)


func start_position() -> Vector3:
	return Vector3(float(route.start[0]),float(route.start[1]),float(route.start[2]))


func end_position() -> Vector3:
	return Vector3(float(route.end[0]),float(route.end[1]),float(route.end[2]))


func route_yaw() -> float:
	return atan2(-_direction.x,-_direction.z)


func set_active(active: bool) -> void:
	_active=active
	set_physics_process(active)


func _physics_process(delta: float) -> void:
	if not _active or not is_instance_valid(director):return
	_yield_hold=maxf(0,_yield_hold-delta)
	if director.should_yield(global_position):_yield_hold=1.0
	var progress:=clampf((global_position-start_position()).dot(_direction),0,_length)
	var remaining:=maxf(0,_length-progress)
	var look_ahead:=clampf(2.1+speed*.55,2.1,5.4)
	var target:=start_position()+_direction*minf(_length,progress+look_ahead)
	var desired:=target-global_position;desired.y=0
	var desired_yaw:=route_yaw() if desired.length()<.08 else atan2(-desired.x,-desired.z)
	var yaw_error:=wrapf(desired_yaw-rotation.y,-PI,PI)
	steering=clampf(yaw_error*.8,-.40,.40)
	var forward: Vector3=-global_basis.z
	obstacle_gap=measure_gap(global_position,rotation.y,MAX_PROBE,[get_rid()])
	if phase in ["fade_out","fade_in"]:
		_update_fade(delta)
		_update_wheels(0)
		_update_lod()
		return
	var cruise: float=route.cruise
	var target_speed:=minf(cruise,sqrt(2.0*BRAKING*maxf(0,remaining-.12)))
	var available:=maxf(0,obstacle_gap-KEEP_GAP)
	target_speed=minf(target_speed,sqrt(2.0*BRAKING*available))
	if _yield_hold>0:
		target_speed=0;phase="yielding"
	elif obstacle_gap<KEEP_GAP+.20:
		target_speed=0;phase="blocked"
	elif remaining<.35:
		target_speed=0;phase="end_hold"
	else:phase="moving"
	var rate:=BRAKING if target_speed<speed else ACCELERATION
	speed=move_toward(speed,target_speed,rate*delta)
	# Conservative yaw clearance stops rotation from clipping a roadside body.
	var yaw_step:=clampf(yaw_error,-.8*delta,.8*delta)*clampf(speed/2.5,0,1)
	if absf(yaw_step)>.00001 and pose_clear(global_position,rotation.y+yaw_step,[get_rid()]):rotation.y=wrapf(rotation.y+yaw_step,-PI,PI)
	forward=-global_basis.z
	velocity.x=forward.x*speed;velocity.z=forward.z*speed
	velocity.y=-.5 if is_on_floor() else velocity.y-20*delta
	var before:=global_position
	move_and_slide()
	var displacement:=global_position-before;displacement.y=0
	var travelled:=displacement.length()
	distance_travelled=minf(1000000,distance_travelled+travelled)
	speed=clampf(Vector2(velocity.x,velocity.z).dot(Vector2(forward.x,forward.z)),0,cruise)
	if travelled<.001 and target_speed>0:
		for index in get_slide_collision_count():
			var normal:=get_slide_collision(index).get_normal()
			if absf(normal.y)<.5 and normal.dot(forward)<-.2:phase="blocked";speed=0;break
	_update_wheels(travelled)
	_update_lod()
	if remaining<.35 and speed<.05 and _yield_hold==0 and obstacle_gap>KEEP_GAP+1 and director.can_recycle(self):
		phase="fade_out";_fade_elapsed=0;speed=0;velocity=Vector3.ZERO
	# A missing road/floor never triggers a hidden teleport. Stop for root QA.
	if global_position.y<-.5:
		speed=0;velocity=Vector3.ZERO;phase="blocked";set_physics_process(false)


func measure_gap(at: Vector3,yaw: float,probe_distance: float,exclude: Array[RID]) -> float:
	var space:=get_world_3d().direct_space_state
	var basis:=Basis(Vector3.UP,yaw)
	var forward: Vector3=-basis.z
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=_sensor
	query.transform=Transform3D(basis,at+Vector3(0,.90,0));query.collision_mask=1;query.exclude=exclude
	# cast_motion ignores initial overlaps; a separate actual overlap query
	# catches thin/narrow actors already inside the sensor envelope.
	if not space.intersect_shape(query,1).is_empty():return 0.0
	query.motion=forward*probe_distance
	var motion:=space.cast_motion(query)
	var gap:=probe_distance*float(motion[0]) if motion.size()==2 else 0.0
	var origin:=at+Vector3(0,.65,0)+forward*(BODY_SIZE.z/2+.02)
	var ray:=PhysicsRayQueryParameters3D.create(origin,origin+forward*probe_distance,1,exclude)
	var hit:=space.intersect_ray(ray)
	if not hit.is_empty():gap=minf(gap,origin.distance_to(hit.position))
	return clampf(gap,0,probe_distance)


func pose_clear(at: Vector3,yaw: float,exclude: Array[RID]) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=_collision.shape
	# Lift .04m to exclude the intended supporting flat ground.
	query.transform=Transform3D(Basis(Vector3.UP,yaw),at+Vector3(0,BODY_SIZE.y/2+.04,0))
	query.collision_mask=1;query.exclude=exclude
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()


func _update_fade(delta: float) -> void:
	if phase=="fade_out" and (_yield_hold>0 or obstacle_gap<KEEP_GAP+1 or not director.can_recycle(self)):
		phase="end_hold";_fade_elapsed=0;_set_opacity(1);return
	_fade_elapsed=minf(FADE_SECONDS,_fade_elapsed+delta)
	var fraction:=_fade_elapsed/FADE_SECONDS
	_set_opacity(1-fraction if phase=="fade_out" else fraction)
	if _fade_elapsed<FADE_SECONDS:return
	if phase=="fade_out":
		# Recheck physical spawn/observer conditions immediately before recycling.
		if not director.can_recycle(self):phase="end_hold";_set_opacity(1);return
		global_position=start_position();rotation.y=route_yaw();speed=0;velocity=Vector3.ZERO
		cycles=mini(10000,cycles+1);phase="fade_in";_fade_elapsed=0
	else:
		phase="moving";_fade_elapsed=0;_set_opacity(1)


func _update_wheels(travelled: float) -> void:
	if travelled!=0:wheel_phase=wrapf(wheel_phase-travelled/WHEEL_RADIUS,-PI,PI)
	for wheels: Dictionary in _wheels:
		for wheel: Node3D in wheels.values():wheel.rotation.x=wheel_phase
	for pivots: Array in _steer_pivots:
		for pivot: Node3D in pivots:pivot.rotation.y=steering


func _update_lod() -> void:
	var observer: Variant=director.observer_position()
	var next:=0
	if observer is Vector3:
		var distance:=global_position.distance_to(observer)
		next=1 if distance>(27.0 if _lod==0 else 23.0) else 0
	_lod=next
	for index in _models.size():_models[index].visible=index==_lod


func _load_model(packed: PackedScene) -> void:
	var model:=packed.instantiate() as Node3D;add_child(model);_models.append(model)
	var wheels: Dictionary={};var pivots: Array=[]
	for id: String in ["Wheel_LF","Wheel_RF","Wheel_LR","Wheel_RR"]:
		var wheel:=model.find_child(id,true,false) as Node3D
		if wheel==null:push_error("TRAFFIC_AXLE_MISSING "+id);continue
		wheels[id]=wheel
		if id.ends_with("F"):
			var parent:=wheel.get_parent();var pivot:=Node3D.new();pivot.name=id+"_Steering"
			pivot.transform=wheel.transform;parent.add_child(pivot);wheel.reparent(pivot,true);pivots.append(pivot)
	_wheels.append(wheels);_steer_pivots.append(pivots)
	_bind_materials(model)
	model.visible=_models.size()==1


func _bind_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh:=node as MeshInstance3D
		for index in mesh.mesh.get_surface_count():
			var original:=mesh.get_active_material(index) as StandardMaterial3D
			if original==null:continue
			var key:=original.resource_name
			if not _materials.has(key):
				_materials[key]=original.duplicate()
				_original_alpha[key]=original.albedo_color.a
				_original_transparency[key]=original.transparency
			# Reuse base material/texture resources for the separate LOD model.
			mesh.set_surface_override_material(index,_materials[key])
	for child: Node in node.get_children():_bind_materials(child)


func _set_opacity(value: float) -> void:
	_opacity=clampf(value,0,1)
	for key: String in _materials:
		var material: StandardMaterial3D=_materials[key]
		var colour:=material.albedo_color;colour.a=float(_original_alpha[key])*_opacity;material.albedo_color=colour
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA if _opacity<.999 else int(_original_transparency[key])


func serialize() -> Dictionary:
	return {"id":traffic_id,"position":[global_position.x,global_position.y,global_position.z],
		"yaw":wrapf(rotation.y,-PI,PI),"speed":speed,"distance":distance_travelled,"wheel_phase":wheel_phase,
		"steering":steering,"cycles":cycles,"phase":phase,"yield_hold":_yield_hold,"fade_elapsed":_fade_elapsed}


func apply_snapshot(data: Dictionary) -> void:
	global_position=Vector3(float(data.position[0]),float(data.position[1]),float(data.position[2]))
	rotation.y=float(data.yaw);speed=float(data.speed);distance_travelled=float(data.distance)
	wheel_phase=float(data.wheel_phase);steering=float(data.steering);cycles=int(data.cycles)
	phase=str(data.phase);_yield_hold=float(data.yield_hold);_fade_elapsed=float(data.fade_elapsed)
	velocity=-global_basis.z*speed
	_set_opacity(1-_fade_elapsed/FADE_SECONDS if phase=="fade_out" else(_fade_elapsed/FADE_SECONDS if phase=="fade_in" else 1.0))
	_update_wheels(0);_update_lod()


func diagnostics() -> Dictionary:
	return {"id":traffic_id,"phase":phase,"speed":speed,"position":global_position,
		"gap":obstacle_gap,"distance":distance_travelled,"wheel_phase":wheel_phase,"steering":steering,
		"cycles":cycles,"opacity":_opacity,"lod":_lod,"active":_active,"material_instances":_materials.size()}
