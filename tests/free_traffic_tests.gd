extends SceneTree

const Case = preload("res://scripts/police_case.gd")
const Legacy = preload("res://scripts/police_case_v1.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text);push_error(text)
func rejected(model: RefCounted, data: Variant, text: String) -> void:
	var before: Dictionary=model.to_dict()
	check(not model.restore(data),text)
	check(model.to_dict()==before,text+" remains atomic")
func road(model: RefCounted) -> void:
	for step: String in Case.BASIC_STEPS:
		model.tick(1);check(model.complete_step(step),"Controller-confirmed preparation: "+step)
	for at: Vector3 in Case.CONE_TARGETS:
		model.tick(1);check(model.place_cone(at).ok,"Physical cone in distinct safe zone")
	for id: String in ["damage","marks","road"]:
		model.tick(1);check(model.record_observation(id),"Capture selected variant observation "+id)
	for id: String in ["lotte","bram"]:
		model.tick(1);check(model.speak(id,"open").ok,"Open adult statement from current person "+id)
	model.tick(1)
func cards(model: RefCounted) -> Array:
	var sources: Array=model.report_cards()
	sources.sort_custom(func(a,b):return float(a.time)<float(b.time))
	var result: Array=[]
	for source: Dictionary in sources:
		if source.id!="conclusion_guilt":result.append({"id":source.id,"category":source.category})
	return result
func _initialize() -> void:
	var model:=Case.new()
	check(not model.begin("free"),"Free cases require incident identity and variant")
	for invalid in [0,-1,1.5,NAN,INF,true,"3",null,10_000_001]:
		var before:=model.to_dict()
		check(not model.begin_free(invalid,0) and model.to_dict()==before,"Reject invalid incident ID atomically: "+str(invalid))
	for invalid in [-1,3,.25,NAN,INF,false,"1",null]:
		var before:=model.to_dict()
		check(not model.begin_free(1,invalid) and model.to_dict()==before,"Reject invalid variant atomically: "+str(invalid))
	check(model.begin_free(12.0,0.0),"Integral JSON numbers accepted")
	check(not model.finalize_report().ok and not model.closed,"Cannot close before submitting a report")
	check(not model.place_cone(Case.CONE_TARGETS[0]).ok and not model.speak("driver","open").ok,"Free case preserves preparation/safety constraints")
	check(model.submit_report([]).score<50 and model.report_score.is_empty(),"Free mode cannot replace scene work with paperwork")
	var names: Dictionary={}
	for variant in range(3):
		check(model.begin_free(40+variant,variant),"Begin original variant "+str(variant))
		check(model.mode=="free" and model.incident_id==40+variant and model.variant==variant and not model.closed,"Precise incident metadata")
		check(not model.case_title().is_empty(),"Scenario title available")
		for id: String in ["lotte","bram"]:
			var person:=model.person_data(id)
			check(person.age>=18 and person.age<=100,"Adult person with explicit age")
			check(not names.has(person.source),"Distinct sourced adult across variants")
			names[person.source]=true
			check(not person.motive.is_empty(),"Contextual motive kept apart from evidence")
			person.source="tampered"
			person.position[0]=0
			check(model.person_data(id).source!="tampered" and model.person_data(id).position[0]!=0,"Exposed dialogue data is deep copied")
		var observed:=model.observation_data()
		observed.road.text="tampered"
		check(model.observation_data("pc_signal").text!="tampered","Observation dictionary copy isolated")
		check(model.person_data("missing").is_empty() and model.observation_data("missing").is_empty(),"Unknown physical source has no substitute data")
		road(model)
		check(model.statements.lotte.source==model.person_data("driver").source,"Saved declaration belongs to current driver")
		check(model.statements.bram.text==model.person_data("witness").open,"Saved witness limits are the actual original statement")
		check(model.observations.road.text==model.observation_data("road").text,"Wet patch observation never derives weather as cause")
		var rows:=cards(model)
		check(model.score_report(rows).result=="careful","Careful outcome without confession, variant "+str(variant))
		var restored:=Case.new()
		check(restored.restore(JSON.parse_string(JSON.stringify(model.to_dict()))),"Active source/time/location JSON roundtrip")
		var forged:=model.to_dict();forged.variant=(variant+1)%3
		rejected(restored,forged,"Reject copied evidence after changing variant")
		forged=model.to_dict();forged.statements.lotte.source="Another driver"
		rejected(restored,forged,"Reject changed adult source")
		forged=model.to_dict();forged.observations.road.text="Het regende en daarom was de bestuurder schuldig."
		rejected(restored,forged,"Reject fabricated causal observation")
		forged=model.to_dict();forged.incident_id=0
		rejected(restored,forged,"Free record needs positive incident ID")
		forged=model.to_dict();forged.variant=.5
		rejected(restored,forged,"Variant cannot be fractional")
		forged=model.to_dict();forged.closed=true
		rejected(restored,forged,"Closed state needs actual submitted score")
		var wrong:=rows.duplicate(true);wrong.append({"id":"conclusion_guilt","category":"conclusion"})
		check(model.submit_report(wrong).result=="wrong" and model.phase=="report" and not model.closed,"Wrong free report remains correctable")
		check(restored.restore(JSON.parse_string(JSON.stringify(model.to_dict()))) and restored.result=="wrong" and not restored.closed,"Unclosed wrong draft persists")
		if variant==0:
			check(model.submit_report(rows).result=="careful" and model.phase=="completed" and model.closed,"Correction before closure preserves normal success")
		else:
			if variant==2:
				rows.pop_back()
				check(model.submit_report(rows).result=="incomplete","Player may omit a required report conclusion")
			var score_before:=model.report_score.duplicate(true)
			var outcome:=model.finalize_report()
			check(outcome.ok and outcome.score==score_before and model.report_score==score_before,"Explicit closure preserves deficient score exactly")
			check(model.phase=="completed" and model.result in ["wrong","incomplete"],"Closure ends dispatch lifecycle without upgrading outcome")
			check(not model.finalize_report().ok,"No repeated closure")
			var closed_before:=model.to_dict()
			check(not model.tick(1) and not model.speak("driver","open").ok and not model.record_observation("damage"),"Closed deficient reports are immutable gameplay")
			model.submit_report(cards(model))
			check(model.to_dict()==closed_before,"Re-submitting after explicit closure cannot rewrite history")
		check(restored.restore(JSON.parse_string(JSON.stringify(model.to_dict()))) and restored.to_dict()==model.to_dict(),"Completed result restores with exact canonical score")
		forged=model.to_dict();forged.report_score.score=99
		rejected(restored,forged,"Reject forged score on closed free report")
		forged=model.to_dict();forged.observations.damage.time=forged.elapsed+1
		rejected(restored,forged,"Reject future event in free report")
		forged=model.to_dict();forged.schema=2.1
		rejected(restored,forged,"Unknown fractional schema rejected")
		forged=model.to_dict();forged.mode="campaign"
		rejected(restored,forged,"Free metadata cannot be passed into campaign state")
	check(model.begin("basis") and model.incident_id==0 and model.variant==0 and not model.closed,"Changing mode clears all free dispatch metadata")
	check(model.person_data("lotte").source=="Lotte, bestuurder","Original academy cast unaffected")
	for mode: String in ["none","campaign","basis","intake"]:
		var legacy:=Legacy.new();legacy.begin(mode)
		if mode in ["campaign","basis"]:
			road(legacy);legacy.submit_report(cards(legacy))
		elif mode=="intake":
			for right: String in Case.RIGHTS_STEPS:legacy.tick(1);legacy.rights(right)
			for i in range(3):legacy.tick(1);legacy.register_print(.9)
			legacy.submit_report(cards(legacy))
		var old:=legacy.to_dict()
		check(model.restore(JSON.parse_string(JSON.stringify(old))),"Strict schema1 migration: "+mode)
		var migrated:=model.to_dict()
		check(migrated.schema==2 and migrated.incident_id==0 and migrated.variant==0 and not migrated.closed,"Migration assigns no free identity: "+mode)
		migrated.erase("incident_id");migrated.erase("variant");migrated.erase("closed");migrated.schema=1
		check(migrated==old,"Migration preserves every original scenario field: "+mode)
		var invalid:=old.duplicate(true);invalid.incident_id=1
		rejected(model,invalid,"Legacy rejects unknown free key before migration")
		invalid=old.duplicate(true);invalid.mode="free"
		rejected(model,invalid,"Legacy cannot smuggle free mode without metadata")
		invalid=model.to_dict();invalid.incident_id=1
		rejected(model,invalid,"Non-free schema2 ID remains zero")
		invalid=model.to_dict();invalid.variant=1
		rejected(model,invalid,"Non-free schema2 variant remains zero")
		invalid=model.to_dict();invalid.closed=true
		rejected(model,invalid,"Only free mode can carry an explicit closure flag")
		if mode!="none":
			invalid=old.duplicate(true);invalid.report_score.score=0
			rejected(model,invalid,"Migration still rejects forged legacy score")
	model.begin_free(123,1);road(model)
	model.speak("driver","leading")
	check(model.submit_report(cards(model)).result=="incomplete","Suggestive free dialogue harms report quality")
	check(model.speak("driver","open").ok and model.report_score.is_empty(),"Open follow-up clears the superseded evaluation")
	check(model.submit_report(cards(model)).result=="careful","Valid source correction before closure recovers careful result")
	print("SCENE112_FREE_TRAFFIC_", "OK" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
