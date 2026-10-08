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
#   S) through the bends to 0.8 m (a straight road's worst: 0.66 m)
# - no traffic car wrecks, nothing goes non-finite
# - no car's position jumps against its velocity, origin shifts included
# - no wheel ever touches a sidewalk while over the lanes: a chunk's collision
#   that lags a recycle or an origin shift lies across a curved road for a
#   tick and launches cars (RoadChunkBuilder.sync_collision)
# - the chase camera follows the road (step R4): it looks within 10 deg of
#   the road's direction and stays within 12 m of the car, through every bend
#   and origin shift
# - with hills on (CURVE_DRIVE_HILLS, tests/hill_drive.gd): the road really
#   climbs (grade over 3% somewhere), the surface the wheels meet is where the
#   road says it is, to 1 cm, at every lane centre every metre for 300 m
#   ahead, chunk joins included, and the player never leaves the ground
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
## CURVE_DRIVE_CURVES=0, 2026-10-07). A lane change on a bend runs a little
## wider: up to 0.75 m (hill_drive seed 7, 85 km/h on a 919 m bend). Bodies in
## neighbouring lanes have 1.1 m between them (RoadChunkBuilder.LANE_W).
const TRAFFIC_MAX_ERR := 0.8

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
var cam_angle := 0.0
var cam_note := ""
var cam_dist := 0.0
var traffic_errs := PackedFloat32Array()
var _noted := {}
var max_grade := 0.0
var surface_err := 0.0
var surface_note := ""
var surface_rays := 0
var air_ticks := 0
var worst_air := 0

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	# Its own knob, not NEON_CURVES: run_tests.bat may set that to 0 for the
	# older drive tests. CURVE_DRIVE_CURVES=0 runs this on a straight road to
	# compare.
	var curves := OS.get_environment("CURVE_DRIVE_CURVES")
	OS.set_environment("NEON_CURVES", curves if curves.is_valid_float() else "1.0")
	# Flat unless asked: hills have their own test (hill_drive.gd).
	var hills := OS.get_environment("CURVE_DRIVE_HILLS")
	OS.set_environment("NEON_HILLS", hills if hills.is_valid_float() else "0")
	if not OS.get_environment("NEON_ROAD_SEED").is_valid_int():
		OS.set_environment("NEON_ROAD_SEED", str(ROAD_SEED))
	game = Harness.boot(self, 0, 300.0, 777, 300.0)

func _setup() -> void:
	traffic = game.get("traffic")
	traffic.own_lanes_used = [0, 2, 3]  # the player's lane stays clear
	traffic.set_car_count(CARS)
	var p: PlayerCar = game.get("player")
	p.driver = Harness.lane_driver(Harness.lane_x(PLAYER_LANE), 1.0, CRUISE)
	var cam: Node = game.get("camera")
	if cam != null:
		cam.set("shake_enabled", false)
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
	var cam := game.get("camera") as Camera3D
	if cam != null and tick > RATE:
		var cf := -cam.global_transform.basis.z
		cf.y = 0.0
		var rf := RoadFrame.basis_at(u.z) * Vector3.FORWARD
		var ang := rad_to_deg(cf.normalized().angle_to(rf))
		if ang > cam_angle:
			cam_angle = ang
			cam_note = "%.0f m in, road heading %.1f deg" % [travelled, heading]
		cam_dist = maxf(cam_dist, cam.global_position.distance_to(p.global_position))
	if RoadFrame.has_hills():
		_check_hills(p, u)
	for car in traffic.cars:
		if not Harness.finite(car):
			return _end("non-finite state in a traffic car at tick %d" % tick)
		if car.wrecked:
			_check(false, "a traffic car wrecked at tick %d, %.0f m in" % [tick, travelled])
		if OS.get_environment("CURVE_DRIVE_DEBUG") == "1" and car.detailed and (car._wreck_t > 0.0 or car._stuck_t > 3.0) and not _noted.has(car):
			_noted[car] = true
			var du := RoadFrame.unroll(car.global_position)
			print("TROUBLE tick %d: dir %d lane %d u %s path_x %.2f speed %.1f target %.1f bend %.1f lead_gap %.1f lead_speed %.1f wreck_t %.2f stuck_t %.2f up %.3f heading %.2f wheels %s player dz %.0f grade %.3f" % [
				tick, car.direction, car.lane_i, du, car.path_x(), car.current_speed(), car.target_speed, car.bend_speed(), car.lead_gap, car.lead_speed,
				car._wreck_t, car._stuck_t, car.global_transform.basis.y.y, RoadFrame.basis_to_road(du.z, car.global_transform.basis).z.z * -car.direction,
				car.wheel_array.map(func(w): return (w.get_collider() as Node).name if w.is_colliding() else "-"), du.z - u.z,
				RoadFrame.align.grade_at(RoadFrame._chunk_of(du.z), RoadFrame._s_in_chunk(du.z, RoadFrame._chunk_of(du.z))) if RoadFrame.align != null else 0.0])
		if not car.detailed:
			continue
		for w in car.wheel_array:
			if w.is_colliding() and (w.get_collider() as Node).name.begins_with("Sidewalk") and absf(RoadFrame.unroll(w.get_collision_point()).x) < 13.5:
				_check(false, "a wheel hit %s/%s over the lanes at tick %d" % [(w.get_collider() as Node).get_parent().name, (w.get_collider() as Node).name, tick])
		var step: Vector3 = car.global_position - car.previous_global_position
		var jump := (step - car.linear_velocity * delta).length()
		worst_step = maxf(worst_step, jump)
		if jump > 0.05 and OS.get_environment("CURVE_DRIVE_DEBUG") == "1":
			print("JUMP %.3f m tick %d shifts %d step %s vel*dt %s car y %.2f wheels %s" % [jump, tick, shifts, step, car.linear_velocity * delta, car.global_position.y, car.wheel_array.map(func(w): return (w.get_collider() as Node).name if w.is_colliding() else "-")])
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

