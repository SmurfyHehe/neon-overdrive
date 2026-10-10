extends RefCounted

# Side-street mouths (world step 6, W7, 2026-10-10): some gaps between
# buildings open onto a short side street you can look down but not drive:
# 30-60 m of two-lane road with kerbs and pavements, one street lamp with
# its light pool, a parked car and a stop sign, fading into the dark. The
# city reads as a city instead of a corridor.
#
# Where: one building slot per mouth is turned into the opening (like a
# building that stands at a crossing's corner, _clear_at_junction: the slot's
# random draws are already taken, so the road layout does not change). Which
# slots is a hash of the district run (1-3 mouths per 800 m run, never on a
# crossing's chunks or a freeway), so a recycled chunk matches a fresh one.
# The gap walls leave the mouth open like a crossing's; the kerb drops across
# it; the invisible boundary wall stays, so it is look-only.
#
# Cost: two MultiMeshes per chunk, drawn only on a chunk with a mouth: the
# road kit (asphalt plane + two kerb-and-pavement blocks, vertex colours
# fading to black at the far end, scaled to the street's length) and the
# props (parked car and stop sign in one mesh, RoofProps' shape-collapse
# trick). The lamp and its pool are two more instances in the chunk's own
# lamp buffers (0 draw calls). CPU per frame: none.
#
# Picks are mine: MOUTH_W, the street's cross-section, the 30-60 m length,
# where the car and lamp stand, 1-3 per run.

const Districts := preload("res://scripts/world/districts.gd")

const LANE_W := 3.0           # the side street's lanes are narrower than the main road's
const KERB_W := 0.3
const WALK_W := 1.5
const KERB_H := 0.12
const ROAD_HALF := LANE_W     # two lanes, centre line to kerb face
const MOUTH_HALF := ROAD_HALF + KERB_W + WALK_W  # 4.8 m: the opening's half width
const LEN_MIN := 30.0
const LEN_MAX := 60.0
const PER_RUN_MIN := 1
const PER_RUN_MAX := 3
const CAPACITY := 2           # mouths per chunk at most (one per building slot)
const LAMP_SETBACK := 0.35
const LAMP_AT := 0.55         # fraction of the length where the lamp stands
const CAR_AT := Vector2(0.3, 0.65)  # the parked car stands between these fractions
const SIGN_IN := 2.0          # stop sign this far into the street
const SIGN_H := 2.2
const FADE_END := 0.03        # vertex colour at the far end (near black)
const ASPHALT := Color(0.13, 0.13, 0.135)
const KERB_COLOR := Color(0.2, 0.195, 0.185)  # the main pavement's concrete, a shade lighter than the asphalt
const SIGN_RED := Color(0.62, 0.08, 0.06)

const SHAPE_CAR := 0
const SHAPE_SIGN := 1

## Switch (NEON_SIDE_STREETS=0 turns the mouths off, for before/after runs).
static var enabled := OS.get_environment("NEON_SIDE_STREETS") != "0"

const PROP_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

varying vec3 tint;
varying float glow;

void vertex() {
	if (abs(UV2.x - INSTANCE_CUSTOM.r) > 0.5) {
		VERTEX = vec3(0.0);  // not this instance's shape: collapse it
	}
	tint = INSTANCE_CUSTOM.gba;
	glow = UV2.y;
}

