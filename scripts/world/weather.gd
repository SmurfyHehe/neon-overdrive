extends RefCounted

# Rain (water, Part 2 of the 2026-10-09 "hide unseen parts and water" note).
# One shared weather state for the whole road, held in static vars like
# RoadFrame's, so the player, traffic and (later) cops all read the same rain
# without anything being wired between them.
#
# WX0 (2026-10-10) adds the other stages (haze, fog, drizzle, snow, slush) as
# rows of one table, STAGE, and eases every live value toward its row:
# wetness, fog, rain, snow fall, snow cover, and the two scalars derived from
# them (road grip, NPC speed). Nothing draws the new values yet (WX1+);
# `version` bumps whenever one moves so consumers can skip their work while
# everything is still.
#
# Rain still works exactly as before, from `wetness`, 0 (dry) to 1 (downpour):
#   - road grip:      1.0 dry, 0.85 rain, 0.80 downpour  (rain_grip)
#   - puddle depth:   empty when dry, full from steady rain up (puddle_fill)
#   - AI speed:       NPC drivers ease off in the wet     (ai_speed_factor)
# Wheel-level grip (puddles, aquaplaning, the 55% floor and the left/right
# limit) is in scripts/car/wet_grip.gd.
#
# The game rolls tonight's weather at boot and at each new night (game.gd).
# The benchmark and tests stay dry unless NEON_WEATHER pins a stage
# (dry / rain / downpour / damp / haze / fog / drizzle / snow / snow_roads /
# slush), so earlier runs keep matching.
# No class_name on purpose: preload it, so no class cache refresh is needed.

## Stage numbers are SAVED AS INTS (run.json): append only, never reorder.
## DOWNPOUR is the storm (weather_plan.gd). DAMP is the road after rain: wet
## and holding, no rain falling, grip nearly dry, shallow puddles. SNOW covers
## both white-city nights and white-roads nights (see `road_snow`).
enum Level { DRY, RAIN, DOWNPOUR, DAMP, HAZE, FOG, DRIZZLE, SNOW, SLUSH }

