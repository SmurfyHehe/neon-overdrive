extends SceneTree

# Traffic stability test (milestone 3, stage B step 3; milestone 4 traffic), at
# the game's 120 Hz tick with 80 cars and a 300 m draw distance: every car
# within 300 m of the player runs the full raycast sim (milestone 4 cars spawn
# hidden beyond it and drive in).
#
# Phase 1, "clear lane" (35 s): traffic uses own lanes 1-3 and all four
# oncoming lanes; the scripted player holds lane 0 (the passing lane) at full
# throttle and passes dense traffic at its top speed (~240 km/h). Asserts,
# every tick:
# - no NaN or infinity anywhere in the player or any car
# - the player and every full-sim car stay upright (up.y > 0.7, no flip) and
#   above the road (no fall-through)
# - the player holds its lane centre and every car its path (lane centre or
#   lane-change S; milestone 4 cars change lane within lanes 1-3)
# - nothing touches the player (no car centre inside the player's footprint)
#   and no two cars touch (every 10th tick)
# - the player reaches at least 220 km/h and holds within 10% of its top speed
#   over the last 5 s
# Phase 2, "crash" (20 s): lane 0 opens to traffic, traffic stops treating the
# player as a car to keep clear of (TrafficManager.react_to_player, milestone
# 4), and the player keeps full throttle, so it rear-ends cars at up to
# 170 km/h closing. Asserts: still finite, nobody through the floor, and no
# tunnelling (two car centres less than 0.5 m apart, i.e. one body passed
# through another). Flips and contacts are reported, not asserted, as is the
# closest approach of any two centres. (The tunnelling check used to be a
# centre-in-box test in the other car's frame with no height bound; a car
# thrown onto its side "tunnelled" into one 13 m away and failed 2 of 5
# baseline runs on 2026-10-06.)
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/traffic_stability.gd

const Harness := preload("res://tests/traffic_harness.gd")

const RATE := 120
const CARS := 80
const PHASE1_TICKS := RATE * 35
const PHASE2_TICKS := RATE * 20
const TIMEOUT_TICKS := (PHASE1_TICKS + PHASE2_TICKS) * 2
const PLAYER_LANE := 0  # the passing lane, next to the oncoming lanes
const MIN_TOP_KMH := 220.0
const MAX_TOP_KMH := 270.0

var logger := Harness.ErrorCounter.new()
var game: Node
var traffic: TrafficManager
var tick := 0
var fails: Array[String] = []
var phase := 1
var top_speed := 0.0
var tail_sum := 0.0
var tail_n := 0
var min_up := 1.0
var min_car_up := 1.0
var max_player_lane_err := 0.0
var max_car_lane_err := 0.0
var contacts := 0
var crash_min_up := 1.0
var crash_contacts := 0
var crash_top := 0.0
var crash_end_speed := 0.0
var crash_min_gap_player := INF  # closest centre-to-centre distance, player and a car
var crash_min_gap_cars := INF    # same, two traffic cars (sampled every 10th tick)
var min_y := INF

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	game = Harness.boot(self, 0, 300.0, 777)

## The scene is ready on the first tick, not inside _initialize.
func _setup() -> void:
	traffic = game.get("traffic")
	traffic.own_lanes_used = [1, 2, 3]
	traffic.set_car_count(CARS)
	var p: PlayerCar = game.get("player")
	p.driver = Harness.lane_driver(Harness.lane_x(PLAYER_LANE), 1.0)
	Harness.move_player_to_lane(p, Harness.lane_x(PLAYER_LANE))

