extends RefCounted

# The map: which road the player is on, and what is where on it (loop 1,
# 2026-10-10; Roy: the city is several highway loops joined by interchanges,
# one loop first, built as a complete game). The pause map and the sat-nav
# read this file and nothing else.
#
# A road here is a closed loop of `period` chunks. The loop is closed in what
# is on it, not in the world: chunk i and chunk i + period are the same place
# (the same bend, hill, district, buildings and centre barrier), so driving on
# in either direction brings the same districts round again, and there is no
# end to fall off. The road is still laid out down world -Z around the
# floating origin, lap after lap, so RoadFrame, traffic and the chunk pool
# keep working in plain metres along the road with no wrap anywhere;
# RoadAlignment makes the shape repeat (its `period`), and everything that
# picks what a chunk contains asks lap_chunk() for the chunk's place first.
# Laps are never counted or shown: a place is (road id, s, dir).
#
# A place: road id (0 while there is one loop), s = metres round the loop from
# its start, dir = +1 the way the chunks count, -1 the other way. The save
# writes exactly these (SaveDirector), and where() gives them live.
#
# What is fixed and what changes each night. Fixed, from this file: the
# districts, the crossings, the exits, the median gaps, the stops, the
# buildings and the centre barrier (the road's own `seed`). New each night,
# from the night's road seed, and the same on every pass that night: bends
# and hills. pins() marks the chunks that must be straight and level whatever
# the night's seed (the approaches to crossings, exits and median gaps).
#
# Growing by act: a district has the `act` it first appears in. use(id, act)
# takes the districts of that act and earlier, in order, so an act's new
# districts go on after the last one and nothing already placed moves (its s
# stays the same). Loop length is just a number: 8 districts (6.4 km) in act
# 1, 12 in act 2, 16 (12.8 km) in act 3. Every act's last district is a
# highway stretch, so the crossing at the start of district 1 stays put.
#
# "endless" (id -1) is the road from before the map: no loop, districts picked
# by a hash, one crossing at 600 m. NEON_ROAD=endless runs it (tests that are
# about that road, and like-for-like benchmarks against older builds). With no
# road set (tests that build chunks without a game) everything behaves as
# endless.
#
# Districts: each is `chunks` long and uses one of Districts.SPECS' building
# mixes. `area` groups them: a "city" area is entered through a signalised
# crossing (Junction) at each end, a "highway" stretch has none, so traffic on
# it keeps moving. Names and zones are placeholders (the story is Roy's).
# No class_name on purpose: preload it, so no class cache refresh is needed.

const L := 50.0  # RoadChunkBuilder.CHUNK_LEN (not referenced: this file loads first)
const ENDLESS := -1
const DEFAULT := 0
const MAX_ACT := 3

