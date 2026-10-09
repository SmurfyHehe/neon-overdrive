extends SceneTree

# Automatic quality check and "Test my PC" (2026-10-09). Real renderer (it
# reads GPU frame times). Checks that
# - pick() maps GPU time at Medium to High / Medium / Low at the thresholds
# - the check never starts by itself in a test run (should_auto_run false)
# - the Graphics page's "Test my PC" runs it under the pause menu: the
#   button greys out, a preset is picked from a real GPU time, applied,
#   saved to the settings file, and the page says which
# - nothing logs an error
# Prints the GPU time and pick for this machine (the reference laptop lands
# on Medium; not asserted, it depends on what else is running).
# Exit code 1 on failure. Run (a window opens for ~15 s):
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tests/quality_check.gd

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

var logger := ErrorCounter.new()
var failures: Array[String] = []
var game: Node
var menu: PauseMenu
var frame := 0
var done := false

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func _initialize() -> void:
	OS.add_logger(logger)
	_check(QualityCheck.pick(QualityCheck.HIGH_BELOW - 0.5) == "high", "fast GPU picks High")
	_check(QualityCheck.pick(9.8) == "medium", "the reference laptop's 9.8 ms picks Medium")
	_check(QualityCheck.pick(QualityCheck.LOW_ABOVE + 0.5) == "low", "slow GPU picks Low")
	_check(not QualityCheck.should_auto_run(), "the check does not start by itself in a test run")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Harness.SETTINGS_PATH))
	game = Harness.boot(self, 0, 300.0, 7)

func _process(_d: float) -> bool:
	frame += 1
	if frame == 40:
		_check(game.get_node_or_null("QualityCheck") == null, "no check running at boot in a test")
		for n in game.get_children():
			if n is PauseMenu:
				menu = n
			if n is GameState:
				n.pause()
		menu.show_graphics()
		menu.test_my_pc()
		_check(menu.gfx_test_button.disabled and game.get_node_or_null("QualityCheck") != null, "Test my PC starts the check and greys the button")
		var qc: QualityCheck = game.get_node("QualityCheck")
		qc.finished.connect(func(preset: String, gpu_ms: float) -> void:
			print("this PC: Medium %.2f ms on the GPU -> %s" % [gpu_ms, preset])
			_check(gpu_ms > 0.0, "a real GPU time was measured")
			_check(GraphicsSettings.preset == preset, "the pick is applied")
			var cfg := ConfigFile.new()
			cfg.load(AudioSettings.path)
			_check(str(cfg.get_value("graphics", "preset", "")) == preset, "the pick is saved")
			done = true)
	if done and frame < 100000:
		frame = 100000
	if frame == 100003:
		_check(not menu.gfx_test_button.disabled and menu.gfx_test_label.text.begins_with("Picked"), "the page says what was picked")
		return _end("")
	if frame == 1200 and not done:
		return _end("the check never finished")
	return false

func _end(why: String) -> bool:
	if why != "":
		failures.append(why)
	for e in logger.errors:
		failures.append("logged error: " + e)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Harness.SETTINGS_PATH))
	if failures.is_empty():
		print("quality_check: PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL ", f)
		quit(1)
	return true
