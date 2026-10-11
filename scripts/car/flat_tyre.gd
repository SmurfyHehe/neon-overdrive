extends RefCounted

# A tyre on its rim (brief LM, 2026-10-11). A wheel whose pressure offset
# (DamageOffsets.PRESSURE_MULT) is at or under RIM_PRESSURE has no air left:
# the rim meets the road. It does not touch the engine and sets no speed; the
# car is slower because of what the wheel does:
#
# - grip: CarDamage puts DamageOffsets.GRIP_MULT at CarDamage.RIM_GRIP for
#   that wheel; the car multiplies it into the wheel's grip.
# - rolling drag: a force against the car's motion at that wheel, RIM_DRAG of
#   the load the wheel carries, so the car pulls toward that corner.
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
## Rolling drag as a share of the wheel's load, and how much more at full wear.
const RIM_DRAG := 0.15
const RIM_WEAR_DRAG := 0.6
## The drag fades in over this speed (m/s), so a parked car is not pushed.
const DRAG_FADE_MS := 1.5
## Shake force (N) per (m/s)^2, how much more at full wear, and its cap as a
## share of the wheel's load (the wheel is never thrown off the road by it).
const RIM_SHAKE_N := 0.9
const RIM_WEAR_SHAKE := 1.0
const RIM_SHAKE_MAX := 0.45
## The camera's shake is full at this speed with one wheel on a worn rim.
const SHAKE_FULL_MS := 35.0
## Rim wear per (m/s)^2 second, i.e. per metre x speed: 2 km at 72 km/h wears
## it out.
const RIM_WEAR_K := 2.5e-5

## True if wheel i of these offsets is on its rim.
static func on_rim(offsets: DamageOffsets, i: int) -> bool:
	return offsets.get_wheel(i, DamageOffsets.PRESSURE_MULT) <= RIM_PRESSURE

## Drag force (N) for a wheel on its rim carrying `load` N at `speed` m/s.
static func drag_force(load: float, speed: float, wear: float) -> float:
	return RIM_DRAG * (1.0 + RIM_WEAR_DRAG * clampf(wear, 0.0, 1.0)) * maxf(load, 0.0) * clampf(speed / DRAG_FADE_MS, 0.0, 1.0)

## Peak of the once-per-turn shake force (N).
static func shake_force(load: float, speed: float, wear: float) -> float:
	return minf(RIM_SHAKE_N * (1.0 + RIM_WEAR_SHAKE * clampf(wear, 0.0, 1.0)) * speed * speed, RIM_SHAKE_MAX * maxf(load, 0.0))

## Rim wear gained in dt at `speed` m/s.
static func wear_step(speed: float, dt: float) -> float:
	return RIM_WEAR_K * speed * speed * dt

## One physics tick on the car: applies drag and shake for every wheel on its
## rim. `phase` holds each wheel's turn angle (rad) and is advanced here.
## Returns the camera shake, 0..1.
static func apply(v: Vehicle, offsets: DamageOffsets, rim_wear: Array[float], phase: PackedFloat32Array, dt: float) -> float:
	var shake := 0.0
	var vel := v.linear_velocity
	var up := v.global_transform.basis.y
	var flat_vel := vel - up * vel.dot(up)
	var speed := flat_vel.length()
	for i in mini(4, v.wheel_array.size()):
		if not on_rim(offsets, i):
			phase[i] = 0.0
			continue
		var w: Wheel = v.wheel_array[i]
		phase[i] = fposmod(phase[i] + absf(w.spin) * dt, TAU)
		if not w.is_colliding():
			continue
		var at := w.global_position - v.global_position
		var load := w.spring_force
		if speed > 0.01:
			v.apply_force(-flat_vel / speed * drag_force(load, speed, rim_wear[i]), at)
		var peak := shake_force(load, speed, rim_wear[i])
		v.apply_force(up * peak * sin(phase[i]), at)
		shake = maxf(shake, clampf(speed / SHAKE_FULL_MS, 0.0, 1.0) * clampf(speed / SHAKE_FULL_MS, 0.0, 1.0) * (0.5 + 0.5 * rim_wear[i]))
	return minf(shake, 1.0)
