extends SceneTree

# Interior mods batch 1 (2026-10-09), headless, no scene:
# - CabinSpots has a strut bar for every player car, inside that car's body
#   (half width from the sheet, under its height, ahead of the cabin), and the
#   cabin spots a part needs
# - every shift knob builds (small, non-zero), an unknown id is stock, the
#   short shifter's stick is shorter than stock
# - the strut bar mesh builds for every player car, small, spanning the towers
# - CabinMods saves and reloads every pick, an unknown id reads as the default,
#   NEON_CABIN_MODS-style overrides parse
# - apply_sim holds the shift time and the front bar at spec + mods, however
#   often it runs (the tuner writes the spec's values back to the car)
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/view/cabin_mods.gd

const CFG := "user://cabin_mods_test.cfg"
const MAX_KNOB_TRIS := 260
const MAX_BAR_TRIS := 400

var failures: Array[String] = []

func _initialize() -> void:
	AudioSettings.path = CFG
	DirAccess.remove_absolute(CFG)
	_spots()
	_knobs()
	_bars()
	_settings()
	_sim()
	DirAccess.remove_absolute(CFG)
	print("cabin_mods: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

static func _tris(m: ArrayMesh) -> int:
	if m.get_surface_count() == 0:
		return 0
	return (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3

static func _aabb(m: ArrayMesh) -> AABB:
	var verts: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	return box

func _spots() -> void:
	for kind in PlayerCars.ids():
		_check(CabinSpots.has_car(kind), "%s has no CabinSpots entry" % kind)
		var ends := CabinSpots.strut_bar(kind)
		var l := ends[0]
		var r := ends[1]
		_check(l.x < 0.0 and r.x > 0.0 and is_equal_approx(-l.x, r.x), "%s strut bar should be symmetric about x, got %s %s" % [kind, l, r])
		var half_w: float = P1CoupeBuilder.WIDTH / 2.0 if kind == P1CoupeBuilder.KIND else float(NpcCarBuilder.config(kind).main_w) / 2.0
		_check(r.x < half_w - 0.1, "%s strut bar end x %.2f should be inside the body (half width %.2f)" % [kind, r.x, half_w])
		var height: float = P1CoupeBuilder.HEIGHT + P1CoupeBuilder.BODY_LIFT if kind == P1CoupeBuilder.KIND else float(NpcCarBuilder.KINDS[kind].height) - float(NpcCarBuilder.KINDS[kind].rest_y)
		_check(r.y > 0.4 and r.y < height, "%s strut bar y %.2f should be under the roof (%.2f) and above the floor" % [kind, r.y, height])
		_check(r.z < -0.8, "%s strut bar z %.2f should be ahead of the cabin" % [kind, r.z])
	for spot in ["mirror_hang", "shifter", "handbrake", "dash_pod", "vent_left", "vent_right"]:
		_check(CabinSpots.cabin("p1_coupe", spot) != Vector3.ZERO, "the coupe cabin should have a %s spot" % spot)
	_check(CabinSpots.cabin("p1_coupe", "shifter").is_equal_approx(Vector3(0.0, 0.615, -0.02)), "the shifter spot should be where CockpitFrame puts the lever")
	_check(CabinSpots.cabin("no-such-car", "mirror_hang") == CabinSpots.CABIN["mirror_hang"], "an unknown car gets the shared cabin spots")

func _knobs() -> void:
	_check(CabinMods.KNOB_IDS[0] == CabinMods.KNOB_STOCK, "index 0 should be stock")
	_check(CabinMods.KNOB_IDS.size() >= 4, "want stock plus at least 3 knobs, got %d" % CabinMods.KNOB_IDS.size())
	for id in CabinMods.KNOB_IDS:
		_check(CabinMods.KNOB_NAMES.has(id), "%s has no display name" % id)
		var m := ShifterMods.knob_mesh(id, null)
		var n := _tris(m)
		_check(n > 10 and n <= MAX_KNOB_TRIS, "%s knob: %d tris, want 10..%d" % [id, n, MAX_KNOB_TRIS])
		var box := _aabb(m)
		_check(box.size.x < 0.08 and box.size.z < 0.08 and box.size.y < 0.09, "%s knob is too big for a hand: %s" % [id, box.size])
	var stock := _aabb(ShifterMods.knob_mesh("no-such-knob", null))
	_check(stock.is_equal_approx(_aabb(ShifterMods.knob_mesh(CabinMods.KNOB_STOCK, null))), "an unknown knob id should build stock")
	var long := ShifterMods.shaft_mesh(CockpitFrame.LEVER_LEN, null)
	var short := ShifterMods.shaft_mesh(CockpitFrame.LEVER_LEN * CabinMods.SHORT_LEVER_SCALE, null)
	_check(_aabb(short).size.y < _aabb(long).size.y * 0.8, "the short shifter's stick should be clearly shorter")

func _bars() -> void:
	for kind in PlayerCars.ids():
		var m := StrutBar.mesh(kind)
		var n := _tris(m)
		_check(n > 20 and n <= MAX_BAR_TRIS, "%s strut bar: %d tris, want 20..%d" % [kind, n, MAX_BAR_TRIS])
		var box := _aabb(m)
		var ends := CabinSpots.strut_bar(kind)
		_check(box.position.x < ends[0].x + 0.01 and box.end.x > ends[1].x - 0.01, "%s strut bar should span the towers" % kind)
		_check(box.size.y < 0.08 and box.size.z < 0.2, "%s strut bar is too tall or deep: %s" % [kind, box.size])
		var mi := StrutBar.instance(kind)
		_check(mi.name == StrutBar.NODE and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the bar node should be named and cast no shadow")
		mi.free()

func _settings() -> void:
	CabinMods.set_trinket("wrench")
	CabinMods.set_shift_knob("weighted")
	CabinMods.set_short_shifter(true)
	CabinMods.set_strut_bar(true)
	var v := CabinMods.version
	_check(CabinMods.save_settings(), "save_settings failed")
	CabinMods.set_trinket("none")
	CabinMods.set_shift_knob("stock")
	CabinMods.set_short_shifter(false)
	CabinMods.set_strut_bar(false)
	_check(CabinMods.version > v, "a change should bump the version")
	CabinMods.load_settings()
	_check(CabinMods.trinket == "wrench" and CabinMods.shift_knob == "weighted" and CabinMods.short_shifter and CabinMods.strut_bar,
		"saved picks should reload, got %s %s %s %s" % [CabinMods.trinket, CabinMods.shift_knob, CabinMods.short_shifter, CabinMods.strut_bar])
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value(CabinMods.SECTION, "shift_knob", "not-a-knob")
	cfg.save(CFG)
	CabinMods.load_settings()
	_check(CabinMods.shift_knob == CabinMods.KNOB_STOCK, "unknown saved knob should read as stock, got %s" % CabinMods.shift_knob)
	# the other sections stay
	cfg.set_value("audio", "probe", 7)
	cfg.save(CFG)
	CabinMods.save_settings()
	cfg = ConfigFile.new()
	cfg.load(CFG)
	_check(int(cfg.get_value("audio", "probe", 0)) == 7, "save_settings should keep the other sections")
	CabinMods.apply_override("knob=ball; short=0;strut=1;trinket=tree;junk")
	_check(CabinMods.shift_knob == "ball" and not CabinMods.short_shifter and CabinMods.strut_bar and CabinMods.trinket == "tree", "the override string should set every field it names")
	CabinMods.apply_override("")
	_check(CabinMods.shift_knob == "ball", "an empty override changes nothing")

func _sim() -> void:
	# a bare Vehicle (no wheels): shift_time is read live; the bar only re-runs
	# the suspension on a ready car, so here only the values are checked (the
	# built car is checked in tests/view/cockpit_interior.gd)
	var v := Vehicle.new()
	var spec := {"shift_time": 0.2, "front_arb_ratio": 0.3}
	v.shift_time = 0.2
	v.front_arb_ratio = 0.3
	CabinMods.set_short_shifter(true)
	CabinMods.set_strut_bar(true)
	CabinMods.apply_sim(v, spec)
	_check(is_equal_approx(v.shift_time, 0.2 * CabinMods.SHORT_SHIFT_TIME), "short shifter should scale shift_time, got %.3f" % v.shift_time)
	_check(is_equal_approx(v.front_arb_ratio, 0.3 + CabinMods.STRUT_BAR_ARB), "strut bar should bump the front bar, got %.3f" % v.front_arb_ratio)
	CabinMods.apply_sim(v, spec)
	_check(is_equal_approx(v.shift_time, 0.2 * CabinMods.SHORT_SHIFT_TIME) and is_equal_approx(v.front_arb_ratio, 0.3 + CabinMods.STRUT_BAR_ARB), "a second apply should not stack")
	# a Tuner write puts the spec's value on the car; the next apply adds the bonus back
	v.front_arb_ratio = 0.3
	CabinMods.apply_sim(v, spec)
	_check(is_equal_approx(v.front_arb_ratio, 0.3 + CabinMods.STRUT_BAR_ARB), "the bonus should come back after a tuner write, got %.3f" % v.front_arb_ratio)
	spec.front_arb_ratio = 0.4
	CabinMods.apply_sim(v, spec)
	_check(is_equal_approx(v.front_arb_ratio, 0.4 + CabinMods.STRUT_BAR_ARB), "a tuned spec is the base, got %.3f" % v.front_arb_ratio)
	CabinMods.set_short_shifter(false)
	CabinMods.set_strut_bar(false)
	CabinMods.apply_sim(v, spec)
	_check(is_equal_approx(v.shift_time, 0.2) and is_equal_approx(v.front_arb_ratio, 0.4), "turning them off should restore the spec values, got %.3f %.3f" % [v.shift_time, v.front_arb_ratio])
	_check(spec.shift_time == 0.2, "the spec itself is never written")
	v.free()
