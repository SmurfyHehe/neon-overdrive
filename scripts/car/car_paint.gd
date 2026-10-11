extends RefCounted
class_name CarPaint

# One paint and one glass shader for every car body (look pass, 2026-10-10).
# The cars read as carved wood for three reasons: every triangle was lit on
# its own (flat normals), the paint had nothing to reflect at night, and
# chrome, rubber and plastic all shared one dull finish. So:
#
# - build_groups() gives the sheet meshes smooth normals (hard edges only
#   where two faces meet at more than CREASE_DEG), a finish per sheet
#   material (chrome, rubber, plastic), baked shade under the car and in the
#   wheel arches, and per-vertex distances to the body's creases and to the
#   lines where paint meets trim or glass.
# - the body shader paints with them: gloss / satin / matte on one shader,
#   a clear-coat rim light, dark shut lines with a lit bevel beside them,
#   crease highlights (stronger on dark paint), rust, road grime.
# - Medium and up reflect a made-up night city (no probe, no texture, no
#   extra camera): a dusk sky, a band of lit windows on the horizon, sodium
#   light overhead.
# - High adds the street lamps themselves: the two nearest lamps of the row
#   the player is driving under light the body and slide across it as
#   highlights (CarLampSweep feeds four global uniforms once a frame).
#
# Tiers follow GraphicsSettings.car_paint (the "Car paint" row on the Picture
# page; each Quality preset picks one): Plain = paint only, Reflections =
# + city reflection and the moon's rim light (and CarFx's soft contact
# shadow), Lamp light = + the street lamps and metal flake. A change of tier
# rewrites the shader code once.
#
# Look upgrade (2026-10-11): the coupe assembled from parts (CarAssembler)
# wears the same shader now ("body_parts" and "trim_parts": its baked shade
# and shut lines come in CUSTOM0 instead of UV2 and the edge distances), and
# every car gets a cool rim from the moon's side.

const TIER_LOW := 0
const TIER_MEDIUM := 1
const TIER_HIGH := 2

## Faces meeting at less than this share a smooth normal; sharper stays an edge.
const CREASE_DEG := 38.0
## Two paint faces meeting at more than this (and bending outward) are a body
## crease that catches the light.
const HIGHLIGHT_DEG := 28.0
## Edge distances are stored as 1 - d / EDGE_W so a mesh without them (all
## zeros) reads as "EDGE_W away from any edge": no line.
const EDGE_W := 0.03
const NO_EDGE := -50.0

## [metallic, gloss] per sheet material that is not the paint. Gloss is
## 1 - roughness, so a mesh without this array (zeros) is plain matte.
const FINISH := {
	"chrome": [0.95, 0.86], "head_off": [0.4, 0.8],
	"rim_dark": [0.6, 0.55], "rim_gold": [0.85, 0.7], "rim_bronze": [0.85, 0.65],
	"rim_gap": [0.0, 0.1], "tire": [0.0, 0.12], "tire_side": [0.0, 0.22],
	"trim": [0.0, 0.42], "pillar": [0.0, 0.72], "grille": [0.0, 0.3],
	"under": [0.0, 0.04], "exh_hole": [0.0, 0.0], "bed": [0.0, 0.25],
	"interior": [0.0, 0.1], "paint2": [0.2, 0.7],
	"rust": [0.0, 0.05], "bondo": [0.0, 0.12], "primer": [0.0, 0.2],
}
const FINISH_DEFAULT := [0.1, 0.25]
## Sheet materials that are a hole or the dark underside: fully shaded.
const PIT_MATS := ["under", "exh_hole", "rim_gap"]
const TYRE_MATS := ["tire", "tire_side"]

## Paint finish per car: [gloss (1 gloss, 0.5 satin, 0 matte), rust 0..1,
## flake 0..1]. Gloss is the default (Roy, 2026-10-10); the beater is faded
## and rusty, the work trucks a little dull.
const CAR_FINISH := {
	"p0_beater": [0.4, 0.75, 0.0],
	"p17_work_pickup": [0.75, 0.0, 0.2],
	"n3_pickup": [0.75, 0.0, 0.2],
}
const CAR_FINISH_DEFAULT := [1.0, 0.0, 0.5]
## Side doors per car, for the door shut lines (cut_seams).
const DOORS := {
	"n1_commuter": 4, "n2_cityhatch": 4, "c1_patrol": 4, "c2_patrolsuv": 4,
	"c3_interceptor": 4, "p6_crossover": 4, "p0_beater": 4,
}

