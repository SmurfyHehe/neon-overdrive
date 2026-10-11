class_name SurfaceFeel
extends RefCounted
## Tyre and surface feel (2026-10-11): what the tyres do on each kind of
## ground, on top of GEVP's own tyre model.
##
## GEVP keeps five per-surface numbers on each wheel (current_cof and friends)
## and only refreshes them when the collider group under the wheel changes.
## This rewrites them every tick, after the vehicle's own step, from the spec's
## value for that group times the row below for the band SurfaceMap finds
## under the wheel. The vendored files are untouched, and so is Wheel.grip_mult
## (PowertrainHealth owns that: tyre heat and wear).
##
## It also adds what GEVP's brush model leaves out on purpose: grip that falls
## away once the tyre is sliding and comes back only after it has stopped. Each
## wheel carries a `slide` state, 0 gripping .. 1 let go. It rises quickly when
## the tyre's slip passes the surface's onset and falls at the surface's
## recovery rate, so a wet road lets go earlier, loses more, and takes longer
## to hook up again than a dry one, and loose grit never bites hard but never
## snaps either.
##
## On dry asphalt with the tyres gripping every factor is exactly 1.0, so a
## car that is not sliding carries the same numbers as before.

# Columns of a row.
enum { PEAK, STIFF, LONG, ASSIST, ROLL, ONSET, DROP, RECOVER, ROUGH, BRAKE }
# PEAK    grip at the limit, x the spec's friction
# STIFF   how sharply grip builds with slip, x the spec's tyre stiffness
#         (lower = vaguer, the limit arrives at a bigger slide angle)
# LONG    traction and braking against cornering grip, x the spec's ratio
# ASSIST  x the spec's lateral grip assist (the keyboard-friendly catch)
# ROLL    rolling drag, x the spec's rolling resistance
# ONSET   slip where the tyre starts to let go (slide angle in rad, or slip
#         ratio x LON_SCALE)
# DROP    share of PEAK left once fully sliding
# RECOVER how fast a tyre that has stopped sliding grips again, 1/s
# ROUGH   rumble through the camera and the surface sound, 0..1
# BRAKE   x the spec's braking_grip_multiplier: GEVP's extra grip for a tyre
#         that is braking hard or locked. It is what stops the car, more than
#         PEAK or LONG: with those alone a soaked road only added 3% to a full
#         stop from 108 km/h.
#
# The shoulder's STIFF is kept near the lane's on purpose: with two wheels on
# each, the stiffer pair out-pushes the softer one (the wheels' toe forces
# stop cancelling) and the car creeps toward the shoulder. At 0.55 it crept
# 0.13 m in the first second hands-off at 108 km/h and was on the kerb in
# three; a tug to steer against is the cue, being dragged in is not.
#
# Rows by SurfaceMap.Kind. PAVEMENT is GEVP's "Dirt" group, whose lower grip
# and stiffness already come from the spec, so its dry row leaves them alone.
const DRY := [
	[1.00, 1.00, 1.00, 1.0, 1.00, 0.16, 0.94, 7.0, 0.00, 1.00],  # asphalt
	[0.94, 1.00, 0.95, 1.0, 1.00, 0.13, 0.90, 6.0, 0.00, 0.90],  # paint
	[0.88, 0.85, 0.88, 0.5, 1.40, 0.18, 0.94, 4.0, 0.35, 0.80],  # grit (shoulder)
	[0.92, 0.90, 0.95, 0.5, 1.20, 0.14, 0.92, 5.0, 1.00, 0.90],  # kerb strip
	[1.00, 1.00, 1.00, 1.0, 1.00, 0.20, 0.92, 4.0, 1.00, 1.00],  # pavement
]
const WET := [
	[0.80, 0.80, 0.78, 0.5, 1.08, 0.11, 0.80, 2.2, 0.00, 0.55],
	[0.62, 0.70, 0.70, 0.0, 1.08, 0.08, 0.75, 2.0, 0.00, 0.40],
	[0.74, 0.75, 0.72, 0.0, 1.60, 0.14, 0.86, 3.0, 0.35, 0.55],
	[0.70, 0.75, 0.75, 0.0, 1.25, 0.10, 0.80, 2.5, 1.00, 0.50],
	[0.86, 0.90, 0.88, 0.5, 1.05, 0.15, 0.84, 2.8, 1.00, 0.70],
]
## How fast a tyre past its onset lets go, 1/s.
const LET_GO := 9.0
## Slip past the onset at which the tyre is fully sliding.
const SPAN := 0.18
## Slip ratio counted against the slide-angle onsets: a ratio of 0.35 is about
## as far gone as 0.16 rad.
const LON_SCALE := 0.45
## Share of DROP a rear tyre takes (the car drives toward -Z, so rear wheels
## sit at +Z). The fronts wash out first, like a road car set up to push: with
## the rears taking the full drop, even 4% of it spun the load-sensitive car in
## tests/car/tyres.gd's rising-speed corner (its "lateral g" read 1.84 from the
## spin, against 1.32 without this layer). At 0.35 it corners at 1.21 and the
## standard car is unchanged at 1.38.
const REAR_DROP := 0.35

