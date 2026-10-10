extends Vehicle
class_name TrafficCar

# Traffic car (stage B step 3; milestone 3 lane follow 2026-10-05, milestone 4
# braking, lane changes and wrecks 2026-10-06; Roy: Option C).
#
# A traffic car IS the vendored raycast Vehicle the player drives
# (scripts/vendor/gevp/), built the same way PlayerCar is: CarSpec data,
# CarSpec.build_collision(), CarSpec.build_wheels(), initialize(). What differs
# from the player is only the spec dict (CarSpec.traffic_default() unless the
# spawner hands in another one), the body kind/colour, and who sets
# throttle_input/brake_input/steering_input -- the controller below instead of
# the keyboard. There is no cheaper physics path for a car the player can see.
#
# Steering: pure pursuit (R. C. Coulter, "Implementation of the Pure Pursuit
# Path Tracking Algorithm", CMU-RI-TR-92-01, 1992): aim at the point on the
# path `lookahead` metres ahead and steer with the curvature of the circular
# arc through it; the lookahead grows with speed so the car does not weave at
# highway speed. The path is the lane centre, or during a lane change a
# half-cosine S from the old lane centre to the new one over LC_TIME seconds;
# the target point is taken where the S will be when the car gets there.
#
# Speed: a constant-time-gap follower, the usual adaptive-cruise law (e.g.
# Rajamani, "Vehicle Dynamics and Control", 2nd ed., ch. 5-6): the speed it
# wants is the car ahead's speed plus K_GAP x (gap - (S0 + T_GAP x speed)),
# capped at its own cruise speed, and the acceleration it asks for is K_V x
# the speed error. Two physical guards sit on top: it never brakes harder than
# B_COMF unless it has to, and when the deceleration needed to stop closing
# before S_STOP (closing^2 / 2 x gap) gets near that, it brakes at least 1.3x
# that. Positive demand goes to throttle_input, negative past A_COAST to
# GEVP's brake_input (the same brakes and ABS the player has). "The car ahead"
# is whatever the TrafficManager's occupancy index finds in this car's
# corridor: other traffic either way, the player, a wreck. The player counts
# as a car that may not brake (see TrafficManager.react_to_player).
#
# Lane changes (own-direction and oncoming cars alike, each only within its
# own side of the road, never across the centre line): a simplified MOBIL
# (Kesting, Treiber, Helbing, "General lane-changing model MOBIL for
# car-following models", Transportation Research Record 1999, 2007): a change
# must be SAFE (the new follower would not need more than B_SAFE to stay
# behind, and this car would not need more than B_SAFE for its new leader; a
# player behind needs PLAYER_TTC seconds of closing time, since nothing says
# it will brake) and WORTH IT, in this order: get round a stopped or crawling
# obstacle, move over for something closing fast from behind (that includes
# the player), pass a slower car, or drop back right onto a free lane.
#
# Wrecks: a car that is flipped, or slow and pointing the wrong way or off its
# path, for WRECK_SECONDS stops trying (hazard stop: brakes on), and the
# TrafficManager recycles it once the player cannot see it.
#
# Rails (near-band traffic, 2026-10-09; Roy: keep the full physics rate): only
# a car within TrafficManager.physics_distance (about 60 m) of the player runs
# the raycast sim and can crash. Further out it is frozen as a kinematic body
# that drives its lane on rails with the same follower law on its speed and
# the same lane-change decisions, steering the same half-cosine S. Inside the
# draw distance (TrafficManager.detail_distance) a car on rails stays visible,
# wheels turning and brake lamps working; beyond it it is hidden and only
# moves over for a closing player, instantly. The sim resumes, with position,
# speed, heading and any lane change handed over, when the car comes back
# inside the band. Going the other way a car only leaves the sim once it is
# upright and back on its path: a crashed or knocked car stays in the sim, so
# nothing snaps upright in view. Why not "run the sim every other tick" for
# far cars: the Wheel applies its spring and tyre forces per physics step, so
# a car that skips a step gets gravity without suspension on that step and
# sags; the honest cheap path is no sim at all plus a clean handover.
#
# Rails, the cheap half (80-car pass, 2026-10-10): with 80 cars about 70 are on
# rails, and at ~90 us a tick each they cost more than the 7 in the sim. So a
# rail car keeps its own road-space z (no world -> road search to find out
# where it is), and it thinks (the follower's scan, the bend look-ahead, lane
# changes, lamps) only RAIL_THINK_HZ times a second, staggered across cars,
# holding the acceleration it chose in between. A drawn one still moves every
# tick; a hidden one (past the fog, half the cars at 80) thinks
# RAIL_THINK_HZ_HIDDEN times a second and moves once per think by the ticks
# since the last one, with its wheels' own _process off. Nothing in the sim
# changes.

const WetReflections := preload("res://scripts/world/wet_reflections.gd")

## Which car: an NpcCarBuilder.KINDS key (the stage B step 5 traffic cars,
## e.g. "n1_commuter") or a CarBuilder.KIND_CONFIGS key (the old box cars).
var kind := "coupe"
## The sheet variant of an NPC car (NpcCarBuilder.builds), e.g. "taxi".
var build := "stock"
## Undercarriage role: "" = from the kind (n* traffic, c* cop, else player
## class). A spawner that puts a player-class body on the road as an ally or
## rival sets Undercarriage.ROLE_CREW; a cop spawner sets ROLE_COP.
var role := ""
## Vehicle tune (CarSpec dict). Empty = CarSpec.npc_spec(kind). Set before
## add_child(), like PlayerCar.spec.
var spec := {}
## Chassis origin height when settled on the springs (place() callers use it).
var rest_y := TrafficManager.REST_Y
var color := Color(0.6, 0.6, 0.65)
## No body mesh, lights or shadow (tests and the perf harness).
var sim_only := false
## Races (race_controller.gd): a live rival is never recycled or frozen; once
## released it drives on and is removed when out of range instead of respawning.
var race_pinned := false
var race_released := false
## The spawner, for the occupancy queries. Null = plain lane follow at
## target_speed (nothing to brake for, no lane changes).
var traffic: TrafficManager

## Road-space x (RoadFrame) of the lane centre this car holds, or is
## changing INTO. Every x and z this car reasons in is road space: across and
## along the road, the same as world axes only while the road is straight.
var lane_x := 0.0
## Lane index on this car's side of the road, 0 next to the centre line.
var lane_i := 0
## -1.0 drives the player's way (forward is -Z, the road-chunk convention);
## +1.0 is oncoming. Set together with the spawn yaw by TrafficManager.
var direction := -1.0
## Cruise speed, m/s.
var target_speed := 25.0