## The one table (WX0). Columns:
##   wet         wetness the road settles at (puddles, wet grip)
##   fog         multiplies the base fog_density (0.009)
##   rain        rain intensity 0-1
##   snow_fall   snow falling 0-1
##   snow_cover  snow lying on the world 0-1
##   road_snow   0 wet city, 1 white roads, 0.4 slush edges
##   sky         per_night | broken | hidden | overcast
##   traffic     share of the hour band's cars left on the road
##   npc         top speed NPC drivers keep (share of dry)
##   cop         share of cops on the road
##   sight       how far a cop sees you (share of dry)
##   pay         race pay multiplier (any bad weather: +15%)
##   wipers      off | intermittent | normal | fast
##   grip        road grip for every tyre (tracks, on white roads)
## Rain and storm NPC speed are what the old wetness rule gave (1 - 0.15 w).
const STAGE := {
	Level.DRY: {"wet": 0.0, "fog": 1.0, "rain": 0.0, "snow_fall": 0.0, "snow_cover": 0.0, "road_snow": 0.0,
		"sky": "per_night", "traffic": 1.0, "npc": 1.0, "cop": 1.0, "sight": 1.0, "pay": 1.0, "wipers": "off", "grip": 1.0},
	Level.RAIN: {"wet": 0.75, "fog": 1.5, "rain": 0.7, "snow_fall": 0.0, "snow_cover": 0.0, "road_snow": 0.0,
		"sky": "overcast", "traffic": 0.9, "npc": 0.8875, "cop": 0.9, "sight": 0.85, "pay": 1.15, "wipers": "normal", "grip": 0.85},
	Level.DOWNPOUR: {"wet": 1.0, "fog": 2.4, "rain": 1.0, "snow_fall": 0.0, "snow_cover": 0.0, "road_snow": 0.0,
		"sky": "overcast", "traffic": 0.65, "npc": 0.85, "cop": 0.5, "sight": 0.6, "pay": 1.15, "wipers": "fast", "grip": 0.8},
	Level.DAMP: {"wet": 0.3, "fog": 1.2, "rain": 0.0, "snow_fall": 0.0, "snow_cover": 0.0, "road_snow": 0.0,
		"sky": "broken", "traffic": 1.0, "npc": 0.95, "cop": 1.0, "sight": 1.0, "pay": 1.0, "wipers": "off", "grip": 0.94},
	Level.HAZE: {"wet": 0.0, "fog": 1.8, "rain": 0.0, "snow_fall": 0.0, "snow_cover": 0.0, "road_snow": 0.0,
		"sky": "broken", "traffic": 1.0, "npc": 1.0, "cop": 1.0, "sight": 0.9, "pay": 1.0, "wipers": "off", "grip": 1.0},
	Level.FOG: {"wet": 0.15, "fog": 4.0, "rain": 0.0, "snow_fall": 0.0, "snow_cover": 0.0, "road_snow": 0.0,
		"sky": "hidden", "traffic": 0.9, "npc": 0.9, "cop": 0.75, "sight": 0.5, "pay": 1.15, "wipers": "intermittent", "grip": 0.97},
	Level.DRIZZLE: {"wet": 0.4, "fog": 1.3, "rain": 0.25, "snow_fall": 0.0, "snow_cover": 0.0, "road_snow": 0.0,
		"sky": "overcast", "traffic": 1.0, "npc": 0.95, "cop": 1.0, "sight": 0.9, "pay": 1.0, "wipers": "intermittent", "grip": 0.92},
	Level.SNOW: {"wet": 0.75, "fog": 2.0, "rain": 0.0, "snow_fall": 0.6, "snow_cover": 1.0, "road_snow": 0.0,
		"sky": "overcast", "traffic": 0.8, "npc": 0.85, "cop": 0.8, "sight": 0.75, "pay": 1.15, "wipers": "normal", "grip": 0.85},
	Level.SLUSH: {"wet": 0.6, "fog": 1.4, "rain": 0.0, "snow_fall": 0.1, "snow_cover": 1.0, "road_snow": 0.4,
		"sky": "overcast", "traffic": 0.85, "npc": 0.85, "cop": 0.9, "sight": 0.9, "pay": 1.15, "wipers": "normal", "grip": 0.70},
}
## SNOW on a white-roads night (`road_snow` 1): the ploughs have not been. Its
## own grip, no wetness (puddles stay empty).
const SNOW_ROADS := {"wet": 0.0, "fog": 2.0, "rain": 0.0, "snow_fall": 0.6, "snow_cover": 1.0, "road_snow": 1.0,
	"sky": "overcast", "traffic": 0.75, "npc": 0.75, "cop": 0.8, "sight": 0.75, "pay": 1.15, "wipers": "normal", "grip": 0.75}
## White-roads grip by where on the road (WX3 reads these; tracks are `grip`).
const SNOW_GRIP_FRESH := 0.60
const SNOW_GRIP_SLUSH_EDGE := 0.70
const SNOW_GRIP_BRIDGE := 0.55
## Frost (a modifier, not a stage): nights 20+, clear or haze, after 3 a.m.
const FROST_GRIP := 0.75
const FROST_FLOOR := 0.55

## Grip lost at full wetness (downpour): 1 - 0.20 = 0.80.
const GRIP_LOSS := 0.20
## Easing, per second. Wetness: about 25 s from dry to steady rain; drying is
## slower than wetting, as a road is. Grip and NPC speed follow wetness's rates
## (scaled by what they can lose), so rain behaves exactly as before WX0.
const WET_RATE := 0.03
const DRY_RATE := 0.015
const FOG_RATE := 0.05
const RAIN_RATE := 0.05
const SNOW_FALL_RATE := 0.03
const SNOW_COVER_RATE := 0.004
## Top speed NPC drivers lose at full wetness: 15% under their dry target.
const AI_SLOW := 0.15
## Whether a real run rolls its own weather. Off until rain can be seen (no
## rain, wet-road or puddle visuals yet): invisible grip loss would read as a
## handling bug. Until then NEON_WEATHER=rain or downpour turns it on.
const ROLL_ON := false
## Tonight's odds: dry, rain, downpour.
const ODDS := [0.5, 0.35, 0.15]

