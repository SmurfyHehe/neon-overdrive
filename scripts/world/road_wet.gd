extends RefCounted

# The road surface in the wet (S1a, 2026-10-10). Two shaders, one knob:
#
# 1. The asphalt shader every road strip, shoulder and sidewalk is drawn
#    with (RoadChunkBuilder._asphalt_mat, Junction's crossing). Dry it is the
#    old StandardMaterial3D look: the seamless grain texture through a
#    2-colour ramp, roughness 0.9. One `wetness` uniform (0 dry .. 1 soaked)
#    darkens the albedo, drops the roughness so the moon and lamps draw a
#    glossy highlight, and adds a Fresnel sheen: the horizon glow mirrored in
#    the film of water, strongest at a grazing angle, which is how a wet road
#    looks far ahead. Snow later gets its own uniform on this same shader
#    (brighten + roughen), which is why the surface lives here and not in
#    the chunk builder.
#
# 2. The puddle shader: flat quads on the tarmac where scripts/world/puddles.gd
#    says standing water lies, so what the tyres feel (wet_grip.gd) is what
#    the eye sees. The chunk builder places one MultiMesh per chunk from the
#    same seeded list the grip code reads, when the chunk is built, so there
#    is no per-frame CPU. A puddle is a dark mirror: near-black water that
#    turns into the sky's colour at a grazing angle (Fresnel), so deep ones
#    shine from far off and the player can lift early. Shallow ones mirror
#    half as much. `fill` (0 empty .. 1 full) fades them in with the rain.
#
# Cost: the asphalt shader is a few extra ALU per road pixel (about 0.2 ms
# GPU over the old material at 1080p, measured with benchmark --wet=1 vs 0);
# puddles are 0 to 3 quads per chunk, blended, a few metres across.
#
# Low graphics preset: set_reflections(false) zeroes both sheens (`sheen_gain`
# and `mirror_gain`), so the road still darkens and the puddles still show
# as dark patches (the grip cue stays), but nothing is mirrored.
#
# Wetness comes in through WetReflections.set_wetness (one entry point for
# every wet-road visual): game.gd feeds it from scripts/world/weather.gd, and
# NEON_WET=<0..1> or --wet=<0..1> (benchmark args) pins it for screenshots.
# No class_name on purpose: preload it, so no class cache refresh is needed.

## Puddles sit just under the lamp pools (POOL_Y 0.045) and above the lane
## dashes (top at 0.035): water covers paint, lamp light lands on the water.
const PUDDLE_Y := 0.04
## Puddles are full once wetness reaches steady rain
## (Weather.LEVEL_WETNESS[Weather.Level.RAIN]); the same ramp as
## Weather.puddle_fill, kept here so this script does not depend on weather.
const PUDDLE_FULL_AT := 0.75
## How much of the sky a shallow puddle mirrors, against a deep one's 1.
const SHALLOW_MIRROR := 0.5

## Dry-to-wet asphalt: albedo scale, roughness, Fresnel sheen (linear).
const WET_DARKEN := 0.45
const DRY_ROUGHNESS := 0.9
const WET_ROUGHNESS := 0.3
## The horizon glow (fog_light_color 0.1, 0.066, 0.042) seen in the water.
const SHEEN := Vector3(0.035, 0.026, 0.016)
## Puddle water, and the sky it mirrors at a grazing angle.
const WATER := Vector3(0.004, 0.005, 0.008)
const PUDDLE_SKY := Vector3(0.10, 0.068, 0.04)

const ASPHALT_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D grain : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 grain_scale = vec2(2.0, 6.0);
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float sheen_gain : hint_range(0.0, 1.0) = 1.0;
uniform vec3 sheen = vec3(0.035, 0.026, 0.016);
uniform float wet_darken = 0.45;
uniform float dry_roughness = 0.9;
uniform float wet_roughness = 0.3;
void fragment() {
	vec3 a = texture(grain, UV * grain_scale).rgb;
	ALBEDO = a * mix(1.0, wet_darken, wetness);
	ROUGHNESS = mix(dry_roughness, wet_roughness, wetness);
	SPECULAR = mix(0.5, 0.7, wetness);
	// Fresnel: the film of water mirrors the horizon glow at a grazing angle.
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	EMISSION = sheen * (f * wetness * sheen_gain);
}
"""

## COLOR.r is the instance colour: 1 for a deep puddle, SHALLOW_MIRROR for a
## shallow one. UV 0..1 across the unit quad; the puddle is the inscribed
## ellipse with a soft edge.
const PUDDLE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_back;
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform float mirror_gain : hint_range(0.0, 1.0) = 1.0;
uniform vec3 water = vec3(0.004, 0.005, 0.008);
uniform vec3 sky = vec3(0.10, 0.068, 0.04);
uniform float edge = 0.3;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	float mask = 1.0 - smoothstep(1.0 - edge, 1.0, r2);
	// From above a puddle mirrors the black zenith (darker than the asphalt);
	// at a grazing angle it mirrors the horizon glow and shines.
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 6.0);
	float m = f * COLOR.r * mirror_gain;
	ALBEDO = mix(water, sky, m);
	ALPHA = mask * fill * mix(0.85, 1.0, COLOR.r);
}
"""

