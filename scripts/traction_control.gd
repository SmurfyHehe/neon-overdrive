extends RefCounted
class_name TractionControl

# Traction control (2026-10-08, Roy: "fix tc"; design in tc-research.md).
#
# The vendored GEVP TC never fired: it compares the wheels' slip_vector.y
# against traction_control_max_slip (8 stock, 4 High), but forward wheelspin
# reads NEGATIVE slip_y (-4 to -13 in a burnout) and the positive side is
# bounded under 1, so `slip_y > 8` was never true. This replaces it game-side
# and leaves the vendor file alone: PlayerCar zeroes the vendor's own check
# around its tick and scales engine torque (torque_mult) by (1 - cut) instead.
#
# Signal: the driven wheels' excess surface speed over the ground in the
# direction of drive, wheel.spin_velocity_diff (m/s) x the gear's sign, so
# reverse works too. Allowed excess grows with speed (a + r x v): at a
# standstill a ratio means nothing, at speed r is roughly the slip ratio.
# Cut: proportional across a band above the allowance, capped at max_cut,
# then filtered with a fast attack and a slow release so it does not flicker
# at the tick rate the way the vendor's all-or-nothing cut would.
#
# Levels come from traction_control_max_slip, which the Tuner already sets to
# 0 (Off), the stock 8 (Low) or 4 (High): <= 0 is Off, under 6 is High,
# anything else Low. Roy chose (2026-10-08): Low is light (at most 60% cut)
# and stands aside for drifts and handbrake slides; High keeps cutting; TC
# works in reverse; traffic cars get none. Research suggested an 18% flare,
# but this tyre model grips best well past that: an 18% Low cost the stock
# coupe 6% of its 5 s launch speed while barely trimming the clutch-bite
# spike. Low allows 1.5 m/s + 18%, plus 4.5 m/s at a standstill fading out
# by 4 m/s so the launch chirp gets through; High 1.5 m/s + 15%, 90% cut.

enum Level { OFF, LOW, HIGH }

const LOW_A := 1.5  # m/s of excess allowed at any speed
const LOW_LAUNCH := 4.5  # extra m/s allowed at a standstill, gone by LAUNCH_FADE
const LAUNCH_FADE := 4.0  # m/s
const LOW_R := 0.18  # extra allowed per m/s of speed (~slip ratio)
const LOW_MAX_CUT := 0.6
const HIGH_A := 1.5
const HIGH_R := 0.15
const HIGH_MAX_CUT := 0.9
const ATTACK := 0.04  # s
const RELEASE := 0.2  # s
const SIDEWAYS_DEG := 12.0  # Low stands aside beyond this body slip angle
const STEER_ASIDE := 0.3  # ... or with the wheel turned past this share of lock
const SIDEWAYS_MIN_SPEED := 3.0  # m/s; below this the slip angle is noise
const HANDBRAKE_HOLDOFF := 0.8  # s after the handbrake is let go
const LINE_LOCK_HOLDOFF := 1.0  # s after the line lock lets go

## 0..max_cut: the share of the throttle taken away this tick.
var cut := 0.0
## Why TC is not acting, for tests and the HUD ("" while it can act).
var standing_aside := ""
var _holdoff := 0.0

static func level_of(max_slip: float) -> Level:
	if max_slip <= 0.0:
		return Level.OFF
	return Level.HIGH if max_slip < 6.0 else Level.LOW

## Worst driven-wheel excess speed (m/s) in the direction of drive.
static func excess_speed(car: Vehicle) -> float:
	var dir := signf(car.current_gear)
	var worst := 0.0
	for w in car.drive_wheels:
		if w.is_colliding():
			worst = maxf(worst, w.spin_velocity_diff * dir)
	return worst

## Body slip angle in degrees (0 = rolling straight).
static func slip_angle_deg(car: Vehicle) -> float:
	var v := car.local_velocity
	return rad_to_deg(atan2(absf(v.x), absf(v.z)))

## Run once per tick before the vehicle sim; sets `cut`.
func step(car: Vehicle, throttle: float, handbrake: bool, line_lock: bool, delta: float) -> void:
	var level := level_of(car.traction_control_max_slip)
	if handbrake:
		_holdoff = maxf(_holdoff, HANDBRAKE_HOLDOFF)
	if line_lock:
		_holdoff = maxf(_holdoff, LINE_LOCK_HOLDOFF)
	_holdoff = maxf(_holdoff - delta, 0.0)
	var target := 0.0
	standing_aside = ""
	if level == Level.OFF:
		standing_aside = "off"
	elif car.current_gear == 0:
		standing_aside = "neutral"
	elif throttle < 0.05:
		standing_aside = "no throttle"
	elif _holdoff > 0.0:
		standing_aside = "line lock" if line_lock else "handbrake"
	elif level == Level.LOW and absf(car.steering_input) > STEER_ASIDE:
		# a donut or drift entry builds its angle with the wheel turned: cutting
		# there (before the 12 deg below) took the stock donut from 0.9 to 0.7 turns
		standing_aside = "steering"
	elif level == Level.LOW and car.speed > SIDEWAYS_MIN_SPEED and slip_angle_deg(car) > SIDEWAYS_DEG:
		standing_aside = "sideways"
	else:
		var high := level == Level.HIGH
		var allow := (HIGH_A if high else LOW_A) + (HIGH_R if high else LOW_R) * car.speed
		if not high:  # let the clutch-bite chirp through, catch wheelspin once rolling
			allow += LOW_LAUNCH * clampf(1.0 - car.speed / LAUNCH_FADE, 0.0, 1.0)
		var band := 0.5 * allow + 1.0
		target = clampf((excess_speed(car) - allow) / band, 0.0, 1.0) * (HIGH_MAX_CUT if high else LOW_MAX_CUT)
	var tau := ATTACK if target > cut else RELEASE
	cut = lerpf(cut, target, 1.0 - exp(-delta / tau))
	if cut < 0.005:
		cut = 0.0

