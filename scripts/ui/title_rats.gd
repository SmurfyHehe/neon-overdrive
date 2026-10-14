class_name TitleRats
extends RefCounted

# Rats along the wall (menu rats M9, 2026-10-11): three rats that run the
# seam between the sidewalk and the wall of the Kerbside title set. One comes
# in from the dark end of the street, runs (1.5-3 m/s), stops in the lamp
# light, sits up and sniffs for a moment facing the road, then runs on and
# leaves at the far end or into the gap under the shutter. One rat every
# 20-40 s, now and then two in a row. One MultiMesh, one mesh, one shader;
# the motion is in the vertex shader off the title's `clock` uniform (the
# roaches' clock, title_roaches.gd), so it runs while the title pauses the
# tree and the picture can be held for a screenshot.
#
# Per rat the custom data holds (seed, base start, run length, period): the
# three share one PERIOD-second cycle, each starting at its base plus a
# per-cycle jitter (hashed from the seed and the cycle number), so the
# pattern does not repeat exactly. A rat's run is a pure function of its seed
# and the seconds since it came in (rat_at), products-only hashes, mirrored
# here so a test and the squeak can ask where every rat is.
#
# Scare (the roaches' `scare` uniform, from the turbo): above SCARE_ON a rat
# that is out bolts on at twice its speed, skipping the rest of its sniff;
# none come in while the scare is over SCARE_OFF or for CALM_SECS after. A
# faint scratch and squeak plays when one bolts (assets/ui/sfx/rat_squeak.wav,
# our own render). Look: dark grey-brown, low roughness along the back (wet
# fur), eyes two small amber dots that only show when it faces the camera;
# legs and tail move in 24 fps steps.

const COUNT := 3
const PERIOD := 70.0
## Base start of each rat in the cycle (s): one, then two in a row.
const FIRST := [5.0, 33.0, 36.5]
const JITTER := 8.0            # +/- half of this, per cycle
## The seam the rats run (set space): z just off the wall face, on the
## sidewalk; the dark end they come in from and the far end they leave by.
const SEAM_Z := -2.40
const WALK_Y := 0.1
const X_DARK := -13.5
const X_FAR := 16.5
## Where they stop: in the lamp light at the foot of the wall.
const STOP_X0 := -1.8
const STOP_X1 := 0.6
const SPEED0 := 1.5
const SPEED1 := 3.0
const SNIFF0 := 0.5
const SNIFF1 := 1.5
## The gap under the shutter (the shutter slab in title_kerbside.gd).
const SHUTTER_X := 1.9
const SHUTTER_HALF := 1.2
const INTO_WALL := 0.35
const BOLT_MULT := 2.0
const SCARE_ON := 0.5
const SCARE_OFF := 0.2
const CALM_SECS := 3.0
const RANGE := 60.0
const FUR := Color(0.16, 0.13, 0.11)
const EYE := Color(1.0, 0.78, 0.38)

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial

## Forgets the shared mesh and material; the next use builds them again.
static func drop_cache() -> void:
	_mesh = null
	_mat = null

# ---------- the run of one rat (mirrored in the shader) ----------

static func hs(s: float, k: int) -> float:
	return fposmod((s + 0.1731 * float(k)) * (13.0 + 5.7 * float(k)), 1.0)

static func stop_x(s: float) -> float:
	return STOP_X0 + (STOP_X1 - STOP_X0) * hs(s, 1)

static func speed(s: float) -> float:
	return SPEED0 + (SPEED1 - SPEED0) * hs(s, 2)

static func sniff(s: float) -> float:
	return SNIFF0 + (SNIFF1 - SNIFF0) * hs(s, 3)

## 0: leaves at the far end, 1: into the gap under the shutter.
static func exit_kind(s: float) -> int:
	return 0 if hs(s, 4) < 0.5 else 1

static func gap_x(s: float) -> float:
	return SHUTTER_X + (hs(s, 5) - 0.5) * 2.0 * SHUTTER_HALF

