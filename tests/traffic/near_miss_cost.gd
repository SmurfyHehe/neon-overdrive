extends SceneTree

# Direct cost of the traffic scripts per 120 Hz tick (traffic near-miss fix,
# CPU check). The laptop is shared, and traffic_perf's whole-tick wall time
# moves by +-0.3 ms from run to run, so a 0.03 ms budget cannot be read off it.
# This calls the traffic functions themselves in a tight loop and times only
# them:
#
#   godot --headless --fixed-fps 120 --path . -s res://tests/traffic/near_miss_cost.gd
#
# 40 cars, the player at 150 km/h in lane 1 for WARM_S seconds, then REPS times:
# TrafficManager._physics_process once, _drive on every car in the sim, _cruise
# on every car on rails. The per-tick figure is manager + sim cars x _drive /
# AI_STRIDE + rail cars x _cruise, the best of ROUNDS rounds (the least
# disturbed one). _drive is timed with the stride at 1 so every call does the
# work, then divided by the game's stride. Measurement only: no pass mark
# beyond "ran without an engine error".

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const RATE := 120
const WARM_S := 8.0
const REPS := 240
const ROUNDS := 5

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var started := false
var ticks := 0

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	OS.set_environment("NEON_CURVES", "0.0")
	OS.set_environment("NEON_HILLS", "0.0")
	OS.set_environment("NEON_POLICE", "0")
	OS.set_environment("NEON_NEAR_MISS_FILE", "user://near_miss_cost.txt")
	game = Harness.boot(self, 40, 300.0, 11, 300.0)

func _physics_process(_delta: float) -> bool:
	if not started:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
			return false
		started = true
		var tr: TrafficManager = game.get("traffic")
		if tr.cars.size() != 40:
			tr.set_car_count(40)
		TestDriver.place(p, Harness.lane_x(1), 0.0, 0.0, 150.0 / 3.6)
		p.driver = Harness.lane_driver(Harness.lane_x(1), 1.0, 150.0 / 3.6)
		return false
	ticks += 1
	if ticks < int(WARM_S * RATE):
		return false
	_measure()
	quit(1 if not logger.errors.is_empty() else 0)
	return true

func _measure() -> void:
	var tr: TrafficManager = game.get("traffic")
	var dt := 1.0 / RATE
	var stride := TrafficCar.AI_STRIDE
	var sim: Array[TrafficCar] = []
	var rail: Array[TrafficCar] = []
	for car in tr.cars:
		if car.benched:
			continue
		if car.detailed:
			sim.append(car)
		else:
			rail.append(car)
	var best_m := INF
	var best_d := INF
	var best_c := INF
	for round in ROUNDS:
		var t0 := Time.get_ticks_usec()
		for i in REPS:
			tr._physics_process(dt)
		var m := float(Time.get_ticks_usec() - t0) / REPS
		TrafficCar.AI_STRIDE = 1
		t0 = Time.get_ticks_usec()
		for i in REPS:
			for car in sim:
				car._drive(dt)
		var d := float(Time.get_ticks_usec() - t0) / float(REPS * maxi(sim.size(), 1))
		TrafficCar.AI_STRIDE = stride
		t0 = Time.get_ticks_usec()
		for i in REPS:
			for car in rail:
				car._cruise(dt)
		var c := float(Time.get_ticks_usec() - t0) / float(REPS * maxi(rail.size(), 1))
		best_m = minf(best_m, m)
		best_d = minf(best_d, d)
		best_c = minf(best_c, c)
	var per_tick := best_m + float(sim.size()) * best_d / float(stride) + float(rail.size()) * best_c
	print("NMCOST cars=%d sim=%d rail=%d manager=%.1f us/tick drive=%.2f us/call cruise=%.2f us/call (stride %d) -> traffic scripts %.4f ms per tick" % [
		tr.cars.size(), sim.size(), rail.size(), best_m, best_d, best_c, stride, per_tick / 1000.0])
	if tr.near_miss != null:
		tr.near_miss.finish()
	print("near_miss_cost: %s" % ("PASS" if logger.errors.is_empty() else "FAIL: %s" % logger.errors[0]))
