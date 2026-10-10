class_name AutoBox
extends RefCounted

# The realistic automatic (2026-10-10, Roy: "go ahead", all nine default picks).
# The player's car in AUTO only: a car gets one of these when its spec has an
# "auto" block (CarSpec.player_spec sets it; traffic and cop specs have none and
# keep GEVP's simple automatic untouched).
#
# Two halves, both run from tick(), once per physics step, before GEVP's motor
# and clutch (gevp_vehicle.gd DEVIATION 14 lists the places that read the
# numbers this leaves behind):
#
#  - the shift brain: when to change gear. A smoothed demand instead of the raw
#    throttle (a keyboard is 0 or 1), kickdown (up to two gears in one shift,
#    after the family's delay), gear hold in corners and on a climb, stepping
#    down under braking, first gear for the last 10 km/h.
#  - the torque converter, faked through GEVP's own clutch: the clutch's grip
#    follows engine rpm (a little at idle = creep, all of it by stall rpm, so a
#    launch flares to about stall rpm and holds there), torque is multiplied
#    while it slips, a few percent of slip is left in at speed unless the car
#    has a lock-up clutch, and a gear change keeps driving the car while the
#    revs slide to the next gear's speed, instead of GEVP's throttle-off gap.
#
# Cost per tick: float arithmetic and one small loop over the drive wheels
# (get_drivetrain_spin). No nodes, no allocations.

## The three eras. A car's own "auto" block overrides any of these keys.
## lockup_from_gear: positive = that gear and up; negative = counted from the
## top (-2 = the top two gears); lockup_kmh 0 = no lock-up clutch at all.
const FAMILIES := {
	"old": {  # 60s-80s three- and four-speeds (TH400-like): slow, slurred, loose
		"auto_shift_time": 0.7, "shift_torque": 0.6, "stall_rpm": 2200.0, "conv_mult": 2.1,
		"lockup_kmh": 0.0, "lockup_from_gear": 0, "kickdown_delay": 0.6, "brake_down_rpm": 0.55,
		"blip": false, "hill_hold": 0.0,
	},
	"90s": {  # four-speed overdrive boxes (4L60-like): lock-up in the top two gears
		"auto_shift_time": 0.5, "shift_torque": 0.5, "stall_rpm": 2000.0, "conv_mult": 2.0,
		"lockup_kmh": 70.0, "lockup_from_gear": -2, "kickdown_delay": 0.45, "brake_down_rpm": 0.65,
		"blip": false, "hill_hold": 0.0,
	},
	"modern": {  # five and six gears: quick, firm, locked from 2nd, rev blips, hill hold
		"auto_shift_time": 0.3, "shift_torque": 0.4, "stall_rpm": 1900.0, "conv_mult": 1.8,
		"lockup_kmh": 40.0, "lockup_from_gear": 2, "kickdown_delay": 0.3, "brake_down_rpm": 0.75,
		"blip": true, "hill_hold": 1.0,
	},
}
const DEFAULT_FAMILY := "90s"
## "box" in a car's auto block: what the car was built with. A manual-box car
## driven in AUTO shifts a little slower than its family (Roy's pick 1).
const BOX_MANUAL := "manual"
const BOX_AUTO := "auto"
const BOX_PADDLE := "paddle"
const MANUAL_BOX_EXTRA_TIME := 0.1

# --- shift brain ---
const DEMAND_RISE := 0.4         # s for the smoothed demand to go 0 -> 1
const DEMAND_FALL := 0.8         # s for it to go 1 -> 0
const UP_LIGHT := 0.45           # upshift at this share of max rpm on no demand ...
const UP_FULL := 0.92            # ... and at this share flat out (road-speed rpm: the engine is a few percent above it through the converter)
const DOWN_LIGHT := 0.30         # downshift once the lower gear would sit under this share (no demand) ...
const DOWN_FULL := 0.75          # ... or this share (flat out)
const REVERSAL_GAP := 1.2        # s before the map may undo its last shift (no up-down-up)
const KICK_PRESS := 0.9          # throttle that counts as floored
const KICK_PRESS_TIME := 0.3     # it has to get there this fast to be a kickdown
const KICK_MAX_RPM := 0.75       # the kickdown gear stays under this share of max rpm (at 0.9 it could land a fraction of a second from the next upshift)
const KICK_MAX_GEARS := 2
const KICK_MIN_KMH := 15.0
const CORNER_LAT_G := 0.35
const CORNER_STEER := 0.4        # share of lock
const CORNER_MIN_KMH := 30.0
const CORNER_AFTER := 1.0        # s the gear is still held after the corner
const BRAKE_ON := 0.3
const BRAKE_STEP_GAP := 0.35     # s between brake downshifts
const CLIMB_DECEL := 0.5         # m/s^2 of slowing down ...
const CLIMB_DEMAND := 0.6        # ... with this much demand = a climb: hold the gear
const FIRST_GEAR_KMH := 10.0     # D drops to 1st below this
const ACCEL_TAU := 0.3
const LOCK_DEMAND_ON := 0.6      # the lock-up clutch closes under this demand ...
const LOCK_DEMAND_OFF := 0.7     # ... and opens again above this
const LOCK_KMH_HYST := 5.0
const LOCK_TIME := 0.4           # s for the lock-up clutch to close or open

