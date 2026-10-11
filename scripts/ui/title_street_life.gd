class_name TitleStreetLife
extends RefCounted

# Street life on the Kerbside title set (menu street life M8, 2026-10-11):
# five small things the turbo and its wind stir up, each one node, one mesh
# and one shader with the motion in the vertex shader off the title's street
# `clock` uniform (the roaches' clock), the lamp life `wind` and one event
# time uniform per part, so nothing here costs script per frame and the
# picture holds still for a screenshot.
#
#   C  Neighbour   a window above the shop front: on a long hard boost (or a
#                  second big blow-off) it lights warm, the blind snaps up, a
#                  head-and-shoulders stands there two seconds, the blind
#                  drops, the light goes off (wake_t)
#   D  Pigeons     four hunched on the lamp arm, heads bobbing; a boost over
#                  0.6 (or a passing car) lifts them off together through the
#                  lamp light and out of the top of the frame; they come back
#                  one by one 20-40 s later (lift_t, return time per bird)
#   E  Cat         sits on the shutter box, eyes catching the lamp, tail
#                  flicking; a boost over 0.7 drops it to the sidewalk and it
#                  runs off right out of frame; back 45-90 s later (leave_t,
#                  back_t)
#   F  BinBags     three bags and a split cardboard box against the wall by
#   +  Flies       the shutter, a cloud of flies over them (the moth shader's
#                  idea, smaller, darker, faster); the bags' tops ruffle with
#                  the wind, and at wind 2 the flies scatter and re-gather
#   G  Wire        a low wire from the lamp post off the top-left of the
#                  frame with a pair of sneakers on it; a gentle swing, harder
#                  and spinning with the wind, and at wind 2 they wrap once
#                  round the wire and unwind as they drop (wrap_t)
#
# The events (neighbour, lift-off, cat leaving) are scheduled by the title
# set (title_kerbside.gd): one at a time, none in the first 10 s, pigeons
# never with the bat's pass. Settings' "Roaches and rats" switch hides the
# flies with the roaches and the rats; nothing else here. All of it is in
# Amber vs Dusk: dusk greys, the window's amber-white, the cat's amber eyes.
# Positions are set space (title_kerbside.gd): the wall face at z = WALL_Z,
# the sidewalk at y = WALK_Y, the shutter about x = 1.9.

const StreetAnimals := preload("res://scripts/world/street_animals.gd")

const WALL_Z := -2.5
const WALK_Y := 0.1
## The shutter box above the roller shutter: the cat's seat.
const BOX_AT := Vector3(1.9, 2.97, -2.36)
const BOX_SIZE := Vector3(3.7, 0.34, 0.28)
## The neighbour's window, above the shop front.
const WINDOW_AT := Vector3(1.9, 5.3, WALL_Z)
const WINDOW_W := 1.1
const WINDOW_H := 1.4
## Neighbour timeline, seconds after wake_t.
const WAKE_LIGHT_ON := 0.3
const WAKE_BLIND_UP := 0.5
const WAKE_BLIND_UP_LEN := 0.25
const WAKE_HEAD_LEN := 2.0
const WAKE_BLIND_DOWN_LEN := 0.35
const WAKE_LIGHT_OFF := 0.3
const WAKE_LEN := WAKE_BLIND_UP + WAKE_BLIND_UP_LEN + WAKE_HEAD_LEN + WAKE_BLIND_DOWN_LEN + WAKE_LIGHT_OFF   # 3.4
## Pigeons: on the lamp arm (the post at x = -1.1, arm top y = 7.6, along +Z).
const PIGEON_COUNT := 4
const PERCH_X := -1.1
const PERCH_Y := 7.6
const PERCH_Z := [-0.5, -0.2, 0.1, 0.4]
const LIFT_STAGGER := 0.08
const LIFT_FLY := 2.4          # s from the arm to out of frame
const RETURN_FLY := 2.6        # s from out of frame back to the arm
const RETURN_MIN := 20.0
const RETURN_MAX := 40.0
## The cat: seat on the shutter box, drop, run right, back along the sidewalk.
const CAT_SCALE := 0.85
const CAT_SIT := Vector3(3.0, 3.14, -2.3)
const CAT_LAND := Vector3(3.0, WALK_Y, -1.7)
const CAT_OFF_X := 17.0
const CAT_DROP := 0.45
const CAT_SPEED := 5.5
const CAT_RUN := (CAT_OFF_X - 3.0) / CAT_SPEED   # ~2.5 s
const CAT_RUN_IN := CAT_RUN
const CAT_JUMP := 0.5
const CAT_BACK_MIN := 45.0
const CAT_BACK_MAX := 90.0
## Bags and the box, by the shutter; the flies' nest over them.
const BAGS := [[Vector3(4.4, WALK_Y, -2.17), 0.36, 0.55], [Vector3(4.95, WALK_Y, -2.1), 0.32, 0.5],
	[Vector3(5.4, WALK_Y, -2.2), 0.30, 0.45], [Vector3(4.72, WALK_Y + 0.5, -2.25), 0.25, 0.36]]
const BOX_CARD_AT := Vector3(6.05, WALK_Y, -2.25)
const BOX_CARD_SIZE := Vector3(0.6, 0.42, 0.45)
const FLY_COUNT := 26
const FLY_NEST := Vector3(4.85, 0.95, -2.15)
## The wire: from the lamp post top off the top-left of the frame; the
## shoes hang at WIRE_SHOES of the way along.
const WIRE_A := Vector3(-1.1, 6.9, -0.6)
const WIRE_B := Vector3(-16.0, 8.0, 1.5)
const WIRE_SAG := 0.6
const WIRE_SHOES := 0.30
const SHOE_DROP := 0.55
const WRAP_WIND := 1.98
const WRAP_UP := 1.1
const WRAP_DOWN := 2.5
const WRAP_LEN := WRAP_UP + WRAP_DOWN
const RANGE := 60.0

static var _meshes := {}
static var _mats := {}

# ---------- the clock and the wind ----------

static func set_clock(t: float) -> void:
	for m in _mats.values():
		(m as ShaderMaterial).set_shader_parameter("clock", t)

static func set_wind(w: float) -> void:
	for m in _mats.values():
		(m as ShaderMaterial).set_shader_parameter("wind", w)

static func set_uniform(part: String, uniform: String, value: Variant) -> void:
	mat(part).set_shader_parameter(uniform, value)

