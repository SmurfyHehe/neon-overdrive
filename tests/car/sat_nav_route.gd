extends SceneTree

# The sat-nav's route finder (scripts/car/sat_nav_route.gd, 2026-10-11): pure
# logic on the map's numbers, so no game is booted.
#
# Checks:
# 1. Loop 1, act 1: the Shop's exit 300 m ahead is one exit step, 300 m.
# 2. The Shop's exit just behind: turning round twice (at the gaps at 625 and
#    225) beats going round the loop with the 1500 m penalty and loses to it
#    with a 3000 m one; every turn sits on a gap or a crossing.
# 3. Fuel 2 is on the other carriageway: one turn at a legal spot, then an
#    exit on side -1.
# 4. A route across the lap seam.
# 5. Acts 2 and 3: the same answers where the loop is the same, and routes
#    into the new districts use their gaps and exits.
# 6. A made-up two-loop city: the route each way takes the interchange.
# 7. progress(): driving past the exit sets missed exactly once, and replan()
#    finds the next legal way.
# 8. 1000 plan() calls on the act 3 loop: the mean time.
#
# Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/car/sat_nav_route.gd

const RoadMap := preload("res://scripts/world/road_map.gd")
const SatNavRoute := preload("res://scripts/car/sat_nav_route.gd")

var failures: Array[String] = []
var checks := 0

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failures.append(msg)

func _kinds(route: Dictionary) -> String:
	var out: Array = []
	for st: Dictionary in route.steps:
		out.append("%s %s@%d" % [st.kind, st.id, int(st.s)])
	return ", ".join(out)

func _line(route: Dictionary) -> String:
	return "[%s] total %d m, cost %d" % [_kinds(route), int(route.total_m), int(route.cost_m)]

## Every turn-round of a route is at a gap or a crossing of the road in use.
func _turns_legal(route: Dictionary) -> bool:
	for st: Dictionary in route.steps:
		if st.kind != "turn_around":
			continue
		var ok := false
		for g: Dictionary in RoadMap.gaps():
			ok = ok or is_equal_approx(float(g.s), float(st.s))
		for c in RoadMap.junctions():
			ok = ok or is_equal_approx(c, float(st.s))
		if not ok:
			return false
	return true

func _turn_count(route: Dictionary) -> int:
	var n := 0
	for st: Dictionary in route.steps:
		if st.kind == "turn_around":
			n += 1
	return n

