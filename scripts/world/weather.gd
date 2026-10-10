extends RefCounted

# Rain (water, Part 2 of the 2026-10-09 "hide unseen parts and water" note).
# One shared weather state for the whole road, held in static vars like
# RoadFrame's, so the player, traffic and (later) cops all read the same rain
# without anything being wired between them.
#
# Everything follows `wetness`, 0 (dry) to 1 (downpour), which eases toward the
# level's target instead of jumping (Roy: changes are gradual):
#   - road grip:      1.0 dry, 0.85 rain, 0.80 downpour  (rain_grip)
#   - puddle depth:   empty when dry, full from steady rain up (puddle_fill)
#   - AI speed:       NPC drivers ease off in the wet     (ai_speed_factor)
# Wheel-level grip (puddles, aquaplaning, the 55% floor and the left/right
# limit) is in scripts/car/wet_grip.gd.
#
# The game rolls tonight's weather at boot and at each new night (game.gd).
# The benchmark and tests stay dry unless NEON_WEATHER pins a level
# (dry / rain / downpour), so earlier runs keep matching.
# No class_name on purpose: preload it, so no class cache refresh is needed.

## DOWNPOUR is the storm (weather_plan.gd). DAMP is the road after rain: wet
## and holding, no rain falling, grip nearly dry, shallow puddles.
enum Level { DRY, RAIN, DOWNPOUR, DAMP }

## Wetness each level settles at. Rain grip falls linearly with wetness, so
## these give exactly 0.85 and 0.80 grip once settled.
const LEVEL_WETNESS := [0.0, 0.75, 1.0, 0.3]
## What the level does to the night's numbers (W1, decided by Roy): fewer cars
## and cops on the road in bad weather, better pay for racing in it. One
## entry per Level, dry = 1.0 so a dry night is exactly as before.
const TRAFFIC_SHARE := [1.0, 0.9, 0.65, 1.0]
const COP_SHARE := [1.0, 0.9, 0.5, 1.0]
const PAY_FACTOR := [1.0, 1.15, 1.35, 1.0]
## Grip lost at full wetness (downpour): 1 - 0.20 = 0.80.
const GRIP_LOSS := 0.20
## Wetness change per second: about 25 s from dry to steady rain. Drying is
## slower than wetting, as a road is.
const WET_RATE := 0.03
const DRY_RATE := 0.015
## Top speed NPC drivers keep at full wetness: 15% under their dry target.
const AI_SLOW := 0.15
## Whether a real run rolls its own weather. Off until rain can be seen (no
## rain, wet-road or puddle visuals yet): invisible grip loss would read as a
## handling bug. Until then NEON_WEATHER=rain or downpour turns it on.
const ROLL_ON := false
## Tonight's odds: dry, rain, downpour.
const ODDS := [0.5, 0.35, 0.15]

static var level := Level.DRY
static var wetness := 0.0
## Bumped whenever wetness changes: a car whose tyres have settled on the
## rain's grip skips all its water work until this moves (wet_grip.gd).
static var version := 0
## Tonight's plan entry (weather_plan.gd); {} when no plan is running (tests,
## benchmark, pinned NEON_WEATHER).
static var tonight := {}

static func set_level(l: int, instant: bool = false) -> void:
	level = clampi(l, Level.DRY, Level.DAMP) as Level
	if instant:
		wetness = LEVEL_WETNESS[level]
		version += 1

static func target_wetness() -> float:
	return LEVEL_WETNESS[level]

## Eases wetness toward the level's target. Called once per physics tick by
## game.gd; cheap enough to call from a test loop too.
static func step(delta: float) -> void:
	var t: float = LEVEL_WETNESS[level]
	if wetness < t:
		wetness = minf(wetness + WET_RATE * delta, t)
		version += 1
	elif wetness > t:
		wetness = maxf(wetness - DRY_RATE * delta, t)
		version += 1

## Road grip from rain alone, for every tyre on the road.
static func rain_grip() -> float:
	return 1.0 - GRIP_LOSS * wetness

## How full the puddles are: 0 dry, 1 from steady rain up.
static func puddle_fill() -> float:
	return clampf(wetness / LEVEL_WETNESS[Level.RAIN], 0.0, 1.0)

## NPC target speed scale: 1 dry, about 0.89 in rain, 0.85 in a downpour.
static func ai_speed_factor() -> float:
	return 1.0 - AI_SLOW * wetness

## Bend speed scale: cornering speed goes with the square root of grip.
static func ai_bend_factor() -> float:
	return sqrt(rain_grip())

## Share of the hour band's traffic left on the road now (1.0 dry).
static func traffic_factor() -> float:
	return TRAFFIC_SHARE[level]

## Share of cops on the road now (1.0 dry). No cops on main yet; the police
## spawner reads this when it lands.
static func cop_factor() -> float:
	return COP_SHARE[level]

## Race pay multiplier now (1.0 dry). The race payout reads this when it lands.
static func pay_factor() -> float:
	return PAY_FACTOR[level]

static func is_dry() -> bool:
	return wetness <= 0.0

## Picks tonight's weather; r in [0, 1).
static func roll(r: float) -> int:
	if r < ODDS[0]:
		return Level.DRY
	if r < ODDS[0] + ODDS[1]:
		return Level.RAIN
	return Level.DOWNPOUR

## NEON_WEATHER as a level, or -1 when unset or unknown.
static func env_level() -> int:
	match OS.get_environment("NEON_WEATHER").to_lower():
		"dry", "0":
			return Level.DRY
		"rain", "1":
			return Level.RAIN
		"downpour", "2":
			return Level.DOWNPOUR
	return -1

static func reset() -> void:
	tonight = {}
	level = Level.DRY
	wetness = 0.0
	version += 1
