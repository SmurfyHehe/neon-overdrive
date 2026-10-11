extends SceneTree

# Police P6 proof in the real game (spec section 11): the dispatcher never has
# more than 3 driving cops, and no cop is ever put on the road in view.
# 16 traffic cars, the weave bot as the fleeing player, heat held at 1, then
# 2, then 3, then 5 (the test holds it there; what raises heat is P1's).
#
# Checked every tick: at most PoliceRules.MAX_COPS cops; no cop off its wheels;
# none stuck in view for over 5 s; none driven over the patrol car's top speed.
# Checked at every spawn: the place is not in any camera's view and is out
# past the reveal distance; a blocker is put AHEAD of the player, the others
# behind.
# Checked by the end: heat 1 had one cop chasing, heat 2 brought a blocker
# that got in front of the player in its lane, heat 3 a flanker that got
# beside it; then the player slows and stops, the cops close in (box-in) and
# the ring busts it.
# Needs --fixed-fps 60 (about 3 min):
#   <godot> --headless --fixed-fps 60 --path . -s res://tests/traffic/police_dispatch.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const R := CopBrain.Role
## [heat level, seconds held]
const PLAN := [[1, 25.0], [2, 50.0], [3, 60.0], [5, 20.0]]
const CARS := 16
const BOT_KMH := 110.0

var failures: Array[String] = []
var game: Node
var p: PlayerCar
var police: PolicePatrol
var heat: PoliceHeat
var traffic: TrafficManager
var bot: RefCounted
var phase := -1
var t := 0.0
var game_t := 0.0
var hold := 0
var spawns: Array[String] = []
var roles_spawned := {}
var most := 0
var flip_ticks := 0
var stuck := {}
var stuck_max := 0.0
var fastest := 0.0
var chasing_at := {}        # level -> most cops in the chase at once
var block_secs := 0.0
var flank_secs := 0.0
var busts := 0
var first_bust := -1.0
var level_ticks := {}
var cop_touches := 0
var touching := {}
var heat_jumps := 0
var busted := false
var near_at_bust := 0
var stop_t := 0.0
var want_kmh := 30.0

func _check(ok: bool, msg: String) -> void:
	if not ok and not failures.has(msg):
		failures.append(msg)
		printerr("FAIL: " + msg)

func _initialize() -> void:
	OS.set_environment("NEON_POLICE", "1")
	OS.set_environment("NEON_NEAR_MISS_LOG", "")
	game = Harness.boot(self, CARS, 300.0, 5, 300.0)

func _on_spawn(car: PatrolCar, role: int) -> void:
	var u := RoadFrame.unroll(car.global_position)
	var pu := RoadFrame.unroll(p.global_position)
	var ahead := (u.z - pu.z) * -1.0   # the bot drives toward -z
	var seen := traffic.in_view(car.global_position)
	spawns.append("%s at heat %d, %.0f m %s, in view %s" % [CopBrain.ROLE_NAMES[role], heat.level, absf(ahead), "ahead" if ahead > 0.0 else "behind", seen])
	_check(not seen, "a %s was put on the road in view (%.0f m %s)" % [CopBrain.ROLE_NAMES[role], absf(ahead), "ahead" if ahead > 0.0 else "behind"])
	_check(absf(ahead) > traffic.reveal_distance(), "a %s was put %.0f m away, inside the reveal distance %.0f" % [CopBrain.ROLE_NAMES[role], absf(ahead), traffic.reveal_distance()])
	if heat.level >= PoliceHeat.ONE_CAR:
		roles_spawned[role] = true
		_check((ahead > 0.0) == (role == R.BLOCKER), "a %s was put %s the player" % [CopBrain.ROLE_NAMES[role], "ahead of" if ahead > 0.0 else "behind"])

func _on_bust(_c: Node3D) -> void:
	busted = true
	busts += 1
	if first_bust < 0.0:
		first_bust = game_t

func _slow_driver() -> Callable:
	var x := RoadFrame.unroll(p.global_position).x
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

