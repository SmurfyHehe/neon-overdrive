extends SceneTree

# Night clock test (living world step 1, 2026-10-08), headless and silent:
# - the pure helpers: 12-hour car-clock text, the hour, "HH:MM" parsing
# - a sweep of the whole night (every 10 game minutes) through WindowLights:
#   the share of lit windows follows the curve, thins out to 4:30 a.m., comes
#   back a little before 6, windows never flicker, and the texture is only
#   uploaded when a window changes
# - save and load: a round trip, a missing file, a damaged file, a NaN
# - the real game, started at 23:58 (NEON_CLOCK) with the clock sped up:
#   the clock runs, the HUD and the head unit show it, midnight strikes and
#   Dave reads it out on his station (not on a music station), the windows
#   change, pausing stops the clock, 6 a.m. rolls into the next night with
#   Dave's sign-off, and the clock is saved on the way out.
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/night_clock.gd

const TIMEOUT_TICKS := 1800
const TALK := 2   # The Dave Show

enum Step { BOOT, RUN, MIDNIGHT, MUSIC_HOUR, PAUSE, DAWN, DONE, EXIT }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var game: Node
var clock: NightClock
var hours: Array[int] = []
var minutes_at := 0.0
var uploads_at := 0
var nights_ended := 0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	_helper_tests()
	_sweep_tests()
	_save_tests()
	NightClock.path = "user://test_night_clock_game.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NightClock.path))
	OS.set_environment("NEON_CLOCK", "23:58")
	change_scene_to_file("res://Game.tscn")

func _helper_tests() -> void:
	_eq(NightClock.clock_text(0.0), "8:00 PM")
	_eq(NightClock.clock_text(239.9), "11:59 PM")
	_eq(NightClock.clock_text(240.0), "12:00 AM")
	_eq(NightClock.clock_text(305.0), "1:05 AM")
	_eq(NightClock.clock_text(599.9), "5:59 AM")
	_check(NightClock.hour24(0.0) == 20 and NightClock.hour24(240.0) == 0 and NightClock.hour24(599.0) == 5, "hour24")
	_check(NightClock.parse_time("20:00") == 0.0, "parse 20:00")
	_check(NightClock.parse_time("00:30") == 270.0, "parse 00:30")
	_check(NightClock.parse_time("05:59") == 599.0, "parse 05:59")
	for bad in ["06:00", "12:00", "19:59", "25:00", "x", "1:2:3", ""]:
		_check(NightClock.parse_time(bad) < 0.0, "'%s' is not night time" % bad)
	for h in [21, 22, 23, 0, 1, 2, 3, 4, 5, 6]:
		_check(RadioStations.time_line(h).begins_with("Dave:"), "Dave has a line for %d:00" % h)

func _sweep_tests() -> void:
	var n := WindowLights.slot_count()
	_check(n >= 40, "the window grid should have its slots (%d)" % n)
	var prev_lit: Array[bool] = []
	var flips := []
	flips.resize(n)
	flips.fill(0)
	var fractions := {}
	var uploads_before := WindowLights.uploads
	var changes := 0
	var m := 0.0
	while m <= NightClock.NIGHT_MINUTES:
		var before := WindowLights.uploads
		var mask_before: Array[bool] = []
		for i in n:
			mask_before.append(WindowLights.is_lit(i))
		WindowLights.set_minutes(m)
		var changed := false
		for i in n:
			if WindowLights.is_lit(i) != mask_before[i]:
				changed = true
				if m > 0.0:   # the first step only moves off the texture's midnight start
					flips[i] += 1
		if changed:
			changes += 1
		_check((WindowLights.uploads > before) == changed, "upload only when a window changed (%.0f min)" % m)
		var f := WindowLights.lit_fraction()
		var want := WindowLights.lit_fraction_target(m)
		_check(absf(f - want) < 0.17, "at %s %.2f of windows lit, curve says %.2f" % [NightClock.clock_text(minf(m, 599.9)), f, want])
		fractions[int(m)] = f
		m += 10.0
	_check(changes > 10, "windows should switch through the night (%d changes)" % changes)
	_check(WindowLights.uploads - uploads_before == changes, "one upload per change")
	_check(fractions[0] > fractions[240] and fractions[240] > fractions[480], "fewer windows lit as the night goes on (8 p.m. %.2f, midnight %.2f, 4 a.m. %.2f)" % [fractions[0], fractions[240], fractions[480]])
	_check(fractions[0] >= 0.4, "8 p.m. is busy (%.2f)" % fractions[0])
	_check(fractions[480] <= 0.2, "4 a.m. is mostly dark (%.2f)" % fractions[480])
	_check(fractions[600] > fractions[510], "early risers are on before 6 (%.2f vs %.2f at 4:30)" % [fractions[600], fractions[510]])
	# A window goes dark at bedtime and maybe on again with the early risers:
	# at most two switches a night, never back and forth.
	var most := 0
	for i in n:
		most = maxi(most, flips[i])
	_check(most <= 2, "a window switched %d times in one night" % most)
	WindowLights.set_minutes(240.0)

