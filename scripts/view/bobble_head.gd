extends Node3D
class_name BobbleHead

# The dash bobble head (interiors build step 10, 2026-10-11; Roy 957, 959,
# 974). One figure stands on the passenger-side dash top (CabinSpots
# "dash_pass"), more than 20 degrees right of straight ahead and never in front
# of the driver. A child of the CockpitFrame, car space, visual only.
#
# Look: about 7 cm tall, a big head on a spring neck over a small body and a
# round base, a painted simple face. Flat shaded vertex colours (ROADMAP
# palette), well under 300 triangles. ONE mesh, ONE draw call: the head and
# the neck carry a weight and the neck's height in the mesh (UV.x, UV.y), and
# the shader tilts each vertex about the neck point by that weight times the
# bob.
#
# Motion: one damped spring for the whole car, on the CPU, a handful of
# multiplies a frame. The car's acceleration (the same velocity difference and
# low-pass the mirror trinket uses) leans the head the way a loose head lags:
# a corner throws it outward, braking pitches it forward, a launch pins it
# back. Bumps (vertical acceleration) nod it. The two angles go to the shader
# as one number pair. No sound.
#
# Built only while the cockpit view is on (CockpitFrame.set_cockpit calls
# set_active); outside it the mesh is freed and nothing updates. Garage and
# photo views will call set_active too, once those exist. The pick is
# CabinMods.bobble_for(car kind), changed from the pause menu's Settings.

const NONE := BobbleFigures.NONE
const IDS := BobbleFigures.IDS

# ---- figure dimensions (m), figure space: y = 0 at the base's underside ----
const BASE_R := 0.019
const BASE_H := 0.006
const BODY_Y0 := 0.006
const BODY_Y1 := 0.030
const NECK_Y0 := 0.030      # the pivot the shader tilts about
const NECK_Y1 := 0.038
const NECK_R := 0.0042
const HEAD_R := 0.0165
const HEAD_C := Vector3(0.0, 0.0545, 0.0)
## Standing height without the accessories (base to crown).
const HEIGHT := 0.071

# ---- motion ----
## Spring rate (Hz) and damping ratio: a lively bobble that rings ~1.5 s.
const SPRING_HZ := 2.8
const ZETA := 0.10
## Tilt (rad) per m/s^2 of the car's acceleration, and per m/s^2 of bump.
const LEAN_GAIN := 0.075
const NOD_GAIN := 0.03
## The most the head leans (rad, ~30 degrees).
const TILT_MAX := 0.55
## Low-pass time constant on the car's acceleration (s) and its cap (m/s^2).
const ACCEL_TAU := 0.04
const ACCEL_CAP := 30.0
const GRAVITY := 9.81

const BOB_SHADER := """
shader_type spatial;
// bob.x leans the head toward the car's +x (rad), bob.y toward +z. UV.x is how
// much of that a vertex takes (0 base and body, 1 head); UV.y is the neck
// pivot height. One draw call for the whole figure.
uniform vec2 bob = vec2(0.0);
void vertex() {
	float w = UV.x;
	vec3 p = VERTEX - vec3(0.0, UV.y, 0.0);
	vec3 n = NORMAL;
	float s = bob.x * w;
	float f = bob.y * w;
	float cs = cos(s);
	float ss = sin(s);
	float cf = cos(f);
	float sf = sin(f);
	p = vec3(p.x * cs + p.y * ss, -p.x * ss + p.y * cs, p.z);
	p = vec3(p.x, p.y * cf - p.z * sf, p.z * cf + p.y * sf);
	n = vec3(n.x * cs + n.y * ss, -n.x * ss + n.y * cs, n.z);
	n = vec3(n.x, n.y * cf - n.z * sf, n.z * cf + n.y * sf);
	VERTEX = p + vec3(0.0, UV.y, 0.0);
	NORMAL = n;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.6;
	SPECULAR = 0.1;
}
"""
static var _shader: Shader

var player: Node3D            # the PlayerCar
var kind := ""                # the car's chassis kind (CabinSpots, CabinMods)
## The lean cap (rad): TILT_MAX, or less where the head would reach the glass (CabinSpots bobble "tilt").
var tilt_max := TILT_MAX
var figure := NONE            # the id currently built
## The spring's output: x leans toward +x, y toward +z (rad). The shader's pair.
var bob := Vector2.ZERO
var bob_rate := Vector2.ZERO
var accel_local := Vector3.ZERO   # filtered car acceleration, car space

