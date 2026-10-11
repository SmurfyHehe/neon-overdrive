extends SceneTree

# More-alive traffic (MA2, 2026-10-11): the tailgater (T3) and phone drivers
# (T1). Staged cases on an empty straight road, the player on a script, the
# near-miss log on (NEON_NEAR_MISS_FILE below), 120 Hz:
#
#   godot --headless --fixed-fps 120 --path . -s res://tests/traffic/more_alive_traffic.gd
#
# MAT_ONLY=<name> runs one case. Cases:
#   tailgate   you crawl at 50 km/h in the fast lane; a car 150 m behind comes
#              up, sits at about 0.8 s behind you, flashes twice, passes on the
#              right 3-5 s later, honks once alongside and pulls back in ahead
#              of you at the normal gap. One tailgater, never closer than the
#              lane-change gap (S0 + LC_MIN_GAP_T of your speed), no contact; a
#              second car 20 s later is not picked inside TG_EVERY
#   quick      the same player at speed (not slow): nobody tailgates
#   drift      a phone driver alone on the road drifts inside its lane (up to
#              0.35 m, both ways) and never leaves it
#   green      a phone driver and an ordinary one stopped at a red (a stub
#              junction); at green the ordinary one moves off at once, the phone
#              one 1.5-3 s late, and the car behind it taps its horn once
#   lane       a phone driver held up by a slow car with you in the lane beside
#              it never moves toward you
#   pool       a phone car handed out again as an ordinary driver loses the
#              flag and the glow; spawn share is about 1 in 12
# Prints the per-tick cost of the new logic (_life_step) at the end.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const RATE := 120
const KMH := 1.0 / 3.6
const P_HW := 1.0
const P_HL := 2.2
const KIND := "n1_commuter"

class FakeJunction extends Junction:
	var red := true
	var line_z := 0.0
	func stop_gap(z: float, dir: float, half_l: float, _v: float) -> float:
		if not red:
			return INF
		var d := (line_z - z) * dir - half_l
		if d < -2.0 or d > 100.0:
			return INF
		return d

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var traffic: TrafficManager
var fails: Array[String] = []
var cases: Array[String] = ["tailgate", "quick", "drift", "green", "lane", "pool"]
var case_i := -1
var name_now := ""
var t := 0.0
var tick := 0
var phase := 0
var p_x := 0.0
var p_v := 0.0
var a: TrafficCar
var b: TrafficCar
var c: TrafficCar
var note := ""
var f := {}
var min_gap_behind := INF
var min_gap_ahead := INF
var touched := false
var life_usec := 0
var life_calls := 0

static func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	OS.set_environment("NEON_CURVES", "0.0")
	OS.set_environment("NEON_HILLS", "0.0")
	OS.set_environment("NEON_POLICE", "0")
	OS.set_environment("NEON_NEAR_MISS_FILE", "user://more_alive_traffic.txt")
	var only := _env("MAT_ONLY", "")
	if only != "":
		cases = [only]
	game = Harness.boot(self, 0, 300.0, 11, 300.0)

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
	if done or t > float(f.get("limit", 60.0)):
		if not done:
			_fail("timed out at %.0f s" % t)
		print("  %s %-9s %s" % ["ok  " if not f.get("failed", false) else "FAIL", name_now, note])
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
	note = ""
	f = {}
	min_gap_behind = INF
	min_gap_ahead = INF
	touched = false
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

func _player(lane: int, v: float, z := 0.0) -> void:
	p.damage.garage_repair(null)
	p.health.repair()
	p.fuel.litres = FuelTank.CAPACITY_L
	p_x = _lane(lane)
	p_v = v
	TestDriver.place(p, p_x, z, 0.0, v)

## A traffic car `ahead` metres up the road from the player (negative: behind).
## Pinned (never recycled), but with no race driver, so it drives as traffic.
func _car(lane: int, ahead: float, v: float, pinned := true) -> TrafficCar:
	var car := traffic.add_rival(KIND, _lane(lane), _pz() - ahead, v, Color(0.7, 0.7, 0.72))
	car.reaction_s = 0.6
	car.race_pinned = pinned
	return car

func _x(car: TrafficCar) -> float:
	return RoadFrame.unroll(car.global_position).x

func _ahead(car: TrafficCar) -> float:
	return _pz() - RoadFrame.unroll(car.global_position).z

