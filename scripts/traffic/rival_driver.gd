class_name RivalDriver
extends RefCounted

# The racing driver (rival driver build spec, step 1: pace and line). A pinned
# TrafficCar holds one in `racer`; TrafficCar._drive then calls drive() instead
# of the traffic controller. The car is the same raycast sim as every other
# car; only who works the wheel and pedals changes.
#
# NO RUBBER BAND. Nothing here reads the gap to the player, the player's
# progress or the distance to the finish. The driver sees the road, its own
# car and whatever is right in front of its bumper. The player is only ever
# looked at as a car in the way, inside PLAYER_NEAR metres, so the rival does
# not drive through them. Difficulty is the rival's car, never its driving.
#
# Two clocks. The plan (PLAN_HZ, staggered by car index) extends the racing
# line and rebuilds the speed profile. The drive tick (every traffic AI
# stride) steers at the line and works the pedals from the profile.
#
# Speed plan, every plan tick: SAMPLES points STEP metres apart ahead of the
# car.
#   1. corner speed at each: sqrt(commit x sideways grip / |curvature|),
#      capped at the car's top speed, times Weather.ai_bend_factor() in rain.
#      The curvature is the path's: the road's bend less what the racing line
#      takes out of it (see below), so a bend taken on the line is planned at
#      the speed the line allows.
#   2. backward pass from the far end: v[i] = min(v[i], sqrt(v[i+1]^2 +
#      2 x b x STEP)), b = the car's braking x brake_late.
#   3. the speed wanted now is the profile under the car. Over it by
#      COAST_BAND: brake, as hard as the profile is falling plus a share of the
#      error (full pedal allowed). Under it: full throttle.
#   4. a car ahead in its path: the traffic follower law at a racing gap
#      (T_GAP), and the lower of the two wins.
#
# Racing line: outside, apex, outside across its own side of the road, lane
# lines ignored, never over the centre line. A bend is a run of road chunks
# bending the same way tighter than LINE_MIN_RADIUS. For each one the line is
# three parabolas: turn in over `e_in` metres of the straight before it, run
# wide through it, straighten over `e_out` metres after it. That makes the
# path one arc of curvature c = k x length / (length + e_in + e_out), flatter
# than the road's k, and puts the car EDGE metres from the inside edge at the
# apex when there is room (bend_line()). Between bends it holds the x it came
# out on, and moves across (two parabolas) just before the next turn
# in when that bend wants the other side (as far as MOVE_ACCEL lets it in
# the road it has). With no room to turn in or out (a
# bend straight after another) the line degrades to holding its x, and the
# speed plan uses the road's own curvature there.
#
# The line is for a clear road. With any car on its side of the road within
# TRAFFIC_AHEAD metres ahead or TRAFFIC_BEHIND behind (the player counts only
# inside PLAYER_NEAR), it holds the x it is on and plans its speed on the
# road's own bends: sweeping the width of the road through traffic needs the
# corridor scoring and overtaking of a later step. Until then a rival that
# catches slower traffic in its path follows it at the racing gap.
#
# Everything is in absolute road distance S (RoadFrame.s_at), so the line
# survives floating-origin shifts.

const Weather := preload("res://scripts/world/weather.gd")

