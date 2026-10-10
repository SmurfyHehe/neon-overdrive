extends SceneTree

# Shared test driver, mode "clean" (scripts/core/test_driver.gd): the bot drives
# a bendy road with traffic at each target speed and must touch nothing.
#
#   godot --headless --fixed-fps 120 --path . -s res://tests/core/drive_clean.gd
#
# Per speed (DRIVE_SPEEDS, km/h, default "150,300"): the car is launched in
# lane 1 at min(target, 300 km/h) and drives DRIVE_SECS (default 10) of game
# time among DRIVE_CARS (default 24) traffic cars, one of which is put 90 m
# ahead in its lane doing 80 km/h so every run has to deal with traffic. Then two recovery runs on an
# empty road: "spin", dropped in at 90 km/h going backwards, and "turn", parked
# pointing back up the road. Both have to end up driving the right way again.
# The road is straight unless DRIVE_CURVES / DRIVE_HILLS say otherwise
# (tests/core/drive_bends.gd is this test on bends and hills).
#
# Fails on: any wall or car contact (the driver's own per-tick count, the crash
# sound's impact count and the damage model's hit count), a lane error over
# LANE_MAX_ERR outside a lane change, never getting near the target speed on
# a road that allows it, a NaN, the car under the road, an engine error.
# The long version (run_tests.bat full tier) sets DRIVE_SECS=120 and more cars.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const RATE := 120
const LANE_MAX_ERR := 1.2
const LAUNCH_MAX := 300.0  # km/h: faster targets are reached under power
const SPIN_SECS := 40.0

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var bot: TestDriver
var speeds: Array[float] = []
var secs := 10.0
var cars := 16
var phase := -1
var phase_tick := 0
var top := 0.0
var launch := 0.0
var road_cap := INF
var crash: CrashAudio
var fails: Array[String] = []

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	for s in _env("DRIVE_SPEEDS", "150,300").split(",", false):
		speeds.append(float(s))
	secs = float(_env("DRIVE_SECS", "10"))
	cars = int(_env("DRIVE_CARS", "24"))
	OS.set_environment("NEON_CURVES", _env("DRIVE_CURVES", "0.0"))
	OS.set_environment("NEON_HILLS", _env("DRIVE_HILLS", "0.0"))
	if not OS.get_environment("NEON_ROAD_SEED").is_valid_int():
		OS.set_environment("NEON_ROAD_SEED", "37")
	game = Harness.boot(self, 0, 300.0, int(_env("DRIVE_SEED", "777")), 300.0)

static func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback

