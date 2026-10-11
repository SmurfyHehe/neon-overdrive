extends RefCounted

# Damage offsets (brief DP0, 2026-10-11): what damage does to the car, as plain
# numbers the sim reads on top of the tune. CarDamage builds this when damage
# changes (a hit, a kerb strike, a repair); the car applies it each physics
# tick as effective = tuned x mult (or + add). The tuned values are never
# written over, so a repair is "offsets back to neutral" and nothing has to
# guess the base. No class_name: preload it.
#
# Layout, 43 floats: 4 wheels (FL, FR, RL, RR) x 9 fields, then 7 per car.
# Neutral is 1 for a *_MULT, 0 for everything else.

## Per wheel, index = wheel * WHEEL_FIELDS + field.
const TOE_ADD := 0            # rad
const CAMBER_ADD := 1         # rad
const SPRING_MULT := 2
const DAMPER_MULT := 3
const RIDE_DROP := 4          # m
const PRESSURE_MULT := 5
const GRIP_MULT := 6
const RUNOUT := 7             # m
const BRAKE_MULT := 8
const WHEEL_FIELDS := 9
const WHEELS := 4

## Per car, index = CAR_BASE + field.
const CAR_BASE := WHEELS * WHEEL_FIELDS   # 36
const STEER_LOCK_MULT := CAR_BASE + 0
const STEER_CENTRE := CAR_BASE + 1        # rad, visual only
const COOLING_MULT := CAR_BASE + 2
const TORQUE_MULT := CAR_BASE + 3
const BOOST_MULT := CAR_BASE + 4
const DRAG_ADD := CAR_BASE + 5
const DOWNFORCE_REAR_MULT := CAR_BASE + 6
const SIZE := CAR_BASE + 7                # 43

## Which per-wheel fields and per-car indices are multipliers (neutral 1).
const _WHEEL_MULTS := [SPRING_MULT, DAMPER_MULT, PRESSURE_MULT, GRIP_MULT, BRAKE_MULT]
const _CAR_MULTS := [STEER_LOCK_MULT, COOLING_MULT, TORQUE_MULT, BOOST_MULT, DOWNFORCE_REAR_MULT]

var data := PackedFloat32Array()

func _init() -> void:
	data.resize(SIZE)
	neutral()

## Everything back to no effect. Returns self so a rebuild can chain.
func neutral() -> RefCounted:
	data.fill(0.0)
	for w in WHEELS:
		for f in _WHEEL_MULTS:
			data[w * WHEEL_FIELDS + f] = 1.0
	for c in _CAR_MULTS:
		data[c] = 1.0
	return self

func get_wheel(i: int, field: int) -> float:
	return data[i * WHEEL_FIELDS + field]

func set_wheel(i: int, field: int, v: float) -> void:
	data[i * WHEEL_FIELDS + field] = v

## Per-car fields are addressed by their constant: get_car(COOLING_MULT).
func get_car(index: int) -> float:
	return data[index]

func set_car(index: int, v: float) -> void:
	data[index] = v

func is_neutral() -> bool:
	for w in WHEELS:
		for f in WHEEL_FIELDS:
			if data[w * WHEEL_FIELDS + f] != (1.0 if _WHEEL_MULTS.has(f) else 0.0):
				return false
	for c in range(CAR_BASE, SIZE):
		if data[c] != (1.0 if _CAR_MULTS.has(c) else 0.0):
			return false
	return true