const L := RoadChunkBuilder.CHUNK_LEN
const PLAN_HZ := 10.0
const STEP := 5.0
const SAMPLES := 60                 # 300 m
## Sideways grip the plan assumes, m/s^2, until each car's is measured: the
## test driver's grip-mode number, which was set on the player's coupe (road
## friction GRIP_MU), scaled to this car's own road friction in setup(). The
## AI cars run friction 1.0, so they plan on 6.7.
const GRIP_LAT_ACCEL := 8.0
const GRIP_MU := 1.2
## Braking a full pedal is worth, m/s^2, until each car's is measured
## (traffic_default() read 8.2 at 30 m/s, TrafficCar's pedal map).
const BRAKE_DECEL := 8.2
const COAST_BAND := 0.5             # m/s over the profile before the brakes come on
const K_BRAKE := 3.0                # 1/s: speed over the profile -> extra braking
const K_THROTTLE := 2.0             # throttle per m/s under the profile
const T_GAP := 0.6                  # s, racing gap to a car ahead
const LOOK_AHEAD := 150.0           # m searched for a car in the way
## The player counts as a car in the way only this close (see the header).
const PLAYER_NEAR := 30.0
const LEAD_MARGIN := 0.25           # m either side of the body
const TRAFFIC_AHEAD := 250.0        # m: a car this close on its side of the road, no racing line
const TRAFFIC_BEHIND := 30.0
const LOOKAHEAD_SECONDS := 0.8
const LOOKAHEAD_MIN := 10.0
const LOOKAHEAD_MAX := 60.0
## Understeer. Pure pursuit asks for the wheel angle the geometry needs
## (wheelbase x curvature); at speed the tyres need more: the hot hatch at
## 175 km/h and 5 m/s^2 wanted 1.3 degrees where the geometry says 0.3, and
## without the difference ran 3 m wide of its apex. The usual model is
## angle = wheelbase x curvature x (1 + g v^2), so the driver multiplies
## everything it asks of the wheel by (1 + g v^2): the line's arc and its
## corrections alike. g differs per car, so it starts at G_START and is
## measured as it drives: whenever the car is turning, the wheel angle it has
## on against the curvature it is actually getting gives g, low-passed over
## G_SECONDS and kept inside G_MAX. It reads the car only (never the line
## error), so it cannot chase itself. NEON_RIVAL_G overrides the start.
static var G_START := float(OS.get_environment("NEON_RIVAL_G")) if OS.get_environment("NEON_RIVAL_G").is_valid_float() else 0.0012
const G_MAX := 0.004
const G_SECONDS := 1.5
const G_MIN_SPEED := 15.0           # m/s
const G_MIN_K := 0.0007             # 1/m of actual turning before it measures
const SLIP_LIFT := 0.12             # rad of sideslip before it eases the throttle

const EDGE := 1.2                   # m kept from either edge of its side, at the car's middle
const LINE_MIN_RADIUS := 600.0      # gentler bends get no line
const LINE_MIN_K := 1.0 / LINE_MIN_RADIUS
const E_MAX := 120.0                # m, longest turn-in or straighten-out
## Crossing the road on a straight costs this much sideways grip at top speed.
const MOVE_ACCEL := 1.5             # m/s^2
const LINE_LOOK := 400.0            # m ahead a bend is planned from
const MAX_BEND_CHUNKS := 40
## Back in the sim after this many ticks on rails: the line starts again from
## where the car is.
const STALE_TICKS := 30

var personality := {}
var commit := 0.84
var brake_late := 0.85
## The one random stream this rival has (seed = the race seed). Step 1 draws
## nothing from it; mistakes (a later step) will.
var rng := RandomNumberGenerator.new()

## The car's numbers the plan runs on (setup() fills them in).
var lat_accel := GRIP_LAT_ACCEL
var brake_decel := BRAKE_DECEL
var v_top := 60.0
var k_move := MOVE_ACCEL / 3600.0   # 1/m: MOVE_ACCEL at v_top
var x_lo := RoadChunkBuilder.MEDIAN_GAP + EDGE
var x_hi := RoadChunkBuilder.MEDIAN_GAP + 4.0 * RoadChunkBuilder.LANE_W - EDGE
var own_lanes := 4

# The line: pieces in order of S, each x = x0 + v0 ds + a ds^2 / 2 from its
# start to the next one's. The last piece always holds (v0 = a = 0).
var _ps := PackedFloat64Array()
var _px := PackedFloat64Array()
var _pv := PackedFloat64Array()
var _pa := PackedFloat64Array()
var _pi := 0
var _end_s := 0.0
var _end_x := 0.0
var _scan_i := 0
var _started := false

# The speed profile from the last plan, and where it starts.
var _v := PackedFloat32Array()
var _plan_s := 0.0
var _plan_at := 0
var _plan_every := 12
var _last_drive := -1000000
var _x_cap := INF
var _gap := INF
var _lead_v := 0.0
var _lead_k := -1

## The measured understeer (see G_START).
var steer_g := G_START