const _LIB := """
varying vec3 obj_pos;
varying vec3 obj_nrm;
varying vec3 w_pos;
float soft_noise(vec3 q) {
	return 0.5 + 0.25 * (sin(q.x * 1.7 + sin(q.z * 2.3 + q.y)) + sin(q.z * 1.3 + sin(q.y * 2.9 + q.x * 1.1)));
}
#ifdef PANO
global uniform vec4 car_lamp_light;
global uniform vec3 sky_moon_dir;
// The moon's cool rim (research item 9): a navy edge on the side of the car
// that faces the moon, stronger the higher it hangs. Glancing angles only.
vec3 moon_rim(vec3 n, vec3 v, float f) {
	vec3 m = normalize(sky_moon_dir + vec3(0.0, 1e-4, 0.0));
	float side = clamp(dot(n, m) * 0.6 + 0.4, 0.0, 1.0);
	float back = clamp(0.6 - 0.4 * dot(v, m), 0.0, 1.0);
	// f^5 and weak: a broad wash turned red paint mauve (pictures, 2026-10-11).
	float f2 = f * f;
	return vec3(0.10, 0.15, 0.30) * f2 * f2 * f * side * back * (0.25 + 0.75 * clamp(m.y * 2.5, 0.0, 1.0));
}
// The night city a car mirrors: asphalt below, a warm band of lit windows
// and far lamps on the horizon, dusk sky above, sodium light from overhead.
// `blur` 0 is a mirror, 1 a matte smear.
vec3 city(vec3 r, float blur) {
	float y = r.y;
	float soft = 0.05 + 0.35 * blur;
	vec3 sky = mix(vec3(0.16, 0.10, 0.08), vec3(0.02, 0.03, 0.06), smoothstep(0.0, 0.55, y));
	vec3 c = mix(vec3(0.030, 0.025, 0.020), sky, smoothstep(-soft, soft, y));
	vec2 h = normalize(r.xz + vec2(1e-4));
	float cells = 0.5 + 0.5 * sin(h.x * 9.0 + 2.0 * sin(h.y * 5.0)) * sin(h.y * 11.0 + 1.3);
	float band = exp(-pow((y - 0.09) / (0.06 + 0.3 * blur), 2.0));
	c += vec3(1.0, 0.55, 0.2) * band * (0.3 + 0.25 * smoothstep(0.4, 0.9, cells) * (1.0 - blur));
	c += car_lamp_light.rgb * OVERHEAD * smoothstep(0.3, 0.95, y);
	return c;
}
#else
vec3 city(vec3 r, float blur) {
	return mix(vec3(0.012, 0.010, 0.009), vec3(0.045, 0.034, 0.034), smoothstep(-0.2, 0.3, r.y));
}
#endif
#ifdef LAMPS
global uniform vec3 car_lamp_origin;
global uniform vec3 car_lamp_fwd;
global uniform vec4 car_lamp_grid;
// The two nearest lamps of the row (one each side). Where each lamp is and
// how strong is worked out per vertex (lamp_vec: xyz = direction to the lamp,
// w = strength); the lamps hang metres away, so it barely changes across a
// panel, and the pixels only pay for the highlight (measured 2026-10-11).
varying vec4 lamp_a;
varying vec4 lamp_b;
vec4 lamp_vec(vec3 wp, int i) {
	vec3 rel = wp - car_lamp_origin;
	vec3 right = normalize(cross(car_lamp_fwd, vec3(0.0, 1.0, 0.0)));
	float s = dot(rel, car_lamp_fwd);
	float x = dot(rel, right) + car_lamp_grid.w;
	float period = car_lamp_grid.x;
	float reach = min(period * 0.5, 16.0);
	float at = (i == 0) ? car_lamp_grid.y : car_lamp_grid.z;
	float hx = (i == 0) ? car_lamp_light.w : -car_lamp_light.w;
	float da = mod(at - s + period * 0.5, period) - period * 0.5;
	vec3 l = right * (hx - x) + vec3(0.0, 7.3 - rel.y, 0.0) + car_lamp_fwd * da;
	float d2 = dot(l, l);
	float w = clamp(1.0 - da * da / (reach * reach), 0.0, 1.0);
	float att = w * w * 250.0 / (250.0 + d2) * (1.0 - smoothstep(45.0, 70.0, length(rel)));
	return vec4(l * inversesqrt(d2), att);
}
// x = light on a matte surface, y = the highlight. `shine` is the
// highlight's tightness.
vec2 lamps(vec3 n, vec3 v, float shine) {
	vec3 la = normalize(lamp_a.xyz);
	vec3 lb = normalize(lamp_b.xyz);
	vec2 sum = vec2(max(dot(n, la), 0.0), pow(max(dot(n, normalize(la + v)), 0.0), shine)) * lamp_a.w;
	sum += vec2(max(dot(n, lb), 0.0), pow(max(dot(n, normalize(lb + v)), 0.0), shine)) * lamp_b.w;
	return sum;
}
#endif
"""

