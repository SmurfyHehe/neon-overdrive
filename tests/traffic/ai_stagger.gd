extends SceneTree

# Staggered traffic AI and hidden wheel visuals (2026-10-10).
#
# 1. Every full-sim car runs its lane controller once per TrafficCar.AI_STRIDE
#    ticks, the cars split over alternate ticks (never all on one tick), and
#    none goes more than AI_STRIDE ticks without a run.
# 2. The wheel-mesh process (Wheel._process) runs for a car exactly when it is
#    drawn: hidden and sim_only cars have it off, drawn ones on.
# 3. Behaviour is unchanged: the same traffic at stride 1 and at stride 2
#    keeps its lanes as well (mean lane error within 0.25 m) and nothing goes
#    non-finite or logs an error.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/traffic/ai_stagger.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 120
const CARS := 24
const WARMUP_TICKS := RATE * 6
const PHASE_TICKS := RATE * 20
const TIMEOUT_TICKS := (WARMUP_TICKS + PHASE_TICKS * 2) * 3
const PLAYER_LANE := 0
const PLAYER_SPEED := 28.0
const MAX_LANE_ERR_DIFF := 0.25  # runs differ by ~0.1 m on their own; this guards a gross regression

var logger := Harness.ErrorCounter.new()
var game: Node
var traffic: TrafficManager
var tick := 0
var phase := 0  # 0 warm-up, 1 stride 2, 2 stride 1
var phase_tick := 0
var fails: Array[String] = []

var last_run: Dictionary = {}  # car instance id -> last frame seen with a new _ai_last
var runs: Dictionary = {}      # car instance id -> runs this phase
var ticks_in_sim: Dictionary = {}
var max_gap := 0
var both_parities := true
var per_tick_runs := PackedInt32Array()
var wheels_on_drawn := 0
var wheels_off_hidden := 0
var wheel_mismatch := 0
var mismatch_drawn_off := 0
var mismatch_hidden_on_sim := 0
var lane_err_sum: Array[float] = [0.0, 0.0]
var lane_err_n: Array[int] = [0, 0]

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	game = Harness.boot(self, 0, 300.0, 4242)

func _setup() -> void:
	traffic = game.get("traffic")
	traffic.own_lanes_used = [1, 2, 3]
	traffic.set_car_count(CARS)
	var p: PlayerCar = game.get("player")
	p.driver = Harness.lane_driver(Harness.lane_x(PLAYER_LANE), 1.0, PLAYER_SPEED)
	Harness.move_player_to_lane(p, Harness.lane_x(PLAYER_LANE))
	TrafficCar.AI_STRIDE = 2

func _physics_process(_delta: float) -> bool:
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
	var frame := Engine.get_physics_frames()
	var p: PlayerCar = game.get("player")
	if not Harness.finite(p):
		return _end("non-finite player state at tick %d" % tick)
	for car in traffic.cars:
		if not Harness.finite(car):
			return _end("non-finite traffic car at tick %d" % tick)
	if phase == 0:
		if tick >= WARMUP_TICKS:
			phase = 1
			phase_tick = 0
			_reset_counts()
		return false
	phase_tick += 1
	var ran := 0
	for car in traffic.cars:
		var id := car.get_instance_id()
		if not car.detailed or car.benched:
			last_run.erase(id)
		if car.detailed and not car.benched:
			ticks_in_sim[id] = int(ticks_in_sim.get(id, 0)) + 1
			var seen_last: int = last_run.get(id, -1)
			if car._ai_last != seen_last:
				if seen_last >= 0 and car._ai_last - seen_last > 0:
					max_gap = maxi(max_gap, car._ai_last - seen_last)
				last_run[id] = car._ai_last
				runs[id] = int(runs.get(id, 0)) + 1
				ran += 1
			if not car.changing:
				var err := absf(RoadFrame.unroll(car.global_position).x - car.path_x())
				lane_err_sum[phase - 1] += err
				lane_err_n[phase - 1] += 1
		if car.wheel_array.size() > 0 and not car.benched:
			var on := car.wheel_array[0].is_processing()
			var drawn := car.visible and not car.sim_only
			if on != drawn:
				wheel_mismatch += 1
				if drawn:
					mismatch_drawn_off += 1
				elif car.detailed:
					mismatch_hidden_on_sim += 1
			elif drawn:
				wheels_on_drawn += 1
			else:
				wheels_off_hidden += 1
	if phase == 1:
		per_tick_runs.append(ran)
	if phase_tick >= PHASE_TICKS:
		if phase == 1:
			_check_stagger()
			phase = 2
			phase_tick = 0
			TrafficCar.AI_STRIDE = 1
			_reset_counts()
			return false
		return _finish()
	return false

