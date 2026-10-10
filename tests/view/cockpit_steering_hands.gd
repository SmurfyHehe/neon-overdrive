extends SceneTree

# Continuous steering in the cockpit (2026-10-09, Roy: hands higher on the
# wheel, the wheel rolls instead of snapping left/right), headless and silent:
# - the drawn wheel (CockpitFrame.wheel_angle) chases the car's steering
#   through the spring: it never jumps more than its rate cap allows in one
#   tick, never passes lock, and settles on the target once the input holds
# - the hands stay on the rim centreline through every pattern, never leave
#   their ranges (so never rise above DriverModel.HAND_TOP_MIN_DEG below the
#   eye) and never teleport: a hand's angle round the rim moves at most what
#   the rim or a slide allows per tick
# - at least one hand is on the wheel in every tick it turns; full lock at a
#   standstill makes the hands shuffle (let go and re-grip) and the wheel
#   reaches lock
# - after the wheel comes back to straight and rests, both hands are home
# - the patterns: a step to full lock each way, hold and release; a slow ramp;
#   fast left/right taps; a sawtooth; the same rolling (the lock cap shrinks
#   with speed); then the same in reverse
# - no engine errors during any of it
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/cockpit_steering_hands.gd

const TIMEOUT_TICKS := 60 * 150
const RIM_TOL := 0.03          # the rim tube plus the slide lift, and the flat bottom is no arc

class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var _lock := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function])
		_lock.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass

static func ticks(secs: float) -> int:
	return int(round(secs * Engine.physics_ticks_per_second))

## A pattern: a name and a list of segments, [steer, seconds] to hold, or
## ["ramp", from, to, seconds] to sweep.
var patterns := [
	["step right", [[1.0, 1.2], [0.0, 1.5]]],
	["step left", [[-1.0, 1.2], [0.0, 1.5]]],
	["slow ramp", [["ramp", 0.0, 1.0, 2.0], ["ramp", 1.0, -1.0, 3.0], ["ramp", -1.0, 0.0, 1.5], [0.0, 1.0]]],
	["taps", [[1.0, 0.15], [-1.0, 0.15], [1.0, 0.15], [-1.0, 0.15], [0.0, 0.1], [1.0, 0.3], [0.0, 0.05], [-1.0, 0.3], [0.0, 1.5]]],
	["sawtooth", [["ramp", 0.0, 1.0, 0.6], [-1.0, 0.4], ["ramp", -1.0, 1.0, 0.8], [0.0, 1.5]]],
]
const PHASES := ["standstill", "rolling", "reverse"]

var tick := 0
var failures: Array[String] = []
var logger := ErrorCounter.new()
var steer := 0.0
var throttle := 0.0
var brake := 1.0
var phase := 0
var pattern_i := 0
var seg_i := 0
var seg_start := 0
var started := false
var waiting := false           # getting up to speed / into reverse
var prev_wheel := 0.0
var prev_w := {-1: 0.0, 1: 0.0}
var hold_ticks := 0            # ticks the input has been constant
var lock_seen := false
var min_below_eye := 90.0
var min_below_where := ""
var samples := 0
var max_wheel_step := 0.0
var max_hand_step := 0.0
var rest_tick := -1
var warm := 0                  # ticks since the cockpit view came up
var steer_changes := 0         # times a pattern moved the input (counted per tick)
var snap_changes := 0          # the car as the render frame being judged saw it:
var snap_hold := 0             #   steer_changes, hold_ticks and the steering target,
var snap_target := 0.0         #   taken at the start of that frame (physics runs first)
var seen_changes := 0          # steer_changes as the last judged frame saw them
var held_secs := 0.0           # render-frame seconds the input has been constant
var hold_judged := false       # the held-input check ran for this hold
var rest_secs := 0.0           # render-frame seconds since the pattern run ended
var last_dt := 0.0             # delta of the render frame the nodes last ran with
var cur_frame: CockpitFrame
var cur_d: DriverModel
var cur_p: PlayerCar
var cur_where := ""            # where the physics tick says we are; "" = not judging

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_cockpit_steering_hands_exhaust.json"
	OS.add_logger(logger)
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.handbrake_input = 0.0
	c.steering_input = steer