var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _tris := 0
var _active := false
var _last_vel := Vector3.ZERO
var _have_vel := false

func _init(car: Node3D = null, car_kind: String = "") -> void:
	player = car
	kind = car_kind
	name = "Bobble"
	position = CabinSpots.dash_pass(kind) if kind != "" else CabinSpots.dash_pass(CabinSpots.DEFAULT_KIND)
	scale = Vector3.ONE * CabinSpots.dash_pass_scale(kind if kind != "" else CabinSpots.DEFAULT_KIND)
	tilt_max = minf(TILT_MAX, float(CabinSpots.bobble_fit(kind).get("tilt", TILT_MAX)))
	set_physics_process(false)

func _ready() -> void:
	var p := get_parent()
	if p != null and bool(p.get("cockpit")):
		set_active(true)

## True while the figure is built and updating (cockpit view).
func is_active() -> bool:
	return _active

## Cockpit view on: build the picked figure and start the spring. Off: free the
## mesh and stop; the spring restarts at rest next time.
func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	set_physics_process(on)
	if on:
		set_figure(CabinMods.bobble_for(kind))
	else:
		set_figure(NONE)
		bob = Vector2.ZERO
		bob_rate = Vector2.ZERO
		accel_local = Vector3.ZERO
		_have_vel = false

func triangle_count() -> int:
	return _tris

func is_shown() -> bool:
	return _mesh != null

## The figure's mesh, null while nothing stands there (tests).
func mesh_instance() -> MeshInstance3D:
	return _mesh

## Builds the figure (an unknown id counts as "none"). Cheap; called when the
## pick changes or the cockpit comes on, never per frame.
func set_figure(id: String) -> void:
	if not BobbleFigures.FIGURES.has(id):
		id = NONE
	figure = id
	if _mesh != null:
		remove_child(_mesh)
		_mesh.free()
		_mesh = null
		_mat = null
	_tris = 0
	if id == NONE:
		return
	var spec: Dictionary = BobbleFigures.FIGURES[id]
	var body := CockpitKit.new()
	var neck := CockpitKit.new()
	var head := CockpitKit.new()
	_build_base_and_body(body, spec)
	neck.cylinder(NECK_R, NECK_Y0, NECK_Y1, Vector3.ZERO, BobbleFigures.SILVER, 6)
	_build_head(head, id, spec)
	call("_fig_" + id, body, head, spec)
	var mi := MeshInstance3D.new()
	mi.name = "Figure"
	mi.mesh = _assemble(body, neck, head)
	_tris = body.tri_count() + neck.tri_count() + head.tri_count()
	if _shader == null:
		_shader = Shader.new()
		_shader.code = BOB_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("bob", bob)
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = CockpitFrame.INTERIOR_BIT
	mi.extra_cull_margin = 0.05   # the shader moves the head outside the mesh's box
	_mesh = mi
	add_child(mi)

# ---------- mesh assembly ----------

