extends SceneTree

# Traffic at speed (speed feel, 2026-10-10): the real Game.tscn, 40 cars, a
# straight road, the player held at 150, 300 and 400 km/h in turn in lane 1 as
# a ghost (traffic knows where it is, nothing collides with it, so one crash
# does not end the run).
#
# Before this change the player's own lane emptied above ~250 km/h: no car was
# placed in it (10 s of closing speed is longer than the spawn band) and any
# car in it moved over from up to 290 m away.
#
# Asserts (exit code 1 on failure):
# - at 300 km/h the player still comes up on cars in their own lane: at least
#   MIN_MET_300 per km driven (a car counts when it is in the lane 100 m ahead);
# - the road carries every car up to 300 km/h and about half of them at 400;
# - at 400 km/h the lane is not empty either;
# - no engine or script errors.
# Prints cars met per km at each speed.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/traffic/speed_lane_busy.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 60
const CARS := 40
const LANE := 1
const SETTLE_TICKS := RATE * 10
const MEASURE_TICKS := RATE * 24
const MEET_AT := 100.0     # m ahead where a car in the lane counts as met
const MIN_MET_300 := 1.0   # per km
const MIN_MET_400 := 0.3
const SPEEDS := [150.0, 300.0, 400.0]

var game: Node
var fails := 0
var tick := 0
var phase := -1
var phase_tick := 0
var lane_x := 0.0
var gap_before := {}
var met := 0
var active_sum := 0
var results := {}

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	game = Harness.boot(self, CARS, 150.0, 20261010)

func _physics_process(_delta: float) -> bool:
	tick += 1
	if tick < 30:
		return false
	var p: PlayerCar = game.get("player")
	var traffic: TrafficManager = game.get("traffic")
	if phase < 0:
		lane_x = Harness.lane_x(LANE)
		var cars := 1 << (CarSpec.CAR_LAYER - 1)
		p.collision_layer = 0
		p.collision_mask &= ~cars
		for w in p.wheel_array:
			w.collision_mask &= ~cars
		Harness.move_player_to_lane(p, lane_x)
		p.driver = Harness.lane_driver(lane_x, 0.4)
		_next_phase(p)
		return false
	var target: float = SPEEDS[phase] / 3.6
	p.linear_velocity += Vector3.FORWARD * (target - p.linear_velocity.dot(Vector3.FORWARD))
	phase_tick += 1
	var pu := RoadFrame.unroll(p.global_position)
	if not Harness.finite(p) or absf(pu.x - lane_x) > 1.5:
		_check(false, "the player left its lane at %d km/h (x off by %.1f m)" % [int(SPEEDS[phase]), pu.x - lane_x])
		return _end()
	if phase_tick == SETTLE_TICKS:
		met = 0
		active_sum = 0
		gap_before.clear()
	if phase_tick > SETTLE_TICKS:
		active_sum += traffic.active_count()
		for car in traffic.cars:
			if car.benched or car.direction > 0.0:
				continue
			var u := RoadFrame.unroll(car.global_position)
			var gap := pu.z - u.z
			var id: int = car.get_instance_id()
			if gap <= MEET_AT and float(gap_before.get(id, -1.0)) > MEET_AT and absf(u.x - lane_x) < RoadChunkBuilder.LANE_W * 0.5:
				met += 1
			gap_before[id] = gap
	if phase_tick >= SETTLE_TICKS + MEASURE_TICKS:
		# speed x time, not positions: the floating origin moves those
		var km := target * float(MEASURE_TICKS) / float(RATE) / 1000.0
		var per_km := float(met) / maxf(km, 0.001)
		var active := float(active_sum) / float(MEASURE_TICKS)
		results[SPEEDS[phase]] = {"per_km": per_km, "active": active}
		print("speed_lane_busy: %3d km/h  met %2d in %.2f km = %.2f per km, %.1f of %d cars on the road" % [int(SPEEDS[phase]), met, km, per_km, active, traffic.cars.size()])
		if phase + 1 >= SPEEDS.size():
			return _end()
		_next_phase(p)
	return false

func _next_phase(p: PlayerCar) -> void:
	phase += 1
	phase_tick = 0
	Harness.launch_player(p, SPEEDS[phase] / 3.6)

func _end() -> bool:
	if results.has(300.0):
		_check(results[300.0].per_km >= MIN_MET_300, "at 300 km/h only %.2f cars per km in the player's lane (min %.1f)" % [results[300.0].per_km, MIN_MET_300])
		_check(results[300.0].active >= CARS - 2.0, "at 300 km/h only %.1f of %d cars were on the road" % [results[300.0].active, CARS])
	if results.has(400.0):
		_check(results[400.0].per_km >= MIN_MET_400, "at 400 km/h only %.2f cars per km in the player's lane (min %.1f)" % [results[400.0].per_km, MIN_MET_400])
		_check(absf(results[400.0].active - CARS * 0.5) <= 4.0, "at 400 km/h %.1f of %d cars were on the road, wanted about half" % [results[400.0].active, CARS])
	_check(results.size() == SPEEDS.size(), "the run stopped after %d of %d speeds" % [results.size(), SPEEDS.size()])
	print("speed_lane_busy: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(0 if fails == 0 else 1)
	return true