static var wetness := 0.0
static var reflections := true
static var _asphalt_mats: Array[ShaderMaterial] = []
static var _asphalt_shader: Shader
static var _puddle_mat: ShaderMaterial
static var _puddle_shader: Shader
static var _puddle_mesh: PlaneMesh

## An asphalt material in `color`: the grain ramp runs from color.darkened(0.2)
## to color.lightened(0.1), tiled 2 x 6 over a strip's UV (the old
## StandardMaterial3D's uv1_scale). Every material made here follows
## set_wetness and set_reflections.
static func asphalt_mat(color: Color) -> ShaderMaterial:
	var noise := FastNoiseLite.new()
	noise.seed = 1337
	noise.frequency = 0.6
	var tex := NoiseTexture2D.new()
	tex.width = 64
	tex.height = 64
	tex.seamless = true
	tex.noise = noise
	var grad := Gradient.new()
	grad.colors = PackedColorArray([color.darkened(0.2), color.lightened(0.1)])
	tex.color_ramp = grad
	var m := ShaderMaterial.new()
	m.shader = asphalt_shader()
	m.set_shader_parameter("grain", tex)
	m.set_shader_parameter("grain_scale", Vector2(2.0, 6.0))
	m.set_shader_parameter("sheen", SHEEN)
	m.set_shader_parameter("wet_darken", WET_DARKEN)
	m.set_shader_parameter("dry_roughness", DRY_ROUGHNESS)
	m.set_shader_parameter("wet_roughness", WET_ROUGHNESS)
	m.set_shader_parameter("wetness", wetness)
	m.set_shader_parameter("sheen_gain", 1.0 if reflections else 0.0)
	_asphalt_mats.append(m)
	return m

## The one asphalt shader every asphalt material shares.
static func asphalt_shader() -> Shader:
	if _asphalt_shader == null:
		_asphalt_shader = Shader.new()
		_asphalt_shader.code = ASPHALT_SHADER
	return _asphalt_shader

static func puddle_mat() -> ShaderMaterial:
	if _puddle_mat == null:
		_puddle_shader = Shader.new()
		_puddle_shader.code = PUDDLE_SHADER
		_puddle_mat = ShaderMaterial.new()
		_puddle_mat.shader = _puddle_shader
		_puddle_mat.set_shader_parameter("water", WATER)
		_puddle_mat.set_shader_parameter("sky", PUDDLE_SKY)
		_puddle_mat.set_shader_parameter("fill", puddle_fill())
		_puddle_mat.set_shader_parameter("mirror_gain", 1.0 if reflections else 0.0)
	return _puddle_mat

## The unit quad puddles scale from: PlaneMesh lies in XZ, UV.y along Z.
static func puddle_mesh() -> PlaneMesh:
	if _puddle_mesh == null:
		_puddle_mesh = PlaneMesh.new()
		_puddle_mesh.size = Vector2.ONE
	return _puddle_mesh

## A "Puddles" MultiMesh for one chunk, `capacity` instances with colours
## (use_colors must be set before instance_count, so the chunk builder's
## generic factory cannot make it).
static func new_puddle_multimesh(capacity: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = puddle_mesh()
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Puddles"
	mmi.multimesh = mm
	mmi.material_override = puddle_mat()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

## Scale for a puddle of half length `hl` (along the road, z) and half width
## `hw` (across it, x), as puddles.gd lists them.
static func puddle_basis(hl: float, hw: float) -> Basis:
	return Basis.from_scale(Vector3(2.0 * hw, 1.0, 2.0 * hl))

## Instance colour for a puddle of puddles.gd depth (1 shallow, 2 deep).
static func puddle_colour(depth: int) -> Color:
	var k := 1.0 if depth >= 2 else SHALLOW_MIRROR
	return Color(k, k, k, 1.0)

## 0 dry .. 1 soaked: the road's uniform and the puddles' fill. Called from
## WetReflections.set_wetness; nothing else should write these.
static func set_wetness(w: float) -> void:
	wetness = clampf(w, 0.0, 1.0)
	for m in _asphalt_mats:
		m.set_shader_parameter("wetness", wetness)
	if _puddle_mat != null:
		_puddle_mat.set_shader_parameter("fill", puddle_fill())

## How full the puddles are drawn at the current wetness.
static func puddle_fill() -> float:
	return clampf(wetness / PUDDLE_FULL_AT, 0.0, 1.0)

## Mirrors on (Medium, High) or off (Low): the asphalt sheen and the puddle
## mirror. The darkening and the dark patches stay either way.
static func set_reflections(on: bool) -> void:
	reflections = on
	var g := 1.0 if on else 0.0
	for m in _asphalt_mats:
		m.set_shader_parameter("sheen_gain", g)
	if _puddle_mat != null:
		_puddle_mat.set_shader_parameter("mirror_gain", g)