## Aero, same two plain vars PlayerCar declares: CarSpec.apply() sets them
## through v.set() and AeroModel reads them. Traffic gets small values from
## traffic_default().
var aero_downforce_coefficient_front := 0.0
var aero_downforce_coefficient_rear := 0.0

var chassis_visual: Node3D
## Exhaust flames, only on a car whose spec has a flame value (null otherwise).
var flames: ExhaustFlames
## Exhaust heat 0..1 for the heat shimmer (HeatShimmer.next_heat); only
## stepped while detailed, so a far cruising car pays nothing.
var heat := 0.0
var wheelbase := 2.5
## Footprint half sizes for the occupancy index: across the tyres, and
## bumper to the middle.
var half_w := 1.03
var half_l := 1.7
## True while the full sim runs (inside the physics band). See set_detailed().
var detailed := true
## True while the car is drawn (inside the draw distance). See set_shown().
var shown := true
## Rain and puddles on each tyre, the same rules as the player (wet_grip.gd).
var wet := WetGrip.new()
const WetGrip := preload("res://scripts/car/wet_grip.gd")
const Weather := preload("res://scripts/world/weather.gd")
var _cruise_speed := 0.0
## On rails: what is left of the sideways and height offset the car had when
## it left the sim, eased out over RAIL_EASE seconds so nothing snaps in view.
var _rail_dx := 0.0
var _rail_dy := 0.0
var _rail_dyaw := 0.0
## On rails: road-space z, the coordinate the car is driven along. NAN = not
## known (just left the sim, placed, or the floating origin moved): the next
## rail tick reads it back from the world position once.
var _rail_z := NAN
## On rails: ticks until the next think, and the acceleration held meanwhile.
var _think_in := 0
var _rail_a := 0.0
## Hidden on rails: ticks of travel not yet applied to the car (it moves once
## per think). rail_z_now() counts them in; being shown pays them at once.
var _owed := 0
## On rails across a floating-origin shift: the physics tick of the shift and
## the collision layer and mask put away for it (see shift_world). -1 = none.
var _ghost_frame := -1
var _ghost_layer := 0
var _ghost_mask := 0
## Slot in the TrafficManager's occupancy index (set by it every tick).
var _idx := -1
## Physics frame before which a car parked by a deferred spawn does not
## retry (TrafficManager).
var retry_frame := 0
## Off the road for this hour band (TrafficManager.active_share): parked
## hidden and frozen until the band wants more cars.
var benched := false
## Rule breaker (living world step 3): picked at each spawn from the event
## share (WorldMood). Speeds, tailgates, passes sooner and cuts in tighter, but
## keeps the full margins to the player (PLAYER_TTC, PLAYER_MIN_GAP), so it
## reads as a character, never as a car aimed at you.
var rule_breaker := false
## Drifts this many metres either side of its lane (bar close); 0 = holds it.
var weave := 0.0
var _weave_t := 0.0
## TrafficManager: a car found in sight is not looked at again until this tick.
var seen_recheck_frame := 0
## Index entry of the car ahead found by the last full scan; between scans
## its gap and speed are read straight from the index (see _accel_command).
var _lead_k := -1
var _scan_in := 0

## What the follower saw this tick (tests read these): bumper gap to the car
## ahead in this car's corridor (INF = none within LOOK_AHEAD), its speed
## along this car's direction, and whether it is the player.
var lead_gap := INF
var lead_speed := 0.0
var lead_is_player := false
## True while a red (or amber) light ahead holds this car: it is stopping or
## queueing for the stop line (Junction.stop_gap). The stuck-car check and
## obstacle lane changes are off meanwhile: the head of a red queue has
## nothing ahead of it and would otherwise be flagged stuck after
## STUCK_SECONDS (12 s) of a 22 s red.
var signal_held := false

## Lane change in progress (lane_x / lane_i already name the new lane).
var changing := false
var lane_changes := 0
var _lc_from := 0.0
var _lc_t := 0.0
var _lc_dur := 3.0
## Counts down to 0 after a change, then on below 0: -t is the time since the
## car last changed lane (or was placed).
var _lc_cooldown := 0.0
var _decide_t := 0.0
var _m_gap := INF
var _m_speed := 0.0

var wrecked := false
## True while the hazard brake holds (crashed, stuck or wrecked).
var hazard := false
## Lamp state last sent to the body (NpcCarBuilder.set_lamps), so the
## instance uniforms are only written when it changes.
var _lamp_key := -1
var _wreck_t := 0.0
var _stuck_t := 0.0

## Pure-pursuit lookahead: this many seconds of travel, clamped. GEVP turns the
## wheels toward the input at a rate that falls with speed (process_steering),
## so a short lookahead weaves at highway speed: with 0.6 s / 30 m max the
## scripted player oscillated 2 m either side of the lane for 20 s at 150 km/h
## (tests/scratch run, 2026-10-05). 1 s / 60 m is damped; 8 m is the floor so
## a car crawling after a spawn still aims somewhere ahead.
const LOOKAHEAD_SECONDS := 1.0
const LOOKAHEAD_MIN := 8.0
const LOOKAHEAD_MAX := 60.0
## Throttle per m/s of speed error: full throttle from 1.25 m/s under target.
## 0.35 sat 1.4 m/s under target at 85 km/h (drag needs about half throttle
## there); the engine's own drag does the slowing down.
const SPEED_P := 0.8

