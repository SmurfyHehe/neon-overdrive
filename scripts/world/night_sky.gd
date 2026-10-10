extends RefCounted
class_name NightSky

# Night sky with a phasing moon (2026-10-07), night pass (2026-10-10).
#
# One sky shader, no extra draw calls:
# - Base gradient: palette navy at the top (#0E1424 "Dusk") down to a lighter
#   navy at the horizon, with the same curve maths as Godot's procedural sky.
# - City glow dome: a sodium glow that sits on the horizon and dies out
#   12-15 degrees up. Colour and height come from the district the player is
#   in (SkyDirector blends them as the road changes district).
# - Stars: a hashed grid over the sky, one pattern per night (the night number
#   from NightClock is the seed). They fade into the glow dome and dim a
#   little under a bright moon.
# - Moon: assets/sky/moon.png lit by a terminator mask on a sphere. Phase runs
#   on a 29.5-night cycle (phase_for_night); the moon hangs up and to one side
#   on a path picked per night (moon_path), rising through the night.
#   The wide amber haze is gone; a tight silver halo is all that is left.
# - Dither: interleaved gradient noise, one 8-bit step, so the navy gradient
#   does not band.
#
# Moon, stars and dither are drawn in the main sky pass only (not
# AT_CUBEMAP_PASS), so the radiance map stays a plain gradient. No TIME in
# the shader, and the values that move during a night (moon direction, glow
# dome) are global shader parameters, so the radiance map is only re-rendered
# when the night changes (phase and star seed are ordinary uniforms).
#
# Dawn (2026-10-10, sky PR 2): from 5 a.m. (DAWN_START_MINUTES) to 6 a.m. the
# clock drives a global `sky_dawn` 0..1. The navy top lifts toward #1B2A4A, a
# dim amber band grows on one side of the horizon (dawn_dir, picked per night),
# the glow dome swells, and stars and moon wash out. Nothing is lit by it: the
# ambient pin stays, so asphalt keeps its colour.
#
# Ambient light is no longer taken from the sky (game.gd pins it to a fixed
# colour), so repainting the sky never lifts the asphalt.

## Palette navy ("Amber vs. Dusk"): #0E1424 at the top, toward #1B2A4A low.
const SKY_TOP := Color("0E1424")
const SKY_HORIZON := Color("15203A")
const GROUND_BOTTOM := Color(0.008, 0.008, 0.01)
const GROUND_HORIZON := Color(0.11, 0.065, 0.04)

## City glow dome per district (districts.gd names): colour at the horizon
## and how many degrees up it reaches. Downtown is the brightest and widest,
## industrial the dimmest and lowest.
const GLOW := {
	"downtown": {"color": Color(0.21, 0.11, 0.05), "height_deg": 15.0},
	"strip": {"color": Color(0.20, 0.115, 0.055), "height_deg": 14.0},
	"residential": {"color": Color(0.16, 0.09, 0.047), "height_deg": 13.0},
	"industrial": {"color": Color(0.13, 0.07, 0.04), "height_deg": 12.0},
}
const DEFAULT_DISTRICT := "downtown"

const MOON_SIZE_DEG := 2.5
## Synodic month, nights. Night 1 starts at a waxing crescent so the first
## nights show a moon that grows.
const PHASE_CYCLE_NIGHTS := 29.53
const PHASE_NIGHT_1 := 0.18

## Where the moon can hang: up and to one side of the road ahead. Elevation
## stays under ~20 degrees so it is on screen from the chase camera (which
## pitches ~10 degrees down with a 70 degree vertical FOV).
const MOON_EL_RISE := Vector2(12.0, 15.0)   # degrees at 8 p.m., min/max
const MOON_EL_CLIMB := Vector2(4.0, 6.0)    # degrees gained by 6 a.m.
const MOON_AZ := Vector2(16.0, 30.0)        # degrees off straight ahead
const MOON_AZ_DRIFT := 4.0                  # degrees it slides outward by 6 a.m.

## Dawn runs from 5 a.m. to 6 a.m. (game minutes since 8 p.m.).
const DAWN_START_MINUTES := 540.0

## 0 until 5 a.m., 1 at 6 a.m., eased.
static func dawn_for_minutes(minutes: float) -> float:
	return smoothstep(DAWN_START_MINUTES, 600.0, minutes)

