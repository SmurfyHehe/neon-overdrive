extends SceneTree

# Near-band traffic test (2026-10-09): only cars within
# TrafficManager.physics_distance of the player run the raycast sim; the rest
# drive on rails, drawn inside the draw distance. In the real Game.tscn at the
# game's 120 Hz, default car count and draw distance, all lanes open, the
# scripted player holds lane 1 at 160 km/h for 40 s, passing own-direction
# traffic and meeting the oncoming flow, so cars cross the band edge both ways
# all the time. Asserts:
# - cars do cross the band both ways (into the sim and back onto rails)
# - no drawn car jumps at a hand-over: its step over the tick stays within
#   JUMP_M of what its speed says, and it turns no more than TURN_RAD
# - the band is respected: no car on rails inside it (one tick of slack), no
#   car in the sim beyond its outer edge unless it is not fit for the rails
#   (crashed or knocked off its path: TrafficCar.can_rail)
# - nothing touches the player, no two sim cars touch
# - no NaN, no engine or script errors
# Reports the average number of cars in the sim against the car count.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/traffic_near_band.gd

const Harness := preload("res://tests/traffic_harness.gd")

const RATE := 120
const KMH := 1.0 / 3.6
const RUN_TICKS := RATE * 40
const WARMUP_TICKS := RATE * 2
const TIMEOUT_TICKS := RUN_TICKS * 3
const PLAYER_LANE := 1
const PLAYER_KMH := 160.0
## A drawn car may move this much more or less than its speed says in one tick.
const JUMP_M := 0.25
## ... and turn this much in one tick (a car on a lane-change S turns ~0.002).
const TURN_RAD := 0.03

var logger := Harness.ErrorCounter.new()
var game: Node
var traffic: TrafficManager
var p: PlayerCar
var tick := 0
var fails: Array[String] = []

var last_pos := {}
var last_basis := {}
var last_detailed := {}
var last_events := 0
var into_sim := 0
var onto_rails := 0
var worst_jump := 0.0
var worst_jump_note := ""
var worst_turn := 0.0
var held_in_sim := 0
var sim_sum := 0
var sim_n := 0
var player_contacts := 0
var pair_contacts := 0
var speed_sum := 0.0

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	game = Harness.boot(self, TrafficSettings.CAR_COUNT_DEFAULT, TrafficSettings.DETAIL_DEFAULT, 9191, 8000.0)

