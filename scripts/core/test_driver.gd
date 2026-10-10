extends RefCounted

# The shared test driver (2026-10-10, Roy: "when you test you're not a good
# driver, you hit walls, cars etc" and "sometimes there is a need to test those
# but not at all times"). One bot for the headless tests, the benchmark, stress
# runs and for watching in the game itself. It drives through PlayerCar.driver,
# the same hook the older per-test bots use, and is picked by a named mode:
#
#   clean        holds a lane at `target_speed`, brakes for traffic, changes
#                lane only into a checked gap, slows for bends, recovers a spin.
#                Meant to touch nothing.
#   weave        clean, plus a lane change every `weave_period` seconds when a
#                gap is there (replaces the benchmark's blind timed lane swap).
#   grip         clean at the grip limit: bends at `GRIP_LAT_ACCEL`, throttle
#                eased when the car starts to slide.
#   aim          steers at `aim_point` (a world position) or `aim_node` and
#                holds `target_speed`: the crash-on-purpose mode.
#   brake_to     clean, stopping (or reaching `brake_speed`) at `brake_s`,
#                metres along the road.
#   flee         full speed away from `threat` (a Node3D), in whichever lane
#                has the most free road.
#   fuzz         seeded random keys through PlayerCar.apply_keys (the real key
#                path): the same `seed_value` gives the same key presses.
#   replay       plays `keys` back (a DriveRecorder file, or a fuzz run's log).
#   hold         fixed pedals and wheel: `hold_throttle`, `hold_brake`, `hold_steer`.
#   legacy_bench the benchmark's old bang-bang heading hold, full throttle,
#                never brakes; `legacy_weave` = its blind 4 s lane swap.
#   legacy_lane  (static legacy_lane()) the old traffic-harness lane keeper.
#
# The same switch starts it everywhere: start(game, mode, opts). The game calls
# it for `-- --bot=<mode> --speed=<km/h>` (or NEON_BOT / NEON_BOT_SPEED), in a
# window or headless; tests call it directly. See docs/TEST_DRIVER.md.
#
# Cost: only the steering runs every tick (the same pure pursuit the traffic
# cars use); everything that looks at traffic, the road ahead or a spin runs
# every PLAN_SECS and is cached. watch_contacts reads the body's contact count
# each tick and lists the contacts only while something is touching.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const KMH := 1.0 / 3.6
const PLAN_SECS := 0.05          # traffic and bend lookahead refresh
const HALF_W := 1.0              # TrafficManager.PLAYER_HALF_W
const HALF_L := 2.2
const SIDE_MARGIN := 0.35        # m of air wanted each side of the body
## Lane keeping. Pure pursuit to the lane centre (TrafficCar.lane_steer), aimed
## LAT_DAMP_T seconds of the car's own sideways speed short of it.
const LAT_DAMP_T := 3.0
const CHANGE_DAMP_T := 1.2
const UNDERSTEER_FF := 0.0008    # the player car's bend feed-forward (was Harness.PLAYER_UNDERSTEER_FF)
## Speed.
const CLEAN_LAT_ACCEL := 4.0     # m/s^2 in a bend, clean and weave
const GRIP_LAT_ACCEL := 8.0      # m/s^2, grip mode
const PLAN_DECEL := 5.0          # m/s^2 the bot plans its braking on
const BRAKE_FULL := 9.0          # m/s^2 a full brake pedal is worth
const SPEED_GAIN := 1.0          # throttle per m/s under the target
const T_GAP := 1.2               # s, following gap
const COAST_BAND := 1.5          # m/s over the target before the brakes come on
## Lane changes.
const CHANGE_DONE := 0.5         # m from the new lane centre = arrived
const GAP_BEHIND := 8.0          # m, plus CLOSE_SECS of the closing speed
const GAP_AHEAD := 10.0
const CLOSE_SECS := 3.0
const CHANGE_GAIN := 3.0         # m/s a lane must be faster by to be worth moving for
## Spin recovery.
const SPIN_SLIP := 0.45          # rad between nose and travel = spinning
const SPIN_MIN_SPEED := 6.0
const WRONG_WAY := 1.2           # rad off the road's heading at low speed = turn round
const TURN_LEG_SECS := 2.5
const TURN_DONE := 0.8           # rad: the lane keeper can take it from here

