extends RefCounted
class_name RoadFrame

# Road space (#37 curves and elevation, steps R1 and R3; plan in
# docs/planning/curves-elevation-proposal-2026-10-07.md).
#
# Road space is the road unrolled straight: x is across the road (lane
# offsets, own lanes at +x, RoadChunkBuilder.lane_offset), y is up from the
# road surface, z is along it with forward = -z, in the same units and the
# same floating-origin frame as world z on today's straight road. Everything
# that reasons in lanes and "metres ahead" (traffic, the chunk pool, the
# benchmark bot) reads positions through unroll() and writes poses through
# pose(), so it never assumes the road runs down world -Z.
#
# The road's shape comes from `align` (RoadAlignment, step R3): chunk i is a
# circular arc, placed in the world relative to the floating origin's chunk
# `origin_index` (game.gd keeps both up to date). With no alignment the road
# is straight and every function here is the identity, exactly as in step R1;
# tests that build chunks without a game see that.

const L := RoadChunkBuilder.CHUNK_LEN
## Steps unroll() takes to find the chunk a point is in. Each step jumps by
## the point's distance along the current chunk's direction, which is at
## least half the true distance (the heading stays within 30 deg of -Z, so
## two chunks are never more than 60 deg apart): even a car parked 10 km
## behind is found in about 8.
const SEARCH_STEPS := 24
## Furthest from the centre line a point counts as beside a chunk, m: well
## past the out-of-bounds walls (about 16 m out).
const BESIDE := 100.0
## How far past a chunk's ends a point may read and still count as in it, m.
const EDGE_SLACK := 0.01

## The road's shape; null = straight.
static var align: RoadAlignment
## The chunk whose start sits at the world origin (game.gd's floating origin).
static var origin_index := 0
## Lane counts, median and exits along the road (RoadLayout, road lane
## proposal step 1); null = the plain 4+4 road.
static var layout: RoadLayout

## Metres along the road from the start of chunk 0 for road-space z: what
## RoadLayout is keyed by, independent of the floating origin.
static func s_at(z: float) -> float:
	return float(origin_index) * L - z

## World transform of chunk i's start: on the centre line, -Z along the road.
## Cached per chunk for the current origin (perf, 2026-10-09): roll() and
## pose() run it for every traffic car every tick, and rebuilding it from
## RoadAlignment's arrays was most of their cost. RoadAlignment only ever
## appends chunks, so a chunk's transform cannot change until the origin
## moves or the road is replaced, which drop the cache (_check_caches).
static func chunk_xf(i: int, origin: int = origin_index) -> Transform3D:
	if align == null:
		return Transform3D(Basis.IDENTITY, Vector3(0, 0, -float(i - origin) * L))
	if origin != origin_index:
		return _chunk_xf_uncached(i, origin)
	_check_caches()
	var xf: Variant = _xf_cache.get(i)
	if xf == null:
		xf = _chunk_xf_uncached(i, origin)
		_xf_cache[i] = xf
	return xf

static func _chunk_xf_uncached(i: int, origin: int) -> Transform3D:
	# Absolute positions are 64-bit; subtract before they become a Vector3.
	# Turned only about world up: the chunk's slope lives in its centreline.
	return Transform3D(Basis(Vector3.UP, align.start_heading(i)),
		Vector3(align.start_x(i) - align.start_x(origin), align.start_height(i) - align.start_height(origin), align.start_z(i) - align.start_z(origin)))

## Curvature of chunk i, 1/m, + = bending left (0 on a straight road).
static func curvature(i: int) -> float:
	return 0.0 if align == null else align.curvature(i)

## Grade at the start of chunk i (rise per metre) and its vertical curvature
## (1/m, + = sag): the middle of the chunk's surface is start_grade s +
## vcurve s^2 / 2 above its start, and the curvature eases to the next
## chunk's over RoadAlignment.EASE metres around each join (vstep(i) is the
## change going into chunk i). 0 on a flat road.
static func start_grade(i: int) -> float:
	return 0.0 if align == null else align.start_grade(i)

static func vcurve(i: int) -> float:
	return 0.0 if align == null else align.vcurve(i)

static func vstep(i: int) -> float:
	return 0.0 if align == null else align.vstep(i)

## Whether the road leaves y = 0 anywhere (the flat ground plane is not
## enough then; every chunk carries its own road collision).
static func has_hills() -> bool:
	return align != null and align.has_hills()

## Height of the road surface above the start of chunk i, s metres into it.
static func _rise(i: int, s: float) -> float:
	return 0.0 if align == null else align.rise(i, s)

## chunk_xf(i).affine_inverse(), cached (perf, 2026-10-08): unroll() runs
## about a hundred times a physics tick (traffic, the chunk pool, the camera)
## and building the transform from RoadAlignment's arrays then inverting it
## was most of its cost. Same transform, computed once per chunk; the cache is
## dropped whenever the floating origin moves or the road is replaced.
##
## unroll() itself is memoised per physics tick on the exact input position:
## a traffic car asks about its own position several times a tick (the
## follower, the bend look-ahead, the spawner, the occupancy index), and the
## answer cannot change until the next tick moves it. Exact Vector3 keys, so
## the result is the same bits the full search would return.
static var _inv_cache := {}
static var _xf_cache := {}  # chunk_xf(i), see there
static var _inv_origin := 0
static var _inv_align: RoadAlignment = null
static var _memo := {}
static var _memo_tick := -1

