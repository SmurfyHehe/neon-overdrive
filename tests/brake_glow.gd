extends SceneTree

# Glowing brake discs (2026-10-09), headless. Boots the real Game.tscn and
# checks that
# - the player has a BrakeGlow with its own front and rear wheel materials
#   (not the shared one), cold brakes give no glow
# - a hard stop from ~200 km/h heats the brakes past GLOW_START, so the
#   discs glow (front brighter than rear), and the glow fades as they cool
#   driving on afterwards
# - heat_for() maps GLOW_START..GLOW_FULL onto 0..1, clamped
# - nothing logs an error the whole time
# The look (dull red, orange near the top) was checked by eye on the real
# renderer. Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/brake_glow.gd

const TIMEOUT_TICKS := 60 * 90

enum Step { BOOT, CHECK, LAUNCH, BRAKE, COOL, DONE }

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
var peak_heat := 0.0

func _initialize() -> void:
	OS.add_logger(logger)
	change_scene_to_file("res://Game.tscn")

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.steering_input = 0.0
	c.handbrake_input = 0.0

func _go(s: Step) -> void:
	step = s
	step_start = tick

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	if tick > TIMEOUT_TICKS:
		return _end("timed out in step %d" % step)
	var p: PlayerCar = game.player
	p.driver = _drive
	var glow := p.get_node_or_null("BrakeGlow") as BrakeGlow
	var waited := tick - step_start
	match step:
		Step.BOOT:
			_go(Step.CHECK)
		Step.CHECK:
			if waited < 5:
				return false
			_check(glow != null, "the player has a BrakeGlow")
			if glow == null:
				return _end("")
			_check(glow.front_mat != null and glow.rear_mat != null and glow.front_mat != glow.rear_mat, "front and rear wheels get their own materials")
			_check(is_equal_approx(BrakeGlow.heat_for(BrakeGlow.GLOW_START), 0.0) and is_equal_approx(BrakeGlow.heat_for(BrakeGlow.GLOW_FULL), 1.0)
				and BrakeGlow.heat_for(2000.0) == 1.0 and BrakeGlow.heat_for(20.0) == 0.0, "heat_for maps and clamps")
			_check(float(glow.front_mat.get_shader_parameter("brake_heat")) == 0.0, "cold brakes do not glow")
			throttle = 1.0
			_go(Step.LAUNCH)
		Step.LAUNCH:
			if p.current_speed() * 3.6 >= 200.0 or waited > 60 * 40:
				print("braking from %.0f km/h" % (p.current_speed() * 3.6))
				throttle = 0.0
				brake = 1.0
				_go(Step.BRAKE)
		Step.BRAKE:
			peak_heat = maxf(peak_heat, float(glow.front_mat.get_shader_parameter("brake_heat")))
			if p.current_speed() < 1.0 or waited > 60 * 15:
				var front := float(glow.front_mat.get_shader_parameter("brake_heat"))
				var rear := float(glow.rear_mat.get_shader_parameter("brake_heat"))
				print("stopped: brakes %.0f degC, front heat %.2f, rear %.2f" % [p.health.brake_temp, front, rear])
				_check(front > 0.2, "a hard stop from speed makes the discs glow (front heat %.2f)" % front)
				_check(rear < front, "the rear discs glow less than the front")
				brake = 0.0
				throttle = 0.5
				_go(Step.COOL)
		Step.COOL:
			if waited > 60 * 10:
				var after := float(glow.front_mat.get_shader_parameter("brake_heat"))
				print("10 s on: front heat %.2f (peak %.2f)" % [after, peak_heat])
				_check(after < peak_heat * 0.8, "the glow fades as the brakes cool")
				return _end("")
	return false

func _end(why: String) -> bool:
	if why != "":
		failures.append(why)
	for e in logger.errors:
		failures.append("logged error: " + e)
	if failures.is_empty():
		print("brake_glow: PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL ", f)
		quit(1)
	return true
