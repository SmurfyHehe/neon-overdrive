extends SceneTree

# Feel pass 1 test (2026-10-05): in the real Game.tscn
# - the car shifts itself: holding W alone reaches 3rd gear or higher
# - a steering key ramps toward lock (two ticks in, nowhere near full lock)
# - the lock available shrinks with speed (a held key stays under the cap for the speed)
# - the wheels really turn by the capped amount: at ~30 and ~50 m/s a held key
#   puts the front wheels at the player's capped lock (the fraction of
#   max_steering_angle, read off the wheel nodes), not GEVP's rate-limited,
#   exponent-squashed version of it. Before the steer-feel change the wheels
#   were at 0.10 and 0.06 of lock there, against caps of 0.56 and 0.25 (0.27 and
#   0.25 with the grip limit).
# - G switches to the manual gearbox and back
# Exit code 1 on failure. Run (silent, a window opens for ~30 s):
#   Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . -s res://tests/feel_pass_1.gd

## 40 s of game time, whatever the tick rate (the 50 m/s check needs ~25 s at 120 Hz).
func _timeout() -> int:
	return 40 * Engine.physics_ticks_per_second

const HOLD_TICKS := 6

enum Step { BOOT, ACCEL, WHEEL, STRAIGHTEN, SETTLE, RAMP, GEAR_KEY, DONE }

## Speeds (m/s) the real wheel angle is checked at; WHEEL_HOLD_SECS of held key each.
const WHEEL_SPEEDS := [30.0, 50.0]
## Long enough for the ramp to reach the cap (0.2 s at the worst), short enough that
## GEVP's countersteer assist (it pulls the wheels back as the car starts to slide
## sideways) has not yet eaten into it: at 50 m/s it takes ~0.3 s to.
const WHEEL_HOLD_SECS := 0.22
var wheel_i := 0
var wheel_pressed := false

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var releases := {}

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	for code in releases.keys():
		if tick >= releases[code]:
			_key(code, false)
			releases.erase(code)
	var game := current_scene
	if game == null or game.get("player") == null:
		return tick > _timeout() and _end("Game never became ready")
	var p: PlayerCar = game.player
	var waited := tick - step_start
	match step:
		Step.BOOT:
			_check(p.automatic_transmission, "the car should start in automatic")
			_key(KEY_W, true)
			_go(Step.ACCEL)
		Step.ACCEL:
			_hold_heading(p)
			if p.current_gear >= 3 and p.current_speed() > 25.0:
				_go(Step.WHEEL)
			elif waited > _timeout():
				return _end("W alone never got past gear %d (speed %.1f)" % [p.current_gear, p.current_speed()])
		Step.SETTLE:
			# keys up and the steering back at centre, so the ramp below starts from zero
			if waited >= int(0.5 * Engine.physics_ticks_per_second):
				_set_dir(false, true)
				_go(Step.RAMP)
		Step.RAMP:
			if waited == 2:
				_check(absf(p.steer_fraction()) < 0.2, "steering jumped to %.2f two ticks after a key press" % p.steer_fraction())
			if waited == 90:
				var cap := p.steer_lock_cap()
				_check(absf(p.steer_fraction()) <= cap + 0.02, "held key %.2f is over the %.2f cap at %.0f m/s" % [absf(p.steer_fraction()), cap, p.current_speed()])
				_check(absf(p.steer_fraction()) > 0.1, "held key never built up any steering (%.2f)" % p.steer_fraction())
				_key(KEY_D, false)
				_go(Step.GEAR_KEY)
				_tap(KEY_G)
		Step.WHEEL:
			var want_speed: float = WHEEL_SPEEDS[wheel_i]
			if not wheel_pressed:
				_hold_heading(p)
				if p.current_speed() >= want_speed and not p.is_shifting and absf(p.global_rotation.y) < 0.03 and absf(p.angular_velocity.y) < 0.1:
					_set_dir(false, true)
					wheel_pressed = true
					_go(Step.WHEEL)
				elif waited > _timeout():
					return _end("never reached %.0f m/s for the wheel check (%.1f)" % [want_speed, p.current_speed()])
			elif waited >= int(WHEEL_HOLD_SECS * Engine.physics_ticks_per_second):
				var cap := p.steer_lock_cap()
				var wheel := _wheel_fraction(p)
				print("wheel at %.1f m/s: input %.3f (cap %.3f), wheel %.3f of lock (%.1f deg)" % [p.current_speed(), absf(p.steer_fraction()), cap, wheel, rad_to_deg(wheel * p.max_steering_angle)])
				_check(absf(wheel - cap) <= 0.06, "wheels at %.3f of lock at %.0f m/s, the speed cap says %.3f" % [wheel, p.current_speed(), cap])
				wheel_pressed = false
				wheel_i += 1
				_go(Step.STRAIGHTEN)
		Step.STRAIGHTEN:
			# Swing back onto the road heading so the next check starts on the road.
			_hold_heading(p)
			if (absf(p.global_rotation.y) < 0.03 and absf(p.angular_velocity.y) < 0.1) or waited > _timeout():
				if wheel_i >= WHEEL_SPEEDS.size():
					_set_dir(false, false)
					_go(Step.SETTLE)
				else:
					_go(Step.WHEEL)
		Step.GEAR_KEY:
			if waited == 20:
				_check(not p.automatic_transmission, "G should switch to manual")
				_tap(KEY_G)
			if waited == 45:
				_check(p.automatic_transmission, "G again should switch back to automatic")
				return _end("")
	return false

## Mean of the two front wheels' steer angle as a fraction of max_steering_angle
## (the mean cancels toe and the Ackermann difference between the wheels).
func _wheel_fraction(p: PlayerCar) -> float:
	var a := (p.front_left_wheel.rotation.y + p.front_right_wheel.rotation.y) * 0.5
	return absf(a) / p.max_steering_angle

## Holds the heading down the road with the A/D keys (the same input path a player uses).
func _hold_heading(p: PlayerCar) -> void:
	# yaw plus a bit of yaw rate, so the bang-bang keys do not overshoot at speed
	var err := p.global_rotation.y + 0.35 * p.angular_velocity.y
	_set_dir(err < -0.02, err > 0.02)

var _dir_left := false
var _dir_right := false
func _set_dir(left: bool, right: bool) -> void:
	if left != _dir_left:
		_key(KEY_A, left)
		_dir_left = left
	if right != _dir_right:
		_key(KEY_D, right)
		_dir_right = right

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _tap(code: Key) -> void:
	_key(code, true)
	releases[code] = tick + HOLD_TICKS

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("feel_pass_1: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
