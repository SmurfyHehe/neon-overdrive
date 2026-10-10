extends SceneTree

# Shared test driver: spawning at speed (scripts/core/test_driver.gd, place()
# and mode "clean"). The car is put on the road already moving at each speed in
# DRIVE_SPAWN_SPEEDS (km/h, default "0,50,100,200,300,400") and the bot holds
# that speed in lane 1 for HOLD_SECS on an empty road.
#
#   godot --headless --fixed-fps 120 --path . -s res://tests/core/drive_spawn.gd
#
# Fails on: a speed jump at the spawn (the teleport read as a velocity burst),
# a spin, a wall touch, leaving the lane, the car not upright, a NaN, the car
# under the road, an engine error. DRIVE_CURVES / DRIVE_HILLS (default 0)
# spawn it on bends and hills instead.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const RATE := 120
const HOLD_SECS := 3.0
const LANE_MAX_ERR := 1.0
const BURST := 3.0   # m/s over the spawn speed

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var bot: TestDriver
var speeds: Array[float] = []
var at := -1
var tick := 0
var top := 0.0
var low := INF
var max_tilt := 0.0
var fails: Array[String] = []

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	var s := OS.get_environment("DRIVE_SPAWN_SPEEDS")
	for x in (s if s != "" else "0,50,100,200,300,400").split(",", false):
		speeds.append(float(x))
	for k in ["CURVES", "HILLS"]:
		var v := OS.get_environment("DRIVE_" + k)
		OS.set_environment("NEON_" + k, v if v != "" else "0")
	if not OS.get_environment("NEON_ROAD_SEED").is_valid_int():
		OS.set_environment("NEON_ROAD_SEED", "37")
	game = Harness.boot(self, 0, 300.0, 5)

func _physics_process(_delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
			p = null
			return false
		return _next()
	tick += 1
	var v := p.linear_velocity.length()
	top = maxf(top, v)
	low = minf(low, v)
	max_tilt = maxf(max_tilt, acos(clampf(RoadFrame.basis_to_road(RoadFrame.unroll(p.global_position).z, p.global_transform.basis).y.y, -1.0, 1.0)))
	var bad := TestDriver.sanity(p)
	if bad != "":
		fails.append("%d km/h, tick %d: %s" % [int(speeds[at]), tick, bad])
		return _end()
	if tick >= int(HOLD_SECS * RATE):
		_close()
		return _next()
	return false

func _next() -> bool:
	at += 1
	if at >= speeds.size():
		return _end()
	tick = 0
	top = 0.0
	low = INF
	max_tilt = 0.0
	p.damage.garage_repair(null)
	p.health.repair()
	p.fuel.litres = FuelTank.CAPACITY_L
	bot = TestDriver.start(game, "clean", {"speed": speeds[at]})
	TestDriver.place(p, Harness.lane_x(1), 0.0, 0.0, speeds[at] / 3.6)
	return false

func _close() -> void:
	var want: float = speeds[at] / 3.6
	var n := "%d km/h" % int(speeds[at])
	print("drive_spawn %s: speed %.0f..%.0f km/h, tilt %.1f deg, %s" % [n, low * 3.6, top * 3.6, rad_to_deg(max_tilt), bot.summary()])
	if top > want + BURST:
		fails.append("%s: speed jumped to %.0f km/h" % [n, top * 3.6])
	if bot.spins > 0:
		fails.append("%s: spun" % n)
	if bot.wall_contacts > 0 or bot.car_contacts > 0:
		fails.append("%s: touched something (%s)" % [n, bot.first_contact])
	if bot.max_lane_err > LANE_MAX_ERR:
		fails.append("%s: %.2f m off its lane" % [n, bot.max_lane_err])
	if max_tilt > deg_to_rad(12.0):
		fails.append("%s: tilted %.0f deg" % [n, rad_to_deg(max_tilt)])
	if p.damage.hits > 0:
		fails.append("%s: the damage model counted %d hits" % [n, p.damage.hits])

func _end() -> bool:
	if not logger.errors.is_empty():
		fails.append("%d engine errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	for f in fails:
		printerr("FAIL: " + f)
	print("drive_spawn: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
