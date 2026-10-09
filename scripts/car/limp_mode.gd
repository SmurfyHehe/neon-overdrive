class_name LimpMode
extends RefCounted

# Limp mode (Stage C, 2026-10-09). One rule for every cause, Roy's decision:
# the SLOWEST cause wins. An overheated engine, a damaged engine and an empty
# tank each have their own speed cap; they never stack (no multiplying caps or
# torque cuts), the car simply runs at the lowest active cap.
#
# The cap is a governor on the throttle, not a brake: above the cap the car
# coasts down, inside the last GOV_BAND_KMH below it the throttle fades to zero.
# While limping, engine torque is the worse of the overheat derate and
# LIMP_TORQUE, again the worse one only.
#
# Causes:
# - FUEL: the tank is dry (FuelTank). 60 km/h, decided; game-test later.
# - OVERHEAT: engine at PowertrainHealth.LIMP_C. Below that the existing derate
#   handles it.
# - ENGINE: engine damage; the damage system sets `engine_damage_kmh` (INF = none).

enum Cause { NONE = 0, FUEL = 1, OVERHEAT = 2, ENGINE = 4 }

const FUEL_KMH := 60.0
const OVERHEAT_KMH := 80.0   # placeholder, feel call
const GOV_BAND_KMH := 6.0
const LIMP_TORQUE := 0.5

## Set by the damage system (not built yet). INF = engine healthy.
var engine_damage_kmh := INF
## Read-outs for the HUD and tests, refreshed by update().
var cap_kmh := INF
var cause := Cause.NONE
var active_causes := 0

## Works out the cap from the car's state. Returns the active cap in km/h.
func update(fuel_empty: bool, engine_temp: float) -> float:
	var caps := {}
	if fuel_empty:
		caps[Cause.FUEL] = FUEL_KMH
	if engine_temp >= PowertrainHealth.LIMP_C:
		caps[Cause.OVERHEAT] = OVERHEAT_KMH
	if engine_damage_kmh < INF:
		caps[Cause.ENGINE] = engine_damage_kmh
	active_causes = 0
	cap_kmh = INF
	cause = Cause.NONE
	for c: int in caps:
		active_causes |= c
		if caps[c] < cap_kmh:
			cap_kmh = caps[c]
			cause = c as Cause
	return cap_kmh

func is_limping() -> bool:
	return cause != Cause.NONE

## Throttle multiplier 0..1 for a speed in km/h under the current cap.
func throttle_scale(speed_kmh: float) -> float:
	if cap_kmh == INF:
		return 1.0
	return clampf((cap_kmh - speed_kmh) / GOV_BAND_KMH, 0.0, 1.0)

## Torque multiplier while limping: the worse of the overheat derate and
## LIMP_TORQUE, never their product.
func torque_mult(health_mult: float) -> float:
	return minf(health_mult, LIMP_TORQUE) if is_limping() else health_mult

static func cause_name(c: int) -> String:
	match c:
		Cause.FUEL:
			return "NO FUEL"
		Cause.OVERHEAT:
			return "OVERHEAT"
		Cause.ENGINE:
			return "ENGINE"
	return ""
