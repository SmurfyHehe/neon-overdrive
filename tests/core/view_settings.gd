extends SceneTree

# ViewSettings (2026-10-06): the cockpit FOV defaults to 62, clamps to 55-78,
# saves into the shared settings file without touching other sections, and
# loads back. Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/core/view_settings.gd

var failures: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	AudioSettings.path = "user://view_settings_test.cfg"
	DirAccess.remove_absolute(AudioSettings.path)
	ViewSettings.load_settings()
	_check(is_equal_approx(ViewSettings.cockpit_fov, 62.0), "default should be 62, got %.1f" % ViewSettings.cockpit_fov)
	ViewSettings.set_cockpit_fov(10.0)
	_check(is_equal_approx(ViewSettings.cockpit_fov, 55.0), "should clamp up to 55")
	ViewSettings.set_cockpit_fov(200.0)
	_check(is_equal_approx(ViewSettings.cockpit_fov, 78.0), "should clamp down to 78")
	AudioSettings.set_volume("Music", 0.5)
	AudioSettings.save_settings()
	ViewSettings.set_cockpit_fov(70.0)
	_check(ViewSettings.save_settings(), "save failed")
	ViewSettings.set_cockpit_fov(62.0)
	ViewSettings.load_settings()
	_check(is_equal_approx(ViewSettings.cockpit_fov, 70.0), "70 should round-trip, got %.1f" % ViewSettings.cockpit_fov)
	_check(ViewSettings.camera_smoothing == 1, "smoothing default should be 1 (B)")
	ViewSettings.set_camera_smoothing(9)
	_check(ViewSettings.camera_smoothing == 2, "smoothing should clamp to 2")
	ViewSettings.set_camera_smoothing(0)
	ViewSettings.save_settings()
	ViewSettings.set_camera_smoothing(1)
	ViewSettings.load_settings()
	_check(ViewSettings.camera_smoothing == 0 and is_equal_approx(ViewSettings.cockpit_fov, 70.0), "smoothing 0 should round-trip beside the FOV")
	AudioSettings.volumes["Music"] = 1.0
	AudioSettings.load_settings()
	_check(is_equal_approx(AudioSettings.volumes["Music"], 0.5), "saving the view must keep the audio section")
	DirAccess.remove_absolute(AudioSettings.path)
	print("view_settings: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)
