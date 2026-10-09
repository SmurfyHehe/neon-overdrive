extends SceneTree

# Free look on the arrow keys (2026-10-09), headless and silent:
# - look_left/right/up/down exist, sit on the arrow keys and are listed on the
#   Controls page; the arrows are off accelerate/brake/steer, which keep
#   W/S/A/D
# - holding Up does not press "accelerate" (the arrows no longer drive)
# - in both the chase and the cockpit view, with real arrow key events:
#   holding Left turns the camera left of the car, Right to the right, Up
#   pitches it up, Down pitches it down; letting go swings it back to centre
# - holding long stops at the yaw limit
# - the old V + A/D mirror glance is gone: V + D in the cockpit leaves the view
#   straight ahead
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/free_look.gd

const TIMEOUT_TICKS := 60 * 30
const HOLD := 30     # ticks an arrow is held
## Ticks allowed for the view to come back after release. The look moves on
## the render frame (_process), and headless runs fewer frames than physics
## ticks, so the release is polled until it lands instead of read at a fixed tick.
const BACK := 180
const Harness := preload("res://tests/traffic_harness.gd")

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

## One sweep entry: the arrow, the look it should give, and the sign check.
const SWEEP := [
	[KEY_LEFT, "left"], [KEY_RIGHT, "right"], [KEY_UP, "up"], [KEY_DOWN, "down"]]