## One ArrayMesh from the three kits, with UV = (tilt weight, neck pivot y):
## body 0, neck rising 0 -> 1 up its length, head 1.
func _assemble(body: CockpitKit, neck: CockpitKit, head: CockpitKit) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var parts := [[body, 0], [neck, 1], [head, 2]]
	for part in parts:
		var kit: CockpitKit = part[0]
		if kit.is_empty():
			continue
		var arr := kit.commit().surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		verts.append_array(v)
		normals.append_array(arr[Mesh.ARRAY_NORMAL])
		colors.append_array(arr[Mesh.ARRAY_COLOR])
		for p in v:
			var w := 0.0
			if part[1] == 2:
				w = 1.0
			elif part[1] == 1:
				w = clampf((p.y - NECK_Y0) / (NECK_Y1 - NECK_Y0), 0.0, 1.0)
			uvs.append(Vector2(w, NECK_Y0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# ---------- shape helpers (faces toward +z, the driver) ----------

## A faceted ellipsoid: `segs` around, `rings` bands, flat shaded.
static func _sphere(k: CockpitKit, c: Vector3, r: float, col: Color, scale := Vector3.ONE, segs := 8, rings := 5) -> void:
	var levels: Array = []
	for ri in range(1, rings):
		var th := PI * float(ri) / rings
		var ring := []
		for i in segs:
			var a := TAU * float(i) / segs
			ring.append(c + Vector3(cos(a) * sin(th) * r * scale.x, cos(th) * r * scale.y, sin(a) * sin(th) * r * scale.z))
		levels.append(ring)
	var top := c + Vector3(0.0, r * scale.y, 0.0)
	var bot := c - Vector3(0.0, r * scale.y, 0.0)
	var first: Array = levels[0]
	var last: Array = levels[levels.size() - 1]
	for i in segs:
		var j := (i + 1) % segs
		k.tri(top, first[j], first[i], col)
		k.tri(bot, last[i], last[j], col)
	for li in range(levels.size() - 1):
		var up: Array = levels[li]
		var lo: Array = levels[li + 1]
		for i in segs:
			var j := (i + 1) % segs
			k.quad(lo[i], up[i], up[j], lo[j], col)

## A closed truncated cone along +y from y0 (radius r0) to y0 + h (radius r1).
static func _frustum(k: CockpitKit, c: Vector3, r0: float, r1: float, h: float, col: Color, sides := 6) -> void:
	var bot := []
	var top := []
	for i in sides:
		var a := TAU * float(i) / sides
		var d := Vector3(cos(a), 0.0, sin(a))
		bot.append(c + d * r0)
		top.append(c + d * r1 + Vector3(0.0, h, 0.0))
	for i in sides:
		var j := (i + 1) % sides
		k.quad(bot[i], top[i], top[j], bot[j], col)
	for i in range(1, sides - 1):
		k.tri(top[0], top[i + 1], top[i], col)
		k.tri(bot[0], bot[i], bot[i + 1], col)

func _build_base_and_body(k: CockpitKit, spec: Dictionary) -> void:
	var body_col: Color = spec.body
	k.cylinder(BASE_R, 0.0, BASE_H, Vector3.ZERO, BobbleFigures.INK, 8)
	k.box(Vector3(0.022, BODY_Y1 - BODY_Y0, 0.016), Vector3(0.0, (BODY_Y0 + BODY_Y1) * 0.5, 0.0), body_col)
	for side in [-1.0, 1.0]:
		k.box(Vector3(0.005, 0.016, 0.006), Vector3(side * 0.0135, 0.020, 0.0), body_col)

func _build_head(k: CockpitKit, id: String, spec: Dictionary) -> void:
	var skin: Color = spec.head
	match id:
		"cone_face":
			# a traffic cone: orange, a bone band, the face on the front
			_frustum(k, Vector3(0.0, 0.036, 0.0), 0.0195, 0.014, 0.012, skin)
			_frustum(k, Vector3(0.0, 0.048, 0.0), 0.014, 0.0095, 0.008, BobbleFigures.BONE)
			_frustum(k, Vector3(0.0, 0.056, 0.0), 0.0095, 0.0035, 0.016, skin)
			_face(k, Vector3(0.0, 0.0425, 0.0), 0.0155)
		"pike":
			# a fish head: long snout, eye on each side, no painted face
			_sphere(k, HEAD_C, HEAD_R, skin, Vector3(0.78, 0.92, 1.25))
		_:
			_sphere(k, HEAD_C, HEAD_R, skin)
			_face(k, HEAD_C, 0.0153)

## Painted face: two eyes and a mouth on the +z side of a head centred at c;
## `front` is the surface's z from the centre at eye height.
func _face(k: CockpitKit, c: Vector3, front: float) -> void:
	for side in [-1.0, 1.0]:
		k.box(Vector3(0.0038, 0.0048, 0.003), c + Vector3(side * 0.0055, 0.003, front + 0.0004), BobbleFigures.INK)
	k.box(Vector3(0.008, 0.0024, 0.003), c + Vector3(0.0, -0.0062, front + 0.0002), BobbleFigures.INK)

# ---------- figures: accessories on top of the shared base / body / head ----------

func _fig_kasumi_driver(_body: CockpitKit, head: CockpitKit, spec: Dictionary) -> void:
	head.box(Vector3(0.030, 0.008, 0.030), HEAD_C + Vector3(0.0, 0.0125, -0.001), BobbleFigures.INK)        # black hair
	head.box(Vector3(0.036, 0.005, 0.036), HEAD_C + Vector3(0.0, 0.0045, 0.0), spec.accent)                 # headband
	head.box(Vector3(0.008, 0.012, 0.006), HEAD_C + Vector3(0.0, 0.006, -0.0195), spec.accent)              # knot and tails

func _fig_diesel_trucker(_body: CockpitKit, head: CockpitKit, spec: Dictionary) -> void:
	head.cylinder(0.0175, 0.008, 0.017, HEAD_C, spec.accent, 8)                                             # cap
	head.box(Vector3(0.026, 0.002, 0.014), HEAD_C + Vector3(0.0, 0.009, 0.0185), spec.accent)               # brim
	head.box(Vector3(0.020, 0.004, 0.004), HEAD_C + Vector3(0.0, -0.0035, 0.0163), BobbleFigures.INK)       # moustache

func _fig_gruppe9_driver(body: CockpitKit, head: CockpitKit, spec: Dictionary) -> void:
	head.box(Vector3(0.034, 0.007, 0.034), HEAD_C + Vector3(0.0, 0.0125, 0.0), spec.accent)                 # flat cap
	head.box(Vector3(0.028, 0.002, 0.012), HEAD_C + Vector3(0.0, 0.0105, 0.0205), spec.accent)              # peak
	for side in [-1.0, 1.0]:
		body.box(Vector3(0.0065, 0.007, 0.0075), Vector3(side * 0.0135, 0.0135, 0.0), BobbleFigures.INK)    # driving gloves

func _fig_ironbridge_welder(body: CockpitKit, head: CockpitKit, spec: Dictionary) -> void:
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-24.0))
	head.box(Vector3(0.036, 0.018, 0.005), HEAD_C + Vector3(0.0, 0.0165, 0.006), spec.accent, tilt)         # mask pushed up
	head.box(Vector3(0.026, 0.005, 0.0055), HEAD_C + Vector3(0.0, 0.0165, 0.0095), BobbleFigures.AMBER, tilt)   # lens
	body.box(Vector3(0.012, 0.010, 0.002), Vector3(0.0, 0.017, 0.0085), BobbleFigures.RUST)                 # leather apron

