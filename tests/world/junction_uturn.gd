extends SceneTree

# U-turn at a city crossing (T2, 2026-10-11; Roy 1420: a U-turn at a city
# crossing costs no heat). The player drives up to each act-1 crossing with
# City lights on and traffic running, turns round inside the box and leaves
# the other way.
#
# hold     Junction.uturn_hold is on while the nose is more than 45 degrees off
#          the road inside the box, and only then.
# stop     when it begins, cars are put on the main road 38 m short of the stop
#          line in both directions and two lanes each (own lanes 0 and 2, oncoming 0 and 1; 14 m/s, a green light):
#          none crosses a line while the hold is on.
# contact  the player touches nobody (traffic cars, or each other).
# resume   5 s after the hold ends no car is still held and every car that was
#          held has crossed its line or is moving.
#
# Nothing here touches police: a U-turn in the box raises no offence because no
# code looks for one; tests/world/junction_lights.gd covers the lights.
#
# Run (the game boots on the real loop road):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/world/junction_uturn.gd
# NEON_CROSSINGS=0,2 runs only those crossings (indexes into RoadMap.junctions()).

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")

const RATE := 120
const L := 50.0
const APPROACH := 45.0       # m short of the crossing the player starts
const APPROACH_V := 5.0      # m/s
const TURN_FROM := 13.0      # m short of the centre the wheel goes over
const CAR_BACK := 38.0       # m short of its line when the hold begins
const CAR_V := 14.0
const SCENE_TICKS := RATE * 22   # inside the 30 s green
const TIMEOUT_TICKS := RATE * 400
## +1 or -1: which way the steering input turns the car toward +x.
const STEER_SIGN := -1.0
## Own lane the player turns from (lane 0 is next to the median, 3 the outer).
## Lane 1 is wide enough to turn round inside the box (radius about 4.3 m).
const PLAYER_LANE := 1

var game: Node
var traffic: TrafficManager
var junction: Junction
var p: PlayerCar
var fails: Array[String] = []
var lines: Array[String] = []
var crossings: Array = []   # s of each crossing to try
var k := -1
var phase := 0              # 0 travel, 1 settle, 2 run
var tick := 0
var turn_dir := 1.0
var cars: Array[TrafficCar] = []
var line_z: Array[float] = []
var ever_held: Array[bool] = []
var crossed: Array[bool] = []
var hold_ticks := 0
var hold_tick0 := -1
var release_tick := -1
var contacts := 0
var crossed_in_hold := 0
var max_ang := 0.0
var stage := 0              # driver: 0 approach, 1 turn, 2 leave
var logger := Harness.ErrorCounter.new()

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	for key in ["NEON_CURVES", "NEON_HILLS"]:
		OS.set_environment(key, "0")
	OS.set_environment("NEON_ROAD", "")
	OS.set_environment("NEON_ACT", "")
	OS.set_environment("NEON_FREEMODE", "0")   # story act 1 (a new save is free)
	OS.set_environment("NEON_ROAD_SEED", "31337")
	OS.set_environment("NEON_CITY_LIGHTS", "1")
	OS.set_environment("NEON_LAYOUT", "0")
	TrafficSettings.city_lights = true
	SaveDirector.enabled = false
	game = Harness.boot(self, 0, 300.0, 4343, 8000.0)

func _physics_process(_delta: float) -> bool:
	if Engine.get_physics_frames() > TIMEOUT_TICKS:
		return _end("timed out after %d ticks (crossing %d, phase %d)" % [Engine.get_physics_frames(), k, phase])
	if traffic == null:
		if game.get("player") == null or game.get("junction") == null:
			return false
		traffic = game.get("traffic")
		junction = game.get("junction")
		p = game.get("player")
		if not RoadMap.is_loop():
			return _end("the game did not boot on the loop road")
		var only := OS.get_environment("NEON_CROSSINGS")
		var all := RoadMap.junctions()
		for i in all.size():
			if only == "" or str(i) in only.split(","):
				crossings.append(all[i])
		p.driver = _drive
		_next()
		return false
	tick += 1
	match phase:
		0:
			_travel()
		1:
			if tick >= RATE:
				_start_run()
		2:
			_run()
			if tick >= SCENE_TICKS:
				_finish()
				_next()
				if k >= crossings.size():
					return _end("")
	return false