## Bumper gap between a car and the player while they share a corridor.
func _watch() -> void:
	for car in traffic.cars:
		if absf(_x(car) - _px()) < car.half_w + P_HW - 0.1:
			var d := _ahead(car)
			var gap := absf(d) - car.half_l - P_HL
			if d > 0.0:
				min_gap_ahead = minf(min_gap_ahead, gap)
			else:
				min_gap_behind = minf(min_gap_behind, gap)
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
	traffic.junction = null
	traffic.tailgater = null
	traffic.tailgate_count = 0
	traffic._tg_slow_since = -1.0
	traffic._tg_last = -1000.0
	traffic.phone_share = 0.0
	traffic.phone_honk_count = 0
	traffic._phone_honks.clear()
	traffic.honk_log.clear()
	a = null
	b = null
	c = null

func _drive(car: PlayerCar) -> void:
	var u := RoadFrame.unroll(car.global_position)
	var side_v := RoadFrame.dir_to_road(u.z, car.linear_velocity).x
	car.steering_input = TrafficCar.lane_steer(car, p_x - side_v * 1.2, -1.0, 2.5, 0.0008)
	car.handbrake_input = 0.0
	var v := car.current_speed()
	var acc := (p_v - v) * 1.5
	if acc < -0.5:
		car.throttle_input = 0.0
		car.brake_input = clampf(-acc / 8.0, 0.0, 1.0)
	else:
		car.throttle_input = clampf(acc, 0.0, 1.0)
		car.brake_input = 0.0

# ---------- tailgate ----------

func _setup_tailgate() -> void:
	f["limit"] = 112.0
	_player(0, 50.0 * KMH)

func _tick_tailgate() -> bool:
	# The player crawls from the start; a car comes up behind once the six
	# slow seconds are done (an earlier one would pass on its own, as ever).
	if phase == 0 and t >= 7.0:
		phase = 1
		a = _car(0, -130.0, 115.0 * KMH)
	# a second car well inside TG_EVERY: it must not be picked
	if phase == 1 and t >= 60.0:
		phase = 2
		b = _car(0, -130.0, 115.0 * KMH)
	if phase == 2 and t >= 88.0:
		phase = 3
		f["count_at_88"] = traffic.tailgate_count
	# and one after it: picked
	if phase == 3 and t >= 100.0:
		phase = 4
		c = _car(0, -130.0, 115.0 * KMH)
	if t < 108.0:
		return false
	var v := p_v
	var lc_gap := TrafficCar.S0 + TrafficCar.LC_MIN_GAP_T * v
	if a.tg_flashes != 1:
		_fail("no tailgater: flashes %d, picked %d" % [a.tg_flashes, traffic.tailgate_count])
	if a.head_flashes != 2:
		_fail("it flashed %d times, wanted two" % a.head_flashes)
	if a.tg_passes != 1 or a.tg_returns != 1:
		_fail("pass %d, return %d (wanted 1 and 1)" % [a.tg_passes, a.tg_returns])
	if a.tg_honk_count != 1:
		_fail("%d honk(s) alongside, wanted 1" % a.tg_honk_count)
	if min_gap_behind < lc_gap - 0.5:
		_fail("it sat %.1f m behind you, under the lane-change gap %.1f m" % [min_gap_behind, lc_gap])
	if min_gap_ahead < maxf(TrafficCar.PLAYER_MIN_GAP, TrafficCar.PLAYER_GAP_T * v) - 0.5:
		_fail("it pulled back in %.1f m ahead of you, under the normal gap" % min_gap_ahead)
	if int(f.count_at_88) != 1 or b.tg_flashes != 0:
		_fail("a second tailgater inside %.0f s (count %d at 88 s)" % [TrafficManager.TG_EVERY, int(f.count_at_88)])
	if traffic.tailgate_count != 2 or c.tg_phase == TrafficCar.TG_NONE:
		_fail("no tailgater after TG_EVERY (count %d, phase %d)" % [traffic.tailgate_count, c.tg_phase])
	if touched:
		_fail("you touched a car")
	# cost of the new per-bookkeeping-tick logic, measured directly
	var t0 := Time.get_ticks_usec()
	for i in 2000:
		traffic._life_step()
	life_usec = Time.get_ticks_usec() - t0
	var near := 0
	for r in traffic.near_miss_records:
		if str(r.get("doing", "")).begins_with("tailgat"):
			near += 1
	var log_line := "near-miss log: %d record(s), %d of tailgating, smallest side gap %.2f m, shortest time to contact %.1f s" % [
		traffic.near_miss_count, near, traffic.near_miss.min_side_gap if traffic.near_miss != null else -1.0,
		traffic.near_miss.min_ttc if traffic.near_miss != null else -1.0]
	note = "picked %d (1 at 88 s), 2 flashes, honk %d, closest behind %.1f m (lane-change gap %.1f m), back in %.1f m ahead; %s; _life_step %.1f us per call" % [
		traffic.tailgate_count, a.tg_honk_count, min_gap_behind, lc_gap, min_gap_ahead, log_line, life_usec / 2000.0]
	return true

