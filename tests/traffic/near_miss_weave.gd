extends SceneTree

# Near-miss baseline (traffic near-miss fix, step 1): the shared test driver in
# mode "weave" at 180 km/h through 40 traffic cars for 90 s of game time, one
# seed per process, and the near-miss log's counts by kind, by who moved and by
# what the car was doing. Run it ONE seed at a time:
#
#   WEAVE_SEED=3 godot --headless --fixed-fps 120 --path . -s res://tests/traffic/near_miss_weave.gd
#
# WEAVE_BLIND=1 gives the bot no traffic at all (TestDriver traffic=false: no
# braking, no gap checks): it holds its lane at 180 km/h and runs into what is
# in it. The careful default bot keeps over 1 m beside every car and never gets
# under 9 s from one, so it records nothing; the blind run is the other end,
# not a weaving player.
# Env: WEAVE_SEED (default 1), WEAVE_CARS (40; 16 is the game's default),
# WEAVE_SECS (90), WEAVE_SPEED km/h (180), WEAVE_CURVES / WEAVE_HILLS (0: a
# straight, flat road so the runs differ only by seed). It prints one
# NEARMISS line to paste into a table and writes the log file next to the
# user data (user://near_miss_weave_<seed>.txt), so the individual moments can
# be read. Only fails on an engine error or a player that never got moving: the
# counts are the baseline, not a pass mark.
#
# If the player is wrecked it is put back on the road at speed (repaired) and
# the restart is counted, so one crash does not turn the rest of the 90 s into
# a parked car.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const RATE := 120
const STALL_KMH := 25.0
const STALL_TICKS := RATE * 3

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var bot: TestDriver
var seed_value := 1
var cars := 40
var secs := 90.0
var speed_kmh := 180.0
var ticks := 0
var stalled := 0
var restarts := 0
var metres := 0.0
var last_z := 0.0
var started := false
var fails: Array[String] = []

static func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	seed_value = int(_env("WEAVE_SEED", "1"))
	cars = int(_env("WEAVE_CARS", "40"))
	secs = float(_env("WEAVE_SECS", "90"))
	speed_kmh = float(_env("WEAVE_SPEED", "180"))
	OS.set_environment("NEON_CURVES", _env("WEAVE_CURVES", "0.0"))
	OS.set_environment("NEON_HILLS", _env("WEAVE_HILLS", "0.0"))
	if not OS.get_environment("NEON_ROAD_SEED").is_valid_int():
		OS.set_environment("NEON_ROAD_SEED", "37")
	OS.set_environment("NEON_NEAR_MISS_LOG", "")
	var f := "user://near_miss_weave_%d.txt" % seed_value
	if FileAccess.file_exists(f):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))   # this test's own output
	OS.set_environment("NEON_NEAR_MISS_FILE", f)
	game = Harness.boot(self, cars, 300.0, seed_value, 300.0)

func _physics_process(_delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
			p = null
			return false
		var opts := {"speed": speed_kmh, "seed": seed_value}
		if _env("WEAVE_BLIND", "0") == "1":
			opts["traffic"] = false
		# The settings file is shared with any other Godot run on this machine
		# (a run with 0 traffic cars started a moment ago can win the race), so
		# the count is set here, not trusted from the file.
		var tr: TrafficManager = game.get("traffic")
		if tr.cars.size() != cars:
			tr.set_car_count(cars)
		bot = TestDriver.start(game, "weave", opts)
		_launch()
		started = true
		return false
	ticks += 1
	var z := RoadFrame.unroll(p.global_position).z
	metres += absf(z - last_z)
	last_z = z
	if p.current_speed() * 3.6 < STALL_KMH:
		stalled += 1
		if stalled > STALL_TICKS:
			restarts += 1
			stalled = 0
			_launch()
	else:
		stalled = 0
	var bad := TestDriver.sanity(p)
	if bad != "":
		fails.append("sanity: " + bad)
		return _end()
	if ticks >= int(secs * RATE):
		return _end()
	return false

func _launch() -> void:
	p.damage.garage_repair(null)
	p.health.repair()
	p.fuel.litres = FuelTank.CAPACITY_L
	TestDriver.place(p, Harness.lane_x(1), 0.0, 0.0, speed_kmh / 3.6)
	last_z = RoadFrame.unroll(p.global_position).z

static func _fmt(d: Dictionary) -> String:
	var keys := d.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s=%d" % [k, d[k]])
	return "{" + " ".join(parts) + "}"

func _end() -> bool:
	var traffic: TrafficManager = game.get("traffic")
	var nm = traffic.near_miss
	if nm != null:
		nm.finish()
		print("NEARMISS blind=%s seed=%d cars=%d secs=%d speed=%d total=%d kind=%s who=%s doing=%s" % [
			_env("WEAVE_BLIND", "0"), seed_value, cars, int(secs), int(speed_kmh), nm.count, _fmt(nm.by_kind), _fmt(nm.by_who), _fmt(nm.by_doing)])
		print("NEARMISS_SEEN seed=%d looked_at=%d closest_side_gap=%.2f m shortest_ttc=%.2f s passes_under_1m_or_2s=%d check_cost=%.4f ms/tick" % [
			seed_value, nm.evaluated, nm.min_side_gap, nm.min_ttc, nm.loose_count, float(nm.cost_usec) / 1000.0 / float(maxi(nm.ticks_seen, 1))])
		print("NEARMISS_FILE ", ProjectSettings.globalize_path("user://near_miss_weave_%d.txt" % seed_value))
	else:
		fails.append("the near-miss log is off")
	print("near_miss_weave traffic: pool %d, spawns %d, recycles %d, deferred %d, benched %d, lane changes %d" % [
		traffic.cars.size(), traffic.spawn_count, traffic.recycle_count, traffic.deferred_count, traffic.bench_count, traffic.lane_change_count])
	print("near_miss_weave seed %d: drove %.1f km, restarts %d, lane changes %d, %s" % [seed_value, metres / 1000.0, restarts, traffic.lane_change_count, bot.summary()])
	if traffic.cars.size() != cars or traffic.spawn_count < cars:
		fails.append("the road had %d cars and %d spawns, wanted %d (another Godot run sharing user://settings can zero the traffic: rerun)" % [traffic.cars.size(), traffic.spawn_count, cars])
	if metres < 500.0:
		fails.append("the player barely moved (%.0f m)" % metres)
	if not logger.errors.is_empty():
		fails.append("%d engine errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	for f in fails:
		printerr("FAIL: " + f)
	print("near_miss_weave: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