## True while a car near it has the racing line switched off (see the header).
var in_traffic := false

## What the last drive tick decided (tests and the no-rubber-band log).
var target_speed := 0.0
var line_error := 0.0

## Cost, microseconds and runs, for this rival.
var plan_us := 0
var plan_runs := 0
var drive_us := 0
var drive_runs := 0
var first_frame := -1
var last_frame := -1

func _init(row := {}, seed_value := 0) -> void:
	personality = row if not row.is_empty() else RivalPersonality.row(RivalPersonality.DOCKS)
	commit = float(personality.get("commit", commit))
	brake_late = float(personality.get("brake_late", brake_late))
	rng.seed = seed_value
	_v.resize(SAMPLES)

## Reads the car (after it is in the tree): top speed, its side of the road,
## and which tick it plans on.
func setup(car: TrafficCar) -> void:
	v_top = top_speed(car)
	k_move = MOVE_ACCEL / maxf(v_top * v_top, 100.0)
	car.target_speed = v_top
	var mu: Variant = car.spec.get("coefficient_of_friction")
	if mu is Dictionary and mu.has("Road"):
		lat_accel = GRIP_LAT_ACCEL * float(mu["Road"]) / GRIP_MU
	if car.traffic != null:
		own_lanes = car.traffic.own_lanes
	x_hi = _edge_x(own_lanes)
	_plan_every = maxi(1, roundi(float(Engine.physics_ticks_per_second) / PLAN_HZ))
	_plan_at = Engine.get_physics_frames() + (maxi(car._idx, 0) * 5) % _plan_every
	_started = false

## The driver gets out: the car is plain traffic again, in the lane it is in.
static func release(car: TrafficCar, cruise: float) -> void:
	if car == null or not is_instance_valid(car) or car.racer == null:
		return
	car.racer = null
	var lanes := car.traffic.own_lanes if car.traffic != null else 4
	car.lane_i = clampi(RoadChunkBuilder.lane_at(absf(RoadFrame.unroll(car.global_position).x)), 0, lanes - 1)
	car.lane_x = TrafficManager.lane_centre(car.lane_i, car.direction > 0.0)
	car.changing = false
	car.target_speed = cruise

# ---------- pure helpers (tests/traffic/rival_plan_pure.gd) ----------

## Fastest a bend of curvature k (1/m) is taken: sqrt(commit x grip / |k|),
## capped at the car's top speed.
static func corner_speed(k: float, commit_share: float, grip: float, top: float) -> float:
	var ak := absf(k)
	if ak < 1e-7:
		return top
	return minf(top, sqrt(commit_share * grip / ak))

## The backward braking pass, in place: no point may be faster than the next
## one allows braking at b over `step` metres.
static func brake_pass(v: PackedFloat32Array, b: float, step: float) -> void:
	for i in range(v.size() - 2, -1, -1):
		var next := v[i + 1]
		v[i] = minf(v[i], sqrt(next * next + 2.0 * b * step))

## Redline in top gear: the cap the plan uses for "flat out".
static func top_speed(car: Vehicle) -> float:
	if car.gear_ratios.is_empty() or car.average_drive_wheel_radius <= 0.0:
		return 60.0
	var top_ratio: float = car.gear_ratios[car.gear_ratios.size() - 1] * car.final_drive
	return car.max_rpm / Vehicle.ANGULAR_VELOCITY_TO_RPM / maxf(top_ratio, 0.01) * car.average_drive_wheel_radius

