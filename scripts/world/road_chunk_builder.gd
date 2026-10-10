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
const Districts := preload("res://scripts/world/districts.gd")

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

static var _own_mat: StandardMaterial3D
static var _onc_mat: StandardMaterial3D
static var _shoulder_mat: StandardMaterial3D
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
static var _barrier_mesh: BoxMesh
static var _lamp_mesh: ArrayMesh
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

## Procedural asphalt-grain material: a small seamless noise texture mapped
## through a 2-color gradient, tiled via uv1_scale so it repeats along the
## chunk instead of stretching. Back faces are culled (the default), so the
## tapered strips below must wind their triangles to face up.
static func _asphalt_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var noise := FastNoiseLite.new()
	noise.seed = 1337
	noise.frequency = 0.6
	var tex := NoiseTexture2D.new()
	tex.width = 64
	tex.height = 64
	tex.seamless = true
	tex.noise = noise
	var grad := Gradient.new()
	grad.colors = PackedColorArray([color.darkened(0.2), color.lightened(0.1)])
	tex.color_ramp = grad
	m.albedo_texture = tex
	m.uv1_scale = Vector3(2.0, 6.0, 1.0)
	m.roughness = 0.9
	m.metallic = 0.0
	return m

static func _get_own_mat() -> StandardMaterial3D:
	if _own_mat == null:
		_own_mat = _asphalt_mat(Color(0.085, 0.085, 0.09))
	return _own_mat

static func _get_onc_mat() -> StandardMaterial3D:
	if _onc_mat == null:
		_onc_mat = _asphalt_mat(Color(0.08, 0.08, 0.085))
	return _onc_mat

static func _get_shoulder_mat() -> StandardMaterial3D:
	if _shoulder_mat == null:
		_shoulder_mat = _asphalt_mat(Color(0.055, 0.055, 0.058))
	return _shoulder_mat

## Curb: crossable rumble cue, not a wall (see file header). Light concrete
## (stage A: was a bright emissive strip, part of the neon look) so it still
## reads as the road's edge against the darker shoulder.
static func _get_curb_mat() -> StandardMaterial3D:
	if _curb_mat == null:
		_curb_mat = _flat_mat(Color(0.42, 0.41, 0.39), true, 0.12)
	return _curb_mat