static var level := Level.DRY
## The live values. All ease toward the current row (step); set_level(instant)
## and restore() snap them.
static var wetness := 0.0
static var fog := 1.0         # multiplier on the base fog density
static var rain := 0.0
static var snow_fall := 0.0
static var snow_cover := 0.0
static var road_snow := 0.0   # fixed for the night (set with the level)
static var grip := 1.0        # road grip from the stage (rain_grip reads it)
static var npc_speed := 1.0   # NPC top speed share from the stage
## Frost on the road now (a modifier flag, weather_plan.gd decides when).
static var frost := false
## Bumped whenever a live value changes: a car whose tyres have settled on the
## rain's grip skips all its water work until this moves (wet_grip.gd).
static var version := 0
## Tonight's plan entry (weather_plan.gd); {} when no plan is running (tests,
## benchmark, pinned NEON_WEATHER).
static var tonight := {}

## The current stage's row (SNOW on white-roads nights is its own row).
static func row() -> Dictionary:
	if level == Level.SNOW and road_snow >= 1.0:
		return SNOW_ROADS
	return STAGE[level]

## Sets the stage. `snow_roads` only matters for SNOW: true on a white-roads
## night (road_snow 1), false for a white city. `instant` snaps the live
## values to the row instead of easing.
static func set_level(l: int, instant: bool = false, snow_roads: bool = false) -> void:
	level = clampi(l, Level.DRY, Level.SLUSH) as Level
	road_snow = 1.0 if (level == Level.SNOW and snow_roads) else float(STAGE[level].road_snow)
	if instant:
		_snap()
		version += 1

static func _snap() -> void:
	var r := row()
	wetness = r.wet
	fog = r.fog
	rain = r.rain
	snow_fall = r.snow_fall
	snow_cover = r.snow_cover
	grip = r.grip
	npc_speed = r.npc

## Puts the live values back from a save (run.json "weather" block): they snap,
## nothing eases. A missing or non-finite value falls back to the stage's row.
static func restore(d: Dictionary) -> void:
	_snap()
	for k in ["wet", "fog", "rain", "snow_fall", "snow_cover"]:
		var v: Variant = d.get(k)
		if not ((v is float or v is int) and is_finite(float(v))):
			continue
		var f := float(v)
		match k:
			"wet":
				wetness = clampf(f, 0.0, 1.0)
			"fog":
				fog = clampf(f, 0.0, 6.0)
			"rain":
				rain = clampf(f, 0.0, 1.0)
			"snow_fall":
				snow_fall = clampf(f, 0.0, 1.0)
			"snow_cover":
				snow_cover = clampf(f, 0.0, 1.0)
	version += 1

## What a save keeps of the live state (run.json "weather").
static func capture(change_done: bool) -> Dictionary:
	return {"stage": int(level), "road_snow": road_snow, "wet": wetness, "fog": fog, "rain": rain,
		"snow_fall": snow_fall, "snow_cover": snow_cover, "change_done": change_done}

static func set_frost(on: bool) -> void:
	if on != frost:
		frost = on
		version += 1

static func target_wetness() -> float:
	return row().wet

static func _ease(cur: float, to: float, up: float, down: float, delta: float) -> float:
	if cur < to:
		return minf(cur + up * delta, to)
	if cur > to:
		return maxf(cur - down * delta, to)
	return cur

