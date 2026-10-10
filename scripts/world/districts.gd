extends RefCounted

# Districts (buildings step 4, 2026-10-07): the road passes through runs of
# 16 chunks (800 m) that each belong to one district. A district changes
# the building MIX, not the assets: which types appear, how tall they are,
# how big their footprint is, how far they sit back from the sidewalk, how
# often a slot is left as an empty lot, and how many windows are lit.
#
# The map is fixed along the road (a table indexed by the run, not the global
# random sequence), so it never disturbs the road layout and a chunk rebuilt
# from the pool matches one built fresh. The first run is always downtown so
# a drive starts among tall buildings. Around each run boundary the two
# districts blend, building by building, so changes feel gradual.
#
# World step 3 (W6, 2026-10-10) takes the kinds from 4 to 11 (old town,
# lofts, hillside, airport edge, docks, Route 9 freeway, canyon) and replaces
# the weighted hash with ORDER: a loop of 16 runs (12.8 km) in which no kind
# follows itself, the wrap from the last run back to the first included.
# Each new kind is a SPECS row; what the road itself does in a freeway or a
# canyon run is the road recipe's job (V1), not this table's.
#
# World step 3b (2026-10-10): at night the kinds were hard to tell apart,
# because what a driver sees in the dark is light, and every kind had the same
# sodium lamps over the same asphalt. Each kind now also names its street kit
# ("street", "signs", "panel" below): the lamp's shape, its light colour and
# how many stand in a chunk, the road surface, and the colours its signs burn
# in. All of it is picked when a chunk is built from a handful of shared
# meshes and materials; nothing is added to a frame.

#
# On a loop (road_map.gd) the districts are the map's, in its order and at its
# lengths, and come round again every lap; a "run" is then a district's number
# on the loop. Off a loop (the endless road, and chunks built without a game)
# it is the hashed map above.

const RoadMap := preload("res://scripts/world/road_map.gd")

const RUN := 16
# Chunks on each side of a run boundary that mix the two districts. The
# share of the far district steps 1/5, 2/5 | 3/5, 4/5 across the boundary.
const BLEND := 2

