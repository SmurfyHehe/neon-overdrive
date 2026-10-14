extends RefCounted
# Lamp wear (street life L1 + L2, 2026-10-14): the lamp row stops being a
# copy-paste. Per district a share of the street lamps is
#
#   dead   the head is dark and there is no pool: a gap in the row
#   buzz   a bad ballast: the head and its pool jitter between half and full
#          brightness and drop out for a beat now and then
#   swap   the council replaced this head with a cool-white one among the
#          district's sodium or amber lamps (never where the district is
#          already white)
#
# ZERO per-frame script work. Which lamp is which is a hash of the chunk,
# the side and the slot (a pooled chunk rebuilt later gets the same lamps,
# and the road's random sequence is untouched), written once per chunk as
# per-instance custom data on the "Lamps" and "LampPools" MultiMeshes:
#
#   r  1 = dead      g  1 = buzz      b  phase 0..1      a  1 = cool-white
#
# The lamp head and the pool each have one ShaderMaterial per light colour
# (head_mat / pool_mat, cached) that reads that data and TIME. The pool
# shader draws the same radial pool as the old StandardMaterial3D (additive,
# fading out from 110 to 170 m, no fog). Lamps with all-zero data (side
# streets, ramps, the signed U-turn pool) look exactly as before.
#
# NEON_LAMP_WEAR=0 in the environment turns it off (tests, benchmarks);
# NEON_LAMP_WEAR=heavy wears a quarter of the lamps each way (screenshots).

const Districts := preload("res://scripts/world/districts.gd")

## Per district, in percent of the street lamps: dead, buzzing, swapped to
## a cool-white head. Old and industrial areas are worst kept.
const WEAR := {
	"downtown":    {"dead": 3, "buzz": 5, "swap": 2},
	"residential": {"dead": 5, "buzz": 7, "swap": 6},
	"strip":       {"dead": 4, "buzz": 8, "swap": 3},
	"industrial":  {"dead": 8, "buzz": 10, "swap": 4},
	"old_town":    {"dead": 6, "buzz": 9, "swap": 8},
	"lofts":       {"dead": 5, "buzz": 6, "swap": 5},
	"hillside":    {"dead": 7, "buzz": 7, "swap": 4},
	"airport":     {"dead": 1, "buzz": 2, "swap": 0},
	"docks":       {"dead": 9, "buzz": 10, "swap": 3},
	"freeway":     {"dead": 2, "buzz": 3, "swap": 0},
	"canyon":      {"dead": 3, "buzz": 4, "swap": 0},
}
const DEFAULT := {"dead": 4, "buzz": 6, "swap": 3}
## Every district, when `heavy` is set: for judging the look by eye.
const HEAVY := {"dead": 25, "buzz": 25, "swap": 25}

## The head's brightness (unshaded albedo; above the glow threshold, so it
## blooms like the old emissive head did) and the colour of a dead head.
const HEAD_ENERGY := 4.0
const DEAD_COLOR := Color(0.09, 0.08, 0.07)
## The replacement head's colour: the district table's white lamp.
const SWAP_LIGHT := "white"
## Pools fade out between these distances (as the old material did).
const POOL_FADE := Vector2(110.0, 170.0)

static var enabled := true
static var heavy := false
static var _enabled_read := false
static var _head_mats := {}  # light -> ShaderMaterial
static var _pool_mats := {}  # light -> ShaderMaterial

static func _read_enabled() -> void:
	if _enabled_read:
		return
	_enabled_read = true
	if OS.has_environment("NEON_LAMP_WEAR"):
		var v := OS.get_environment("NEON_LAMP_WEAR")
		enabled = v != "0"
		heavy = v == "heavy"

## The wear of one street lamp, as the custom data the shaders read.
## slot: the lamp's slot in the chunk (0..3); light: the district's lamp
## colour (no swap where it is already white).
static func roll(chunk_index: int, side: int, slot: int, district: String, light: String) -> Color:
	_read_enabled()
	if not enabled:
		return Color(0.0, 0.0, 0.0, 0.0)
	var w: Dictionary = HEAVY if heavy else WEAR.get(district, DEFAULT)
	var r := posmod(hash([chunk_index, side, slot, "lamp wear"]), 1000)
	var dead := 1.0 if r < int(w.dead) * 10 else 0.0
	var buzz := 1.0 if dead == 0.0 and r < (int(w.dead) + int(w.buzz)) * 10 else 0.0
	var swap := 0.0
	if dead == 0.0 and light != SWAP_LIGHT:
		var r2 := posmod(hash([chunk_index, side, slot, "lamp swap"]), 1000)
		swap = 1.0 if r2 < int(w.swap) * 10 else 0.0
	var phase := float(posmod(hash([chunk_index, side, slot, "lamp phase"]), 97)) / 97.0
	return Color(dead, buzz, phase, swap)

