extends Node3D
class_name ExhaustFlames

# Exhaust flames v3, look A "shed fire" (2026-10-10, Roy: the fireball that
# followed the car looked outdated). v2 (2026-10-07, Option A shader quads)
# left a round camera-facing fireball that kept half the car's speed, so it
# hung behind the bumper like a balloon. Now the fire is SHED: it stays on the
# road where it was spat out and the car drives away from it.
#
# One burst is three things, all hidden while idle (no draw calls, no light):
# - a JET per exhaust tip: a short, tight white-amber tongue. Two crossed
#   strips stretched along the pipe axis (vertex shader): one turned to face
#   the eye, one at right angles to it, so the tongue still reads from behind
#   the car, where the first strip is edge-on;
# - LOBES: 2-3 small ragged pieces of fire per tip that stay where they were
#   spat out (LOBE_CARRY of the car's speed, near zero) and stretch into a
#   streak along the car's travel as it pulls away. Each lobe is ONE quad with
#   two layers in one shader pass (premultiplied blend): a hot additive core
#   and a dark see-through soot rim. The core burns out over the first
#   LOBE_HOT share of its life; the rim goes dark brown, then thins into a grey
#   smoke wisp. There is no separate smoke puff any more;
# - one pooled OmniLight flash per car (no shadows), a few frames long.
# Colours: white-hot -> amber #FFC066 -> sodium orange #FF8A1F (Amber vs.
# Dusk), soot dark brown, wisp grey. No blue core, no magenta, no cyan.
#
# Chunky PS2 feel: the jets and lobes animate in steps of STEP (about 24 fps):
# their ages, shapes and positions only advance every STEP of game time. The
# light flash is per frame (it is two frames long). Each lobe has its own
# random seed, so no two have the same shape.
#
# The Flame knob (spec.exhaust.flame, 0..1) sets size AND lobe count: 0.1 is
# one small spit and a short tongue, 1.0 three big lobes and a longer tongue.
# The Pops knob only sets how often (EngineSynth / _simulate_pops).
#
# Styles: FIRE (every car) and GHOST (the bone car, 2026-10-10): the same
# shaders with a ghost-green colour set (pale white-green core, #B8F28A,
# dark olive edge), a STEADY jet instead of bursts while the throttle is down,
# and an afterburner (set_afterburner): a longer flame with bright bands inside
# it (shock diamonds, drawn in the jet shader). Its V8 pops are green lobes.
# The bone car itself is not on main yet (PR #360 is the jet-force physics
# spike); a car asks for the style with spec.fire_style = "ghost" or
# set_style(Style.GHOST).
#
# Triggers (unchanged from v2):
# - the synth's flame events (EngineSynth.take_flames(): overrun pops, limiter
#   bangs, the anti-lag volley), on a car with EngineAudio (the player);
# - the same laws run here from the car's own state on a car without one
#   (traffic: TrafficManager only adds this node to a car whose spec has a
#   flame value above 0);
# - an upshift at full throttle, only when the car's flame setting is at least
#   UPSHIFT_FLAME_MIN (Roy, 2026-10-07: upshift flames only on high-flame cars).
# All of it is cosmetic: nothing in the sim reads it.
#
# Brightness follows the throttle (2026-10-07): `drive` tracks the car's
# throttle_amount, rising at once and falling over THROTTLE_RELEASE when the
# foot comes off, and scales the jet, lobe and light energy between GLOW_FLOOR
# and 1. Only the energy changes, so the heat colours stay as they are.
#
# Sync: the synth renders audio BUFFER ahead of what is heard, so an event
# taken from it now is heard VISUAL_DELAY later. Every burst goes through a
# small delay queue (queue_burst) and shows when its sound plays.
#
# Tips come from the chassis visual's "exhaust_tips" meta (TestCarBuilder,
# P1CoupeBuilder, NpcCarBuilder); a car without the meta gets one centre pipe.

signal burst_shown(kind: int, size: float)

enum Kind { POP, UPSHIFT }
enum Style { FIRE, GHOST }