static func uniform(part: String, uniform: String) -> Variant:
	return mat(part).get_shader_parameter(uniform)

# ---------- mirrors of the shaders (tests, scheduling) ----------

## The neighbour's window at seconds `a` after wake_t: {light 0..1, blind
## 0 down..1 up, head true while the shape stands there}.
static func neighbour_at(a: float) -> Dictionary:
	if a < 0.0:
		return {"light": 0.0, "blind": 0.0, "head": false}
	var off_at := WAKE_LEN - WAKE_LIGHT_OFF
	var light := smoothstep(0.0, WAKE_LIGHT_ON, a) * (1.0 - smoothstep(off_at, WAKE_LEN, a))
	var up0 := WAKE_BLIND_UP
	var up1 := up0 + WAKE_BLIND_UP_LEN
	var down0 := up1 + WAKE_HEAD_LEN
	var down1 := down0 + WAKE_BLIND_DOWN_LEN
	var blind := smoothstep(up0, up1, a) * (1.0 - smoothstep(down0, down1, a))
	return {"light": light, "blind": blind, "head": a >= up0 + 0.1 and a <= down1 - 0.1}

## What pigeon i is doing at clock t: "rest", "out" (flying off), "gone",
## "back" (flying in). lift_t -1: never lifted; ret_t: its return clock.
static func pigeon_state(i: int, t: float, lift_t: float, ret_t: float) -> String:
	if lift_t < 0.0:
		return "rest"
	var a := t - lift_t - LIFT_STAGGER * float(i)
	if a < 0.0:
		return "rest"
	if a < LIFT_FLY:
		return "out"
	if ret_t < 0.0 or t < ret_t:
		return "gone"
	if t < ret_t + RETURN_FLY:
		return "back"
	return "rest"

## The cat at clock t: "sit", "drop", "run", "gone", "run_in", "jump".
static func cat_state(t: float, leave_t: float, back_t: float) -> String:
	if leave_t < 0.0:
		return "sit"
	var a := t - leave_t
	if a < 0.0:
		return "sit"
	if a < CAT_DROP:
		return "drop"
	if a < CAT_DROP + CAT_RUN:
		return "run"
	if back_t < 0.0 or t < back_t:
		return "gone"
	var b := t - back_t
	if b < CAT_RUN_IN:
		return "run_in"
	if b < CAT_RUN_IN + CAT_JUMP:
		return "jump"
	return "sit"

## The shoes' wrap at seconds `a` after wrap_t: 0 hanging free, 1 wound
## round the wire; up over WRAP_UP, back down over WRAP_DOWN.
static func wrap_at(a: float) -> float:
	if a < 0.0 or a > WRAP_LEN:
		return 0.0
	if a < WRAP_UP:
		return smoothstep(0.0, WRAP_UP, a)
	return 1.0 - smoothstep(WRAP_UP, WRAP_LEN, a)

## A point on the wire, 0 at the post, 1 off frame.
static func wire_point(t: float) -> Vector3:
	var p := WIRE_A.lerp(WIRE_B, t)
	p.y -= WIRE_SAG * 4.0 * t * (1.0 - t)
	return p

# ---------- nodes ----------

static func create_all() -> Array[Node3D]:
	return [create_neighbour(), create_pigeons(), create_cat(), create_bags(), create_flies(), create_wire()]

