extends SceneTree

# Shared test driver, crashing on purpose (scripts/core/test_driver.gd, mode
# "aim"): the bot is pointed at a wall, the kerb, the centre barrier and at
# traffic cars from behind, from the side and head-on, and the game has to
# stay sane through every hit.
#
#   godot --headless --fixed-fps 120 --path . -s res://tests/core/drive_crash.gd
#
# Every scenario runs at each speed in DRIVE_CRASH_SPEEDS (km/h, default "120";
# the long run in run_tests.bat's full tier uses "60,150,250,350").
# DRIVE_CRASH_ONLY=<name> runs one scenario.
#
# Fails on: the hit not happening (wall and car scenarios), a NaN, the car
# under the road, the car through the out-of-bounds wall, an engine error.
# The barrier scenario only reports what it met: on some chunks the centre
# line has no barrier at all.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const RATE := 120
const RUN_SECS := 7.0       # a scenario's time limit
const AFTER_SECS := 1.0     # kept running this long after the first touch
const SCENARIOS := ["wall", "wall_square", "kerb", "barrier", "car_rear", "car_side", "car_head_on"]

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var traffic: TrafficManager
var bot: TestDriver
var todo: Array = []   # [scenario, km/h]
var at := -1
var tick := 0
var hit_tick := -1
var off_road := false
var wall_x := 0.0
var min_x := INF
var hits0 := 0
var fails: Array[String] = []

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	var only := OS.get_environment("DRIVE_CRASH_ONLY")
	var speeds := OS.get_environment("DRIVE_CRASH_SPEEDS")
	for s in (speeds if speeds != "" else "120").split(",", false):
		for sc in SCENARIOS:
			if only == "" or only == sc:
				todo.append([sc, float(s)])
	game = Harness.boot(self, 0, 300.0, 4242, 1e7)