## Seconds between the synth handing out a flame event and it being heard
## (EngineAudio.BUFFER_SECS of audio is queued ahead): the visual waits as long.
const VISUAL_DELAY := 0.06
## Upshift flames only on cars whose flame setting is at least this.
const UPSHIFT_FLAME_MIN := 0.4
const MAX_QUEUED := 16
## Animation step, s: jets and lobes advance this often (about 24 fps).
const STEP := 1.0 / 24.0

const JET_LIFE := 0.12      # s
const JET_LEN := Vector2(0.3, 0.9)     # m at flame size 0 / 1
const JET_WIDTH := Vector2(0.12, 0.26) # m
const LOBE_LIFE := 0.9      # s, hot core then soot then wisp
const LOBE_HOT := 0.35      # share of LOBE_LIFE the core burns
const LOBE_RADIUS := Vector2(0.07, 0.2)  # m at birth, size 0 / 1
const LOBE_GROW := 2.2      # radius multiplier by the end of its life
const LOBE_SPIT := 2.5      # m/s out of the pipe, on top of the car's velocity x LOBE_CARRY
const LOBE_CARRY := 0.05    # the lobe keeps almost none of the car's speed: it is shed
const LOBE_RISE := 0.35     # m/s, hot air
const LOBE_STREAK := 0.05   # m of stretch per m/s of the car's speed at spit
const LOBE_STREAK_MAX := 1.4  # m
const LOBES_MAX := 3        # per tip at flame 1
const POOL := 8             # lobes per car
const LIGHT_LIFE := 0.08
const LIGHT_ENERGY := 2.0
const LIGHT_RANGE := 4.0
const LIGHT_COLOR := Color(1.0, 0.68, 0.32)
const JET_ENERGY := 1.7
const LOBE_ENERGY := 1.3
## Brightness at zero throttle, as a share of full (see the header).
const GLOW_FLOOR := 0.4
## Seconds for `drive` to fall from 1 to 0 after the throttle lifts.
const THROTTLE_RELEASE := 0.25
## Seconds for `drive` to rise from 0 to 1 (the foot going down shows at once).
const THROTTLE_ATTACK := 0.05
## Ghost style: the steady jet's length, m, at afterburner 0 / 1.
const GHOST_JET_LEN := Vector2(0.7, 1.7)
const GHOST_JET_WIDTH := Vector2(0.2, 0.3)

const HOT := Color(1.0, 0.95, 0.85)    # white-hot, warm
const AMBER := Color(1.0, 0.753, 0.4)  # #FFC066
const ORANGE := Color(1.0, 0.541, 0.122)  # #FF8A1F
const SOOT := Color(0.16, 0.085, 0.04)   # dark brown rim
const WISP := Color(0.3, 0.3, 0.32)      # thin grey smoke
## Ghost-green set (bone car): pale white-green core, #B8F28A, dark olive edge.
const GHOST_HOT := Color(0.88, 1.0, 0.86)
const GHOST_MID := Color(0.722, 0.949, 0.541)  # #B8F28A
const GHOST_EDGE := Color(0.2, 0.32, 0.1)
const GHOST_SOOT := Color(0.06, 0.1, 0.04)
const GHOST_LIGHT := Color(0.72, 0.95, 0.54)

const NOISE_GLSL := """
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
"""

const JET_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform, fog_disabled;
uniform float burst = 0.0;      // 1 -> 0 over the jet's life (steady: held near 1)
uniform float size = 0.5;       // flame size 0..1
uniform float jet_len = 0.8;    // m
uniform float jet_width = 0.25; // m
uniform float seed = 0.0;
uniform float energy = 1.7;
uniform float tick = 0.0;       // stepped time, s (STEP)
uniform float cross_strip = 0.0; // 1: the strip at right angles to the eye-facing one
uniform float diamonds = 0.0;   // ghost afterburner: bright bands along the flame
uniform vec3 hot : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 amber : source_color = vec3(1.0, 0.753, 0.4);
uniform vec3 orange : source_color = vec3(1.0, 0.541, 0.122);
varying vec2 jv;
""" + NOISE_GLSL + """
void vertex() {
	// Quad x in [-0.5, 0.5] across, y in [-0.5, 0.5] along. Stretch it along
	// the node's +Z (the pipe axis) and turn it about that axis to face the
	// eye; the cross strip is the same quad turned a quarter further, so the
	// tongue still shows from straight behind.
	vec3 o = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 ax = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	vec3 side = cross(ax, normalize(o));
	side = length(side) < 0.001 ? vec3(1.0, 0.0, 0.0) : normalize(side);
	if (cross_strip > 0.5) {
		side = normalize(cross(ax, side));
	}
	float t = VERTEX.y + 0.5;
	jv = vec2(VERTEX.x * 2.0, t);
	VERTEX = o + ax * t * jet_len + side * VERTEX.x * jet_width;
	NORMAL = normalize(cross(side, ax));
}

