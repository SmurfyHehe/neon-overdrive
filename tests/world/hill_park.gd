extends SceneTree

# Hills (#37 step R5): the GEVP car on a slope. The real Game.tscn on a hilly,
# straight road (NEON_HILLS=1, NEON_CURVES=0, fixed road seed), no traffic.
# The player is put on the steepest stretch in the first 900 m, standing still:
# - with brake and handbrake held it holds about as well as on a flat road:
#   under 0.2 m of creep over 10 s (GEVP's hill hold, gevp_vehicle.gd
#   deviation 12). Measured 2026-10-07 on a 4.5% grade: 0.69 m without the
#   hold, 0.09 m with it. NB a braked GEVP car creeps on a FLAT road too,
#   0.40 m in 10 s on main's ground plane (HILL_PARK_HILLS=0 here): that is
#   older than hills and not this test's to fix.
# - it sits on the slope: its pitch matches the grade to 1 deg, all four
#   wheels on the road
# - let go, it rolls downhill (over 1 m in 5 s): the slope is real to the
#   physics, not just drawn
# - no engine or script errors logged
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/world/hill_park.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 60
const ROAD_SEED := 2026
const SETTLE := RATE * 2
const HOLD := RATE * 10
const ROLL := RATE * 5
const CREEP_MAX := 0.2

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var tick := 0
var fails: Array[String] = []
var grade := 0.0
var road_z := 0.0
var held_from := Vector3.ZERO
var brakes := true

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	OS.set_environment("NEON_HILLS", OS.get_environment("HILL_PARK_HILLS") if OS.get_environment("HILL_PARK_HILLS").is_valid_float() else "1.0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_ROAD_SEED", str(ROAD_SEED))
	game = Harness.boot(self, 0, 300.0, 777)

func _setup() -> void:
	p = game.get("player")
	# The steepest point in the first 900 m (the road starts level; the pool
	# rebuilds round the car wherever it is put).
	for m in range(5, 900):
		var z := -float(m)
		var i := RoadFrame._chunk_of(z)
		var g := RoadFrame.align.grade_at(i, RoadFrame._s_in_chunk(z, i)) if RoadFrame.align != null else 0.0
		if absf(g) > absf(grade):
			grade = g
			road_z = z
	p.global_transform = RoadFrame.pose(Harness.lane_x(1), 0.0, road_z, 0.0)
	# Build the road round the car now, before the next physics tick: with
	# hills there is no ground plane to stand on in the meantime. The pool
	# extends from its furthest chunk, so walk it there as a drive would.
	var walk := 0.0
	while walk > road_z:
		walk = maxf(walk - 25.0, road_z)
		game.call("_update_chunk_pool", walk)
	game.call("flush_rebuilds")  # rebuilds are spread over frames; the car needs the road now
	TrafficCar.set_moving(p, 0.0)
	p.reset_physics_interpolation()
	p.driver = func(c: Vehicle) -> void:
		c.throttle_input = 0.0
		c.steering_input = 0.0
		c.brake_input = 1.0 if brakes else 0.0
		c.handbrake_input = 1.0 if brakes else 0.0
	print("hill_park: parked at road z %.0f on a %.1f%% grade" % [road_z, grade * 100.0])

func _physics_process(_delta: float) -> bool:
	if p == null:
		if game.get("player") == null:
			return false
		_setup()
		return false
	tick += 1
	if not Harness.finite(p):
		return _end("non-finite player state at tick %d" % tick)
	if tick == SETTLE:
		held_from = p.global_position
		var pitch := rad_to_deg(asin(clampf(-p.global_transform.basis.z.y, -1.0, 1.0)))
		var want := rad_to_deg(atan(grade))
		var grounded := 0
		for w in p.wheel_array:
			if w.is_colliding():
				grounded += 1
		print("hill_park: pitch %.2f deg on a %.2f deg grade, %d wheels down" % [pitch, want, grounded])
		_check(absf(pitch - want) < 1.0, "the car sits at %.2f deg on a %.2f deg grade" % [pitch, want])
		_check(grounded == 4, "only %d wheels on the road" % grounded)
	if tick > SETTLE and tick < SETTLE + HOLD and (tick - SETTLE) % RATE == 0 and OS.get_environment("HILL_PARK_DEBUG") == "1":
		print("  t+%ds moved %.4f m, speed %.4f m/s, brake %.2f" % [(tick - SETTLE) / RATE, p.global_position.distance_to(held_from), p.linear_velocity.length(), p.brake_amount])
	if tick == SETTLE + HOLD:
		var creep := p.global_position.distance_to(held_from)
		print("hill_park: crept %.4f m in %d s with the brakes on" % [creep, HOLD / RATE])
		_check(creep < CREEP_MAX, "the braked car crept %.3f m down the slope" % creep)
		brakes = false
		held_from = p.global_position
	if tick == SETTLE + HOLD + ROLL:
		var moved := RoadFrame.unroll(p.global_position).z - RoadFrame.unroll(held_from).z
		# Downhill along the road: +z (backwards) on a rising grade, -z on a falling one.
		var downhill := moved * signf(grade)
		print("hill_park: rolled %.2f m downhill in %d s with the brakes off" % [downhill, ROLL / RATE])
		_check(downhill > 1.0, "let go on a %.1f%% grade it rolled only %.2f m downhill" % [grade * 100.0, downhill])
		return _end("")
	return false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		fails.append(msg)
	_check(absf(grade) > 0.03, "the steepest grade found was only %.1f%%" % (grade * 100.0))
	_check(logger.errors.is_empty(), "%d errors logged: %s" % [logger.errors.size(), logger.errors.slice(0, 3)])
	for f in fails:
		printerr("FAIL: " + f)
	print("hill_park: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
