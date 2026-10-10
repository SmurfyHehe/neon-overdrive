extends SceneTree

# Near-miss fix, the checks that need real traffic flowing (steps 2-3). One
# case per run, picked with NMF_CASE:
#
#   NMF_CASE=spawn godot --headless --fixed-fps 120 --path . -s res://tests/traffic/near_miss_flow.gd
#
#   spawn    5 min at 250 km/h with lane changes (the careful weave bot), every
#            placement logged. Worked out here from the logged positions, not
#            taken from the manager's own figure: no car is placed in the lane
#            you are in or the one you are heading for with under 10 s to
#            contact behind you, 4 s ahead of you, or 6 s oncoming; cars placed
#            behind you are at least 2 lanes away and at least 5 s apart.
#   blinker  60 s of normal traffic around a steady player: every lane change
#            that was not an emergency swerve had its blinker on for 1.5 s
#            first (0.8 s round an obstacle), and no car is seen mid change
#            with its blinker off.
# Env: NMF_SEED (1), NMF_CARS (40), NMF_SECS (per case).

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const RATE := 120
const KMH := 1.0 / 3.6
const P_HW := 1.0
const P_HL := 2.2
const INTENT_T := 1.2

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var traffic: TrafficManager
var mode := "spawn"
var seed_value := 1
var cars := 40
var secs := 60.0
var ticks := 0
var fails: Array[String] = []
var note := ""

# blinker
var seen_dark := 0

static func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	mode = _env("NMF_CASE", "spawn")
	seed_value = int(_env("NMF_SEED", "1"))
	cars = int(_env("NMF_CARS", "40"))
	secs = float(_env("NMF_SECS", {"spawn": "300", "blinker": "60"}.get(mode, "90")))
	OS.set_environment("NEON_CURVES", "0.0")
	OS.set_environment("NEON_HILLS", "0.0")
	OS.set_environment("NEON_POLICE", "0")
	OS.set_environment("NEON_NEAR_MISS_FILE", "user://near_miss_flow.txt")
	game = Harness.boot(self, cars, 300.0, seed_value, 300.0)

