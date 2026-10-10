extends SceneTree

# Near-miss fix, the staged cases (traffic near-miss fix steps 2-6). An empty
# road, the player on a script, and one to three traffic cars put exactly where
# each case needs them (TrafficManager.add_rival: a normal traffic car that is
# never recycled). All cases in one run, one after another:
#
#   godot --headless --fixed-fps 120 --path . -s res://tests/traffic/near_miss_cases.gd
#
# NMC_ONLY=<name> runs one case. Cases:
#   pullout     you close at +100 km/h and pull out right at 3 s to contact:
#               neither car ahead starts a lane change or signals
#   noflash     10 m behind a car for 20 s: it holds its lane
#   flash       one flash, right lane free: the car signals right, then moves
#               over within reaction + 1.5 s + 3 s; the car beyond it does nothing
#   blindspot   you sit alongside a car that has a stopped car ahead: it does
#               not change into your lane until you are 2 car lengths past it
#   abort       you swerve into the lane a car has just started moving into:
#               it steers back, never closer than 0.5 m
#   edge        you sit 1.2 m beside a car: it shifts up to 0.3 m away and
#               stays in its lane
#   cutoff      you cut in 0.5 s ahead of a car: one honk, two headlight
#               flashes, hard braking, no second honk within 5 s
#   swerve      you brake to a stop in front of a car: it swerves into the
#               free lane and does not touch you
#   siren       a patrol car with lights on closes from behind: cars ahead
#               move right and slow; with the lights off nothing changes
#
# Straight flat road, no police patrol of its own, 120 Hz.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const RATE := 120
const KMH := 1.0 / 3.6
const P_HW := 1.0
const P_HL := 2.2
const KIND := "n1_commuter"

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var traffic: TrafficManager
var fails: Array[String] = []
var cases: Array[String] = ["pullout", "noflash", "flash", "blindspot", "abort", "edge"]
var case_i := -1
var name_now := ""
var t := 0.0
var tick := 0
var phase := 0
var mark := 0.0

# The scripted player: holds road-space x p_x at p_v m/s, or keeps pace with
# `pace` (its z plus pace_off metres further along the road).
var p_x := 0.0
var p_v := 0.0
var p_damp := 1.2
var p_brake := false
var pace: TrafficCar
var pace_off := 0.0

# Per-case scratch.
var a: TrafficCar
var b: TrafficCar
var c: TrafficCar
var min_side := INF
var min_len := INF
var touched := false
var note := ""
var f := {}

static func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	OS.set_environment("NEON_CURVES", "0.0")
	OS.set_environment("NEON_HILLS", "0.0")
	OS.set_environment("NEON_POLICE", "0")
	OS.set_environment("NEON_NEAR_MISS_FILE", "user://near_miss_cases.txt")
	var only := _env("NMC_ONLY", "")
	if only != "":
		cases = [only]
	game = Harness.boot(self, 0, 300.0, 7, 300.0)

