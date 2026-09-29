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
#   one. A random ~12% are tagged building_type="garage" (wider/shorter,
#   warm-lit) -- purely a reserved visual variant for now, not wired to
#   anything; milestone 8's stop-places can reuse the tag later instead of
#   needing new building art.
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

# Curves + elevation are their own later architecture change (Path3D-driven
# procedural mesh) and are explicitly NOT attempted here.
#
# Interior lane-divider dashes and the center barrier/dash line are snapped
# to each chunk's own (end-of-chunk) lane count, not tapered. Kept on purpose
# (issue #36, closed won't-fix 2026-09-29): on a lane ADD the new divider
# carries on from the old road edge while the new lane opens beside it, and
# on a lane DROP the outer lane narrows away with no divider -- which is how
# real roads mark both. Tapering would mean dividers appearing and
# disappearing mid-span for a worse-looking result.

const LANE_W := 2.3
const CHUNK_LEN := 50.0
const DASH_SPACING := 4.0
const SHOULDER_W := 1.6
const CURB_W := 0.3
const SIDEWALK_W := 2.2
const PYLON_SPACING := 8.0
const PYLON_HEIGHT := 0.9
const BUILDING_SPACING := 22.0

# Dash / pylon / barrier dimensions, previously inline magic numbers repeated
# at each construction site. They are constants now because the shared meshes
# further down are built from them exactly once.
const DASH_LEN := 2.4
const DASH_H := 0.05
const DASH_Y := 0.01
const CENTER_DASH_W := 0.22
const LANE_DASH_W := 0.2
const PYLON_W := 0.12
const BARRIER_W := 0.2
const BARRIER_H := 0.65
# Carried over verbatim from the pre-pass code, which sat the barrier at 0.32
# rather than exactly half its height (0.325). Kept as-is so this pass stays
# visually neutral; it is a 5 mm difference, not a deliberate design value.
const BARRIER_Y := 0.32

# Must match the clampi() ranges in game.gd::_section_at(). The MultiMesh
# instance buffers are sized for the worst case exactly once, so these cannot
# be exceeded at runtime -- _apply() clamps defensively rather than overrun.
const MAX_OWN_LANES := 4
const MAX_ONC_LANES := 2

const CENTER_COLOR := Color(1, 0.72, 0)
const LANE_DASH_COLOR := Color(0, 0.9, 0.94)
const BUILDING_COLOR_GARAGE := Color(0.12, 0.1, 0.05)
const BUILDING_COLOR_TOWER := Color(0.08, 0.05, 0.14)

static var _own_mat: StandardMaterial3D
static var _onc_mat: StandardMaterial3D
static var _shoulder_mat: StandardMaterial3D
static var _curb_mat: StandardMaterial3D
static var _sidewalk_mat: StandardMaterial3D
static var _edge_line_mat: StandardMaterial3D
static var _pylon_mat_own: StandardMaterial3D
static var _pylon_mat_onc: StandardMaterial3D
static var _window_tex: ImageTexture
static var _barrier_mat: StandardMaterial3D
static var _center_dash_mat: StandardMaterial3D
static var _lane_dash_mat: StandardMaterial3D
static var _building_mat_garage: StandardMaterial3D
static var _building_mat_tower: StandardMaterial3D

# Shared geometry, built once and reused by every chunk in the pool -- see the
# "shared geometry" section below.
static var _center_dash_mesh: BoxMesh
static var _lane_dash_mesh: BoxMesh
static var _pylon_mesh: BoxMesh
static var _barrier_mesh: BoxMesh

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
		_own_mat = _asphalt_mat(Color(0.047, 0.067, 0.125))
	return _own_mat

static func _get_onc_mat() -> StandardMaterial3D:
	if _onc_mat == null:
		_onc_mat = _asphalt_mat(Color(0.07, 0.047, 0.094))
	return _onc_mat

static func _get_shoulder_mat() -> StandardMaterial3D:
	if _shoulder_mat == null:
		_shoulder_mat = _asphalt_mat(Color(0.03, 0.03, 0.045))
	return _shoulder_mat

