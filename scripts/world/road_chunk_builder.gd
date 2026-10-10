extends RefCounted
class_name RoadChunkBuilder

# Builds/rebuilds one road chunk's geometry in world-space.
#
# 2026-09-13 cheap visual/geometry pass #1 (tapering + asphalt texture +
# shoulders + pylons) -- see git history / project memory for details.
#
# 2026-09-13 pass #2 ("still doesn't look like a real road" + "how do these
# apply to gameplay" feedback, decisions locked in before building):
# - curb + sidewalk strips beyond the shoulder, both tapered like everything
#   else (visually). Sidewalks are DRIVABLE by design (risk/reward shortcut,
#   see project memory) at reduced grip -- the curb is crossable, NOT a
#   collision wall, so it does not block the player. It DOES still function
#   as the effective lane boundary for traffic AI once that exists (M3/4):
#   NPCs simply never target a path across it.
#   UPDATE (2026-09-13 physics rewrite): grip + the curb bump used to be
#   hand-rolled x-position math in game.gd/player.gd. Now that PlayerCar's
#   wheels are real raycasts (see player.gd), both come for free from real
#   geometry: _update_sidewalk_collision() below sizes a "Dirt"-group collision
#   box (raised slightly above the flat "Road" ground slab) under the
#   curb+sidewalk band, and the vendored Wheel controller reads the group a
#   wheel's raycast hits to pick tire values AND feels the real height step.
#   UPDATE (2026-09-29, issue #35): this used to be one box at the chunk's
#   average width, up to 1.15 m off the drawn sidewalk at each end of a
#   lane-change chunk. It is now a tapered prism that matches the strip.
# - roadside buildings beyond the sidewalks: real collision (StaticBody3D +
#   BoxShape3D) so the player can't drive through them -- this is now the
#   actual hard boundary of the drivable world, since the curb no longer is
#   one. A random ~12% are tagged building_type="garage" (low sheds) --
#   purely a reserved variant for now, not wired to anything; milestone 8's
#   stop-places can reuse the tag later. Their look comes from
#   scripts/world/building_kit.gd (buildings step 1, 2026-10-07).
# - brighter/wider lane markings (the old dash/center-line material wasn't
#   even emissive, just flat albedo -- part of why markings read as
#   invisible) + a new solid (non-dashed) edge line along each lane's outer
#   boundary, matching how real roads mark the edge differently from the
#   interior lane splits.
#
# 2026-09-29 draw-call / allocation pass #3 (measured findings, see
# ISSUES.md). Three problems, all in the build path rather than the visuals:
# - hundreds of duplicate Mesh resources: every dash, pylon and building box
#   allocated its own BoxMesh for identical dimensions. Now five shared
#   meshes, built once.
# - no MultiMesh anywhere, despite lane dashes and pylons being the textbook
#   case (identical mesh, shared material, no collision on any of them).
#   Dashes and pylons are now four MultiMeshInstance3D per chunk instead of
#   24-60 MeshInstance3D.
# - "recycling" only reused the chunk root: rebuild_chunk() queue_free()'d all
#   ~70 children and rebuilt them, roughly every 0.9 s at 55 m/s. The chunk
#   node skeleton is now created once per pooled root and updated in place;
#   see _create_nodes() / _apply().
# Visuals are deliberately unchanged by this pass -- same dimensions, colors,
# vertex order and materials. The CULL_DISABLED double-rasterisation on the
# asphalt strips is a known separate issue, left alone here on purpose.

# 2026-10-04 stage A environment pass (ROADMAP "Stage A plan and decisions"):
# - repainted for the look Roy picked on the Look Board (option B, "Gritty PS2
#   night": dark, orange sodium lamps, lamp pools, no neon). Markings are
#   paint now (white/yellow, faint retroreflective emission below the glow
#   threshold) instead of glowing cyan/amber; the cyan/magenta pylons are
#   delineator posts; asphalt, curbs and sidewalks are neutral greys.
# - narrower road: shoulder 1.6 -> 0.9 m, buildings 0.5 m behind the
#   sidewalk instead of 1.0, and the lane-count cap moved from 4 to 3 in
#   game.gd::_section_at(). The sidewalk stays 2.2 m (a drivable risk/reward
#   shortcut by design; 1.8 m was tried and barely fit the car). LANE_W was
#   left at 2.3 m then; traffic milestone 4 widened it (see LANE_W).
# - dense roadside detail, all MultiMesh: sodium street lamps every 25 m per
#   side (staggered), a fake light pool on the road under each one (additive
#   decal-style quad, zero lighting cost), posts every 5 m, and concrete walls
#   closing the gaps between buildings.
# - buildings: their window emission was set up as ADD with a white emission
#   colour, which lit every face at 1.4x -- the solid white blocks in every
#   screenshot. Now MULTIPLY (only the windows glow), world-space triplanar so
#   windows are the same size on every building, and longer frontages.
#   (Superseded 2026-10-07 by the facade kit, scripts/world/building_kit.gd.)

# Curves + elevation (#37, docs/planning/curves-elevation-proposal-2026-10-07.md):
# every chunk carries its centreline as a Path3D ("Centerline"), and
# everything below is laid out in the frame of that curve -- see the
# "centreline" section. The curve's bend comes from RoadAlignment (step R3);
# with no alignment it is straight and the street is what it always was.
#
# Interior lane-divider dashes and the center barrier/dash line are snapped
# to each chunk's own (end-of-chunk) lane count, not tapered. Kept on purpose
# (issue #36, closed won't-fix 2026-09-29): on a lane ADD the new divider
# carries on from the old road edge while the new lane opens beside it, and
# on a lane DROP the outer lane narrows away with no divider -- which is how
# real roads mark both. Tapering would mean dividers appearing and
# disappearing mid-span for a worse-looking result.

