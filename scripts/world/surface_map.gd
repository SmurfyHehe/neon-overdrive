class_name SurfaceMap
extends RefCounted
## What a tyre is standing on, finer than the collider groups GEVP reads.
##
## GEVP only knows the first group of the body under a wheel, and the world has
## two: "Road" (one plane under the lanes, shoulder, kerb strip and all paint)
## and "Dirt" (the raised pavement). The bands inside "Road" are drawn only, so
## this works them out from where the contact point is across the road, with
## the same numbers RoadChunkBuilder draws them from. No extra colliders.
##
## Static like RoadFrame: one road, one answer for every car.

enum Kind { ASPHALT, PAINT, GRIT, KERB, PAVEMENT }
const NAMES := ["asphalt", "paint", "grit", "kerb", "pavement"]

## Set on the ground bodies the bands are drawn on (game.gd's plane, a hilly
## chunk's RoadCol). A "Road" body without it (the Auto-Tune track) is plain
## asphalt everywhere.
const BANDS_META := &"road_bands"

const L := RoadChunkBuilder.CHUNK_LEN
# The solid edge line, from RoadChunkBuilder's EdgeLine strips: 0.12 m inside
# the lane edge to 0.03 m outside it.
const EDGE_LINE_IN := 0.12
const EDGE_LINE_OUT := 0.03
## Half a tyre's contact patch, m: a tyre is on a line when its edge is.
const TYRE_HALF := 0.08

## How wet the whole road is, 0 dry .. 1 soaked. Nothing shows a wet road on
## main yet, so nothing raises this in a normal run (NEON_WET=0..1 does, to try
## it). Weather (#341) and the wet-road look (#372) are meant to drive it.
static var wetness := 0.0
## Optional extra water at one spot (puddles): called with the road-space
## position, returns 0..1 on top of `wetness`.
static var wet_source: Callable = Callable()

## Reads NEON_WET once at game start.
static func read_env() -> void:
	var e := OS.get_environment("NEON_WET")
	wetness = clampf(e.to_float(), 0.0, 1.0) if e != "" else 0.0

static func wet_at(u: Vector3) -> float:
	if wet_source.is_valid():
		return clampf(wetness + float(wet_source.call(u)), 0.0, 1.0)
	return wetness

## Lanes on one side of chunk `idx`: the same answer game.gd's _section_at
## gives the chunk builder (tests/car/surface_feel.gd checks they agree).
static func lanes(idx: int, oncoming: bool) -> int:
	var lay := RoadFrame.layout
	if lay != null and lay.lanes_live:
		return lay.lanes_at(oncoming, float(idx) * L)
	return RoadChunkBuilder.MAX_ONC_LANES if oncoming else RoadChunkBuilder.MAX_OWN_LANES

## Distance from the centre line to the lane edge at `s` metres along the
## road: tapered across the chunk from the previous chunk's width, like the
## drawn strips.
static func edge_at(s: float, oncoming: bool) -> float:
	var idx := floori(s / L)
	var t := (s - float(idx) * L) / L
	return lerpf(RoadChunkBuilder._lane_w(lanes(idx - 1, oncoming)), RoadChunkBuilder._lane_w(lanes(idx, oncoming)), t)

## The band at road-space position `u` (RoadFrame.unroll), on a banded body.
static func kind_at(u: Vector3) -> int:
	var s := RoadFrame.s_at(u.z)
	var idx := floori(s / L)
	var along := s - float(idx) * L
	var onc := u.x < 0.0
	var ax := absf(u.x)
	var n := lanes(idx, onc)
	var edge := lerpf(RoadChunkBuilder._lane_w(lanes(idx - 1, onc)), RoadChunkBuilder._lane_w(n), along / L)
	var out := ax - edge
	if out > EDGE_LINE_OUT + TYRE_HALF:
		if out < RoadChunkBuilder.SHOULDER_W:
			return Kind.GRIT
		if out < RoadChunkBuilder.SHOULDER_W + RoadChunkBuilder.CURB_W:
			return Kind.KERB
		return Kind.ASPHALT  # past the pavement: the lot in front of the buildings
	if out >= -EDGE_LINE_IN - TYRE_HALF:
		return Kind.PAINT
	# Lane dashes: DASH_LEN of paint centred in every DASH_SPACING, on each
	# divider between two lanes. None inside a crossing.
	var half := RoadChunkBuilder.DASH_SPACING * 0.5
	if absf(fposmod(along, RoadChunkBuilder.DASH_SPACING) - half) <= RoadChunkBuilder.DASH_LEN * 0.5:
		var lane_pos := (ax - RoadChunkBuilder.MEDIAN_GAP) / RoadChunkBuilder.LANE_W
		var nearest := roundf(lane_pos)
		if nearest >= 1.0 and nearest <= float(n - 1) \
				and absf(lane_pos - nearest) * RoadChunkBuilder.LANE_W <= RoadChunkBuilder.LANE_DASH_W * 0.5 + TYRE_HALF \
				and not Junction.in_box(idx, -along):
			return Kind.PAINT
	return Kind.ASPHALT

## The band under one wheel that is touching the ground.
static func kind_under(w: Wheel) -> int:
	if w.surface_type != "Road":
		return Kind.PAVEMENT
	if w.last_collider == null or not w.last_collider.has_meta(BANDS_META):
		return Kind.ASPHALT
	return kind_at(RoadFrame.unroll(w.last_collision_point))
