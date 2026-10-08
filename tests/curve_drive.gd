extends SceneTree

# Curves (#37 step R3): the real Game.tscn on a bending road (NEON_CURVES=1,
# fixed road seed), 16 traffic cars, and a scripted player holding the middle
# lane at about 120 km/h for 3 km, with the floating origin recentring every
# 300 m so shifts land mid-bend.
#
# Asserts (exit code 1 on failure):
# - the road really bends under the player: its heading swings more than 10 deg
# - the player holds its lane through the bends: under 1.0 m off, measured
#   across the road (RoadFrame), after a settling second
# - every full-sim traffic car holds its path (lane centre, or its lane-change
#   S) through the bends as well as it does on a straight road (0.75 m)
# - no traffic car wrecks, nothing goes non-finite
# - no car's position jumps against its velocity, origin shifts included
# - no wheel ever touches a sidewalk while over the lanes: a chunk's collision
#   that lags a recycle or an origin shift lies across a curved road for a
#   tick and launches cars (RoadChunkBuilder.sync_collision)
# - no engine or script errors logged
# Prints the worst lane errors and where they happened.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/curve_drive.gd

const Harness := preload("res://tests/traffic_harness.gd")

const RATE := 120
const CARS := 16
const DISTANCE := 3000.0
const TIMEOUT_TICKS := RATE * 180
const PLAYER_LANE := 1
const CRUISE := 33.0  # m/s, ~120 km/h
const ROAD_SEED := 37
const PLAYER_MAX_ERR := 1.0
## The straight road's own worst is 0.66 m, mid lane change (this test with
## NEON_CURVES=0, 2026-10-07); bends may not make it worse than that.
const TRAFFIC_MAX_ERR := 0.75

var logger := Harness.ErrorCounter.new()
var game: Node
var traffic: TrafficManager
var tick := 0
var fails: Array[String] = []
var start_z := 0.0
var travelled := 0.0
var last_origin := 0
var shifts := 0
var min_heading := INF
var max_heading := -INF
var player_err := 0.0
var player_note := ""
var traffic_err := 0.0
var traffic_note := ""
var worst_step := 0.0
var samples := 0
var traffic_errs := PackedFloat32Array()

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	# Its own knob, not NEON_CURVES: run_tests.bat may set that to 0 for the
	# older drive tests. CURVE_DRIVE_CURVES=0 runs this on a straight road to
	# compare.
	var curves := OS.get_environment("CURVE_DRIVE_CURVES")
	OS.set_environment("NEON_CURVES", curves if curves.is_valid_float() else "1.0")
	if not OS.get_environment("NEON_ROAD_SEED").is_valid_int():
		OS.set_environment("NEON_ROAD_SEED", str(ROAD_SEED))
	game = Harness.boot(self, 0, 300.0, 777, 300.0)

func _setup() -> void:
	traffic = game.get("traffic")
	traffic.own_lanes_used = [0, 2, 3]  # the player's lane stays clear
	traffic.set_car_count(CARS)
	var p: PlayerCar = game.get("player")
	p.driver = Harness.lane_driver(Harness.lane_x(PLAYER_LANE), 1.0, CRUISE)
	Harness.launch_player(p, CRUISE)