# Lane width. 2.3 m until traffic milestone 4 (2026-10-06, Roy's call after the
# audit): with ~1.8-2.1 m cars that left about 0.25 m either side, and the
# scripted player sideswiped oncoming traffic within seconds at 240 km/h.
# Real highway lanes are 3.5-3.7 m; 3.2 m keeps the road a little tight for
# the sense of speed and leaves ~1.1 m between bodies in adjacent lanes.
# Everything else across the road (shoulder, curb, sidewalk, buildings,
# lamps, lane dashes, traffic lane centres) is laid out from this constant.
const BuildingKit := preload("res://scripts/world/building_kit.gd")
const BuildingSigns := preload("res://scripts/world/building_signs.gd")
const RoofProps := preload("res://scripts/world/roof_props.gd")
const WetReflections := preload("res://scripts/world/wet_reflections.gd")
const RoadWet := preload("res://scripts/world/road_wet.gd")
const Districts := preload("res://scripts/world/districts.gd")
const Kit := preload("res://scripts/world/roadside_kit.gd")
const LampLife := preload("res://scripts/world/lamp_life.gd")
const PlaceNames := preload("res://scripts/world/place_names.gd")
const RoadSigns := preload("res://scripts/world/road_signs.gd")
const RoadPaint := preload("res://scripts/world/road_paint.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const GasStation := preload("res://scripts/world/gas_station.gd")
const SideStreets := preload("res://scripts/world/side_streets.gd")
const StreetAnimals := preload("res://scripts/world/street_animals.gd")

const LANE_W := 3.2
const CHUNK_LEN := 50.0
const DASH_SPACING := 4.0
# Road space (2026-10-06, Roy: "I want more space"): the shoulder went 0.9 ->
# 1.4 m, and the lanes moved MEDIAN_GAP away from the centre line / barrier on
# each side (the gap is plain paved road). Lanes stay LANE_W wide. Everything
# outside the road edge (shoulder, curb, sidewalk, out-of-bounds walls,
# buildings, lamps) is laid out from _lane_w(), so it all moved out with it.
const SHOULDER_W := 1.4
## Clear road between the centre line (or barrier) and the nearest lane, per
## side. Roy's range is 0.2-0.6 m.
const MEDIAN_GAP := 0.4
const CURB_W := 0.3
const SIDEWALK_RAMP := 0.3  # width of the sloped road-side edge of the sidewalk collision
const SIDEWALK_W := 2.2  # kept: the sidewalk is a drivable shortcut by design,
                         # and 1.8 m would barely fit the car's 1.76 m track
# "Pylons" are delineator posts since stage A (node names kept). Denser
# spacing on purpose: near-road objects whipping past are the main speed cue.
const PYLON_SPACING := 5.0
const PYLON_HEIGHT := 1.0
const BUILDING_SPACING := 25.0
const BUILDING_GAP := 0.5  # m between the sidewalk's outer edge and a building front

# Pavements step 1 (2026-10-10): the kerb is a real raised edge, not a flat
# lighter strip. Its cross-section (KERB_PROFILE, fractions of CURB_W across
# and of KERB_H up, the z flag = scaled by the drop factor) is a vertical face
# from the gutter, a rounded top edge and a flat top flush with the pavement.
# The gutter is the shoulder's last GUTTER_W, dipping GUTTER_DIP to the kerb
# foot. Kerb and pavement are cut into rows only where something changes
# (_kerb_rows: the bend's pieces, the edges of a dropped kerb's ramps, the
# edges of a painted stretch), so a dropped kerb (a car-park entrance, the
# crossing's mouth) sinks to DROP_MIN of its height over DROP_RAMP m either
# side of a DROP_HALF m opening, and the kerb near a crossing or a hydrant is
# painted yellow (vertex colour) with a PAINT_EDGE m edge. A straight chunk
# with nothing on it is one piece, like the flat strips.
const KERB_H := 0.1
const KERB_PROFILE: Array[Vector3] = [
	Vector3(0.0, -0.15, 0.0),   # foot, in the gutter (not scaled by the drop)
	Vector3(0.0, 0.7, 1.0),     # face
	Vector3(0.1, 0.93, 1.0),    # rounded edge
	Vector3(0.27, 1.0, 1.0),
	Vector3(1.0, 1.0, 1.0),     # top, meets the pavement
]
const GUTTER_W := 0.3
const GUTTER_DIP := 0.015
const DROP_HALF := 2.5
const DROP_RAMP := 1.0
const DROP_MIN := 0.15
const PAINT_REACH := 6.0     # yellow kerb this far back from a crossing's mouth
const PAINT_HALF := 2.5      # and this far either side of a hydrant
const PAINT_EDGE := 0.05     # the paint's edge blends over this much kerb
const HYDRANT_SETBACK := 0.45  # hydrant centre behind the kerb's outer edge
const HYDRANT_CHANCE := 55   # per cent of chunk sides with a hydrant
# Pavements step 2 (cross-section table, Districts.CROSS): the drawn kerb
# height is per district and tapers between chunks. The wheels' collision top
# stays COL_EXTRA above the drawn pavement, as it always was (0.15 on 0.1),
# except where the kerb is flat (a freeway verge, below FLAT_BELOW).
const COL_EXTRA := 0.05
const FLAT_BELOW := 0.02
# Drains (K4): a grate in the gutter, hashed 0..1 per chunk side, at most
# DRAIN_MAX per side, never in a crossing's mouth or on a dropped kerb.
const DRAIN_MAX := 2
const DRAIN_CHANCE := 70     # per cent, per slot
const DRAIN_LEN := 0.9
const KERB_COLOR := Color(0.42, 0.41, 0.39)
const KERB_PAINT := Color(0.86, 0.62, 0.12)  # the road paint yellow

# Street lamps (stage A). Each side gets one every LAMP_SPACING m, the two
# sides staggered by half that, so a lamp passes every 12.5 m.
const LAMP_SPACING := 25.0
const LAMP_SETBACK := 0.35  # pole distance outside the curb's outer edge
const LAMP_POLE_H := 7.5
const LAMP_ARM := 1.9       # how far the arm reaches out over the road
const POOL_ACROSS := 13.0   # light pool size on the road, m
const POOL_ALONG := 17.0
const POOL_Y := 0.045       # just above the lane dashes (top at 0.035)
const SODIUM := Color(1.0, 0.55, 0.2)

const WALL_H := 2.2         # gap walls between buildings
const WALL_T := 0.3
# Invisible out-of-bounds wall (#28). Was 6 m high and 1 m thick; raised and
# thickened 2026-10-10 (driving off the map, step 1) for the tall and the very
# fast cars to come: a car thrown 8 m up at the wall went over the 6 m one
# (tests/world/off_map_rescue.gd). Thickness grows outward, into the buildings.
# What still gets past is put back by OffMapRescue.
const BOUNDARY_H := 20.0
const BOUNDARY_T := 3.0

# Dash / pylon / barrier dimensions, previously inline magic numbers repeated
# at each construction site. They are constants now because the shared meshes
# further down are built from them exactly once.
const DASH_LEN := 2.4
const DASH_H := 0.05
const DASH_Y := 0.01
const CENTER_DASH_W := 0.22
const LANE_DASH_W := 0.2
const PYLON_W := 0.1
const BARRIER_W := 0.2
const BARRIER_H := 0.65
# Carried over verbatim from the pre-pass code, which sat the barrier at 0.32
# rather than exactly half its height (0.325). Kept as-is so this pass stays
# visually neutral; it is a 5 mm difference, not a deliberate design value.
const BARRIER_Y := 0.32

# Must match game.gd's lane counts (OWN_LANES / ONC_LANES). The MultiMesh
# instance buffers are sized for the worst case exactly once, so these cannot
# be exceeded at runtime -- _apply() clamps defensively rather than overrun.
# Stage B step 3 (2026-10-05): 4 lanes each way; oncoming was capped at 2.
const MAX_OWN_LANES := 4
const MAX_ONC_LANES := 4

# Road paint (stage A): plain white and yellow, with just enough emission to
# read at night like retroreflective paint -- below the 1.0 glow threshold.
const CENTER_COLOR := Color(0.86, 0.62, 0.12)
const LANE_DASH_COLOR := Color(0.82, 0.82, 0.78)
const PAINT_ENERGY := 0.28

static var _own_mat: ShaderMaterial
static var _onc_mat: ShaderMaterial
static var _shoulder_mat: ShaderMaterial
static var _curb_mat: StandardMaterial3D
static var _sidewalk_mat: StandardMaterial3D
static var _edge_line_mat: StandardMaterial3D
static var _pylon_mat_own: StandardMaterial3D
static var _pylon_mat_onc: StandardMaterial3D
static var _barrier_mat: StandardMaterial3D
static var _center_dash_mat: StandardMaterial3D
static var _lane_dash_mat: StandardMaterial3D

# Shared geometry, built once and reused by every chunk in the pool -- see the
# "shared geometry" section below.
static var _center_dash_mesh: BoxMesh
static var _lane_dash_mesh: BoxMesh
static var _pylon_mesh: BoxMesh
static var _barrier_mesh: ArrayMesh
static var _lamp_mesh: ArrayMesh
static var _lamp_mesh_dark: ArrayMesh
static var _pool_mesh: PlaneMesh
static var _pool_mat: StandardMaterial3D
static var _wall_mesh: BoxMesh
static var _reflector_mesh: ArrayMesh
static var _reflector_mat: ShaderMaterial
static var _reflector_glow := 1.0
static var _wall_mat: StandardMaterial3D

static func _flat_mat(color: Color, emissive: bool = false, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
	return m

## Asphalt-grain material (scripts/world/road_wet.gd): a small seamless noise
## texture through a 2-colour gradient, tiled so it repeats along the chunk,
## plus the wet-road look driven by one `wetness` uniform. Back faces are
## culled, so the tapered strips below must wind their triangles to face up.
static func _asphalt_mat(color: Color) -> ShaderMaterial:
	return RoadWet.asphalt_mat(color)

static func _get_own_mat() -> ShaderMaterial:
	if _own_mat == null:
		_own_mat = _asphalt_mat(Color(0.085, 0.085, 0.09))
	return _own_mat

static func _get_onc_mat() -> ShaderMaterial:
	if _onc_mat == null:
		_onc_mat = _asphalt_mat(Color(0.08, 0.08, 0.085))
	return _onc_mat

static func _get_shoulder_mat() -> ShaderMaterial:
	if _shoulder_mat == null:
		_shoulder_mat = _asphalt_mat(Color(0.055, 0.055, 0.058))
	return _shoulder_mat

## Curb: crossable, not a wall (see file header). Light concrete (stage A:
## was a bright emissive strip, part of the neon look) so it still reads as
## the road's edge against the darker shoulder. The colour comes from the
## vertex colours since pavements step 1, so the rows near a crossing or a
## hydrant can be painted yellow in the same mesh.
static func _get_curb_mat() -> StandardMaterial3D:
	if _curb_mat == null:
		_curb_mat = _flat_mat(Color.WHITE, true, 0.12)
		_curb_mat.vertex_color_use_as_albedo = true
		_curb_mat.emission = KERB_COLOR
		_curb_mat.roughness = 0.85
	return _curb_mat

static var _gutter_mat: ShaderMaterial
static var _hydrant_mat: StandardMaterial3D
static var _hydrant_mesh: ArrayMesh

## Gutter: the shoulder's edge, a shade darker and smoother (it holds the
## water), dipping to the kerb foot.
static func _get_gutter_mat() -> ShaderMaterial:
	if _gutter_mat == null:
		_gutter_mat = _asphalt_mat(Color(0.045, 0.045, 0.05))
	return _gutter_mat

## Sidewalk: concrete slabs. A seamless 64 px tile of concrete grain with a
## dark groove along two edges, tiled 1.1 x 1 m (uv1_scale on the strip's
## 0..1 UVs: 2 across the 2.2 m pavement, 50 along the 50 m chunk), so the
## slab lines run with the kerb and across it.
## TEST BUILD: stays a plain material, so the slabs do not take the wet-road
## look (S1a made the pavement an asphalt shader; the two need one owner).
static func _get_sidewalk_mat() -> StandardMaterial3D:
	if _sidewalk_mat == null:
		var m := StandardMaterial3D.new()
		var size := 64
		var noise := FastNoiseLite.new()
		noise.seed = 4242
		noise.frequency = 0.11
		var img := Image.create(size, size, false, Image.FORMAT_RGB8)
		var base := Color(0.125, 0.12, 0.115)
		for y in size:
			for x in size:
				var g := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5  # 0..1
				var c := base.darkened(0.25).lerp(base.lightened(0.12), g)
				# the groove: two texels along the tile's low edges, the texel
				# next to it a touch darker (a chamfered slab edge)
				if x < 2 or y < 2:
					c = c.darkened(0.55)
				elif x == 2 or y == 2:
					c = c.darkened(0.2)
				img.set_pixel(x, y, c)
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.uv1_scale = Vector3(2.0, CHUNK_LEN, 1.0)
		m.roughness = 0.92
		m.metallic = 0.0
		_sidewalk_mat = m
	return _sidewalk_mat

## Hydrant: a dull painted red-orange (the palette's sodium side, no neon),
## with the faint reflector-grade emission the posts use so it reads at night.
static func _get_hydrant_mat() -> StandardMaterial3D:
	if _hydrant_mat == null:
		_hydrant_mat = _flat_mat(Color(0.72, 0.28, 0.08), true, 0.15)
		_hydrant_mat.roughness = 0.6
	return _hydrant_mat

## A boxy fire hydrant, origin at its base: barrel, cap, bonnet and two
## side outlets. ~70 triangles, one MultiMesh slot per chunk side.
static func _get_hydrant_mesh() -> ArrayMesh:
	if _hydrant_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		Junction._box(st, Transform3D(Basis(), Vector3(0.0, 0.3, 0.0)), Vector3(0.22, 0.6, 0.22))   # barrel
		Junction._box(st, Transform3D(Basis(), Vector3(0.0, 0.08, 0.0)), Vector3(0.3, 0.06, 0.3))    # base flange
		Junction._box(st, Transform3D(Basis(), Vector3(0.0, 0.64, 0.0)), Vector3(0.28, 0.08, 0.28))  # cap flange
		Junction._box(st, Transform3D(Basis(), Vector3(0.0, 0.74, 0.0)), Vector3(0.18, 0.12, 0.18))  # bonnet
		Junction._box(st, Transform3D(Basis(), Vector3(0.16, 0.4, 0.0)), Vector3(0.14, 0.11, 0.11))  # outlets
		Junction._box(st, Transform3D(Basis(), Vector3(-0.16, 0.4, 0.0)), Vector3(0.14, 0.11, 0.11))
		st.generate_normals()
		_hydrant_mesh = st.commit()
	return _hydrant_mesh

static var _drain_mat: StandardMaterial3D
static var _drain_mesh: ArrayMesh

## Drain grate (K4): lighter cast-iron frame, dark slots; vertex colours.
static func _get_drain_mat() -> StandardMaterial3D:
	if _drain_mat == null:
		_drain_mat = _flat_mat(Color.WHITE, true, 0.1)
		_drain_mat.vertex_color_use_as_albedo = true
		_drain_mat.emission = Color(0.3, 0.3, 0.3)
		_drain_mat.roughness = 0.5
	return _drain_mat

## A flat grate across the gutter, origin at its centre on the gutter's
## surface: frame plus five slots. 6 boxes, 72 triangles, one MultiMesh slot
## per drain.
static func _get_drain_mesh() -> ArrayMesh:
	if _drain_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_color(Color(0.17, 0.165, 0.16))
		Junction._box(st, Transform3D(Basis(), Vector3(0.0, 0.004, 0.0)), Vector3(GUTTER_W + 0.04, 0.008, DRAIN_LEN))
		st.set_color(Color(0.02, 0.02, 0.022))
		for k in 5:
			var z := (float(k) - 2.0) * DRAIN_LEN / 5.5
			Junction._box(st, Transform3D(Basis(), Vector3(0.0, 0.0085, z)), Vector3(GUTTER_W - 0.04, 0.003, DRAIN_LEN / 11.0))
		st.generate_normals()
		_drain_mesh = st.commit()
	return _drain_mesh

## Solid (non-dashed) lane-edge line -- real roads mark the outer edge
## differently from interior lane splits; ours didn't distinguish them at all.
static func _get_edge_line_mat() -> StandardMaterial3D:
	if _edge_line_mat == null:
		_edge_line_mat = _flat_mat(LANE_DASH_COLOR, true, PAINT_ENERGY)
	return _edge_line_mat

## Delineator posts (stage A; were cyan/magenta neon pylons). Faint emission
## stands in for the reflector catching headlights, so the 5 m rhythm still
## reads in the dark without glowing.
static func _get_pylon_mat_own() -> StandardMaterial3D:
	if _pylon_mat_own == null:
		_pylon_mat_own = _flat_mat(Color(0.72, 0.72, 0.7), true, 0.35)
	return _pylon_mat_own

static func _get_pylon_mat_onc() -> StandardMaterial3D:
	if _pylon_mat_onc == null:
		_pylon_mat_onc = _flat_mat(Color(0.72, 0.62, 0.45), true, 0.35)
	return _pylon_mat_onc

## The center barrier and the two dash colors were the three materials in this
## file that bypassed the static-var cache above, constructed fresh inside
## _populate() on every chunk build. A new material per chunk defeats the
## batching the rest of the cache exists to enable.
## Stage A: a concrete median barrier instead of a glowing amber bar.
static func _get_barrier_mat() -> StandardMaterial3D:
	if _barrier_mat == null:
		_barrier_mat = _flat_mat(Color(0.36, 0.355, 0.34), true, 0.1)
	return _barrier_mat

static func _get_center_dash_mat() -> StandardMaterial3D:
	if _center_dash_mat == null:
		_center_dash_mat = _flat_mat(CENTER_COLOR, true, PAINT_ENERGY)
	return _center_dash_mat

static func _get_lane_dash_mat() -> StandardMaterial3D:
	if _lane_dash_mat == null:
		_lane_dash_mat = _flat_mat(LANE_DASH_COLOR, true, PAINT_ENERGY)
	return _lane_dash_mat

# ---------- shared geometry ----------
#
# Every dash, pylon and building box used to allocate its own BoxMesh for
# identical dimensions -- hundreds of duplicate Mesh resources per pool where
# these four shared ones do the job. Dash and pylon sizes are baked into the
# mesh rather than scaled from a unit cube, so the MultiMesh transforms below
# stay pure translation.

static func _box_mesh(size: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = size
	return bm

static func _get_center_dash_mesh() -> BoxMesh:
	if _center_dash_mesh == null:
		_center_dash_mesh = _box_mesh(Vector3(CENTER_DASH_W, DASH_H, DASH_LEN))
	return _center_dash_mesh

static func _get_lane_dash_mesh() -> BoxMesh:
	if _lane_dash_mesh == null:
		_lane_dash_mesh = _box_mesh(Vector3(LANE_DASH_W, DASH_H, DASH_LEN))
	return _lane_dash_mesh

static func _get_pylon_mesh() -> BoxMesh:
	if _pylon_mesh == null:
		_pylon_mesh = _box_mesh(Vector3(PYLON_W, PYLON_HEIGHT, PYLON_W))
	return _pylon_mesh

## Median barrier reflectors (2026-10-07): amber dots on top of the barrier
## every REFLECTOR_SPACING, so the wall's line reads at night before you are
## on it. Each dot is a camera-facing quad that never drops below
## REFLECTOR_MIN_SCREEN of the screen height and fades out past headlight reach
## (REFLECTOR_FADE), like a retroreflector the car's lamps stop catching.
## A reflector only shines back what hits it: once the player's car reports
## its headlights (set_reflector_lamp), a dot is lit only inside the beam, so
## the ones beside and behind the car, and all of them with the lamps off or
## broken, stay dark instead of hanging there as glowing balls (2026-10-10).
## One dot per barrier piece, a MultiMesh child of the Barrier so it shows
## and bends with it: one draw call per barrier chunk. TrafficSettings.light_glow scales it.
const REFLECTOR_SPACING := 5.0
const REFLECTOR_NEAR_R := 0.06
const REFLECTOR_MIN_SCREEN := 0.004
const REFLECTOR_FADE := Vector2(60.0, 200.0)
const REFLECTOR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;
uniform vec3 tint = vec3(1.0, 0.53, 0.13);
uniform float energy = 1.3;
uniform float gain = 1.0;
uniform float near_r = 0.06;
uniform float min_screen = 0.004;
uniform vec2 fade = vec2(60.0, 200.0);
uniform float lamp_known = 0.0;
uniform float lamp_share = 1.0;
uniform vec3 lamp_pos = vec3(0.0);
uniform vec3 lamp_dir = vec3(0.0, 0.0, -1.0);
uniform vec2 lamp_cone = vec2(0.5, 0.82);
varying float v_k;
void vertex() {
	vec3 c = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = max(-c.z, 0.05);
	v_k = 1.0 - smoothstep(fade.x, fade.y, d);
	if (lamp_known > 0.5) {
		vec3 to = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - lamp_pos;
		v_k *= lamp_share * smoothstep(lamp_cone.x, lamp_cone.y, dot(normalize(to), lamp_dir));
	}
	float far_r = min_screen * 2.0 * d / abs(PROJECTION_MATRIX[1][1]);
	c *= max(d - 0.1, 0.05) / d;
	c.xy += UV * max(near_r, far_r) * step(0.001, gain * v_k);
	VERTEX = c;
}
void fragment() {
	float f = 1.0 - smoothstep(0.45, 1.0, length(UV));
	ALBEDO = tint * energy * gain * f * v_k;
}
"""

static func set_reflector_glow(g: float) -> void:
	_reflector_glow = g
	if _reflector_mat != null:
		_reflector_mat.set_shader_parameter("gain", g)

## Cosines of the angle off the headlights' axis at which a reflector is dark
## and fully lit: wider than the beam itself (CarFx.HEADLIGHT_ANGLE), since a
## reflector answers to very little stray light.
const REFLECTOR_LAMP_CONE := Vector2(0.5, 0.82)

## The player's headlights, in world space, each physics tick: where they are,
## which way they point, and how much of the beam is left (0 = off).
static func set_reflector_lamp(pos: Vector3, dir: Vector3, share: float) -> void:
	var m := _get_reflector_mat()
	m.set_shader_parameter("lamp_known", 1.0)
	m.set_shader_parameter("lamp_pos", pos)
	m.set_shader_parameter("lamp_dir", dir)
	m.set_shader_parameter("lamp_share", share)

## Back to dots that shine whatever the headlights do (no player car).
static func clear_reflector_lamp() -> void:
	if _reflector_mat != null:
		_reflector_mat.set_shader_parameter("lamp_known", 0.0)

static func _get_reflector_mat() -> ShaderMaterial:
	if _reflector_mat == null:
		var sh := Shader.new()
		sh.code = REFLECTOR_SHADER
		_reflector_mat = ShaderMaterial.new()
		_reflector_mat.shader = sh
		_reflector_mat.set_shader_parameter("near_r", REFLECTOR_NEAR_R)
		_reflector_mat.set_shader_parameter("min_screen", REFLECTOR_MIN_SCREEN)
		_reflector_mat.set_shader_parameter("fade", REFLECTOR_FADE)
		_reflector_mat.set_shader_parameter("gain", _reflector_glow)
		_reflector_mat.set_shader_parameter("lamp_cone", REFLECTOR_LAMP_CONE)
	return _reflector_mat

## In one barrier piece's local space (a box centred on the origin, one station long).
static func _get_reflector_mesh() -> ArrayMesh:
	if _reflector_mesh == null:
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]
		var seg := CHUNK_LEN / STATIONS
		var n := maxi(1, int(seg / REFLECTOR_SPACING))
		for i in n:
			var p := Vector3(0.0, BARRIER_H / 2.0 + 0.03, -seg / 2.0 + (float(i) + 0.5) * seg / n)
			for uv in corners:
				verts.append(p)
				uvs.append(uv)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		_reflector_mesh = ArrayMesh.new()
		_reflector_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_reflector_mesh.surface_set_material(0, _get_reflector_mat())
	return _reflector_mesh

## How far a barrier piece's sides and top run on past its end faces, into
## the next piece.
const BARRIER_OVERLAP := 0.06

## One station of the centre barrier. A plain box per station left a hairline
## crack at every joint on a bend or a change of slope (the pieces are
## straight, the road is not), and through the crack you saw the next piece's
## end face. That face meets the headlights square on while the wall's side
## only catches them at a glancing angle, so every joint showed as a bright
## vertical line (2026-10-10). Here the sides and the top overlap the next
## piece by BARRIER_OVERLAP, which closes the crack; the end faces stay on the
## joint, inside the neighbour, and still close the wall where a run of
## barrier ends. No bottom: it sits on the road.
static func _get_barrier_mesh() -> ArrayMesh:
	if _barrier_mesh == null:
		var h := Vector3(BARRIER_W, BARRIER_H, CHUNK_LEN / STATIONS) / 2.0
		var l := h.z + BARRIER_OVERLAP
		var faces := [
			[Vector3.RIGHT, Vector3(h.x, -h.y, l), Vector3(h.x, h.y, l), Vector3(h.x, h.y, -l), Vector3(h.x, -h.y, -l)],
			[Vector3.LEFT, Vector3(-h.x, -h.y, -l), Vector3(-h.x, h.y, -l), Vector3(-h.x, h.y, l), Vector3(-h.x, -h.y, l)],
			[Vector3.UP, Vector3(-h.x, h.y, l), Vector3(-h.x, h.y, -l), Vector3(h.x, h.y, -l), Vector3(h.x, h.y, l)],
			[Vector3.BACK, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
			[Vector3.FORWARD, Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
		]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for f in faces:
			st.set_normal(f[0])
			for i in [1, 2, 3, 1, 3, 4]:
				st.add_vertex(f[i])
		_barrier_mesh = st.commit()
	return _barrier_mesh

## Street lamp, built once and shared by every chunk's lamp MultiMesh: a pole
## and arm (dark metal) and a sodium head (emissive, above the glow threshold
## so it blooms). Two surfaces, so materials live on the mesh, not on the
## MultiMeshInstance3D. Local space: pole at the origin, arm reaching toward
## -X (over the road on the player's side; the other side is mirrored by the
## instance transform).
static func _get_lamp_mesh() -> ArrayMesh:
	if _lamp_mesh == null:
		var metal := _flat_mat(Color(0.2, 0.2, 0.21))
		metal.roughness = 0.6
		var head := _flat_mat(SODIUM, true, 4.0)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_add_box(st, Vector3(0.0, LAMP_POLE_H / 2.0, 0.0), Vector3(0.16, LAMP_POLE_H, 0.16))
		_add_box(st, Vector3(-LAMP_ARM / 2.0, LAMP_POLE_H - 0.05, 0.0), Vector3(LAMP_ARM, 0.1, 0.12))
		_lamp_mesh = st.commit()
		_lamp_mesh.surface_set_material(0, metal)
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_add_box(st, Vector3(-LAMP_ARM + 0.2, LAMP_POLE_H - 0.16, 0.0), Vector3(0.75, 0.14, 0.36))
		_lamp_mesh = st.commit(_lamp_mesh)
		_lamp_mesh.surface_set_material(1, head)
	return _lamp_mesh

## The lamp mesh, or its twin with the head switched off (MomentSpots' power
## cut swaps a chunk's "Lamps" to it: no per-instance data needed).
static func lamp_mesh(dark := false) -> ArrayMesh:
	if not dark:
		return _get_lamp_mesh()
	if _lamp_mesh_dark == null:
		_lamp_mesh_dark = _get_lamp_mesh().duplicate()
		_lamp_mesh_dark.surface_set_material(1, _flat_mat(Color(0.09, 0.08, 0.07)))
	return _lamp_mesh_dark

## Axis-aligned box into a SurfaceTool, flat-shaded (one normal per face) and
## wound clockwise from outside, matching Godot's front faces.
static func _add_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size / 2.0
	var faces := [
		[Vector3.RIGHT, Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)],
		[Vector3.LEFT, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		[Vector3.UP, Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)],
		[Vector3.DOWN, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z)],
		[Vector3.BACK, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3.FORWARD, Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
	]
	for f in faces:
		st.set_normal(f[0])
		for i in [1, 2, 3, 1, 3, 4]:
			st.add_vertex(center + f[i])

## Light pool: a flat quad with a radial falloff, added on top of the road
## (BLEND_MODE_ADD, unshaded), so a lamp "lights" the asphalt at zero lighting
## cost. Fades out with distance instead of fog: fog on an additive surface
## would add fog colour, not remove light.
static func _get_pool_mesh() -> PlaneMesh:
	if _pool_mesh == null:
		_pool_mesh = PlaneMesh.new()
		_pool_mesh.size = Vector2.ONE
	return _pool_mesh

static func _get_pool_mat() -> StandardMaterial3D:
	if _pool_mat == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.42), Color(1, 1, 1, 0)])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 128
		tex.height = 128
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = tex
		m.albedo_color = Color(SODIUM.r * 0.42, SODIUM.g * 0.42, SODIUM.b * 0.42, 1.0)
		m.disable_fog = true
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		m.distance_fade_min_distance = 170.0  # min > max: fade OUT with distance
		m.distance_fade_max_distance = 110.0
		_pool_mat = m
	return _pool_mat

static func _get_wall_mesh() -> BoxMesh:
	if _wall_mesh == null:
		_wall_mesh = _box_mesh(Vector3.ONE)  # scaled per instance
	return _wall_mesh

static func _get_wall_mat() -> StandardMaterial3D:
	if _wall_mat == null:
		_wall_mat = _flat_mat(Color(0.15, 0.145, 0.14))
		_wall_mat.roughness = 0.95
	return _wall_mat

## Distance from the centre line to the road edge on a side with `lanes` lanes:
## the median gap plus the lanes. (The name is older than the gap.)
static func _barrier_kind(cfg: Dictionary) -> String:
	var b: Variant = cfg.get("barrier", false)
	if b is bool:
		return RoadBarriers.CONCRETE if b else RoadBarriers.NONE
	return String(b)

static func _lane_w(lanes: int) -> float:
	return MEDIAN_GAP + float(lanes) * LANE_W

## Centre of lane i (0 = nearest the centre line), as a distance from the centre
## line. TrafficManager.lane_centre() adds the sign for the direction.
static func lane_offset(lane_i: int) -> float:
	return MEDIAN_GAP + (float(lane_i) + 0.5) * LANE_W

## The inverse: which lane a distance from the centre line falls in (unclamped
## above, 0 for anything inside the median gap).
static func lane_at(dist: float) -> int:
	return maxi(0, floori((dist - MEDIAN_GAP) / LANE_W))

# ---------- centreline (#37 curves and elevation) ----------
#
# Each chunk's centreline is a Curve3D on a Path3D child, from the chunk root
# (distance s = 0) to the chunk's end (s = CHUNK_LEN), forward = -Z. The
# street is described the way it always was -- x across the road, y up, z
# along it from 0 to -CHUNK_LEN -- and every point and transform is then put
# through the curve's frame at s = -z (_at / _xf). On a straight curve that
# frame is a plain translation; a curved one (RoadAlignment, step R3) bends
# the whole street with it, and a sloped one (R5) will lift it.
#
# Anything long along the road (strips, sidewalk collision, out-of-bounds
# walls, the barrier) is cut into STATIONS pieces so it can follow a bend.

## Pieces per chunk for geometry that follows the curve: one every 5 m.
const STATIONS := 10
## Bake spacing of the centreline, m. Sampling interpolates between baked
## points, so 1 m is plenty for the radii the road uses (300 m and up).
const CENTERLINE_BAKE := 1.0

## The centreline of the chunk _apply() is laying out, and its curvature.
static var _curve: Curve3D
static var _curve_k := 0.0
## Its frame every metre, sampled once per _apply() (_cache_frames). Sampling
## the Curve3D for each of the ~600 points a chunk lays out cost about a
## third of a rebuild (2026-10-07).
static var _frame_xf: Array[Transform3D] = []
static var _frame_o := PackedVector3Array()
static var _frame_f := PackedVector3Array()

static func _cache_frames(curve: Curve3D) -> void:
	var n := int(CHUNK_LEN) + 1
	_frame_xf.resize(n)
	_frame_o.resize(n)
	_frame_f.resize(n)
	for i in n:
		var f := station(curve, float(i))
		_frame_xf[i] = f
		_frame_o[i] = f.origin
		_frame_f[i] = -f.basis.z

## The cached frame s metres along the chunk: exact on every whole metre
## (where nearly every corner sits), interpolated between (a metre's chord of
## a 300 m bend is off by 0.4 mm).
static func _frame(s: float) -> Transform3D:
	var sc := clampf(s, 0.0, CHUNK_LEN)
	var i := mini(int(sc), int(CHUNK_LEN) - 1)
	var t := sc - float(i)
	if t == 0.0:
		return _frame_xf[i]
	if t == 1.0:
		return _frame_xf[i + 1]
	var o := _frame_o[i].lerp(_frame_o[i + 1], t)
	var fwd := _frame_f[i].lerp(_frame_f[i + 1], t).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	return Transform3D(Basis(right, right.cross(fwd), -fwd), o)

static func _new_centerline() -> Path3D:
	var path := Path3D.new()
	path.name = "Centerline"
	path.curve = Curve3D.new()
	path.curve.bake_interval = CENTERLINE_BAKE
	return path

## The chunk's arc (RoadAlignment, curvature k: 0 = straight) as a cubic
## Bezier: handles along the start and end tangents, sized so the cubic
## follows the circle to well under a millimetre at the road's radii.
##
## Hills (R5): the height rises by g s + vc s^2 / 2; a cubic's y follows that
## parabola exactly when its handles carry the start and end slopes over a
## third of the chunk each, which they do.
##
## Eased hills (2026-10-10): where the vertical curvature changes at the
## chunk's start (by dc_in) or end (dc_out), the height is a cubic over the
## first and last EASE / 2 metres and the parabola between, so the curve gets
## a point at each change-over and is still exact piece by piece.
static func _update_centerline(root: Node3D, k: float, g: float = 0.0, vc: float = 0.0, dc_in: float = 0.0, dc_out: float = 0.0) -> Curve3D:
	var curve: Curve3D = (root.get_node(^"Centerline") as Path3D).curve
	curve.clear_points()
	if dc_in != 0.0 or dc_out != 0.0:
		var e := RoadAlignment.EASE * 0.5
		var cuts: Array[float] = [0.0, e, CHUNK_LEN - e, CHUNK_LEN]
		for j in cuts.size():
			var s := cuts[j]
			var before := 0.0 if j == 0 else s - cuts[j - 1]
			var after := 0.0 if j == cuts.size() - 1 else cuts[j + 1] - s
			var a := RoadAlignment.arc_heading(k, s)
			var fwd := Vector3(-sin(a), 0.0, -cos(a))
			var slope := RoadAlignment.ease_grade(g, vc, dc_in, dc_out, s)
			var p := RoadAlignment.arc_point(k, s) + Vector3(0.0, RoadAlignment.ease_rise(g, vc, dc_in, dc_out, s), 0.0)
			curve.add_point(p,
				-fwd * RoadAlignment.bezier_handle(k, before) - Vector3(0.0, slope * before / 3.0, 0.0),
				fwd * RoadAlignment.bezier_handle(k, after) + Vector3(0.0, slope * after / 3.0, 0.0))
		return curve
	var h := RoadAlignment.bezier_handle(k, CHUNK_LEN)
	var turn := RoadAlignment.arc_heading(k, CHUNK_LEN)
	var end_fwd := Vector3(-sin(turn), 0.0, -cos(turn))
	var g_end := g + vc * CHUNK_LEN
	var end := RoadAlignment.arc_point(k, CHUNK_LEN) + Vector3(0.0, g * CHUNK_LEN + 0.5 * vc * CHUNK_LEN * CHUNK_LEN, 0.0)
	curve.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0.0, g * CHUNK_LEN / 3.0, -h))
	curve.add_point(end, -end_fwd * h - Vector3(0.0, g_end * CHUNK_LEN / 3.0, 0.0), Vector3.ZERO)
	return curve

## The chunk-local frame at distance s along a chunk's centreline: origin on
## the centreline, -Z along the road, X to the right, Y up.
##
## s is distance along the road's plan (what RoadFrame and the layout count);
## on a slope the curve itself is a touch longer (0.13% at 5%), so s is
## scaled to it.
##
## Only the curve's position and direction are used: its own baked up vector
## is carried along the curve and picks up a slight twist on a road that both
## bends and climbs (7.7 cm at the road's edge by a chunk's end, a step at
## every join). The road has no camber, so the frame is rebuilt from the
## direction and world up, which cannot twist.
static func station(curve: Curve3D, s: float) -> Transform3D:
	var len3 := curve.get_baked_length()
	var xf := curve.sample_baked_with_rotation(clampf(s * len3 / CHUNK_LEN, 0.0, len3), false, false)
	var fwd := -xf.basis.z
	var right := fwd.cross(Vector3.UP).normalized()
	return Transform3D(Basis(right, right.cross(fwd), -fwd), xf.origin)

## Chunk-local transform for something laid out at (x, y, z) in the straight
## street description, turned by `local` relative to the road.
static func _xf(x: float, y: float, z: float, local: Basis = Basis()) -> Transform3D:
	return _frame(-z) * Transform3D(local, Vector3(x, y, 0.0))

## Like _xf, for things that stand upright whatever the slope (buildings,
## walls, lamps, posts): placed at (x, z) on the road surface, raised y
## straight up, and turned only to the road's heading.
static func _xf_up(x: float, y: float, z: float, local: Basis = Basis()) -> Transform3D:
	var f := _frame(-z)
	var fwd := -f.basis.z
	fwd.y = 0.0
	return Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP) * local, f * Vector3(x, 0.0, 0.0) + Vector3(0.0, y, 0.0))

## How far upright things reach below the road surface on a hilly road, so a
## building or wall on a slope never shows a gap under its downhill end.
const FOUNDATION := 4.0

static func _foundation() -> float:
	return FOUNDATION if RoadFrame.has_hills() else 0.0

## Chunk-local position of the straight-description point (x, y, z).
static func _at(x: float, y: float, z: float) -> Vector3:
	return _frame(-z) * Vector3(x, y, 0.0)

# ---------- tapered strips ----------
#
# These are the only per-chunk geometry whose SHAPE actually changes, since
# lane widths taper between chunks. Each keeps one ArrayMesh for the life of
# the pool and has its six vertices rewritten in place on rebuild; the old
# path spun up a SurfaceTool for all ten strips on every single rebuild.
#
# Godot treats clockwise triangles (seen from the front) as front faces, and
# every strip material culls back faces. The oncoming-side strips are passed
# mirrored x values (outer < inner), which flips the winding, so the vertex
# order is picked per side to keep every strip facing up.

## Pieces a road strip is cut into along the chunk: enough that each piece's
## straight chord stays within STRIP_SAG of the curve (8 on a 300 m bend), and
## 1 on a straight, level chunk -- exactly the old single quad. The strips
## were the bulk of a chunk rebuild at 10 pieces each (0.35 of 0.84 ms,
## 2026-10-07).
const STRIP_SAG := 0.02
static func strip_pieces(k: float, vc: float = 0.0) -> int:
	var c := maxf(absf(k), absf(vc))
	if c < 1e-9:
		return 1
	return clampi(ceili(CHUNK_LEN * sqrt(c / (8.0 * STRIP_SAG))), 1, STATIONS)

## The chunk _apply() is laying out: its strip piece count.
static var _strip_n := 1

static func _strip_arrays(x_inner0: float, x_inner1: float, x_outer0: float, x_outer1: float, length: float, y: float) -> Array:
	# _strip_n quads along the strip, each corner put through the centreline
	# frame (#37). UVs as before: x across the strip, y along it (0..1 over
	# the chunk), so the asphalt texture tiles exactly as it did.
	var n := _strip_n
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(6 * n)
	normals.resize(6 * n)
	uvs.resize(6 * n)
	# [a, b, c] runs clockwise seen from above only when outer is left of inner.
	var mirrored := x_outer0 < x_inner0
	var f0 := _frame(0.0)
	var t0 := 0.0
	for k in n:
		var t1 := float(k + 1) / float(n)
		var f1 := _frame(length * t1)
		var a := f0 * Vector3(lerpf(x_inner0, x_inner1, t0), y, 0.0)
		var b := f0 * Vector3(lerpf(x_outer0, x_outer1, t0), y, 0.0)
		var c := f1 * Vector3(lerpf(x_inner0, x_inner1, t1), y, 0.0)
		var d := f1 * Vector3(lerpf(x_outer0, x_outer1, t1), y, 0.0)
		var n0 := f0.basis.y
		var n1 := f1.basis.y
		var j := 6 * k
		if mirrored:
			verts[j] = a; verts[j + 1] = b; verts[j + 2] = c; verts[j + 3] = b; verts[j + 4] = d; verts[j + 5] = c
			uvs[j] = Vector2(0, t0); uvs[j + 1] = Vector2(1, t0); uvs[j + 2] = Vector2(0, t1)
			uvs[j + 3] = Vector2(1, t0); uvs[j + 4] = Vector2(1, t1); uvs[j + 5] = Vector2(0, t1)
			normals[j] = n0; normals[j + 1] = n0; normals[j + 2] = n1; normals[j + 3] = n0; normals[j + 4] = n1; normals[j + 5] = n1
		else:
			verts[j] = a; verts[j + 1] = c; verts[j + 2] = b; verts[j + 3] = b; verts[j + 4] = c; verts[j + 5] = d
			uvs[j] = Vector2(0, t0); uvs[j + 1] = Vector2(0, t1); uvs[j + 2] = Vector2(1, t0)
			uvs[j + 3] = Vector2(1, t0); uvs[j + 4] = Vector2(0, t1); uvs[j + 5] = Vector2(1, t1)
			normals[j] = n0; normals[j + 1] = n1; normals[j + 2] = n0; normals[j + 3] = n0; normals[j + 4] = n1; normals[j + 5] = n1
		f0 = f1
		t0 = t1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	return arrays

static func _new_strip(strip_name: String, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = strip_name
	mi.mesh = ArrayMesh.new()
	mi.material_override = mat
	return mi

static func _update_strip(root: Node3D, strip_name: String, x_inner0: float, x_inner1: float, x_outer0: float, x_outer1: float, y: float = 0.0) -> void:
	var mi: MeshInstance3D = root.get_node(NodePath(strip_name))
	var am: ArrayMesh = mi.mesh
	am.clear_surfaces()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _strip_arrays(x_inner0, x_inner1, x_outer0, x_outer1, CHUNK_LEN, y))

# ---------- profile strips (pavements step 1) ----------
#
# A strip with a cross-section: `profile` points are (fraction across the
# band from its inner to its outer edge, height in m, 1 = height scaled by
# the row's drop factor). The band's edges taper like the flat strips. Rows
# sit at `ts` (fractions along the chunk, ascending, 0 and 1 included),
# every corner through the centreline frame. `hs` is the drop factor per row
# (one per t, or empty for 1 everywhere) and `cols` the vertex colour per
# row (or empty for none).
#
# Winding follows _strip_arrays: per side, so every face is a front face
# seen from the road or above. Normals are per profile segment (flat shaded
# faces, like the rest of the PS2-era road).

static func _profile_arrays(x_inner0: float, x_inner1: float, x_outer0: float, x_outer1: float, profile: Array[Vector3], ts: PackedFloat32Array, hs: PackedFloat32Array, cols: PackedColorArray) -> Array:
	var np := profile.size()
	var pieces := ts.size() - 1
	var mirrored := x_outer0 < x_inner0
	var sgn := -1.0 if mirrored else 1.0
	var nq := (np - 1) * pieces
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	verts.resize(6 * nq)
	normals.resize(6 * nq)
	uvs.resize(6 * nq)
	var coloured := cols.size() == ts.size()
	if coloured:
		colors.resize(6 * nq)
	# u across the profile: cumulative length over the section's total
	var us := PackedFloat32Array()
	us.resize(np)
	var total := 0.0
	for i in range(1, np):
		var w := absf(x_outer0 - x_inner0)
		total += Vector2((profile[i].x - profile[i - 1].x) * w, profile[i].y - profile[i - 1].y).length()
		us[i] = total
	if total > 0.0:
		for i in np:
			us[i] /= total
	# row 0
	var prev := PackedVector3Array()
	prev.resize(np)
	var prev_f := _frame(0.0)
	var h0 := hs[0] if hs.size() > 0 else 1.0
	for i in np:
		var p := profile[i]
		prev[i] = prev_f * Vector3(lerpf(x_inner0, x_outer0, p.x), p.y * (h0 if p.z > 0.5 else 1.0), 0.0)
	var t0 := 0.0
	var cur := PackedVector3Array()
	cur.resize(np)
	for k in pieces:
		var t1 := ts[k + 1]
		var f1 := _frame(CHUNK_LEN * t1)
		var h1 := hs[k + 1] if hs.size() > 0 else 1.0
		var xi := lerpf(x_inner0, x_inner1, t1)
		var xo := lerpf(x_outer0, x_outer1, t1)
		for i in np:
			var p := profile[i]
			cur[i] = f1 * Vector3(lerpf(xi, xo, p.x), p.y * (h1 if p.z > 0.5 else 1.0), 0.0)
		for i in range(np - 1):
			var a := prev[i]
			var b := prev[i + 1]
			var c := cur[i]
			var d := cur[i + 1]
			# segment normal in the row's frame: perpendicular to the section
			# segment, pointing up / toward the road
			var dx := (profile[i + 1].x - profile[i].x) * absf(xo - xi) * sgn
			var dy := profile[i + 1].y * (h1 if profile[i + 1].z > 0.5 else 1.0) - profile[i].y * (h1 if profile[i].z > 0.5 else 1.0)
			var nl := Vector3(-dy, dx, 0.0) * sgn
			if nl.length_squared() < 1e-12:
				nl = Vector3.UP
			var n0 := (prev_f.basis * nl).normalized()
			var n1 := (f1.basis * nl).normalized()
			var j := 6 * ((np - 1) * k + i)
			var u0 := us[i]
			var u1 := us[i + 1]
			if mirrored:
				verts[j] = a; verts[j + 1] = b; verts[j + 2] = c; verts[j + 3] = b; verts[j + 4] = d; verts[j + 5] = c
				uvs[j] = Vector2(u0, t0); uvs[j + 1] = Vector2(u1, t0); uvs[j + 2] = Vector2(u0, t1)
				uvs[j + 3] = Vector2(u1, t0); uvs[j + 4] = Vector2(u1, t1); uvs[j + 5] = Vector2(u0, t1)
				normals[j] = n0; normals[j + 1] = n0; normals[j + 2] = n1; normals[j + 3] = n0; normals[j + 4] = n1; normals[j + 5] = n1
				if coloured:
					colors[j] = cols[k]; colors[j + 1] = cols[k]; colors[j + 2] = cols[k + 1]
					colors[j + 3] = cols[k]; colors[j + 4] = cols[k + 1]; colors[j + 5] = cols[k + 1]
			else:
				verts[j] = a; verts[j + 1] = c; verts[j + 2] = b; verts[j + 3] = b; verts[j + 4] = c; verts[j + 5] = d
				uvs[j] = Vector2(u0, t0); uvs[j + 1] = Vector2(u0, t1); uvs[j + 2] = Vector2(u1, t0)
				uvs[j + 3] = Vector2(u1, t0); uvs[j + 4] = Vector2(u0, t1); uvs[j + 5] = Vector2(u1, t1)
				normals[j] = n0; normals[j + 1] = n1; normals[j + 2] = n0; normals[j + 3] = n0; normals[j + 4] = n1; normals[j + 5] = n1
				if coloured:
					colors[j] = cols[k]; colors[j + 1] = cols[k + 1]; colors[j + 2] = cols[k]
					colors[j + 3] = cols[k]; colors[j + 4] = cols[k + 1]; colors[j + 5] = cols[k + 1]
		var swap := prev
		prev = cur
		cur = swap
		prev_f = f1
		t0 = t1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if coloured:
		arrays[Mesh.ARRAY_COLOR] = colors
	return arrays

static func _update_profile_strip(root: Node3D, strip_name: String, x_inner0: float, x_inner1: float, x_outer0: float, x_outer1: float, profile: Array[Vector3], ts: PackedFloat32Array, hs: PackedFloat32Array = PackedFloat32Array(), cols: PackedColorArray = PackedColorArray()) -> void:
	var mi: MeshInstance3D = root.get_node(NodePath(strip_name))
	var am: ArrayMesh = mi.mesh
	am.clear_surfaces()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _profile_arrays(x_inner0, x_inner1, x_outer0, x_outer1, profile, ts, hs, cols))

## Row positions for a strip cut into `n` equal pieces.
static func _uniform_rows(n: int) -> PackedFloat32Array:
	var ts := PackedFloat32Array()
	ts.resize(n + 1)
	for i in n + 1:
		ts[i] = float(i) / float(n)
	return ts

## Row positions for this chunk side's kerb and pavement: the bend's
## _strip_n pieces, plus a row at each edge of every drop's opening and
## ramps, and a pair of rows PAINT_EDGE apart at each edge of every painted
## stretch (so the colour steps there instead of blending over a piece).
## Sorted, unique, clamped to the chunk.
static func _kerb_rows(drops: Array, paint: Array) -> PackedFloat32Array:
	var zs := PackedFloat32Array()
	for i in _strip_n + 1:
		zs.append(-CHUNK_LEN * float(i) / float(_strip_n))
	for d in drops:
		var zc := float(d[0])
		var half := float(d[1])
		for e in [zc - half - DROP_RAMP, zc - half, zc + half, zc + half + DROP_RAMP]:
			zs.append(e)
	for p in paint:
		var zc := float(p[0])
		var half := float(p[1])
		for e in [zc - half - PAINT_EDGE, zc - half, zc + half, zc + half + PAINT_EDGE]:
			zs.append(e)
	var ts := PackedFloat32Array()
	for z in zs:
		ts.append(clampf(-z / CHUNK_LEN, 0.0, 1.0))
	ts.sort()
	var out := PackedFloat32Array()
	for t in ts:
		if out.is_empty() or t - out[out.size() - 1] > 1e-4:
			out.append(t)
	return out

## The kerb section in metres: KERB_PROFILE's fractions times KERB_H.
static func _kerb_profile() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in KERB_PROFILE:
		out.append(Vector3(p.x, p.y * KERB_H, p.z))
	return out

## The pavement section: flat at kerb height, dropping with the kerb.
static func _walk_profile() -> Array[Vector3]:
	return [Vector3(0.0, KERB_H, 1.0), Vector3(1.0, KERB_H, 1.0)]

## The gutter section: from the shoulder's level down GUTTER_DIP at the kerb.
static func _gutter_profile() -> Array[Vector3]:
	return [Vector3(0.0, 0.0, 0.0), Vector3(1.0, -GUTTER_DIP, 0.0)]

## Drop factor per kerb row (`ts`) for this chunk side: 1 = full height,
## down to DROP_MIN across each opening in `drops` ([z_centre, half_width]
## pairs, chunk-local z), easing over DROP_RAMP outside the opening.
static func _kerb_heights(drops: Array, ts: PackedFloat32Array) -> PackedFloat32Array:
	var hs := PackedFloat32Array()
	hs.resize(ts.size())
	for r in ts.size():
		var z := -CHUNK_LEN * ts[r]
		var h := 1.0
		for d in drops:
			var dist: float = absf(z - float(d[0])) - float(d[1])
			h = minf(h, clampf(dist / DROP_RAMP, 0.0, 1.0))
		hs[r] = maxf(h, DROP_MIN)
	return hs

## Vertex colour per kerb row (`ts`): concrete, or the paint yellow within
## `paint` ([z_centre, half_width] pairs). The rows _kerb_rows puts on a
## band's edges make the paint start and end there.
static func _kerb_colours(paint: Array, ts: PackedFloat32Array) -> PackedColorArray:
	var cols := PackedColorArray()
	cols.resize(ts.size())
	for r in ts.size():
		var z := -CHUNK_LEN * ts[r]
		var c := KERB_COLOR
		for p in paint:
			if absf(z - float(p[0])) <= float(p[1]) + 1e-4:
				c = KERB_PAINT
				break
		cols[r] = c
	return cols

## The collision's top at chunk-local z: `ch` holds it in metres per row of
## `ts` (the builder's per-district, drop-aware heights); empty = the old 0.15.
static func _col_h(ch: PackedFloat32Array, ts: PackedFloat32Array, z: float) -> float:
	if ch.size() == 0 or ts.size() < 2:
		return KERB_H + COL_EXTRA
	return _drop_at(ch, ts, z)

## The drop factor at chunk-local z, interpolated between the rows at `ts`
## (for the collision and for things standing on the pavement).
static func _drop_at(hs: PackedFloat32Array, ts: PackedFloat32Array, z: float) -> float:
	if hs.size() == 0 or ts.size() < 2:
		return 1.0
	var t := clampf(-z / CHUNK_LEN, 0.0, 1.0)
	var i := ts.bsearch(t, false) - 1  # last row at or before t
	i = clampi(i, 0, ts.size() - 2)
	var span := ts[i + 1] - ts[i]
	if span <= 1e-6:
		return hs[i]
	return lerpf(hs[i], hs[i + 1], clampf((t - ts[i]) / span, 0.0, 1.0))

# ---------- multimesh helpers ----------
#
# Lane dashes and pylons are the textbook MultiMesh case: identical mesh,
# shared material, hundreds of instances, and no collision on any of them
# (pylons are cosmetic, dashes are paint), so there is no physics consequence
# to collapsing them into instance buffers.
#
# Capacity is allocated once at build time for the WORST case (max lane
# count) and never reallocated; a rebuild only writes transforms and moves
# visible_instance_count. That is what makes the recycle path cheap.

## puddles.gd reads this class's constants, so it is loaded on first use
## rather than preloaded (no cycle at parse time).
static var _puddles_script: GDScript

static func _puddles() -> GDScript:
	if _puddles_script == null:
		_puddles_script = load("res://scripts/world/puddles.gd")
	return _puddles_script

static func _new_multimesh(mm_name: String, mesh: Mesh, mat: Material, capacity: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = mm_name
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi

static func _dash_slots() -> int:
	return int(CHUNK_LEN / DASH_SPACING)

static func _pylon_slots() -> int:
	return int(CHUNK_LEN / PYLON_SPACING)

static func _building_slots() -> int:
	return int(CHUNK_LEN / BUILDING_SPACING)

static func _lamp_slots() -> int:
	return int(CHUNK_LEN / LAMP_SPACING)

# ---------- collision (reused bodies) ----------
#
# Real "Dirt"-group collision spanning the sidewalk band on one side for this
# whole chunk. Created once per side and RESHAPED on rebuild -- the shape
# resource is reused. It is tapered exactly like the sidewalk strip (issue
# #35), so the grip change and the height step sit under the drawn curb edge
# all along a lane-count change.
#
# Since #37 it is a triangle mesh of the sidewalk's ramp and top, following
# the centreline, instead of a convex prism: a prism cannot follow a bend, and
# ten convex pieces per side (Godot builds a hull for each) made the sidewalk
# a third of a chunk rebuild. Wheels and the chassis only ever meet the ramp
# and the top; the out-of-bounds wall stands just behind the outer edge.

static func _new_sidewalk_collision(body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.add_to_group("Kerb")  # CarSpec gives the "Kerb" surface its own grip numbers
	body.collision_layer = 1 << (CarSpec.KERB_LAYER - 1)  # wheels only, see CarSpec
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var tri := ConcavePolygonShape3D.new()
	tri.backface_collision = true  # met from either side, whatever the winding
	col.shape = tri
	body.add_child(col)
	return body

static func _update_sidewalk_collision(root: Node3D, body_name: String, inner0: float, inner1: float, outer0: float, outer1: float, side: int, ts: PackedFloat32Array = PackedFloat32Array(), hs: PackedFloat32Array = PackedFloat32Array(), group: StringName = &"Kerb") -> void:
	var body: StaticBody3D = root.get_node(NodePath(body_name))
	# The surface is the body's FIRST group (GEVP): "Kerb" for a pavement,
	# "Grass" for a freeway's verge. Only one is ever on the body.
	for g in [&"Kerb", &"Grass"]:
		if g != group and body.is_in_group(g):
			body.remove_from_group(g)
	if not body.is_in_group(group):
		body.add_to_group(group)
	# chunk start is z=0, end is z=-CHUNK_LEN; top at 0.15 like the old box.
	# Points are in chunk-local space, so the body sits at origin.
	#
	# The road-side edge is a ramp, not a wall (2026-10-06): it rises from the
	# ground at the drawn sidewalk edge to full height SIDEWALK_RAMP further in.
	# It used to be a 0.05-0.15 m vertical lip, and the chassis collision box
	# rides within a few cm of the ground, so steering onto the sidewalk at a
	# shallow angle could catch the box square on that lip and stop the car
	# dead (tests/audio/car_audio.gd's kerb phase, once the ground became a plane in
	# PR #129). A sloped face pushes the box up instead.
	#
	# The back edge is a ramp too (2026-10-09): a district setback (buildings
	# step 4) leaves a drivable lot behind the sidewalk, and a car scraping the
	# set-back wall at speed ran its inside wheels into the bare 0.15 m back
	# lip where it shifts between chunks and rolled over (tests/car/wall_hit.gd).
	#
	# STATIONS pieces along the chunk, each corner through the centreline
	# frame (#37); on a straight centreline the ramp and top are exactly the
	# old prism's. Plus the kerb's own rows (`ts`, pavements step 1) where a
	# dropped kerb lowers the top with the drawn pavement by `hs`.
	var sx := float(side)
	var faces := PackedVector3Array()
	var rows := _uniform_rows(STATIONS)
	if ts.size() > 2:
		rows.append_array(ts)
		rows.sort()
	for k in rows.size() - 1:
		var t0 := rows[k]
		var t1 := rows[k + 1]
		if t1 - t0 < 1e-4:
			continue
		var z0 := -CHUNK_LEN * t0
		var z1 := -CHUNK_LEN * t1
		var h0 := _col_h(hs, ts, z0)
		var h1 := _col_h(hs, ts, z1)
		var i0 := lerpf(inner0, inner1, t0)
		var i1 := lerpf(inner0, inner1, t1)
		var o0 := lerpf(outer0, outer1, t0)
		var o1 := lerpf(outer0, outer1, t1)
		var ramp0 := minf(SIDEWALK_RAMP, absf(o0 - i0) / 2.0)
		var ramp1 := minf(SIDEWALK_RAMP, absf(o1 - i1) / 2.0)
		var foot0 := _at(i0 * sx, 0.0, z0)
		var foot1 := _at(i1 * sx, 0.0, z1)
		var lip0 := _at((i0 + ramp0) * sx, h0, z0)
		var lip1 := _at((i1 + ramp1) * sx, h1, z1)
		var top0 := _at((o0 - ramp0) * sx, h0, z0)
		var top1 := _at((o1 - ramp1) * sx, h1, z1)
		var back0 := _at(o0 * sx, 0.0, z0)
		var back1 := _at(o1 * sx, 0.0, z1)
		faces.append_array([foot0, foot1, lip0, lip0, foot1, lip1])  # the ramp
		faces.append_array([lip0, lip1, top0, top0, lip1, top1])     # the top
		faces.append_array([top0, top1, back0, back0, top1, back1])  # the back ramp
	((body.get_node(^"Shape") as CollisionShape3D).shape as ConcavePolygonShape3D).set_faces(faces)
	body.position = Vector3.ZERO

# Invisible out-of-bounds wall (#28). Buildings are 22 m apart, so on their
# own they leave gaps onto open, drivable slab. One reused box per side runs
# the whole chunk just behind the sidewalk, at the building fronts' line.
# It sits at the WIDER of the chunk's two ends so it never cuts into the
# sidewalk on a taper; at the narrow end it is simply hidden inside the
# buildings (they are 3-6 m deep). No group, so it is not a drivable surface.

static func _new_boundary(body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	CarSpec.make_wall(body)
	# One box per station (#37) so the wall can follow a bend.
	for k in STATIONS:
		var col := CollisionShape3D.new()
		col.name = "Shape" if k == 0 else "Shape%d" % k
		col.shape = BoxShape3D.new()
		body.add_child(col)
	return body

## Inner faces of a built chunk's two out-of-bounds walls, |x| from the centre
## line: (own side, oncoming side). What OffMapRescue tests the car against.
static func bounds(root: Node3D) -> Vector2:
	return root.get_meta(&"bounds", Vector2.ZERO)

## Boxes overlap their neighbours by this much, so the outside of a bend
## never opens a gap between two straight pieces.
const BOUNDARY_OVERLAP := 0.1

static func _update_boundary(root: Node3D, body_name: String, inner_x: float, side: int) -> void:
	var body: StaticBody3D = root.get_node(NodePath(body_name))
	var seg := CHUNK_LEN / STATIONS
	for k in STATIONS:
		var col: CollisionShape3D = body.get_node(NodePath("Shape" if k == 0 else "Shape%d" % k))
		var f := _foundation()
		(col.shape as BoxShape3D).size = Vector3(BOUNDARY_T, BOUNDARY_H + f, seg + BOUNDARY_OVERLAP)
		col.transform = _xf_up((inner_x + BOUNDARY_T / 2.0) * float(side), (BOUNDARY_H - f) / 2.0, -seg * (float(k) + 0.5))
	body.position = Vector3.ZERO

# Road collision (#37 step R5). On a flat road the wheels drive on game.gd's
# infinite ground plane; on a hilly one there is no single plane, so each
# chunk carries its own surface: quads across the whole drivable width (out
# past the out-of-bounds walls), following the centreline, in the "Road"
# group like the plane. Built always, switched on only with hills.
#
# How many quads (2026-10-10, road bumps). The surface used to be STATIONS
# flat 5 m pieces, one quad wide, whatever the road did. Two things about
# that kicked the wheels:
#
# - Along the road, where it bends vertically, each piece meets the next at
#   a small angle (1/80 on a 400 m sag), and a wheel crossing that edge has
#   its spring speed jump by speed x angle: 0.4 m/s at 120 km/h, every 5 m,
#   which is a bump you feel. So such chunks get shorter pieces, enough that
#   no edge turns more than ROAD_COL_KINK (ROAD_COL_MAX_ROWS at most).
# - Across the road, on a bend that also climbs, the inside of the bend is
#   shorter than the outside, so it climbs more steeply. A quad's two flat
#   triangles each have one slope, the inside edge's and the outside edge's,
#   and a wheel crossing the diagonal between them jumps by speed x grade x
#   quad width / bend radius: up to 0.28 m/s at 120 km/h on one 50 m wide quad,
#   every piece. So such chunks are cut into ROAD_COL_LANE_COLS columns a side
#   across the lanes (one more a side covers the rest, which nothing drives).
#
# A straight, evenly sloped chunk keeps the old 10 quads. The heights come
# straight from the road's formula (RoadAlignment), not from the centreline's
# 1 m bake: rows between baked points would just sit on the chord.

## Most an edge between two road collision pieces may turn, radians. A wheel
## at 200 km/h has its spring speed change by 39 mm/s over one (the car's own
## noise on the flat plane is 30-55, tests/world/hill_bumps.gd).
const ROAD_COL_KINK := 0.0007
## Most pieces along a chunk: 0.5 m each.
const ROAD_COL_MAX_ROWS := 100
## Columns a side across the lanes of a chunk that both bends and slopes.
const ROAD_COL_LANE_COLS := 4
## Half-width they cover, m: the widest road's lanes and shoulder.
const ROAD_COL_LANE_HALF := MAX_OWN_LANES * LANE_W + MEDIAN_GAP + SHOULDER_W

## Pieces along (x) and across (y) a chunk's road collision: k and g are its
## curvature and start grade, vc its vertical curvature, dc_in / dc_out the
## vertical curvature steps eased in around its start and end
## (RoadAlignment.vstep).
static func road_collision_grid(k: float, g: float, vc: float, dc_in: float = 0.0, dc_out: float = 0.0) -> Vector2i:
	# The sharpest vertical bend anywhere in the chunk: its own, or the eased
	# value at either end.
	var bend := maxf(absf(vc), maxf(absf(vc - 0.5 * dc_in), absf(vc + 0.5 * dc_out)))
	var rows := STATIONS
	if bend > 1e-9:
		rows = clampi(ceili(CHUNK_LEN * bend / ROAD_COL_KINK), STATIONS, ROAD_COL_MAX_ROWS)
	var cols := 1
	if absf(k) > 1e-9 and (absf(g) > 1e-6 or bend > 1e-9):
		cols = 2 * ROAD_COL_LANE_COLS + 2
	return Vector2i(rows, cols)

## The chunk _apply() is laying out: start grade, vertical curvature and the
## eased curvature steps at its two ends.
static var _vert := [0.0, 0.0, 0.0, 0.0]

## How far past the out-of-bounds walls the road collision reaches, m.
const ROAD_COL_MARGIN := 2.0

static func _new_road_collision() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "RoadCol"
	body.add_to_group("Road")
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var tri := ConcavePolygonShape3D.new()
	tri.backface_collision = true  # met from either side, whatever the winding
	col.shape = tri
	col.disabled = true
	body.add_child(col)
	return body

static func _update_road_collision(root: Node3D, half_w: float) -> void:
	var col: CollisionShape3D = root.get_node(^"RoadCol/Shape")
	var tri: ConcavePolygonShape3D = col.shape
	if not RoadFrame.has_hills():
		col.disabled = true
		tri.set_faces(PackedVector3Array())
		return
	var g0: float = _vert[0]
	var vc: float = _vert[1]
	var dc_in: float = _vert[2]
	var dc_out: float = _vert[3]
	var grid := road_collision_grid(_curve_k, g0, vc, dc_in, dc_out)
	var n := grid.x
	var cols := grid.y
	# Column edges across the road, left to right.
	var xs := PackedFloat32Array([-half_w, half_w])
	if cols > 1:
		xs.resize(cols + 1)
		var w := minf(ROAD_COL_LANE_HALF, half_w * 0.8) / ROAD_COL_LANE_COLS
		xs[0] = -half_w
		for j in 2 * ROAD_COL_LANE_COLS + 1:
			xs[j + 1] = w * float(j - ROAD_COL_LANE_COLS)
		xs[cols] = half_w
	var faces := PackedVector3Array()
	faces.resize(6 * n * cols)
	var last := int(CHUNK_LEN) - 1
	var prev := PackedVector3Array()
	var cur := PackedVector3Array()
	prev.resize(cols + 1)
	cur.resize(cols + 1)
	var q := 0
	for r in n + 1:
		# One row of points: level, square to the road, at the height the
		# road's own formula gives (the chunk root sits at its start height).
		var s := CHUNK_LEN * float(r) / float(n)
		var i := mini(int(s), last)
		var t := s - float(i)
		var o := _frame_o[i].lerp(_frame_o[i + 1], t)
		var f := _frame_f[i].lerp(_frame_f[i + 1], t)
		var right := Vector3(-f.z, 0.0, f.x).normalized()
		o.y = RoadAlignment.ease_rise(g0, vc, dc_in, dc_out, s)
		for j in cols + 1:
			cur[j] = o + right * xs[j]
		if r > 0:
			for j in cols:
				var a := prev[j]
				var b := prev[j + 1]
				var c := cur[j]
				var d := cur[j + 1]
				faces[q] = a; faces[q + 1] = c; faces[q + 2] = b
				faces[q + 3] = b; faces[q + 4] = c; faces[q + 5] = d
				q += 6
		var swap := prev
		prev = cur
		cur = swap
	tri.set_faces(faces)
	col.disabled = false

## The district cross wall: spans x between the two boundary lines (xs.x and
## xs.y, both |x|) at the chunk's start, z = 0. Disabled when there is no step.
## A setback step wall: one box across the lot at the chunk start. Not
## _new_boundary(): that makes one box per station (#37), and _update_step
## sizes only "Shape", so the spare unit boxes would stick out of the wall.
static func _new_step(body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	CarSpec.make_wall(body)
	var col := CollisionShape3D.new()
	col.name = "Shape"
	col.shape = BoxShape3D.new()
	body.add_child(col)
	return body

static func _update_step(root: Node3D, body_name: String, xs: Vector2, side: int, on: bool) -> void:
	var body: StaticBody3D = root.get_node(NodePath(body_name))
	var col: CollisionShape3D = body.get_node(^"Shape")
	col.disabled = not on
	var x0 := minf(xs.x, xs.y)
	var x1 := maxf(xs.x, xs.y) + BOUNDARY_T
	(col.shape as BoxShape3D).size = Vector3(maxf(x1 - x0, 0.1), BOUNDARY_H, BOUNDARY_T)
	body.transform = _xf_up((x0 + x1) / 2.0 * float(side), BOUNDARY_H / 2.0, -BOUNDARY_T / 2.0)
	body.set_meta("step", on)

# ---------- buildings (reused nodes) ----------
#
# Buildings keep one MeshInstance3D + one StaticBody3D each rather than
# becoming a MultiMesh: every one needs a real collision body anyway (they
# are the drivable world's hard boundary -- see file header), and the
# per-node building_type="garage" meta that milestone 8 is meant to reuse
# cannot live on a MultiMesh instance.
#
# Buildings step 1 (2026-10-07): every building now shares one unit cube and
# one facade ShaderMaterial (scripts/world/building_kit.gd). The facade is mapped
# from the building's own size in the shader, not from BoxMesh UVs, so the
# node is simply scaled; tile, tint, floor count and lit-window density are
# per-instance shader parameters.
#
# The look is drawn from a per-building RNG seeded by chunk index, slot and
# the building's footprint, NOT from the global random sequence: the global
# calls below are kept exactly as before (4 per building, in the same
# order), so the road layout game.gd
# rolls after each chunk is unchanged for any seed, and a chunk rebuilt from
# the pool looks the same as one built fresh.

static var _bld_rng := RandomNumberGenerator.new()
## On a loop (road_map.gd) a lot's four draws come from here, seeded by the
## chunk's place on the loop, so the same buildings stand there every lap and
## when the player turns round and comes back.
static var _lot_rng := RandomNumberGenerator.new()

static func _new_building(index: int) -> Array:
	var mi := MeshInstance3D.new()
	mi.name = "BuildingMesh%d" % index
	mi.mesh = BuildingKit.unit_box()
	var body := StaticBody3D.new()
	body.name = "BuildingBody%d" % index
	CarSpec.make_wall(body)
	var col := CollisionShape3D.new()
	col.name = "Shape"
	col.shape = BoxShape3D.new()
	body.add_child(col)
	return [mi, body]

## Returns the building's length along the road (its z size, so the gap
## walls can fill what is left between buildings), its type and sign, and
## where its front face is.
static func _update_building(root: Node3D, index: int, edge_x_abs: float, z: float, side: int, chunk_index: int = 0, draws: Array = []) -> Dictionary:
	var mi: MeshInstance3D = root.get_node(NodePath("BuildingMesh%d" % index))
	var body: StaticBody3D = root.get_node(NodePath("BuildingBody%d" % index))
	var col: CollisionShape3D = body.get_node(^"Shape")
	var box: BoxShape3D = col.shape

	# Stage A: longer frontages (d, along the road) so the street reads as a
	# continuous built-up corridor; w is how deep the block goes.
	# Keep these four global calls exactly as they are (see the section
	# comment; randf_range() takes more draws than randf(), so even swapping
	# one for the other shifts the road layout).
	var is_garage: bool
	var w_draw: float
	var d_draw: float
	var h_old: float
	if RoadMap.is_loop():
		chunk_index = RoadMap.lap_chunk(chunk_index)
		_lot_rng.seed = hash([RoadMap.road_id, chunk_index, index, "lot"])
		is_garage = _lot_rng.randf() < 0.12
		w_draw = _lot_rng.randf_range(4.0, 10.0)
		d_draw = _lot_rng.randf_range(9.0, 18.0)
		h_old = _lot_rng.randf_range(3.0, 4.5) if is_garage else _lot_rng.randf_range(6.0, 22.0)
	elif not draws.is_empty():
		# a staged rebuild took them when it began (_building_draws)
		is_garage = draws[0]
		w_draw = draws[1]
		d_draw = draws[2]
		h_old = draws[3]
	else:
		is_garage = randf() < 0.12
		w_draw = randf_range(4.0, 10.0)
		d_draw = randf_range(9.0, 18.0)
		h_old = randf_range(3.0, 4.5) if is_garage else randf_range(6.0, 22.0)
	var h_roll := inverse_lerp(3.0, 4.5, h_old) if is_garage else inverse_lerp(6.0, 22.0, h_old)

	# w and d come from the global sequence, so the look changes from run to
	# run with the road while a rebuild of the same chunk still matches
	_bld_rng.seed = hash([chunk_index, index, w_draw, d_draw])
	# Districts (step 4) remap the same draws onto their own footprint
	# ranges, push the fronts back by the chunk's setback, and leave some
	# slots as empty lots (the gap walls close them).
	var spec := Districts.spec(Districts.name_for_building(chunk_index, _bld_rng.randf()))
	# World step 1: one skyline landmark per district run, on a fixed slot of
	# a fixed chunk. Its building is pinned (type, height, biggest footprint,
	# never an empty lot); RoofProps puts the landmark itself on top.
	var landmark := Districts.landmark_at(chunk_index, index)
	if landmark != "":
		spec = Districts.landmark_spec(spec, landmark)
	var w: float = lerpf(spec.w[0], spec.w[1], inverse_lerp(4.0, 10.0, w_draw))
	var d: float = lerpf(spec.d[0], spec.d[1], inverse_lerp(9.0, 18.0, d_draw))
	var front := edge_x_abs + BUILDING_GAP + Districts.setback_at(chunk_index)
	if _bld_rng.randf() < float(spec.gap):
		mi.visible = false
		col.disabled = true
		box.size = Vector3(w, 1.0, d)
		mi.transform = _xf_up((front + w / 2.0) * float(side), 0.5, z, Basis.from_scale(box.size))
		body.transform = _xf_up((front + w / 2.0) * float(side), 0.5, z)
		mi.set_meta("building_type", "lot")
		for k in ["sign_word", "facade_tile", "roof_top", "landmark", "shop_front"]:
			if mi.has_meta(k):
				mi.remove_meta(k)
		return {"empty": true, "d": 0.0, "z": z, "side": side}
	mi.visible = true
	col.disabled = false
	var info := BuildingKit.dress(mi, _bld_rng, is_garage, h_roll, w, d, spec)
	var h: float = info.h
	# Special buildings (step 5) stand at the back of their lot: a gas
	# station's kiosk behind its canopy, a diner behind its pole sign. The
	# forecourt is behind the out-of-bounds wall like any building's
	# footprint, so it is scenery, not a place to drive (yet).
	var lot_front := front
	if info.type == "gas" or info.type == "diner":
		var lot := 16.0 if info.type == "gas" else 11.0
		var body_w := 7.0
		front = lot_front + lot - body_w
		w = body_w
	# Through the centreline frame (#37); on a hilly road the block reaches
	# FOUNDATION below the road so its downhill end never floats. The facade
	# counts floors up from the road ("base"), not from the block's bottom.
	var f := _foundation()
	var size := Vector3(w, h + f, d)
	mi.set_instance_shader_parameter("size", size)
	mi.set_instance_shader_parameter("base", f)
	mi.transform = _xf_up((front + w / 2.0) * float(side), (h - f) / 2.0, z, Basis.from_scale(size))
	box.size = size
	body.transform = _xf_up((front + w / 2.0) * float(side), (h - f) / 2.0, z)
	info["empty"] = false
	info["d"] = d
	info["w"] = w
	info["front_x_abs"] = front
	info["lot_front_x_abs"] = lot_front
	info["z"] = z
	info["side"] = side
	return info

## City lights (Junction, J0): a building whose frontage overlaps the
## crossing's corner is turned into an empty lot (no mesh, no collision, no
## sign). _update_building has already taken its random draws, so the road
## layout is the same with the switch on or off.
static func _clear_at_junction(root: Node3D, index: int, info: Dictionary, chunk_index: int) -> Dictionary:
	if info.empty:
		return info
	var z0 := float(info.z) + float(info.d) / 2.0
	var z1 := float(info.z) - float(info.d) / 2.0
	# a gas station (own side only) clears its lot the same way
	if not Junction.cleared(chunk_index, z0, z1) and not (int(info.side) == 1 and GasStation.cleared(chunk_index, z0, z1)):
		return info
	var mi: MeshInstance3D = root.get_node(NodePath("BuildingMesh%d" % index))
	var body: StaticBody3D = root.get_node(NodePath("BuildingBody%d" % index))
	mi.visible = false
	(body.get_node(^"Shape") as CollisionShape3D).disabled = true
	mi.set_meta("building_type", "lot")
	return {"empty": true, "d": 0.0, "z": info.z, "side": info.side}

## World step 6 (W7): a building slot that opens onto a side street is an
## empty lot MOUTH_HALF * 2 wide, so the gap walls leave the mouth open the
## way they leave a crossing's. The draws were taken by _update_building,
## so the road layout is the same with the mouths on or off.
static func _clear_for_mouth(root: Node3D, index: int, info: Dictionary, mouth: Dictionary) -> Dictionary:
	if mouth.is_empty():
		return info
	var mi: MeshInstance3D = root.get_node(NodePath("BuildingMesh%d" % index))
	var body: StaticBody3D = root.get_node(NodePath("BuildingBody%d" % index))
	mi.visible = false
	(body.get_node(^"Shape") as CollisionShape3D).disabled = true
	mi.set_meta("building_type", "mouth")
	return {"empty": true, "d": SideStreets.MOUTH_HALF * 2.0, "z": info.z, "side": info.side, "mouth": true}

## Shop and garage signs (buildings step 2): one lightbox per signed
## building, on its front just above the ground floor, from one MultiMesh.
static func _update_signs(root: Node3D, infos: Array) -> int:
	var mm: MultiMesh = (root.get_node(^"Signs") as MultiMeshInstance3D).multimesh
	var n := 0
	var xfs := []
	var anchors := PackedFloat32Array()
	for info in infos:
		if info.empty or info.sign == "":
			continue
		anchors.append(float(info.z))
		var fh: float = info.floor_h
		var garage: bool = info.type == "garage"
		var x: float = float(info.front_x_abs) * float(info.side)
		var lot_x: float = float(info.lot_front_x_abs) * float(info.side)
		if info.type == "gas":
			# fascia along the front edge of the canopy
			xfs.append(BuildingSigns.place(mm, n, info.sign, info.sign_color, info.sign_style, Vector3(lot_x + 0.4 * float(info.side), 5.0, info.z), info.side, 0.6, 6.0))
		elif info.type == "diner":
			# high on its pole, square-on to the oncoming traffic
			xfs.append(BuildingSigns.place(mm, n, info.sign, info.sign_color, info.sign_style, Vector3(lot_x + 1.2 * float(info.side), 7.8, float(info.z) + float(info.d) * 0.35), info.side, 1.6, 4.5, false, PI / 2.0))
		elif info.blade:
			# over the sidewalk, clear of a car roof, one floor up; on a one-floor
			# shop that would be above the roof, so it hangs under the roofline
			xfs.append(BuildingSigns.place(mm, n, info.sign, info.sign_color, info.sign_style, Vector3(x, minf(fh + 0.9, float(info.h) - 0.45), info.z), info.side, 0.8, 2.0, true))
		else:
			# shop: the dark band at the top of the shopfront glass; garage:
			# over the roller doors
			var sh := 0.6 if garage else 0.75
			var y: float = fh - (0.45 if garage else 0.42)
			xfs.append(BuildingSigns.place(mm, n, info.sign, info.sign_color, info.sign_style, Vector3(x, y, info.z), info.side, sh, float(info.d) * 0.8))
		n += 1
	mm.visible_instance_count = n
	_bend_instances(mm, 0, xfs, anchors)
	return n

## Rooftop props and billboards (buildings step 3); billboard faces take
## the sign slots after the shop signs.
static func _update_roofs(root: Node3D, infos: Array, signs_used: int) -> void:
	var props: MultiMesh = (root.get_node(^"RoofProps") as MultiMeshInstance3D).multimesh
	var signs: MultiMesh = (root.get_node(^"Signs") as MultiMeshInstance3D).multimesh
	var r := RoofProps.update(props, infos, signs, signs_used, _foundation())
	signs.visible_instance_count = r.signs
	_bend_instances(props, 0, r.prop_xfs, r.prop_anchor)
	_bend_instances(signs, signs_used, r.sign_xfs, r.sign_anchor)
	root.set_meta("roof_props", r.props)

## Where an area sign's post stands, past the sidewalk's outer edge, m.
const NAME_SIGN_SETBACK := 0.25
## Where along its chunk (chunk-local z) the area gantry and the advance sign
## stand: the gantry in the last chunk before an area, the advance sign a
## whole number of chunks further back (PlaceNames.ADVANCE_M).
const GANTRY_Z := -42.0
const ADVANCE_Z := -2.0

## Which area sign, if any, belongs to chunk `chunk_index`: "" (none), "gantry"
## or "advance"; the area it announces is Districts.name_of_run(run + 1).
static func name_sign_kind(chunk_index: int) -> String:
	if chunk_index < 0:
		return ""
	var ahead := int(round(PlaceNames.ADVANCE_M / CHUNK_LEN))
	if posmod(chunk_index + 1, Districts.RUN) == 0:
		return "gantry"
	if posmod(chunk_index + 1 + ahead, Districts.RUN) == 0:
		return "advance"
	return ""

## Area signs (world step 4, "Names you can read"): the gantry in the last
## chunk before an area and the advance sign 400 m earlier, drawn from this
## chunk's one NameSigns MultiMesh. Zero instances on every other chunk.
static func _update_names(root: Node3D, chunk_index: int, walk0: float, walk1: float) -> void:
	var mmi := root.get_node(^"NameSigns") as MultiMeshInstance3D
	var mm: MultiMesh = mmi.multimesh
	var kind := name_sign_kind(chunk_index)
	if RoadSigns.has_flag("hide"):
		mmi.visible = kind != ""
	if kind == "":
		mm.visible_instance_count = 0
		return
	var area := PlaceNames.area_name(Districts.name_of_run(Districts.run_of(chunk_index) + 1))
	var z := GANTRY_Z if kind == "gantry" else ADVANCE_Z
	var x := lerpf(walk0, walk1, -z / CHUNK_LEN) + NAME_SIGN_SETBACK
	var foot := Vector3(x, 0.0, z)
	var burnt := -1
	if kind == "gantry":
		var hb := posmod(hash([chunk_index, "floodlight"]), 6)
		burnt = hb if hb < 3 else -1
	# With "cache" the parts come laid out around a foot at the origin, once
	# per area, and only move to this chunk's foot here.
	var cached := RoadSigns.has_flag("cache")
	var list: Array
	if cached:
		list = RoadSigns.parts_at_origin(kind, area, _foundation(), burnt)
	elif kind == "gantry":
		list = RoadSigns.gantry(area, foot, _foundation(), burnt)
	else:
		list = RoadSigns.advance(area, foot, _foundation())
	var n := mini(list.size(), mm.instance_count)
	var xfs := []
	var anchors := PackedFloat32Array()
	for k in n:
		var xf: Transform3D = list[k].xf
		if cached:
			xf.origin += foot
		xfs.append(xf)
		anchors.append(z)
		mm.set_instance_custom_data(k, list[k].cd)
	mm.visible_instance_count = n
	_bend_instances(mm, 0, xfs, anchors)

## Painted road words and arrows (RoadPaint.marks decides which): flat decals
## laid on the road surface through the centreline frame, so they follow a
## bend or a hill. Zero instances on most chunks.
static func _update_paint(root: Node3D, chunk_index: int, lanes_changed: bool, own_lanes: int) -> void:
	var mmi := root.get_node(^"RoadPaint") as MultiMeshInstance3D
	var mm: MultiMesh = mmi.multimesh
	var crossing := Junction.local_centre(chunk_index) if Junction.enabled else INF
	var marks := RoadPaint.marks(chunk_index, Districts.name_at(chunk_index), Districts.RUN, own_lanes, lanes_changed, crossing, MEDIAN_GAP, LANE_W, CHUNK_LEN)
	var n := mini(marks.size(), mm.instance_count)
	if RoadSigns.has_flag("hide"):
		mmi.visible = n > 0
	for k in n:
		var m: Dictionary = marks[k]
		mm.set_instance_transform(k, _xf(m.x, RoadPaint.PAINT_Y, m.z, m.basis))
		mm.set_instance_custom_data(k, m.cd)
	mm.visible_instance_count = n

## Signs and roof props are laid out on the straight road description; this
## writes instances from slot `from` on through the centreline frame (#37),
## each one rigid with the building it belongs to: `anchors[k]` is that
## building's road z, and the piece keeps its offset from there in the
## building's own frame (heading and height at the anchor), so a roof prop
## sits exactly on its flat roof on a slope instead of following the road
## grade at its own spot (up to 0.45 m off on a 5% grade, the residue PR
## #318 noted). On a straight, flat road this is the plain transform.
##
## The straight transforms come from the callers' arrays, never from
## mm.get_instance_transform(): with physics interpolation on (project
## setting, ISSUES B7) that getter returns the data last drawn, which on a
## pooled chunk rebuilt in the game is the previous occupant's. The old
## read-modify-write here put those stale props back, so office roof tanks
## hung 40 m over a one-floor lot (floating structures, 2026-10-09).
static func _bend_instances(mm: MultiMesh, from: int, xfs: Array, anchors: PackedFloat32Array) -> void:
	for k in xfs.size():
		var t: Transform3D = xfs[k]
		var a := float(anchors[k])
		mm.set_instance_transform(from + k, _xf_up(0.0, 0.0, a) * Transform3D(t.basis, Vector3(t.origin.x, t.origin.y, t.origin.z - a)))

# ---------- build / rebuild ----------

## Creates the fixed node skeleton for a chunk: ten strips, two collision
## bodies plus two out-of-bounds walls, seven MultiMeshInstance3D (pylons x2, dashes x2, lamps, lamp
## pools, gap walls), the barrier, and the building pairs.
## Runs ONCE per pooled chunk root -- everything after that is an in-place
## update, which is the whole point of the recycle path below.
static func _create_nodes(root: Node3D) -> void:
	root.add_child(_new_centerline())
	root.add_child(_new_strip("RoadOwn", _get_own_mat()))
	root.add_child(_new_strip("RoadOnc", _get_onc_mat()))
	root.add_child(_new_strip("EdgeLineOwn", _get_edge_line_mat()))
	root.add_child(_new_strip("EdgeLineOnc", _get_edge_line_mat()))
	root.add_child(_new_strip("ShoulderOwn", _get_shoulder_mat()))
	root.add_child(_new_strip("ShoulderOnc", _get_shoulder_mat()))
	root.add_child(_new_strip("GutterOwn", _get_gutter_mat()))
	root.add_child(_new_strip("GutterOnc", _get_gutter_mat()))
	root.add_child(_new_strip("CurbOwn", _get_curb_mat()))
	root.add_child(_new_strip("CurbOnc", _get_curb_mat()))
	root.add_child(_new_strip("SidewalkOwn", _get_sidewalk_mat()))
	root.add_child(_new_strip("SidewalkOnc", _get_sidewalk_mat()))

	root.add_child(_new_road_collision())
	root.add_child(_new_sidewalk_collision("SidewalkColOwn"))
	root.add_child(_new_sidewalk_collision("SidewalkColOnc"))
	root.add_child(_new_boundary("BoundaryOwn"))
	root.add_child(_new_boundary("BoundaryOnc"))
	root.add_child(_new_step("BoundaryStepOwn"))
	root.add_child(_new_step("BoundaryStepOnc"))

	var slots := _dash_slots()
	root.add_child(_new_multimesh("PylonsOwn", _get_pylon_mesh(), _get_pylon_mat_own(), _pylon_slots()))
	root.add_child(_new_multimesh("PylonsOnc", _get_pylon_mesh(), _get_pylon_mat_onc(), _pylon_slots()))
	root.add_child(_new_multimesh("CenterDashes", _get_center_dash_mesh(), _get_center_dash_mat(), slots))
	# Worst case: every interior divider on both sides at max lane count.
	var max_dividers := (MAX_OWN_LANES - 1) + (MAX_ONC_LANES - 1)
	root.add_child(_new_multimesh("LaneDashes", _get_lane_dash_mesh(), _get_lane_dash_mat(), max_dividers * slots))

	# Stage A roadside detail: street lamps (both sides in one buffer), their
	# light pools, and the walls between buildings. Capacity is the worst case,
	# allocated once, like the dashes and pylons above.
	# World step 6 (W7): plus one lamp and pool per side-street mouth.
	root.add_child(_new_multimesh("Lamps", _get_lamp_mesh(), null, _lamp_slots() * 2 + SideStreets.CAPACITY))
	# Pavements step 1: at most one hydrant per side, on the pavement by the kerb.
	root.add_child(_new_multimesh("Hydrants", _get_hydrant_mesh(), _get_hydrant_mat(), 2))
	root.add_child(_new_multimesh("Drains", _get_drain_mesh(), _get_drain_mat(), DRAIN_MAX * 2))
	root.add_child(_new_multimesh("LampPools", _get_pool_mesh(), _get_pool_mat(), _lamp_slots() * 2 + SideStreets.CAPACITY))
	# living world step 2: moths, banners, steam and litter (lamp_life.gd)
	LampLife.create_nodes(root, _lamp_slots() * 2)
	# Fake wet-road reflections (RESEARCH-cheap-pretty item 7): one additive
	# streak on the tarmac under each lamp head, placed with the pools.
	var smears := _new_multimesh("LampSmears", WetReflections.quad_mesh(), WetReflections.lamp_mat(), _lamp_slots() * 2)
	smears.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(smears)
	# Visible puddles (S1a): one flat quad per grip puddle of this chunk
	# (scripts/world/puddles.gd), placed in _apply from the same seeded list
	# the tyres read, so the water the eye sees is the water the car feels.
	root.add_child(RoadWet.new_puddle_multimesh(_puddles().MAX_PER_CHUNK))
	# World step 6: side-street mouths (W7) and the animals' eyes (A1).
	for n in SideStreets.new_nodes():
		root.add_child(n)
	root.add_child(StreetAnimals.new_multimesh())
	# Per side: a gap either side of each building, +1 for the district step
	# wall, +1 more
	# where a crossing's mouth (Junction) splits a gap in two
	root.add_child(_new_multimesh("GapWalls", _get_wall_mesh(), _get_wall_mat(), (_building_slots() + 3) * 2))

	# The centre barrier, one piece per station so it can follow a bend (#37).
	# Its reflectors are a child with one piece per station too, placed with
	# the same transforms, so they show and bend with it.
	# R1 (RoadBarriers): its mesh is swapped per barrier type, the reflectors
	# have two more slots for the crash cushions at a crossover, and the
	# barrier and cushions are real collision.
	var barrier_mmi := _new_multimesh("Barrier", _get_barrier_mesh(), _get_barrier_mat(), STATIONS)
	var refl := _new_multimesh("Reflectors", _get_reflector_mesh(), null, STATIONS + 2)
	refl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	refl.extra_cull_margin = 1.0
	barrier_mmi.add_child(refl)
	root.add_child(barrier_mmi)
	root.add_child(_new_multimesh("Cushions", RoadBarriers.cushion_mesh(), null, 2))
	RoadBarriers.new_bodies(root)

	for i in range(_building_slots() * 2):
		for n in _new_building(i):
			root.add_child(n)
	# shop signs plus rooftop billboards: at most two per building
	root.add_child(BuildingSigns.new_multimesh(_building_slots() * 4))
	root.add_child(RoofProps.new_multimesh())
	# Roadside kit (hydrants, bins, dumpsters, cones, work-zone jersey
	# barriers, kerb guardrail): one MultiMesh per kind and two collision
	# bodies, see roadside_kit.gd.
	Kit.new_nodes(root)
	# area signs (names you can read) and painted road words: zero instances
	# shown on most chunks
	if not RoadSigns.off():
		root.add_child(RoadSigns.new_multimesh())
		root.add_child(RoadPaint.new_multimesh())

	root.set_meta("nodes_built", true)

## Rewrites an already-built chunk skeleton for a new position/config. No
## node is created, freed, or reparented here -- this is what replaces the
## old queue_free()-everything teardown.
##
## origin_index is the floating-origin offset (game.gd, issue #26): the chunk
## that currently sits at world z=0. The subtraction is done in ints BEFORE
## converting to float, so a chunk millions of indices out still lands on an
## exact, small coordinate instead of a rounded huge one.
static func _apply(root: Node3D, chunk_index: int, prev_cfg: Dictionary, cfg: Dictionary, origin_index: int = 0, job: RebuildJob = null) -> void:
	root.name = "Chunk_%d" % chunk_index
	# Where the road's shape (RoadFrame / RoadAlignment, #37) puts this chunk;
	# on a straight road that is (0, 0, -(chunk_index - origin_index) * 50).
	root.transform = RoadFrame.chunk_xf(chunk_index, origin_index)
	if job != null:
		# Parked PARK_BELOW under its place until the last stage: out of every
		# camera and the fog, with its collision off, while the stages rewrite
		# it. (Not visible = false: the dummy renderer of a headless run drops
		# the instance data of a hidden MultiMesh.)
		root.transform = root.transform.translated(Vector3(0.0, PARK_BELOW, 0.0))
		root.set_meta("rebuilding", true)
		root.reset_physics_interpolation()
	root.set_meta("chunk_index", chunk_index)
	_curve_k = RoadFrame.curvature(chunk_index)
	_vert[0] = RoadFrame.start_grade(chunk_index)
	_vert[1] = RoadFrame.vcurve(chunk_index)
	_vert[2] = RoadFrame.vstep(chunk_index)
	_vert[3] = RoadFrame.vstep(chunk_index + 1)
	_curve = _update_centerline(root, _curve_k, _vert[0], _vert[1], _vert[2], _vert[3])
	_cache_frames(_curve)
	# Its own curvatures only: a level chunk easing into a neighbour's hill
	# leaves a single flat strip by 5 mm at most (RoadAlignment.EASE).
	_strip_n = strip_pieces(_curve_k, _vert[1])

	var own_lanes: int = clampi(int(cfg.own_lanes), 1, MAX_OWN_LANES)
	var onc_lanes: int = clampi(int(cfg.onc_lanes), 1, MAX_ONC_LANES)
	# cfg.barrier: a RoadBarriers type ("" for none), or the old bool (true
	# = concrete). cfg.gap: this chunk holds its district's crossover.
	# City lights (Junction, J0): no centre barrier on a chunk the crossing
	# touches. Read here, not rolled in game.gd's _section_at, so the road
	# layout's random sequence is the same with the switch on or off.
	var barrier_kind := _barrier_kind(cfg)
	if Junction.touches(chunk_index):
		barrier_kind = RoadBarriers.NONE
	var barrier := barrier_kind != RoadBarriers.NONE
	var start_own_w := _lane_w(prev_cfg.own_lanes)
	var end_own_w := _lane_w(own_lanes)
	var start_onc_w := _lane_w(prev_cfg.onc_lanes)
	var end_onc_w := _lane_w(onc_lanes)

	# road surfaces (tapered)
	_update_strip(root, "RoadOwn", 0.0, 0.0, start_own_w, end_own_w)
	_update_strip(root, "RoadOnc", 0.0, 0.0, -start_onc_w, -end_onc_w)

	# solid edge line along each lane's OUTER boundary -- distinct from the
	# dashed interior lane splits handled further below
	_update_strip(root, "EdgeLineOwn", start_own_w - 0.12, end_own_w - 0.12, start_own_w + 0.03, end_own_w + 0.03, 0.012)
	_update_strip(root, "EdgeLineOnc", -(start_onc_w - 0.12), -(end_onc_w - 0.12), -(start_onc_w + 0.03), -(end_onc_w + 0.03), 0.012)

	# shoulders (tapered, flush with the road edge)
	# The cross-section table (Districts.cross_at, pavements step 2) sets the
	# shoulder, pavement and kerb height; each tapers from the previous
	# chunk's value to this one's.
	var sec0 := Districts.cross_at(chunk_index - 1)
	var sec1 := Districts.cross_at(chunk_index)
	var start_shoulder_w := float(sec0.shoulder)
	var end_shoulder_w := float(sec1.shoulder)
	var start_own_shoulder := start_own_w + start_shoulder_w
	var end_own_shoulder := end_own_w + end_shoulder_w
	var start_onc_shoulder := start_onc_w + start_shoulder_w
	var end_onc_shoulder := end_onc_w + end_shoulder_w
	# The shoulder's last GUTTER_W is the gutter, a separate strip dipping
	# to the kerb foot (pavements step 1).
	_update_strip(root, "ShoulderOwn", start_own_w, end_own_w, start_own_shoulder - GUTTER_W, end_own_shoulder - GUTTER_W)
	_update_strip(root, "ShoulderOnc", -start_onc_w, -end_onc_w, -(start_onc_shoulder - GUTTER_W), -(end_onc_shoulder - GUTTER_W))
	var gutter_rows := _uniform_rows(_strip_n)
	_update_profile_strip(root, "GutterOwn", start_own_shoulder - GUTTER_W, end_own_shoulder - GUTTER_W, start_own_shoulder, end_own_shoulder, _gutter_profile(), gutter_rows)
	_update_profile_strip(root, "GutterOnc", -(start_onc_shoulder - GUTTER_W), -(end_onc_shoulder - GUTTER_W), -start_onc_shoulder, -end_onc_shoulder, _gutter_profile(), gutter_rows)

	# curb -- a raised edge, crossable, NOT a collision wall (see file
	# header). Drawn further down, once the buildings say where it drops.
	var start_own_curb := start_own_shoulder + CURB_W
	var end_own_curb := end_own_shoulder + CURB_W
	var start_onc_curb := start_onc_shoulder + CURB_W
	var end_onc_curb := end_onc_shoulder + CURB_W

	# sidewalk -- drivable, lower grip (comes from the Dirt collision below).
	# Its width is district data (Districts.walk_at; all 2.2 m until
	# pavements step 2), tapered from the previous chunk's like the lanes.
	var start_walk_w := float(sec0.walk)
	var end_walk_w := float(sec1.walk)
	var start_own_walk := start_own_curb + start_walk_w
	var end_own_walk := end_own_curb + end_walk_w
	var start_onc_walk := start_onc_curb + start_walk_w
	var end_onc_walk := end_onc_curb + end_walk_w

	# out-of-bounds walls, at the same set-back _update_building() uses
	# (plus the district's setback: strip malls sit behind a drivable lot)
	var setback := Districts.setback_at(chunk_index)
	var bound_own := maxf(start_own_walk, end_own_walk) + BUILDING_GAP + setback
	var bound_onc := maxf(start_onc_walk, end_onc_walk) + BUILDING_GAP + setback
	_update_boundary(root, "BoundaryOwn", bound_own, 1)
	_update_boundary(root, "BoundaryOnc", bound_onc, -1)
	root.set_meta(&"bounds", Vector2(bound_own, bound_onc))
	# Where the setback changes from the previous chunk, a cross wall at this
	# chunk's start closes the step between the two boundary lines, so the
	# deeper lot does not open behind the shallower chunk's wall.
	var prev_setback := Districts.setback_at(chunk_index - 1)
	var step_own := Vector2(bound_own, start_own_walk + BUILDING_GAP + prev_setback)
	var step_onc := Vector2(bound_onc, start_onc_walk + BUILDING_GAP + prev_setback)
	_update_step(root, "BoundaryStepOwn", step_own, 1, absf(setback - prev_setback) > 0.01)
	_update_step(root, "BoundaryStepOnc", step_onc, -1, absf(setback - prev_setback) > 0.01)
	_update_road_collision(root, maxf(bound_own, bound_onc) + BOUNDARY_T + ROAD_COL_MARGIN)

	if job != null:
		job.keep(_curve_k, _vert, _strip_n)
		await job.go
		_prime(root, job)
	# edge pylons -- cosmetic rhythm/speed cues, interpolated along each
	# shoulder's outer edge between this chunk's start and end width
	var pylons_own: MultiMesh = (root.get_node(^"PylonsOwn") as MultiMeshInstance3D).multimesh
	var pylons_onc: MultiMesh = (root.get_node(^"PylonsOnc") as MultiMeshInstance3D).multimesh
	var n_pylons := _pylon_slots()
	var n_posts := 0
	for i in range(n_pylons):
		var pz := -float(i) * PYLON_SPACING - PYLON_SPACING / 2.0
		if Junction.in_mouth(chunk_index, pz):
			continue  # none across the crossing's mouth
		var pt: float = -pz / CHUNK_LEN
		var own_edge: float = lerp(start_own_shoulder, end_own_shoulder, pt)
		var onc_edge: float = lerp(start_onc_shoulder, end_onc_shoulder, pt)
		# a gas station bay: the own post is parked out of sight (the two sides
		# share one instance count)
		var own_y := -50.0 if GasStation.in_bay(chunk_index, pz) else PYLON_HEIGHT / 2.0
		pylons_own.set_instance_transform(n_posts, _xf_up(own_edge, own_y, pz))
		pylons_onc.set_instance_transform(n_posts, _xf_up(-onc_edge, PYLON_HEIGHT / 2.0, pz))
		n_posts += 1
	pylons_own.visible_instance_count = n_posts
	pylons_onc.visible_instance_count = n_posts

	if job != null:
		job.keep(_curve_k, _vert, _strip_n)
		await job.go
		_prime(root, job)
	# roadside buildings -- real collision, the world's actual hard boundary
	var n_buildings := _building_slots()
	var spans := {1: [], -1: []}  # per side: [z_front, z_back] of each building
	var infos := []
	# World step 6 (W7): the slots that open onto a side street this chunk
	var mouths: Array = SideStreets.mouths_at(chunk_index)
	for i in range(n_buildings):
		var bz := -float(i) * BUILDING_SPACING - BUILDING_SPACING / 2.0
		var bt: float = -bz / CHUNK_LEN
		var own_edge_b: float = lerp(start_own_walk, end_own_walk, bt)
		var onc_edge_b: float = lerp(start_onc_walk, end_onc_walk, bt)
		var own_info := _clear_at_junction(root, i * 2, _update_building(root, i * 2, own_edge_b, bz, 1, chunk_index, job.draws[i * 2] if job != null and not job.draws.is_empty() else []), chunk_index)
		var onc_info := _clear_at_junction(root, i * 2 + 1, _update_building(root, i * 2 + 1, onc_edge_b, bz, -1, chunk_index, job.draws[i * 2 + 1] if job != null and not job.draws.is_empty() else []), chunk_index)
		own_info = _clear_for_mouth(root, i * 2, own_info, SideStreets.mouth_for(mouths, 1, i))
		onc_info = _clear_for_mouth(root, i * 2 + 1, onc_info, SideStreets.mouth_for(mouths, -1, i))
		infos.append(own_info)
		infos.append(onc_info)
		var d_own: float = own_info.d
		var d_onc: float = onc_info.d
		spans[1].append([bz + d_own / 2.0, bz - d_own / 2.0])
		spans[-1].append([bz + d_onc / 2.0, bz - d_onc / 2.0])

	var signs_used := _update_signs(root, infos)
	root.set_meta("signs_used", signs_used)
	_update_roofs(root, infos, signs_used)
	if not RoadSigns.off():
		_update_names(root, chunk_index, start_own_walk, end_own_walk)
		_update_paint(root, chunk_index, int(prev_cfg.own_lanes) != own_lanes, own_lanes)

	if job != null:
		job.keep(_curve_k, _vert, _strip_n)
		await job.go
		_prime(root, job)
	# kerb, pavement, their collision and the hydrants (pavements step 1).
	# Dropped kerbs: a DROP_HALF opening centred on each building front the
	# district lists as a car-park entrance (Districts.drops), and the whole
	# of the crossing's mouth. Yellow paint: PAINT_REACH back from the mouth
	# on both sides of the crossing, and PAINT_HALF either side of a hydrant.
	var hydrants: MultiMesh = (root.get_node(^"Hydrants") as MultiMeshInstance3D).multimesh
	var n_hydrants := 0
	var drains: MultiMesh = (root.get_node(^"Drains") as MultiMeshInstance3D).multimesh
	var n_drains := 0
	var drop_types: Array = sec1.drops
	var kh0 := float(sec0.kerb_h)
	var kh1 := float(sec1.kerb_h)
	var flat := maxf(kh0, kh1) < FLAT_BELOW  # a freeway's verge: no hydrants, paint or drains
	var verge := not bool(sec1.kerb)
	var all_types := drop_types.has("*")
	for side in [1, -1]:
		var drops: Array = []
		var paint: Array = []
		for info in infos:
			if int(info.side) != side or bool(info.empty):
				continue
			if all_types or drop_types.has(String(info.type)):
				drops.append([float(info.z), DROP_HALF])
		for m in mouths:  # a side street's mouth drops the kerb like a crossing's (W7)
			if int(m.side) == side:
				drops.append([float(m.z), SideStreets.MOUTH_HALF])
		if Junction.touches(chunk_index):
			var jc := Junction.local_centre(chunk_index)
			drops.append([jc, Junction.MOUTH_HALF])
			var reach := PAINT_REACH / 2.0
			paint.append([jc + Junction.MOUTH_HALF + reach, reach])
			paint.append([jc - Junction.MOUTH_HALF - reach, reach])
		# one hydrant on HYDRANT_CHANCE % of chunk sides, 8..42 m in, hashed
		# so a recycled chunk matches a fresh one and the road's RNG is untouched
		var hroll := posmod(hash([chunk_index, side, "hydrant"]), 100)
		var hz := -8.0 - float(posmod(hash([chunk_index, side, "hydrant_z"]), 35))
		var hydrant_ok := not flat and hroll < HYDRANT_CHANCE and not Junction.near(chunk_index, hz, Junction.CLEAR_HALF + PAINT_HALF)
		for d in drops:
			if absf(hz - float(d[0])) < float(d[1]) + DROP_RAMP + PAINT_HALF:
				hydrant_ok = false
		if hydrant_ok:
			paint.append([hz, PAINT_HALF])
		var ts := _kerb_rows(drops, paint)
		var ds := _kerb_heights(drops, ts)
		var cols := _kerb_colours(paint, ts)
		# The district's kerb height, tapered from the previous chunk's: `hs`
		# scales the drawn kerb (1 = KERB_H), `ch` is the collision top in
		# metres: the drawn pavement plus COL_EXTRA (less on a low kerb).
		var hs := PackedFloat32Array()
		var ch := PackedFloat32Array()
		hs.resize(ts.size())
		ch.resize(ts.size())
		for r in ts.size():
			var kh := lerpf(kh0, kh1, ts[r])
			hs[r] = ds[r] * kh / KERB_H
			ch[r] = ds[r] * (kh + COL_EXTRA * clampf(kh / KERB_H, 0.0, 1.0))
		var sh0: float = start_own_shoulder if side == 1 else start_onc_shoulder
		var sh1: float = end_own_shoulder if side == 1 else end_onc_shoulder
		var cb0: float = start_own_curb if side == 1 else start_onc_curb
		var cb1: float = end_own_curb if side == 1 else end_onc_curb
		var wk0: float = start_own_walk if side == 1 else start_onc_walk
		var wk1: float = end_own_walk if side == 1 else end_onc_walk
		var sx := float(side)
		var suffix := "Own" if side == 1 else "Onc"
		_update_profile_strip(root, "Curb" + suffix, sh0 * sx, sh1 * sx, cb0 * sx, cb1 * sx, _kerb_profile(), ts, hs, cols)
		_update_profile_strip(root, "Sidewalk" + suffix, cb0 * sx, cb1 * sx, wk0 * sx, wk1 * sx, _walk_profile(), ts, hs)
		_update_sidewalk_collision(root, "SidewalkCol" + suffix, cb0, cb1, wk0, wk1, side, ts, ch, &"Grass" if verge else &"Kerb")
		if hydrant_ok:
			var ht: float = -hz / CHUNK_LEN
			var hx: float = lerpf(cb0, cb1, ht) + HYDRANT_SETBACK
			hydrants.set_instance_transform(n_hydrants, _xf_up(hx * sx, KERB_H * _drop_at(hs, ts, hz), hz))
			n_hydrants += 1
		# Drains (K4): a grate in the gutter, hashed per chunk side and slot,
		# clear of the crossing, every dropped kerb and the hydrant's paint.
		if not flat:
			for k in DRAIN_MAX:
				if posmod(hash([chunk_index, side, "drain", k]), 100) >= DRAIN_CHANCE:
					continue
				var dz := -4.0 - 22.0 * float(k) - float(posmod(hash([chunk_index, side, "drain_z", k]), 18))
				var clear := not Junction.near(chunk_index, dz, Junction.MOUTH_HALF + 1.0)
				for d in drops:
					if absf(dz - float(d[0])) < float(d[1]) + DROP_RAMP + DRAIN_LEN:
						clear = false
				if hydrant_ok and absf(dz - hz) < PAINT_HALF + DRAIN_LEN:
					clear = false
				if not clear:
					continue
				var dt: float = -dz / CHUNK_LEN
				var dx: float = lerpf(sh0, sh1, dt) - GUTTER_W / 2.0
				drains.set_instance_transform(n_drains, _xf_up(dx * sx, -GUTTER_DIP / 2.0, dz))
				n_drains += 1
	hydrants.visible_instance_count = n_hydrants
	drains.visible_instance_count = n_drains

	if job != null:
		job.keep(_curve_k, _vert, _strip_n)
		await job.go
		_prime(root, job)
	# gap walls (stage A) -- close the open lots between buildings along the
	# building-front line. Visual only: out-of-bounds collision is issue #28,
	# which is being worked on separately, so it is deliberately not done here.
	var walls: MultiMesh = (root.get_node(^"GapWalls") as MultiMeshInstance3D).multimesh
	var n_walls := 0
	for side in [1, -1]:
		var walk0: float = start_own_walk if side == 1 else start_onc_walk
		var walk1: float = end_own_walk if side == 1 else end_onc_walk
		var z_from := 0.0
		var edges: Array = spans[side].duplicate()
		if Junction.touches(chunk_index):
			# the crossing's mouth is an opening like a building's frontage
			var jc := Junction.local_centre(chunk_index)
			edges.append([jc + Junction.MOUTH_HALF, jc - Junction.MOUTH_HALF])
			edges.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		edges.append([-CHUNK_LEN, -CHUNK_LEN])
		for e in edges:
			var z_to: float = e[0]
			var length := z_from - z_to
			if length > 0.3:
				var zc := (z_from + z_to) / 2.0
				var x: float = lerp(walk0, walk1, -zc / CHUNK_LEN) + BUILDING_GAP + setback + WALL_T / 2.0
				var f := _foundation()
				var basis := Basis.from_scale(Vector3(WALL_T, WALL_H + f, length))
				walls.set_instance_transform(n_walls, _xf_up(x * float(side), (WALL_H - f) / 2.0, zc, basis))
				n_walls += 1
			z_from = minf(z_from, e[1]) if Junction.touches(chunk_index) else e[1]
		# the district step: a visible wall across the lot edge, where the
		# invisible cross wall stands
		var step: Vector2 = step_own if side == 1 else step_onc
		if absf(setback - prev_setback) > 0.01:
			var sx := absf(step.x - step.y)
			var basis2 := Basis.from_scale(Vector3(sx, WALL_H, WALL_T))
			walls.set_instance_transform(n_walls, Transform3D(basis2, Vector3((step.x + step.y) / 2.0 * float(side), WALL_H / 2.0, -WALL_T / 2.0)))
			n_walls += 1
	walls.visible_instance_count = n_walls

	if job != null:
		job.keep(_curve_k, _vert, _strip_n)
		await job.go
		_prime(root, job)
	# street lamps + their light pools (stage A). Pole just outside the curb,
	# arm over the road; the oncoming side is the same mesh turned 180 deg.
	var lamps: MultiMesh = (root.get_node(^"Lamps") as MultiMeshInstance3D).multimesh
	var pools: MultiMesh = (root.get_node(^"LampPools") as MultiMeshInstance3D).multimesh
	var smears: MultiMesh = (root.get_node(^"LampSmears") as MultiMeshInstance3D).multimesh
	var n_lamps := 0
	var lamp_zs := {1: [], -1: []}  # pole z per side, for the roadside kit's bins
	for i in range(_lamp_slots()):
		for side in [1, -1]:
			# own side at 6.25, 31.25 m; oncoming at 18.75, 43.75 m into the chunk
			var lz := -float(i) * LAMP_SPACING - (LAMP_SPACING * 0.25 if side == 1 else LAMP_SPACING * 0.75)
			if Junction.in_mouth(chunk_index, lz):
				continue  # the signal masts stand there
			if side == 1 and GasStation.in_bay(chunk_index, lz):
				continue  # the gas station canopy lights the bay
			lamp_zs[side].append(lz)
			var lt: float = -lz / CHUNK_LEN
			var curb: float = lerp(start_own_curb, end_own_curb, lt) if side == 1 else lerp(start_onc_curb, end_onc_curb, lt)
			var pole_x := (curb + LAMP_SETBACK) * float(side)
			var turn := Basis() if side == 1 else Basis(Vector3.UP, PI)
			lamps.set_instance_transform(n_lamps, _xf_up(pole_x, 0.0, lz, turn))
			var head_x := pole_x - (LAMP_ARM - 0.2) * float(side)
			pools.set_instance_transform(n_lamps, _xf(head_x, POOL_Y, lz, Basis.from_scale(Vector3(POOL_ACROSS, 1.0, POOL_ALONG))))
			smears.set_instance_transform(n_lamps, _xf(head_x, WetReflections.SMEAR_Y, lz, WetReflections.lamp_smear_basis()))
			n_lamps += 1
	# side-street mouths (W7): the kit, its props, and one more lamp and pool each
	var mouth_edges := PackedFloat32Array()
	for m in mouths:
		var mt: float = -float(m.z) / CHUNK_LEN
		mouth_edges.append(lerpf(start_own_walk, end_own_walk, mt) if int(m.side) == 1 else lerpf(start_onc_walk, end_onc_walk, mt))
	n_lamps += SideStreets.update(root, mouths, mouth_edges, lamps, pools, n_lamps)
	lamps.visible_instance_count = n_lamps
	pools.visible_instance_count = n_lamps
	smears.visible_instance_count = n_lamps
	var lamp_xfs := []
	for k in range(n_lamps):
		lamp_xfs.append(lamps.get_instance_transform(k))
	LampLife.apply(root, chunk_index, Districts.name_at(chunk_index), lamp_xfs, _xf(0.0, 0.0, -CHUNK_LEN * 0.5),
		-(start_onc_w + end_onc_w) * 0.5, (start_own_w + end_own_w) * 0.5)
	# animals at shop fronts and alley mouths (A1): placed now, their eyes
	# shine per frame from StreetAnimals.step (game.gd)
	StreetAnimals.update(root, chunk_index, infos, mouths, [start_own_walk, end_own_walk, start_onc_walk, end_onc_walk], setback)

	if job != null:
		job.keep(_curve_k, _vert, _strip_n)
		await job.go
		_prime(root, job)
	# roadside kit: laid out from the edges above (so a width change moves
	# it), the lamps (bins stand at their feet) and the lots a car can drive
	# into (dumpsters at their back wall).
	var kit_edges := {
		1: {"road": [start_own_w, end_own_w], "curb_in": [start_own_shoulder, end_own_shoulder],
			"curb_out": [start_own_curb, end_own_curb], "walk": [start_own_walk, end_own_walk]},
		-1: {"road": [start_onc_w, end_onc_w], "curb_in": [start_onc_shoulder, end_onc_shoulder],
			"curb_out": [start_onc_curb, end_onc_curb], "walk": [start_onc_walk, end_onc_walk]},
	}
	var lots := {1: [], -1: []}
	for info in infos:
		lots[int(info.side)].append([float(info.z), (BUILDING_SPACING * 0.6) if info.empty else float(info.d)])
	Kit.apply(root, chunk_index, kit_edges, setback, lamp_zs, lots)

	# puddles: road-space s along the road (chunk c covers [c * L, (c + 1) * L))
	# becomes chunk-local z = -(s - c * L); x is already across the road.
	var puddles: MultiMesh = (root.get_node(^"Puddles") as MultiMeshInstance3D).multimesh
	var plist: PackedFloat32Array = _puddles().of_chunk(chunk_index)
	var n_puddles := 0
	var pi := 0
	while pi < plist.size():
		var pz := -(plist[pi] - float(chunk_index) * CHUNK_LEN)
		puddles.set_instance_transform(n_puddles, _xf(plist[pi + 1], RoadWet.PUDDLE_Y, pz, RoadWet.puddle_basis(plist[pi + 2], plist[pi + 3])))
		puddles.set_instance_color(n_puddles, RoadWet.puddle_colour(int(plist[pi + 4])))
		n_puddles += 1
		pi += 5  # Puddles.STRIDE
	puddles.visible_instance_count = n_puddles

	if job != null:
		job.keep(_curve_k, _vert, _strip_n)
		await job.go
		_prime(root, job)
	# center line / barrier -- snapped to this chunk's own end-of-chunk
	# config, not tapered (see file header). Both the wall and the dash
	# buffer always exist; only one of them is shown.
	var slots := _dash_slots()
	var center: MultiMesh = (root.get_node(^"CenterDashes") as MultiMeshInstance3D).multimesh
	RoadBarriers.apply(root, chunk_index, barrier_kind, bool(cfg.get("gap", false)))
	if barrier:
		center.visible_instance_count = 0
	else:
		var n_center := 0
		for i in range(slots):
			var dz := -float(i) * DASH_SPACING - DASH_SPACING / 2.0
			if Junction.in_box(chunk_index, dz):
				continue  # no markings inside the crossing
			center.set_instance_transform(n_center, _xf(0.0, DASH_Y, dz))
			n_center += 1
		center.visible_instance_count = n_center

	# interior lane dividers, both directions packed into one instance
	# buffer; unused capacity is simply left outside visible_instance_count
	var lane: MultiMesh = (root.get_node(^"LaneDashes") as MultiMeshInstance3D).multimesh
	var written := 0
	for lane_i in range(1, own_lanes):
		var x: float = MEDIAN_GAP + lane_i * LANE_W
		for i in range(slots):
			var dz2 := -float(i) * DASH_SPACING - DASH_SPACING / 2.0
			if Junction.in_box(chunk_index, dz2):
				continue
			lane.set_instance_transform(written, _xf(x, DASH_Y, dz2))
			written += 1
	for lane_i in range(1, onc_lanes):
		var x2: float = -(MEDIAN_GAP + lane_i * LANE_W)
		for i in range(slots):
			var dz3 := -float(i) * DASH_SPACING - DASH_SPACING / 2.0
			if Junction.in_box(chunk_index, dz3):
				continue
			lane.set_instance_transform(written, _xf(x2, DASH_Y, dz3))
			written += 1
	lane.visible_instance_count = written
	if job != null:
		# Into place. job.origin_index is kept current by game.gd across a
		# floating-origin shift that lands mid-job.
		root.set_meta("rebuilding", false)
		root.transform = RoadFrame.chunk_xf(chunk_index, job.origin_index)
		_set_solid(root, true)
		root.reset_physics_interpolation()
		sync_collision(root)
		job.done = true

# ---------- staged rebuild (chunk rebuild budget, #314) ----------
# TEST BUILD port: #314 cut _apply() into stage functions; every world branch
# has since rewritten that body, so here the same body pauses between its
# sections instead (a coroutine: its locals carry over), which keeps the
# intent (a recycled chunk costs a slice per frame, not ~3 ms in one frame;
# parked below and not solid until done) without a second copy of the body.
# As in #314 the global random draws of the buildings are taken when the
# rebuild begins (_building_draws), so spreading it changes no layout.

## The stages of a rebuild, in order; one rebuild_step() call runs one.
const STAGES: Array[String] = ["strips", "pylons", "buildings", "kerbs", "walls", "lamps", "kit", "dashes"]

## How far under its place a chunk is parked while its rebuild is in flight.
const PARK_BELOW := -1000.0

class RebuildJob extends RefCounted:
	signal go
	var root: Node3D
	var index := 0
	var prev_cfg: Dictionary
	var cfg: Dictionary
	var origin_index := 0
	var stage := 0
	var done := false
	# the per-chunk statics of the builder, kept across the frames between stages
	var curve_k := 0.0
	var vert := [0.0, 0.0, 0.0, 0.0]
	var strip_n := 1
	# the four global random draws of each building slot, taken at rebuild_begin
	var draws: Array = []

	func keep(k: float, v: Array, n: int) -> void:
		curve_k = k
		vert = v.duplicate()
		strip_n = n

## Spike attribution (spike_log.gd): logs the stage that ended now. Free unless the benchmark is running.
static func _stage(tag: String, since_usec: int) -> void:
	if SpikeLog.enabled:
		SpikeLog.mark(tag, SpikeLog.since(since_usec))

## The collision bodies of the chunk: on, or off (layer 0) while a staged
## rebuild is in flight, so a half-rewritten sidewalk or wall never meets a
## wheel. The real layer of each body is kept in meta the first time it is
## switched off.
static func _set_solid(root: Node3D, on: bool) -> void:
	for c in root.get_children():
		if c is CollisionObject3D:
			var body := c as CollisionObject3D
			if on:
				if body.has_meta("layer"):
					body.collision_layer = body.get_meta("layer")
			else:
				if not body.has_meta("layer"):
					body.set_meta("layer", body.collision_layer)
				body.collision_layer = 0

## Primes the static centreline/frame cache and shape for this chunk: the
## stages run on different frames, and another chunk (or a test) may have
## been built in between.
static func _prime(root: Node3D, job: RebuildJob) -> void:
	_curve = (root.get_node(^"Centerline") as Path3D).curve
	_cache_frames(_curve)
	_curve_k = job.curve_k
	for i in 4:
		_vert[i] = job.vert[i]
	_strip_n = job.strip_n

## Starts a rebuild of a pooled chunk and returns its job; rebuild_step()
## runs it a stage at a time. Until the job finishes the chunk is parked and
## its collision is off, so nothing meets a half-rewritten chunk.
static func rebuild_begin(root: Node3D, chunk_index: int, prev_cfg: Dictionary, cfg: Dictionary, origin_index: int = 0) -> RebuildJob:
	if not root.has_meta("nodes_built"):
		_create_nodes(root)
	_set_solid(root, false)
	var job := RebuildJob.new()
	job.root = root
	job.index = chunk_index
	job.prev_cfg = prev_cfg
	job.cfg = cfg
	job.origin_index = origin_index
	job.draws = _building_draws()
	return job

## The global random draws _update_building() would take for every building
## slot of a chunk, in its order (own side then oncoming, slot by slot), so
## a rebuild spread over frames, with traffic spawns drawing in between,
## still lays out the same road for a seed. None on a loop road: its lots
## come from their own seeded generator.
static func _building_draws() -> Array:
	var out := []
	if RoadMap.is_loop():
		return out
	for i in _building_slots() * 2:
		var is_garage := randf() < 0.12
		var w_draw := randf_range(4.0, 10.0)
		var d_draw := randf_range(9.0, 18.0)
		var h_old := randf_range(3.0, 4.5) if is_garage else randf_range(6.0, 22.0)
		out.append([is_garage, w_draw, d_draw, h_old])
	return out

## True while a staged rebuild of this chunk is in flight.
static func is_rebuilding(root: Node3D) -> bool:
	return root.get_meta("rebuilding", false)

## Runs the next stage of the job. Returns true when the job is done (and
## the chunk is in place and solid again). A chunk freed under the job
## (scene restart) ends it.
static func rebuild_step(job: RebuildJob) -> bool:
	if job.done or not is_instance_valid(job.root):
		return true
	var t0 := Time.get_ticks_usec()
	if job.stage == 0:
		_apply(job.root, job.index, job.prev_cfg, job.cfg, job.origin_index, job)
	else:
		job.go.emit()
	_stage("chunk/" + STAGES[mini(job.stage, STAGES.size() - 1)], t0)
	job.stage += 1
	return job.done

## Builds a fresh chunk root positioned at world Z = -(chunk_index - origin_index) * CHUNK_LEN,
## spanning from z=0 to z=-CHUNK_LEN locally.
static func build_chunk(chunk_index: int, prev_cfg: Dictionary, cfg: Dictionary, origin_index: int = 0) -> Node3D:
	var root := Node3D.new()
	# The world is static between rebuilds: a chunk only moves in _process
	# (recycle, floating-origin recenter), never per physics tick, so there
	# is nothing for physics interpolation to smooth. Off, the renderer skips
	# interpolating every MultiMesh instance buffer in the chunk each frame
	# (dashes, pylons, lamps, walls, signs...) and stops warning that the
	# buffers were written from outside the physics step (perf pass
	# 2026-10-09). Children inherit the mode.
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_create_nodes(root)
	_apply(root, chunk_index, prev_cfg, cfg, origin_index)
	return root

## The recycle path. Previously this queue_free()'d all ~70 children and
## rebuilt them from scratch, which at 55 m/s over a 50 m chunk meant a full
## teardown-and-reallocate roughly every 0.9 seconds -- a periodic stutter on
## a 15 W CPU. Now it only rewrites vertex data, transforms and shape sizes
## into nodes that already exist.
static func rebuild_chunk(root: Node3D, chunk_index: int, prev_cfg: Dictionary, cfg: Dictionary, origin_index: int = 0) -> void:
	if not root.has_meta("nodes_built"):
		_create_nodes(root)
	_apply(root, chunk_index, prev_cfg, cfg, origin_index)
	sync_collision(root)

## Hands a moved chunk's collision to the physics server now. Moving the
## chunk root only tells its bodies they moved when Godot next flushes
## transform notifications, but their reshaped pieces (sidewalk hulls, wall
## boxes) reach the server at once; for the physics ticks in between, the new
## pieces sat at the old chunk's place and angle. On the straight road the
## two layouts were the same, so nobody noticed; on a curved one (#37) a
## recycled chunk's sidewalk swept across the lanes for a tick and launched
## traffic cars (tests/world/curve_drive.gd, 2026-10-07).
static func sync_collision(root: Node3D) -> void:
	if not root.is_inside_tree():
		return
	root.force_update_transform()
	for c in root.get_children():
		if c is CollisionObject3D:
			(c as Node3D).force_update_transform()
