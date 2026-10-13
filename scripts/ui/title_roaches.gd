class_name TitleRoaches
extends RefCounted

# Roaches in and out of the sewer (menu roaches M7, 2026-10-11): ten
# cockroaches that come out of the ajar manhole on the Kerbside title set, dash
# about the lamp pool in stop-start runs and go back down, into the gutter at
# the kerb or under the car's shadow. One MultiMesh, one shared mesh, one
# shared shader; the motion is all in the vertex shader (as lamp_life.gd), so
# it runs while the title pauses the tree and costs no script per frame.
#
# Time: one `clock` uniform in seconds, written each frame by the title set
# (it starts at 0 when the menu shows, so the first roach is out ~6 s in, and
# it can be held still for screenshots). Per roach the custom data holds
# (seed, window start, window length, slot period): the ten roaches share
# three "slots"; in a slot the roaches take turns, so at most one per slot is
# out and never more than 3 in all. A roach's run is a pure function of its
# seed and the seconds since it came out (roach_at), hashed with products only
# (no sin hashes), and the same arithmetic is mirrored here in GDScript so a
# test and the skitter sound can ask where every roach is.
#
# Scare: `scare_t` (the clock when the scare began, or -1) and `origin` (the
# clock the slot cycles count from). While scared every roach that is out runs
# to the nearer of the gap and its own exit at FLEE_SPEED and is gone when it
# gets there; when the scare ends the cycles restart CALM_SECS later, so
# nothing comes out before then. The title writes those two uniforms only on
# the transitions. Look: dark glossy brown (#2A1A10), two shell halves tilted
# apart so the sodium lamp leaves a glint on one, six leg slivers that flick in
# 24 fps steps, a dark blob under each in place of a shadow.

const COUNT := 10
const SLOTS := 3
## Seconds after the clock starts before each slot's first roach comes out.
const SLOT_FIRST := [6.0, 13.0, 21.0]
## Hidden time between one roach of a slot going in and the next coming out.
const SLOT_GAP0 := 2.0
const SLOT_GAP1 := 8.0
## The lid: moved LID_SHIFT away from the camera so the hole shows a dark
## crescent on the camera's side, and tilted so the near edge lifts a little.
const LID_SHIFT := 0.12
const LID_TILT := 0.035
const LID_R := 0.45
const HOLE_Y := 0.004
## Where a roach stands (its blob), above the hole's black disc.
const BASE_Y := 0.006
## Along `near` from the hole's centre: hidden under the lid, and just past the
## hole's edge on the road.
const GAP_IN := 0.20
const GAP_OUT := 0.60
const EMERGE_SPEED := 0.8
const WANDER_R0 := 0.6
const WANDER_R1 := 1.8
const SPEED0 := 0.6
const SPEED1 := 1.2
const PAUSE0 := 0.3
const PAUSE1 := 2.0
## The gutter exit: at the kerb (road edge z = 0).
const KERB_Z := 0.12
const FLEE_SPEED := 2.4
const CALM_SECS := 3.0
const SCARE_ON := 0.5
const SCARE_OFF := 0.2
const RANGE := 40.0
const SHELL := Color(0.165, 0.102, 0.063)   # #2A1A10

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial

## Forgets the shared mesh and material; the next use builds them again.
static func drop_cache() -> void:
	_mesh = null
	_mat = null

# ---------- the run of one roach (mirrored in the shader) ----------

## A stable value in [0, 1) for (seed, k), products only so the GPU and the
## CPU agree to float precision.
static func hs(s: float, k: int) -> float:
	return fposmod((s + 0.1731 * float(k)) * (13.0 + 5.7 * float(k)), 1.0)

## The environment the runs are laid in (title-set space, XZ): the hole's
## centre, the unit direction toward the camera and the car-shadow exit.
static func env(vent: Vector3, near: Vector2, car_exit: Vector2) -> Dictionary:
	return {"vent": Vector2(vent.x, vent.z), "near": near, "side": Vector2(-near.y, near.x), "car_exit": car_exit}

static func gap_in(e: Dictionary) -> Vector2:
	return e.vent + e.near * GAP_IN

static func _gap_out(s: float, e: Dictionary) -> Vector2:
	return e.vent + e.near * GAP_OUT + e.side * ((hs(s, 0) - 0.5) * 0.4)

