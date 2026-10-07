extends Node3D
class_name ExhaustFlames

# Exhaust flames v2 (2026-10-07, Roy picked Option A of
# exhaust-flames-research-2026-10-07.md: shader quads). Replaces v1's single
# billboard blob (effects pack v1, 2026-10-06).
#
# One burst is four things, all hidden while idle (no draw calls, no light):
# - a JET per exhaust tip: a quad stretched along the pipe axis and turned
#   about that axis to face the camera (vertex shader), noise-scrolled, white
#   hot at the nozzle through amber to orange at the tip;
# - a BALL: a round fireball left in world space at the tip, so as the car
#   drives on it trails behind, swelling and cooling from amber to orange;
# - a dark SMOKE puff, also in world space, that lingers after the fire;
# - one pooled OmniLight flash per car (no shadows), amber, a few frames long.
# Colours: white-hot -> amber #FFC066 -> sodium orange #FF8A1F (Amber vs.
# Dusk). No blue core, no magenta, no cyan. Pushed past 1.0 so the tight glow
# pass picks the hot part up.
#
# Triggers:
# - the synth's flame events (EngineSynth.take_flames(): overrun pops, limiter
#   bangs, the anti-lag volley), on a car with EngineAudio (the player);
# - the same laws run here from the car's own state on a car without one
#   (traffic: TrafficManager only adds this node to a car whose spec has a
#   flame value above 0, today only the C3 interceptor's preset at 0.05);
# - an upshift at full throttle, only when the car's flame setting is at least
#   UPSHIFT_FLAME_MIN (Roy, 2026-10-07: upshift flames only on high-flame cars).
# All of it is cosmetic: nothing in the sim reads it.
#
# Brightness follows the throttle (2026-10-07): `drive` tracks the car's
# throttle_amount, rising at once and falling over THROTTLE_RELEASE when the
# foot comes off, and scales the jet, fireball and light energy between
# GLOW_FLOOR and 1. The floor is not 0 because most flames are overrun pops,
# which only fire off throttle: a coasting pop is dim, not gone. Only the
# energy changes, so the heat colours stay as they are and no draw is added.
#
# Sync: the synth renders audio BUFFER ahead of what is heard, so an event
# taken from it now is heard VISUAL_DELAY later. Every burst goes through a
# small delay queue (queue_burst) and shows when its sound plays. The new
# exhaust/crackle sound can use the same hook: call queue_burst() with the
# delay its own audio needs, or listen to `burst_shown`.
#
# Tips come from the chassis visual's "exhaust_tips" meta (TestCarBuilder or
# P1CoupeBuilder); a car without the meta gets one centre pipe.

signal burst_shown(kind: int, size: float)

enum Kind { POP, UPSHIFT }

## Seconds between the synth handing out a flame event and it being heard
## (EngineAudio.BUFFER_SECS of audio is queued ahead): the visual waits as long.
const VISUAL_DELAY := 0.06
## Upshift flames only on cars whose flame setting is at least this.
const UPSHIFT_FLAME_MIN := 0.4
const MAX_QUEUED := 16

const JET_LIFE := 0.12      # s
const JET_LEN := Vector2(0.3, 0.9)     # m at flame size 0 / 1
const JET_WIDTH := Vector2(0.12, 0.26) # m
const BALL_LIFE := 0.32
const BALL_RADIUS := Vector2(0.08, 0.2)  # m at birth, size 0 / 1
const BALL_GROW := 1.6      # radius multiplier by the end of its life
const BALL_SPEED := 2.5     # m/s out of the pipe, on top of the car's velocity x BALL_CARRY
const BALL_CARRY := 0.5     # the ball keeps half the car's speed: it trails
const SMOKE_LIFE := 0.9
const SMOKE_RADIUS := Vector2(0.12, 0.25)
const SMOKE_GROW := 2.4
const SMOKE_RISE := 0.5     # m/s
const POOL := 4             # balls and smoke puffs per car
const LIGHT_LIFE := 0.08
const LIGHT_ENERGY := 2.0
const LIGHT_RANGE := 4.0
const LIGHT_COLOR := Color(1.0, 0.68, 0.32)
const JET_ENERGY := 1.7
const BALL_ENERGY := 1.3
## Brightness at zero throttle, as a share of full (see the header).
const GLOW_FLOOR := 0.4
## Seconds for `drive` to fall from 1 to 0 after the throttle lifts.
const THROTTLE_RELEASE := 0.25
## Seconds for `drive` to rise from 0 to 1 (the foot going down shows at once).
const THROTTLE_ATTACK := 0.05