const _BODY := """
// Vertex alpha 0 marks paint (or rim) faces; they take the tint and the finish.
// Fixed slots: the body, lamp and flare shaders on one car share its instance
// uniforms by slot, so unnumbered ones collide (brake lamps painted the body).
#ifdef PAINT_INSTANCE
instance uniform vec3 paint : source_color, instance_index(0) = vec3(0.79, 0.81, 0.84);
#else
uniform vec3 paint : source_color = vec3(1.0, 0.54, 0.12);
#endif
// x gloss (1 gloss, 0.5 satin, 0 matte), y rust, z metal flake.
instance uniform vec4 finish : instance_index(4) = vec4(1.0, 0.0, 0.5, 0.0);
// Door shut lines, body space: three cut positions along the car (equal ones
// are no cut) and the belt line they stop at. w = 0: none.
instance uniform vec4 seams : instance_index(5) = vec4(0.0);
uniform float paint_metallic = 0.3;
uniform float paint_roughness = 0.26;
// Road grime (car_dirt.gd): 0 clean .. 1 a full night's dirt. Thick on the
// sills, thin on the roof, in soft patches.
uniform float dirt : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dirt_color : source_color = vec3(0.40, 0.35, 0.28);
#ifdef PARTS
// A body assembled from parts: x = baked light (1 open, 0 shut in), y = 1 on
// a shut line fading to 0 six millimetres either side.
varying vec2 ao_shut;
#else
varying vec3 e_crease;
varying vec3 e_seam;
#endif
void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#ifdef LAMPS
	lamp_a = lamp_vec(w_pos, 0);
	lamp_b = lamp_vec(w_pos, 1);
#endif
#ifdef PARTS
	ao_shut = CUSTOM0.rg;
#else
	e_crease = CUSTOM0.rgb;
	e_seam = CUSTOM1.rgb;
#endif
}
float line_at(float d, float w, float px) {
	float wl = max(w, 0.5 * px);
	return clamp((wl - d) / px + 0.5, 0.0, 1.0) * sqrt(w / wl);
}
void fragment() {
	float p = 1.0 - COLOR.a;
#ifdef PARTS
	vec2 fin = vec2(0.1, 0.25);
	float occ = 1.0 - ao_shut.x;
#else
	vec2 fin = UV;
	float occ = UV2.x;
#endif
	float gloss = mix(fin.y, finish.x, p);
	vec3 base = mix(COLOR.rgb, paint, p);
	float metallic = mix(fin.x, paint_metallic, p);
	float rough = mix(1.0 - fin.y, mix(0.85, paint_roughness, finish.x), p);
	float px = max(length(dFdx(w_pos)), length(dFdy(w_pos))) + 1e-5;

#ifdef PARTS
	// Shut lines are real gaps between the parts, baked per vertex.
	float d_seam = EDGE_W * (1.0 - ao_shut.y);
	float d_crease = EDGE_W;
	float gap = ao_shut.y * 0.88;
	float bevel = 4.0 * ao_shut.y * (1.0 - ao_shut.y) * clamp(0.02 / px, 0.0, 1.0);
	float crease = 0.0;
#else
	// Shut lines: where paint meets trim or glass (baked), and the door cuts.
	float d_seam = EDGE_W * (1.0 - max(e_seam.x, max(e_seam.y, e_seam.z)));
	if (seams.w > 0.0) {
		float on_side = smoothstep(0.55, 0.8, abs(obj_nrm.x)) * p
			* step(seams.w * 0.3, obj_pos.y) * step(obj_pos.y, seams.w);
		float dz = min(min(abs(obj_pos.z - seams.x), abs(obj_pos.z - seams.y)), abs(obj_pos.z - seams.z));
		d_seam = min(d_seam, mix(1.0, dz, on_side));
	}
	float gap = line_at(d_seam, 0.004, px);
	float bevel = (1.0 - smoothstep(0.004, 0.016, d_seam)) * (1.0 - gap) * clamp(0.02 / px, 0.0, 1.0);
	float d_crease = EDGE_W * (1.0 - max(e_crease.x, max(e_crease.y, e_crease.z)));
	float crease = line_at(d_crease, 0.006, px) * clamp(0.03 / px, 0.0, 1.0);
#endif

	// Rust eats the paint from the sills and the seams up (the beater).
	float rust = 0.0;
	if (finish.y > 0.0) {
		float low = 1.0 - smoothstep(0.15, 0.75, obj_pos.y);
		float near_edge = 1.0 - smoothstep(0.0, 0.05, min(d_seam, d_crease));
		float n = mix(soft_noise(obj_pos * 7.0), soft_noise(obj_pos.zxy * 23.0), 0.35);
		rust = smoothstep(1.0 - finish.y * (0.3 + 0.5 * low + 0.3 * near_edge), 1.05 - finish.y * 0.3, n) * p;
		base = mix(base, vec3(0.15, 0.055, 0.02) * (0.6 + 0.8 * n), rust);
	}
	float grime = 0.0;
	if (dirt > 0.0) {
		float low = 1.0 - smoothstep(0.08, 1.0, obj_pos.y);      // sills first, roof last
		float side = 1.0 - 0.55 * max(obj_nrm.y, 0.0);            // flat tops catch less
		float blotch = mix(soft_noise(obj_pos * 5.0), soft_noise(obj_pos.yzx * 17.0), 0.4);
		grime = clamp(dirt * (0.2 + 1.3 * low) * side * (0.35 + 0.65 * blotch), 0.0, 1.0);
		base = mix(base, dirt_color * 0.8, grime * 0.7);
	}
	float dull = max(rust, grime * 0.75);
	gloss *= 1.0 - dull;
	float shade = (1.0 - 0.7 * occ) * (1.0 - 0.85 * gap);
	ALBEDO = base * shade;
	METALLIC = mix(metallic, 0.0, dull);
	ROUGHNESS = mix(rough, 0.92, dull);
	SPECULAR = 0.5;

	// What the surface mirrors. Paint is a clear coat over colour: a weak
	// mirror face on, a strong one at a glancing angle, which is what draws
	// the car's outline at night. Chrome mirrors everything, tinted.
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - w_pos);
	float f = 1.0 - clamp(dot(n, v), 0.0, 1.0);
	float f2 = f * f;
	float fres = f2 * f2 * f;
	float metal = METALLIC * (1.0 - p);
	// Dark paint has no colour to show under sodium light, so its coat, its
	// creases and its panel edges carry the shape instead.
	float dark = 1.0 - smoothstep(0.02, 0.22, dot(base, vec3(0.3, 0.5, 0.2)));
	float coat = mix(0.10 + 0.90 * fres, 0.55 + 0.45 * fres, metal) * (1.0 + 0.7 * dark * p);
	float edges = (crease * (0.2 + 0.7 * dark) + bevel * (0.2 + 0.4 * dark)) * p;
	float k = (coat + edges) * mix(0.15, 1.0, gloss) * (1.0 - occ) * (1.0 - gap);
	vec3 tint = mix(vec3(1.0), base * 1.6, max(metal, 0.35 * paint_metallic * p));
	vec3 lit = city(reflect(-v, n), 1.0 - gloss) * k * tint;
#ifdef PANO
	// The street's own light from above, soft: what the lamps leave on a
	// body between their pools.
	lit += car_lamp_light.rgb * base * shade * (1.0 - METALLIC) * (0.5 + 0.5 * n.y) * OVERHEAD * 0.6;
	lit += moon_rim(n, v, f) * mix(0.3, 1.0, gloss) * (1.0 - occ) * (1.0 - gap);
#endif
#ifdef LAMPS
	vec2 lamp = lamps(n, v, mix(12.0, 220.0, gloss * gloss));
	vec3 lamp_c = car_lamp_light.rgb * shade;
	// 0.55: a full-strength wash turned bright paints pale under the tone map.
	lit += lamp_c * base * (1.0 - METALLIC) * lamp.x * 0.55;
	lit += lamp_c * tint * lamp.y * mix(0.08, 2.5, gloss) * (0.35 + 0.65 * coat + edges);
	// Metal flake: sparks in the paint where a lamp's highlight falls.
	float cell = fract(sin(dot(floor(obj_pos * 260.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	lit += lamp_c * step(0.975, cell) * (lamp.y * 3.0 + lamp.x * 0.15) * finish.z * p * gloss * clamp(0.006 / px, 0.0, 1.0);
#endif
	EMISSION = lit;
}
"""