func _reset_counts() -> void:
	last_run.clear()
	runs.clear()
	ticks_in_sim.clear()
	max_gap = 0
	# Start from what each car last did, so the first tick does not count them all.
	for car in traffic.cars:
		last_run[car.get_instance_id()] = car._ai_last

func _check_stagger() -> void:
	var stride := TrafficCar.AI_STRIDE
	_check(max_gap <= stride, "a car went %d ticks between controller runs, stride %d" % [max_gap, stride])
	var cars_sampled := 0
	for id in runs:
		var t := int(ticks_in_sim.get(id, 0))
		if t < RATE * 5:
			continue
		cars_sampled += 1
		var rate := float(runs[id]) / float(t)
		_check(absf(rate - 1.0 / stride) < 0.08, "car runs its controller on %.2f of its ticks, wanted %.2f" % [rate, 1.0 / stride])
	_check(cars_sampled >= 4, "only %d cars were in the sim long enough to sample" % cars_sampled)
	# Spread: no tick takes every car's run, and both halves of the cars are used.
	var worst := 0
	var total := 0
	for n in per_tick_runs:
		worst = maxi(worst, n)
		total += n
	var busy := 0
	for n in per_tick_runs:
		if n > 0:
			busy += 1
	_check(busy > per_tick_runs.size() * 9 / 10, "controller runs landed on only %d of %d ticks" % [busy, per_tick_runs.size()])
	var mean := float(total) / float(maxi(per_tick_runs.size(), 1))
	_check(float(worst) <= mean * 2.0 + 2.0, "one tick ran %d controllers, mean %.1f: not spread" % [worst, mean])
	print("stagger: stride %d, cars sampled %d, max gap %d ticks, controller runs per tick mean %.1f worst %d" % [stride, cars_sampled, max_gap, mean, worst])

func _finish() -> bool:
	_check(wheel_mismatch == 0, "%d car-ticks where the wheel process did not follow visibility" % wheel_mismatch)
	_check(wheels_on_drawn > 0, "never saw a drawn car")
	_check(wheels_off_hidden > 0, "never saw a hidden car")
	var e2: float = lane_err_sum[0] / maxf(float(lane_err_n[0]), 1.0)
	var e1: float = lane_err_sum[1] / maxf(float(lane_err_n[1]), 1.0)
	_check(lane_err_n[0] > 1000 and lane_err_n[1] > 1000, "too few lane samples (%d, %d)" % [lane_err_n[0], lane_err_n[1]])
	_check(e2 <= e1 + MAX_LANE_ERR_DIFF, "mean lane error %.3f m at stride 2 vs %.3f m at stride 1" % [e2, e1])
	print("wheels: drawn+on %d, hidden+off %d, mismatches %d (drawn but off %d, hidden but on in sim %d)" % [wheels_on_drawn, wheels_off_hidden, wheel_mismatch, mismatch_drawn_off, mismatch_hidden_on_sim])
	print("lane error: stride 2 %.3f m (%d samples), stride 1 %.3f m (%d samples)" % [e2, lane_err_n[0], e1, lane_err_n[1]])
	return _end("")

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
	print("ai_stagger: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	OS.remove_logger(logger)
	quit(0 if fails.is_empty() else 1)
	return true