## Curb: bright, slightly emissive strip -- crossable rumble cue, not a wall
## (see file header). Bright on purpose so it visually reads as a real
## marked edge, not just another shade of shoulder.
static func _get_curb_mat() -> StandardMaterial3D:
	if _curb_mat == null:
		_curb_mat = _flat_mat(Color(0.95, 0.85, 0.55), true, 0.9)
	return _curb_mat

## Sidewalk: flat, non-emissive concrete tone -- deliberately calm/neutral so
## it reads as "different surface" against the neon road without competing
## with it visually.
static func _get_sidewalk_mat() -> StandardMaterial3D:
	if _sidewalk_mat == null:
		_sidewalk_mat = _asphalt_mat(Color(0.11, 0.1, 0.12))
	return _sidewalk_mat

## Solid (non-dashed) lane-edge line -- real roads mark the outer edge
## differently from interior lane splits; ours didn't distinguish them at all.
static func _get_edge_line_mat() -> StandardMaterial3D:
	if _edge_line_mat == null:
		_edge_line_mat = _flat_mat(Color(0.85, 0.95, 1.0), true, 2.2)
	return _edge_line_mat

static func _get_pylon_mat_own() -> StandardMaterial3D:
	if _pylon_mat_own == null:
		_pylon_mat_own = _flat_mat(Color(0, 0.9, 0.94), true, 2.5)
	return _pylon_mat_own

static func _get_pylon_mat_onc() -> StandardMaterial3D:
	if _pylon_mat_onc == null:
		_pylon_mat_onc = _flat_mat(Color(1, 0.15, 0.75), true, 2.5)
	return _pylon_mat_onc

## Procedural window-grid texture for buildings -- built once (a punched dot
## grid of lit "windows" over a dark base) and shared across every building
## material instance as an emission_texture, instead of spawning extra window
## meshes per building.
static func _get_window_tex() -> ImageTexture:
	if _window_tex == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
		img.fill(Color(0.015, 0.015, 0.025))
		var gy := 2
		while gy < 30:
			var gx := 2
			while gx < 30:
				if randf() < 0.55:
					img.set_pixel(gx, gy, Color(1.0, 0.85, 0.45))
					img.set_pixel(gx + 1, gy, Color(1.0, 0.85, 0.45))
				gx += 4
			gy += 4
		_window_tex = ImageTexture.create_from_image(img)
	return _window_tex

## Cached building materials. Only two variants exist (garage / tower), but
## _building_mat() used to be called per building -- 4 fresh
## StandardMaterial3D per chunk, 32 across the pool, every one a duplicate of
## one of these two. Cached like every other material in this file so the
## renderer can batch them.
static func _building_mat(base_color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = base_color
	m.emission_enabled = true
	m.emission_texture = _get_window_tex()
	m.emission = Color(1, 1, 1)
	m.emission_energy_multiplier = 1.4
	m.roughness = 0.85
	return m

static func _get_building_mat(is_garage: bool) -> StandardMaterial3D:
	if is_garage:
		if _building_mat_garage == null:
			_building_mat_garage = _building_mat(BUILDING_COLOR_GARAGE)
		return _building_mat_garage
	if _building_mat_tower == null:
		_building_mat_tower = _building_mat(BUILDING_COLOR_TOWER)
	return _building_mat_tower

## The center barrier and the two dash colors were the three materials in this
## file that bypassed the static-var cache above, constructed fresh inside
## _populate() on every chunk build. A new material per chunk defeats the
## batching the rest of the cache exists to enable.
static func _get_barrier_mat() -> StandardMaterial3D:
	if _barrier_mat == null:
		_barrier_mat = _flat_mat(CENTER_COLOR, true, 1.4)
	return _barrier_mat

static func _get_center_dash_mat() -> StandardMaterial3D:
	if _center_dash_mat == null:
		_center_dash_mat = _flat_mat(CENTER_COLOR, true, 2.0)
	return _center_dash_mat

static func _get_lane_dash_mat() -> StandardMaterial3D:
	if _lane_dash_mat == null:
		_lane_dash_mat = _flat_mat(LANE_DASH_COLOR, true, 2.0)
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

static func _get_barrier_mesh() -> BoxMesh:
	if _barrier_mesh == null:
		_barrier_mesh = _box_mesh(Vector3(BARRIER_W, BARRIER_H, CHUNK_LEN))
	return _barrier_mesh

static func _lane_w(lanes: int) -> float:
	return float(lanes) * LANE_W

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

static func _strip_arrays(x_inner0: float, x_inner1: float, x_outer0: float, x_outer1: float, length: float, y: float) -> Array:
	var a := Vector3(x_inner0, y, 0.0)
	var b := Vector3(x_outer0, y, 0.0)
	var c := Vector3(x_inner1, y, -length)
	var d := Vector3(x_outer1, y, -length)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	# [a, b, c] runs clockwise seen from above only when outer is left of inner.
	var mirrored := x_outer0 < x_inner0
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([a, b, c, b, d, c] if mirrored else [a, c, b, b, c, d])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP,
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(0, 1),
		Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
	] if mirrored else [
		Vector2(0, 0), Vector2(0, 1), Vector2(1, 0),
		Vector2(1, 0), Vector2(0, 1), Vector2(1, 1),
	])
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