const _GLASS := """
// Glass: nearly black, mirrors the street, and a hint of the cabin's own
// light low in each window. `see` < 1 lets the cabin show through.
uniform vec3 glass : source_color = vec3(0.082, 0.114, 0.18);
uniform float see = 1.0;
void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#ifdef LAMPS
	lamp_a = lamp_vec(w_pos, 0);
	lamp_b = lamp_vec(w_pos, 1);
#endif
}
void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - w_pos);
	float f = 1.0 - clamp(dot(n, v), 0.0, 1.0);
	float f2 = f * f;
	float fres = 0.08 + 0.92 * f2 * f2 * f;
	ALBEDO = glass * 0.45;
	METALLIC = 0.3;
	ROUGHNESS = 0.06;
	SPECULAR = 0.6;
	vec3 lit = city(reflect(-v, n), 0.0) * fres * 1.5;
	lit += vec3(1.0, 0.62, 0.3) * 0.022 * UV.x * UV.x * (1.0 - fres);
#ifdef PANO
	lit += moon_rim(n, v, f);
#endif
#ifdef LAMPS
	vec2 lamp = lamps(n, v, 320.0);
	lit += car_lamp_light.rgb * lamp.y * (0.5 + fres);
#endif
	EMISSION = lit;
#ifdef SEE_THROUGH
	ALPHA = clamp(see + fres * 0.7, 0.0, 1.0);
#endif
}
"""

# The trim of a body assembled from parts (CarAssembler: plastic, rubber,
# chrome, plate, mirror glass, lamp lens on one surface). COLOR.a * 8 is the
# class; chrome and the mirror glass show the city and the lamps.
const _TRIM := """
// roughness, metallic, specular per class: 1 plastic, 2 rubber, 3 chrome,
// 4 plate, 5 mirror glass, 6 red lamp lens.
const vec3 FINISH[8] = vec3[](vec3(0.6, 0.0, 0.5), vec3(0.55, 0.0, 0.5), vec3(0.9, 0.0, 0.3), vec3(0.2, 1.0, 0.5),
	vec3(0.45, 0.0, 0.5), vec3(0.06, 1.0, 0.5), vec3(0.12, 0.0, 0.8), vec3(0.6, 0.0, 0.5));
// How strongly the trim mirrors the street (1 = as designed).
uniform float trim_shine = 1.0;
varying vec2 ao_shut;
varying flat vec3 trim_fin;
void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#ifdef LAMPS
	lamp_a = lamp_vec(w_pos, 0);
	lamp_b = lamp_vec(w_pos, 1);
#endif
	ao_shut = CUSTOM0.rg;
	trim_fin = FINISH[clamp(int(COLOR.a * 8.0 + 0.5), 0, 7)];
}
void fragment() {
	float shade = mix(1.0, ao_shut.x, 0.7) * (1.0 - 0.75 * ao_shut.y);
	ALBEDO = COLOR.rgb * shade;
	ROUGHNESS = trim_fin.x;
	METALLIC = trim_fin.y;
	SPECULAR = trim_fin.z;
#ifdef PANO
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - w_pos);
	float f = 1.0 - clamp(dot(n, v), 0.0, 1.0);
	float f2 = f * f;
	float fres = f2 * f2 * f;
	float gloss = 1.0 - trim_fin.x;
	// Chrome and mirror glass mirror the street; plastic and rubber only at a
	// glancing angle, and dully.
	float k = mix(0.04 + 0.5 * fres, 0.55 + 0.45 * fres, trim_fin.y) * mix(0.1, 1.0, gloss) * ao_shut.x * trim_shine;
	vec3 tint = mix(vec3(1.0), COLOR.rgb * 1.6, trim_fin.y);
	vec3 lit = city(reflect(-v, n), trim_fin.x) * k * tint;
#ifdef LAMPS
	vec2 lamp = lamps(n, v, mix(10.0, 200.0, gloss * gloss));
	vec3 lamp_c = car_lamp_light.rgb * shade;
	lit += lamp_c * COLOR.rgb * (1.0 - trim_fin.y) * lamp.x;
	lit += lamp_c * tint * lamp.y * mix(0.05, 2.0, gloss) * (0.3 + 0.7 * k);
#endif
	EMISSION = lit;
#endif
}
"""

