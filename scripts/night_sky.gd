extends RefCounted
class_name NightSky

# Night sky with a phasing moon (2026-10-07).
#
# Replaces the ProceduralSkyMaterial with one sky shader: the same Stage A
# gradient (same colours, same curve maths as Godot's procedural sky), plus a
# low silver moon with a faint amber haze. The moon is the hand-painted
# assets/sky/moon.png, lit by a terminator mask computed on a sphere, so the
# phase runs new -> crescent -> quarter -> gibbous -> full -> back. The phase
# is picked per run; set `NightSky.set_phase(sky, p)` to drive it from a
# night clock later.
#
# The moon is drawn in the main sky pass only (not AT_CUBEMAP_PASS), so it
# never leaks into the radiance map and the ambient light stays exactly the
# Stage A gradient. No TIME in the shader, so the radiance map is not
# re-rendered every frame.

## Sky gradient, Stage A ("Gritty PS2 night"): near-black top, dull sodium glow
## at the horizon.
const SKY_TOP := Color(0.008, 0.01, 0.018)
const SKY_HORIZON := Color(0.17, 0.095, 0.05)
const GROUND_BOTTOM := Color(0.008, 0.008, 0.01)
const GROUND_HORIZON := Color(0.11, 0.065, 0.04)

## Where the moon hangs: low over the road ahead (the player drives toward -Z),
## a touch left of centre so it sits in the gap between the building rows.
const MOON_ELEVATION_DEG := 9.0
const MOON_AZIMUTH_DEG := 5.0  # positive = left of straight ahead
const MOON_SIZE_DEG := 2.5

const SHADER := """
shader_type sky;

uniform vec3 sky_top_color : source_color;
uniform vec3 sky_horizon_color : source_color;
uniform vec3 ground_bottom_color : source_color;
uniform vec3 ground_horizon_color : source_color;
uniform float sky_curve = 0.15;
uniform float ground_curve = 0.02;

uniform sampler2D moon_tex : source_color, filter_linear, repeat_disable;
uniform vec3 moon_dir = vec3(0.0, 0.156, -0.988);
uniform float moon_radius = 0.0218; // half the angular size, radians
uniform float phase = 0.5;          // 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter
uniform float tilt = 0.5;           // terminator tilt, radians
uniform vec3 moon_color : source_color = vec3(0.78, 0.80, 0.84);  // silver
uniform float moon_energy = 1.15;
uniform float earthshine = 0.01;
uniform vec3 haze_color : source_color = vec3(1.0, 0.75, 0.40);   // amber #FFC066
uniform float haze_energy = 0.05;
uniform float horizon_haze = 0.45;  // how much the low moon sinks into the glow
// City in the reflections (polish pass, 2026-10-08): lit windows round the
// horizon and the glow of the lamp rows, drawn into the radiance map only, so
// glossy things (traffic paint, glass) mirror a city, the visible sky stays
// as it was. 0 = off (GraphicsSettings "reflections", set by WorldLook).
uniform float city = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 city_band(vec3 d) {
	float az = atan(d.x, -d.z);
	float top = 0.05 + 0.2 * hash(vec2(floor(az * 14.0), 3.0));
	vec3 c = vec3(0.0);
	if (d.y > -0.02 && d.y < top) {
		vec2 g = vec2(az * 70.0, d.y * 55.0);
		vec2 f = fract(g);
		float pane = step(0.25, f.x) * step(f.x, 0.75) * step(0.3, f.y) * step(f.y, 0.75);
		c += vec3(1.0, 0.75, 0.40) * pane * step(0.68, hash(floor(g))) * 0.5;
	}
	// The lamp rows either side, a soft sodium band above the skyline.
	float side = smoothstep(0.5, 0.9, abs(d.x));
	c += vec3(1.0, 0.55, 0.2) * side * exp(-pow((d.y - 0.32) * 9.0, 2.0)) * 0.12;
	return c;
}

vec3 gradient(vec3 d) {
	float v_angle = acos(clamp(d.y, -1.0, 1.0));
	if (d.y >= 0.0) {
		float c = 1.0 - v_angle / (PI * 0.5);
		return mix(sky_horizon_color, sky_top_color, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	}
	float c = (v_angle - PI * 0.5) / (PI * 0.5);
	return mix(ground_horizon_color, ground_bottom_color, clamp(1.0 - pow(1.0 - c, 1.0 / ground_curve), 0.0, 1.0));
}

void sky() {
	vec3 col = gradient(EYEDIR);
	if (AT_CUBEMAP_PASS && city > 0.0) {
		col += city_band(EYEDIR) * city;
	}
	if (!AT_CUBEMAP_PASS) {
		vec3 m = normalize(moon_dir);
		float ang = acos(clamp(dot(EYEDIR, m), -1.0, 1.0));
		// Lit fraction: 0 at new, 1 at full.
		float lit_frac = 0.5 - 0.5 * cos(phase * TAU);
		// Amber haze: a soft glow a few moon-widths wide, scaled by how much
		// of the face is lit.
		float h = ang / moon_radius;
		col += haze_color * haze_energy * lit_frac * (exp(-h * 0.55) + 0.25 * exp(-h * 0.12));
		if (ang < moon_radius * 1.05) {
			// Disc coordinates: right/up across the face, -1..1.
			vec3 right = normalize(cross(m, vec3(0.0, 1.0, 0.0)));
			vec3 up = cross(right, m);
			vec2 uv = vec2(dot(EYEDIR, right), dot(EYEDIR, up)) / sin(moon_radius);
			float r2 = dot(uv, uv);
			float edge = 1.0 - smoothstep(0.92, 1.0, r2);
			// Sphere normal facing the viewer, lit by a sun that swings
			// round behind the moon (new) to behind the viewer (full).
			vec3 n = vec3(uv, sqrt(max(1.0 - r2, 0.0)));
			float a = phase * TAU;
			vec3 l = vec3(sin(a) * cos(tilt), sin(a) * sin(tilt), -cos(a));
			float lit = smoothstep(-0.06, 0.06, dot(n, l));
			float albedo = texture(moon_tex, uv * vec2(0.5, -0.5) + 0.5).r;
			vec3 face = moon_color * albedo * moon_energy * mix(earthshine, 1.0, lit);
			// Low in the sky the moon sits behind the city glow: tint it
			// toward amber and dim it a little (multiplicative, so the dark
			// side stays dark).
			float low = horizon_haze * (1.0 - smoothstep(0.0, 0.35, m.y));
			face *= mix(vec3(1.0), haze_color * 0.85, low);
			col = mix(col, max(col, face), edge);
		}
	}
	COLOR = col;
}
"""

