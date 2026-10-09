class_name DashAnim
extends RefCounted

# Dashboard and engine animations (2026-10-09), all cosmetic and cheap (a few
# sin() calls per frame, no allocation, no extra draws). Each has its own
# FxSettings flag so it can be switched off:
# - needle_shake:  the tach needle trembles in the last few percent before the redline
# - idle_shake:    the cockpit eye vibrates a hair while the engine idles
# - startup_sweep: both needles sweep to full and back when the engine starts
# - coldstart_puff: a small puff of exhaust smoke (no fire) when it starts
# The laws are static so tests and the consumers (CockpitFrame, ChaseCamera,
# ExhaustFlames) share them. The instance only keeps the start-up sweep clock.

## Share of max rpm where the needle starts to shake; full shake at 1.0.
const SHAKE_START := 0.92
const SHAKE_DEG := 1.6
const SHAKE_HZ_A := 37.0
const SHAKE_HZ_B := 53.0

## Idle vibration: amplitude in metres (eye) and degrees (roll), fading out as
## the revs leave idle and as the car picks up speed.
const IDLE_SHAKE_M := 0.0012
const IDLE_SHAKE_DEG := 0.08
const IDLE_BAND := 0.6        # fades to nothing at idle_rpm * (1 + IDLE_BAND)
const IDLE_SPEED_FADE := 8.0  # m/s at which the road noise has swallowed it
const IDLE_HZ_MAX := 30.0     # keeps the wobble readable at 60 fps

## Start-up sweep: up, a short hold at full, down.
const SWEEP_UP := 0.45
const SWEEP_HOLD := 0.08
const SWEEP_DOWN := 0.6
const SWEEP_TOTAL := SWEEP_UP + SWEEP_HOLD + SWEEP_DOWN

## Cold-start puff size (ExhaustFlames smoke, 0..1) and how long after the
## engine catches it appears.
const PUFF_SIZE := 0.5
const PUFF_DELAY := 0.15

var sweep_t := -1.0   # < 0: not sweeping
var _was_running := false

## 0..1 redline tremble amount for a (displayed) rev fraction.
static func shake_amount(frac: float) -> float:
	return clampf((frac - SHAKE_START) / (1.0 - SHAKE_START), 0.0, 1.0)

## Needle offset in degrees: two unrelated sines so it never looks periodic.
static func needle_shake_deg(frac: float, t: float) -> float:
	var a := shake_amount(frac)
	if a <= 0.0:
		return 0.0
	return a * SHAKE_DEG * (0.6 * sin(t * SHAKE_HZ_A * TAU) + 0.4 * sin(t * SHAKE_HZ_B * TAU + 1.3))

## 0..1 how strongly the idle vibration shows: engine running, revs near idle, car nearly still.
static func idle_amount(engine_running: bool, motor_rpm: float, idle_rpm: float, speed: float) -> float:
	if not engine_running or idle_rpm <= 0.0:
		return 0.0
	var rpm_k := 1.0 - clampf((motor_rpm - idle_rpm) / (idle_rpm * IDLE_BAND), 0.0, 1.0)
	var speed_k := 1.0 - clampf(absf(speed) / IDLE_SPEED_FADE, 0.0, 1.0)
	return rpm_k * speed_k

## Idle vibration as {pos: Vector3 metres (car-local), roll: degrees}; zero when amount is 0.
static func idle_shake(amount: float, motor_rpm: float, t: float) -> Dictionary:
	if amount <= 0.0:
		return {"pos": Vector3.ZERO, "roll": 0.0}
	var hz := minf(motor_rpm / 60.0 * 2.0, IDLE_HZ_MAX)
	var s := sin(t * hz * TAU)
	var c := sin(t * hz * 1.37 * TAU + 0.8)
	return {"pos": Vector3(0.5 * c, s, 0.0) * IDLE_SHAKE_M * amount, "roll": c * IDLE_SHAKE_DEG * amount}

## Needle fraction (0..1) of the start-up sweep at time t seconds in.
static func sweep_curve(t: float) -> float:
	if t < 0.0 or t >= SWEEP_TOTAL:
		return 0.0
	if t < SWEEP_UP:
		var u := t / SWEEP_UP
		return 1.0 - (1.0 - u) * (1.0 - u)
	if t < SWEEP_UP + SWEEP_HOLD:
		return 1.0
	var d := (t - SWEEP_UP - SWEEP_HOLD) / SWEEP_DOWN
	return 1.0 - d * d * (3.0 - 2.0 * d)

## Per frame: watch the engine start (not running -> running; the first frame
## counts, so the sweep also plays on spawn) and advance the sweep clock.
## Returns true on the frame the engine catches.
func update(engine_running: bool, delta: float) -> bool:
	var started := engine_running and not _was_running
	_was_running = engine_running
	if started:
		sweep_t = 0.0
	elif sweep_t >= 0.0:
		sweep_t += delta
		if sweep_t >= SWEEP_TOTAL:
			sweep_t = -1.0
	return started

## Displayed needle fraction: the real one, or the sweep if that is higher
## (so a start at speed never drags a needle below the truth).
func needle(real_frac: float) -> float:
	if sweep_t < 0.0 or not FxSettings.is_on("startup_sweep"):
		return real_frac
	return maxf(real_frac, sweep_curve(sweep_t))
