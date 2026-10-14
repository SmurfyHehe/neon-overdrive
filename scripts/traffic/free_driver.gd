class_name FreeDriver
extends RefCounted

# The free driver (police step P4, spec section 5): drives a TrafficCar after
# a moving target instead of down a lane. Cops in pursuit use it; a rival or a
# runner can too. It plugs in like the racing driver does: set
# `car.free_driver` and TrafficCar._drive hands the car over while it is in
# the full sim. On the rails (far away, out of view) the car is plain traffic
# again at the `target_speed` this driver last gave it.
#
# What it does, each AI tick of its car:
#   steering  pure pursuit (TrafficCar.lane_steer, the traffic cars' own maths)
#             to a line across the road, `aim_x`.
#   target    the role's spot by the target: `offset_back` m behind it along
#             its travel (negative = in front of it) and `offset_x` m across
#             the road from where it will be `lead_secs` from now.
#   speed     the follower law with the target point as the car ahead, and
#             with the nearest traffic car in its own corridor; never more
#             than the car's own top speed (no rubber band: a slow car stays
#             slow) or `v_max`.
#   traffic   before it commits to a line it scans that corridor in the
#             manager's occupancy index, ahead and alongside (as
#             TrafficCar._merge_safe does). The line it wants is tried first,
#             then the lane centres nearest to it. Nothing open: it holds the
#             line it is on and brakes behind whatever is there.
#   stuck     stopped while it wants to go, or on its roof, for STUCK_SECS:
#             `recycle_due` goes true and recycle() moves it behind the target,
#             out of view, as soon as no camera can see it.
#
# In front of its target (issue #625: cops cut into your lane ahead of you and
# braked, and every crash the clean test bot had in an hour was into one):
#   - it only moves onto the target's line in front of it when the target
#     could stop for it at TARGET_DECEL with REACT_S to react, at CUT_HEADWAY
#     or more (cut_in_ok); a role spot behind the target (the chaser, the
#     heavy) is never reached by crossing in front: it drops back on a line
#     beside the target's and moves in once it is behind;
#   - on the target's line in front of it, it never slows harder than
#     GENTLE_DECEL, and not below the target's pace at all while the target
#     could not stop for it (only traffic in its own way brakes it harder,
#     as it would anybody).

# Not here (later steps): turning round and crossing the centre. A target
# going the other way sets `wrong_way` and the driver just stops safely; a
# target on the other carriageway is shadowed from this one. Median gaps and
# three-point turns belong to the cop brain (P5).
#
# Cost: one unroll and one steer per AI tick; the line choice (up to
# 2 + lanes corridor scans, each a short walk of the index) runs PLAN_HZ times
# a second, staggered by the car's index.