var mode := "clean"
var target_speed := 150.0 * KMH
var lane := 1
var seed_value := 1
var watch_contacts := true
var traffic: TrafficManager      # null = drive as if the road were empty
var game: Node
var wheelbase := 2.5

var weave_period := 4.0
var aim_point := Vector3.ZERO
var aim_node: Node3D
var brake_s := INF               # RoadFrame.s_at() to be at brake_speed by
var brake_speed := 0.0
var threat: Node3D
var hold_throttle := 0.0
var hold_brake := 0.0
var hold_steer := 0.0            # + = right, share of full lock
var legacy_weave := false
var keys := PackedInt32Array()   # replay input; fuzz appends what it pressed
var record_keys := false         # fuzz: keep the keys in `keys`

# ---- what happened (tests read these) ----
var ticks := 0
var wall_contacts := 0           # separate touches (rising edges)
var car_contacts := 0
var wall_ticks := 0
var car_ticks := 0
var first_contact := ""          # "wall <name>" / "car <name>" and the tick
var spins := 0
var lane_changes := 0
var refused_changes := 0         # wanted a lane, gap was not there
var max_lane_err := 0.0          # m off the wanted lane while not changing
var min_gap := INF               # closest it got to the car ahead, bumper to bumper
var replay_done := false

var _step := Callable()
var _rng := RandomNumberGenerator.new()
var _plan_left := 0.0
var _dt := 1.0 / 120.0
var _t := 0.0
var _gap := INF
var _lead_v := 0.0
var _bend_v := INF
var _changing := false
var _next_weave := 0.0
var _weave_dir := 1
var _touch_wall := false
var _touch_car := false
var _rec := 0                    # 0 driving, 1 stopping a spin, 2 turning round
var _rec_t := 0.0
var _rec_fwd := true
var _fuzz_keys := 0
var _fuzz_left := 0.0
var _legacy_t := 0.0
var _last_speed := 0.0
var _bend_here := 0.0             # |road curvature| under the car, from the last plan
var _check_spin := true

# ---------- starting it ----------

## The one switch. Puts a driver in `mode` on the game's player car and returns
## it. opts: speed (km/h), lane, seed, weave_period, traffic (false = ignore
## traffic), plus any of this object's fields by name.
static func start(game_node: Node, mode_name: String, opts := {}) -> RefCounted:
	var d: RefCounted = load("res://scripts/core/test_driver.gd").new()
	d.game = game_node
	d.traffic = game_node.get("traffic")
	d.configure(mode_name, opts)
	d.attach(game_node.get("player"))
	return d

## `-- --bot=<mode>` or NEON_BOT=<mode>; "" when neither is set.
static func requested_mode() -> String:
	var m := Benchmark.opt("bot")
	return m if m != "" else OS.get_environment("NEON_BOT")

## --replay=<file> or NEON_REPLAY: a DriveRecorder file to play back, "" = none.
static func requested_replay() -> String:
	var r := Benchmark.opt("replay")
	return r if r != "" else OS.get_environment("NEON_REPLAY")

## --speed=<km/h> or NEON_BOT_SPEED, as m/s; `fallback` (m/s) when absent.
static func requested_speed(fallback: float) -> float:
	var s := Benchmark.opt("speed")
	if not s.is_valid_float():
		s = OS.get_environment("NEON_BOT_SPEED")
	return float(s) * KMH if s.is_valid_float() else fallback

func configure(mode_name: String, opts := {}) -> void:
	for k in opts:
		match k:
			"speed":
				target_speed = float(opts[k]) * KMH
			"seed":
				seed_value = int(opts[k])
			"traffic":
				if opts[k] is bool and not opts[k]:
					traffic = null
			_:
				set(k, opts[k])
	set_mode(mode_name)

func set_mode(mode_name: String) -> void:
	mode = mode_name
	_rng.seed = seed_value
	_rec = 0
	match mode:
		"clean", "weave", "grip", "brake_to":
			_step = _drive_clean
		"aim":
			_step = _drive_aim
		"flee":
			_step = _drive_flee
		"fuzz":
			_step = _drive_fuzz
		"replay":
			_step = _drive_replay
		"hold":
			_step = _drive_hold
		"legacy_bench":
			_step = _drive_legacy_bench
		_:
			push_error("TestDriver: unknown mode '%s'" % mode)
			mode = "hold"
			_step = _drive_hold

