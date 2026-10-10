extends RefCounted

# Every name the world prints on a sign or a road, in one table (world step 4,
# "Names you can read", 2026-10-10). Roy writes the final names; until then
# these are placeholders keyed on the districts in districts.gd. To rename an
# area, change its "name" here and nothing else: the signs, the head unit and
# the glyph atlas all read this table.
#
# Cost of the names themselves: none. Lettering is drawn once at boot into a
# texture array (word_atlas.gd) with the "road" font role (Overpass).

## One entry per district key in districts.gd.
##   name:  what the area sign and the head unit say, capitals.
##   speed: the number painted on the road at the area's start (decoration
##          only: nothing in the game enforces a limit).
##   bus:   whether the outer lane gets a painted BUS here now and then.
const AREAS := {
	"downtown": {"name": "DOWNTOWN", "speed": 50, "bus": true},
	"residential": {"name": "RESIDENTIAL", "speed": 30, "bus": false},
	"strip": {"name": "THE STRIP", "speed": 40, "bus": false},
	"industrial": {"name": "INDUSTRIAL", "speed": 60, "bus": false},
}

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
const ARROWS := ["#STRAIGHT", "#LEFT", "#RIGHT"]

static func area_name(district: String) -> String:
	if AREAS.has(district):
		return String(AREAS[district].name)
	return district.to_upper()

static func speed_of(district: String) -> int:
	return int(AREAS[district].speed) if AREAS.has(district) else 50

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
		var sp := str(speed_of(k))
		if not out.has(sp):
			out.append(sp)
	for s in CROSS_STREETS:
		out.append(s)
	for w in PAINT_WORDS:
		if not out.has(w):
			out.append(w)
	for a in ARROWS:
		out.append(a)
	return out