## Off = GEVP's own per-group numbers (NEON_SURFACE_FEEL=0, or a test).
static var enabled := OS.get_environment("NEON_SURFACE_FEEL") != "0"

# Per wheel, in wheel_array order. Sound, camera and effects read these.
var kind := PackedInt32Array()
var wet := PackedFloat32Array()
var slide := PackedFloat32Array()
var rough := PackedFloat32Array()
var on_ground := PackedByteArray()

var _was_on := false

## One column for a band at a wetness.
static func value(k: int, column: int, wetness: float) -> float:
	return lerpf(DRY[k][column], WET[k][column], wetness)

## How far gone a tyre is, as one number: slide angle and slip ratio together.
static func slip_of(slip: Vector2) -> float:
	return sqrt(slip.x * slip.x + slip.y * slip.y * LON_SCALE * LON_SCALE)

## The slide state a tick later.
static func next_slide(now: float, slip: float, onset: float, recover: float, delta: float) -> float:
	var want := smoothstep(onset, onset + SPAN, slip)
	return move_toward(now, want, (LET_GO if want > now else recover) * delta)

func _fit(n: int) -> void:
	if kind.size() == n:
		return
	kind.resize(n)
	wet.resize(n)
	slide.resize(n)
	rough.resize(n)
	on_ground.resize(n)
	kind.fill(SurfaceMap.Kind.ASPHALT)
	wet.fill(0.0)
	slide.fill(0.0)
	rough.fill(0.0)
	on_ground.fill(0)

## Call after the vehicle's own _physics_process: the numbers apply from the
## next tick.
func step(v: Vehicle, delta: float) -> void:
	var wheels := v.wheel_array
	_fit(wheels.size())
	if not enabled:
		if _was_on:
			_was_on = false
			for i in wheels.size():
				_write(wheels[i], 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)
				slide[i] = 0.0
				rough[i] = 0.0
				wet[i] = 0.0
				kind[i] = SurfaceMap.Kind.ASPHALT
		return
	_was_on = true
	for i in wheels.size():
		var w: Wheel = wheels[i]
		if not w.is_colliding() or w.last_collider == null:
			# In the air: nothing to grip, and a tyre lands as it left.
			on_ground[i] = 0
			rough[i] = 0.0
			continue
		on_ground[i] = 1
		var k := SurfaceMap.kind_under(w)
		var wt := SurfaceMap.wetness
		if wt > 0.0 or SurfaceMap.wet_source.is_valid():
			wt = SurfaceMap.wet_at(RoadFrame.unroll(w.last_collision_point))
		kind[i] = k
		wet[i] = wt
		var d: Array = DRY[k]
		var e: Array = WET[k]
		rough[i] = lerpf(d[ROUGH], e[ROUGH], wt)
		var sl := next_slide(slide[i], slip_of(w.slip_vector), lerpf(d[ONSET], e[ONSET], wt), lerpf(d[RECOVER], e[RECOVER], wt), delta)
		slide[i] = sl
		_write(w,
			lerpf(d[PEAK], e[PEAK], wt) * lerpf(1.0, lerpf(d[DROP], e[DROP], wt), sl * (REAR_DROP if w.position.z > 0.0 else 1.0)),
			lerpf(d[STIFF], e[STIFF], wt),
			lerpf(d[LONG], e[LONG], wt),
			lerpf(d[ASSIST], e[ASSIST], wt),
			lerpf(d[ROLL], e[ROLL], wt),
			lerpf(d[BRAKE], e[BRAKE], wt))

## Same formulas as Wheel.initialize() and its surface-change branch, times
## the factors.
static func _write(w: Wheel, peak: float, stiff: float, lon: float, assist: float, roll: float, brake: float) -> void:
	var s: String = w.surface_type
	w.current_cof = w.coefficient_of_friction[s] * peak
	w.current_tire_stiffness = 1000000.0 + 8000000.0 * w.tire_stiffnesses[s] * stiff
	w.current_longitudinal_grip_ratio = w.longitudinal_grip_ratio[s] * lon
	w.current_lateral_grip_assist = w.lateral_grip_assist[s] * assist
	w.current_rolling_resistance = w.rolling_resistance[s] * roll
	w.braking_grip_multiplier = w.vehicle.braking_grip_multiplier * brake

## Share of the wheels on the ground that are on band `k`, 0..1.
func share(k: int) -> float:
	var n := 0
	var hit := 0
	for i in kind.size():
		if on_ground[i] == 1:
			n += 1
			if kind[i] == k:
				hit += 1
	return float(hit) / float(n) if n > 0 else 0.0

## Mean roughness under the wheels on the ground, 0..1.
func rough_share() -> float:
	var n := 0
	var sum := 0.0
	for i in rough.size():
		if on_ground[i] == 1:
			n += 1
			sum += rough[i]
	return sum / float(n) if n > 0 else 0.0

## The most let-go tyre, 0..1.
func slide_max() -> float:
	var m := 0.0
	for i in slide.size():
		if on_ground[i] == 1:
			m = maxf(m, slide[i])
	return m

## Whether wheel `i` is on something a sliding tyre leaves rubber and smoke on.
func lays_rubber(i: int) -> bool:
	return i >= kind.size() or kind[i] != SurfaceMap.Kind.GRIT