func _next() -> void:
	k += 1
	phase = 0
	tick = 0
	if k >= crossings.size():
		return
	traffic.set_car_count(0)
	p.driver = Callable()
	p.throttle_input = 0.0
	p.brake_input = 1.0
	p.handbrake_input = 1.0

## Jumps toward the crossing in steps the floating origin can follow, then
## puts the car APPROACH m short of it in its own lane 3, facing down the road.
func _travel() -> void:
	if tick % 20 != 1:
		return
	var u := RoadFrame.unroll(p.global_position)
	var s := RoadFrame.s_at(u.z)
	var target: float = crossings[k] - APPROACH
	var delta := wrapf(target - s, -RoadMap.length() / 2.0, RoadMap.length() / 2.0)
	if absf(delta) > 300.0:
		_put(u.x, u.z - signf(delta) * 300.0)
		return
	if absf(delta) > 0.5:
		_put(TrafficManager.lane_centre(PLAYER_LANE, false), u.z - delta)
		return
	phase = 1
	tick = 0

func _put(x: float, z: float) -> void:
	var y := RoadFrame.unroll(p.global_position).y
	var t := RoadFrame.pose(x, y, z, 0.0)
	game.saver.restore_car(p, {"xform": SaveDirector.xform_to_array(t), "lin_vel": [0.0, 0.0, 0.0], "ang_vel": [0.0, 0.0, 0.0], "gear": 1})
	game.call("_update_chunk_pool", z)
	game.call("flush_rebuilds")

func _start_run() -> void:
	phase = 2
	tick = 0
	cars.clear()
	line_z.clear()
	ever_held.clear()
	crossed.clear()
	hold_ticks = 0
	hold_tick0 = -1
	release_tick = -1
	contacts = 0
	crossed_in_hold = 0
	max_ang = 0.0
	stage = 0
	turn_dir = signf(TrafficManager.lane_centre(1, true) - TrafficManager.lane_centre(PLAYER_LANE, false))
	traffic.set_car_count(4)
	traffic.detail_distance = 300.0
	traffic.recycle_behind = 2000.0
	traffic.own_lanes_used = [0, 1]
	traffic.onc_lanes_used = [0, 1]
	junction.force_flash = 0
	junction.t = 0.0   # a full green ahead
	p.brake_input = 0.0
	p.handbrake_input = 0.0
	p.driver = _drive

## Road-space heading of the player: 0 = down the road, + = toward +x.
func _ang() -> float:
	var u := RoadFrame.unroll(p.global_position)
	var f := RoadFrame.dir_to_road(u.z, -p.global_transform.basis.z)
	return atan2(f.x, -f.z)

func _drive(c: Vehicle) -> void:
	var u := RoadFrame.unroll(c.global_position)
	var dz := u.z - Junction.centre_z()    # + = short of the centre, going down the road
	var ang := _ang()
	var v := c.linear_velocity.length()
	c.brake_input = 0.0
	c.throttle_input = 1.0 if v < APPROACH_V else 0.0
	if stage == 0 and dz < TURN_FROM:
		stage = 1
	if stage == 1 and absf(ang) > 2.7:
		stage = 2
	if stage == 0:
		var side_v := RoadFrame.dir_to_road(u.z, c.linear_velocity).x
		c.steering_input = TrafficCar.lane_steer(c, TrafficManager.lane_centre(PLAYER_LANE, false) - side_v * 3.0, -1.0, 2.5, 0.0008)
	elif stage == 1:
		c.steering_input = STEER_SIGN * turn_dir
	else:
		var side_v := RoadFrame.dir_to_road(u.z, c.linear_velocity).x
		c.steering_input = TrafficCar.lane_steer(c, TrafficManager.lane_centre(1, true) - side_v * 3.0, 1.0, 2.5, 0.0008)