static func _mesh_node(node_name: String, mesh: Mesh, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = RANGE
	return mi

static func _mm_node(node_name: String, mesh: Mesh, m: Material, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = count
	for i in count:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = RANGE
	return mmi

static func create_neighbour() -> MeshInstance3D:
	return _mesh_node("Neighbour", mesh("neighbour"), mat("neighbour"))

static func create_pigeons() -> MultiMeshInstance3D:
	var n := _mm_node("Pigeons", mesh("pigeon"), mat("pigeon"), PIGEON_COUNT)
	for i in PIGEON_COUNT:
		n.multimesh.set_instance_custom_data(i, pigeon_custom(i, -1.0))
	return n

## Custom data of pigeon i: x seed, y perch z, z return clock (-1 none),
## w which way it faces along the arm (+1 / -1).
static func pigeon_custom(i: int, ret_t: float) -> Color:
	var s := fposmod(0.23 + 0.6180339887 * float(i), 1.0)
	return Color(s, float(PERCH_Z[i]), ret_t, 1.0 if i % 2 == 0 else -1.0)

static func create_cat() -> MultiMeshInstance3D:
	var n := _mm_node("Cat", StreetAnimals.mesh(), mat("cat"), 1)
	n.multimesh.set_instance_custom_data(0, Color(1.0, 0.0, 0.0, 0.0))
	return n

static func create_bags() -> MeshInstance3D:
	return _mesh_node("BinBags", mesh("bags"), mat("bags"))

static func create_flies() -> MeshInstance3D:
	var n := _mesh_node("Flies", mesh("flies"), mat("flies"))
	return n

static func create_wire() -> MeshInstance3D:
	return _mesh_node("Wire", mesh("wire"), mat("wire"))

static func triangles(part: String) -> int:
	return floori(float(mesh(part).surface_get_array_len(0)) / 3.0)

# ---------- meshes ----------

class _Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()

	func tri(a: Vector3, b: Vector3, cc: Vector3, col: Color, root := Vector2.ZERO) -> void:
		var nrm := (b - a).cross(cc - a)
		nrm = nrm.normalized() if nrm.length() > 1e-9 else Vector3.UP
		for p in [a, b, cc]:
			v.append(p)
			n.append(nrm)
			c.append(col)
			uv.append(root)

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, col: Color, root := Vector2.ZERO) -> void:
		tri(a, b, cc, col, root)
		tri(a, cc, d, col, root)

	## A triangle with its own colour and UV per corner.
	func tri_each(pts: Array, cols: Array, uvs: Array) -> void:
		var nrm: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0])
		nrm = nrm.normalized() if nrm.length() > 1e-9 else Vector3.UP
		for i in 3:
			v.append(pts[i])
			n.append(nrm)
			c.append(cols[i])
			uv.append(uvs[i])

	## A quad with its own colour and UV per corner (a, b, cc, d in order).
	func quad_each(pts: Array, cols: Array, uvs: Array) -> void:
		tri_each([pts[0], pts[1], pts[2]], [cols[0], cols[1], cols[2]], [uvs[0], uvs[1], uvs[2]])
		tri_each([pts[0], pts[2], pts[3]], [cols[0], cols[2], cols[3]], [uvs[0], uvs[2], uvs[3]])

	## A box, faces wound outward, every vertex with the same colour.
	func box(center: Vector3, size: Vector3, col: Color) -> void:
		var h := size * 0.5
		var faces := [
			[Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)],
			[Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)],
			[Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)],
			[Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z)],
			[Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
			[Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
		]
		for f in faces:
			quad(center + f[0], center + f[1], center + f[2], center + f[3], col)

	## A lump: rings of `sides` points about a vertical axis at `at`, from
	## the ground to height h, with the radius profile `prof` [[frac of h,
	## frac of r], ...] and a little per-vertex noise. col.g is overwritten
	## with the height fraction.
	func lump(at: Vector3, r: float, h: float, prof: Array, sides: int, col: Color, seed: float) -> void:
		var rings := []
		for k in prof.size():
			var row := []
			for i in sides:
				var a := TAU * float(i) / float(sides)
				var nz := 1.0 + 0.09 * (fposmod((seed + float(i) * 0.371 + float(k) * 0.713) * 17.0, 1.0) - 0.5)
				var rr: float = r * float(prof[k][1]) * nz
				row.append(at + Vector3(cos(a) * rr, h * float(prof[k][0]), sin(a) * rr))
			rings.append(row)
		for k in prof.size() - 1:
			var ck := Color(col.r, float(prof[k][0]), col.b, 1.0)
			for i in sides:
				var i1 := (i + 1) % sides
				quad(rings[k][i], rings[k + 1][i], rings[k + 1][i1], rings[k][i1], ck)
		var top := at + Vector3(0.0, h, 0.0)
		var ct := Color(col.r, 1.0, col.b, 1.0)
		var last: Array = rings[prof.size() - 1]
		for i in sides:
			tri(last[i], top, last[(i + 1) % sides], ct)

	func commit(aabb: AABB) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.custom_aabb = aabb
		return m

static func mesh(part: String) -> ArrayMesh:
	if not _meshes.has(part):
		match part:
			"neighbour":
				_meshes[part] = _neighbour_mesh()
			"pigeon":
				_meshes[part] = _pigeon_mesh()
			"bags":
				_meshes[part] = _bags_mesh()
			"flies":
				_meshes[part] = _flies_mesh()
			"wire":
				_meshes[part] = _wire_mesh()
	return _meshes[part]

# Neighbour parts, COLOR.r: 0 frame and sill (dark painted wood), 0.2 the
# shutter box, 0.5 glass, 0.75 the blind (UV.y = 0 at the top rail, 1 at
# the hem; the shader draws it up), 1 the head and shoulders.
static func _neighbour_mesh() -> ArrayMesh:
	var b := _Buf.new()
	var w := WINDOW_W
	var h := WINDOW_H
	var c := WINDOW_AT
	var frame := Color(0.0, 0.0, 0.0, 1.0)
	var t := 0.08
	var proud := 0.06
	# frame: four strips standing proud of the wall
	b.box(c + Vector3(0.0, h * 0.5 + t * 0.5, proud * 0.5), Vector3(w + 2.0 * t, t, proud), frame)
	b.box(c + Vector3(0.0, -h * 0.5 - t * 0.5, proud * 0.5), Vector3(w + 2.0 * t, t, proud), frame)
	b.box(c + Vector3(-w * 0.5 - t * 0.5, 0.0, proud * 0.5), Vector3(t, h, proud), frame)
	b.box(c + Vector3(w * 0.5 + t * 0.5, 0.0, proud * 0.5), Vector3(t, h, proud), frame)
	# a thin mullion down the middle
	b.box(c + Vector3(0.0, 0.0, proud * 0.4), Vector3(0.04, h, proud * 0.8), frame)
	# the sill
	b.box(c + Vector3(0.0, -h * 0.5 - t - 0.02, 0.08), Vector3(w + 2.0 * t + 0.1, 0.05, 0.16), frame)
	# the shutter box over the roller shutter
	b.box(BOX_AT, BOX_SIZE, Color(0.2, 0.0, 0.0, 1.0))
	# glass, 1 cm proud of the wall; the shutter and the silhouette in front
	var g := Color(0.5, 0.0, 0.0, 1.0)
	var z := c.z + 0.01
	b.quad(Vector3(c.x - w * 0.5, c.y - h * 0.5, z), Vector3(c.x - w * 0.5, c.y + h * 0.5, z),
		Vector3(c.x + w * 0.5, c.y + h * 0.5, z), Vector3(c.x + w * 0.5, c.y - h * 0.5, z), g)
	# head and shoulders: a cap of an octagon on a trapezoid, dark
	var s := Color(1.0, 0.0, 0.0, 1.0)
	var zs := c.z + 0.02
	var head := Vector3(c.x + 0.05, c.y + 0.05, zs)
	var hr := 0.14
	for i in 8:
		var a0 := TAU * float(i) / 8.0
		var a1 := TAU * float(i + 1) / 8.0
		b.tri(head, head + Vector3(cos(a1) * hr * 0.85, sin(a1) * hr, 0.0), head + Vector3(cos(a0) * hr * 0.85, sin(a0) * hr, 0.0), s)
	var neck_y := head.y - hr + 0.02
	b.quad(Vector3(head.x - 0.06, neck_y, zs), Vector3(head.x - 0.06, neck_y - 0.12, zs),
		Vector3(head.x + 0.06, neck_y - 0.12, zs), Vector3(head.x + 0.06, neck_y, zs), s)
	var sh_y := neck_y - 0.10
	b.quad(Vector3(head.x - 0.20, sh_y - 0.06, zs), Vector3(head.x - 0.34, c.y - h * 0.5, zs),
		Vector3(head.x + 0.34, c.y - h * 0.5, zs), Vector3(head.x + 0.20, sh_y - 0.06, zs), s)
	b.quad(Vector3(head.x - 0.20, sh_y + 0.04, zs), Vector3(head.x - 0.20, sh_y - 0.06, zs),
		Vector3(head.x + 0.20, sh_y - 0.06, zs), Vector3(head.x + 0.20, sh_y + 0.04, zs), s)
	# the blind: a sheet from the top rail; UV.y 0 at the rail, 1 at the hem
	var bl := Color(0.75, 0.0, 0.0, 1.0)
	var zb := c.z + 0.03
	var rows := 6
	for r in rows:
		var y0 := c.y + h * 0.5 - h * float(r) / float(rows)
		var y1 := c.y + h * 0.5 - h * float(r + 1) / float(rows)
		var u0 := Vector2(0.0, float(r) / float(rows))
		var u1 := Vector2(0.0, float(r + 1) / float(rows))
		b.quad_each([Vector3(c.x - w * 0.5, y0, zb), Vector3(c.x + w * 0.5, y0, zb), Vector3(c.x + w * 0.5, y1, zb), Vector3(c.x - w * 0.5, y1, zb)],
			[bl, bl, bl, bl], [u0, u0, u1, u1])
	# the blind's rail at the top
	b.box(c + Vector3(0.0, h * 0.5 - 0.03, 0.035), Vector3(w, 0.06, 0.04), frame)
	return b.commit(AABB(Vector3(-0.5, 2.5, -3.0), Vector3(5.0, 4.5, 1.5)))

# Pigeon parts, COLOR.r: 0 body and tail, 0.25 head, 0.5 wing (COLOR.g side
# -1/+1; the wing hinges on the x axis through y = 0.10). Forward +X, feet
# at y = 0, about 0.3 m long, hunched.
static func _pigeon_mesh() -> ArrayMesh:
	var b := _Buf.new()
	var rings := [[-0.13, 0.025], [-0.08, 0.055], [-0.02, 0.065], [0.04, 0.06], [0.085, 0.045], [0.11, 0.03]]
	var sides := 6
	var pts := []
	for ring in rings:
		var x: float = ring[0]
		var r: float = ring[1]
		var row := []
		for k in sides:
			var a := (float(k) + 0.5) / float(sides) * TAU
			row.append(Vector3(x, 0.04 + r * 0.9 * (1.0 + sin(a)), r * cos(a)))
		pts.append(row)
	var body := Color(0.0, 0.0, 0.0, 1.0)
	for i in rings.size() - 1:
		for k in sides:
			var k1 := (k + 1) % sides
			b.quad(pts[i][k], pts[i][k1], pts[i + 1][k1], pts[i + 1][k], body)
	# the tail: a flat fan behind the body
	b.quad(Vector3(-0.12, 0.085, -0.035), Vector3(-0.12, 0.085, 0.035), Vector3(-0.23, 0.10, 0.05), Vector3(-0.23, 0.10, -0.05), body)
	b.quad(Vector3(-0.12, 0.085, 0.035), Vector3(-0.12, 0.085, -0.035), Vector3(-0.23, 0.10, -0.05), Vector3(-0.23, 0.10, 0.05), body)
	# the head: a small lump tucked forward, part 0.25
	var head := Color(0.25, 0.0, 0.0, 1.0)
	var hrings := [[0.10, 0.015], [0.125, 0.034], [0.16, 0.028], [0.185, 0.012]]
	var hp := []
	for ring in hrings:
		var x: float = ring[0]
		var r: float = ring[1]
		var row := []
		for k in sides:
			var a := (float(k) + 0.5) / float(sides) * TAU
			row.append(Vector3(x, 0.11 + r * (sin(a)), r * cos(a)))
		hp.append(row)
	for i in hrings.size() - 1:
		for k in sides:
			var k1 := (k + 1) % sides
			b.quad(hp[i][k], hp[i][k1], hp[i + 1][k1], hp[i + 1][k], head)
	# beak
	b.tri(Vector3(0.185, 0.115, -0.008), Vector3(0.185, 0.115, 0.008), Vector3(0.215, 0.105, 0.0), Color(0.25, 0.5, 0.0, 1.0))
	# wings: a quad each side hinged along the spine (y = 0.10), tip out at z
	for side: float in [-1.0, 1.0]:
		var w := Color(0.5, 0.5 + side * 0.5, 0.0, 1.0)
		var r0 := Vector3(-0.06, 0.10, side * 0.02)
		var r1 := Vector3(0.07, 0.10, side * 0.02)
		var t0 := Vector3(-0.10, 0.10, side * 0.30)
		var t1 := Vector3(0.03, 0.10, side * 0.33)
		if side > 0.0:
			b.quad(r0, r1, t1, t0, w)
		else:
			b.quad(r0, t0, t1, r1, w)
	# the shader flies them off the arm and over the camera
	return b.commit(AABB(Vector3(-4.0, 6.0, -2.0), Vector3(8.0, 8.0, 10.0)))

# Bags, COLOR.r: 0 black plastic (COLOR.g height fraction), 0.5 cardboard
# (COLOR.b 1 on a flap's free edge).
static func _bags_mesh() -> ArrayMesh:
	var b := _Buf.new()
	var prof := [[0.0, 0.8], [0.3, 1.0], [0.62, 0.9], [0.85, 0.6], [0.96, 0.3]]
	var plastic := Color(0.0, 0.0, 0.0, 1.0)
	var k := 0
	for bag in BAGS:
		b.lump(bag[0], float(bag[1]), float(bag[2]), prof, 8, plastic, 0.3 + 0.17 * float(k))
		# the knot: a small tuft on top
		var top: Vector3 = bag[0] + Vector3(0.0, float(bag[2]), 0.0)
		b.quad(top + Vector3(-0.03, 0.0, -0.02), top + Vector3(0.0, 0.07, 0.0), top + Vector3(0.03, 0.0, 0.02), top + Vector3(0.0, 0.03, 0.0), Color(0.0, 1.0, 0.0, 1.0))
		k += 1
	# the split cardboard box: open, one flap up and torn, one hanging out
	var card := Color(0.5, 0.0, 0.0, 1.0)
	var c := BOX_CARD_AT
	var s := BOX_CARD_SIZE
	var hx := s.x * 0.5
	var hz := s.z * 0.5
	var y0 := c.y
	var y1 := c.y + s.y
	# four sides and the bottom, as thin quads, cull off in the shader
	b.quad(Vector3(c.x - hx, y0, c.z + hz), Vector3(c.x - hx, y1, c.z + hz), Vector3(c.x + hx, y1, c.z + hz), Vector3(c.x + hx, y0, c.z + hz), card)
	b.quad(Vector3(c.x + hx, y0, c.z - hz), Vector3(c.x + hx, y1, c.z - hz), Vector3(c.x - hx, y1, c.z - hz), Vector3(c.x - hx, y0, c.z - hz), card)
	b.quad(Vector3(c.x + hx, y0, c.z + hz), Vector3(c.x + hx, y1, c.z + hz), Vector3(c.x + hx, y1, c.z - hz), Vector3(c.x + hx, y0, c.z - hz), card)
	b.quad(Vector3(c.x - hx, y0, c.z - hz), Vector3(c.x - hx, y1, c.z - hz), Vector3(c.x - hx, y1, c.z + hz), Vector3(c.x - hx, y0, c.z + hz), card)
	# a flap standing open from the far long edge, leaning out over the road
	var flap := Color(0.5, 0.0, 1.0, 1.0)
	b.quad(Vector3(c.x - hx, y1, c.z + hz), Vector3(c.x - hx, y1 + 0.12, c.z + hz + 0.19), Vector3(c.x + hx * 0.4, y1 + 0.12, c.z + hz + 0.19), Vector3(c.x + hx * 0.4, y1, c.z + hz), card)
	# the torn half of it, hanging down the side
	b.quad(Vector3(c.x + hx * 0.4, y1, c.z + hz), Vector3(c.x + hx * 0.4, y1 - 0.16, c.z + hz + 0.06), Vector3(c.x + hx, y1 - 0.16, c.z + hz + 0.06), Vector3(c.x + hx, y1, c.z + hz), flap)
	# the other long flap folded flat inward, split down the middle
	b.quad(Vector3(c.x - hx, y1, c.z - hz), Vector3(c.x - hx, y1 + 0.01, c.z - hz + 0.20), Vector3(c.x - 0.02, y1 + 0.01, c.z - hz + 0.20), Vector3(c.x - 0.02, y1, c.z - hz), card)
	b.quad(Vector3(c.x + 0.02, y1, c.z - hz), Vector3(c.x + 0.02, y1 + 0.03, c.z - hz + 0.14), Vector3(c.x + hx, y1 + 0.03, c.z - hz + 0.14), Vector3(c.x + hx, y1, c.z - hz), flap)
	return b.commit(AABB(Vector3(3.5, -0.2, -3.0), Vector3(4.0, 2.0, 2.0)))

static func _flies_mesh() -> ArrayMesh:
	var b := _Buf.new()
	for i in FLY_COUNT:
		var col := Color(0.0, (float(i) + 0.37) / float(FLY_COUNT), 0.0, 1.0)
		b.quad(Vector3(-1, -1, 0), Vector3(-1, 1, 0), Vector3(1, 1, 0), Vector3(1, -1, 0), col)
		# corner UVs: the shader billboards about the centre
		var n := b.uv.size()
		var corners := [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1)]
		for k in 6:
			b.uv[n - 6 + k] = corners[k]
	return b.commit(AABB(Vector3(2.0, -0.5, -4.0), Vector3(8.0, 5.0, 6.0)))

