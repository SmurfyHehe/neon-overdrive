extends SceneTree

# PerfLadder: what the game does instead of pausing when the PC falls behind.
# - the project caps physics catch-up at 4 steps a frame;
# - 60 fps never climbs; a slow stretch climbs one rung at a time, picture
#   first, then traffic, then rivals, then a burst of slow motion;
# - warm-up and the frames right after a change are not judged;
# - room to spare climbs back down, slower after a bounce;
# - with the 30 fps cap on, 30 fps is not "behind";
# - the rungs are holds on the traffic manager and the step cap, and all let go.
# Pure logic plus a bare TrafficManager, headless.
#   <godot> --headless --path . -s res://tests/core/perf_ladder.gd

var failures: Array[String] = []

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func _warm() -> PerfLadder:
	var l := PerfLadder.new()
	l.live = false
	for i in 240:
		l.feed(1.0 / 60.0)
	return l

func _run(l: PerfLadder, frame: float, secs: float, cap := 0) -> void:
	var t := 0.0
	while t < secs:
		l.feed(frame, cap)
		t += frame

func _initialize() -> void:
	var steps := Engine.max_physics_steps_per_frame
	_check(int(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame")) == 4, "project setting: physics catch-up is not capped at 4 steps")
	_check(steps == 4, "engine runs with %d catch-up steps" % steps)
	_check(int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")) == 120, "the car no longer steps at 120 Hz")
	var hz := Engine.physics_ticks_per_second

	var l := _warm()
	_run(l, 1.0 / 60.0, 30.0)
	_check(l.rung == PerfLadder.NONE and l.climbs == 0, "60 fps climbed to rung %d" % l.rung)
	l.free()

	# 25 fps: one rung after UP_SECS, not before; then one at a time.
	l = _warm()
	_run(l, 0.04, 0.5)
	_check(l.rung == PerfLadder.NONE, "climbed after 0.5 s at 25 fps")
	_run(l, 0.04, 0.2)
	_check(l.rung == PerfLadder.PICTURE, "0.7 s at 25 fps: rung %d, want PICTURE" % l.rung)
	_run(l, 0.04, 0.8)
	_check(l.rung == PerfLadder.PICTURE, "climbed again inside the settle time")
	_run(l, 0.04, 1.0)
	_check(l.rung == PerfLadder.TRAFFIC, "second rung is %d, want TRAFFIC" % l.rung)
	_run(l, 0.04, 1.8)
	_check(l.rung == PerfLadder.RIVALS and not l.slowmo, "third rung is %d (slow motion %s), want RIVALS" % [l.rung, l.slowmo])
	_run(l, 0.04, 1.8)
	_check(l.rung == PerfLadder.RIVALS and l.slowmo, "still behind on the top rung: no slow motion")
	_run(l, 0.04, PerfLadder.SLOWMO_SECS + 0.1)
	_check(not l.slowmo and l.slowmo_count == 1, "slow motion did not end after %.0f s" % PerfLadder.SLOWMO_SECS)
	_run(l, 0.04, PerfLadder.SLOWMO_REST - 1.5)
	_check(l.slowmo_count == 1, "a second slow motion inside the rest time")
	_run(l, 0.04, 4.0)
	_check(l.slowmo_count == 2, "no second slow motion after the rest time")
	l.free()

	# Every other frame slow still adds up.
	l = _warm()
	for i in 120:
		l.feed(0.05)
		l.feed(0.02)
	_check(l.rung >= PerfLadder.PICTURE, "a stutter every other frame never climbed")
	l.free()

	# Warm-up: a slow start is not the frame rate.
	l = PerfLadder.new()
	l.live = false
	_run(l, 0.1, 2.5)
	_check(l.rung == PerfLadder.NONE, "climbed during warm-up")
	l.free()

	# Room to spare: down one rung after DOWN_SECS; after a bounce it waits twice as long.
	l = _warm()
	_run(l, 0.04, 0.7)
	_run(l, 1.0 / 60.0, PerfLadder.SETTLE_SECS + PerfLadder.DOWN_SECS - 0.5)
	_check(l.rung == PerfLadder.PICTURE, "came down too soon")
	_run(l, 1.0 / 60.0, 1.0)
	_check(l.rung == PerfLadder.NONE, "did not come down after %.0f s of room" % PerfLadder.DOWN_SECS)
	_run(l, 0.04, 2.0)
	_check(l.rung == PerfLadder.PICTURE, "did not climb again")
	_run(l, 1.0 / 60.0, PerfLadder.SETTLE_SECS + PerfLadder.DOWN_SECS + 2.0)
	_check(l.rung == PerfLadder.PICTURE, "came down as fast after a bounce")
	_run(l, 1.0 / 60.0, PerfLadder.DOWN_SECS)
	_check(l.rung == PerfLadder.NONE, "never came down after a bounce")
	l.free()

	# The 30 fps cap: 30 fps is the target.
	l = _warm()
	_run(l, 1.0 / 30.0, 10.0, 30)
	_check(l.rung == PerfLadder.NONE, "30 fps with the 30 cap climbed")
	_run(l, 0.05, 1.0, 30)
	_check(l.rung == PerfLadder.PICTURE, "20 fps with the 30 cap did not climb")
	l.free()

	# The holds.
	var tm := TrafficManager.new()
	var band := tm.physics_distance
	var pinned := tm.pinned_distance
	_check(pinned >= band, "a rival's full-sim distance (%.0f) is under the traffic band (%.0f)" % [pinned, band])
	l = PerfLadder.new()
	l.live = false
	l.traffic = tm
	l.rung = PerfLadder.PICTURE
	l.apply()
	_check(tm.physics_distance == band and tm.pinned_distance == pinned, "PICTURE touched the traffic")
	l.rung = PerfLadder.TRAFFIC
	l.apply()
	_check(tm.physics_distance == minf(band, PerfLadder.TRAFFIC_BAND) and tm.pinned_distance == pinned, "TRAFFIC band is %.0f" % tm.physics_distance)
	l.rung = PerfLadder.RIVALS
	l.apply()
	_check(tm.pinned_distance == 0.0, "RIVALS left the rival's distance at %.0f" % tm.pinned_distance)
	_check(Engine.max_physics_steps_per_frame == steps, "a rung without slow motion changed the step cap")
	l.slowmo = true
	l.apply()
	_check(Engine.max_physics_steps_per_frame == PerfLadder.SLOWMO_STEPS, "slow motion runs %d steps a frame" % Engine.max_physics_steps_per_frame)
	_check(Engine.physics_ticks_per_second == hz, "slow motion changed the tick rate")
	l.slowmo = false
	l.rung = PerfLadder.NONE
	l.apply()
	_check(tm.physics_distance == band and tm.pinned_distance == pinned and Engine.max_physics_steps_per_frame == steps,
		"the holds did not let go: band %.0f, rival %.0f, steps %d" % [tm.physics_distance, tm.pinned_distance, Engine.max_physics_steps_per_frame])
	# New settings start from the bottom rung.
	l.rung = PerfLadder.RIVALS
	l.apply()
	l.apply_graphics()
	l.apply()
	_check(l.rung == PerfLadder.NONE and tm.physics_distance == band, "a settings change kept rung %d / band %.0f" % [l.rung, tm.physics_distance])
	tm.free()
	l.free()

	for f in failures:
		printerr("FAIL: ", f)
	print("perf_ladder: ", "FAIL (%d)" % failures.size() if failures else "PASS")
	quit(1 if failures else 0)
