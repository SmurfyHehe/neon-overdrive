extends SceneTree

# Graphics settings (polish pass, 2026-10-08), headless and silent. Checks
# - each preset sets its values; a hand change to a value makes the preset
#   "custom", and changing it back to the preset's value names the preset again
# - render scale clamps, and NaN falls back to 1
# - save/load round-trips a preset and a custom set; a damaged file falls back
#   to the default preset
# - the real Game.tscn boots with the settings applied to the root viewport,
#   the pause menu's Graphics page exists, and picking a preset there applies it
# - nothing logs an error the whole time
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/graphics_settings.gd

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
var frame := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func _initialize() -> void:
	OS.add_logger(logger)
	_unit_checks()
	game = Harness.boot(self, 0, 300.0, 3)

func _unit_checks() -> void:
	AudioSettings.path = "user://graphics_test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioSettings.path))
	for p in GraphicsSettings.PRESETS:
		GraphicsSettings.set_preset(p)
		var v: Dictionary = GraphicsSettings.PRESET_VALUES[p]
		_check(GraphicsSettings.preset == p and GraphicsSettings.aa == v.aa and is_equal_approx(GraphicsSettings.render_scale, v.render_scale), "preset %s sets its values" % p)
	GraphicsSettings.set_preset("high")
	GraphicsSettings.set_aa("off")
	_check(GraphicsSettings.preset == "custom", "a hand change makes the preset custom")
	GraphicsSettings.set_aa(GraphicsSettings.PRESET_VALUES.high.aa)
	_check(GraphicsSettings.preset == "high", "changing back names the preset again")
	GraphicsSettings.set_render_scale(0.1)
	_check(is_equal_approx(GraphicsSettings.render_scale, GraphicsSettings.SCALE_MIN), "render scale clamps low")
	GraphicsSettings.set_render_scale(NAN)
	_check(is_equal_approx(GraphicsSettings.render_scale, 1.0), "NaN render scale falls back to 1")
	GraphicsSettings.set_aa("bogus")
	_check(GraphicsSettings.aa in GraphicsSettings.AA_MODES, "an unknown AA mode is ignored")

	# Round trip: a preset, then a custom set.
	GraphicsSettings.set_preset("low")
	_check(GraphicsSettings.save_settings(), "save works")
	GraphicsSettings.set_preset("high")
	GraphicsSettings.load_settings()
	_check(GraphicsSettings.preset == "low" and GraphicsSettings.aa == GraphicsSettings.PRESET_VALUES.low.aa, "a saved preset loads back")
	GraphicsSettings.set_preset("medium")
	GraphicsSettings.set_aa("msaa4")
	GraphicsSettings.set_render_scale(0.65)
	GraphicsSettings.save_settings()
	GraphicsSettings.set_preset("low")
	GraphicsSettings.load_settings()
	_check(GraphicsSettings.preset == "custom" and GraphicsSettings.aa == "msaa4" and is_equal_approx(GraphicsSettings.render_scale, 0.65), "a custom set loads back")

	# Damaged file: the default preset.
	var f := FileAccess.open(AudioSettings.path, FileAccess.WRITE)
	f.store_string("[graphics]\npreset=\"nonsense\"\naa=12\nrender_scale=\"x\"\n")
	f.close()
	GraphicsSettings.load_settings()
	_check(GraphicsSettings.aa in GraphicsSettings.AA_MODES and GraphicsSettings.render_scale >= GraphicsSettings.SCALE_MIN, "a damaged file still gives valid values")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioSettings.path))
	GraphicsSettings.set_preset(GraphicsSettings.PRESET_DEFAULT)

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 30:
		var vp := root
		var v: Dictionary = GraphicsSettings.PRESET_VALUES[GraphicsSettings.preset]
		_check(is_equal_approx(vp.scaling_3d_scale, v.render_scale), "the game applies the render scale at boot")
		var menu: PauseMenu = null
		for n in game.get_children():
			if n is PauseMenu:
				menu = n
		_check(menu != null and menu.graphics_page != null, "the pause menu has a Graphics page")
		if menu != null:
			menu.show_graphics()
			_check(menu.graphics_page.visible and not menu.main_page.visible, "the Graphics page opens")
			menu.gfx_preset.select(2)
			menu.gfx_preset.item_selected.emit(2)  # High
			_check(GraphicsSettings.preset == "high" and vp.msaa_3d == Viewport.MSAA_4X, "picking High in the menu applies MSAA 4x")
			menu.gfx_preset.item_selected.emit(0)  # Low
			_check(vp.scaling_3d_scale < 1.0 and vp.msaa_3d == Viewport.MSAA_2X, "picking Low applies its scale and MSAA 2x")
			menu.gfx_aa.item_selected.emit(0)
			_check(GraphicsSettings.preset == "custom" and menu.gfx_preset.selected == 3, "a hand change shows Custom")
			menu.show_main()
	if frame == 40:
		for e in logger.errors:
			failures.append("logged error: " + e)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioSettings.path))
		if failures.is_empty():
			print("PASS graphics_settings")
			quit(0)
		else:
			for f in failures:
				print("FAIL ", f)
			quit(1)
		return true
	return false