const HOT := Color(1.0, 0.95, 0.85)    # white-hot, warm
const AMBER := Color(1.0, 0.753, 0.4)  # #FFC066
const ORANGE := Color(1.0, 0.541, 0.122)  # #FF8A1F

const JET_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform, fog_disabled;
uniform float burst = 0.0;      // 1 -> 0 over the jet's life
uniform float size = 0.5;       // flame size 0..1
uniform float jet_len = 0.8;    // m
uniform float jet_width = 0.25; // m
uniform float seed = 0.0;
uniform float energy = 1.7;
uniform vec3 hot : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 amber : source_color = vec3(1.0, 0.753, 0.4);
uniform vec3 orange : source_color = vec3(1.0, 0.541, 0.122);
varying vec2 jv;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	// Quad x in [-0.5, 0.5] across, y in [-0.5, 0.5] along. Stretch it along
	// the node's +Z (the pipe axis) and turn it about that axis to face the eye.
	vec3 o = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 ax = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	vec3 side = cross(ax, normalize(o));
	side = length(side) < 0.001 ? vec3(1.0, 0.0, 0.0) : normalize(side);
	float t = VERTEX.y + 0.5;
	jv = vec2(VERTEX.x * 2.0, t);
	VERTEX = o + ax * t * jet_len + side * VERTEX.x * jet_width;
	NORMAL = normalize(cross(side, ax));
}

void fragment() {
	float t = jv.y;      // 0 at the nozzle, 1 at the tip
	float a = abs(jv.x); // 0 on the axis, 1 at the quad edge
	float tm = TIME * 18.0 + seed * 13.0;
	float n = vnoise(vec2(jv.x * 3.0 + seed, t * 6.0 - tm));
	float n2 = vnoise(vec2(jv.x * 7.0 - seed, t * 13.0 - tm * 1.7));
	// a narrow neck at the nozzle that swells, then a ragged, shrinking tip
	float reach = mix(0.55, 1.0, burst) * (0.75 + 0.35 * n);
	float w = mix(0.35, 1.0, sqrt(clamp(t / 0.35, 0.0, 1.0))) * (1.0 - smoothstep(reach * 0.55, reach, t));
	float body = 1.0 - smoothstep(w * 0.55, w, a + 0.25 * (n2 - 0.5));
	float heat = clamp((1.0 - t / max(reach, 0.01)) * (1.0 - a / max(w, 0.01)) * 1.4 + 0.25 * (n - 0.5), 0.0, 1.0);
	vec3 c = mix(orange, amber, smoothstep(0.15, 0.5, heat));
	c = mix(c, hot, smoothstep(0.7, 0.95, heat));
	float k = body * smoothstep(0.0, 0.08, t) * clamp(burst * 1.6, 0.0, 1.0);
	ALBEDO = c * energy * (0.45 + 0.55 * size) * (0.35 + 0.65 * heat) * k;
	ALPHA = k;
}
"""

const BALL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float age = 1.0;  // 0 at birth -> 1 dead
uniform float size = 0.5;
uniform float seed = 0.0;
uniform float energy = 1.3;
uniform vec3 hot : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 amber : source_color = vec3(1.0, 0.753, 0.4);
uniform vec3 orange : source_color = vec3(1.0, 0.541, 0.122);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	// billboard
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float n = vnoise(p * 3.0 + vec2(seed * 7.0, -age * 5.0));
	float d = length(p) + 0.35 * (n - 0.5);
	float body = 1.0 - smoothstep(0.55, 1.0, d);
	float heat = clamp((1.0 - d) * 1.3 * (1.0 - age) + 0.2 * (n - 0.5), 0.0, 1.0);
	vec3 c = mix(orange, amber, smoothstep(0.2, 0.55, heat));
	c = mix(c, hot, smoothstep(0.75, 0.98, heat));
	float k = body * (1.0 - age) * (1.0 - age);
	ALBEDO = c * energy * (0.5 + 0.5 * size) * k;
	ALPHA = k;
}
"""

