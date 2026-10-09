extends RefCounted
class_name P1CoupeBuilder

# P1 sports coupe, the player's car (stage D step 1, Roy 2026-10-06: build the
# merged B1 design sheet as is, judge it in game). The shape is the design
# proxy from docs/design/fleet/sheets/p1_coupe.png, exported by
# tools/fleet_design/game_export.py into scripts/p1_coupe_data.gd, so what
# drives is exactly what the sheet shows: long hood, cabin pushed back,
# fastback, hoop wing, pop-up lamps up. 4.42 x 1.80 x 1.24 m, wheelbase 2.52.
#
# Laid out the way B1 planned the game cars, 7 draw calls:
#   Body     one MeshInstance3D, 3 surfaces: body (vertex colours, paint as a
#            shader uniform so recolouring is free), dark glass, lights (glow)
#   wheels   one mesh per axle, drawn 4 times under the physics wheel nodes
# Flat shaded, no textures: the gritty PS2 look, palette Amber vs Dusk.
#
# Visual only. The physics wheels stay where player.gd's CFG puts them
# (r 0.34, x 0.88, z 1.25); the design drew its wheels at r 0.32, x 0.765,
# z 1.26, so each wheel's visual is scaled to the physics tyre radius and
# slid 11.5 cm inboard of its raycast so it fills the arch like the sheet
# instead of standing proud of the body, and the body is drawn BODY_LIFT
# higher than the chassis origin so the car stands at the sheet's ride height
# once the suspension has settled (see BODY_LIFT).
#
# The neutral #63 test box is still there for comparison: run with
# NEON_TEST_CAR=1 (see PlayerCar.chassis_kind).

const Data := preload("res://scripts/p1_coupe_data.gd")

const KIND := "p1_coupe"
const PAINT := Color("#FF8A1F")   # Sodium, the hero paint
const LENGTH := 4.42
const WIDTH := 1.80
const HEIGHT := 1.24
const DESIGN_WHEEL_R := 0.32
const DESIGN_WHEEL_X := 0.765
## The chassis origin is on the ground only with the springs fully extended;
## at rest they sit about half compressed (measured 11 cm front, 13 cm rear
## with the default coupe), which left the body 12 cm lower on its wheels than
## the sheet, sill on the road and tyres up in the arches. The body is drawn
## this much higher so the car stands at the sheet's ride height at rest and
## still dips and squats with the suspension. Visual only; 0 shows the raw
## physics stance.
const BODY_LIFT := 0.12
const GLOW_ENERGY := 2.5
## Door mirrors (cockpit milestone, 2026-10-06): the sheet has none, so two small
## paint-coloured cups on short stalks at the belt line by the A-pillars, open
## toward the driver. Centre in body space (before BODY_LIFT) and the yaw of the
## open face about +y; the cockpit's mirror glass and cameras sit in them.
const MIRRORS := [
	{"pos": Vector3(-1.01, 0.86, -0.55), "yaw": 12.0},
	{"pos": Vector3(1.01, 0.86, -0.55), "yaw": -20.0},
]
const MIRROR_SIZE := Vector3(0.21, 0.125, 0.10)
const MIRROR_INSIDE := Color("#0B0E14")
## Faces whose colour is the paint: flagged in the vertex alpha so one surface
## carries paint and trim and the paint can still change at runtime.
const PAINT_MATS := ["paint", "roof"]
const RIM_MATS := ["rim", "rim_face"]

const BODY_SHADER := """
shader_type spatial;
render_mode cull_back;
// Vertex alpha 0 marks paint (or rim) faces; they take the tint and a glossier finish.
uniform vec3 paint : source_color = vec3(1.0, 0.54, 0.12);
uniform float paint_metallic = 0.5;
uniform float paint_roughness = 0.38;
void fragment() {
	float p = 1.0 - COLOR.a;
	ALBEDO = mix(COLOR.rgb, paint, p);
	METALLIC = mix(0.1, paint_metallic, p);
	ROUGHNESS = mix(0.75, paint_roughness, p);
	SPECULAR = 0.5;
}
"""

