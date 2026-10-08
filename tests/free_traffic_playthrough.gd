extends SceneTree
## Integrated real-input campaign + two free traffic calls. Queue/time and
## between-stop poses are declared fixtures; driving/cones/sources/PV are real.
const Scene = preload("res://scenes/main.tscn")
const SAVE := "user://validation-free-traffic.json"
var app: Node3D
var police: RefCounted
var movement: RefCounted
var archived: Dictionary
func _initialize() -> void: call_deferred("run")

func run() -> void:
	app=Scene.instantiate();root.add_child(app);await process_frame
	app.test_mode=true;app._test_timeout(360)
	police=load("res://scripts/police_validation.gd").new();police._app=app
	movement=load("res://scripts/fire_validation.gd").new();movement.app=app
	_cleanup()
	# Earn the original campaign archive through actual scene/input actions;
	# no completed-case or score fixture is injected into this test.
	if not app._press_menu("Nieuwe campagne · De eerste dienst"): return
	print("FREE_TRAFFIC_STAGE=original_campaign")
	if not await _scene_actions(): return
	if not await police._open_report(): return
	if not police._edit_categories(false) or not police._order_cards(): return
	if not app._press_menu("Rapport ter beoordeling indienen"): return
	if not app._check(app.state.campaign_stage==1 and app.police_model.result=="careful","Actual completed campaign establishes archival history"): return
	archived=app.state.police_campaign.duplicate(true)
	if not app._press_menu("Dienst vervolgen"): return
	if not await app._tap_action("pause",func():return app._menu_title_is("Dienstpauze"),"Actual menu transition to free duty"):return
	if not app._press_menu("Naar hoofdmenu"):return
	if not app._press_menu("Vrije politiedienst"):return
	if not _archive_unchanged("free duty entry"):return
	if not await app._test_station("equipment"):return
	if not await app._test_station("radio"):return
	# Only shorten the deterministic queue. Each offer is handed over/accepted
	# with the real radio UI, and no incident status/outcome is assigned here.
	app.ledger.start(2,"police")
	if not await _next_traffic(-1):return
	var first_variant: int=app.police_model.variant
	var first_source: String=app.police_model.person_data("lotte").source
	print("FREE_TRAFFIC_STAGE=first_call variant=",first_variant," source=",first_source)
	if not await _scene_actions():return
	if not await _free_report():return
	if not police._edit_categories(true) or not police._order_cards():return
	if not app._press_menu("Rapport ter beoordeling indienen"):return
	if not app._check(app.police_model.result=="wrong" and app.ledger.incident.phase=="accepted","Wrong free PV remains correctable and does not auto-resolve dispatch"):return
	if not app._press_menu("Concept verbeteren"):return
	if not police._edit_categories(false) or not police._order_cards():return
	var draft: Array=app.police_ui.capture_draft()
	var before: Dictionary=app.police_model.to_dict()
	app.save_game(SAVE)
	if not app._check(FileAccess.file_exists(SAVE),"Actual root save writes free draft with dispatch/source state"):return
	if not police._edit_categories(true):return
	app.start_training("fire")
	app.load_game(SAVE)
	if not app._check(movement._same_snapshot(before,app.police_model.to_dict()) and movement._same_snapshot(draft,app.police_ui.capture_draft()),"Load restores exact free case/draft after another role reset"):return
	if not _archive_unchanged("free draft reload"):return
	if not await _free_report():return
	if not app._press_menu("Rapport ter beoordeling indienen"):return
	if not app._check(app.police_model.result=="careful" and app.police_model.phase=="completed" and app.ledger.incident.phase=="resolved" and app.ledger.incident.quality==100 and app.ledger.completed==1,"Corrected real free PV resolves matching dispatch at100 without campaign advancement"):return
	if not _archive_unchanged("first free completion"):return
	if DisplayServer.get_name()!="headless":await movement._capture("free-traffic-corrected")
	if not app._press_menu("Dienst vervolgen"):return
	if not await _next_traffic(first_variant):return
	if not app._check(app.police_model.variant!=first_variant and app.police_model.person_data("lotte").source!=first_source,"A later actual accepted call uses a different sourced adult variant"):return
	# Reset only the vehicle's travel start pose between calls; its >20m drive,
	# brake/exit and every scene action are repeated by actual input below.
	var car: Node3D=app.district.objects.police_car
	car.position=Vector3(2,.1,9);car.rotation.y=PI/2;car.speed=0;car.velocity=Vector3.ZERO
	app.police_ui._drive_start=car.global_position
	print("FREE_TRAFFIC_STAGE=repeat_call variant=",app.police_model.variant)
	if not await _scene_actions():return
	if not await _free_report():return
	if not police._edit_categories(true) or not police._order_cards():return
	if not app._press_menu("Rapport ter beoordeling indienen"):return
	var bad_score: Dictionary=app.police_model.report_score.duplicate(true)
	if not app._check(bad_score.result=="wrong" and app.police_model.phase!="completed","Second poor report exposes its actual consequence"):return
	if not app._press_menu("Afsluiten met deze tekortkomingen"):return
	if not app._check(app.police_model.phase=="completed" and app.police_model.result=="wrong" and app.ledger.incident.phase=="resolved" and app.ledger.incident.quality==int(bad_score.score) and app.ledger.completed==2,"Explicit deficient closure keeps score and resolves only matching free incident"):return
	if not app._check(app._menu_title_is("Rapportbeoordeling") and not police._has_button("Concept verbeteren"),"Closed deficient report is read-only in the real UI"):return
	if not _archive_unchanged("wrong free closure"):return
	before=app.police_model.to_dict()
	app.save_game(SAVE)
	app.start_training("fire")
	app.load_game(SAVE)
	if not app._check(movement._same_snapshot(before,app.police_model.to_dict()) and app.ledger.completed==2 and app.police_model.closed,"Completed deficient source history/dispatch survives actual root load"):return
	if not _archive_unchanged("completed free reload"):return
	if not await _free_report():return
	if DisplayServer.get_name()!="headless":await movement._capture("free-traffic-closed-wrong")
	_cleanup()
	print("SCENE112_FREE_TRAFFIC_PLAY_OK actual campaign archive, R offer/handover/accept, two variant cases, 3xdrive>20m, camera/Q cones, E observed sources/two adult statements, PVwrong/correction and explicit wrongclosure, dispatch, save/load, archives preserved; deterministic queue/time and travel pose fixtures")
	app._test_finished=true
	await app.quit_game(0)

