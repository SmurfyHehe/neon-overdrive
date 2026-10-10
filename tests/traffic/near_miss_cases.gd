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
#   rulebreak   rule breakers with cut-ins on the player OFF (the default) and
#               ON (TrafficSettings.cut_in_player): the gap one keeps when it
#               merges behind or in front of you, how close it follows you,
#               and whether a weaver drifts toward you
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
var cases: Array[String] = ["pullout", "noflash", "flash", "blindspot", "abort", "edge", "rulebreak", "cutoff", "swerve", "horns"]
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
	TrafficSettings.cut_in_player = false
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

# ---------- rulebreak ----------

func _setup_rulebreak() -> void:
	traffic.own_lanes_used = [1, 2]
	_player(1, 100.0 * KMH)
	# a: a rule breaker in the next lane, at your speed, for the merge checks,
	# then put behind you to see how close it follows.
	a = _car(2, 0.0, 100.0 * KMH)
	a.set_rule_breaker(true, 0.0)
	a._lc_cooldown = 1000.0
	# b: a weaver two lanes over, level with you.
	b = _car(3, 0.0, 100.0 * KMH)
	b.set_rule_breaker(true, 0.5)
	b._lc_cooldown = 1000.0
	pace = b
	pace_off = 0.0

## Puts the rule breaker `ahead` m (bumper to bumper, + = in front of you) in lane 2.
func _beside(ahead: float) -> void:
	var d := ahead + signf(ahead) * (a.half_l + P_HL)
	a.place(_lane(2), -1.0, _pz() - d, a.rest_y, p.current_speed())
	traffic._build_index()
	a._my_x = _lane(2)
	a._my_z = _pz() - d

func _merge_ok() -> bool:
	return a._merge_safe(_lane(1), a.lane_speed())

func _tick_rulebreak() -> bool:
	var v := p.current_speed()
	if phase == 0 and t >= 2.0:
		# Merge gaps, asked directly: 16 m behind you, and 20 m in front of you.
		var res := []
		for on in [false, true]:
			TrafficSettings.cut_in_player = on
			_beside(-16.0)
			res.append(_merge_ok())
			_beside(20.0)
			res.append(_merge_ok())
		TrafficSettings.cut_in_player = false
		if res[0]:
			_fail("switch off: it would merge 16 m behind you (the normal gap at this speed is %.0f m)" % (TrafficCar.S0 + TrafficCar.LC_MIN_GAP_T * v))
		if res[1]:
			_fail("switch off: it would merge 20 m in front of you (1.0 s is %.0f m)" % v)
		if not res[2]:
			_fail("switch on: the old tight merge behind you (16 m) is refused")
		if not res[3]:
			_fail("switch on: the old merge 20 m in front of you is refused")
		f["merge"] = "merge 16 m behind / 20 m ahead of you: off %s / %s, on %s / %s" % [
			"yes" if res[0] else "no", "yes" if res[1] else "no", "yes" if res[2] else "no", "yes" if res[3] else "no"]
		# Now behind you in your lane, with nowhere to go, wanting 25 km/h more.
		traffic.own_lanes_used = [1, 3]
		a.place(_lane(1), -1.0, _pz() + 60.0, a.rest_y, v)
		a.target_speed = v + TrafficCar.RB_SPEED
		phase = 1
		mark = t
	elif phase == 1:
		f["b_lo"] = minf(float(f.get("b_lo", 0.0)), _x(b) - _lane(3))   # toward you
		f["b_hi"] = maxf(float(f.get("b_hi", 0.0)), _x(b) - _lane(3))   # away
		if t - mark >= 12.0:
			f["follow_off"] = a.lead_gap / maxf(a.lane_speed(), 1.0)
			if not a.lead_is_player:
				_fail("it is not following you (gap %.1f)" % a.lead_gap)
			if float(f.follow_off) < 0.95:
				_fail("switch off: it follows you at %.2f s" % float(f.follow_off))
			if float(f.b_lo) < -0.2:
				_fail("switch off: the weaver drifted %.2f m toward you" % -float(f.b_lo))
			if float(f.b_hi) < 0.25:
				_fail("the weaver did not weave at all (%.2f m away)" % float(f.b_hi))
			f["weave_off"] = -float(f.b_lo)
			f.erase("b_lo")
			TrafficSettings.cut_in_player = true
			phase = 2
			mark = t
	elif phase == 2:
		f["b_lo"] = minf(float(f.get("b_lo", 0.0)), _x(b) - _lane(3))
		if t - mark >= 25.0:   # the follower closes up slowly (1/K_GAP is 7 s)
			var follow_on := a.lead_gap / maxf(a.lane_speed(), 1.0)
			TrafficSettings.cut_in_player = false
			# Still closing up after 25 s (it settles at S0 + 0.6 s: 0.74 s at this
			# speed); under the 1.0 s it keeps with the switch off is the point.
			if follow_on > 0.93:
				_fail("switch on: it follows you at %.2f s, not the old 0.6 s tailgate" % follow_on)
			if float(f.b_lo) > -0.25:
				_fail("switch on: the weaver no longer drifts toward you (%.2f m)" % -float(f.b_lo))
			if touched:
				_fail("you were touched")
			note = "%s; follows you at %.2f s off, %.2f s on; weaver toward you %.2f m off, %.2f m on" % [
				f.merge, f.follow_off, follow_on, f.weave_off, -float(f.b_lo)]
			return true
	return false