const SHADER := """
shader_type sky;

uniform vec3 sky_top_color : source_color;
uniform vec3 sky_horizon_color : source_color;
uniform vec3 ground_bottom_color : source_color;
uniform vec3 ground_horizon_color : source_color;
uniform float sky_curve = 0.25;
uniform float ground_curve = 0.02;

// City glow dome: colour on the horizon, gone sky_glow_height radians up.
// These and the moon direction are GLOBAL shader parameters (project.godot
// [shader_globals]) on purpose: setting an ordinary sky uniform marks the
// sky dirty and re-renders the radiance map, which on the Mobile renderer
// stalled the main thread for ~150 ms per change (benchmark, 2026-10-10:
// process max 20 ms -> 190 ms while the dome blended). Globals change
// nothing on the material, so the main pass follows them for free and the
// radiance map keeps whatever it last rendered.
global uniform vec4 sky_glow_color : source_color;
global uniform float sky_glow_height;
global uniform vec3 sky_moon_dir;
global uniform float sky_dawn;

// Stars: seed per night; density is the share of grid cells holding one.
uniform float star_seed = 1.0;
uniform float star_density = 0.13;
uniform float star_energy = 0.9;
uniform float star_cell = 0.0262;   // radians, 1.5 degrees
uniform float star_radius = 0.0017; // radians, ~0.1 degree

uniform sampler2D moon_tex : source_color, filter_linear, repeat_disable;
uniform float moon_radius = 0.0218; // half the angular size, radians
uniform float phase = 0.5;          // 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter
uniform float tilt = 0.5;           // terminator tilt, radians
uniform vec3 moon_color : source_color = vec3(0.78, 0.80, 0.84);  // silver
uniform float moon_energy = 1.15;
uniform float earthshine = 0.01;
uniform vec3 halo_color : source_color = vec3(0.85, 0.82, 0.76);  // silver, a touch warm
uniform float halo_energy = 0.03;

// Dawn: horizontal direction the first light comes from (set per night).
uniform vec3 dawn_dir = vec3(0.0, 0.0, -1.0);

float hash1(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

vec3 hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yzz) * p.zyx);
}

vec3 gradient(vec3 d) {
	float v_angle = acos(clamp(d.y, -1.0, 1.0));
	if (d.y >= 0.0) {
		float c = 1.0 - v_angle / (PI * 0.5);
		// Dawn lifts the top toward #1B2A4A and the horizon toward a dusky navy.
		vec3 top = mix(sky_top_color, vec3(0.011, 0.023, 0.069), sky_dawn);
		vec3 hor = mix(sky_horizon_color, vec3(0.030, 0.045, 0.100), sky_dawn);
		vec3 col = mix(hor, top, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
		float elev = PI * 0.5 - v_angle;
		// The dome replaces the navy rather than adding to it: navy plus
		// sodium reads mauve, and the palette has no magenta.
		float g = 1.0 - clamp(elev / (sky_glow_height * (1.0 + 0.7 * sky_dawn)), 0.0, 1.0);
		col = mix(col, sky_glow_color.rgb, (g * g * (3.0 - 2.0 * g)) * g);
		// First light: a dim amber band on the dawn side, 25 degrees high.
		float side = 0.3 + 0.7 * pow(max(dot(normalize(d.xz + vec2(1e-5)), dawn_dir.xz), 0.0), 2.0);
		float band = 1.0 - smoothstep(0.0, 0.44, elev);
		return mix(col, vec3(0.34, 0.17, 0.05), sky_dawn * side * band * band);
	}
	float c = (v_angle - PI * 0.5) / (PI * 0.5);
	return mix(ground_horizon_color, ground_bottom_color, clamp(1.0 - pow(1.0 - c, 1.0 / ground_curve), 0.0, 1.0));
}

// Stars on an azimuth/elevation grid. Cells are star_cell tall and about as
// wide (the azimuth count shrinks with cos(elevation)), one star at most per
// cell, placed and weighted by the cell's hash.
vec3 stars(vec3 d, float elev) {
	if (elev <= 0.0) {
		return vec3(0.0);
	}
	float az = atan(d.x, -d.z) + PI;           // 0..2PI
	float n_az = max(floor(TAU / star_cell * cos(elev)), 8.0);
	float cell_w = TAU / n_az;
	vec2 cell = vec2(floor(az / cell_w), floor(elev / star_cell));
	vec3 h = hash3(vec3(cell, star_seed * 7.13 + 1.0));
	if (h.x > star_density) {
		return vec3(0.0);
	}
	vec2 centre = (cell + vec2(0.1 + 0.8 * h.y, 0.1 + 0.8 * h.z)) * vec2(cell_w, star_cell);
	float daz = (az - centre.x) * cos(elev);
	float del = elev - centre.y;
	float dist = sqrt(daz * daz + del * del);
	float b = hash1(vec3(cell, star_seed * 3.71 + 9.0));
	float bright = b * b * b;                   // mostly dim, a few bright
	float disc = 1.0 - smoothstep(0.0, star_radius * (1.0 + bright), dist);
	vec3 tint = mix(vec3(0.72, 0.78, 0.90), vec3(0.95, 0.88, 0.74), hash1(vec3(cell, 5.0)));
	return tint * disc * (0.25 + bright) * star_energy;
}

void sky() {
	vec3 base = gradient(EYEDIR);
	vec3 col = base;
	if (!AT_CUBEMAP_PASS) {
		float elev = asin(clamp(EYEDIR.y, -1.0, 1.0));
		float lit_frac = 0.5 - 0.5 * cos(phase * TAU);
		// Stars: hidden inside the glow dome, dimmer under a bright moon.
		float clear = smoothstep(sky_glow_height * 0.5, sky_glow_height * 1.6, elev);
		col += stars(EYEDIR, elev) * clear * (1.0 - 0.45 * lit_frac) * (1.0 - smoothstep(0.1, 0.75, sky_dawn));
		vec3 m = normalize(sky_moon_dir);
		float ang = acos(clamp(dot(EYEDIR, m), -1.0, 1.0));
		// A tight silver halo, two moon-widths wide, scaled by the lit face.
		float h = ang / moon_radius;
		float wash = 1.0 - 0.6 * sky_dawn;  // the moon fades as the sky lifts
			col += halo_color * halo_energy * lit_frac * exp(-h * 0.9) * wash;
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
			vec3 face = moon_color * albedo * moon_energy * wash * mix(earthshine, 1.0, lit);
			// The disc covers the stars behind it: blend from the plain
			// gradient, not from the starry sky.
			col = mix(col, max(base, face), edge);
		}
		// Dither: one 8-bit sRGB step of interleaved gradient noise, sized
		// for the local brightness so dark navy gets it too.
		float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		col += (n - 0.5) * (2.4 / 255.0) * pow(max(col, vec3(1e-5)), vec3(0.583));
	}
	COLOR = max(col, vec3(0.0));
}
"""

