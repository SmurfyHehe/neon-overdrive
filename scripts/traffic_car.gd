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
# Lane position (threading, 2026-10-08, Roy's decision in
# docs/planning/road-lane-changes-proposal-2026-10-08.md section 0): real
# drivers do not sit on the lane centre. On the HighD freeway data
# (PMC9690543) each driver keeps their own offset, spread with a standard
# deviation of about 0.3 m, inside-lane drivers lean toward the median and
# outside-lane drivers toward the shoulder. Each car rolls such a `drift` at
# spawn and steers to lane centre + drift. On top of that, when the player
# closes fast from behind, slightly off to one side (lining up a gap), the car
# rolls once whether it eases away from that side to near its lane line: the
# courtesy drivers give a motorbike. Some do, some don't (MAKE_ROOM_CHANCE,
# less for a "rude" driver), so a gap is never guaranteed. While the player
# is alongside, a car never drifts toward it or changes lane toward it.
#
# Wrecks: a car that is flipped, or slow and pointing the wrong way or off its
# path, for WRECK_SECONDS stops trying (hazard stop: brakes on), and the
# TrafficManager recycles it once the player cannot see it.
#
# Far cars (TrafficManager.detail_distance): a car that is further from the
# player than the draw distance is hidden and frozen as a kinematic body that
# cruises along its lane, with the same follower law on its speed; the full
# sim resumes, with position, speed and heading handed over, when it comes
# back inside. Roy (2026-10-06): that counts as full sim. Why not "run the sim
# every other tick" for far cars: the Wheel applies its spring and tyre forces
# per physics step, so a car that skips a step gets gravity without
# suspension on that step and sags; the honest cheap path is no sim at all
# plus a clean handover.

## CarBuilder.KIND_CONFIGS key for the body and wheel visuals. The three NPC
## cars (stage B step 5) swap this and `spec` per car; nothing else changes.
var kind := "coupe"
## Vehicle tune (CarSpec dict). Empty = CarSpec.traffic_default(). Set before
## add_child(), like PlayerCar.spec.
var spec := {}
var color := Color(0.6, 0.6, 0.65)
## No body mesh, lights or shadow (tests and the perf harness).
var sim_only := false
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
var wheelbase := 2.5
## Footprint half sizes for the occupancy index: across the tyres, and
## bumper to the middle.
var half_w := 1.03
var half_l := 1.7
## True while the full sim runs (inside the draw distance). See set_detailed().
var detailed := true
var _cruise_speed := 0.0
## Slot in the TrafficManager's occupancy index (set by it every tick).
var _idx := -1
## Physics frame before which a car parked by a deferred spawn does not
## retry (TrafficManager).
var retry_frame := 0
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

## Offset from the lane centre, metres toward this side's road edge (+) or
## the centre line (-); see the header. `_drift_want` is where it is heading.
var drift := 0.0
var _drift_want := 0.0
## This driver's own preferred offset, rolled at spawn, and whether they
## seldom make room (rolled at spawn too).
var drift_pref := 0.0
var rude := false
## Make room: rolled once per approach of the player; while `making_room`
## the car holds `_room_drift` (away from the player's side).
var making_room := false
var _room_rolled := false
var _room_drift := 0.0
var _room_lost_t := 0.0
## Half the body's width (CarBuilder main_w / 2), for line clearances.
var body_half_w := 0.8

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
const LC_TIME := 3.0          # s for the 3.4 m S: peak sideways 1.9 m/s^2
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
const MIN_LC_SPEED := 8.0      # m/s; below it only obstacles trigger a change

## Bends (#37): cornering traffic will take, m/s^2 (a calm driver's 0.2 g;
## at 2.5 a car at 109 km/h on a 385 m bend still ran 0.76 m wide), and how
## far ahead it looks for the tightest bend, at BEND_SAMPLES points.
const BEND_LAT_ACCEL := 2.0
const BEND_LOOK := 80.0
const BEND_SAMPLES := 3