# ---------- collision (reused bodies) ----------
#
# Real "Dirt"-group collision spanning the sidewalk band on one side for this
# whole chunk. Created once per side and RESHAPED on rebuild -- the shape
# resource is reused. It is a convex prism tapered exactly like the sidewalk
# strip (issue #35), so the grip change and the height step sit under the
# drawn curb edge all along a lane-count change.

static func _new_sidewalk_collision(body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.add_to_group("Dirt")
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var hull := ConvexPolygonShape3D.new()
	# placeholder until _apply() reshapes it -- an empty hull logs an error
	hull.points = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK])
	col.shape = hull
	body.add_child(col)
	return body

static func _update_sidewalk_collision(root: Node3D, body_name: String, inner0: float, inner1: float, outer0: float, outer1: float, side: int) -> void:
	var body: StaticBody3D = root.get_node(NodePath(body_name))
	var col: CollisionShape3D = body.get_node(^"Shape")
	var hull: ConvexPolygonShape3D = col.shape
	# chunk start is z=0, end is z=-CHUNK_LEN; same 0.05..0.15 height band as
	# the old box. Points are in chunk-local space, so the body sits at origin.
	var sx := float(side)
	var pts := PackedVector3Array()
	for y in [0.05, 0.15]:
		pts.append(Vector3(inner0 * sx, y, 0.0))
		pts.append(Vector3(outer0 * sx, y, 0.0))
		pts.append(Vector3(inner1 * sx, y, -CHUNK_LEN))
		pts.append(Vector3(outer1 * sx, y, -CHUNK_LEN))
	hull.points = pts
	body.position = Vector3.ZERO

# ---------- buildings (reused nodes) ----------
#
# Buildings keep one MeshInstance3D + one StaticBody3D each rather than
# becoming a MultiMesh: every one needs a real collision body anyway (they
# are the drivable world's hard boundary -- see file header), and the
# per-node building_type="garage" meta that milestone 8 is meant to reuse
# cannot live on a MultiMesh instance.
#
# They are also the one case that does NOT share a mesh. Godot's BoxMesh lays
# out UVs proportional to the box dimensions, so the window-grid emission
# texture stretches with a building's height -- sharing one unit cube and
# scaling the node would flatten that into a uniform grid, which is a real
# visual change. Instead each slot keeps its own BoxMesh for the life of the
# pool and has its size rewritten on rebuild: identical UVs to before, and
# still nothing allocated per rebuild. They do now share the two cached
# materials instead of one fresh material each.

static func _new_building(index: int) -> Array:
	var mi := MeshInstance3D.new()
	mi.name = "BuildingMesh%d" % index
	mi.mesh = _box_mesh(Vector3.ONE)
	var body := StaticBody3D.new()
	body.name = "BuildingBody%d" % index
	var col := CollisionShape3D.new()
	col.name = "Shape"
	col.shape = BoxShape3D.new()
	body.add_child(col)
	return [mi, body]