static func dash_count(s: float) -> int:
	return 2 + int(hs(s, 1) * 3.0)

static func exit_kind(s: float) -> int:
	return int(hs(s, 18) * 3.0)

## Where this roach goes at the end of its run: 0 back into the gap, 1 the
## gutter at the kerb, 2 under the car's shadow.
static func exit_target(s: float, e: Dictionary) -> Vector2:
	var k := exit_kind(s)
	if k == 0:
		return gap_in(e)
	if k == 1:
		return Vector2(e.vent.x + (hs(s, 19) - 0.5) * 3.0, KERB_Z)
	return Vector2(e.car_exit.x + hs(s, 19) * 1.2, e.car_exit.y)

## The run as segments {t0, t1, a, b, moving}: emerge, then dashes and pauses,
## then the exit leg(s). Hidden before t0 of the first and after t1 of the last.
static func plan(s: float, e: Dictionary) -> Array:
	var segs := []
	var p0 := gap_in(e)
	var p1 := _gap_out(s, e)
	var t := 0.0
	var d := p0.distance_to(p1) / EMERGE_SPEED
	segs.append({"t0": t, "t1": t + d, "a": p0, "b": p1, "moving": 1.0})
	t += d
	var cur := p1
	var n := dash_count(s)
	for i in n:
		var ang := hs(s, 2 + 2 * i) * TAU
		var r := WANDER_R0 + (WANDER_R1 - WANDER_R0) * hs(s, 3 + 2 * i)
		var tgt: Vector2 = e.vent + Vector2(cos(ang), sin(ang)) * r
		var v := SPEED0 + (SPEED1 - SPEED0) * hs(s, 10 + i)
		d = cur.distance_to(tgt) / v
		segs.append({"t0": t, "t1": t + d, "a": cur, "b": tgt, "moving": 1.0})
		t += d
		var p := PAUSE0 + (PAUSE1 - PAUSE0) * hs(s, 14 + i)
		segs.append({"t0": t, "t1": t + p, "a": tgt, "b": tgt, "moving": 0.0})
		t += p
		cur = tgt
	var ve := SPEED0 + (SPEED1 - SPEED0) * hs(s, 20)
	if exit_kind(s) == 0:
		d = cur.distance_to(p1) / ve
		segs.append({"t0": t, "t1": t + d, "a": cur, "b": p1, "moving": 1.0})
		t += d
		cur = p1
	var ex := exit_target(s, e)
	d = cur.distance_to(ex) / ve
	segs.append({"t0": t, "t1": t + d, "a": cur, "b": ex, "moving": 1.0})
	return segs

static func run_len(s: float, e: Dictionary) -> float:
	var segs := plan(s, e)
	return segs[segs.size() - 1].t1

## Where the roach is u seconds into its run: {pos, dir, moving}.
static func roach_at(s: float, u: float, e: Dictionary) -> Dictionary:
	var segs := plan(s, e)
	var dir: Vector2 = e.near
	for sg in segs:
		var a: Vector2 = sg.a
		var b: Vector2 = sg.b
		if not a.is_equal_approx(b):
			dir = (b - a).normalized()
		if u < sg.t1:
			var f := 0.0 if sg.t1 <= sg.t0 else clampf((u - sg.t0) / (sg.t1 - sg.t0), 0.0, 1.0)
			return {"pos": a.lerp(b, f), "dir": dir, "moving": sg.moving}
	var last: Dictionary = segs[segs.size() - 1]
	return {"pos": last.b, "dir": dir, "moving": 0.0}

# ---------- schedule ----------

## The ten roaches' custom data: x seed, y window start, z window length,
## w slot period (seconds). Round-robin over SLOTS slots; in a slot the runs
## follow one another with a hidden gap between, so one roach per slot at most.
static func schedule(e: Dictionary) -> Array[Color]:
	var out: Array[Color] = []
	var cursor := []
	for k in SLOTS:
		cursor.append(float(SLOT_FIRST[k]))
	var lens := []
	for i in COUNT:
		var s := seed_of(i)
		var slot := i % SLOTS
		var len := run_len(s, e)
		out.append(Color(s, cursor[slot], len, 0.0))
		lens.append(len)
		cursor[slot] += len + SLOT_GAP0 + (SLOT_GAP1 - SLOT_GAP0) * hs(s, 21)
	for i in COUNT:
		var c := out[i]
		c.a = cursor[i % SLOTS]
		out[i] = c
	return out

