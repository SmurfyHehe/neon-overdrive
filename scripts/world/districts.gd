extends RefCounted

# Districts (buildings step 4, 2026-10-07): the road passes through runs of
# 16 chunks (800 m) that each belong to one district. A district changes
# the building MIX, not the assets: which types appear, how tall they are,
# how big their footprint is, how far they sit back from the sidewalk, how
# often a slot is left as an empty lot, and how many windows are lit.
#
# The map is fixed along the road (a hash of the run index, not the global
# random sequence), so it never disturbs the road layout and a chunk rebuilt
# from the pool matches one built fresh. The first run is always downtown so
# a drive starts among tall buildings. The last 2 chunks of a run blend
# toward the next district, building by building, so changes feel gradual.

#
# On a loop (road_map.gd) the districts are the map's, in its order and at its
# lengths, and come round again every lap; a "run" is then a district's number
# on the loop. Off a loop (the endless road, and chunks built without a game)
# it is the hashed map above.

const RoadMap := preload("res://scripts/world/road_map.gd")

const RUN := 16
const BLEND := 2

# Weights for picking the district of each run after the first.
const PICK := [["downtown", 25], ["residential", 35], ["strip", 25], ["industrial", 15]]

# mix: type weights. h: per-type height range override, m. d / w: footprint
# ranges (frontage along the road / depth), remapped from the same draws as
# before. setback: m from the sidewalk to the building fronts (strip malls
# sit behind a parking lot). gap: chance a slot is an empty lot. lit:
# lit-window multiplier. low: what the old "low shed" roll becomes.
# billboard: multiplier on rooftop billboard chance.
const SPECS := {
	"downtown": {
		"mix": [["office", 35], ["parking", 15], ["apartment", 25], ["shop", 25]],
		"h": {"office": [30.0, 80.0], "apartment": [18.0, 40.0], "parking": [9.0, 18.0]},
		"d": [14.0, 24.0], "w": [10.0, 20.0], "setback": 0.0, "gap": 0.0, "lit": 1.0,
		"low": "shop", "billboard": 1.0,
	},
	"residential": {
		"mix": [["apartment", 63], ["shop", 29], ["parking", 4], ["diner", 4]],
		"h": {"apartment": [8.0, 18.0]},
		"d": [9.0, 18.0], "w": [6.0, 12.0], "setback": 1.5, "gap": 0.15, "lit": 1.25,
		"low": "garage", "billboard": 0.5,
	},
	"strip": {
		"mix": [["shop", 45], ["garage", 25], ["gas", 15], ["diner", 15]],
		"h": {"shop": [3.4, 7.0]},
		"d": [12.0, 22.0], "w": [8.0, 14.0], "setback": 8.0, "gap": 0.2, "lit": 1.0,
		"low": "garage", "billboard": 1.0,
	},
	"industrial": {
		"mix": [["warehouse", 75], ["garage", 25]],
		"h": {},
		"d": [16.0, 24.0], "w": [12.0, 24.0], "setback": 3.0, "gap": 0.3, "lit": 0.35,
		"low": "garage", "billboard": 0.5,
	},
}

static func run_of(chunk_index: int) -> int:
	if RoadMap.is_loop():
		return RoadMap.district_of(chunk_index)
	return floori(float(chunk_index) / float(RUN))

static func name_of_run(run: int) -> String:
	if RoadMap.is_loop():
		return RoadMap.district_kind(run)
	if run == 0:
		return "downtown"
	var total := 0
	for e in PICK:
		total += int(e[1])
	var r := posmod(hash([run, "district"]), total)
	for e in PICK:
		r -= int(e[1])
		if r < 0:
			return String(e[0])
	return String(PICK[0][0])

## The district a chunk belongs to (its run's), for chunk-wide things like
## the setback.
static func name_at(chunk_index: int) -> String:
	return name_of_run(run_of(chunk_index))

## The district one building in this chunk follows: its run's, or, in the
## last BLEND chunks of a run, sometimes the next run's. roll is in [0, 1).
static func name_for_building(chunk_index: int, roll: float) -> String:
	var run := run_of(chunk_index)
	var into := posmod(chunk_index, RUN) - (RUN - BLEND - 1)
	if RoadMap.is_loop():
		into = BLEND - RoadMap.left_in_district(chunk_index)
	if into > 0 and roll < float(into) / float(BLEND + 1):
		return name_of_run(run + 1)
	return name_of_run(run)

static func spec(name: String) -> Dictionary:
	return SPECS[name]

static func setback_at(chunk_index: int) -> float:
	return float(SPECS[name_at(chunk_index)].setback)