static var _tier := -1
static var _shaders := {}  # variant -> Shader

static func tier_of(preset: String) -> int:
	match preset:
		"low":
			return TIER_LOW
		"high":
			return TIER_HIGH
	return TIER_MEDIUM  # medium, and a hand-tuned "custom" set

static func tier() -> int:
	if _tier < 0:
		_tier = clampi(GraphicsSettings.car_paint, TIER_LOW, TIER_HIGH)
	return _tier

## The tier a preset name stands for on its own (tests, tools).
static func set_preset(preset: String) -> void:
	set_tier(tier_of(preset))

## GraphicsSettings.apply() calls this: recompiles the car shaders when the
## tier changed (a one-off hitch in the menu), and swaps the contact shadow.
static func set_tier(t: int) -> void:
	t = clampi(t, TIER_LOW, TIER_HIGH)
	if t == _tier:
		return
	_tier = t
	for variant in _shaders:
		(_shaders[variant] as Shader).code = code(variant, t)
	CarFx.set_soft_shadow(t >= TIER_MEDIUM)

## The body shader. `instance_paint`: the paint colour comes per car from an
## instance uniform (the shared sheet-car material); otherwise it is the
## material's own `paint` (the coupe, wheels).
static func body_shader(instance_paint: bool) -> Shader:
	return _shader("body_instance" if instance_paint else "body")

## The paint and trim shaders of a body assembled from parts (CarAssembler).
static func parts_body_shader() -> Shader:
	return _shader("body_parts")

static func parts_trim_shader() -> Shader:
	return _shader("trim_parts")

## The glass shader; `see_through` blends the cabin in behind it.
static func glass_shader(see_through: bool) -> Shader:
	return _shader("glass_see" if see_through else "glass")

static func _shader(variant: String) -> Shader:
	if not _shaders.has(variant):
		var sh := Shader.new()
		sh.code = code(variant, tier())
		_shaders[variant] = sh
	return _shaders[variant]

## The shader source of a variant at a tier (tests compile every pair).
static func code(variant: String, at_tier: int) -> String:
	var head := "shader_type spatial;\n"
	head += "render_mode cull_back;\n"
	head += "#define EDGE_W %s\n" % EDGE_W
	if at_tier >= TIER_MEDIUM:
		head += "#define PANO\n"
	if at_tier >= TIER_HIGH:
		head += "#define LAMPS\n"
	# With the real lamps drawn, the overhead glow is only the far ones.
	head += "#define OVERHEAD %s\n" % (0.12 if at_tier >= TIER_HIGH else 0.35)
	match variant:
		"body_instance":
			return head + "#define PAINT_INSTANCE\n" + _LIB + _BODY
		"body_parts":
			return head + "#define PARTS\n" + _LIB + _BODY
		"trim_parts":
			return head + _LIB + _TRIM
		"glass":
			return head + _LIB + _GLASS
		"glass_see":
			return head + "#define SEE_THROUGH\n" + _LIB + _GLASS
	return head + _LIB + _BODY

const VARIANTS := ["body", "body_instance", "body_parts", "trim_parts", "glass", "glass_see"]

## The finish instance uniform for a car kind.
static func finish_for(kind: String) -> Vector4:
	var f: Array = CAR_FINISH.get(kind, CAR_FINISH_DEFAULT)
	return Vector4(f[0], f[1], f[2], 0.0)

# ---------- meshes ----------

