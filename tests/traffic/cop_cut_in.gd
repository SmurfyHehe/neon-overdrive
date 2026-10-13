extends SceneTree

# Issue #625 replay: cops cut into your lane in front of you and brake. All 4
# crashes the clean test bot had in an hour of headless driving were into a
# cop (notes/driving-ai-measured-2026-10-13.md, section 5):
#   - a chaser (heat 1) in the next lane slightly AHEAD of you: its spot is
#     12 m behind you, so it braked from 44 to 12 km/h while sliding into your
#     lane 17 m in front of you at 98 km/h;
#   - a blocker (heat 2) crossed into your lane 24 m ahead doing 13-25 km/h
#     while you did 150 km/h.
#
# This puts the cop exactly there (the next lane, that far ahead, that slow),
# on both sides, with the clean bot driving the player, then a blocker sent
# ahead the way the dispatcher sends one, and a heavy unit from behind. Every tick,
# for every cop in the full sim:
#   cut in   in front of the player, in its corridor, slower than it, and
#            closer than the player needs to shed that closing speed at
#            TARGET_DECEL plus REACT_S of it (+2 m). Must never happen.
#   brake    in front, in the corridor, within BRAKE_HEADWAY s of the player,
#            and slowing harder than BRAKE_DECEL for BRAKE_HOLD s. Must never
#            happen.
#   hit      the player's nose meets a cop in front of it. Must never happen.
#   panic    the player (the bot keeps its distance) brakes harder than
#            PANIC_DECEL with a cop in front of it in its corridor. Never.
# And the cops still do their jobs: the chaser ends up behind you near its
# spot, the blocker gets in front of you in your lane (at a safe gap) and
# holds there, the heavy unit gets to your tail.
# Needs --fixed-fps 60 (about 3 min):
#   <godot> --headless --fixed-fps 60 --path . -s res://tests/traffic/cop_cut_in.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const R := CopBrain.Role
const CARS := 16
## The bounds every cop is held to (issue #625 fix direction).
const TARGET_DECEL := 4.0       # m/s^2 the player may be asked to brake at
const REACT_S := 0.5            # s of closing speed on top, to react
const BRAKE_HEADWAY := 2.0      # s of the player's speed: "close in front"
const BRAKE_DECEL := 2.5        # m/s^2: a cop close in front never slows harder...
const BRAKE_HOLD := 0.25        # ...for longer than this
const PANIC_DECEL := 5.0        # m/s^2 the bot never needs with a cop in front
const CORRIDOR_AIR := 0.2       # m on top of both half widths

## [name, role, heat, player km/h, player lane, cop lane offset, cop body gap
## ahead (m, negative = behind), cop km/h, seconds]
const SCENES := [
	["chaser ahead, left", R.CHASER, 1, 98.0, 1, -1, 17.0, 44.0, 14.0],
	["chaser ahead, right", R.CHASER, 1, 98.0, 1, 1, 17.0, 44.0, 14.0],
	["blocker ahead, left", R.BLOCKER, 2, 150.0, 1, -1, 24.0, 20.0, 18.0],
	["blocker ahead, right", R.BLOCKER, 2, 150.0, 1, 1, 24.0, 20.0, 18.0],
	["blocker sent ahead", R.BLOCKER, 2, 130.0, 1, 1, 150.0, 78.0, 30.0],
	["heavy from behind", R.HEAVY, 4, 120.0, 1, 0, -40.0, 120.0, 20.0],
]

var failures: Array[String] = []
var game: Node
var p: PlayerCar
var police: PolicePatrol
var heat: PoliceHeat
var traffic: TrafficManager
var bot: RefCounted
var scene := -1
var state := 0                  # 0 wait for a patrol, 1 place it, 2 run
var t := 0.0
var game_t := 0.0
var cop: PatrolCar
var unit: PolicePatrol.Unit
var lines: Array[String] = []
# per scene
var cut_ticks := 0
var worst_cut := ""
var brake_t := {}
var brake_events := 0
var worst_brake := 0.0
var hits := 0
var hitting := {}
var panic_ticks := 0
var worst_panic := 0.0
var v_prev := {}
var decel := {}
var pv_prev := NAN
var p_decel := 0.0
var behind_near := 0.0          # s the chaser / heavy sat 0-40 m behind
var block_safe := 0.0           # s the blocker held in front, in the lane
var min_gap_ahead := INF

func _check(ok: bool, msg: String) -> void:
	if not ok and not failures.has(msg):
		failures.append(msg)
		printerr("FAIL: " + msg)

func _initialize() -> void:
	OS.set_environment("NEON_POLICE", "1")
	OS.set_environment("NEON_NEAR_MISS_LOG", "")
	game = Harness.boot(self, CARS, 300.0, 1, 300.0)

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
		p.set_headlights(true)
		_next_scene()
		return false
	t += delta
	game_t += delta
	if game_t > 600.0:
		_check(false, "ran out of time in scene %d" % scene)
		return _finish()
	match state:
		0:
			# the next patrol on the road (any; the scene puts it where it wants)
			if heat.level > PoliceHeat.NONE:
				heat._clear_heat()
			if police.units.is_empty():
				police.set("_wait", 0.0)
				return false
			state = 1
		1:
			if _place():
				state = 2
				t = 0.0
		2:
			_measure(delta)
			var sc: Array = SCENES[scene]
			if heat.heat < float(sc[2]):
				heat._raise_to(float(sc[2]))
			if t >= float(sc[8]):
				_end_scene()
				if scene + 1 >= SCENES.size():
					return _finish()
				_next_scene()
	return false

