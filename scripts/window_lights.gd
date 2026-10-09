class_name WindowLights
extends RefCounted

# Building windows that follow the night clock (living world step 1,
# 2026-10-08). Every building shares one small window-grid texture as its
# emission mask (RoadChunkBuilder._building_mat), so switching windows is one
# 32x32 texture update for the whole city: no per-building work, no extra draw
# calls, nothing on the GPU but a 3 KB upload, and only when a window actually
# changes (a few times per game hour).
#
# Each window slot gets a fixed colour (mostly warm incandescent, some cool
# fluorescent) and two random ranks. A window is lit while its "bedtime" rank
# is under the evening curve (busy at 8 p.m., thinning out past midnight) or
# its "early riser" rank is under the morning curve (a few back on before 6).
# The ranks are fixed, so the same windows go dark in the same order every
# night and a window never flickers back and forth.
#
# Stage A's static texture had 32% of window slots lit (a city at midnight);
# the evening curve passes through that at midnight.

const SIZE := 32
## Evening curve: share of windows lit, by game minutes since 8 p.m.
const EVENING := [[0.0, 0.58], [120.0, 0.46], [240.0, 0.32], [360.0, 0.19], [480.0, 0.10], [600.0, 0.08]]
## Early risers: share lit again, from 4:30 a.m. to 6 a.m.
const MORNING := [[510.0, 0.0], [600.0, 0.12]]

static var _tex: ImageTexture
static var _img: Image
static var _slots: Array = []   # [{x, y, colour, bed, rise}]
static var _lit_mask := PackedByteArray()
static var _minutes := 240.0    # midnight until a clock says otherwise
# The curve values the windows were last painted for: a window's state only
# depends on them, and the clock holds them flat most of the night.
static var _painted_eve := NAN
static var _painted_morn := NAN
## How many texture uploads happened (tests read it).
static var uploads := 0

## The shared emission texture, built on first use for the current time.
static func texture() -> ImageTexture:
	if _tex == null:
		_build_slots()
		_img = Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		_lit_mask.resize(_slots.size())
		_lit_mask.fill(2)   # neither lit nor dark: forces the first paint
		_painted_eve = NAN
		_paint()
		_tex = ImageTexture.create_from_image(_img)
	return _tex

## Called by the night clock as it runs; uploads only when a window changed.
static func set_minutes(m: float) -> void:
	_minutes = m
	if _tex == null:
		return
	if _paint():
		_tex.update(_img)
		uploads += 1

static func lit_fraction_target(m: float) -> float:
	return clampf(_curve(EVENING, m) + _curve(MORNING, m), 0.0, 1.0)

## Share of window slots lit right now (tests read it).
static func lit_fraction() -> float:
	texture()
	var n := 0
	for v in _lit_mask:
		n += 1 if v == 1 else 0
	return float(n) / maxf(_slots.size(), 1.0)

static func slot_count() -> int:
	texture()
	return _slots.size()

static func is_lit(i: int) -> bool:
	texture()
	return _lit_mask[i] == 1

# Same grid as stage A: 2-pixel-wide windows every 4 pixels. Own seeded RNG so
# the pattern does not consume (or depend on) the global random sequence the
# road layout uses.
static func _build_slots() -> void:
	_slots.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2004
	var gy := 2
	while gy < 30:
		var gx := 1
		while gx < 30:
			var c := Color(1.0, 0.78, 0.45) if rng.randf() < 0.7 else Color(0.62, 0.8, 1.0)
			c = c * rng.randf_range(0.55, 1.0)
			_slots.append({"x": gx, "y": gy, "colour": c, "bed": rng.randf(), "rise": rng.randf()})
			gx += 4
		gy += 4

## Repaints the windows whose state changed; true when any did.
static func _paint() -> bool:
	var eve := _curve(EVENING, _minutes)
	var morn := _curve(MORNING, _minutes)
	if eve == _painted_eve and morn == _painted_morn:
		return false  # same curve values, same windows: skip the scan
	_painted_eve = eve
	_painted_morn = morn
	var changed := false
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		var lit := 1 if (s.bed < eve or s.rise < morn) else 0
		if _lit_mask[i] == lit:
			continue
		_lit_mask[i] = lit
		changed = true
		var c: Color = s.colour if lit == 1 else Color(0, 0, 0)
		_img.set_pixel(s.x, s.y, c)
		_img.set_pixel(s.x + 1, s.y, c)
	return changed

## Piecewise-linear lookup, flat beyond the ends.
static func _curve(points: Array, m: float) -> float:
	if m <= points[0][0]:
		return points[0][1]
	for i in range(1, points.size()):
		if m <= points[i][0]:
			var a: Array = points[i - 1]
			var b: Array = points[i]
			return lerpf(a[1], b[1], (m - a[0]) / (b[0] - a[0]))
	return points[-1][1]