## The triangles of one sheet mesh sorted into surfaces "body", "glass",
## "glow", each [vertices, normals, colours, uv, uv2, custom0, custom1]:
## - normals smoothed across edges flatter than CREASE_DEG,
## - colours linear, alpha 0 on `tint_mats` faces (the paint, or the rim),
## - uv = (metallic, gloss) per FINISH on body faces; x = how low in the
##   window a glass vertex sits,
## - uv2.x = baked shade (0 none .. 1 black): the underside, the sills, the
##   wheel arches (`opts.wheels` hubs and `opts.wheel_r`, mesh space), or the
##   depth of a rim (`opts.is_wheel`),
## - custom0 / custom1 = 1 - distance / EDGE_W to the triangle's crease edges
##   and paint-boundary edges (NO_EDGE for an edge that is neither).
## Each design triangle is written a, c, b for Godot's clockwise front faces.
static func build_groups(data: GDScript, tris: PackedVector3Array, mats: PackedByteArray,
		tint_mats: Array, opts := {}) -> Dictionary:
	var is_wheel: bool = opts.get("is_wheel", false)
	if not is_wheel and opts.get("mirror", true):
		var sym := mirrored(tris, mats)
		tris = sym[0]
		mats = sym[1]
	var n_tri := mats.size()
	var hubs: Array = opts.get("wheels", [])
	var wheel_r: float = opts.get("wheel_r", 0.3)
	var cos_crease := cos(deg_to_rad(CREASE_DEG))
	var cos_high := cos(deg_to_rad(HIGHLIGHT_DEG))

	var names: Array = data.NAMES
	# Per sheet material, worked out once: class, colour, finish, pit, tyre.
	var m_class := PackedByteArray()
	var m_col := PackedColorArray()
	var m_fin := PackedVector2Array()
	var m_pit := PackedByteArray()
	var m_tyre := PackedByteArray()
	for mname: String in names:
		var cls := 3 if mname in data.EMISSIVE else (2 if mname in data.GLASS else (0 if mname in tint_mats else 1))
		m_class.append(cls)
		var col := Color(data.COLORS[mname]).srgb_to_linear() if data.COLORS.has(mname) else Color.BLACK
		col.a = 0.0 if cls == 0 else 1.0
		m_col.append(col)
		var fin: Array = FINISH.get(mname, FINISH_DEFAULT)
		m_fin.append(Vector2(fin[0], fin[1]))
		m_pit.append(1 if mname in PIT_MATS else 0)
		m_tyre.append(1 if mname in TYRE_MATS else 0)
	var arch_top := wheel_r * 2.6
	var fn := PackedVector3Array()   # face normal, zero = degenerate
	fn.resize(n_tri)
	var fa := PackedFloat32Array()   # face area
	fa.resize(n_tri)
	var fclass := PackedByteArray()  # 0 tinted, 1 other body, 2 glass, 3 glow
	fclass.resize(n_tri)
	var pid := PackedInt32Array()    # corner -> id of its position
	pid.resize(n_tri * 3)
	var ids := {}                    # Vector3i (mm) -> id
	var at_point: Array[PackedInt32Array] = []  # id -> faces touching it
	var at_edge := {}                # edge key -> PackedInt32Array of faces
	var x_out := -INF
	var glass_y0 := INF
	var glass_y1 := -INF
	for t in n_tri:
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var n := (b - a).cross(c - a)
		fclass[t] = m_class[mats[t]]
		if n.length_squared() < 1e-12:
			continue
		fa[t] = n.length() * 0.5
		fn[t] = n.normalized()
		for k in 3:
			var p := tris[t * 3 + k]
			x_out = maxf(x_out, p.x)
			if fclass[t] == 2:
				glass_y0 = minf(glass_y0, p.y)
				glass_y1 = maxf(glass_y1, p.y)
			var key := Vector3i((p * 1000.0).round())
			var id: int = ids.get(key, -1)
			if id < 0:
				id = at_point.size()
				ids[key] = id
				at_point.append(PackedInt32Array())
			pid[t * 3 + k] = id
			at_point[id].append(t)
		for k in 3:
			var ek := _edge_key(pid[t * 3 + (k + 1) % 3], pid[t * 3 + (k + 2) % 3])
			if not at_edge.has(ek):
				at_edge[ek] = PackedInt32Array()
			at_edge[ek].append(t)

	var groups := {}
	for t in n_tri:
		if fn[t] == Vector3.ZERO:
			continue
		var mi := mats[t]
		var cls := fclass[t]
		var surf: String = "glow" if cls == 3 else ("glass" if cls == 2 else "body")
		if not groups.has(surf):
			groups[surf] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(),
				PackedVector2Array(), PackedVector2Array(), PackedFloat32Array(), PackedFloat32Array()]
		var g: Array = groups[surf]
		var col := m_col[mi]
		var fin := m_fin[mi]
		var no_edges := true
		var centre := (tris[t * 3] + tris[t * 3 + 1] + tris[t * 3 + 2]) / 3.0
		# Edge k is the one opposite corner k.
		var crease_h := [NO_EDGE, NO_EDGE, NO_EDGE]
		var seam_h := [NO_EDGE, NO_EDGE, NO_EDGE]
		if surf == "body":
			for k in 3:
				var pa := tris[t * 3 + (k + 1) % 3]
				var pb := tris[t * 3 + (k + 2) % 3]
				var faces: PackedInt32Array = at_edge[_edge_key(pid[t * 3 + (k + 1) % 3], pid[t * 3 + (k + 2) % 3])]
				if faces.size() != 2:
					continue
				var o := faces[1] if faces[0] == t else faces[0]
				var h := 2.0 * fa[t] / maxf(pa.distance_to(pb), 1e-6)
				if fclass[o] != cls and (cls == 0 or fclass[o] == 0):
					seam_h[k] = h
					no_edges = false
				elif cls == 0 and fn[o].dot(fn[t]) < cos_high:
					var oc := (tris[o * 3] + tris[o * 3 + 1] + tris[o * 3 + 2]) / 3.0
					if fn[t].dot(oc - centre) < -1e-5:
						crease_h[k] = h
						no_edges = false
		for k in [0, 2, 1]:
			var p := tris[t * 3 + k]
			var n := Vector3.ZERO
			for o in at_point[pid[t * 3 + k]]:
				if fn[o].dot(fn[t]) >= cos_crease:
					n += fn[o] * fa[o]
			g[0].append(p)
			g[1].append(n.normalized() if n.length_squared() > 1e-16 else fn[t])
			g[2].append(col)
			if surf == "glass":
				g[3].append(Vector2(1.0 - inverse_lerp(glass_y0, glass_y1, p.y) if glass_y1 > glass_y0 else 0.0, 0.0))
			else:
				g[3].append(fin)
			var occ := 0.0
			if m_pit[mi] == 1:
				occ = 1.0
			elif is_wheel:
				if m_tyre[mi] == 0:
					occ = clampf((x_out - p.x) / 0.12, 0.0, 1.0) * 0.75
			else:
				occ = 0.4 * (1.0 - smoothstep(0.1, 0.45, p.y))
				if fn[t].y < -0.5:
					occ = maxf(occ, 0.7)
				for hub: Vector3 in (hubs if p.y < arch_top else []):
					var to_hub := Vector2(hub.y - p.y, hub.z - p.z)
					var d := to_hub.length()
					if d < wheel_r * 1.5 and absf(p.x - hub.x) < 0.45:
						var facing := Vector2(fn[t].y, fn[t].z).dot(to_hub / maxf(d, 1e-4))
						occ = maxf(occ, 0.92 if facing > 0.35 else 0.5 * (1.0 - smoothstep(wheel_r * 1.02, wheel_r * 1.5, d)))
			g[4].append(Vector2(occ, 0.0))
			if surf != "body":
				continue
			if no_edges:
				g[5].append_array(_NO_EDGES)
				g[6].append_array(_NO_EDGES)
				continue
			for j in 3:
				var hc: float = crease_h[j]
				var hs: float = seam_h[j]
				g[5].append(NO_EDGE if hc == NO_EDGE else (1.0 - hc / EDGE_W if j == k else 1.0))
				g[6].append(NO_EDGE if hs == NO_EDGE else (1.0 - hs / EDGE_W if j == k else 1.0))
	return groups

