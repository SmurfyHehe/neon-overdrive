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
#
# Eased (2026-10-10, road bumps): a vertical bend that switches on all at once
# at a chunk's start throws the car's weight on or off its springs in one
# step (0.8 g at 200 km/h into a 400 m sag), which reads as a bump. So the
# bend rate now ramps from one chunk's value to the next's over EASE metres
# centred on the join, the way a real road's vertical curve is spiralled in.
# That is the same as averaging the stepped profile over a sliding EASE-metre
# window, so no grade is steeper and no crest or sag tighter than before, and
# the road sits within a couple of centimetres of where the same seed put it.
# The plain formula above still holds in the middle of a chunk; height_at(),
# grade_at() and rise() are the eased truth everywhere.
#
# A loop (road_map.gd, 2026-10-10): with `period` > 0 the shape repeats every
# `period` chunks, in both directions (chunks before 0 are the end of the lap
# before, not straight). The first lap is rolled as usual, except that its
# last few chunks steer the heading and the grade back to where chunk 0
# started, and the whole lap is tilted by a constant grade (well under 1 %)
# so it ends at the height it began. Each lap then sits one lap's length
# further down the world from the last; nothing wraps in space.

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
## Metres over which the vertical bend rate changes from one chunk's to the
## next's, centred on the join. Must stay under the chunk length. 40 m was
## tried (2026-10-10) and measured no better in tests/world/hill_bumps.gd,
## for more collision and strip pieces on the chunks either side.
const EASE := 10.0
## A loop's last chunks: these many turn the heading back to 0 (30 degrees at
## MIN_RADIUS takes four), and these many level the grade (one, at 1000 m).
const CLOSE_CHUNKS := 6
const CLOSE_VCHUNKS := 2

## 0 = a straight road, 1 = mostly bends. Share of segments that are bends.
var curviness := 0.5
## 0 = flat, 1 = rolling the whole way. Share of vertical segments that are
## crests or sags rather than a steady grade.
var hilliness := 0.0
## Chance a crest is a kicker (KICKER_RADIUS_*). 0 outside the R6 playtest.
var kicker_chance := 0.0
## Chunks in one lap of a loop; 0 = an endless road.
var period := 0
var _closed := false

var _rng := RandomNumberGenerator.new()
var _k := PackedFloat64Array()    # curvature of chunk i
var _psi := PackedFloat64Array([0.0])  # heading at the start of chunk i
var _px := PackedFloat64Array([0.0])   # start position of chunk i, world-absolute x
var _pz := PackedFloat64Array([0.0])   # ... and z
var _seg_k := 0.0
var _seg_left := 0
var _vrng := RandomNumberGenerator.new()
var _vc := PackedFloat64Array()        # vertical curvature of chunk i
# The stepped profile the hills are rolled on (height and grade at the start
# of chunk i before easing), then what easing makes of it:
var _h := PackedFloat64Array([0.0])
var _g := PackedFloat64Array([0.0])
var _dc := PackedFloat64Array()        # change of vertical curvature entering chunk i
var _h0 := PackedFloat64Array()        # eased height at the start of chunk i
var _g0 := PackedFloat64Array()        # eased grade at the start of chunk i
var _lift := 0.0  # height the easing has added up to the newest chunk
var _vseg_target := 0.0  # grade the current vertical segment is heading for
var _vseg_c := 0.0
var _vseg_left := 0

func _init(seed_value: int, curviness_value: float, hilliness_value: float = 0.0, kicker_value: float = 0.0, period_value: int = 0) -> void:
	period = maxi(period_value, 0)
	_rng.seed = seed_value
	_vrng.seed = seed_value ^ 0x5EED_4111
	curviness = clampf(curviness_value, 0.0, 1.0)
	hilliness = clampf(hilliness_value, 0.0, 1.0)
	kicker_chance = clampf(kicker_value, 0.0, 1.0)

## Whether the road ever leaves y = 0 (game.gd keeps the flat ground plane
## when it does not).
func has_hills() -> bool:
	return hilliness > 0.0

## A loop: chunk i's place on the lap (the lap is rolled on first use).
func _at(i: int) -> int:
	if not _closed:
		_close()
	return posmod(i, period)

func _close() -> void:
	_closed = true
	_ensure(period - 1)
	# End at the height it began: tilt the lap by a constant grade.
	var tilt := _h[period] / (float(period) * L)
	for j in period + 1:
		_g[j] -= tilt
		_h[j] -= tilt * float(j) * L

func vcurve(i: int) -> float:
	if period > 0:
		return _vc[_at(i)]
	if i < 0:
		return 0.0
	_ensure(i)
	return _vc[i]

