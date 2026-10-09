extends SceneTree

# Dirt and the wash, no scene (2026-10-09):
# - CarDirt: grime grows with metres driven, four times as fast off-road, clamps
#   at 1, ignores NaN and negative distances, and the "dirt" setting off draws 0
#   while keeping the level
# - it saves and loads its level through its own file; a damaged value loads as 0
# - FxSettings has the "dirt" flag, on by default, round-trips through the file
# - WashScreen.Model: a car-shaped mask, a still sponge cleans nothing, a moving
#   one takes grime off under it, progress goes 0 -> 1, and sweeping the whole car
#   ends with done = true and almost nothing left
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/car_dirt.gd

var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	if not CarDirt.path.get_file().begins_with("test_"):
		printerr("FAIL: not in test mode (dirt path %s). Nothing written." % CarDirt.path)
		quit(1)
		return
	CarDirt.path = CarDirt.path.get_base_dir().path_join("test_car_dirt_unit.cfg")
	var f := FileAccess.open(CarDirt.path, FileAccess.WRITE)  # start empty
	f.store_string("")
	f = null

	# --- build-up ---
	var d := CarDirt.new(null)
	_check(d.level == 0.0, "starts dirty: %s" % d.level)
	d.add_distance(CarDirt.FULL_NIGHT_METRES / 2.0, false)
	_check(is_equal_approx(d.level, 0.5), "half a night should be 0.5: %s" % d.level)
	d.set_level(0.0)
	d.add_distance(1000.0, true)
	_check(is_equal_approx(d.level, 4000.0 / CarDirt.FULL_NIGHT_METRES), "off-road should count x4: %s" % d.level)
	d.add_distance(1e9, false)
	_check(d.level == 1.0, "should clamp at 1: %s" % d.level)
	d.add_distance(NAN, false)
	d.add_distance(-5.0, false)
	_check(d.level == 1.0, "NaN or negative metres changed the level: %s" % d.level)
	d.set_level(INF)
	_check(d.level == 0.0, "an infinite level should read 0: %s" % d.level)
	d.set_level(0.4)
	d.enabled = false
	_check(d.shown_level() == 0.0 and d.level == 0.4, "off should draw 0 and keep the level: %s / %s" % [d.shown_level(), d.level])
	d.enabled = true
	_check(d.shown_level() == 0.4, "on again should draw the kept level: %s" % d.shown_level())

	# --- save / load ---
	d.set_level(0.37)
	_check(d.save_state(), "save failed")
	var e := CarDirt.new(null)
	e.load_state()
	_check(is_equal_approx(e.level, 0.37), "load should give 0.37: %s" % e.level)
	f = FileAccess.open(CarDirt.path, FileAccess.WRITE)
	f.store_string("[dirt]\nlevel=\"lots\"\n")
	f = null
	e.load_state()
	_check(e.level == 0.0, "a damaged level should load as 0: %s" % e.level)
	f = FileAccess.open(CarDirt.path, FileAccess.WRITE)
	f.store_string("[dirt]\nlevel=nan\n")
	f = null
	e.load_state()
	_check(e.level == 0.0, "nan should load as 0: %s" % e.level)

	# --- setting ---
	_check("dirt" in FxSettings.EFFECTS, "FxSettings has no dirt flag")
	var real_path := AudioSettings.path
	AudioSettings.path = real_path.get_base_dir().path_join("test_car_dirt_settings.cfg")
	f = FileAccess.open(AudioSettings.path, FileAccess.WRITE)
	f.store_string("")
	f = null
	FxSettings.load_settings()
	_check(FxSettings.is_on("dirt"), "dirt should default to on")
	FxSettings.set_on("dirt", false)
	FxSettings.save_settings()
	FxSettings.set_on("dirt", true)
	FxSettings.load_settings()
	_check(not FxSettings.is_on("dirt"), "dirt off did not survive save/load")
	FxSettings.set_on("dirt", true)
	FxSettings.save_settings()
	AudioSettings.path = real_path

	# --- wash model ---
	var m := WashScreen.Model.new(0.8, 3)
	var car_cells := 0
	for i in m.mask.size():
		if m.mask[i] == 1:
			car_cells += 1
	_check(car_cells > 400 and car_cells < m.mask.size(), "mask should be a car, not the whole grid: %d of %d" % [car_cells, m.mask.size()])
	_check(not m.done and m.start > 0.5 and m.start <= 0.8, "start grime off: %s" % m.start)
	_check(m.progress() == 0.0, "progress should start at 0: %s" % m.progress())
	var before := m.remaining()
	m.move(Vector2.ZERO, 1.0)
	_check(is_equal_approx(m.remaining(), before), "a still sponge should clean nothing")
	m.move(Vector2.RIGHT, 0.2)
	_check(m.remaining() < before, "a moving sponge should take grime off")
	_check(m.progress() > 0.0 and m.progress() < 0.5, "a short stroke should not finish the wash: %s" % m.progress())
	var zero := WashScreen.Model.new(0.0)
	_check(zero.done and zero.progress() == 1.0, "a clean car should be done at once")
	# Sweep every row with the sponge, like a player would.
	_sweep(m)
	_check(m.done, "sweeping the whole car should finish it (left %s)" % m.remaining())
	_check(m.remaining() <= WashScreen.Model.DONE_AT, "too much left after a full sweep: %s" % m.remaining())
	_check(m.progress() > 0.95, "progress after a full sweep: %s" % m.progress())

	d.free()
	e.free()
	for p in [CarDirt.path, real_path.get_base_dir().path_join("test_car_dirt_settings.cfg")]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_end()

## Serpentine over the grid in SPONGE_R-wide rows, twice.
static func _sweep(m: WashScreen.Model) -> void:
	var dt := 0.05
	for pass_n in 2:
		var row := 0.0
		var right := true
		while row <= WashScreen.Model.ROWS and not m.done:
			m.sponge = Vector2(0.0 if right else WashScreen.Model.COLS, row)
			var dir := Vector2.RIGHT if right else Vector2.LEFT
			for i in 200:
				m.move(dir, dt)
				if m.done:
					break
			row += WashScreen.Model.SPONGE_R
			right = not right

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end() -> void:
	for f in failures:
		printerr("FAIL: ", f)
	print("car_dirt: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