## Hills: grade seen, the player's airtime, and every SURFACE_EVERY ticks the
## road surface under the lanes against where RoadFrame says it is.
const SURFACE_EVERY := 120
func _check_hills(p: PlayerCar, u: Vector3) -> void:
	var i := RoadFrame._chunk_of(u.z)
	max_grade = maxf(max_grade, absf(RoadFrame.align.grade_at(i, RoadFrame._s_in_chunk(u.z, i))))
	var grounded := 0
	for w in p.wheel_array:
		if w.is_colliding():
			grounded += 1
	if grounded == 0 and tick > RATE:
		air_ticks += 1
		worst_air = maxi(worst_air, air_ticks)
	else:
		air_ticks = 0
	if tick % SURFACE_EVERY != 0:
		return
	var space := (game as Node3D).get_world_3d().direct_space_state
	for lane in 4:
		for side in [1.0, -1.0]:
			var x: float = RoadChunkBuilder.lane_offset(lane) * side
			for m in range(10, 300):
				var want := RoadFrame.roll(Vector3(x, 0.0, u.z - float(m)))
				var q := PhysicsRayQueryParameters3D.create(want + Vector3(0, 3, 0), want - Vector3(0, 3, 0))
				var hit := space.intersect_ray(q)
				if hit.is_empty() or not (hit.collider as Node).is_in_group("Road"):
					continue  # a car in the way
				surface_rays += 1
				var e := absf(hit.position.y - want.y)
				if e > surface_err:
					surface_err = e
					surface_note = "tick %d, %d m ahead, lane x %.1f, chunk %s" % [tick, m, x, (hit.collider as Node).get_parent().name]

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
	print("  camera: worst %.1f deg off the road (%s), furthest %.1f m from the car" % [cam_angle, cam_note, cam_dist])
	if RoadFrame.has_hills():
		print("  hills: steepest grade %.1f%%, surface worst %.4f m over %d rays (%s), longest airtime %d ticks" % [max_grade * 100.0, surface_err, surface_rays, surface_note, worst_air])
	print("  wreck recycles %d, worst step error %.3f m" % [traffic.wreck_recycle_count if traffic != null else -1, worst_step])
	_check(max_heading - min_heading > 10.0, "the road barely bent: heading only %.1f..%.1f deg" % [min_heading, max_heading])
	_check(player_err < PLAYER_MAX_ERR, "the player drifted %.2f m off its lane (%s)" % [player_err, player_note])
	_check(traffic_err < TRAFFIC_MAX_ERR, "a traffic car drifted %.2f m off its path (%s)" % [traffic_err, traffic_note])
	_check(traffic == null or traffic.wreck_recycle_count == 0, "%d wrecked cars recycled" % (traffic.wreck_recycle_count if traffic != null else 0))
	_check(cam_angle < 10.0, "the chase camera looked %.1f deg off the road (%s)" % [cam_angle, cam_note])
	_check(cam_dist < 12.0, "the chase camera got %.1f m from the car" % cam_dist)
	if RoadFrame.has_hills():
		_check(max_grade > 0.03, "the road barely climbed: steepest grade %.1f%%" % (max_grade * 100.0))
		_check(surface_rays > 1000, "only %d surface rays hit the road" % surface_rays)
		_check(surface_err < 0.01, "the road surface is %.3f m off where the road says (%s)" % [surface_err, surface_note])
		_check(worst_air == 0, "the player left the ground for %d ticks at 120 km/h" % worst_air)
	_check(shifts >= 5, "only %d origin shifts" % shifts)
	_check(logger.errors.is_empty(), "%d errors logged: %s" % [logger.errors.size(), logger.errors.slice(0, 3)])
	for f in fails:
		printerr("FAIL: " + f)
	print("curve_drive: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
