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

static func setback_at(chunk_index: int) -> float:
	return float(SPECS[name_at(chunk_index)].setback)

# Cross-section table (pavements steps 1-2 and 5, 2026-10-10). One row per
# district says how the road's edge is laid out from the lane edge outward:
#   shoulder: paved strip from the lane to the gutter, m (a parking lane in
#     the districts where cars park at the kerb: downtown, residential);
#   walk:     pavement width, m;
#   kerb_h:   kerb height, m (the pavement sits at this height; the drawn
#     face rises from the gutter to it);
#   kerb:     false = no raised kerb (a freeway: shoulder, then a flat verge);
#   drops:    the building types whose frontage gets a dropped kerb (a
#     car-park entrance); "*" = every building (strip malls all sit behind
#     a lot).
# The road builder tapers every value between chunks like the lanes, and
# buildings, boundary walls, lamps, pylons and the roadside kit all lay
# themselves out from the edges it produces. Read it through cross_at /
# walk_at / shoulder_at / kerb_h_at, not by indexing CROSS.
#
# Picks (Roy answered "widths by area table" yes, the numbers are mine):
# pavements are widest downtown and thinnest in the industrial yards; kerb
# height follows (a 6 in kerb downtown, 4 in on the strip); parking lanes
# only where the buildings front the street.
const CROSS := {
	"downtown": {"walk": 3.6, "shoulder": 2.4, "kerb_h": 0.15, "kerb": true, "drops": ["parking"]},
	"residential": {"walk": 2.4, "shoulder": 2.2, "kerb_h": 0.13, "kerb": true, "drops": ["parking", "garage"]},
	"strip": {"walk": 2.0, "shoulder": 1.4, "kerb_h": 0.10, "kerb": true, "drops": ["*"]},
	"industrial": {"walk": 1.5, "shoulder": 1.4, "kerb_h": 0.10, "kerb": true, "drops": ["warehouse", "garage", "parking"]},
}
## A freeway stretch (the layout's "outskirts"): no raised kerb, a wide hard
## shoulder, and a flat verge instead of a pavement (K5).
const FREEWAY := {"walk": 1.2, "shoulder": 3.0, "kerb_h": 0.0, "kerb": false, "drops": []}
## The geometry at a crossing: Junction draws its own quads at these widths,
## so a chunk that touches one is laid out with exactly this section (the
## district's kerb and drops carry on).
const JUNCTION := {"walk": 2.2, "shoulder": 1.4, "kerb_h": 0.1}

## The section at the END of chunk `chunk_index` (the road builder tapers
## from cross_at(i - 1) to cross_at(i) across chunk i). Keyed by the same
## fixed-map districts as everything else here, so a recycled chunk matches
## a fresh one. A chunk whose neighbour touches a crossing is held at the
## crossing's section too, so the chunk that touches it starts and ends there.
static func cross_at(chunk_index: int) -> Dictionary:
	if Junction.touches(chunk_index) or Junction.touches(chunk_index + 1):
		var d: Dictionary = CROSS[name_at(chunk_index)].duplicate()
		d.merge(JUNCTION, true)  # the crossing's geometry, the district's drops
		return d
	if is_freeway(chunk_index):
		return FREEWAY
	return CROSS[name_at(chunk_index)]

## Whether the chunk is on a freeway stretch: RoadLayout's "outskirts"
## (fixed map seed, so the same stretches every run). No layout, no freeway.
static func is_freeway(chunk_index: int) -> bool:
	var lay: RoadLayout = RoadFrame.layout
	if lay == null:
		return false
	return lay.district_at((float(chunk_index) + 0.5) * RoadChunkBuilder.CHUNK_LEN) == "outskirts"

static func walk_at(chunk_index: int) -> float:
	return float(cross_at(chunk_index).walk)

static func shoulder_at(chunk_index: int) -> float:
	return float(cross_at(chunk_index).shoulder)

static func kerb_h_at(chunk_index: int) -> float:
	return float(cross_at(chunk_index).kerb_h)

static func drops_for(name: String) -> Array:
	return CROSS[name].drops