# --- converter ---
const CREEP_ACCEL := 1.3         # m/s^2 the idle creep pulls with from rest
const CREEP_TOP := 2.0           # m/s (7.2 km/h): the creep has faded to nothing here
const SLIP_MIN := 0.03           # slip left in at speed, light load ...
const SLIP_MAX := 0.05           # ... and flat out
const LOAD_TAU := 0.15
const IDLE_DEAD := 120.0         # rpm above idle before the converter takes up drive (idle wobble moves nothing)
const MULT_CAP := 1.0            # multiplied torque never tops this share of the engine's peak torque
const COUPLE_RATIO := 0.85       # turbine / engine speed where torque multiplication ends
const OVERRUN_BRAKING := 0.5     # share of engine braking that gets through a slipping converter
const DOWN_DRAG := 0.10          # share of max torque the wheels may spend pulling the revs up on a downshift
const CATCH_TIME := 1.0          # s the revs get to arrive after a downshift before the box couples anyway
const BLIP_TIME := 0.12          # s for the rev blip to reach the lower gear's speed
const MIN_SLIDE_SPIN := 30.0     # rad/s at the engine side: under this a shift has nothing to slide
const SHIFT_RAMP := 1.0 / 0.15   # the torque cut fades in and out over 15% of the shift
const REF_REFRESH := 120         # ticks between re-reading the torque curve at stall rpm

# --- the car's own numbers (setup) ---
var family := DEFAULT_FAMILY
var box := BOX_MANUAL
var shift_time := 0.5
var shift_torque := 0.5
var stall_rpm := 2000.0
var conv_mult := 2.0
var lockup_kmh := 70.0
var lock_gear := 99              # lowest gear the lock-up clutch works in
var kickdown_delay := 0.45
var brake_down_rpm := 0.65
var blip := false
var hill_hold := 0.0
var _steer_hold := 0.4

# --- what GEVP reads each tick ---
var clutch_amount := 1.0         # 0 = fully gripping, 1 = open (GEVP's sense)
var speed_k := 1.0               # engine speed the clutch aims for, as a multiple of the gearbox's
var gain := 1.0                  # torque multiplication on the way to the wheels
var torque_scale := 1.0          # engine torque cut during an upshift
var drag_scale := 1.0            # engine braking through the converter
var drag_cap := INF              # Nm the wheels may put into the engine (downshifts)
var feed_torque := 0.0           # Nm put through the clutch directly: the idle creep, and the drive during an upshift
var hill_hold_left := 0.0        # s of hill hold left after the brake came off

# --- state others may read ---
var demand := 0.0
var shifting := false
var shift_dir := 0
var shift_count := 0             # every gear change the box has made (tests, cockpit)
var lock := 0.0                  # 0 = converter slipping, 1 = lock-up clutch closed
var blipping := false
var kick_count := 0

var _shift_t := 0.0
var _shift_len := 0.5
var _blip_shift := false
var _k0 := 1.0
var _catch_left := 0.0
var _since_shift := 10.0
var _last_dir := 0
var _rise_t := 0.0
var _was_floored := false
var _kick_armed := false
var _kick_left := 0.0
var _corner_left := 0.0
var _accel := 0.0
var _prev_fwd := 0.0
var _load := 0.0
var _lock_want := false
var _t_ref := 0.0
var _ref_age := REF_REFRESH

## The family's numbers with the car's own on top.
static func resolve(cfg: Dictionary) -> Dictionary:
	var fam := String(cfg.get("family", DEFAULT_FAMILY))
	if not FAMILIES.has(fam):
		fam = DEFAULT_FAMILY
	var out: Dictionary = FAMILIES[fam].duplicate()
	for k in cfg:
		out[k] = cfg[k]
	out["family"] = fam
	if not out.has("box"):
		out["box"] = BOX_MANUAL
	return out

