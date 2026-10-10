class_name TuneTrack
extends Node3D

# Hidden test track for Auto-Tune (step 2): flat "Road" ground, three scripted
# runs per spec, measured on the SAME PlayerCar / vendored Vehicle + Wheel sim
# the game uses (a PlayerCar built from the spec, driven by a scripted driver
# instead of the keyboard).
#
#   accel  : full throttle, auto-shifting      -> t_0_100, top_speed_kmh
#   brake  : accelerate to 100 km/h, full brake -> brake_dist_100 (m)
#   corner : fixed steering, rising speed       -> peak_lat_g, max_slip_deg
#
# The three runs of a spec go side by side in three lanes (40 m apart, outside
# aero draft range, so the cars don't affect each other), and specs are
# evaluated one after another in the SAME lanes on the same ground. That is
# deliberate: Godot's physics is single precision, so the same run at a
# different position gives slightly different numbers (2% on the slide metrics
# when specs were batched across lanes kilometres apart). Evaluated like this,
# the result depends only on the spec. Batching would not be faster anyway: a
# car-step costs the same however many cars are in flight. Usage (the track
# must be in the tree):
#   var results: Array = await track.evaluate([spec_a, spec_b])
# results[i] is a Dictionary of metrics for specs[i].
#
# The drivers are deliberately simple and fixed; the numbers are only comparable
# between specs run by the same drivers.
#
# With record_trace on, the brake run (launch to 100 km/h, then full brakes) also
# keeps a small telemetry trace for the Tuner's pit-wall result: speed, throttle
# and brake every TRACE_STEP seconds, as metrics.trace = {step, speed, throttle,
# brake} (speed in km/h). Off for the Auto-Tune search, which never shows one.

const KMH := 1.0 / 3.6
const LANE_SPACING := 40.0
## Where lane 0 sits. Off the game road (x -17..17 m with 4 lanes each way of
## 3.2 m, buildings to about x 27 m) because tests run the track inside the live
## Game.tscn, and the stage B step 3 player parks in a lane: with lane 0 on
## x=0 the accel car rear-ended the coasting player (tests/car/tyres.gd,
## 2026-10-05). Note: positions move the single-precision results a hair.
const LANE_X0 := -120.0
const SETTLE_TIME := 1.0       # car held on the brakes while the suspension settles
const SHIFT_RPM_FRACTION := 0.97  # upshift at this fraction of the spec's max_rpm
const ACCEL_TIME := 35.0
const CORNER_TIME := 30.0
const CORNER_STEER := 0.3
## First slip this big (degrees) in the corner run is "the car has started to
## slide": the speed it happened at is metrics.v_slide_ms (bolt-on worth sweep).
const SLIDE_ONSET_DEG := 12.0
const TRACE_STEP := 0.1        # seconds between trace samples (~100 per brake run)
# Safety stop for a run that never finishes: 4000 steps was ~67 s at 60 Hz; scaled so the
# budget stays ~67 s at the game's 120 Hz (4000 steps was 33 s there, under the 35 s accel run).
const MAX_SECONDS := 4000.0 / 60.0
var max_steps := ceili(MAX_SECONDS * Engine.physics_ticks_per_second)

enum Kind { ACCEL, BRAKE, CORNER }
const ALL_KINDS := [Kind.ACCEL, Kind.BRAKE, Kind.CORNER]

## How the scripted driver drives (balance sweep, 2026-10-09). The default is
## exactly the driver the track always had, so every existing measurement and
## test is unchanged; tools/balance_sweep.gd swaps in weaker drivers to see how
## much of a car's pace a novice can reach.
##   shift_frac    : upshift at this fraction of max_rpm
##   throttle_max  : the most throttle the driver uses on a straight
##   throttle_ramp : seconds to squeeze from 0 to throttle_max at launch (0 = instant)
##   brake_max     : the most brake pedal the driver uses
const DEFAULT_PROFILE := {"shift_frac": SHIFT_RPM_FRACTION, "throttle_max": 1.0, "throttle_ramp": 0.0, "brake_max": 1.0}

