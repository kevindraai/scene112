extends SceneTree

const Case = preload("res://scripts/police_case.gd")
var failures := 0

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func reject(model: RefCounted, data: Variant, label: String) -> void:
	var before: Dictionary = model.to_dict()
	check(not model.restore(data), label)
	check(model.to_dict() == before, label + " is atomic")

func basic(model: RefCounted) -> void:
	for step in ["equipment", "radio", "enter", "drive", "exit"]:
		model.tick(1)
		check(model.complete_step(step), "perform actual controller-confirmed " + step)

func road(model: RefCounted, mode: String = "campaign") -> void:
	model.begin(mode)
	basic(model)
	for at in [Vector3(-26, 0, 15), Vector3(-28, 0, 17), Vector3(-26, 0, 19)]:
		model.tick(1)
		check(model.place_cone(at).ok, "place distinct safe physical cone")
	for id in ["damage", "marks", "road"]:
		model.tick(1)
		check(model.record_observation(id), "record source/time/location for " + id)
	model.tick(1)
	check(model.speak("lotte", "open").ok, "listen to the driver without assuming guilt")
	model.tick(1)
	check(model.speak("bram", "open").ok, "record witness limits separately from driver")
	model.tick(1)

func ordered_cards(model: RefCounted) -> Array:
	var available: Array = model.report_cards()
	available.sort_custom(func(first, second): return float(first.time) < float(second.time))
	var result: Array = []
	for card in available:
		if card.id != "conclusion_guilt": result.append({"id": card.id, "category": card.category})
	return result