## Sidewalk: flat, non-emissive concrete tone -- calm and neutral so it reads
## as a different surface without competing with the road.
static func _get_sidewalk_mat() -> StandardMaterial3D:
	if _sidewalk_mat == null:
		_sidewalk_mat = _asphalt_mat(Color(0.12, 0.115, 0.11))
	return _sidewalk_mat

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
varying float v_k;
void vertex() {
	vec3 c = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = max(-c.z, 0.05);
	v_k = 1.0 - smoothstep(fade.x, fade.y, d);
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

static func _get_barrier_mesh() -> BoxMesh:
	if _barrier_mesh == null:
		_barrier_mesh = _box_mesh(Vector3(BARRIER_W, BARRIER_H, CHUNK_LEN / STATIONS))
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

## The centreline of the chunk _apply() is laying out.
static var _curve: Curve3D
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
static func _update_centerline(root: Node3D, k: float, g: float = 0.0, vc: float = 0.0) -> Curve3D:
	var curve: Curve3D = (root.get_node(^"Centerline") as Path3D).curve
	curve.clear_points()
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
	body.add_to_group("Dirt")
	body.collision_layer = 1 << (CarSpec.KERB_LAYER - 1)  # wheels only, see CarSpec
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var tri := ConcavePolygonShape3D.new()
	tri.backface_collision = true  # met from either side, whatever the winding
	col.shape = tri
	body.add_child(col)
	return body

static func _update_sidewalk_collision(root: Node3D, body_name: String, inner0: float, inner1: float, outer0: float, outer1: float, side: int) -> void:
	var body: StaticBody3D = root.get_node(NodePath(body_name))
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
	# old prism's.
	var sx := float(side)
	var faces := PackedVector3Array()
	for k in STATIONS:
		var t0 := float(k) / STATIONS
		var t1 := float(k + 1) / STATIONS
		var z0 := -CHUNK_LEN * t0
		var z1 := -CHUNK_LEN * t1
		var i0 := lerpf(inner0, inner1, t0)
		var i1 := lerpf(inner0, inner1, t1)
		var o0 := lerpf(outer0, outer1, t0)
		var o1 := lerpf(outer0, outer1, t1)
		var ramp0 := minf(SIDEWALK_RAMP, absf(o0 - i0) / 2.0)
		var ramp1 := minf(SIDEWALK_RAMP, absf(o1 - i1) / 2.0)
		var foot0 := _at(i0 * sx, 0.0, z0)
		var foot1 := _at(i1 * sx, 0.0, z1)
		var lip0 := _at((i0 + ramp0) * sx, 0.15, z0)
		var lip1 := _at((i1 + ramp1) * sx, 0.15, z1)
		var top0 := _at((o0 - ramp0) * sx, 0.15, z0)
		var top1 := _at((o1 - ramp1) * sx, 0.15, z1)
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
# chunk carries its own surface: STATIONS quads across the whole drivable
# width (out past the out-of-bounds walls), following the centreline, in the
# "Road" group like the plane. Built always, switched on only with hills.

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
	var faces := PackedVector3Array()
	for k in STATIONS:
		var z0 := -CHUNK_LEN * float(k) / STATIONS
		var z1 := -CHUNK_LEN * float(k + 1) / STATIONS
		var a := _at(-half_w, 0.0, z0)
		var b := _at(half_w, 0.0, z0)
		var c := _at(-half_w, 0.0, z1)
		var d := _at(half_w, 0.0, z1)
		faces.append_array([a, c, b, b, c, d])
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
static func _update_building(root: Node3D, index: int, edge_x_abs: float, z: float, side: int, chunk_index: int = 0) -> Dictionary:
	var mi: MeshInstance3D = root.get_node(NodePath("BuildingMesh%d" % index))
	var body: StaticBody3D = root.get_node(NodePath("BuildingBody%d" % index))
	var col: CollisionShape3D = body.get_node(^"Shape")
	var box: BoxShape3D = col.shape

	# Stage A: longer frontages (d, along the road) so the street reads as a
	# continuous built-up corridor; w is how deep the block goes.
	# Keep these four global calls exactly as they are (see the section
	# comment; randf_range() takes more draws than randf(), so even swapping
	# one for the other shifts the road layout).
	var is_garage: bool = randf() < 0.12
	var w_draw: float = randf_range(4.0, 10.0)
	var d_draw: float = randf_range(9.0, 18.0)
	var h_old: float = randf_range(3.0, 4.5) if is_garage else randf_range(6.0, 22.0)
	var h_roll := inverse_lerp(3.0, 4.5, h_old) if is_garage else inverse_lerp(6.0, 22.0, h_old)

	# w and d come from the global sequence, so the look changes from run to
	# run with the road while a rebuild of the same chunk still matches
	_bld_rng.seed = hash([chunk_index, index, w_draw, d_draw])
	# Districts (step 4) remap the same draws onto their own footprint
	# ranges, push the fronts back by the chunk's setback, and leave some
	# slots as empty lots (the gap walls close them).
	var spec := Districts.spec(Districts.name_for_building(chunk_index, _bld_rng.randf()))
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
		for k in ["sign_word", "facade_tile"]:
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
	if info.empty or not Junction.cleared(chunk_index, float(info.z) + float(info.d) / 2.0, float(info.z) - float(info.d) / 2.0):
		return info
	var mi: MeshInstance3D = root.get_node(NodePath("BuildingMesh%d" % index))
	var body: StaticBody3D = root.get_node(NodePath("BuildingBody%d" % index))
	mi.visible = false
	(body.get_node(^"Shape") as CollisionShape3D).disabled = true
	mi.set_meta("building_type", "lot")
	return {"empty": true, "d": 0.0, "z": info.z, "side": info.side}

## Shop and garage signs (buildings step 2): one lightbox per signed
## building, on its front just above the ground floor, from one MultiMesh.
static func _update_signs(root: Node3D, infos: Array) -> int:
	var mm: MultiMesh = (root.get_node(^"Signs") as MultiMeshInstance3D).multimesh
	var n := 0
	for info in infos:
		if info.empty or info.sign == "":
			continue
		var fh: float = info.floor_h
		var garage: bool = info.type == "garage"
		var x: float = float(info.front_x_abs) * float(info.side)
		var lot_x: float = float(info.lot_front_x_abs) * float(info.side)
		if info.type == "gas":
			# fascia along the front edge of the canopy
			BuildingSigns.place(mm, n, info.sign, info.sign_color, info.sign_style, Vector3(lot_x + 0.4 * float(info.side), 5.0, info.z), info.side, 0.6, 6.0)
		elif info.type == "diner":
			# high on its pole, square-on to the oncoming traffic
			BuildingSigns.place(mm, n, info.sign, info.sign_color, info.sign_style, Vector3(lot_x + 1.2 * float(info.side), 7.8, float(info.z) + float(info.d) * 0.35), info.side, 1.6, 4.5, false, PI / 2.0)
		elif info.blade:
			# over the sidewalk, clear of a car roof, one floor up
			BuildingSigns.place(mm, n, info.sign, info.sign_color, info.sign_style, Vector3(x, fh + 0.9, info.z), info.side, 0.8, 2.0, true)
		else:
			# shop: the dark band at the top of the shopfront glass; garage:
			# over the roller doors
			var sh := 0.6 if garage else 0.75
			var y: float = fh - (0.45 if garage else 0.42)
			BuildingSigns.place(mm, n, info.sign, info.sign_color, info.sign_style, Vector3(x, y, info.z), info.side, sh, float(info.d) * 0.8)
		n += 1
	mm.visible_instance_count = n
	_bend_instances(mm, 0, n)
	return n

## Rooftop props and billboards (buildings step 3); billboard faces take
## the sign slots after the shop signs.
static func _update_roofs(root: Node3D, infos: Array, signs_used: int) -> void:
	var props: MultiMesh = (root.get_node(^"RoofProps") as MultiMeshInstance3D).multimesh
	var signs: MultiMesh = (root.get_node(^"Signs") as MultiMeshInstance3D).multimesh
	var counts := RoofProps.update(props, infos, signs, signs_used)
	signs.visible_instance_count = counts[1]
	_bend_instances(props, 0, counts[0])
	_bend_instances(signs, signs_used, counts[1])
	root.set_meta("roof_props", counts[0])

## Signs and roof props are laid out on the straight road description; this
## carries instances [from, to) through the centreline frame (#37), the same
## mapping _xf_up gives everything else. A no-op on a straight, flat road.
static func _bend_instances(mm: MultiMesh, from: int, to: int) -> void:
	for i in range(from, to):
		var t := mm.get_instance_transform(i)
		mm.set_instance_transform(i, _xf_up(t.origin.x, t.origin.y, t.origin.z, t.basis))

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
	root.add_child(_new_multimesh("Lamps", _get_lamp_mesh(), null, _lamp_slots() * 2))
	root.add_child(_new_multimesh("LampPools", _get_pool_mesh(), _get_pool_mat(), _lamp_slots() * 2))
	# Per side: a gap either side of each building, +1 for the district step
	# wall, +1 more
	# where a crossing's mouth (Junction) splits a gap in two
	root.add_child(_new_multimesh("GapWalls", _get_wall_mesh(), _get_wall_mat(), (_building_slots() + 3) * 2))

	# The centre barrier, one piece per station so it can follow a bend (#37).
	# Its reflectors are a child with one piece per station too, placed with
	# the same transforms, so they show and bend with it.
	var barrier_mmi := _new_multimesh("Barrier", _get_barrier_mesh(), _get_barrier_mat(), STATIONS)
	var refl := _new_multimesh("Reflectors", _get_reflector_mesh(), null, STATIONS)
	refl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	refl.extra_cull_margin = 1.0
	barrier_mmi.add_child(refl)
	root.add_child(barrier_mmi)

	for i in range(_building_slots() * 2):
		for n in _new_building(i):
			root.add_child(n)
	# shop signs plus rooftop billboards: at most two per building
	root.add_child(BuildingSigns.new_multimesh(_building_slots() * 4))
	root.add_child(RoofProps.new_multimesh())

	root.set_meta("nodes_built", true)

## Rewrites an already-built chunk skeleton for a new position/config. No
## node is created, freed, or reparented here -- this is what replaces the
## old queue_free()-everything teardown.
##
## origin_index is the floating-origin offset (game.gd, issue #26): the chunk
## that currently sits at world z=0. The subtraction is done in ints BEFORE
## converting to float, so a chunk millions of indices out still lands on an
## exact, small coordinate instead of a rounded huge one.
static func _apply(root: Node3D, chunk_index: int, prev_cfg: Dictionary, cfg: Dictionary, origin_index: int = 0) -> void:
	root.name = "Chunk_%d" % chunk_index
	# Where the road's shape (RoadFrame / RoadAlignment, #37) puts this chunk;
	# on a straight road that is (0, 0, -(chunk_index - origin_index) * 50).
	root.transform = RoadFrame.chunk_xf(chunk_index, origin_index)
	root.set_meta("chunk_index", chunk_index)
	_curve = _update_centerline(root, RoadFrame.curvature(chunk_index), RoadFrame.start_grade(chunk_index), RoadFrame.vcurve(chunk_index))
	_cache_frames(_curve)
	_strip_n = strip_pieces(RoadFrame.curvature(chunk_index), RoadFrame.vcurve(chunk_index))

	var own_lanes: int = clampi(int(cfg.own_lanes), 1, MAX_OWN_LANES)
	var onc_lanes: int = clampi(int(cfg.onc_lanes), 1, MAX_ONC_LANES)
	# City lights (Junction, J0): no centre barrier on a chunk the crossing
	# touches. Read here, not rolled in game.gd's _section_at, so the road
	# layout's random sequence is the same with the switch on or off.
	var barrier: bool = cfg.barrier and not Junction.touches(chunk_index)
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
	var start_own_shoulder := start_own_w + SHOULDER_W
	var end_own_shoulder := end_own_w + SHOULDER_W
	var start_onc_shoulder := start_onc_w + SHOULDER_W
	var end_onc_shoulder := end_onc_w + SHOULDER_W
	_update_strip(root, "ShoulderOwn", start_own_w, end_own_w, start_own_shoulder, end_own_shoulder)
	_update_strip(root, "ShoulderOnc", -start_onc_w, -end_onc_w, -start_onc_shoulder, -end_onc_shoulder)

	# curb -- crossable rumble strip, NOT a collision wall (see file header)
	var start_own_curb := start_own_shoulder + CURB_W
	var end_own_curb := end_own_shoulder + CURB_W
	var start_onc_curb := start_onc_shoulder + CURB_W
	var end_onc_curb := end_onc_shoulder + CURB_W
	_update_strip(root, "CurbOwn", start_own_shoulder, end_own_shoulder, start_own_curb, end_own_curb, 0.1)
	_update_strip(root, "CurbOnc", -start_onc_shoulder, -end_onc_shoulder, -start_onc_curb, -end_onc_curb, 0.1)

	# sidewalk -- drivable, lower grip (comes from the Dirt collision below)
	var start_own_walk := start_own_curb + SIDEWALK_W
	var end_own_walk := end_own_curb + SIDEWALK_W
	var start_onc_walk := start_onc_curb + SIDEWALK_W
	var end_onc_walk := end_onc_curb + SIDEWALK_W
	_update_strip(root, "SidewalkOwn", start_own_curb, end_own_curb, start_own_walk, end_own_walk, 0.1)
	_update_strip(root, "SidewalkOnc", -start_onc_curb, -end_onc_curb, -start_onc_walk, -end_onc_walk, 0.1)

	_update_sidewalk_collision(root, "SidewalkColOwn", start_own_curb, end_own_curb, start_own_walk, end_own_walk, 1)
	_update_sidewalk_collision(root, "SidewalkColOnc", start_onc_curb, end_onc_curb, start_onc_walk, end_onc_walk, -1)

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
		pylons_own.set_instance_transform(n_posts, _xf_up(own_edge, PYLON_HEIGHT / 2.0, pz))
		pylons_onc.set_instance_transform(n_posts, _xf_up(-onc_edge, PYLON_HEIGHT / 2.0, pz))
		n_posts += 1
	pylons_own.visible_instance_count = n_posts
	pylons_onc.visible_instance_count = n_posts

	# roadside buildings -- real collision, the world's actual hard boundary
	var n_buildings := _building_slots()
	var spans := {1: [], -1: []}  # per side: [z_front, z_back] of each building
	var infos := []
	for i in range(n_buildings):
		var bz := -float(i) * BUILDING_SPACING - BUILDING_SPACING / 2.0
		var bt: float = -bz / CHUNK_LEN
		var own_edge_b: float = lerp(start_own_walk, end_own_walk, bt)
		var onc_edge_b: float = lerp(start_onc_walk, end_onc_walk, bt)
		var own_info := _clear_at_junction(root, i * 2, _update_building(root, i * 2, own_edge_b, bz, 1, chunk_index), chunk_index)
		var onc_info := _clear_at_junction(root, i * 2 + 1, _update_building(root, i * 2 + 1, onc_edge_b, bz, -1, chunk_index), chunk_index)
		infos.append(own_info)
		infos.append(onc_info)
		var d_own: float = own_info.d
		var d_onc: float = onc_info.d
		spans[1].append([bz + d_own / 2.0, bz - d_own / 2.0])
		spans[-1].append([bz + d_onc / 2.0, bz - d_onc / 2.0])

	_update_roofs(root, infos, _update_signs(root, infos))

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

	# street lamps + their light pools (stage A). Pole just outside the curb,
	# arm over the road; the oncoming side is the same mesh turned 180 deg.
	var lamps: MultiMesh = (root.get_node(^"Lamps") as MultiMeshInstance3D).multimesh
	var pools: MultiMesh = (root.get_node(^"LampPools") as MultiMeshInstance3D).multimesh
	var n_lamps := 0
	for i in range(_lamp_slots()):
		for side in [1, -1]:
			# own side at 6.25, 31.25 m; oncoming at 18.75, 43.75 m into the chunk
			var lz := -float(i) * LAMP_SPACING - (LAMP_SPACING * 0.25 if side == 1 else LAMP_SPACING * 0.75)
			if Junction.in_mouth(chunk_index, lz):
				continue  # the signal masts stand there
			var lt: float = -lz / CHUNK_LEN
			var curb: float = lerp(start_own_curb, end_own_curb, lt) if side == 1 else lerp(start_onc_curb, end_onc_curb, lt)
			var pole_x := (curb + LAMP_SETBACK) * float(side)
			var turn := Basis() if side == 1 else Basis(Vector3.UP, PI)
			lamps.set_instance_transform(n_lamps, _xf_up(pole_x, 0.0, lz, turn))
			var head_x := pole_x - (LAMP_ARM - 0.2) * float(side)
			pools.set_instance_transform(n_lamps, _xf(head_x, POOL_Y, lz, Basis.from_scale(Vector3(POOL_ACROSS, 1.0, POOL_ALONG))))
			n_lamps += 1
	lamps.visible_instance_count = n_lamps
	pools.visible_instance_count = n_lamps

	# center line / barrier -- snapped to this chunk's own end-of-chunk
	# config, not tapered (see file header). Both the wall and the dash
	# buffer always exist; only one of them is shown.
	var slots := _dash_slots()
	var center: MultiMesh = (root.get_node(^"CenterDashes") as MultiMeshInstance3D).multimesh
	var barrier_mmi := root.get_node(^"Barrier") as MultiMeshInstance3D
	var refl_mm: MultiMesh = (barrier_mmi.get_node(^"Reflectors") as MultiMeshInstance3D).multimesh
	var seg := CHUNK_LEN / STATIONS
	for k in STATIONS:
		var bxf := _xf(0.0, BARRIER_Y, -seg * (float(k) + 0.5))
		barrier_mmi.multimesh.set_instance_transform(k, bxf)
		refl_mm.set_instance_transform(k, bxf)
	barrier_mmi.multimesh.visible_instance_count = STATIONS
	refl_mm.visible_instance_count = STATIONS
	barrier_mmi.visible = barrier
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

## Builds a fresh chunk root positioned at world Z = -(chunk_index - origin_index) * CHUNK_LEN,
## spanning from z=0 to z=-CHUNK_LEN locally.
static func build_chunk(chunk_index: int, prev_cfg: Dictionary, cfg: Dictionary, origin_index: int = 0) -> Node3D:
	var root := Node3D.new()
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