## The line through one bend of curvature k (1/m, > 0) and `length` metres,
## with `e_in_room` / `e_out_room` metres of straight free before and after
## it, starting `room_in` metres from the inside limit and `room_out` from the
## outside one. Distances across are y, + toward the inside, from where the
## car starts. Returns e_in, e_out, c (the path's curvature), apex_s (metres
## into the bend), apex_y, end_y (where it ends up).
static func bend_line(k: float, length: float, e_in_room: float, e_out_room: float, room_in: float, room_out: float) -> Dictionary:
	var none := {"e_in": 0.0, "e_out": 0.0, "c": k, "apex_s": 0.0, "apex_y": 0.0, "end_y": 0.0}
	if k <= 0.0 or length <= 0.0 or room_in <= 0.05:
		return none
	# Turn-in and straighten-out equal: the apex lands mid bend, k h e / 2 in.
	var e_sym := 2.0 * room_in / (k * length * 0.5)
	var e_in := maxf(minf(minf(e_sym, E_MAX), e_in_room), 0.0)
	var e_out := maxf(minf(minf(e_sym, E_MAX), e_out_room), 0.0)
	for n in 32:
		if e_in + e_out < 0.5:
			return none
		var c := k * length / (length + e_in + e_out)
		var y0 := c * e_in * e_in * 0.5
		var apex_s := c * e_in / (k - c)
		var apex_y := y0 + c * e_in * c * e_in / (2.0 * (k - c))
		var end_y := y0 + c * e_in * length - (k - c) * length * length * 0.5 - c * e_out * e_out * 0.5
		if end_y < -room_out - 1e-6:
			e_out *= 0.8      # would end wider than the road: straighten out sooner
		elif apex_y > room_in + 1e-6:
			e_in *= 0.9       # would cut inside the limit: turn in later
			if e_in_room < e_sym:
				e_out *= 0.9
		else:
			return {"e_in": e_in, "e_out": e_out, "c": c, "apex_s": apex_s, "apex_y": apex_y, "end_y": end_y}
	return none

# ---------- the line ----------

func _edge_x(lanes: int) -> float:
	return RoadChunkBuilder.MEDIAN_GAP + float(lanes) * RoadChunkBuilder.LANE_W - EDGE

## Starts the line at road distance s, holding x.
func start_line(s: float, x: float) -> void:
	_started = true
	_ps.clear()
	_px.clear()
	_pv.clear()
	_pa.clear()
	_pi = 0
	_end_s = s
	_end_x = clampf(x, x_lo, x_hi)
	_piece(s, _end_x, 0.0, 0.0)
	# A bend it is already in gets no line: it holds its x to the end of it.
	_scan_i = floori(s / L)
	var sgn := signf(RoadFrame.curvature(_scan_i))
	while absf(RoadFrame.curvature(_scan_i)) >= LINE_MIN_K and signf(RoadFrame.curvature(_scan_i)) == sgn and _scan_i < floori(s / L) + MAX_BEND_CHUNKS:
		_scan_i += 1

func _piece(s: float, x: float, v: float, a: float) -> void:
	_ps.append(s)
	_px.append(x)
	_pv.append(v)
	_pa.append(a)

## Plans every bend that starts within LINE_LOOK of road distance s.
func extend_line(s: float) -> void:
	while float(_scan_i) * L < s + LINE_LOOK:
		var k := RoadFrame.curvature(_scan_i)
		if absf(k) < LINE_MIN_K:
			_scan_i += 1
			continue
		var i0 := _scan_i
		var sgn := signf(k)
		var k_sum := 0.0
		while absf(k) >= LINE_MIN_K and signf(k) == sgn and _scan_i - i0 < MAX_BEND_CHUNKS:
			k_sum += absf(k)
			_scan_i += 1
			k = RoadFrame.curvature(_scan_i)
		_add_bend(i0, _scan_i, sgn, k_sum / float(_scan_i - i0), s)
	# Forget what is well behind.
	while _ps.size() > 1 and _ps[1] < s - 30.0:
		_ps.remove_at(0)
		_px.remove_at(0)
		_pv.remove_at(0)
		_pa.remove_at(0)
		_pi = maxi(_pi - 1, 0)

