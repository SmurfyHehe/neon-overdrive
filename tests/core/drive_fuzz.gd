extends SceneTree

# Shared test driver, mode "fuzz" (scripts/core/test_driver.gd): seeded random
# key presses through the real key path (PlayerCar.apply_keys), in traffic.
# Whatever the keys do, the game has to stay sane.
#
#   godot --headless --fixed-fps 120 --path . -s res://tests/core/drive_fuzz.gd
#
# One run per seed in DRIVE_FUZZ_SEEDS (default "1,2"), DRIVE_SECS (default
# 8) of game time each, among DRIVE_CARS (default 12) cars. A failure names
# the seed and the tick, and the same seed presses the same keys again:
#   DRIVE_FUZZ_SEEDS=<seed> godot ... -s res://tests/core/drive_fuzz.gd
# (the keys repeat exactly; traffic around the car may not).
#
# Fails on: an engine error, a NaN, the car under the road, or two drivers
# with the same seed pressing different keys.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const RATE := 120

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var bot: TestDriver
var seeds: Array[int] = []
var secs := 8.0
var at := -1
var tick := 0
var top := 0.0
var fails: Array[String] = []

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	var s := OS.get_environment("DRIVE_FUZZ_SEEDS")
	for x in (s if s != "" else "1,2").split(",", false):
		seeds.append(int(x))
	var sec := OS.get_environment("DRIVE_SECS")
	secs = float(sec) if sec.is_valid_float() else 8.0
	var cars := OS.get_environment("DRIVE_CARS")
	_same_seed_same_keys()
	game = Harness.boot(self, int(cars) if cars.is_valid_int() else 12, 300.0, 99)

# The repeatability the mode promises: the key stream depends on the seed only.
func _same_seed_same_keys() -> void:
	var a := TestDriver.new()
	var b := TestDriver.new()
	var c := TestDriver.new()
	a.configure("fuzz", {"seed": 7})
	b.configure("fuzz", {"seed": 7})
	c.configure("fuzz", {"seed": 8})
	var differs := false
	for i in 2000:
		var ka := a.random_keys()
		if ka != b.random_keys():
			fails.append("two fuzz drivers with seed 7 pressed different keys at tick %d" % i)
			return
		differs = differs or ka != c.random_keys()
	if not differs:
		fails.append("fuzz seeds 7 and 8 pressed the same keys")

func _physics_process(_delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
			p = null
			return false
		return _next()
	tick += 1
	top = maxf(top, p.linear_velocity.length())
	var bad := TestDriver.sanity(p)
	if bad != "":
		fails.append("seed %d, tick %d: %s" % [seeds[at], tick, bad])
		return _end()
	if tick >= int(secs * RATE):
		print("drive_fuzz seed %d: top %.0f km/h, %s" % [seeds[at], top * 3.6, bot.summary()])
		return _next()
	return false

func _next() -> bool:
	at += 1
	if at >= seeds.size():
		return _end()
	tick = 0
	top = 0.0
	p.damage.garage_repair(null)
	p.health.repair()
	p.fuel.litres = FuelTank.CAPACITY_L
	p.set_transmission_mode(PlayerCar.Transmission.AUTO)
	TestDriver.place(p, Harness.lane_x(1), 0.0, 0.0, 30.0)
	bot = TestDriver.start(game, "fuzz", {"seed": seeds[at]})
	return false

func _end() -> bool:
	if not logger.errors.is_empty():
		fails.append("%d engine errors (seed %d), first: %s" % [logger.errors.size(), seeds[clampi(at, 0, seeds.size() - 1)], logger.errors[0]])
	for f in fails:
		printerr("FAIL: " + f)
	print("drive_fuzz: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