## The body with its right half rebuilt as the mirror image of its left half
## (the driver's side, x < 0): [triangles, materials, sheet materials left
## alone]. The sheets are the same shape on both sides to the millimetre,
## but their triangles are not mirror images (each four-sided patch is cut
## along the same diagonal, not the mirrored one), so the two sides caught
## the light differently. Left as they are:
## - parts that exist on one side only (an exhaust, a spotlight, an aerial)
##   and triangles that cross the centre line,
## - every sheet material whose left and right halves do not cover the same
##   area (within MIRROR_AREA_TOL): the red and blue halves of a police
##   light bar, the beater's one-sided patches. Mirroring those would paint
##   one side's colours over the other.
const MIRROR_AREA_TOL := 0.005
const MIRROR_AREA_MIN := 0.0002
static func mirrored(tris: PackedVector3Array, mats: PackedByteArray) -> Array:
	var n_tri := mats.size()
	var left := {}    # mm key -> true, vertices with x < 0
	var right := {}   # mm key -> the vertex, x > 0
	for p in tris:
		var k := Vector3i((p * 1000.0).round())
		if k.x < 0:
			left[k] = true
		elif k.x > 0:
			right[k] = p
	# Pass 1: what would go (0 keep, 1 drop, 2 keep and mirror), and the area
	# each sheet material would lose and gain on the right.
	var memo_l := {}
	var memo_r := {}
	var plan := PackedByteArray()
	plan.resize(n_tri)
	var twins := {}    # triangle -> its three mirrored corners
	var lost := {}     # material -> area dropped
	var gained := {}   # material -> area mirrored in
	var on_right := {} # material -> its whole right-side area
	for t in n_tri:
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var lo := minf(a.x, minf(b.x, c.x))
		var hi := maxf(a.x, maxf(b.x, c.x))
		var area := (b - a).cross(c - a).length() * 0.5
		var m := mats[t]
		if lo > -0.0005 and hi > 0.0005:
			on_right[m] = float(on_right.get(m, 0.0)) + area
			if _has_twin(left, a, memo_l) and _has_twin(left, b, memo_l) and _has_twin(left, c, memo_l):
				plan[t] = 1
				lost[m] = float(lost.get(m, 0.0)) + area
		elif hi < 0.0005 and lo < -0.0005:
			var ma: Variant = _twin_of(right, a, memo_r)
			var mb: Variant = _twin_of(right, b, memo_r)
			var mc: Variant = _twin_of(right, c, memo_r)
			if ma != null and mb != null and mc != null:
				plan[t] = 2
				# Mirroring turns the triangle inside out: swap two corners back.
				twins[t] = [ma, mc, mb]
				gained[m] = float(gained.get(m, 0.0)) + area
	var skip := {}
	for m in on_right:
		if not lost.has(m) and not gained.has(m):
			continue
		var diff := absf(float(lost.get(m, 0.0)) - float(gained.get(m, 0.0)))
		if diff > maxf(MIRROR_AREA_TOL * float(on_right[m]), MIRROR_AREA_MIN):
			skip[m] = true
	for m in gained:
		if not on_right.has(m):
			skip[m] = true
	# Pass 2.
	var out_tris := PackedVector3Array()
	var out_mats := PackedByteArray()
	var add_tris := PackedVector3Array()
	var add_mats := PackedByteArray()
	for t in n_tri:
		var m := mats[t]
		var todo := 0 if skip.has(m) else plan[t]
		if todo == 1:
			continue
		out_tris.append(tris[t * 3])
		out_tris.append(tris[t * 3 + 1])
		out_tris.append(tris[t * 3 + 2])
		out_mats.append(m)
		if todo == 2:
			add_tris.append_array(PackedVector3Array(twins[t]))
			add_mats.append(m)
	out_tris.append_array(add_tris)
	out_mats.append_array(add_mats)
	return [out_tris, out_mats, skip.keys()]

