extends RefCounted
class_name SlideHelp

# Slide-catch help (driving-feel pass, 2026-10-08; Roy: "slide help with off
# switch, yes"). On a keyboard the steering is all or nothing, so catching the
# rear when it steps out takes a precise, quick countersteer that a key can't
# give. This adds it: once the rear steps out, the front wheels get turned
# toward where the car is actually going, on top of what the keys ask for.
# Pointing the fronts down the direction of travel is what a driver does to
# catch a slide; it doesn't stop a drift you hold, it stops the snap into a
# spin.
#
# When it acts: the car rotating in a direction the keys are not asking for
# (you let go, or your countersteer is not enough), past OVER_FROM, with the
# body slip angle past FROM_DEG. While you steer the way the car is rotating
# you meant it (a corner, a drift), and the help stays out unless the slide
# is past BIG_DEG, the start of a spin. Slip angle alone can't tell a slide
# from a corner: a hard steady corner on this car already runs several
# degrees of it, and turning in opens it quickly (tests/feel_pass_1.gd and the
# corner case in tests/slide_help.gd caught both). Once it has acted the help
# stays on, fading over HOLD_S, so it keeps holding the catch.
#
# - Only the keyboard path (PlayerCar._read_keyboard): AI drivers and tests
#   that drive through `driver` steer exactly as they ask.
# - Stands aside with the handbrake held and for HANDBRAKE_HOLDOFF after it,
#   so a handbrake entry gets its rotation first; below MIN_SPEED and in
#   reverse it does nothing.
# - The help may go past the speed lock cap (a slide needs more lock than the
#   cap allows at speed) up to MAX_LOCK.
# The off switch is AssistSettings.slide_help ([assist] in settings.cfg,
# "Slide help" in the pause menu). `amount` is for tests and the HUD.

const FROM_DEG := 4.0        # slip angle where it starts to help
const FULL_DEG := 10.0       # ... and helps in full from here
const OVER_FROM := 0.25      # rad/s of rotation the keys are not asking for
const OVER_FULL := 0.7       # ... in full from here
const BIG_DEG := 20.0        # steering with the rotation, the help still catches past this
const BIG_FULL_DEG := 30.0
const WITH_KEYS := 0.05      # lock share that counts as steering one way
const HOLD_S := 0.8          # s the help takes to let go once the car stops over-rotating
const GAIN := 0.85           # share of the countersteer that points the fronts down the slide
const MAX_LOCK := 0.7        # most lock the help can ask for
const MIN_SPEED := 6.0       # m/s
const HANDBRAKE_HOLDOFF := 0.8  # s after the handbrake is let go

## Lock fraction added this tick, + = right (steer_fraction's sign).
var amount := 0.0
var _holdoff := 0.0
var _engage := 0.0           # 0..1, latched by the slip opening up, fades over HOLD_S
var over := 0.0              # rad/s of rotation the keys are not asking for, for tests

## The lock fraction (+ right) to ask for, given what the keys ask for (`want`,
## same sign) and the cap the keys are held to.
func steer(car: PlayerCar, want: float, cap: float, delta: float) -> float:
	amount = 0.0
	if car.handbrake_input > 0.5:
		_holdoff = HANDBRAKE_HOLDOFF
	else:
		_holdoff = maxf(_holdoff - delta, 0.0)
	var b := car.global_transform.basis
	var v := car.linear_velocity
	var along := v.dot(-b.z)
	var slip := atan2(v.dot(b.x), along) if along > 0.5 else 0.0   # + = moving to its right of where it points
	if not AssistSettings.slide_help or _holdoff > 0.0 or along < MIN_SPEED:
		_engage = 0.0
		over = 0.0
		return want
	# Yaw rate, + = turning right (steer_fraction's sign).
	var yaw := -car.angular_velocity.dot(b.y)
	var with_keys := absf(want) > WITH_KEYS and signf(want) == signf(yaw)
	var source := 0.0
	if with_keys:
		over = 0.0
		source = smoothstep(deg_to_rad(BIG_DEG), deg_to_rad(BIG_FULL_DEG), absf(slip))
	else:
		over = absf(yaw)
		source = smoothstep(OVER_FROM, OVER_FULL, over)
	_engage = maxf(_engage - delta / HOLD_S, source)
	var t := smoothstep(deg_to_rad(FROM_DEG), deg_to_rad(FULL_DEG), absf(slip)) * _engage
	if t <= 0.0:
		return want
	# The fronts pointing down the direction of travel: that lock, as a share.
	var catch := clampf(slip / maxf(car.max_steering_angle, 0.01), -MAX_LOCK, MAX_LOCK)
	amount = catch * GAIN * t
	return clampf(want + amount, -maxf(cap, MAX_LOCK), maxf(cap, MAX_LOCK))