# ---------- quick ----------

func _setup_quick() -> void:
	f["limit"] = 25.0
	_player(0, 112.0 * KMH)
	a = _car(0, -90.0, 118.0 * KMH)

func _tick_quick() -> bool:
	if traffic.tailgate_count > 0 or a.tg_phase != TrafficCar.TG_NONE:
		_fail("a car tailgated a player at the flow")
		return true
	if t >= 20.0:
		note = "20 s at 112 km/h in the fast lane: nobody tailgates"
		return true
	return false

# ---------- drift ----------

func _setup_drift() -> void:
	f["limit"] = 40.0
	_player(0, 90.0 * KMH)
	a = _car(2, 70.0, 90.0 * KMH)    # keeps pace 70 m ahead, two lanes over (past WEAVE_CLEAR_M)
	a.set_phone(true, 2.0, 7.0, 0.0)
	a._lc_cooldown = 1000.0   # keeps its lane: this is about the drift
	f["lo"] = INF
	f["hi"] = -INF

func _tick_drift() -> bool:
	if t > 5.0:
		var dx := _x(a) - _lane(2)
		f["lo"] = minf(f.lo, dx)
		f["hi"] = maxf(f.hi, dx)
	if t >= 30.0:
		if f.hi < 0.2 or f.lo > -0.2:
			_fail("it did not drift both ways: %.2f .. %.2f m" % [f.lo, f.hi])
		if f.hi > 0.5 or f.lo < -0.5:
			_fail("it left its lane centre by %.2f .. %.2f m (wanted 0.35 plus tracking)" % [f.lo, f.hi])
		if a.lane_changes != 0:
			_fail("it changed lane while drifting")
		var has_glow := a._phone_glow != null and a._phone_glow.visible
		if not has_glow:
			_fail("no glow on a phone driver")
		note = "drift %.2f .. +%.2f m over 25 s, glow %s" % [f.lo, f.hi, "on" if has_glow else "MISSING"]
		return true
	return false

# ---------- green ----------

func _setup_green() -> void:
	f["limit"] = 30.0
	_player(0, 0.0, 30.0)   # 30 m behind the stop: its horn range covers the cars
	var line := _pz() - 40.0
	var fj := FakeJunction.new()
	fj.line_z = line
	traffic.junction = fj
	f["fj"] = fj
	a = _car(2, 26.0, 0.0)       # the phone driver, at the front of the queue
	a.set_phone(true, 2.3, 8.0, 0.0)
	b = _car(2, 16.0, 0.0)       # the car behind it
	c = _car(1, 26.0, 0.0)       # an ordinary driver at the line next door
	f["phone_moved"] = -1.0
	f["plain_moved"] = -1.0
	a.target_speed = 15.0
	b.target_speed = 15.0
	c.target_speed = 15.0