# The district of each run, repeating. Neighbours are picked to contrast on
# the skyline (tall next to low, built-up next to open) and to make sense on
# a map: old town and the lofts ring downtown, the hills lead to the canyon,
# the freeway comes back in past the strip, and the sheds, the airport and
# the docks share the flat ground. tests/world/district_kinds.gd holds every
# pair of neighbours to two differences out of landmark, roof height, fill.
const ORDER := [
	"downtown", "old_town", "lofts", "residential",
	"hillside", "canyon", "freeway", "strip",
	"industrial", "airport", "docks", "old_town",
	"downtown", "residential", "strip", "freeway",
]

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
#
# World step 3 (2026-10-10, shop fronts) adds one more:
# fronts: weights for what is behind a shop's ground-floor glass
#   (BuildingKit.ROOMS: store, laundromat, bar, vacant, shuttered). A gas
#   station's kiosk is always a store and a diner always a bar room; the
#   table only decides plain shops.
#
# World step 3 (district kinds) adds one more:
# tints: weights over BuildingKit.TINTS indices, the district's palette. A
#   district that leaves it out draws evenly from the first 8, as before.
#
# World step 3b adds the street kit:
# street: {lamp, light, every, road}, any of them left out falls back to
#   STREET. lamp: the pole's shape (RoadChunkBuilder.LAMP_KINDS). light: its
#   colour (RoadChunkBuilder.LIGHTS). every: 1 = four lamps a chunk, 2 = two,
#   4 = one, 0 = none (a dark road). road: the surface
#   (RoadChunkBuilder.ROADS).
# signs: weights over BuildingSigns.COLORS, the colours the district's signs
#   burn in. Left out: an even draw, as before.
# panel: share of signs that are a lit panel with dark letters rather than
#   lit letters on a dark box.
const DEFAULTS := {
	"wear": [0.3, 0.7],
	"tops": [["flat", 50], ["cornice", 25], ["gable", 25]],
	"landmark": "",
	"fronts": [["store", 35], ["bar", 20], ["laundromat", 15], ["vacant", 15], ["shuttered", 15]],
	"tints": [],
	"signs": [],
	"panel": 0.3,
}
const STREET := {"lamp": "cobra", "light": "sodium", "every": 1, "road": "asphalt"}
# Light colours, inside Amber vs. Dusk: deep sodium orange, a paler amber for
# old lantern posts, and a silver-white for metal-halide yards and newer
# streets. pool: how strongly the lamp's pool adds to the road.
const LIGHTS := {
	"sodium": {"color": Color(1.0, 0.55, 0.2), "pool": 0.42},
	"amber": {"color": Color(1.0, 0.78, 0.45), "pool": 0.36},
	"white": {"color": Color(0.8, 0.88, 1.0), "pool": 0.3},
}
# How high up a building front each lamp shape's light reaches, m, and how
# much of it there is by lamp count (every): the wash BuildingKit paints on
# the walls, so a whole street takes its lamps' colour.
const WASH_REACH := {"cobra": 10.0, "post": 5.5, "mast": 14.0, "flood": 20.0}
const WASH_BY_EVERY := {0: 0.0, 1: 1.0, 2: 0.7, 4: 0.4}
const SPECS := {
	"downtown": {
		"mix": [["office", 35], ["parking", 15], ["apartment", 25], ["shop", 25]],
		"h": {"office": [30.0, 80.0], "apartment": [18.0, 40.0], "parking": [9.0, 18.0]},
		"d": [14.0, 24.0], "w": [10.0, 20.0], "setback": 0.0, "gap": 0.0, "lit": 1.0,
		"low": "shop", "billboard": 1.0,
		"wear": [0.1, 0.45], "tops": [["crown", 35], ["setback", 25], ["cornice", 20], ["flat", 20]],
		"landmark": "tower",
		"fronts": [["store", 35], ["bar", 30], ["laundromat", 5], ["vacant", 10], ["shuttered", 20]],
		"street": {"lamp": "cobra", "light": "sodium", "every": 1, "road": "asphalt"},
	},
	"residential": {
		"mix": [["apartment", 63], ["shop", 29], ["parking", 4], ["diner", 4]],
		"h": {"apartment": [8.0, 18.0]},
		"d": [9.0, 18.0], "w": [6.0, 12.0], "setback": 1.5, "gap": 0.15, "lit": 1.25,
		"low": "garage", "billboard": 0.5,
		"wear": [0.3, 0.7], "tops": [["gable", 30], ["hip", 20], ["cornice", 25], ["flat", 25]],
		"landmark": "water_tower",
		"fronts": [["store", 30], ["laundromat", 30], ["bar", 15], ["vacant", 10], ["shuttered", 15]],
		"street": {"lamp": "cobra", "light": "amber", "every": 2},
		"signs": [[1, 70], [0, 30]],
	},
	"strip": {
		"mix": [["shop", 45], ["garage", 25], ["gas", 15], ["diner", 15]],
		"h": {"shop": [3.4, 7.0]},
		"d": [12.0, 22.0], "w": [8.0, 14.0], "setback": 8.0, "gap": 0.2, "lit": 1.0,
		"low": "garage", "billboard": 1.0,
		"wear": [0.4, 0.85], "tops": [["parapet", 40], ["gable", 20], ["hip", 10], ["flat", 30]],
		"landmark": "screen",
		"fronts": [["store", 35], ["bar", 20], ["laundromat", 20], ["vacant", 15], ["shuttered", 10]],
		"street": {"lamp": "flood", "light": "sodium", "every": 2},
		"signs": [[0, 55], [1, 20], [2, 25]], "panel": 0.7,
	},
	"industrial": {
		"mix": [["warehouse", 75], ["garage", 25]],
		"h": {},
		"d": [16.0, 24.0], "w": [12.0, 24.0], "setback": 3.0, "gap": 0.3, "lit": 0.35,
		"wear": [0.6, 1.0], "tops": [["gable", 45], ["flat", 55]],
		"landmark": "stacks",
		"low": "garage", "billboard": 0.5,
		"fronts": [["shuttered", 50], ["vacant", 30], ["store", 20]],
		"street": {"lamp": "cobra", "light": "sodium", "every": 4, "road": "worn"},
		"signs": [[1, 100]], "panel": 0.0,
	},
	# ---- world step 3 (W6) ----
	# Old town: narrow brick tenements over shops, shoulder to shoulder at
	# the sidewalk, heavy cornices, a church steeple over the roofs.
	"old_town": {
		"mix": [["tenement", 55], ["shop", 35], ["garage", 5], ["diner", 5]],
		"h": {"tenement": [10.5, 18.0], "shop": [6.5, 10.0]},
		"d": [7.0, 12.0], "w": [8.0, 14.0], "setback": 0.0, "gap": 0.04, "lit": 1.1,
		"low": "shop", "billboard": 0.3,
		"wear": [0.45, 0.85], "tops": [["cornice", 45], ["gable", 20], ["hip", 15], ["flat", 20]],
		"landmark": "steeple",
		"tints": [[8, 45], [2, 30], [6, 15], [5, 10]],
		"street": {"lamp": "post", "light": "amber", "every": 1, "road": "setts"},
		"signs": [[1, 60], [0, 40]], "panel": 0.1,
	},
	# Lofts and nightlife: converted mills with big factory windows, most of
	# them lit, clubs and bars at street level, a lit rooftop sign.
	"lofts": {
		"mix": [["loft", 60], ["shop", 20], ["parking", 10], ["diner", 10]],
		"h": {"loft": [16.0, 28.0], "shop": [6.8, 10.2], "parking": [12.0, 18.0]},
		"d": [15.0, 23.0], "w": [12.0, 18.0], "setback": 0.0, "gap": 0.05, "lit": 1.7,
		"low": "shop", "billboard": 1.5,
		"wear": [0.3, 0.65], "tops": [["flat", 30], ["cornice", 30], ["setback", 25], ["parapet", 15]],
		"landmark": "marquee",
		"tints": [[2, 30], [8, 20], [5, 25], [7, 15], [3, 10]],
		"street": {"lamp": "cobra", "light": "white", "every": 1},
		"signs": [[3, 70], [1, 30]], "panel": 0.15,
	},
	# Hillside houses: two-storey timber houses behind front yards, every
	# roof pitched, warm windows, nothing taller than a chimney.
	"hillside": {
		"mix": [["house", 85], ["shop", 8], ["diner", 7]],
		"h": {"house": [5.6, 8.4], "shop": [3.4, 3.4]},
		"d": [8.0, 12.0], "w": [7.0, 10.0], "setback": 5.0, "gap": 0.25, "lit": 1.35,
		"low": "garage", "billboard": 0.0,
		"wear": [0.15, 0.5], "tops": [["gable", 60], ["hip", 40]],
		"landmark": "",
		"tints": [[9, 35], [4, 25], [1, 20], [7, 10], [3, 10]],
		"street": {"lamp": "post", "light": "white", "every": 4, "road": "worn"},
		"signs": [[1, 100]],
	},
	# Airport edge: pale hangars and long-stay car parks far back from the
	# road, wide dark gaps between them, a control tower with a lit cab.
	"airport": {
		"mix": [["hangar", 50], ["parking", 20], ["warehouse", 15], ["office", 15]],
		"h": {"hangar": [12.0, 18.0], "parking": [9.0, 15.0], "office": [10.0, 16.0]},
		"d": [20.0, 24.0], "w": [16.0, 26.0], "setback": 8.0, "gap": 0.4, "lit": 0.5,
		"low": "garage", "billboard": 0.6,
		"wear": [0.15, 0.45], "tops": [["flat", 70], ["gable", 30]],
		"landmark": "control_tower",
		"tints": [[10, 55], [0, 25], [7, 20]],
		"street": {"lamp": "mast", "light": "white", "every": 2, "road": "concrete"},
		"signs": [[2, 60], [1, 40]], "panel": 0.8,
	},
	# Docks: container stacks in mixed colours, rusted sheds, almost no lit
	# windows, a gantry crane over the stacks.
	"docks": {
		"mix": [["containers", 50], ["warehouse", 30], ["hangar", 10], ["garage", 10]],
		"h": {"containers": [5.2, 13.0], "hangar": [12.0, 12.0]},
		"d": [14.0, 24.0], "w": [10.0, 20.0], "setback": 4.0, "gap": 0.25, "lit": 0.3,
		"low": "garage", "billboard": 0.3,
		"wear": [0.55, 0.95], "tops": [["flat", 80], ["gable", 20]],
		"landmark": "crane",
		"tints": [[11, 30], [3, 25], [6, 20], [12, 15], [5, 10]],
		"street": {"lamp": "flood", "light": "sodium", "every": 2, "road": "concrete"},
		"signs": [[0, 60], [1, 40]], "panel": 0.0,
	},
	# Route 9 freeway: more open verge than buildings; gas stations, diners,
	# motels and sheds far apart, billboards on most of them, a high sign.
	"freeway": {
		"mix": [["gas", 22], ["diner", 13], ["shop", 20], ["warehouse", 25], ["office", 20]],
		"h": {"shop": [3.4, 7.0], "office": [12.0, 22.0]},
		"d": [14.0, 22.0], "w": [10.0, 16.0], "setback": 8.0, "gap": 0.6, "lit": 0.75,
		"low": "garage", "billboard": 2.5,
		"wear": [0.3, 0.6], "tops": [["flat", 60], ["parapet", 40]],
		"landmark": "high_sign",
		"tints": [[0, 35], [7, 30], [4, 20], [1, 15]],
		"street": {"lamp": "mast", "light": "sodium", "every": 2, "road": "concrete"},
		"signs": [[2, 60], [0, 40]], "panel": 0.8,
	},
	# Canyon: almost nothing. A lone cabin, a shack garage or a roadhouse
	# every few hundred metres, and a radio mast with its red light.
	"canyon": {
		"mix": [["house", 45], ["garage", 25], ["diner", 20], ["gas", 10]],
		"h": {"house": [5.6, 5.6]},
		"d": [8.0, 12.0], "w": [7.0, 10.0], "setback": 6.0, "gap": 0.85, "lit": 0.6,
		"low": "garage", "billboard": 0.4,
		"wear": [0.5, 0.9], "tops": [["gable", 100]],
		"landmark": "mast",
		"tints": [[5, 35], [6, 30], [1, 35]],
		"street": {"lamp": "cobra", "light": "sodium", "every": 0, "road": "worn"},
		"signs": [[0, 100]], "panel": 0.0,
	},
}