## Follower (see the header). Gaps are bumper to bumper.
const S0 := 4.0             # m kept at a standstill
const T_GAP := 1.5          # s of own speed kept on top of S0
const K_GAP := 0.15         # 1/s: gap error -> speed command
const K_V := 0.6            # 1/s: speed error -> acceleration command
const B_COMF := 2.5         # m/s^2: normal firm braking
const S_STOP := 3.0         # m: the gap the required-deceleration guard stops at
# Pedal map, measured on traffic_default() at 30 m/s, 120 Hz (2026-10-06,
# brake held 0.5 s): off both pedals it slows at ~0.9 m/s^2 (drag + engine
# braking), and each unit of brake_input adds ~7.3 m/s^2 (0.25 -> 2.9,
# 0.5 -> 4.7, 1.0 -> 8.2 m/s^2 in total).
const A_COAST := 0.8        # m/s^2: gentler slowing is left to drag and engine braking
const A_BRAKE_GAIN := 7.3   # m/s^2 per unit of brake_input on top of A_COAST
const A_BRAKE_FULL := 8.0   # m/s^2: about what brake_input 1 gives
const LOW_SPEED := 5.0      # m/s: below it, slow down on the brake (GEVP creeps off the pedals)
const CREEP_BRAKE := 0.12   # just over GEVP's creep cut-out (brake_input 0.1)
const HOLD_BRAKE := 0.4     # brake held at a standstill
const LOOK_AHEAD := 150.0   # m searched for a car ahead
const LOOK_BEHIND := 300.0  # m searched for a car behind (lane changes; a fast player)
const CORRIDOR_MARGIN := 0.25  # m either side of the tyres
## Full corridor scan every this many ticks (staggered across cars); the
## ticks between only refresh the gap to the car already found.
const LEAD_SCAN_TICKS := 3

## Lane changes (see the header).
const DECIDE_PERIOD := 0.25
const LC_TIME := 3.0          # s for the 3.2 m S: peak sideways 1.75 m/s^2
const LC_TIME_URGENT := 2.0   # obstacle or yielding: 3.9 m/s^2
const LC_COOLDOWN := 4.0
const KEEP_RIGHT_AFTER := 6.0  # s after the last change before moving back right
const KEEP_RIGHT_GAP := 80.0   # m of free lane wanted to move back right
const PASS_DV := 2.0           # m/s under cruise speed before a slower car counts as in the way
const PASS_GAIN := 2.0         # m/s a new lane must offer to pass into it
const OBSTACLE_SPEED := 3.0    # m/s: anything slower ahead is an obstacle to get round
const OBSTACLE_RANGE := 100.0
const YIELD_DV := 3.0          # m/s closing from behind ...
const YIELD_TTC := 5.0         # ... with this little time to contact: move over
## A hidden car (beyond the draw distance) moves over for a closing player
## this early, instantly: nobody sees it, and the player's lane is clear by
## the time the car comes into view.
const YIELD_TTC_HIDDEN := 10.0
const YIELD_SLOWDOWN := 3.0    # m/s a car accepts losing to move over
const B_SAFE := 2.5            # m/s^2 a change may ask of anyone
const LC_MIN_GAP_T := 0.5      # s of speed (plus S0) kept to the new leader/follower
const PLAYER_TTC := 8.0        # s of closing time a player behind must have
const PLAYER_MIN_GAP := 15.0
## Rule breakers (see rule_breaker).
const RB_SPEED := 6.9          # m/s over the lane speed (+25 km/h)
const RB_T_GAP := 0.6          # s kept to the car ahead instead of T_GAP: tailgating
const RB_LC_MIN_GAP_T := 0.25  # s instead of LC_MIN_GAP_T: cuts in
const RB_LC_COOLDOWN := 1.5
const RB_PASS_DV := 0.5
const WEAVE_PERIOD := 5.0      # s for one drift left and back
const MIN_LC_SPEED := 8.0     # m/s; below it only obstacles trigger a change

## Bends (#37): cornering traffic will take, m/s^2 (a calm driver's 0.2 g;
## at 2.5 a car at 109 km/h on a 385 m bend still ran 0.76 m wide), and how
## far ahead it looks for the tightest bend, at BEND_SAMPLES points.
const BEND_LAT_ACCEL := 2.0
const BEND_LOOK := 80.0
const BEND_SAMPLES := 3

## Wrecks.
const WRECK_SECONDS := 3.0
const WRECK_UP := 0.5          # basis.y.y below this: on its side or roof
const WRECK_HEADING := 0.7     # cos 45 deg: pointing further off than this
const WRECK_OFF_PATH := 2.0    # m off the lane / lane-change path
const WRECK_MAX_SPEED := 4.0
const STUCK_SECONDS := 12.0    # stopped this long with nothing ahead

## Leaving the sim for the rails (see the header): only this upright, this
## close to its path and pointing this well down its lane.
const RAIL_UP := 0.995         # road-space up, about 6 deg of roll or pitch
const RAIL_OFF_PATH := 0.75    # m
const RAIL_YAW := 0.1          # rad off the heading the rails would give
## s: time constant the hand-over offset eases out with on rails.
const RAIL_EASE := 0.6
## A car on rails thinks this many times a second (a follower law with a
## 1.5 s time gap does not need more): every 4th tick at the game's 120 Hz.
const RAIL_THINK_HZ := 30.0
## A hidden one this often (it moves 2 m a step at 110 km/h, out past the fog
## where nothing is drawn).
const RAIL_THINK_HZ_HIDDEN := 15.0
## The two as physics ticks, at the current tick rate (TrafficManager keeps
## them current: tests run at 60 Hz, the game at 120).
static var think_ticks := 4
static var think_ticks_hidden := 8

static func update_think_ticks() -> void:
	var tps := float(Engine.physics_ticks_per_second)
	think_ticks = maxi(1, roundi(tps / RAIL_THINK_HZ))
	think_ticks_hidden = maxi(1, roundi(tps / RAIL_THINK_HZ_HIDDEN))