func attach(c: PlayerCar) -> void:
	if c == null:
		return
	_dt = 1.0 / float(Engine.physics_ticks_per_second)
	wheelbase = 2.0 * float(PlayerCar.wheel_config(PlayerCar.chassis_kind()).get("axle_z", 1.25))
	c.driver = drive

func detach(c: PlayerCar) -> void:
	c.driver = Callable()

## PlayerCar calls this every physics tick instead of reading the keyboard.
func drive(c: PlayerCar) -> void:
	ticks += 1
	_t += _dt
	_step.call(c)
	# Not on the first ticks: after a teleport the body still lists what it was
	# touching where it came from.
	if watch_contacts and ticks > 3:
		_count_contacts(c)
	_last_speed = c.linear_velocity.length()

# ---------- the behaviours (usable on their own from a test) ----------

## 1. Steering input that holds the car on road-space x `lane_x`.
func steer_to(c: PlayerCar, lane_x: float) -> float:
	var side_v := RoadFrame.dir_to_road(RoadFrame.unroll(c.global_position).z, c.linear_velocity).x
	# Less damping while it is moving over on purpose, or a lane change at
	# town speed takes five seconds.
	var damp := CHANGE_DAMP_T if _changing and c.speed < 60.0 else LAT_DAMP_T
	return TrafficCar.lane_steer(c, lane_x - side_v * damp, -1.0, wheelbase, UNDERSTEER_FF)

## 1. Pedals for `v0` m/s behind something `gap` m ahead doing `lead_v` (INF =
## clear road). Brakes as hard as the gap needs; reuses the traffic follower law.
func pedals_for(c: PlayerCar, v0: float, gap := INF, lead_v := 0.0) -> void:
	var v := c.current_speed()
	# Up to COAST_BAND over the target it just lifts; past that it brakes.
	var a := (v0 - v) * SPEED_GAIN
	if v > v0:
		a = minf(0.0, (v0 + COAST_BAND - v) * 1.5)
	if gap < INF:
		a = minf(a, TrafficCar.follow_accel(v, v0, gap, lead_v, T_GAP))
	c.handbrake_input = 0.0
	if a < -0.3:
		# Grip is shared: the harder the car is cornering, the less brake it gets.
		var lat := v * v * _bend_here / BRAKE_FULL
		c.throttle_input = 0.0
		c.brake_input = clampf(-a / BRAKE_FULL, 0.0, sqrt(maxf(0.15, 1.0 - lat * lat)))
	else:
		c.throttle_input = clampf(a, 0.0, 1.0)
		c.brake_input = 0.0

## 2. Whether lane `lane_i` has room for the car right now: nothing alongside,
## nobody behind who would have to brake, enough road ahead to slow in.
func gap_free(c: PlayerCar, lane_i: int) -> bool:
	if lane_i < 0 or (traffic != null and lane_i >= traffic.own_lanes):
		return false
	if traffic == null:
		return true
	var u := RoadFrame.unroll(c.global_position)
	var x := TrafficManager.lane_centre(lane_i, false)
	var lo := minf(u.x, x) - HALF_W - SIDE_MARGIN
	var hi := maxf(u.x, x) + HALF_W + SIDE_MARGIN
	var v := c.current_speed()
	var behind := traffic.scan(u.z, -1.0, lo, hi, false, 0, HALF_L, 200.0, true)
	if behind < GAP_BEHIND + maxf(0.0, traffic.q_speed - v) * CLOSE_SECS:
		return false
	var ahead := traffic.scan(u.z, -1.0, lo, hi, true, 0, HALF_L, _reach(v), true)
	var closing := maxf(0.0, v - traffic.q_speed)
	return ahead >= GAP_AHEAD + closing * CLOSE_SECS + closing * closing / (2.0 * PLAN_DECEL)