## Lowest angle below the eye of any corner of the hands' (and the bracelet's)
## mesh bounds, car space, a running minimum with where it happened.
func _track_view(d: DriverModel, where: String) -> void:
	var eye := ChaseCamera.COCKPIT_EYE
	for side in [-1, 1]:
		var hand: MeshInstance3D = d.hands[side]
		for c in 8:
			var pts := [hand.transform * hand.get_aabb().get_endpoint(c)]
			if side > 0:
				pts.append(hand.transform * d.bracelet.transform * d.bracelet.get_aabb().get_endpoint(c))
			for pt in pts:
				var v: Vector3 = eye - pt
				var below := rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))
				if below < min_below_eye:
					min_below_eye = below
					min_below_where = "%s hand %d" % [where, side]

## Sets steer from the current pattern; true once the pattern has ended.
func _play_pattern() -> bool:
	var segs: Array = patterns[pattern_i][1]
	if seg_i >= segs.size():
		return true
	var seg: Array = segs[seg_i]
	var t := float(tick - seg_start) / Engine.physics_ticks_per_second
	var want := 0.0
	var secs := 0.0
	if seg[0] is String:
		secs = seg[3]
		want = lerpf(seg[1], seg[2], clampf(t / secs, 0.0, 1.0))
	else:
		secs = seg[1]
		want = seg[0]
	if not is_equal_approx(want, steer):
		steer_changes += 1
	hold_ticks = hold_ticks + 1 if is_equal_approx(want, steer) else 0
	steer = want
	if t >= secs:
		seg_i += 1
		seg_start = tick
	return false

## The wheel and the hands move in the nodes' _process by that render frame's
## delta, which is wall-clock time: on a loaded machine a frame can be 50 or
## 500 ms long while the physics ticks around it still count 1/60 s each (the
## old per-tick judging saw "hand 1 moved 6.0 deg of rim in 0.017 s" when the
## frame was really 50 ms). So they are judged per render frame, against the
## delta the nodes got. The SceneTree's _process runs before the nodes' in a
## frame, so what it sees is the state after the previous frame, made with the
## previous frame's delta (last_dt).
func _process(delta: float) -> bool:
	if cur_frame != null and last_dt > 0.0:
		if cur_where == "":
			# not judging (warming up, waiting for speed): just keep the baseline
			prev_wheel = cur_frame.wheel_angle
			for side in [-1, 1]:
				prev_w[side] = cur_d.rim_deg(side)
		else:
			_checks(cur_frame, cur_d, cur_p, cur_where, last_dt)
	last_dt = delta
	# What this frame's nodes are about to see of the car: the ticks that ran
	# before this frame, not the ones that run before the next.
	snap_changes = steer_changes
	snap_hold = hold_ticks
	if cur_p != null:
		snap_target = cur_p.steer_fraction() * CockpitFrame.WHEEL_LOCK_RAD
	return false