func _add_bend(i0: int, i1: int, sgn: float, k: float, s_now: float) -> void:
	var s_a := float(i0) * L
	var s_b := float(i1) * L
	var base := maxf(_end_s, s_now + 5.0)
	if s_a <= base + 1.0:
		return  # no road left to set it up on: hold x through it
	var gap := s_a - base
	# + curvature bends left; own lanes are at +x, so the outside of a left
	# bend is the high edge. Fewer lanes anywhere near it (road layout): the
	# high edge comes in.
	var hi := minf(x_hi, _edge_x(_lanes_between(s_a - E_MAX, s_b + E_MAX)))
	var x_out := hi if sgn > 0.0 else x_lo
	var x_in := x_lo if sgn > 0.0 else hi
	# Straight free after it, shared with the next bend when one follows.
	var after := 0.0
	var m := i1
	while after < E_MAX and absf(RoadFrame.curvature(m)) < LINE_MIN_K:
		after += L
		m += 1
	var e_out_room := minf(after, E_MAX) if after >= E_MAX else after * 0.5
	# Across to the outside first, if there is road for it.
	var from_x := clampf(_end_x, x_lo, hi)
	var dx := x_out - from_x
	var e_want := minf(E_MAX, 2.0 * absf(x_out - x_in) / (k * (s_b - s_a) * 0.5))
	var lm := sqrt(4.0 * absf(dx) / k_move)
	if lm + e_want > gap:
		lm = gap * lm / (lm + e_want)
	var moved := signf(dx) * minf(absf(dx), k_move * lm * lm * 0.25)
	if absf(moved) < 0.05 or lm < 1.0:
		moved = 0.0
		lm = 0.0
	var x_entry := from_x + moved
	var line := bend_line(k, s_b - s_a, gap - lm, e_out_room, absf(x_entry - x_in), absf(x_entry - x_out))
	var e_in: float = line.e_in
	var e_out: float = line.e_out
	var c: float = line.c
	var s_entry := s_a - e_in
	if lm > 0.0:
		var s_move := s_entry - lm
		var a := 4.0 * moved / (lm * lm)
		_piece(s_move, from_x, 0.0, a)
		_piece(s_move + lm * 0.5, from_x + moved * 0.5, a * lm * 0.5, -a)
	if e_in + e_out < 0.5:
		_piece(s_entry, x_entry, 0.0, 0.0)
		_end_s = s_entry
		_end_x = x_entry
		return
	var inward := -sgn
	var blen := s_b - s_a
	var y_start := c * e_in * e_in * 0.5
	var y_end := y_start + c * e_in * blen - (k - c) * blen * blen * 0.5
	_piece(s_entry, x_entry, 0.0, inward * c)
	_piece(s_a, x_entry + inward * y_start, inward * c * e_in, -inward * (k - c))
	_piece(s_b, x_entry + inward * y_end, -inward * c * e_out, inward * c)
	_end_s = s_b + e_out
	_end_x = clampf(x_entry + inward * float(line.end_y), x_lo, hi)
	_piece(_end_s, _end_x, 0.0, 0.0)

## Fewest own lanes between two road distances (the plain road: own_lanes).
func _lanes_between(s0: float, s1: float) -> int:
	var layout := RoadFrame.layout
	if layout == null or not layout.lanes_live:
		return own_lanes
	var n := own_lanes
	var s := s0
	while s <= s1:
		n = mini(n, layout.lanes_at(false, s))
		s += L
	return n

func _seek(s: float) -> int:
	var i := _pi
	var n := _ps.size()
	while i + 1 < n and _ps[i + 1] <= s:
		i += 1
	while i > 0 and _ps[i] > s:
		i -= 1
	_pi = i
	return i

## Where the line is across the road at road distance s.
func line_x(s: float) -> float:
	if _ps.is_empty():
		return _end_x
	var i := _seek(s)
	var ds := maxf(s - _ps[i], 0.0)
	return _px[i] + _pv[i] * ds + 0.5 * _pa[i] * ds * ds

## The curvature the line adds to the road's at s (what the plan drives on is
## the road's curvature less this).
func line_accel(s: float) -> float:
	return 0.0 if _ps.is_empty() else _pa[_seek(s)]

# ---------- the plan (PLAN_HZ) ----------

## The speed profile from road distance s: SAMPLES speeds, STEP apart.
func plan_speeds(s: float) -> void:
	var wet: float = Weather.ai_bend_factor()
	var grip := commit * lat_accel * wet * wet
	var ci := -(1 << 40)
	var kr := 0.0
	var i := _seek(s) if not _ps.is_empty() else -1
	var n := _ps.size()
	for j in SAMPLES:
		var sj := s + float(j) * STEP
		var chunk := floori(sj / L)
		if chunk != ci:
			ci = chunk
			kr = RoadFrame.curvature(chunk)
		var ke := kr
		if i >= 0:
			while i + 1 < n and _ps[i + 1] <= sj:
				i += 1
			ke -= _pa[i]
		var ak := absf(ke)
		_v[j] = v_top if ak < 1e-7 else minf(v_top, sqrt(grip / ak))
	brake_pass(_v, brake_decel * brake_late, STEP)
	_plan_s = s