## True when the mirror image of `p` is a left-side vertex (within 1 mm), or
## `p` is on the centre line. `memo` remembers the answer per vertex.
static func _has_twin(left: Dictionary, p: Vector3, memo: Dictionary) -> bool:
	var k := Vector3i((p * 1000.0).round())
	if k.x == 0:
		return true
	var m := Vector3i(-k.x, k.y, k.z)
	if left.has(m):
		return true
	var known: Variant = memo.get(k)
	if known != null:
		return known
	var found := false
	for i in 27:
		if left.has(m + Vector3i(i % 3 - 1, (i / 3) % 3 - 1, i / 9 - 1)):
			found = true
			break
	memo[k] = found
	return found

## The right-side vertex that mirrors left-side `p` (within 1 mm), `p` itself
## on the centre line, or null. `memo` remembers the answer per vertex.
static func _twin_of(right: Dictionary, p: Vector3, memo: Dictionary) -> Variant:
	var k := Vector3i((p * 1000.0).round())
	if k.x == 0:
		return p
	var m := Vector3i(-k.x, k.y, k.z)
	var exact: Variant = right.get(m)
	if exact != null:
		return exact
	if memo.has(k):
		return memo[k]
	var found: Variant = null
	for i in 27:
		var o := m + Vector3i(i % 3 - 1, (i / 3) % 3 - 1, i / 9 - 1)
		if right.has(o):
			found = right[o]
			break
	memo[k] = found
	return found

const _NO_EDGES: PackedFloat32Array = [NO_EDGE, NO_EDGE, NO_EDGE]

static func _edge_key(a: int, b: int) -> int:
	return mini(a, b) * 1000003 + maxi(a, b)

## Adds one build_groups() surface to `mesh` and returns its index.
static func add_surface(mesh: ArrayMesh, g: Array, surf: String) -> int:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = g[0]
	arrays[Mesh.ARRAY_NORMAL] = g[1]
	arrays[Mesh.ARRAY_COLOR] = g[2]
	var flags := 0
	if surf != "glow":
		arrays[Mesh.ARRAY_TEX_UV] = g[3]
	if surf == "body":
		arrays[Mesh.ARRAY_TEX_UV2] = g[4]
		arrays[Mesh.ARRAY_CUSTOM0] = g[5]
		arrays[Mesh.ARRAY_CUSTOM1] = g[6]
		flags = (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	var idx := mesh.get_surface_count() - 1
	mesh.surface_set_name(idx, surf)
	return idx

## Where the door shut lines go, for the `seams` instance uniform: read off
## the side windows (the doors start at the windscreen pillar's foot and end
## under the glass), since the sheets carry no door parts. Zero when the car
## has no side glass.
static func cut_seams(data: GDScript, tris: PackedVector3Array, mats: PackedByteArray, doors: int) -> Vector4:
	var names: Array = data.NAMES
	var y0 := INF
	var pts := PackedVector3Array()
	for t in mats.size():
		if not (names[mats[t]] in data.GLASS):
			continue
		var a := tris[t * 3]
		var n := (tris[t * 3 + 1] - a).cross(tris[t * 3 + 2] - a).normalized()
		if absf(n.x) < 0.5:
			continue
		for k in 3:
			pts.append(tris[t * 3 + k])
			y0 = minf(y0, tris[t * 3 + k].y)
	if pts.is_empty():
		return Vector4.ZERO
	var z0 := INF
	var z1 := -INF
	for p in pts:
		if p.y < y0 + 0.12:
			z0 = minf(z0, p.z)
			z1 = maxf(z1, p.z)
	var front := z0 - 0.04
	if doors >= 4:
		return Vector4(front, lerpf(z0, z1, 0.5), z1 - 0.12, y0 - 0.02)
	var back := minf(front + 1.25, lerpf(z0, z1, 0.72))
	return Vector4(front, back, back, y0 - 0.02)