func start_height(i: int) -> float:
	if period > 0:
		return _h[_at(i)]
	if i < 0:
		return 0.0
	_ensure(i)
	return _h0[i]

func start_grade(i: int) -> float:
	if period > 0:
		return _g[_at(i)]
	if i < 0:
		return 0.0
	_ensure(i)
	return _g0[i]

## How much the vertical curvature changes going into chunk i
## (vcurve(i) - vcurve(i - 1)): the step the easing spreads over EASE metres
## around the chunk's start.
func vstep(i: int) -> float:
	if i < 0:
		return 0.0
	_ensure(i)
	return _dc[i]

## Height of the road above the start of chunk i, s metres into it.
func rise(i: int, s: float) -> float:
	if i < -1:
		return 0.0
	_ensure(i + 1)
	if i < 0:
		return ease_rise(0.0, 0.0, 0.0, _dc[0], s)
	return ease_rise(_g0[i], _vc[i], _dc[i], _dc[i + 1], s)

## Height and grade at distance s into chunk i.
func height_at(i: int, s: float) -> float:
	return start_height(i) + rise(i, s)

func grade_at(i: int, s: float) -> float:
	if i < -1:
		return 0.0
	_ensure(i + 1)
	if i < 0:
		return ease_grade(0.0, 0.0, 0.0, _dc[0], s)
	return ease_grade(_g0[i], _vc[i], _dc[i], _dc[i + 1], s)

# One chunk's eased vertical profile: start grade g0, its own curvature c,
# and the curvature steps at its start (dc_in) and end (dc_out). A step of 1
# at t = 0, spread into a ramp from -EASE/2 to +EASE/2, changes the grade by
# _ease_g(t) and the height by _ease_h(t) compared with the plain step.

static func _ease_g(t: float) -> float:
	var e := EASE * 0.5
	if t <= -e or t >= e:
		return 0.0
	var d := t + e if t < 0.0 else t - e
	return d * d / (2.0 * EASE)

static func _ease_h(t: float) -> float:
	var e := EASE * 0.5
	if t <= -e:
		return 0.0
	if t >= e:
		return EASE * EASE / 24.0
	if t < 0.0:
		return (t + e) * (t + e) * (t + e) / (6.0 * EASE)
	return (2.0 * e * e * e + (t - e) * (t - e) * (t - e)) / (6.0 * EASE)

static func ease_rise(g0: float, c: float, dc_in: float, dc_out: float, s: float) -> float:
	var y := g0 * s + 0.5 * c * s * s
	if dc_in != 0.0:
		y += dc_in * (_ease_h(s) - EASE * EASE / 48.0 - EASE / 8.0 * s)
	if dc_out != 0.0:
		y += dc_out * _ease_h(s - L)
	return y

static func ease_grade(g0: float, c: float, dc_in: float, dc_out: float, s: float) -> float:
	var g := g0 + c * s
	if dc_in != 0.0:
		g += dc_in * (_ease_g(s) - EASE / 8.0)
	if dc_out != 0.0:
		g += dc_out * _ease_g(s - L)
	return g

func curvature(i: int) -> float:
	if period > 0:
		return _k[_at(i)]
	if i < 0:
		return 0.0
	_ensure(i)
	return _k[i]

func start_heading(i: int) -> float:
	if period > 0:
		return _psi[_at(i)]
	if i < 0:
		return 0.0
	_ensure(i)
	return _psi[i]

## World-absolute start of chunk i (x, z), as 64-bit floats.
func start_x(i: int) -> float:
	if period > 0:
		var m := _at(i)
		@warning_ignore("integer_division")
		return _px[m] + float((i - m) / period) * _px[period]
	if i < 0:
		return 0.0
	_ensure(i)
	return _px[i]

func start_z(i: int) -> float:
	if period > 0:
		var m := _at(i)
		@warning_ignore("integer_division")
		return _pz[m] + float((i - m) / period) * _pz[period]
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
	if period > 0 and i >= period - CLOSE_CHUNKS:
		k = clampf(-psi / L, -1.0 / MIN_RADIUS, 1.0 / MIN_RADIUS)
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
		if period > 0 and i >= period - CLOSE_VCHUNKS:
			c = clampf(-g / L, -1.0 / CREST_MIN_RADIUS, 1.0 / SAG_MIN_RADIUS)
	_vc.append(c)
	# Eased start of this chunk: half of its own curvature step is behind it.
	var dc := c - (_vc[i - 1] if i > 0 else 0.0)
	_dc.append(dc)
	_h0.append(_h[i] + _lift + dc * EASE * EASE / 48.0)
	_g0.append(g + dc * EASE / 8.0)
	_lift += dc * EASE * EASE / 24.0
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
