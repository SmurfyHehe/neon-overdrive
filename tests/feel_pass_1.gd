extends SceneTree

# Feel pass 1 test (2026-10-05): in the real Game.tscn
# - the car shifts itself: holding W alone reaches 3rd gear or higher
# - a steering key ramps toward lock (two ticks in, nowhere near full lock)
# - the lock available shrinks with speed (a held key stays under the speed's cap)
# - G switches to the manual gearbox and back
# Exit code 1 on failure. Run (silent, a window opens for ~30 s):
#   Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . -s res://tests/feel_pass_1.gd

const TIMEOUT_TICKS := 60 * 40
const HOLD_TICKS := 6

enum Step { BOOT, ACCEL, RAMP, HELD, GEAR_KEY, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var releases := {}

func _initialize() -> void:
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	for code in releases.keys():
		if tick >= releases[code]:
			_key(code, false)
			releases.erase(code)
	var game := current_scene
	if game == null or game.get("player") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	var waited := tick - step_start
	match step:
		Step.BOOT:
			_check(p.automatic_transmission, "the car should start in automatic")
			_key(KEY_W, true)
			_go(Step.ACCEL)
		Step.ACCEL:
			if p.current_gear >= 3 and p.current_speed() > 25.0:
				_go(Step.RAMP)
				_key(KEY_D, true)
			elif waited > TIMEOUT_TICKS:
				return _end("W alone never got past gear %d (speed %.1f)" % [p.current_gear, p.current_speed()])
		Step.RAMP:
			if waited == 2:
				_check(absf(p.steering_input) < 0.2, "steering jumped to %.2f two ticks after a key press" % p.steering_input)
			if waited == 90:
				var speed_t := clampf((p.current_speed() - PlayerCar.STEER_SLOW_SPEED) / (PlayerCar.STEER_FAST_SPEED - PlayerCar.STEER_SLOW_SPEED), 0.0, 1.0)
				var cap := lerpf(1.0, PlayerCar.STEER_LOCK_MIN, speed_t)
				_check(absf(p.steering_input) <= cap + 0.02, "held key %.2f is over the %.2f cap at %.0f m/s" % [absf(p.steering_input), cap, p.current_speed()])
				_check(absf(p.steering_input) > 0.1, "held key never built up any steering (%.2f)" % p.steering_input)
				_key(KEY_D, false)
				_go(Step.GEAR_KEY)
				_tap(KEY_G)
		Step.GEAR_KEY:
			if waited == 20:
				_check(not p.automatic_transmission, "G should switch to manual")
				_tap(KEY_G)
			if waited == 45:
				_check(p.automatic_transmission, "G again should switch back to automatic")
				return _end("")
	return false

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