func profile() -> PackedFloat32Array:
	return _v

func _plan(car: TrafficCar, u: Vector3, s: float) -> void:
	var t0 := Time.get_ticks_usec()
	var near := car.traffic != null and _traffic_near(car, u)
	if near:
		if not in_traffic or not _started:
			start_line(s, line_x(s) if _started else u.x)   # hold this x
	else:
		if in_traffic or not _started:
			start_line(s, line_x(s) if _started else u.x)
		extend_line(s)
	in_traffic = near
	plan_speeds(s)
	# The road narrowing ahead (a lane drop) caps where it may aim.
	_x_cap = _edge_x(_lanes_between(s, s + 150.0))
	# Whatever is in the way: the strip the body sweeps to where it is aiming.
	_gap = INF
	_lead_v = 0.0
	_lead_k = -1
	var traffic := car.traffic
	if traffic != null:
		var aim := line_x(s + clampf(car.speed * LOOKAHEAD_SECONDS, LOOKAHEAD_MIN, LOOKAHEAD_MAX))
		var lo := minf(u.x, aim) - car.half_w - LEAD_MARGIN
		var hi := maxf(u.x, aim) + car.half_w + LEAD_MARGIN
		_gap = traffic.scan(u.z, car.direction, lo, hi, true, car._idx, car.half_l, LOOK_AHEAD, false)
		if traffic.q_player and _gap > PLAYER_NEAR:
			_gap = traffic.scan(u.z, car.direction, lo, hi, true, car._idx, car.half_l, LOOK_AHEAD, true)
		_lead_v = traffic.q_speed
		_lead_k = traffic.q_idx
	plan_us += Time.get_ticks_usec() - t0
	plan_runs += 1

## Whether a car is near enough on this side of the road to put the racing
## line away (see the header).
func _traffic_near(car: TrafficCar, u: Vector3) -> bool:
	var t := car.traffic
	var hi := x_hi + EDGE + RoadChunkBuilder.SHOULDER_W
	var g := t.scan(u.z, car.direction, 0.0, hi, true, car._idx, car.half_l, TRAFFIC_AHEAD, false)
	if g < INF and t.q_player and g > PLAYER_NEAR:
		g = t.scan(u.z, car.direction, 0.0, hi, true, car._idx, car.half_l, TRAFFIC_AHEAD, true)
	if g < INF:
		return true
	return t.scan(u.z, car.direction, 0.0, hi, false, car._idx, car.half_l, TRAFFIC_BEHIND, false) < INF

# ---------- the drive tick (every traffic AI stride) ----------

