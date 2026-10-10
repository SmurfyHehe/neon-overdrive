extends SceneTree

# Near-miss scenarios (traffic near-miss fix, step 2): two bots that drive the
# way that got Roy nearly hit, so the fix has a before and an after. The step 1
# weave bot is too careful: it never came within 9 s of a car.
#
#   NMS_MODE=pullout NMS_SEED=1 godot --headless --fixed-fps 120 --path . -s res://tests/traffic/near_miss_scenarios.gd
#
# NMS_MODE
#   pullout  200 km/h (about +100 on the traffic). Comes up behind a car in its
#            lane and, somewhere between 3 and 5.5 s from contact (drawn per
#            car, seeded), pulls out to the right without looking at the lane
#            it goes to (left only from the rightmost lane). Brakes only when
#            under BRAKE_T s from contact.
#   drift    150 km/h. The same, but lazier: it starts 5.5 to 8 s from contact
#            and slides sideways at DRIFT_V (four seconds a lane), to either
#            side, again without looking.
# Env: NMS_SEED (1), NMS_CARS (40), NMS_SECS (120). Straight flat road, so runs
# differ only by seed and by the traffic code.
#
# Prints one NMS line: every near miss, how many traffic caused (who moved =
# traffic or both), touches the player did not cause, and the counts by what
# the car was doing. The counts are the measurement, not a pass mark: it fails
# only on an engine error or a player that never moved. Run ONE at a time.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const RATE := 120
const STALL_KMH := 25.0
const STALL_TICKS := RATE * 3
const BRAKE_T := 1.2
const DRIFT_V := 0.8   # m/s sideways: four seconds a lane
const HALF_W := 1.0
const HALF_L := 2.2

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var traffic: TrafficManager
var mode := "pullout"
var seed_value := 1
var cars := 40
var secs := 120.0
var speed := 200.0 / 3.6
var rng := RandomNumberGenerator.new()
var lane := 1
var trigger := 4.0
var t := 0.0
var ticks := 0
var stalled := 0
var restarts := 0
var crashes := 0
var crash_in := -1
var pullouts := 0
var _ramp_x := 0.0
var metres := 0.0
var last_z := 0.0
var fails: Array[String] = []

static func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	mode = _env("NMS_MODE", "pullout")
	seed_value = int(_env("NMS_SEED", "1"))
	cars = int(_env("NMS_CARS", "40"))
	secs = float(_env("NMS_SECS", "120"))
	speed = (200.0 if mode == "pullout" else 150.0) / 3.6
	rng.seed = seed_value * 7919 + 13
	trigger = rng.randf_range(3.0, 5.5)
	OS.set_environment("NEON_CURVES", "0.0")
	OS.set_environment("NEON_HILLS", "0.0")
	OS.set_environment("NEON_POLICE", "0")
	if not OS.get_environment("NEON_ROAD_SEED").is_valid_int():
		OS.set_environment("NEON_ROAD_SEED", "37")
	OS.set_environment("NEON_NEAR_MISS_LOG", "")
	# The log appends: each run adds its own "game start" block to the file.
	var f := "user://near_miss_%s_%d.txt" % [mode, seed_value]
	OS.set_environment("NEON_NEAR_MISS_FILE", f)
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
		p.driver = _drive
		_launch()
		return false
	ticks += 1
	t += 1.0 / RATE
	var z := RoadFrame.unroll(p.global_position).z
	if absf(z - last_z) < 5.0:   # not the floating-origin shift or a relaunch
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
	# A crash: counted once, and the bot starts again on clear road half a second
	# later, so one pile-up is one event and not twenty touches in the wreckage.
	if crash_in < 0 and ticks > 3:
		for b in p.get_colliding_bodies():
			if b is TrafficCar:
				crashes += 1
				crash_in = RATE / 2
				break
	elif crash_in >= 0:
		crash_in -= 1
		if crash_in < 0:
			stalled = 0
			_launch(true)
	var bad := TestDriver.sanity(p)
	if bad != "":
		fails.append("sanity: " + bad)
		return _end()
	if ticks >= int(secs * RATE):
		return _end()
	return false

func _launch(find_room := false) -> void:
	p.damage.garage_repair(null)
	p.health.repair()
	p.fuel.litres = FuelTank.CAPACITY_L
	lane = 1
	var ahead := 0.0
	if find_room:
		# The first clear 100 m of lane from 150 m on.
		var z := RoadFrame.unroll(p.global_position).z
		var found := false
		for d in range(150, 600, 50):
			for l in [1, 2, 0, 3]:
				var x := Harness.lane_x(l)
				if traffic.scan(z - d, -1.0, x - HALF_W, x + HALF_W, true, 0, HALF_L, 300.0, false) > 50.0 						and traffic.scan(z - d, -1.0, x - HALF_W, x + HALF_W, false, 0, HALF_L, 300.0, false) > 50.0:
					lane = l
					ahead = float(d)
					found = true
					break
			if found:
				break
	TestDriver.place(p, Harness.lane_x(lane), ahead, 0.0, speed)
	_ramp_x = Harness.lane_x(lane)
	last_z = RoadFrame.unroll(p.global_position).z

# ---------- the bots ----------