func setup(v: Vehicle, cfg: Dictionary) -> void:
	var c := resolve(cfg)
	family = c.family
	box = String(c.box)
	shift_time = float(c.auto_shift_time) + (MANUAL_BOX_EXTRA_TIME if box == BOX_MANUAL else 0.0)
	shift_torque = float(c.shift_torque)
	stall_rpm = maxf(float(c.stall_rpm), v.idle_rpm + 300.0)
	conv_mult = float(c.conv_mult)
	lockup_kmh = float(c.lockup_kmh)
	var from := int(c.lockup_from_gear)
	var n := v.gear_ratios.size()
	lock_gear = 99 if lockup_kmh <= 0.0 or from == 0 else (from if from > 0 else maxi(n + from + 1, 1))
	kickdown_delay = float(c.kickdown_delay)
	brake_down_rpm = float(c.brake_down_rpm)
	blip = bool(c.blip)
	hill_hold = float(c.hill_hold)
	_steer_hold = pow(CORNER_STEER, 1.0 / maxf(v.steering_exponent, 0.1))
	reset()

## Forget everything in flight (the gearbox mode changed, or the car was reset).
func reset() -> void:
	shifting = false
	blipping = false
	shift_dir = 0
	_catch_left = 0.0
	_kick_armed = false
	_was_floored = false
	_corner_left = 0.0
	_since_shift = 10.0
	_last_dir = 0
	lock = 0.0
	_lock_want = false
	speed_k = 1.0
	gain = 1.0
	torque_scale = 1.0
	drag_scale = 1.0
	drag_cap = INF
	feed_torque = 0.0
	hill_hold_left = 0.0
	_ref_age = REF_REFRESH

