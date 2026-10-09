extends SceneTree

# Smoke test (GitHub #39, ISSUES F2): boot the real Game.tscn, drive it for a
# fixed number of frames, and fail on any engine or script error.
#
# This is the "does the game still start and run" check. It asserts nothing
# about visuals or timing, so it works under --headless (the dummy renderer is
# fine here -- nothing reads MultiMesh data) and is cheap enough for CI.
#
# A bot holds W and shifts up with E so the player, gearbox and chunk
# recycling code all actually run, not just _ready().
#
# Asserts (exit code 1 on failure):
# - Game.tscn loads and instantiates
# - zero errors logged while it runs (script, engine or shader errors;
#   warnings are printed but do not fail)
# - the car moved, so the physics tick is alive
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/core/smoke.gd

const FRAMES := 600  # ~10 s at 60 Hz physics; frames, not seconds, so fast machines finish sooner
const MIN_TRAVEL := 5.0  # metres; a car that boots but never moves is a failure

# Collects everything the engine logs as an error, from any thread.
class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var warnings := 0
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_lock.lock()
		if error_type == ERROR_TYPE_WARNING:
			warnings += 1
		else:
			var msg := rationale if rationale != "" else code
			errors.append("%s (%s:%d in %s)" % [msg, file, line, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

var logger := ErrorCounter.new()
var game: Node
var frame := 0
var start_pos := Vector3.ZERO

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	OS.add_logger(logger)
	seed(777)
	var scene := load("res://Game.tscn") as PackedScene
	if scene == null:
		_finish("Game.tscn failed to load")
		return
	game = scene.instantiate()
	root.add_child(game)

func _press(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _process(_delta: float) -> bool:
	if game == null:
		return true
	var p: PlayerCar = game.get("player")
	if p == null:
		_finish("game has no player after _ready")
		return true
	if frame == 0:
		start_pos = p.global_position
		_press(KEY_W, true)
	frame += 1
	if p.gear >= 1 and p.gear < 6 and p.linear_velocity.length() > 9.0 * p.gear and not p.is_shifting:
		_press(KEY_E, true)
		_press(KEY_E, false)
	if frame >= FRAMES:
		var travel := p.global_position.distance_to(start_pos)
		print("frames=%d travel=%.1f m" % [frame, travel])
		_finish("car only moved %.1f m" % travel if travel < MIN_TRAVEL else "")
		return true
	return false

func _finish(fail_msg: String) -> void:
	var fails: Array[String] = []
	if fail_msg != "":
		fails.append(fail_msg)
	for e in logger.errors:
		fails.append("logged error: " + e)
	for f in fails:
		print("FAIL ", f)
	print("errors=%d warnings=%d" % [logger.errors.size(), logger.warnings])
	print("RESULT: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	OS.remove_logger(logger)
	quit(0 if fails.is_empty() else 1)
