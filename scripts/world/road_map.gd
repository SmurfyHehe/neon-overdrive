extends RefCounted

# The map: which road the player is on (loop 1, 2026-10-10; Roy: the city is
# several loops joined by interchanges, one loop first).
#
# A road here is a closed loop of PERIOD chunks. The loop is closed in what is
# on it, not in the world: chunk i and chunk i + PERIOD are the same place (the
# same bend, hill, district, buildings and centre barrier), so driving on in
# either direction brings the same districts round again, and there is no end
# to fall off. The road is still laid out down world -Z around the floating
# origin, lap after lap, so RoadFrame, traffic and the chunk pool keep working
# in plain metres along the road with no wrap anywhere; RoadAlignment makes the
# shape repeat (its `period`), and everything that picks what a chunk contains
# asks lap_chunk() for the chunk's place on the loop first.
#
# Every road has an id, and the save records it (SaveDirector), so a save made
# on one road never opens on another: a save with an id this build does not
# know (or none: saves from before the map) starts at the top of the default
# road, keeping the clock and the radio.
#
# "endless" is the road from before the map: no loop, districts picked by a
# hash, one crossing at 600 m. NEON_ROAD=endless runs it (tests that are about
# that road, and like-for-like benchmarks against older builds). With no road
# set (tests that build chunks without a game) everything behaves as endless.
#
# Districts: each is `chunks` long and uses one of Districts.SPECS' building
# mixes. `area` groups them: a "city" area is entered through a signalised
# crossing (Junction) at each end, a "highway" stretch has none, so traffic on
# it keeps moving. Names are placeholders (the story is Roy's).
# No class_name on purpose: preload it, so no class cache refresh is needed.

const L := 50.0  # RoadChunkBuilder.CHUNK_LEN (not referenced: this file loads first)
const ENDLESS := "endless"
const DEFAULT := "loop_1"

const ROADS := {
	"loop_1": {
		"name": "Loop 1",
		"seed": 20261010,
		"districts": [
			{"name": "District 1", "kind": "downtown", "area": "city", "chunks": 16},
			{"name": "District 2", "kind": "residential", "area": "city", "chunks": 16},
			{"name": "District 3", "kind": "strip", "area": "highway", "chunks": 16},
			{"name": "District 4", "kind": "industrial", "area": "highway", "chunks": 16},
			{"name": "District 5", "kind": "residential", "area": "city", "chunks": 16},
			{"name": "District 6", "kind": "downtown", "area": "city", "chunks": 16},
			{"name": "District 7", "kind": "strip", "area": "highway", "chunks": 16},
			{"name": "District 8", "kind": "industrial", "area": "highway", "chunks": 16},
		],
	},
}

## Crossing centre, metres inside the city area from its edge.
const JUNCTION_INSET := 75.0

## The road this run is on: "" or "endless" = the road from before the map.
static var road_id := ""
## Chunks in one lap; 0 = not a loop.
static var period := 0
static var _starts := PackedInt32Array()   # first chunk of each district
static var _kinds := PackedStringArray()
static var _junctions := PackedFloat64Array()  # crossing centres, metres round the loop

static func knows(id: String) -> bool:
	return id == ENDLESS or ROADS.has(id)

static func is_loop() -> bool:
	return period > 0

## Puts the run on road `id` ("" or "endless" = no loop).
static func use(id: String) -> void:
	road_id = id if ROADS.has(id) else (ENDLESS if id == ENDLESS else "")
	period = 0
	_starts = PackedInt32Array()
	_kinds = PackedStringArray()
	_junctions = PackedFloat64Array()
	if not ROADS.has(id):
		return
	var ds: Array = ROADS[id].districts
	for d in ds:
		_starts.append(period)
		_kinds.append(String(d.kind))
		period += int(d.chunks)
	# A crossing just inside each end of every city area.
	for n in ds.size():
		var prev: Dictionary = ds[posmod(n - 1, ds.size())]
		var next: Dictionary = ds[posmod(n + 1, ds.size())]
		if ds[n].area != "city":
			continue
		if prev.area != "city":
			_junctions.append(float(_starts[n]) * L + JUNCTION_INSET)
		if next.area != "city":
			_junctions.append(float(_starts[n] + int(ds[n].chunks)) * L - JUNCTION_INSET)

static func seed_of(id: String) -> int:
	return int(ROADS[id].seed) if ROADS.has(id) else 0

## Metres in one lap (0 = not a loop).
static func length() -> float:
	return float(period) * L

## A chunk's place on the loop, 0 .. period - 1 (the chunk itself off a loop).
static func lap_chunk(chunk_index: int) -> int:
	return posmod(chunk_index, period) if period > 0 else chunk_index

## Metres round the loop for metres along the road (RoadFrame.s_at).
static func wrap_s(s: float) -> float:
	return fposmod(s, length()) if period > 0 else s

## Which district (0 .. count - 1) a chunk is in; -1 off a loop.
static func district_of(chunk_index: int) -> int:
	if period <= 0:
		return -1
	var m := lap_chunk(chunk_index)
	var n := _starts.size() - 1
	while n > 0 and _starts[n] > m:
		n -= 1
	return n

static func district_count() -> int:
	return _starts.size()

static func district_kind(n: int) -> String:
	return _kinds[posmod(n, _kinds.size())]

static func district_info(n: int) -> Dictionary:
	return ROADS[road_id].districts[posmod(n, _starts.size())] if period > 0 else {}

## Chunks from the start of its district to this chunk, and to the district's end.
static func into_district(chunk_index: int) -> int:
	return lap_chunk(chunk_index) - _starts[district_of(chunk_index)]

static func left_in_district(chunk_index: int) -> int:
	var n := district_of(chunk_index)
	return int(ROADS[road_id].districts[n].chunks) - into_district(chunk_index) - 1

## Crossing centres, metres round the loop.
static func junctions() -> PackedFloat64Array:
	return _junctions

## The crossing nearest to `s` metres along the road, as metres along the road
## (the same lap as s, or the one before or after). INF when there is none.
static func junction_near(s: float) -> float:
	if _junctions.is_empty():
		return INF
	var lap := length()
	var best := INF
	var m := fposmod(s, lap)
	for c in _junctions:
		var d := fposmod(c - m + lap * 0.5, lap) - lap * 0.5
		if absf(d) < absf(best):
			best = d
	return s + best