void fragment() {
	float t = jv.y;      // 0 at the nozzle, 1 at the tip
	float a = abs(jv.x); // 0 on the axis, 1 at the quad edge
	float tm = tick * 18.0 + seed * 13.0;
	float n = vnoise(vec2(jv.x * 3.0 + seed, t * 6.0 - tm));
	float n2 = vnoise(vec2(jv.x * 7.0 - seed, t * 13.0 - tm * 1.7));
	// a narrow neck at the nozzle that swells, then a ragged, shrinking tip
	float reach = mix(0.55, 1.0, burst) * (0.75 + 0.35 * n);
	float w = mix(0.35, 1.0, sqrt(clamp(t / 0.35, 0.0, 1.0))) * (1.0 - smoothstep(reach * 0.55, reach, t));
	float body = 1.0 - smoothstep(w * 0.55, w, a + 0.25 * (n2 - 0.5));
	float heat = clamp((1.0 - t / max(reach, 0.01)) * (1.0 - a / max(w, 0.01)) * 1.4 + 0.25 * (n - 0.5), 0.0, 1.0);
	vec3 c = mix(orange, amber, smoothstep(0.15, 0.5, heat));
	c = mix(c, hot, smoothstep(0.7, 0.95, heat));
	// shock diamonds: bright bands down the flame, fading toward the tip
	float dia = 1.0 + diamonds * 1.4 * pow(0.5 + 0.5 * cos(t * 30.0 - tick * 4.0), 4.0) * (1.0 - t) * (1.0 - a);
	float k = body * smoothstep(0.0, 0.08, t) * clamp(burst * 1.6, 0.0, 1.0);
	ALBEDO = c * dia * energy * (0.45 + 0.55 * size) * (0.35 + 0.65 * heat) * k;
	ALPHA = k;
}
"""

# One quad, two layers: ALBEDO is added to the screen and ALPHA darkens it
# (premultiplied blend: out = src + dst * (1 - alpha)). The hot core has
# alpha 0 (pure additive); the soot rim has a dark colour and alpha; the
# wisp is the same rim, thinner and grey.
const LOBE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform, fog_disabled;
uniform float age = 1.0;        // 0 at birth -> 1 dead
uniform float hot_share = 0.35; // share of the life the core burns
uniform float size = 0.5;
uniform float seed = 0.0;
uniform float energy = 1.3;
uniform float radius = 0.1;     // m
uniform vec3 stretch_dir = vec3(0.0, 0.0, 1.0);  // world: the car's travel
uniform float stretch = 0.0;    // m, extra length along stretch_dir
uniform vec3 hot : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 amber : source_color = vec3(1.0, 0.753, 0.4);
uniform vec3 orange : source_color = vec3(1.0, 0.541, 0.122);
uniform vec3 soot : source_color = vec3(0.16, 0.085, 0.04);
uniform vec3 wisp : source_color = vec3(0.3, 0.3, 0.32);
varying vec2 lv;
""" + NOISE_GLSL + """
void vertex() {
	// A billboard drawn out along the screen projection of stretch_dir: a
	// streak from the side, a receding blob from straight behind.
	vec3 c = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	vec3 d = (VIEW_MATRIX * vec4(stretch_dir, 0.0)).xyz;
	d.z = 0.0;
	float dl = length(d);
	vec3 along = dl > 0.001 ? d / dl : vec3(0.0, 1.0, 0.0);
	vec3 perp = vec3(-along.y, along.x, 0.0);
	lv = VERTEX.xy * 2.0;
	VERTEX = c + along * VERTEX.y * (2.0 * radius + stretch * dl) + perp * VERTEX.x * 2.0 * radius;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = lv;  // -1..1 across, -1..1 along the (stretched) length
	float n = vnoise(p * 3.0 + vec2(seed * 7.0, seed * 3.0));            // this lobe's own ragged shape
	float n2 = vnoise(p * 6.0 + vec2(-seed * 5.0, age * 2.0 + seed));   // slow churn
	float d = length(p) + 0.45 * (n - 0.5) + 0.15 * (n2 - 0.5);
	float hot_t = clamp(age / hot_share, 0.0, 1.0);
	float cool_t = clamp((age - hot_share) / (1.0 - hot_share), 0.0, 1.0);
	// hot core: shrinks and dims through the hot phase
	float core = (1.0 - smoothstep(0.2, 0.8 - 0.35 * hot_t, d)) * (1.0 - hot_t);
	float heat = clamp((1.0 - d) * 1.3 * (1.0 - hot_t) + 0.2 * (n - 0.5), 0.0, 1.0);
	vec3 c = mix(orange, amber, smoothstep(0.2, 0.55, heat));
	c = mix(c, hot, smoothstep(0.75, 0.98, heat));
	// soot rim: around the core while it burns, the whole lobe once it is out
	float rim = (1.0 - smoothstep(0.6, 1.0, d)) * smoothstep(0.05, 0.4, d + 0.4 * hot_t);
	float soot_a = rim * mix(0.3, 0.55, hot_t) * (1.0 - cool_t);
	// then a thin grey wisp that thins out
	float wisp_a = (1.0 - smoothstep(0.1, 0.9, d)) * 0.28 * smoothstep(0.0, 0.25, cool_t) * (1.0 - cool_t);
	float a = clamp(soot_a + wisp_a, 0.0, 1.0);
	vec3 dark = mix(soot, wisp, cool_t) * a;
	ALBEDO = c * energy * (0.5 + 0.5 * size) * core + dark;
	ALPHA = a;
}
"""