func _fig_rally_codriver(body: CockpitKit, head: CockpitKit, spec: Dictionary) -> void:
	head.box(Vector3(0.036, 0.017, 0.036), HEAD_C + Vector3(0.0, 0.0105, 0.0), spec.accent)                 # helmet
	head.box(Vector3(0.037, 0.004, 0.037), HEAD_C + Vector3(0.0, 0.0105, 0.0), BobbleFigures.SODIUM)        # stripe
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-15.0))
	body.box(Vector3(0.016, 0.020, 0.003), Vector3(0.0, 0.019, 0.0105), BobbleFigures.BONE, tilt)           # pace-note book
	body.box(Vector3(0.012, 0.002, 0.0035), Vector3(0.0, 0.021, 0.0107), BobbleFigures.INK, tilt)           # a line of notes

func _fig_topspeed_king(body: CockpitKit, head: CockpitKit, spec: Dictionary) -> void:
	head.box(Vector3(0.036, 0.006, 0.036), HEAD_C + Vector3(0.0, 0.0065, 0.0), BobbleFigures.INK)           # goggle strap
	var face := Basis(Vector3.RIGHT, deg_to_rad(90.0))
	body.cylinder(0.0085, 0.0, 0.0035, Vector3(0.0, 0.018, 0.0095), BobbleFigures.SILVER, 8, face)          # tiny speedometer
	body.box(Vector3(0.0018, 0.0075, 0.002), Vector3(0.0015, 0.0205, 0.0132), spec.accent, Basis(Vector3.BACK, deg_to_rad(-35.0)))   # needle

func _fig_eurosedan_king(body: CockpitKit, head: CockpitKit, spec: Dictionary) -> void:
	head.box(Vector3(0.028, 0.005, 0.0035), HEAD_C + Vector3(0.0, 0.003, 0.0162), BobbleFigures.INK)        # sunglasses
	head.box(Vector3(0.030, 0.007, 0.030), HEAD_C + Vector3(0.0, 0.0125, -0.001), BobbleFigures.INK)        # slicked hair
	body.box(Vector3(0.004, 0.016, 0.002), Vector3(0.0, 0.019, 0.0085), spec.accent)                        # tie