## Lane position (see the header). The mean lean of the inside lane (lane 0,
## toward the median) and of the outermost lane (toward the shoulder), HighD's
## 0.17-0.33 m and up to 0.30 m; lanes between have none.
const LEAN_INSIDE := -0.25
const LEAN_OUTSIDE := 0.2
const DRIFT_SD := 0.3
## A driver's own offset is clamped to this: two cars leaning toward each
## other in neighbouring 3.4 m lanes still keep 0.8 m between bodies.
const DRIFT_MAX := 0.5
## Making room goes this close to the lane line (body edge to line).
const ROOM_LINE_MARGIN := 0.1
## Sideways rate of the drift, m/s: a slow wander, and a quicker ease over.
const DRIFT_RATE := 0.25
const ROOM_RATE := 0.6
## Chance a driver makes room, per lane from the inside lane out (more in
## the slow lanes), and the factor for a rude driver.
const MAKE_ROOM_CHANCE: Array[float] = [0.3, 0.4, 0.5, 0.55]
const RUDE_SHARE := 0.2
const RUDE_FACTOR := 0.25
## The player triggers it when offset ROOM_DX_MIN..ROOM_DX_MAX sideways from
## the car (lined up on a gap, not squarely behind it: that is the move-over
## case) and either closing faster than ROOM_DV with under ROOM_TTC to the
## car's tail (within ROOM_RANGE), or sitting within ROOM_NEAR behind it and
## not dropping back (a player hanging there, lined up, wants through).
const ROOM_DV := 3.0
const ROOM_TTC := 5.0
const ROOM_RANGE := 120.0
const ROOM_NEAR := 25.0
const ROOM_DX_MIN := 0.6
const ROOM_DX_MAX := 3.0
## Making room ends this many metres after the player's tail clears the car's
## nose, or after the trigger has been gone this long.
const ROOM_CLEAR := 10.0
const ROOM_LOST_SECONDS := 2.0
## Alongside: the player within this much (on top of both half lengths) along
## the road and ALONGSIDE_DX across. No drift toward it, no lane change toward it.
const ALONGSIDE_DZ := 4.0
const ALONGSIDE_DX := 4.5

## Wrecks.
const WRECK_SECONDS := 3.0
const WRECK_UP := 0.5          # basis.y.y below this: on its side or roof
const WRECK_HEADING := 0.7     # cos 45 deg: pointing further off than this
const WRECK_OFF_PATH := 2.0    # m off the lane / lane-change path
const WRECK_MAX_SPEED := 4.0
const STUCK_SECONDS := 12.0    # stopped this long with nothing ahead

func _ready() -> void:
	# Not super._ready(): Vehicle's _ready() is initialize(), which needs the
	# wheels built first (same as PlayerCar).
	if spec.is_empty():
		spec = CarSpec.traffic_default()
	var cfg: Dictionary = CarBuilder.KIND_CONFIGS.get(kind, CarBuilder.KIND_CONFIGS["coupe"])
	wheelbase = float(cfg.axle_z) * 2.0
	half_w = float(cfg.wheel_x) + 0.15
	half_l = (float(cfg.main_z1) - float(cfg.hood_z0)) / 2.0
	body_half_w = float(cfg.main_w) / 2.0

	if not sim_only:
		chassis_visual = CarBuilder.shared_chassis_visual(kind, color)
		add_child(chassis_visual)

	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = PlayerCar.LINEAR_DAMP
	CarSpec.set_collision_layers(self)
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
		# Blob shadow only: 80 spotlights would be a rendering bill of their own.
		CarFx.attach(self, half_l, false)
		# Data-driven flames: only a car whose exhaust has a flame value gets
		# the node (today only the C3 interceptor's preset); the rest pay nothing.
		var ex: Variant = spec.get("exhaust")
		if ex is Dictionary and float(ex.get("flame", 0.0)) > 0.0 and FxSettings.is_on("exhaust_flames"):
			flames = ExhaustFlames.new(self)
			add_child(flames)

func _physics_process(delta: float) -> void:
	if not detailed:
		_cruise(delta)
		return
	_drive(delta)
	super._physics_process(delta)
	AeroModel.apply(self)