func _line(dir: float) -> float:
	return Junction.centre_z() - dir * Junction.STOP_OFF

func _d(car: TrafficCar) -> float:
	return (_line(car.direction) - RoadFrame.unroll(car.global_position).z) * car.direction - car.half_l

func _add(lane: int, oncoming: bool) -> void:
	var car: TrafficCar = traffic.cars[cars.size()]
	var dir := 1.0 if oncoming else -1.0
	car.target_speed = 20.0
	car.set_detailed(true)
	car.place(TrafficManager.lane_centre(lane, oncoming), dir, _line(dir) + dir * (-CAR_BACK - car.half_l), car.rest_y, CAR_V)
	cars.append(car)
	ever_held.append(false)
	crossed.append(false)

func _run() -> void:
	var a := _ang()
	max_ang = maxf(max_ang, absf(a))
	if OS.get_environment("NEON_DEBUG") != "" and tick % 60 == 0:
		var u := RoadFrame.unroll(p.global_position)
		print("t%d stage %d dz %.1f x %.1f ang %.0f v %.1f hold %s" % [tick, stage, u.z - Junction.centre_z(), u.x, rad_to_deg(a), p.linear_velocity.length(), junction.uturn_hold])
	if junction.uturn_hold:
		hold_ticks += 1
		if hold_tick0 < 0:
			hold_tick0 = tick
			for spec in [[0, false], [2, false], [0, true], [1, true]]:
				_add(spec[0], spec[1])
	elif hold_tick0 >= 0 and release_tick < 0:
		release_tick = tick
	for i in cars.size():
		var c := cars[i]
		if c.signal_held:
			ever_held[i] = true
		if not crossed[i] and _d(c) < 0.0:
			crossed[i] = true
			if junction.uturn_hold:
				crossed_in_hold += 1
		if Harness.overlaps(p, c, 1.5, 3.0):
			contacts += 1
		for j in range(i + 1, cars.size()):
			if Harness.overlaps(c, cars[j], 1.5, 3.0):
				contacts += 1
	if release_tick >= 0 and tick == release_tick + 5 * RATE:
		var held_now := 0
		var stuck_after := 0
		for i in cars.size():
			if cars[i].signal_held:
				held_now += 1
			if ever_held[i] and not crossed[i] and cars[i].current_speed() < 2.0:
				stuck_after += 1
		_check(held_now == 0, "crossing %d: %d cars still held 5 s after the U-turn" % [k, held_now])
		_check(stuck_after == 0, "crossing %d: %d held cars still standing 5 s after the U-turn" % [k, stuck_after])

func _finish() -> void:
	var held := 0
	for h in ever_held:
		if h:
			held += 1
	lines.append("crossing %d (s %.0f): hold %.1f s, max heading %.0f deg, %d cars held, %d crossed during the hold, %d contacts, released at tick %d" % [
		k, crossings[k], float(hold_ticks) / RATE, rad_to_deg(max_ang), held, crossed_in_hold, contacts, release_tick])
	_check(hold_ticks > RATE / 2, "crossing %d: the hold was on for %.2f s (the U-turn never happened, or was not seen)" % [k, float(hold_ticks) / RATE])
	_check(max_ang > 2.5, "crossing %d: the car only turned %.0f deg" % [k, rad_to_deg(max_ang)])
	_check(held >= 2, "crossing %d: only %d cars were held by the U-turn" % [k, held])
	_check(crossed_in_hold == 0, "crossing %d: %d cars drove through the box during the U-turn" % [k, crossed_in_hold])
	_check(contacts == 0, "crossing %d: %d contacts" % [k, contacts])
	_check(release_tick >= 0, "crossing %d: the hold never ended" % k)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _end(err: String) -> bool:
	if err != "":
		fails.append(err)
	for e in logger.errors:
		fails.append("engine error: " + e)
	for l in lines:
		print(l)
	if fails.is_empty():
		print("PASS: junction_uturn")
		quit(0)
	else:
		for f in fails:
			printerr("FAIL: ", f)
		quit(1)
	return true