func _archive_unchanged(label: String) -> bool:
	return app._check(app.state.campaign_stage==1 and app.state.course_passes.is_empty() and movement._same_snapshot(archived,app.state.police_campaign),"Original campaign/source archive unchanged: "+label)

func _next_traffic(previous_variant: int) -> bool:
	for offered in range(8):
		var advance: float=maxf(.02,float(app.ledger.next_report)-float(app.ledger.duty_time)+.02)
		app.ledger.tick(advance)
		await process_frame;await process_frame
		if not app._check(app.ledger.incident.phase=="offered","Deterministic queue produces an actual offered incident"):return false
		if not await app._tap_action("radio",func():return app._menu_title_is("Meldkamer"),"Actual R radio for next free offer"):return false
		if app.ledger.incident.kind=="traffic" and int(app.ledger.incident.variant)!=previous_variant:
			if not app._press_menu("Melding aannemen"):return false
			return await app._wait_for(func():return app.police_model.mode=="free" and app.ledger.incident.phase=="accepted" and app.police_model.incident_id==app.ledger.serial,"Root accepts matching free traffic case")
		if not app._press_menu("Doorgeven aan andere eenheid"):return false
	return app._check(false,"A varied traffic offer must occur within the deterministic queue")

func _scene_actions() -> bool:
	if not app.state.equipment:
		if not await app._test_station("equipment"):return false
	if not app.state.radio_checked:
		if not await app._test_station("radio"):return false
	var car: Node3D=app.district.objects.police_car
	car.rotation.y=PI/2
	movement._fixture(car.to_global(Vector3(1.8,.1,0)))
	if not await app._wait_for(func():return app.current_target.get("id")=="police_car","Real car entry proximity",10):return false
	if not await app._tap_action("interact",func():return app.state.occupied_vehicle=="police_car","Real free/campaign vehicle entry"):return false
	var start: Vector3=car.position
	Input.action_press("move_forward")
	var driven: bool=await app._wait_for(func():return car.position.x < -23,"Actual scene drive past20m",40)
	Input.action_release("move_forward")
	if not driven:return false
	Input.action_press("brake")
	var stopped: bool=await app._wait_for(func():return absf(car.speed)<.1,"Actual car brake before exit",20)
	Input.action_release("brake")
	if not stopped or not app._check(car.position.distance_to(start)>20,"Observed physical body travel over20m"):return false
	if not await app._tap_action("interact",func():return app.state.occupied_vehicle.is_empty(),"Actual safe scene exit"):return false
	if not await app._wait_for(func():return app.police_model.basics.exit,"Controller confirms actual prepare/drive/exit sequence",10):return false
	for zone: Vector3 in app.police_site.CONE_ZONES:
		movement._fixture(zone+Vector3(0,.1,1.5))
		if not await _aim_at_ground(zone):return false
		var count: int=app.police_model.cones.size()
		if not await app._tap_action("place_cone",func():return app.police_model.cones.size()==count+1,"Actual officer camera Q cone raycast"):return false
	var points: Dictionary={"pc_damage":Vector3(-15.4,.1,18),"pc_tracks":Vector3(-20,.1,13.7),"pc_signal":Vector3(-21.5,.1,19.2)}
	for id: String in points:
		movement._fixture(points[id])
		if not await app._wait_for(func():return app.current_target.get("id")==id,"Actual scene source proximity "+id,10):return false
		var count: int=app.police_model.observations.size()
		if not await app._tap_action("interact",func():return app.police_model.observations.size()==count+1,"Actual E source "+id):return false
	for id: String in ["pc_lotte","pc_bram"]:
		movement._fixture(app.district.objects[id].global_position+Vector3(0,.1,1.5))
		if not await app._wait_for(func():return app.current_target.get("id")==id,"Actual adult proximity "+id,10):return false
		if not await app._tap_action("interact",func():return app.paused,"Actual E adult conversation"):return false
		var person_id: String="lotte" if id=="pc_lotte" else "bram"
		if not app._check(app._menu_title_is(str(app.police_model.person_data(person_id).source)),"Actual dialogue title uses variant adult source"):return false
		if not app._press_menu("Open vraag: vertel wat er gebeurde"):return false
		if not app._press_menu("Terug naar de locatie"):return false
	return app._check(app.police_model.can_report(),"Real observation/conversation work unlocks free PV")