static var _shader: Shader

static func build(phase: float) -> Sky:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("sky_top_color", SKY_TOP)
	mat.set_shader_parameter("sky_horizon_color", SKY_HORIZON)
	mat.set_shader_parameter("ground_bottom_color", GROUND_BOTTOM)
	mat.set_shader_parameter("ground_horizon_color", GROUND_HORIZON)
	mat.set_shader_parameter("moon_tex", load("res://assets/sky/moon.png"))
	mat.set_shader_parameter("moon_dir", moon_direction())
	mat.set_shader_parameter("moon_radius", deg_to_rad(MOON_SIZE_DEG) * 0.5)
	mat.set_shader_parameter("phase", phase)
	var sky := Sky.new()
	sky.sky_material = mat
	return sky

static func moon_direction() -> Vector3:
	var el := deg_to_rad(MOON_ELEVATION_DEG)
	var az := deg_to_rad(MOON_AZIMUTH_DEG)
	return Vector3(-sin(az) * cos(el), sin(el), -cos(az) * cos(el))

## A phase for this run, 0..1. Weighted away from the near-new phases (where
## the moon all but vanishes) so most runs show something: 1 in 10 is a new
## moon, the rest spread from thin crescent through full and back.
static func random_phase(rng: RandomNumberGenerator) -> float:
	if rng.randf() < 0.1:
		return 0.0
	return rng.randf_range(0.07, 0.93)

## City lights in the reflections on (1) or off (0); the radiance map re-renders once.
static func set_city(sky: Sky, amount: float) -> void:
	(sky.sky_material as ShaderMaterial).set_shader_parameter("city", amount)

static func set_phase(sky: Sky, phase: float) -> void:
	(sky.sky_material as ShaderMaterial).set_shader_parameter("phase", fposmod(phase, 1.0))