func _drive(c: PlayerCar) -> void:
	var u := RoadFrame.unroll(c.global_position)
	var v := c.current_speed()
	var lx := Harness.lane_x(lane)
	# What is ahead in the strip of road the body covers on the way to its lane.
	var lo := minf(u.x, lx) - HALF_W
	var hi := maxf(u.x, lx) + HALF_W
	var gap := traffic.scan(u.z, -1.0, lo, hi, true, 0, HALF_L, 300.0, false)
	var lead_v := traffic.q_speed
	var ttc := gap / (v - lead_v) if gap < INF and v > lead_v + 0.5 else INF
	var settled := absf(u.x - lx) < 0.6
	var aim := lx
	if mode == "pullout":
		if settled and ttc < trigger:
			lane = lane + 1 if lane < traffic.own_lanes - 1 else lane - 1
			trigger = rng.randf_range(3.0, 5.5)
			pullouts += 1
	else:
		# Drift: starts earlier and slides over at DRIFT_V, to either side.
		if settled and ttc < trigger:
			var step := 1 if rng.randf() < 0.5 else -1
			if lane + step < 0 or lane + step >= traffic.own_lanes:
				step = -step
			lane += step
			trigger = rng.randf_range(5.5, 8.0)
			pullouts += 1
			_ramp_x = u.x
		_ramp_x = move_toward(_ramp_x, Harness.lane_x(lane), DRIFT_V / RATE)
		aim = _ramp_x
	_pedals(c, v, gap if ttc < BRAKE_T else INF, lead_v)
	var side_v := RoadFrame.dir_to_road(u.z, c.linear_velocity).x
	c.steering_input = TrafficCar.lane_steer(c, aim - side_v * 1.2, -1.0, 2.5, 0.0008)
	c.handbrake_input = 0.0

func _pedals(c: PlayerCar, v: float, gap: float, lead_v: float) -> void:
	var a := speed - v
	if gap < INF:
		a = minf(a, TrafficCar.follow_accel(v, speed, gap, lead_v, 1.0))
	if a < -0.3:
		c.throttle_input = 0.0
		c.brake_input = clampf(-a / 9.0, 0.0, 1.0)
	else:
		c.throttle_input = clampf(a, 0.0, 1.0)
		c.brake_input = 0.0

# ---------- the report ----------

static func _fmt(d: Dictionary) -> String:
	var keys := d.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s=%d" % [k, d[k]])
	return "{" + " ".join(parts) + "}"

func _end() -> bool:
	var nm = traffic.near_miss
	if nm != null:
		nm.finish()
		var by_traffic := 0
		var traffic_doing := {}
		for cause in nm.by_cause:
			var c := String(cause)
			if c.begins_with("traffic:"):
				by_traffic += int(nm.by_cause[cause])
				traffic_doing[c.substr(8)] = int(traffic_doing.get(c.substr(8), 0)) + int(nm.by_cause[cause])
		var both := int(nm.by_who.get("both", 0))
		# Touches the player did not cause (the last 200 records are kept; a run
		# with more says so).
		var touches_not_you := 0
		for rec in nm.records:
			if rec.kind == "touch" and rec.who != "you":
				touches_not_you += 1
		print("NMS mode=%s seed=%d cars=%d secs=%d total=%d traffic_caused=%d (traffic=%d both=%d) you=%d neither=%d touches_not_you=%d crashes=%d%s" % [
			mode, seed_value, cars, int(secs), nm.count, by_traffic + both, by_traffic, both,
			int(nm.by_who.get("you", 0)), int(nm.by_who.get("neither", 0)), touches_not_you, crashes,
			" (only the last 200 records looked at)" if nm.count > nm.records.size() else ""])
		print("NMS_DETAIL seed=%d kind=%s traffic_doing=%s all_doing=%s" % [seed_value, _fmt(nm.by_kind), _fmt(traffic_doing), _fmt(nm.by_doing)])
		print("NMS_SEEN seed=%d looked_at=%d closest_side_gap=%.2f m shortest_ttc=%.2f s passes_under_1m_or_2s=%d " % [
			seed_value, nm.evaluated, nm.min_side_gap, nm.min_ttc, nm.loose_count])
		print("NMS_FILE ", ProjectSettings.globalize_path("user://near_miss_%s_%d.txt" % [mode, seed_value]))
	else:
		fails.append("the near-miss log is off")
	print("near_miss_scenarios %s seed %d: drove %.1f km, pull-outs %d, crashes %d, restarts %d, traffic lane changes %d, spawns %d" % [
		mode, seed_value, metres / 1000.0, pullouts, crashes, restarts, traffic.lane_change_count, traffic.spawn_count])
	if traffic.cars.size() != cars or traffic.spawn_count < cars:
		fails.append("the road had %d cars and %d spawns, wanted %d (another Godot run sharing user://settings can zero the traffic: rerun)" % [traffic.cars.size(), traffic.spawn_count, cars])
	if metres < 500.0:
		fails.append("the player barely moved (%.0f m)" % metres)
	if not logger.errors.is_empty():
		fails.append("%d engine errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	for f in fails:
		printerr("FAIL: " + f)
	print("near_miss_scenarios: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