## The controller. Sets steering_input, throttle_input and brake_input.
func _drive(delta: float) -> void:
	var v := current_speed()
	if changing:
		_lc_t += delta
		if _lc_t >= _lc_dur:
			changing = false
	_lc_cooldown -= delta
	var a := _accel_command(v)
	var hazard := _check_wreck(delta, v)
	_update_drift(delta, v)
	var steer_x := target_x()
	if changing:
		var look := clampf(speed * LOOKAHEAD_SECONDS, LOOKAHEAD_MIN, LOOKAHEAD_MAX)
		steer_x = _path_x_at(_lc_t + look / maxf(absf(v), 1.0)) + _out() * drift
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
		var p := RoadFrame.unroll(global_position)
		_scan_in -= 1
		if _scan_in <= 0:
			_scan_in = LEAD_SCAN_TICKS
			var lo := p.x - half_w - CORRIDOR_MARGIN
			var hi := p.x + half_w + CORRIDOR_MARGIN
			if changing:
				lo = minf(lo, lane_x - half_w - CORRIDOR_MARGIN)
				hi = maxf(hi, lane_x + half_w + CORRIDOR_MARGIN)
			lead_gap = traffic.scan(p.z, direction, lo, hi, true, _idx, half_l, LOOK_AHEAD, false, _player_trim())
			lead_speed = traffic.q_speed
			lead_is_player = traffic.q_player
			_lead_k = traffic.q_idx
		elif _lead_k >= 0:
			lead_gap = traffic.entry_gap(_lead_k, p.z, direction, half_l)
			lead_speed = traffic.entry_speed(_lead_k, direction)
			lead_is_player = _lead_k == 0
	return follow_accel(v, minf(target_speed, bend_speed()), lead_gap, lead_speed)

## How much narrower the corridor is for a player ALONGSIDE (threading past):
## down from the tyres plus CORRIDOR_MARGIN to the body plus 0.15 m, so a car
## does not stand on its brakes for a player squeezing by with 0.25 m to spare
## (the player's index footprint is 0.1 m wider than its body).
func _player_trim() -> float:
	return maxf(half_w + CORRIDOR_MARGIN - (body_half_w + 0.15), 0.0)

## +1 if this car's side of the road is at positive road x (own direction),
## -1 if negative: turns an outward drift into road x.
func _out() -> float:
	return 1.0 if lane_x >= 0.0 else -1.0

## The mean lean of lane `lane` on a side with `n` lanes (see LEAN_INSIDE).
static func lane_lean(lane: int, n: int) -> float:
	if n <= 1:
		return 0.0
	if lane <= 0:
		return LEAN_INSIDE
	if lane >= n - 1:
		return LEAN_OUTSIDE
	return 0.0

## Furthest a car may drift from its lane centre before its body is within
## ROOM_LINE_MARGIN of the line.
func room_max() -> float:
	return maxf(RoadChunkBuilder.LANE_W / 2.0 - body_half_w - ROOM_LINE_MARGIN, 0.0)

## Where this car wants to sit in its lane when nobody is threading by,
## outward metres: the lane's lean plus this driver's own offset.
func _home_drift() -> float:
	if traffic == null or not traffic.lane_drift:
		return 0.0
	var n := traffic.onc_lanes if direction > 0.0 else traffic.own_lanes
	return clampf(lane_lean(lane_i, n) + drift_pref, -DRIFT_MAX, DRIFT_MAX)

## The player relative to this car, from the occupancy index: dz (+ = ahead
## of this car along its direction), dx (road x, player minus this car's
## path), closing (m/s the player gains on it), gap (bumper gap while behind).
## Empty with no traffic manager or react_to_player off.
func _player_rel(v: float) -> Dictionary:
	if traffic == null or not traffic.react_to_player:
		return {}
	var e := traffic.player_entry()
	var z := RoadFrame.unroll(global_position).z
	var dz: float = (float(e.z) - z) * direction
	return {"dz": dz, "dx": float(e.x) - path_x(), "closing": float(e.vz) * direction - v,
		"gap": -dz - half_l - TrafficManager.PLAYER_HALF_L}

## True if the player is alongside this car (see ALONGSIDE_DZ), on the side
## `side` points to (+ = larger road x) if side is not 0.
func player_alongside(rel: Dictionary, side: float = 0.0) -> bool:
	if rel.is_empty():
		return false
	if absf(rel.dz) > half_l + TrafficManager.PLAYER_HALF_L + ALONGSIDE_DZ or absf(rel.dx) > ALONGSIDE_DX:
		return false
	return side == 0.0 or signf(rel.dx) == signf(side)