## One scripted run on one car.
class Run extends RefCounted:
	var kind: int
	var car: PlayerCar
	var t := 0.0
	var done := false
	var failed := ""
	var m := {}
	var dt := 1.0 / Engine.physics_ticks_per_second
	# brake
	var brake_phase := false
	var brake_start := Vector3.ZERO
	var brake_v0 := 0.0
	var brake_t0 := 0.0
	# corner
	var lat_g_smooth := 0.0
	var peak_lat_g := 0.0
	var max_slip := 0.0
	# trace (brake run with record_trace only): {step, speed, throttle, brake}
	var trace := {}
	var trace_ticks := 0
	var profile: Dictionary = DEFAULT_PROFILE
	var corner_steer := CORNER_STEER
	# heat telemetry (record_heat only): one [speed m/s, engine load 0..1, on limiter, brake power W]
	# per tick, replayed through PowertrainHealth offline by the balance sweep
	var record_heat := false
	var heat_log: Array = []
	var start_pos := Vector3.ZERO
	var has_start := false

	func drive(c: PlayerCar) -> void:
		if done:
			c.throttle_input = 0.0
			c.brake_input = 1.0
			return
		var settling := t < 0.0
		t += dt
		c.handbrake_input = 0.0
		c.steering_input = 0.0
		if settling:
			c.throttle_input = 0.0
			c.brake_input = 1.0
			return
		c.brake_input = 0.0
		if c.global_transform.basis.y.y < 0.3:
			_finish("flipped")
			return
		match kind:
			Kind.ACCEL: _accel(c)
			Kind.BRAKE: _brake(c)
			Kind.CORNER: _corner(c)
		if not trace.is_empty():
			_sample(c)
		if record_heat:
			_log_heat(c)

	## Same load and brake power PowertrainHealth.step() reads from the car.
	func _log_heat(c: PlayerCar) -> void:
		var peak_power := c.max_torque * c.max_rpm / 9.5488 * 0.7
		var power := maxf(c.torque_output, 0.0) * c.motor_rpm / 9.5488
		var load := clampf(power / maxf(peak_power, 1.0), 0.0, 1.0)
		heat_log.append([c.speed, load, c.limiter_cut, c.brake_force * c.speed])

	## Full throttle for the stock driver; a novice squeezes it on and never floors it.
	func _throttle(c: PlayerCar) -> void:
		var cap: float = profile.throttle_max
		var ramp: float = profile.throttle_ramp
		if ramp > 0.0 and t < ramp:
			cap *= clampf(t / ramp, 0.0, 1.0)
		c.throttle_input = cap

	func _sample(c: PlayerCar) -> void:
		if trace_ticks % maxi(1, roundi(TRACE_STEP / dt)) == 0:
			trace.speed.append(snappedf(absf(c.current_speed()) * 3.6, 0.1))
			trace.throttle.append(c.throttle_input)
			trace.brake.append(c.brake_input)
		trace_ticks += 1

	func _shift(c: PlayerCar) -> void:
		if c.current_gear >= 1 and c.current_gear < c.gear_ratios.size() and not c.is_shifting \
				and c.motor_rpm >= c.max_rpm * float(profile.shift_frac):
			c.manual_shift(1)

	func _finish(why := "") -> void:
		done = true
		if why != "":
			failed = why

	func _accel(c: PlayerCar) -> void:
		_throttle(c)
		_shift(c)
		var v := c.current_speed()
		var kmh := v * 3.6
		m.top_speed_kmh = maxf(m.get("top_speed_kmh", 0.0), kmh)
		if not m.has("t_0_100") and v >= 100.0 * KMH:
			m.t_0_100 = t
		if not has_start:
			start_pos = c.global_position
			has_start = true
		# Standing 400 m (balance sweep): the "lap" is built from this.
		if not m.has("t_400") and c.global_position.distance_to(start_pos) >= 400.0:
			m.t_400 = t
		if t >= ACCEL_TIME:
			_finish()

	func _brake(c: PlayerCar) -> void:
		var v := c.current_speed()
		if not brake_phase:
			_throttle(c)
			_shift(c)
			if v >= 100.0 * KMH:
				brake_phase = true
				brake_start = c.global_position
				brake_v0 = v
				brake_t0 = t
			elif t > ACCEL_TIME:
				_finish("never reached 100 km/h")
			return
		c.throttle_input = 0.0
		c.brake_input = profile.brake_max
		if v < 0.3 or t - brake_t0 > 20.0:
			var d := c.global_position.distance_to(brake_start)
			# Braking starts a hair above 100 km/h (one tick of overshoot);
			# scale to exactly 100 assuming constant deceleration.
			m.brake_dist_100 = d * pow(100.0 * KMH / brake_v0, 2.0)
			m.brake_time = t - brake_t0
			_finish()

	func _corner(c: PlayerCar) -> void:
		c.steering_input = corner_steer
		var target := 4.0 + 1.2 * t
		c.throttle_input = clampf((target - c.current_speed()) * 0.5, 0.0, 1.0)
		_shift(c)
		var vel := c.linear_velocity
		vel.y = 0.0
		var sp := vel.length()
		var a_lat := sp * absf(c.angular_velocity.y)
		lat_g_smooth = lerpf(lat_g_smooth, a_lat / 9.81, clampf(dt / 0.25, 0.0, 1.0))
		peak_lat_g = maxf(peak_lat_g, lat_g_smooth)
		if sp > 5.0:
			var heading := -c.global_transform.basis.z
			heading.y = 0.0
			var slip_deg := rad_to_deg(heading.normalized().angle_to(vel / sp))
			max_slip = maxf(max_slip, slip_deg)
			if not m.has("v_slide_ms") and slip_deg >= SLIDE_ONSET_DEG:
				m.v_slide_ms = sp
		m.peak_lat_g = peak_lat_g
		m.max_slip_deg = max_slip
		# Past the limit the car just plows out; stop once the grip has clearly gone.
		if t >= CORNER_TIME or (t > 4.0 and peak_lat_g > 0.3 and lat_g_smooth < 0.6 * peak_lat_g):
			_finish()