static func is_dead(c: Color) -> bool:
	return c.r > 0.5

## Shared by both shaders: k is the lamp's brightness this frame.
const WEAR_GLSL := """
float hash1(float n) { return fract(sin(n) * 43758.5453); }
// A bad ballast: fast jitter between 55 % and full, and now and then out
// for a beat (about a third of 1.4 s windows).
float buzz(float t, float phase) {
	float fast = hash1(floor(t * 24.0) + phase * 97.0);
	float beat = hash1(floor(t * 0.7 + phase) + phase * 31.0);
	return step(0.3, beat) * mix(0.55, 1.0, fast);
}
float wear_k(vec4 c, float t) {
	return (1.0 - c.r) * mix(1.0, buzz(t, c.b), c.g);
}
"""

const HEAD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec3 color = vec3(1.0, 0.55, 0.2);
uniform vec3 alt_color = vec3(0.8, 0.88, 1.0);
uniform vec3 dead_color = vec3(0.09, 0.08, 0.07);
uniform float energy = 4.0;
varying float k;
varying float swap;
""" + WEAR_GLSL + """
void vertex() {
	k = wear_k(INSTANCE_CUSTOM, TIME);
	swap = INSTANCE_CUSTOM.a;
}
void fragment() {
	ALBEDO = mix(dead_color, mix(color, alt_color, swap) * energy, k);
}
"""

const POOL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, fog_disabled, cull_back;
uniform vec3 color = vec3(1.0, 0.55, 0.2);
uniform vec3 alt_color = vec3(0.8, 0.88, 1.0);
uniform float gain = 0.8;
uniform float alt_gain = 0.57;
uniform vec2 fade = vec2(110.0, 170.0);
varying float k;
varying float swap;
varying float depth;
""" + WEAR_GLSL + """
void vertex() {
	k = wear_k(INSTANCE_CUSTOM, TIME);
	swap = INSTANCE_CUSTOM.a;
	depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}
void fragment() {
	// the old radial gradient: 1 at the centre, 0.5 at 30 %, 0 at the rim
	float r = length(UV - vec2(0.5)) * 2.0;
	float a = r < 0.3 ? mix(1.0, 0.5, r / 0.3) : mix(0.5, 0.0, clamp((r - 0.3) / 0.7, 0.0, 1.0));
	float far = 1.0 - smoothstep(fade.x, fade.y, depth);
	vec3 c = mix(color * gain, alt_color * alt_gain, swap);
	ALBEDO = c * a * far * k;
}
"""

## The lamp head's material for a district light colour (cached).
static func head_mat(light: String) -> ShaderMaterial:
	if not _head_mats.has(light):
		var sh := Shader.new()
		sh.code = HEAD_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("color", _rgb(Districts.LIGHTS[light].color))
		m.set_shader_parameter("alt_color", _rgb(Districts.LIGHTS[SWAP_LIGHT].color))
		m.set_shader_parameter("dead_color", _rgb(DEAD_COLOR))
		m.set_shader_parameter("energy", HEAD_ENERGY)
		_head_mats[light] = m
	return _head_mats[light]

## The pool's material for a district light colour (cached). pool_boost:
## RoadChunkBuilder.POOL_BOOST, the table's pool strength to albedo.
static func pool_mat(light: String, pool_boost: float) -> ShaderMaterial:
	if not _pool_mats.has(light):
		var sh := Shader.new()
		sh.code = POOL_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("color", _rgb(Districts.LIGHTS[light].color))
		m.set_shader_parameter("alt_color", _rgb(Districts.LIGHTS[SWAP_LIGHT].color))
		m.set_shader_parameter("gain", float(Districts.LIGHTS[light].pool) * pool_boost)
		m.set_shader_parameter("alt_gain", float(Districts.LIGHTS[SWAP_LIGHT].pool) * pool_boost)
		m.set_shader_parameter("fade", POOL_FADE)
		_pool_mats[light] = m
	return _pool_mats[light]

static func _rgb(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)