func _fig_muscle_king(body: CockpitKit, head: CockpitKit, spec: Dictionary) -> void:
	head.box(Vector3(0.026, 0.009, 0.022), HEAD_C + Vector3(0.0, 0.0145, 0.002), BobbleFigures.INK)         # greaser quiff
	head.box(Vector3(0.022, 0.008, 0.010), HEAD_C + Vector3(0.0, 0.0165, 0.0135), BobbleFigures.INK, Basis(Vector3.RIGHT, deg_to_rad(-25.0)))
	body.box(Vector3(0.0235, 0.004, 0.0175), Vector3(0.0, 0.0145, 0.0), spec.accent)                        # belt

func _fig_pike(body: CockpitKit, head: CockpitKit, spec: Dictionary) -> void:
	head.box(Vector3(0.010, 0.006, 0.012), HEAD_C + Vector3(0.0, -0.004, 0.0215), spec.head)                # snout
	head.box(Vector3(0.0035, 0.012, 0.016), HEAD_C + Vector3(0.0, 0.0175, -0.002), spec.accent)             # dorsal fin
	for side in [-1.0, 1.0]:
		head.box(Vector3(0.003, 0.0065, 0.0065), HEAD_C + Vector3(side * 0.0125, 0.003, 0.008), BobbleFigures.BONE)   # eye
		head.box(Vector3(0.0032, 0.003, 0.003), HEAD_C + Vector3(side * 0.0142, 0.003, 0.0088), BobbleFigures.INK)     # pupil
	body.box(Vector3(0.004, 0.016, 0.002), Vector3(0.0, 0.019, 0.0085), spec.accent)                        # tie

func _fig_dog(_body: CockpitKit, head: CockpitKit, _spec: Dictionary) -> void:
	for side in [-1.0, 1.0]:
		head.box(Vector3(0.006, 0.015, 0.009), HEAD_C + Vector3(side * 0.0170, 0.0, -0.002), Color("#6B4423"))   # floppy ears
	head.box(Vector3(0.012, 0.008, 0.009), HEAD_C + Vector3(0.0, -0.0045, 0.0170), BobbleFigures.BONE)      # snout
	head.box(Vector3(0.0045, 0.003, 0.003), HEAD_C + Vector3(0.0, -0.0015, 0.0222), BobbleFigures.INK)      # nose

func _fig_walt(body: CockpitKit, head: CockpitKit, spec: Dictionary) -> void:
	for side in [-1.0, 1.0]:
		head.box(Vector3(0.005, 0.009, 0.010), HEAD_C + Vector3(side * 0.0160, 0.004, -0.002), spec.accent)     # grey side hair
		head.box(Vector3(0.0095, 0.0075, 0.0025), HEAD_C + Vector3(side * 0.0058, 0.003, 0.0172), BobbleFigures.INK)   # glasses
	head.box(Vector3(0.004, 0.0015, 0.0025), HEAD_C + Vector3(0.0, 0.0045, 0.0172), BobbleFigures.INK)      # bridge
	body.box(Vector3(0.014, 0.012, 0.002), Vector3(0.0, 0.019, 0.0085), spec.body.darkened(0.25))           # overalls bib

func _fig_dave(_body: CockpitKit, head: CockpitKit, spec: Dictionary) -> void:
	head.box(Vector3(0.036, 0.004, 0.006), HEAD_C + Vector3(0.0, 0.0155, 0.0), spec.accent)                 # headband
	for side in [-1.0, 1.0]:
		head.box(Vector3(0.004, 0.017, 0.006), HEAD_C + Vector3(side * 0.0172, 0.007, 0.0), spec.accent)    # band down the side
		head.box(Vector3(0.008, 0.014, 0.014), HEAD_C + Vector3(side * 0.0195, -0.0005, 0.0), BobbleFigures.SODIUM)   # ear cups
	head.box(Vector3(0.010, 0.003, 0.0025), HEAD_C + Vector3(0.0, 0.0072, 0.0166), spec.accent)             # tired lids

func _fig_cone_face(_body: CockpitKit, _head: CockpitKit, _spec: Dictionary) -> void:
	pass   # the head is the cone; nothing more to add