const PLAN_HZ := 10.0
const LEAD_SECS := 0.7           # how far ahead of the target it aims (0.5-1.0 s)
## Line choice.
const NEAR_M := 22.0             # closer than this (plus NEAR_T of own speed) it goes for the role's spot itself
const NEAR_T := 0.4
const LOOK_M := 120.0            # corridor searched ahead
const OPEN_T := 1.4              # s of own speed a line must be clear for, on top of S0
const SIDE_GAP := 5.0            # m a car alongside or just behind must leave before moving over
const SIDE_AIR := 0.6             # m of air it wants beside it when it moves across
const SIDE_TTC := 1.6            # s: a faster car behind in the new line must be further off than this
const KEEP_SECS := 0.8           # a chosen line is kept this long unless it closes
const SLEW := 3.0                # m/s the aim moves across the road
const SLEW_SLOW := 1.5           # ...below SLOW_V (a tight turn at walking pace swings the tail)
const SLOW_V := 8.0
const EDGE := 1.1                # m kept between the car's centre and the road's edge / the centre line
## Speed.
const K_CLOSE := 0.7             # 1/s: metres short of the spot -> closing speed
const CLOSE_MAX := 22.0          # m/s faster than the target at most while catching up
const WAIT_CLOSE := 6.0          # m/s slower than the target at most while waiting for its spot to come up
const T_GAP := 0.7               # s gap to traffic in pursuit (traffic keeps 1.5)
const T_GAP_TARGET := 0.35       # s gap to the target's own bumper
const BEND_K := 1.5              # bends at this times the traffic car's bend speed
const BRAKE_READ := 0.6           # s ahead a braking target's speed is read
const PASS_CLEAR := 6.5          # m of clear road in front of a target before moving over in front of it
const B_PLAN := 5.5              # m/s^2 it counts on when closing on its spot
const WAIT_SHARE := 0.6          # of the target's pace: a blocker in front of its spot rolls on at this
## In front of the target (issue #625; the header).
const TARGET_DECEL := 4.0        # m/s^2 the target may be asked to brake at for a cop cutting in
const REACT_S := 0.5             # s of closing speed on top, to react
const CUT_HEADWAY := 0.8         # s of the target's speed: the least gap cut in at
const CUT_SLOW_KMH := 40.0       # under this (box-in) the headway is not asked for, only S0
const GENTLE_DECEL := 2.0        # m/s^2: the hardest it slows on the target's line in front of it
const FLIP_SLOWER := 2.0         # m/s: traffic this much slower than the target on its side makes it go round the other side
const FLIP_SECS := 3.0           # ...at most this often
const TARGET_HALF_W := 1.0       # the target's half width (TrafficManager.PLAYER_HALF_W)
const TARGET_HALF_L := 2.2       # and half length
## Stuck.
const STUCK_SECS := 5.0
const STUCK_V := 1.0
const FLIP_UP := 0.3             # the body's up axis below this = on its side or roof
const RECYCLE_PAST_REVEAL := 40.0

var target: Node3D
var offset_x := 0.0
var offset_back := 10.0
var lead_secs := LEAD_SECS
## Bumper gap it keeps to a stopped target that is in its way (traffic keeps S0).
var stand_gap := 2.0
## The chaser's nudge: inside `ram_gap` of a target that is slower than it, it
## does not brake to a stand-off but closes at `ram_dv` and touches.
var ram := false
var ram_gap := 3.0
var ram_dv := 3.0
## Which side of the target it keeps to while it may not be on the target's
## line: going round to get in front, or dropping back to a spot behind
## (0 = not out to a side).
var pass_side := 0.0
var v_max := INF
## Read back by its owner and by tests.
var v_top := 60.0
var aim_x := 0.0                 # the line it is steering for now
var line_x := 0.0                # the line it has chosen (aim_x slews to it)
var gap_along := 0.0             # m from the car to its spot, along its direction
var blocked := false             # no open line: holding and braking
var in_front := false            # on the target's line, in front of it (issue #625)
var cut_ok := true               # ...and the target could stop for it there
var wrong_way := false           # the target is going the other way
var stuck_t := 0.0
var recycle_due := false
var recycles := 0
var line_changes := 0
var refused := 0                 # times it wanted a line and the corridor said no
var plan_us := 0
var plan_runs := 0
var drive_us := 0
var drive_runs := 0

var _plan_at := -1
var _plan_every := 12
var _keep := 0.0
var _lead_gap := INF
var _lead_v := 0.0
var _started := false
var _vt_last := NAN
var _t_acc := 0.0
var _bend_v := INF               # the bend limit ahead, from the last plan
var _t_gap := INF                # body gap to the target ahead of it, + = the car is in front
var _t_close := 0.0              # m/s the target closes on the car (+ = closing)
var _t_v := 0.0                  # the target's speed along the car's direction
var _t_x := 0.0                  # the target's line (road x)
var _flip_t := 0.0
var _t_rel := -INF               # m the car's centre is in front of the target's, along the target's way
var _t_ahead := false            # the car is not behind the target (in front of it or beside it), going its way