# Per instance, not static: a static Shader would hold its RID past the
# renderer's teardown at quit (the same reason v1 kept its texture per instance).
var _jet_shader: Shader
var _lobe_shader: Shader

var enabled := true:
	set(v):
		enabled = v
		set_process(v)
		if not v:
			_clear()

## FIRE on every car, GHOST on the bone car (see the header).
var style: Style = Style.FIRE
## Ghost style: 0 cruise, 1 afterburner (longer flame, shock diamonds).
var afterburner := 0.0

## Bursts shown so far, the biggest, and how many were upshift flames (tests, tuning).
var bursts := 0
var max_size := 0.0
var upshift_bursts := 0
## Lobes spat so far (tests).
var lobes_spawned := 0
## The jets, two per tip: [tip0 facing, tip0 cross, tip1 facing, ...] (tests).
var jets: Array[MeshInstance3D] = []
## Smoothed throttle, 0..1: what the brightness follows.
var drive := 0.0
## Stepped time, s: advances by STEP at a time (tests).
var tick := 0.0

var _car: Vehicle
var _audio: EngineAudio
var _tips: Array = []          # [{pos, dir}] in car space
var _jet_mats: Array[ShaderMaterial] = []  # [facing, cross]
var _jet_left := 0.0
var _jet_size := 0.0
var _lobes: Array = []         # [{mi, mat, vel, life, r0, dir, speed}]
var _next_lobe := 0
var _light: OmniLight3D
var _light_left := 0.0
var _light_peak := 0.0
var _queue: Array = []         # [[show_at_s, size, kind]]
var _clock := 0.0
var _step_acc := 0.0
var _rng := RandomNumberGenerator.new()
var _was_up_shifting := false
var _pop_wait := 0.0           # carless-synth pop timer (traffic)
var _steady_on := false

func _init(car: Vehicle) -> void:
	_car = car
	name = "ExhaustFlames"