const ROADS := {
	0: {
		"name": "Loop 1",
		# Buildings and the centre barrier: the same every night.
		"seed": 20261010,
		# Where a night starts (beside the shop's district).
		"start": {"s": 0.0, "dir": 1},
		"districts": [
			{"name": "District 1", "zone": "Route 9", "kind": "downtown", "area": "city", "act": 1, "chunks": 16},
			{"name": "District 2", "zone": "Route 9", "kind": "residential", "area": "city", "act": 1, "chunks": 16},
			{"name": "District 3", "zone": "Route 9", "kind": "strip", "area": "highway", "act": 1, "chunks": 16},
			{"name": "District 4", "zone": "Route 9", "kind": "industrial", "area": "highway", "act": 1, "chunks": 16},
			{"name": "District 5", "zone": "The Docks", "kind": "residential", "area": "city", "act": 1, "chunks": 16},
			{"name": "District 6", "zone": "The Docks", "kind": "downtown", "area": "city", "act": 1, "chunks": 16},
			{"name": "District 7", "zone": "The Docks", "kind": "strip", "area": "highway", "act": 1, "chunks": 16},
			{"name": "District 8", "zone": "The Docks", "kind": "industrial", "area": "highway", "act": 1, "chunks": 16},
			{"name": "District 9", "zone": "", "kind": "residential", "area": "city", "act": 2, "chunks": 16},
			{"name": "District 10", "zone": "", "kind": "downtown", "area": "city", "act": 2, "chunks": 16},
			{"name": "District 11", "zone": "", "kind": "strip", "area": "highway", "act": 2, "chunks": 16},
			{"name": "District 12", "zone": "", "kind": "industrial", "area": "highway", "act": 2, "chunks": 16},
			{"name": "District 13", "zone": "", "kind": "downtown", "area": "city", "act": 3, "chunks": 16},
			{"name": "District 14", "zone": "", "kind": "residential", "area": "city", "act": 3, "chunks": 16},
			{"name": "District 15", "zone": "", "kind": "strip", "area": "highway", "act": 3, "chunks": 16},
			{"name": "District 16", "zone": "", "kind": "industrial", "area": "highway", "act": 3, "chunks": 16},
		],
		# The loop as drawn on the map: a closed line through these points, in a
		# 0-1 square (x right, y down), in loop order from s = 0. A schematic:
		# the road itself never closes in space.
		"map": [
			Vector2(0.50, 0.10), Vector2(0.72, 0.12), Vector2(0.88, 0.24), Vector2(0.92, 0.45),
			Vector2(0.86, 0.66), Vector2(0.70, 0.84), Vector2(0.50, 0.90), Vector2(0.30, 0.86),
			Vector2(0.13, 0.70), Vector2(0.08, 0.48), Vector2(0.14, 0.26), Vector2(0.30, 0.13),
		],
		# Exits, one pair per district, 400 m in: s = the gore, side +1 = the
		# carriageway going the way the chunks count, -1 = the other one.
		# `number` is what the sign says.
		"exits": [
			{"id": "x1a", "s": 400.0, "side": 1, "number": 1}, {"id": "x1b", "s": 400.0, "side": -1, "number": 1},
			{"id": "x2a", "s": 1200.0, "side": 1, "number": 2}, {"id": "x2b", "s": 1200.0, "side": -1, "number": 2},
			{"id": "x3a", "s": 2000.0, "side": 1, "number": 3}, {"id": "x3b", "s": 2000.0, "side": -1, "number": 3},
			{"id": "x4a", "s": 2800.0, "side": 1, "number": 4}, {"id": "x4b", "s": 2800.0, "side": -1, "number": 4},
			{"id": "x5a", "s": 3600.0, "side": 1, "number": 5}, {"id": "x5b", "s": 3600.0, "side": -1, "number": 5},
			{"id": "x6a", "s": 4400.0, "side": 1, "number": 6}, {"id": "x6b", "s": 4400.0, "side": -1, "number": 6},
			{"id": "x7a", "s": 5200.0, "side": 1, "number": 7}, {"id": "x7b", "s": 5200.0, "side": -1, "number": 7},
			{"id": "x8a", "s": 6000.0, "side": 1, "number": 8}, {"id": "x8b", "s": 6000.0, "side": -1, "number": 8},
			{"id": "x9a", "s": 6800.0, "side": 1, "number": 9}, {"id": "x9b", "s": 6800.0, "side": -1, "number": 9},
			{"id": "x10a", "s": 7600.0, "side": 1, "number": 10}, {"id": "x10b", "s": 7600.0, "side": -1, "number": 10},
			{"id": "x11a", "s": 8400.0, "side": 1, "number": 11}, {"id": "x11b", "s": 8400.0, "side": -1, "number": 11},
			{"id": "x12a", "s": 9200.0, "side": 1, "number": 12}, {"id": "x12b", "s": 9200.0, "side": -1, "number": 12},
			{"id": "x13a", "s": 10000.0, "side": 1, "number": 13}, {"id": "x13b", "s": 10000.0, "side": -1, "number": 13},
			{"id": "x14a", "s": 10800.0, "side": 1, "number": 14}, {"id": "x14b", "s": 10800.0, "side": -1, "number": 14},
			{"id": "x15a", "s": 11600.0, "side": 1, "number": 15}, {"id": "x15b", "s": 11600.0, "side": -1, "number": 15},
			{"id": "x16a", "s": 12400.0, "side": 1, "number": 16}, {"id": "x16b", "s": 12400.0, "side": -1, "number": 16},
		],
		# Gaps in the centre barrier (a legal place to turn round), two per
		# district, 225 m and 625 m in.
		"gaps": [
			{"id": "g1a", "s": 225.0}, {"id": "g1b", "s": 625.0}, {"id": "g2a", "s": 1025.0}, {"id": "g2b", "s": 1425.0},
			{"id": "g3a", "s": 1825.0}, {"id": "g3b", "s": 2225.0}, {"id": "g4a", "s": 2625.0}, {"id": "g4b", "s": 3025.0},
			{"id": "g5a", "s": 3425.0}, {"id": "g5b", "s": 3825.0}, {"id": "g6a", "s": 4225.0}, {"id": "g6b", "s": 4625.0},
			{"id": "g7a", "s": 5025.0}, {"id": "g7b", "s": 5425.0}, {"id": "g8a", "s": 5825.0}, {"id": "g8b", "s": 6225.0},
			{"id": "g9a", "s": 6625.0}, {"id": "g9b", "s": 7025.0}, {"id": "g10a", "s": 7425.0}, {"id": "g10b", "s": 7825.0},
			{"id": "g11a", "s": 8225.0}, {"id": "g11b", "s": 8625.0}, {"id": "g12a", "s": 9025.0}, {"id": "g12b", "s": 9425.0},
			{"id": "g13a", "s": 9825.0}, {"id": "g13b", "s": 10225.0}, {"id": "g14a", "s": 10625.0}, {"id": "g14b", "s": 11025.0},
			{"id": "g15a", "s": 11425.0}, {"id": "g15b", "s": 11825.0}, {"id": "g16a", "s": 12225.0}, {"id": "g16b", "s": 12625.0},
		],
	},
}