# Wire parts, COLOR.r: 0 the wire (COLOR.g = 0..1 along it), 0.5 laces,
# 0.75 soles, 1 the shoes. Laces and shoes are modelled hanging straight
# down from the hang point; the shader swings, spins and wraps them.
static func _wire_mesh() -> ArrayMesh:
	var b := _Buf.new()
	var segs := 24
	var half := 0.014
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var p0 := wire_point(t0)
		var p1 := wire_point(t1)
		var c0 := Color(0.0, t0, 0.0, 1.0)
		var c1 := Color(0.0, t1, 0.0, 1.0)
		b.quad_each([p0 + Vector3(0, -half, 0), p0 + Vector3(0, half, 0), p1 + Vector3(0, half, 0), p1 + Vector3(0, -half, 0)],
			[c0, c0, c1, c1], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var hang := wire_point(WIRE_SHOES)
	var lace := Color(0.5, 0.0, 0.0, 1.0)
	var shoe := Color(1.0, 0.0, 0.0, 1.0)
	var sole := Color(0.75, 0.0, 0.0, 1.0)
	# two sneakers hanging heel-up by their laces, one a little lower
	var sz := Vector3(0.10, 0.26, 0.10)
	for off: Vector3 in [Vector3(0.0, -SHOE_DROP, 0.07), Vector3(0.03, -SHOE_DROP - 0.07, -0.07)]:
		var top := hang + off
		b.quad(hang + Vector3(-0.006, 0, 0), hang + Vector3(0.006, 0, 0), top + Vector3(0.006, 0, 0), top + Vector3(-0.006, 0, 0), lace)
		b.quad(hang + Vector3(0, 0, -0.006), hang + Vector3(0, 0, 0.006), top + Vector3(0, 0, 0.006), top + Vector3(0, 0, -0.006), lace)
		var centre := top + Vector3(0.0, -sz.y * 0.5, 0.0)
		b.box(centre, sz, shoe)
		# the sole: a dark slab down one long side, and under the toe
		b.box(centre + Vector3(sz.x * 0.5 + 0.006, -0.01, 0.0), Vector3(0.012, sz.y - 0.02, sz.z + 0.012), sole)
		b.box(centre + Vector3(sz.x * 0.3, -sz.y * 0.5 - 0.01, 0.0), Vector3(0.07, 0.02, sz.z + 0.012), sole)
	return b.commit(AABB(Vector3(-17.0, 5.0, -2.0), Vector3(17.0, 5.0, 5.0)))

# ---------- shaders ----------

const NEIGHBOUR_SHADER := """
shader_type spatial;
render_mode cull_disabled;

// COLOR.r: 0 frame, 0.2 shutter box, 0.5 glass, 0.75 blind (UV.y 0 rail..1 hem), 1 silhouette
uniform float clock = 0.0;
uniform float wind = 0.6;
uniform float wake_t = -1.0;   // the clock the neighbour woke, or -1

const float LIGHT_ON = 0.3;
const float BLIND_UP = 0.5;
const float BLIND_UP_LEN = 0.25;
const float HEAD_LEN = 2.0;
const float BLIND_DOWN_LEN = 0.35;
const float LIGHT_OFF = 0.3;
const float LEN = 3.4;

varying float part;
varying float lit;

void vertex() {
	part = COLOR.r;
	float a = wake_t < 0.0 ? -1.0 : clock - wake_t;
	float light = 0.0;
	float blind = 0.0;
	bool head = false;
	if (a >= 0.0) {
		light = smoothstep(0.0, LIGHT_ON, a) * (1.0 - smoothstep(LEN - LIGHT_OFF, LEN, a));
		float up0 = BLIND_UP;
		float up1 = up0 + BLIND_UP_LEN;
		float down0 = up1 + HEAD_LEN;
		float down1 = down0 + BLIND_DOWN_LEN;
		blind = smoothstep(up0, up1, a) * (1.0 - smoothstep(down0, down1, a));
		head = a >= up0 + 0.1 && a <= down1 - 0.1;
	}
	lit = light;
	if (COLOR.r > 0.7 && COLOR.r < 0.8) {
		// the blind rolls up from the hem: the sheet shrinks toward the rail
		float top = 6.0;   // the rail's y (WINDOW_AT.y + WINDOW_H / 2)
		VERTEX.y = top - (top - VERTEX.y) * (1.0 - blind * 0.96);
	} else if (COLOR.r > 0.9) {
		// the head and shoulders: only while the blind is up
		if (!head) { VERTEX = vec3(1.9, 5.3, -2.6); }   // a point in the wall
	}
}

void fragment() {
	if (part < 0.1) {
		ALBEDO = vec3(0.11, 0.09, 0.08);     // dark painted frame
		ROUGHNESS = 0.8;
	} else if (part < 0.3) {
		ALBEDO = vec3(0.17, 0.165, 0.16);    // the shutter box, dull metal
		ROUGHNESS = 0.6;
		METALLIC = 0.3;
	} else if (part < 0.6) {
		// glass: a dusk reflection when dark, amber-white when the light is on
		ALBEDO = mix(vec3(0.07, 0.09, 0.13), vec3(0.6, 0.5, 0.36), lit);
		ROUGHNESS = 0.15;
		SPECULAR = 0.6;
		EMISSION = vec3(1.0, 0.80, 0.55) * 1.3 * lit;
	} else if (part < 0.9) {
		// the blind: pale cloth, lit through from behind when the room is on
		ALBEDO = vec3(0.55, 0.50, 0.42);
		ROUGHNESS = 0.9;
		EMISSION = vec3(1.0, 0.78, 0.5) * 0.45 * lit;
	} else {
		ALBEDO = vec3(0.01);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	}
}
"""

const PIGEON_SHADER := """
shader_type spatial;
render_mode cull_disabled;

// INSTANCE_CUSTOM: x seed, y perch z, z return clock (-1 none), w facing (+1/-1 along the arm)
// COLOR.r: 0 body, 0.25 head, 0.5 wing (COLOR.g side)
uniform float clock = 0.0;
uniform float wind = 0.6;
uniform float lift_t = -1.0;   // the clock the flock lifted, or -1
uniform vec3 perch = vec3(-1.1, 7.6, 0.0);   // x and y of the arm top; z per bird

const float STAGGER = 0.08;
const float FLY = 2.4;
const float RET_FLY = 2.6;

varying float part;

mat2 rot2(float a) { float c = cos(a); float s = sin(a); return mat2(vec2(c, s), vec2(-s, c)); }

// the way out: up and toward the camera, through the lamp light
vec3 path(float a, float sx) { return vec3(sx * 0.5 * a, 0.4 * a + 1.3 * a * a, 1.6 * a); }

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float s = cd.x;
	part = COLOR.r;
	float idx = floor((cd.y + 0.5) / 0.3 + 0.5);   // 0..3 from the perch z
	vec3 P = vec3(perch.x, perch.y, cd.y);
	float a = lift_t < 0.0 ? -1.0 : clock - lift_t - STAGGER * idx;
	float ret = cd.z;
	int state = 0;   // 0 rest, 1 out, 2 gone, 3 back
	if (a >= 0.0) {
		if (a < FLY) { state = 1; }
		else if (ret < 0.0 || clock < ret) { state = 2; }
		else if (clock < ret + RET_FLY) { state = 3; }
	}
	if (state == 2) {
		VERTEX = vec3(P.x, -1.0, P.z);
	} else {
		float sx = s > 0.5 ? 1.0 : -1.0;
		vec3 p = VERTEX;
		vec3 pos = P;
		vec2 dir = vec2(0.0, cd.w);   // at rest: along the arm
		float flap = 0.0;
		float pitch = 0.0;
		if (state == 1) {
			pos = P + path(a, sx);
			dir = normalize(vec2(sx * 0.5, 1.6));
			flap = 1.0;
			pitch = 0.5 - 0.3 * smoothstep(0.0, 1.0, a);
		} else if (state == 3) {
			float ar = FLY * (1.0 - (clock - ret) / RET_FLY);
			pos = P + path(ar, sx);
			dir = -normalize(vec2(sx * 0.5, 1.6));
			flap = 1.0;
			pitch = -0.25 + 0.35 * smoothstep(FLY, 0.0, ar);
		}
		// wings: folded down along the body at rest, beating in flight
		if (COLOR.r > 0.4 && COLOR.r < 0.6) {
			float side = COLOR.g > 0.5 ? 1.0 : -1.0;
			float fold = mix(-1.25, 0.0, flap);
			float beat = flap * (0.9 * sin(clock * 6.283185307 * 7.0 + s * 6.0) + 0.1);
			vec2 rel = p.zy - vec2(0.0, 0.10);
			p.zy = vec2(0.0, 0.10) + rot2(side * (fold + beat)) * rel;
		}
		// the head bobs on a slow loop at rest, a peck now and then
		if (COLOR.r > 0.2 && COLOR.r < 0.3 && state == 0) {
			float bob = 0.012 * sin(clock * 1.1 + s * 6.0);
			float peck = 0.03 * step(0.93, fract(clock * 0.11 + s * 3.0)) * abs(sin(clock * 12.0));
			p.x += bob + peck;
			p.y -= 0.6 * (bob + peck);
		}
		// a settle on landing
		if (state == 0 && ret >= 0.0 && clock >= ret + RET_FLY && clock < ret + RET_FLY + 0.4) {
			p.y -= 0.02 * sin((clock - ret - RET_FLY) / 0.4 * 3.14159);
		}
		if (pitch != 0.0) {
			vec2 rel = p.xy;
			p.xy = rot2(pitch) * rel;
		}
		vec3 f3 = vec3(dir.x, 0.0, dir.y);
		vec3 r3 = vec3(-dir.y, 0.0, dir.x);
		VERTEX = p.x * f3 + p.y * vec3(0.0, 1.0, 0.0) + p.z * r3 + pos;
		NORMAL = NORMAL.x * f3 + NORMAL.y * vec3(0.0, 1.0, 0.0) + NORMAL.z * r3;
	}
}

void fragment() {
	if (part < 0.1) {
		ALBEDO = vec3(0.40, 0.40, 0.44);    // dusk grey
		ROUGHNESS = 0.85;
	} else if (part < 0.3) {
		ALBEDO = vec3(0.30, 0.31, 0.35);    // darker head
		ROUGHNESS = 0.8;
	} else {
		ALBEDO = vec3(0.36, 0.36, 0.40);    // wings
		ROUGHNESS = 0.9;
	}
}
"""

const CAT_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

// The street animals' mesh (nose -Z, tail +Z, eyes UV2.y = 1).
uniform float clock = 0.0;
uniform float wind = 0.6;
uniform float leave_t = -1.0;   // the clock it dropped off the box, or -1
uniform float back_t = -1.0;    // the clock it comes running back, or -1
uniform vec3 seat = vec3(3.0, 3.14, -2.3);
uniform vec3 land = vec3(3.0, 0.1, -1.7);
uniform float off_x = 17.0;

const float SCALE = 0.85;
const float DROP = 0.45;
const float SPEED = 5.5;
const float JUMP = 0.5;

varying float eye;
varying float shine;

mat2 rot2(float a) { float c = cos(a); float s = sin(a); return mat2(vec2(c, s), vec2(-s, c)); }

void vertex() {
	eye = UV2.y;
	float run = (off_x - seat.x) / SPEED;
	int state = 0;   // 0 sit, 1 drop, 2 run, 3 gone, 4 run in, 5 jump
	float a = leave_t < 0.0 ? -1.0 : clock - leave_t;
	float b = back_t < 0.0 ? -1.0 : clock - back_t;
	if (a >= 0.0) {
		if (a < DROP) { state = 1; }
		else if (a < DROP + run) { state = 2; }
		else if (b < 0.0) { state = 3; }
		else if (b < run) { state = 4; }
		else if (b < run + JUMP) { state = 5; }
	}
	if (state == 3) {
		VERTEX = vec3(seat.x, -1.0, seat.z);
		shine = 0.0;
	} else {
		vec3 p = VERTEX * SCALE;
		float st = floor(clock * 24.0) / 24.0;
		// the tail: a lazy sway with a flick now and then (24 fps steps)
		if (VERTEX.z > 0.2 && VERTEX.y < 0.16) {
			float f = (VERTEX.z - 0.21) / 0.22;
			float sway = 0.05 * sin(st * 1.4) + 0.09 * step(0.9, fract(st * 0.13 + 0.3)) * sin(st * 14.0);
			p.x += sway * f * SCALE;
			p.y += 0.02 * f * abs(sin(st * 0.7)) * SCALE;
		}
		vec3 pos = seat;
		vec2 dir = normalize(vec2(-0.85, 0.53));   // along the box toward the lamp, eyes to the road
		float gallop = 0.0;
		if (state == 1) {
			float f = a / DROP;
			pos = mix(seat, land, f);
			pos.y = mix(seat.y, land.y, f * f);
			dir = normalize(vec2(0.6, 1.0));
		} else if (state == 2) {
			pos = land + vec3((a - DROP) * SPEED, 0.0, 0.0);
			dir = vec2(1.0, 0.0);
			gallop = 1.0;
		} else if (state == 4) {
			pos = vec3(off_x - b * SPEED, land.y, land.z);
			dir = vec2(-1.0, 0.0);
			gallop = 1.0;
		} else if (state == 5) {
			float f = (b - run) / JUMP;
			pos = mix(land, seat, f);
			pos.y = mix(land.y, seat.y, 1.0 - (1.0 - f) * (1.0 - f));
			dir = normalize(vec2(-0.3, 1.0));
		}
		if (gallop > 0.5) {
			p.y += 0.05 * abs(sin(st * 6.283185307 * 4.0));
			vec2 rel = p.zy;
			p.zy = rot2(-0.15) * rel;
		}
		// the mesh's nose is -Z: forward f3 is where -Z goes
		vec3 f3 = vec3(dir.x, 0.0, dir.y);
		vec3 r3 = vec3(-dir.y, 0.0, dir.x);
		VERTEX = -p.z * f3 + p.y * vec3(0.0, 1.0, 0.0) + p.x * r3 + pos;
		NORMAL = -NORMAL.z * f3 + NORMAL.y * vec3(0.0, 1.0, 0.0) + NORMAL.x * r3;
		shine = state == 0 ? 1.0 : 0.0;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.95;
	// the eyes catch the lamp while it sits there
	EMISSION = eye > 0.5 ? vec3(1.0, 0.78, 0.38) * shine * 1.7 : vec3(0.0);
}
"""

const BAGS_SHADER := """
shader_type spatial;
render_mode cull_disabled;

// COLOR.r: 0 plastic (COLOR.g height fraction), 0.5 cardboard (COLOR.b flap edge)
uniform float clock = 0.0;
uniform float wind = 0.6;

varying float part;

void vertex() {
	part = COLOR.r;
	float wn = clamp((wind - 0.3) / 1.7, 0.0, 1.0);
	if (COLOR.r < 0.25) {
		// the bags' tops ruffle: more wind, higher up, more
		float h = COLOR.g;
		float amp = 0.035 * wn * h * h;
		float ph = VERTEX.x * 9.0 + VERTEX.y * 7.0 + VERTEX.z * 5.0;
		float sp = 5.0 + 5.0 * wn;
		VERTEX += amp * vec3(sin(clock * sp + ph), 0.5 * sin(clock * sp * 1.3 + ph * 1.7), cos(clock * sp * 0.9 + ph));
	} else if (COLOR.b > 0.5) {
		// a loose flap edge lifts and drops
		VERTEX.y += 0.05 * wn * (0.5 + 0.5 * sin(clock * (4.0 + 3.0 * wn) + VERTEX.x * 3.0));
		VERTEX.z += 0.03 * wn * sin(clock * 5.0 + VERTEX.x * 2.0);
	}
}

void fragment() {
	if (part < 0.25) {
		ALBEDO = vec3(0.025, 0.025, 0.03);   // black plastic: the lamp glints
		ROUGHNESS = 0.28;
		SPECULAR = 0.65;
	} else {
		ALBEDO = vec3(0.40, 0.29, 0.17);     // cardboard
		ROUGHNESS = 0.95;
		SPECULAR = 0.1;
	}
}
"""

const FLIES_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

// A cloud of flies over the bags: the moths' loops, smaller, darker and
// faster. COLOR.g is each fly's phase. Above wind 1.2 they scatter
// downwind and up; as the wind drops they gather again.
uniform float clock = 0.0;
uniform float wind = 0.6;
uniform vec3 nest = vec3(4.85, 0.95, -2.15);

void vertex() {
	float ph = COLOR.g;
	float g = smoothstep(1.2, 2.0, wind);
	float t = clock * (4.0 + 3.0 * ph) + ph * 40.0;
	float a = t * 2.6;
	float r = (0.12 + 0.14 * sin(t * 1.7 + ph * 9.0)) * (1.0 + 6.0 * g);
	vec3 c = nest + vec3(cos(a) * r, 0.10 * sin(t * 3.1 + ph * 5.0) + 0.3 * g * (0.5 + ph), sin(a * 0.93) * r);
	c.x += g * ph * 2.0;
	c += 0.02 * vec3(sin(clock * 31.0 + ph * 50.0), sin(clock * 37.0 + ph * 70.0), sin(clock * 29.0 + ph * 30.0));
	vec4 vp = MODELVIEW_MATRIX * vec4(c, 1.0);
	vp.xy += (UV - vec2(0.5)) * 2.0 * 0.011 * (1.0 - 0.4 * g);
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	ALBEDO = vec3(0.07, 0.06, 0.05);
}
"""

const WIRE_SHADER := """
shader_type spatial;
render_mode cull_disabled;

// COLOR.r: 0 the wire (COLOR.g along it), 0.5 laces, 0.75 soles, 1 shoes.
// The laces and shoes hang from `hang`; the wire's direction there is `axis`.
uniform float clock = 0.0;
uniform float wind = 0.6;
uniform float wrap_t = -1.0;   // the clock the gust wrapped them, or -1
uniform vec3 hang = vec3(-5.57, 6.73, 0.03);
uniform vec3 axis = vec3(-0.99, 0.07, 0.14);

const float WRAP_UP = 1.1;
const float WRAP_LEN = 3.6;

varying float part;

mat3 rot_axis(vec3 ax, float a) {
	float c = cos(a); float s = sin(a); float t = 1.0 - c;
	return mat3(
		vec3(t * ax.x * ax.x + c, t * ax.x * ax.y + s * ax.z, t * ax.x * ax.z - s * ax.y),
		vec3(t * ax.x * ax.y - s * ax.z, t * ax.y * ax.y + c, t * ax.y * ax.z + s * ax.x),
		vec3(t * ax.x * ax.z + s * ax.y, t * ax.y * ax.z - s * ax.x, t * ax.z * ax.z + c));
}

void vertex() {
	part = COLOR.r;
	float wn = clamp((wind - 0.6) / 1.4, 0.0, 1.0);
	if (COLOR.r < 0.25) {
		// the wire sways a little in the middle of its span
		float f = COLOR.g * (1.0 - COLOR.g) * 4.0;
		VERTEX.z += 0.05 * wn * f * sin(clock * 1.7 + COLOR.g * 3.0);
		VERTEX.y -= 0.02 * wn * f * sin(clock * 2.3);
	} else {
		vec3 rel = VERTEX - hang;
		// the wrap: wound up round the wire, then back down as the lace drops
		float wrap = 0.0;
		if (wrap_t >= 0.0) {
			float a = clock - wrap_t;
			if (a >= 0.0 && a <= WRAP_LEN) {
				wrap = a < WRAP_UP ? smoothstep(0.0, WRAP_UP, a) : 1.0 - smoothstep(WRAP_UP, WRAP_LEN, a);
			}
		}
		rel *= 1.0 - 0.8 * wrap;
		// the swing: a slow pendulum, harder in the wind, and a spin
		float swing = (0.04 + 0.24 * wn) * sin(clock * 2.1 + 0.3 * sin(clock * 0.7));
		float across = (0.02 + 0.12 * wn) * sin(clock * 1.6 + 1.0);
		float spin = wn * clock * 1.6 + 0.3 * sin(clock * 0.9);
		rel = rot_axis(vec3(0.0, 1.0, 0.0), spin) * rel;
		rel = rot_axis(normalize(cross(axis, vec3(0.0, 1.0, 0.0))), across) * rel;
		rel = rot_axis(axis, swing + wrap * 6.283185307) * rel;
		VERTEX = hang + rel;
	}
}

void fragment() {
	if (part < 0.25) {
		ALBEDO = vec3(0.035, 0.035, 0.04);
		ROUGHNESS = 0.7;
	} else if (part < 0.6) {
		ALBEDO = vec3(0.5, 0.48, 0.42);     // laces
		ROUGHNESS = 0.9;
	} else if (part < 0.9) {
		ALBEDO = vec3(0.12, 0.11, 0.10);    // rubber soles
		ROUGHNESS = 0.8;
	} else {
		ALBEDO = vec3(0.58, 0.56, 0.50);    // dusty canvas
		ROUGHNESS = 0.92;
	}
}
"""

static func mat(part: String) -> ShaderMaterial:
	if not _mats.has(part):
		var code := ""
		match part:
			"neighbour":
				code = NEIGHBOUR_SHADER
			"pigeon":
				code = PIGEON_SHADER
			"cat":
				code = CAT_SHADER
			"bags":
				code = BAGS_SHADER
			"flies":
				code = FLIES_SHADER
			"wire":
				code = WIRE_SHADER
		var sh := Shader.new()
		sh.code = code
		var m := ShaderMaterial.new()
		m.shader = sh
		if part == "wire":
			var hang := wire_point(WIRE_SHOES)
			m.set_shader_parameter("hang", hang)
			m.set_shader_parameter("axis", (wire_point(WIRE_SHOES + 0.01) - wire_point(WIRE_SHOES - 0.01)).normalized())
		elif part == "pigeon":
			m.set_shader_parameter("perch", Vector3(PERCH_X, PERCH_Y, 0.0))
		elif part == "cat":
			m.set_shader_parameter("seat", CAT_SIT)
			m.set_shader_parameter("land", CAT_LAND)
			m.set_shader_parameter("off_x", CAT_OFF_X)
		elif part == "flies":
			m.set_shader_parameter("nest", FLY_NEST)
		_mats[part] = m
	return _mats[part]