func _physics_process(_delta: float) -> bool:
	if Engine.get_physics_frames() > TIMEOUT_TICKS:
		return _end("timed out")
	if traffic == null:
		if game.get("player") == null:
			return false
		traffic = game.get("traffic")
		p = game.get("player")
		Harness.move_player_to_lane(p, Harness.lane_x(PLAYER_LANE))
		Harness.launch_player(p, PLAYER_KMH * KMH)
		p.driver = Harness.lane_driver(Harness.lane_x(PLAYER_LANE), 1.0, PLAYER_KMH * KMH)
		return false
	tick += 1
	if not Harness.finite(p):
		return _end("non-finite player state at tick %d" % tick)
	var dt := 1.0 / RATE
	# A respawn teleports a car on purpose: skip the jump check on such ticks.
	var events := traffic.spawn_count + traffic.recycle_count + traffic.deferred_count
	var respawned := events != last_events
	last_events = events
	var pz := RoadFrame.unroll(p.global_position).z
	var n_sim := 0
	for car in traffic.cars:
		if not Harness.finite(car):
			return _end("non-finite traffic state at tick %d" % tick)
		var d := absf(RoadFrame.unroll(car.global_position).z - pz)
		if car.detailed:
			n_sim += 1
		if last_detailed.has(car):
			var was: bool = last_detailed[car]
			if car.detailed and not was:
				into_sim += 1
			elif was and not car.detailed:
				onto_rails += 1
			if car.shown and not respawned and tick > 1:
				var step: float = (car.global_position - last_pos[car]).length()
				var err := absf(step - absf(car.lane_speed()) * dt)
				if err > worst_jump:
					worst_jump = err
					worst_jump_note = "tick %d, %s, %.0f m from the player, %s" % [tick, "sim" if car.detailed else "rails",
						d, "into the sim" if car.detailed and not was else ("onto rails" if was and not car.detailed else "no hand-over")]
				if car.detailed != was:
					var turn: float = (last_basis[car] as Basis).get_rotation_quaternion().angle_to(car.global_transform.basis.get_rotation_quaternion())
					worst_turn = maxf(worst_turn, turn)
		last_pos[car] = car.global_position
		last_basis[car] = car.global_transform.basis
		last_detailed[car] = car.detailed
		if tick > WARMUP_TICKS:
			if not car.detailed and d < traffic.physics_distance - 5.0 and car.global_position.z < 5000.0:
				_check(false, "a car on rails %.1f m from the player at tick %d" % [d, tick])
			if car.detailed and d > traffic.physics_distance + TrafficManager.PHYSICS_HYSTERESIS + 5.0:
				if car.can_rail():
					_check(false, "a railable car still in the sim %.1f m from the player at tick %d" % [d, tick])
				else:
					held_in_sim += 1
			if car.detailed and Harness.overlaps(p, car, 1.5, 3.0):
				player_contacts += 1
	if tick > WARMUP_TICKS:
		sim_sum += n_sim
		sim_n += 1
		speed_sum += p.current_speed()
		if tick % 10 == 0:
			var cars := traffic.cars
			for i in cars.size():
				if not cars[i].detailed:
					continue
				for j in range(i + 1, cars.size()):
					if cars[j].detailed and Harness.overlaps(cars[i], cars[j], 1.5, 3.0):
						pair_contacts += 1
	if tick >= RUN_TICKS:
		return _end("")
	return false

func _check(ok: bool, msg: String) -> void:
	if not ok and fails.size() < 30:
		fails.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		fails.append(msg)
	var mean_kmh := Harness.kmh(speed_sum / maxi(sim_n, 1))
	print("traffic_near_band: %d cars, draw %.0f m, physics band %.0f m (+%.0f out), player lane %d at %.0f km/h (mean %.0f)" % [
		traffic.cars.size() if traffic else 0, traffic.detail_distance if traffic else 0.0, traffic.physics_distance if traffic else 0.0,
		TrafficManager.PHYSICS_HYSTERESIS, PLAYER_LANE, PLAYER_KMH, mean_kmh])
	print("traffic_near_band: in the sim %.1f cars on average; hand-overs into the sim %d, onto rails %d; car-ticks held in the sim past the band (not railable) %d" % [
		float(sim_sum) / maxi(sim_n, 1), into_sim, onto_rails, held_in_sim])
	print("traffic_near_band: worst drawn step error %.3f m (%s), worst turn at a hand-over %.4f rad; player contacts %d, car pairs touching %d" % [
		worst_jump, worst_jump_note, worst_turn, player_contacts, pair_contacts])
	_check(into_sim > 0 and onto_rails > 0, "no hand-overs both ways (into the sim %d, onto rails %d)" % [into_sim, onto_rails])
	_check(worst_jump < JUMP_M, "a drawn car jumped %.3f m in one tick (%s)" % [worst_jump, worst_jump_note])
	_check(worst_turn < TURN_RAD, "a drawn car turned %.4f rad in one tick at a hand-over" % worst_turn)
	_check(player_contacts == 0, "%d ticks with traffic touching the player" % player_contacts)
	_check(pair_contacts == 0, "two sim cars touched (%d samples)" % pair_contacts)
	_check(mean_kmh > PLAYER_KMH - 15.0, "the player averaged %.0f km/h, under %.0f" % [mean_kmh, PLAYER_KMH - 15.0])
	print("errors=%d warnings=%d" % [logger.errors.size(), logger.warnings])
	_check(logger.errors.is_empty(), "engine or script errors: %s" % str(logger.errors.slice(0, 3)))
	for f in fails:
		print("FAIL: ", f)
	print("traffic_near_band: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
	return true
