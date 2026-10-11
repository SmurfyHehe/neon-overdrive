extends RefCounted
class_name P1CoupeBuilder

# P1 sports coupe, the player's car (stage D step 1, Roy 2026-10-06: build the
# merged B1 design sheet as is, judge it in game). The shape is the design
# proxy from docs/design/fleet/sheets/p1_coupe.png, exported by
# tools/fleet_design/game_export.py into scripts/car/p1_coupe_data.gd, so what
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
#
# Cars from parts (pilot, 2026-10-10): when assets/cars/p1_coupe/body.glb is
# there the body is no longer the one-piece sheet proxy above but the same
# shape cut into real parts (hood, doors, fenders, bumpers, glass, lamps,
# mirrors...), merged by CarAssembler into one mesh with 4 surfaces (body,
# trim, glass, glow), so the draw calls stay at 9: the door mirrors are parts
# of that mesh now instead of a mesh of their own. NEON_COUPE_LEGACY=1 keeps
# the old proxy (before-shots, comparisons); NEON_CAR_PANELS=open builds it
# with the hood, doors and trunk open (+4 draw calls, for pictures).

const Data := preload("res://scripts/car/p1_coupe_data.gd")

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

## The paint shader is CarPaint's (one for every car); the name stays for
## the code that reads it.
static var BODY_SHADER: String:
	get: return CarPaint.code("body", CarPaint.tier())

## The plain paint shader the body assembled from parts (CarAssembler) wore
## until the look upgrade (2026-10-11). The body now wears CarPaint's
## "body_parts" variant (_new_parts_paint_material), which reads the same
## baked occlusion and shut lines from CUSTOM0; this stays for the tests and
## tools that read it.
const PARTS_BODY_SHADER := """
shader_type spatial;
render_mode cull_back;
// Vertex alpha 0 marks paint (or rim) faces; they take the tint and a glossier finish.
uniform vec3 paint : source_color = vec3(1.0, 0.54, 0.12);
uniform float paint_metallic = 0.5;
uniform float paint_roughness = 0.38;
// Road grime (car_dirt.gd): 0 clean .. 1 a full night's dirt. Thick on the sills,
// thin on the roof, blotchy from a hash of the object-space position, so it
// costs a few ALU ops per pixel and no texture (integrated graphics).
uniform float dirt : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dirt_color : source_color = vec3(0.40, 0.35, 0.28);
varying vec3 obj_pos;
varying vec3 obj_nrm;
float grime_hash(vec3 q) {
	return fract(sin(dot(q, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}
void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}
void fragment() {
	float p = 1.0 - COLOR.a;
	vec3 albedo = mix(COLOR.rgb, paint, p);
	float metallic = mix(0.1, paint_metallic, p);
	float roughness = mix(0.75, paint_roughness, p);
	float low = 1.0 - smoothstep(0.08, 1.0, obj_pos.y);           // sills first, roof last
	float side = 1.0 - 0.55 * max(obj_nrm.y, 0.0);                 // flat tops catch less
	float blotch = mix(grime_hash(floor(obj_pos * 11.0)), grime_hash(floor(obj_pos * 3.5) + 7.0), 0.5);
	float grime = clamp(dirt * (0.2 + 1.3 * low) * side * (0.35 + 0.65 * blotch), 0.0, 1.0);
	ALBEDO = mix(albedo, dirt_color, grime * 0.95);
	METALLIC = mix(metallic, 0.0, grime);
	ROUGHNESS = mix(roughness, 0.92, grime);
	SPECULAR = 0.5;
}
"""

## The lamps use NpcCarBuilder's glow shader (drawn from both sides: the lamp
## lenses are single quads laid on the body, and the design's left pop-up lens
## is wound the other way round, which backface culling would hide). It gives
## the coupe the same lamp channels as every car: brake, reverse, indicators.
static var _body_mesh: ArrayMesh
static var _wheel_meshes := {}
static var _glass_mat: ShaderMaterial
static var _wheel_mat: ShaderMaterial
## CarFittings' counts and points for this body (see NpcCarBuilder.fittings).
static var _fit_counts := {}
static var _fit_points := {}
static var _fit_frames := {}

