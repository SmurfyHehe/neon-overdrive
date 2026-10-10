extends SceneTree

# Off-map rescue test (2026-10-10, Roy: "driving off the map", step 1).
# One boot, one scenario after another. Each starts from the car standing in
# a lane, then puts or drives it somewhere and watches what happens.
#
# Placed (the guard itself): under the road, outside each wall, far above the
# road, on its roof outside the wall, behind the built road's end.
# Driven (the walls and the guard together): launched at the wall at
# LAUNCH_SPEEDS x LAUNCH_ANGLES, launched up and over the wall, turned round
# and driven back the wrong way until the road runs out.
# First of all a plain drive down a lane, which must NOT trigger a rescue.
#
# Asserts (exit code 1 on failure):
# - a placed scenario is rescued, exactly once, for the reason expected
# - a driven one ends inside the walls: held by them or rescued, never left
#   outside or under the road (which of the two is printed, not asserted)
# - after every rescue, within SETTLE seconds: every number finite, inside
#   the walls, at ride height, upright, 3+ wheels down, standing still,
#   pointing down the road, screen clear again
# - a rescue costs nothing: cash, bank and damage hits are unchanged
# - the plain drive is never rescued
# - no engine errors
# Also prints what the watch costs per tick, in microseconds.
#
# NEON_HILLS=1 NEON_CURVES=1 runs the same on hills and bends (no ground
# plane there: past the road's collision the car falls).
# NEON_OFFMAP_GUARD=0 switches the guard off and only reports what the walls
# hold by themselves (never fails): the before/after for wall changes.
# NEON_OFFMAP_LOG=1 prints the car every 0.1 s; NEON_OFFMAP_ONLY=<text> runs
# only the scenarios whose name contains it.
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/world/off_map_rescue.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const LAUNCH_SPEEDS := [20.0, 55.0, 68.0, 100.0, 150.0, 220.0]  # m/s; 68 is the fastest car today
const LAUNCH_ANGLES := [30.0, 89.0]  # degrees toward the wall
const SETTLE := 2.0  # s after the screen clears
const TIMEOUT := 8.0  # s for a scenario to play out

var rate := 120
var logger := Harness.ErrorCounter.new()
var game: Node
var rescue: OffMapRescue
var p: PlayerCar
var tick := 0
var fails: Array[String] = []
var guard := true
var log_ticks := false

var scenarios: Array = []
var index := -1
var stage := 0  # 0 standing in the lane, 1 playing out, 2 settling
var t := 0.0
var s := {}
var rest_y := 0.0
var count_before := 0
var money_before := 0
var hits_before := 0
var held := 0
var saved := 0

func _initialize() -> void:
	OS.add_logger(logger)
	ExhaustTune.save_path = "user://autotune/test_off_map_exhaust.json"
	Engine.physics_ticks_per_second = rate
	guard = OS.get_environment("NEON_OFFMAP_GUARD") != "0"
	log_ticks = OS.get_environment("NEON_OFFMAP_LOG") == "1"
	if guard:
		scenarios.append({"name": "plain drive, 12 s", "kind": "drive", "secs": 12.0, "expect": "none"})
		scenarios.append({"name": "placed 10 m under the road", "kind": "place", "x": 0.0, "y": -10.0, "expect": OffMapRescue.REASON_BELOW})
		scenarios.append({"name": "placed outside the right wall", "kind": "place", "side": 1.0, "out": 4.0, "expect": OffMapRescue.REASON_OUTSIDE})
		scenarios.append({"name": "placed outside the left wall", "kind": "place", "side": -1.0, "out": 4.0, "expect": OffMapRescue.REASON_OUTSIDE})
		scenarios.append({"name": "placed on its roof outside the wall", "kind": "place", "side": 1.0, "out": 4.0, "roof": true, "expect": OffMapRescue.REASON_OUTSIDE})
		scenarios.append({"name": "placed 100 m above the road", "kind": "place", "x": 0.0, "y": 100.0, "expect": OffMapRescue.REASON_ABOVE})
		scenarios.append({"name": "placed 80 m behind the road's end", "kind": "behind", "expect": "any"})
	for v: float in LAUNCH_SPEEDS:
		for a: float in LAUNCH_ANGLES:
			scenarios.append({"name": "into the wall, %3.0f m/s at %2.0f deg" % [v, a], "kind": "launch", "speed": v, "angle": a, "expect": "inside", "secs": 4.0})
	for v: float in [30.0, 60.0]:
		scenarios.append({"name": "thrown up and over the wall, %2.0f m/s" % v, "kind": "lob", "speed": v, "expect": "inside"})
	scenarios.append({"name": "turned round, driven back off the road's end", "kind": "reverse", "expect": "any", "secs": 40.0})
	var only := OS.get_environment("NEON_OFFMAP_ONLY")
	if only != "":
		scenarios = scenarios.filter(func(d: Dictionary) -> bool: return (d.name as String).contains(only))
	game = Harness.boot(self, 6, 300.0, 4242)