# ---------- cutoff ----------

func _setup_cutoff() -> void:
	traffic.own_lanes_used = [1]
	_player(3, 100.0 * KMH)
	a = _car(1, 60.0, 100.0 * KMH)
	a.reaction_s = 0.6
	f["h0"] = traffic.honk_count

## Puts you in the car's lane with 0.5 s of its speed between the bumpers,
## going a little slower than it (the follower then wants about 3.5 m/s^2).
func _cut_in() -> void:
	var gap := 0.5 * a.lane_speed()
	p_x = _lane(1)
	p_v = a.lane_speed() - 1.5
	TestDriver.place(p, p_x, _ahead(a) + a.half_l + P_HL + gap, 0.0, p_v)
	pace = null

func _tick_cutoff() -> bool:
	f["brake"] = maxf(float(f.get("brake", 0.0)), a.brake_input)
	if phase == 0 and t >= 2.0:
		phase = 1
		mark = t
		_cut_in()
	elif phase == 1:
		if traffic.honk_count - int(f.h0) >= 1 and not f.has("honk_at"):
			f["honk_at"] = t - mark
			f["long"] = bool(traffic.honk_log.back().long)
		if t - mark >= 2.5:
			if not f.has("honk_at"):
				_fail("no horn within 2.5 s of the cut-in (follower asked for brake %.2f)" % float(f.brake))
				return true
			if float(f.honk_at) < 0.6 - 0.02 or float(f.honk_at) > 0.8 + 0.1:
				_fail("horn %.2f s after the cut-in (its reaction time is 0.6)" % float(f.honk_at))
			if a.head_flashes != 2:
				_fail("%d headlight flashes, wanted 2" % a.head_flashes)
			if float(f.brake) < 0.2:
				_fail("it barely braked (pedal %.2f)" % float(f.brake))
			# Away and straight back in: inside 5 s there is no second horn.
			phase = 2
			_player(3, 100.0 * KMH)
			TestDriver.place(p, _lane(3), 0.0, 0.0, 100.0 * KMH)
	elif phase == 2 and t - mark >= 3.2:
		phase = 3
		_cut_in()
	elif phase == 3 and t - mark >= 4.8:
		if traffic.honk_count - int(f.h0) != 1:
			_fail("a second horn %.1f s after the first" % (t - mark))
		phase = 4
		_player(3, 100.0 * KMH)
		TestDriver.place(p, _lane(3), 0.0, 0.0, 100.0 * KMH)
	elif phase == 4 and t - mark >= 7.0:
		phase = 5
		_cut_in()
	elif phase == 5 and t - mark >= 9.0:
		if traffic.honk_count - int(f.h0) != 2:
			_fail("%d horns after a third cut-in past the 5 s limit, wanted 2" % (traffic.honk_count - int(f.h0)))
		if touched:
			_fail("you touched")
		note = "horn %.2f s after the cut-in (%s), 2 headlight flashes, brake pedal %.2f; no second horn inside 5 s, one again after" % [
			f.honk_at, "long" if f.long else "short", f.brake]
		return true
	return false