## Lights are drawn from both sides: the lamp lenses are single quads laid on
## the body, and the design's left pop-up lens is wound the other way round
## (one side of the sheet's 4 head triangles), which backface culling would hide.
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float energy = 2.5;
uniform float brake_gain = 2.2;
// Brake lamps (2026-10-09): per-instance, set by set_lamps(). Slots 1 and 2 are
// free: the body shader above has no instance uniforms.
instance uniform float brake : instance_index(1) = 0.0;
instance uniform float reverse : instance_index(2) = 0.0;
void fragment() {
	vec3 c = COLOR.rgb;
	// Linear colours: the tail red is the only lamp with green and blue near 0.
	float tail = step(0.4, c.r) * step(c.g, 0.06) * step(c.b, 0.06);
	// Reverse: the tail lens goes warm white until the brake is on (brake wins,
	// red and brighter). The sheet has no separate reverse lens.
	c = mix(c, vec3(0.8, 0.62, 0.35), tail * reverse * (1.0 - brake) * 0.8);
	ALBEDO = c;
	EMISSION = c * energy * mix(1.0, 1.0 + brake * brake_gain, tail);
}
"""

static var _body_mesh: ArrayMesh
static var _wheel_meshes := {}
static var _body_shader: Shader
static var _glow_shader: Shader
static var _glass_mat: StandardMaterial3D
static var _glow_mat: ShaderMaterial
static var _wheel_mat: ShaderMaterial

## Body, glass, lights and the sticker slot markers -- no wheels, those hang
## under the physics wheel nodes (build_wheel_visual). Metas, read by CarFx
## and the effects: "kind", "body_mat" (ShaderMaterial, paint uniform),
## "half_w", "half_l", "exhaust_tips", "sticker_slots", "headlights", "tail_lights".
static func build_chassis_visual(paint: Color = PAINT) -> Node3D:
	var root := Node3D.new()
	root.name = "P1Coupe"
	root.set_meta("kind", KIND)

	var lift := Vector3(0.0, BODY_LIFT, 0.0)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.position = lift
	var mesh := _get_body_mesh()
	body.mesh = mesh
	var paint_mat := _new_paint_material(paint)
	for i in mesh.get_surface_count():
		if mesh.surface_get_name(i) == "body":
			body.set_surface_override_material(i, paint_mat)
	root.add_child(body)
	var mirrors := _build_mirrors()
	mirrors.position = lift
	mirrors.set_surface_override_material(0, paint_mat)   # same paint, recolours with the body
	root.add_child(mirrors)

	var slots := []
	for s in Data.STICKER_SLOTS:
		var placements: Array = s.placements
		for k in placements.size():
			var p: Dictionary = placements[k]
			var marker := Node3D.new()
			marker.name = "Sticker_%s" % s.id
			if placements.size() > 1:
				marker.name += "_L" if p.center.x < 0.0 else "_R"
			marker.transform = slot_transform(p.center + lift, p.normal)
			root.add_child(marker)
			slots.append({"id": s.id, "note": s.note, "size": s.size, "center": p.center + lift,
				"normal": p.normal, "node": marker})
	root.set_meta("sticker_slots", slots)

	# Positions below are in the car's space (the vehicle node's), lift included.
	var tips := []
	for t in Data.EXHAUST_TIPS:
		tips.append({"pos": t.pos + lift, "dir": t.dir, "r": t.r})
	root.set_meta("exhaust_tips", tips)
	var lamps := _lamp_centres()
	root.set_meta("headlights", [lamps.head[0] + lift, lamps.head[1] + lift])
	root.set_meta("tail_lights", [lamps.tail[0] + lift, lamps.tail[1] + lift])

	root.set_meta("body_mat", paint_mat)
	root.set_meta("half_w", WIDTH / 2.0)
	root.set_meta("half_l", LENGTH / 2.0)
	return root

## Brake lamps on/off (0..1) and reverse lamps for the player's body; `vis`
## is its chassis_visual. Two instance uniforms on the Body, no material change.
static func set_lamps(vis: Node3D, brake: float, reverse: bool) -> void:
	var mi := vis.get_node_or_null(^"Body") as MeshInstance3D
	if mi != null:
		mi.set_instance_shader_parameter("brake", brake)
		mi.set_instance_shader_parameter("reverse", 1.0 if reverse else 0.0)

static func recolor(car: Node3D, color: Color) -> void:
	var m: ShaderMaterial = car.get_meta("body_mat")
	if m:
		m.set_shader_parameter("paint", color)

## A sticker slot as a transform: origin at the slot centre, +Z the outward
## normal (so a quad in the XY plane faces out), +Y up on the body sides and
## toward the nose on the hood and sun strip.
static func slot_transform(center: Vector3, normal: Vector3) -> Transform3D:
	var n := normal.normalized()
	var up := Vector3.UP if absf(n.y) < 0.9 else Vector3.FORWARD
	var x := up.cross(n).normalized()
	var y := n.cross(x).normalized()
	return Transform3D(Basis(x, y, n), center)

## Tyre and rim for one corner, to parent under its physics Wheel node. The
## returned pivot is what the wheel moves (travel on y, spin on x); the mesh
## inside is scaled to the physics radius and slid to the design track.
## `hub` is the physics wheel position in car space.
static func build_wheel_visual(radius: float, hub: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "P1Wheel"
	var side := signf(hub.x) if hub.x != 0.0 else 1.0
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _get_wheel_mesh(hub.z > 0.0)
	mi.set_surface_override_material(0, _get_wheel_material())
	var k := radius / DESIGN_WHEEL_R
	mi.scale = Vector3(k, k, k)
	mi.position = Vector3(side * DESIGN_WHEEL_X - hub.x, 0.0, 0.0)
	if side < 0.0:
		mi.rotation.y = PI   # the design's right wheel, mirrored for the left
	pivot.add_child(mi)
	return pivot

## Triangle count of one car as drawn: body plus 4 wheels.
static func triangle_count() -> int:
	var n := 0
	var b := _get_body_mesh()
	for i in b.get_surface_count():
		n += b.surface_get_array_len(i) / 3
	for rear in [false, true]:
		n += 2 * _get_wheel_mesh(rear).surface_get_array_len(0) / 3
	return n

## Draw calls of one car: body surfaces, the door mirrors, plus one per wheel.
static func draw_call_count() -> int:
	return _get_body_mesh().get_surface_count() + 1 + 4

## Triangles in the two door mirror cups (on top of triangle_count()).
static func mirror_triangle_count() -> int:
	var mi := _build_mirrors()
	var n := (mi.mesh as ArrayMesh).surface_get_array_len(0) / 3
	mi.free()
	return n

## The two door mirrors as one mesh (one draw call): a cup open toward the
## driver, dark inside, paint outside (vertex alpha 0 = paint, like the body),
## on a stalk from the door. Body space, like the body mesh.
static func _build_mirrors() -> MeshInstance3D:
	var k := CockpitKit.new()
	var paint := Color(PAINT, 0.0)
	for h in MIRRORS:
		var pos: Vector3 = h.pos
		var basis := Basis(Vector3.UP, deg_to_rad(float(h.yaw)))
		k.cup(MIRROR_SIZE, pos, basis, paint, MIRROR_INSIDE, 0.035)
		var side := signf(pos.x)
		k.box(Vector3(0.12, 0.035, 0.05), Vector3(side * 0.90, pos.y - 0.015, pos.z), paint)
	var mi := k.instance(null, "Mirrors")
	return mi

# ---------- meshes ----------

static func _get_body_mesh() -> ArrayMesh:
	if _body_mesh == null:
		_body_mesh = _build_mesh(decode_points(Data.b64(Data.BODY_POS)), Marshalls.base64_to_raw(Data.b64(Data.BODY_MAT)), true)
	return _body_mesh

static func _get_wheel_mesh(rear: bool) -> ArrayMesh:
	var key := "rear" if rear else "front"
	if not _wheel_meshes.has(key):
		var w: Dictionary = Data.WHEELS[2 if rear else 0]   # FR / RR
		_wheel_meshes[key] = _build_mesh(decode_points(w.pos), Marshalls.base64_to_raw(w.mat), false)
	return _wheel_meshes[key]

static func decode_points(b64: String) -> PackedVector3Array:
	var raw := Marshalls.base64_to_raw(b64)
	var n := raw.size() / 6
	var out := PackedVector3Array()
	out.resize(n)
	for i in n:
		out[i] = Vector3(raw.decode_s16(i * 6), raw.decode_s16(i * 6 + 2), raw.decode_s16(i * 6 + 4)) * 0.001
	return out

static func _surface_of(mat: String) -> String:
	if mat in Data.EMISSIVE:
		return "glow"
	if mat in Data.GLASS:
		return "glass"
	return "body"

## One ArrayMesh from the packed triangles: surfaces "body", "glass", "glow"
## (whichever exist), flat normals, vertex colours in linear space with the
## alpha flag for tinted faces. The design's triangles are counter-clockwise
## seen from outside; Godot's front faces are clockwise, so each one is
## written a, c, b.
static func _build_mesh(tris: PackedVector3Array, mats: PackedByteArray, is_body: bool) -> ArrayMesh:
	var groups := {}
	var tint_mats: Array = PAINT_MATS if is_body else RIM_MATS
	for t in mats.size():
		var mname: String = Data.NAMES[mats[t]]
		var kind := _surface_of(mname)
		if not groups.has(kind):
			groups[kind] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
		var g: Array = groups[kind]
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		var col := Color(Data.COLORS[mname]).srgb_to_linear()
		col.a = 0.0 if mname in tint_mats else 1.0
		for p in [a, c, b]:
			g[0].append(p)
			g[1].append(n)
			g[2].append(col)
	var mesh := ArrayMesh.new()
	for kind in ["body", "glass", "glow"]:
		if not groups.has(kind):
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = groups[kind][0]
		arrays[Mesh.ARRAY_NORMAL] = groups[kind][1]
		arrays[Mesh.ARRAY_COLOR] = groups[kind][2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var idx := mesh.get_surface_count() - 1
		mesh.surface_set_name(idx, kind)
		match kind:
			"glass":
				mesh.surface_set_material(idx, _get_glass_material())
			"glow":
				mesh.surface_set_material(idx, _get_glow_material())
			_:
				mesh.surface_set_material(idx, _new_paint_material(PAINT))
	return mesh

## Centres of the head and tail lamp faces, left and right, from the glow
## surface (for the effects that need to know where the lights are).
static func _lamp_centres() -> Dictionary:
	var tris := decode_points(Data.b64(Data.BODY_POS))
	var mats := Marshalls.base64_to_raw(Data.b64(Data.BODY_MAT))
	var acc := {"head": [Vector3.ZERO, Vector3.ZERO, 0, 0], "tail": [Vector3.ZERO, Vector3.ZERO, 0, 0]}
	for t in mats.size():
		var mname: String = Data.NAMES[mats[t]]
		if not acc.has(mname):
			continue
		var c := (tris[t * 3] + tris[t * 3 + 1] + tris[t * 3 + 2]) / 3.0
		var side := 0 if c.x < 0.0 else 1
		acc[mname][side] += c
		acc[mname][2 + side] += 1
	var out := {}
	for k in acc:
		var a: Array = acc[k]
		out[k] = [a[0] / maxi(a[2], 1), a[1] / maxi(a[3], 1)]
	return out

# ---------- materials ----------

static func _new_paint_material(paint: Color) -> ShaderMaterial:
	if _body_shader == null:
		_body_shader = Shader.new()
		_body_shader.code = BODY_SHADER
	var m := ShaderMaterial.new()
	m.shader = _body_shader
	m.set_shader_parameter("paint", paint)
	return m

static func _get_wheel_material() -> ShaderMaterial:
	if _wheel_mat == null:
		_wheel_mat = _new_paint_material(Color(Data.COLORS.rim))
		_wheel_mat.set_shader_parameter("paint_metallic", 0.8)
		_wheel_mat.set_shader_parameter("paint_roughness", 0.3)
	return _wheel_mat

static func _get_glass_material() -> StandardMaterial3D:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		# See-through (cockpit milestone 2): the driver and cabin show through
		# the windows in the chase view. Dark tint, so the outside look holds.
		_glass_mat.albedo_color = Color(Color(Data.COLORS.glass), 0.5)
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mat.metallic = 0.6
		_glass_mat.roughness = 0.08
	return _glass_mat

static func _get_glow_material() -> ShaderMaterial:
	if _glow_mat == null:
		_glow_shader = Shader.new()
		_glow_shader.code = GLOW_SHADER
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = _glow_shader
		_glow_mat.set_shader_parameter("energy", GLOW_ENERGY)
	return _glow_mat