func _initialize() -> void:
	var model := Case.new()
	check(model.mode == "none" and not model.can_report(), "idle case has no reportable content")
	check(not model.begin("invented") and model.mode == "none", "invalid mode cannot mutate the case")
	model.begin("campaign")
	check(not model.complete_step("drive") and not model.basics.drive, "driving cannot skip gear and radio")
	check(not model.place_cone(Vector3(-26, 0, 15)).ok, "physical traffic safety requires prepared arrival")
	check(not model.record_observation("damage") and not model.speak("lotte", "open").ok, "location examination waits for safety")
	check(model.submit_report([]).result == "incomplete" and model.report_score.is_empty(), "empty paperwork cannot bypass gameplay")
	check(model.score_report([]).score < 50, "absent scene work cannot earn a high report score")
	basic(model)
	check(not model.place_cone(Vector3(-18, 0, 18)).ok, "reject unsafe cone beside the wreck")
	check(not model.place_cone(Vector3(NAN, 0, 15)).ok, "reject nonfinite cone position")
	check(model.place_cone(Vector3(-26, 0, 15)).ok, "safe approach zone accepts its first cone")
	check(not model.place_cone(Vector3(-26.2, 0, 15.1)).ok, "same cone zone cannot be farmed twice")
	check(not model.record_observation("damage"), "one cone is insufficient safety")
	model.place_cone(Vector3(-28, 0, 17))
	model.place_cone(Vector3(-26, 0, 19))
	check(not model.place_cone(Vector3(-26, 0, 19)).ok, "cone count remains bounded at three")
	check(model.record_observation("pc_damage") and not model.record_observation("damage"), "observation aliases record once")
	check(model.observations.damage.source == "eigen waarneming" and model.observations.damage.location == [-18.0, 0.0, 18.0], "observation preserves provenance")
	road(model)
	check(model.can_report() and model.phase == "report", "physical case actions unlock the report")
	check(model.statements.lotte.source == "Lotte, bestuurder" and model.statements.bram.source == "Bram, getuige", "latest canonical actor roles are consistent")
	var rows := ordered_cards(model)
	var score: Dictionary = model.score_report(rows)
	check(score.score == 100 and score.result == "careful", "careful sourced report can succeed without a confession")
	check(score.objectivity == 25 and score.completeness == 25 and score.proportionality == 25 and score.consistency == 25, "four independent report dimensions are exposed")
	var incomplete := rows.duplicate(true)
	incomplete.pop_back()
	check(model.score_report(incomplete).result == "incomplete" and model.score_report(incomplete).completeness < 25, "omitted conclusion affects completeness")
	var wrong_source := rows.duplicate(true)
	for row in wrong_source:
		if row.id == "declaration_lotte": row.category = "observation"
	check(model.submit_report(wrong_source).result == "wrong", "presenting a declaration as personal observation harms the dossier")
	check(model.result == "wrong", "wrong report persists its quality outcome")
	check(model.submit_report(rows).result == "careful", "wrong report can be corrected with the actual recorded sources")
	check(model.phase == "completed" and not model.tick(1), "accepted dossier stops its case clock")
	var saved := model.to_dict()
	var restored := Case.new()
	check(restored.restore(saved) and restored.to_dict() == saved, "completed case restores exactly")
	check(restored.restore(JSON.parse_string(JSON.stringify(saved))) and restored.to_dict() == saved, "completed case JSON roundtrip recomputes verified scoring")
	var malformed := saved.duplicate(true)
	malformed.report_score.score = 99
	reject(restored, malformed, "reject forged report score")
	malformed = saved.duplicate(true)
	malformed.submitted_cards[0].id = "invented"
	reject(restored, malformed, "reject forged report content")
	reject(restored, null, "reject null case save")
	for field in ["schema", "elapsed"]:
		malformed = saved.duplicate(true)
		malformed[field] = NAN
		reject(restored, malformed, "reject nonfinite " + field)
	malformed = saved.duplicate(true)
	malformed.mode = ["campaign"]
	reject(restored, malformed, "reject nonstring mode")
	malformed = saved.duplicate(true)
	malformed.cones[0][0] = INF
	reject(restored, malformed, "reject nonfinite saved cone")
	malformed = saved.duplicate(true)
	malformed.cones[1] = malformed.cones[0].duplicate()
	reject(restored, malformed, "reject duplicate saved safety zones")
	malformed = saved.duplicate(true)
	malformed.cone_times[1] = malformed.cone_times[0] - 1
	reject(restored, malformed, "reject backwards cone chronology")
	malformed = saved.duplicate(true)
	malformed.observations.damage.source = "Bram"
	reject(restored, malformed, "reject rewritten observation source")
	malformed = saved.duplicate(true)
	malformed.statements.lotte.reliability = 0.1
	reject(restored, malformed, "reject invented statement reliability")
	malformed = saved.duplicate(true)
	malformed.basics.equipment = false
	reject(restored, malformed, "reject skipped preparation prefix")
	malformed = saved.duplicate(true)
	malformed.observations.road.time = malformed.elapsed + 1
	reject(restored, malformed, "reject future observation time")
	malformed = saved.duplicate(true)
	malformed.erase("cone_times")
	reject(restored, malformed, "reject incomplete save structure")
	malformed = saved.duplicate(true)
	malformed.intake_rights.explanation = true
	malformed.rights_times.explanation = 0.0
	reject(restored, malformed, "reject intake flags mixed into road-case state")
	var isolated := restored.to_dict()
	isolated.cones.clear()
	isolated.observations.damage.location[0] = 0
	check(restored.to_dict() == saved, "exported saves do not share mutable evidence")
	road(model, "basis")
	check(model.mode == "basis" and model.can_report() and model.report_score.is_empty(), "academy basis repeats the road scenario with fresh progress")
	model.speak("driver", "leading")
	check(model.statements.lotte.reliability < 1.0 and model.score_report(ordered_cards(model)).result == "incomplete", "suggestive questions reduce reliable report quality")
	model.submit_report(ordered_cards(model))
	model.speak("driver", "open")
	check(model.report_score.is_empty(), "new evidence invalidates the previous scored draft")
	model.tick(1)
	check(model.submit_report(ordered_cards(model)).result == "careful", "open follow-up recovers a weak conversation")
	road(model)
	var reverse := ordered_cards(model)
	reverse.reverse()
	check(model.score_report(reverse).consistency < 25 and model.score_report(reverse).result == "wrong", "reversed chronology has a visible dossier consequence")
	rows = ordered_cards(model)
	rows.append({"id": "conclusion_guilt", "category": "conclusion"})
	check(model.score_report(rows).result == "wrong" and model.score_report(rows).objectivity == 0, "unsupported speed and guilt conclusion cannot win")
	rows = ordered_cards(model)
	rows.append(rows[0].duplicate())
	check(model.score_report(rows).score == 1, "duplicate report cards cannot inflate the score")
	model.begin("intake")
	check(not model.rights("lawyer") and not model.register_print(0.9), "registration cannot bypass explanation, caution and consultation")
	check(model.rights("explanation") and not model.rights("lawyer"), "intake ground and rights precede later steps")
	model.tick(1)
	check(model.rights("cautie") and not model.register_print(0.9), "caution alone does not replace consultation")
	model.tick(1)
	check(model.rights("lawyer") and not model.rights("lawyer"), "consultation completes the rights chain once")
	check(not model.register_print(NAN) and not model.register_print(1.1) and not model.register_print(-0.1), "print quality must be finite and bounded")
	for quality in [0.2, 0.85, 0.95]:
		model.tick(1)
		check(model.register_print(quality), "record actual controller-measured print quality")
	check(not model.can_report(), "one unusable print prevents academy intake completion")
	check(not model.register_print(0.1) and model.print_qualities.size() == 3, "bad repeats do not erase better records")
	model.tick(1)
	check(model.register_print(0.9) and model.can_report(), "repeat the weakest print to recover quality")
	model.tick(1)
	var false_print_conclusion := ordered_cards(model)
	false_print_conclusion.append({"id": "conclusion_guilt", "category": "conclusion"})
	check(model.score_report(false_print_conclusion).result == "wrong" and model.score_report(false_print_conclusion).proportionality == 0, "registration quality cannot justify a guilt conclusion")
	check(model.submit_report(ordered_cards(model)).result == "careful", "rights, usable prints and sourced report complete intake")
	check(restored.restore(JSON.parse_string(JSON.stringify(model.to_dict()))) and restored.result == "careful", "intake print replacement times restore through JSON")
	malformed = model.to_dict()
	malformed.print_qualities[0] = INF
	reject(restored, malformed, "reject nonfinite saved print")
	malformed = model.to_dict()
	malformed.intake_rights.cautie = false
	reject(restored, malformed, "reject impossible rights chain")
	malformed = model.to_dict()
	malformed.print_times[0] = 0
	reject(restored, malformed, "reject registration before consultation")
	model.begin("none")
	check(restored.restore(model.to_dict()) and restored.phase == "none", "new idle case restores safely")
	var before := model.to_dict()
	check(not model.tick(INF) and not model.tick(NAN) and not model.tick(-1), "invalid time cannot advance case")
	check(model.to_dict() == before, "rejected time updates leave progress intact")
	print("SCENE112_POLICE_CASE_TESTS_", "OK" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
