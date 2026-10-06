extends SceneTree

# Effects pack v1 (2026-10-06), headless and silent: boots the real Game.tscn and
# checks that
# - game.fx exists with its three nodes (ScreenFx, SkidMarks, ExhaustFlames) in
#   the tree, all four FxSettings flags default on, and set_effect() flips each
#   node's state off and back on
# - a handbrake slide at speed lays at least one skid quad
# - lifting off at rpm makes the synth spit a flame that ExhaustFlames shows
#   (bursts > 0 through the real EngineAudio -> take_flames() path)
# - shift_world() moves every live skid quad by the offset
# - nothing logs an error the whole time
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/fx_pack.gd

const TIMEOUT_TICKS := 60 * 60

enum Step { BOOT, CHECK, LAUNCH, SLIDE, REV, LIFT, SHIFT, DONE }

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
var steer := 0.0
var handbrake := 0.0

func _initialize() -> void:
	# Never read (or write) the player's saved exhaust tune: a test must see the preset.
	ExhaustTune.save_path = "user://autotune/test_fx_pack_exhaust.json"
	OS.add_logger(logger)
	seed(777)
	change_scene_to_file("res://Game.tscn")

func _sec(seconds: float) -> int:
	return int(seconds * Engine.physics_ticks_per_second)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 0.0
	c.steering_input = steer
	c.handbrake_input = handbrake

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("fx") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	if tick > TIMEOUT_TICKS:
		return _end("timed out in step %d" % step)
	var p: PlayerCar = game.player
	var fx: FxPack = game.fx
	p.driver = _drive
	var waited := tick - step_start
	match step:
		Step.BOOT:
			_go(Step.CHECK)
		Step.CHECK:
			if waited < 5:
				return false
			_check(fx.is_inside_tree() and fx.get_parent() == game, "FxPack should be a child of the game")
			_check(fx.screen != null and fx.screen.is_inside_tree(), "ScreenFx should be in the tree")
			_check(fx.skids != null and fx.skids.is_inside_tree(), "SkidMarks should be in the tree")
			_check(fx.flames != null and fx.flames.is_inside_tree() and fx.flames.get_parent() == p, "ExhaustFlames should be on the player")
			for e in FxSettings.EFFECTS:
				_check(FxSettings.is_on(e), "%s should default on" % e)
			# each flag turns its node off and back on
			fx.set_effect("vignette", false)
			fx.set_effect("speed_lines", false)
			_check(not fx.screen.vignette_on and not fx.screen.speed_lines_on and not fx.screen._rect.visible, "vignette + speed lines off should hide the screen pass")
			fx.set_effect("vignette", true)
			_check(fx.screen.vignette_on and fx.screen._rect.visible, "vignette on should show the screen pass again")
			fx.set_effect("speed_lines", true)
			_check(fx.screen.speed_lines_on, "speed_lines flag should reach ScreenFx")
			fx.set_effect("skid_marks", false)
			_check(not fx.skids.enabled and not fx.skids.visible and not fx.skids.is_physics_processing(), "skid_marks off should hide and stop SkidMarks")
			fx.set_effect("skid_marks", true)
			_check(fx.skids.enabled and fx.skids.visible and fx.skids.is_physics_processing(), "skid_marks on should restart SkidMarks")
			fx.set_effect("exhaust_flames", false)
			_check(not fx.flames.enabled and not fx.flames.is_processing(), "exhaust_flames off should stop ExhaustFlames")
			fx.set_effect("exhaust_flames", true)
			_check(fx.flames.enabled and fx.flames.is_processing(), "exhaust_flames on should restart ExhaustFlames")
			_check(fx.flames.get_child_count() == 2, "the test car has two exhaust tips (%d quads)" % fx.flames.get_child_count())
			# the visual path on its own: a direct flash shows the quads
			fx.flames.flash(0.5)
			_check(fx.flames.is_showing(), "flash() should start a burst")
			throttle = 1.0
			_go(Step.LAUNCH)
		Step.LAUNCH:
			if p.linear_velocity.length() > 16.0:
				throttle = 0.0
				handbrake = 1.0
				steer = 1.0
				_go(Step.SLIDE)
			elif waited > _sec(25):
				return _end("launch never reached 16 m/s (%.1f)" % p.linear_velocity.length())
		Step.SLIDE:
			if waited >= _sec(2.0):
				print("slide: %d skid quads laid, %d live" % [fx.skids.laid, fx.skids.live_count()])
				_check(fx.skids.laid > 0, "a handbrake slide at speed should lay skid marks")
				handbrake = 0.0
				steer = 0.0
				throttle = 1.0
				fx.flames.bursts = 0
				_go(Step.REV)
		Step.REV:
			if waited >= _sec(2.5):
				throttle = 0.0
				fx.flames.bursts = 0
				_go(Step.LIFT)
		Step.LIFT:
			if waited >= _sec(3.0):
				print("lift-off: %d flame bursts, biggest %.2f" % [fx.flames.bursts, fx.flames.max_size])
				_check(fx.flames.bursts > 0, "lifting off at rpm should produce a flame burst through EngineAudio")
				_go(Step.SHIFT)
		Step.SHIFT:
			var before: Array[Vector3] = []
			var idx: Array[int] = []
			for i in SkidMarks.MAX_SEGMENTS:
				if fx.skids._live[i] == 1:
					idx.append(i)
					before.append(fx.skids._xf[i].origin)
			var offset := Vector3(0.0, 0.0, 150.0)
			fx.shift_world(offset)
			var moved := true
			for k in idx.size():
				if not fx.skids._xf[idx[k]].origin.is_equal_approx(before[k] + offset):
					moved = false
			_check(idx.size() > 0 and moved, "shift_world should move every live skid quad (%d quads)" % idx.size())
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
	for e in logger.errors:
		failures.append("logged error: " + e)
	for f in failures:
		printerr("FAIL: ", f)
	print("fx_pack: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	OS.remove_logger(logger)
	quit(0 if failures.is_empty() else 1)
	return true
