extends RefCounted

# Soft tyres, bent rims and tyres on the rim (briefs LM and DP3, 2026-10-11).
# Everything here reads the damage offsets of one wheel:
#
# - PRESSURE_MULT under 1 (a leak): the tyre is a little less stiff, grips a
#   little less and rolls harder (on top of what the Tuner's pressure does),
#   sits lower (SIDEWALL_SAG of its radius when empty) and drags (SOFT_DRAG):
#   the car leans and pulls to that corner. The numbers are small on purpose.
#   Measured on the coupe at 70 km/h with the wheel straight, the Tuner's own
#   per-bar numbers fed a one-sided 1 bar loss threw the car 3.6 m sideways
#   in 3 s (they were made for both tyres of an axle together), because every
#   car runs toe-in and one weak tyre lets the other one steer.
# - RUNOUT (a bent rim or a flat spot): a once-per-turn force at that wheel,
#   the rim's runout swinging the unsprung mass, so it rises with the square
#   of the speed until the tyre's own give limits it.
# - PRESSURE_MULT at or under RIM_PRESSURE: no air left, the rim meets the
#   road. It does not touch the engine and sets no speed; the car is slower
#   because of what the wheel does:
#
# - grip: CarDamage puts DamageOffsets.GRIP_MULT at CarDamage.RIM_GRIP for
#   that wheel; the car multiplies it into the wheel's grip.
# - rolling drag: a force against the car's motion at that wheel, RIM_DRAG of
#   the load the wheel carries plus a part that grows with the square of the
#   speed (the rim hammering the road), never more than metal can grip
#   (RIM_DRAG_MAX of the load). The car pulls toward that corner, and how
#   fast it can still go depends on the car: its weight and its engine.
# - shake: an up-and-down force at that wheel once per wheel turn that grows
#   with the square of the speed, and a 0..1 number for the camera.
# - rim wear (CarDamage.rim_wear, 0..1) grows with distance x speed and raises
#   the drag and the shake, up to a cap. The wheel never comes off.
#
# Everything reads the offsets, so the Damage setting applies: on Looks only
# the pressure offset is neutral and none of this runs. Nothing is random.
# No class_name: preload it.
#
# TODO: sparks off the rim. There is no spark emitter to hook yet (CrashSfx
# only has the sound).

const DamageOffsets := preload("res://scripts/car/damage_offsets.gd")

## At or under this pressure share the wheel runs on its rim.
const RIM_PRESSURE := 0.1
## Rolling drag as a share of the wheel's load: at a crawl, per (m/s)^2 on
## top, how much more at full wear, and the most it can ever be (a steel rim
## sliding on asphalt grips about this much).
const RIM_DRAG := 0.15
const RIM_DRAG_V2 := 0.0006
const RIM_WEAR_DRAG := 0.5
const RIM_DRAG_MAX := 0.6
## The drag fades in over this speed (m/s), so a parked car is not pushed.
const DRAG_FADE_MS := 1.5
## Shake force (N) per (m/s)^2, how much more at full wear, and its cap as a
## share of the wheel's load (the wheel is never thrown off the road by it).
const RIM_SHAKE_N := 0.9
const RIM_WEAR_SHAKE := 1.0
const RIM_SHAKE_MAX := 0.3
## The camera's shake is full at this speed with one wheel on a worn rim.
const SHAKE_FULL_MS := 35.0
## Rim wear per (m/s)^2 second, i.e. per metre x speed: 2 km at 72 km/h wears
## it out.
const RIM_WEAR_K := 2.5e-5

## A soft tyre, each as the share at no pressure at all (they grow in a
## straight line from nothing at full pressure): drag as a share of the
## wheel's load, the radius the wheel loses, the stiffness and grip it loses
## and the rolling resistance it gains.
const SOFT_DRAG := 0.03
const SIDEWALL_SAG := 0.02
const SOFT_STIFFNESS_LOSS := 0.03
const SOFT_GRIP_LOSS := 0.03
const SOFT_ROLL_GAIN := 0.3
## Runout wobble: the unsprung mass the rim swings (kg) and the tyre's radial
## stiffness (N/m) that limits the force once the wheel turns fast enough.
const WOBBLE_MASS := 25.0
const WOBBLE_STIFFNESS := 2.5e5
## The camera's shake is full at this wobble force (N).
const WOBBLE_SHAKE_N := 1500.0

## Drag share of the load for a tyre at pressure share p, not yet on its rim.
static func soft_drag_share(p: float) -> float:
	return SOFT_DRAG * clampf((1.0 - p) / (1.0 - RIM_PRESSURE), 0.0, 1.0)

## The wheel radius left at pressure share p.
static func radius_mult(p: float) -> float:
	return 1.0 - SIDEWALL_SAG * clampf(1.0 - p, 0.0, 1.0)

## Peak of the once-per-turn force (N) of a rim `runout` m out of round on a
## wheel turning at `spin` rad/s.
static func wobble_force(runout: float, spin: float) -> float:
	return maxf(runout, 0.0) * minf(WOBBLE_MASS * spin * spin, WOBBLE_STIFFNESS)