static var _shader: Shader

## The sky for a night: phase, star pattern and the moon's 8 p.m. position
## all follow the night number. district picks the glow dome.
static func build(night: int, district: String = DEFAULT_DISTRICT) -> Sky:
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
	mat.set_shader_parameter("moon_radius", deg_to_rad(MOON_SIZE_DEG) * 0.5)
	var sky := Sky.new()
	sky.sky_material = mat
	set_night(sky, night)
	set_moon_time(sky, night, 0.0)
	set_glow(sky, GLOW[district].color, GLOW[district].height_deg)
	return sky

## Phase for a night, 0..1: 0 new, 0.5 full, on a 29.53-night cycle.
static func phase_for_night(night: int) -> float:
	return fposmod(PHASE_NIGHT_1 + float(night - 1) / PHASE_CYCLE_NIGHTS, 1.0)

## Phase, star seed and moon path for a night.
static func set_night(sky: Sky, night: int) -> void:
	var mat := sky.sky_material as ShaderMaterial
	mat.set_shader_parameter("phase", phase_for_night(night))
	mat.set_shader_parameter("star_seed", float(posmod(night, 1000)))
	# First light comes from the side the moon is not on, 35-65 degrees off the road.
	var off := 35.0 + 30.0 * float(posmod(hash([night, "dawn"]), 100)) / 100.0
	var a := deg_to_rad(-float(moon_path(night).side) * off)
	mat.set_shader_parameter("dawn_dir", Vector3(-sin(a), 0.0, -cos(a)))

## The moon's path tonight: {side, el0, el1, az0, az1} in degrees, from a
## hash of the night number. side is -1 (right of the road) or +1 (left).
static func moon_path(night: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([night, "moon_path"])
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var el0 := rng.randf_range(MOON_EL_RISE.x, MOON_EL_RISE.y)
	var az0 := rng.randf_range(MOON_AZ.x, MOON_AZ.y)
	return {
		"side": side,
		"el0": el0, "el1": el0 + rng.randf_range(MOON_EL_CLIMB.x, MOON_EL_CLIMB.y),
		"az0": az0 * side, "az1": (az0 + MOON_AZ_DRIFT) * side,
	}

## Where the moon is at `t` (0 at 8 p.m., 1 at 6 a.m.) on a night's path.
static func moon_direction(night: int, t: float) -> Vector3:
	var p := moon_path(night)
	t = clampf(t, 0.0, 1.0)
	var el := deg_to_rad(lerpf(p.el0, p.el1, t))
	var az := deg_to_rad(lerpf(p.az0, p.az1, t))  # positive = left of straight ahead
	return Vector3(-sin(az) * cos(el), sin(el), -cos(az) * cos(el))

## Moon direction and glow dome are global shader parameters (see the shader
## header): there is one sky, and changing them must not dirty its material.
static var moon_dir := Vector3(0.0, 0.3, -0.95)  # last value set, world space

static func set_moon_time(_sky: Sky, night: int, t: float) -> void:
	moon_dir = moon_direction(night, t)
	RenderingServer.global_shader_parameter_set("sky_moon_dir", moon_dir)

static func set_glow(_sky: Sky, color: Color, height_deg: float) -> void:
	RenderingServer.global_shader_parameter_set("sky_glow_color", color)
	RenderingServer.global_shader_parameter_set("sky_glow_height", deg_to_rad(height_deg))

## The dawn factor is a global shader parameter too (see the shader header).
static var dawn := 0.0

static func set_dawn(value: float) -> void:
	dawn = clampf(value, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("sky_dawn", dawn)

static func set_phase(sky: Sky, phase: float) -> void:
	(sky.sky_material as ShaderMaterial).set_shader_parameter("phase", fposmod(phase, 1.0))

## Where the moon is now (global_shader_parameter_get is editor-only).
static func moon_dir_of(_sky: Sky) -> Vector3:
	return moon_dir