func tick(v: Vehicle, delta: float) -> void:
	var gear := v.current_gear
	if gear == 0:
		if v.is_shifting:
			clutch_amount = 1.0
			return
		# D has no neutral: a car handed over in N goes straight to first.
		v.current_gear = 1
		v.requested_gear = 1
		gear = 1
	if not v.engine_running:
		# engine off (a stall carried over, a dead engine): nothing to transmit, no creep
		reset()
		clutch_amount = 1.0
		return
	var fwd := -v.local_velocity.z
	var kmh := fwd * 3.6
	var thr := clampf(v.throttle_input, 0.0, 1.0)
	demand = move_toward(demand, thr, delta / (DEMAND_RISE if thr > demand else DEMAND_FALL))
	_since_shift += delta
	_accel += ((fwd - _prev_fwd) / delta - _accel) * minf(1.0, delta / ACCEL_TAU)
	_prev_fwd = fwd

	if gear > 0 and not v.is_shifting:
		_brain(v, delta, gear, fwd, kmh, thr)
		gear = v.current_gear

	# ---- converter ----
	var ratio := v.get_gear_ratio(gear)
	var spin := v.get_drivetrain_spin()
	var w_e := maxf(v.motor_rpm / Vehicle.ANGULAR_VELOCITY_TO_RPM, 1.0)
	var w_t := absf(spin * ratio)

	# lock-up clutch
	if lock_gear <= gear:
		if _lock_want:
			_lock_want = kmh > lockup_kmh - LOCK_KMH_HYST and demand < LOCK_DEMAND_OFF and gear >= lock_gear
		else:
			_lock_want = kmh > lockup_kmh and demand < LOCK_DEMAND_ON
	else:
		_lock_want = false
	var lock_to := 1.0 if _lock_want and not shifting and not _kick_armed else 0.0
	lock = move_toward(lock, lock_to, delta / LOCK_TIME)

	# slip left in at speed: with the load, so it changes sign smoothly on the overrun
	_load += (clampf(v.torque_output / maxf(v.max_torque, 1.0), -1.0, 1.0) - _load) * minf(1.0, delta / LOAD_TAU)
	var slip := clampf(_load * 10.0, -1.0, 1.0) * lerpf(SLIP_MIN, SLIP_MAX, absf(_load)) * (1.0 - lock)
	speed_k = 1.0 + slip
	torque_scale = 1.0
	drag_cap = INF
	blipping = false
	var sliding_up := false
	var shift_feed := 0.0

	if shifting:
		_shift_t += delta
		var s := _shift_t / _shift_len
		if s >= 1.0:
			shifting = false
			if shift_dir < 0 and not _blip_shift:
				_catch_left = CATCH_TIME
		else:
			speed_k = lerpf(_k0, speed_k, s * s * (3.0 - 2.0 * s))
			if shift_dir > 0:
				# Upshift: the revs are walked down to the higher gear's speed and
				# the wheels get shift_torque of what the engine is making. The
				# clutch solver is left out of it: locking the engine to the falling
				# target would hand its spin-down to the wheels as extra shove (with
				# GEVP's heavy flywheel, more than the engine's own torque), which
				# made a shift faster than no shift.
				sliding_up = true
				torque_scale = lerpf(1.0, shift_torque, clampf(minf(s, 1.0 - s) * SHIFT_RAMP, 0.0, 1.0))
				shift_feed = maxf(v.torque_output, 0.0)  # last tick's, already scaled
				v.motor_rpm = maxf(w_t * speed_k * Vehicle.ANGULAR_VELOCITY_TO_RPM, v.idle_rpm)
				w_e = maxf(v.motor_rpm / Vehicle.ANGULAR_VELOCITY_TO_RPM, 1.0)
			elif _blip_shift:
				# rev blip: the engine is put on the lower gear's speed, the wheels pay nothing
				blipping = true
				drag_cap = 0.0
				v.motor_rpm = maxf(v.motor_rpm, w_t * speed_k * Vehicle.ANGULAR_VELOCITY_TO_RPM)
				w_e = maxf(v.motor_rpm / Vehicle.ANGULAR_VELOCITY_TO_RPM, 1.0)
			else:
				drag_cap = DOWN_DRAG * v.max_torque
	elif _catch_left > 0.0:
		# after a downshift with no blip: the revs are still on their way up
		_catch_left -= delta
		if w_e >= 0.97 * w_t * speed_k:
			_catch_left = 0.0
		else:
			drag_cap = DOWN_DRAG * v.max_torque

	# grip: nothing below idle, the creep at idle, everything by stall rpm
	_ref_age += 1
	if _ref_age >= REF_REFRESH:
		_ref_age = 0
		_t_ref = maxf(v.get_torque_at_rpm(stall_rpm), 1.0)
	var x := (v.motor_rpm - v.idle_rpm - IDLE_DEAD) / (stall_rpm - v.idle_rpm - IDLE_DEAD)
	var cap := _t_ref * x * x if x > 0.0 else 0.0
	var max_cap := maxf(v.max_clutch_torque * v.clutch_cap_mult, 1.0)
	clutch_amount = 1.0 if sliding_up else 1.0 - clampf(lerpf(cap / max_cap, 1.0, lock), 0.0, 1.0)

	# torque multiplication while the turbine is well behind the engine
	var sr := w_t / w_e
	gain = lerpf(lerpf(conv_mult, 1.0, clampf(sr / COUPLE_RATIO, 0.0, 1.0)), 1.0, lock)
	gain = clampf(MULT_CAP * v.max_torque / maxf(minf(cap, max_cap), 1.0), 1.0, gain)

	# Creep: at idle the clutch's own torque is whatever locking the wheels to
	# the engine would take, scaled down, which is next to nothing at walking
	# pace. So the creep is a set pull instead, fed in next to it: CREEP_ACCEL
	# from rest, fading to none at CREEP_TOP, off with the brake on.
	feed_torque = shift_feed
	if (gear == 1 or gear == -1) and v.brake_input <= 0.1 and x < 0.2 and not sliding_up and not v.is_shifting:
		var along := fwd if gear > 0 else -fwd
		var creep := CREEP_ACCEL * v.mass * v.average_drive_wheel_radius / (absf(ratio) * gain)
		creep *= clampf(1.0 - along / CREEP_TOP, 0.0, 1.0)
		creep *= clampf((v.motor_rpm - 0.6 * v.idle_rpm) / (0.3 * v.idle_rpm), 0.0, 1.0)
		feed_torque = creep * (1.0 - maxf(x, 0.0) * 5.0)  # hands over to the converter as the revs rise
	drag_scale = lerpf(OVERRUN_BRAKING, 1.0, maxf(lock, v.throttle_amount))

	# hill hold after the brake comes off (modern boxes)
	if v.brake_input >= BRAKE_ON:
		hill_hold_left = hill_hold
	elif hill_hold_left > 0.0:
		hill_hold_left -= delta

