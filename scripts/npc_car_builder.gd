extends RefCounted
class_name NpcCarBuilder

# The traffic cars (stage B step 5): N1 commuter sedan, N2 city hatchback,
# N3 pickup. Like P1CoupeBuilder, each body is the design proxy from
# docs/design/fleet/sheets/<id>.png, exported by tools/fleet_design/game_export.py
# into scripts/<id>_data.gd, so what drives in traffic is exactly what the sheet
# shows, from every angle. Unlike the player's car, each one ships all of its
# sheet builds (stock plus two variants, e.g. the N1 taxi) and traffic picks one
# per car.
#
# Built for many copies on screen at once (draw calls are the limit, see
# docs/design/fleet/README.md "Budget plan"):
#   Body     one MeshInstance3D per car, all cars of a build share ONE mesh
#            and ONE set of materials: body (vertex colours; the paint is an
#            instance uniform, so every colour is the same material), dark
#            glass (opaque: nothing to sort), lights (glow)
#   wheels   one shared mesh per axle and build, drawn 4 times
# 3 + 4 = 7 draw calls a car, against ~18 for the old box traffic car.
#
# Physics: the wheels sit exactly where the sheet draws them (KINDS wheel_r,
# wheel_x, axle_z = fleet.json physics_hint), so nothing is slid or scaled.
# Every car runs the same raycast sim as the player; only its CarSpec dict
# differs (CarSpec.npc_spec).
#
# Adding a car: export its data file, add a KINDS entry and a CarSpec.npc_spec
# branch. Nothing else in traffic changes.

const KINDS := {
	"n1_commuter": {
		"data": preload("res://scripts/n1_commuter_data.gd"),
		# fleet.json dims and physics_hint
		"length": 4.80, "width": 1.82, "height": 1.51, "clearance": 0.16,
		"front_overhang": 0.98, "rear_overhang": 1.02,
		"wheel_r": 0.31, "wheel_x": 0.78, "axle_z": 1.40,
		## Chassis origin height settled on the springs, flat road (negative:
		## the origin is on the ground with the springs fully extended).
		## Measured by tests/npc_cars.gd. The body is drawn -rest_y higher so
		## the car stands at the sheet's ride height at rest (P1CoupeBuilder
		## BODY_LIFT, same reason).
		"rest_y": -0.121,
		"builds": {"stock": 60, "sport": 25, "taxi": 15},
		## Builds with a fixed paint instead of a random traffic neutral.
		"build_paint": {"taxi": Color("#F2B53A")},
	},
	"n2_cityhatch": {
		"data": preload("res://scripts/n2_cityhatch_data.gd"),
		"length": 3.95, "width": 1.69, "height": 1.53, "clearance": 0.15,
		"front_overhang": 0.80, "rear_overhang": 0.62,
		"wheel_r": 0.295, "wheel_x": 0.73, "axle_z": 1.265,
		"rest_y": -0.12,
		"builds": {"stock": 55, "sport": 25, "rack": 20},
		"build_paint": {},
	},
	"n3_pickup": {
		"data": preload("res://scripts/n3_pickup_data.gd"),
		"length": 5.30, "width": 1.86, "height": 1.86, "clearance": 0.30,
		"front_overhang": 0.92, "rear_overhang": 1.30,
		"wheel_r": 0.39, "wheel_x": 0.79, "axle_z": 1.54,
		"rest_y": -0.12,
		"builds": {"stock": 50, "covered": 30, "sportsbar": 20},
		"build_paint": {},
	},
}

## fleet.json traffic_paints (weights), without Taxi amber: that one is the
## taxi's own colour, so an amber car always reads as a taxi.
const PAINTS := [
	[Color("#C9CED6"), 22], [Color("#E9E6DF"), 18], [Color("#15171C"), 16],
	[Color("#4A505B"), 14], [Color("#26314D"), 8], [Color("#B9AE98"), 7],
	[Color("#8E2A28"), 6], [Color("#2B4A3A"), 5],
]

const GLOW_ENERGY := 2.5
const PAINT_MATS := ["paint", "roof"]
const RIM_MATS := ["rim", "rim_face"]