func _ready() -> void:
	# Not super._ready(): Vehicle's _ready() is initialize(), which needs the
	# wheels built first (same as PlayerCar).
	if spec.is_empty():
		spec = CarSpec.npc_spec(kind)
	var npc := NpcCarBuilder.is_npc(kind)
	var cfg: Dictionary = NpcCarBuilder.config(kind) if npc else CarBuilder.KIND_CONFIGS.get(kind, CarBuilder.KIND_CONFIGS["coupe"])
	wheelbase = float(cfg.axle_z) * 2.0
	half_w = float(cfg.wheel_x) + 0.15
	half_l = (float(cfg.main_z1) - float(cfg.hood_z0)) / 2.0
	if npc:
		rest_y = float(cfg.rest_y)

	if not sim_only:
		chassis_visual = NpcCarBuilder.chassis_visual(kind, build, color, role) if npc else CarBuilder.shared_chassis_visual(kind, color)
		add_child(chassis_visual)
		# Wet-road tail smears (wet_reflections.gd): ride with the visual.
		var tail: Dictionary = WetReflections.tail_info(chassis_visual)
		if not tail.is_empty():
			WetReflections.attach_tail(chassis_visual, tail.lamps, tail.ground_y)

	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = PlayerCar.LINEAR_DAMP
	CarSpec.set_collision_layers(self)
	if npc:
		# The sheet body's own box (NpcCarBuilder.config).
		CarSpec.build_collision(self, cfg.col_size, cfg.col_y)
	else:
		# Box sized from the body config, same height and seat as the player's
		# (CarSpec.build_collision's verified ground clearance).
		CarSpec.build_collision(self, Vector3(float(cfg.main_w), 1.0, float(cfg.main_z1) - float(cfg.hood_z0)), 0.7)
	CarSpec.apply(self, spec)
	CarSpec.build_wheels(self, kind, cfg, front_spring_length, rear_spring_length)
	initialize()
	current_gear = 1
	# Drafting (aero.gd) finds other cars through this group.
	add_to_group("aero_vehicles")
	if not sim_only:
		# Cop, ally and rival specs ask for the parts set with parts = "full"
		# (CarParts.wants_parts); traffic never does and pays nothing.
		if CarParts.wants_parts(spec):
			CarParts.attach(self, {"lod": true, "rim": CarParts.rim_for_style(String(spec.get("rim", "")))})
		# Blob shadow only: 80 spotlights would be a rendering bill of their own.
		CarFx.attach(self, half_l, false)
		# Crew and cops carry an underside and maybe parts: the CarDetail node
		# switches those (Low preset, photo mode). Traffic has neither.
		if chassis_visual != null and chassis_visual.get_node_or_null(Undercarriage.NODE_NAME) != null:
			CarDetail.of(self)
		# Data-driven flames: only a car whose exhaust has a flame value gets
		# the node (today only the C3 interceptor's preset); the rest pay nothing.
		var ex: Variant = spec.get("exhaust")
		if ex is Dictionary and float(ex.get("flame", 0.0)) > 0.0 and FxSettings.is_on("exhaust_flames"):
			flames = ExhaustFlames.new(self)
			add_child(flames)

func _physics_process(delta: float) -> void:
	if not detailed:
		if _ghost_frame >= 0 and Engine.get_physics_frames() > _ghost_frame:
			_end_ghost()
		_cruise(delta)
		return
	_drive(delta)
	super._physics_process(delta)
	AeroModel.apply(self)
	heat = HeatShimmer.next_heat(heat, self, delta)
	var wet_on := wet.step(self, delta)
	# Written whenever it moved, even on the tick it settles back to dry (or a
	# respawn's settle()); nothing else sets grip_mult on traffic.
	if wet.dirty:
		wet.write(self)
	if wet_on:
		wet.apply_drag(self)
	_update_lamps()

## Brake lamps on any brake pedal (a held stop included), hazards while the
## hazard brake holds. NPC bodies only; the old box cars have no such lamps.
func _update_lamps() -> void:
	if chassis_visual == null or not NpcCarBuilder.is_npc(kind):
		return
	var key := (1 if brake_input > 0.05 else 0) + (2 if hazard else 0)
	if key != _lamp_key:
		_lamp_key = key
		NpcCarBuilder.set_lamps(chassis_visual, float(key & 1), hazard)
		WetReflections.set_tail_brake(chassis_visual, float(key & 1))

## The controller. Sets steering_input, throttle_input and brake_input.
func _drive(delta: float) -> void:
	var v := current_speed()
	if changing:
		_lc_t += delta
		if _lc_t >= _lc_dur:
			changing = false
	_lc_cooldown -= delta
	var a := _accel_command(v)
	hazard = _check_wreck(delta, v)
	var steer_x := lane_x
	if changing:
		var look := clampf(speed * LOOKAHEAD_SECONDS, LOOKAHEAD_MIN, LOOKAHEAD_MAX)
		steer_x = _path_x_at(_lc_t + look / maxf(absf(v), 1.0))
	elif weave > 0.0:
		_weave_t += delta
		steer_x += weave * sin(TAU * _weave_t / WEAVE_PERIOD)
	steering_input = lane_steer(self, steer_x, direction, wheelbase)
	handbrake_input = 0.0
	if hazard:
		throttle_input = 0.0
		brake_input = 1.0
		return
	if traffic != null:
		_decide_t -= delta
		if _decide_t <= 0.0:
			_decide_t = DECIDE_PERIOD
			_consider_lane_change(v)
	_apply_accel(v, a)

## Acceleration this car wants (m/s^2), from the car ahead in its corridor.
## Also stores lead_gap / lead_speed / lead_is_player.
func _accel_command(v: float) -> float:
	lead_gap = INF
	lead_speed = 0.0
	lead_is_player = false
	if traffic != null:
		var p := _road_pos()
		_scan_in -= 1
		if _scan_in <= 0:
			_scan_in = LEAD_SCAN_TICKS
			var lo := p.x - half_w - CORRIDOR_MARGIN
			var hi := p.x + half_w + CORRIDOR_MARGIN
			if changing:
				lo = minf(lo, lane_x - half_w - CORRIDOR_MARGIN)
				hi = maxf(hi, lane_x + half_w + CORRIDOR_MARGIN)
			lead_gap = traffic.scan(p.z, direction, lo, hi, true, _idx, half_l, LOOK_AHEAD, false)
			lead_speed = traffic.q_speed
			lead_is_player = traffic.q_player
			_lead_k = traffic.q_idx
		elif _lead_k >= 0:
			lead_gap = traffic.entry_gap(_lead_k, p.z, direction, half_l)
			lead_speed = traffic.entry_speed(_lead_k, direction)
			lead_is_player = _lead_k == 0
	# Rain: drivers ease off, and take bends slower on wet tyres (weather.gd).
	var v0 := minf(target_speed * Weather.ai_speed_factor(), bend_speed() * Weather.ai_bend_factor())
	var a := follow_accel(v, v0, lead_gap, lead_speed, _t_gap())
	signal_held = false
	if traffic != null and traffic.junction != null:
		# The red light is an invisible stopped car at the stop line (see
		# junction.gd): follow it like any other, stopping STOP_SHORT short.
		var sg := traffic.junction.stop_gap(road_z(), direction, half_l, v)
		if sg < INF:
			signal_held = true
			a = minf(a, follow_accel(v, v0, sg + S0 - Junction.STOP_SHORT, 0.0, _t_gap()))
	return a