## Eases every live value toward the stage's row. Called once per physics tick
## by game.gd; cheap enough to call from a test loop too (a handful of
## compares; nothing is written while all are settled).
static func step(delta: float) -> void:
	var r := row()
	var moved := false
	var v := _ease(wetness, r.wet, WET_RATE, DRY_RATE, delta)
	if v != wetness:
		wetness = v
		moved = true
	v = _ease(fog, r.fog, FOG_RATE, FOG_RATE, delta)
	if v != fog:
		fog = v
		moved = true
	v = _ease(rain, r.rain, RAIN_RATE, RAIN_RATE, delta)
	if v != rain:
		rain = v
		moved = true
	v = _ease(snow_fall, r.snow_fall, SNOW_FALL_RATE, SNOW_FALL_RATE, delta)
	if v != snow_fall:
		snow_fall = v
		moved = true
	v = _ease(snow_cover, r.snow_cover, SNOW_COVER_RATE, SNOW_COVER_RATE, delta)
	if v != snow_cover:
		snow_cover = v
		moved = true
	# Grip and NPC speed fall at the wetting rate and recover at the drying
	# rate, each scaled by how much it can lose.
	v = _ease(grip, r.grip, GRIP_LOSS * DRY_RATE, GRIP_LOSS * WET_RATE, delta)
	if v != grip:
		grip = v
		moved = true
	v = _ease(npc_speed, r.npc, AI_SLOW * DRY_RATE, AI_SLOW * WET_RATE, delta)
	if v != npc_speed:
		npc_speed = v
		moved = true
	if moved:
		version += 1

## Road grip from the weather, for every tyre on the road: the wetness rule
## (1 - 0.2 w) or the stage's own grip, whichever is lower. Frost is applied
## by the wheel code on top (FROST_GRIP), only on its patches (later).
static func rain_grip() -> float:
	return minf(1.0 - GRIP_LOSS * wetness, grip)

## How full the puddles are: 0 dry, 1 from steady rain up.
static func puddle_fill() -> float:
	return clampf(wetness / float(STAGE[Level.RAIN].wet), 0.0, 1.0)

## NPC target speed scale: 1 dry, about 0.89 in rain, 0.85 in a downpour.
static func ai_speed_factor() -> float:
	return minf(1.0 - AI_SLOW * wetness, npc_speed)

## Bend speed scale: cornering speed goes with the square root of grip.
static func ai_bend_factor() -> float:
	return sqrt(rain_grip())

## Share of the hour band's traffic left on the road now (1.0 dry).
static func traffic_factor() -> float:
	return row().traffic

## Share of cops on the road now (1.0 dry). No cops on main yet; the police
## spawner reads this when it lands.
static func cop_factor() -> float:
	return row().cop

## How far cops see you now, as a share of the dry distance (fog 0.5).
static func cop_sight() -> float:
	return row().sight

## Race pay multiplier now: 1.0 clear, haze, drizzle and after-rain, 1.15 for
## the rest (any bad weather, Roy). The race payout reads this when it lands.
static func pay_factor() -> float:
	return row().pay

## Wiper mode for the stage: off | intermittent | normal | fast.
static func wipers() -> String:
	return row().wipers

## Sky for the stage: per_night | broken | hidden | overcast.
static func sky() -> String:
	return row().sky

static func is_dry() -> bool:
	return wetness <= 0.0

## Picks tonight's weather; r in [0, 1).
static func roll(r: float) -> int:
	if r < ODDS[0]:
		return Level.DRY
	if r < ODDS[0] + ODDS[1]:
		return Level.RAIN
	return Level.DOWNPOUR

## NEON_WEATHER as a stage, or -1 when unset or unknown ("plan" is not a
## stage: it runs the deck).
static func env_level() -> int:
	match OS.get_environment("NEON_WEATHER").to_lower():
		"dry", "clear", "0":
			return Level.DRY
		"rain", "1":
			return Level.RAIN
		"downpour", "storm", "2":
			return Level.DOWNPOUR
		"damp", "3":
			return Level.DAMP
		"haze", "4":
			return Level.HAZE
		"fog", "5":
			return Level.FOG
		"drizzle", "6":
			return Level.DRIZZLE
		"snow", "snow_roads", "7":
			return Level.SNOW
		"slush", "8":
			return Level.SLUSH
	return -1

## True when NEON_WEATHER asks for the white-roads snow night.
static func env_snow_roads() -> bool:
	return OS.get_environment("NEON_WEATHER").to_lower() == "snow_roads"

static func reset() -> void:
	tonight = {}
	level = Level.DRY
	road_snow = 0.0
	frost = false
	_snap()
	version += 1
