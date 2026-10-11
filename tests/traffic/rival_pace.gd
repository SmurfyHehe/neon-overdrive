extends SceneTree

# Rival driver: pace (rival driver build spec, step 1). The same written bendy
# road, no traffic, the same car (the tuner, on the player's own numbers),
# driven three times in one run and timed over the same 3 km:
#   1. the shared test driver's grip mode (scripts/core/test_driver.gd), the
#      yardstick: lane centre, bends at the grip limit,
#   2. the rival at commit 0.97: must be within 3% of the yardstick,
#   3. the rival at commit 0.84 (the Docks crew): must be measurably slower
#      than at 0.97.
# Also reports what the race brain costs per physics tick.
#
# Exit code 1 on failure. Run (about 4 min), with NEON_TICKS=120:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 120 --path . -s res://tests/traffic/rival_pace.gd

const R := preload("res://tests/traffic/rival_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")

const KIND := "p3_tuner"
## [radius (+ left), chunks]; the heading stays inside the road's 30 degrees.
const ROAD := [[0.0, 4], [200.0, 2], [-200.0, 4], [200.0, 2], [0.0, 6], [-300.0, 3], [0.0, 4], [300.0, 3], [0.0, 6],
	[-200.0, 2], [200.0, 4], [-200.0, 2], [0.0, 6]]
const START_S := 60.0
const START_SPEED := 30.0
const LINE_A := 400.0
const LINE_B := 3400.0
const TIMEOUT_TICKS := 120 * 200
const RUNS := ["grip bot", "rival 0.97", "rival 0.84"]
const COMMITS := [0.0, 0.97, 0.84]

var failures: Array[String] = []
var game: Node
var rival: TrafficCar
var bot: RefCounted
var run := 0
var state := 0     # 0 booting, 1 driving, 2 tearing down
var wait := 0
var player_y := 0.0
var t_a := -1.0
var last_s := 0.0
var times: Array[float] = []
var slowest := INF
var top := 0.0
var costs: Array[String] = []

func _initialize() -> void:
	R.env(ROAD)
	OS.set_environment("NEON_CAR", KIND)
	game = R.boot(self)

func _physics_process(_delta: float) -> bool:
	wait += 1
	match state:
		0:
			if R.ready(game) and wait > 60:
				var p: PlayerCar = game.player
				player_y = RoadFrame.unroll(p.global_position).y
				if run == 0:
					R.park_player(p, TrafficManager.lane_centre(1, false), START_S, player_y)
					TrafficCar.set_moving(p, START_SPEED)
					bot = TestDriver.start(game, "grip", {"speed": 400.0, "lane": 1, "traffic": false})
				else:
					R.hold_player(p)
					var car_spec := CarSpec.clone_spec(p.spec)
					car_spec["automatic_transmission"] = true
					rival = R.spawn_rival(game, KIND, 1, START_S, START_SPEED, COMMITS[run], 7, car_spec)
				t_a = -1.0
				last_s = START_S
				slowest = INF
				top = 0.0
				wait = 0
				state = 1
		1:
			var car: Vehicle = game.player if run == 0 else rival
			var s := R.s_of(car)
			if run > 0:
				R.park_player(game.player, TrafficManager.lane_centre(1, false), s - 150.0, player_y)
			var now := float(wait) / 120.0
			# The crossing time, to a fraction of a tick.
			if t_a < 0.0 and s >= LINE_A:
				t_a = now - (s - LINE_A) / maxf(s - last_s, 0.001) / 120.0
			if t_a >= 0.0:
				var v: float = car.linear_velocity.length()
				slowest = minf(slowest, v)
				top = maxf(top, v)
			if s >= LINE_B:
				var t := now - (s - LINE_B) / maxf(s - last_s, 0.001) / 120.0 - t_a
				times.append(t)
				_report(t)
				_next()
			elif wait > TIMEOUT_TICKS or (run > 0 and rival.wrecked):
				_fail("%s did not finish (%.0f of %.0f m)" % [RUNS[run], s, LINE_B])
				times.append(INF)
				_next()
			last_s = s
		2:
			if wait > 20:
				if run >= RUNS.size():
					return _finish()
				game = R.boot(self)
				wait = 0
				state = 0
	return false

func _report(t: float) -> void:
	var extra := ""
	if run == 0:
		extra = bot.summary()
		if bot.wall_contacts > 0:
			_fail("the grip bot hit a wall: the yardstick is no good")
	else:
		extra = rival.racer.cost_summary()
		costs.append("%s: %s" % [RUNS[run], extra])
		if rival.racer.cost_ms_per_tick() >= 0.05:
			_fail("%s: race brain %.4f ms per tick, budget 0.05" % [RUNS[run], rival.racer.cost_ms_per_tick()])
	print("pace %s: %.2f s over %.0f m (%.0f km/h average, slowest %.0f, top %.0f)  %s" % [
		RUNS[run], t, LINE_B - LINE_A, (LINE_B - LINE_A) / t * 3.6, slowest * 3.6, top * 3.6, extra])

func _next() -> void:
	R.teardown(game)
	game = null
	rival = null
	bot = null
	run += 1
	wait = 0
	state = 2

func _finish() -> bool:
	if times.size() == 3 and times[0] < INF and times[1] < INF and times[2] < INF:
		var off := (times[1] - times[0]) / times[0]
		print("pace: rival 0.97 is %+.2f%% against the grip bot; rival 0.84 is %+.2f%% against rival 0.97" % [off * 100.0, (times[2] - times[1]) / times[1] * 100.0])
		if absf(off) > 0.03:
			_fail("rival at commit 0.97 is %+.2f%% off the grip bot's time, wanted within 3%%" % (off * 100.0))
		if times[2] < times[1] * 1.005:
			_fail("rival at commit 0.84 (%.2f s) is not measurably slower than at 0.97 (%.2f s)" % [times[2], times[1]])
	RoadAlignment.scripted = []
	print("rival_pace: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true

func _fail(what: String) -> void:
	failures.append(what)
	printerr("FAIL: ", what)