## Places to stop: rest areas off an exit, and real side streets. `exit` is an
## exit id on `road`. Placeholders until the stops are designed.
const STOPS := [
	{"id": "shop", "name": "The Shop", "kind": "shop", "road": 0, "exit": "x1a"},
	{"id": "fuel_1", "name": "Fuel 1", "kind": "station", "road": 0, "exit": "x3a"},
	{"id": "fuel_2", "name": "Fuel 2", "kind": "station", "road": 0, "exit": "x7b"},
]

## Joins between loops: [{id, a: {road, s}, b: {road, s}, kind}]. Empty until
## there is a second loop.
const INTERCHANGES := []

## Crossing centre, metres inside the city area from its edge.
const JUNCTION_INSET := 75.0
## Chunks kept straight and level either side of a crossing's or an exit's own.
const PIN_APPROACH := 1

## The road this run is on: ENDLESS = the road from before the map.
static var road_id := ENDLESS
static var act := 1
## Chunks in one lap; 0 = not a loop.
static var period := 0
static var _starts := PackedInt32Array()   # first chunk of each district
static var _kinds := PackedStringArray()
static var _junctions := PackedFloat64Array()  # crossing centres, metres round the loop
static var _exits: Array = []
static var _gaps: Array = []
static var _gap_chunk := PackedByteArray()
static var _pins := PackedByteArray()
static var _map_len := PackedFloat32Array()  # distance along the drawn line to each point

static func knows(id: int) -> bool:
	return id == ENDLESS or ROADS.has(id)

static func is_loop() -> bool:
	return period > 0

## Puts the run on road `id` as it is in act `act_value` (ENDLESS = no loop).
static func use(id: int, act_value: int = 1) -> void:
	road_id = id if ROADS.has(id) else ENDLESS
	act = clampi(act_value, 1, MAX_ACT)
	period = 0
	_starts = PackedInt32Array()
	_kinds = PackedStringArray()
	_junctions = PackedFloat64Array()
	_exits = []
	_gaps = []
	_gap_chunk = PackedByteArray()
	_pins = PackedByteArray()
	_map_len = PackedFloat32Array()
	if not ROADS.has(id):
		return
	var road: Dictionary = ROADS[id]
	var ds := districts()
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
	# Exits and gaps on the part of the road this act has; straight, level
	# road at each and at the crossings.
	_pins.resize(period)
	_gap_chunk.resize(period)
	for e in road.exits:
		if float(e.s) < length():
			_exits.append(e)
			_pin(floori(float(e.s) / L), PIN_APPROACH)
	for g in road.gaps:
		if float(g.s) < length():
			_gaps.append(g)
			_gap_chunk[floori(float(g.s) / L)] = 1
			_pin(floori(float(g.s) / L), 0)
	for c in _junctions:
		_pin(floori(c / L), PIN_APPROACH)
	var pts: Array = road.map
	_map_len.append(0.0)
	for i in pts.size():
		_map_len.append(_map_len[i] + (pts[(i + 1) % pts.size()] as Vector2).distance_to(pts[i]))