## The run as segments {t0, t1, a, b, moving, sit}.
static func plan(s: float) -> Array:
	var segs := []
	var v := speed(s)
	var p0 := Vector2(X_DARK, SEAM_Z)
	var p1 := Vector2(stop_x(s), SEAM_Z)
	var t := 0.0
	var d := p0.distance_to(p1) / v
	segs.append({"t0": t, "t1": t + d, "a": p0, "b": p1, "moving": 1.0, "sit": 0.0})
	t += d
	var p := sniff(s)
	segs.append({"t0": t, "t1": t + p, "a": p1, "b": p1, "moving": 0.0, "sit": 1.0})
	t += p
	if exit_kind(s) == 0:
		var p2 := Vector2(X_FAR, SEAM_Z)
		d = p1.distance_to(p2) / v
		segs.append({"t0": t, "t1": t + d, "a": p1, "b": p2, "moving": 1.0, "sit": 0.0})
	else:
		var g := Vector2(gap_x(s), SEAM_Z)
		d = p1.distance_to(g) / v
		segs.append({"t0": t, "t1": t + d, "a": p1, "b": g, "moving": 1.0, "sit": 0.0})
		t += d
		var inside := Vector2(g.x, SEAM_Z - INTO_WALL)
		segs.append({"t0": t, "t1": t + INTO_WALL / v, "a": g, "b": inside, "moving": 1.0, "sit": 0.0})
	return segs

static func run_len(s: float) -> float:
	var segs := plan(s)
	return segs[segs.size() - 1].t1

## Where the rat is u seconds into its run: {pos, dir, moving, sit}.
static func rat_at(s: float, u: float) -> Dictionary:
	var segs := plan(s)
	var dir := Vector2(1.0, 0.0)
	for sg in segs:
		var a: Vector2 = sg.a
		var b: Vector2 = sg.b
		if not a.is_equal_approx(b):
			dir = (b - a).normalized()
		if u < sg.t1:
			var f := 0.0 if sg.t1 <= sg.t0 else clampf((u - sg.t0) / (sg.t1 - sg.t0), 0.0, 1.0)
			return {"pos": a.lerp(b, f), "dir": dir, "moving": sg.moving, "sit": sg.sit}
	var last: Dictionary = segs[segs.size() - 1]
	return {"pos": last.b, "dir": dir, "moving": 0.0, "sit": 0.0}

## The sniff window [t0, t1] of this rat's run.
static func sniff_window(s: float) -> Vector2:
	var sg: Dictionary = plan(s)[1]
	return Vector2(sg.t0, sg.t1)

# ---------- schedule ----------

static func seed_of(i: int) -> float:
	return fposmod(0.311 + 0.6180339887 * float(i), 1.0)

## Custom data per rat: x seed, y base start, z run length, w period.
static func schedule() -> Array[Color]:
	var out: Array[Color] = []
	for i in COUNT:
		var s := seed_of(i)
		out.append(Color(s, float(FIRST[i]), run_len(s), PERIOD))
	return out

## Seconds into its run at clock t, or -1 when hidden (the shader's alive_u).
static func alive_u(cd: Color, t: float, origin: float) -> float:
	if t < origin:
		return -1.0
	var c := floorf((t - origin) / cd.a)
	var tl := t - origin - c * cd.a
	var j := (hs(cd.r, 30 + posmod(int(c), 5)) - 0.5) * JITTER
	var u := tl - (cd.g + j)
	return u if (u >= 0.0 and u < cd.b) else -1.0

## Seconds into its run for a rat that was us seconds in when the scare began
## at scare_t: time runs at BOLT_MULT, and what was left of a sniff is skipped.
static func bolt_u(s: float, us: float, t: float, scare_t: float) -> float:
	var w := sniff_window(s)
	var skip := 0.0
	if us >= w.x and us < w.y:
		skip = w.y - us
	return us + skip + (t - scare_t) * BOLT_MULT