func _ready() -> void:
	_rng.seed = 2206 + get_instance_id() % 997
	for c in _car.get_children():
		if c is EngineAudio:
			_audio = c
	var raw: Array = [Vector3(0.0, 0.3, 2.3)]
	var vis: Node3D = _car.get("chassis_visual")
	if vis != null and vis.has_meta("exhaust_tips"):
		raw = vis.get_meta("exhaust_tips")
	for tip in raw:
		# TestCarBuilder gives Vector3 tips; P1CoupeBuilder gives {pos, dir, r}.
		var pos: Vector3 = tip.pos if tip is Dictionary else tip
		var out: Vector3 = tip.dir if tip is Dictionary else Vector3(0.0, 0.0, 1.0)
		_tips.append({"pos": pos + out * 0.04, "dir": out.normalized()})  # +Z is the tail
	_jet_shader = _shader(JET_SHADER)
	_lobe_shader = _shader(LOBE_SHADER)
	for strip in 2:
		var m := _material(_jet_shader)
		m.set_shader_parameter("cross_strip", float(strip))
		_jet_mats.append(m)
	for tip in _tips:
		for strip in 2:
			var mi := _quad(_jet_mats[strip])
			mi.position = tip.pos
			mi.basis = _basis_along(tip.dir)
			# The vertex shader stretches the quad; give the culler a box that fits.
			mi.custom_aabb = AABB(Vector3(-0.6, -0.6, -0.6), Vector3(1.2, 1.2, GHOST_JET_LEN.y + 1.2))
			add_child(mi)
			jets.append(mi)
	for i in POOL:
		_lobes.append(_world_quad(_lobe_shader))
	_light = OmniLight3D.new()
	_light.light_color = LIGHT_COLOR
	_light.omni_range = LIGHT_RANGE
	_light.shadow_enabled = false
	_light.light_specular = 0.2
	var mid := Vector3.ZERO
	for tip in _tips:
		mid += tip.pos
	_light.position = mid / maxf(_tips.size(), 1) + Vector3(0.0, 0.1, 0.3)
	_light.visible = false
	add_child(_light)
	var spec: Variant = _car.get("spec")
	if spec is Dictionary and str(spec.get("fire_style", "")) == "ghost":
		set_style(Style.GHOST)
	else:
		_apply_colours()
	enabled = enabled

## Switch the colour set and jet behaviour (see the header).
func set_style(s: Style) -> void:
	style = s
	_apply_colours()
	if style != Style.GHOST:
		_steady_on = false
		if _jet_left <= 0.0:
			for j in jets:
				j.visible = false

## Ghost style: 0 cruise, 1 afterburner. Ignored on FIRE.
func set_afterburner(x: float) -> void:
	afterburner = clampf(x, 0.0, 1.0)

func _apply_colours() -> void:
	var ghost := style == Style.GHOST
	var mats: Array = _jet_mats.duplicate()
	for l in _lobes:
		mats.append(l.mat)
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("hot", GHOST_HOT if ghost else HOT)
		(m as ShaderMaterial).set_shader_parameter("amber", GHOST_MID if ghost else AMBER)
		(m as ShaderMaterial).set_shader_parameter("orange", GHOST_EDGE if ghost else ORANGE)
	for l in _lobes:
		(l.mat as ShaderMaterial).set_shader_parameter("soot", GHOST_SOOT if ghost else SOOT)
	if _light != null:
		_light.light_color = GHOST_LIGHT if ghost else LIGHT_COLOR

## The flame setting (0..1) of this car's exhaust tune, read from its spec.
func flame_setting() -> float:
	var spec: Variant = _car.get("spec")
	if spec is Dictionary and spec.get("exhaust") is Dictionary:
		return clampf(float(spec.exhaust.get("flame", 0.0)), 0.0, 1.0)
	return 0.0

## Lobes per tip for a burst of this size: 1 at 0.1, 2 from 0.34, 3 from 0.67.
static func lobes_for(size: float) -> int:
	return clampi(1 + int(clampf(size, 0.0, 1.0) * (LOBES_MAX - 0.01)), 1, LOBES_MAX)