enum Step { BOOT, SETTLE, PRESS, RELEASE, LIMIT, LIMIT_BACK, GLANCE, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var logger := ErrorCounter.new()
var game: Node
var views := [ChaseCamera.View.CHASE, ChaseCamera.View.COCKPIT]
var view_i := 0
var sweep_i := 0
var base := Vector2.ZERO   # (yaw, pitch) degrees of the view at rest, car space

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_free_look_exhaust.json"
	OS.add_logger(logger)
	game = Harness.boot(self, 0, 300.0, 7)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = 0.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = 0.0

## A real key event, as the keyboard would send it.
static func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

static func _keys(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append((ev as InputEventKey).keycode)
	return out

## Where the camera points, in the car's frame: (yaw + left, pitch + up), degrees.
static func _aim(cam: Camera3D, car: Node3D) -> Vector2:
	var f: Vector3 = car.global_basis.inverse() * -cam.global_basis.z
	var flat := Vector2(f.x, f.z).length()
	return Vector2(rad_to_deg(atan2(-f.x, -f.z)), rad_to_deg(atan2(f.y, flat)))

func _physics_process(_delta: float) -> bool:
	tick += 1
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	p.driver = _drive
	var waited := tick - step_start
	var vname := "chase" if views[mini(view_i, views.size() - 1)] == ChaseCamera.View.CHASE else "cockpit"
	match step:
		Step.BOOT:
			if waited < 5:
				return false
			var arrows := {"look_left": KEY_LEFT, "look_right": KEY_RIGHT, "look_up": KEY_UP, "look_down": KEY_DOWN}
			for a in arrows:
				_check(InputMap.has_action(a), "%s is an input action" % a)
				_check(_keys(a) == [arrows[a]], "%s is on %s only (%s)" % [a, OS.get_keycode_string(arrows[a]), _keys(a)])
			var drive := {"accelerate": KEY_W, "brake": KEY_S, "steer_left": KEY_A, "steer_right": KEY_D}
			for a in drive:
				_check(_keys(a) == [drive[a]], "%s keeps only %s, no arrow (%s)" % [a, OS.get_keycode_string(drive[a]), _keys(a)])
			var listed := {}
			for group in PauseMenu.controls_groups():
				for row in group[1]:
					listed[row[0]] = group[0]
			for a in arrows:
				_check(listed.get(a, "") == "Camera", "%s is on the Controls page under Camera (%s)" % [a, listed.get(a, "missing")])
			_key(KEY_UP, true)
			_check(Input.is_action_pressed("look_up") and not Input.is_action_pressed("accelerate"), "Up presses look_up, not accelerate")
			_key(KEY_UP, false)
			cam.shake_enabled = false
			root.size = Vector2i(1280, 720)
			cam.set_view(views[view_i])
			_go(Step.SETTLE)
		Step.SETTLE:
			if waited == 30:
				base = _aim(cam, p)
				_key(SWEEP[sweep_i][0], true)
				_go(Step.PRESS)
		Step.PRESS:
			if waited == HOLD:
				var d := _aim(cam, p) - base
				var dir: String = SWEEP[sweep_i][1]
				print("%s, hold %s: look yaw %.1f pitch %.1f, camera turned yaw %.1f pitch %.1f" % [vname, dir, cam.look_yaw, cam.look_pitch, d.x, d.y])
				# The camera must actually turn by the look angle (within 2 degrees).
				match dir:
					"left": _check(cam.look_yaw > 20.0 and absf(d.x - cam.look_yaw) < 2.0, "%s: Left turns the view left (yaw %.1f, camera %.1f)" % [vname, cam.look_yaw, d.x])
					"right": _check(cam.look_yaw < -20.0 and absf(d.x - cam.look_yaw) < 2.0, "%s: Right turns the view right (yaw %.1f, camera %.1f)" % [vname, cam.look_yaw, d.x])
					"up": _check(cam.look_pitch > 15.0 and absf(d.y - cam.look_pitch) < 2.0, "%s: Up tilts the view up (pitch %.1f, camera %.1f)" % [vname, cam.look_pitch, d.y])
					"down": _check(cam.look_pitch < -15.0 and absf(d.y - cam.look_pitch) < 2.0, "%s: Down tilts the view down (pitch %.1f, camera %.1f)" % [vname, cam.look_pitch, d.y])
				_key(SWEEP[sweep_i][0], false)
				_go(Step.RELEASE)
		Step.RELEASE:
			var d := _aim(cam, p) - base
			var home := absf(cam.look_yaw) < 0.5 and absf(cam.look_pitch) < 0.5 and d.length() < 1.0
			if home or waited == BACK:
				if home:
					print("%s, let go of %s: back to centre in %d ticks" % [vname, SWEEP[sweep_i][1], waited])
				_check(absf(cam.look_yaw) < 0.5 and absf(cam.look_pitch) < 0.5 and d.length() < 1.0,
					"%s: letting go of %s brings the view back (yaw %.1f pitch %.1f, camera off by %.2f)" % [vname, SWEEP[sweep_i][1], cam.look_yaw, cam.look_pitch, d.length()])
				sweep_i += 1
				if sweep_i < SWEEP.size():
					_key(SWEEP[sweep_i][0], true)
					base = _aim(cam, p)
					_go(Step.PRESS)
				else:
					_key(KEY_LEFT, true)
					_go(Step.LIMIT)
		Step.LIMIT:
			if waited == 240:
				_check(is_equal_approx(cam.look_yaw, ChaseCamera.LOOK_YAW_MAX), "%s: a long hold stops at %.0f degrees (%.1f)" % [vname, ChaseCamera.LOOK_YAW_MAX, cam.look_yaw])
				_key(KEY_LEFT, false)
				_go(Step.LIMIT_BACK)
		Step.LIMIT_BACK:
			if absf(cam.look_yaw) < 0.5 or waited == BACK:
				_check(absf(cam.look_yaw) < 0.5, "%s: back to centre after the long hold (%.1f)" % [vname, cam.look_yaw])
				view_i += 1
				sweep_i = 0
				if view_i < views.size():
					cam.set_view(views[view_i])
					_go(Step.SETTLE)
				else:
					# The removed mirror glance: V + D must not turn the head.
					base = _aim(cam, p)
					Input.action_press("steer_right")
					_key(KEY_V, true)
					_go(Step.GLANCE)
		Step.GLANCE:
			if waited == 1:
				_key(KEY_V, false)
			if waited == 3:
				Input.action_release("steer_right")
			if waited == 45:
				var d := _aim(cam, p) - base
				_check(absf(cam.look_yaw) < 0.5 and absf(d.x) < 2.0, "V + D no longer turns the head (look %.1f, camera %.1f)" % [cam.look_yaw, d.x])
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
	print("free_look: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
