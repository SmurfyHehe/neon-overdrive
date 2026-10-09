extends SceneTree

# Graphics tiers (2026-10-09, car look doc section 13), headless and silent.
# Checks
# - dynamic resolution: drops one step after 2 s over budget, stops at its
#   floor, climbs back only with predicted headroom, never above the preset
#   scale, ignores missing GPU numbers, and holds still when switched off or
#   while the first-launch pick is measuring
# - the first-launch pick: thresholds, and the fps estimate sees through
#   V-sync (a fast machine held at 60 still reads fast; a missed V-sync counts)
# - the settings sweep on the real Game.tscn: every preset from the pause
#   menu reaches the viewport, the running traffic (car count and sim
#   distance) and the mirror renders; every other option and both ends of the
#   resolution slider on the Graphics page apply; a traffic slider moved by
#   hand shows Custom; each preset survives save and load
# - the automatic pick end to end: it runs, applies, saves "auto", the menu
#   shows it, and a hand change clears it
# - nothing logs an error the whole time
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/graphics_tiers.gd

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
var step := 0
var wait := 0
var picker: GraphicsAutoPick

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func _initialize() -> void:
	OS.add_logger(logger)
	_dynres_checks()
	_auto_pick_checks()
	game = Harness.boot(self, 4, 150.0, 5)

# ---------- unit: dynamic resolution ----------
func _feed(d: DynamicResolution, gpu_ms: float, secs: float) -> void:
	var dt := 1.0 / 60.0
	for i in int(secs / dt):
		d.step(gpu_ms, dt)

func _dynres_checks() -> void:
	GraphicsSettings.set_dynamic_res(true)
	var d := DynamicResolution.new()
	var budget := 1000.0 / 60.0
	d.reset(1.0, budget)
	_feed(d, 20.0, 1.5)
	_check(is_equal_approx(d.scale, 1.0), "dynres waits 2 s before dropping (scale %.2f)" % d.scale)
	_feed(d, 20.0, 1.0)
	_check(is_equal_approx(d.scale, 0.9), "dynres drops one step after 2 s over budget (scale %.2f)" % d.scale)
	_feed(d, 30.0, 20.0)
	_check(is_equal_approx(d.scale, DynamicResolution.FLOOR), "dynres stops at its floor from full res (scale %.2f)" % d.scale)
	# 14 ms at 0.66 predicts 14*(0.76/0.66)^2 = 18.6 ms at 0.76: no room, stays.
	_feed(d, 14.0, 10.0)
	_check(is_equal_approx(d.scale, DynamicResolution.FLOOR), "dynres does not climb without predicted headroom (scale %.2f)" % d.scale)
	_feed(d, 5.0, 4.0)
	_check(is_equal_approx(d.scale, DynamicResolution.FLOOR), "dynres waits 5 s before climbing (scale %.2f)" % d.scale)
	_feed(d, 5.0, 30.0)
	_check(is_equal_approx(d.scale, 1.0), "dynres climbs back to the preset scale and no further (scale %.2f)" % d.scale)
	d.reset(0.75, budget)
	_feed(d, 40.0, 30.0)
	_check(is_equal_approx(d.scale, DynamicResolution.floor_for(0.75)) and d.scale < 0.66, "Low's floor is below 0.66 (scale %.2f)" % d.scale)
	_feed(d, 2.0, 60.0)
	_check(is_equal_approx(d.scale, 0.75), "dynres never climbs above Low's 0.75 (scale %.2f)" % d.scale)
	d.reset(1.0, budget)
	_feed(d, 0.0, 10.0)
	_check(is_equal_approx(d.scale, 1.0), "no GPU measurement (headless) leaves the scale alone")
	_feed(d, 5000.0, 10.0)
	_check(is_equal_approx(d.scale, 1.0), "a garbage GPU number is ignored")
	GraphicsSettings.set_dynamic_res(false)
	_feed(d, 40.0, 10.0)
	_check(is_equal_approx(d.scale, 1.0), "dynres switched off holds the scale")
	GraphicsSettings.set_dynamic_res(true)
	GraphicsAutoPick.running = true
	_feed(d, 40.0, 10.0)
	_check(is_equal_approx(d.scale, 1.0), "dynres holds still while the first-launch pick measures")
	GraphicsAutoPick.running = false
	_check(is_equal_approx(DynamicResolution.budget_for(30, 144.0), 1000.0 / 30.0), "a 30 fps cap sets a 33 ms budget")
	_check(is_equal_approx(DynamicResolution.budget_for(0, 144.0), 1000.0 / 60.0), "V-sync budget is capped at 60 fps")
	_check(is_equal_approx(DynamicResolution.budget_for(0, 0.0), 1000.0 / 60.0), "an unknown refresh rate reads as 60")
	d.free()

