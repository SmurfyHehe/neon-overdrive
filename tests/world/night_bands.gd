extends SceneTree

# Hour bands test (living world step 2, 2026-10-08), headless and silent:
# - the pure helpers: which band each time is in, the traffic curve (full at
#   dusk, never above the slider, lowest at 3:30 a.m., no jumps), Dave's band
#   lines joining his rotation on the talk station only
# - the real game started at 3:30 a.m. (NEON_CLOCK): the Traffic slider's cars
#   thin out to the dead-hours share, every car leaves the road out of the
#   player's sight, Dave's rotation carries a dead-hours line; then the clock
#   is set back to 8 p.m. and the cars come back
#
# Setting sweep: run it with NEON_TRAFFIC=0 / 4 / 16 / 80 and
# NEON_DETAIL=50 / 150 / 300 (draw distance); defaults 16 and 150.
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . -s res://tests/world/night_bands.gd

const TIMEOUT_TICKS := 1800
const TALK := 2   # The Dave Show
## Ticks allowed for the road to thin out / fill back up.
const SETTLE_TICKS := 3600

enum Step { BOOT, THIN, DAVE, REFILL, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var game: Node
var cars := 16
var detail := 150.0
var min_active := 99

func _initialize() -> void:
	var env := OS.get_environment("NEON_TRAFFIC")
	cars = int(env) if env.is_valid_int() else 16
	OS.set_environment("NEON_TRAFFIC", str(cars))
	var d := OS.get_environment("NEON_DETAIL")
	detail = float(d) if d.is_valid_float() else 150.0
	_helper_tests()
	NightClock.path = "user://test_night_bands.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NightClock.path))
	OS.set_environment("NEON_CLOCK", "03:30")
	print("night_bands: %d cars, draw distance %.0f m" % [cars, detail])
	change_scene_to_file("res://Game.tscn")

func _helper_tests() -> void:
	var B := NightBands.Band
	_check(NightBands.band_of(0.0) == B.DUSK, "8 p.m. is dusk")
	_check(NightBands.band_of(119.9) == B.DUSK, "9:59 p.m. is dusk")
	_check(NightBands.band_of(120.0) == B.LATE, "10 p.m. is late")
	_check(NightBands.band_of(299.0) == B.LATE, "12:59 a.m. is late")
	_check(NightBands.band_of(300.0) == B.DEAD, "1 a.m. is the dead hours")
	_check(NightBands.band_of(480.0) == B.PREDAWN, "4 a.m. is pre-dawn")
	_check(NightBands.band_of(599.9) == B.PREDAWN, "5:59 a.m. is pre-dawn")
	_check(NightBands.traffic_share(0.0) == 1.0 and NightBands.traffic_share(119.0) == 1.0, "dusk runs the full slider")
	_check(is_equal_approx(NightBands.traffic_share(450.0), 0.3), "3:30 a.m. is the low point (%.2f)" % NightBands.traffic_share(450.0))
	_check(NightBands.traffic_share(NAN) == 1.0, "NaN time: full slider")
	var prev := NightBands.traffic_share(0.0)
	var lo := 1.0
	var m := 0.0
	while m <= NightClock.NIGHT_MINUTES:
		var s := NightBands.traffic_share(m)
		_check(s <= 1.0 and s >= 0.3, "share stays 0.3..1 (%.2f at %.0f)" % [s, m])
		_check(absf(s - prev) < 0.02, "no jump in traffic at %.0f min (%.3f -> %.3f)" % [m, prev, s])
		lo = minf(lo, s)
		prev = s
		m += 1.0
	_check(is_equal_approx(lo, 0.3), "lowest share is 0.3 (%.2f)" % lo)
	for b in 4:
		var lines := RadioStations.dj_lines(TALK, b)
		_check(lines.size() == RadioStations.STATIONS[TALK].dj.size() + NightBands.band_lines(b).size(), "Dave's band %d lines join his rotation" % b)
		for l in NightBands.band_lines(b):
			_check(String(l).begins_with("Dave:"), "band line in Dave's voice: %s" % l)
		for s in [0, 1, 3]:
			_check(RadioStations.dj_lines(s, b).is_empty(), "music station %d gets no Dave lines" % s)
			_check(not RadioStations.break_state(s, 3.0, b).in_break, "music station %d has no breaks" % s)
	_check(RadioStations.dj_lines(TALK).size() == RadioStations.STATIONS[TALK].dj.size(), "no band: plain rotation")

func _physics_process(_delta: float) -> bool:
	tick += 1
	if step == Step.DONE:
		return false
	game = current_scene
	if game == null or game.get("traffic") == null or game.get("radio") == null or game.get("night_clock") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var traffic: TrafficManager = game.traffic
	var clock: NightClock = game.night_clock
	var waited := tick - step_start
	match step:
		Step.BOOT:
			_check(game.bands_on(), "bands are on with NEON_CLOCK set in a test")
			_check(absf(clock.minutes - 450.0) < 0.5, "starts at 3:30 a.m. (%s)" % clock.text())
			_check(traffic.cars.size() == cars, "the slider's %d cars exist (%d)" % [cars, traffic.cars.size()])
			traffic.detail_distance = detail
			clock.speed = 0.0   # hold 3:30 a.m.
			game.radio.station = TALK
			_go(Step.THIN)
		Step.THIN:
			var want := traffic.active_target()
			if waited == 2:
				_check(want == roundi(cars * 0.3), "3:30 a.m. wants 30%% of %d cars (%d)" % [cars, want])
				_check(game.radio.band == NightBands.Band.DEAD, "the radio knows it is the dead hours (%d)" % game.radio.band)
			min_active = mini(min_active, traffic.active_count())
			if waited > 2 and traffic.active_count() == want:
				_check(traffic.bench_seen == 0, "no car left the road in view (%d)" % traffic.bench_seen)
				_check(traffic.bench_count == cars - want, "benched %d of %d" % [traffic.bench_count, cars - want])
				print("night_bands: thinned %d -> %d cars in %.1f s, %d benched" % [cars, want, waited / 60.0, traffic.bench_count])
				_go(Step.DAVE)
			elif waited > SETTLE_TICKS:
				return _end("traffic never thinned to %d (still %d)" % [want, traffic.active_count()])
		Step.DAVE:
			# Walk the station clock through one whole rotation: a dead-hours line must come up.
			var heard := false
			var n := RadioStations.dj_lines(TALK, NightBands.Band.DEAD).size()
			for i in n:
				var st := RadioStations.break_state(TALK, RadioStations.DAVE_PERIOD * i + 1.0, NightBands.Band.DEAD)
				if NightBands.band_lines(NightBands.Band.DEAD).has(RadioStations.dj_lines(TALK, NightBands.Band.DEAD)[st.line]):
					heard = true
			_check(heard, "Dave's rotation reaches a dead-hours line")
			clock.minutes = 0.0   # back to 8 p.m.: full traffic
			_go(Step.REFILL)
		Step.REFILL:
			if waited == 2:
				_check(game.radio.band == NightBands.Band.DUSK, "the radio follows the clock back to dusk")
			if waited > 2 and traffic.active_count() == cars:
				_check(traffic.unbench_count == traffic.bench_count, "every benched car came back (%d of %d)" % [traffic.unbench_count, traffic.bench_count])
				print("night_bands: refilled to %d cars in %.1f s" % [cars, waited / 60.0])
				return _end("")
			elif waited > SETTLE_TICKS:
				return _end("traffic never came back to %d (%d)" % [cars, traffic.active_count()])
	return false

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

var _ended := false
func _end(msg: String) -> bool:
	if _ended:
		return true
	_ended = true
	step = Step.DONE
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NightClock.path))
	print("night_bands: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
