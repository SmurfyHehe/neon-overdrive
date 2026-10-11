extends RefCounted

# The totalled meter (TM1, Roy 2026-10-11): big crashes fill a meter instead of
# ending the run; at 100% the car is totalled and the night ends. Pure numbers,
# no nodes, so a test can check every rule without booting the game.
#
# The number itself lives in CarDamage.totalled (0.0..1.0, saved with the car).
# This file is the rules that move it:
#
# - a hit's step comes from its wall speed (WreckRules.wall_speed): under 55
#   km/h nothing, 55 up to 100 adds 0.30, 100 and up adds 0.60. The same hit
#   always adds the same step: no randomness.
# - one hit never adds more than MAX_STEP.
# - a second contact with the same object within SAME_HIT_SECS of a counted
#   hit is the same hit (a car scraping along a wall): it does not add again.
# - a roll adds its own step per vehicle kind (step_for_roll). TM2 calls it.
# - the stage of the meter (0..4) is for the damage looks and the station
#   patch's button (TM3, DP4b); 4 is totalled.
# - a difficulty factor multiplies every step. Roy has not decided per
#   difficulty values (QA will tune them): all three are 1.0.
# - "Damage: Looks only" turns the meter off: nothing is added and the car can
#   never be totalled (Roy 1437). "Full" and "Light" both count it in full.
#
# No class_name on purpose: preload it, so no class cache refresh is needed.

const WreckRules := preload("res://scripts/car/wreck_rules.gd")

const HIT_STEP := 0.30     # 55 <= wall < 100 km/h
const BIG_HIT_STEP := 0.60 # wall >= 100 km/h
const MAX_STEP := 0.60     # one hit never adds more
const SAME_HIT_SECS := 0.5

## Where each stage starts: stage 1 at 0.30, 2 at 0.60, 3 at 0.90, 4 (totalled)
## at 1.0. Under the first entry the car is stage 0.
const STAGE_AT := [0.30, 0.60, 0.90, 1.0]

## What a roll adds, by vehicle kind.
const ROLL_STEP := {
	"car": 0.25,
	"m1_monster": 0.20,
	"l1_lowrider": 0.50,
	# Not built yet (decided by Roy, numbers kept here for when they are):
	# "bike": 0.50,   # a spill
	# "trike": 0.50,  # a roll
}

## TODO(DP4a+DP7): read the per-difficulty values from
## scripts/car/damage_difficulty.gd once it exists. Roy has not set them.
const DIFFICULTY_MULT := {"daily": 1.0, "weekend": 1.0, "racer": 1.0}

## The same hit seen twice inside the window counts once.
var _last_key := -1
var _last_at := -INF

## The step a hit of this wall speed (km/h) adds, before difficulty and
## before the same-object rule. `kind` is the vehicle kind; every kind takes
## the same hit steps for now (bikes get their own with the bike).
static func step_for_hit(wall_kmh: float, _kind: String = "car") -> float:
	if wall_kmh >= WreckRules.BIG_HIT_KMH:
		return BIG_HIT_STEP
	if wall_kmh >= WreckRules.WRECK_KMH:
		return HIT_STEP
	return 0.0

## The step a roll adds for this vehicle kind (the car's, for an unknown kind).
static func step_for_roll(kind: String) -> float:
	return float(ROLL_STEP.get(kind, ROLL_STEP["car"]))

## 0 (under 0.30) up to 4 (totalled, at 1.0).
static func stage(meter: float) -> int:
	var s := 0
	for at: float in STAGE_AT:
		if meter >= at - 0.0001:
			s += 1
	return s

static func is_totalled(meter: float) -> bool:
	return meter >= 1.0 - 0.0001

## The factor on every step for the current difficulty.
## TODO(DP4a+DP7): ask the difficulty setting once it is on the base.
static func difficulty_mult() -> float:
	return float(DIFFICULTY_MULT.get(_difficulty(), 1.0))

## False when "Damage: Looks only" is on: the meter never moves.
## TODO(DP4a+DP7): read the Damage setting ("Full" / "Light" / "Looks only")
## once it exists; until then every run counts the meter in full.
static func counts() -> bool:
	return _damage_setting() != "Looks only"

static func _difficulty() -> String:
	return "daily"  # TODO(DP4a+DP7)

static func _damage_setting() -> String:
	return "Full"  # TODO(DP4a+DP7)

## A step as the game applies it: through the difficulty factor, capped at one
## hit's worth.
static func scaled(step: float) -> float:
	if step <= 0.0 or not counts():
		return 0.0
	return minf(step * difficulty_mult(), MAX_STEP)

## The meter after a hit of `wall_kmh` on object `key` (an instance id, 0 for
## "no object") at time `now` (seconds). Remembers the hit so the same object
## within SAME_HIT_SECS adds nothing.
func after_hit(meter: float, wall_kmh: float, key: int, now: float, kind: String = "car") -> float:
	var step := scaled(step_for_hit(wall_kmh, kind))
	if step <= 0.0:
		return meter
	if key == _last_key and now - _last_at < SAME_HIT_SECS:
		return meter
	_last_key = key
	_last_at = now
	return add(meter, step)

## The meter plus a step, kept inside 0..1.
static func add(meter: float, step: float) -> float:
	return clampf(meter + step, 0.0, 1.0)