# ---------- unit: first-launch pick ----------
func _arr(v: float, n: int = 30) -> PackedFloat32Array:
	var a: PackedFloat32Array = []
	for i in n:
		a.append(v)
	return a

func _auto_pick_checks() -> void:
	_check(GraphicsAutoPick.pick_for(30.0) == "low", "30 fps picks Low")
	_check(GraphicsAutoPick.pick_for(49.9) == "low", "just under 50 fps picks Low")
	_check(GraphicsAutoPick.pick_for(60.0) == "medium", "60 fps picks Medium")
	_check(GraphicsAutoPick.pick_for(100.0) == "medium", "exactly 100 fps stays Medium")
	_check(GraphicsAutoPick.pick_for(140.0) == "high", "140 fps picks High")
	_check(GraphicsAutoPick.pick_for(GraphicsAutoPick.estimate_fps(_arr(7.0))) == "high", "7 ms uncapped frames pick High")
	_check(GraphicsAutoPick.pick_for(GraphicsAutoPick.estimate_fps(_arr(14.0))) == "medium", "14 ms uncapped frames pick Medium")
	_check(GraphicsAutoPick.pick_for(GraphicsAutoPick.estimate_fps(_arr(25.0))) == "low", "25 ms uncapped frames pick Low")
	var spiky := _arr(12.0, 90)
	spiky.append_array(_arr(80.0, 10))
	_check(GraphicsAutoPick.pick_for(GraphicsAutoPick.estimate_fps(spiky)) == "medium", "a few hitches do not drag the pick down (median)")
	_check(GraphicsAutoPick.estimate_fps(PackedFloat32Array()) > 0.0, "no samples does not divide by zero")

# ---------- the sweep on the real game ----------
func _mirror_sizes() -> Array:
	var out := []
	for n in game.find_children("*", "CockpitMirrors", true, false):
		for v in (n as CockpitMirrors).views:
			out.append(v.vp.size)
	return out

func _check_tier(p: String) -> void:
	var v: Dictionary = GraphicsSettings.PRESET_VALUES[p]
	var t: TrafficManager = game.traffic
	_check(GraphicsSettings.preset == p, "%s: preset reads %s (got %s)" % [p, p, GraphicsSettings.preset])
	_check(is_equal_approx(root.scaling_3d_scale, v.render_scale), "%s: render scale reaches the viewport (got %.2f)" % [p, root.scaling_3d_scale])
	_check(root.msaa_3d == (Viewport.MSAA_4X if v.aa == "msaa4" else Viewport.MSAA_2X), "%s: MSAA reaches the viewport" % p)
	_check(TrafficSettings.car_count == v.traffic and t.cars.size() == v.traffic, "%s: %d traffic cars running (got %d)" % [p, v.traffic, t.cars.size()])
	_check(is_equal_approx(t.detail_distance, v.detail), "%s: traffic sim distance %d m (got %d)" % [p, v.detail, t.detail_distance])
	_check(FxSettings.mirror_quality == v.mirror_q, "%s: mirror quality %d" % [p, v.mirror_q])
	var sizes := _mirror_sizes()
	if not sizes.is_empty():
		var want := CockpitMirrors._scaled(CockpitMirrors.REAR_SIZE)
		_check(sizes[0] == want, "%s: rear mirror renders at %s (got %s)" % [p, want, sizes[0]])

func _pick(i: int) -> void:
	menu.gfx_preset.select(i)
	menu.gfx_preset.item_selected.emit(i)