## Show a burst of this size (0..1) now. Tests and a garage preview call it
## directly; everything in game goes through queue_burst().
func flash(size: float, kind: int = Kind.POP) -> void:
	size = clampf(size, 0.0, 1.0)
	if size <= 0.0:
		return
	bursts += 1
	if kind == Kind.UPSHIFT:
		upshift_bursts += 1
	max_size = maxf(max_size, size)
	_jet_size = maxf(_jet_size if _jet_left > 0.0 else 0.0, size)
	_jet_left = JET_LIFE * (1.0 + 0.3 * size)
	var seed_v := _rng.randf() * 10.0
	for m in _jet_mats:
		m.set_shader_parameter("seed", seed_v)
		m.set_shader_parameter("jet_len", lerpf(JET_LEN.x, JET_LEN.y, size))
		m.set_shader_parameter("jet_width", lerpf(JET_WIDTH.x, JET_WIDTH.y, size))
		m.set_shader_parameter("size", _jet_size)
		m.set_shader_parameter("energy", JET_ENERGY * glow())
		m.set_shader_parameter("burst", 1.0)
		m.set_shader_parameter("diamonds", 0.0)
	for j in jets:
		j.visible = true
	var vel := _car.linear_velocity
	var speed := vel.length()
	var travel := vel / speed if speed > 0.5 else -(_car.global_transform.basis * Vector3(0.0, 0.0, 1.0))
	var n := lobes_for(size)
	for tip in _tips:
		var g: Transform3D = _car.global_transform
		var out: Vector3 = g.basis * tip.dir
		var side: Vector3 = g.basis * Vector3(1.0, 0.0, 0.0)
		for i in n:
			# the first lobe right at the tongue's end, the rest a little further out and scattered
			var along := lerpf(JET_LEN.x, JET_LEN.y, size) * (0.5 + 0.35 * i) + 0.1 * _rng.randf()
			var at: Vector3 = g * tip.pos + out * along + side * (0.1 * (_rng.randf() - 0.5) * i) + Vector3.UP * 0.05 * i
			var spit := out * LOBE_SPIT * (0.6 + 0.8 * _rng.randf()) + Vector3.UP * LOBE_RISE
			var r0 := lerpf(LOBE_RADIUS.x, LOBE_RADIUS.y, size) * (0.75 + 0.5 * _rng.randf())
			_spawn(_lobes[_next_lobe], at, vel * LOBE_CARRY + spit, r0, size, travel, speed)
			_next_lobe = (_next_lobe + 1) % POOL
			lobes_spawned += 1
	_light_peak = maxf(_light_peak if _light_left > 0.0 else 0.0, size)
	_light_left = LIGHT_LIFE
	_light.visible = true
	burst_shown.emit(kind, size)

## Show a burst after `delay` seconds (the sync hook: line the fire up with the
## sound that goes with it).
func queue_burst(size: float, kind: int = Kind.POP, delay: float = VISUAL_DELAY) -> void:
	if size <= 0.0 or _queue.size() >= MAX_QUEUED:
		return
	_queue.append([_clock + delay, size, kind])

func is_showing() -> bool:
	return _jet_left > 0.0 or _steady_on

## Fire still on screen anywhere (jet, hot lobes, light; not the soot/wisp).
func is_active() -> bool:
	if _jet_left > 0.0 or _light_left > 0.0 or _steady_on:
		return true
	for l in _lobes:
		if l.life > LOBE_LIFE * (1.0 - LOBE_HOT):
			return true
	return false

## Lobes alive in any phase (tests).
func live_lobes() -> int:
	var n := 0
	for l in _lobes:
		if l.life > 0.0:
			n += 1
	return n

## Brightness multiplier now: GLOW_FLOOR at no throttle, 1 at full.
func glow() -> float:
	return lerpf(GLOW_FLOOR, 1.0, drive)

func _process(delta: float) -> void:
	_clock += delta
	_follow_throttle(delta)
	var flame := flame_setting()
	if _audio != null:
		var f: float = _audio.take_flames()
		if f > 0.0:
			# The block was rendered flames_late ago (EngineAudio renders on a
			# worker and hands its flames out a frame later), so wait that much less.
			queue_burst(f, Kind.POP, maxf(VISUAL_DELAY - _audio.flames_late, 0.0))
	elif flame > 0.0:
		_simulate_pops(delta, flame)
	_watch_upshift(flame)
	while not _queue.is_empty() and _queue[0][0] <= _clock:
		var q: Array = _queue.pop_front()
		flash(q[1], q[2])
	_animate(delta)