func _next_scene() -> void:
	scene += 1
	var sc: Array = SCENES[scene]
	if bot != null:
		bot.call("detach", p)
	heat._clear_heat()
	heat.reset()
	for u in police.units.duplicate():
		police._drop(u)
	police.set("_wait", 0.0)
	police.oncoming_next = false
	# upright and repaired on the road where it is (a scene before may have
	# left it spun), then on the scene's lane
	if p.damage.is_engine_dead() or p.damage.any_tyre_flat():
		p.damage.garage_repair(null)
		p.health.repair()
	var pz := RoadFrame.unroll(p.global_position).z
	p.global_transform = RoadFrame.pose(TrafficManager.lane_centre(int(sc[4]), false), OffMapRescue.PARK_Y, pz, 0.0)
	TrafficCar.set_moving(p, 0.0)
	for w in p.wheel_array:
		w.last_collision_point = w.global_position
	p.reset_physics_interpolation()
	p.damage.forget_motion()
	bot = TestDriver.start(game, "clean", {"speed": float(sc[3]), "seed": 1, "lane": int(sc[4])})
	Harness.launch_player(p, float(sc[3]) / 3.6)
	state = 0
	t = 0.0
	cut_ticks = 0
	worst_cut = ""
	brake_t.clear()
	brake_events = 0
	worst_brake = 0.0
	hits = 0
	hitting.clear()
	panic_ticks = 0
	worst_panic = 0.0
	v_prev.clear()
	decel.clear()
	pv_prev = NAN
	p_decel = 0.0
	behind_near = 0.0
	block_safe = 0.0
	min_gap_ahead = INF

## Puts the scene's cop where the issue saw it. False = that spot is taken
## by traffic this tick; tried again next tick.
func _place() -> bool:
	var sc: Array = SCENES[scene]
	if police.units.is_empty():
		state = 0
		return false
	unit = police.units[0]
	var role: int = sc[1]
	if role == R.HEAVY and unit.car.kind != PolicePatrol.HEAVY_KIND:
		# the heavy is its own body: put one on the road in place of the patrol
		police._drop(unit)
		if not police.spawn_unit(R.HEAVY):
			return false
		unit = police.units[0]
	cop = unit.car
	var pu := RoadFrame.unroll(p.global_position)
	var lane := clampi(int(sc[4]) + int(sc[5]), 0, traffic.own_lanes - 1)
	var x := TrafficManager.lane_centre(lane, false)
	var body: float = sc[6]
	var centre := body + signf(body) * (cop.half_l + TrafficManager.PLAYER_HALF_L)
	var z := pu.z - centre   # the player drives toward -z
	var v: float = float(sc[7]) / 3.6
	if traffic._slot_check(cop, x, z, -1.0, v).is_empty():
		return false
	cop.place(x, -1.0, z, cop.rest_y, v)
	traffic._put(cop)
	unit.brain.role = role
	heat._raise_to(float(sc[2]))
	unit.brain.step(0.0)   # into Pursuit now, with its role
	lines.append("%s: placed %.0f m %s in lane %d at %.0f km/h, player lane %d at %.0f km/h" % [sc[0], absf(body), "ahead" if body > 0.0 else "behind", lane, sc[7], sc[4], p.current_speed() * 3.6])
	return true

