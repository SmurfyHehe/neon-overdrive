extends SceneTree

# Breakable world I1 (2026-10-11): the swap-on-hit core, scripts/world/prop_break.gd.
#
# 1. Table: every active kind is stood in the car's lane and hit at 30, 80,
#    150 and 250 km/h with the left corner, the centre and the right corner,
#    the car coasting with the wheel straight. Per hit:
#      - the speed lost is within 1 km/h of PropBreak.loss_for(kind, speed)
#        (coasting drag, read from the tick before, is taken off);
#      - the nose turns by the kind's amount toward the hit corner (EXPECT
#        below, degrees, the largest swing in the 1.5 s after) and not at
#        all for a centre hit or a kind with no nudge;
#      - no spin (heading back inside 8 degrees, turning under 0.2 rad/s) and
#        no wheel off the ground for more than a couple of ticks;
#      - the prop is marked gone, and the pools stay inside their caps.
# 2. A real post from the chunk's own record is hit: it bends, in place. The
#    post and its run-up are on a plain stretch of shoulder: no gas station
#    lot or its taper (the lot's walls stand where the car's right side runs)
#    and no slip lane opening or closing (the post line bends outward there).
# 3. Layers: a rolling prop is on its own layer, which neither the car body
#    nor a wheel looks at.
# 4. Spree: 20 props in a row at 100 km/h. The caps hold (16 flying, 4
#    rolling, 8 bending, 32 debris a chunk), everything comes to rest as
#    debris, and the breaker's tick stays under the 0.3 ms ceiling (mean and
#    95th percentile; the single worst tick is printed, a busy laptop can
#    spike it).
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 120 --path . -s res://tests/world/prop_hit.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const Props := preload("res://scripts/world/roadside_props.gd")
const PropBreak := preload("res://scripts/world/prop_break.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const GasStation := preload("res://scripts/world/gas_station.gd")

const RATE := 120
const SPEEDS := [30.0, 80.0, 150.0, 250.0]
const CORNERS := [-0.8, 0.0, 0.8]
const LANE := 1
## Largest heading swing for a full corner hit, degrees [low, high], by kind.
const EXPECT := {
	Props.SIGN: [0.4, 2.0],
	Props.HYDRANT: [1.0, 3.0],
	Props.LAMP: [2.0, 4.5],
}
const STRAIGHT_DEG := 1.0

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var breaker: Node3D
var fails: Array[String] = []
var half := Vector3.ZERO

var cases: Array = []         # [kind, speed, corner]
var case_i := -1
var phase := "boot"
var t := 0
var hits_before := 0
var v_hist := PackedFloat32Array([0.0, 0.0, 0.0])
var yaw0 := 0.0
var swing := 0.0
var swing_signed := 0.0
var air_run := 0
var air_worst := 0
var measured_loss := 0.0
var prop_ref: Array = []
var spree_cost := PackedFloat32Array()
var spree_hits0 := 0
var spree_water := 0.0
var max_fly := 0
var max_roll := 0
var max_bend := 0

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL ", msg)

func _initialize() -> void:
	OS.add_logger(logger)
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_POLICE", "0")
	Engine.physics_ticks_per_second = RATE
	game = Harness.boot(self, 0, 300.0, 4242, 1e7)
	for kind in PropBreak.ACTIVE:
		for v in SPEEDS:
			for c in CORNERS:
				cases.append([kind, v, c])

func _coast(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

func _yaw() -> float:
	var f := RoadFrame.dir_to_road(RoadFrame.unroll(p.global_position).z, -p.global_transform.basis.z)
	return atan2(-f.x, -f.z)   # + = nose to the left of the road's direction

func _airborne() -> bool:
	for w in p.wheel_array:
		if not w.is_colliding():
			return true
	return false

func _physics_process(_delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
			p = null
			return false
		breaker = game.get("breaker")
		if breaker == null:
			_fail("the game has no breaker")
			return _end()
		half = breaker._half_of(p)
		p.driver = _coast
		_layers()
		_next_case()
		return false
	t += 1
	v_hist[0] = v_hist[1]
	v_hist[1] = v_hist[2]
	v_hist[2] = p.linear_velocity.length() * 3.6
	max_fly = maxi(max_fly, breaker.flying())
	max_roll = maxi(max_roll, breaker.rolling())
	max_bend = maxi(max_bend, breaker.bending())
	var bad := TestDriver.sanity(p)
	if bad != "":
		_fail("car state in %s: %s" % [phase, bad])
		return _end()
	match phase:
		"approach":
			if breaker.hits > hits_before:
				# the breaker ran after this script last tick: v_hist[1] is the
				# speed going in, [2] the speed after the push and one tick of drag
				measured_loss = (v_hist[1] - v_hist[2]) - (v_hist[0] - v_hist[1])
				yaw0 = _yaw_before
				swing = 0.0
				swing_signed = 0.0
				air_run = 0
				air_worst = 0
				phase = "after"
				t = 0
			elif t > RATE * 4:
				_fail("%s: the car never reached the prop" % _case_name())
				_next_case()
			_yaw_before = _yaw()
		"after":
			var d := rad_to_deg(wrapf(_yaw() - yaw0, -PI, PI))
			if absf(d) > swing:
				swing = absf(d)
				swing_signed = d
			air_run = air_run + 1 if _airborne() else 0
			air_worst = maxi(air_worst, air_run)
			if t >= int(RATE * 1.5):
				_judge(d)
				_next_case()
		"real_post":
			if breaker.hits > hits_before:
				if breaker.bending() < 1:
					_fail("real post: hit but nothing is bending")
				var rec: Dictionary = Props.of(_root_of(int(breaker.last.chunk)))
				if int(rec.kind[int(breaker.last.index)]) != Props.POST:
					_fail("real post: hit a %s instead" % Props.NAMES[rec.kind[int(breaker.last.index)]])
				print("real post: bent at %.0f km/h, %.1f km/h lost" % [breaker.last.speed_kmh, breaker.last.loss_kmh])
				_start_spree()
			elif t > RATE * 6:
				_fail("real post: never hit")
				_start_spree()
		"spree":
			spree_cost.append(breaker.cost_usec)
			spree_water += float(breaker.get("water_usec")) if breaker.get("water_usec") != null else 0.0
			if t >= RATE * 7:
				_judge_spree()
				return _end()
	return false

var _yaw_before := 0.0

func _case_name() -> String:
	var c: Array = cases[case_i]
	return "%s at %.0f km/h, %s" % [Props.NAMES[c[0]], c[1], "left corner" if c[2] < 0.0 else ("right corner" if c[2] > 0.0 else "centre")]

func _root_of(chunk: int) -> Node3D:
	for e in game.get("chunk_pool"):
		if int(e.index) == chunk:
			return e.root
	return null

func _place(speed_kmh: float, x: float, ahead := 0.0) -> void:
	p.damage.garage_repair(null)
	TestDriver.place(p, x, ahead, 0.0, speed_kmh / 3.6)
	p.damage.forget_motion()

func _next_case() -> void:
	case_i += 1
	if case_i >= cases.size():
		_start_real_post()
		return
	var c: Array = cases[case_i]
	var x := Harness.lane_x(LANE)
	if breaker.get("water") != null:
		breaker.water.new_night()   # the last case's burst hydrant is not this case's wet road
	_place(float(c[1]), x)
	# far enough for the springs to settle before the hit
	var ahead := float(c[1]) / 3.6 * 0.7 + 6.0
	prop_ref = breaker.add_test_prop(int(c[0]), x + float(c[2]) * half.x, p.global_position, ahead)
	if prop_ref.is_empty():
		_fail("%s: no chunk to stand the prop on" % _case_name())
	hits_before = breaker.hits
	phase = "approach"
	t = 0

func _judge(end_deg: float) -> void:
	var c: Array = cases[case_i]
	var kind := int(c[0])
	var corner := float(c[2])
	var want_loss: float = PropBreak.loss_for(kind, float(breaker.last.speed_kmh))
	var line := "%-28s lost %5.2f km/h (want %5.2f)  swing %+5.2f deg  end %+5.2f  wheels off %d ticks" % [
		_case_name(), measured_loss, want_loss, swing_signed, end_deg, air_worst]
	print(line)
	if absf(measured_loss - want_loss) > 1.0:
		_fail("%s: lost %.2f km/h, want %.2f" % [_case_name(), measured_loss, want_loss])
	if EXPECT.has(kind) and corner != 0.0:
		var r: Array = EXPECT[kind]
		if swing < float(r[0]) or swing > float(r[1]):
			_fail("%s: nose swung %.2f deg, want %.1f..%.1f" % [_case_name(), swing, r[0], r[1]])
		# toward the hit corner: a right-corner hit turns the nose right (negative)
		if signf(swing_signed) != -signf(corner):
			_fail("%s: nose swung away from the hit corner" % _case_name())
	elif swing > STRAIGHT_DEG:
		_fail("%s: nose swung %.2f deg, want under %.1f" % [_case_name(), swing, STRAIGHT_DEG])
	if absf(end_deg) > 8.0 or absf(p.angular_velocity.y) > 0.2:
		_fail("%s: spinning (heading %.1f deg, turning %.2f rad/s)" % [_case_name(), end_deg, p.angular_velocity.y])
	if air_worst > 3:
		_fail("%s: a wheel was off the ground for %d ticks" % [_case_name(), air_worst])
	if not prop_ref.is_empty():
		var root := _root_of(int(prop_ref[0]))
		if root != null and (root.get_meta("props_gone") as PackedByteArray)[int(prop_ref[1])] != 1:
			_fail("%s: the prop is not marked gone" % _case_name())

func _layers() -> void:
	var bit := 1 << (CarSpec.PROP_LAYER - 1)
	if p.collision_mask & bit:
		_fail("layers: the car body looks at the prop layer")
	for w in p.wheel_array:
		if w.collision_mask & bit:
			_fail("layers: a wheel looks at the prop layer")
			break

## Run-up to the real post, m (a little over 3 s at 60 km/h).
const POST_RUN_UP := 50.0

## Whether the own-side shoulder from road distance s0 to s1 is plain: no gas
## station lot or the taper before it, no ring site's ramps, and no slip lane
## opening or closing (the edge, and so the post line, runs straight).
func _plain_shoulder(s0: float, s1: float) -> bool:
	var s := s0
	while s <= s1 + 0.01:
		var c := floori(s / Props.CHUNK_LEN)
		var z := -(s - float(c) * Props.CHUNK_LEN)
		if GasStation.in_frontage(c, z, 1) or RoadMap.ramp_zone(c):
			return false
		var aux: Vector2 = RoadMap.aux(c)
		if not is_equal_approx(aux.x, aux.y):
			return false
		s += 5.0
	return true

func _start_real_post() -> void:
	# The nearest own-side post at least 40 m ahead with a plain run-up, from
	# the chunk's record; the car starts POST_RUN_UP before it. (Since the ring
	# sites, the gas stations sit on the slip lanes past a ring: a start beside
	# Fuel 7A put the car's flank into the lot wall and aimed it at a post on
	# the next ring's widening slip lane, which it never reached.)
	var u := RoadFrame.unroll(p.global_position)
	var s := RoadFrame.s_at(u.z)
	var here := floori(s / Props.CHUNK_LEN)
	var best := INF
	var post_x := 0.0
	for c in range(here + 1, here + 7):
		var root := _root_of(c)
		if root == null:
			continue
		var rec: Dictionary = Props.of(root)
		for i in rec.kind.size():
			if rec.kind[i] != Props.POST or rec.side[i] != 1 or rec.slot[i] < 0:
				continue
			var ahead: float = float(c) * Props.CHUNK_LEN - rec.road[i].y - s
			if ahead > 40.0 and ahead < best and _plain_shoulder(s + ahead - POST_RUN_UP, s + ahead + 5.0):
				best = ahead
				post_x = rec.road[i].x
	if best == INF:
		_fail("real post: no post with a plain run-up within six chunks")
		_start_spree()
		return
	# the right-hand corner just reaches the post line; the wheels stay off the kerb
	_place(60.0, post_x - half.x * 0.9, best - POST_RUN_UP)
	hits_before = breaker.hits
	phase = "real_post"
	t = 0

func _start_spree() -> void:
	var x := Harness.lane_x(LANE)
	_place(100.0, x)
	spree_hits0 = breaker.hits
	# the spree of the budget: flying and rolling things, and one hydrant
	var kinds: Array = [Props.CONE, Props.BIN, Props.CONE, Props.POST, Props.CONE]
	var stood := 0
	for k in 20:
		var kind := int(kinds[k % kinds.size()])
		if k == 10 and Props.HYDRANT in PropBreak.ACTIVE:
			kind = Props.HYDRANT
		var ref: Array = breaker.add_test_prop(kind, x + (float(k % 3) - 1.0) * 0.6, p.global_position, 20.0 + float(k) * 2.5)
		if not ref.is_empty():
			stood += 1
	if stood < 20:
		_fail("spree: only %d of 20 props could be stood" % stood)
	breaker.reset_cost()
	spree_cost.clear()
	max_fly = 0
	max_roll = 0
	max_bend = 0
	phase = "spree"
	t = 0

func _judge_spree() -> void:
	var n: int = breaker.hits - spree_hits0
	spree_cost.sort()
	var mean := 0.0
	for c in spree_cost:
		mean += c
	mean /= maxf(float(spree_cost.size()), 1.0)
	var p95 := spree_cost[int(float(spree_cost.size()) * 0.95)]
	var peak := spree_cost[spree_cost.size() - 1]
	print("spree: %d hits; most at once: %d flying, %d rolling, %d bending; breaker tick mean %.1f us (water %.1f of it), 95th %.1f us, worst %.1f us (ceiling %.0f)" % [
		n, max_fly, max_roll, max_bend, mean, spree_water / maxf(float(spree_cost.size()), 1.0), p95, peak, PropBreak.CEILING_USEC])
	if n < 20:
		_fail("spree: %d of 20 props were hit" % n)
	if max_fly > PropBreak.MAX_FLYERS or max_roll > PropBreak.MAX_ROLLERS or max_bend > PropBreak.MAX_BENDS:
		_fail("spree: a pool went over its cap")
	if breaker.flying() != 0 or breaker.rolling() != 0:
		_fail("spree: %d flying and %d rolling pieces never came to rest" % [breaker.flying(), breaker.rolling()])
	var debris := 0
	for e in game.get("chunk_pool"):
		var d: int = breaker.debris_count(int(e.index))
		debris += d
		if d > PropBreak.DEBRIS_PER_CHUNK:
			_fail("spree: chunk %d holds %d debris copies" % [int(e.index), d])
	if debris == 0:
		_fail("spree: nothing froze into debris")
	if mean > PropBreak.CEILING_USEC or p95 > PropBreak.CEILING_USEC:
		_fail("spree: the breaker's tick is over the ceiling (mean %.1f us, 95th %.1f us)" % [mean, p95])

func _end() -> bool:
	if not logger.errors.is_empty():
		_fail("%d script errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	print("prop_hit: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