## One render frame's worth of judging: `elapsed` is the frame's delta.
func _checks(frame: CockpitFrame, d: DriverModel, p: PlayerCar, where: String, elapsed: float) -> void:
	var wheel := frame.wheel_angle
	var step := absf(wheel - prev_wheel)
	# the wheel: bounded, never faster than the cap
	max_wheel_step = maxf(max_wheel_step, step / elapsed)
	var slack := elapsed
	var cap := deg_to_rad(CockpitFrame.WHEEL_RATE_DEG) * slack * 1.2 + deg_to_rad(0.5)
	if step > cap:
		_fail("%s: the wheel jumped %.1f deg in %.3f s (cap %.1f)" % [where, rad_to_deg(step), elapsed, rad_to_deg(cap)])
	if absf(wheel) > CockpitFrame.WHEEL_LOCK_RAD + 1e-4:
		_fail("%s: the wheel passed lock (%.1f deg)" % [where, rad_to_deg(wheel)])
	if absf(absf(wheel) - CockpitFrame.WHEEL_LOCK_RAD) < deg_to_rad(1.0):
		lock_seen = true
	# held input: the wheel settles on what the car steers, once the input has
	# held for 0.8 s of both ticks (the car's steering) and render time (the wheel)
	if snap_changes != seen_changes:
		seen_changes = snap_changes
		held_secs = 0.0
		hold_judged = false
	held_secs += elapsed
	if rest_tick > 0:
		rest_secs += elapsed
	if not hold_judged and snap_hold >= ticks(0.8) and held_secs >= 0.8:
		hold_judged = true
		if absf(wheel - snap_target) > deg_to_rad(1.5):
			_fail("%s: after 0.8 s of held input the wheel sits at %.1f deg, the car steers %.1f" % [where, rad_to_deg(wheel), rad_to_deg(snap_target)])
	prev_wheel = wheel
	# the hands: on the rim, in range, continuous, at least one holding on
	var to_wheel := (frame.wheel_mount.transform * frame.wheel.transform).affine_inverse()
	var any_grip := false
	var slide_cap := maxf(absf(d.wheel_rate_deg()) * DriverModel.SLIDE_RATE_MULT, DriverModel.SLIDE_MIN_RATE) * slack * 1.2 + 0.5
	var rim_cap := rad_to_deg(step) * 1.2 + 0.5
	var home_cap := DriverModel.HOME_RATE * slack * 1.2 + 0.5
	for side in [-1, 1]:
		var local: Vector3 = to_wheel * d.hand_position(side)
		var ang := rad_to_deg(atan2(local.y, local.x))
		var off := local.distance_to(frame.wheel.rim_point(ang))
		if off > RIM_TOL:
			_fail("%s: hand %d is %.3f m off the rim" % [where, side, off])
		var w: float = d.rim_deg(side)
		var span := DriverModel.rim_range(side)
		if w < span[0] - 0.5 or w > span[1] + 0.5:
			_fail("%s: hand %d at %.1f deg of the rim, outside %s" % [where, side, w, span])
		var hs := absf(w - prev_w[side])
		max_hand_step = maxf(max_hand_step, hs / elapsed)
		if hs > maxf(maxf(slide_cap, rim_cap), home_cap):
			_fail("%s: hand %d moved %.1f deg of rim in %.3f s (holding %s)" % [where, side, hs, elapsed, str(d.is_gripping(side))])
		prev_w[side] = w
		any_grip = any_grip or d.is_gripping(side)
	if not any_grip and absf(frame.wheel_rate()) > deg_to_rad(DriverModel.STILL_RATE):
		_fail("%s: no hand on the wheel while it turns (%.0f deg)" % [where, rad_to_deg(wheel)])
	_track_view(d, where)
	samples += 1

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	var frame: CockpitFrame = cam.frame
	var d: DriverModel = frame.driver
	cur_where = ""
	if not started:
		p.driver = _drive
		cam.set_view(ChaseCamera.View.COCKPIT)
		started = true
		cur_frame = frame
		cur_d = d
		cur_p = p
		seg_start = tick
		for side in [-1, 1]:
			prev_w[side] = d.rim_deg(side)
		return false
	if tick > TIMEOUT_TICKS:
		return _end("timed out in phase %d pattern %d" % [phase, pattern_i])
	warm += 1
	if warm < ticks(0.5):
		# the first render frames place the hands and settle the wheel
		seg_start = tick
		prev_wheel = frame.wheel_angle
		for side in [-1, 1]:
			prev_w[side] = d.rim_deg(side)
		return false
	if waiting:
		return false
	var where := "%s/%s" % [PHASES[phase], patterns[pattern_i][0] if rest_tick < 0 else "rest"]
	if rest_tick > 0:
		# back to straight: after the rest both hands are home, the wheel straight
		steer = 0.0
		if tick - rest_tick >= ticks(2.5) and rest_secs >= 2.5:
			for side in [-1, 1]:
				var off := absf(d.rim_deg(side) - d.home_deg(side))
				_check(off < 1.0 and d.is_gripping(side), "%s: at rest hand %d sits %.1f deg from its grip point" % [PHASES[phase], side, off])
			_check(absf(frame.wheel_angle) < deg_to_rad(1.0), "%s: at rest the wheel is straight (%.1f deg)" % [PHASES[phase], rad_to_deg(frame.wheel_angle)])
			print("%s rest done at tick %d" % [PHASES[phase], tick])
			rest_tick = -1
			rest_secs = 0.0
			_next_phase(p)
			return false
		cur_where = where
		return false
	if _play_pattern():
		print("%s done at tick %d (wheel %.0f deg, hands L %.0f R %.0f, %d shuffles)" % [where, tick, rad_to_deg(frame.wheel_angle), d.rim_deg(-1), d.rim_deg(1), d.shuffle_count])
		if pattern_i == 0 and phase == 0:
			_check(lock_seen, "a full-lock step at a standstill turns the wheel to lock")
			_check(d.shuffle_count > 0, "full lock makes the hands shuffle (let go and re-grip)")
		pattern_i += 1
		seg_i = 0
		seg_start = tick
		if pattern_i >= patterns.size():
			rest_tick = tick
			pattern_i = 0
		return false
	cur_where = where
	return false

