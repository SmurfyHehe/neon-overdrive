extends SceneTree

# Head movement in the cockpit (Roy, 2026-10-06), headless and silent:
# - rigid at the eye while cruising straight at a steady speed (offset ~0)
# - hard braking moves the eye forward and dips it, within 4 cm and 2 degrees
# - a hard turn moves the eye outward and rolls it, within the same caps
# - FxSettings "head_motion" off: the eye eases back to COCKPIT_EYE and stays
#   there through the same braking
# Read from ChaseCamera.head_offset (car-local metres) and head_tilt (pitch,
# roll in degrees), which _place_cockpit adds to COCKPIT_EYE each frame (the
# camera itself is placed in _process on the interpolated car transform, so a
# physics-tick reading of its global transform is half a frame of travel off).
# Exit code 1 on failure.
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/cockpit_head_motion.gd

const TIMEOUT_TICKS := 60 * 40
const EPS_M := 0.004
const EPS_DEG := 0.2

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

enum Step { BOOT, CRUISE, BRAKE, TURN, OFF, DONE }

static func ticks(secs: float) -> int:
	return int(round(secs * Engine.physics_ticks_per_second))

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var steer := 0.0
var throttle := 0.0
var brake := 0.0
var logger := ErrorCounter.new()
var peak_fwd := 0.0
var peak_pitch := 0.0
var peak_lat := 0.0
var peak_roll := 0.0
var max_offset := 0.0
var max_tilt := 0.0
var off_offset := 0.0

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_cockpit_head_motion_exhaust.json"
	OS.add_logger(logger)
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.handbrake_input = 0.0
	c.steering_input = steer

## The head: [offset from the eye (m, car-local), pitch (deg), roll (deg)].
static func _head(_p: PlayerCar, cam: ChaseCamera) -> Array:
	return [cam.head_offset, cam.head_tilt.x, cam.head_tilt.y]

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	p.driver = _drive
	var waited := tick - step_start
	if step != Step.BOOT:
		var h := _head(p, cam)
		max_offset = maxf(max_offset, (h[0] as Vector3).length())
		max_tilt = maxf(max_tilt, maxf(absf(h[1]), absf(h[2])))
	match step:
		Step.BOOT:
			cam.shake_enabled = false
			cam.set_view(ChaseCamera.View.COCKPIT)
			p.automatic_transmission = true
			throttle = 1.0
			_check(FxSettings.is_on("head_motion"), "head motion defaults on")
			_go(Step.CRUISE)
		Step.CRUISE:
			if p.current_speed() > 25.0:
				throttle = 0.35   # hold about 90 km/h
			if waited == ticks(6.0):
				var h := _head(p, cam)
				print("cruise: speed %.0f km/h, offset %s, pitch %.2f, roll %.2f" % [p.current_speed() * 3.6, h[0], h[1], h[2]])
				_check((h[0] as Vector3).length() < 0.012 and absf(h[1]) < 0.6 and absf(h[2]) < 0.6, "cruising straight the head is near the eye (offset %.3f m, pitch %.2f, roll %.2f)" % [(h[0] as Vector3).length(), h[1], h[2]])
				throttle = 0.0
				brake = 1.0
				_go(Step.BRAKE)
		Step.BRAKE:
			var h := _head(p, cam)
			peak_fwd = maxf(peak_fwd, -(h[0] as Vector3).z)
			peak_pitch = maxf(peak_pitch, -h[1])
			if waited == ticks(1.2):
				print("brake: head forward %.3f m, dip %.2f deg" % [peak_fwd, peak_pitch])
				_check(peak_fwd > 0.01 and peak_fwd <= ChaseCamera.HEAD_MAX_M + EPS_M, "braking moves the head forward 1 to 4 cm (%.3f)" % peak_fwd)
				_check(peak_pitch > 0.5 and peak_pitch <= ChaseCamera.HEAD_MAX_DEG + EPS_DEG, "braking dips the head 0.5 to 2 degrees (%.2f)" % peak_pitch)
				brake = 0.0
				throttle = 1.0
				_go(Step.TURN)
		Step.TURN:
			# back up to about 60 km/h first (the brake step may have left the
			# automatic in reverse at a standstill), then two seconds of full lock
			if p.current_speed() > 17.0:
				throttle = 0.3
			if steer == 0.0 and p.current_speed() > 14.0 and waited > ticks(1.0):
				steer = -0.6   # right, short of a spin
				step_start = tick - ticks(5.0)
			var h := _head(p, cam)
			if steer != 0.0:
				peak_lat = maxf(peak_lat, absf((h[0] as Vector3).x))
				peak_roll = maxf(peak_roll, absf(h[2]))
			if waited > ticks(20.0):
				return _end("the car never got back up to speed for the turn (%.0f km/h)" % (p.current_speed() * 3.6))
			if steer != 0.0 and waited == ticks(7.0):
				print("turn: speed %.0f km/h, head sideways %.3f m, roll %.2f deg" % [p.current_speed() * 3.6, peak_lat, peak_roll])
				_check(peak_lat > 0.005 and peak_lat <= ChaseCamera.HEAD_MAX_M + EPS_M, "a hard turn moves the head sideways 0.5 to 4 cm (%.3f)" % peak_lat)
				_check(peak_roll > 0.25 and peak_roll <= ChaseCamera.HEAD_MAX_DEG + EPS_DEG, "a hard turn rolls the head 0.25 to 2 degrees (%.2f)" % peak_roll)
				steer = 0.0
				FxSettings.set_on("head_motion", false)
				_go(Step.OFF)
		Step.OFF:
			if waited < ticks(2.0):
				throttle = 1.0
			if waited == ticks(2.0):
				throttle = 0.0
				brake = 1.0
			if waited > ticks(2.0):
				off_offset = maxf(off_offset, (_head(p, cam)[0] as Vector3).length())
			if waited == ticks(3.5):
				var h := _head(p, cam)
				print("off: offset while braking %.4f m, pitch %.2f" % [off_offset, h[1]])
				_check(off_offset < EPS_M and absf(h[1]) < EPS_DEG and absf(h[2]) < EPS_DEG, "with head motion off the eye stays rigid under braking (%.4f m, %.2f deg)" % [off_offset, h[1]])
				FxSettings.set_on("head_motion", true)
				_check(max_offset <= ChaseCamera.HEAD_MAX_M + EPS_M and max_tilt <= ChaseCamera.HEAD_MAX_DEG + EPS_DEG, "the caps held throughout (max %.3f m, %.2f deg)" % [max_offset, max_tilt])
				_check(logger.errors.is_empty(), "engine errors: %s" % [logger.errors.slice(0, 5)])
				return _end("")
	return false

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("cockpit_head_motion: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