func _physics_process(delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < 60:
			p = null
			return false
		police = game.get("police")
		heat = game.get("police_heat")
		traffic = game.get("traffic")
		_check(police != null, "no police in the game with NEON_POLICE=1")
		if police == null:
			return _finish()
		if traffic.cars.size() < CARS:
			traffic.set_car_count(CARS)
		(game.get("night_clock") as NightClock).night = 2
		police.oncoming_next = false
		police.unit_spawned.connect(_on_spawn)
		police.busted.connect(_on_bust)
		p.set_headlights(true)
		bot = TestDriver.start(game, "weave", {"speed": BOT_KMH, "seed": 5})
		Harness.launch_player(p, 25.0)
		return false
	t += delta
	game_t += delta
	# every tick, whatever the phase
	most = maxi(most, police.units.size())
	_check(police.units.size() <= PoliceRules.MAX_COPS, "%d cops on the road (max %d)" % [police.units.size(), PoliceRules.MAX_COPS])
	var pu := RoadFrame.unroll(p.global_position)
	var in_chase := 0
	for u in police.units:
		var c := u.car
		if u.brain.in_chase():
			in_chase += 1
		if not c.detailed:
			stuck.erase(c)
			touching.erase(c)
			continue
		fastest = maxf(fastest, c.current_speed() * 3.6)
		if c.global_transform.basis.y.y < FreeDriver.FLIP_UP:
			flip_ticks += 1
		if u.brain.in_chase() and c.current_speed() < FreeDriver.STUCK_V and p.current_speed() > 5.0 and traffic.in_view(c.global_position):
			stuck[c] = float(stuck.get(c, 0.0)) + delta
			stuck_max = maxf(stuck_max, float(stuck[c]))
		else:
			stuck.erase(c)
		var cu := RoadFrame.unroll(c.global_position)
		var ahead := (cu.z - pu.z) * -1.0
		var dx := absf(cu.x - pu.x)
		if u.brain.role == R.BLOCKER and ahead > 4.0 and ahead < 40.0 and dx < 1.6:
			block_secs += delta
		if u.brain.role == R.FLANKER and absf(ahead) < 7.0 and dx > 1.4 and dx < 3.6:
			flank_secs += delta
		var hit := Harness.overlaps(c, p, c.half_w + 0.95, c.half_l + 2.2)
		if hit and not touching.has(c):
			cop_touches += 1
		if hit:
			touching[c] = true
		else:
			touching.erase(c)
	if heat.level >= PoliceHeat.ONE_CAR:
		chasing_at[heat.level] = maxi(int(chasing_at.get(heat.level, 0)), in_chase)
		level_ticks[heat.level] = int(level_ticks.get(heat.level, 0)) + 1
	match phase:
		-1:
			if police.units.is_empty() or t < 4.0:
				if t > 90.0:
					_check(false, "no patrol car for 90 s")
					return _finish()
				return false
			# the patrol 60 m behind the bot, so the chase has its first cop
			var c := police.car
			var x := TrafficManager.lane_centre(clampi(RoadChunkBuilder.lane_at(pu.x), 0, traffic.own_lanes - 1), false)
			if traffic._slot_check(c, x, pu.z + 60.0, -1.0, maxf(p.current_speed(), 10.0)).is_empty():
				return false
			c.place(x, -1.0, pu.z + 60.0, c.rest_y, maxf(p.current_speed(), 10.0))
			traffic._put(c)
			heat.reset()
			phase = 0
			t = 0.0
		0, 1, 2, 3:
			var level: int = PLAN[phase][0]
			if heat.level > level:
				heat_jumps += 1   # something raised it past where the test holds it
			if heat.heat < float(level):
				heat._raise_to(float(level))
			if t >= float(PLAN[phase][1]):
				phase += 1
				t = 0.0
				if phase == PLAN.size():
					# box-in: the player slows to 30, then stops
					heat._clear_heat()
					heat._raise_to(3.0)
					busted = false
					bot.call("detach", p)
					want_kmh = 30.0
					p.driver = _slow_driver()
		4:
			if heat.heat < 3.0 and not busted:
				heat._raise_to(3.0)
			if t > 12.0:
				want_kmh = 0.0
			if p.current_speed() < 1.0 and want_kmh <= 0.0:
				stop_t += delta
			if busted:
				for u in police.units:
					if u.car.global_position.distance_to(p.global_position) < 15.0:
						near_at_bust += 1
				return _finish()
			if stop_t > 40.0:
				var where: Array[String] = []
				for u in police.units:
					where.append("%s %s %.0f m" % [CopBrain.ROLE_NAMES[u.brain.role], u.brain.state_name(), u.car.global_position.distance_to(p.global_position)])
				_check(false, "stopped for 40 s at heat 3 and not busted (ring %.2f; cops: %s)" % [police.bust_fill, ", ".join(where)])
				return _finish()
	return false

func _finish() -> bool:
	for s in spawns:
		print("police_dispatch: spawn: " + s)
	print("police_dispatch: %.0f s; most cops at once %d; most in the chase by heat level %s; fastest cop %.0f km/h" % [game_t, most, chasing_at, fastest])
	print("police_dispatch: blocker in front of the player in its lane %.0f s, flanker beside it %.0f s; cop bodies met the player's %d times; heat went past the held level on %d ticks" % [block_secs, flank_secs, cop_touches, heat_jumps])
	print("police_dispatch: flips %d ticks, longest stuck in view %.1f s; busts while fleeing %d (first at %.0f s); at the end busted %s after %.0f s stopped with %d cops within 15 m" % [flip_ticks, stuck_max, busts - (1 if busted else 0), first_bust, busted, stop_t, near_at_bust])
	if bot != null:
		print("police_dispatch: bot " + String(bot.call("summary")))
	_check(most <= PoliceRules.MAX_COPS, "%d cops at once" % most)
	_check(flip_ticks == 0, "a cop was off its wheels for %d ticks" % flip_ticks)
	_check(stuck_max <= FreeDriver.STUCK_SECS + 0.5, "a cop was stuck in view for %.1f s" % stuck_max)
	_check(fastest <= PoliceRules.PATROL_TOP_KMH + 5.0, "a patrol car was driven at %.0f km/h (top %.0f)" % [fastest, PoliceRules.PATROL_TOP_KMH])
	if phase >= 1:
		_check(int(chasing_at.get(1, 0)) >= 1, "heat 1: nobody chased")
		_check(int(chasing_at.get(1, 0)) <= 1, "heat 1: %d cops chased (one car on the icon)" % int(chasing_at.get(1, 0)))
	if phase >= 2:
		_check(roles_spawned.has(R.BLOCKER), "heat 2 for %.0f s and no blocker was sent" % float(PLAN[1][1]))
		_check(int(chasing_at.get(2, 0)) <= 2, "heat 2: %d cops chased (two cars on the icon)" % int(chasing_at.get(2, 0)))
	if phase >= 3:
		_check(roles_spawned.has(R.FLANKER), "heat 3 for %.0f s and no flanker was sent" % float(PLAN[2][1]))
		_check(most == PoliceRules.MAX_COPS, "heat 3 and up never had %d cops (most %d)" % [PoliceRules.MAX_COPS, most])
	if phase >= 4:
		_check(block_secs >= 2.0, "the blocker was in front of the player in its lane for only %.1f s" % block_secs)
		_check(flank_secs >= 2.0, "the flanker was beside the player for only %.1f s" % flank_secs)
		_check(busted, "the player stopped among the cops and was not busted")
	print("police_dispatch: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