func _physics_process(delta: float) -> bool:
	if Engine.get_physics_frames() > TIMEOUT_TICKS:
		return _end("timed out after %d ticks, %.0f m driven" % [Engine.get_physics_frames(), travelled])
	if traffic == null:
		if game.get("player") == null:
			return false
		_setup()
		return false
	tick += 1
	var p: PlayerCar = game.get("player")
	var origin: int = game.get("origin_index")
	if origin != last_origin:
		shifts += 1
		last_origin = origin
	var u := RoadFrame.unroll(p.global_position)
	var road_z := u.z - float(origin) * RoadChunkBuilder.CHUNK_LEN  # not reset by recentring
	if tick == 1:
		start_z = road_z
	travelled = start_z - road_z
	if not Harness.finite(p):
		return _end("non-finite player state at tick %d" % tick)
	var heading := rad_to_deg(RoadFrame.heading_at(u.z))
	min_heading = minf(min_heading, heading)
	max_heading = maxf(max_heading, heading)
	if tick > RATE:
		var e := absf(u.x - Harness.lane_x(PLAYER_LANE))
		if e > player_err:
			player_err = e
			player_note = "%.0f m in, road heading %.1f deg, curvature 1/%.0f m, %.0f km/h" % [
				travelled, heading, _radius_at(u.z), Harness.kmh(p.current_speed())]
	for car in traffic.cars:
		if not Harness.finite(car):
			return _end("non-finite state in a traffic car at tick %d" % tick)
		if car.wrecked:
			_check(false, "a traffic car wrecked at tick %d, %.0f m in" % [tick, travelled])
		if not car.detailed:
			continue
		for w in car.wheel_array:
			if w.is_colliding() and (w.get_collider() as Node).name.begins_with("Sidewalk") and absf(RoadFrame.unroll(w.get_collision_point()).x) < 13.5:
				_check(false, "a wheel hit %s/%s over the lanes at tick %d" % [(w.get_collider() as Node).get_parent().name, (w.get_collider() as Node).name, tick])
		var step: Vector3 = car.global_position - car.previous_global_position
		var jump := (step - car.linear_velocity * delta).length()
		worst_step = maxf(worst_step, jump)
		if jump > 0.5:
			_check(false, "car position jumped %.2f m against its velocity at tick %d (origin shifts %d)" % [jump, tick, shifts])
		if tick > RATE * 2:
			var cu := RoadFrame.unroll(car.global_position)
			var ce := absf(cu.x - car.path_x())
			samples += 1
			traffic_errs.append(ce)
			if ce > traffic_err:
				traffic_err = ce
				traffic_note = "tick %d, %s car at %.0f km/h, %s, road curvature 1/%.0f m" % [
					tick, "own" if car.direction < 0.0 else "oncoming", Harness.kmh(car.current_speed()),
					"changing lane" if car.changing else "in lane", _radius_at(cu.z)]
	if travelled >= DISTANCE:
		return _end("")
	return false

func _radius_at(z: float) -> float:
	var k := RoadFrame.curvature(RoadFrame._chunk_of(z))
	return INF if k == 0.0 else 1.0 / k

func _check(ok: bool, msg: String) -> void:
	if not ok and fails.size() < 30:
		fails.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		fails.append(msg)
	print("curve_drive: %.0f m in %d ticks, %d origin shifts, road heading %.1f..%.1f deg" % [travelled, tick, shifts, min_heading, max_heading])
	print("  player worst %.3f m off its lane (%s)" % [player_err, player_note])
	print("  traffic worst %.3f m off its path over %d samples (%s)" % [traffic_err, samples, traffic_note])
	var st := Harness.stats(traffic_errs) if traffic_errs.size() > 0 else {}
	print("  traffic path error: %s" % st)
	print("  wreck recycles %d, worst step error %.3f m" % [traffic.wreck_recycle_count if traffic != null else -1, worst_step])
	_check(max_heading - min_heading > 10.0, "the road barely bent: heading only %.1f..%.1f deg" % [min_heading, max_heading])
	_check(player_err < PLAYER_MAX_ERR, "the player drifted %.2f m off its lane (%s)" % [player_err, player_note])
	_check(traffic_err < TRAFFIC_MAX_ERR, "a traffic car drifted %.2f m off its path (%s)" % [traffic_err, traffic_note])
	_check(traffic == null or traffic.wreck_recycle_count == 0, "%d wrecked cars recycled" % (traffic.wreck_recycle_count if traffic != null else 0))
	_check(shifts >= 5, "only %d origin shifts" % shifts)
	_check(logger.errors.is_empty(), "%d errors logged: %s" % [logger.errors.size(), logger.errors.slice(0, 3)])
	for f in fails:
		printerr("FAIL: " + f)
	print("curve_drive: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