func _physics_process(_delta: float) -> bool:
	# A tick that errors out never reaches _end, so a hard stop keeps the suite moving.
	if Engine.get_physics_frames() > TIMEOUT_TICKS:
		printerr("FAIL: timed out after ", Engine.get_physics_frames(), " ticks")
		quit(1)
		return true
	if traffic == null:
		if game.get("player") == null:
			return false
		_setup()
		return false
	tick += 1
	var p: PlayerCar = game.get("player")
	if not Harness.finite(p):
		return _end("non-finite player state at tick %d (phase %d)" % [tick, phase])
	for car in traffic.cars:
		if not Harness.finite(car):
			return _end("non-finite traffic car state at tick %d (phase %d)" % [tick, phase])
		min_y = minf(min_y, car.global_position.y)
		if car.global_position.y < -0.5:
			_check(false, "a car fell through the road at tick %d (phase %d)" % [tick, phase])
	min_y = minf(min_y, p.global_position.y)
	_check(p.global_position.y > -0.5, "player fell through the road at tick %d" % tick)

	var speed := p.current_speed()
	var up := p.global_transform.basis.y.y
	if phase == 1:
		top_speed = maxf(top_speed, speed)
		min_up = minf(min_up, up)
		_check(up > 0.7, "player flipped (up.y %.2f) at tick %d" % [up, tick])
		if tick > RATE * 3:
			var err := absf(p.global_position.x - Harness.lane_x(PLAYER_LANE))
			max_player_lane_err = maxf(max_player_lane_err, err)
			_check(err < 1.5, "player %.2f m off lane centre at tick %d" % [err, tick])
		if tick > PHASE1_TICKS - RATE * 5:
			tail_sum += speed
			tail_n += 1
		for car in traffic.cars:
			if not car.detailed:
				continue
			var cup := car.global_transform.basis.y.y
			min_car_up = minf(min_car_up, cup)
			_check(cup > 0.7, "a traffic car flipped (up.y %.2f) at tick %d" % [cup, tick])
			if tick > RATE * 2:
				# Mid lane change the car runs up to ~1 m behind its S (pure
				# pursuit cuts the curve); it is in both lanes' index then.
				var cerr := absf(car.global_position.x - car.path_x())
				max_car_lane_err = maxf(max_car_lane_err, cerr)
				var lim := 1.6 if car.changing else 1.2
				_check(cerr < lim, "a traffic car is %.2f m off its path at tick %d (changing lane %s)" % [cerr, tick, car.changing])
			if Harness.overlaps(p, car, 1.5, 3.0):
				contacts += 1
				_check(false, "a car touched the player in the clear-lane phase at tick %d" % tick)
		if tick % 10 == 0:
			_check_car_pairs(1.5, 3.0, "two cars touched at tick %d" % tick)
		if tick >= PHASE1_TICKS:
			_check(Harness.kmh(top_speed) >= MIN_TOP_KMH, "top speed %.0f km/h, wanted at least %.0f" % [Harness.kmh(top_speed), MIN_TOP_KMH])
			_check(Harness.kmh(top_speed) <= MAX_TOP_KMH, "top speed %.0f km/h, above %.0f" % [Harness.kmh(top_speed), MAX_TOP_KMH])
			var tail := tail_sum / maxi(tail_n, 1)
			_check(tail >= top_speed * 0.9, "speed over the last 5 s averaged %.0f km/h, under 90%% of the top %.0f" % [Harness.kmh(tail), Harness.kmh(top_speed)])
			print("traffic_stability phase 1: top %.1f km/h, last 5 s mean %.1f km/h, player min up.y %.3f, max lane err player %.2f m / traffic %.2f m, contacts %d, cars full-sim %d/%d, spawns %d recycles %d deferred %d" % [
				Harness.kmh(top_speed), Harness.kmh(tail), min_up, max_player_lane_err, max_car_lane_err, contacts, traffic.detailed_count(), traffic.cars.size(), traffic.spawn_count, traffic.recycle_count, traffic.deferred_count])
			phase = 2
			traffic.own_lanes_used = []
			traffic.react_to_player = false
	else:
		crash_top = maxf(crash_top, speed)
		crash_min_up = minf(crash_min_up, up)
		crash_end_speed = speed
		for car in traffic.cars:
			if not car.detailed:
				continue
			if Harness.overlaps(p, car, 1.5, 3.0):
				crash_contacts += 1
			crash_min_gap_player = minf(crash_min_gap_player, p.global_position.distance_to(car.global_position))
			if Harness.tunnelled(p, car):
				_check(false, "a car tunnelled into the player at tick %d (centres %.2f m apart)" % [tick, p.global_position.distance_to(car.global_position)])
		if tick % 10 == 0:
			_check_car_pairs(0.0, 0.0, "a car tunnelled into another at tick %d" % tick, true)
		if tick >= PHASE1_TICKS + PHASE2_TICKS:
			print("traffic_stability phase 2 (crash): top %.1f km/h, end speed %.1f km/h, player min up.y %.3f, ticks in contact %d, min y %.3f m, closest centres: player-car %.2f m, car-car %.2f m" % [
				Harness.kmh(crash_top), Harness.kmh(crash_end_speed), crash_min_up, crash_contacts, min_y, crash_min_gap_player, crash_min_gap_cars])
			return _end("")
	return false

## Any two full-sim cars touching (box test of half_x x half_z) or, with
## `deep`, one through the other (centres under 0.5 m apart).
func _check_car_pairs(half_x: float, half_z: float, msg: String, deep := false) -> void:
	var cars := traffic.cars
	for i in cars.size():
		if not cars[i].detailed:
			continue
		for j in range(i + 1, cars.size()):
			if not cars[j].detailed:
				continue
			if deep:
				crash_min_gap_cars = minf(crash_min_gap_cars, cars[i].global_position.distance_to(cars[j].global_position))
			var hit: bool = Harness.tunnelled(cars[i], cars[j]) if deep else Harness.overlaps(cars[i], cars[j], half_x, half_z)
			if hit:
				_check(false, msg)
				return

func _check(ok: bool, msg: String) -> void:
	if not ok and fails.size() < 50:
		fails.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		fails.append(msg)
	for e in logger.errors:
		fails.append("logged error: " + e)
	for f in fails:
		printerr("FAIL: ", f)
	print("errors=%d warnings=%d" % [logger.errors.size(), logger.warnings])
	print("traffic_stability: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	OS.remove_logger(logger)
	quit(0 if fails.is_empty() else 1)
	return true