## 2. The speed lane `lane_i` would let the car hold (for comparing lanes).
func lane_pace(c: PlayerCar, lane_i: int) -> float:
	if traffic == null:
		return target_speed
	var u := RoadFrame.unroll(c.global_position)
	var x := TrafficManager.lane_centre(lane_i, false)
	var v := c.current_speed()
	var gap := traffic.scan(u.z, -1.0, x - HALF_W - SIDE_MARGIN, x + HALF_W + SIDE_MARGIN, true, 0, HALF_L, _reach(v), true)
	if gap == INF:
		return target_speed
	return minf(target_speed, sqrt(maxf(0.0, traffic.q_speed * traffic.q_speed + 2.0 * PLAN_DECEL * maxf(0.0, gap - GAP_AHEAD))))

## 3. The most speed the car may carry now and still be at `v_there` m/s
## `dist` metres on, braking at PLAN_DECEL.
static func speed_to_reach(v_there: float, dist: float) -> float:
	return sqrt(v_there * v_there + 2.0 * PLAN_DECEL * maxf(0.0, dist))

## 4. Steering input that points the car's travel at a world position.
func steer_at(c: PlayerCar, point: Vector3) -> float:
	var fwd := -c.global_transform.basis.z
	var vel := c.linear_velocity
	vel.y = 0.0
	if vel.length() > 3.0 and vel.dot(fwd) > 0.0:
		fwd = vel.normalized()
	else:
		fwd.y = 0.0
		fwd = fwd.normalized()
	var to := point - c.global_position
	var ahead := to.dot(fwd)
	var lateral := to.dot(fwd.cross(Vector3.UP))
	var dist := maxf(Vector2(lateral, ahead).length(), 0.01)
	var want := clampf(atan(wheelbase * 2.0 * sin(atan2(lateral, ahead)) / dist) / c.max_steering_angle, -1.0, 1.0)
	return _wheel(c, want)

## 5. Fastest the road lets the car go now for `lat_accel` in every bend it
## could not brake for in time. INF on a straight road. `at_speed` looks as
## far ahead as a car doing that speed would need (default: its own speed).
func bend_speed(c: PlayerCar, lat_accel: float, at_speed := -1.0) -> float:
	if RoadFrame.align == null:
		return INF
	var z := RoadFrame.unroll(c.global_position).z
	var v := c.current_speed() if at_speed < 0.0 else at_speed
	var look := v * v / (2.0 * PLAN_DECEL) + 60.0
	var best := INF
	var d := 0.0
	while d <= look:
		var k := absf(RoadFrame.curvature_at(z - d))
		if k > 1e-6:
			best = minf(best, speed_to_reach(sqrt(lat_accel / k), d - 20.0))
		d += 25.0
	return best

## Sideslip: the angle between where the nose points and where the car goes,
## rad, + = nose right of travel. 0 below walking pace.
static func slip_angle(c: PlayerCar) -> float:
	var vel := c.linear_velocity
	vel.y = 0.0
	if vel.length() < 2.0:
		return 0.0
	var fwd := -c.global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized().signed_angle_to(vel.normalized(), Vector3.UP)

## The nose's angle off the road's own direction of travel, rad, + = right.
static func heading_error(c: PlayerCar) -> float:
	var z := RoadFrame.unroll(c.global_position).z
	var f := RoadFrame.dir_to_road(z, -c.global_transform.basis.z)
	return atan2(f.x, -f.z)

## 7. The next tick of seeded random key presses (PlayerCar.KEY_* bits).
func random_keys() -> int:
	_fuzz_left -= _dt
	var one_shot := 0
	if _fuzz_left <= 0.0:
		_fuzz_left = _rng.randf_range(0.05, 1.2)
		var k := 0
		if _rng.randf() < 0.7:
			k |= PlayerCar.KEY_ACCEL
		if _rng.randf() < 0.2:
			k |= PlayerCar.KEY_BRAKE
		if _rng.randf() < 0.3:
			k |= PlayerCar.KEY_LEFT
		if _rng.randf() < 0.3:
			k |= PlayerCar.KEY_RIGHT
		if _rng.randf() < 0.1:
			k |= PlayerCar.KEY_HANDBRAKE
		if _rng.randf() < 0.05:
			k |= PlayerCar.KEY_CLUTCH
		_fuzz_keys = k
		var r := _rng.randf()
		if r < 0.06:
			one_shot = PlayerCar.KEY_SHIFT_UP
		elif r < 0.12:
			one_shot = PlayerCar.KEY_SHIFT_DOWN
		elif r < 0.14:
			one_shot = PlayerCar.KEY_GEARBOX
		elif r < 0.18:
			one_shot = PlayerCar.KEY_REVERSE
	return _fuzz_keys | one_shot