## Moves `drift` toward where this driver wants to be: its own spot, or out of
## the player's way while making room. Never toward a player alongside.
func _update_drift(delta: float, v: float) -> void:
	var rel := _player_rel(v)
	var room := room_max()
	if not rel.is_empty() and traffic.lane_drift:
		var closing_in: bool = rel.gap < ROOM_RANGE and rel.closing > ROOM_DV and rel.gap / rel.closing < ROOM_TTC
		var hanging: bool = rel.gap < ROOM_NEAR and rel.closing > -1.0
		var lined_up: bool = rel.gap > 0.0 and (closing_in or hanging) \
				and absf(rel.dx) > ROOM_DX_MIN and absf(rel.dx) < ROOM_DX_MAX
		if lined_up and not _room_rolled:
			_room_rolled = true
			var chance := traffic.make_room_chance
			if chance < 0.0:
				chance = MAKE_ROOM_CHANCE[clampi(lane_i, 0, MAKE_ROOM_CHANCE.size() - 1)] * (RUDE_FACTOR if rude else 1.0)
			if randf() < chance:
				making_room = true
				traffic.make_room_count += 1
				# Away from the player's side, in outward units.
				_room_drift = -signf(rel.dx) * _out() * room
		if making_room:
			_room_lost_t = 0.0 if lined_up or player_alongside(rel) else _room_lost_t + delta
			if rel.dz > half_l + TrafficManager.PLAYER_HALF_L + ROOM_CLEAR or _room_lost_t > ROOM_LOST_SECONDS:
				making_room = false
		# A new approach rolls again once the player is well past or well back.
		if _room_rolled and not making_room and (rel.dz > half_l + TrafficManager.PLAYER_HALF_L + ROOM_CLEAR or rel.gap > ROOM_RANGE * 1.5):
			_room_rolled = false
	else:
		making_room = false
	_drift_want = clampf(_room_drift if making_room else _home_drift(), -room, room)
	var nd := move_toward(drift, _drift_want, (ROOM_RATE if making_room else DRIFT_RATE) * delta)
	# The door stays open: a player alongside on the side this would move
	# toward stops the move (an outward step times _out() is the road-x move).
	if nd != drift and player_alongside(rel, (nd - drift) * _out()):
		return
	drift = nd

## Fastest this car takes the road from here to BEND_LOOK m ahead: no more
## than BEND_LAT_ACCEL of cornering on the tightest bend in that stretch (#37).
## INF on a straight road. Without it the fast lane (115 km/h) took a 350 m
## bend at 3.1 m/s^2 and ran 1.6 m wide (tests/curve_drive.gd, 2026-10-07).
func bend_speed() -> float:
	var z := RoadFrame.unroll(global_position).z
	var k := 0.0
	for d in BEND_SAMPLES:
		k = maxf(k, absf(RoadFrame.curvature_at(z + direction * BEND_LOOK * float(d) / float(BEND_SAMPLES - 1))))
	return INF if k < 1e-6 else sqrt(BEND_LAT_ACCEL / k)

## The follower law (see the header): acceleration wanted at speed v, cruise
## speed v0, behind something `gap` metres ahead (bumper to bumper, INF for a
## free road) moving at vl along this car's direction.
static func follow_accel(v: float, v0: float, gap: float, vl: float) -> float:
	if gap == INF:
		return maxf(K_V * (v0 - v), -B_COMF)
	var v_des := clampf(vl + K_GAP * (gap - (S0 + T_GAP * v)), 0.0, v0)
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
func _potential(v: float, gap: float, vl: float) -> float:
	if gap == INF:
		return target_speed
	return clampf(vl + K_GAP * (gap - (S0 + T_GAP * v)), 0.0, target_speed)

func _consider_lane_change(v: float) -> void:
	if changing or _lc_cooldown > 0.0:
		return
	var obstacle := lead_gap < OBSTACLE_RANGE and lead_speed < OBSTACLE_SPEED and target_speed > OBSTACLE_SPEED
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
	var constrained := lead_gap < INF and cur_pot < target_speed - PASS_DV
	var keep_right := not (obstacle or yielding or constrained) and _lc_cooldown < -KEEP_RIGHT_AFTER
	if not (obstacle or yielding or constrained or keep_right):
		return
	var oncoming := direction > 0.0
	var best := -1
	var best_score := -INF
	var rel := _player_rel(v)
	for lane in [lane_i - 1, lane_i + 1]:
		if not traffic.lane_allowed(lane, oncoming):
			continue
		# Nobody closes the door mid-squeeze (threading): no change toward a
		# player alongside.
		if player_alongside(rel, TrafficManager.lane_centre(lane, oncoming) - lane_x):
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
	if _m_gap < S0 + LC_MIN_GAP_T * v:
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
	if fg < S0 + LC_MIN_GAP_T * fs:
		return false
	return fs <= v or (fs - v) * (fs - v) / (2.0 * maxf(fg - S_STOP, 0.3)) <= B_SAFE