## Reads the car (after it is in the tree): top speed, where it is.
func setup(car: TrafficCar) -> void:
	v_top = RivalDriver.top_speed(car)
	_plan_every = maxi(1, roundi(float(Engine.physics_ticks_per_second) / PLAN_HZ))
	_plan_at = Engine.get_physics_frames() + (maxi(car._idx, 0) * 5) % _plan_every
	_started = false

## The driver gets out: the car is plain traffic again in the lane it is in.
static func release(car: TrafficCar, cruise: float) -> void:
	if car == null or not is_instance_valid(car) or car.free_driver == null:
		return
	car.free_driver = null
	var far := RoadFrame.unroll(car.global_position).x < 0.0
	var lanes := 4
	if car.traffic != null:
		lanes = car.traffic.onc_lanes if far else car.traffic.own_lanes
	car.lane_i = clampi(RoadChunkBuilder.lane_at(absf(RoadFrame.unroll(car.global_position).x)), 0, maxi(lanes, 1) - 1)
	car.lane_x = TrafficManager.lane_centre(car.lane_i, far)
	car.changing = false
	car.target_speed = cruise

# ---------- pure helpers (tests/traffic/free_driver_pure.gd) ----------

## Acceleration wanted at speed v to arrive at a spot `gap` m ahead that moves
## at `vt` along the car's direction, cruising at most at v0: close at
## K_CLOSE of the distance (CLOSE_MAX at most), and brake in time to match the
## spot's speed there. A spot behind the car (gap < 0) is waited for, at no
## more than WAIT_CLOSE under the spot's pace: a car out in front of you that
## wants to be behind you, or a blocker waiting for you, is never far slower
## than you (issue #625: they dropped to walking pace in front of you).
static func approach_accel(v: float, v0: float, gap: float, vt: float) -> float:
	var v_des := clampf(vt + clampf(K_CLOSE * gap, -WAIT_CLOSE, CLOSE_MAX), 0.0, v0)
	if gap > 0.0 and v_des > vt:
		# never faster than it can still shed before the spot
		v_des = minf(v_des, sqrt(maxf(vt, 0.0) * maxf(vt, 0.0) + 2.0 * B_PLAN * gap))
	return clampf(TrafficCar.K_V * (v_des - v) * 2.0, -TrafficCar.A_BRAKE_FULL, 6.0)

## Whether a corridor with the first car `gap` m ahead (bumper to bumper)
## doing `vl` is open for a car at speed v that has `need` m to go in it.
static func line_open(v: float, gap: float, vl: float, need: float) -> bool:
	if gap == INF:
		return true
	if gap >= need:
		return true   # it is past where the driver is going
	if gap < TrafficCar.S0 + OPEN_T * v:
		return false
	return v <= vl or (v - vl) * (v - vl) / (2.0 * maxf(gap - TrafficCar.S_STOP, 0.3)) <= TrafficCar.B_COMF

## Whether a car `gap` m behind (bumper to bumper, INF = none) doing `vf`
## leaves room for a car at speed v to move into its corridor.
static func side_clear(v: float, gap: float, vf: float) -> bool:
	if gap == INF:
		return true
	if gap < SIDE_GAP:
		return false
	return vf <= v or gap / (vf - v) >= SIDE_TTC

## Whether a car `gap` m (bumper to bumper) in front of a target doing `vt`
## and closing on it at `closing` m/s may be on the target's line: the target
## sheds the closing speed at TARGET_DECEL after REACT_S, and keeps
## CUT_HEADWAY of its own speed (S0 when it is slower than CUT_SLOW_KMH).
static func cut_in_ok(gap: float, closing: float, vt: float) -> bool:
	if gap <= 0.0:
		return false
	var need := TrafficCar.S0 if vt * 3.6 < CUT_SLOW_KMH else maxf(TrafficCar.S0, CUT_HEADWAY * vt)
	if closing > 0.0:
		need += closing * closing / (2.0 * TARGET_DECEL) + closing * REACT_S
	return gap >= need