func _initialize() -> void:
	# --- 1-4: Loop 1 as it is in act 1 (6400 m) ---
	RoadMap.use(0, 1)
	var nav: RefCounted = SatNavRoute.new().build()
	print("act 1: loop %d m, %d graph points, crossings at %s" % [int(RoadMap.length()), nav.point_count(), RoadMap.junctions()])

	var r: Dictionary = nav.plan_to_stop({"road": 0, "s": 100.0, "dir": 1}, "shop")
	print("1. s 100 dir +1 to the Shop: ", _line(r))
	_check(r.ok and r.steps.size() == 1 and r.steps[0].kind == "exit" and r.steps[0].id == "x1a"
		and is_equal_approx(r.steps[0].s, 400.0) and is_equal_approx(r.total_m, 300.0), "1: want one exit step at 400, 300 m")

	r = nav.plan_to_stop({"road": 0, "s": 500.0, "dir": 1}, "shop")
	print("2. s 500 dir +1 to the Shop, penalty 1500: ", _line(r))
	_check(_turn_count(r) == 2 and r.steps.size() == 3 and is_equal_approx(r.steps[0].s, 625.0)
		and is_equal_approx(r.steps[1].s, 225.0) and r.steps[2].kind == "exit", "2: want turns at 625 and 225, then the exit")
	_check(is_equal_approx(r.total_m, 700.0) and is_equal_approx(r.cost_m, 3700.0), "2: want 700 m driven, cost 3700")
	_check(int(r.steps[0].dir) == 1 and int(r.steps[1].dir) == -1 and int(r.steps[2].dir) == 1, "2: leg directions +1, -1, +1")
	_check(_turns_legal(r), "2: a turn off a gap or crossing")
	var dear: RefCounted = SatNavRoute.new().build({}, RoadMap.STOPS, RoadMap.INTERCHANGES, 3000.0)
	var r2: Dictionary = dear.plan_to_stop({"road": 0, "s": 500.0, "dir": 1}, "shop")
	print("2. the same, penalty 3000: ", _line(r2))
	_check(_turn_count(r2) == 0 and r2.steps.size() == 1 and is_equal_approx(r2.total_m, RoadMap.length() - 100.0),
		"2: with a 3000 m penalty, want straight on round the loop")

	r = nav.plan_to_stop({"road": 0, "s": 100.0, "dir": 1}, "fuel_2")
	print("3. s 100 dir +1 to Fuel 2: ", _line(r))
	_check(_turn_count(r) == 1 and _turns_legal(r) and r.steps[-1].kind == "exit" and r.steps[-1].id == "x7b"
		and int(r.steps[-1].dir) == -1, "3: want one legal turn and the exit on side -1")
	_check(is_equal_approx(r.steps[0].s, 225.0) and is_equal_approx(r.total_m, 125.0 + 225.0 + 1200.0), "3: want the first gap ahead (225), 1550 m")

	r = nav.plan_to_stop({"road": 0, "s": 6300.0, "dir": 1}, "shop")
	print("4. s 6300 dir +1 to the Shop (over the seam): ", _line(r))
	_check(r.steps.size() == 1 and is_equal_approx(r.total_m, 500.0), "4: want 500 m, no turn")

	# --- 7: progress and replan, still act 1 ---
	r = nav.plan_to_stop({"road": 0, "s": 100.0, "dir": 1}, "shop")
	var missed := 0
	var p: Dictionary = {}
	var log_7: Array = []
	for s in [100.0, 250.0, 390.0, 410.0, 450.0, 520.0]:
		p = nav.progress(r, {"road": 0, "s": s, "dir": 1})
		log_7.append("%d:%s%d" % [int(s), "MISSED " if p.missed else "", int(p.next_m)])
		if p.missed:
			missed += 1
		if is_equal_approx(s, 250.0):
			_check(p.next_kind == "exit" and is_equal_approx(p.next_m, 150.0) and is_equal_approx(p.left_m, 150.0), "7: 150 m to the exit at s 250")
	print("7. driving past the Shop's exit (s:next_m): ", " ".join(log_7))
	_check(missed == 1, "7: missed must be true exactly once, got %d" % missed)
	var again: Dictionary = nav.replan(r, {"road": 0, "s": 410.0, "dir": 1})
	print("7. replan from s 410: ", _line(again))
	_check(again.ok and _turn_count(again) == 2 and is_equal_approx(again.steps[0].s, 625.0) and _turns_legal(again)
		and again.steps[-1].id == "x1a", "7: replan wants the gap at 625, then 225, then the exit")
	# Following the new route: turn-rounds tick themselves off, the exit by advance().
	var log_f: Array = []
	for place: Dictionary in [{"s": 500.0, "dir": 1}, {"s": 620.0, "dir": 1}, {"s": 630.0, "dir": -1}, {"s": 300.0, "dir": -1},
			{"s": 220.0, "dir": 1}, {"s": 390.0, "dir": 1}]:
		place.road = 0
		p = nav.progress(again, place)
		log_f.append("%d/%+d:%s %d (left %d)" % [int(place.s), int(place.dir), p.next_kind, int(p.next_m), int(p.left_m)])
		_check(not p.missed, "7: no miss while following the new route at s %d" % int(place.s))
	print("7. following it: ", ", ".join(log_f))
	_check(p.next_kind == "exit" and is_equal_approx(p.next_m, 10.0) and is_equal_approx(p.left_m, 10.0), "7: 10 m to the exit at the end")
	nav.advance(again)
	_check(nav.progress(again, {"road": 0, "s": 400.0, "dir": 1}).done, "7: done after the exit is taken")
	# Heading flipped away from any turn spot: missed.
	r = nav.plan_to_stop({"road": 0, "s": 100.0, "dir": 1}, "shop")
	_check(nav.progress(r, {"road": 0, "s": 150.0, "dir": -1}).missed, "7: facing the wrong way is a miss")
	# A place that is not an exit: arriving is passing it.
	r = nav.plan({"road": 0, "s": 100.0, "dir": 1}, {"road": 0, "s": 300.0, "side": 1})
	_check(r.steps[-1].kind == "arrive" and is_equal_approx(r.total_m, 200.0), "7: a plain place ends in arrive")
	nav.progress(r, {"road": 0, "s": 290.0, "dir": 1})
	p = nav.progress(r, {"road": 0, "s": 305.0, "dir": 1})
	_check(p.done and not p.missed, "7: passing a plain place is arriving")

	# --- 5: acts 2 and 3 ---
	for act in [2, 3]:
		RoadMap.use(0, act)
		var big: RefCounted = SatNavRoute.new().build()
		var lap := RoadMap.length()
		var a: Dictionary = big.plan_to_stop({"road": 0, "s": 100.0, "dir": 1}, "shop")
		var b: Dictionary = big.plan_to_stop({"road": 0, "s": 500.0, "dir": 1}, "shop")
		var c: Dictionary = big.plan_to_stop({"road": 0, "s": 100.0, "dir": 1}, "fuel_2")
		# Into the act's new districts: exit x10b (7600, side -1) from s 7000 dir +1.
		var d: Dictionary = big.plan({"road": 0, "s": 7000.0, "dir": 1}, {"road": 0, "s": 7600.0, "side": -1})
		print("5. act %d (%d m, %d points): shop ahead %s | shop behind %s | fuel 2 %s | x10b %s" % [act, int(lap),
			big.point_count(), _line(a), _line(b), _line(c), _line(d)])
		_check(is_equal_approx(a.total_m, 300.0) and a.steps.size() == 1, "5: act %d shop ahead" % act)
		_check(is_equal_approx(b.total_m, 700.0) and _turn_count(b) == 2 and _turns_legal(b), "5: act %d shop behind" % act)
		# Fuel 2 (5200, side -1): turn at the first gap (225) and drive back over
		# the seam, or drive on to the gap past it (5425) and come back 225 m,
		# whichever is shorter on a loop this long.
		var back := 125.0 + 225.0 + (lap - 5200.0)
		var on := 5325.0 + 225.0
		_check(_turn_count(c) == 1 and _turns_legal(c) and c.steps[-1].id == "x7b"
			and is_equal_approx(c.steps[0].s, 225.0 if back < on else 5425.0)
			and is_equal_approx(c.total_m, minf(back, on)), "5: act %d fuel 2" % act)
		_check(_turn_count(d) == 1 and _turns_legal(d) and is_equal_approx(d.steps[0].s, 7825.0) and d.steps[-1].id == "x10b"
			and is_equal_approx(d.total_m, 825.0 + 225.0), "5: act %d x10b by the gap at 7825" % act)

	# --- 8: timing on the act 3 loop (RoadMap is on act 3 here) ---
	var t0 := Time.get_ticks_usec()
	var act3: RefCounted = SatNavRoute.new().build()
	var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var lap3 := RoadMap.length()
	var stops := ["shop", "fuel_1", "fuel_2"]
	var sum := 0.0
	t0 = Time.get_ticks_usec()
	for i in 1000:
		var route: Dictionary = act3.plan_to_stop({"road": 0, "s": fmod(float(i) * 137.0, lap3), "dir": 1 if i % 2 == 0 else -1}, stops[i % 3])
		sum += route.total_m
	var mean_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 1000.0
	var live: Dictionary = act3.plan_to_stop({"road": 0, "s": 100.0, "dir": 1}, "fuel_2")
	t0 = Time.get_ticks_usec()
	for i in 10000:
		act3.progress(live, {"road": 0, "s": 100.0 + float(i) * 0.01, "dir": 1})
	var progress_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 10000.0
	print("8. act 3: build %.2f ms once; plan mean %.4f ms over 1000 calls (mean route %d m); progress mean %.4f ms" % [build_ms,
		mean_ms, int(sum / 1000.0), progress_ms])
	_check(mean_ms < 0.05, "8: plan mean %.4f ms, want well under 0.1" % mean_ms)

	# --- 6: a made-up city of two loops joined by one interchange ---
	var city := {
		0: {"length": 4000.0, "exits": [{"id": "a1", "s": 500.0, "side": 1}], "gaps": [{"id": "ga", "s": 2000.0}], "junctions": []},
		1: {"length": 3000.0, "exits": [{"id": "b1", "s": 1500.0, "side": 1}, {"id": "b2", "s": 2500.0, "side": -1}],
			"gaps": [{"id": "gb", "s": 200.0}], "junctions": []},
	}
	var city_stops := [{"id": "home", "road": 0, "exit": "a1"}, {"id": "far", "road": 1, "exit": "b1"}, {"id": "back", "road": 1, "exit": "b2"}]
	var joins := [{"id": "i1", "a": {"road": 0, "s": 1000.0}, "b": {"road": 1, "s": 1000.0}, "kind": "ramp", "length": 200.0}]
	var two: RefCounted = SatNavRoute.new().build(city, city_stops, joins)
	var out: Dictionary = two.plan_to_stop({"road": 0, "s": 400.0, "dir": 1}, "far")
	print("6. loop A s 400 to loop B's b1: ", _line(out))
	_check(out.ok and out.steps.size() == 2 and out.steps[0].kind == "keep_right" and out.steps[0].id == "i1"
		and int(out.steps[0].to_road) == 1 and out.steps[1].id == "b1" and is_equal_approx(out.total_m, 600.0 + 200.0 + 500.0),
		"6: want keep at i1 then b1, 1300 m")
	var home: Dictionary = two.plan_to_stop({"road": 1, "s": 1400.0, "dir": -1}, "home")
	print("6. loop B s 1400 dir -1 to loop A's a1: ", _line(home))
	_check(home.ok and home.steps[0].kind == "keep_right" and int(home.steps[0].to_road) == 0 and home.steps[-1].id == "a1", "6: want keep at i1 then a1")
	# Onto the other loop's far carriageway, and the interchange ticked off by progress().
	var other: Dictionary = two.plan_to_stop({"road": 0, "s": 400.0, "dir": 1}, "back")
	print("6. loop A s 400 to loop B's b2 (side -1): ", _line(other))
	_check(other.ok and other.steps[0].kind == "keep_right" and int(other.steps[-1].dir) == -1 and _turn_count(other) == 0
		and is_equal_approx(other.total_m, 600.0 + 200.0 + 1500.0), "6: the interchange lands on either carriageway")
	p = two.progress(out, {"road": 0, "s": 900.0, "dir": 1})
	_check(p.next_kind == "keep_right" and is_equal_approx(p.next_m, 100.0) and is_equal_approx(p.left_m, 800.0), "6: 100 m to the interchange")
	p = two.progress(out, {"road": 1, "s": 1010.0, "dir": 1})
	_check(p.next_kind == "exit" and is_equal_approx(p.next_m, 490.0) and not p.missed, "6: on loop B the next step is the exit")
	# No way: a road the table does not have.
	_check(not two.plan({"road": 0, "s": 0.0, "dir": 1}, {"road": 7, "s": 0.0, "side": 1}).ok, "6: an unknown road is no route")

	RoadMap.use(RoadMap.ENDLESS)
	print("sat_nav_route: %d checks, %d failed" % [checks, failures.size()])
	for f in failures:
		print("  FAIL ", f)
	print("PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
