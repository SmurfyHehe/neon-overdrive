extends SceneTree

# Shared test driver, mode "flatout" (scripts/core/test_driver.gd), on the
# max-tuned car (scripts/tuning/max_tune.gd): from a standstill in traffic,
# flat out on a straight road, it has to reach the car's ladder top speed
# (340 km/h for the coupe) and touch nothing on the way. The "clean" driver
# queues behind traffic and settles near 200 km/h here whatever its target
# (the 195 km/h benchmark runs, 2026-10-13); flatout changes lane round it.
#
#   godot --headless --fixed-fps 120 --path . -s res://tests/core/drive_flatout.gd
#
# FLAT_SECS (default 100) of game time, FLAT_CARS (default 16, the default
# traffic) cars, FLAT_CAR the car (default the coupe). Engine heat, fuel and
# damage are on, as in the game.
#
# Fails on: any wall or car contact (driver's count and the damage model's), a
# spin, a NaN or the car under the road, an engine error, or a top speed under
# the car's ladder top.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const MaxTune := preload("res://scripts/tuning/max_tune.gd")
const RATE := 120

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var bot: TestDriver
var secs := 100.0
var top := 0.0
var ticks := 0
var fails: Array[String] = []

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	secs = float(_env("FLAT_SECS", "100"))
	OS.set_environment("NEON_CURVES", "0.0")
	OS.set_environment("NEON_HILLS", "0.0")
	OS.set_environment("NEON_CAR", _env("FLAT_CAR", "p1_coupe"))
	if not OS.get_environment("NEON_ROAD_SEED").is_valid_int():
		OS.set_environment("NEON_ROAD_SEED", "37")
	MaxTune.forced = 1
	game = Harness.boot(self, int(_env("FLAT_CARS", "16")), 300.0, int(_env("FLAT_SEED", "777")))

static func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback

func _physics_process(_delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
			p = null
			return false
		bot = TestDriver.start(game, "flatout", {"speed": 999.0})
		return false
	ticks += 1
	top = maxf(top, p.current_speed())
	if ticks % (RATE * 10) == 0:
		print("  t=%3d s  %5.1f km/h  gear %d  lane %d  gap %s  engine x%.2f" % [ticks / RATE, p.current_speed() * 3.6, p.current_gear, bot.lane,
			"-" if bot._gap == INF else "%.0f m" % bot._gap, p.health.torque_mult])
	var bad := TestDriver.sanity(p)
	if bad != "":
		fails.append(bad)
		return _end()
	if ticks >= int(secs * RATE):
		return _end()
	return false

func _end() -> bool:
	var kind := PlayerCar.chassis_kind()
	var ladder := MaxTune.ladder_top(kind)
	print("drive_flatout %s: top %.1f km/h (ladder %.0f), %s" % [kind, top * 3.6, ladder, bot.summary()])
	if bot.wall_contacts > 0 or bot.car_contacts > 0:
		fails.append("touched something (%s)" % bot.first_contact)
	if p.damage.hits > 0:
		fails.append("the damage model counted %d hits" % p.damage.hits)
	if bot.spins > 0:
		fails.append("spun %d times" % bot.spins)
	if top * 3.6 < ladder:
		fails.append("top %.1f km/h, under the car's ladder top %.0f" % [top * 3.6, ladder])
	if bot.min_gap == INF:
		fails.append("never met any traffic")
	if not logger.errors.is_empty():
		fails.append("%d engine errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	for f in fails:
		printerr("FAIL: " + f)
	print("drive_flatout: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