## Puts the car on the road at road-space x, `ahead` metres on from where it
## is, nose `yaw_right` rad right of the road's direction, moving at `speed`
## m/s along its nose. Follows bends and hills (wall_hit's world-x version
## only works on a straight road).
static func place(c: PlayerCar, x: float, ahead: float, yaw_right: float, speed: float, y := 0.0) -> void:
	var u := RoadFrame.unroll(c.global_position)
	c.global_transform = RoadFrame.pose(x, u.y if y == 0.0 else y, u.z - ahead, -yaw_right)
	c.angular_velocity = Vector3.ZERO
	TrafficCar.set_moving(c, speed)
	for w in c.wheel_array:
		w.last_collision_point = w.global_position
	c.reset_physics_interpolation()

## "" when the car's state is sane, else what is wrong: a NaN, or the car
## under the road.
static func sanity(c: PlayerCar) -> String:
	var p := c.global_position
	if not (p.is_finite() and c.linear_velocity.is_finite() and c.angular_velocity.is_finite()
			and c.global_transform.basis.x.is_finite() and is_finite(c.motor_rpm)):
		return "NaN in the car's state"
	for w in c.wheel_array:
		if not is_finite(w.spin):
			return "NaN in a wheel's spin"
	var y := RoadFrame.unroll(p).y
	if y < -1.0:
		return "car is %.1f m under the road" % -y
	return ""

## The old traffic-harness lane keeper, unchanged: fixed throttle under
## max_speed, never brakes, never looks at traffic (tests/traffic/traffic_harness.gd
## lane_driver forwards here).
static func legacy_lane(lane_x: float, throttle: float, max_speed: float = INF) -> Callable:
	return func(c: Vehicle) -> void:
		# Sideways velocity across the road (RoadFrame, #37), not world x.
		var side_v := RoadFrame.dir_to_road(RoadFrame.unroll(c.global_position).z, c.linear_velocity).x
		c.steering_input = TrafficCar.lane_steer(c, lane_x - side_v * LAT_DAMP_T, -1.0, 2.5, UNDERSTEER_FF)
		c.throttle_input = throttle if c.current_speed() < max_speed else 0.0
		c.brake_input = 0.0
		c.handbrake_input = 0.0

# ---------- modes ----------

func _drive_clean(c: PlayerCar) -> void:
	if _recovering(c):
		return
	_plan_left -= _dt
	if _plan_left <= 0.0:
		_plan_left = PLAN_SECS
		_check_spin = true
		_plan(c)
	var lane_x := TrafficManager.lane_centre(lane, false)
	var v0 := minf(target_speed, _bend_v)
	if mode == "brake_to" and brake_s < INF:
		var left := brake_s - RoadFrame.s_at(RoadFrame.unroll(c.global_position).z)
		v0 = minf(v0, speed_to_reach(brake_speed, left) if left > 0.0 else brake_speed)
	c.steering_input = steer_to(c, lane_x)
	pedals_for(c, v0, _gap, _lead_v)
	if mode == "grip" and absf(slip_angle(c)) > 0.12:
		c.throttle_input *= 0.3
	if v0 <= 0.01 and c.current_speed() < 0.5:
		c.throttle_input = 0.0
		c.brake_input = 1.0