## Drops both caches when the floating origin moves or the road is replaced.
static func _check_caches() -> void:
	if _inv_origin != origin_index or _inv_align != align:
		_inv_cache.clear()
		_xf_cache.clear()
		_memo.clear()
		_inv_origin = origin_index
		_inv_align = align

static func _inv_xf(i: int) -> Transform3D:
	var xf: Variant = _inv_cache.get(i)
	if xf == null:
		xf = chunk_xf(i).affine_inverse()
		_inv_cache[i] = xf
	return xf

## World position -> road space.
static func unroll(p: Vector3) -> Vector3:
	if align == null:
		return p
	_check_caches()
	var tick := Engine.get_physics_frames()
	if tick != _memo_tick:
		_memo.clear()
		_memo_tick = tick
	var hit: Variant = _memo.get(p)
	if hit != null:
		return hit
	var u := _unroll_uncached(p)
	_memo[p] = u
	return u

static func _unroll_uncached(p: Vector3) -> Vector3:
	var i := origin_index + floori(-p.z / L)
	var local := Vector3.ZERO
	var sd := Vector2.ZERO
	for n in SEARCH_STEPS:
		local = _inv_xf(i) * p
		sd = RoadAlignment.arc_project(align.curvature(i), local)
		# Accept the chunk only if the point is beside it: a point far away can
		# also project onto a curved chunk's circle further round.
		var beside := absf(sd.y) < BESIDE
		# EDGE_SLACK: far from the origin a point right on a join can read as
		# just behind one chunk and just past the other in float32; either
		# answer is the same place, so take it rather than flip between them.
		if beside and sd.x >= -EDGE_SLACK and sd.x < L + EDGE_SLACK:
			break
		var ahead: float = sd.x if beside else -local.z
		if ahead < 0.0:
			i += mini(-1, floori(ahead / L))
		else:
			i += maxi(1, floori(ahead / L))
	# y: up from the road surface (world up; the road has no camber).
	return Vector3(sd.y, local.y - _rise(i, sd.x), -(float(i - origin_index) * L + sd.x))

## Road space -> world position.
static func roll(u: Vector3) -> Vector3:
	if align == null:
		return u
	var i := _chunk_of(u.z)
	var s := _s_in_chunk(u.z, i)
	var k := align.curvature(i)
	var h := RoadAlignment.arc_heading(k, s)
	var local := RoadAlignment.arc_point(k, s) + Vector3(cos(h), 0.0, -sin(h)) * u.x + Vector3(0.0, _rise(i, s) + u.y, 0.0)
	return chunk_xf(i) * local

## World orientation of the road's axes at road-space z (x across, y up off
## the surface, -z forward, up or down the slope).
static func basis_at(z: float) -> Basis:
	if align == null:
		return Basis.IDENTITY
	# The heading, then the slope: nose up on a rising grade. heading_at(z)
	# inlined (same chunk, same s): this runs for every traffic car several
	# times a tick.
	var i := _chunk_of(z)
	var s := _s_in_chunk(z, i)
	var h := align.start_heading(i) + RoadAlignment.arc_heading(align.curvature(i), s)
	return Basis(Vector3.UP, h) * Basis(Vector3.RIGHT, atan(align.grade_at(i, s)))

## Road heading at road-space z, radians about world up (0 = down world -Z).
static func heading_at(z: float) -> float:
	if align == null:
		return 0.0
	var i := _chunk_of(z)
	return align.start_heading(i) + RoadAlignment.arc_heading(align.curvature(i), _s_in_chunk(z, i))

## Road curvature at road-space z, 1/m, + = bending left as you drive down
## the road (-z). 0 on a straight road.
static func curvature_at(z: float) -> float:
	return 0.0 if align == null else align.curvature(_chunk_of(z))

static func _chunk_of(z: float) -> int:
	return floori((float(origin_index) * L - z) / L)

static func _s_in_chunk(z: float, i: int) -> float:
	return float(origin_index) * L - z - float(i) * L

## A world-space direction (velocity, a basis axis) -> road space at z.
static func dir_to_road(z: float, v: Vector3) -> Vector3:
	return basis_at(z).transposed() * v

## A world basis -> road space at z.
static func basis_to_road(z: float, b: Basis) -> Basis:
	return basis_at(z).transposed() * b

## World transform of something at road-space (x, y, z), yawed by `yaw`
## relative to the road (0 = pointing down the road, PI = oncoming).
static func pose(x: float, y: float, z: float, yaw: float) -> Transform3D:
	return Transform3D(basis_at(z) * Basis(Vector3.UP, yaw), roll(Vector3(x, y, z)))
