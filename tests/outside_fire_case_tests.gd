extends SceneTree

const Case = preload("res://scripts/outside_fire_case.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_deferred.call_deferred()

func _deferred() -> void:
	_test_state_and_geometry()
	_test_local_suppression_and_water()
	_test_fire_time_and_safety()
	_test_completion()
	_test_json_and_atomic_validation()
	_test_simulation_replay()
	print("OUTSIDE_FIRE_TESTS ", checks, " checks / ", failures, " failures")
	quit(0 if failures == 0 else 1)

func verify(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func active(material_variant: int = 0, site: Vector3 = Vector3(20, 0, 30)) -> OutsideFireCase:
	var test := Case.new()
	verify(test.begin(21, material_variant, site), "begin valid original outdoor incident")
	for step in Case.BASICS: verify(test.complete_step(step), "physical acknowledgement " + step)
	verify(test.check_recon("exterior") and test.check_recon("surroundings"), "two exterior observations")
	verify(test.connect_water() and test.choose_tactic("defensive"), "bounded defensive active state")
	verify(test.add_hose_point(site + Vector3(0, 0, -4)), "actual source to safe ground hose")
	return test

func _test_state_and_geometry() -> void:
	var test := Case.new()
	verify(test.mode == "none" and test.victim.status == "none" and not test.can_enter(), "empty case has no fictional victim or interior")
	verify(not test.begin(-1, 0, Vector3.ZERO) and not test.begin(1, 3, Vector3.ZERO) and not test.begin(1, 0, Vector3(NAN, 0, 0)), "reject invalid begin inputs")
	verify(test.begin(1, 0, Vector3(10, 0, 20)), "valid world origin")
	verify(test.target_position("center") == Vector3(10, 0.55, 20) and test.target_position("unknown") == Vector3.INF, "world target positions and unknown sentinel")
	verify(not test.complete_step("drive") and not test.check_recon("exterior") and not test.connect_water(), "cannot skip physical arrival")
	for step in Case.BASICS: test.complete_step(step)
	verify(not test.complete_step("exit"), "physical basics cannot be repeated for score")
	test.check_recon("surroundings"); test.check_recon("exterior"); test.connect_water()
	verify(not test.choose_tactic("interior") and test.choose_tactic("defensive"), "outside-only tactic")
	verify(not test.add_hose_point(Vector3.INF) and not test.add_hose_point(Vector3(10, 2, 16)), "nonfinite/elevated hose endpoints rejected")
	verify(not test.add_hose_point(Vector3(10, 0, 19)) and not test.add_hose_point(Vector3(10, 0, 11)), "unsafe hot/remote ground rejected")
	verify(not test.add_hose_point(test.water_source()) and test.add_hose_point(Vector3(10, 0, 16)), "real minimum hose segment")
	verify(test.has_nozzle_at(Vector3(10, 0, 16)) and not test.has_nozzle_at(Vector3(10, 0, 19)), "nozzle proximity plus safe approach rule")
	var points := [Vector3(9, 0, 16), Vector3(8, 0, 16), Vector3(7, 0, 16), Vector3(6, 0, 16)]
	for point in points: verify(test.add_hose_point(point), "bounded safe hose point")
	verify(test.hose_points.size() == 6 and not test.add_hose_point(Vector3(5, 0, 16)) and test.hose_length() <= 35, "six-point/35m bounded hose")

func _test_local_suppression_and_water() -> void:
	var test := active()
	var before := test.to_dict()
	verify(not test.spray("forged-target", 1) and test.to_dict() == before, "unknown target causes no mutation")
	verify(test.spray("", 1) and test.cells == before.cells and test.water_liters == 206 and test.hit_water == 0, "actual MISS consumes 14 liters without cooling")
	var cells_before: Array = test.cells.duplicate(true)
	verify(test.spray("center", 1), "direct valid local target")
	verify(float(test.cells[0].heat) < float(cells_before[0].heat) and test.cells[1] == cells_before[1] and test.cells[2] == cells_before[2], "one target cools one actual cell")
	verify(test.tick(1) and test.water_liters == 198 and test.water_used == 28 and test.hit_water == 14, "source supplies 6L/s with durable consumption")
	while test.water_liters >= 14: test.spray("", 1)
	before = test.to_dict()
	verify(not test.spray("center", 1) and test.to_dict() == before, "empty tank prevents free cooling")
	for count in range(10): test.tick(5)
	verify(test.water_liters == 220, "water source refills only to 220 liters")
	verify(not test.spray("center", NAN) and not test.spray("center", -1) and not test.spray("center", 6), "invalid spray durations rejected")

func _test_fire_time_and_safety() -> void:
	var test := active()
	var cold_before := float(test.cells[2].heat)
	verify(test.tick(5) and float(test.cells[2].heat) > cold_before and float(test.cells[0].burned) > 0, "actual simulation grows/spreads and burns fuel")
	var safe := test.origin + Vector3(0, 0, -4)
	test.tick(1, safe); test.tick(1, test.origin)
	verify(test.unsafe_seconds == 1, "actual unsafe on-foot position has consequence")
	test.tick(1, test.origin + Vector3(0, 0, -20))
	verify(test.unsafe_seconds == 1, "distant retreat outside hazard zone is not penalized")
	var before := test.to_dict()
	verify(not test.tick(INF) and not test.tick(0) and not test.tick(1, Vector3(NAN, 0, 0)) and test.to_dict() == before, "invalid simulation inputs atomic")
	verify(test.tick(1), "omitted operator uses explicit INF sentinel")
	var fast := active(1)
	var slow := active(2)
	fast.tick(5); slow.tick(5)
	verify(float(fast.cells[0].burned) > float(slow.cells[0].burned), "material variants change real fuel kinetics")

func _test_completion() -> void:
	var test := active()
	verify(test.finish().is_empty(), "active fire cannot claim careful completion")
	for cell in test.cells:
		while float(cell.heat) > 0.03:
			test.spray(cell.id, 0.25)
			test.tick(0.25, test.origin + Vector3(0, 0, -4))
	var score := test.finish()
	verify(score.result == "careful" and int(score.total) >= 80 and int(score.total) <= 100 and score.victim == "none", "real targeted cooling can finish carefully")
	var completed := test.to_dict()
	verify(test.finish(true) == score and not test.tick(1) and not test.spray("center", 1) and test.to_dict() == completed, "completion is idempotent and immutable")
	var withdrawn := active()
	var partial := withdrawn.finish(true)
	verify(partial.result == "partial" and not withdrawn.all_cold() and int(partial.total) < 80, "withdraw keeps active heat and clear partial result")
	var short_burst := active()
	short_burst.spray("center", 0.1)
	var brief_score := short_burst.finish(true)
	verify(brief_score.result == "partial" and brief_score.suppression < 5 and brief_score.total < 65, "one short burst cannot receive credit for initially cold space")
	var max_id := Case.new()
	verify(max_id.begin(10_000_000, 2, Vector3.ZERO), "dispatch maximum ID accepted")
	json_restore(max_id)
	var max_before := max_id.to_dict()
	verify(not max_id.begin(10_000_001, 0, Vector3.ZERO) and max_id.to_dict() == max_before, "ID beyond dispatch maximum refused atomically")
	verify(not max_id.begin(0, 0, Vector3.ZERO), "zero is not a live incident ID")
	var burnout := active()
	for count in range(150): burnout.tick(5)
	var burnout_score := burnout.finish()
	verify(burnout.all_cold() and burnout_score.result == "partial" and int(burnout_score.total) <= 45 and burnout.hit_water == 0, "waiting for burnout never becomes successful suppression")
	var unsafe := active()
	unsafe.tick(5, unsafe.origin)
	verify(int(unsafe.finish(true).safety) == 0, "unsafe approach costs safety score")
	var wasteful := active()
	for count in range(30): wasteful.tick(1); wasteful.spray("center", 1)
	for cell in wasteful.cells:
		while float(cell.heat) > 0.02: wasteful.spray(cell.id, 0.25); wasteful.tick(0.25)
	verify(wasteful.finish().result == "partial", "excess water on a cold target cannot earn careful outcome")

func json_restore(source: OutsideFireCase) -> OutsideFireCase:
	var restored := Case.new()
	var parsed: Variant = JSON.parse_string(JSON.stringify(source.to_dict()))
	verify(parsed is Dictionary and restored.restore(parsed), "real JSON round-trip accepted")
	verify(Case._equal(restored.to_dict(), source.to_dict()), "round-trip preserves complete incident state")
	return restored

func reject_atomically(target: OutsideFireCase, bad: Variant, label: String) -> void:
	var before := target.to_dict()
	verify(not target.restore(bad) and target.to_dict() == before, label)

func _test_json_and_atomic_validation() -> void:
	json_restore(Case.new())
	var briefing := Case.new()
	briefing.begin(81, 2, Vector3(-490, 0, 490)); briefing.complete_step("gear")
	json_restore(briefing)
	var test := active()
	test.tick(2); test.spray("center", 1)
	var restored := json_restore(test)
	for field in ["schema", "incident_id", "variant"]:
		var bad := test.to_dict(); bad[field] = 1.5
		reject_atomically(restored, bad, "fractional integer " + field + " rejected")
	var bad := test.to_dict(); bad.water_used = true
	reject_atomically(restored, bad, "boolean cannot become numerical water")
	bad = test.to_dict(); bad.water_liters = NAN
	reject_atomically(restored, bad, "nonfinite water rejected")
	bad = test.to_dict(); bad.cells[0].fuel = 0.1
	reject_atomically(restored, bad, "fuel/burned conservation enforced")
	bad = test.to_dict(); bad.cells[0].wet = 1
	reject_atomically(restored, bad, "wetting must be backed by water on a target")
	bad = test.to_dict(); bad.water_liters = 1
	reject_atomically(restored, bad, "tank water cannot disappear without consumption")
	bad = test.to_dict(); bad.cells[0].pos = [0, 0, 0]
	reject_atomically(restored, bad, "forged world target position rejected")
	bad = test.to_dict(); bad.hose_points[1] = [20, 0, 30]
	reject_atomically(restored, bad, "unsafe saved hose point rejected")
	bad = test.to_dict(); bad.actions[0].kind = "victim_rescued"
	reject_atomically(restored, bad, "forged rescue event rejected")
	bad = test.to_dict(); bad.actions.reverse()
	reject_atomically(restored, bad, "known events in impossible order rejected")
	bad = test.to_dict(); bad.actions.pop_back()
	reject_atomically(restored, bad, "missing source action rejected")
	bad = test.to_dict(); bad.report_score = {"total": 100}
	reject_atomically(restored, bad, "active score injection rejected")
	bad = test.to_dict(); bad.victim.status = "rescued"
	reject_atomically(restored, bad, "outside model cannot import invented victim")
	bad = test.to_dict(); bad.unknown = "event"
	reject_atomically(restored, bad, "unknown schema fields rejected")
	var partial := test.finish(true)
	verify(partial.result == "partial", "JSON test creates partial completed incident")
	json_restore(test)
	bad = test.to_dict(); bad.report_score.total = 100
	reject_atomically(restored, bad, "forged completed score rejected")
	bad = test.to_dict(); bad.actions.back().time = 1
	reject_atomically(restored, bad, "finish event must match stopped incident clock")
	bad = test.to_dict(); bad.withdrew = false; bad.actions.back().kind = "handover"
	reject_atomically(restored, bad, "hot incident cannot forge cold handover")
	var cooled := active(2, Vector3(-40, 0, 8))
	for cell in cooled.cells:
		while float(cell.heat) > 0.02: cooled.spray(cell.id, 0.25)
	verify(cooled.finish().result == "careful", "second site and material complete")
	json_restore(cooled)

func _test_simulation_replay() -> void:
	var test := active()
	for count in range(60):
		test.tick(1.0 / 60, test.origin + Vector3(0, 0, -4))
		test.spray("center", 1.0 / 60)
	verify(test.simulation.size() == 1 and test.simulation[0].count == 60 and test.simulation[0].pattern.size() == 2, "per-frame tick/spray pairs compact losslessly")
	var restored := json_restore(test)
	verify(restored._operation_count == 120, "replay reconstructs bounded operation count")
	for count in range(20):
		test.tick(0.1, test.origin); restored.tick(0.1, restored.origin)
		test.spray("left", 0.1); restored.spray("left", 0.1)
	verify(Case._equal(restored.to_dict(), test.to_dict()), "restored physics continues exactly from saved simulation")
	var bad := test.to_dict(); bad.cells[0].heat = 0
	reject_atomically(restored, bad, "forged cold snapshot rejected despite plausible fuel and water totals")
	bad = test.to_dict(); bad.unsafe_seconds = 0
	reject_atomically(restored, bad, "unsafe-position consequences cannot be removed from snapshot")
	bad = test.to_dict(); bad.simulation.clear()
	reject_atomically(restored, bad, "physics snapshot needs actual replay operations")
	bad = test.to_dict(); bad.simulation[0].after = 0
	reject_atomically(restored, bad, "simulation cannot predate actual preparation")
	bad = test.to_dict(); bad.simulation[0].pattern[0][0] = "cool_all"
	reject_atomically(restored, bad, "unknown simulation operation rejected")
	bad = test.to_dict(); bad.simulation[0].pattern[0][1] = NAN
	reject_atomically(restored, bad, "nonfinite simulation duration rejected")
	bad = test.to_dict(); bad.simulation[0].pattern[0][2] = 0
	reject_atomically(restored, bad, "unsafe flag must be boolean")
	bad = test.to_dict(); bad.simulation[0].count = 500001
	reject_atomically(restored, bad, "oversized run rejected before replay")
	bad = test.to_dict(); bad.simulation[0].count = 1.5
	reject_atomically(restored, bad, "fractional run count rejected")
	bad = test.to_dict(); bad.simulation[0].extra = true
	reject_atomically(restored, bad, "extra simulation row field rejected")
	bad = test.to_dict(); bad.simulation = {}
	reject_atomically(restored, bad, "wrong journal type rejected without typed-assignment error")
	bad = test.to_dict(); bad.actions = {}
	reject_atomically(restored, bad, "wrong action type rejected without typed-assignment error")
	var tiny := active()
	tiny.tick(0.00000000000001)
	json_restore(tiny)