## Writes what a pressure share does to one wheel's tyre: stiffness, grip,
## rolling resistance and radius. The Tuner's pressure (tuned_bar against
## stock_bar, the tyre model's own numbers) stays underneath, so full
## pressure gives back exactly what the Tuner set. On the rim the grip and
## the drag are the rim's own (GRIP_MULT and drag_force), so those two only
## carry the Tuner's part.
static func write_pressure(w: Wheel, p: float, tuned_bar: float, stock_bar: float, tuned_radius: float) -> void:
	var dp := tuned_bar - stock_bar
	var lost := clampf(1.0 - p, 0.0, 1.0)
	var rim := p <= RIM_PRESSURE
	w.pressure_stiffness_mult = (1.0 + Wheel.PRESSURE_STIFFNESS_PER_BAR * dp) * (1.0 - SOFT_STIFFNESS_LOSS * lost)
	w.pressure_grip_mult = (1.0 - Wheel.PRESSURE_GRIP_LOSS_PER_BAR * maxf(absf(dp) - Wheel.PRESSURE_IDEAL_WINDOW, 0.0)) * (1.0 if rim else 1.0 - SOFT_GRIP_LOSS * lost)
	w.pressure_roll_mult = (1.0 - Wheel.PRESSURE_ROLL_PER_BAR * dp) * (1.0 if rim else 1.0 + SOFT_ROLL_GAIN * lost)
	w.tire_radius = tuned_radius * radius_mult(p)

## True if wheel i of these offsets is on its rim.
static func on_rim(offsets: DamageOffsets, i: int) -> bool:
	return offsets.get_wheel(i, DamageOffsets.PRESSURE_MULT) <= RIM_PRESSURE

## Drag force (N) for a wheel on its rim carrying `load` N at `speed` m/s.
static func drag_force(load: float, speed: float, wear: float) -> float:
	var share := minf((RIM_DRAG + RIM_DRAG_V2 * speed * speed) * (1.0 + RIM_WEAR_DRAG * clampf(wear, 0.0, 1.0)), RIM_DRAG_MAX)
	return share * maxf(load, 0.0) * clampf(speed / DRAG_FADE_MS, 0.0, 1.0)

## Peak of the once-per-turn shake force (N).
static func shake_force(load: float, speed: float, wear: float) -> float:
	return minf(RIM_SHAKE_N * (1.0 + RIM_WEAR_SHAKE * clampf(wear, 0.0, 1.0)) * speed * speed, RIM_SHAKE_MAX * maxf(load, 0.0))

## Rim wear gained in dt at `speed` m/s.
static func wear_step(speed: float, dt: float) -> float:
	return RIM_WEAR_K * speed * speed * dt

## One physics tick on the car: drag for every soft tyre, drag and shake for
## every wheel on its rim, the wobble of every rim that is out of round.
## `phase` holds each wheel's turn angle (rad) and is advanced here.
## Returns the camera shake, 0..1.
static func apply(v: Vehicle, offsets: DamageOffsets, rim_wear: Array[float], phase: PackedFloat32Array, dt: float) -> float:
	var shake := 0.0
	var vel := v.linear_velocity
	var up := v.global_transform.basis.y
	var flat_vel := vel - up * vel.dot(up)
	var speed := flat_vel.length()
	for i in mini(4, v.wheel_array.size()):
		var p := offsets.get_wheel(i, DamageOffsets.PRESSURE_MULT)
		var runout := offsets.get_wheel(i, DamageOffsets.RUNOUT)
		var rim := p <= RIM_PRESSURE
		if p >= 1.0 and runout <= 0.0:
			phase[i] = 0.0
			continue
		var w: Wheel = v.wheel_array[i]
		phase[i] = fposmod(phase[i] + absf(w.spin) * dt, TAU)
		if not w.is_colliding():
			continue
		var at := w.global_position - v.global_position
		var load := w.spring_force
		var drag := drag_force(load, speed, rim_wear[i]) if rim else soft_drag_share(p) * maxf(load, 0.0) * clampf(speed / DRAG_FADE_MS, 0.0, 1.0)
		if speed > 0.01 and drag > 0.0:
			v.apply_force(-flat_vel / speed * drag, at)
		var peak := wobble_force(runout, w.spin)
		shake = maxf(shake, clampf(peak / WOBBLE_SHAKE_N, 0.0, 1.0))
		if rim:
			peak += shake_force(load, speed, rim_wear[i])
			shake = maxf(shake, clampf(speed / SHAKE_FULL_MS, 0.0, 1.0) * clampf(speed / SHAKE_FULL_MS, 0.0, 1.0) * (0.5 + 0.5 * rim_wear[i]))
		# never more than the wheel carries: the wobble shakes the car, it does not throw it
		v.apply_force(up * minf(peak, 0.6 * maxf(load, 0.0)) * sin(phase[i]), at)
	return minf(shake, 1.0)