## Body, glass, lights and the sticker slot markers -- no wheels, those hang
## under the physics wheel nodes (build_wheel_visual). Metas, read by CarFx
## and the effects: "kind", "body_mat" (ShaderMaterial, paint uniform),
## "half_w", "half_l", "exhaust_tips", "sticker_slots", "headlights", "tail_lights".
static func build_chassis_visual(paint: Color = PAINT) -> Node3D:
	var root := Node3D.new()
	root.name = "P1Coupe"
	root.set_meta("kind", KIND)

	var lift := Vector3(0.0, BODY_LIFT, 0.0)
	var paint_mat: ShaderMaterial
	var lamps: Dictionary
	if uses_parts():
		# the body from its parts: one mesh, 4 surfaces, door mirrors included
		paint_mat = _new_parts_paint_material(paint)
		var body := CarAssembler.build(KIND, parts_config(), paint_mat)
		body.position = lift
		body.set_instance_shader_parameter("finish", CarPaint.finish_for(KIND))
		var gi := CarAssembler.surface_index(body.mesh, "glass")
		if gi >= 0:
			body.set_surface_override_material(gi, _get_glass_material())
		root.add_child(body)
		lamps = CarAssembler.lamp_centres(KIND)
	else:
		var body := MeshInstance3D.new()
		body.name = "Body"
		body.position = lift
		var mesh := _get_body_mesh()
		body.mesh = mesh
		body.set_instance_shader_parameter("finish", CarPaint.finish_for(KIND))
		body.set_instance_shader_parameter("seams", mesh.get_meta("paint_seams", Vector4.ZERO))
		paint_mat = _new_paint_material(paint)
		for i in mesh.get_surface_count():
			if mesh.surface_get_name(i) == "body":
				body.set_surface_override_material(i, paint_mat)
		root.add_child(body)
		var mirrors := _build_mirrors()
		mirrors.position = lift
		mirrors.set_surface_override_material(0, paint_mat)   # same paint, recolours with the body
		root.add_child(mirrors)
		lamps = _lamp_centres()

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
	root.set_meta("headlights", [lamps.head[0] + lift, lamps.head[1] + lift])
	root.set_meta("tail_lights", [lamps.tail[0] + lift, lamps.tail[1] + lift])

	root.set_meta("body_mat", paint_mat)
	root.set_meta("half_w", WIDTH / 2.0)
	root.set_meta("half_l", LENGTH / 2.0)
	# Which small parts this body carries (CarSlots, tests/car/required_slots.gd).
	root.set_meta("fittings", _fit_counts)
	root.set_meta("fitting_points", _fit_points)
	root.set_meta("windscreen", _fit_frames.screen)
	root.set_meta("fuel_flap_site", _fit_frames.flap)
	# The real underside (car-parts plan, section 5b): one more draw call.
	Undercarriage.attach(root, undercarriage_params(), Undercarriage.ROLE_PLAYER)
	return root

## What the underside is built from, in car space (lift included). The
## ground at rest is BODY_LIFT above the chassis origin (see BODY_LIFT), the
## floor is the body's lowest point, the wheels are the sheet's.
static func undercarriage_params() -> Dictionary:
	var floor_y: float = _get_body_mesh().get_aabb().position.y + BODY_LIFT
	var tips := []
	for t in Data.EXHAUST_TIPS:
		tips.append({"pos": t.pos + Vector3(0.0, BODY_LIFT, 0.0), "dir": t.dir, "r": t.r})
	return Undercarriage.params(WIDTH / 2.0, LENGTH / 2.0, floor_y, BODY_LIFT,
		DESIGN_WHEEL_R, DESIGN_WHEEL_X, absf(Data.WHEELS[0].hub.z), tips, "rwd")

## True when the body is assembled from the parts glb (the default once the
## glb is in the project); NEON_COUPE_LEGACY=1 keeps the one-piece sheet proxy.
static func uses_parts() -> bool:
	return OS.get_environment("NEON_COUPE_LEGACY") != "1" and CarAssembler.has_car(KIND)

## What CarAssembler builds: the stock parts, panels closed. NEON_CAR_PANELS=open
## opens the hood, doors and trunk (pictures; nothing in the game opens them yet).
static func parts_config() -> Dictionary:
	return {"panels": "open"} if OS.get_environment("NEON_CAR_PANELS") == "open" else {}

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
	if uses_parts():
		n = CarAssembler.triangle_count(KIND)
	else:
		var b := _get_body_mesh()
		for i in b.get_surface_count():
			n += b.surface_get_array_len(i) / 3
	for rear in [false, true]:
		n += 2 * _get_wheel_mesh(rear).surface_get_array_len(0) / 3
	return n - fittings_triangle_count()