func _physics_process(_delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
			p = null
			return false
		traffic = game.get("traffic")
		traffic.react_to_player = false
		traffic.set_car_count(1)
		return false
	if traffic.cars.is_empty():
		return false
	if at < 0:
		return _next()
	tick += 1
	var bad := TestDriver.sanity(p)
	var u := RoadFrame.unroll(p.global_position)
	if bad == "" and absf(u.x) > wall_x + 2.5:
		bad = "car is through the out-of-bounds wall (x %.1f, wall %.1f)" % [u.x, wall_x]
	if bad != "":
		fails.append("%s: %s" % [_name(), bad])
		return _end()
	if OS.get_environment("DRIVE_DEBUG") == "1" and tick % 30 == 0:
		print("  t=%.2f v=%.0f x=%.2f thr=%.2f brk=%.2f steer=%.2f gear=%d rpm=%.0f limp=%s" % [tick / float(RATE), p.current_speed() * 3.6, u.x,
			p.throttle_input, p.brake_input, p.steer_fraction(), p.current_gear, p.motor_rpm, p.limp.is_limping()])
		var cu := RoadFrame.unroll(traffic.cars[0].global_position)
		print("      car dx=%.2f ahead=%.1f v=%.0f detailed=%s contacts=%d" % [cu.x - u.x, u.z - cu.z, traffic.cars[0].lane_speed() * 3.6, traffic.cars[0].detailed, p.get_contact_count()])
	off_road = off_road or p.is_off_road()
	min_x = minf(min_x, u.x)
	if hit_tick < 0 and (bot.wall_contacts > 0 or bot.car_contacts > 0):
		hit_tick = tick
	if (hit_tick >= 0 and tick - hit_tick > int(AFTER_SECS * RATE)) or tick > int(RUN_SECS * RATE):
		_close()
		return _next()
	return false

func _name() -> String:
	return "%s at %d km/h" % [todo[at][0], int(todo[at][1])]

func _next() -> bool:
	at += 1
	if at >= todo.size():
		return _end()
	tick = 0
	hit_tick = -1
	off_road = false
	min_x = INF
	p.damage.garage_repair(null)
	hits0 = p.damage.hits
	p.health.repair()
	p.fuel.litres = FuelTank.CAPACITY_L
	var kind: String = todo[at][0]
	var v: float = todo[at][1] / 3.6
	# Back to a known spot on the road first: the last scenario left the car anywhere.
	TestDriver.place(p, Harness.lane_x(1), 30.0, 0.0, 0.0)
	var u := RoadFrame.unroll(p.global_position)
	wall_x = _wall_face(u)
	var car: TrafficCar = traffic.cars[0]
	bot = TestDriver.start(game, "aim", {"speed": todo[at][1]})
	# The target car out of the way unless this scenario uses it.
	car.place(TrafficManager.lane_centre(3, true), 1.0, u.z + 250.0, car.rest_y, 20.0)
	match kind:
		"wall":   # 30 degrees into the right-hand wall
			TestDriver.place(p, Harness.lane_x(3), 0.0, 0.0, v)
			bot.aim_point = RoadFrame.roll(Vector3(wall_x + 3.0, u.y, u.z - (wall_x + 3.0 - Harness.lane_x(3)) / tan(deg_to_rad(30.0))))
		"wall_square":   # nearly square on
			TestDriver.place(p, Harness.lane_x(1), 0.0, deg_to_rad(80.0), v)
			bot.aim_point = RoadFrame.roll(Vector3(wall_x + 3.0, u.y, u.z - 2.0))
		"kerb":   # a shallow run up onto the sidewalk
			TestDriver.place(p, Harness.lane_x(3), 0.0, 0.0, v)
			bot.aim_point = RoadFrame.roll(Vector3(16.0, u.y, u.z - 60.0))
		"barrier":   # across the centre line
			TestDriver.place(p, Harness.lane_x(1), 0.0, 0.0, v)
			bot.aim_point = RoadFrame.roll(Vector3(-1.0, u.y, u.z - 40.0))
		"car_rear":
			TestDriver.place(p, Harness.lane_x(2), 0.0, 0.0, v)
			car.place(Harness.lane_x(2), -1.0, u.z - 45.0, car.rest_y, v * 0.5)
			car.target_speed = v * 0.5   # or it speeds up to its lane's pace and a slow player never catches it
			bot.aim_node = car
		"car_side":
			TestDriver.place(p, Harness.lane_x(1), 0.0, 0.0, v)
			# Alongside, a nose ahead: further forward and the bot just tucks in behind it.
			car.place(Harness.lane_x(2), -1.0, u.z - 1.5, car.rest_y, v)
			car.target_speed = v
			bot.aim_node = car
		"car_head_on":
			TestDriver.place(p, TrafficManager.lane_centre(1, true), 0.0, 0.0, v)
			car.place(TrafficManager.lane_centre(1, true), 1.0, u.z - 120.0, car.rest_y, 22.0)
			bot.aim_node = car
	return false

func _close() -> void:
	var kind: String = todo[at][0]
	var what := "nothing"
	if bot.wall_contacts > 0 or bot.car_contacts > 0:
		what = bot.first_contact
	print("drive_crash %s: hit %s; off road %s; damage hits %d; ended at %.0f km/h, %.0f deg from upright" % [
		_name(), what, "yes" if off_road else "no", p.damage.hits - hits0, p.linear_velocity.length() * 3.6,
		rad_to_deg(acos(clampf(p.global_transform.basis.y.y, -1.0, 1.0)))])
	match kind:
		"wall", "wall_square":
			if bot.wall_contacts == 0:
				fails.append("%s: never reached the wall" % _name())
		"kerb":
			if not off_road:
				fails.append("%s: never left the road" % _name())
		"barrier":
			print("  barrier: %s" % ("stopped by it at x %.1f (%s)" % [min_x, bot.first_contact] if bot.wall_contacts > 0 and min_x > -3.0
				else "nothing solid on the centre line here: the car crossed it and reached x %.1f" % min_x))
		_:
			if bot.car_contacts == 0:
				fails.append("%s: never touched the car" % _name())

## The inner face of the right-hand out-of-bounds wall nearest the car, in
## road space (tests/car/wall_hit.gd's finder, which reads world x).
func _wall_face(u: Vector3) -> float:
	var found := []
	var stack: Array = [game]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name == "BoundaryOwn":
			found.append(n)
		else:
			stack.append_array(n.get_children())
	var best := 17.6
	var best_dz := INF
	for b in found:
		for c in (b as Node).get_children():
			var col := c as CollisionShape3D
			if col == null:
				continue
			var cu := RoadFrame.unroll(col.global_position)
			var dz := absf(cu.z - u.z)
			if dz < best_dz:
				best_dz = dz
				best = cu.x - (col.shape as BoxShape3D).size.x / 2.0
	return best

func _end() -> bool:
	if not logger.errors.is_empty():
		fails.append("%d engine errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	for f in fails:
		printerr("FAIL: " + f)
	print("drive_crash: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