## Fastest this car takes the road from here to BEND_LOOK m ahead: no more
## than BEND_LAT_ACCEL of cornering on the tightest bend in that stretch (#37).
## INF on a straight road. Without it the fast lane (115 km/h) took a 350 m
## bend at 3.1 m/s^2 and ran 1.6 m wide (tests/world/curve_drive.gd, 2026-10-07).
func bend_speed() -> float:
	var z := road_z()
	var k := 0.0
	for d in BEND_SAMPLES:
		k = maxf(k, absf(RoadFrame.curvature_at(z + direction * BEND_LOOK * float(d) / float(BEND_SAMPLES - 1))))
	return INF if k < 1e-6 else sqrt(BEND_LAT_ACCEL / k)

## The follower law (see the header): acceleration wanted at speed v, cruise
## speed v0, behind something `gap` metres ahead (bumper to bumper, INF for a
## free road) moving at vl along this car's direction.
static func follow_accel(v: float, v0: float, gap: float, vl: float, t_gap := T_GAP) -> float:
	if gap == INF:
		return maxf(K_V * (v0 - v), -B_COMF)
	var v_des := clampf(vl + K_GAP * (gap - (S0 + t_gap * v)), 0.0, v0)
	var a := K_V * (v_des - v)
	if v > vl:
		var a_req := (v - vl) * (v - vl) / (2.0 * maxf(gap - S_STOP, 0.3))
		a = maxf(a, -maxf(B_COMF, a_req * 1.3))
		if a_req > B_COMF * 0.6:
			a = minf(a, -a_req * 1.3)
		if gap < S_STOP:
			a = -A_BRAKE_FULL
	else:
		a = maxf(a, -B_COMF)
	return a

## Acceleration command -> GEVP pedals.
func _apply_accel(v: float, a: float) -> void:
	if a < -A_COAST:
		throttle_input = 0.0
		brake_input = clampf((-a - A_COAST) / A_BRAKE_GAIN, 0.0, 1.0)
	elif a < 0.0 and v < LOW_SPEED:
		throttle_input = 0.0
		brake_input = maxf((-a) / A_BRAKE_GAIN, CREEP_BRAKE)
	else:
		# a / K_V is the speed error; the milestone 3 throttle-only hold on it.
		throttle_input = clampf(a / K_V * SPEED_P, 0.0, 1.0)
		brake_input = 0.0
	if a < 0.0 and v < 0.5:
		throttle_input = 0.0
		brake_input = maxf(brake_input, HOLD_BRAKE)

## How fast this car could go behind something `gap` ahead at vl (the
## follower's speed command), for comparing lanes.
func _t_gap() -> float:
	return RB_T_GAP if rule_breaker else T_GAP

func _lc_gap_t() -> float:
	return RB_LC_MIN_GAP_T if rule_breaker else LC_MIN_GAP_T

## Set at every spawn (TrafficManager._respawn).
func set_rule_breaker(on: bool, weave_m: float) -> void:
	rule_breaker = on
	weave = weave_m if on else 0.0
	_weave_t = randf() * WEAVE_PERIOD if weave > 0.0 else 0.0

func _potential(v: float, gap: float, vl: float) -> float:
	if gap == INF:
		return target_speed
	return clampf(vl + K_GAP * (gap - (S0 + _t_gap() * v)), 0.0, target_speed)

func _consider_lane_change(v: float) -> void:
	if changing or _lc_cooldown > 0.0:
		return
	# Not while queueing at a red light: the car ahead is waiting, not broken down.
	var obstacle := lead_gap < OBSTACLE_RANGE and lead_speed < OBSTACLE_SPEED and target_speed > OBSTACLE_SPEED and not signal_held
	if v < MIN_LC_SPEED and not obstacle:
		return
	var u := RoadFrame.unroll(global_position)
	var x := u.x
	var skip_player := not traffic.react_to_player
	var f_gap := traffic.scan(u.z, direction, x - half_w - CORRIDOR_MARGIN, x + half_w + CORRIDOR_MARGIN,
		false, _idx, half_l, LOOK_BEHIND, skip_player)
	var f_speed := traffic.q_speed
	var yielding := f_gap < INF and f_speed - v > YIELD_DV and f_gap / (f_speed - v) < YIELD_TTC
	var cur_pot := _potential(v, lead_gap, lead_speed)
	var constrained := lead_gap < INF and cur_pot < target_speed - (RB_PASS_DV if rule_breaker else PASS_DV)
	var keep_right := not (obstacle or yielding or constrained) and _lc_cooldown < -KEEP_RIGHT_AFTER
	if not (obstacle or yielding or constrained or keep_right):
		return
	var oncoming := direction > 0.0
	var best := -1
	var best_score := -INF
	for lane in [lane_i - 1, lane_i + 1]:
		if not traffic.lane_allowed(lane, oncoming):
			continue
		if keep_right and lane != lane_i + 1:
			continue
		if not _merge_safe(TrafficManager.lane_centre(lane, oncoming), v):
			continue
		var pot := _potential(v, _m_gap, _m_speed)
		var score := pot
		var ok := false
		if obstacle:
			ok = pot > cur_pot + 1.0
		elif yielding:
			ok = pot >= minf(v, target_speed) - YIELD_SLOWDOWN
			score += 2.0 if lane > lane_i else 0.0  # move over to the right first
		elif constrained:
			ok = pot > cur_pot + PASS_GAIN
			score += 1.0 if lane < lane_i else 0.0  # pass on the left first
		else:
			ok = pot >= target_speed - 0.5 and _m_gap > KEEP_RIGHT_GAP
		if ok and score > best_score:
			best = lane
			best_score = score
	if best >= 0:
		_start_lane_change(best, obstacle or yielding)

## Whether a move into the lane centred at lx is safe right now. Leaves the
## new leader's gap and speed in _m_gap / _m_speed.
func _merge_safe(lx: float, v: float) -> bool:
	var lo := lx - half_w - CORRIDOR_MARGIN
	var hi := lx + half_w + CORRIDOR_MARGIN
	var z := RoadFrame.unroll(global_position).z
	var skip_player := not traffic.react_to_player
	_m_gap = traffic.scan(z, direction, lo, hi, true, _idx, half_l, LOOK_AHEAD, skip_player)
	_m_speed = traffic.q_speed
	if _m_gap < S0 + _lc_gap_t() * v:
		return false
	if v > _m_speed and (v - _m_speed) * (v - _m_speed) / (2.0 * maxf(_m_gap - S_STOP, 0.3)) > B_SAFE:
		return false
	if traffic.player_behind_blocks(z, direction, lo, hi, v, half_l, PLAYER_TTC, PLAYER_MIN_GAP):
		return false
	var fg := traffic.scan(z, direction, lo, hi, false, _idx, half_l, LOOK_BEHIND, skip_player)
	if fg == INF:
		return true
	var fs := traffic.q_speed
	if traffic.q_player:
		return fg >= PLAYER_MIN_GAP and (fs <= v or fg / (fs - v) >= PLAYER_TTC)
	if fg < S0 + _lc_gap_t() * fs:
		return false
	return fs <= v or (fs - v) * (fs - v) / (2.0 * maxf(fg - S_STOP, 0.3)) <= B_SAFE