func _measure(delta: float) -> void:
	var pu := RoadFrame.unroll(p.global_position)
	var pv := -RoadFrame.dir_to_road(pu.z, p.linear_velocity).z
	if pv_prev == pv_prev:
		p_decel = lerpf(p_decel, (pv_prev - pv) / delta, 0.3)
	pv_prev = pv
	var cop_in_front := false
	for u in police.units:
		var c := u.car
		if not c.detailed or not u.brain.in_chase():
			continue
		var cu := RoadFrame.unroll(c.global_position)
		var cv := -RoadFrame.dir_to_road(cu.z, c.linear_velocity).z
		if v_prev.has(c):
			decel[c] = lerpf(float(decel.get(c, 0.0)), (float(v_prev[c]) - cv) / delta, 0.3)
		v_prev[c] = cv
		var ahead := -(cu.z - pu.z)
		var gap := ahead - c.half_l - TrafficManager.PLAYER_HALF_L
		var dx := absf(cu.x - pu.x)
		var corridor := dx < c.half_w + 0.95 + CORRIDOR_AIR
		var closing := pv - cv
		if ahead > 0.0 and corridor:
			cop_in_front = true
			min_gap_ahead = minf(min_gap_ahead, gap)
			var need := closing * closing / (2.0 * TARGET_DECEL) + closing * REACT_S + 2.0
			if closing > 2.0 and gap < need:
				cut_ticks += 1
				if worst_cut == "":
					worst_cut = "%s %.1f m ahead doing %.0f km/h, player %.0f km/h (needs %.0f m)" % [CopBrain.ROLE_NAMES[u.brain.role], gap, cv * 3.6, pv * 3.6, need]
			var d := float(decel.get(c, 0.0))
			if gap < pv * BRAKE_HEADWAY and d > BRAKE_DECEL:
				brake_t[c] = float(brake_t.get(c, 0.0)) + delta
				worst_brake = maxf(worst_brake, d)
				if float(brake_t[c]) >= BRAKE_HOLD and float(brake_t[c]) - delta < BRAKE_HOLD:
					brake_events += 1
			else:
				brake_t.erase(c)
			if u.brain.role == R.BLOCKER and gap > 0.0 and dx < 1.6:
				block_safe += delta
		else:
			brake_t.erase(c)
		if (u.brain.role == R.CHASER or u.brain.role == R.HEAVY) and ahead < 0.0 and ahead > -40.0:
			behind_near += delta
		var hit := Harness.overlaps(c, p, c.half_w + 0.95, c.half_l + TrafficManager.PLAYER_HALF_L)
		if hit and not hitting.has(c) and ahead > 0.0:
			hits += 1
		if hit:
			hitting[c] = true
		else:
			hitting.erase(c)
	if OS.get_environment("COP_CUT_DEBUG") != "" and Engine.get_physics_frames() % 30 == 0:
		for u in police.units:
			var cu2 := RoadFrame.unroll(u.car.global_position)
			var d2 := u.brain.driver
			print("  t=%.1f %s %s det=%s ahead=%.1f dx=%.1f v=%.0f pv=%.0f%s" % [t, CopBrain.ROLE_NAMES[u.brain.role], u.brain.state_name(), u.car.detailed, -(cu2.z - pu.z), cu2.x - pu.x, u.car.current_speed() * 3.6, pv * 3.6,
				(" gap_along=%.1f off=%.1f line=%.1f aim=%.1f blocked=%s pass=%.0f front=%s ok=%s refused=%d vmax=%.0f lead=%.0f@%.0f bend=%.0f" % [d2.gap_along, d2.offset_back, d2.line_x - pu.x, d2.aim_x - pu.x, d2.blocked, d2.pass_side, d2.in_front, d2.cut_ok, d2.refused, d2.v_max * 3.6, d2._lead_gap, d2._lead_v * 3.6, d2._bend_v * 3.6]) if d2 != null else ""])
	if cop_in_front and p_decel > PANIC_DECEL:
		panic_ticks += 1
		worst_panic = maxf(worst_panic, p_decel)

func _end_scene() -> void:
	var sc: Array = SCENES[scene]
	var name: String = sc[0]
	lines.append("%s: cut-in ticks %d%s; brake-checks %d (hardest %.1f m/s^2); rear-ended a cop %d; bot panic-braked %d ticks (hardest %.1f m/s^2); closest cop in front %.1f m; chaser/heavy behind 0-40 m %.1f s; blocker in place %.1f s; bot %s" % [
		name, cut_ticks, (" (first: %s)" % worst_cut) if worst_cut != "" else "", brake_events, worst_brake, hits, panic_ticks, worst_panic,
		min_gap_ahead, behind_near, block_safe, String(bot.call("summary")) if bot != null else ""])
	_check(cut_ticks == 0, "%s: a cop cut in front of the player inside its stopping distance (%d ticks; %s)" % [name, cut_ticks, worst_cut])
	_check(brake_events == 0, "%s: a cop close in front of the player braked harder than %.1f m/s^2 (%d times, hardest %.1f)" % [name, BRAKE_DECEL, brake_events, worst_brake])
	_check(hits == 0, "%s: the player rear-ended a cop %d times" % [name, hits])
	_check(panic_ticks == 0, "%s: the bot had to brake harder than %.1f m/s^2 for a cop in front (%d ticks, hardest %.1f)" % [name, PANIC_DECEL, panic_ticks, worst_panic])
	match int(sc[1]):
		R.CHASER, R.HEAVY:
			_check(behind_near >= 3.0, "%s: the cop never settled behind the player (%.1f s within 40 m behind)" % [name, behind_near])
		R.BLOCKER:
			# from 20 km/h right beside you a blocker cannot get back in front
			# of a car doing 150 (it has the patrol car's acceleration, nothing
			# more): those scenes only check that it never cuts in. Sent ahead
			# the way the dispatcher sends it (the lane beside yours, out of
			# sight, at 0.6 of your pace) it gets in front of you.
			if float(sc[6]) > 100.0:
				_check(block_safe >= 2.0, "%s: the blocker was in front of the player in its lane for only %.1f s" % [name, block_safe])

func _finish() -> bool:
	for l in lines:
		print("cop_cut_in: " + l)
	print("cop_cut_in: %.0f s of game time" % game_t)
	print("cop_cut_in: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