## The seed of roach i, fixed, away from any hash boundary.
static func seed_of(i: int) -> float:
	return fposmod(0.137 + 0.6180339887 * float(i), 1.0)

## Seconds into its run at clock t for a roach with custom data cd, or -1
## when it is hidden (the mirror of the shader's alive_u).
static func alive_u(cd: Color, t: float, origin: float) -> float:
	if t < origin:
		return -1.0
	var tl := fposmod(t - origin, cd.a)
	var u := tl - cd.g
	return u if (u >= 0.0 and u < cd.b) else -1.0

## Where every roach is at clock t: a list of {out, pos}. scare_t is the
## clock when the scare began, or -1. This is the shader's top level.
static func positions(sched: Array[Color], e: Dictionary, t: float, origin: float, scare_t: float) -> Array:
	var out := []
	for cd in sched:
		var s := cd.r
		if scare_t >= 0.0:
			var us := alive_u(cd, scare_t, origin)
			if us < 0.0:
				out.append({"out": false, "pos": gap_in(e)})
				continue
			var ps: Vector2 = roach_at(s, us, e).pos
			var g := gap_in(e)
			var ex := exit_target(s, e)
			var tgt: Vector2 = g if ps.distance_to(g) <= ps.distance_to(ex) else ex
			var d := ps.distance_to(tgt)
			var trav := (t - scare_t) * FLEE_SPEED
			if trav >= d:
				out.append({"out": false, "pos": tgt})
			else:
				out.append({"out": true, "pos": ps.lerp(tgt, trav / d)})
			continue
		var u := alive_u(cd, t, origin)
		if u < 0.0:
			out.append({"out": false, "pos": gap_in(e)})
		else:
			out.append({"out": true, "pos": roach_at(s, u, e).pos})
	return out

static func out_count(sched: Array[Color], e: Dictionary, t: float, origin: float, scare_t: float) -> int:
	var n := 0
	for r in positions(sched, e, t, origin, scare_t):
		if r.out:
			n += 1
	return n

# ---------- nodes ----------

static func create_node() -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = get_mesh()
	mm.instance_count = COUNT
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Roaches"
	mmi.multimesh = mm
	mmi.material_override = get_mat()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = RANGE
	return mmi

## Writes the schedule and the environment: every instance at the set's
## origin (the shader places it), the uniforms for the hole and the exits.
static func fill(mm: MultiMesh, e: Dictionary) -> Array[Color]:
	var sched := schedule(e)
	mm.visible_instance_count = COUNT
	for i in COUNT:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, sched[i])
	var m := get_mat()
	m.set_shader_parameter("vent", e.vent)
	m.set_shader_parameter("near", e.near)
	m.set_shader_parameter("car_exit", e.car_exit)
	return sched

static func set_uniform(uniform: String, value: float) -> void:
	get_mat().set_shader_parameter(uniform, value)

## The hole under the lid: a black disc just above the asphalt (the asphalt
## is a solid slab, so a disc below road level would not show).
static func hole_disc(at: Vector3) -> MeshInstance3D:
	var b := _Buf.new()
	var sides := 16
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		b.tri(Vector3.ZERO, Vector3(cos(a0) * LID_R, 0.0, sin(a0) * LID_R), Vector3(cos(a1) * LID_R, 0.0, sin(a1) * LID_R), Color.BLACK)
	var mi := MeshInstance3D.new()
	mi.name = "VentHole"
	mi.mesh = b.commit(AABB(Vector3(-0.5, -0.01, -0.5), Vector3(1.0, 0.02, 1.0)))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color.BLACK
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at + Vector3(0.0, HOLE_Y, 0.0)
	return mi

## The lid's transform: shifted LID_SHIFT away from the camera (along -near)
## and tilted up on the near edge.
static func lid_transform(vent: Vector3, near: Vector2) -> Transform3D:
	var axis := Vector3(-near.y, 0.0, near.x)   # across the near direction
	return Transform3D(Basis(axis, LID_TILT), vent - Vector3(near.x, 0.0, near.y) * LID_SHIFT)

# ---------- mesh ----------

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