func _next_phase(p: PlayerCar) -> void:
	phase += 1
	pattern_i = 0
	seg_i = 0
	seg_start = tick
	var d: DriverModel = current_scene.camera.frame.driver
	if phase == 1:
		p.automatic_transmission = true
		_roll.call_deferred(p)
	elif phase == 2:
		_reverse.call_deferred(p)
	else:
		print("steering hands: %d samples, wheel rate max %.0f deg/s, hand slide max %.0f deg/s, %d shuffles" % [samples, rad_to_deg(max_wheel_step), max_hand_step, d.shuffle_count])
		print("hands: highest point seen %.1f deg below the eye (%s)" % [min_below_eye, min_below_where])
		_check(min_below_eye >= DriverModel.HAND_TOP_MIN_DEG, "a hand rose to %.1f deg below the eye (%s); the road band must stay clear" % [min_below_eye, min_below_where])
		_check(logger.errors.is_empty(), "engine errors: %s" % [logger.errors.slice(0, 5)])
		_end("")

## Up to a rolling speed, then the patterns with the throttle held.
func _roll(p: PlayerCar) -> void:
	waiting = true
	brake = 0.0
	throttle = 0.6
	var t0 := tick
	while p.current_speed() < 12.0 and tick - t0 < ticks(8.0):
		await physics_frame
	_check(p.current_speed() >= 12.0, "the car got rolling for the second pass (%.1f m/s)" % p.current_speed())
	throttle = 0.35
	seg_start = tick
	waiting = false

## Stop, into reverse, then the patterns backing up.
func _reverse(p: PlayerCar) -> void:
	waiting = true
	throttle = 0.0
	brake = 1.0
	var t0 := tick
	while p.current_speed() > PlayerCar.REVERSE_MAX_SPEED * 0.5 and tick - t0 < ticks(10.0):
		await physics_frame
	for i in 20:
		await physics_frame
	# an auto box is still shifting down to first for a moment after the stop,
	# and toggle_reverse refuses while is_shifting
	t0 = tick
	while p.is_shifting and tick - t0 < ticks(3.0):
		await physics_frame
	_check(p.toggle_reverse(), "the car goes into reverse once stopped (%.1f m/s)" % p.current_speed())
	t0 = tick
	while p.is_shifting and tick - t0 < ticks(3.0):
		await physics_frame
	brake = 0.0
	throttle = 0.5
	seg_start = tick
	waiting = false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _fail(msg: String) -> void:
	if failures.size() < 40:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("cockpit_steering_hands: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
