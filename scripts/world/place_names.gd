extends RefCounted

# Every name the world prints on a sign or a road, in one table (world step 4,
# "Names you can read", 2026-10-10). Roy writes the final names; until then
# these are placeholders keyed on the districts in districts.gd. To rename an
# area, change its "name" here and nothing else: the signs, the head unit and
# the glyph atlas all read this table.
#
# Cost of the names themselves: none. Lettering is drawn once at boot into a
# texture array (word_atlas.gd) with the "road" font role (Overpass).

const Rules := preload("res://scripts/traffic/police_rules.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")

## One entry per district key in districts.gd.
##   name:  what the area sign and the head unit say, capitals.
##   bus:   whether the outer lane gets a painted BUS here now and then.
## The number on the signs and the road is not here: it is the posted limit
## the police act on (PoliceRules.POSTED_KMH), by the map's area class, so the
## signs cannot say one thing and the cops another (police step P3).
const AREAS := {
	"downtown": {"name": "DOWNTOWN", "bus": true},
	"residential": {"name": "RESIDENTIAL", "bus": false},
	"strip": {"name": "THE STRIP", "bus": false},
	"industrial": {"name": "INDUSTRIAL", "bus": false},
}

## How far apart the round repeater signs stand inside an area, in chunks
## (8 x 50 m = 400 m), and which chunk of each stretch carries one.
const REPEAT_CHUNKS := 8
const REPEAT_AT := 3

## First line of the area gantry, and the distance line of the advance sign.
const ENTERING := "ENTERING"
const ADVANCE := "400 m"
## How far before an area's start the advance sign stands, metres. Must be a
## whole number of chunks (RoadChunkBuilder.CHUNK_LEN).
const ADVANCE_M := 400.0

## The main road's name on the cross street's blades, and the names the cross
## streets are dealt from (by crossing, so a given crossing always has one).
const MAIN_STREET := "MAIN ST"
const CROSS_STREETS := ["5TH ST", "ELM ST", "DOCK RD", "HIGH ST"]

## Words painted on the road, besides the speed numbers.
const PAINT_WORDS := ["SLOW", "BUS", "STOP"]
## Painted arrows are drawn into the atlas as shapes, not text; the "#" marks
## them. Order matters: the atlas row follows it.
## "#UTURN" is the turn-round arrow (up the lane, over toward the median, back
## down); "#NOUTURN" is the red ring and slash drawn over it on a no-U-turn sign.
const ARROWS := ["#STRAIGHT", "#LEFT", "#RIGHT", "#UTURN", "#NOUTURN"]

static func area_name(district: String) -> String:
	if AREAS.has(district):
		return String(AREAS[district].name)
	return district.to_upper()

## The posted limit in chunk `chunk_index`, km/h: 60 in a city district, 100
## on a highway stretch (a road with no map is city, as for the police).
static func limit_at(chunk_index: int) -> int:
	return int(Rules.posted_limit(RoadMap.area_at((float(chunk_index) + 0.5) * RoadMap.L)))

## Every limit a sign or the road can show.
static func limits() -> Array:
	var out: Array = []
	for v in Rules.POSTED_KMH.values():
		out.append(int(v))
	return out

static func has_bus(district: String) -> bool:
	return bool(AREAS[district].bus) if AREAS.has(district) else false

## The cross street at crossing number k (the junction's index along the road).
static func cross_street(k: int) -> String:
	return CROSS_STREETS[posmod(k, CROSS_STREETS.size())]

## Every text the atlas has to draw, in layer order, without repeats.
static func atlas_words() -> Array:
	var out: Array = [ENTERING, ADVANCE, MAIN_STREET]
	for k in AREAS:
		out.append(area_name(k))
	for v in limits():
		out.append(str(v))
	for s in CROSS_STREETS:
		out.append(s)
	for w in PAINT_WORDS:
		if not out.has(w):
			out.append(w)
	for a in ARROWS:
		out.append(a)
	return out
