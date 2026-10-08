extends SceneTree
const Director = preload("res://scripts/audio_director.gd")
const House = preload("res://scripts/fire_case.gd")
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var director := Director.new()
	director.settings_path = "user://outside-audio-test.json"
	root.add_child(director)
	await process_frame
	director.set_process(false)
	var cells := []
	for index in 3:
		cells.append({"id": ["center", "left", "right"][index], "pos": [42.0 + index, 0.55, -34.0], "heat": 0.6})
	var context := {"mode": "free", "phase": "active", "clock": 2.0, "water_liters": 160.0, "cells": cells, "withdrew": false}
	var at := Vector3(42, 0.1, -38)
	check(director.update_outside_fire(context, at, true), "Explicit outdoor world context accepted")
	director._process(0.1)
	check(director._fire_outside and not director._fire.has("victim") and not director._fire.has("oxygen"), "No invented rescue or air state")
	check(director._fire_live and director._water_source.playing and not director._breath_source.playing, "Water and fire active; exterior never starts breathing loop")
	for index in 3:
		check(director._fire_sources[index].global_position == Vector3(42 + index, 0.55, -34), "Source uses actual world coordinates")
	var before: Dictionary = director._fire.duplicate(true)
	for field in ["heat", "pos", "id"]:
		var bad: Dictionary = context.duplicate(true)
		bad.cells[1][field] = {"heat": NAN, "pos": [42, INF, -34], "id": "center"}[field]
		check(not director.update_outside_fire(bad, at, true) and director._fire == before, "Invalid outdoor source rejected atomically: " + field)
	check(not director.update_outside_fire(context, Vector3(NAN, 0, 0), false), "Nonfinite nozzle rejected")
	var nodes_before := director.get_child_count()
	for index in 20: director.update_outside_fire(context, at, true)
	check(director._fire_sources.size() == 3 and director.get_child_count() == nodes_before, "Repeated outside context reuses bounded fire voices and one lever cue")
	context.phase = "completed"
	context.withdrew = true
	check(director.update_outside_fire(context, at, false), "Real outdoor withdrawal accepted")
	for index in 12:
		director.update_outside_fire(context, at, false)
		director._process(0.1)
	check(not director._fire_live and not director._water_source.playing and director._fire_sources.all(func(source): return not source.playing), "Completed outside incident fades all fire/water")
	var house := House.new()
	house.begin("campaign")
	check(director.update_fire(house.to_dict(), House.SITE, false, false), "Switch to genuine house state succeeds")
	check(not director._fire_outside and director._fire.victim.status == "waiting", "House victim remains actual house model")
	check(director.update_outside_fire({"mode": "none"}, at, false) and director._fire.mode == "campaign", "Inactive outdoor controller cannot clear live house context")
	await director.shutdown()
	check(director.status().shutdown_synchronized, "Audio waits for actual mixing shutdown")
	director.queue_free()
	await process_frame
	await process_frame
	print("SCENE112_OUTSIDE_AUDIO_", "OK" if failures == 0 else "FAIL", " checks=", checks)
	quit(0 if failures == 0 else 1)
