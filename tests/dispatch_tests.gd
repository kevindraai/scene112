extends SceneTree
## Pure ledger checks: no player save files or scene nodes are created.

const Ledger = preload("res://scripts/dispatch.gd")
var failures := 0

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func reject(ledger: RefCounted, malformed: Variant, label: String) -> void:
	var before: Dictionary = ledger.to_dict()
	check(not ledger.restore(malformed), label)
	check(ledger.to_dict() == before, label + " is atomic")

func _initialize() -> void:
	var ledger := Ledger.new()
	ledger.start(112)
	check(ledger.incident.is_empty() and ledger.serial == 0, "radio starts without an incident spam list")
	check(not ledger.accept() and not ledger.hand_over() and not ledger.resolve(80), "no actions without an incident")
	check(not ledger.tick(19) and ledger.incident.is_empty(), "first report waits twenty seconds")
	check(ledger.tick(1) and ledger.incident.phase == "offered" and ledger.serial == 1, "first report becomes available at twenty seconds")
	check(not ledger.resolve(80), "offered incident cannot be resolved without acceptance")
	check(ledger.accept() and not ledger.accept(), "accept once and keep one accepted incident")
	check(not ledger.tick(10) and ledger.serial == 1, "accepted incident prevents extra offers")
	check(not ledger.resolve(-1) and not ledger.resolve(101), "quality must be within zero to one hundred")
	check(ledger.resolve(85) and ledger.incident.quality == 85 and ledger.completed == 1, "resolution records outcome and count")
	check(not ledger.resolve(85) and not ledger.accept() and not ledger.hand_over(), "terminal incident actions cannot repeat")
	check(not ledger.tick(29) and ledger.serial == 1, "thirty seconds of rest after completion")
	var previous_variant := int(ledger.incident.variant)
	check(ledger.tick(1) and ledger.serial == 2 and ledger.incident.kind == "traffic", "next incident alternates the playable family")
	check(int(ledger.incident.variant) != previous_variant, "consecutive incident locations vary")
	check(ledger.hand_over() and ledger.completed == 1 and ledger.missed == 0, "offered incident can be handed over without a penalty")
	check(ledger.tick(30) and ledger.accept() and ledger.hand_over(), "accepted incident can also be handed over")
	check(ledger.tick(30) and ledger.incident.phase == "offered", "hand-over respects the report interval")
	check(ledger.tick(90) and ledger.incident.phase == "expired" and ledger.missed == 1, "unanswered report expires exactly at its deadline")
	check(not ledger.accept() and not ledger.resolve(100), "expired report cannot revive")
	check(ledger.tick(30) and ledger.accept(), "another report arrives after expiry rest")
	check(ledger.tick(90) and ledger.incident.phase == "expired" and ledger.missed == 2, "accepted incident still has a response deadline")
	check(ledger.messages.size() == 8, "radio history remains bounded")

	var restored := Ledger.new()
	check(restored.restore(ledger.to_dict()) and restored.to_dict() == ledger.to_dict(), "snapshot restores the entire incident and radio state")
	var parsed: Variant = JSON.parse_string(JSON.stringify(ledger.to_dict()))
	check(restored.restore(parsed) and restored.to_dict() == ledger.to_dict(), "JSON roundtrip keeps integer fields and random state exact")
	check(ledger.tick(300) == restored.tick(300) and ledger.to_dict() == restored.to_dict(), "saved ledger continues with the same deterministic future")
	var coarse := Ledger.new()
	var fine := Ledger.new()
	coarse.start(431)
	fine.start(431)
	coarse.tick(300)
	for frame in range(300):
		fine.tick(1)
	check(coarse.to_dict() == fine.to_dict(), "event order is independent of timestep size")
	check(coarse.serial == 3 and coarse.missed == 2 and coarse.incident.phase == "offered", "five-minute unattended duty has bounded incident capacity")
	seed(42)
	var expected_global := randi()
	seed(42)
	var independent := Ledger.new()
	independent.start(-9223372036854775807 - 1)
	independent.tick(300)
	check(randi() == expected_global, "dispatch does not mutate the global random generator")
	check(restored.restore(independent.to_dict()), "extreme signed seed still produces JSON-safe random state")

	var before: Dictionary = restored.to_dict()
	check(not restored.tick(NAN) and not restored.tick(INF) and not restored.tick(-1) and not restored.tick(3601), "invalid or unbounded time inputs are rejected")
	check(restored.to_dict() == before, "rejected tick never mutates the ledger")
	reject(restored, null, "reject null save")
	var malformed: Dictionary = ledger.to_dict()
	malformed.schema = 99
	reject(restored, malformed, "reject unsupported schema")
	for key in ["duty_time", "next_report", "serial", "completed", "missed", "rng_state"]:
		malformed = ledger.to_dict()
		malformed[key] = NAN
		reject(restored, malformed, "reject nonfinite " + key)
	malformed = ledger.to_dict()
	malformed.serial = 0.5
	reject(restored, malformed, "reject fractional serial")
	malformed = ledger.to_dict()
	malformed.completed = malformed.serial + 1
	reject(restored, malformed, "reject impossible outcome counts")
	malformed = ledger.to_dict()
	malformed.messages = ["ok", 5]
	reject(restored, malformed, "reject nontext radio history")
	malformed = ledger.to_dict()
	malformed.messages.resize(9)
	reject(restored, malformed, "reject unbounded radio history")
	for key in ["id", "variant", "reported_at", "deadline", "closed_at", "quality"]:
		malformed = ledger.to_dict()
		malformed.incident[key] = INF
		reject(restored, malformed, "reject nonfinite incident " + key)
	malformed = ledger.to_dict()
	malformed.incident.position[0] = NAN
	reject(restored, malformed, "reject nonfinite target coordinates")
	malformed = ledger.to_dict()
	malformed.incident.position = [0, 0, 0]
	reject(restored, malformed, "reject position inconsistent with location variant")
	malformed = ledger.to_dict()
	malformed.incident.phase = "invented"
	reject(restored, malformed, "reject unknown incident lifecycle")
	malformed = ledger.to_dict()
	malformed.incident.deadline = malformed.incident.reported_at - 1
	reject(restored, malformed, "reject reversed incident time")
	malformed = ledger.to_dict()
	malformed.incident = {}
	reject(restored, malformed, "reject missing current incident")
	malformed = ledger.to_dict()
	malformed.incident.erase("quality")
	reject(restored, malformed, "reject partial incident snapshot")

	var isolated := ledger.to_dict()
	isolated.incident.position[0] = 99
	isolated.messages.clear()
	check(ledger.to_dict() != isolated and not ledger.messages.is_empty(), "save dictionaries do not share mutable arrays with live state")
	var initial := Ledger.new()
	initial.start(55)
	initial.tick(5)
	check(restored.restore(initial.to_dict()), "pre-report save restores during initial waiting period")
	check(initial.tick(15) and restored.tick(15) and initial.to_dict() == restored.to_dict(), "pre-report restore keeps first report scheduling deterministic")
	var future_fire := initial.to_dict()
	future_fire.incident.kind = "fire"
	future_fire.incident.title = "Kleine buitenbrand"
	check(restored.restore(future_fire), "future fire family supports a scenario-specific title")
	check(restored.accept() and restored.resolve(0) and restored.incident.quality == 0, "zero quality is a valid completed incident outcome")
	check(initial.restore(restored.to_dict()), "completed incident restores with outcome zero")
	malformed = restored.to_dict()
	malformed.incident.quality = -1
	reject(initial, malformed, "resolved incident requires a recorded quality")
	malformed = restored.to_dict()
	malformed.next_report += 1
	reject(initial, malformed, "next report must follow the terminal event rest interval")
	malformed = restored.to_dict()
	malformed.incident.closed_at = malformed.duty_time + 1
	reject(initial, malformed, "incident cannot close in the future")
	malformed = restored.to_dict()
	malformed.incident.kind = "unknown"
	reject(initial, malformed, "reject unknown incident family")
	malformed = restored.to_dict()
	malformed.incident.title = ""
	reject(initial, malformed, "reject empty report title")
	# Replay different player actions across multiple seeds, saving in every phase.
	var replay_valid := true
	for replay_seed in [-112, 0, 1, 112, 9248]:
		var source := Ledger.new()
		var mirror := Ledger.new()
		source.start(replay_seed)
		mirror.start(replay_seed)
		for step in range(24):
			source.tick(20)
			mirror.tick(20)
			if not source.incident.is_empty() and source.incident.phase == "offered":
				if step % 3 == 0:
					source.accept()
					mirror.accept()
				elif step % 3 == 1:
					source.hand_over()
					mirror.hand_over()
			elif not source.incident.is_empty() and source.incident.phase == "accepted" and step % 4 != 0:
				source.resolve(75)
				mirror.resolve(75)
			replay_valid = replay_valid and source.to_dict() == mirror.to_dict()
			replay_valid = replay_valid and mirror.restore(JSON.parse_string(JSON.stringify(source.to_dict())))
			replay_valid = replay_valid and source.to_dict() == mirror.to_dict()
	check(replay_valid, "multiple-seed action replays survive JSON saves in every reached lifecycle phase")
	print("SCENE112_DISPATCH_TESTS_", "OK" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