# Everything that looks further than the bonnet, every PLAN_SECS.
func _plan(c: PlayerCar) -> void:
	var u := RoadFrame.unroll(c.global_position)
	var v := c.current_speed()
	var lane_x := TrafficManager.lane_centre(lane, false)
	var off := absf(u.x - lane_x)
	if _changing and off < CHANGE_DONE:
		_changing = false
	if not _changing:
		max_lane_err = maxf(max_lane_err, off)
	_bend_v = bend_speed(c, GRIP_LAT_ACCEL if mode == "grip" else CLEAN_LAT_ACCEL)
	_bend_here = absf(RoadFrame.curvature_at(u.z))
	_gap = INF
	_lead_v = 0.0
	if traffic == null:
		return
	# The strip of road the body sweeps between here and the wanted lane.
	var lo := minf(u.x, lane_x) - HALF_W - SIDE_MARGIN
	var hi := maxf(u.x, lane_x) + HALF_W + SIDE_MARGIN
	_gap = traffic.scan(u.z, -1.0, lo, hi, true, 0, HALF_L, _reach(v), true)
	_lead_v = traffic.q_speed
	min_gap = minf(min_gap, _gap)
	if _changing:
		return
	var want := 0
	if mode == "weave" and _t >= _next_weave:
		want = _weave_dir if _lane_ok(lane + _weave_dir) else -_weave_dir
	elif _gap < INF and lane_pace(c, lane) < minf(target_speed, _bend_v) - CHANGE_GAIN:
		# Held up: the faster neighbour, if it is worth the move.
		var here := lane_pace(c, lane)
		var best := here + CHANGE_GAIN
		for d in [-1, 1]:
			if _lane_ok(lane + d):
				var pace := lane_pace(c, lane + d)
				if pace > best:
					best = pace
					want = d
	if want == 0:
		return
	if gap_free(c, lane + want):
		lane += want
		_changing = true
		lane_changes += 1
		if mode == "weave":
			_next_weave = _t + weave_period
			_weave_dir = -_weave_dir if not _lane_ok(lane + _weave_dir) else _weave_dir
	else:
		refused_changes += 1

func _lane_ok(i: int) -> bool:
	return i >= 0 and i < (traffic.own_lanes if traffic != null else 4)

func _reach(v: float) -> float:
	return clampf(v * v / (2.0 * PLAN_DECEL) + 80.0, 100.0, 900.0)

# Spin recovery. A spin: off the throttle, brakes on, until it has stopped.
# Then, if the nose points the wrong way, turn round in short forward and
# reverse legs. True while it has the controls.
func _recovering(c: PlayerCar) -> bool:
	if _rec == 0 and not _check_spin:
		return false
	_check_spin = false
	var v := c.linear_velocity.length()
	if _rec == 0:
		if v > SPIN_MIN_SPEED and absf(slip_angle(c)) > SPIN_SLIP:
			_rec = 1
			spins += 1
		elif v < 3.0 and absf(heading_error(c)) > WRONG_WAY and c.current_gear != -1:
			_rec = 1
		else:
			return false
	c.handbrake_input = 0.0
	if _rec == 1:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
		if v < 0.4:
			_rec = 2
			_rec_t = 0.0
			_rec_fwd = true
		return true
	# Turning round: lock toward the road's direction going forward, the other
	# lock in reverse, in timed legs. Done once the nose is within TURN_DONE of
	# the road's direction and the car is in a forward gear.
	var err := heading_error(c)
	var in_reverse := c.current_gear == -1
	if absf(err) < TURN_DONE:
		_rec_fwd = true
		if not in_reverse:
			_rec = 0
			_plan_left = 0.0
			return false
	if in_reverse == _rec_fwd:
		# Wrong gear for this leg: stop, then swap.
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.steering_input = 0.0
		if v < 1.0 and not c.is_shifting:
			c.toggle_reverse()
		return true
	_rec_t += _dt
	if _rec_t > TURN_LEG_SECS:
		_rec_fwd = not _rec_fwd
		_rec_t = 0.0
		return true
	var turn := -signf(err)   # err + = nose right of the road, so turn left
	if not _rec_fwd:
		turn = -turn
	c.steering_input = _wheel(c, turn)
	c.throttle_input = 0.45 if v < 5.0 else 0.0
	c.brake_input = 0.0
	return true

func _drive_aim(c: PlayerCar) -> void:
	var point := aim_node.global_position if aim_node != null and is_instance_valid(aim_node) else aim_point
	c.steering_input = steer_at(c, point)
	pedals_for(c, target_speed)

