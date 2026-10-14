extends SceneTree

# Police P4: the free driver's pure rules (no game, under a second).
#   <godot> --headless --path . -s res://tests/traffic/free_driver_pure.gd

var failures: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	_approach()
	_no_rubber_band()
	_lines()
	_span()
	_in_front()
	for f in failures:
		printerr("FAIL: " + f)
	print("free_driver_pure: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)

## Closing on a spot: speeds up when behind it, matches it there, waits when ahead of it.
func _approach() -> void:
	var v0 := 60.0
	_check(FreeDriver.approach_accel(30.0, v0, 100.0, 30.0) > 1.0, "100 m short of its spot at the target's speed it does not speed up")
	_check(absf(FreeDriver.approach_accel(30.0, v0, 0.0, 30.0)) < 0.05, "on its spot at the target's speed it is not steady (%.2f)" % FreeDriver.approach_accel(30.0, v0, 0.0, 30.0))
	_check(FreeDriver.approach_accel(30.0, v0, -15.0, 30.0) < -1.0, "15 m past its spot it does not ease off")
	# arriving 20 m/s too fast with 20 m to go: it brakes hard
	_check(FreeDriver.approach_accel(50.0, v0, 20.0, 30.0) < -4.0, "20 m/s too fast 20 m from its spot: only %.1f m/s^2" % FreeDriver.approach_accel(50.0, v0, 20.0, 30.0))
	# a stopped target: it stops at the spot, it does not creep through it
	_check(FreeDriver.approach_accel(0.0, v0, 0.0, 0.0) <= 0.0, "at a stopped target's spot it still pulls away")
	# simulated: from 150 m behind a 30 m/s target it arrives and settles without overshooting 3 m
	var v := 30.0
	var gap := 150.0
	var worst := 0.0
	var dt := 1.0 / 60.0
	for i in 60 * 40:
		v = maxf(v + FreeDriver.approach_accel(v, v0, gap, 30.0) * dt, 0.0)
		gap -= (v - 30.0) * dt
		worst = minf(worst, gap)
	_check(absf(gap) < 1.0, "after 40 s it sits %.1f m from its spot" % gap)
	_check(worst > -3.0, "it overshot its spot by %.1f m" % -worst)

## No rubber band: the command never asks for more than the car's own top
## speed, however far ahead the target is.
func _no_rubber_band() -> void:
	for top in [35.0, 50.0, 70.0]:
		for gap in [50.0, 500.0, 5000.0]:
			var a := FreeDriver.approach_accel(top, top, gap, 90.0)
			_check(a <= 0.001, "at its top speed %.0f m/s with the target %.0f m ahead it still asks for %.2f m/s^2" % [top, gap, a])
	# and the closing speed is capped: a far target is not chased at any speed the car has
	var v := 0.0
	for i in 60 * 60:
		v = maxf(v + FreeDriver.approach_accel(v, 200.0, 2000.0, 20.0) / 60.0, 0.0)
	_check(v <= 20.0 + FreeDriver.CLOSE_MAX + 0.5, "closing on a 20 m/s target it reached %.0f m/s (cap %.0f over)" % [v, FreeDriver.CLOSE_MAX])

## Corridor rules.
func _lines() -> void:
	_check(FreeDriver.line_open(40.0, INF, 0.0, 100.0), "an empty corridor is closed")
	_check(not FreeDriver.line_open(40.0, 20.0, 20.0, 100.0), "a car 20 m ahead doing half the speed is open")
	_check(FreeDriver.line_open(40.0, 110.0, 38.0, 100.0), "a car past where the driver is going closes the line")
	_check(FreeDriver.line_open(30.0, 80.0, 30.0, 100.0), "a car 80 m ahead at the same speed closes the line")
	_check(not FreeDriver.line_open(40.0, 70.0, 10.0, 200.0), "a car 70 m ahead 30 m/s slower is open (needs 6.7 m/s^2)")
	_check(FreeDriver.side_clear(30.0, INF, 0.0), "nobody behind is not clear")
	_check(not FreeDriver.side_clear(30.0, 2.0, 30.0), "a car 2 m behind is clear")
	_check(FreeDriver.side_clear(30.0, 15.0, 25.0), "a slower car 15 m behind is not clear")
	_check(not FreeDriver.side_clear(30.0, 15.0, 45.0), "a car 15 m behind closing at 15 m/s is clear (1 s away)")
	_check(FreeDriver.side_clear(30.0, 60.0, 45.0), "a car 60 m behind closing at 15 m/s is not clear (4 s away)")

## The span it may drive in keeps it off the edges and on its own carriageway.
func _span() -> void:
	var own := FreeDriver.side_span(4, false)
	var far := FreeDriver.side_span(4, true)
	_check(own.x > 0.0 and own.y > own.x, "own span %s" % own)
	_check(far.y < 0.0 and far.x < far.y, "far span %s" % far)
	_check(is_equal_approx(own.x, -far.y) and is_equal_approx(own.y, -far.x), "the two sides are not mirror images")
	_check(own.y <= RoadChunkBuilder.MEDIAN_GAP + 4.0 * RoadChunkBuilder.LANE_W - 1.0, "own span reaches %.2f, the road ends at %.2f" % [own.y, RoadChunkBuilder.MEDIAN_GAP + 4.0 * RoadChunkBuilder.LANE_W])
	var one := FreeDriver.side_span(1, false)
	_check(one.y >= one.x, "a one-lane road has an inverted span %s" % one)

## In front of the target (issue #625): when it may be on the target's line,
## and how hard it may slow there.
func _in_front() -> void:
	# the issue's two crashes: never allowed
	_check(not FreeDriver.cut_in_ok(17.0, (98.0 - 44.0) / 3.6, 98.0 / 3.6), "a chaser 17 m ahead at 44 km/h may cut in front of 98 km/h")
	_check(not FreeDriver.cut_in_ok(24.0, (150.0 - 20.0) / 3.6, 150.0 / 3.6), "a blocker 24 m ahead at 20 km/h may cut in front of 150 km/h")
	# matched speed: a headway of CUT_HEADWAY is needed, not less
	var vt := 150.0 / 3.6
	_check(FreeDriver.cut_in_ok(vt * FreeDriver.CUT_HEADWAY + 0.5, 0.0, vt), "at matched speed %.0f m ahead (more than %.1f s) it may not move over" % [vt * FreeDriver.CUT_HEADWAY + 0.5, FreeDriver.CUT_HEADWAY])
	_check(not FreeDriver.cut_in_ok(vt * FreeDriver.CUT_HEADWAY - 0.5, 0.0, vt), "at matched speed it may move over under %.1f s ahead" % FreeDriver.CUT_HEADWAY)
	# closing: the target sheds it at TARGET_DECEL after REACT_S
	var c := 10.0
	var need := vt * FreeDriver.CUT_HEADWAY + c * c / (2.0 * FreeDriver.TARGET_DECEL) + c * FreeDriver.REACT_S
	_check(FreeDriver.cut_in_ok(need + 0.5, c, vt) and not FreeDriver.cut_in_ok(need - 0.5, c, vt), "closing at %.0f m/s the line is not at %.0f m" % [c, need])
	# box-in speeds: only S0, so the cops can close in round a slow car
	_check(FreeDriver.cut_in_ok(TrafficCar.S0 + 0.1, 0.0, 30.0 / 3.6), "at 30 km/h it may not move over at %.1f m" % (TrafficCar.S0 + 0.1))
	_check(not FreeDriver.cut_in_ok(0.0, 0.0, 0.0), "it may move over onto the target itself")
	# braking in front: never harder than GENTLE_DECEL while the target could stop
	_check(is_equal_approx(FreeDriver.front_floor(30.0, 30.0, true), -FreeDriver.GENTLE_DECEL), "the floor in front is not -%.1f" % FreeDriver.GENTLE_DECEL)
	# and not below the target's pace while it could not: a slow car in front speeds up
	_check(FreeDriver.front_floor(12.0, 27.0, false) > 1.0, "slower than a target that could not stop for it, it does not speed up (%.2f)" % FreeDriver.front_floor(12.0, 27.0, false))
	_check(FreeDriver.front_floor(30.0, 27.0, false) >= -FreeDriver.GENTLE_DECEL, "faster than the target it brakes harder than %.1f" % FreeDriver.GENTLE_DECEL)
	# waiting for a spot behind it: never more than WAIT_CLOSE under the target's pace
	var v := 30.0
	for i in 600:
		v = maxf(v + FreeDriver.approach_accel(v, 60.0, -200.0, 30.0) / 60.0, 0.0)
	_check(v >= 30.0 - FreeDriver.WAIT_CLOSE - 0.5, "200 m past its spot it slowed to %.1f m/s in front of a 30 m/s target" % v)