## Where every rat is at clock t: a list of {out, pos, sit}. scare_t is the
## clock when the scare began, or -1.
static func positions(sched: Array[Color], t: float, origin: float, scare_t: float) -> Array:
	var out := []
	for cd in sched:
		var s := cd.r
		var u := -1.0
		if scare_t >= 0.0:
			var us := alive_u(cd, scare_t, origin)
			if us >= 0.0:
				u = bolt_u(s, us, t, scare_t)
				if u >= cd.b:
					u = -1.0
		else:
			u = alive_u(cd, t, origin)
		if u < 0.0:
			out.append({"out": false, "pos": Vector2(X_DARK, SEAM_Z), "sit": 0.0})
		else:
			var r := rat_at(s, u)
			out.append({"out": true, "pos": r.pos, "sit": r.sit})
	return out

static func out_count(sched: Array[Color], t: float, origin: float, scare_t: float) -> int:
	var n := 0
	for r in positions(sched, t, origin, scare_t):
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
	mmi.name = "Rats"
	mmi.multimesh = mm
	mmi.material_override = get_mat()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = RANGE
	return mmi

static func fill(mm: MultiMesh) -> Array[Color]:
	var sched := schedule()
	mm.visible_instance_count = COUNT
	for i in COUNT:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, sched[i])
	return sched

static func set_uniform(uniform: String, value: float) -> void:
	get_mat().set_shader_parameter(uniform, value)

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

# Mesh parts, COLOR.r: 0 body, 0.25 head, 0.5 leg (COLOR.g 0/1 = gait group),
# 0.75 tail (COLOR.g = fraction along it), 0.9 blob, 1 eye. UV holds the
# root a leg swings about (local XY). Forward is +X, the rat stands on y = 0,
# nose at x = 0.14, tail tip at x = -0.29.
static func get_mesh() -> ArrayMesh:
	if _mesh == null:
		var b := _Buf.new()
		var rings := [[-0.105, 0.012], [-0.08, 0.030], [-0.04, 0.037], [0.01, 0.035], [0.06, 0.028], [0.085, 0.024], [0.105, 0.021], [0.135, 0.007]]
		var sides := 6
		var pts := []
		for ring in rings:
			var x: float = ring[0]
			var r: float = ring[1]
			var ry := r * 0.85
			var row := []
			for k in sides:
				var a := (float(k) + 0.5) / float(sides) * TAU
				row.append(Vector3(x, ry * (1.0 + sin(a)), r * cos(a)))
			pts.append(row)
		for i in rings.size() - 1:
			var part := 0.0 if i < 4 else 0.25
			var col := Color(part, 0.0, 0.0, 1.0)
			for k in sides:
				var k1 := (k + 1) % sides
				b.quad(pts[i][k], pts[i][k1], pts[i + 1][k1], pts[i + 1][k], col)
		# nose and rump caps
		var nose := Vector3(0.142, 0.010, 0.0)
		var rump := Vector3(-0.112, 0.012, 0.0)
		for k in sides:
			var k1 := (k + 1) % sides
			b.tri(pts[rings.size() - 1][k], pts[rings.size() - 1][k1], nose, Color(0.25, 0.0, 0.0, 1.0))
			b.tri(pts[0][k1], pts[0][k], rump, Color(0.0, 0.0, 0.0, 1.0))
		# ears: two small leaves on the head
		for side: float in [-1.0, 1.0]:
			var e := Vector3(0.088, 0.052, side * 0.016)
			b.quad(e, e + Vector3(-0.006, 0.016, side * 0.004), e + Vector3(0.006, 0.018, side * 0.006), e + Vector3(0.010, 0.004, side * 0.002), Color(0.25, 0.0, 0.0, 1.0))
		# eyes: tiny squares on the head's sides, forward
		for side: float in [-1.0, 1.0]:
			var c := Vector3(0.118, 0.030, side * 0.016)
			var r := 0.0035
			b.quad(c + Vector3(-r, -r, 0.0), c + Vector3(-r, r, 0.0), c + Vector3(r, r, 0.0), c + Vector3(r, -r, 0.0), Color(1.0, 0.0, 0.0, 1.0))
		# four legs: thin slivers down from the belly, roots in UV (x, y)
		var li := 0
		for side: float in [-1.0, 1.0]:
			for rx: float in [0.068, -0.075]:
				var root := Vector3(rx, 0.028, side * 0.024)
				var tip := Vector3(rx + 0.008, 0.0, side * 0.034)
				var across := Vector3(0.0, 0.0, side * 0.004)
				var fwd := Vector3(0.004, 0.0, 0.0)
				var group := float((li + (1 if side > 0.0 else 0)) % 2)
				b.quad(root - fwd, root + fwd, tip + fwd, tip - fwd, Color(0.5, group, 0.0, 1.0), Vector2(root.x, root.y))
				b.quad(root - across, root + across, tip + across, tip - across, Color(0.5, group, 0.0, 1.0), Vector2(root.x, root.y))
				li += 1
		# the tail: a thin vertical strip in six pieces, thinning to the tip
		var tseg := 6
		var tail_len := 0.18
		for i in tseg:
			var f0 := float(i) / float(tseg)
			var f1 := float(i + 1) / float(tseg)
			var x0 := -0.105 - tail_len * f0
			var x1 := -0.105 - tail_len * f1
			var h0 := 0.006 * (1.0 - 0.6 * f0)
			var h1 := 0.006 * (1.0 - 0.6 * f1)
			var y0 := 0.012 - 0.004 * f0
			var y1 := 0.012 - 0.004 * f1
			var c0 := Color(0.75, f0, 0.0, 1.0)
			var c1 := Color(0.75, f1, 0.0, 1.0)
			b.tri(Vector3(x0, y0 - h0, 0.0), Vector3(x0, y0 + h0, 0.0), Vector3(x1, y1 + h1, 0.0), c0)
			b.tri(Vector3(x0, y0 - h0, 0.0), Vector3(x1, y1 + h1, 0.0), Vector3(x1, y1 - h1, 0.0), c1)
		# a dark blob under it all
		var blob := Color(0.9, 0.0, 0.0, 1.0)
		b.quad(Vector3(-0.13, 0.001, -0.05), Vector3(-0.13, 0.001, 0.05), Vector3(0.15, 0.001, 0.05), Vector3(0.15, 0.001, -0.05), blob)
		# the shader runs them along the whole wall foot and into the wall
		_mesh = b.commit(AABB(Vector3(X_DARK - 1.0, -0.2, SEAM_Z - 1.0), Vector3(X_FAR - X_DARK + 2.0, 1.0, 2.0)))
	return _mesh