## Tools: one district everywhere (tools/roadside_kit_shots.gd).
static var force := ""

static func run_of(chunk_index: int) -> int:
	if RoadMap.is_loop():
		return RoadMap.district_of(chunk_index)
	return floori(float(chunk_index) / float(RUN))

static func name_of_run(run: int) -> String:
	if force != "":
		return force
	if RoadMap.is_loop():
		return RoadMap.district_kind(run)
	return ORDER[posmod(run, ORDER.size())]

## The district a chunk belongs to (its run's), for chunk-wide things like
## the setback.
static func name_at(chunk_index: int) -> String:
	return name_of_run(run_of(chunk_index))

## The neighbouring run a chunk blends with and how much of the chunk follows
## it: [run, share]. Share is 0 away from a run boundary; in the last BLEND
## chunks of a run it climbs toward the next run, in the first BLEND chunks
## it falls away from the previous one. The very first run has no "before":
## a drive starts in pure downtown.
static func blend_at(chunk_index: int) -> Array:
	var run := run_of(chunk_index)
	var pos := posmod(chunk_index, RUN)
	var left := RUN - 1 - pos
	var looped := RoadMap.is_loop()
	if looped:
		# a loop's districts set their own lengths (road_map.gd)
		pos = RoadMap.into_district(chunk_index)
		left = RoadMap.left_in_district(chunk_index)
	var steps := float(2 * BLEND + 1)
	if left < BLEND:
		return [run + 1, float(BLEND - left) / steps]
	if pos < BLEND and (run != 0 or looped):
		return [run - 1, float(BLEND - pos) / steps]
	return [run, 0.0]

