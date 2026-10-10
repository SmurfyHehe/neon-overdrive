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
#
# World step 1 (2026-10-10) adds three optional keys, so a new district style
# only lists what differs from DEFAULTS:
# wear: [min, max] facade wear per building (ground grime, rain streaks,
#   stains, a soot line under the roof edge; BuildingKit's shader).
# tops: weights for the roof shape per building (BuildingKit.TOPS: flat,
#   cornice, parapet, gable, hip, setback, crown). A type only takes the
#   shapes that suit it, so a car park stays flat whatever the table says.
# landmark: the one skyline landmark per run (RoofProps.LANDMARKS: tower,
#   water_tower, stacks, screen), on the building landmark_at() names.
const DEFAULTS := {
	"wear": [0.3, 0.7],
	"tops": [["flat", 50], ["cornice", 25], ["gable", 25]],
	"landmark": "",
}
const SPECS := {
	"downtown": {
		"mix": [["office", 35], ["parking", 15], ["apartment", 25], ["shop", 25]],
		"h": {"office": [30.0, 80.0], "apartment": [18.0, 40.0], "parking": [9.0, 18.0]},
		"d": [14.0, 24.0], "w": [10.0, 20.0], "setback": 0.0, "gap": 0.0, "lit": 1.0,
		"low": "shop", "billboard": 1.0,
		"wear": [0.1, 0.45], "tops": [["crown", 35], ["setback", 25], ["cornice", 20], ["flat", 20]],
		"landmark": "tower",
	},
	"residential": {
		"mix": [["apartment", 63], ["shop", 29], ["parking", 4], ["diner", 4]],
		"h": {"apartment": [8.0, 18.0]},
		"d": [9.0, 18.0], "w": [6.0, 12.0], "setback": 1.5, "gap": 0.15, "lit": 1.25,
		"low": "garage", "billboard": 0.5,
		"wear": [0.3, 0.7], "tops": [["gable", 30], ["hip", 20], ["cornice", 25], ["flat", 25]],
		"landmark": "water_tower",
	},
	"strip": {
		"mix": [["shop", 45], ["garage", 25], ["gas", 15], ["diner", 15]],
		"h": {"shop": [3.4, 7.0]},
		"d": [12.0, 22.0], "w": [8.0, 14.0], "setback": 8.0, "gap": 0.2, "lit": 1.0,
		"low": "garage", "billboard": 1.0,
		"wear": [0.4, 0.85], "tops": [["parapet", 40], ["gable", 20], ["hip", 10], ["flat", 30]],
		"landmark": "screen",
	},
	"industrial": {
		"mix": [["warehouse", 75], ["garage", 25]],
		"h": {},
		"d": [16.0, 24.0], "w": [12.0, 24.0], "setback": 3.0, "gap": 0.3, "lit": 0.35,
		"wear": [0.6, 1.0], "tops": [["gable", 45], ["flat", 55]],
		"landmark": "stacks",
		"low": "garage", "billboard": 0.5,
	},
}

static func run_of(chunk_index: int) -> int:
	return floori(float(chunk_index) / float(RUN))

static func name_of_run(run: int) -> String:
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
	if into > 0 and roll < float(into) / float(BLEND + 1):
		return name_of_run(run + 1)
	return name_of_run(run)

static func spec(name: String) -> Dictionary:
	return SPECS[name]

# ---------- landmarks (world step 1) ----------

# Which chunk of a run carries the run's landmark, and which building slot in
# it (RoadChunkBuilder's index: 0 is the first slot on the player's side).
# Chunk 8 of 16 keeps it clear of the blend chunks at the run's end, and it
# is never the city-lights crossing (Junction.CENTRE_S is in chunk 12).
const LANDMARK_CHUNK := 8
const LANDMARK_SLOT := 0

# What building a landmark stands on: its type and height, m. The building is
# the district's biggest footprint and never an empty lot, so the piece on
# top always has something under it.
const LANDMARK_BUILDING := {
	"tower": {"type": "office", "h": 115.0},
	"water_tower": {"type": "apartment", "h": 14.0},
	"stacks": {"type": "warehouse", "h": 9.0},
	"screen": {"type": "shop", "h": 4.0},
}

## The landmark on building `index` of chunk `chunk_index`, or "" (almost
## every building). One per run, on the run's own district (never a blend).
static func landmark_at(chunk_index: int, index: int) -> String:
	if index != LANDMARK_SLOT or posmod(chunk_index, RUN) != LANDMARK_CHUNK:
		return ""
	return String(SPECS[name_at(chunk_index)].get("landmark", ""))

## A copy of a district spec pinned to the landmark's building: one type at
## one height on the district's biggest footprint, no empty-lot roll, and
## `is_landmark` for BuildingKit.dress.
static func landmark_spec(district: Dictionary, landmark: String) -> Dictionary:
	var b: Dictionary = LANDMARK_BUILDING[landmark]
	var s := district.duplicate()
	s["mix"] = [[b.type, 1]]
	s["low"] = b.type
	s["h"] = {b.type: [b.h, b.h]}
	s["w"] = [district.w[1], district.w[1]]
	s["d"] = [district.d[1], district.d[1]]
	s["gap"] = 0.0
	s["is_landmark"] = landmark
	return s

static func setback_at(chunk_index: int) -> float:
	return float(SPECS[name_at(chunk_index)].setback)