const SHADER := """
shader_type spatial;
render_mode cull_disabled;

// INSTANCE_CUSTOM: x seed, y base start, z run length, w period.
uniform float clock = 0.0;      // the title's street clock (the roaches' clock)
uniform float origin = 0.0;     // the clock the cycles count from
uniform float scare_t = -1.0;   // the clock the scare began, or -1

const float SEAM_Z = -2.40;
const float WALK_Y = 0.1;
const float X_DARK = -13.5;
const float X_FAR = 16.5;
const float STOP_X0 = -1.8;
const float STOP_X1 = 0.6;
const float SPEED0 = 1.5;
const float SPEED1 = 3.0;
const float SNIFF0 = 0.5;
const float SNIFF1 = 1.5;
const float SHUTTER_X = 1.9;
const float SHUTTER_HALF = 1.2;
const float INTO_WALL = 0.35;
const float BOLT_MULT = 2.0;
const float JITTER = 8.0;

varying float part;
varying float facing;
varying float back;   // how much the surface faces up, set space

float hs(float s, float k) { return fract((s + 0.1731 * k) * (13.0 + 5.7 * k)); }
float stop_x(float s) { return STOP_X0 + (STOP_X1 - STOP_X0) * hs(s, 1.0); }
float speed(float s) { return SPEED0 + (SPEED1 - SPEED0) * hs(s, 2.0); }
float sniff(float s) { return SNIFF0 + (SNIFF1 - SNIFF0) * hs(s, 3.0); }
int exit_kind(float s) { return hs(s, 4.0) < 0.5 ? 0 : 1; }
float gap_x(float s) { return SHUTTER_X + (hs(s, 5.0) - 0.5) * 2.0 * SHUTTER_HALF; }

bool leg(float u, float t0, float t1, vec2 a, vec2 b, float mv, float st, inout vec2 pos, inout vec2 dir, inout float moving, inout float sit) {
	if (distance(a, b) > 1e-6) { dir = normalize(b - a); }
	if (u < t1) {
		float f = t1 <= t0 ? 0.0 : clamp((u - t0) / (t1 - t0), 0.0, 1.0);
		pos = mix(a, b, f);
		moving = mv;
		sit = st;
		return true;
	}
	return false;
}

// Where the rat is u seconds into its run (mirrors TitleRats.rat_at).
// sniff_t0/t1: the sniff window, for the bolt's skip and the turn.
void rat_at(float s, float u, out vec2 pos, out vec2 dir, out float moving, out float sit, out float sniff_t0, out float sniff_t1) {
	float v = speed(s);
	vec2 p0 = vec2(X_DARK, SEAM_Z);
	vec2 p1 = vec2(stop_x(s), SEAM_Z);
	dir = vec2(1.0, 0.0);
	moving = 0.0;
	sit = 0.0;
	float t = 0.0;
	float d = distance(p0, p1) / v;
	bool done = leg(u, t, t + d, p0, p1, 1.0, 0.0, pos, dir, moving, sit);
	t += d;
	float p = sniff(s);
	sniff_t0 = t;
	sniff_t1 = t + p;
	if (done) { return; }
	if (leg(u, t, t + p, p1, p1, 0.0, 1.0, pos, dir, moving, sit)) { return; }
	t += p;
	if (exit_kind(s) == 0) {
		vec2 p2 = vec2(X_FAR, SEAM_Z);
		d = distance(p1, p2) / v;
		if (leg(u, t, t + d, p1, p2, 1.0, 0.0, pos, dir, moving, sit)) { return; }
		pos = p2;
	} else {
		vec2 g = vec2(gap_x(s), SEAM_Z);
		d = distance(p1, g) / v;
		if (leg(u, t, t + d, p1, g, 1.0, 0.0, pos, dir, moving, sit)) { return; }
		t += d;
		vec2 inside = vec2(g.x, SEAM_Z - INTO_WALL);
		if (leg(u, t, t + INTO_WALL / v, g, inside, 1.0, 0.0, pos, dir, moving, sit)) { return; }
		pos = inside;
	}
	moving = 0.0;
}

float alive_u(vec4 cd, float t) {
	if (t < origin) { return -1.0; }
	float c = floor((t - origin) / cd.w);
	float tl = t - origin - c * cd.w;
	float j = (hs(cd.x, 30.0 + mod(c, 5.0)) - 0.5) * JITTER;
	float u = tl - (cd.y + j);
	return (u >= 0.0 && u < cd.z) ? u : -1.0;
}

mat2 rot2(float a) { float c = cos(a); float s = sin(a); return mat2(vec2(c, s), vec2(-s, c)); }

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float s = cd.x;
	part = COLOR.r;
	facing = 0.0;
	back = 0.0;
	float u = -1.0;
	float bolt = 0.0;
	if (scare_t >= 0.0) {
		float us = alive_u(cd, scare_t);
		if (us >= 0.0) {
			vec2 ps; vec2 ds; float ms; float ss; float w0; float w1;
			rat_at(s, us, ps, ds, ms, ss, w0, w1);
			float skip = (us >= w0 && us < w1) ? (w1 - us) : 0.0;
			u = us + skip + (clock - scare_t) * BOLT_MULT;
			if (u >= cd.z) { u = -1.0; }
			bolt = 1.0;
		}
	} else {
		u = alive_u(cd, clock);
	}
	if (u < 0.0) {
		VERTEX = vec3(X_DARK, -0.5, SEAM_Z);   // under the sidewalk: no pixels
	} else {
		vec2 pos; vec2 dir; float moving; float sit; float w0; float w1;
		rat_at(s, u, pos, dir, moving, sit, w0, w1);
		vec3 cam = CAMERA_POSITION_WORLD - NODE_POSITION_WORLD;
		vec2 to_cam = normalize(cam.xz - pos);
		// sitting up it turns to face the road (a short blend in and out)
		if (sit > 0.5) {
			float f = smoothstep(0.0, 0.2, u - w0) * (1.0 - smoothstep(w1 - 0.2, w1, u));
			dir = normalize(mix(dir, to_cam, f));
		}
		float st = floor(clock * 24.0) / 24.0;
		vec3 p = VERTEX;
		float gait = moving * (10.0 + 6.0 * bolt);
		if (COLOR.r > 0.4 && COLOR.r < 0.6) {
			// a leg: swings about its root in the body's XY plane, in 24 fps steps
			float grp = COLOR.g > 0.5 ? 1.0 : -1.0;
			float ang = moving > 0.5
				? 0.55 * grp * sign(sin(st * 6.283185307 * gait * 0.5 + s * 6.283185307))
				: 0.0;
			vec2 rel = p.xy - UV;
			p.xy = UV + rot2(ang) * rel;
		} else if (COLOR.r > 0.7 && COLOR.r < 0.8) {
			// the tail: a wave along it while running, a lazy sway at rest
			float f = COLOR.g;
			float wav = moving > 0.5 ? 0.025 * sin(st * 6.283185307 * 3.0 - f * 4.0 + s) : 0.012 * sin(st * 1.3 + s * 4.0 + f * 2.0);
			p.z += wav * f;
		}
		if (sit > 0.5 && COLOR.r < 0.7) {
			// sits up: body, head, eyes and front legs pitch up about the hips
			float rise = smoothstep(0.0, 0.25, u - w0) * (1.0 - smoothstep(w1 - 0.25, w1, u));
			if (p.x > -0.07) {
				vec2 piv = vec2(-0.07, 0.03);
				vec2 rel = p.xy - piv;
				float nod = 0.08 * sin(st * 6.283185307 * 2.2 + s * 3.0) * step(0.1, p.x);
				p.xy = piv + rot2(1.0 * rise + nod * rise) * rel;
			}
		}
		if (moving > 0.5 && COLOR.r < 0.7) {
			// a low gallop: the body bobs with the gait
			p.y += 0.006 * abs(sin(st * 6.283185307 * gait * 0.5 + s * 6.283185307));
		}
		vec3 f3 = vec3(dir.x, 0.0, dir.y);
		vec3 r3 = vec3(-dir.y, 0.0, dir.x);
		VERTEX = p.x * f3 + p.y * vec3(0.0, 1.0, 0.0) + p.z * r3 + vec3(pos.x, WALK_Y, pos.y);
		NORMAL = NORMAL.x * f3 + NORMAL.y * vec3(0.0, 1.0, 0.0) + NORMAL.z * r3;
		back = NORMAL.y;
		facing = dot(dir, to_cam);
	}
}

void fragment() {
	vec3 fur = vec3(0.16, 0.13, 0.11);
	if (part > 0.95) {
		// eyes: two amber dots, only when it faces the camera
		ALBEDO = vec3(0.02);
		ROUGHNESS = 0.4;
		EMISSION = vec3(1.0, 0.78, 0.38) * 1.6 * smoothstep(0.35, 0.65, facing);
	} else if (part > 0.85) {
		ALBEDO = vec3(0.0);        // the blob
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	} else if (part < 0.1) {
		// body: wet fur, a low roughness along the back where the lamp hits
		ALBEDO = fur;
		ROUGHNESS = mix(0.8, 0.3, clamp(back, 0.0, 1.0));
		SPECULAR = 0.5;
	} else if (part < 0.3) {
		ALBEDO = fur * 0.9;        // head and ears
		ROUGHNESS = 0.6;
		SPECULAR = 0.4;
	} else {
		ALBEDO = vec3(0.14, 0.11, 0.10);   // legs, tail: bare skin
		ROUGHNESS = 0.55;
		SPECULAR = 0.3;
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
