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
