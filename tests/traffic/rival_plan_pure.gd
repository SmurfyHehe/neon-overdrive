extends SceneTree

# Rival driver, the pure parts (rival driver build spec, step 1): no game, no
# physics. Exact values for
#   1. the corner-speed formula and its top-speed cap,
#   2. the backward braking pass,
#   3. where the racing line puts the apex (bend_line and the built line),
#   4. the same seed giving the same driver, and the Docks crew's numbers.
#
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/traffic/rival_plan_pure.gd

var failures: Array[String] = []

func _initialize() -> void:
	_corner_speed()
	_brake_pass()
	_bend_line()
	_built_line()
	_seeded()
	RoadAlignment.scripted = []
	RoadFrame.align = null
	print("rival_plan_pure: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _corner_speed() -> void:
	# sqrt(0.84 x 8 x 300) = 44.8999
	_near(RivalDriver.corner_speed(1.0 / 300.0, 0.84, 8.0, 100.0), sqrt(0.84 * 8.0 * 300.0), 1e-4, "corner speed, 300 m left")
	_near(RivalDriver.corner_speed(-1.0 / 300.0, 0.84, 8.0, 100.0), 44.8999, 1e-3, "corner speed, 300 m right (sign ignored)")
	_near(RivalDriver.corner_speed(1.0 / 150.0, 0.97, 8.0, 100.0), sqrt(0.97 * 8.0 * 150.0), 1e-4, "corner speed, 150 m at commit 0.97")
	_near(RivalDriver.corner_speed(1.0 / 300.0, 0.84, 8.0, 40.0), 40.0, 1e-6, "corner speed capped at top speed")
	_near(RivalDriver.corner_speed(0.0, 0.84, 8.0, 61.5), 61.5, 1e-6, "straight road = top speed")
	print("corner speed: 300 m at 0.84 = %.2f m/s, 150 m at 0.97 = %.2f m/s" % [
		RivalDriver.corner_speed(1.0 / 300.0, 0.84, 8.0, 100.0), RivalDriver.corner_speed(1.0 / 150.0, 0.97, 8.0, 100.0)])

func _brake_pass() -> void:
	# b = 8.5 x 0.85 = 7.225 m/s^2 over 5 m steps, into a 20 m/s point.
	var v := PackedFloat32Array([60.0, 60.0, 60.0, 20.0, 60.0])
	RivalDriver.brake_pass(v, 7.225, 5.0)
	_near(v[4], 60.0, 1e-4, "brake pass leaves the far end")
	_near(v[3], 20.0, 1e-4, "brake pass keeps the slow point")
	_near(v[2], sqrt(400.0 + 72.25), 1e-3, "brake pass, one step back (21.731)")
	_near(v[1], sqrt(400.0 + 144.5), 1e-3, "brake pass, two steps back (23.335)")
	_near(v[0], sqrt(400.0 + 216.75), 1e-3, "brake pass, three steps back (24.834)")
	print("brake pass into 20 m/s: %.3f %.3f %.3f %.3f" % [v[0], v[1], v[2], v[3]])

func _bend_line() -> void:
	# 350 m bend, 300 m long, all the road it wants: turn in 48.533 m before,
	# apex in the middle 10.4 m across, back where it started.
	var k := 1.0 / 350.0
	var d := RivalDriver.bend_line(k, 300.0, 1000.0, 1000.0, 10.4, 0.0)
	_near(d.e_in, 2.0 * 10.4 * 350.0 / 150.0, 1e-3, "350 m bend: turn-in length")
	_near(d.e_out, d.e_in, 1e-6, "350 m bend: straighten-out equals turn-in")
	_near(d.c, k * 300.0 / (300.0 + 2.0 * float(d.e_in)), 1e-9, "350 m bend: path curvature")
	_near(d.apex_s, 150.0, 1e-3, "350 m bend: apex in the middle")
	_near(d.apex_y, 10.4, 1e-3, "350 m bend: apex on the inside limit")
	_near(d.end_y, 0.0, 1e-3, "350 m bend: ends where it began")
	print("350 m x 300 m bend: turn in %.2f m, path radius %.0f m, apex %.1f m in at %.2f m across" % [d.e_in, 1.0 / float(d.c), d.apex_s, d.apex_y])
	# No road before it: it cannot turn in early, so it only runs wide after
	# the bend if there is room on the outside, and there is none.
	var none := RivalDriver.bend_line(k, 300.0, 0.0, 1000.0, 10.4, 0.0)
	_near(none.c, k, 1e-9, "no turn-in road and no room outside: no line")
	# Turn-in only (a bend straight after it): a late line that ends inside.
	var late := RivalDriver.bend_line(k, 300.0, 1000.0, 0.0, 10.4, 0.0)
	_check(late.e_in > 1.0 and is_zero_approx(late.e_out), "turn-in only keeps the turn-in")
	_check(late.apex_y <= 10.4 + 1e-4 and late.end_y > 0.0 and late.end_y <= 10.4 + 1e-4, "turn-in only stays inside the road (apex %.2f, ends %.2f)" % [late.apex_y, late.end_y])
	_check(late.c < k, "turn-in only still flattens the bend")
	_near(RivalDriver.bend_line(0.0, 300.0, 100.0, 100.0, 10.4, 0.0).c, 0.0, 1e-9, "no bend, no line")

func _built_line() -> void:
	# A written road: 400 m straight, a 350 m left 150 m long, 400 m straight,
	# a 150 m right 100 m long, straight on.
	RoadAlignment.scripted = [[0.0, 8], [350.0, 3], [0.0, 8], [-150.0, 2], [0.0, 400]]
	RoadFrame.origin_index = 0
	RoadFrame.layout = null
	RoadFrame.align = RoadAlignment.new(1, 1.0)
	_near(RoadFrame.curvature(8), 1.0 / 350.0, 1e-9, "written road: chunk 8 is the 350 m left")
	_near(RoadFrame.curvature(19), -1.0 / 150.0, 1e-9, "written road: chunk 19 is the 150 m right")
	var d := RivalDriver.new(RivalPersonality.row("docks"), 7)
	var lane1 := TrafficManager.lane_centre(1, false)
	d.start_line(0.0, lane1)
	var lo := INF
	var hi := -INF
	# Driven along: the line forgets what is behind, so the checks below read
	# what it said at each place as it passed (and 300 m ahead of it).
	var at := {}
	var want := [100.0, 400.0 - 2.0 * 10.4 * 350.0 / 75.0, 475.0, 550.0 + 2.0 * 10.4 * 350.0 / 75.0, 700.0,
		950.0 - 2.0 * 10.4 * 150.0 / 50.0, 1000.0, 1050.0 + 2.0 * 10.4 * 150.0 / 50.0]
	var v := PackedFloat32Array()
	d.v_top = 90.0
	var s := 0.0
	while s < 1600.0:
		d.extend_line(s)
		var x := d.line_x(s)
		lo = minf(lo, x)
		hi = maxf(hi, x)
		for w: float in want:
			if w >= s and w < s + 2.5:
				at[w] = d.line_x(w)
		if s == 700.0:
			d.plan_speeds(700.0)
			v = d.profile().duplicate()
		s += 2.5
	var lx := func(w: float) -> float: return at.get(w, NAN)
	_near(lx.call(100.0), lane1, 1e-6, "holds its lane on the straight")
	# Left bend, chunks 8-10 (400-550 m): outside is the high edge.
	var e350 := 2.0 * 10.4 * 350.0 / 75.0
	_near(lx.call(400.0 - e350), 12.0, 1e-6, "left bend: 1.2 m from the outer edge at turn-in (x 12.0)")
	_near(lx.call(475.0), 1.6, 1e-6, "left bend: apex mid bend, 1.2 m from the centre-side edge (x 1.6)")
	_near(lx.call(550.0 + e350), 12.0, 1e-6, "left bend: back outside on exit")
	_near(lx.call(700.0), 12.0, 1e-6, "holds the exit x down the straight")
	# Right bend, chunks 19-20 (950-1050 m): outside is the centre side.
	var e150 := 2.0 * 10.4 * 150.0 / 50.0
	_near(lx.call(950.0 - e150), 1.6, 1e-6, "right bend: moved across to the centre side by turn-in (x 1.6)")
	_near(lx.call(1000.0), 12.0, 1e-6, "right bend: apex mid bend at the outer edge side (x 12.0)")
	_near(lx.call(1050.0 + e150), 1.6, 1e-6, "right bend: back to the centre side on exit")
	_check(lo >= 1.6 - 1e-6 and hi <= 12.0 + 1e-6, "line stays inside its side, never over the centre line (%.3f to %.3f)" % [lo, hi])
	print("built line: x from %.2f to %.2f m; apexes at x %.2f (left) and %.2f (right)" % [lo, hi, lx.call(475.0), lx.call(1000.0)])
	# The speed plan on that road, 250 m before the right bend: the bend is
	# planned on the line's flatter path, and the braking pass reaches back.
	var c150 := (1.0 / 150.0) * 100.0 / (100.0 + 2.0 * e150)
	var apex_i := int((1000.0 - 700.0) / RivalDriver.STEP) - 1
	_near(v[apex_i], sqrt(0.84 * 8.0 / c150), 0.01, "plan: bend speed is the line's, not the road's")
	_check(v[apex_i] > RivalDriver.corner_speed(1.0 / 150.0, 0.84, 8.0, 90.0) + 5.0, "plan: the line is worth speed over the lane centre")
	var b := RivalDriver.BRAKE_DECEL * 0.85
	for i in RivalDriver.SAMPLES - 1:
		if v[i] * v[i] > v[i + 1] * v[i + 1] + 2.0 * b * RivalDriver.STEP + 0.01:
			_check(false, "plan: sample %d needs more than its braking to reach the next" % i)
			break
	print("plan 250 m before the 150 m bend: now %.1f m/s, at the bend %.1f m/s (lane centre would be %.1f)" % [
		v[0], v[apex_i], RivalDriver.corner_speed(1.0 / 150.0, 0.84, 8.0, 90.0)])

func _seeded() -> void:
	var row := RivalPersonality.row("docks")
	_check(is_equal_approx(row.commit, 0.84) and is_equal_approx(row.brake_late, 0.85) and is_equal_approx(row.margin, 0.15)
		and is_equal_approx(row.lc_gap_t, 0.35) and row.shoulder == false and row.block == false and is_equal_approx(row.mistake_rate, 0.05),
		"Docks crew row")
	_check(RivalPersonality.row("nobody") == row, "unknown crew gets the Docks row")
	var a := RivalDriver.new(row, 4242)
	var b := RivalDriver.new(row, 4242)
	var c := RivalDriver.new(row, 4243)
	var same := true
	var differs := false
	for n in 16:
		var ra := a.rng.randf()
		same = same and ra == b.rng.randf()
		differs = differs or ra != c.rng.randf()
	_check(same, "same seed, same draws")
	_check(differs, "another seed, other draws")
	# And the same plan: two drivers on the same road agree to the last bit.
	for d: RivalDriver in [a, b]:
		d.start_line(0.0, 5.2)
		d.extend_line(300.0)
		d.plan_speeds(300.0)
	_check(a.profile() == b.profile(), "same seed and road, same speed plan")
	_near(a.commit, 0.84, 1e-9, "driver reads commit from its row")
	_near(a.brake_late, 0.85, 1e-9, "driver reads brake_late from its row")

func _near(got: float, want: float, tol: float, what: String) -> void:
	_check(absf(got - want) <= tol, "%s: got %.6f, want %.6f" % [what, got, want])

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		printerr("FAIL: ", what)
