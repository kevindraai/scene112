class_name DistrictTraffic
extends Node3D
## At most three original hatchbacks on existing straight road lanes.

const CAR := preload("res://scripts/traffic_car.gd")
const MAX_CARS := 3
const SCHEMA := 1
const RECYCLE_DISTANCE := 35.0
const DEFAULT_ROUTES := [
	{"id":"east","start":[-60.0,.03,19.0],"end":[60.0,.03,19.0],"cruise":5.2},
	{"id":"west","start":[60.0,.03,15.0],"end":[-60.0,.03,15.0],"cruise":4.8}]
var cars: Array[CharacterBody3D] = []
var _routes: Array = []
var _active := false
var _emergency: Array[Vector3] = []
var _observer: Node3D
var _observer_override: Variant = null


func setup_routes(district: Node3D,config: Array = []) -> bool:
	var plans: Array=DEFAULT_ROUTES.duplicate(true) if config.is_empty() else config.duplicate(true)
	if not is_instance_valid(district) or district==self or is_ancestor_of(district) or not _valid_routes(plans):return false
	plans=_canonical_routes(plans)
	if not district.is_inside_tree() or not _spawn_poses_clear(district,plans):return false
	clear()
	if get_parent()==null:district.add_child(self)
	elif get_parent()!=district:reparent(district,false)
	name="DistrictTraffic";transform=Transform3D.IDENTITY;process_mode=Node.PROCESS_MODE_PAUSABLE
	_routes=plans
	for plan: Dictionary in plans:
		var car:=CAR.new();car.configure(plan,self);add_child(car);cars.append(car)
	set_simulation_active(false)
	return true


func set_simulation_active(active: bool) -> void:
	_active=active
	for car: CharacterBody3D in cars:car.set_active(active)


func set_observer(observer: Node3D) -> void:
	_observer=observer;_observer_override=null


func set_observer_position(position: Variant) -> bool:
	if position==null:_observer_override=null;return true
	var value: Variant=_vector(position)
	if not value is Vector3:return false
	_observer_override=value
	return true


func observer_position() -> Variant:
	if _observer_override is Vector3:return _observer_override
	if is_instance_valid(_observer) and _observer.is_inside_tree():return _observer.global_position
	var camera:=get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if is_instance_valid(camera) else null


func update_emergency_context(context: Dictionary) -> bool:
	# One service DTO or up to two service vehicles. Sound stays in AudioDirector.
	if context.is_empty():_emergency.clear();return true
	if context.has("vehicles") and not context.vehicles is Array:return false
	var entries: Array=context.vehicles if context.has("vehicles") else [context]
	if entries.size()>2:return false
	var next: Array[Vector3]=[]
	for entry: Variant in entries:
		if not entry is Dictionary:return false
		var enabled: Variant=entry.get("active",entry.get("siren",false))
		if not enabled is bool:return false
		if not enabled:continue
		var at: Variant=_vector(entry.get("position",null))
		if not at is Vector3:return false
		next.append(at)
	_emergency=next
	return true


func should_yield(at: Vector3) -> bool:
	for emergency: Vector3 in _emergency:
		if Vector2(at.x,at.z).distance_to(Vector2(emergency.x,emergency.z))<22.0:return true
	return false


func can_recycle(car: CharacterBody3D) -> bool:
	var observer: Variant=observer_position()
	if not observer is Vector3 or should_yield(car.global_position):return false
	var remaining: float=(car.end_position()-car.global_position).dot((car.end_position()-car.start_position()).normalized())
	if remaining>.4 or remaining<-.4 or car.speed>.05 or car.obstacle_gap<CAR.KEEP_GAP+1:return false
	var start: Vector3=car.start_position()
	if car.global_position.distance_to(observer)<RECYCLE_DISTANCE or start.distance_to(observer)<RECYCLE_DISTANCE:return false
	var exclude: Array[RID]=[car.get_rid()]
	if not car.pose_clear(start,car.route_yaw(),exclude):return false
	return car.measure_gap(start,car.route_yaw(),5.0,exclude)>3.0


func serialize() -> Dictionary:
	var states: Array=[]
	for car: CharacterBody3D in cars:states.append(car.serialize())
	return {"schema":SCHEMA,"active":_active,"routes":_routes.duplicate(true),"cars":states}