# Mesh parts, COLOR.r: 0 shell, 0.25 head, 0.5 leg (COLOR.g 0/1 = gait
# group), 0.75 antenna, 1 blob. UV holds the root a leg or antenna swings
# about (local XZ). Forward is +X, the roach stands on y = 0.
static func get_mesh() -> ArrayMesh:
	if _mesh == null:
		var b := _Buf.new()
		# shell: a ridge down the middle, two halves sloping to the sides;
		# [x, half width, ridge height]
		var prof := [[-0.020, 0.004, 0.011], [-0.012, 0.0085, 0.017], [0.0, 0.009, 0.018], [0.010, 0.007, 0.016], [0.017, 0.0045, 0.012]]
		var shell := Color(0.0, 0.0, 0.0, 1.0)
		for side: float in [-1.0, 1.0]:
			for i in prof.size() - 1:
				var p0: Array = prof[i]
				var p1: Array = prof[i + 1]
				var r0 := Vector3(p0[0], p0[2], 0.0)
				var r1 := Vector3(p1[0], p1[2], 0.0)
				var s0 := Vector3(p0[0], 0.008, side * p0[1])
				var s1 := Vector3(p1[0], 0.008, side * p1[1])
				if side > 0.0:
					b.quad(r0, s0, s1, r1, shell)
				else:
					b.quad(r0, r1, s1, s0, shell)
		# head: a small darker cap in front of the shell
		var head := Color(0.25, 0.0, 0.0, 1.0)
		b.quad(Vector3(0.017, 0.012, -0.0045), Vector3(0.017, 0.012, 0.0045), Vector3(0.024, 0.009, 0.003), Vector3(0.024, 0.009, -0.003), head)
		b.quad(Vector3(0.017, 0.008, 0.0045), Vector3(0.017, 0.012, 0.0045), Vector3(0.024, 0.009, 0.003), Vector3(0.024, 0.007, 0.003), head)
		b.quad(Vector3(0.017, 0.012, -0.0045), Vector3(0.017, 0.008, -0.0045), Vector3(0.024, 0.007, -0.003), Vector3(0.024, 0.009, -0.003), head)
		# six legs: slivers from the body's side, flat, each with its root in UV
		var legs := [[0.010, 0.55], [0.0, 0.0], [-0.011, -0.55]]   # root x, splay from straight out
		var li := 0
		for side: float in [-1.0, 1.0]:
			for leg in legs:
				var root := Vector3(leg[0], 0.004, side * 0.008)
				var ang: float = leg[1]
				var dir := Vector3(sin(ang), 0.0, side * cos(ang)).normalized()
				var across := Vector3(-dir.z, 0.0, dir.x) * 0.0018
				var tip := root + dir * 0.016
				var group := float((li + (1 if side > 0.0 else 0)) % 2)
				b.quad(root - across, root + across, tip + across, tip - across, Color(0.5, group, 0.0, 1.0), Vector2(root.x, root.z))
				li += 1
		# two antennae, forward and out
		for side: float in [-1.0, 1.0]:
			var root := Vector3(0.022, 0.009, side * 0.003)
			var dir := Vector3(cos(0.45), 0.0, side * sin(0.45))
			var across := Vector3(-dir.z, 0.0, dir.x) * 0.001
			var tip := root + dir * 0.026
			b.quad(root - across, root + across, tip + across, tip - across, Color(0.75, 0.5 + side * 0.5, 0.0, 1.0), Vector2(root.x, root.z))
		# the dark blob under it all
		var blob := Color(1.0, 0.0, 0.0, 1.0)
		b.quad(Vector3(-0.032, 0.0005, -0.018), Vector3(-0.032, 0.0005, 0.018), Vector3(0.030, 0.0005, 0.018), Vector3(0.030, 0.0005, -0.018), blob)
		# the shader walks them over the road between the hole, the kerb and
		# the car: the box covers all of it
		_mesh = b.commit(AABB(Vector3(-12.0, -0.1, -1.0), Vector3(16.0, 0.5, 13.0)))
	return _mesh