func _u() -> Vector3:
	return RoadFrame.unroll(p.global_position)

func _bounds(z: float) -> Vector2:
	return rescue._bounds_at(z)

func _inside(u: Vector3, inset: float) -> bool:
	var b := _bounds(u.z)
	return b != Vector2.ZERO and u.x < b.x - inset and u.x > -(b.y - inset) and u.y > -1.0

func _wheels_down() -> int:
	var n := 0
	for w in p.wheel_array:
		if (w as Wheel).is_colliding():
			n += 1
	return n

func _stand() -> void:
	p.driver = func(c: Vehicle) -> void:
		c.steering_input = 0.0
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.handbrake_input = 1.0

func _put(x: float, y: float, z: float, yaw: float, speed: float, basis_extra := Basis.IDENTITY) -> void:
	var xf := RoadFrame.pose(x, y, z, yaw)
	p.global_transform = Transform3D(xf.basis * basis_extra, xf.origin)
	TrafficCar.set_moving(p, speed)
	for w in p.wheel_array:
		w.last_collision_point = w.global_position
	p.reset_physics_interpolation()

func _begin() -> void:
	s = scenarios[index]
	stage = 0
	t = 0.0
	_stand()
	# Back in a lane on built road, standing, so the guard has a good spot.
	var u := _u()
	var z: float = u.z if _inside(u, 1.0) else rescue.target().z
	_put(Harness.lane_x(1), rest_y, z, 0.0, 0.0)

func _act() -> void:
	var u := _u()
	var b := _bounds(u.z)
	count_before = rescue.count
	var w: Object = game.get("wallet")
	money_before = int(w.get("cash")) + int(w.get("bank"))
	hits_before = p.damage.hits
	match s.kind:
		"drive":
			p.driver = Harness.lane_driver(Harness.lane_x(1), 1.0, 45.0)
		"place":
			var x: float = s.get("x", 0.0)
			if s.has("side"):
				var edge: float = b.x if s.side > 0.0 else b.y
				x = (edge + RoadChunkBuilder.BOUNDARY_T + s.out) * s.side
			var roof := Basis(Vector3.FORWARD, PI) if s.get("roof", false) else Basis.IDENTITY
			_put(x, s.get("y", rest_y + 0.3), u.z, 0.0, 0.0, roof)
		"behind":
			var lo := INF
			for c: Dictionary in game.chunk_pool:
				lo = minf(lo, float(c.index))
			var z := -(lo - float(game.origin_index)) * RoadChunkBuilder.CHUNK_LEN + 80.0
			_put(Harness.lane_x(1), rest_y + 0.2, z, 0.0, 0.0)
		"launch":
			var a := deg_to_rad(s.angle)
			var gap := clampf(s.speed * sin(a) * 0.4, 4.6, b.x - Harness.lane_x(0))
			_put(b.x - gap, rest_y, u.z, -a, s.speed)
			p.driver = func(c: Vehicle) -> void:
				c.steering_input = 0.0
				c.throttle_input = 1.0
				c.brake_input = 0.0
				c.handbrake_input = 0.0
		"lob":
			# 8 m short of the wall, pointing at it, thrown up at 70 degrees.
			_put(b.x - 8.0, rest_y, u.z, -PI / 2.0, 0.0)
			var out := RoadFrame.basis_at(u.z) * Vector3(1.0, 2.75, 0.0).normalized()
			p.linear_velocity = out * s.speed
		"reverse":
			_put(Harness.lane_x(1), rest_y, u.z, PI, 30.0)
			p.driver = func(c: Vehicle) -> void:
				# hold the lane the wrong way, as oncoming traffic steers (dir +1)
				var side_v := RoadFrame.dir_to_road(RoadFrame.unroll(c.global_position).z, c.linear_velocity).x
				c.steering_input = TrafficCar.lane_steer(c, Harness.lane_x(1) - side_v * Harness.LAT_DAMP_T, 1.0, 2.5, Harness.PLAYER_UNDERSTEER_FF)
				c.throttle_input = 1.0 if c.current_speed() < 45.0 else 0.0
				c.brake_input = 0.0
				c.handbrake_input = 0.0

