extends SceneTree

# DisplaySettings (menus A-list, 2026-10-08): fullscreen is the default (so the
# first launch opens fullscreen), the render scale clamps to 50-100%, an unknown
# resolution falls back to the default, saving keeps the other sections, and
# GameState pauses on focus loss only when asked to. Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/display_settings.gd

var failures: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	AudioSettings.path = "user://display_settings_test.cfg"
	DirAccess.remove_absolute(AudioSettings.path)
	DisplaySettings.load_settings()
	_check(DisplaySettings.fullscreen, "first launch (no file) should be fullscreen")
	_check(is_equal_approx(DisplaySettings.render_scale, 1.0), "default render scale should be 100%")
	_check(not DisplaySettings.player_run(), "a test must not count as a player run (window untouched)")
	DisplaySettings.set_render_scale(0.1)
	_check(is_equal_approx(DisplaySettings.render_scale, 0.5), "render scale should clamp up to 50%")
	DisplaySettings.set_render_scale(NAN)
	_check(is_equal_approx(DisplaySettings.render_scale, 1.0), "NaN render scale should fall back to 100%")
	DisplaySettings.set_resolution(Vector2i(123, 45))
	_check(DisplaySettings.resolution == DisplaySettings.RESOLUTION_DEFAULT, "unknown resolution should fall back")
	AudioSettings.set_volume("Music", 0.5)
	AudioSettings.save_settings()
	DisplaySettings.set_fullscreen(false)
	DisplaySettings.set_resolution(Vector2i(1600, 900))
	DisplaySettings.set_render_scale(0.7)
	_check(DisplaySettings.save_settings(), "save failed")
	DisplaySettings.reset_defaults()
	DisplaySettings.load_settings()
	_check(not DisplaySettings.fullscreen, "windowed should round-trip")
	_check(DisplaySettings.resolution == Vector2i(1600, 900), "1600x900 should round-trip, got %s" % DisplaySettings.resolution)
	_check(is_equal_approx(DisplaySettings.render_scale, 0.7), "70% should round-trip")
	AudioSettings.volumes["Music"] = 1.0
	AudioSettings.load_settings()
	_check(is_equal_approx(AudioSettings.volumes["Music"], 0.5), "saving display must keep the audio section")
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", "false")  # hand-edited as text
	cfg.save(AudioSettings.path)
	DisplaySettings.load_settings()
	_check(not DisplaySettings.fullscreen, "fullscreen stored as text should still load")
	DirAccess.remove_absolute(AudioSettings.path)
	# Render scale reaches the window even in a test (only the mode/size are skipped).
	DisplaySettings.set_render_scale(0.6)
	DisplaySettings.apply(root)
	_check(is_equal_approx(root.scaling_3d_scale, 0.6), "apply should set the 3D render scale")
	DisplaySettings.reset_defaults()
	DisplaySettings.apply(root)

## The tree is only live once the main loop runs, so GameState is tested here.
var _done := false
func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	# Focus loss pauses only when the flag is on.
	var gs := GameState.new()
	root.add_child(gs)
	gs.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(gs.state == GameState.State.PLAYING, "focus loss must not pause when the flag is off")
	gs.pause_on_focus_loss = true
	gs.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(gs.state == GameState.State.PAUSED and paused, "focus loss should pause a play session")
	gs.resume()
	print("display_settings: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)
	return false