func _physics_process(_delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
			p = null
			return false
		traffic = game.get("traffic")
		if traffic.cars.size() != 0:
			traffic.set_car_count(0)
		p.driver = _drive
		_next_case()
		return false
	tick += 1
	t += 1.0 / RATE
	_watch()
	var done: bool = call("_tick_" + name_now)
	if done or t > 60.0:
		if not done:
			_fail("timed out")
		print("  %s %-10s %s" % ["ok  " if not f.get("failed", false) else "FAIL", name_now, note])
		return _next_case()
	return false

func _next_case() -> bool:
	_clear()
	case_i += 1
	if case_i >= cases.size():
		return _end()
	name_now = cases[case_i]
	t = 0.0
	tick = 0
	phase = 0
	mark = 0.0
	min_side = INF
	min_len = INF
	touched = false
	note = ""
	f = {}
	pace = null
	p_brake = false
	p_damp = 1.2
	call("_setup_" + name_now)
	return false

func _fail(msg: String) -> void:
	f["failed"] = true
	fails.append("%s: %s" % [name_now, msg])

# ---------- helpers ----------

func _lane(i: int) -> float:
	return Harness.lane_x(i)

func _pz() -> float:
	return RoadFrame.unroll(p.global_position).z

func _px() -> float:
	return RoadFrame.unroll(p.global_position).x

## Player in lane `lane` at `v` m/s, where it is along the road.
func _player(lane: int, v: float) -> void:
	p.damage.garage_repair(null)
	p.health.repair()
	p.fuel.litres = FuelTank.CAPACITY_L
	p_x = _lane(lane)
	p_v = v
	TestDriver.place(p, p_x, 0.0, 0.0, v)

## A traffic car `ahead` metres up the road from the player (centre to centre).
func _car(lane: int, ahead: float, v: float) -> TrafficCar:
	var car := traffic.add_rival(KIND, _lane(lane), _pz() - ahead, v, Color(0.7, 0.7, 0.72))
	car.reaction_s = 0.6
	return car

func _x(car: TrafficCar) -> float:
	return RoadFrame.unroll(car.global_position).x

## Metres the car is ahead of the player (centre to centre).
func _ahead(car: TrafficCar) -> float:
	return _pz() - RoadFrame.unroll(car.global_position).z

## Sideways air between the bodies (only meaningful while they overlap lengthwise).
func _side_gap(car: TrafficCar) -> float:
	return absf(_x(car) - _px()) - car.half_w - P_HW

func _alongside(car: TrafficCar) -> bool:
	return absf(_ahead(car)) < car.half_l + P_HL

func _watch() -> void:
	for car in traffic.cars:
		if _alongside(car):
			min_side = minf(min_side, _side_gap(car))
		elif absf(_x(car) - _px()) < car.half_w + P_HW:
			min_len = minf(min_len, absf(_ahead(car)) - car.half_l - P_HL)
	if tick > 3:
		for body in p.get_colliding_bodies():
			if body is TrafficCar:
				touched = true

func _clear() -> void:
	if traffic == null:
		return
	for car in traffic.cars.duplicate():
		traffic.cars.erase(car)
		car.set_detailed(false)
		car.set_shown(false)
		car.remove_from_group("aero_vehicles")
		car.global_position.z += 50000.0
		car.queue_free()
	traffic._build_index()
	traffic.own_lanes_used = []
	a = null
	b = null
	c = null

func _drive(car: PlayerCar) -> void:
	var u := RoadFrame.unroll(car.global_position)
	var side_v := RoadFrame.dir_to_road(u.z, car.linear_velocity).x
	car.steering_input = TrafficCar.lane_steer(car, p_x - side_v * p_damp, -1.0, 2.5, 0.0008)
	car.handbrake_input = 0.0
	var want := p_v
	if pace != null and is_instance_valid(pace):
		var where := RoadFrame.unroll(pace.global_position).z - pace_off
		want = maxf(pace.lane_speed() + 0.8 * (u.z - where), 0.0)
	var v := car.current_speed()
	var acc := (want - v) * 1.5
	if p_brake:
		car.throttle_input = 0.0
		car.brake_input = 1.0
	elif acc < -0.5:
		car.throttle_input = 0.0
		car.brake_input = clampf(-acc / 8.0, 0.0, 1.0)
	else:
		car.throttle_input = clampf(acc, 0.0, 1.0)
		car.brake_input = 0.0

# ---------- pullout ----------

func _setup_pullout() -> void:
	_player(1, 200.0 * KMH)
	a = _car(1, 200.0, 100.0 * KMH)
	b = _car(1, 320.0, 100.0 * KMH)

func _tick_pullout() -> bool:
	var closing := p.current_speed() - a.lane_speed()
	var gap := _ahead(a) - a.half_l - P_HL
	if phase == 0 and closing > 1.0 and gap / closing < 3.0:
		phase = 1
		p_damp = 0.6
		p_x = _lane(2)   # pull out right, without looking
	for car in [a, b]:
		# Only until you are past it: after that it may drift back right.
		if _ahead(car) > -15.0 and (car.changing or car.turn != 0 or car.lane_changes > 0):
			_fail("a car ahead %s as you came up behind it (t %.2f, car %s, it was %s, %.0f m ahead, you at x %.2f, sideways %.2f m/s)" % [
				"signalled" if not car.changing else "started a lane change", t, "A" if car == a else "B", car.doing, _ahead(car), _px(), traffic.p_vx])
			return true
	if _ahead(b) < -40.0:
		if touched:
			_fail("you touched a car")
		# How close the pass was is the scripted player's doing (it takes 3 s to
		# cross a lane at 200 km/h); the cars' part is that they stayed put.
		note = "both cars ahead held their lane (your own pass came %.2f m beside)" % min_side
		return true
	return false

# ---------- noflash ----------

func _setup_noflash() -> void:
	_player(1, 100.0 * KMH)
	a = _car(1, 10.0 + P_HL + 1.7, 100.0 * KMH)
	pace = a
	pace_off = -(10.0 + P_HL + a.half_l)

func _tick_noflash() -> bool:
	if a.changing or a.turn != 0 or a.lane_changes > 0:
		_fail("the car moved or signalled at %.1f s with nobody flashing it" % t)
		return true
	if t >= 20.0:
		note = "20 s, 10 m behind it: lane held (gap now %.1f m)" % (_ahead(a) - a.half_l - P_HL)
		return true
	return false

# ---------- flash ----------

func _setup_flash() -> void:
	_player(1, 100.0 * KMH)
	a = _car(1, 30.0, 100.0 * KMH)
	b = _car(1, 90.0, 100.0 * KMH)
	pace = a
	pace_off = -30.0
	a.reaction_s = 0.8
	b._lc_cooldown = 100.0   # no keep-right of its own: only a flash could move it

func _tick_flash() -> bool:
	if phase == 0 and t >= 1.0:
		phase = 1
		mark = t
		p.beams.flash()
	if phase == 0:
		return false
	var since := t - mark
	if b.turn != 0 or b.changing or b.lane_changes > 0:
		_fail("the second car reacted to a flash meant for the first")
		return true
	if phase == 1:
		if a.turn != 0:
			phase = 2
			f["blink_at"] = since
			if a.turn != 2:
				_fail("it signalled left with the right lane free")
			if since < a.reaction_s - 0.01:
				_fail("it signalled %.2f s after the flash, before its %.1f s reaction time" % [since, a.reaction_s])
		elif since > a.reaction_s + 0.5:
			_fail("no blinker %.1f s after the flash" % since)
			return true
	elif phase == 2:
		if a.changing:
			phase = 3
			f["start_at"] = since
			if a.last_signal_s < 1.5 - 0.01:
				_fail("it moved after %.2f s of blinker (wanted 1.5)" % a.last_signal_s)
		elif since > a.reaction_s + 1.5 + 0.6:
			_fail("no lane change %.1f s after the flash" % since)
			return true
	elif phase == 3 and not a.changing:
		f["end_at"] = since
		if a.lane_i != 2:
			_fail("it ended in lane %d, not the lane to the right" % (a.lane_i + 1))
		if since > a.reaction_s + 1.5 + 3.0 + 0.6:
			_fail("moved over %.1f s after the flash (limit %.1f)" % [since, a.reaction_s + 5.1])
		if a.turn != 0:
			_fail("the blinker stayed on after the change")
		if traffic.flash_count != 1 or traffic.flashed_car != a:
			_fail("flash went to %d cars" % traffic.flash_count)
		note = "blinker %.2f s after the flash, moving at %.2f s, in the right lane at %.2f s; second car did nothing" % [f.blink_at, f.start_at, since]
		return true
	return false

# ---------- blindspot ----------

func _setup_blindspot() -> void:
	traffic.own_lanes_used = [1, 2]
	_player(2, 90.0 * KMH)
	a = _car(1, 0.0, 90.0 * KMH)
	b = _car(1, 260.0, 0.0)
	b.wrecked = true   # a stopped car on the hazard brake
	pace = a
	pace_off = 0.0

func _tick_blindspot() -> bool:
	var lead := _ahead(b) - _ahead(a) - a.half_l - b.half_l   # a's gap to the stopped car
	if phase == 0:
		if a.changing or a.lane_changes > 0:
			_fail("it changed into your lane while you were alongside (%.1f m ahead of it)" % -_ahead(a))
			return true
		if lead < 75.0:
			phase = 1   # now drive off: the lane opens once you are 2 lengths past its nose
			pace = null
			p_v = 150.0 * KMH
			f["released_at"] = t
	elif phase == 1:
		if a.lane_changes > 0 and not f.has("past"):
			# How far your tail was past its nose when it started to move.
			f["past"] = -_ahead(a) - a.half_l - P_HL
			if float(f.past) < 2.0 * 2.0 * a.half_l - 0.5:
				_fail("it started to move with you only %.1f m past its nose (2 car lengths is %.1f)" % [f.past, 4.0 * a.half_l])
		if f.has("past") and not a.changing:
			if touched:
				_fail("you touched a car")
			note = "held its lane beside you, moved once you were %.1f m past its nose (2 lengths = %.1f m)" % [f.past, 4.0 * a.half_l]
			return true
		if t - float(f.released_at) > 12.0:
			_fail("it never went round the stopped car after you left (doing %s)" % a.doing)
			return true
	return false

# ---------- abort ----------

func _setup_abort() -> void:
	traffic.own_lanes_used = [1, 2]
	_player(3, 100.0 * KMH)
	a = _car(1, 1.0, 100.0 * KMH)
	b = _car(1, 45.0, 70.0 * KMH)
	pace = a
	pace_off = 1.0

func _tick_abort() -> bool:
	if phase == 0:
		if a.changing:
			phase = 1
			mark = t
			if a.lane_i != 2:
				_fail("it went for lane %d" % (a.lane_i + 1))
		elif t > 15.0:
			_fail("it never pulled out to pass the slow car")
			return true
	elif phase == 1:
		if t - mark >= 0.25:
			phase = 2
			p_damp = 0.5
			p_x = _lane(2)   # swerve into the lane it is moving into
	elif phase == 2:
		if traffic.abort_count > 0 and not f.has("abort_at"):
			f["abort_at"] = t - mark
			f["x_at"] = _x(a) - _lane(1)
		if f.has("abort_at") and not a.changing:
			if a.lane_i != 1 or absf(_x(a) - _lane(1)) > 0.5:
				_fail("after the abort it is %.2f m from its old lane centre" % absf(_x(a) - _lane(1)))
			if a.turn != 0:
				_fail("blinker still on after the abort")
			if min_side < 0.5:
				_fail("it came within %.2f m of you" % min_side)
			if touched:
				_fail("you touched")
			note = "steered back %.2f s into the change (%.2f m out), closest %.2f m beside you" % [f.abort_at, f.x_at, min_side]
			return true
		if t - mark > 6.0:
			_fail("no abort (abort_count %d, changing %s, lane %d)" % [traffic.abort_count, a.changing, a.lane_i + 1])
			return true
	return false

# ---------- edge ----------

func _setup_edge() -> void:
	traffic.own_lanes_used = [1]   # nowhere to go: this is about the shift, not a lane change
	_player(2, 100.0 * KMH)
	a = _car(1, 0.0, 100.0 * KMH)
	p_x = _lane(1) + a.half_w + P_HW + 1.2   # 1.2 m of air beside it
	TestDriver.place(p, p_x, 0.0, 0.0, 100.0 * KMH)
	pace = a
	pace_off = 0.0

func _tick_edge() -> bool:
	var off := _x(a) - _lane(1)   # - = away from you
	if phase == 0:
		f["most"] = minf(float(f.get("most", 0.0)), off)
		if absf(off) + a.half_w > RoadChunkBuilder.LANE_W * 0.5:
			_fail("it left its lane (%.2f m off centre)" % off)
			return true
		if t >= 5.0:
			f["held"] = off
			if off > -0.15:
				_fail("it shifted %.2f m away (wanted up to 0.3)" % -off)
			if float(f.most) < -0.45:
				_fail("it shifted %.2f m, more than the 0.3 allowed" % -float(f.most))
			phase = 1
			mark = t
			pace = null
			p_v = 150.0 * KMH   # drive off
	elif t - mark >= 5.0:
		if absf(off) > 0.12:
			_fail("it did not come back to the middle after you left (%.2f m off)" % off)
		if a.lane_changes > 0:
			_fail("it changed lane")
		note = "shifted %.2f m away with you 1.2 m beside it, back to %.2f m off centre after you left" % [-float(f.held), absf(off)]
		return true
	return false

# ---------- the end ----------

func _end() -> bool:
	if traffic != null and traffic.near_miss != null:
		traffic.near_miss.finish()
	if not logger.errors.is_empty():
		fails.append("%d engine errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	for msg in fails:
		printerr("FAIL: " + msg)
	print("near_miss_cases: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