func _fig_hula(body: CockpitKit, head: CockpitKit, spec: Dictionary) -> void:
	_frustum(body, Vector3(0.0, BODY_Y0, 0.0), 0.0205, 0.0125, 0.017, spec.accent, 6)                       # grass skirt
	head.box(Vector3(0.032, 0.012, 0.030), HEAD_C + Vector3(0.0, 0.0105, -0.002), BobbleFigures.INK)        # black hair
	head.box(Vector3(0.007, 0.007, 0.004), HEAD_C + Vector3(0.0125, 0.010, 0.012), BobbleFigures.SODIUM)    # flower

func _fig_cat(body: CockpitKit, head: CockpitKit, spec: Dictionary) -> void:
	for side in [-1.0, 1.0]:
		var turn := Basis(Vector3.BACK, deg_to_rad(side * 45.0))
		head.box(Vector3(0.0095, 0.0095, 0.004), HEAD_C + Vector3(side * 0.0098, 0.0152, 0.0), spec.head, turn)    # ears
	head.box(Vector3(0.0045, 0.003, 0.003), HEAD_C + Vector3(0.0, -0.0022, 0.0162), spec.accent)            # nose
	head.box(Vector3(0.036, 0.0015, 0.0015), HEAD_C + Vector3(0.0, -0.0035, 0.0150), BobbleFigures.BONE)    # whiskers
	body.box(Vector3(0.004, 0.020, 0.004), Vector3(0.0105, 0.017, -0.0105), spec.head, Basis(Vector3.BACK, deg_to_rad(-20.0)))   # tail

func _fig_skeleton(body: CockpitKit, head: CockpitKit, spec: Dictionary) -> void:
	head.box(Vector3(0.016, 0.005, 0.012), HEAD_C + Vector3(0.0, -0.0150, 0.0035), BobbleFigures.BONE)      # jaw
	head.box(Vector3(0.010, 0.0022, 0.003), HEAD_C + Vector3(0.0, -0.0128, 0.0100), spec.accent)            # teeth line
	for i in 3:
		body.box(Vector3(0.019, 0.0022, 0.0015), Vector3(0.0, 0.0105 + 0.0065 * i, 0.0082), spec.accent)    # ribs

func _fig_tiny_mechanic(body: CockpitKit, head: CockpitKit, spec: Dictionary) -> void:
	head.cylinder(0.0172, 0.007, 0.0150, HEAD_C, BobbleFigures.NAVY, 8)                                     # cap
	head.box(Vector3(0.024, 0.002, 0.012), HEAD_C + Vector3(0.0, 0.0085, 0.0185), BobbleFigures.NAVY)       # peak
	body.box(Vector3(0.0032, 0.022, 0.0032), Vector3(0.0165, 0.025, 0.0045), spec.accent, Basis(Vector3.BACK, deg_to_rad(-12.0)))   # wrench shaft
	body.box(Vector3(0.0085, 0.0040, 0.0032), Vector3(0.0188, 0.0365, 0.0045), spec.accent)                 # wrench jaw

# ---------- motion ----------

func _physics_process(delta: float) -> void:
	var want := CabinMods.bobble_for(kind)
	if want != figure:
		set_figure(want)
	if _mesh == null or player == null or delta <= 0.0:
		return
	var v := _velocity_of(player)
	if not _have_vel:
		_last_vel = v
		_have_vel = true
	var basis_inv := player.global_transform.basis.orthonormalized().inverse()
	var a := basis_inv * ((v - _last_vel) / delta)
	_last_vel = v
	a = a.limit_length(ACCEL_CAP)
	accel_local = accel_local.lerp(a, 1.0 - exp(-delta / ACCEL_TAU))
	step(delta, accel_local)

## One spring step. `accel` is the car's acceleration in car space (its y is
## the bump signal). Public so a test can drive it without a car. The head
## leans away from the acceleration (it lags); a jolt up nods it forward.
func step(delta: float, accel: Vector3) -> void:
	var target := Vector2(
		-accel.x * LEAN_GAIN,
		-accel.z * LEAN_GAIN - accel.y * NOD_GAIN)
	target = target.limit_length(tilt_max)
	var w := TAU * SPRING_HZ
	bob_rate += ((target - bob) * (w * w) - bob_rate * (2.0 * ZETA * w)) * delta
	bob += bob_rate * delta
	bob = bob.limit_length(tilt_max)
	if _mat != null:
		_mat.set_shader_parameter("bob", bob)

static func _velocity_of(body: Node3D) -> Vector3:
	var v: Variant = body.get("linear_velocity")
	return v if v is Vector3 else Vector3.ZERO