## An upshift with the foot down, on a high-flame car: the ignition cut spits
## fire. GEVP raises is_up_shifting for the shift's length.
func _watch_upshift(flame: float) -> void:
	var up: bool = _car.is_up_shifting
	if up and not _was_up_shifting and flame >= UPSHIFT_FLAME_MIN and upshift_spits(_car):
		queue_burst(flame * (0.8 + 0.2 * _rng.randf()), Kind.UPSHIFT)
	_was_up_shifting = up

## The upshift law, shared with EngineAudio's upshift bang so sound and fire
## agree: foot down and revs up when the shift starts. GEVP raises
## is_up_shifting in auto, semi and manual alike.
static func upshift_spits(car: Vehicle) -> bool:
	var rpm_norm := clampf((car.motor_rpm - car.idle_rpm) / maxf(car.max_rpm - car.idle_rpm, 1.0), 0.0, 1.0)
	return car.throttle_input > 0.6 and rpm_norm > 0.5

## A car with no EngineAudio (traffic): the synth's pop laws (engine_synth.gd
## render(): overrun rate, limiter bangs, the anti-lag volley), run per frame
## from the car's own state. No sound; nothing heard to wait for, but the same
## queue keeps the look identical.
func _simulate_pops(delta: float, flame: float) -> void:
	var spec: Dictionary = _car.get("spec")
	var ex: Dictionary = spec.get("exhaust", {})
	var pops := float(ex.get("pops", 0.0))
	var anti_lag := ExhaustTune.anti_lag_live(spec)
	var rpm_norm := clampf((_car.motor_rpm - _car.idle_rpm) / maxf(_car.max_rpm - _car.idle_rpm, 1.0), 0.0, 1.0)
	var rate := 0.0
	if _car.throttle_amount < 0.08 and rpm_norm > 0.3:
		rate = pops * (3.0 + 22.0 * rpm_norm)
		if anti_lag:
			rate = maxf(rate, EngineSynth.ANTI_LAG_RATE)
	elif _car.motor_is_redline:
		rate = pops * 10.0
	if rate <= 0.0:
		_pop_wait = 0.0
		return
	_pop_wait -= delta
	if _pop_wait <= 0.0:
		queue_burst(flame * (0.4 + 0.6 * _rng.randf()))
		_pop_wait = (0.3 + 1.4 * _rng.randf()) / rate

## Rise fast, fall over THROTTLE_RELEASE. throttle_amount is the pedal the
## engine sees (the keyboard's 0/1 already ramped by the car), as audio uses.
func _follow_throttle(delta: float) -> void:
	var target := clampf(_car.throttle_amount, 0.0, 1.0)
	var rate := 1.0 / (THROTTLE_ATTACK if target > drive else THROTTLE_RELEASE)
	drive = move_toward(drive, target, rate * delta)

func _animate(delta: float) -> void:
	var g := glow()
	# The light is two frames long: per frame.
	if _light_left > 0.0:
		_light_left -= delta
		var k := clampf(_light_left / LIGHT_LIFE, 0.0, 1.0)
		_light.light_energy = LIGHT_ENERGY * g * (0.3 + 0.7 * _light_peak) * k * (0.8 + 0.4 * _rng.randf())
		if _light_left <= 0.0:
			_light.visible = false
	# Jets and lobes: in steps of STEP (the chunky look).
	_step_acc += delta
	if _step_acc < STEP:
		return
	var dt := _step_acc
	_step_acc = 0.0
	tick += dt
	if _jet_left > 0.0:
		_jet_left -= dt
		if _jet_left <= 0.0:
			if not _steady_on:
				for j in jets:
					j.visible = false
		else:
			for m in _jet_mats:
				m.set_shader_parameter("burst", _jet_left / (JET_LIFE * (1.0 + 0.3 * _jet_size)))
				m.set_shader_parameter("energy", JET_ENERGY * g)
				m.set_shader_parameter("tick", tick)
	if style == Style.GHOST:
		_steady_jet(g)
	for l in _lobes:
		_age(l, dt, g)

