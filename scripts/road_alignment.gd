extends RefCounted
class_name RoadAlignment

# The road's shape (#37 curves, step R3; plan in
# docs/planning/curves-elevation-proposal-2026-10-07.md): one constant
# curvature per 50 m chunk, rolled from a seed in runs of straights and bends.
# Chunk i is a circular arc of curvature curvature(i) (1/m, + = bending left)
# starting at start_pos(i) with heading start_heading(i) (radians about world
# up, 0 = down world -Z). Each chunk's Path3D centreline is a Bezier fitted to
# its arc (RoadChunkBuilder), and RoadFrame answers "where along the road am
# I" from the arcs directly, so the two agree to well under a millimetre.
#
# Limits (Roy's sign-off on #165): no bend tighter than MIN_RADIUS, and the
# heading never more than MAX_HEADING off -Z, so the road never doubles back
# or crosses itself. Chunks before 0 are straight.
#
# The same seed always gives the same road, whatever order chunks are asked
# for in: the sequence is generated from chunk 0 forward and cached.

const L := RoadChunkBuilder.CHUNK_LEN
const MIN_RADIUS := 300.0
const MAX_RADIUS := 1500.0
const MAX_HEADING := deg_to_rad(30.0)
## Past this share of MAX_HEADING a new bend always turns back toward 0.
const RETURN_SHARE := 0.5

## 0 = a straight road, 1 = mostly bends. Share of segments that are bends.
var curviness := 0.5

var _rng := RandomNumberGenerator.new()
var _k := PackedFloat64Array()    # curvature of chunk i
var _psi := PackedFloat64Array([0.0])  # heading at the start of chunk i
var _px := PackedFloat64Array([0.0])   # start position of chunk i, world-absolute x
var _pz := PackedFloat64Array([0.0])   # ... and z
var _seg_k := 0.0
var _seg_left := 0

func _init(seed_value: int, curviness_value: float) -> void:
	_rng.seed = seed_value
	curviness = clampf(curviness_value, 0.0, 1.0)

func curvature(i: int) -> float:
	if i < 0:
		return 0.0
	_ensure(i)
	return _k[i]

func start_heading(i: int) -> float:
	if i < 0:
		return 0.0
	_ensure(i)
	return _psi[i]

## World-absolute start of chunk i (x, z), as 64-bit floats.
func start_x(i: int) -> float:
	if i < 0:
		return 0.0
	_ensure(i)
	return _px[i]

func start_z(i: int) -> float:
	if i < 0:
		return -float(i) * L
	_ensure(i)
	return _pz[i]

func _ensure(i: int) -> void:
	while _k.size() <= i:
		_extend()

func _extend() -> void:
	if _seg_left <= 0:
		_new_segment()
	_seg_left -= 1
	var i := _k.size()
	var psi := _psi[i]
	var k := _seg_k
	# Keep the heading inside the limit: shorten the turn at the edge.
	var end := psi + k * L
	if absf(end) > MAX_HEADING:
		k = (signf(end) * MAX_HEADING - psi) / L
	_k.append(k)
	var e := arc_point(k, L).rotated(Vector3.UP, psi)
	_psi.append(psi + k * L)
	_px.append(_px[i] + e.x)
	_pz.append(_pz[i] + e.z)

func _new_segment() -> void:
	if _rng.randf() >= curviness:
		_seg_k = 0.0
		_seg_left = _rng.randi_range(2, 6)
		return
	var r := _rng.randf_range(MIN_RADIUS, MAX_RADIUS)
	var psi := _psi[_k.size()]
	var s := -1.0 if _rng.randf() < 0.5 else 1.0
	if absf(psi) > MAX_HEADING * RETURN_SHARE:
		s = -signf(psi)
	_seg_k = s / r
	_seg_left = _rng.randi_range(2, 8)

# ---------- one chunk's arc, in the chunk's own frame ----------
# Start at the origin heading -Z, x to the right.

## Point at distance s along an arc of curvature k.
static func arc_point(k: float, s: float) -> Vector3:
	if absf(k) < 1e-9:
		return Vector3(0.0, 0.0, -s)
	var r := 1.0 / k
	return Vector3(-r + r * cos(k * s), 0.0, -r * sin(k * s))

## Heading change after distance s (radians, + = left).
static func arc_heading(k: float, s: float) -> float:
	return k * s

## (s, d): distance along the arc and signed distance to its right, for a
## point in the chunk's frame. s is not clamped to the chunk.
static func arc_project(k: float, p: Vector3) -> Vector2:
	if absf(k) < 1e-9:
		return Vector2(-p.z, p.x)
	var r := 1.0 / k
	# Centre of the turn at (-r, 0, 0); p relative to it, scaled by r so the
	# angle comes out right for both directions.
	var vx := (p.x + r) / r
	var vz := p.z / r
	var s := atan2(-vz, vx) / k
	# In 64-bit floats: r can be tens of km on a nearly straight chunk (the
	# tail of a bend cut short at MAX_HEADING), where a Vector2's 32 bits
	# would lose millimetres.
	var cx := float(p.x) + r
	var cz := float(p.z)
	var dist := sqrt(cx * cx + cz * cz)
	return Vector2(s, signf(k) * (dist - absf(r)))

## Bezier handle length that makes a cubic fit a circular arc of curvature k
## over length l (4/3 tan(theta/4) r; l/3 on a straight).
static func bezier_handle(k: float, l: float) -> float:
	if absf(k) < 1e-9:
		return l / 3.0
	var theta := k * l
	return absf(4.0 / 3.0 * tan(theta / 4.0) / k)