func _start_lane_change(lane: int, urgent: bool) -> void:
	_lc_from = _base_x()
	lane_i = lane
	lane_x = TrafficManager.lane_centre(lane, direction > 0.0)
	changing = true
	_lc_t = 0.0
	_lc_dur = LC_TIME_URGENT if urgent else LC_TIME
	_lc_cooldown = LC_COOLDOWN
	lane_changes += 1
	_scan_in = 0
	traffic.note_lane_change(self)

## Where the car's path is across the road now: the lane centre, or the
## lane-change S, plus its drift in the lane.
func path_x() -> float:
	return _base_x() + _out() * drift

## The path without the drift: lane centre or the lane-change S.
func _base_x() -> float:
	return _path_x_at(_lc_t) if changing else lane_x

## Road x of the spot this car is heading for in its (new) lane.
func target_x() -> float:
	return lane_x + _out() * drift

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
	var stuck := absf(v) < 0.5 and lead_gap > 30.0 and target_speed > 1.0
	_stuck_t = _stuck_t + delta if stuck else 0.0
	if _wreck_t > WRECK_SECONDS or _stuck_t > STUCK_SECONDS:
		wrecked = true
	return bad or wrecked

## Extra path curvature asked for per m/s^2 of cornering the road's bend
## needs (see lane_steer), for the traffic tune: 0.0015 took the mean drift
## on bends from 0.35 m to 0.11 m and the worst back to the straight road's
## (tests/curve_drive.gd); 0.003 overshot to the inside. Another car passes
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
	# player at 120 km/h (tests/curve_drive.gd, 2026-10-07). Feed the extra in
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
	_wreck_t = 0.0
	_stuck_t = 0.0
	_lc_cooldown = 0.0
	making_room = false
	_room_rolled = false
	_room_lost_t = 0.0
	drift = _home_drift()
	_drift_want = drift
	_decide_t = randf() * DECIDE_PERIOD
	_lead_k = -1
	_scan_in = 0
	var yaw := 0.0 if dir < 0.0 else PI
	global_transform = RoadFrame.pose(target_x(), y, z, yaw)
	set_moving(self, speed)
	reset_physics_interpolation()
	_cruise_speed = speed

## Full sim on (inside the draw distance) or the frozen lane cruise (outside).
func set_detailed(on: bool) -> void:
	if on == detailed:
		return
	detailed = on
	visible = on and not sim_only
	if on:
		freeze = false
		set_moving(self, _cruise_speed)
	else:
		_cruise_speed = maxf(current_speed(), 0.0)
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		changing = false
		# Snap to the lane, upright; nothing is drawn out here.
		var yaw := 0.0 if direction < 0.0 else PI
		var u := RoadFrame.unroll(global_position)
		global_transform = RoadFrame.pose(target_x(), u.y, u.z, yaw)
		reset_physics_interpolation()

## Frozen cruise: straight down the lane, with the follower law on its speed.
func _cruise(delta: float) -> void:
	var a := clampf(_accel_command(_cruise_speed), -A_BRAKE_FULL, 2.0)
	_cruise_speed = maxf(_cruise_speed + a * delta, 0.0)
	var u := RoadFrame.unroll(global_position)
	u.z += direction * _cruise_speed * delta
	global_transform = RoadFrame.pose(u.x, u.y, u.z, 0.0 if direction < 0.0 else PI)
	previous_global_position = global_position
	if traffic != null and traffic.react_to_player:
		_decide_t -= delta
		if _decide_t <= 0.0:
			_decide_t = DECIDE_PERIOD
			_hidden_yield()

## A hidden car with the player closing on it in its lane moves over at once
## (YIELD_TTC_HIDDEN), if a lane next to it is safe.
func _hidden_yield() -> void:
	var v := _cruise_speed
	var fg := traffic.scan(RoadFrame.unroll(global_position).z, direction, target_x() - half_w - CORRIDOR_MARGIN, target_x() + half_w + CORRIDOR_MARGIN,
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
			drift = _home_drift()
			_drift_want = drift
			var u := RoadFrame.unroll(global_position)
			global_transform = RoadFrame.pose(target_x(), u.y, u.z, 0.0 if direction < 0.0 else PI)
			previous_global_position = global_position
			lane_changes += 1
			_scan_in = 0
			traffic.note_lane_change(self)
			return

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
func shift_world(offset: Vector3) -> void:
	global_position += offset
	previous_global_position += offset
	for w in wheel_array:
		w.previous_global_position += offset
		w.last_collision_point += offset
	if flames != null:
		flames.shift_world(offset)
	reset_physics_interpolation()
