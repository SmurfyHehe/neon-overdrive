extends SceneTree

# Line lock (2026-10-08), headless and silent: boots the real Game.tscn with
# the stock car (traction control and stability at their defaults) and checks
# - brake alone at rest does not engage the line lock
# - brake + full throttle from a stop engages it: the fronts hold the car
#   (under 3 m of creep in 3 s), the rears spin (surface speed over 8 m/s),
#   the engine revs (mean over 3,000 rpm) and burnout smoke pours
# - lifting the throttle releases it and puts the brake split back exactly
# - brake + throttle while rolling at 12 m/s does not engage it
# - nothing logs an error the whole time
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/car/burnout_line_lock.gd

const TIMEOUT_TICKS := 60 * 90

enum Step { BOOT, SETTLE, BRAKE_ONLY, BURNOUT, RELEASE, LAUNCH, ROLLING }

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

var logger := ErrorCounter.new()
var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
var brake := 0.0
var start_x := 0.0
var start_pos := Vector3.ZERO
var bias := Vector2.ZERO
var mark := 0
var n := 0
var rear_surface := 0.0
var rpm := 0.0
var locked_ticks := 0

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_burnout_line_lock_exhaust.json"
	OS.add_logger(logger)
	seed(4242)
	change_scene_to_file("res://Game.tscn")

func _sec(seconds: float) -> int:
	return int(seconds * Engine.physics_ticks_per_second)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.steering_input = 0.0
	c.handbrake_input = 0.0

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("fx") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	if tick > TIMEOUT_TICKS:
		return _end("timed out in step %d" % step)
	var p: PlayerCar = game.player
	# tyre smoke (PR #159) may not be on this branch yet: check it only when present
	var s = game.fx.get("smoke")
	p.driver = _drive
	var waited := tick - step_start
	match step:
		Step.BOOT:
			if waited >= 5:
				if s != null:
					load("res://scripts/fx/fx_settings.gd").call("set_smoke", 1.0, 1.0)
				start_x = p.global_position.x
				brake = 1.0
				_go(Step.SETTLE)
		Step.SETTLE:
			if waited >= _sec(1.5):
				p.global_transform = Transform3D(Basis.IDENTITY, Vector3(start_x, p.global_position.y + 0.05, p.global_position.z))
				p.linear_velocity = Vector3.ZERO
				p.angular_velocity = Vector3.ZERO
				bias = Vector2(p.front_axle.brake_bias, p.rear_axle.brake_bias)
				_check(p.traction_control_max_slip > 0.0 and p.stability_yaw_strength > 0.0,
					"the stock car should have traction control and stability on")
				_go(Step.BRAKE_ONLY)
		Step.BRAKE_ONLY:
			if waited >= _sec(0.5):
				_check(not p.line_lock, "brake alone should not engage the line lock")
				start_pos = p.global_position
				mark = s.emitted_burnout if s != null else 0
				throttle = 1.0
				_go(Step.BURNOUT)
		Step.BURNOUT:
			if p.line_lock:
				locked_ticks += 1
			var w2 = p.wheel_array[2]
			var w3 = p.wheel_array[3]
			rear_surface += (absf(w2.spin * w2.tire_radius) + absf(w3.spin * w3.tire_radius)) / 2.0
			rpm += p.motor_rpm
			n += 1
			if waited >= _sec(3.0):
				var moved := p.global_position.distance_to(start_pos)
				var puffs: int = s.emitted_burnout - mark if s != null else -1
				print("line lock burnout: locked %d%% of ticks, rear surface %.1f m/s, rpm %.0f, moved %.2f m, %d burnout puffs, bias %.2f/%.2f" % [
					100 * locked_ticks / n, rear_surface / n, rpm / n, moved, puffs, p.front_axle.brake_bias, p.rear_axle.brake_bias])
				_check(locked_ticks > n * 0.95, "brake + throttle at rest should hold the line lock")
				_check(p.front_axle.brake_bias == 1.0 and p.rear_axle.brake_bias == 0.0, "line lock should brake the fronts only")
				_check(rear_surface / n > 8.0, "the rears should spin (%.1f m/s)" % (rear_surface / n))
				_check(rpm / n > 3000.0, "the engine should rev, not bog (%.0f rpm)" % (rpm / n))
				_check(moved < 3.0, "the fronts should hold the car (moved %.2f m)" % moved)
				_check(s == null or puffs > 0, "a line-lock burnout should make burnout smoke")
				throttle = 0.0
				_go(Step.RELEASE)
		Step.RELEASE:
			if waited >= 2:
				_check(not p.line_lock, "lifting the throttle should release the line lock")
				_check(p.front_axle.brake_bias == bias.x and p.rear_axle.brake_bias == bias.y,
					"release should restore the brake split (%.2f/%.2f, was %.2f/%.2f)" % [p.front_axle.brake_bias, p.rear_axle.brake_bias, bias.x, bias.y])
				brake = 0.0
				throttle = 1.0
				_go(Step.LAUNCH)
		Step.LAUNCH:
			if p.speed >= 12.0:
				brake = 1.0
				_go(Step.ROLLING)
			elif waited > _sec(20):
				return _end("never reached 12 m/s")
		Step.ROLLING:
			_check(not p.line_lock, "brake + throttle while rolling at 12 m/s should not engage the line lock")
			if waited >= _sec(0.3):
				return _end("")
	return false

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok and not failures.has(msg):
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for e in logger.errors:
		failures.append("logged error: " + e)
	for f in failures:
		printerr("FAIL: ", f)
	print("burnout_line_lock: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	OS.remove_logger(logger)
	quit(0 if failures.is_empty() else 1)
	return true