func _start_lane_change(lane: int, urgent: bool) -> void:
	_lc_from = path_x()
	lane_i = lane
	lane_x = TrafficManager.lane_centre(lane, direction > 0.0)
	changing = true
	_lc_t = 0.0
	_lc_dur = LC_TIME_URGENT if urgent else LC_TIME
	_lc_cooldown = RB_LC_COOLDOWN if rule_breaker else LC_COOLDOWN
	lane_changes += 1
	_scan_in = 0
	traffic.note_lane_change(self)

## Where the car's path is across the road now: the lane centre, or the
## lane-change S.
func path_x() -> float:
	return _path_x_at(_lc_t) if changing else lane_x

func _path_x_at(t: float) -> float:
	var u := clampf(t / _lc_dur, 0.0, 1.0)
	return lerpf(_lc_from, lane_x, 0.5 - 0.5 * cos(PI * u))

## Wreck bookkeeping. Returns true while the car looks crashed (it then
## stops: hazard brake); `wrecked` latches after WRECK_SECONDS.
func _check_wreck(delta: float, v: float) -> bool:
	var u := RoadFrame.unroll(global_position)
	var b := RoadFrame.basis_to_road(u.z, global_transform.basis)
	var heading := -b.z.z * direction  # 1 = pointing down its lane
	var off := absf(u.x - path_x())
	# Upside down is against world up, not the road's: a car on its roof is
	# wrecked whatever the slope.
	var bad := global_transform.basis.y.y < WRECK_UP or ((heading < WRECK_HEADING or off > WRECK_OFF_PATH) and absf(v) < WRECK_MAX_SPEED)
	_wreck_t = _wreck_t + delta if bad else 0.0
	var stuck := absf(v) < 0.5 and lead_gap > 30.0 and target_speed > 1.0 and not signal_held
	_stuck_t = _stuck_t + delta if stuck else 0.0
	if _wreck_t > WRECK_SECONDS or _stuck_t > STUCK_SECONDS:
		wrecked = true
	return bad or wrecked

## Extra path curvature asked for per m/s^2 of cornering the road's bend
## needs (see lane_steer), for the traffic tune: 0.0015 took the mean drift
## on bends from 0.35 m to 0.11 m and the worst back to the straight road's
## (tests/world/curve_drive.gd); 0.003 overshot to the inside. Another car passes
## its own. NEON_UNDERSTEER_FF overrides it for tuning runs.
static var UNDERSTEER_FF := float(OS.get_environment("NEON_UNDERSTEER_FF")) if OS.get_environment("NEON_UNDERSTEER_FF").is_valid_float() else 0.0015

## Below this speed the bearing uses the body heading, above it the velocity
## direction (see lane_steer).
const VELOCITY_FRAME_MIN_SPEED := 3.0

## Pure-pursuit steering toward the lane centre (road-space x `lane`, so the
## target follows the road through a bend), as a steering_input in -1..1.
## Shared with the tests' scripted player so there is one lane-keeper. Sign:
## GEVP yaws LEFT for a positive input (see player.gd's keyboard note), so a
## target on the right gives a negative input.
##
## The bearing to the target is taken from the direction the car is MOVING,
## not the way its nose points. A GEVP car runs with a small standing sideslip
## (a few tenths of a degree), and a nose-based bearing then settles with the
## car offset from the lane by lookahead x sideslip: 0.43 m for the player at
## 246 km/h (60 m lookahead), 0.25 m for traffic, measured 2026-10-05. In
## adjacent lanes with 0.6 m between bodies that was a sideswipe at 340 km/h
## closing. An integral term was tried first and swung the player across the
## road at every gain from 0.03 down to 0.0001 per metre-second: at 65 m/s a
## thousandth of lock is 1 m/s^2 sideways. With the velocity frame the car is
## on the lane whenever it is moving along it, whatever its nose does.
static func lane_steer(v: Vehicle, lane: float, dir: float, wb: float, understeer_ff: float = UNDERSTEER_FF) -> float:
	var lookahead := clampf(v.speed * LOOKAHEAD_SECONDS, LOOKAHEAD_MIN, LOOKAHEAD_MAX)
	var u := RoadFrame.unroll(v.global_position)
	var target := RoadFrame.roll(Vector3(lane, u.y, u.z + dir * lookahead))
	target.y = v.global_position.y
	var fwd := -v.global_transform.basis.z
	var vel := v.linear_velocity
	vel.y = 0.0
	if vel.length() > VELOCITY_FRAME_MIN_SPEED and vel.dot(fwd) > 0.0:
		fwd = vel.normalized()
	else:
		fwd.y = 0.0
		fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var to_target := target - v.global_position
	var ahead := to_target.dot(fwd)
	var lateral := to_target.dot(right)
	var dist := maxf(Vector2(lateral, ahead).length(), 0.01)
	var alpha := atan2(lateral, ahead)  # bearing to the target, + = right
	var curvature := 2.0 * sin(alpha) / dist
	# Bends (#37): pure pursuit asks for the path's geometric curvature, but
	# the tyres need extra lock to hold it at speed (understeer), so on a bend
	# the car settled toward the outside until the lateral error made up the
	# difference: 0.3 m on average for traffic, nearly 1 m for the scripted
	# player at 120 km/h (tests/world/curve_drive.gd, 2026-10-07). Feed the extra in
	# directly, in proportion to the cornering acceleration the bend asks for.
	# Zero on a straight road. The bend's curvature is the road's (left +)
	# for a car driving down it, mirrored for one driving up it (dir +1).
	var bend := RoadFrame.curvature_at(u.z) * -dir
	curvature -= understeer_ff * v.speed * v.speed * bend
	var steer_angle := atan(wb * curvature)
	var want := clampf(steer_angle / v.max_steering_angle, -1.0, 1.0)
	# GEVP raises the input to steering_exponent (1.5) before it reaches the
	# wheels (process_steering), which squashes small inputs: at 240 km/h the
	# lane-keeper asks for ~0.01 and got 0.001, so the loop went soft and
	# wandered off the lane in a slow 30 s swing (2026-10-05). Undo it here so
	# the wheels get the angle pure pursuit asked for.
	return -signf(want) * pow(absf(want), 1.0 / maxf(v.steering_exponent, 0.1))