## The district one building in this chunk follows: its run's, or, near a run
## boundary, sometimes the neighbouring run's (blend_at). roll is in [0, 1).
static func name_for_building(chunk_index: int, roll: float) -> String:
	var b := blend_at(chunk_index)
	if roll < float(b[1]):
		return name_of_run(int(b[0]))
	return name_of_run(run_of(chunk_index))

static func spec(name: String) -> Dictionary:
	return SPECS[name]

## A district's street kit, every key filled in (STREET where the row leaves
## one out).
static func street(name: String) -> Dictionary:
	if not _streets.has(name):
		var out := STREET.duplicate()
		out.merge(SPECS[name].get("street", {}), true)
		_streets[name] = out
	return _streets[name]

static var _streets := {}  # name -> filled-in kit, built once (read-only)
static var _washes := {}   # "light/lamp/every" -> [colour * strength, reach]

## The street kit of a chunk: its run's. The street does not blend the way
## the buildings do; lamps and surface change at the run boundary, the way a
## road changes hands at a city line.
static func street_at(chunk_index: int) -> Dictionary:
	return street(name_at(chunk_index))

## The lamp light on a district's building fronts: [colour * strength, how
## high it reaches in m]. Takes a spec (or a landmark's copy of one).
static func wash_of(district: Dictionary) -> Array:
	var st: Dictionary = district.get("street", STREET)
	var light: String = st.get("light", STREET.light)
	var lamp: String = st.get("lamp", STREET.lamp)
	var every := int(st.get("every", STREET.every))
	var key := "%s/%s/%d" % [light, lamp, every]
	if not _washes.has(key):
		var c: Color = LIGHTS[light].color
		var k: float = WASH_BY_EVERY[every]
		_washes[key] = [Vector3(c.r, c.g, c.b) * k, float(WASH_REACH[lamp])]
	return _washes[key]

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
	"steeple": {"type": "tenement", "h": 12.4},
	"marquee": {"type": "loft", "h": 20.0},
	"control_tower": {"type": "hangar", "h": 12.0},
	"crane": {"type": "containers", "h": 7.8},
	"high_sign": {"type": "shop", "h": 3.4},
	"mast": {"type": "house", "h": 5.6},
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