func drive(car: TrafficCar, delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var frame := Engine.get_physics_frames()
	if first_frame < 0:
		first_frame = frame
	if frame - _last_drive > STALE_TICKS:
		_started = false   # new, or back from the rails: the line starts here
		_plan_at = mini(_plan_at, frame)
	_last_drive = frame
	last_frame = frame
	var u := RoadFrame.unroll(car.global_position)
	var s := RoadFrame.s_at(u.z)
	if frame >= _plan_at:
		_plan_at = frame + _plan_every
		_plan(car, u, s)
	var v := car.current_speed()
	# Steering: at the line, LOOKAHEAD_SECONDS ahead.
	var look := clampf(car.speed * LOOKAHEAD_SECONDS, LOOKAHEAD_MIN, LOOKAHEAD_MAX)
	var here_x := minf(line_x(s), _x_cap)
	line_error = u.x - here_x
	# The wreck check and the hand-over to the rails read the car's path here.
	car.lane_x = here_x
	car.lane_i = clampi(RoadChunkBuilder.lane_at(here_x), 0, own_lanes - 1)
	car.changing = false
	var k_path := RoadFrame.curvature(floori(s / L)) - line_accel(s)
	_measure_understeer(car, v, delta)
	car.steering_input = TrafficCar.lane_steer(car, minf(line_x(s + look), _x_cap), car.direction, car.wheelbase, 0.0, look, 1.0 + steer_g * v * v)
	car.handbrake_input = 0.0

	# Speed: the profile under the car.
	var f := clampf((s - _plan_s) / STEP, 0.0, float(SAMPLES - 1) - 0.001)
	var i := int(f)
	var v_a := _v[i]
	var v_b := _v[i + 1]
	target_speed = lerpf(v_a, v_b, f - float(i))
	var gap := INF
	if _lead_k >= 0 and car.traffic != null:
		gap = car.traffic.entry_gap(_lead_k, u.z, car.direction, car.half_l)
		_lead_v = car.traffic.entry_speed(_lead_k, car.direction)
	car.lead_gap = gap
	car.lead_speed = _lead_v
	car.lead_is_player = _lead_k == 0
	car.hazard = car._check_wreck(delta, v)
	if car.hazard:
		car.throttle_input = 0.0
		car.brake_input = 1.0
		_tock(t0)
		return
	var a := 0.0
	if v > target_speed + COAST_BAND:
		a = -(maxf(v_a * v_a - v_b * v_b, 0.0) / (2.0 * STEP) + K_BRAKE * (v - target_speed))
	elif v < target_speed:
		a = (target_speed - v) * K_THROTTLE
	if gap < INF:
		a = minf(a, TrafficCar.follow_accel(v, target_speed, gap, _lead_v, T_GAP))
	if a < 0.0:
		car.throttle_input = 0.0
		# Grip is shared: the harder it is cornering, the less brake it gets.
		var lat := v * v * absf(k_path) / maxf(lat_accel, 0.1)
		car.brake_input = clampf(-a / brake_decel, 0.0, sqrt(maxf(0.15, 1.0 - lat * lat)))
	else:
		car.brake_input = 0.0
		car.throttle_input = clampf(a, 0.0, 1.0)
		if car.throttle_input > 0.3 and absf(_slip(car)) > SLIP_LIFT:
			car.throttle_input *= 0.3
	_tock(t0)

## One sample of g (see G_START) from what the car is doing now.
func _measure_understeer(car: TrafficCar, v: float, delta: float) -> void:
	if v < G_MIN_SPEED:
		return
	var k_act := car.angular_velocity.y / v
	# Only while wheel and car turn the same way, steadily enough to read.
	if absf(k_act) < G_MIN_K or k_act * car.steering_amount <= 0.0:
		return
	var angle := pow(absf(car.steering_amount), car.steering_exponent) * car.max_steering_angle
	var g := (angle / (car.wheelbase * absf(k_act)) - 1.0) / (v * v)
	steer_g = clampf(steer_g + (g - steer_g) * minf(delta / G_SECONDS, 1.0), 0.0, G_MAX)

func _tock(t0: int) -> void:
	drive_us += Time.get_ticks_usec() - t0
	drive_runs += 1

## Sideslip, rad: the angle between the nose and the way the car is going.
static func _slip(car: Vehicle) -> float:
	var vel := car.linear_velocity
	vel.y = 0.0
	if vel.length_squared() < 16.0:
		return 0.0
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized().signed_angle_to(vel.normalized(), Vector3.UP)

## Average milliseconds of race brain per physics tick since the first drive.
func cost_ms_per_tick() -> float:
	var ticks := last_frame - first_frame + 1
	return 0.0 if first_frame < 0 or ticks <= 0 else float(plan_us + drive_us) / 1000.0 / float(ticks)

## One line for a test's log.
func cost_summary() -> String:
	return "race brain %.4f ms per physics tick (plan %.3f ms x %d runs, drive %.4f ms x %d runs), understeer g %.5f" % [
		cost_ms_per_tick(), float(plan_us) / 1000.0 / maxf(float(plan_runs), 1.0), plan_runs,
		float(drive_us) / 1000.0 / maxf(float(drive_runs), 1.0), drive_runs, steer_g]