## Ghost style: the jet burns whenever the throttle is down; longer with the
## afterburner and banded with shock diamonds. A burst's own jet shape takes
## over while it plays (it is the same quads).
func _steady_jet(g: float) -> void:
	var on := drive > 0.05
	if on != _steady_on:
		_steady_on = on
		if not on and _jet_left <= 0.0:
			for j in jets:
				j.visible = false
	if not on or _jet_left > 0.0:
		return
	var flicker := 0.85 + 0.15 * _rng.randf()
	for m in _jet_mats:
		m.set_shader_parameter("burst", flicker)
		m.set_shader_parameter("size", lerpf(0.5, 1.0, afterburner))
		m.set_shader_parameter("jet_len", lerpf(GHOST_JET_LEN.x, GHOST_JET_LEN.y, afterburner) * (0.6 + 0.4 * drive))
		m.set_shader_parameter("jet_width", lerpf(GHOST_JET_WIDTH.x, GHOST_JET_WIDTH.y, afterburner))
		m.set_shader_parameter("energy", JET_ENERGY * g)
		m.set_shader_parameter("diamonds", afterburner)
		m.set_shader_parameter("tick", tick)
	for j in jets:
		j.visible = true

func _age(p: Dictionary, dt: float, g: float) -> void:
	if p.life <= 0.0:
		return
	p.life -= dt
	var mi: MeshInstance3D = p.mi
	if p.life <= 0.0:
		mi.visible = false
		return
	var age: float = 1.0 - p.life / LOBE_LIFE
	p.vel *= exp(-3.0 * dt)  # air drag
	mi.global_position += p.vel * dt
	var m: ShaderMaterial = p.mat
	m.set_shader_parameter("age", age)
	m.set_shader_parameter("radius", p.r0 * lerpf(1.0, LOBE_GROW, sqrt(age)))
	# drawn out along the car's travel as it pulls away
	m.set_shader_parameter("stretch", minf(p.speed * LOBE_STREAK, LOBE_STREAK_MAX) * smoothstep(0.0, 0.4, age))
	if age < LOBE_HOT:
		m.set_shader_parameter("energy", LOBE_ENERGY * g)

func _spawn(p: Dictionary, at: Vector3, vel: Vector3, r0: float, size: float, travel: Vector3, speed: float) -> void:
	var mi: MeshInstance3D = p.mi
	mi.global_position = at
	mi.visible = true
	p.vel = vel
	p.life = LOBE_LIFE
	p.r0 = r0
	p.speed = speed
	var m: ShaderMaterial = p.mat
	m.set_shader_parameter("age", 0.0)
	m.set_shader_parameter("seed", _rng.randf() * 10.0)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("radius", r0)
	m.set_shader_parameter("stretch", 0.0)
	m.set_shader_parameter("stretch_dir", travel)
	m.set_shader_parameter("hot_share", LOBE_HOT)
	m.set_shader_parameter("energy", LOBE_ENERGY * glow())

## Floating-origin recentre: the world moved by offset; move the shed lobes
## with it (they are top-level, outside the car).
func shift_world(offset: Vector3) -> void:
	for p in _lobes:
		if p.life > 0.0:
			(p.mi as MeshInstance3D).global_position += offset

func _clear() -> void:
	_queue.clear()
	_jet_left = 0.0
	_light_left = 0.0
	_steady_on = false
	for j in jets:
		j.visible = false
	if _light != null:
		_light.visible = false
	for p in _lobes:
		p.life = 0.0
		(p.mi as MeshInstance3D).visible = false

func _quad(mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mi.mesh = quad
	mi.material_override = mat
	mi.layers = 1 << (CarFx.CAR_LAYER - 1)  # the blob shadow decal does not darken it
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi

func _world_quad(shader: Shader) -> Dictionary:
	var mat := _material(shader)
	var mi := _quad(mat)
	mi.top_level = true
	# the vertex shader sizes and stretches it; a box that holds the longest streak
	mi.custom_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3.0, 3.0, 3.0))
	add_child(mi)
	return {"mi": mi, "mat": mat, "vel": Vector3.ZERO, "life": 0.0, "r0": 0.1, "speed": 0.0}

func _material(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("hot", HOT)
	m.set_shader_parameter("amber", AMBER)
	m.set_shader_parameter("orange", ORANGE)
	return m

static func _shader(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s

## A basis whose +Z is `dir` (the jet shader stretches along +Z).
static func _basis_along(dir: Vector3) -> Basis:
	var z := dir.normalized()
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	return Basis(x, z.cross(x), z)