## The chunk's setback, m: its district's, eased toward the neighbouring
## district's near a run boundary (blend_at), so a deep lot meets a street
## wall in four small steps instead of one big one.
static func setback_at(chunk_index: int) -> float:
	var own := float(SPECS[name_at(chunk_index)].setback)
	var b := blend_at(chunk_index)
	if float(b[1]) <= 0.0:
		return own
	return lerpf(own, float(SPECS[name_of_run(int(b[0]))].setback), float(b[1]))

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

## TEST BUILD (integration): the seven newer district kinds (world step 3,
## #378) have no CROSS row yet, so each borrows the nearest of the four
## that do. Placeholder picks, not design: the kerbs owner sets real rows.
const CROSS_LIKE := {
	"lofts": "downtown", "old_town": "downtown", "hillside": "residential",
	"docks": "industrial", "airport": "industrial",
}
const CROSS_OPEN := ["freeway", "canyon"]   # no raised kerb: the FREEWAY section

static func cross_of(name: String) -> Dictionary:
	if CROSS.has(name):
		return CROSS[name]
	if name in CROSS_OPEN:
		return FREEWAY
	return CROSS[CROSS_LIKE.get(name, "residential")]

## The section at the END of chunk `chunk_index` (the road builder tapers
## from cross_at(i - 1) to cross_at(i) across chunk i). Keyed by the same
## fixed-map districts as everything else here, so a recycled chunk matches
## a fresh one. A chunk whose neighbour touches a crossing is held at the
## crossing's section too, so the chunk that touches it starts and ends there.
static func cross_at(chunk_index: int) -> Dictionary:
	if Junction.touches(chunk_index) or Junction.touches(chunk_index + 1):
		var d: Dictionary = cross_of(name_at(chunk_index)).duplicate()
		d.merge(JUNCTION, true)  # the crossing's geometry, the district's drops
		return d
	if is_freeway(chunk_index):
		return FREEWAY
	return cross_of(name_at(chunk_index))

## Whether the chunk is on a freeway stretch: RoadLayout's "outskirts"
## (fixed map seed, so the same stretches every run). No layout, no freeway.
static func is_freeway(chunk_index: int) -> bool:
	var lay: RoadLayout = RoadFrame.layout
	if lay == null:
		return false
	# On a loop the same chunk every lap (and never a negative distance, which
	# the layout reads as its first city): buildings stood 0.8 m further out a
	# lap later where only the later lap fell in the outskirts.
	return lay.district_at((float(RoadMap.lap_chunk(chunk_index)) + 0.5) * RoadChunkBuilder.CHUNK_LEN) == "outskirts"

static func walk_at(chunk_index: int) -> float:
	return float(cross_at(chunk_index).walk)

static func shoulder_at(chunk_index: int) -> float:
	return float(cross_at(chunk_index).shoulder)

static func kerb_h_at(chunk_index: int) -> float:
	return float(cross_at(chunk_index).kerb_h)

static func drops_for(name: String) -> Array:
	return cross_of(name).drops
