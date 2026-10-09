extends SceneTree

# Dash trinket (2026-10-09): the charm on the rear-view mirror. Headless, no
# scene needed for the physics and the catalogue:
# - every id builds (non-zero triangles), "none" builds nothing, an unknown id
#   falls back to none, and the designs are small (under MAX_TRIS)
# - cornering swings it outward, braking throws it forward, launching pins it
#   back, and it settles upright again once the car is steady
# - the swing is capped (a wall hit does not spin it)
# - ViewSettings saves and reloads the pick; an unknown saved id reads as default
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/dash_trinket.gd

const CFG := "user://dash_trinket_test.cfg"
const MAX_TRIS := 200
const DT := 1.0 / 120.0
const G := Vector3(0.0, -9.81, 0.0)

var failures: Array[String] = []

func _initialize() -> void:
	AudioSettings.path = CFG
	DirAccess.remove_absolute(CFG)
	var t := DashTrinket.new(null)
	root.add_child(t)
	_designs(t)
	_motion(t)
	_settings()
	DirAccess.remove_absolute(CFG)
	print("dash_trinket: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _designs(t: DashTrinket) -> void:
	_check(DashTrinket.IDS[0] == DashTrinket.NONE, "index 0 should be none")
	_check(DashTrinket.IDS.size() >= 5, "want at least 4 designs plus none, got %d ids" % DashTrinket.IDS.size())
	for id in DashTrinket.IDS:
		_check(DashTrinket.NAMES.has(id), "%s has no display name" % id)
		t.set_design(id)
		if id == DashTrinket.NONE:
			_check(not t.is_shown() and t.triangle_count() == 0, "none should draw nothing")
		else:
			_check(t.is_shown() and t.triangle_count() > 12, "%s should build a mesh, got %d tris" % [id, t.triangle_count()])
			_check(t.triangle_count() <= MAX_TRIS, "%s is %d tris, over the %d budget" % [id, t.triangle_count(), MAX_TRIS])
			var mi := t.find_child("Charm", true, false) as MeshInstance3D
			var box := mi.get_aabb() if mi != null else AABB()
			_check(box.size.y < 0.16 and box.size.x < 0.08 and box.size.z < 0.08, "%s is too big for a dash charm: %s" % [id, box.size])
	t.set_design("no-such-charm")
	_check(t.design == DashTrinket.NONE, "unknown id should fall back to none, got %s" % t.design)

func _run(t: DashTrinket, accel: Vector3, secs: float) -> void:
	for i in int(secs / DT):
		t.step(DT, accel, G)

func _motion(t: DashTrinket) -> void:
	t.set_design("dice")
	_run(t, Vector3.ZERO, 3.0)
	_check(absf(t.phi) < 0.01 and absf(t.psi) < 0.01, "steady car: should hang straight, got phi %.3f psi %.3f" % [t.phi, t.psi])
	# right-hand corner: the car accelerates toward +x (centripetal), the charm swings to -x
	var peak := 0.0
	for i in int(1.0 / DT):
		t.step(DT, Vector3(6.0, 0, 0), G)
		peak = minf(peak, t.phi)
	_check(peak < -0.3, "a 6 m/s^2 right corner should swing it to -x (left, outward), peak phi %.3f" % peak)
	_run(t, Vector3.ZERO, 4.0)
	_check(absf(t.phi) < 0.02, "should settle upright after the corner, phi %.3f" % t.phi)
	# braking: car accelerates toward +z (backwards), the charm swings forward (-z): psi < 0
	var fore := 0.0
	for i in int(0.6 / DT):
		t.step(DT, Vector3(0, 0, 8.0), G)
		fore = minf(fore, t.psi)
	_check(fore < -0.3, "hard braking should throw it forward (psi < 0), peak psi %.3f" % fore)
	_run(t, Vector3.ZERO, 4.0)
	# launch: car accelerates toward -z, the charm swings back (+z): psi > 0
	var back := 0.0
	for i in int(0.6 / DT):
		t.step(DT, Vector3(0, 0, -8.0), G)
		back = maxf(back, t.psi)
	_check(back > 0.3, "a launch should pin it back (psi > 0), peak psi %.3f" % back)
	# the cap
	_run(t, Vector3(60.0, 0, 0), 2.0)
	_check(absf(t.phi) <= DashTrinket.SWING_MAX + 1e-6, "swing should be capped at %.2f rad, got %.3f" % [DashTrinket.SWING_MAX, t.phi])
	# the pose follows: rotation z = phi, rotation x = -psi
	var pivot := t.get_node("Pivot") as Node3D
	_check(is_equal_approx(pivot.rotation.z, t.phi) and is_equal_approx(pivot.rotation.x, -t.psi), "pivot should show phi/psi")

func _settings() -> void:
	ViewSettings.set_dash_trinket("medal")
	_check(ViewSettings.save_settings(), "save_settings failed")
	ViewSettings.set_dash_trinket("tree")
	ViewSettings.load_settings()
	_check(ViewSettings.dash_trinket == "medal", "saved pick should reload, got %s" % ViewSettings.dash_trinket)
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("view", "dash_trinket", "not-a-charm")
	cfg.save(CFG)
	ViewSettings.load_settings()
	_check(ViewSettings.dash_trinket == ViewSettings.DASH_TRINKET_DEFAULT, "unknown saved id should read as the default, got %s" % ViewSettings.dash_trinket)