const SMOKE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform float age = 1.0;
uniform float seed = 0.0;
uniform float density = 0.45;
uniform vec3 tint : source_color = vec3(0.07, 0.065, 0.065);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float n = vnoise(p * 2.5 + vec2(seed * 5.0, age * 2.0));
	float d = length(p) + 0.4 * (n - 0.5);
	float body = 1.0 - smoothstep(0.3, 1.0, d);
	// fades in over the first 15% (it starts behind the fireball), then out
	float k = body * smoothstep(0.0, 0.15, age) * (1.0 - age);
	ALBEDO = tint;
	ALPHA = k * density;
}
"""

# Per instance, not static: a static Shader would hold its RID past the
# renderer's teardown at quit (the same reason v1 kept its texture per instance).
var _jet_shader: Shader
var _ball_shader: Shader
var _smoke_shader: Shader

var enabled := true:
	set(v):
		enabled = v
		set_process(v)
		if not v:
			_clear()

## Bursts shown so far, the biggest, and how many were upshift flames (tests, tuning).
var bursts := 0
var max_size := 0.0
var upshift_bursts := 0
## The jets, one per tip (tests).
var jets: Array[MeshInstance3D] = []
## Smoothed throttle, 0..1: what the brightness follows.
var drive := 0.0

var _car: Vehicle
var _audio: EngineAudio
var _tips: Array = []          # [{pos, dir}] in car space
var _jet_mat: ShaderMaterial
var _jet_left := 0.0
var _jet_size := 0.0
var _balls: Array = []         # [{mi, mat, vel, life, r0}]
var _smokes: Array = []
var _next_ball := 0
var _next_smoke := 0
var _light: OmniLight3D
var _light_left := 0.0
var _light_peak := 0.0
var _queue: Array = []         # [[show_at_s, size, kind]]
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
var _was_up_shifting := false
var _pop_wait := 0.0           # carless-synth pop timer (traffic)

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
	_ball_shader = _shader(BALL_SHADER)
	_smoke_shader = _shader(SMOKE_SHADER)
	_jet_mat = _material(_jet_shader)
	for tip in _tips:
		var mi := _quad(_jet_mat)
		mi.position = tip.pos
		mi.basis = _basis_along(tip.dir)
		# The vertex shader stretches the quad; give the culler a box that fits.
		mi.custom_aabb = AABB(Vector3(-0.6, -0.6, -0.6), Vector3(1.2, 1.2, JET_LEN.y + 1.2))
		add_child(mi)
		jets.append(mi)
	for i in POOL:
		_balls.append(_world_quad(_ball_shader))
		_smokes.append(_world_quad(_smoke_shader))
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
	enabled = enabled

## The flame setting (0..1) of this car's exhaust tune, read from its spec.
func flame_setting() -> float:
	var spec: Variant = _car.get("spec")
	if spec is Dictionary and spec.get("exhaust") is Dictionary:
		return clampf(float(spec.exhaust.get("flame", 0.0)), 0.0, 1.0)
	return 0.0

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
	_jet_mat.set_shader_parameter("seed", _rng.randf() * 10.0)
	_jet_mat.set_shader_parameter("jet_len", lerpf(JET_LEN.x, JET_LEN.y, size))
	_jet_mat.set_shader_parameter("jet_width", lerpf(JET_WIDTH.x, JET_WIDTH.y, size))
	_jet_mat.set_shader_parameter("size", _jet_size)
	_jet_mat.set_shader_parameter("energy", JET_ENERGY * glow())
	for j in jets:
		j.visible = true
	var vel := _car.linear_velocity
	for tip in _tips:
		var g: Transform3D = _car.global_transform
		var at: Vector3 = g * (tip.pos + tip.dir * lerpf(JET_LEN.x, JET_LEN.y, size) * 0.6)
		var out: Vector3 = g.basis * tip.dir
		_spawn(_balls[_next_ball], at, vel * BALL_CARRY + out * BALL_SPEED, BALL_LIFE, lerpf(BALL_RADIUS.x, BALL_RADIUS.y, size), size)
		_next_ball = (_next_ball + 1) % POOL
		if size >= 0.15:
			_spawn(_smokes[_next_smoke], at, vel * 0.2 + out * 1.0 + Vector3.UP * SMOKE_RISE, SMOKE_LIFE, lerpf(SMOKE_RADIUS.x, SMOKE_RADIUS.y, size), size)
			_next_smoke = (_next_smoke + 1) % POOL
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
	return _jet_left > 0.0

## Fire still on screen anywhere (jet, balls, light; not the smoke).
func is_active() -> bool:
	if _jet_left > 0.0 or _light_left > 0.0:
		return true
	for b in _balls:
		if b.life > 0.0:
			return true
	return false

## Brightness multiplier now: GLOW_FLOOR at no throttle, 1 at full.
func glow() -> float:
	return lerpf(GLOW_FLOOR, 1.0, drive)

func _process(delta: float) -> void:
	_clock += delta
	_follow_throttle(delta)
	var flame := flame_setting()
	if _audio != null:
		var f: float = _audio.synth.take_flames()
		if f > 0.0:
			queue_burst(f)
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
	var anti_lag := float(ex.get("anti_lag", 0.0)) >= 0.5
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
	if _jet_left > 0.0:
		_jet_left -= delta
		if _jet_left <= 0.0:
			for j in jets:
				j.visible = false
		else:
			_jet_mat.set_shader_parameter("burst", _jet_left / (JET_LIFE * (1.0 + 0.3 * _jet_size)))
			_jet_mat.set_shader_parameter("energy", JET_ENERGY * g)
	if _light_left > 0.0:
		_light_left -= delta
		var k := clampf(_light_left / LIGHT_LIFE, 0.0, 1.0)
		_light.light_energy = LIGHT_ENERGY * g * (0.3 + 0.7 * _light_peak) * k * (0.8 + 0.4 * _rng.randf())
		if _light_left <= 0.0:
			_light.visible = false
	for b in _balls:
		_age(b, delta, BALL_GROW)
		if b.life > 0.0:
			(b.mat as ShaderMaterial).set_shader_parameter("energy", BALL_ENERGY * g)
	for s in _smokes:
		_age(s, delta, SMOKE_GROW)

func _age(p: Dictionary, delta: float, grow: float) -> void:
	if p.life <= 0.0:
		return
	p.life -= delta
	var mi: MeshInstance3D = p.mi
	if p.life <= 0.0:
		mi.visible = false
		return
	var age: float = 1.0 - p.life / p.total
	p.vel *= exp(-3.0 * delta)  # air drag
	mi.global_position += p.vel * delta
	var r: float = p.r0 * lerpf(1.0, grow, sqrt(age))
	mi.scale = Vector3(r, r, r) * 2.0
	(p.mat as ShaderMaterial).set_shader_parameter("age", age)

func _spawn(p: Dictionary, at: Vector3, vel: Vector3, life: float, r0: float, size: float) -> void:
	var mi: MeshInstance3D = p.mi
	mi.global_position = at
	mi.scale = Vector3(r0, r0, r0) * 2.0
	mi.visible = true
	p.vel = vel
	p.life = life
	p.total = life
	p.r0 = r0
	var m: ShaderMaterial = p.mat
	m.set_shader_parameter("age", 0.0)
	m.set_shader_parameter("seed", _rng.randf() * 10.0)
	if m.shader == _ball_shader:
		m.set_shader_parameter("size", size)
		m.set_shader_parameter("energy", BALL_ENERGY * glow())

## Floating-origin recentre: the world moved by offset; move the loose balls and
## smoke with it (they are top-level, outside the car).
func shift_world(offset: Vector3) -> void:
	for p in _balls + _smokes:
		if p.life > 0.0:
			(p.mi as MeshInstance3D).global_position += offset

func _clear() -> void:
	_queue.clear()
	_jet_left = 0.0
	_light_left = 0.0
	for j in jets:
		j.visible = false
	if _light != null:
		_light.visible = false
	for p in _balls + _smokes:
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
	mi.custom_aabb = AABB(Vector3(-1.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))
	add_child(mi)
	return {"mi": mi, "mat": mat, "vel": Vector3.ZERO, "life": 0.0, "total": 1.0, "r0": 0.3}

func _material(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	if shader != _smoke_shader:
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