func restore(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=4 or not _number(data.get("schema"),SCHEMA,SCHEMA) or not data.get("active") is bool:return false
	if not data.get("routes") is Array or not _valid_routes(data.routes) or _canonical_routes(data.routes)!=_routes:return false
	if not data.get("cars") is Array or data.cars.size()!=cars.size():return false
	var expected: Dictionary={}
	var exclude: Array[RID]=[]
	for car: CharacterBody3D in cars:expected[car.traffic_id]=car;exclude.append(car.get_rid())
	var checked: Dictionary={}
	for state: Variant in data.cars:
		if not state is Dictionary or state.size()!=11:return false
		if not state.get("id") is String:return false
		var id: String=state.id
		if not expected.has(id) or checked.has(id) or not _valid_state(state,expected[id]):return false
		var at: Variant=_vector(state.position)
		if not expected[id].pose_clear(at,float(state.yaw),exclude):return false
		for previous: Dictionary in checked.values():
			if _poses_overlap(state,previous):return false
		checked[id]=state
	# Atomic application only after all finite/type/route/space checks pass.
	set_simulation_active(false)
	for id: String in checked:expected[id].apply_snapshot(checked[id])
	_emergency.clear()
	set_simulation_active(bool(data.active))
	return true


func clear() -> void:
	set_simulation_active(false)
	for car: CharacterBody3D in cars:
		if is_instance_valid(car):remove_child(car);car.queue_free()
	cars.clear();_routes.clear();_emergency.clear()


func _valid_routes(plans: Array) -> bool:
	if plans.is_empty() or plans.size()>MAX_CARS:return false
	var ids: Dictionary={}
	for plan: Variant in plans:
		if not plan is Dictionary or plan.size()!=4:return false
		var id: Variant=plan.get("id")
		if not id is String or id.is_empty() or id.length()>20 or ids.has(id):return false
		var start: Variant=_vector(plan.get("start"));var finish: Variant=_vector(plan.get("end"))
		if not start is Vector3 or not finish is Vector3 or not _number(plan.get("cruise"),2,6):return false
		if absf(start.y-.03)>.0001 or absf(finish.y-.03)>.0001 or start.distance_to(finish)<20:return false
		var main_lane:=is_equal_approx(start.z,finish.z) and (is_equal_approx(start.z,15) or is_equal_approx(start.z,19)) and absf(start.x)<=64 and absf(finish.x)<=64
		var side_lane:=is_equal_approx(start.x,finish.x) and (is_equal_approx(start.x,-18) or is_equal_approx(start.x,-22)) and absf(start.z)<=64 and absf(finish.z)<=64
		if not main_lane and not side_lane:return false
		if main_lane and ((finish.x>start.x)!=(start.z>17)):return false
		if side_lane and ((finish.z>start.z)!=(start.x<-20)):return false
		ids[id]=true
	return true


func _valid_state(state: Dictionary,car: CharacterBody3D) -> bool:
	var at: Variant=_vector(state.get("position"))
	if not at is Vector3 or at.y<-.25 or at.y>.5:return false
	var start: Vector3=car.start_position();var finish: Vector3=car.end_position();var direction: Vector3=(finish-start).normalized()
	var projection: float=(at-start).dot(direction)
	var side: Vector3=at-start-direction*projection;side.y=0
	if projection<-.3 or projection>start.distance_to(finish)+.4 or side.length()>.65:return false
	for bounds in [["yaw",-PI,PI],["speed",0,6],["distance",0,1000000],["wheel_phase",-PI,PI],["steering",-.4,.4],["cycles",0,10000],["yield_hold",0,1],["fade_elapsed",0,CAR.FADE_SECONDS]]:
		if not _number(state.get(bounds[0]),float(bounds[1]),float(bounds[2])):return false
	if float(state.speed)>float(car.route.cruise)+.01 or float(state.cycles)!=floor(float(state.cycles)):return false
	if not state.get("phase") is String or state.phase not in CAR.PHASES:return false
	if absf(wrapf(float(state.yaw)-car.route_yaw(),-PI,PI))>.40:return false
	if state.phase=="fade_out" and (projection<_length_of(car)-.6 or float(state.speed)>.05 or float(state.yield_hold)>0):return false
	if state.phase=="fade_in" and (projection>.4 or float(state.speed)>.05):return false
	return true


func _vector(value: Variant) -> Variant:
	if value is Vector3:return value if value.is_finite() and value.length()<300 else null
	if not value is Array or value.size()!=3:return null
	for coordinate: Variant in value:
		if not _number(coordinate,-200,200):return null
	return Vector3(float(value[0]),float(value[1]),float(value[2]))


func _number(value: Variant,low: float,high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high


func _length_of(car: CharacterBody3D) -> float:
	return car.start_position().distance_to(car.end_position())


func _poses_overlap(a: Dictionary,b: Dictionary) -> bool:
	# Rectangle SAT accepts the actual 4m opposing-lane spacing, unlike circles.
	var delta: Vector3=_vector(b.position)-_vector(a.position)
	var first:=Basis(Vector3.UP,float(a.yaw));var second:=Basis(Vector3.UP,float(b.yaw))
	var half_x: float=CAR.BODY_SIZE.x/2+.015;var half_z: float=CAR.BODY_SIZE.z/2+.015
	for axis: Vector3 in [first.x,first.z,second.x,second.z]:
		var extent_a:=absf(first.x.dot(axis))*half_x+absf(first.z.dot(axis))*half_z
		var extent_b:=absf(second.x.dot(axis))*half_x+absf(second.z.dot(axis))*half_z
		if absf(delta.dot(axis))>=extent_a+extent_b:return false
	return true


func _canonical_routes(plans: Array) -> Array:
	var result: Array=[]
	for plan: Dictionary in plans:
		var start: Vector3=_vector(plan.start);var finish: Vector3=_vector(plan.end)
		result.append({"id":str(plan.id),"start":[float(start.x),float(start.y),float(start.z)],
			"end":[float(finish.x),float(finish.y),float(finish.z)],"cruise":float(plan.cruise)})
	return result


func _spawn_poses_clear(district: Node3D,plans: Array) -> bool:
	var exclude: Array[RID]=[]
	for car in cars:exclude.append(car.get_rid())
	var shape:=BoxShape3D.new();shape.size=CAR.BODY_SIZE
	var previous: Array=[]
	for plan: Dictionary in plans:
		var at: Vector3=_vector(plan.start);var direction: Vector3=(_vector(plan.end)-at).normalized()
		var yaw:=atan2(-direction.x,-direction.z)
		var pose: Dictionary={"position":at,"yaw":yaw}
		for prior: Dictionary in previous:
			if _poses_overlap(pose,prior):return false
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=1;query.exclude=exclude
		query.transform=Transform3D(Basis(Vector3.UP,yaw),at+Vector3(0,CAR.BODY_SIZE.y/2+.04,0))
		if not district.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return false
		previous.append(pose)
	return true