func current_speed() -> float:
	return -local_velocity.z  # own forward, whichever way the car points

## Speed along this car's lane direction, full sim or cruising.
func lane_speed() -> float:
	return current_speed() if detailed else _cruise_speed

## Places the car in a lane, pointing along `dir`, moving at `speed`, with the
## sim's own history (previous positions, wheel spin) made consistent so the
## next tick does not read the teleport as a velocity burst (same care as
## game.gd's floating-origin shift). Clears lane-change and wreck state.
func place(lane: float, dir: float, z: float, y: float, speed: float) -> void:
	lane_x = lane
	lane_i = RoadChunkBuilder.lane_at(absf(lane))
	direction = dir
	changing = false
	wrecked = false
	hazard = false
	_wreck_t = 0.0
	_stuck_t = 0.0
	_lc_cooldown = 0.0
	_decide_t = randf() * DECIDE_PERIOD
	_lead_k = -1
	_scan_in = 0
	var yaw := 0.0 if dir < 0.0 else PI
	global_transform = RoadFrame.pose(lane, y, z, yaw)
	set_moving(self, speed)
	reset_physics_interpolation()
	_cruise_speed = speed
	_rail_dx = 0.0
	_rail_dy = 0.0
	_rail_dyaw = 0.0
	_rail_z = z
	_think_in = _think_phase()
	_rail_a = 0.0
	_owed = 0

## Drawn or not. TrafficManager owns this (the reveal distance and ViewGuard):
## a car is shown only inside the distance where the world itself ends in fog,
## and never flips for any other reason. Independent of the sim: a car on rails
## inside that distance is still drawn.
func set_shown(on: bool) -> void:
	if on == shown:
		return
	shown = on
	visible = on and not sim_only
	# Wheel._process only turns and seats the wheel mesh: nothing to do unseen.
	for w in wheel_array:
		w.set_process(on)
	_think_in = mini(_think_in, think_ticks)
	if on:
		if not detailed and _owed > 0 and not is_nan(_rail_z):
			# Coming into view: stand where the car is by now, not where its
			# last step left it (up to 2 m back).
			_rail_z = rail_z_now()
			_rail_pose(_rail_z)
		_owed = 0
		# A hidden car may have jumped lanes (_hidden_yield): no smear into view.
		reset_physics_interpolation()

## Full sim on (inside the physics band) or the frozen car on rails (outside).
## Set shown first: a car that leaves the sim in view keeps its lane change
## and eases out of its offset; a hidden one snaps to its lane.
func set_detailed(on: bool) -> void:
	if on == detailed:
		return
	detailed = on
	# A frozen car's wheel rays are never read: stop the engine casting them
	# every tick. GEVP force-updates them itself once the sim runs again.
	for w in wheel_array:
		w.enabled = on
	if on:
		_end_ghost()
		freeze = false
		# The body is where the node is, now: a frozen body's last move may
		# still be waiting for the next physics step (see shift_world).
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
		set_moving(self, _cruise_speed)
	else:
		_cruise_speed = maxf(current_speed(), 0.0)
		_rail_a = 0.0
		_owed = 0
		_think_in = _think_phase()
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		var u := RoadFrame.unroll(global_position)
		if shown:
			_rail_dx = u.x - path_x()
			_rail_dy = u.y - rest_y
			_rail_dyaw = _yaw_error(RoadFrame.basis_to_road(u.z, global_transform.basis))
			for w in wheel_array:
				w.rotation.y = 0.0
		else:
			changing = false
			_rail_dx = 0.0
			_rail_dy = 0.0
			_rail_dyaw = 0.0
		_rail_z = u.z
		_rail_pose(u.z)
		if not shown:
			reset_physics_interpolation()

## Whether the car can leave the sim for the rails without a visible snap:
## driving normally, upright and on its path (see the header).
func can_rail() -> bool:
	if hazard or wrecked:
		return false
	var u := RoadFrame.unroll(global_position)
	var b := RoadFrame.basis_to_road(u.z, global_transform.basis)
	return b.y.y > RAIL_UP and absf(u.x - path_x()) < RAIL_OFF_PATH and absf(_yaw_error(b)) < RAIL_YAW

## Yaw (road space) of the basis b against the heading the rails would give it.
func _yaw_error(b: Basis) -> float:
	return wrapf(atan2(b.z.x, b.z.z) - _rail_yaw(), -PI, PI)

## Heading on rails relative to the road: down the lane, turned into the
## lane-change S by the angle of its sideways speed.
func _rail_yaw() -> float:
	var yaw := 0.0 if direction < 0.0 else PI
	if changing and _cruise_speed > 0.5:
		var u := clampf(_lc_t / _lc_dur, 0.0, 1.0)
		var dxdt := (lane_x - _lc_from) * 0.5 * PI / _lc_dur * sin(PI * u)
		yaw += direction * atan2(dxdt, _cruise_speed)
	return yaw

func _rail_pose(z: float) -> void:
	global_transform = RoadFrame.pose(path_x() + _rail_dx, rest_y + _rail_dy, z, _rail_yaw() + _rail_dyaw)
	previous_global_position = global_position

## Road-space position (y unused on rails) and z of the car: the rails' own
## coordinates, else looked up from the world position.
func _road_pos() -> Vector3:
	if detailed or is_nan(_rail_z):
		return RoadFrame.unroll(global_position)
	return Vector3(path_x() + _rail_dx, 0.0, _rail_z)

func road_z() -> float:
	if detailed or is_nan(_rail_z):
		return RoadFrame.unroll(global_position).z
	return _rail_z

## On rails: road-space z counting the travel a hidden car is still owed, so
## the TrafficManager measures its distance as if it moved every tick.
func rail_z_now() -> float:
	return _rail_z + direction * _cruise_speed * float(_owed) / float(Engine.physics_ticks_per_second)

## Ticks to a rail car's first think: spread over the cars by their index
## slot, so 80 cars placed together do not all think on the same tick.
func _think_phase() -> int:
	return maxi(_idx, 0) % (think_ticks if shown else think_ticks_hidden)