# ---------- swerve ----------

func _setup_swerve() -> void:
	traffic.own_lanes_used = [1, 2]
	_player(3, 100.0 * KMH)
	a = _car(1, 80.0, 100.0 * KMH)
	a.reaction_s = 0.4
	a._lc_cooldown = 100.0   # no pass or keep-right of its own

func _tick_swerve() -> bool:
	if phase == 0 and t >= 2.0:
		phase = 1
		mark = t
		# You, suddenly in its lane, slow and braking to a stop, 1.2 s from contact.
		var slow := 10.0
		var gap := 1.2 * (a.lane_speed() - slow)
		p_x = _lane(1)
		TestDriver.place(p, p_x, _ahead(a) + a.half_l + P_HL + gap, 0.0, slow)
		p_brake = true
	elif phase == 1:
		f["over"] = maxf(float(f.get("over", 0.0)), _x(a) - _lane(2))
		if a._lc_why == TrafficCar.DO_SWERVE and a.changing and not f.has("swerve_at"):
			f["swerve_at"] = t - mark
			if a.turn != 0:
				_fail("it signalled an emergency swerve")
		if touched:
			_fail("it hit you %.2f s in (swerve %s; it was %.2f m sideways of you, doing %.0f km/h to your %.0f)" % [
				t - mark, "started %.2f s in" % float(f.swerve_at) if f.has("swerve_at") else "never started",
				absf(_x(a) - _px()), a.lane_speed() * 3.6, p.current_speed() * 3.6])
			return true
		if _ahead(a) > 15.0 and t - mark > 1.0:
			if not f.has("swerve_at"):
				_fail("it got past without swerving?")
			if a.honks < 1:
				_fail("no horn")
			if float(f.over) + a.half_w > RoadChunkBuilder.LANE_W * 0.5 + 0.3:
				_fail("it overshot the lane it swerved into by %.2f m" % float(f.over))
			# The gap is by the index's footprints (yours is 0.1 m wider than the body each side).
			note = "swerved %.2f s after you appeared, no contact (%.2f m between footprints), overshot its new lane centre by %.2f m, horn %s" % [
				f.get("swerve_at", -1.0), min_side, f.over, "sounded" if a.honks > 0 else "silent"]
			return true
		if t - mark > 8.0:
			_fail("it never got past (speed %.1f m/s, doing %s)" % [a.lane_speed(), a.doing])
			return true
	return false

# ---------- horns ----------

func _setup_horns() -> void:
	_player(1, 80.0 * KMH)

## The six horns are six different sounds: right length, not silent, and each
## table entry names a horn that exists.
func _tick_horns() -> bool:
	if phase == 1:
		# Checked already: only waiting for the build thread.
		if TrafficHorns.ready() or t > 20.0:
			if not TrafficHorns.ready():
				_fail("the horns were never built")
			return true
		return false
	phase = 1
	var peaks := PackedStringArray()
	var seen := {}
	for horn in TrafficHorns.NAMES:
		var s := TrafficHorns.samples(horn, TrafficHorns.LONG_S)
		var peak := 0.0
		var crossings := 0
		for i in range(1, s.size()):
			peak = maxf(peak, absf(s[i]))
			if s[i - 1] < 0.0 and s[i] >= 0.0:
				crossings += 1
		if s.size() != int(TrafficHorns.LONG_S * TrafficHorns.RATE):
			_fail("%s is %d samples long" % [horn, s.size()])
		if peak < 0.2 or peak > 1.0:
			_fail("%s peaks at %.2f" % [horn, peak])
		if seen.has(crossings):
			_fail("%s and %s sound the same (%d zero crossings)" % [horn, seen[crossings], crossings])
		seen[crossings] = horn
		peaks.append("%s %d Hz-ish, peak %.2f" % [horn, crossings, peak])
	for kind in TrafficHorns.BY_KIND:
		if not (TrafficHorns.BY_KIND[kind] in TrafficHorns.NAMES):
			_fail("%s has an unknown horn" % kind)
	if TrafficHorns.horn_for("n2_cityhatch") != "beep" or TrafficHorns.horn_for("n3_pickup") != "blare" or TrafficHorns.horn_for("no_such_car") != "two_tone":
		_fail("the horn table")
	note = "; ".join(peaks)
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