void fragment() {
	ALBEDO = COLOR.rgb * tint;
	ROUGHNESS = 0.7;
	// the sign plate's red is retro-reflective paint: a small steady glow so
	// it reads from the main road, well under the bloom threshold
	EMISSION = glow > 0.5 ? COLOR.rgb * 0.35 : vec3(0.0);
}
"""

static var _kit_mesh: ArrayMesh
static var _kit_mat: StandardMaterial3D
static var _prop_mesh: ArrayMesh
static var _prop_mat: ShaderMaterial

# ---------- where the mouths are ----------

## The mouths of chunk `chunk_index`: [{side, slot, len, car_t, car_tint}],
## from the district run's hash. slot is the building slot (0 or 1) whose
## lot becomes the opening.
static func mouths_at(chunk_index: int) -> Array:
	if not enabled or Districts.is_freeway(chunk_index):
		return []
	var run := Districts.run_of(chunk_index)
	var n := PER_RUN_MIN + posmod(hash([run, "mouths"]), PER_RUN_MAX - PER_RUN_MIN + 1)
	var slots := RoadChunkBuilder._building_slots()
	var out := []
	var taken := {}
	for k in n:
		var c := run * Districts.RUN + posmod(hash([run, k, "mouth_chunk"]), Districts.RUN)
		if c != chunk_index:
			continue
		var side := 1 if posmod(hash([run, k, "mouth_side"]), 2) == 0 else -1
		var slot := posmod(hash([run, k, "mouth_slot"]), slots)
		if taken.has([side, slot]):
			continue
		var bz := slot_z(slot)
		# not on a crossing's chunks (its mouth and corner lots are its own)
		if Junction.touches(chunk_index) or Junction.near(chunk_index, bz, Junction.MOUTH_HALF + MOUTH_HALF + 2.0):
			continue
		taken[[side, slot]] = true
		var roll := float(posmod(hash([run, k, "mouth_len"]), 1000)) / 1000.0
		out.append({
			"side": side, "slot": slot, "z": bz,
			"len": lerpf(LEN_MIN, LEN_MAX, roll),
			"car_t": lerpf(CAR_AT.x, CAR_AT.y, float(posmod(hash([run, k, "mouth_car"]), 1000)) / 1000.0),
			"car_tint": _car_tint(posmod(hash([run, k, "mouth_tint"]), 5)),
		})
	return out

static func slot_z(slot: int) -> float:
	return -float(slot) * RoadChunkBuilder.BUILDING_SPACING - RoadChunkBuilder.BUILDING_SPACING / 2.0

## The mouth on this side and slot, or {}.
static func mouth_for(mouths: Array, side: int, slot: int) -> Dictionary:
	for m in mouths:
		if int(m.side) == side and int(m.slot) == slot:
			return m
	return {}

static func _car_tint(i: int) -> Color:
	# dark, desaturated: a car asleep under one lamp, not a hero
	return [Color(0.35, 0.35, 0.37), Color(0.22, 0.2, 0.19), Color(0.3, 0.12, 0.1), Color(0.42, 0.42, 0.4), Color(0.14, 0.17, 0.26)][i]

# ---------- meshes ----------

## The street kit, 1 m long along -Z (scaled to the length per instance):
## the asphalt plane between the kerbs, and a kerb-and-pavement block each
## side. Vertex colours go from 1 at the mouth to FADE_END at the far end,
## so the street fades to black whatever the lighting does.
static func kit_mesh() -> ArrayMesh:
	if _kit_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# asphalt: y just above the ground like the main road's paint
		_quad_fade(st, Vector3(-ROAD_HALF, 0.012, 0.0), Vector3(ROAD_HALF, 0.012, -1.0), ASPHALT)
		for s: float in [-1.0, 1.0]:
			var x0: float = s * ROAD_HALF
			var x1: float = s * (ROAD_HALF + KERB_W + WALK_W)
			_block_fade(st, minf(x0, x1), maxf(x0, x1), KERB_H, KERB_COLOR)
		_kit_mesh = st.commit()
	return _kit_mesh

static func kit_material() -> StandardMaterial3D:
	if _kit_mat == null:
		_kit_mat = StandardMaterial3D.new()
		_kit_mat.vertex_color_use_as_albedo = true
		# no specular: seen from the road the street is at a grazing angle, and
		# the sky's reflection would light the far end the vertex colours put out
		_kit_mat.roughness = 1.0
		_kit_mat.metallic = 0.0
		_kit_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _kit_mat

## Props: shape 0 a parked car (body, cabin, four wheel stubs), shape 1 a
## stop sign (post and octagon plate, red front, grey back). Each vertex
## carries its shape in UV2.x; UV2.y marks the sign's red face.
static func prop_mesh() -> ArrayMesh:
	if _prop_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# parked car, 4.3 x 1.7 m, nose along -Z; the tint is per instance
		var dark := Color(1.0, 1.0, 1.0)
		var glass := Color(0.25, 0.27, 0.3)
		var tyre := Color(0.12, 0.12, 0.12)
		_box(st, Vector3(0.0, 0.55, 0.0), Vector3(1.7, 0.5, 4.3), dark, SHAPE_CAR)
		_box(st, Vector3(0.0, 1.05, 0.2), Vector3(1.5, 0.5, 2.2), glass, SHAPE_CAR)
		for sx in [-0.72, 0.72]:
			for sz in [-1.35, 1.35]:
				_box(st, Vector3(sx, 0.3, sz), Vector3(0.22, 0.6, 0.62), tyre, SHAPE_CAR)
		# stop sign: post, plate facing -Z (down the street)
		_box(st, Vector3(0.0, SIGN_H / 2.0, 0.0), Vector3(0.07, SIGN_H, 0.07), Color(0.35, 0.35, 0.36), SHAPE_SIGN)
		_octagon(st, Vector3(0.0, SIGN_H + 0.1, 0.0), 0.38, SIGN_RED, Color(0.45, 0.45, 0.44), SHAPE_SIGN)
		_prop_mesh = st.commit()
	return _prop_mesh

static func prop_material() -> ShaderMaterial:
	if _prop_mat == null:
		var sh := Shader.new()
		sh.code = PROP_SHADER
		_prop_mat = ShaderMaterial.new()
		_prop_mat.shader = sh
	return _prop_mat

static func new_nodes() -> Array:
	var kit := RoadChunkBuilder._new_multimesh("SideStreets", kit_mesh(), kit_material(), CAPACITY)
	kit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = prop_mesh()
	mm.instance_count = CAPACITY * 2
	mm.visible_instance_count = 0
	var props := MultiMeshInstance3D.new()
	props.name = "SideStreetProps"
	props.multimesh = mm
	props.material_override = prop_material()
	props.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return [kit, props]

# ---------- layout ----------

## The street's frame: origin at the pavement's outer edge (edge_x, on the
## road surface at z), -Z turned to point away from the road on `side`.
## RoadChunkBuilder._xf keeps the road's pitch, so the plane is the main
## road's surface carried sideways; uprights use _xf_up at the same spot.
static func turn(side: int) -> Basis:
	return Basis(Vector3.UP, -PI / 2.0 * float(side))

## Lays out the chunk's mouths. edge_x: the pavement's outer edge (absolute,
## unsigned) at each mouth's z, in the same order as `mouths`. lamps/pools:
## the chunk's lamp buffers, from instance `first_lamp` on. Returns the
## number of lamps added. Stores every placement in the root's "side_streets"
## meta (headless Godot keeps no MultiMesh data, so tests read that).
static func update(root: Node3D, mouths: Array, edge_x: PackedFloat32Array, lamps: MultiMesh, pools: MultiMesh, first_lamp: int) -> int:
	var kit: MultiMesh = (root.get_node(^"SideStreets") as MultiMeshInstance3D).multimesh
	var props: MultiMesh = (root.get_node(^"SideStreetProps") as MultiMeshInstance3D).multimesh
	var n := 0
	var n_props := 0
	var n_lamps := 0
	var placed := []
	for i in mouths.size():
		if i >= CAPACITY:
			break
		var m: Dictionary = mouths[i]
		var side := int(m.side)
		var sx := float(side)
		var z := float(m.z)
		var x0 := float(edge_x[i])
		var length := float(m.len)
		var t := turn(side)
		# the kit: scaled to the street's length along its -Z
		var kit_xf := RoadChunkBuilder._xf(x0 * sx, 0.0, z, t * Basis.from_scale(Vector3(1.0, 1.0, length)))
		kit.set_instance_transform(n, kit_xf)
		# the lamp: on the right-hand pavement (local +X), arm over the street
		var lx := ROAD_HALF + KERB_W + LAMP_SETBACK
		var ld := LAMP_AT * length
		var lamp_xf := _upright(x0 + ld, KERB_H, z, side, lx, t)
		lamps.set_instance_transform(first_lamp + n_lamps, lamp_xf)
		var head := lamp_xf * Vector3(-(RoadChunkBuilder.LAMP_ARM - 0.2), 0.0, 0.0)
		var pool_xf := RoadChunkBuilder._xf(x0 * sx, RoadChunkBuilder.POOL_Y, z, t)
		pool_xf.origin = Vector3(head.x, pool_xf.origin.y + (head.y - lamp_xf.origin.y), head.z)
		pool_xf.basis = pool_xf.basis * Basis.from_scale(Vector3(RoadChunkBuilder.POOL_ACROSS, 1.0, RoadChunkBuilder.POOL_ALONG))
		pools.set_instance_transform(first_lamp + n_lamps, pool_xf)
		n_lamps += 1
		# the parked car: left-hand kerb (local -X), nose away from the road
		var cd := float(m.car_t) * length
		var car_xf := _upright(x0 + cd, 0.0, z, side, -(ROAD_HALF - 0.95), t)
		props.set_instance_transform(n_props, car_xf)
		var tint: Color = m.car_tint
		props.set_instance_custom_data(n_props, Color(float(SHAPE_CAR), tint.r, tint.g, tint.b))
		n_props += 1
		# the stop sign: right-hand pavement at the mouth, facing down the street
		var sign_xf := _upright(x0 + SIGN_IN, KERB_H, z, side, lx, t)
		props.set_instance_transform(n_props, sign_xf)
		props.set_instance_custom_data(n_props, Color(float(SHAPE_SIGN), 1.0, 1.0, 1.0))
		n_props += 1
		placed.append({"side": side, "z": z, "x0": x0, "len": length, "kit": kit_xf, "lamp": lamp_xf, "pool": pool_xf, "car": car_xf, "sign": sign_xf})
		n += 1
	kit.visible_instance_count = n
	props.visible_instance_count = n_props
	root.set_meta("side_streets", placed)
	return n_lamps

## An upright thing `along` m into the street and `across` m from its centre
## line (local +X is the street's right-hand side), standing on the road
## surface there: the street runs along the road's x, so the surface point
## is the station at z ± across, x = along.
static func _upright(along: float, y: float, z: float, side: int, across: float, t: Basis) -> Transform3D:
	# local +X of the street frame is world +z for side 1 (turn by -90 deg
	# takes +X to +Z), world -z for side -1
	var zz := z + across * float(side)
	return RoadChunkBuilder._xf_up(along * float(side), y, zz, t)

# ---------- geometry helpers ----------
#
# Every face goes through _face, which winds it clockwise seen from outside
# (Godot's front face): the outward normal of a clockwise triangle (a, b, c)
# is (c - a) x (b - a), so a quad whose corners come in the other order is
# reversed. The lamp-mesh rule in tests/world/roadside_detail.gd is checked
# on these meshes by tests/world/side_streets.gd.

## Quad p0..p3 (a loop round the face) with outward normal n; colours per
## corner; uv2 = (shape, glow) for the prop shader.
static func _face(st: SurfaceTool, p: Array, n: Vector3, cols: Array, uv2: Vector2) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	var a: Vector3 = p[0]
	if (p[2] - a).cross(p[1] - a).dot(n) < 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i in order:
		st.set_normal(n)
		st.set_color(cols[i])
		st.set_uv2(uv2)
		st.add_vertex(p[i])

## A flat quad from a (near, left) to b (far, right), colour fading along -Z.
static func _quad_fade(st: SurfaceTool, a: Vector3, b: Vector3, col: Color) -> void:
	var near := col
	var far := col * FADE_END
	far.a = 1.0
	var p := [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)]
	_face(st, p, Vector3.UP, [near, near, far, far], Vector2.ZERO)

## A kerb-and-pavement block between x0 and x1, h high, 1 m long along -Z,
## reaching FOUNDATION below so it never floats on a hill. Fades like the
## road. No underside: nothing sees it.
static func _block_fade(st: SurfaceTool, x0: float, x1: float, h: float, col: Color) -> void:
	var lo := -RoadChunkBuilder.FOUNDATION
	var near := col
	var far := col * FADE_END
	far.a = 1.0
	var faces := [
		[[Vector3(x0, h, 0.0), Vector3(x1, h, 0.0), Vector3(x1, h, -1.0), Vector3(x0, h, -1.0)], Vector3.UP],
		[[Vector3(x0, lo, 0.0), Vector3(x0, h, 0.0), Vector3(x0, h, -1.0), Vector3(x0, lo, -1.0)], Vector3.LEFT],
		[[Vector3(x1, lo, 0.0), Vector3(x1, h, 0.0), Vector3(x1, h, -1.0), Vector3(x1, lo, -1.0)], Vector3.RIGHT],
		[[Vector3(x0, lo, 0.0), Vector3(x1, lo, 0.0), Vector3(x1, h, 0.0), Vector3(x0, h, 0.0)], Vector3.BACK],
		[[Vector3(x0, lo, -1.0), Vector3(x1, lo, -1.0), Vector3(x1, h, -1.0), Vector3(x0, h, -1.0)], Vector3.FORWARD],
	]
	for fc in faces:
		var p: Array = fc[0]
		var cols := []
		for v in p:
			cols.append(near if (v as Vector3).z > -0.5 else far)
		_face(st, p, fc[1], cols, Vector2.ZERO)

static func _box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color, shape: int) -> void:
	var h := size / 2.0
	var c := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	var faces := [
		[[4, 5, 6, 7], Vector3.BACK], [[0, 1, 2, 3], Vector3.FORWARD], [[1, 5, 6, 2], Vector3.RIGHT],
		[[0, 4, 7, 3], Vector3.LEFT], [[3, 2, 6, 7], Vector3.UP], [[0, 1, 5, 4], Vector3.DOWN],
	]
	var cols := [col, col, col, col]
	for fc in faces:
		var p := []
		for i in fc[0]:
			p.append(center + c[i])
		_face(st, p, fc[1], cols, Vector2(float(shape), 0.0))

## An octagon plate in the XY plane at `center`, front (red, glowing) facing
## -Z and back (grey) facing +Z.
static func _octagon(st: SurfaceTool, center: Vector3, r: float, front: Color, back: Color, shape: int) -> void:
	var pts := []
	for i in 8:
		var a := (float(i) + 0.5) * TAU / 8.0
		pts.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	for i in 8:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[(i + 1) % 8]
		var mid := (p0 + p1) / 2.0  # a degenerate 4th corner keeps _face's quad shape
		var off := Vector3(0.0, 0.0, 0.015)
		_face(st, [center - off, center + p0 - off, center + mid - off, center + p1 - off], Vector3.FORWARD, [front, front, front, front], Vector2(float(shape), 1.0))
		_face(st, [center + off, center + p0 + off, center + mid + off, center + p1 + off], Vector3.BACK, [back, back, back, back], Vector2(float(shape), 0.0))