func _physics_process(_delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
			p = null
			return false
		traffic = game.get("traffic")
		if traffic.cars.size() != cars:
			traffic.set_car_count(cars)
		traffic.log_spawns = true
		traffic.log_changes = true
		traffic.spawn_log.clear()
		match mode:
			"spawn":
				TestDriver.place(p, Harness.lane_x(1), 0.0, 0.0, 250.0 * KMH)
				TestDriver.start(game, "weave", {"speed": 250.0, "seed": seed_value})
			"blinker":
				# Slower than its lane, so it runs into nobody: traffic has to
				# deal with it.
				TestDriver.place(p, Harness.lane_x(3), 0.0, 0.0, 55.0 * KMH)
				p.driver = Harness.lane_driver(Harness.lane_x(3), 1.0, 55.0 * KMH)
			_:
				fails.append("unknown NMF_CASE '%s'" % mode)
				return _end()
		return false
	ticks += 1
	if mode == "blinker":
		for car in traffic.cars:
			if car.changing and car.turn == 0 and car._lc_why != TrafficCar.DO_SWERVE and car._lc_why != TrafficCar.DO_ABORT and not car.hazard:
				seen_dark += 1
	if ticks >= int(secs * RATE):
		return _end()
	return false

# ---------- spawn safety ----------

func _check_spawns() -> void:
	var behind_n := 0
	var last_behind_t := -1000.0
	var worst := {"behind": INF, "ahead": INF, "oncoming": INF}
	var in_lane := 0
	for e in traffic.spawn_log:
		var lane_x := float(e.lane_x)
		var px := float(e.player_x)
		var ix := px + clampf(float(e.player_vx) * INTENT_T, -RoadChunkBuilder.LANE_W, RoadChunkBuilder.LANE_W)
		var lane := RoadChunkBuilder.lane_at(absf(lane_x))
		var same_side := (lane_x < 0.0) == (px < 0.0)
		var lanes_away := 99
		if same_side:
			lanes_away = absi(lane - RoadChunkBuilder.lane_at(absf(px)))
			if (ix < 0.0) == (px < 0.0):
				lanes_away = mini(lanes_away, absi(lane - RoadChunkBuilder.lane_at(absf(ix))))
		var dist := float(e.dist)                       # + = ahead of you
		var gap := absf(dist) - 1.7 - P_HL
		var pv := float(e.player_speed)
		var along := float(e.speed) * (1.0 if float(e.direction) == -1.0 else -1.0)   # the car's speed your way
		var kind := "behind" if dist < 0.0 else ("ahead" if along > 0.0 else "oncoming")
		if bool(e.behind):
			behind_n += 1
			if lanes_away < 2:
				fails.append("a car was placed behind you %d lane(s) from yours" % lanes_away)
			if float(e.t) - last_behind_t < 5.0 - 0.01:
				fails.append("two cars placed behind you %.1f s apart" % (float(e.t) - last_behind_t))
			last_behind_t = float(e.t)
		if lanes_away != 0:
			continue
		in_lane += 1
		var closing := (along - pv) if dist < 0.0 else (pv - along)
		if closing <= 0.0:
			continue
		var ttc := gap / closing
		worst[kind] = minf(float(worst[kind]), ttc)
		var limit: float = {"behind": 10.0, "ahead": 4.0, "oncoming": 6.0}[kind]
		if ttc < limit:
			fails.append("a car was placed %s, in your lane or the one you were heading for, %.1f s from contact (limit %.0f)" % [kind, ttc, limit])
	note = "%d placements, %d behind you; %d in your lane or the one you were heading for, shortest time to contact there: behind %s, ahead %s, oncoming %s" % [
		traffic.spawn_log.size(), behind_n, in_lane, _s(worst.behind), _s(worst.ahead), _s(worst.oncoming)]
	if traffic.spawn_log.size() < 100:
		fails.append("only %d placements in %d s" % [traffic.spawn_log.size(), int(secs)])

static func _s(v: float) -> String:
	return "none" if v == INF else "%.1f s" % v

# ---------- the end ----------

func _end() -> bool:
	match mode:
		"spawn":
			_check_spawns()
		"blinker":
			var n := 0
			var short := 0
			var by_why := {}
			for e in traffic.lane_change_log:
				var why := String(e.why)
				by_why[why] = int(by_why.get(why, 0)) + 1
				if why == TrafficCar.DO_SWERVE:
					continue
				n += 1
				var need := TrafficCar.SIGNAL_T_OBSTACLE if why == TrafficCar.DO_OBSTACLE else TrafficCar.SIGNAL_T
				if float(e.signal_s) < need - 0.01:
					short += 1
					if short <= 3:
						fails.append("a '%s' lane change after %.2f s of blinker (wanted %.1f)" % [why, float(e.signal_s), need])
			if n < 5:
				fails.append("only %d lane changes in %d s" % [n, int(secs)])
			if seen_dark > 0:
				fails.append("a car was mid lane change with its blinker off on %d ticks" % seen_dark)
			note = "%d lane changes %s, %d with too little blinker, %d ticks mid change without one" % [n, str(by_why), short, seen_dark]
	if traffic.near_miss != null:
		traffic.near_miss.finish()
		print("near_miss_flow %s: near misses %d %s" % [mode, traffic.near_miss.count, str(traffic.near_miss.by_cause)])
	print("near_miss_flow %s seed %d: %s" % [mode, seed_value, note])
	if p.current_speed() < 5.0 and mode != "spawn":
		fails.append("the player was stopped at the end")
	if not logger.errors.is_empty():
		fails.append("%d engine errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	for msg in fails:
		printerr("FAIL: " + msg)
	print("near_miss_flow: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