## -1 runs the cars exactly as the game does (PlayerCar.LINEAR_DAMP, 0). 0 or
## more replaces the RigidBody's linear damping with that value, for what-if
## runs: Godot's old default of 0.1 capped the car near 124 km/h.
var linear_damp_override := -1.0
## Keep the brake run's telemetry trace (see the top of the file).
var record_trace := false
## Steering input of the corner run (CORNER_STEER = the track's usual number).
var corner_steer := CORNER_STEER
## The scripted driver's limits (DEFAULT_PROFILE = the track's usual driver).
var driver_profile: Dictionary = DEFAULT_PROFILE
## Keep per-tick heat telemetry of the accel and brake runs as metrics.heat_accel
## and metrics.heat_brake (see Run.heat_log), for the balance sweep's offline
## PowertrainHealth replay. Off by default.
var record_heat := false

var steps_taken := 0  # physics steps the last evaluate() ran, all specs together
var cars_simulated := 0  # cars in flight at any one step (3)

## Runs the scripted tests for every spec, one spec at a time; returns one
## metrics dictionary per spec: top_speed_kmh, t_0_100, brake_dist_100,
## brake_time, peak_lat_g, max_slip_deg, plus "ok" (false, with "problems"
## listing why, if a run flipped, never got going, or produced a non-finite
## number). `kinds` picks which runs to do (the search only runs what its goals
## need); a run always uses its own lane, so a metric is the same number
## whichever other runs are along.
func evaluate(specs: Array, kinds: Array = ALL_KINDS) -> Array:
	steps_taken = 0
	cars_simulated = kinds.size()
	var results: Array = []
	for spec in specs:
		results.append(await _evaluate_one(spec, kinds))
	return results

func _evaluate_one(spec: Dictionary, kinds: Array) -> Dictionary:
	var ground := _make_ground()
	var runs: Array = []
	for kind in kinds:
		runs.append(_spawn(spec, kind, kind))
	var steps := 0
	var pending := true
	while pending and steps < max_steps:
		await get_tree().physics_frame
		steps += 1
		pending = false
		for r in runs:
			if not r.done:
				pending = true
				break
	steps_taken += steps
	var out := {"ok": true, "problems": []}
	for r: Run in runs:
		if not r.done:
			r.failed = "did not finish in %d steps" % max_steps
		if r.failed != "":
			out.ok = false
			out.problems.append("%s: %s" % [Kind.keys()[r.kind].to_lower(), r.failed])
		out.merge(r.m)
		if not r.trace.is_empty():
			out.trace = r.trace
		if r.record_heat and r.kind == Kind.ACCEL:
			out.heat_accel = r.heat_log
		if r.record_heat and r.kind == Kind.BRAKE:
			out.heat_brake = r.heat_log
	for key in out:
		if out[key] is float and not is_finite(out[key]):
			out.ok = false
			out.problems.append("%s not finite" % key)
	for r: Run in runs:
		remove_child(r.car)
		r.car.queue_free()
	remove_child(ground)
	ground.queue_free()
	# One more step so the freed cars are really gone before the next spec's cars
	# appear in the same place.
	await get_tree().physics_frame
	return out

func _make_ground() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_to_group("Road")  # the wheels pick their tire numbers from the collider's group
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3 * LANE_SPACING + 200.0, 2.0, 6000.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(LANE_X0 + LANE_SPACING, -1.0, -2400.0)  # centred on the middle lane
	add_child(body)
	return body

func _spawn(spec: Dictionary, lane: int, kind: int) -> Run:
	var r := Run.new()
	r.kind = kind
	r.dt = 1.0 / Engine.physics_ticks_per_second
	r.t = -SETTLE_TIME
	r.profile = driver_profile
	r.corner_steer = corner_steer
	r.record_heat = record_heat and kind != Kind.CORNER
	if record_trace and kind == Kind.BRAKE:
		r.trace = {"step": TRACE_STEP, "speed": [], "throttle": [], "brake": []}
	var car := PlayerCar.new()
	car.sim_only = true
	car.spec = CarSpec.clone_spec(spec)
	# TuneTrack shifts by itself (_shift); the game default is automatic now.
	car.spec["automatic_transmission"] = false
	car.driver = r.drive
	car.position = Vector3(LANE_X0 + lane * LANE_SPACING, 0.3, 0.0)
	add_child(car)
	if linear_damp_override >= 0.0:  # after _ready(), which sets the game's value
		car.linear_damp = linear_damp_override
	r.car = car
	return r
