## Where every small roadside thing stands (breakable world, I0).
##
## Posts, cones, bins, hydrants, lamp posts and sign posts are copies in a
## MultiMesh: there is nothing to ask "what is standing here". The chunk
## builder therefore writes one record per prop into the chunk's "props" meta
## while it lays them out, and this file is the only reader:
##
##   kind  PackedInt32Array    one of the KINDS below
##   pos   PackedVector3Array  the foot, in the chunk's own space (through the
##                             centreline frame, so it is right on a bend)
##   slot  PackedInt32Array    instance index in that kind's MultiMesh
##   side  PackedInt32Array    1 own side, -1 oncoming
##   road  PackedVector2Array  the straight-road spot: x across (signed), z
##                             along (0 .. -CHUNK_LEN); the prop's identity
##
## near() answers "which props is this car's box over right now" from a 5 m
## bucket table built once per chunk, so a tick costs a handful of distance
## checks whatever the chunk holds.
##
## No class_name on purpose: preload it, so no class cache refresh is needed.
extends RefCounted

enum { POST, CONE, BIN, HYDRANT, LAMP, SIGN, GANTRY }
const NAMES := ["post", "cone", "bin", "hydrant", "lamp", "sign", "gantry"]

## How a kind answers a hit (design: docs/design/world/breakable-props).
## GIVES flies or bends and costs nothing; BREAKAWAY breaks for the night;
## GHOST is a thing the car still passes through (listed by the audit only).
enum { GIVES, BREAKAWAY, GHOST }
const CLASS := [GIVES, GIVES, GIVES, BREAKAWAY, BREAKAWAY, BREAKAWAY, GHOST]
## Touch radius in metres (the prop's footprint, not its height).
const RADIUS := [0.08, 0.2, 0.27, 0.16, 0.12, 0.08, 0.3]

## Tools: off writes an empty record (tools/prop_cost.gd times both).
static var enabled := true

const BUCKET := 5.0
const CHUNK_LEN := 50.0
const N_BUCKETS := 10

## The builder's scratch record for one chunk; write() turns it into the meta.
static func begin() -> Dictionary:
	return {"kind": PackedInt32Array(), "pos": PackedVector3Array(), "slot": PackedInt32Array(),
		"side": PackedInt32Array(), "road": PackedVector2Array()}

static func add(rec: Dictionary, kind: int, pos: Vector3, slot: int, side: int, road_x: float, road_z: float) -> void:
	if not enabled:
		return
	rec.kind.append(kind)
	rec.pos.append(pos)
	rec.slot.append(slot)
	rec.side.append(side)
	rec.road.append(Vector2(road_x, road_z))

## Stores the record on the chunk with its bucket table: buckets[b] lists the
## props whose road z falls in 5 m slice b.
static func write(root: Node3D, rec: Dictionary) -> void:
	var buckets := []
	buckets.resize(N_BUCKETS)
	for b in N_BUCKETS:
		buckets[b] = PackedInt32Array()
	var road: PackedVector2Array = rec.road
	for i in road.size():
		var b := clampi(int(-road[i].y / BUCKET), 0, N_BUCKETS - 1)
		buckets[b].append(i)
	rec["buckets"] = buckets
	root.set_meta("props", rec)

static func of(root: Node3D) -> Dictionary:
	return root.get_meta("props", {})

static func count(root: Node3D, kind: int) -> int:
	var rec := of(root)
	if rec.is_empty():
		return 0
	return (rec.kind as PackedInt32Array).count(kind)

## Appends to `out` the indices of the chunk's props under a car's box.
## `to_car` takes chunk space to the car's own space (car_inverse * chunk
## transform); the box is half_w wide either side, from `front` metres ahead
## of the car's origin (pass the nose plus this tick's travel, so nothing is
## skipped at speed) to `back` metres behind it. `car_z` is the car's place
## along the chunk on the straight road (0 .. -CHUNK_LEN), which picks the
## buckets, and `car_x` its place across it, which throws out everything on
## the far kerb before any vector maths; `skip` (same size as the record)
## marks props that are gone.
static func near(rec: Dictionary, to_car: Transform3D, car_x: float, car_z: float, half_w: float, front: float, back: float,
		skip: PackedByteArray, out: PackedInt32Array) -> void:
	if rec.is_empty():
		return
	var buckets: Array = rec.buckets
	var pos: PackedVector3Array = rec.pos
	var kind: PackedInt32Array = rec.kind
	var road: PackedVector2Array = rec.road
	var reach := maxf(front, back) + 1.0
	var b0 := clampi(int((-car_z - reach) / BUCKET), 0, N_BUCKETS - 1)
	var b1 := clampi(int((-car_z + reach) / BUCKET), 0, N_BUCKETS - 1)
	if -car_z + reach < 0.0 or -car_z - reach > CHUNK_LEN:
		return
	for b in range(b0, b1 + 1):
		var list: PackedInt32Array = buckets[b]
		for i in list:
			if absf(road[i].x - car_x) > reach:
				continue  # across the road from the car, however it is turned
			if not skip.is_empty() and skip[i] != 0:
				continue
			var p := to_car * pos[i]
			var r: float = RADIUS[kind[i]]
			if absf(p.x) > half_w + r or p.z < -front - r or p.z > back + r:
				continue
			out.append(i)
