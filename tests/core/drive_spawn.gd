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
#
# On a bending road each speed is dropped in only where the road ahead lets
# the car carry it (Roy, 2026-10-11, #550 option A): every bend within its
# braking distance can be reached at the bot's own bend speed
# (CLEAN_LAT_ACCEL) by braking in a straight line (a full pedal, BRAKE_FULL).
# Anywhere else the drop-in asks for braking and cornering at once at the
# limit (400 km/h 150 m before a 351 m bend needs 2 g), and the test would
# measure that, not the drop-in. The car is moved there along the road, in
# short hops so the chunks under it are built. A speed no stretch allows
# (400 km/h on the default loop) is tested at the fastest one that is.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const RATE := 120
const HOLD_SECS := 3.0
const LANE_MAX_ERR := 1.0
const BURST := 3.0   # m/s over the spawn speed
const HOP_M := 120.0    # m per hop to the drop-in spot (inside CHUNKS_AHEAD/BEHIND)
const HOP_TICKS := 12   # ticks after each hop for the chunks to build
const SEARCH_AHEAD := 200   # chunks searched ahead for a drop-in spot
const SEARCH_BACK := 100    # ... and back
const CAP_STEP := 10.0      # km/h: a speed no stretch allows is tried this much lower

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
var hop_left := 0.0     # m still to move before the drop-in
var hop_wait := 0

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
	if hop_left != 0.0 or hop_wait > 0:
		return _hop()
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
	hop_left = _to_drop_in(speeds[at] / 3.6)
	if is_nan(hop_left):
		# No stretch of this road lets the bot carry it (400 km/h on the
		# default loop: its longest straight is 250 m). Roy, 2026-10-12
		# (#550): bends are tested up to the fastest speed the road allows;
		# the flat run (no DRIVE_CURVES) still tests every speed.
		var asked := speeds[at]
		while is_nan(hop_left) and speeds[at] > CAP_STEP:
			speeds[at] -= CAP_STEP
			hop_left = _to_drop_in(speeds[at] / 3.6)
		if is_nan(hop_left):
			fails.append("%d km/h: no stretch within %d chunks either way lets the car carry any speed" % [int(asked), SEARCH_AHEAD])
			return _end()
		print("drive_spawn %d km/h: no stretch of this road allows it; tested at %d km/h, the fastest it does" % [int(asked), int(speeds[at])])
	if hop_left != 0.0:
		print("drive_spawn %d km/h: dropped in %.0f m %s, where the road ahead allows it" % [int(speeds[at]), absf(hop_left), "on" if hop_left > 0.0 else "back"])
		return _hop()
	return _drop_in()

func _drop_in() -> bool:
	bot = TestDriver.start(game, "clean", {"speed": speeds[at]})
	TestDriver.place(p, Harness.lane_x(1), 0.0, 0.0, speeds[at] / 3.6)
	return false

## One hop toward the drop-in spot, standing still, then a wait for the
## chunks; the drop-in itself once there.
func _hop() -> bool:
	if hop_wait > 0:
		hop_wait -= 1
		if hop_wait == 0 and hop_left == 0.0:
			return _drop_in()
		return false
	var step := clampf(hop_left, -HOP_M, HOP_M)
	hop_left -= step
	if absf(hop_left) < 0.01:
		hop_left = 0.0
	if bot != null:
		bot.detach(p)
	p.throttle_input = 0.0
	p.brake_input = 1.0
	TestDriver.place(p, Harness.lane_x(1), step, 0.0, 0.0)
	hop_wait = HOP_TICKS
	return false

## Metres along the road (+ = on, - = back) to the nearest chunk start where
## the car can carry `v` m/s: 0.0 on a straight road or where it is already
## fine, NAN if there is none. Chunk resolution: a chunk is one arc.
func _to_drop_in(v: float) -> float:
	if RoadFrame.align == null:
		return 0.0
	var s := float(RoadFrame.origin_index) * RoadFrame.L - RoadFrame.unroll(p.global_position).z
	var here := floori(s / RoadFrame.L)
	if _carries(here, v, s - float(here) * RoadFrame.L):
		return 0.0
	for n in range(1, maxi(SEARCH_AHEAD, SEARCH_BACK) + 1):
		if n <= SEARCH_AHEAD and _carries(here + n, v, 0.0):
			return float(here + n) * RoadFrame.L + 1.0 - s
		if n <= SEARCH_BACK and _carries(here - n, v, 0.0):
			return float(here - n) * RoadFrame.L + 1.0 - s
	return NAN

## Whether a car at `into` m along chunk `i` doing `v` can slow for every bend
## ahead in time: TestDriver.bend_speed's sum, braking with a full pedal
## instead of the bot's gentler planning rate.
func _carries(i: int, v: float, into: float) -> bool:
	var look := v * v / (2.0 * TestDriver.BRAKE_FULL) + 60.0
	var j := i
	while float(j - i) * RoadFrame.L - into <= look:
		var k := absf(RoadFrame.align.curvature(j))
		if k > 1e-6:
			var d := maxf(0.0, float(j - i) * RoadFrame.L - into)
			var v_bend := sqrt(TestDriver.CLEAN_LAT_ACCEL / k)
			if sqrt(v_bend * v_bend + 2.0 * TestDriver.BRAKE_FULL * maxf(0.0, d - 20.0)) < v:
				return false
		j += 1
	return true

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
