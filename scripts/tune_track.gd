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

const KMH := 1.0 / 3.6
const LANE_SPACING := 40.0
const SETTLE_TIME := 1.0       # car held on the brakes while the suspension settles
const SHIFT_RPM_FRACTION := 0.97  # upshift at this fraction of the spec's max_rpm
const ACCEL_TIME := 35.0
const CORNER_TIME := 30.0
const CORNER_STEER := 0.3
const MAX_STEPS := 4000        # safety stop for a run that never finishes

enum Kind { ACCEL, BRAKE, CORNER }
const ALL_KINDS := [Kind.ACCEL, Kind.BRAKE, Kind.CORNER]

## One scripted run on one car.
class Run extends RefCounted:
	var kind: int
	var car: PlayerCar
	var t := 0.0
	var done := false
	var failed := ""
	var m := {}
	var dt := 1.0 / 60.0
	# brake
	var brake_phase := false
	var brake_start := Vector3.ZERO
	var brake_v0 := 0.0
	var brake_t0 := 0.0
	# corner
	var lat_g_smooth := 0.0
	var peak_lat_g := 0.0
	var max_slip := 0.0

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

	func _shift(c: PlayerCar) -> void:
		if c.current_gear >= 1 and c.current_gear < c.gear_ratios.size() and not c.is_shifting \
				and c.motor_rpm >= c.max_rpm * SHIFT_RPM_FRACTION:
			c.manual_shift(1)

	func _finish(why := "") -> void:
		done = true
		if why != "":
			failed = why

	func _accel(c: PlayerCar) -> void:
		c.throttle_input = 1.0
		_shift(c)
		var v := c.current_speed()
		var kmh := v * 3.6
		m.top_speed_kmh = maxf(m.get("top_speed_kmh", 0.0), kmh)
		if not m.has("t_0_100") and v >= 100.0 * KMH:
			m.t_0_100 = t
		if t >= ACCEL_TIME:
			_finish()

	func _brake(c: PlayerCar) -> void:
		var v := c.current_speed()
		if not brake_phase:
			c.throttle_input = 1.0
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
		c.brake_input = 1.0
		if v < 0.3 or t - brake_t0 > 20.0:
			var d := c.global_position.distance_to(brake_start)
			# Braking starts a hair above 100 km/h (one tick of overshoot);
			# scale to exactly 100 assuming constant deceleration.
			m.brake_dist_100 = d * pow(100.0 * KMH / brake_v0, 2.0)
			m.brake_time = t - brake_t0
			_finish()

	func _corner(c: PlayerCar) -> void:
		c.steering_input = CORNER_STEER
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
			max_slip = maxf(max_slip, rad_to_deg(heading.normalized().angle_to(vel / sp)))
		m.peak_lat_g = peak_lat_g
		m.max_slip_deg = max_slip
		# Past the limit the car just plows out; stop once the grip has clearly gone.
		if t >= CORNER_TIME or (t > 4.0 and peak_lat_g > 0.3 and lat_g_smooth < 0.6 * peak_lat_g):
			_finish()

## -1 runs the cars exactly as the game does (PlayerCar.LINEAR_DAMP, 0). 0 or
## more replaces the RigidBody's linear damping with that value, for what-if
## runs: Godot's old default of 0.1 capped the car near 124 km/h.
var linear_damp_override := -1.0

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
	while pending and steps < MAX_STEPS:
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
			r.failed = "did not finish in %d steps" % MAX_STEPS
		if r.failed != "":
			out.ok = false
			out.problems.append("%s: %s" % [Kind.keys()[r.kind].to_lower(), r.failed])
		out.merge(r.m)
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
	body.position = Vector3(box.size.x * 0.5 - 100.0, -1.0, -2400.0)
	add_child(body)
	return body

func _spawn(spec: Dictionary, lane: int, kind: int) -> Run:
	var r := Run.new()
	r.kind = kind
	r.dt = 1.0 / Engine.physics_ticks_per_second
	r.t = -SETTLE_TIME
	var car := PlayerCar.new()
	car.sim_only = true
	car.spec = CarSpec.clone_spec(spec)
	# TuneTrack shifts by itself (_shift); the game default is automatic now.
	car.spec["automatic_transmission"] = false
	car.driver = r.drive
	car.position = Vector3(lane * LANE_SPACING, 0.3, 0.0)
	add_child(car)
	if linear_damp_override >= 0.0:  # after _ready(), which sets the game's value
		car.linear_damp = linear_damp_override
	r.car = car
	return r