static func _pin(chunk: int, approach: int) -> void:
	for i in range(chunk - approach, chunk + approach + 1):
		_pins[posmod(i, period)] = 1

## The fixed seed for what stands on the road (buildings, centre barrier).
static func seed_of(id: int) -> int:
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

## Where a point is: {road, s, dir}, the three values the save writes. `z` is
## road-space z (RoadFrame.unroll(position).z), `forward` the way it faces in
## world space (-basis.z). dir is +1 the way the chunks count, -1 the other.
static func where(z: float, forward: Vector3) -> Dictionary:
	return {"road": road_id, "s": wrap_s(RoadFrame.s_at(z)),
		"dir": 1 if RoadFrame.dir_to_road(z, forward).z <= 0.0 else -1}

## Where a night starts on road `id`: {s, dir}.
static func start_of(id: int) -> Dictionary:
	return ROADS[id].start if ROADS.has(id) else {"s": 0.0, "dir": 1}

## The districts on the road in this act, in loop order.
static func districts() -> Array:
	if not ROADS.has(road_id):
		return []
	return (ROADS[road_id].districts as Array).filter(func(d: Dictionary) -> bool: return int(d.act) <= act)

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

## Districts keep their place in ROADS[id].districts (an act only adds to the end).
static func district_info(n: int) -> Dictionary:
	return ROADS[road_id].districts[posmod(n, _starts.size())] if period > 0 else {}

## Metres round the loop where district n starts.
static func district_start(n: int) -> float:
	return float(_starts[posmod(n, _starts.size())]) * L

## "city" or "highway" at s metres along the road ("" off a loop).
static func area_at(s: float) -> String:
	return String(district_info(district_of(floori(s / L))).area) if period > 0 else ""

## Chunks from the start of its district to this chunk, and to the district's end.
static func into_district(chunk_index: int) -> int:
	return lap_chunk(chunk_index) - _starts[district_of(chunk_index)]

static func left_in_district(chunk_index: int) -> int:
	var n := district_of(chunk_index)
	return int(ROADS[road_id].districts[n].chunks) - into_district(chunk_index) - 1

## Crossing centres, metres round the loop.
static func junctions() -> PackedFloat64Array:
	return _junctions

## Exits on the road in this act: [{id, s, side, number}].
static func exits() -> Array:
	return _exits

## Gaps in the centre barrier in this act: [{id, s}].
static func gaps() -> Array:
	return _gaps

## Whether the centre barrier is open for the whole of this chunk (a gap).
static func gap_in(chunk_index: int) -> bool:
	return period > 0 and _gap_chunk[lap_chunk(chunk_index)] == 1

## One byte per chunk of the lap: 1 = straight and level whatever the night's
## seed (RoadAlignment).
static func pins() -> PackedByteArray:
	return _pins

## An exit of road `id` by its exit id ({} if there is none).
static func exit_of(id: int, exit_id: String) -> Dictionary:
	if ROADS.has(id):
		for e in ROADS[id].exits:
			if e.id == exit_id:
				return e
	return {}

## Where a stop is: {road, s, side} of its exit ({} for an unknown stop).
static func stop_place(stop_id: String) -> Dictionary:
	for st in STOPS:
		if st.id == stop_id:
			var e := exit_of(int(st.road), String(st.exit))
			return {"road": int(st.road), "s": float(e.s), "side": int(e.side)} if not e.is_empty() else {}
	return {}

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

## Where s metres round road `id` is on the drawn map (0-1 square). s wraps,
## so both headings and every lap give the same point. The line is walked at
## an even rate, so a place keeps its share of the way round, not its exact
## point, when a later act makes the loop longer.
static func map_point(id: int, s: float) -> Vector2:
	if id != road_id or period <= 0:
		return Vector2(0.5, 0.5)
	var pts: Array = ROADS[id].map
	var n := pts.size()
	var want := fposmod(s, length()) / length() * _map_len[n]
	var i := 0
	while i < n - 1 and _map_len[i + 1] <= want:
		i += 1
	var seg := _map_len[i + 1] - _map_len[i]
	return (pts[i] as Vector2).lerp(pts[(i + 1) % n], (want - _map_len[i]) / seg if seg > 0.0 else 0.0)