static func _update_building(root: Node3D, index: int, edge_x_abs: float, z: float, side: int) -> void:
	var mi: MeshInstance3D = root.get_node(NodePath("BuildingMesh%d" % index))
	var body: StaticBody3D = root.get_node(NodePath("BuildingBody%d" % index))
	var col: CollisionShape3D = body.get_node(^"Shape")
	var box: BoxShape3D = col.shape

	var is_garage: bool = randf() < 0.12
	var w: float = randf_range(3.0, 6.0)
	var d: float = randf_range(3.0, 6.0)
	var h: float = randf_range(3.0, 4.0) if is_garage else randf_range(5.0, 16.0)
	var gap := 1.0
	var pos := Vector3((edge_x_abs + w / 2.0 + gap) * float(side), h / 2.0, z)

	(mi.mesh as BoxMesh).size = Vector3(w, h, d)
	mi.position = pos
	mi.material_override = _get_building_mat(is_garage)
	if is_garage:
		mi.set_meta("building_type", "garage")
	elif mi.has_meta("building_type"):
		mi.remove_meta("building_type")

	box.size = Vector3(w, h, d)
	body.position = pos

# ---------- build / rebuild ----------

## Creates the fixed node skeleton for a chunk: ten strips, two collision
## bodies, four MultiMeshInstance3D, the barrier, and the building pairs.
## Runs ONCE per pooled chunk root -- everything after that is an in-place
## update, which is the whole point of the recycle path below.
static func _create_nodes(root: Node3D) -> void:
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

	root.add_child(_new_sidewalk_collision("SidewalkColOwn"))
	root.add_child(_new_sidewalk_collision("SidewalkColOnc"))

	var slots := _dash_slots()
	root.add_child(_new_multimesh("PylonsOwn", _get_pylon_mesh(), _get_pylon_mat_own(), _pylon_slots()))
	root.add_child(_new_multimesh("PylonsOnc", _get_pylon_mesh(), _get_pylon_mat_onc(), _pylon_slots()))
	root.add_child(_new_multimesh("CenterDashes", _get_center_dash_mesh(), _get_center_dash_mat(), slots))
	# Worst case: every interior divider on both sides at max lane count.
	var max_dividers := (MAX_OWN_LANES - 1) + (MAX_ONC_LANES - 1)
	root.add_child(_new_multimesh("LaneDashes", _get_lane_dash_mesh(), _get_lane_dash_mat(), max_dividers * slots))

	var wall := MeshInstance3D.new()
	wall.name = "Barrier"
	wall.mesh = _get_barrier_mesh()
	wall.material_override = _get_barrier_mat()
	wall.position = Vector3(0.0, BARRIER_Y, -CHUNK_LEN / 2.0)
	root.add_child(wall)

	for i in range(_building_slots() * 2):
		for n in _new_building(i):
			root.add_child(n)

	root.set_meta("nodes_built", true)