func _physics_process(delta: float) -> bool:
	tick += 1
	if tick < rate:
		return false
	if tick == rate:
		p = game.get("player")
		rescue = game.get("rescue")
		rescue.enabled = guard
		rest_y = _u().y
		index = 0
		_begin()
		return false
	t += delta
	if log_ticks and tick % 12 == 0:
		var u := _u()
		print("  [%d/%d] t=%.1f u=(%.1f %.1f %.1f) v=%.1f up=%.2f phase=%d count=%d" % [index, stage, t, u.x, u.y, u.z, p.linear_velocity.length(), p.global_transform.basis.y.y, rescue.phase, rescue.count])
	match stage:
		0:
			if t >= 1.0:
				_act()
				stage = 1
				t = 0.0
		1:
			var rescued := rescue.count > count_before
			var limit: float = s.get("secs", TIMEOUT)
			if (rescued and rescue.phase == OffMapRescue.Phase.WATCH) or t >= limit or not guard and t >= 5.0:
				if s.kind != "drive":
					_stand()
				stage = 2
				t = 0.0
		2:
			if t >= SETTLE:
				_report()
				index += 1
				if index >= scenarios.size():
					return _end()
				_begin()
	return false

func _report() -> void:
	var bad: Array[String] = []
	var u := _u()
	var n := rescue.count - count_before
	var ok_inside := Harness.finite(p) and _inside(u, 0.0)
	var note := ""
	if not guard:
		note = "held by the wall" if ok_inside else "OUT (x %.1f, y %.1f)" % [u.x, u.y]
		if ok_inside:
			held += 1
		print("%-46s %s" % [s.name, note])
		return
	if s.expect == "none":
		if n != 0:
			bad.append("rescued %d time(s) on a plain drive (%s)" % [n, rescue.last_reason])
		note = "no rescue"
	elif s.expect == "inside":
		if n == 0:
			held += 1
			note = "held by the wall"
		else:
			saved += 1
			note = "rescued (%s)" % rescue.last_reason
		if not ok_inside:
			bad.append("left off the map (x %.1f, y %.1f)" % [u.x, u.y])
	else:
		note = "rescued (%s)" % rescue.last_reason
		if n != 1:
			bad.append("rescued %d times, expected 1" % n)
		elif s.expect == OffMapRescue.REASON_OUTSIDE and RoadFrame.has_hills() and rescue.last_reason == OffMapRescue.REASON_BELOW:
			pass  # on hills there is no ground out there: it may fall first
		elif s.expect != "any" and rescue.last_reason != s.expect:
			bad.append("reason '%s', expected '%s'" % [rescue.last_reason, s.expect])
	if n > 0:
		# what a rescue must leave behind
		if not Harness.finite(p):
			bad.append("non-finite state after the rescue")
		else:
			if not _inside(u, OffMapRescue.GOOD_INSET - 0.2):
				bad.append("not inside the walls after the rescue (x %.1f)" % u.x)
			if absf(u.y - rest_y) > 0.25:
				bad.append("not at ride height (%.2f m off)" % (u.y - rest_y))
			if p.global_transform.basis.y.y < 0.95:
				bad.append("not upright (up %.2f)" % p.global_transform.basis.y.y)
			if _wheels_down() < 3:
				bad.append("%d wheels down" % _wheels_down())
			if p.linear_velocity.length() > 1.0:
				bad.append("still moving at %.1f m/s" % p.linear_velocity.length())
			var fwd := RoadFrame.dir_to_road(u.z, -p.global_transform.basis.z)
			if fwd.z > -0.95:
				bad.append("not pointing down the road")
		if rescue.phase != OffMapRescue.Phase.WATCH or rescue._black.visible:
			bad.append("screen still dark")
		var w: Object = game.get("wallet")
		if int(w.get("cash")) + int(w.get("bank")) != money_before:
			bad.append("money changed")
		if p.damage.hits != hits_before and s.kind in ["place", "behind"]:
			bad.append("the rescue counted as a crash")
	print("%-46s %-36s %s" % [s.name, note, "ok" if bad.is_empty() else "FAIL " + ", ".join(bad)])
	for b in bad:
		fails.append("%s: %s" % [s.name, b])

func _end() -> bool:
	if logger.errors.size() > 0:
		fails.append("%d engine error(s): %s" % [logger.errors.size(), logger.errors[0]])
	if not guard:
		print("off_map_rescue (guard off): the walls held %d of %d" % [held, scenarios.size()])
		print("RESULT: PASS")
		quit(0)
		return true
	print("off_map_rescue: walls held %d, rescued %d of the driven scenarios; rescues in all %d" % [held, saved, rescue.count])
	# What the watch costs per physics tick (the benchmark's fps is too noisy
	# to show it): the same calls _watch makes, timed over 20000 ticks' worth.
	var t0 := Time.get_ticks_usec()
	for i in 20000:
		rescue.check()
		if i % OffMapRescue.REMEMBER_EVERY == 0:
			rescue._remember()
	print("off_map_rescue: the watch costs %.2f us per tick" % (float(Time.get_ticks_usec() - t0) / 20000.0))
	print("RESULT: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	for f in fails:
		print("  " + f)
	quit(0 if fails.is_empty() else 1)
	return true
