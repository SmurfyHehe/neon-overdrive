extends SceneTree

# Police P5 in the real game: the cop brain's states and the bust ring, with
# the patrol car close behind the player on an empty road (no traffic cars:
# each step is about the cop, and traffic would make it a different run every
# time). The 5 minute chase through 40 cars is the free driver's own proof
# (free_driver_chase.gd).
#
#   A  Speeding past the 5 s warning: Patrol -> Checking -> Pursuit. Lights
#      on, the chase is announced, the cop closes up behind and stays there.
#   B  The player stops: the cop pulls up, the bust ring fills in about 3 s,
#      busted. Heat is gone, lights off, back on Patrol. Moving again before
#      it fills drains it.
#   C  Heat 1 again, then the player is gone (moved 600 m up the road, lights
#      off, driving on at 150): Pursuit -> Lost after 2 s -> Search at the last place seen,
#      lights still on, at the search speed. Unseen long enough, heat cools to
#      nothing: escaped, Patrol, lights off.
#   D  A chase far too fast to be safe (240 km/h with no centre barrier): Called off after 3 s, lights off, and
#      the cop stays out of it while the heat is still there.
# Needs --fixed-fps 60:
#   <godot> --headless --fixed-fps 60 --path . -s res://tests/traffic/police_chase.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const S := CopBrain.State

var failures: Array[String] = []
var game: Node
var player: PlayerCar
var police: PolicePatrol
var heat: PoliceHeat
var traffic: TrafficManager
var step := 0
var t := 0.0
var ticks := 0
var want_kmh := 0.0
var seen_states: Array[int] = []
var started := 0
var ended: Array[bool] = []
var busted := 0
var radio: Array[String] = []
var brain_seen: CopBrain
var fill_max := 0.0
var fill_at_go := 0.0
var search_kmh := 0.0
var search_n := 0
var close_m := INF
var stand_m := INF

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		printerr("FAIL: " + msg)

func _initialize() -> void:
	OS.set_environment("NEON_POLICE", "1")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	game = Harness.boot(self, 0, 300.0, 11)

func _pz() -> float:
	return RoadFrame.unroll(player.global_position).z

## Holds lane 1 and `want_kmh`, braking down to it.
func _driver() -> Callable:
	var x := Harness.lane_x(1)
	return func(c: PlayerCar) -> void:
		var side_v := RoadFrame.dir_to_road(RoadFrame.unroll(c.global_position).z, c.linear_velocity).x
		c.steering_input = TrafficCar.lane_steer(c, x - side_v * Harness.LAT_DAMP_T, -1.0, 2.5, Harness.PLAYER_UNDERSTEER_FF)
		c.handbrake_input = 0.0
		var a := (want_kmh / 3.6 - c.current_speed()) * 2.0
		c.throttle_input = clampf(a, 0.0, 1.0) if a >= -0.3 else 0.0
		c.brake_input = clampf(-a / 9.0, 0.0, 1.0) if a < -0.3 else 0.0
		if want_kmh <= 0.0 and c.current_speed() < 1.0:
			c.throttle_input = 0.0
			c.brake_input = 1.0

## The patrol car `back` m behind the player, in the player's lane, at its speed.
func _cop_behind(back: float) -> void:
	var c := police.car
	c.place(Harness.lane_x(1), -1.0, _pz() + back, c.rest_y, maxf(player.current_speed(), 10.0))
	traffic._put(c)

func _watch_brain() -> void:
	if police.brain != brain_seen and police.brain != null:
		brain_seen = police.brain
		brain_seen.state_changed.connect(func(_from: int, to: int) -> void: seen_states.append(to))
		brain_seen.radio.connect(func(text: String) -> void: radio.append(text))

func _go(n: int) -> void:
	step = n
	t = 0.0
	seen_states.clear()

func _dist() -> float:
	return police.car.global_position.distance_to(player.global_position) if police.car != null else INF