func _process(_delta: float) -> bool:
	frame += 1
	if wait > 0:
		wait -= 1
		return false
	match step:
		0:
			if frame < 20:
				return false
			for n in game.get_children():
				if n is PauseMenu:
					menu = n
			_check(menu != null, "the pause menu exists")
			_check(game.find_children("*", "DynamicResolution", true, false).size() == 1, "the game runs dynamic resolution")
			_check(game.find_children("*", "GraphicsAutoPick", true, false).is_empty(), "a headless run does not auto-pick")
			_check(not _mirror_sizes().is_empty(), "the cockpit mirrors exist (their size is checked per tier)")
			if menu == null:
				return _finish()
			menu.show_graphics()
			_pick(0)
			wait = 5
		1:
			_check_tier("low")
			_pick(2)
			wait = 5
		2:
			_check_tier("high")
			_pick(1)
			wait = 5
		3:
			_check_tier("medium")
			_check(not GraphicsSettings.auto_picked, "a menu pick is not marked automatic")
			# Every option on the page, each value, applies.
			for i in GraphicsSettings.AA_MODES.size():
				menu.gfx_aa.item_selected.emit(i)
				_check(GraphicsSettings.aa == GraphicsSettings.AA_MODES[i], "edge smoothing %s applies" % GraphicsSettings.AA_NAMES[i])
			menu.gfx_aa.item_selected.emit(GraphicsSettings.AA_MODES.find("msaa2"))
			for i in 3:
				menu.gfx_mirrors.item_selected.emit(i)
				_check(FxSettings.mirror_quality == i, "mirrors option %d applies" % i)
				var sizes := _mirror_sizes()
				if not sizes.is_empty():
					_check(sizes[0] == CockpitMirrors._scaled(CockpitMirrors.REAR_SIZE), "mirrors option %d resizes the render" % i)
			menu.gfx_mirrors.item_selected.emit(1)
			menu.gfx_dynres.item_selected.emit(1)
			_check(not GraphicsSettings.dynamic_res, "dynamic resolution off applies")
			menu.gfx_dynres.item_selected.emit(0)
			_check(GraphicsSettings.dynamic_res, "dynamic resolution on applies")
			menu.gfx_cap.item_selected.emit(1)
			_check(GraphicsSettings.fps_cap == 30 and Engine.max_fps == 30, "the 30 fps cap reaches the engine")
			menu.gfx_cap.item_selected.emit(0)
			_check(Engine.max_fps == 0, "V-sync only clears the cap")
			for v in [GraphicsSettings.SCALE_MIN, GraphicsSettings.SCALE_MAX]:
				menu.gfx_scale.value = v
				_check(is_equal_approx(root.scaling_3d_scale, v), "resolution slider at %.2f reaches the viewport" % v)
			_check(GraphicsSettings.preset == "medium", "back on Medium's values reads Medium (got %s)" % GraphicsSettings.preset)
			# A traffic slider moved by hand: Custom; a tier moves the main page's slider.
			menu.show_main()
			menu.traffic_cars_slider.value = 40
			_check(GraphicsSettings.preset == "custom", "a traffic slider moved by hand makes the preset Custom")
			menu.show_graphics()
			_check(menu.gfx_preset.selected == 3, "the Graphics page shows Custom")
			_pick(0)
			menu.show_main()
			_check(int(menu.traffic_cars_slider.value) == GraphicsSettings.PRESET_VALUES.low.traffic, "the main page's Cars slider follows the tier")
			# Save and load each preset.
			for p in GraphicsSettings.PRESETS:
				GraphicsSettings.set_preset(p)
				GraphicsSettings.save_settings()
				GraphicsSettings.set_preset("high" if p != "high" else "low")
				TrafficSettings.load_settings()
				FxSettings.load_settings()
				GraphicsSettings.load_settings()
				_check(GraphicsSettings.preset == p and not GraphicsSettings.needs_auto_pick(), "%s survives save and load (got %s)" % [p, GraphicsSettings.preset])
			GraphicsSettings.set_preset("medium")
			GraphicsSettings.apply(self)
			wait = 5
		4:
			_check_tier("medium")
			# The first-launch pick, end to end: no preset in the file.
			var cfg := ConfigFile.new()
			cfg.load(AudioSettings.path)
			cfg.erase_section("graphics")
			cfg.save(AudioSettings.path)
			GraphicsSettings.load_settings()
			_check(GraphicsSettings.needs_auto_pick(), "no preset in the file asks for an automatic pick")
			picker = GraphicsAutoPick.new()
			game.add_child(picker)
		5:
			if is_instance_valid(picker) and frame < 3000:
				return false
			_check(not is_instance_valid(picker), "the automatic pick finishes and frees itself")
			_check(not GraphicsAutoPick.running and Engine.max_fps == 0, "the pick restores the frame cap and lets dynamic resolution run")
			_check(GraphicsSettings.auto_picked and not GraphicsSettings.needs_auto_pick(), "the automatic pick is applied and marked auto")
			_check(GraphicsSettings.preset in GraphicsSettings.PRESETS, "the automatic pick is a tier (got %s)" % GraphicsSettings.preset)
			var cfg := ConfigFile.new()
			cfg.load(AudioSettings.path)
			_check(cfg.get_value("graphics", "auto", false) == true and cfg.get_value("graphics", "preset", "") == GraphicsSettings.preset, "the automatic pick is saved")
			wait = 5
		6:
			if GraphicsSettings.preset in GraphicsSettings.PRESETS:
				_check_tier(GraphicsSettings.preset)
			menu.show_graphics()
			_check(menu.gfx_auto_label.visible, "the Graphics page says the preset was picked automatically")
			menu.gfx_cap.item_selected.emit(0)
			_check(not GraphicsSettings.auto_picked and not menu.gfx_auto_label.visible, "a hand change clears the automatic mark")
			menu.show_main()
			return _finish()
	step += 1
	return false

func _finish() -> bool:
	for e in logger.errors:
		failures.append("logged error: " + e)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioSettings.path))
	Engine.max_fps = 0
	if failures.is_empty():
		print("PASS graphics_tiers")
		quit(0)
	else:
		for f in failures:
			print("FAIL ", f)
		quit(1)
	return true