## Triangles CarFittings merged into the body (lenses and plates), on top of
## the design's TRIS_TOTAL. No extra draw call: they sit in the body's surfaces.
static func fittings_triangle_count() -> int:
	_get_body_mesh()
	return int(_fit_counts.get("tris", 0))

## Draw calls of one car: body surfaces, the door mirrors, the underside,
## plus one per wheel. From parts the mirrors are in the body mesh (its trim
## surface is the call they used to cost).
static func draw_call_count() -> int:
	if uses_parts():
		return CarAssembler.draw_call_count(KIND) + 1 + 4
	return _get_body_mesh().get_surface_count() + 1 + 1 + 4

## Triangles in the underside (on top of triangle_count()).
static func undercarriage_triangle_count() -> int:
	return Undercarriage.triangle_count(undercarriage_params(), Undercarriage.ROLE_PLAYER)

## Triangles in the two door mirror cups (on top of triangle_count()).
static func mirror_triangle_count() -> int:
	if uses_parts():
		return CarAssembler.triangle_count(KIND) - CarAssembler.triangle_count(KIND, {"mirror_l": false, "mirror_r": false})
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
## (whichever exist), built by CarPaint.build_groups (smooth normals, linear
## vertex colours with the alpha flag for tinted faces, the finish, shade and
## edge arrays the paint shader reads).
static func _build_mesh(tris: PackedVector3Array, mats: PackedByteArray, is_body: bool) -> ArrayMesh:
	var opts := {"is_wheel": not is_body}
	if is_body:
		var hubs := []
		for w in Data.WHEELS:
			hubs.append(w.hub)
		opts["wheels"] = hubs
		opts["wheel_r"] = DESIGN_WHEEL_R
	var groups := CarPaint.build_groups(Data, tris, mats, PAINT_MATS if is_body else RIM_MATS, opts)
	if is_body:
		# Reverse and third brake lenses, the indicators the sheet lacks and both
		# plates (CarFittings), merged into the body's own surfaces.
		var fit := CarFittings.build(KIND + "|" + Data.BUILD, tris, mats, Data.NAMES, Data.GLASS, Data.EMISSIVE, Data.COLORS)
		_fit_counts = fit.counts
		_fit_points = fit.points
		_fit_frames = {"screen": fit.get("screen", {}), "flap": fit.get("flap", {})}
		NpcCarBuilder._append_fittings(groups, fit)
	var mesh := ArrayMesh.new()
	for kind in ["body", "glass", "glow"]:
		if not groups.has(kind):
			continue
		var idx := CarPaint.add_surface(mesh, groups[kind], kind)
		match kind:
			"glass":
				mesh.surface_set_material(idx, _get_glass_material())
			"glow":
				mesh.surface_set_material(idx, _get_glow_material())
			_:
				mesh.surface_set_material(idx, _new_paint_material(PAINT))
	if is_body:
		mesh.set_meta("paint_seams", CarPaint.cut_seams(Data, tris, mats, 2))
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
	var m := ShaderMaterial.new()
	m.shader = CarPaint.body_shader(false)
	m.set_shader_parameter("paint", paint)
	return m

## The paint material for a body assembled from parts: the same shader and
## uniforms (paint, dirt, ...) with CarAssembler's two-line hook that darkens
## by the baked ambient occlusion and along the shut lines.
static func _new_parts_paint_material(paint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CarPaint.parts_body_shader()
	m.set_shader_parameter("paint", paint)
	return m

static func _get_wheel_material() -> ShaderMaterial:
	if _wheel_mat == null:
		_wheel_mat = _new_paint_material(Color(Data.COLORS.rim))
		_wheel_mat.set_shader_parameter("paint_metallic", 0.8)
		_wheel_mat.set_shader_parameter("paint_roughness", 0.3)
	return _wheel_mat

static func _get_glass_material() -> ShaderMaterial:
	if _glass_mat == null:
		# See-through (cockpit milestone 2): the driver and cabin show through
		# the windows in the chase view. Dark tint, so the outside look holds.
		_glass_mat = ShaderMaterial.new()
		_glass_mat.shader = CarPaint.glass_shader(true)
		_glass_mat.set_shader_parameter("glass", Color(Data.COLORS.glass))
		_glass_mat.set_shader_parameter("see", 0.5)
	return _glass_mat

static func _get_glow_material() -> ShaderMaterial:
	return NpcCarBuilder._get_glow_material()
