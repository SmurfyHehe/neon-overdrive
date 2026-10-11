class_name PoliceRules
extends RefCounted

# The police rulebook (police steps P1 + P2, decided by Roy 2026-10-10). One
# table of numbers and a few pure functions; nothing here touches the scene.
# PoliceHeat applies it, MomentSpots and tests read it. No spikes anywhere.
#
# Areas come from RoadMap (district "area": "city" or "highway").
#
# NEVER an offence: driving at traffic flow, near misses, flashing, the horn,
# lights off, a crash that is not your fault, anything unseen, witness
# call-ins, a bump under BUMP_KMH with traffic, standing still, driving past
# a cop busy with someone else.

const RoadMap := preload("res://scripts/world/road_map.gd")

const CITY := "city"
const HIGHWAY := "highway"

## Posted limit, the offence line (what a cop acts on) and the crackdown-night
## line, km/h. The posted limit is what the signs and the loudspeaker say.
const POSTED_KMH := {"city": 60.0, "highway": 100.0}
const OFFENCE_KMH := {"city": 85.0, "highway": 125.0}
const CRACKDOWN_KMH := {"city": 70.0, "highway": 110.0}
## Flagrant: this far over the posted limit is heat 1 straight away, and +1
## more if held for FLAGRANT_HOLD seconds.
const FLAGRANT_OVER_KMH := 60.0
const FLAGRANT_HOLD := 5.0
## Matching the lane's flow is never an offence, so the speeding line is never
## below the flow of the lane you are in plus this much (city flow is 115 km/h
## in the fast lane, above the 85 line; see PoliceHeat.flow_kmh).
const FLOW_MARGIN_KMH := 10.0

## Seeing (P1 1.2).
const CONE_HALF_ANGLE := 60.0   # degrees either side of straight ahead
const REACH_LOW := 140.0        # low beam
const REACH_HIGH := 200.0       # high beam or a flash
const REACH_DARK := 18.0        # lights off
const REACH_DARK_LIT := 40.0    # lights off under a street lamp or in a lit district
const ALL_ROUND := 12.0         # any direction, offences needing no speed judgement
const MIRROR_RANGE := 45.0      # behind, driving cops only
const MIRROR_FASTER_KMH := 25.0 # ...and only if you are this much faster than the cop
const JUDGE_SECS := 1.0         # speed judgement: seen this long in a row (patrol)
const RADAR_RANGE := 150.0      # the radar car judges at once, in its cone
const LOOK_HZ := 10.0
const MAX_RAYS_PER_TICK := 7    # line-of-sight rays, all cops together
const EYE_HEIGHT := 1.2         # m above the cop's origin, for the line of sight
const TARGET_HEIGHT := 0.8

## Offences. `heat` is what it adds; `warn` = a soft offence at heat 0 gets the
## warning step first; `judged` = needs speed judgement (cone + JUDGE_SECS);
## `add` = +heat on top of what there is (the rest raise it to that level).
enum Offence { SPEEDING, FLAGRANT, WRONG_SIDE, RED_LIGHT, RACING, CRASH, HIT_AND_RUN, TOUCH_COP, RAM_COP, MEDIAN_GAP }
const OFFENCES := {
	Offence.SPEEDING: {"heat": 1, "warn": true, "judged": true},
	Offence.FLAGRANT: {"heat": 1, "warn": true, "judged": true},
	Offence.WRONG_SIDE: {"heat": 1, "warn": true, "judged": false},
	Offence.RED_LIGHT: {"heat": 1, "warn": true, "judged": false},
	Offence.RACING: {"heat": 2, "warn": false, "judged": false},
	Offence.CRASH: {"heat": 1, "warn": false, "judged": false},
	Offence.HIT_AND_RUN: {"heat": 1, "warn": false, "judged": false, "add": true},
	Offence.TOUCH_COP: {"heat": 1, "warn": true, "judged": false},
	Offence.RAM_COP: {"heat": 4, "warn": false, "judged": false},
	Offence.MEDIAN_GAP: {"heat": 1, "warn": false, "judged": false, "add": true},
}
const WRONG_SIDE_SECS := 2.0    # in the oncoming lanes this long
const SPEED_HOLD_SECS := 1.0    # over the line this long
const BUMP_KMH := 15.0          # contact closing speed: a bump below, a crash / ram at or above
const FAULT_LOOKBACK := 1.0     # s: "your centre moved into their lane"
const FLEE_SECS := 10.0         # after a crash: driving off while seen inside this window
const FLEE_KMH := 20.0
const JUNCTION_COP_RANGE := 60.0  # m: a cop "at the junction" is this close to it