func _brain(v: Vehicle, delta: float, gear: int, fwd: float, kmh: float, thr: float) -> void:
	# corner: lateral g from the yaw rate, or a lot of lock
	if kmh > CORNER_MIN_KMH and (absf(v.angular_velocity.y) * fwd > CORNER_LAT_G * 9.81 or absf(v.steering_amount) > _steer_hold):
		_corner_left = CORNER_AFTER
	elif _corner_left > 0.0:
		_corner_left -= delta

	# kickdown: floored, and it got there fast
	if thr < 0.5:
		_rise_t = 0.0
	else:
		_rise_t += delta
	var floored := thr >= KICK_PRESS
	if floored and not _was_floored and _rise_t <= KICK_PRESS_TIME + delta:
		_kick_armed = true
		_kick_left = kickdown_delay
	elif not floored:
		_kick_armed = false
	_was_floored = floored

	if shifting:
		return
	var n := v.gear_ratios.size()
	var max_rpm := v.max_rpm
	# engine rpm per unit of gear ratio at this road speed (no wheelspin in it)
	var per_ratio := v.final_drive * maxf(fwd, 0.0) / v.average_drive_wheel_radius * Vehicle.ANGULAR_VELOCITY_TO_RPM

	if kmh < FIRST_GEAR_KMH and gear > 1:
		_begin(v, 1, thr)
		return

	if _kick_armed:
		_kick_left -= delta
		if _kick_left > 0.0:
			return  # the box is making its mind up: no other shift meanwhile
		_kick_armed = false
		if kmh >= KICK_MIN_KMH and gear > 1:
			var to := gear
			for g in range(maxi(gear - KICK_MAX_GEARS, 1), gear):
				if v.gear_ratios[g - 1] * per_ratio < max_rpm * KICK_MAX_RPM:
					to = g
					break
			if to < gear:
				demand = 1.0
				kick_count += 1
				_begin(v, to, thr)
				return

	var braking := v.brake_input > BRAKE_ON
	if braking and gear > 1 and _since_shift >= BRAKE_STEP_GAP \
			and v.gear_ratios[gear - 2] * per_ratio < max_rpm * brake_down_rpm:
		_begin(v, gear - 1, thr)
		return

	var gap := v.automatic_time_between_shifts * 0.001
	var rpm_now: float = v.gear_ratios[gear - 1] * per_ratio
	# Run out to the top of the revs: only the shift itself delays that upshift
	# (after a kickdown the engine would otherwise sit on the limiter).
	var revved_out := rpm_now > max_rpm * UP_FULL
	if gear < n and not braking and _corner_left <= 0.0 and not (_accel < -CLIMB_DECEL and demand > CLIMB_DEMAND) \
			and (_last_dir >= 0 or _since_shift >= REVERSAL_GAP or revved_out):
		if rpm_now > max_rpm * lerpf(UP_LIGHT, UP_FULL, demand) and _since_shift >= (shift_time if revved_out else maxf(shift_time, gap)):
			_begin(v, gear + 1, thr)
			return
		# wheelspin on the limiter (GEVP's own rule): road speed nearly there, wheels past max rpm
		if rpm_now > max_rpm * 0.8 and v.get_drivetrain_spin() * v.get_gear_ratio(gear) * Vehicle.ANGULAR_VELOCITY_TO_RPM > max_rpm \
				and _since_shift >= shift_time:
			_begin(v, gear + 1, thr)
			return
	if gear > 1 and (_last_dir <= 0 or _since_shift >= REVERSAL_GAP) and _since_shift >= maxf(shift_time, gap * 0.6) \
			and v.gear_ratios[gear - 2] * per_ratio < max_rpm * lerpf(DOWN_LIGHT, DOWN_FULL, demand):
		_begin(v, gear - 1, thr)

## Change gear now. The ratio switches at once (that is the torque phase); the
## revs then slide to the new gear's speed over the shift time, under power.
func _begin(v: Vehicle, to: int, thr: float) -> void:
	shift_dir = 1 if to > v.current_gear else -1
	v.current_gear = to
	v.requested_gear = to
	v.last_shift_delta_time = v.delta_time
	_since_shift = 0.0
	_last_dir = shift_dir
	_catch_left = 0.0
	shift_count += 1
	var target := absf(v.get_drivetrain_spin() * v.get_gear_ratio(to))
	if target < MIN_SLIDE_SPIN:
		shifting = false  # nearly stopped: the converter takes it up
		return
	_k0 = clampf(v.motor_rpm / Vehicle.ANGULAR_VELOCITY_TO_RPM / target, 0.4, 2.5)
	_shift_t = 0.0
	_blip_shift = shift_dir < 0 and blip and thr < 0.2
	_shift_len = BLIP_TIME if _blip_shift else shift_time
	shifting = true
