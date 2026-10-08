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
#
# Hills (step R5): the height along the road is a separate profile, the way
# real roads are drawn: chunk i starts at height start_height(i) with grade
# start_grade(i) (rise per metre along the road) and bends vertically at a
# constant rate vcurve(i) (1/m; + = sag, - = crest), so
#   y(s) = h + g s + vcurve s^2 / 2.
# Its own random stream: changing curviness never changes the hills.

const L := RoadChunkBuilder.CHUNK_LEN
const MIN_RADIUS := 300.0
const MAX_RADIUS := 1500.0
const MAX_HEADING := deg_to_rad(30.0)
## Past this share of MAX_HEADING a new bend always turns back toward 0.
const RETURN_SHARE := 0.5

## Hills (R5). Steepest grade, and the gentlest-allowed crest and sag radii:
## a car goes light over a crest of radius R at sqrt(9.81 R) m/s, so 600 m
## keeps everything planted below ~275 km/h (only a modded car goes light);
## 400 m sags squat the suspension without bottoming it out.
const MAX_GRADE := 0.05
const CREST_MIN_RADIUS := 600.0
const SAG_MIN_RADIUS := 400.0
const VCURVE_MAX_RADIUS := 3000.0
## "Kicker" crests, for the R6 playtest preset only (kicker_chance 0 by
## default): this tight, so cars leave the ground at 140-180 km/h.
const KICKER_RADIUS_MIN := 150.0
const KICKER_RADIUS_MAX := 250.0
## Past this height either way new hills lead back toward 0, so the city
## does not climb a mountain over a long run.
const HEIGHT_SOFT_LIMIT := 30.0

## 0 = a straight road, 1 = mostly bends. Share of segments that are bends.
var curviness := 0.5
## 0 = flat, 1 = rolling the whole way. Share of vertical segments that are
## crests or sags rather than a steady grade.
var hilliness := 0.0
## Chance a crest is a kicker (KICKER_RADIUS_*). 0 outside the R6 playtest.
var kicker_chance := 0.0

var _rng := RandomNumberGenerator.new()
var _k := PackedFloat64Array()    # curvature of chunk i
var _psi := PackedFloat64Array([0.0])  # heading at the start of chunk i
var _px := PackedFloat64Array([0.0])   # start position of chunk i, world-absolute x
var _pz := PackedFloat64Array([0.0])   # ... and z
var _seg_k := 0.0
var _seg_left := 0
var _vrng := RandomNumberGenerator.new()
var _vc := PackedFloat64Array()        # vertical curvature of chunk i
var _h := PackedFloat64Array([0.0])    # height at the start of chunk i
var _g := PackedFloat64Array([0.0])    # grade at the start of chunk i
var _vseg_target := 0.0  # grade the current vertical segment is heading for
var _vseg_c := 0.0
var _vseg_left := 0

func _init(seed_value: int, curviness_value: float, hilliness_value: float = 0.0, kicker_value: float = 0.0) -> void:
	_rng.seed = seed_value
	_vrng.seed = seed_value ^ 0x5EED_4111
	curviness = clampf(curviness_value, 0.0, 1.0)
	hilliness = clampf(hilliness_value, 0.0, 1.0)
	kicker_chance = clampf(kicker_value, 0.0, 1.0)

## Whether the road ever leaves y = 0 (game.gd keeps the flat ground plane
## when it does not).
func has_hills() -> bool:
	return hilliness > 0.0

func vcurve(i: int) -> float:
	if i < 0:
		return 0.0
	_ensure(i)
	return _vc[i]

func start_height(i: int) -> float:
	if i < 0:
		return 0.0
	_ensure(i)
	return _h[i]

func start_grade(i: int) -> float:
	if i < 0:
		return 0.0
	_ensure(i)
	return _g[i]

## Height and grade at distance s into chunk i.
func height_at(i: int, s: float) -> float:
	return start_height(i) + start_grade(i) * s + 0.5 * vcurve(i) * s * s

func grade_at(i: int, s: float) -> float:
	return start_grade(i) + vcurve(i) * s

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
	_extend_vertical(i)

func _extend_vertical(i: int) -> void:
	var g := _g[i]
	var c := 0.0
	if hilliness > 0.0:
		if _vseg_left <= 0:
			_new_vertical_segment(i)
		_vseg_left -= 1
		c = _vseg_c
		# Once the grade reaches the segment's target, bend only that far and
		# hold the grade for the rest of the segment.
		if c != 0.0 and (g + c * L - _vseg_target) * signf(c) >= 0.0:
			c = (_vseg_target - g) / L
			_vseg_c = 0.0
	_vc.append(c)
	_h.append(_h[i] + g * L + 0.5 * c * L * L)
	_g.append(g + c * L)

func _new_vertical_segment(i: int) -> void:
	var g := _g[i]
	if _vrng.randf() >= hilliness:
		_vseg_c = 0.0  # hold the grade a while
		_vseg_target = g
		_vseg_left = _vrng.randi_range(2, 6)
		return
	var target := _vrng.randf_range(-MAX_GRADE, MAX_GRADE)
	var h := _h[i]
	if absf(h) > HEIGHT_SOFT_LIMIT:
		target = -signf(h) * absf(target)  # head back toward 0
	if absf(target - g) < 0.01:
		target = clampf(g - signf(g + 1e-9) * 0.03, -MAX_GRADE, MAX_GRADE)
	var crest := target < g
	var r: float
	if crest and _vrng.randf() < kicker_chance:
		r = _vrng.randf_range(KICKER_RADIUS_MIN, KICKER_RADIUS_MAX)
	else:
		r = _vrng.randf_range(CREST_MIN_RADIUS if crest else SAG_MIN_RADIUS, VCURVE_MAX_RADIUS)
	_vseg_c = (-1.0 if crest else 1.0) / r
	_vseg_target = target
	# Enough chunks to reach the target grade, plus a little held after it.
	_vseg_left = ceili(absf(target - g) * r / L) + _vrng.randi_range(1, 3)

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
