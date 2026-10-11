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
		# Ring sites, one per district, 400 m in: s = the ring's centre (a raised
		# roundabout over the highway, R2; in R1 a turning pad either side).
		# `number` is what the exit signs say. `kind` is what the ring leads to:
		# "stop" (a spur to a stop, see STOPS), "lot", "landmark" (something on
		# the island), "plain", or "tunnel" (no ring and no exits: the road goes
		# under, built separately). The exits and the gaps are worked out from
		# these (exits(), gaps()).
		"rings": [
			{"id": "x1", "s": 400.0, "number": 1, "kind": "stop"}, {"id": "x2", "s": 1200.0, "number": 2, "kind": "landmark"},
			{"id": "x3", "s": 2000.0, "number": 3, "kind": "stop"}, {"id": "x4", "s": 2800.0, "number": 4, "kind": "plain"},
			{"id": "x5", "s": 3600.0, "number": 5, "kind": "lot"}, {"id": "x6", "s": 4400.0, "number": 6, "kind": "tunnel"},
			{"id": "x7", "s": 5200.0, "number": 7, "kind": "stop"}, {"id": "x8", "s": 6000.0, "number": 8, "kind": "plain"},
			{"id": "x9", "s": 6800.0, "number": 9, "kind": "plain"}, {"id": "x10", "s": 7600.0, "number": 10, "kind": "plain"},
			{"id": "x11", "s": 8400.0, "number": 11, "kind": "plain"}, {"id": "x12", "s": 9200.0, "number": 12, "kind": "plain"},
			{"id": "x13", "s": 10000.0, "number": 13, "kind": "plain"}, {"id": "x14", "s": 10800.0, "number": 14, "kind": "plain"},
			{"id": "x15", "s": 11600.0, "number": 15, "kind": "plain"}, {"id": "x16", "s": 12400.0, "number": 16, "kind": "plain"},
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
## Chunks kept straight and level either side of a crossing's own.
const PIN_APPROACH := 1

# ---------- ring sites (R1) ----------
#
# Everything about a ring site is the same on both sides of the road and
# either way along it, so it is described by `k`, a chunk's offset from the
# ring chunk (the chunk that STARTS at the ring's centre; the centre is on a
# chunk join):
#
#   k -8 .. -5   the slip lane before the ring: an extra lane outside the
#                outside lane, opening over two chunks (AUX_W wide by k = -6);
#   k -4 .. -1   ramps: the lane leaves the road at the gore (the start of
#                k = -4, RING_GORE before the centre) and climbs to the pad;
#   k  0 ..  3   ramps down again, joining the road at the end of k = 3;
#   k  4 ..  7   the slip lane after, closing over the last two chunks.
#
# On the +1 carriageway (driven the way the chunks count) the first half is
# the exit and the second the way back on; on the -1 carriageway it is the
# other way round. So each exit comes RING_GORE before the ring in its own
# direction, and each side's two ramps stand on that side of the road.

## The gore (where a ramp leaves or joins the road), metres from the ring's centre.
const RING_GORE := 200.0
## Chunks either side of the centre with ramps beside the road.
const RAMP_CHUNKS := 4
## Chunks of slip lane beyond those, and how many of them it opens over.
const AUX_CHUNKS := 4
const AUX_TAPER := 2
## Width of the slip lane (and of a ramp's deck), m.
const AUX_W := 4.4
## A signed U-turn at the start of every district, this far in, except where
## a crossing stands within GAP_CLEAR_OF_CROSSING of it.
const GAP_INSET := 25.0
const GAP_CLEAR_OF_CROSSING := 100.0
## Pin values (pins()): straight and level, or level only (the road may bend).
const PIN_STRAIGHT := 1
const PIN_LEVEL := 2

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
static var _rings: Array = []
static var _ring_of := PackedInt32Array()   # per lap chunk: index into _rings, -1 = none
static var _ring_k := PackedInt32Array()    # per lap chunk: its offset k from that ring's chunk
static var _held := PackedByteArray()       # per lap chunk: a crossing's chunk or a neighbour
static var _exit_signs := {}                # lap chunk -> [{side, ring, far}]
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
	_rings = []
	_ring_of = PackedInt32Array()
	_ring_k = PackedInt32Array()
	_held = PackedByteArray()
	_exit_signs = {}
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
	# A crossing just inside each end of every city area that has no ring site.
	for n in ds.size():
		var prev: Dictionary = ds[posmod(n - 1, ds.size())]
		var next: Dictionary = ds[posmod(n + 1, ds.size())]
		if ds[n].area != "city":
			continue
		for at in [float(_starts[n]) * L + JUNCTION_INSET if prev.area != "city" else -1.0,
				float(_starts[n] + int(ds[n].chunks)) * L - JUNCTION_INSET if next.area != "city" else -1.0]:
			if at >= 0.0 and _crossing_allowed(road, at, float(period) * L):
				_junctions.append(at)
	# Rings, exits and gaps on the part of the road this act has; straight,
	# level road at each and at the crossings.
	_pins.resize(period)
	_gap_chunk.resize(period)
	_held.resize(period)
	_ring_of.resize(period)
	_ring_k.resize(period)
	_ring_of.fill(-1)
	for c in _junctions:
		_pin(floori(c / L), PIN_APPROACH)
		for i in range(-1, 2):
			_held[posmod(floori(c / L) + i, period)] = 1
	for r in road.rings:
		if float(r.s) >= length() or String(r.kind) == "tunnel":
			continue
		var ri := _rings.size()
		_rings.append(r)
		var rc := floori(float(r.s) / L)
		for k in range(-RAMP_CHUNKS - AUX_CHUNKS, RAMP_CHUNKS + AUX_CHUNKS):
			_ring_of[posmod(rc + k, period)] = ri
			_ring_k[posmod(rc + k, period)] = k
		# the pad (the ring, from R2) on straight, level road; the ramps on level road
		for k in range(-2, 2):
			_pins[posmod(rc + k, period)] = PIN_STRAIGHT
		for k in [-4, -3, 2, 3]:
			if _pins[posmod(rc + k, period)] == 0:
				_pins[posmod(rc + k, period)] = PIN_LEVEL
		for side in [1, -1]:
			_exits.append({"id": "%s%s" % [r.id, "a" if side > 0 else "b"], "s": float(r.s) - float(side) * RING_GORE,
				"side": side, "number": int(r.number), "ring": String(r.id), "centre": float(r.s)})
			# its two gantries stand 400 m and 1 km before the gore
			for far in [false, true]:
				var chunks := roundi((1000.0 if far else 400.0) / L)
				var at := posmod(rc - RAMP_CHUNKS - chunks if side > 0 else rc + RAMP_CHUNKS + chunks - 1, period)
				if not _exit_signs.has(at):
					_exit_signs[at] = []
				_exit_signs[at].append({"side": side, "ring": ri, "far": far})
	for n in ds.size():
		var gs := float(_starts[n]) * L + GAP_INSET
		var clear := true
		for c in _junctions:
			if absf(fposmod(c - gs + length() * 0.5, length()) - length() * 0.5) < GAP_CLEAR_OF_CROSSING:
				clear = false
		if clear:
			_gaps.append({"id": "g%d" % (n + 1), "s": gs})
			_gap_chunk[floori(gs / L)] = 1
			_pin(floori(gs / L), 0)
	var pts: Array = road.map
	_map_len.append(0.0)
	for i in pts.size():
		_map_len.append(_map_len[i] + (pts[(i + 1) % pts.size()] as Vector2).distance_to(pts[i]))

## Whether a crossing wanted at `at` gets built. Not beside a ring site
## (Roy, 2026-10-11): a crossing belongs where an exit's ramp meets the
## street, and there that is the ring itself, so the highway has no signals
## and the slip lanes keep their full length. A district with no ring (the
## tunnel) keeps its crossing.
static func _crossing_allowed(road: Dictionary, at: float, lap: float) -> bool:
	var reach := float(RAMP_CHUNKS + AUX_CHUNKS) * L
	for r in road.rings:
		if float(r.s) >= lap or String(r.kind) == "tunnel":
			continue
		if at >= float(r.s) - reach and at < float(r.s) + reach:
			return false
	return true

static func _pin(chunk: int, approach: int) -> void:
	for i in range(chunk - approach, chunk + approach + 1):
		_pins[posmod(i, period)] = PIN_STRAIGHT

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

## Exits on the road in this act: [{id, s, side, number, ring, centre}], two
## per ring site. s = the gore: RING_GORE before the ring's centre on the +1
## carriageway (side 1, id "<ring>a"), RING_GORE after it on the -1 one (side
## -1, id "<ring>b"), which is "before" for the traffic on that side.
static func exits() -> Array:
	return _exits

## Gaps in the centre barrier in this act: [{id, s}]: signed U-turns, legal
## for everyone, one at the start of each district.
static func gaps() -> Array:
	return _gaps

## Ring sites on the road in this act: [{id, s, number, kind}] (no tunnels).
static func rings() -> Array:
	return _rings

## The ring site whose ramps or slip lanes run beside this chunk: an index
## into rings(), or -1.
static func ring_at(chunk_index: int) -> int:
	return _ring_of[lap_chunk(chunk_index)] if period > 0 else -1

## That chunk's offset k from the ring's own chunk (see "ring sites" above).
## Only meaningful where ring_at() is not -1.
static func ring_k(chunk_index: int) -> int:
	return _ring_k[lap_chunk(chunk_index)] if period > 0 else 0

## What the ring leads to: "stop", "lot", "landmark" or "plain".
static func ring_kind(ring: int) -> String:
	return String(_rings[ring].kind)

## Whether ramps (or the pad) stand beside this chunk: no buildings, no kerb,
## and the out-of-bounds wall moves out past them.
static func ramp_zone(chunk_index: int) -> bool:
	if period <= 0:
		return false
	var m := lap_chunk(chunk_index)
	return _ring_of[m] >= 0 and _ring_k[m] >= -RAMP_CHUNKS and _ring_k[m] < RAMP_CHUNKS

## Width of the slip lane at the join `offset` chunks from a ring's chunk
## (the join at the START of chunk k is offset k), before crossings are
## taken into account.
static func _aux_plan(offset: int) -> float:
	var d := absi(offset)
	if d < RAMP_CHUNKS or d >= RAMP_CHUNKS + AUX_CHUNKS:
		return 0.0
	return AUX_W * clampf(float(RAMP_CHUNKS + AUX_CHUNKS - d) / float(AUX_TAPER), 0.0, 1.0)

## Width of the slip lane at the start and at the end of a chunk, m (x, y);
## the same on both carriageways. Zero through a crossing's chunk and its
## neighbours (the crossing is built for the plain road), so where a crossing
## stands on a slip lane's length the lane opens after it, in one chunk.
## The ramp chunks themselves have none: the lane has left the road.
static func aux(chunk_index: int) -> Vector2:
	if period <= 0:
		return Vector2.ZERO
	var m := lap_chunk(chunk_index)
	if _ring_of[m] < 0 or _held[m] == 1:
		return Vector2.ZERO
	var k := _ring_k[m]
	if k >= -RAMP_CHUNKS and k < RAMP_CHUNKS:
		return Vector2.ZERO
	var a := _aux_plan(k)
	var b := _aux_plan(k + 1)
	if _held[posmod(m - 1, period)] == 1:
		a = 0.0
	if _held[posmod(m + 1, period)] == 1:
		b = 0.0
	return Vector2(a, b)

## The exit gantries that stand in this chunk: [{side, ring, far}], side +1
## for the carriageway driven the way the chunks count; far = the 1 km one
## (else 400 m). Empty on most chunks.
static func exit_signs(chunk_index: int) -> Array:
	return _exit_signs.get(lap_chunk(chunk_index), []) if period > 0 else []

## The ring site nearest `s` metres along the road: {index (into rings()), s
## (its centre, on the same lap as s or the one before or after)}. index -1
## when there is none.
static func ring_near(s: float) -> Dictionary:
	if _rings.is_empty():
		return {"index": -1, "s": INF}
	var lap := length()
	var m := fposmod(s, lap)
	var best := INF
	var which := -1
	for i in _rings.size():
		var d := fposmod(float(_rings[i].s) - m + lap * 0.5, lap) - lap * 0.5
		if absf(d) < absf(best):
			best = d
			which = i
	return {"index": which, "s": s + best}

## Which side a ring's spur leaves on: +1 / -1 for a "stop" (its STOPS exit's
## side) or +1 for a "lot"; 0 = no spur.
static func ring_spur_side(ring: int) -> int:
	var kind := String(_rings[ring].kind)
	if kind == "lot":
		return 1
	if kind != "stop":
		return 0
	for st in STOPS:
		if int(st.road) == road_id and String(st.exit).trim_suffix("a").trim_suffix("b") == String(_rings[ring].id):
			return 1 if String(st.exit).ends_with("a") else -1
	return 1

## Whether a stop (STOPS) hangs off this ring.
static func ring_has_stop(ring: int) -> bool:
	for st in STOPS:
		if int(st.road) == road_id and String(st.exit).trim_suffix("a").trim_suffix("b") == String(_rings[ring].id):
			return true
	return false

## Whether the centre barrier is open for the whole of this chunk (a gap).
static func gap_in(chunk_index: int) -> bool:
	return period > 0 and _gap_chunk[lap_chunk(chunk_index)] == 1

## One byte per chunk of the lap: PIN_STRAIGHT = straight and level whatever
## the night's seed, PIN_LEVEL = level, but free to bend (RoadAlignment).
static func pins() -> PackedByteArray:
	return _pins

## An exit of road `id` by its exit id ({} if there is none).
static func exit_of(id: int, exit_id: String) -> Dictionary:
	if ROADS.has(id):
		for r in ROADS[id].rings:
			for side in [1, -1]:
				if "%s%s" % [r.id, "a" if side > 0 else "b"] == exit_id and String(r.kind) != "tunnel":
					return {"id": exit_id, "s": float(r.s) - float(side) * RING_GORE, "side": side,
						"number": int(r.number), "ring": String(r.id), "centre": float(r.s)}
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
