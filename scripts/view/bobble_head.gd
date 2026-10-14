extends Node3D
class_name BobbleHead

# The dash bobble head (interiors build step 10, 2026-10-11; Roy 957, 959,
# 974). One figure stands on the passenger-side dash top (CabinSpots
# "dash_pass"), more than 20 degrees right of straight ahead and never in front
# of the driver. A child of the CockpitFrame, car space, visual only.
#
# Look: about 7 cm tall, a big head on a spring neck over a small body and a
# round base, a painted simple face; 29 figures, each its own silhouette, prop
# and pose (BobbleFigures lists them, BobbleSculpt shapes them). Flat shaded
# vertex colours (ROADMAP palette), under 600 triangles. ONE mesh, ONE draw
# call: every vertex carries a bob weight and the pivot it turns about in the
# mesh (UV.x weight, UV.y pivot height, UV2 pivot x and z), and the shader
# tilts it by that weight times the bob. The standard figure is body 0, neck
# 0 -> 1, head 1 about the neck's foot; the hula dancer's spring is at her
# waist, the surfer's at his base, and a loose jaw, a waving paw or a wagging
# finger swing about their own hinges.
#
# Motion: one damped spring for the whole car, on the CPU, a handful of
# multiplies a frame; each figure sets the spring's rate, damping, gain and
# side-to-side share (BobbleFigures "spring"), so a tiki barely moves and the
# drinking bird tips slow and deep, at the same cost. The car's acceleration (the same velocity difference and
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
## The base's radius and the standing height of the standard person (base to
## crown); the shapes themselves are in BobbleSculpt. Tests use these.
const BASE_R := BobbleSculpt.BASE_R
const HEIGHT := 0.073

# ---- motion (the defaults; each figure's own spring scales them) ----
## Spring rate (Hz) and damping ratio: a lively bobble that rings ~1.5 s.
const SPRING_HZ := 2.8
const ZETA := 0.10
## Tilt (rad) per m/s^2 of the car's acceleration, and per m/s^2 of bump.
const LEAN_GAIN := 0.075
const NOD_GAIN := 0.03
## The most the head leans (rad, ~30 degrees), whatever the figure's gain.
const TILT_MAX := 0.55
## Low-pass time constant on the car's acceleration (s) and its cap (m/s^2).
const ACCEL_TAU := 0.04
const ACCEL_CAP := 30.0
const GRAVITY := 9.81

const BOB_SHADER := """
shader_type spatial;
// bob.x leans the head toward the car's +x (rad), bob.y toward +z. UV.x is how
// much of that a vertex takes (0 base and body, 1 head, more for a loose jaw);
// the pivot it turns about is (UV2.x, UV.y, UV2.y) in figure space. One draw
// call for the whole figure.
uniform vec2 bob = vec2(0.0);
void vertex() {
	float w = UV.x;
	vec3 pv = vec3(UV2.x, UV.y, UV2.y);
	vec3 p = VERTEX - pv;
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
	VERTEX = p + pv;
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
## The current figure's spring (BobbleFigures "spring"; the defaults for none).
var spring_hz := SPRING_HZ
var spring_zeta := ZETA
var spring_gain := 1.0
var spring_side := 1.0

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
	# Godot turns _physics_process on when a node with one enters the tree, so
	# the off state set in _init has to be set again here.
	var p := get_parent()
	var cockpit: Variant = p.get("cockpit") if p != null else null
	if cockpit is bool and cockpit:
		set_active(true)
	else:
		set_physics_process(false)

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
	_set_spring(BobbleFigures.spring_of(id))
	if id == NONE:
		return
	var spec: Dictionary = BobbleFigures.FIGURES[id]
	var parts := BobbleSculpt.build(id, spec)
	if parts.is_empty():
		push_warning("BobbleHead: no sculpt for figure '%s'" % id)
		figure = NONE
		return
	var mi := MeshInstance3D.new()
	mi.name = "Figure"
	mi.mesh = assemble(parts)
	for part in parts:
		_tris += (part.kit as CockpitKit).tri_count()
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

func _set_spring(s: Dictionary) -> void:
	spring_hz = float(s.get("hz", SPRING_HZ))
	spring_zeta = float(s.get("zeta", ZETA))
	spring_gain = float(s.get("gain", 1.0))
	spring_side = float(s.get("side", 1.0))

# ---------- mesh assembly ----------

## One ArrayMesh from the sculpt's parts, with UV = (bob weight, pivot y) and
## UV2 = (pivot x, pivot z) per vertex (see BobbleSculpt.build and BOB_SHADER).
static func assemble(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	for part in parts:
		var kit: CockpitKit = part.kit
		if kit.is_empty():
			continue
		var arr := kit.commit().surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		verts.append_array(v)
		normals.append_array(arr[Mesh.ARRAY_NORMAL])
		colors.append_array(arr[Mesh.ARRAY_COLOR])
		var w0 := float(part.w0)
		var w1 := float(part.w1)
		var y0 := float(part.y0)
		var y1 := float(part.y1)
		var pivot: Vector3 = part.pivot
		for p in v:
			var w := w0
			if y1 > y0:
				w = lerpf(w0, w1, clampf((p.y - y0) / (y1 - y0), 0.0, 1.0))
			uvs.append(Vector2(w, pivot.y))
			uv2s.append(Vector2(pivot.x, pivot.z))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Where a mesh vertex ends up for a given bob (the shader's maths, for tests
## and tools): i indexes the surface arrays.
static func bobbed_vertex(verts: PackedVector3Array, uvs: PackedVector2Array, uv2s: PackedVector2Array, i: int, bob_now: Vector2) -> Vector3:
	var uv := uvs[i]
	var pv := Vector3(uv2s[i].x, uv.y, uv2s[i].y)
	var q := verts[i] - pv
	var s := bob_now.x * uv.x
	var f := bob_now.y * uv.x
	q = Vector3(q.x * cos(s) + q.y * sin(s), -q.x * sin(s) + q.y * cos(s), q.z)
	q = Vector3(q.x, q.y * cos(f) - q.z * sin(f), q.z * cos(f) + q.y * sin(f))
	return q + pv

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
		-accel.x * LEAN_GAIN * spring_side,
		-accel.z * LEAN_GAIN - accel.y * NOD_GAIN) * spring_gain
	target = target.limit_length(tilt_max)
	var w := TAU * spring_hz
	bob_rate += ((target - bob) * (w * w) - bob_rate * (2.0 * spring_zeta * w)) * delta
	bob += bob_rate * delta
	bob = bob.limit_length(tilt_max)
	if _mat != null:
		_mat.set_shader_parameter("bob", bob)

static func _velocity_of(body: Node3D) -> Vector3:
	var v: Variant = body.get("linear_velocity")
	return v if v is Vector3 else Vector3.ZERO
