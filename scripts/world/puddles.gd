extends RefCounted

# Puddles (water, Part 2). Where standing water lies on the road, in road
# space: s metres along the road (RoadFrame.s_at, independent of the floating
# origin) and x across it. Each 50 m chunk gets 0 to MAX_PER_CHUNK puddles
# seeded from hash([chunk, k]), like the buildings, so a chunk always has the
# same puddles however often it is rebuilt or revisited. Nothing is placed in
# the scene: wheels ask depth_at() for the spot under them, and the answer is
# only read while the road is wet (wet_grip.gd skips the lookup when dry).
# No class_name on purpose: preload it, so no class cache refresh is needed.

enum Depth { NONE, SHALLOW, DEEP }

const L := RoadChunkBuilder.CHUNK_LEN
const MAX_PER_CHUNK := 3
## Puddles lie across the paved road, both carriageways (4 + 4 lanes of
## RoadChunkBuilder.LANE_W plus the median is about 13.5 m each side).
const HALF_SPAN := 13.0
## Half-sizes, m: along the road, then across it.
const HALF_LEN := Vector2(1.0, 3.0)
const HALF_W := Vector2(0.5, 1.3)
## Share of puddles that are deep.
const DEEP_SHARE := 0.3
## Chunks kept in the cache; the road only ever needs the few around a car.
const CACHE_MAX := 256
## Floats per puddle: s, x, half length, half width, depth.
const STRIDE := 5

static var _cache := {}

## Puddles of chunk c (chunk c covers s in [c * L, (c + 1) * L)).
static func of_chunk(c: int) -> PackedFloat32Array:
	var hit: Variant = _cache.get(c)
	if hit != null:
		return hit
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([c, 0x9dd1e])
	var n := rng.randi_range(0, MAX_PER_CHUNK)
	for k in n:
		rng.seed = hash([c, k])
		var hl := rng.randf_range(HALF_LEN.x, HALF_LEN.y)
		out.append(float(c) * L + rng.randf_range(hl, L - hl))  # wholly inside the chunk
		out.append(rng.randf_range(-HALF_SPAN, HALF_SPAN))
		out.append(hl)
		out.append(rng.randf_range(HALF_W.x, HALF_W.y))
		out.append(float(Depth.DEEP if rng.randf() < DEEP_SHARE else Depth.SHALLOW))
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	_cache[c] = out
	return out

## Depth of the water at road-space (s, x); NONE off every puddle. A puddle is
## an ellipse, and lies wholly inside its chunk, so one chunk is enough.
static func depth_at(s: float, x: float) -> int:
	var p := of_chunk(floori(s / L))
	var d := Depth.NONE
	var i := 0
	while i < p.size():
		var ds := (s - p[i]) / p[i + 2]
		var dx := (x - p[i + 1]) / p[i + 3]
		if ds * ds + dx * dx <= 1.0:
			d = maxi(d, int(p[i + 4]))  # two puddles can overlap: the deeper one counts
		i += STRIDE
	return d

## Gathers into `out` (STRIDE floats each, as of_chunk) every puddle a car
## centred at road-space (s, x), its wheels all within r of the centre, could
## reach by moving less than `margin` m; returns how far the car can move
## before that list could be missing one. Distance is box distance to each
## puddle's extent (a car moves no further along either axis than it drives),
## capped by the edge of the three chunks read, since puddles sit wholly
## inside their chunk. Empty list: the car is clear for the returned distance.
static func gather(s: float, x: float, r: float, margin: float, out: PackedFloat32Array) -> float:
	out.clear()
	var c := floori(s / L)
	var valid := minf(s - float(c - 1) * L, float(c + 2) * L - s)
	for k in range(c - 1, c + 2):
		var p := of_chunk(k)
		var i := 0
		var n := p.size()
		while i < n:
			var d := maxf(absf(s - p[i]) - p[i + 2], absf(x - p[i + 1]) - p[i + 3]) - r
			if d < margin:
				out.append_array(p.slice(i, i + STRIDE))
			elif d < valid:
				valid = d
			i += STRIDE
	return minf(valid, margin) if not out.is_empty() else valid

## How far a car centred at (s, x), wheels within r, is from the nearest of
## the puddles in `list`, by the box distance gather() uses; 0 or less when a
## wheel may be on one.
static func reach(list: PackedFloat32Array, s: float, x: float, r: float) -> float:
	var best := INF
	var i := 0
	var n := list.size()
	while i < n:
		best = minf(best, maxf(absf(s - list[i]) - list[i + 2], absf(x - list[i + 1]) - list[i + 3]) - r)
		i += STRIDE
	return best

## Depth at road-space (s, x) among the puddles in `list` (from gather).
static func depth_in(list: PackedFloat32Array, s: float, x: float) -> int:
	var d := Depth.NONE
	var i := 0
	var n := list.size()
	while i < n:
		var ds := (s - list[i]) / list[i + 2]
		var dx := (x - list[i + 1]) / list[i + 3]
		if ds * ds + dx * dx <= 1.0:
			d = maxi(d, int(list[i + 4]))
		i += STRIDE
	return d

static func clear_cache() -> void:
	_cache.clear()
