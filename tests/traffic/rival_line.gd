extends SceneTree

# Rival driver: the racing line, driven (rival driver build spec, step 1). A
# written road with four bends, 350 m left, 350 m right, 150 m left, 150 m
# right, 400 m of straight between them, no traffic, the real Game.tscn. The
# rival (Docks crew, the hot hatch) drives it once. For every bend:
#   - it uses at least 60% of its own side's width (outside, apex, outside),
#   - no part of the car crosses the centre line,
#   - no part of the car leaves the road (past the shoulder): off road = 0.
# Also reports how far it strays from its line and how much it brakes.
#
# Exit code 1 on failure. Run (about 1.5 min):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 120 --path . -s res://tests/traffic/rival_line.gd

const R := preload("res://tests/traffic/rival_harness.gd")

## [radius (+ left), chunks]: the heading stays inside the road's 30 degrees.
const ROAD := [[0.0, 8], [350.0, 3], [0.0, 8], [-350.0, 6], [0.0, 8], [150.0, 2], [0.0, 8], [-150.0, 2], [0.0, 8], [350.0, 3]]
## name, start and end of each bend in metres down the road.
const BENDS := [["350 m left", 400.0, 550.0], ["350 m right", 950.0, 1250.0], ["150 m left", 1650.0, 1750.0], ["150 m right", 2150.0, 2250.0]]
const AROUND := 130.0          # m either side of a bend that count as its line
const END_S := 2450.0
const OWN_WIDTH := 4.0 * RoadChunkBuilder.LANE_W
const ROAD_EDGE := RoadChunkBuilder.MEDIAN_GAP + OWN_WIDTH + RoadChunkBuilder.SHOULDER_W
const TIMEOUT_TICKS := 120 * 120

var failures: Array[String] = []
var game: Node
var rival: TrafficCar
var wait := 0
var running := false
var player_y := 0.0
var lo: Array[float] = []
var hi: Array[float] = []
var slowest: Array[float] = []
var over_centre := 0
var off_road := 0
var on_shoulder := 0
var worst_err := 0.0
var err_sum := 0.0
var braked := 0
var ticks := 0
var top := 0.0

func _initialize() -> void:
	R.env(ROAD)
	for b in BENDS:
		lo.append(INF)
		hi.append(-INF)
		slowest.append(INF)
	game = R.boot(self)

func _physics_process(_delta: float) -> bool:
	wait += 1
	if not running:
		if R.ready(game) and wait > 60:
			player_y = RoadFrame.unroll(game.player.global_position).y
			R.hold_player(game.player)
			rival = R.spawn_rival(game, "p2_hothatch", 1, 60.0, 30.0, 0.84, 7)
			running = true
			wait = 0
		return false
	var u := RoadFrame.unroll(rival.global_position)
	var s := RoadFrame.s_at(u.z)
	R.park_player(game.player, TrafficManager.lane_centre(1, false), s - 150.0, player_y)
	ticks += 1
	var v := rival.current_speed()
	top = maxf(top, v)
	for i in BENDS.size():
		if s >= float(BENDS[i][1]) - AROUND and s <= float(BENDS[i][2]) + AROUND:
			lo[i] = minf(lo[i], u.x)
			hi[i] = maxf(hi[i], u.x)
			slowest[i] = minf(slowest[i], v)
	if u.x - rival.half_w < 0.0:
		over_centre += 1
	if u.x + rival.half_w > ROAD_EDGE:
		off_road += 1
	if u.x + rival.half_w > RoadChunkBuilder.MEDIAN_GAP + OWN_WIDTH:
		on_shoulder += 1
	# NEON_RIVAL_DUMP=1: a line of telemetry every 0.1 s, for tuning.
	if ticks % 12 == 0 and OS.get_environment("NEON_RIVAL_DUMP") == "1":
		print("T s=%.0f x=%.2f line=%.2f v=%.1f want=%.1f thr=%.2f brk=%.2f steer=%.3f slip=%.3f k=%.5f" % [s, u.x, u.x - rival.racer.line_error, v,
			rival.racer.target_speed, rival.throttle_input, rival.brake_input, rival.steering_input, RivalDriver._slip(rival), RoadFrame.curvature(floori(s / 50.0))])
	var e := absf(rival.racer.line_error)
	worst_err = maxf(worst_err, e)
	err_sum += e
	if rival.brake_input > 0.05:
		braked += 1
	if s >= END_S or wait > TIMEOUT_TICKS or rival.wrecked:
		return _finish(s)
	return false

func _finish(s: float) -> bool:
	if s < END_S:
		_fail("the rival did not finish the road (%.0f of %.0f m, wrecked=%s)" % [s, END_S, rival.wrecked])
	for i in BENDS.size():
		var used := hi[i] - lo[i]
		var share := used / OWN_WIDTH
		print("bend %s: x %.2f to %.2f m, %.1f m = %.0f%% of its side, slowest %.0f km/h" % [BENDS[i][0], lo[i], hi[i], used, share * 100.0, slowest[i] * 3.6])
		if share < 0.6:
			_fail("%s: used %.0f%% of its side, wanted at least 60%%" % [BENDS[i][0], share * 100.0])
	if over_centre > 0:
		_fail("crossed the centre line on %d ticks" % over_centre)
	if off_road > 0:
		_fail("off the road on %d ticks" % off_road)
	print("rival line: %.0f m in %.1f s, top %.0f km/h, braking on %d ticks; off its line by %.2f m at worst, %.2f m on average; over the centre line %d ticks, on the shoulder %d ticks, off road %d ticks" % [
		s - 60.0, float(ticks) / 120.0, top * 3.6, braked, worst_err, err_sum / maxf(float(ticks), 1.0), over_centre, on_shoulder, off_road])
	print("rival ", rival.racer.cost_summary())
	RoadAlignment.scripted = []
	print("rival_line: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true

func _fail(what: String) -> void:
	failures.append(what)
	printerr("FAIL: ", what)