func _physics_process(delta: float) -> bool:
	ticks += 1
	t += delta
	if step == 0:
		if ticks < 5:
			return false
		player = game.get("player")
		police = game.get("police")
		heat = game.get("police_heat")
		traffic = game.get("traffic")
		_check(police != null and heat != null, "no police in the game with NEON_POLICE=1")
		if police == null:
			return _finish()
		(game.get("night_clock") as NightClock).night = 2
		police.oncoming_next = false
		police.pursuit_started.connect(func() -> void: started += 1)
		police.pursuit_ended.connect(func(escaped: bool) -> void: ended.append(escaped))
		police.busted.connect(func(_c: Node3D) -> void: busted += 1)
		Harness.move_player_to_lane(player, Harness.lane_x(1))
		want_kmh = 130.0
		Harness.launch_player(player, want_kmh / 3.6)
		player.driver = _driver()
		player.set_headlights(true)
		_go(1)
		return false
	if police.car == null:
		if t > 40.0:
			_check(false, "step %d: no patrol car for 40 s" % step)
			return _finish()
		return false
	_watch_brain()
	var brain := police.brain
	fill_max = maxf(fill_max, police.bust_fill)
	match step:
		1:
			# A: the cop 50 m behind a car doing 130 in the city
			_check(traffic.cars.has(police.car) and police.car._idx >= 0, "the patrol car is not in the traffic index")
			_cop_behind(50.0)
			heat.reset()
			_go(2)
		2:
			if brain.state == S.PURSUIT and t > 1.0:
				_check(seen_states.has(S.CHECKING), "Pursuit without Checking first (states %s)" % [seen_states])
				_check(police.car.lights_on, "in Pursuit with the lights off")
				_check(police.car.free_driver != null, "in Pursuit without the free driver")
				_check(started == 1, "pursuit_started fired %d times" % started)
				_go(3)
			elif t > 30.0:
				_check(false, "A: 30 s of 130 km/h with a cop 50 m behind: state %s, heat %d, warning %s" % [brain.state_name(), heat.level, heat.warning_active])
				return _finish()
			elif brain.state == S.CHECKING:
				_check(not police.car.lights_on, "Checking with the lights on")
		3:
			if t > 6.0:
				close_m = minf(close_m, _dist())
			if t > 14.0:
				_check(brain.state == S.PURSUIT, "A: 14 s into the chase the cop is in %s" % brain.state_name())
				_check(close_m < 30.0, "A: the chaser never got within 30 m (closest %.0f m)" % close_m)
				_check(police.bust_fill == 0.0 and fill_max == 0.0, "A: the bust ring moved at speed (%.2f)" % fill_max)
				want_kmh = 0.0   # B: stop
				_go(4)
		4:
			if player.current_speed() < 1.0:
				stand_m = minf(stand_m, _dist())
			if busted >= 1:
				_check(t > PoliceRules.BUST_SECS, "B: busted %.1f s after braking (the ring takes %.0f s once stopped)" % [t, PoliceRules.BUST_SECS])
				_check(heat.level == PoliceHeat.NONE, "B: heat %d after the bust" % heat.level)
				_check(not police.car.lights_on and brain.state == S.PATROL, "B: after the bust the cop is in %s, lights %s" % [brain.state_name(), police.car.lights_on])
				_check(ended.size() == 1 and ended[0] == false, "B: pursuit_ended %s (one, not escaped, expected)" % [ended])
				_check(stand_m - PoliceRules.BUST_BODY <= PoliceRules.BUST_RANGE, "B: the cop stood %.1f m off (centre to centre)" % stand_m)
				_go(5)
			elif t > 30.0:
				_check(false, "B: stopped for %.0f s with the cop %.1f m away: ring at %.2f, state %s" % [t, _dist(), police.bust_fill, brain.state_name()])
				return _finish()
		5:
			# B2: the ring drains when you get going again. Heat back to 1, stop, then go at half.
			if t < 0.5:
				return false
			heat._raise_to(1.0)
			want_kmh = 0.0
			_go(6)
		6:
			if police.bust_fill >= 0.5 and fill_at_go == 0.0:
				fill_at_go = police.bust_fill
				want_kmh = 80.0
			if fill_at_go > 0.0 and player.current_speed() * 3.6 > 30.0:
				_check(police.bust_fill < fill_at_go, "B2: the ring did not drain once moving (%.2f -> %.2f)" % [fill_at_go, police.bust_fill])
				_check(busted == 1, "B2: busted while driving off")
				_go(7)
			elif t > 40.0:
				_check(false, "B2: 40 s: ring %.2f, speed %.0f km/h, state %s" % [police.bust_fill, player.current_speed() * 3.6, brain.state_name()])
				return _finish()
		7:
			# C: in a chase, then gone: 600 m up the road, lights off, slowly
			if brain.state != S.PURSUIT:
				if t > 20.0:
					_check(false, "C: no Pursuit at heat %d (state %s)" % [heat.level, brain.state_name()])
					return _finish()
				return false
			if t < 3.0:
				return false
			var u := RoadFrame.unroll(player.global_position)
			player.global_transform = RoadFrame.pose(u.x, player.global_position.y - RoadFrame.roll(Vector3(u.x, 0.0, u.z)).y, u.z - 600.0, 0.0)
			player.set_headlights(false)
			want_kmh = 150.0   # and driving on: a searching cop (60-90 km/h) does not catch it up
			Harness.launch_player(player, want_kmh / 3.6)
			_go(8)
		8:
			if brain.state == S.SEARCH:
				_check(police.car.lights_on, "Search with the lights off")
				if brain.search_t > 6.0:   # once it has slowed from the chase
					search_kmh += police.car.lane_speed() * 3.6
					search_n += 1
			if heat.level == PoliceHeat.NONE:
				_check(seen_states.has(S.LOST) and seen_states.has(S.SEARCH), "C: escaped without Lost and Search (states %s)" % [seen_states])
				_check(seen_states.find(S.LOST) < seen_states.find(S.SEARCH), "C: Search before Lost (states %s)" % [seen_states])
				_go(9)
			elif t > PoliceRules.UNSEEN_DROP_SECS[1] + 30.0:
				_check(false, "C: unseen for %.0f s and heat is still %d (state %s, sees %s)" % [t, heat.level, brain.state_name(), brain.sees])
				return _finish()
		9:
			if t < 0.5:
				return false
			_check(brain.state == S.PATROL and not police.car.lights_on, "C: after the escape the cop is in %s, lights %s" % [brain.state_name(), police.car.lights_on])
			_check(ended.size() == 2 and ended[1] == true, "C: pursuit_ended %s (the second one escaped, expected)" % [ended])
			if search_n > 0:
				var lim := float(PoliceRules.SEARCH_KMH[PoliceRules.CITY])
				_check(search_kmh / search_n <= float(PoliceRules.SEARCH_KMH[PoliceRules.HIGHWAY]) + 10.0, "C: searching at %.0f km/h on average (search speed %.0f to %.0f)" % [search_kmh / search_n, lim, float(PoliceRules.SEARCH_KMH[PoliceRules.HIGHWAY])])
			# D: a chase far too fast
			player.set_headlights(true)
			want_kmh = 400.0
			Harness.launch_player(player, 340.0 / 3.6)
			_cop_behind(15.0)
			police.car.linear_velocity = player.linear_velocity * 0.8
			heat._raise_to(1.0)
			# an open centre here: speed alone (about 240 km/h is all this car has) is under the line
			brain.undivided_at = func(_z: float) -> bool: return true
			_go(10)
		10:
			if brain.called_off >= 1:
				_check(seen_states.has(S.PURSUIT) and seen_states.has(S.CALLED_OFF), "D: called off without Pursuit (states %s)" % [seen_states])
				_check(not police.car.lights_on, "D: called off with the lights on")
				_check(radio.has("Pursuit terminated. Copy."), "D: no radio line (%s)" % [radio])
				_go(11)
			elif t > 20.0:
				_check(false, "D: 20 s at %.0f km/h: danger %.2f (line %.1f), state %s, sees %s" % [player.current_speed() * 3.6, brain.danger, PoliceRules.DANGER_LINE, brain.state_name(), brain.sees])
				return _finish()
		11:
			# it stays out while the heat is still there
			if t > 3.0:
				_check(heat.level >= PoliceHeat.ONE_CAR, "D: heat already gone 3 s after the call-off (cannot tell if it stays out)")
				_check(brain.state == S.PATROL, "D: 3 s after calling off the cop is in %s" % brain.state_name())
				_check(heat.stood_down.has(police.car) and not heat.seen, "D: the called-off cop is still watching for the heat (stood down %s, seen %s)" % [heat.stood_down.has(police.car), heat.seen])
				return _finish()
	return false

func _finish() -> bool:
	print("police_chase: closest in the chase %.0f m, stood %.1f m off at the bust, searching at %.0f km/h, busts %d, pursuits started %d, ended %s" % [close_m, stand_m, search_kmh / maxi(search_n, 1), busted, started, ended])
	print("police_chase: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