func _physics_process(_delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
			p = null
			return false
		for c in p.get_children():
			if c is CrashAudio:
				crash = c
		_next_phase()
		return false
	phase_tick += 1
	if phase_tick == 5 and phase < speeds.size():
		# A slow car in the bot's own lane, as close as leaves room to brake for it.
		var traffic: TrafficManager = game.get("traffic")
		if not traffic.cars.is_empty():
			var car: TrafficCar = traffic.cars[0]
			var v := p.current_speed()
			car.place(Harness.lane_x(1), -1.0, RoadFrame.unroll(p.global_position).z - 90.0 - maxf(0.0, v * v - 22.0 * 22.0) / (2.0 * 6.0), car.rest_y, 22.0)
	top = maxf(top, p.current_speed())
	if bot._bend_v < INF:
		road_cap = minf(road_cap, bot._bend_v)
	if OS.get_environment("DRIVE_DEBUG") == "1" and phase_tick % 30 == 0:
		var u := RoadFrame.unroll(p.global_position)
		print("  t=%.2f v=%.0f x=%.2f lane=%d slip=%.2f head=%.2f steer=%.2f thr=%.2f brk=%.2f gear=%d gap=%.0f bend=%.0f rec=%d k=%.5f" % [
			phase_tick / float(RATE), p.current_speed() * 3.6, u.x, bot.lane, TestDriver.slip_angle(p), TestDriver.heading_error(p),
			p.steer_fraction(), p.throttle_input, p.brake_input, p.current_gear, minf(bot._gap, 9999.0), minf(bot._bend_v, 999.0) * 3.6, bot._rec, RoadFrame.curvature_at(u.z)])
	var bad := TestDriver.sanity(p)
	if bad != "":
		fails.append("%s: %s" % [_name(), bad])
		return _end()
	var spin_phase := phase >= speeds.size()
	if spin_phase and phase_tick > RATE * 3 and absf(TestDriver.heading_error(p)) < 0.3 and p.current_speed() > 15.0:
		_close_phase()
		if phase > speeds.size():
			return _end()
		_next_phase()
		return false
	if phase_tick >= int((SPIN_SECS if spin_phase else secs) * RATE):
		_close_phase()
		if spin_phase:
			fails.append("%s: still not driving the right way after %d s (heading %.2f rad, %.0f km/h)" % [
				_name(), int(SPIN_SECS), TestDriver.heading_error(p), p.current_speed() * 3.6])
		if phase > speeds.size():
			return _end()
		_next_phase()
	return false

func _name() -> String:
	return "%d km/h" % int(speeds[phase]) if phase < speeds.size() else ("spin" if phase == speeds.size() else "turn")

func _next_phase() -> void:
	phase += 1
	phase_tick = 0
	top = 0.0
	road_cap = INF
	var traffic: TrafficManager = game.get("traffic")
	p.damage.garage_repair(null)
	p.health.repair()
	p.fuel.litres = FuelTank.CAPACITY_L
	if phase < speeds.size():
		traffic.set_car_count(cars)
		bot = TestDriver.start(game, "clean", {"speed": speeds[phase]})
		# Launched no faster than the bends just ahead allow.
		launch = minf(minf(speeds[phase], LAUNCH_MAX) / 3.6, bot.bend_speed(p, TestDriver.CLEAN_LAT_ACCEL, speeds[phase] / 3.6))
		TestDriver.place(p, Harness.lane_x(1), 0.0, 0.0, launch)
	elif phase == speeds.size():
		# Spin recovery: alone on the road, going backwards at 90 km/h.
		traffic.set_car_count(0)
		bot = TestDriver.start(game, "clean", {"speed": 100.0})
		TestDriver.place(p, Harness.lane_x(1), 0.0, 2.9, 25.0)
		p.linear_velocity = -p.linear_velocity
	else:
		# Turn round: parked in lane 2 pointing back up the road.
		bot = TestDriver.start(game, "clean", {"speed": 100.0})
		TestDriver.place(p, Harness.lane_x(2), 0.0, 3.0, 0.0)

func _close_phase() -> void:
	var n := _name()
	print("drive_clean %s: top %.0f km/h, road allowed %s, %s" % [n, top * 3.6,
		"any" if road_cap == INF else "%.0f km/h at its tightest" % (road_cap * 3.6), bot.summary()])
	if phase < speeds.size():
		if bot.wall_contacts > 0 or bot.car_contacts > 0:
			fails.append("%s: touched something (%s)" % [n, bot.first_contact])
		if bot.max_lane_err > LANE_MAX_ERR:
			fails.append("%s: %.2f m off its lane (limit %.1f)" % [n, bot.max_lane_err, LANE_MAX_ERR])
		if bot.spins > 0:
			fails.append("%s: spun %d times" % [n, bot.spins])
		if bot.min_gap == INF and cars > 0:
			fails.append("%s: never met the traffic it was meant to deal with" % n)
		if top < launch * 0.9:
			fails.append("%s: never got near its speed (top %.0f km/h)" % [n, top * 3.6])
	else:
		if bot.wall_contacts > 0:
			fails.append("%s: hit a wall recovering (%s)" % [n, bot.first_contact])
	if crash != null and crash.impact_count > 0 and phase < speeds.size():
		fails.append("%s: the crash sound counted %d impacts" % [n, crash.impact_count])
	if p.damage.hits > 0 and phase < speeds.size():
		fails.append("%s: the damage model counted %d hits" % [n, p.damage.hits])

func _end() -> bool:
	if not logger.errors.is_empty():
		fails.append("%d engine errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	for f in fails:
		printerr("FAIL: " + f)
	print("drive_clean: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