## On rails: down the lane path, with the follower law on its speed and, in
## view, the same lane changes as the sim; hidden, only moving over for the
## player. See "Rails, the cheap half" in the header for what runs when.
func _cruise(delta: float) -> void:
	_think_in -= 1
	var think := _think_in <= 0
	if not (think or shown):
		_owed += 1
		return
	if is_nan(_rail_z):
		_rail_z = RoadFrame.unroll(global_position).z
	var every := think_ticks if shown else think_ticks_hidden
	# A hidden car moves once per think, by all the ticks since the last one.
	var dt := delta * float(_owed + 1)
	_owed = 0
	if think:
		_think_in = every
		_rail_a = clampf(_accel_command(_cruise_speed), -A_BRAKE_FULL, 2.0)
	_cruise_speed = maxf(_cruise_speed + _rail_a * dt, 0.0)
	if changing:
		_lc_t += dt
		if _lc_t >= _lc_dur:
			changing = false
	_lc_cooldown -= dt
	if _rail_dx != 0.0 or _rail_dy != 0.0 or _rail_dyaw != 0.0:
		var k := exp(-dt / RAIL_EASE)
		_rail_dx *= k
		_rail_dy *= k
		_rail_dyaw *= k
	_rail_z += direction * _cruise_speed * dt
	var xf := RoadFrame.pose(path_x() + _rail_dx, rest_y + _rail_dy, _rail_z, _rail_yaw() + _rail_dyaw)
	global_transform = xf
	previous_global_position = xf.origin
	# Velocity as the sim would report it (current_speed(), drafting, anything
	# that bumps into it); a frozen body does not integrate it.
	linear_velocity = -xf.basis.z * _cruise_speed
	local_velocity = Vector3(0.0, 0.0, -_cruise_speed)
	if not think:
		return
	if traffic != null:
		_decide_t -= dt if not shown else delta * float(every)
		if _decide_t <= 0.0:
			_decide_t = DECIDE_PERIOD
			if shown:
				_consider_lane_change(_cruise_speed)
			elif traffic.react_to_player:
				_hidden_yield()
	if shown:
		# Lamps and rolling wheels only; the pedals do nothing on rails.
		brake_input = 1.0 if _rail_a < -A_COAST else 0.0
		for w in wheel_array:
			w.spin = _cruise_speed / w.tire_radius
		_update_lamps()

## A hidden car with the player closing on it in its lane moves over at once
## (YIELD_TTC_HIDDEN), if a lane next to it is safe.
func _hidden_yield() -> void:
	var v := _cruise_speed
	var fg := traffic.scan(RoadFrame.unroll(global_position).z, direction, lane_x - half_w - CORRIDOR_MARGIN, lane_x + half_w + CORRIDOR_MARGIN,
		false, _idx, half_l, LOOK_BEHIND, false)
	if fg == INF or not traffic.q_player:
		return
	var closing := traffic.q_speed - v
	if closing <= YIELD_DV or fg / closing >= YIELD_TTC_HIDDEN:
		return
	var oncoming := direction > 0.0
	for lane in [lane_i + 1, lane_i - 1]:
		if traffic.lane_allowed(lane, oncoming) and _merge_safe(TrafficManager.lane_centre(lane, oncoming), v):
			lane_i = lane
			lane_x = TrafficManager.lane_centre(lane, oncoming)
			var u := RoadFrame.unroll(global_position)
			global_transform = RoadFrame.pose(lane_x, u.y, u.z, 0.0 if direction < 0.0 else PI)
			previous_global_position = global_position
			lane_changes += 1
			_scan_in = 0
			traffic.note_lane_change(self)
			return

## Collisions back on after the step that carried a rail car over an origin shift.
func _end_ghost() -> void:
	if _ghost_frame < 0:
		return
	_ghost_frame = -1
	collision_layer = _ghost_layer
	collision_mask = _ghost_mask

## Velocity, saved positions, wheel spin and gear for a Vehicle that is now at
## its current transform moving `speed` m/s along its own forward. Static so
## the tests can launch the player the same way.
static func set_moving(v: Vehicle, speed: float) -> void:
	var vel := -v.global_transform.basis.z * speed
	v.linear_velocity = vel
	v.angular_velocity = Vector3.ZERO
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	v.previous_global_position = v.global_position - vel * dt
	v.local_velocity = Vector3(0.0, 0.0, -speed)
	for w in v.wheel_array:
		w.previous_global_position = w.global_position - vel * dt
		w.local_velocity = Vector3(0.0, 0.0, -speed)
		w.spin = speed / w.tire_radius
	# The gear this speed belongs in, so the automatic does not start a
	# placed car in 1st at 100 km/h and bang off the limiter through four shifts.
	if v.is_ready and speed > 0.5 and not v.is_shifting:
		var wheel_spin := speed / v.average_drive_wheel_radius
		v.current_gear = 1
		for g in range(v.gear_ratios.size(), 0, -1):
			var rpm: float = wheel_spin * v.gear_ratios[g - 1] * v.final_drive * Vehicle.ANGULAR_VELOCITY_TO_RPM
			if rpm >= v.idle_rpm * 1.5 or g == 1:
				v.current_gear = g
				v.motor_rpm = clampf(rpm, v.idle_rpm, v.max_rpm)
				break

## Floating origin (game.gd _shift_origin): the same bookkeeping the player
## gets. Not `shift`: that is Vehicle's gear change.
##
## A car on rails is a frozen kinematic body, and the physics server moves
## those at the next step, as a sweep: for that one step the body still stands
## at its old place, hundreds of metres from where the node now is, with the
## whole shift as its speed (tens of km/s). The sim cars and the player have
## already moved, so a rail car's old place can be exactly where one of them
## now is, and it is thrown: traffic_spawn caught a sim car at 131 m/s, 2.6 m
## up (2026-10-10; the "position jumped against its velocity" flake since the
## near band went in). So a rail car collides with nothing for that one step.
func shift_world(offset: Vector3) -> void:
	if freeze and _ghost_frame < 0:
		_ghost_layer = collision_layer
		_ghost_mask = collision_mask
		collision_layer = 0
		collision_mask = 0
	if freeze:
		_ghost_frame = Engine.get_physics_frames()
	global_position += offset
	previous_global_position += offset
	_rail_z = NAN  # road space is counted from the new origin
	for w in wheel_array:
		w.previous_global_position += offset
		w.last_collision_point += offset
	if flames != null:
		flames.shift_world(offset)
	reset_physics_interpolation()