func _tick_green() -> bool:
	var fj: FakeJunction = f.fj
	if phase == 0 and t >= 6.0:
		phase = 1
		f["green_at"] = t
		fj.red = false
	if phase == 0:
		return false
	if f.phone_moved < 0.0 and a.current_speed() > 1.0:
		f["phone_moved"] = t - f.green_at
	if f.plain_moved < 0.0 and c.current_speed() > 1.0:
		f["plain_moved"] = t - f.green_at
	if t - f.green_at < 9.0:
		return false
	if f.phone_moved < TrafficCar.PHONE_DELAY.x - 0.05 or f.phone_moved > TrafficCar.PHONE_DELAY.y + 1.2:
		_fail("the phone driver moved off %.2f s after green (wanted 1.5-3 plus pick-up)" % f.phone_moved)
	if a.phone_waits != 1 or a.phone_wait_s < TrafficCar.PHONE_DELAY.x - 0.1 or a.phone_wait_s > TrafficCar.PHONE_DELAY.y + 0.1:
		_fail("phone wait %d times, %.2f s" % [a.phone_waits, a.phone_wait_s])
	if f.plain_moved < 0.0 or f.plain_moved > 1.6:
		_fail("the ordinary driver moved off %.2f s after green" % f.plain_moved)
	if traffic.phone_honk_count != 1 or b.honks != 1:
		_fail("the car behind honked %d time(s) (manager %d), wanted one tap" % [b.honks, traffic.phone_honk_count])
	note = "phone driver off %.2f s after green (own wait %.2f s of %.2f), ordinary %.2f s, one tap from the car behind" % [
		f.phone_moved, a.phone_wait_s, a.phone_delay, f.plain_moved]
	return true

# ---------- lane ----------

func _setup_lane() -> void:
	f["limit"] = 30.0
	_player(0, 0.0, 0.0)
	a = _car(1, -140.0, 100.0 * KMH)   # behind the player, one lane over
	a.set_phone(true, 2.0, 8.0, 0.0)
	b = _car(1, -40.0, 20.0 * KMH)     # a slow car in a's lane ahead of it
	b._lc_cooldown = 1000.0
	a.target_speed = 100.0 * KMH
	f["saw0"] = false

func _tick_lane() -> bool:
	# a is in lane 1 with a slow car ahead: lane 0 is toward the player (in lane
	# 0, parked), lane 2 away from it. A phone driver may only take lane 2.
	if a.lane_i == 0 or _x(a) < _lane(1) - 1.0:
		_fail("a phone driver moved toward you at t=%.1f s (lane %d)" % [t, a.lane_i])
		return true
	if t >= 25.0:
		note = "held up by a slow car with you beside it: it stayed off your lane (lane %d, %d change(s))" % [a.lane_i, a.lane_changes]
		return true
	return false

# ---------- pool ----------

func _setup_pool() -> void:
	f["limit"] = 30.0
	traffic.phone_share = 1.0
	traffic.set_car_count(24)
	_player(0, 0.0, 0.0)

func _tick_pool() -> bool:
	if phase == 0 and t >= 2.0:
		phase = 1
		var n := 0
		var glow := 0
		for car in traffic.cars:
			if car.phone:
				n += 1
				if car._phone_glow != null and car._phone_glow.visible:
					glow += 1
		f["phones"] = n
		f["glow"] = glow
		if n == 0:
			_fail("no phone drivers at share 1")
		# the pool hands each car out again as an ordinary driver
		traffic.phone_share = 0.0
		for car in traffic.cars.duplicate():
			if not car.benched:
				traffic._respawn(car)
		var left := 0
		for car in traffic.cars:
			if car.phone or (car._phone_glow != null and car._phone_glow.visible):
				left += 1
		if left != 0:
			_fail("%d car(s) kept the phone flag or glow after respawn" % left)
		# the natural share
		traffic.phone_share = TrafficManager.PHONE_SHARE
		var before := traffic.phone_spawns
		var n_spawn := 0
		for i in 360:
			for car in traffic.cars:
				if not car.benched:
					traffic._respawn(car)
					n_spawn += 1
					if n_spawn >= 1200:
						break
			if n_spawn >= 1200:
				break
		var share := float(traffic.phone_spawns - before) / float(maxi(n_spawn, 1))
		if absf(share - TrafficManager.PHONE_SHARE) > 0.03:
			_fail("phone share %.3f over %d spawns, wanted %.3f" % [share, n_spawn, TrafficManager.PHONE_SHARE])
		note = "%d phone drivers at share 1 (%d with the glow), none after a respawn at share 0; natural share %.3f over %d spawns" % [
			f.phones, f.glow, share, n_spawn]
		return true
	return false

func _end() -> bool:
	if traffic != null and traffic.near_miss != null:
		traffic.near_miss.finish()
	if not logger.errors.is_empty():
		fails.append("%d engine errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	for msg in fails:
		printerr("FAIL: " + msg)
	print("more_alive_traffic: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