## The hardest a car on the target's line in front of it may change speed at
## (an acceleration floor, m/s^2): GENTLE_DECEL while the target could stop
## for it, else none below the target's own pace.
static func front_floor(v: float, vt: float, ok: bool) -> float:
	if ok:
		return -GENTLE_DECEL
	return clampf(TrafficCar.K_V * 2.0 * (vt - v), -GENTLE_DECEL, 6.0)

## The road's drivable span for a car on the +x side (far = false) or the -x
## side, as [lo, hi] for its centre.
static func side_span(lanes: int, far: bool) -> Vector2:
	var a := RoadChunkBuilder.MEDIAN_GAP + EDGE
	var b := RoadChunkBuilder.MEDIAN_GAP + float(maxi(lanes, 1)) * RoadChunkBuilder.LANE_W - EDGE
	b = maxf(b, a)
	return Vector2(-b, -a) if far else Vector2(a, b)

# ---------- driving ----------

func drive(car: TrafficCar, delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var frame := Engine.get_physics_frames()
	var u := RoadFrame.unroll(car.global_position)
	var v := car.current_speed()
	if not _started:
		_started = true
		aim_x = u.x
		line_x = u.x
	if target == null or not is_instance_valid(target):
		_hold(car, v, u.x)
		return
	var tu := RoadFrame.unroll(target.global_position)
	var tvel: Vector3 = target.get("linear_velocity") if target.get("linear_velocity") is Vector3 else Vector3.ZERO
	var tv := RoadFrame.dir_to_road(tu.z, tvel)
	# Which way the chase runs: the target's own way while it moves, else the car's.
	var td := car.direction
	if absf(tv.z) > 2.0:
		td = signf(tv.z)
	wrong_way = td != car.direction
	var far := u.x < 0.0
	var lanes := 4
	if car.traffic != null:
		lanes = car.traffic.onc_lanes if far else car.traffic.own_lanes
	var span := side_span(lanes, far)
	var vt := tv.z * car.direction
	# A braking target is read a little ahead (its brake lamps, in effect):
	# the speed it will have BRAKE_READ seconds on, never a speeding-up one.
	if _vt_last == _vt_last:
		_t_acc = lerpf(_t_acc, (vt - _vt_last) / maxf(delta, 0.001), 0.5)
	_vt_last = vt
	vt = maxf(vt + minf(_t_acc, 0.0) * BRAKE_READ, minf(vt, 0.0))
	# The spot: where the target will be, plus the role's offset.
	# Along the road the spot is measured from where the target is now (the
	# speed law already matches its speed; leading it as well would eat the
	# stand-off at speed). Across the road it is led, so the steering is early.
	var spot_z := tu.z - td * offset_back
	var spot_x := tu.x + tv.x * lead_secs + offset_x
	# A spot in front of the target (a blocker) while the car is still behind
	# or beside it: it goes round, one lane to the side with road, and only
	# moves over to the spot once it is clear in front.
	# The same goes for a spot BEHIND the target while the car is in front of
	# it or beside it (issue #625): it drops back beside the target's line,
	# never on it, and moves in once it is behind.
	var rel := (u.z - tu.z) * td   # + = the car is in front of the target
	var reach := car.half_l + TARGET_HALF_L
	_t_gap = rel - reach
	_t_v = vt
	_t_close = vt - v if td == car.direction else 0.0
	var corridor := car.half_w + TARGET_HALF_W + TrafficCar.CORRIDOR_MARGIN
	in_front = td == car.direction and rel > 0.0 and absf(u.x - tu.x) < corridor
	cut_ok = cut_in_ok(_t_gap, _t_close, maxf(vt, 0.0))
	_t_x = tu.x
	_t_ahead = td == car.direction and rel > -reach
	_t_rel = rel if td == car.direction else -INF
	var going_round := offset_back < 0.0 and (rel < car.half_l + PASS_CLEAR or not cut_ok)
	var dropping_back := offset_back >= 0.0 and absf(offset_x) < corridor and rel > -reach
	_flip_t -= delta
	if td == car.direction and (going_round or dropping_back):
		if pass_side == 0.0:
			pass_side = signf(u.x - tu.x) if absf(u.x - tu.x) > 1.0 else 1.0
			var px := tu.x + pass_side * RoadChunkBuilder.LANE_W
			if px < span.x or px > span.y:
				pass_side = -pass_side
		elif going_round and rel < -reach and _flip_t <= 0.0 and _lead_gap < LOOK_M and _lead_v < vt - FLIP_SLOWER:
			# going round, still behind the target, and its side is held up by
			# slower traffic: the other side, if there is road there (it crosses
			# behind the target, which is allowed)
			var ox := tu.x - pass_side * RoadChunkBuilder.LANE_W
			if ox >= span.x and ox <= span.y:
				pass_side = -pass_side
				_flip_t = FLIP_SECS
		spot_x = tu.x + pass_side * RoadChunkBuilder.LANE_W
	else:
		pass_side = 0.0
	# It keeps to its own carriageway: a target on the other one is shadowed
	# from the lane nearest the centre (crossing over is the cop brain's, P5).
	spot_x = clampf(spot_x, span.x, span.y)
	gap_along = (spot_z - u.z) * car.direction
	if frame >= _plan_at:
		_plan_at = frame + _plan_every
		_plan(car, u, v, spot_x, span)
	_keep -= delta
	# Steering: the aim slews to the chosen line; pure pursuit does the rest.
	aim_x = move_toward(aim_x, line_x, (SLEW_SLOW if v < SLOW_V else SLEW) * delta)
	car.lane_x = aim_x
	car.lane_i = clampi(RoadChunkBuilder.lane_at(absf(aim_x)), 0, maxi(lanes, 1) - 1)
	car.changing = false
	car.steering_input = TrafficCar.lane_steer(car, aim_x, car.direction, car.wheelbase)
	car.handbrake_input = 0.0
	# Speed: the spot, the target's own bumper if it is in the way, traffic.
	var v0 := minf(minf(v_top, v_max), _bend_v)
	car.target_speed = v0   # what it cruises at if it drops onto the rails
	var a := approach_accel(v, v0, gap_along, vt)
	# A blocker in front of its spot dawdles at WAIT_SHARE of the target's
	# pace so the target catches it up (what CopBrain asks of it on the
	# rails), instead of stopping dead in the road: a stopped cop holds up
	# the traffic behind it and the target with it (police_dispatch,
	# 2026-10-12). A target that stops still gets a cop that stops.
	if offset_back < 0.0 and gap_along < 0.0:
		var dawdle := minf(WAIT_SHARE * maxf(vt, 0.0), v0)
		a = maxf(a, clampf(TrafficCar.K_V * 2.0 * (dawdle - v), -TrafficCar.A_BRAKE_FULL, 6.0))
	# On the target's line in front of it: no brake-checking (issue #625).
	if in_front:
		a = maxf(a, front_floor(v, minf(maxf(vt, 0.0), v0), cut_ok))
	var body_gap := (tu.z - u.z) * car.direction - car.half_l - 2.2
	if body_gap > -4.0 and absf(tu.x - u.x) < car.half_w + 1.0 + TrafficCar.CORRIDOR_MARGIN:
		if ram and body_gap < ram_gap and vt < v0 and vt > 1.0:
			a = minf(a, TrafficCar.K_V * 2.0 * (vt + ram_dv - v))   # a nudge, not a brake
		else:
			a = minf(a, TrafficCar.follow_accel(v, v0, maxf(body_gap + TrafficCar.S0 - stand_gap, 0.0), vt, T_GAP_TARGET))
	if _lead_gap < INF:
		a = minf(a, TrafficCar.follow_accel(v, v0, _lead_gap, _lead_v, T_GAP))
		_lead_gap = maxf(_lead_gap - (v - _lead_v) * delta, 0.0)   # until the next plan
	if wrong_way:
		a = minf(a, -TrafficCar.B_COMF)
	car._apply_accel(v, a)
	# Stuck: stopped while it wants to go, or off its wheels.
	var flipped := car.global_transform.basis.y.y < FLIP_UP
	if flipped or (absf(v) < STUCK_V and a > 0.3 and not wrong_way):
		stuck_t += delta
	else:
		stuck_t = maxf(stuck_t - delta * 2.0, 0.0)
	recycle_due = stuck_t >= STUCK_SECS
	drive_us += Time.get_ticks_usec() - t0
	drive_runs += 1

## No target: slow to a stop on the line it is on.
func _hold(car: TrafficCar, v: float, x: float) -> void:
	car.lane_x = x if not _started else aim_x
	car.steering_input = TrafficCar.lane_steer(car, car.lane_x, car.direction, car.wheelbase)
	car.handbrake_input = 0.0
	car._apply_accel(v, -TrafficCar.B_COMF)

## Picks the line across the road (10 Hz): the role's spot if its corridor is
## open, else the nearest open lane centre, else the line it is on.
func _plan(car: TrafficCar, u: Vector3, v: float, spot_x: float, span: Vector2) -> void:
	var t0 := Time.get_ticks_usec()
	_bend_v = car.bend_speed() * BEND_K
	var traffic := car.traffic
	if traffic == null:
		line_x = spot_x
		_lead_gap = INF
		return
	var hw := car.half_w + TrafficCar.CORRIDOR_MARGIN
	var skip_player := target == traffic.player
	var need := maxf(gap_along - car.half_l, 0.0)
	# What is in front on the line it is driving now (the path it is sweeping).
	var lo := minf(u.x, aim_x) - hw
	var hi := maxf(u.x, aim_x) + hw
	_lead_gap = traffic.scan(u.z, car.direction, lo, hi, true, car._idx, car.half_l, LOOK_M, skip_player)
	_lead_v = traffic.q_speed
	if _lead_gap < INF and _is_target(traffic):
		_lead_gap = INF   # the target itself: the spot and its bumper handle that
	var want := clampf(spot_x, span.x, span.y)
	var near := gap_along < NEAR_M + NEAR_T * v
	var cur_open := line_open(v, _lead_gap, _lead_v, need)
	blocked = false
	if absf(want - line_x) < 0.3 and cur_open:
		line_x = want
		plan_us += Time.get_ticks_usec() - t0
		plan_runs += 1
		return
	if _keep > 0.0 and cur_open and not near:
		plan_us += Time.get_ticks_usec() - t0
		plan_runs += 1
		return
	# Candidates, nearest the wanted line first: the line itself, then lane centres.
	var cands: Array[float] = [want]
	var far := u.x < 0.0
	var lanes := traffic.onc_lanes if far else traffic.own_lanes
	for i in lanes:
		var c := TrafficManager.lane_centre(i, far)
		if c >= span.x and c <= span.y and absf(c - want) > 0.6:
			cands.append(c)
	cands.sort_custom(func(a: float, b: float) -> bool: return absf(a - want) < absf(b - want))
	var best := NAN
	for c in cands:
		if _line_free(car, traffic, u, v, c, hw, need, skip_player):
			best = c
			break
	if is_nan(best):
		blocked = not cur_open
		if absf(want - line_x) > 0.3:
			refused += 1
	elif absf(best - line_x) > 0.3:
		line_x = best
		line_changes += 1
		_keep = KEEP_SECS
	plan_us += Time.get_ticks_usec() - t0
	plan_runs += 1

## Whether the corridor at line `x` is free to move into and drive down: clear
## ahead for where it is going, and the strip of road it newly covers on the
## way over (plus SIDE_AIR) has nobody alongside, nobody just ahead that is
## slower, and nobody closing from behind. The strip is checked for any move,
## however small: a line that follows a target across the road in small steps
## must not creep into the car in the next lane.
func _line_free(car: TrafficCar, traffic: TrafficManager, u: Vector3, v: float, x: float, hw: float, need: float, skip_player: bool) -> bool:
	var g := traffic.scan(u.z, car.direction, x - hw, x + hw, true, car._idx, car.half_l, LOOK_M, skip_player)
	if g < INF and not _is_target(traffic) and not line_open(v, g, traffic.q_speed, need):
		return false
	if absf(x - u.x) < 0.15:
		return true   # on it already
	# Onto the target's line in front of it only where the target could stop
	# for it (issue #625).
	if _t_ahead and absf(x - _t_x) < car.half_w + TARGET_HALF_W + TrafficCar.CORRIDOR_MARGIN and not cut_ok:
		return false
	var air := car.half_w + SIDE_AIR
	var lo := u.x + car.half_w if x > u.x else x - air
	var hi := x + air if x > u.x else u.x - car.half_w
	# the target beside it is not in the index scans when it is the player
	if _t_ahead and absf(_t_rel) < car.half_l + TARGET_HALF_L + SIDE_GAP and _t_x + TARGET_HALF_W > lo and _t_x - TARGET_HALF_W < hi:
		return false
	var b := traffic.scan(u.z, car.direction, lo, hi, false, car._idx, car.half_l, 60.0, skip_player)
	if b < INF and not _is_target(traffic) and not side_clear(v, b, traffic.q_speed):
		return false
	var secs := absf(x - u.x) / SLEW
	var f := traffic.scan(u.z, car.direction, lo, hi, true, car._idx, car.half_l, maxf(v * secs, 12.0) + car.half_l, skip_player)
	if f < INF and not _is_target(traffic) and (f < SIDE_GAP or traffic.q_speed < v - 3.0):
		return false
	return true

## Whether the last scan's hit was the target (a traffic car being chased is
## in the index like any other).
func _is_target(traffic: TrafficManager) -> bool:
	if traffic.q_player:
		return target == traffic.player
	return target is TrafficCar and traffic.q_idx == (target as TrafficCar)._idx

## Stuck or flipped for STUCK_SECS and no camera on it: back on the road
## behind the target, out of view, at the target's pace. True if it moved.
func recycle(car: TrafficCar) -> bool:
	var traffic := car.traffic
	if not recycle_due or traffic == null or target == null or not is_instance_valid(target):
		return false
	if traffic.in_view(car.global_position):
		return false
	var tu := RoadFrame.unroll(target.global_position)
	var tvel: Vector3 = target.get("linear_velocity") if target.get("linear_velocity") is Vector3 else Vector3.ZERO
	var tvz := RoadFrame.dir_to_road(tu.z, tvel).z
	var td := signf(tvz) if absf(tvz) > 2.0 else car.direction
	var far := tu.x < 0.0
	var lanes := traffic.onc_lanes if far else traffic.own_lanes
	var z := tu.z - td * (traffic.reveal_distance() + RECYCLE_PAST_REVEAL)
	var speed := minf(maxf(absf(tvz), 15.0), minf(v_top, v_max))
	for i in lanes:
		var x := TrafficManager.lane_centre(i, far)
		if traffic.in_view(RoadFrame.roll(Vector3(x, car.rest_y, z))):
			continue
		if traffic._slot_check(car, x, z, td, speed).is_empty():
			continue
		car.place(x, td, z, car.rest_y, speed)
		if car._idx >= 0:
			traffic._put(car)   # re-files its footprint in the index
		stuck_t = 0.0
		recycle_due = false
		recycles += 1
		_started = false
		return true
	return false