func _save_tests() -> void:
	NightClock.path = "user://test_night_clock_unit.cfg"
	var abs := ProjectSettings.globalize_path(NightClock.path)
	DirAccess.remove_absolute(abs)
	var c := NightClock.new()
	c.load_clock()
	_check(c.minutes == 0.0 and c.night == 1, "no file: night 1 at 8 p.m.")
	c.minutes = 333.5
	c.night = 4
	_check(c.save_clock(), "save")
	var d := NightClock.new()
	d.load_clock()
	_check(absf(d.minutes - 333.5) < 0.001 and d.night == 4, "round trip (%.1f, night %d)" % [d.minutes, d.night])
	var f := FileAccess.open(NightClock.path, FileAccess.WRITE)
	f.store_string("[clock\nminutes=banana")
	f.close()
	var e := NightClock.new()
	e.load_clock()
	_check(e.minutes == 0.0 and e.night == 1, "damaged file: defaults")
	f = FileAccess.open(NightClock.path, FileAccess.WRITE)
	f.store_string("[clock]\nminutes=nan\nnight=-3\n")
	f.close()
	var g := NightClock.new()
	g.load_clock()
	_check(g.minutes == 0.0 and g.night == 1, "NaN minutes / negative night: defaults (%.1f, %d)" % [g.minutes, g.night])
	f = FileAccess.open(NightClock.path, FileAccess.WRITE)
	f.store_string("[clock]\nminutes=9999.0\nnight=2\n")
	f.close()
	var h := NightClock.new()
	h.load_clock()
	_check(h.minutes < NightClock.NIGHT_MINUTES and h.night == 2, "minutes past 6 a.m. are clamped (%.1f)" % h.minutes)
	for x in [c, d, e, g, h]:
		x.free()
	DirAccess.remove_absolute(abs)

func _physics_process(_delta: float) -> bool:
	tick += 1
	if step == Step.EXIT:
		return false
	game = current_scene
	if game == null or game.get("night_clock") == null or game.get("radio") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	clock = game.night_clock
	var waited := tick - step_start
	match step:
		Step.BOOT:
			_check(absf(clock.minutes - 238.0) < 0.5, "NEON_CLOCK=23:58 should start at 11:58 PM (%s)" % clock.text())
			clock.hour_changed.connect(func(h: int) -> void: hours.append(h))
			clock.night_ended.connect(func(_n: int) -> void: nights_ended += 1)
			game.radio.station = TALK
			minutes_at = clock.minutes
			uploads_at = WindowLights.uploads
			_go(Step.RUN)
		Step.RUN:
			if waited == 30:
				_check(clock.minutes > minutes_at, "the clock should run while driving")
				var hud: Hud = _find_hud()
				_check(hud != null and hud.lbl_clock.text == clock.text(), "the HUD shows the clock (%s)" % (hud.lbl_clock.text if hud else "no HUD"))
				var frame = _find_frame()
				_check(frame != null and frame.head_unit.clock_text == clock.text(), "the head unit shows the clock (%s)" % (frame.head_unit.clock_text if frame else "no cockpit"))
				clock.speed = 120.0   # one game minute per tick at 60 Hz
				_go(Step.MIDNIGHT)
		Step.MIDNIGHT:
			if hours.has(0) and waited >= 2:
				_check(game.radio.dj_active and game.radio.dj_text == RadioStations.time_line(0), "Dave reads midnight out (%s)" % game.radio.dj_text)
				_check(WindowLights.uploads > uploads_at, "windows changed as the time moved")
				game.radio.station = 0   # a music station: no time check
				_go(Step.MUSIC_HOUR)
			elif waited > 600:
				return _end("midnight never struck (%s)" % clock.text())
		Step.MUSIC_HOUR:
			if hours.has(1) and waited >= 2:
				_check(not game.radio.dj_text.begins_with("Dave: One"), "no time check on a music station")
				game.game_state.pause()
				minutes_at = clock.minutes
				_go(Step.PAUSE)
			elif waited > 600:
				return _end("1 a.m. never struck (%s)" % clock.text())
		Step.PAUSE:
			if waited == 30:
				_check(clock.minutes == minutes_at, "the clock stops while paused (%.2f -> %.2f)" % [minutes_at, clock.minutes])
				game.game_state.resume()
				game.radio.station = TALK
				clock.speed = 600.0
				_go(Step.DAWN)
		Step.DAWN:
			if nights_ended == 1 and waited >= 2:
				_check(clock.night == 2, "6 a.m. starts night 2 (%d)" % clock.night)
				_check(clock.minutes < 60.0, "and the clock is back at 8 p.m. (%s)" % clock.text())
				_check(game.radio.dj_text == RadioStations.time_line(6), "Dave signs off at 6 (%s)" % game.radio.dj_text)
				var saved := NightClock.new()
				saved.load_clock()
				_check(saved.night == 2, "the new night was saved (%d)" % saved.night)
				saved.free()
				_go(Step.DONE)
			elif waited > 1200:
				return _end("6 a.m. never came (%s)" % clock.text())
		Step.DONE:
			# Saved on the way out: free the game and read the file back.
			clock.speed = 0.0
			minutes_at = clock.minutes
			step = Step.EXIT
			game.queue_free()
			_check_exit_save.call_deferred()
		Step.EXIT:
			pass
	return false

func _check_exit_save() -> void:
	await process_frame
	var saved := NightClock.new()
	saved.load_clock()
	_check(absf(saved.minutes - minutes_at) < 0.01, "the clock is saved on exit (%.1f vs %.1f)" % [saved.minutes, minutes_at])
	saved.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NightClock.path))
	_end("")

func _find_hud() -> Hud:
	for c in game.get_children():
		if c is Hud:
			return c
	return null

func _find_frame() -> Node:
	for n in game.find_children("*", "Node3D", true, false):
		if n is CockpitFrame:
			return n
	return null

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _eq(got: String, want: String) -> void:
	_check(got == want, "expected '%s', got '%s'" % [want, got])

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

var _ended := false
func _end(msg: String) -> bool:
	if _ended:
		return true
	_ended = true
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("night_clock: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
