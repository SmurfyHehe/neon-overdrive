# FROZEN REFERENCE -- do not edit. scripts/road_chunk_builder.gd as of 5cccba1,
# the last version before the 01a84cb draw-call/recycle rewrite.
# tests/chunk_builder_equivalence.gd builds chunks with this and with the
# live builder and asserts the results are identical. class_name removed so
# it doesn't collide with the real RoadChunkBuilder.
#
extends RefCounted

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
#   geometry: _add_sidewalk_collision() below adds a "Dirt"-group collision
#   box (raised slightly above the flat "Road" ground slab) under the
#   curb+sidewalk band, and the vendored Wheel controller reads the group a
#   wheel's raycast hits to pick tire values AND feels the real height step.
#   This box is NOT tapered (per-chunk average width) -- a deliberate
#   simplification, unlike the tapered visual strips above it.
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
# Curves + elevation are their own later architecture change (Path3D-driven
# procedural mesh) and are explicitly NOT attempted here.
#
# Known remaining simplification: interior lane-divider dashes and the
# center barrier/dash line are snapped to each chunk's own (end-of-chunk)
# lane count, not tapered -- properly tapering dividers through a
# lane-count change means dividers appearing/disappearing mid-span, real
# complexity that wasn't worth it for a "cheap fix" pass. Revisit if it
# reads as janky once driven.

const LANE_W := 2.3
const CHUNK_LEN := 50.0
const DASH_SPACING := 4.0
const SHOULDER_W := 1.6
const CURB_W := 0.3
const SIDEWALK_W := 2.2
const PYLON_SPACING := 8.0
const PYLON_HEIGHT := 0.9
const BUILDING_SPACING := 22.0

static var _own_mat: StandardMaterial3D
static var _onc_mat: StandardMaterial3D
static var _shoulder_mat: StandardMaterial3D
static var _curb_mat: StandardMaterial3D
static var _sidewalk_mat: StandardMaterial3D
static var _edge_line_mat: StandardMaterial3D
static var _pylon_mat_own: StandardMaterial3D
static var _pylon_mat_onc: StandardMaterial3D
static var _window_tex: ImageTexture

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
## chunk instead of stretching. Two-sided (CULL_DISABLED) so triangle
## winding on the tapered strips below never matters.
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
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
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

static func _building_mat(base_color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = base_color
	m.emission_enabled = true
	m.emission_texture = _get_window_tex()
	m.emission = Color(1, 1, 1)
	m.emission_energy_multiplier = 1.4
	m.roughness = 0.85
	return m

static func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	return mi

## Flat trapezoid strip at a constant height y: inner/outer edge at z=0
## (chunk start, matches the PREVIOUS chunk's end-width) tapering linearly to
## inner/outer edge at z=-length (this chunk's own end-width, matched by
## whatever chunk comes next). Explicit UP normals + a two-sided material
## means triangle winding direction doesn't matter here.
static func _tapered_strip(x_inner0: float, x_inner1: float, x_outer0: float, x_outer1: float, length: float, mat: Material, y: float = 0.0) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(x_inner0, y, 0.0)
	var b := Vector3(x_outer0, y, 0.0)
	var c := Vector3(x_inner1, y, -length)
	var d := Vector3(x_outer1, y, -length)
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 0)); st.add_vertex(b)
	st.set_uv(Vector2(0, 1)); st.add_vertex(c)
	st.set_uv(Vector2(1, 0)); st.add_vertex(b)
	st.set_uv(Vector2(1, 1)); st.add_vertex(d)
	st.set_uv(Vector2(0, 1)); st.add_vertex(c)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi

static func _lane_w(lanes: int) -> float:
	return float(lanes) * LANE_W

## Real "Dirt"-group collision box spanning the curb+sidewalk band on one
## side of the road for this whole chunk (average width, not tapered -- see
## call site). Raised to y=0.1 so it sits above the flat "Road" ground slab
## and wins the wheel raycast whenever a wheel is actually over it.
static func _add_sidewalk_collision(root: Node3D, inner_x: float, outer_x: float, side: int) -> void:
	var width: float = outer_x - inner_x
	var center_x: float = (inner_x + outer_x) / 2.0 * float(side)
	var body := StaticBody3D.new()
	body.add_to_group("Dirt")
	body.position = Vector3(center_x, 0.1, -CHUNK_LEN / 2.0)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 0.1, CHUNK_LEN)
	col.shape = box
	body.add_child(col)
	root.add_child(body)

## One roadside building: a randomized box + a real StaticBody3D collision
## shape (the player can't drive through these -- see file header), placed
## just past the sidewalk's outer edge. ~12% are tagged as a reserved
## "garage" visual variant for milestone 8 to reuse later.
static func _add_building(root: Node3D, edge_x_abs: float, z: float, side: int) -> void:
	var is_garage: bool = randf() < 0.12
	var w: float = randf_range(3.0, 6.0)
	var d: float = randf_range(3.0, 6.0)
	var h: float = randf_range(3.0, 4.0) if is_garage else randf_range(5.0, 16.0)
	var gap := 1.0
	var x: float = (edge_x_abs + w / 2.0 + gap) * float(side)
	var color := Color(0.12, 0.1, 0.05) if is_garage else Color(0.08, 0.05, 0.14)

	var mesh := _box(Vector3(w, h, d), _building_mat(color))
	mesh.position = Vector3(x, h / 2.0, z)
	if is_garage:
		mesh.set_meta("building_type", "garage")
	root.add_child(mesh)

	var body := StaticBody3D.new()
	body.position = mesh.position
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, h, d)
	col.shape = box
	body.add_child(col)
	root.add_child(body)