## Same look as P1CoupeBuilder.BODY_SHADER, with the paint per instance.
const BODY_SHADER := """
shader_type spatial;
render_mode cull_back;
// Vertex alpha 0 marks paint (or rim) faces; they take the tint and a glossier finish.
instance uniform vec3 paint : source_color = vec3(0.79, 0.81, 0.84);
uniform float paint_metallic = 0.45;
uniform float paint_roughness = 0.45;
void fragment() {
	float p = 1.0 - COLOR.a;
	ALBEDO = mix(COLOR.rgb, paint, p);
	METALLIC = mix(0.1, paint_metallic, p);
	ROUGHNESS = mix(0.75, paint_roughness, p);
	SPECULAR = 0.5;
}
"""

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float energy = 2.5;
void fragment() {
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * energy;
}
"""

static var _body_meshes := {}   # "kind|build" -> ArrayMesh
static var _wheel_meshes := {}  # "kind|build|front/rear" -> ArrayMesh
static var _body_mat: ShaderMaterial
static var _wheel_mat: ShaderMaterial
static var _glass_mat: StandardMaterial3D
static var _glow_mat: ShaderMaterial

static func is_npc(kind: String) -> bool:
	return KINDS.has(kind)

## The keys TrafficCar reads from CarBuilder.KIND_CONFIGS (wheel_r, axle_z,
## wheel_x, main_w, hood_z0 = front tip z, main_z1 = rear tip z), plus this
## car's collision box and rest height.
static func config(kind: String) -> Dictionary:
	var k: Dictionary = KINDS[kind]
	var half_wb: float = k.axle_z
	var lift := -float(k.rest_y)
	# Collision box: the body's footprint, from just above the sheet's ground
	# clearance to most of its height, in chassis space at rest.
	var y0: float = lift + float(k.clearance) + 0.02
	var y1: float = lift + float(k.height) * 0.9
	return {
		"wheel_r": k.wheel_r, "axle_z": k.axle_z, "wheel_x": k.wheel_x,
		"main_w": k.width,
		"hood_z0": -(float(k.front_overhang) + half_wb),
		"main_z1": float(k.rear_overhang) + half_wb,
		"rest_y": k.rest_y,
		"col_size": Vector3(float(k.width) * 0.96, y1 - y0, float(k.length) * 0.97),
		"col_y": (y0 + y1) / 2.0,
	}

static func builds(kind: String) -> Array:
	return (KINDS[kind].data.BUILDS as Dictionary).keys()

## A build by the KINDS weights.
static func pick_build(kind: String) -> String:
	var w: Dictionary = KINDS[kind].builds
	var total := 0
	for b in w:
		total += int(w[b])
	var r := randi() % total
	for b in w:
		r -= int(w[b])
		if r < 0:
			return b
	return "stock"

## Paint for a car of this build: the build's own colour, or a weighted neutral.
static func pick_paint(kind: String, build: String) -> Color:
	var fixed: Dictionary = KINDS[kind].build_paint
	if fixed.has(build):
		return fixed[build]
	var total := 0
	for p in PAINTS:
		total += int(p[1])
	var r := randi() % total
	for p in PAINTS:
		r -= int(p[1])
		if r < 0:
			return p[0]
	return PAINTS[0][0]

## Body, glass and lights (no wheels: those hang under the physics wheels).
## Metas as P1CoupeBuilder's: "kind", "build", "half_w", "half_l",
## "exhaust_tips", "sticker_slots" (centre and normal; no markers, traffic
## has no stickers yet).
static func chassis_visual(kind: String, build: String, paint: Color) -> Node3D:
	var k: Dictionary = KINDS[kind]
	var b: Dictionary = k.data.BUILDS[build]
	var lift := Vector3(0.0, -float(k.rest_y), 0.0)
	var root := Node3D.new()
	root.name = "NpcBody"
	root.set_meta("kind", kind)
	root.set_meta("build", build)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.position = lift
	mi.mesh = body_mesh(kind, build)
	mi.set_instance_shader_parameter("paint", paint)
	root.add_child(mi)
	var tips := []
	for t in b.tips:
		tips.append({"pos": t.pos + lift, "dir": t.dir, "r": t.r})
	root.set_meta("exhaust_tips", tips)
	var slots := []
	for s in b.slots:
		for p in s.placements:
			slots.append({"id": s.id, "size": s.size, "center": p.center + lift, "normal": p.normal})
	root.set_meta("sticker_slots", slots)
	root.set_meta("half_w", float(k.width) / 2.0)
	root.set_meta("half_l", float(k.length) / 2.0)
	return root

## Tyre and rim for one corner, to parent under its physics Wheel (the pivot
## is what the wheel moves and spins). `hub` is the wheel's position in car
## space; the design's right-hand wheel is turned round for the left side.
static func wheel_visual(kind: String, build: String, hub: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "NpcWheel"
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = wheel_mesh(kind, build, hub.z > 0.0)
	if hub.x < 0.0:
		mi.rotation.y = PI
	pivot.add_child(mi)
	return pivot

## Triangles of one car as drawn (body plus 4 wheels).
static func triangle_count(kind: String, build: String) -> int:
	var n := 0
	var m := body_mesh(kind, build)
	for i in m.get_surface_count():
		n += m.surface_get_array_len(i) / 3
	for rear in [false, true]:
		n += 2 * wheel_mesh(kind, build, rear).surface_get_array_len(0) / 3
	return n

static func draw_call_count(kind: String, build: String) -> int:
	return body_mesh(kind, build).get_surface_count() + 4

# ---------- meshes ----------

static func body_mesh(kind: String, build: String) -> ArrayMesh:
	var key := "%s|%s" % [kind, build]
	if not _body_meshes.has(key):
		var data: GDScript = KINDS[kind].data
		var b: Dictionary = data.BUILDS[build]
		_body_meshes[key] = _build_mesh(data, P1CoupeBuilder.decode_points(data.b64(b.body_pos)),
			Marshalls.base64_to_raw(b.body_mat), true)
	return _body_meshes[key]

static func wheel_mesh(kind: String, build: String, rear: bool) -> ArrayMesh:
	var key := "%s|%s|%s" % [kind, build, "rear" if rear else "front"]
	if not _wheel_meshes.has(key):
		var data: GDScript = KINDS[kind].data
		var w: Dictionary = data.BUILDS[build].wheels[1 if rear else 0]
		_wheel_meshes[key] = _build_mesh(data, P1CoupeBuilder.decode_points(w.pos), Marshalls.base64_to_raw(w.mat), false)
	return _wheel_meshes[key]

## Same as P1CoupeBuilder._build_mesh: surfaces "body", "glass", "glow",
## flat normals, linear vertex colours with alpha 0 on tinted faces, each
## design triangle written a, c, b for Godot's clockwise front faces.
static func _build_mesh(data: GDScript, tris: PackedVector3Array, mats: PackedByteArray, is_body: bool) -> ArrayMesh:
	var groups := {}
	var tint_mats: Array = PAINT_MATS if is_body else RIM_MATS
	for t in mats.size():
		var mname: String = data.NAMES[mats[t]]
		var surf := "glow" if mname in data.EMISSIVE else ("glass" if mname in data.GLASS else "body")
		if not groups.has(surf):
			groups[surf] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
		var g: Array = groups[surf]
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		var col := Color(data.COLORS[mname]).srgb_to_linear()
		col.a = 0.0 if mname in tint_mats else 1.0
		for p in [a, c, b]:
			g[0].append(p)
			g[1].append(n)
			g[2].append(col)
	var mesh := ArrayMesh.new()
	for surf in ["body", "glass", "glow"]:
		if not groups.has(surf):
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = groups[surf][0]
		arrays[Mesh.ARRAY_NORMAL] = groups[surf][1]
		arrays[Mesh.ARRAY_COLOR] = groups[surf][2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var idx := mesh.get_surface_count() - 1
		mesh.surface_set_name(idx, surf)
		match surf:
			"glass":
				mesh.surface_set_material(idx, _get_glass_material())
			"glow":
				mesh.surface_set_material(idx, _get_glow_material())
			_:
				mesh.surface_set_material(idx, _get_body_material() if is_body else _get_wheel_material(data))
	return mesh

# ---------- materials (one of each for every traffic car) ----------

static func _get_body_material() -> ShaderMaterial:
	if _body_mat == null:
		var sh := Shader.new()
		sh.code = BODY_SHADER
		_body_mat = ShaderMaterial.new()
		_body_mat.shader = sh
	return _body_mat

## Wheels: the body shader with a plain uniform set to the rim colour, so the
## rim faces get the glossy finish without taking the car's paint. All three
## traffic cars share the same rim colour (proxies.json).
static func _get_wheel_material(data: GDScript) -> ShaderMaterial:
	if _wheel_mat == null:
		var sh := Shader.new()
		sh.code = BODY_SHADER.replace("instance uniform vec3 paint", "uniform vec3 paint")
		_wheel_mat = ShaderMaterial.new()
		_wheel_mat.shader = sh
		_wheel_mat.set_shader_parameter("paint", Color(data.COLORS.rim))
		_wheel_mat.set_shader_parameter("paint_metallic", 0.8)
		_wheel_mat.set_shader_parameter("paint_roughness", 0.3)
	return _wheel_mat

static func _get_glass_material() -> StandardMaterial3D:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.albedo_color = Color("#151D2E")
		_glass_mat.metallic = 0.6
		_glass_mat.roughness = 0.08
	return _glass_mat

static func _get_glow_material() -> ShaderMaterial:
	if _glow_mat == null:
		var sh := Shader.new()
		sh.code = GLOW_SHADER
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = sh
		_glow_mat.set_shader_parameter("energy", GLOW_ENERGY)
	return _glow_mat
