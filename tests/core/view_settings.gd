extends SceneTree

# ViewSettings (2026-10-06): the cockpit FOV defaults to 62, clamps to 55-78,
# saves into the shared settings file without touching other sections, and
# loads back. The View page rows (2026-10-13): chase distance Normal (Near
# 0.85x, Far 1.4x and +0.6 m), chase FOV 58 in 50-70, hood FOV 65 in 55-85,
# remember last view on, camera shake 1.0 in 0-1 and FOV widening on
# (AccessSettings, [access]); each clamps, saves, loads back, and Reset view
# brings every row back. Exit code 1 on failure. Run:
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
	_view_page_rows()
	DirAccess.remove_absolute(AudioSettings.path)
	print("view_settings: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)

func _view_page_rows() -> void:
	DirAccess.remove_absolute(AudioSettings.path)
	ViewSettings.load_settings()
	AccessSettings.load_settings()
	_check(ViewSettings.chase_distance == 1 and ViewSettings.CHASE_DISTANCES[1] == "Normal", "chase distance defaults to Normal")
	_check(is_equal_approx(ViewSettings.chase_dist_scale(), 1.0) and is_equal_approx(ViewSettings.chase_dist_lift(), 0.0), "Normal is the built framing")
	_check(is_equal_approx(ViewSettings.chase_fov, 58.0), "chase FOV defaults to 58, got %.1f" % ViewSettings.chase_fov)
	_check(is_equal_approx(ViewSettings.hood_fov, 65.0), "hood FOV defaults to 65 (1500), got %.1f" % ViewSettings.hood_fov)
	_check(ViewSettings.remember_view, "remember last view defaults on")
	_check(is_equal_approx(AccessSettings.shake_scale, 1.0) and AccessSettings.fov_widening, "shake 100% and widening on by default")
	ViewSettings.set_chase_distance(2)
	_check(is_equal_approx(ViewSettings.chase_dist_scale(), 1.4) and is_equal_approx(ViewSettings.chase_dist_lift(), 0.6), "Far is 1.4x and +0.6 m")
	ViewSettings.set_chase_distance(0)
	_check(is_equal_approx(ViewSettings.chase_dist_scale(), 0.85) and is_equal_approx(ViewSettings.chase_dist_lift(), 0.0), "Near is 0.85x")
	ViewSettings.set_chase_distance(7)
	_check(ViewSettings.chase_distance == 2, "chase distance clamps to Far")
	ViewSettings.set_chase_distance(-3)
	_check(ViewSettings.chase_distance == 0, "chase distance clamps to Near")
	ViewSettings.set_chase_fov(10.0)
	_check(is_equal_approx(ViewSettings.chase_fov, 50.0), "chase FOV clamps up to 50")
	ViewSettings.set_chase_fov(99.0)
	_check(is_equal_approx(ViewSettings.chase_fov, 70.0), "chase FOV clamps down to 70")
	ViewSettings.set_chase_fov(NAN)
	_check(is_equal_approx(ViewSettings.chase_fov, 58.0), "a NaN chase FOV is the default")
	ViewSettings.set_hood_fov(10.0)
	_check(is_equal_approx(ViewSettings.hood_fov, 55.0), "hood FOV clamps up to 55")
	ViewSettings.set_hood_fov(120.0)
	_check(is_equal_approx(ViewSettings.hood_fov, 85.0), "hood FOV clamps down to 85")
	_check(is_equal_approx(ViewSettings.pillar_see_through, 0.35), "pillars see-through defaults to 35%% (#738), got %.2f" % ViewSettings.pillar_see_through)
	ViewSettings.set_pillar_see_through(0.95)
	_check(is_equal_approx(ViewSettings.pillar_see_through, 0.7), "pillars see-through clamps to 70%%")
	ViewSettings.set_pillar_see_through(-1.0)
	_check(is_equal_approx(ViewSettings.pillar_see_through, 0.0), "pillars see-through clamps to 0")
	ViewSettings.set_pillar_see_through(NAN)
	_check(is_equal_approx(ViewSettings.pillar_see_through, 0.35), "NaN falls back to the default")
	ViewSettings.set_pillar_see_through(0.5)
	AccessSettings.set_shake_scale(3.0)
	_check(is_equal_approx(AccessSettings.shake_scale, 1.0), "shake clamps to 100%")
	AccessSettings.set_shake_scale(-1.0)
	_check(is_equal_approx(AccessSettings.shake_scale, 0.0), "shake clamps to 0")
	# round trip
	ViewSettings.set_chase_distance(2)
	ViewSettings.set_chase_fov(64.0)
	ViewSettings.set_hood_fov(72.0)
	ViewSettings.remember_view = false
	AccessSettings.set_shake_scale(0.35)
	AccessSettings.fov_widening = false
	_check(ViewSettings.save_settings() and AccessSettings.save_settings(), "save failed")
	ViewSettings.reset_view()
	_check(ViewSettings.chase_distance == 1 and is_equal_approx(ViewSettings.chase_fov, 58.0) and is_equal_approx(ViewSettings.hood_fov, 65.0) and is_equal_approx(ViewSettings.pillar_see_through, 0.35) and ViewSettings.remember_view, "Reset view restores the view rows")
	_check(is_equal_approx(AccessSettings.shake_scale, 1.0) and AccessSettings.fov_widening and FxSettings.is_on("head_motion"), "Reset view restores shake, widening and head motion")
	ViewSettings.load_settings()
	AccessSettings.load_settings()
	_check(ViewSettings.chase_distance == 2 and is_equal_approx(ViewSettings.chase_fov, 64.0) and is_equal_approx(ViewSettings.hood_fov, 72.0) and is_equal_approx(ViewSettings.pillar_see_through, 0.5), "chase distance, chase FOV, hood FOV and pillars see-through load back")
	_check(not ViewSettings.remember_view and not ViewSettings.remembers_view(), "remember last view off loads back and is obeyed")
	_check(is_equal_approx(AccessSettings.shake_scale, 0.35) and not AccessSettings.fov_widening, "shake and widening load back from [access]")
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	_check(cfg.has_section_key("access", "shake_scale") and cfg.has_section_key("view", "hood_fov"), "shake in [access], hood FOV in [view]")
	# a damaged value reads as the default
	cfg.set_value("view", "chase_fov", "banana")
	cfg.set_value("view", "chase_distance", "far away")
	cfg.save(AudioSettings.path)
	ViewSettings.load_settings()
	_check(ViewSettings.chase_fov >= 50.0 and ViewSettings.chase_fov <= 70.0 and ViewSettings.chase_distance >= 0 and ViewSettings.chase_distance <= 2, "damaged values stay in range")
	ViewSettings.reset_view()