## Rewrites an already-built chunk skeleton for a new position/config. No
## node is created, freed, or reparented here -- this is what replaces the
## old queue_free()-everything teardown.
static func _apply(root: Node3D, chunk_index: int, prev_cfg: Dictionary, cfg: Dictionary) -> void:
	root.name = "Chunk_%d" % chunk_index
	root.position = Vector3(0, 0, -float(chunk_index) * CHUNK_LEN)
	root.set_meta("chunk_index", chunk_index)

	var own_lanes: int = clampi(int(cfg.own_lanes), 1, MAX_OWN_LANES)
	var onc_lanes: int = clampi(int(cfg.onc_lanes), 1, MAX_ONC_LANES)
	var barrier: bool = cfg.barrier
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

	# edge pylons -- cosmetic rhythm/speed cues, interpolated along each
	# shoulder's outer edge between this chunk's start and end width
	var pylons_own: MultiMesh = (root.get_node(^"PylonsOwn") as MultiMeshInstance3D).multimesh
	var pylons_onc: MultiMesh = (root.get_node(^"PylonsOnc") as MultiMeshInstance3D).multimesh
	var n_pylons := _pylon_slots()
	for i in range(n_pylons):
		var pz := -float(i) * PYLON_SPACING - PYLON_SPACING / 2.0
		var pt: float = -pz / CHUNK_LEN
		var own_edge: float = lerp(start_own_shoulder, end_own_shoulder, pt)
		var onc_edge: float = lerp(start_onc_shoulder, end_onc_shoulder, pt)
		pylons_own.set_instance_transform(i, Transform3D(Basis(), Vector3(own_edge, PYLON_HEIGHT / 2.0, pz)))
		pylons_onc.set_instance_transform(i, Transform3D(Basis(), Vector3(-onc_edge, PYLON_HEIGHT / 2.0, pz)))
	pylons_own.visible_instance_count = n_pylons
	pylons_onc.visible_instance_count = n_pylons

	# roadside buildings -- real collision, the world's actual hard boundary
	var n_buildings := _building_slots()
	for i in range(n_buildings):
		var bz := -float(i) * BUILDING_SPACING - BUILDING_SPACING / 2.0
		var bt: float = -bz / CHUNK_LEN
		var own_edge_b: float = lerp(start_own_walk, end_own_walk, bt)
		var onc_edge_b: float = lerp(start_onc_walk, end_onc_walk, bt)
		_update_building(root, i * 2, own_edge_b, bz, 1)
		_update_building(root, i * 2 + 1, onc_edge_b, bz, -1)

	# center line / barrier -- snapped to this chunk's own end-of-chunk
	# config, not tapered (see file header). Both the wall and the dash
	# buffer always exist; only one of them is shown.
	var slots := _dash_slots()
	var center: MultiMesh = (root.get_node(^"CenterDashes") as MultiMeshInstance3D).multimesh
	(root.get_node(^"Barrier") as MeshInstance3D).visible = barrier
	if barrier:
		center.visible_instance_count = 0
	else:
		for i in range(slots):
			var dz := -float(i) * DASH_SPACING - DASH_SPACING / 2.0
			center.set_instance_transform(i, Transform3D(Basis(), Vector3(0.0, DASH_Y, dz)))
		center.visible_instance_count = slots

	# interior lane dividers, both directions packed into one instance
	# buffer; unused capacity is simply left outside visible_instance_count
	var lane: MultiMesh = (root.get_node(^"LaneDashes") as MultiMeshInstance3D).multimesh
	var written := 0
	for lane_i in range(1, own_lanes):
		var x: float = lane_i * LANE_W
		for i in range(slots):
			var dz2 := -float(i) * DASH_SPACING - DASH_SPACING / 2.0
			lane.set_instance_transform(written, Transform3D(Basis(), Vector3(x, DASH_Y, dz2)))
			written += 1
	for lane_i in range(1, onc_lanes):
		var x2: float = -lane_i * LANE_W
		for i in range(slots):
			var dz3 := -float(i) * DASH_SPACING - DASH_SPACING / 2.0
			lane.set_instance_transform(written, Transform3D(Basis(), Vector3(x2, DASH_Y, dz3)))
			written += 1
	lane.visible_instance_count = written

## Builds a fresh chunk root positioned at world Z = -chunk_index * CHUNK_LEN,
## spanning from z=0 to z=-CHUNK_LEN locally.
static func build_chunk(chunk_index: int, prev_cfg: Dictionary, cfg: Dictionary) -> Node3D:
	var root := Node3D.new()
	_create_nodes(root)
	_apply(root, chunk_index, prev_cfg, cfg)
	return root

## The recycle path. Previously this queue_free()'d all ~70 children and
## rebuilt them from scratch, which at 55 m/s over a 50 m chunk meant a full
## teardown-and-reallocate roughly every 0.9 seconds -- a periodic stutter on
## a 15 W CPU. Now it only rewrites vertex data, transforms and shape sizes
## into nodes that already exist.
static func rebuild_chunk(root: Node3D, chunk_index: int, prev_cfg: Dictionary, cfg: Dictionary) -> void:
	if not root.has_meta("nodes_built"):
		_create_nodes(root)
	_apply(root, chunk_index, prev_cfg, cfg)
