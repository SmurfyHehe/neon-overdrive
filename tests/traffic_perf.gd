extends SceneTree

# Traffic perf test (milestone 3, stage B step 3): physics cost per tick at the
# game's 120 Hz with 0, 20, 40 and 80 traffic cars, all in the full raycast
# sim, then 80 cars with the draw distance at 150 m (cars beyond it frozen).
#
# What is measured: the wall-clock time from one physics tick to the next,
# taken at the top of the SceneTree's _physics_process (the first thing that
# runs in a tick). Headless with --fixed-fps the ticks run back to back with
# no rendering and no pacing, so that gap is the CPU cost of one full tick:
# every node's _physics_process (the GEVP vehicle sim of the player and every
# full-sim car, the lane controllers, the aero model, the spawner) plus the
# physics server step (raycasts, body collisions) and the engine's per-frame
# overhead. So these numbers INCLUDE the real raycast vehicle cost and EXCLUDE
# all rendering. (Performance.TIME_PHYSICS_PROCESS was tried first and reported
# more than the wall time per tick in this mode, so it is not used.)
#
# The scripted player holds lane 3 (the outermost own lane, 9 m from the
# oncoming traffic) at full throttle, lifting at MAX_SPEED (198 km/h); traffic
# uses own lanes 0-1 and all four oncoming lanes, so lane 2 is an empty buffer
# beside the player. The count is changed live between phases (set_car_count,
# the pause-menu slider path).
#
# Why not the old set-up (2026-10-06): the player held lane 0, next to the
# oncoming lanes, flat out at 246 km/h with traffic in lanes 1-3. With 80 cars it
# was knocked across the road, spent the rest of the run wrecked at 0 km/h, and
# the test still said PASS; the timings of a wrecked player are not the cost of
# driving. Moving it to lane 3 did not cure it: lanes are 2.3 m and cars 1.6 m
# wide, and at 246 km/h the pure-pursuit lane keeper (traffic_car.gd lane_steer)
# is too weak to hold a lane, so in about half the runs the player drifted
# 1-6 m and went off the road even with nothing beside it. At 198 km/h the lane
# error is 0.03 m in every phase. (Per-tick cost does not depend on the
# player's speed; only the spawn/recycle rate does.)
# Each phase: 2 s warm-up, 10 s measured. Per phase it also reports the
# player's lane error, whether anything touched the player, and the speed, so
# a crash during a phase is visible next to its timing.
#
# Asserts (exit code 1): the car count is right in each phase, the player kept
# moving and was still doing at least MIN_KMH at the end of every phase (and,
# after the first phase, throughout every measured window), no engine or script
# errors. The timings are reported, not asserted:
# they are machine dependent. The 120 Hz budget line (8.33 ms) is printed for
# reading them against.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/traffic_perf.gd

const Harness := preload("res://tests/traffic_harness.gd")

const RATE := 120
const WARMUP_TICKS := RATE * 2
const MEASURE_TICKS := RATE * 10
const TIMEOUT_TICKS := (WARMUP_TICKS + MEASURE_TICKS) * 6 * 2
const BUDGET_MS := 1000.0 / RATE
const PHASES := [
	{"cars": 0, "detail": 300.0},
	{"cars": 16, "detail": 150.0},  # the default since traffic milestone 4
	{"cars": 20, "detail": 300.0},
	{"cars": 40, "detail": 300.0},
	{"cars": 80, "detail": 300.0},
	{"cars": 80, "detail": 150.0},
]
const PLAYER_LANE := 3  # the outermost own lane; traffic keeps to own lanes 0-1
const TRAFFIC_OWN_LANES: Array[int] = [0, 1]
## A healthy run holds 160-250 km/h in every phase (163 km/h at the end of the
## 12 s from standstill in phase 0); a wrecked player sits near 0.
const MIN_KMH := 150.0
## The player lifts at this speed (m/s, 198 km/h). Flat out (246 km/h) the
## pure-pursuit lane keeper is too weak to hold a lane in 80-car traffic and
## the run ends off the road in some runs (see the header).
const MAX_SPEED := 55.0

var logger := Harness.ErrorCounter.new()
var game: Node
var traffic: TrafficManager
var tick := 0
var phase := -1
var phase_start := 0
var samples: PackedFloat32Array = []
var last_usec := 0
var full_sim_min := 0
var full_sim_sum := 0
var lane_err_max := 0.0
var contacts := 0
var first_contact := ""
var min_speed := INF
var fails: Array[String] = []
var results: Array[Dictionary] = []
var start_z := 0.0

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	game = Harness.boot(self, 0, 300.0, 777)