const SHADER := """
shader_type spatial;
render_mode cull_disabled;

// INSTANCE_CUSTOM: x seed, y window start, z window length, w slot period.
uniform float clock = 0.0;      // seconds since the menu showed (the title writes it)
uniform float origin = 0.0;     // the clock the slot cycles count from
uniform float scare_t = -1.0;   // the clock the scare began, or -1
uniform vec2 vent = vec2(-6.6, 4.4);    // the hole's centre, set space XZ
uniform vec2 near = vec2(-0.3, 0.95);   // unit, toward the camera
uniform vec2 car_exit = vec2(-2.6, 2.7);

const float GAP_IN = 0.20;
const float GAP_OUT = 0.60;
const float EMERGE_SPEED = 0.8;
const float WANDER_R0 = 0.6;
const float WANDER_R1 = 1.8;
const float SPEED0 = 0.6;
const float SPEED1 = 1.2;
const float PAUSE0 = 0.3;
const float PAUSE1 = 2.0;
const float KERB_Z = 0.12;
const float FLEE_SPEED = 2.4;
const float BASE_Y = 0.006;

varying float part;

float hs(float s, float k) { return fract((s + 0.1731 * k) * (13.0 + 5.7 * k)); }

vec2 gap_in() { return vent + near * GAP_IN; }
vec2 side_dir() { return vec2(-near.y, near.x); }
vec2 gap_out(float s) { return vent + near * GAP_OUT + side_dir() * ((hs(s, 0.0) - 0.5) * 0.4); }
int exit_kind(float s) { return int(hs(s, 18.0) * 3.0); }

vec2 exit_target(float s) {
	int k = exit_kind(s);
	if (k == 0) { return gap_in(); }
	if (k == 1) { return vec2(vent.x + (hs(s, 19.0) - 0.5) * 3.0, KERB_Z); }
	return vec2(car_exit.x + hs(s, 19.0) * 1.2, car_exit.y);
}

// A straight leg from a to b over [t0, t1]: lands the position if u is in it.
bool leg(float u, float t0, float t1, vec2 a, vec2 b, float mv, inout vec2 pos, inout vec2 dir, inout float moving) {
	if (distance(a, b) > 1e-6) { dir = normalize(b - a); }
	if (u < t1) {
		float f = t1 <= t0 ? 0.0 : clamp((u - t0) / (t1 - t0), 0.0, 1.0);
		pos = mix(a, b, f);
		moving = mv;
		return true;
	}
	return false;
}

// Where the roach is u seconds into its run (mirrors TitleRoaches.roach_at).
void roach_at(float s, float u, out vec2 pos, out vec2 dir, out float moving) {
	vec2 p0 = gap_in();
	vec2 p1 = gap_out(s);
	dir = near;
	moving = 0.0;
	float t = 0.0;
	float d = distance(p0, p1) / EMERGE_SPEED;
	if (leg(u, t, t + d, p0, p1, 1.0, pos, dir, moving)) { return; }
	t += d;
	vec2 cur = p1;
	int n = 2 + int(hs(s, 1.0) * 3.0);
	for (int i = 0; i < 4; i++) {
		if (i >= n) { break; }
		float fi = float(i);
		float ang = hs(s, 2.0 + 2.0 * fi) * 6.283185307;
		float r = WANDER_R0 + (WANDER_R1 - WANDER_R0) * hs(s, 3.0 + 2.0 * fi);
		vec2 tgt = vent + vec2(cos(ang), sin(ang)) * r;
		float v = SPEED0 + (SPEED1 - SPEED0) * hs(s, 10.0 + fi);
		d = distance(cur, tgt) / v;
		if (leg(u, t, t + d, cur, tgt, 1.0, pos, dir, moving)) { return; }
		t += d;
		float p = PAUSE0 + (PAUSE1 - PAUSE0) * hs(s, 14.0 + fi);
		if (leg(u, t, t + p, tgt, tgt, 0.0, pos, dir, moving)) { return; }
		t += p;
		cur = tgt;
	}
	float ve = SPEED0 + (SPEED1 - SPEED0) * hs(s, 20.0);
	if (exit_kind(s) == 0) {
		d = distance(cur, p1) / ve;
		if (leg(u, t, t + d, cur, p1, 1.0, pos, dir, moving)) { return; }
		t += d;
		cur = p1;
	}
	vec2 ex = exit_target(s);
	d = distance(cur, ex) / ve;
	if (leg(u, t, t + d, cur, ex, 1.0, pos, dir, moving)) { return; }
	pos = ex;
	moving = 0.0;
}

// Seconds into its run at clock t, or -1 when hidden.
float alive_u(vec4 cd, float t) {
	if (t < origin) { return -1.0; }
	float tl = mod(t - origin, cd.w);
	float u = tl - cd.y;
	return (u >= 0.0 && u < cd.z) ? u : -1.0;
}

mat2 rot2(float a) { float c = cos(a); float s = sin(a); return mat2(vec2(c, s), vec2(-s, c)); }

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float s = cd.x;
	part = COLOR.r;
	bool hidden = false;
	vec2 pos = gap_in();
	vec2 dir = near;
	float moving = 0.0;
	if (scare_t >= 0.0) {
		float us = alive_u(cd, scare_t);
		if (us < 0.0) {
			hidden = true;
		} else {
			vec2 ps; vec2 ds; float ms;
			roach_at(s, us, ps, ds, ms);
			vec2 g = gap_in();
			vec2 ex = exit_target(s);
			vec2 tgt = distance(ps, g) <= distance(ps, ex) ? g : ex;
			float d = distance(ps, tgt);
			float trav = (clock - scare_t) * FLEE_SPEED;
			if (trav >= d) {
				hidden = true;
			} else {
				pos = mix(ps, tgt, trav / d);
				dir = normalize(tgt - ps);
				moving = 1.0;
			}
		}
	} else {
		float u = alive_u(cd, clock);
		if (u < 0.0) { hidden = true; } else { roach_at(s, u, pos, dir, moving); }
	}
	if (hidden) {
		VERTEX = vec3(pos.x, -0.05, pos.y);   // a point under the road: no pixels
	} else {
	// legs flick in 24 fps steps: the gait while moving, a rare twitch at rest
	float st = floor(clock * 24.0) / 24.0;
	vec3 p = VERTEX;
	if (COLOR.r > 0.4 && COLOR.r < 0.9) {
		float grp = COLOR.g > 0.5 ? 1.0 : -1.0;
		float ang;
		if (COLOR.r > 0.6) {
			// antenna: a slow sway, a flick when it moves off
			ang = 0.18 * sin(st * 8.0 + s * 6.0 + COLOR.g * 3.0) * grp + 0.25 * moving * sign(sin(st * 60.0 + s * 9.0)) * grp;
		} else if (moving > 0.5) {
			ang = 0.5 * grp * sign(sin(st * 6.283185307 * 13.0 + s * 6.283185307));
		} else {
			ang = 0.35 * grp * step(0.93, fract(st * 0.9 + s * 3.1 + COLOR.g * 0.5));
		}
		vec2 rel = p.xz - UV;
		p.xz = UV + rot2(ang) * rel;
	}
	// at rest the body twitches now and then, a few millimetres, in steps
	float heading_wobble = 0.0;
	if (moving < 0.5) {
		float tw = step(0.9, fract(st * 0.7 + s * 5.3));
		p.x += 0.004 * tw * sign(sin(st * 40.0 + s));
		heading_wobble = 0.12 * tw * sign(sin(st * 30.0 + s * 2.0));
	}
	dir = rot2(heading_wobble) * dir;
	vec3 f = vec3(dir.x, 0.0, dir.y);
	vec3 r = vec3(-dir.y, 0.0, dir.x);
	VERTEX = p.x * f + p.y * vec3(0.0, 1.0, 0.0) + p.z * r + vec3(pos.x, BASE_Y, pos.y);
	NORMAL = NORMAL.x * f + NORMAL.y * vec3(0.0, 1.0, 0.0) + NORMAL.z * r;
	}
}

void fragment() {
	vec3 shell = vec3(0.165, 0.102, 0.063);
	if (part > 0.9) {
		ALBEDO = vec3(0.0);        // the blob: no light, no gloss
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	} else if (part < 0.1) {
		// glossy shell: little diffuse (under the sodium lamp the full #2A1A10
		// read as a bright orange chip), the lamp's glint is what shows
		ALBEDO = shell * 0.4;
		ROUGHNESS = 0.45;   // 0.22 made the whole half flash under the lamp
		SPECULAR = 0.3;
	} else if (part < 0.3) {
		ALBEDO = shell * 0.3;      // head
		ROUGHNESS = 0.55;
		SPECULAR = 0.25;
	} else {
		ALBEDO = vec3(0.05, 0.03, 0.02);     // legs, antennae
		ROUGHNESS = 0.7;
		SPECULAR = 0.2;
	}
}
"""

static func get_mat() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	return _mat

static func triangles() -> int:
	return floori(float(get_mesh().surface_get_array_len(0)) / 3.0)