## Heat (P1 1.5): +1 per ESCALATE_SECS in sight and still offending, up to 5.
const MAX_HEAT := 5
const ESCALATE_SECS := 45.0
## Seconds unseen before heat drops one level, indexed by the level it is at.
const UNSEEN_DROP_SECS := [0.0, 30.0, 60.0, 90.0, 120.0, 180.0]
const HIDING_FACTOR := 0.5      # a hiding pocket with lights off halves those times

## Warning (P2 1.4).
const WARN_SECS := 5.0
const WARN_COOLDOWN := 120.0
const WARN_LINES := {"city": "Sixty in the city.", "highway": "Hundred out here."}

static func area_name(area: String) -> String:
	return area if POSTED_KMH.has(area) else CITY

static func posted_limit(area: String) -> float:
	return POSTED_KMH[area_name(area)]

static func offence_line(area: String, crackdown: bool) -> float:
	var a := area_name(area)
	return CRACKDOWN_KMH[a] if crackdown else OFFENCE_KMH[a]

## The area at road distance `s` ("city" or "highway"; a road with no map is city).
static func area_at(s: float) -> String:
	return area_name(RoadMap.area_at(s))

## Speeding: over the line, and not just keeping up with the lane's flow
## (`flow_kmh` < 0 = unknown, no exemption).
static func is_speeding(kmh: float, area: String, crackdown: bool, flow_kmh := -1.0) -> bool:
	var line := offence_line(area, crackdown)
	if flow_kmh >= 0.0:
		line = maxf(line, flow_kmh + FLOW_MARGIN_KMH)
	return kmh > line

static func is_flagrant(kmh: float, area: String) -> bool:
	return kmh >= posted_limit(area) + FLAGRANT_OVER_KMH

## How far a cop sees a car by its lamps. `mode`: 0 off, 1 low, 2 high.
static func reach(mode: int, lit_here: bool) -> float:
	if mode >= 2:
		return REACH_HIGH
	if mode == 1:
		return REACH_LOW
	return REACH_DARK_LIT if lit_here else REACH_DARK

## Geometry only (no walls): whether a cop at `cop_xf` (facing its -Z) sees a
## target by cone and reach. `mirrors` = a driving cop whose target is
## MIRROR_FASTER_KMH or more faster than it.
static func in_cone(cop_xf: Transform3D, target: Vector3, reach_m: float, mirrors := false) -> bool:
	var to := target - cop_xf.origin
	var d := to.length()
	if d > reach_m:
		return false
	var fwd := -cop_xf.basis.z
	var cos_a := fwd.dot(to / d)
	if cos_a >= cos(deg_to_rad(CONE_HALF_ANGLE)):
		return true
	return mirrors and cos_a < 0.0 and d <= MIRROR_RANGE

## Within the all-round radius.
static func is_near(cop_pos: Vector3, target: Vector3) -> bool:
	return cop_pos.distance_to(target) <= ALL_ROUND

## Seconds a car must stay unseen before heat drops from `level`.
static func drop_after(level: int, hiding_dark: bool) -> float:
	var s: float = UNSEEN_DROP_SECS[clampi(level, 0, MAX_HEAT)]
	return s * HIDING_FACTOR if hiding_dark else s

## The crash fault test, in road space. `ahead_m` = how far the other car is
## ahead of the player along the player's direction of travel (negative = it
## is behind). Speeds are along that direction. `lane_half` is half a lane.
## At fault: you were behind it and faster, or your centre moved into its lane
## in the lookback window (outside it then, inside now).
static func player_at_fault(ahead_m: float, player_v: float, other_v: float, x_now: float, x_before: float, other_x: float, lane_half: float) -> bool:
	if ahead_m > 0.0 and player_v > other_v:
		return true
	return absf(x_now - other_x) < lane_half and absf(x_before - other_x) >= lane_half