func _drive_flee(c: PlayerCar) -> void:
	_plan_left -= _dt
	if _plan_left <= 0.0:
		_plan_left = PLAN_SECS
		var keep := lane
		_plan(c)
		if not _changing and lane == keep and traffic != null:
			# The lane with the most free road, away from the threat's side.
			var best := lane_pace(c, lane) + 1.0
			var pick := lane
			for i in traffic.own_lanes:
				if absi(i - lane) == 1 and gap_free(c, i):
					var pace := lane_pace(c, i) + (2.0 if _threat_side(c) * (i - lane) < 0.0 else 0.0)
					if pace > best:
						best = pace
						pick = i
			if pick != lane:
				lane = pick
				_changing = true
				lane_changes += 1
	c.steering_input = steer_to(c, TrafficManager.lane_centre(lane, false))
	pedals_for(c, minf(target_speed, _bend_v), _gap, _lead_v)

# -1 threat on the left, +1 on the right, 0 none or dead behind.
func _threat_side(c: PlayerCar) -> float:
	if threat == null or not is_instance_valid(threat):
		return 0.0
	var dx := RoadFrame.unroll(threat.global_position).x - RoadFrame.unroll(c.global_position).x
	return 0.0 if absf(dx) < 0.5 else signf(dx)

func _drive_fuzz(c: PlayerCar) -> void:
	var k := random_keys()
	if record_keys:
		keys.append(k)
	c.apply_keys(k)

func _drive_replay(c: PlayerCar) -> void:
	var i := ticks - 1
	if i >= keys.size():
		replay_done = true
		c.apply_keys(0)
		return
	c.apply_keys(keys[i])

func _drive_hold(c: PlayerCar) -> void:
	c.throttle_input = hold_throttle
	c.brake_input = hold_brake
	c.handbrake_input = 0.0
	c.steering_input = _wheel(c, hold_steer)

# The benchmark's bot before 2026-10-10, kept so old result lines still compare.
func _drive_legacy_bench(c: PlayerCar) -> void:
	_legacy_t += _dt
	var u := RoadFrame.unroll(c.global_position)
	var l := 1
	if legacy_weave:
		l = 0 if int(_legacy_t / 4.0) % 2 == 0 else 1   # a lane change every 4 s
	var err: float = (c.global_rotation.y - RoadFrame.heading_at(u.z)) + clampf((TrafficManager.lane_centre(l, false) - u.x) * 0.02, -0.05, 0.05)
	var steer := 0.0
	if err < -0.02:
		steer = -1.0  # left (A)
	elif err > 0.02:
		steer = 1.0   # right (D)
	c.throttle_input = 1.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = -steer  # same sign flip as PlayerCar.apply_keys

# ---------- helpers ----------

# Share of lock (+ = right) -> GEVP's steering_input: sign flipped and its
# exponent undone, as PlayerCar.apply_keys does.
static func _wheel(c: PlayerCar, share: float) -> float:
	return -signf(share) * pow(absf(share), 1.0 / maxf(c.steering_exponent, 0.1))

func _count_contacts(c: PlayerCar) -> void:
	var wall := false
	var car := false
	var who := ""
	# The count is free; the list (an allocation) only when something touches.
	for b in (c.get_colliding_bodies() if c.get_contact_count() > 0 else []):
		if b is Vehicle:
			car = true
			who = "car " + String(b.name)
		elif b is CollisionObject3D and b.collision_layer & (1 << (CarSpec.WALL_LAYER - 1)):
			wall = true
			who = "wall " + String(b.name)
	if wall:
		wall_ticks += 1
		if not _touch_wall:
			wall_contacts += 1
	if car:
		car_ticks += 1
		if not _touch_car:
			car_contacts += 1
	if who != "" and first_contact == "":
		first_contact = "%s at tick %d, %.0f km/h" % [who, ticks, _last_speed * 3.6]   # the speed going in
	_touch_wall = wall
	_touch_car = car

## One line for a test's log.
func summary() -> String:
	return "mode=%s ticks=%d wall_contacts=%d car_contacts=%d spins=%d lane_changes=%d refused=%d max_lane_err=%.2f m min_gap=%s%s" % [
		mode, ticks, wall_contacts, car_contacts, spins, lane_changes, refused_changes, max_lane_err,
		"-" if min_gap == INF else "%.1f m" % min_gap, "" if first_contact == "" else " first=[%s]" % first_contact]