## Shared build/rebuild body. prev_cfg supplies the width to taper FROM (the
## previous chunk's own end-of-chunk lane counts); cfg is this chunk's own
## (end-of-chunk) lane counts/barrier, matched by whatever chunk follows.
static func _populate(root: Node3D, chunk_index: int, prev_cfg: Dictionary, cfg: Dictionary) -> void:
	root.name = "Chunk_%d" % chunk_index
	root.position = Vector3(0, 0, -float(chunk_index) * CHUNK_LEN)
	root.set_meta("chunk_index", chunk_index)

	var own_lanes: int = cfg.own_lanes
	var onc_lanes: int = cfg.onc_lanes
	var barrier: bool = cfg.barrier
	var start_own_w := _lane_w(prev_cfg.own_lanes)
	var end_own_w := _lane_w(own_lanes)
	var start_onc_w := _lane_w(prev_cfg.onc_lanes)
	var end_onc_w := _lane_w(onc_lanes)

	# road surfaces (tapered)
	root.add_child(_tapered_strip(0.0, 0.0, start_own_w, end_own_w, CHUNK_LEN, _get_own_mat()))
	root.add_child(_tapered_strip(0.0, 0.0, -start_onc_w, -end_onc_w, CHUNK_LEN, _get_onc_mat()))

	# solid edge line along each lane's OUTER boundary -- distinct from the
	# dashed interior lane splits added further below
	root.add_child(_tapered_strip(start_own_w - 0.12, end_own_w - 0.12, start_own_w + 0.03, end_own_w + 0.03, CHUNK_LEN, _get_edge_line_mat(), 0.012))
	root.add_child(_tapered_strip(-(start_onc_w - 0.12), -(end_onc_w - 0.12), -(start_onc_w + 0.03), -(end_onc_w + 0.03), CHUNK_LEN, _get_edge_line_mat(), 0.012))

	# shoulders (tapered, flush with the road edge)
	var start_own_shoulder := start_own_w + SHOULDER_W
	var end_own_shoulder := end_own_w + SHOULDER_W
	var start_onc_shoulder := start_onc_w + SHOULDER_W
	var end_onc_shoulder := end_onc_w + SHOULDER_W
	root.add_child(_tapered_strip(start_own_w, end_own_w, start_own_shoulder, end_own_shoulder, CHUNK_LEN, _get_shoulder_mat()))
	root.add_child(_tapered_strip(-start_onc_w, -end_onc_w, -start_onc_shoulder, -end_onc_shoulder, CHUNK_LEN, _get_shoulder_mat()))

	# curb -- crossable rumble strip, NOT a collision wall (see file header).
	# Raised slightly (y offset) so it reads as a step up, not just a color change.
	var start_own_curb := start_own_shoulder + CURB_W
	var end_own_curb := end_own_shoulder + CURB_W
	var start_onc_curb := start_onc_shoulder + CURB_W
	var end_onc_curb := end_onc_shoulder + CURB_W
	root.add_child(_tapered_strip(start_own_shoulder, end_own_shoulder, start_own_curb, end_own_curb, CHUNK_LEN, _get_curb_mat(), 0.1))
	root.add_child(_tapered_strip(-start_onc_shoulder, -end_onc_shoulder, -start_onc_curb, -end_onc_curb, CHUNK_LEN, _get_curb_mat(), 0.1))

	# sidewalk -- drivable, lower grip (applied in player.gd/game.gd, not here)
	var start_own_walk := start_own_curb + SIDEWALK_W
	var end_own_walk := end_own_curb + SIDEWALK_W
	var start_onc_walk := start_onc_curb + SIDEWALK_W
	var end_onc_walk := end_onc_curb + SIDEWALK_W
	root.add_child(_tapered_strip(start_own_curb, end_own_curb, start_own_walk, end_own_walk, CHUNK_LEN, _get_sidewalk_mat(), 0.1))
	root.add_child(_tapered_strip(-start_onc_curb, -end_onc_curb, -start_onc_walk, -end_onc_walk, CHUNK_LEN, _get_sidewalk_mat(), 0.1))

	# Physics rewrite (2026-09-13): real "Dirt"-group collision under the
	# curb+sidewalk band, replacing the old x-position math + hand-rolled
	# grip multiplier entirely -- the vendored Wheel raycast now detects
	# this by group and applies its own (already lower) Dirt tire values,
	# AND gets a real physical bump for free since this box's top sits
	# higher (y=0.1) than the flat "Road" ground slab underneath, so a wheel
	# over the sidewalk hits this closer box first. One box per side per
	# chunk, NOT tapered (average width for the chunk) -- a deliberate
	# simplification; a car crossing the curb at an angle near a lane-count
	# change might feel a slightly-off edge position, acceptable for this pass.
	var avg_own_curb := (start_own_curb + end_own_curb) / 2.0
	var avg_own_walk := (start_own_walk + end_own_walk) / 2.0
	var avg_onc_curb := (start_onc_curb + end_onc_curb) / 2.0
	var avg_onc_walk := (start_onc_walk + end_onc_walk) / 2.0
	_add_sidewalk_collision(root, avg_own_curb, avg_own_walk, 1)
	_add_sidewalk_collision(root, avg_onc_curb, avg_onc_walk, -1)

	# edge pylons -- purely cosmetic rhythm/speed cues, linearly interpolated
	# along each shoulder's outer edge between this chunk's start and end width
	var n_pylons := int(CHUNK_LEN / PYLON_SPACING)
	for i in range(n_pylons):
		var pz := -float(i) * PYLON_SPACING - PYLON_SPACING / 2.0
		var pt: float = -pz / CHUNK_LEN
		var own_pylon_edge: float = lerp(start_own_shoulder, end_own_shoulder, pt)
		var onc_pylon_edge: float = lerp(start_onc_shoulder, end_onc_shoulder, pt)
		var p1 := _box(Vector3(0.12, PYLON_HEIGHT, 0.12), _get_pylon_mat_own())
		p1.position = Vector3(own_pylon_edge, PYLON_HEIGHT / 2.0, pz)
		root.add_child(p1)
		var p2 := _box(Vector3(0.12, PYLON_HEIGHT, 0.12), _get_pylon_mat_onc())
		p2.position = Vector3(-onc_pylon_edge, PYLON_HEIGHT / 2.0, pz)
		root.add_child(p2)

	# roadside buildings -- real collision, the world's actual hard boundary
	# now that the curb no longer is one (see file header)
	var n_buildings := int(CHUNK_LEN / BUILDING_SPACING)
	for i in range(n_buildings):
		var bz := -float(i) * BUILDING_SPACING - BUILDING_SPACING / 2.0
		var bt: float = -bz / CHUNK_LEN
		var own_building_edge: float = lerp(start_own_walk, end_own_walk, bt)
		var onc_building_edge: float = lerp(start_onc_walk, end_onc_walk, bt)
		_add_building(root, own_building_edge, bz, 1)
		_add_building(root, onc_building_edge, bz, -1)

	# center line / barrier -- snapped to this chunk's own end-of-chunk
	# config, not tapered (see file header)
	if barrier:
		var bmat := _flat_mat(Color(1, 0.72, 0), true, 1.4)
		var wall := _box(Vector3(0.2, 0.65, CHUNK_LEN), bmat)
		wall.position = Vector3(0.0, 0.32, -CHUNK_LEN / 2.0)
		root.add_child(wall)
	else:
		var center_mat := _flat_mat(Color(1, 0.72, 0), true, 2.0)
		var n := int(CHUNK_LEN / DASH_SPACING)
		for i in range(n):
			var dash := _box(Vector3(0.22, 0.05, 2.4), center_mat)
			dash.position = Vector3(0.0, 0.01, -float(i) * DASH_SPACING - DASH_SPACING / 2.0)
			root.add_child(dash)

	# interior own-lane dividers
	var dash_mat := _flat_mat(Color(0, 0.9, 0.94), true, 2.0)
	for lane_i in range(1, own_lanes):
		var x: float = lane_i * LANE_W
		var n2 := int(CHUNK_LEN / DASH_SPACING)
		for i in range(n2):
			var d := _box(Vector3(0.2, 0.05, 2.4), dash_mat)
			d.position = Vector3(x, 0.01, -float(i) * DASH_SPACING - DASH_SPACING / 2.0)
			root.add_child(d)
	for lane_i in range(1, onc_lanes):
		var x2: float = -lane_i * LANE_W
		var n3 := int(CHUNK_LEN / DASH_SPACING)
		for i in range(n3):
			var d2 := _box(Vector3(0.2, 0.05, 2.4), dash_mat)
			d2.position = Vector3(x2, 0.01, -float(i) * DASH_SPACING - DASH_SPACING / 2.0)
			root.add_child(d2)

## Builds a fresh chunk root positioned at world Z = -chunk_index * CHUNK_LEN,
## spanning from z=0 to z=-CHUNK_LEN locally.
static func build_chunk(chunk_index: int, prev_cfg: Dictionary, cfg: Dictionary) -> Node3D:
	var root := Node3D.new()
	_populate(root, chunk_index, prev_cfg, cfg)
	return root

## Reuses an existing chunk root (freeing its children) instead of allocating
## a new node -- this is the recycle path.
static func rebuild_chunk(root: Node3D, chunk_index: int, prev_cfg: Dictionary, cfg: Dictionary) -> void:
	for c in root.get_children():
		c.queue_free()
	_populate(root, chunk_index, prev_cfg, cfg)
