extends RefCounted

# The totalled look, step 1 (Roy 1555, 2026-10-14): a car that is filling its
# totalled meter (scripts/car/totalled_meter.gd) looks more wrecked at every
# stage, with no HUD text. Pure numbers, no nodes, so a test can check every
# rule without booting the game. TyreSmoke draws the puffs and the sparks
# from its one pool (one draw call for the whole car, nothing new is added),
# CarDamage reads the lamp and the rattle from here.
#
# Arcade rule (Roy 2026-10-14): real-life based, but exaggerated and fun. So
# the smoke is thick and the sparks are long, and every stage reads from the
# chase camera at night without looking at a gauge.
#
#   stage 0  (under 30 %)  nothing from here (a hurt radiator steams on its own)
#   stage 1  (30 %)        thin pale steam from the bonnet edges, always; the
#                          loose-trim rattle has a floor
#   stage 2  (60 %)        grey smoke from the bonnet edges, more under
#                          throttle; the head lamp on the side that took the
#                          most front damage goes dark; the rattle louder
#   stage 3  (90 %)        heavy dark smoke off the whole bonnet whatever the
#                          pedal; sparks from under the car over SPARK_KMH
#   stage 4  (totalled)    the same, heavier: the smoke rolls over the bonnet
#                          while the car coasts to its stop (run_end.gd)
#
# Everything is read from the meter each tick, so it holds until the garage
# repair (CarDamage.garage_repair sets the meter back to 0, which is what F6
# and the "Fix the car" row call). The station patch brings a 90 % car back
# to 60 %: the smoke thins to stage 2 and the lamp stays dark. The stage lamp
# is a look, not a broken part: it costs nothing at the garage and is never
# written into CarDamage.lamps.
#
# Cost: one function call per physics tick with a few float ops; puffs ride
# the existing pool. Nothing per frame, nothing allocated, no new node.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const TotalledMeter := preload("res://scripts/car/totalled_meter.gd")

## Smoke puffs per second from the bonnet, by stage, off the throttle and on
## it. Stage 3 and 4 smoke the same whatever the pedal (the engine bay is
## burning oil, not the throttle).
const SMOKE_IDLE := [0.0, 3.0, 5.0, 14.0, 24.0]
const SMOKE_THROTTLE := [0.0, 3.0, 11.0, 14.0, 24.0]
## How dark the smoke is, 0 (pale steam) .. 1 (oil smoke), by stage.
const SMOKE_DARK := [0.0, 0.0, 0.45, 0.85, 1.0]
## Puff life (s) and size at birth (m) by stage: steam is small and short,
## oil smoke big and lingering.
const SMOKE_LIFE := [0.0, 1.3, 1.8, 2.6, 3.0]
const SMOKE_SIZE := [0.0, 0.35, 0.5, 0.7, 0.85]
## Sparks from under the car, from stage 3, over this speed. The rate rises
## with speed from SPARK_KMH to SPARK_FULL_KMH.
const SPARK_STAGE := 3
const SPARK_KMH := 40.0
const SPARK_FULL_KMH := 90.0
const SPARK_RATE := 45.0     # sparks per second at full speed
const SPARK_LIFE := 0.45     # s
const SPARK_SIZE := 0.07     # m across (a bright point from the chase camera)
## The rattle floor by stage (CarDamage.rattle_level takes the larger of its
## own number and this).
const RATTLE_FLOOR := [0.0, 0.35, 0.6, 0.85, 1.0]
## The stage from which one head lamp is dark.
const LAMP_STAGE := 2

## The look stage, 0..4, straight from the meter (TotalledMeter.STAGE_AT).
static func stage(meter: float) -> int:
	return TotalledMeter.stage(meter)

## Bonnet smoke puffs per second at this stage with the pedal at `throttle`
## (0..1). Between the idle and throttle rates by the pedal.
static func smoke_rate(st: int, throttle: float) -> float:
	st = clampi(st, 0, 4)
	return lerpf(SMOKE_IDLE[st], SMOKE_THROTTLE[st], clampf(throttle, 0.0, 1.0))

static func smoke_dark(st: int) -> float:
	return SMOKE_DARK[clampi(st, 0, 4)]

static func smoke_life(st: int) -> float:
	return SMOKE_LIFE[clampi(st, 0, 4)]

static func smoke_size(st: int) -> float:
	return SMOKE_SIZE[clampi(st, 0, 4)]

## Sparks per second from under the car at this stage and speed (km/h):
## none under SPARK_STAGE or under SPARK_KMH, SPARK_RATE from SPARK_FULL_KMH.
static func spark_rate(st: int, kmh: float) -> float:
	if st < SPARK_STAGE or kmh < SPARK_KMH:
		return 0.0
	return SPARK_RATE * smoothstep(SPARK_KMH, SPARK_FULL_KMH, kmh)

static func rattle_floor(st: int) -> float:
	return RATTLE_FLOOR[clampi(st, 0, 4)]

## Which head lamp the stage puts out: 0 the left, 1 the right, -1 none.
## The side that took the most front damage (the steering arms carry the
## front corners' hits; a tie goes to the left). From LAMP_STAGE.
static func dark_lamp(st: int, steer_fl: float, steer_fr: float) -> int:
	if st < LAMP_STAGE:
		return -1
	return 1 if steer_fr > steer_fl else 0