func _aim_at_ground(zone: Vector3) -> bool:
	# Camera direction changes through the same mouse event as player input.
	await app._test_frames(3)
	var officer: Node3D = app.officer
	var offset := zone - officer.global_position
	var yaw := atan2(-offset.x, -offset.z)
	var height: float = officer._pivot.global_position.y - zone.y
	var pitch := -atan2(height, Vector2(offset.x, offset.z).length())
	if not app._check(pitch >= -0.95 and pitch <= 0.32, "cone is reachable within actual officer pitch limits"): return false
	# Viewport scaling can transform a synthetic motion. Small actual events
	# converge using camera feedback, rather than assigning camera transforms.
	for attempt in range(120):
		var yaw_error := wrapf(float(officer._pivot.rotation.y) - yaw, -PI, PI)
		var pitch_error: float = float(officer._pitch) - pitch
		if absf(yaw_error) < 0.01 and absf(pitch_error) < 0.01: break
		var motion := InputEventMouseMotion.new()
		var step := Vector2(yaw_error, pitch_error) * 0.25 / float(officer.sensitivity)
		motion.relative = Vector2(clampf(step.x, -15, 15), clampf(step.y, -15, 15))
		app.get_viewport().push_input(motion, true)
		await app._test_frames(1)
	await app._test_frames(2)
	print("FREE_TRAFFIC_CAMERA viewport=", app.get_viewport().get_visible_rect().size, " actual_pitch=", officer._pitch, " target_pitch=", pitch, " actual_yaw=", officer._pivot.rotation.y, " target_yaw=", yaw)
	return app._check(officer.camera.current and absf(float(officer._pitch) - pitch) < 0.02 and absf(wrapf(float(officer._pivot.rotation.y) - yaw, -PI, PI)) < 0.02, "real mouse motion aims the active SpringArm camera")


func _free_report() -> bool:
	if not await app._tap_action("radio",func():return app._menu_title_is(app.police_model.case_title()),"Actual R free traffic plan"):return false
	return app._press_menu("Proces-verbaal opstellen")

func _cleanup() -> void:
	for suffix: String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(SAVE+suffix):DirAccess.remove_absolute(SAVE+suffix)
