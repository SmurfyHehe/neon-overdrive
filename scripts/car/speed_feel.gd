extends RefCounted
class_name SpeedFeel

# Per-car speed feel (2026-10-10). Three things every car works out from its own
# data instead of sharing the coupe's:
#
# - top speed: where the engine's power in top gear meets air drag and rolling
#   resistance, or the rev cut if that comes first. From the spec as it stands
#   (torque, redline, gears, final drive, drag, frontal area, mass) and the
#   car's own wheel radius, so a tune or a mod moves it;
# - the speedometer's range: the first dial in DIALS that leaves about 10%
#   above that top speed. A mod that pushes the car past its dial gets the next
#   one up;
# - rattle: how much the car shakes and knocks as it nears its own top speed. A
#   beater flat out at 150 km/h is busier than the coupe cruising at 150.
#
# Read-only: nothing here touches the car or the spec.

const KMH_PER_MS := 3.6
## The effects (camera FOV, shake, vignette, streaks, wind) all keep growing up
## to here: 400 km/h, the fastest any car in the game is meant to go.
const EFFECTS_FULL := 111.1  # m/s

## Speedometer faces, km/h. One tick mark every DIAL_TICK.
const DIALS := [160.0, 200.0, 240.0, 280.0, 320.0, 360.0, 400.0, 440.0]
const DIAL_TICK := 40.0
const DIAL_HEADROOM := 1.10  # the dial ends at least this far past top speed

## How loose each car is, 0 (tight) to 1 (everything buzzes). Starting values
## for Roy to judge by driving.
const RATTLE := {
	"p0_beater": 1.0,
	"p4_kei": 0.9,
	"p2_hothatch": 0.7,
	"p5_muscle": 0.6,
	"p3_tuner": 0.45,
	"p6_crossover": 0.4,
	"p1_coupe": 0.35,
}
const RATTLE_DEFAULT := 0.5
const RATTLE_FROM := 0.55  # share of the car's top speed where it starts
const RATTLE_FULL := 1.05  # and where it is all there

const RECHECK_MS := 1000  # how often a car's spec is looked at for changes

static var _calib := 0.0
static var _cache := {}  # car instance id -> {sig, top, dial, next}

## Top speed in km/h for a spec on wheels of this radius. Same physics and the
## same calibration as the Tuner's stat panel (TunerModel.estimate), which
## assumes the coupe's wheels.
static func top_kmh(spec: Dictionary, wheel_r: float) -> float:
	if _calib <= 0.0:
		_calib = TunerModel.COUPE_MEASURED.top / _raw_top(CarSpec.coupe_default(), PlayerCar.CFG.wheel_r)
	return _raw_top(spec, wheel_r) * _calib

static func _raw_top(s: Dictionary, wheel_r: float) -> float:
	var shape: Dictionary = s.torque_shape
	var curve := CarSpec.build_torque_curve(shape.low_end, shape.peak_pos, shape.plateau, shape.falloff)
	var max_rpm: float = s.max_rpm
	var peak := float(s.max_torque) * (1.0 + float(s.get("turbo_gain", 0.45)) * float(s.get("turbo_boost_max", 0.0)) * 0.6)
	var gears: Array = s.gear_ratios
	var ratio: float = float(gears[gears.size() - 1]) * float(s.final_drive)
	var mass: float = s.vehicle_mass
	var area: float = s.frontal_area
	var drag_k := 0.5 * 1.2 * float(s.coefficient_of_drag) * area
	var down_k := (float(s.aero_downforce_coefficient_front) + float(s.aero_downforce_coefficient_rear)) * 0.5 * 1.2 * area
	var cut_kmh := max_rpm * 1.1 / ratio * TAU / 60.0 * wheel_r * KMH_PER_MS
	var kmh := 20.0
	while kmh < cut_kmh:
		var v := kmh / KMH_PER_MS
		var rpm := v / wheel_r * ratio * 60.0 / TAU
		var torque := curve.sample_baked(clampf(rpm / max_rpm, 0.0, 1.0)) * peak
		# GEVP's rolling resistance grows with speed and with load
		# (gevp_wheel.gd process_rolling_resistance).
		var c_rr := 0.005 + 0.5 * (0.01 + 0.0095 * pow(v * 0.036, 2.0))
		if TunerModel.TOP_POWER_SHARE * torque * ratio / wheel_r < drag_k * v * v + c_rr * (mass * 9.81 + down_k * v * v):
			return kmh
		kmh += 1.0
	return cut_kmh

## The smallest dial that ends at least DIAL_HEADROOM past this top speed.
static func dial_for(top: float) -> float:
	for d: float in DIALS:
		if d >= top * DIAL_HEADROOM:
			return d
	return DIALS[DIALS.size() - 1]

static func rattle_gain(kind: String) -> float:
	return float(RATTLE.get(kind, RATTLE_DEFAULT))

## 0..gain: how hard this car rattles at this speed (m/s), given its top speed.
static func rattle(kind: String, speed: float, top_ms: float) -> float:
	if top_ms <= 0.0:
		return 0.0
	return rattle_gain(kind) * smoothstep(RATTLE_FROM * top_ms, RATTLE_FULL * top_ms, absf(speed))

## This car's top speed (km/h) from its spec as it is now. Cached; the spec is
## checked for changes about once a second, so a tune shows up without anyone
## having to announce it.
static func car_top_kmh(car: PlayerCar) -> float:
	return float(_entry(car).top)

static func car_dial_kmh(car: PlayerCar) -> float:
	return float(_entry(car).dial)

## How hard the player's car rattles right now, 0..1.
static func car_rattle(car: PlayerCar) -> float:
	return rattle(PlayerCar.chassis_kind(), car.current_speed(), float(_entry(car).top) / KMH_PER_MS)

static func _entry(car: PlayerCar) -> Dictionary:
	var id := car.get_instance_id()
	var now := Time.get_ticks_msec()
	var e: Dictionary = _cache.get(id, {})
	if not e.is_empty() and now < int(e.next):
		return e
	if car.spec.is_empty():
		# not built yet: the coupe's numbers, and look again next time
		return {"sig": 0, "top": TunerModel.COUPE_MEASURED.top, "dial": dial_for(TunerModel.COUPE_MEASURED.top), "next": 0}
	var wheel_r: float = PlayerCar.wheel_config(PlayerCar.chassis_kind()).wheel_r
	var s := car.spec
	var sig := hash([s.max_torque, s.max_rpm, s.torque_shape, s.gear_ratios, s.final_drive, s.vehicle_mass,
		s.coefficient_of_drag, s.frontal_area, s.aero_downforce_coefficient_front, s.aero_downforce_coefficient_rear,
		s.get("turbo_boost_max", 0.0), wheel_r])
	if e.is_empty() or int(e.sig) != sig:
		if _cache.size() > 16:
			_cache.clear()  # cars from earlier scenes; ids are never reused for long
		var top := top_kmh(s, wheel_r)
		e = {"sig": sig, "top": top, "dial": dial_for(top)}
		_cache[id] = e
	e["next"] = now + RECHECK_MS
	return e