## The scene is ready on the first tick, not inside _initialize.
func _setup() -> void:
	traffic = game.get("traffic")
	traffic.own_lanes_used = TRAFFIC_OWN_LANES
	var p: PlayerCar = game.get("player")
	p.driver = Harness.lane_driver(Harness.lane_x(PLAYER_LANE), 1.0, MAX_SPEED)
	Harness.move_player_to_lane(p, Harness.lane_x(PLAYER_LANE))
	start_z = p.global_position.z
	print("traffic_perf: physics engine %s, %d Hz, budget %.2f ms/tick, cpu %s" % [
		ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT"), RATE, BUDGET_MS, OS.get_processor_name()])
	_next_phase()

func _next_phase() -> void:
	phase += 1
	if phase >= PHASES.size():
		return
	var cfg: Dictionary = PHASES[phase]
	traffic.detail_distance = cfg.detail
	traffic.set_car_count(cfg.cars)
	phase_start = tick
	samples.clear()
	full_sim_min = 1 << 30
	full_sim_sum = 0
	lane_err_max = 0.0
	contacts = 0
	first_contact = ""
	min_speed = INF

func _physics_process(_delta: float) -> bool:
	# A tick that errors out never reaches _end, so a hard stop keeps the suite moving.
	if Engine.get_physics_frames() > TIMEOUT_TICKS:
		printerr("FAIL: timed out after ", Engine.get_physics_frames(), " ticks")
		quit(1)
		return true
	var now := Time.get_ticks_usec()
	if traffic == null:
		if game.get("player") == null:
			return false
		_setup()
		last_usec = now
		return false
	tick += 1
	var p: PlayerCar = game.get("player")
	var waited := tick - phase_start
	var cfg: Dictionary = PHASES[phase]
	if traffic.cars.size() != cfg.cars:
		_check(false, "phase %d has %d cars, wanted %d" % [phase, traffic.cars.size(), cfg.cars])
	if waited > WARMUP_TICKS:
		samples.append(float(now - last_usec) / 1000.0)
		full_sim_min = mini(full_sim_min, traffic.detailed_count())
		full_sim_sum += traffic.detailed_count()
		lane_err_max = maxf(lane_err_max, absf(p.global_position.x - Harness.lane_x(PLAYER_LANE)))
		min_speed = minf(min_speed, p.current_speed())
		for car in traffic.cars:
			if car.detailed and Harness.overlaps(p, car, 1.5, 3.0):
				contacts += 1
				if first_contact == "":
					first_contact = "first contact at %.1f s: %s car in lane x=%.2f, player x=%.2f" % [
						float(waited) / RATE, "own" if car.direction < 0 else "oncoming", car.lane_x, p.global_position.x]
				break
	last_usec = now
	if waited >= WARMUP_TICKS + MEASURE_TICKS:
		var s := Harness.stats(samples)
		results.append({"cars": cfg.cars, "detail": cfg.detail, "mean": s.mean, "p50": s.p50, "p95": s.p95, "max": s.max,
			"full_sim": full_sim_min, "full_sim_mean": float(full_sim_sum) / samples.size(), "speed": Harness.kmh(p.current_speed()), "min_speed": Harness.kmh(min_speed), "lane_err": lane_err_max,
			"contacts": contacts, "first_contact": first_contact})
		var r: Dictionary = results[results.size() - 1]
		_check(r.speed >= MIN_KMH, "phase %d (%d cars, %.0f m): the player ended at %.0f km/h, under %.0f (wrecked? %d ticks in contact, lane error %.2f m)" % [
			phase, cfg.cars, cfg.detail, r.speed, MIN_KMH, r.contacts, r.lane_err])
		if phase > 0:
			_check(r.min_speed >= MIN_KMH, "phase %d (%d cars, %.0f m): the player dropped to %.0f km/h, under %.0f (%d ticks in contact, lane error %.2f m)" % [
				phase, cfg.cars, cfg.detail, r.min_speed, MIN_KMH, r.contacts, r.lane_err])
		_next_phase()
		if phase >= PHASES.size():
			return _end("")
	return false

func _check(ok: bool, msg: String) -> void:
	if not ok and fails.size() < 20:
		fails.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		fails.append(msg)
	var p: PlayerCar = game.get("player")
	_check(absf(p.global_position.z - start_z) > 100.0 or game.get("recenter_count") > 0, "the player barely moved")
	print("traffic_perf: wall ms per 120 Hz tick, headless --fixed-fps (real raycast vehicle sim + physics server, no rendering), %d ticks per phase" % MEASURE_TICKS)
	print("  cars  draw_dist  full_sim    mean    p50    p95    max   budget   player (min)       lane_err  contacts")
	var base := 0.0
	for r in results:
		if r.cars == 0:
			base = r.mean
		# Per full-sim car, over the mean full-sim count (milestone 4 cars spawn
		# hidden beyond the draw distance, so not every car is full-sim all the time).
		var per_car: float = (r.mean - base) / r.full_sim_mean if r.cars > 0 and r.full_sim_mean > 0.0 else NAN
		print("  %4d   %5.0f m   %4d     %6.2f %6.2f %6.2f %6.2f   %s   %4.0f (%4.0f) km/h   %.2f m   %d%s%s" % [
			r.cars, r.detail, r.full_sim, r.mean, r.p50, r.p95, r.max,
			"under" if r.mean <= BUDGET_MS else "OVER ", r.speed, r.min_speed, r.lane_err, r.contacts,
			"" if is_nan(per_car) else "   (%.3f ms per full-sim car, %.1f full-sim on average)" % [per_car, r.full_sim_mean],
			"" if r.first_contact == "" else "   " + r.first_contact])
	for e in logger.errors:
		fails.append("logged error: " + e)
	for f in fails:
		printerr("FAIL: ", f)
	print("errors=%d warnings=%d" % [logger.errors.size(), logger.warnings])
	print("traffic_perf: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	OS.remove_logger(logger)
	quit(0 if fails.is_empty() else 1)
	return true
