extends MultiMeshInstance3D
class_name RainFall

# Falling rain (WX1 step 1, 2026-10-14, notes/weather-stages-build-spec
# section 8a). The rain you can see: streaks falling through the lamp light
# and lighting up in the headlights, slanting back as the car picks up speed.
# Look only: grip, puddles and the wet road are elsewhere (weather.gd,
# wet_grip.gd, road_wet.gd). Arcade, not a weather report: the streaks are
# longer and brighter than real rain so a downpour reads at a glance, and
# they flare in the beams.
#
# How it draws, and why it costs the CPU nothing per frame:
# - One MultiMesh of thin quads, one draw call, like the tyre smoke. Each
#   drop carries a seed in its custom data and the VERTEX shader does the
#   rest against TIME: the drop sits at a fixed spot in the world, wrapped
#   into a box around whichever camera is drawing (CAMERA_POSITION_WORLD), so
#   the rain never follows the car and the box never has to be moved. Nothing
#   is simulated on the CPU; no transforms are ever written after boot.
# - A drop is a streak along its velocity SEEN FROM THE CAR: still, it falls
#   straight; at speed the streaks lean back and stretch, the way rain does
#   through a windscreen. `car_vel` is the only uniform written while driving,
#   and only when the speed has moved by VEL_STEP (a few writes a second).
# - Lit like the smoke: a dim dusk grey everywhere, sodium under each lamp
#   pool (the lamps' fixed 25 m grid), and amber inside the headlight cone.
#   The node hangs on the player car, so the cone's place and direction are
#   the MODEL_MATRIX for free; `head_on` is written only when H flips.
# - `amount` (Weather.rain, 0..1) scales the brightness, and the visible
#   instance count follows it, so drizzle is a few faint streaks and a
#   downpour fills the box. Both are written only when the amount moves.
# - Drops nearer than NEAR_FADE fade out (no fat quads over the lens, and
#   nothing drawn inside the cabin in the cockpit view); drops beyond the box
#   are not there at all.
#
# Count by graphics preset (apply_graphics): Low 600, Medium 1400, High 2400;
# the FxSettings switch "rain" turns it off. Pin for screenshots and the
# benchmark: NEON_RAIN=<0..1> or --rain=<0..1>; NEON_WEATHER=rain/downpour
# sets the whole stage (wet road, puddles, wipers) and this follows it.
# Measured: see the PR (one draw call; the fill is thin lines).

## Box the drops live in around the camera, m: across, up, along.
const BOX := Vector3(30.0, 16.0, 40.0)
## The box sits this far above the camera's height, so more of it is sky.
const BOX_LIFT := 2.5
## Fall speed, m/s, and its per-drop spread (0.8 .. 1.2 x).
const FALL := 11.0
## "Exposure": a streak is the drop's relative velocity x this, m. Longer than
## a real shutter would give, on purpose (arcade).
const EXPOSURE := 0.07
const LEN_MIN := 0.4
const LEN_MAX := 4.0
## Streak width, m, and the least it may shrink to on screen, px.
const WIDTH := 0.04
const MIN_PX := 1.8
## Fade in from the lens, m, and out toward the box's far edge, m.
const NEAR_FADE := Vector2(0.45, 1.4)
const FAR_FADE := Vector2(16.0, 21.0)
## Brightness (additive) of a streak at full rain.
const ALPHA := 0.7
## Colours, linear: dusk grey ambient, sodium under lamps, amber in the beams.
const DUSK := Color(0.42, 0.50, 0.66)
const SODIUM := Color(1.0, 0.54, 0.12)
const BEAM := Color(1.0, 0.78, 0.45)
const DUSK_LEVEL := 0.45
const LAMP_LEVEL := 1.0
const BEAM_LEVEL := 1.6
## Headlight cone the streaks flare in (CarFx.HEADLIGHT_ANGLE 30 deg half-angle,
## range 55 m), a touch wider so the edge is soft.
const BEAM_COS := 0.84
const BEAM_RANGE := 50.0
## Drops per preset.
const COUNT := {"low": 600, "medium": 1400, "high": 2400}
const COUNT_DEFAULT := 1400
## The car's velocity uniform is rewritten when it has moved this much, m/s.
const VEL_STEP := 1.0
## Rain below this draws nothing at all (the node hides).
const RAIN_OFF := 0.02

const Weather := preload("res://scripts/world/weather.gd")

const SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

uniform float amount = 0.0;
uniform vec3 box = vec3(30.0, 16.0, 40.0);
uniform float box_lift = 2.5;
uniform float fall = 11.0;
uniform float exposure = 0.07;
uniform vec2 len_range = vec2(0.4, 4.0);
uniform float width = 0.04;
uniform float min_px = 1.8;
uniform vec2 near_fade = vec2(0.45, 1.4);
uniform vec2 far_fade = vec2(16.0, 21.0);
uniform float alpha = 0.7;
uniform vec3 car_vel = vec3(0.0);
uniform vec3 wind = vec3(0.6, 0.0, 0.0);
uniform float head_on = 0.0;
uniform vec3 head_offset = vec3(0.0, 0.62, -1.6);
uniform float beam_cos = 0.84;
uniform float beam_range = 50.0;
uniform vec3 dusk : source_color = vec3(0.42, 0.50, 0.66);
uniform vec3 sodium : source_color = vec3(1.0, 0.54, 0.12);
uniform vec3 beam : source_color = vec3(1.0, 0.78, 0.45);
uniform float dusk_level = 0.45;
uniform float lamp_level = 1.0;
uniform float beam_level = 1.6;
uniform float lamp_spacing = 25.0;
uniform float lamp_own = 6.25;
uniform float lamp_onc = 18.75;
uniform float pool_inner = 3.0;
uniform float pool_outer = 9.0;

varying float v_alpha;
varying vec3 v_col;

void vertex() {
	// INSTANCE_CUSTOM: seed xyz in [0, 1), w = per-drop speed spread.
	vec4 c = INSTANCE_CUSTOM;
	vec3 cam = CAMERA_POSITION_WORLD;
	float spd = fall * (0.8 + 0.4 * c.w);
	// The drop's home point drifts down (and with the wind) forever; it is
	// wrapped into the box around the camera, so it stays put in the world
	// while the camera slides past.
	vec3 seed_pos = c.xyz * box + vec3(0.0, -TIME * spd, 0.0) + wind * TIME * c.w;
	vec3 lo = cam + vec3(0.0, box_lift, 0.0) - 0.5 * box;
	vec3 p = lo + mod(seed_pos - lo, box);
	// The streak runs along the drop's velocity as seen from the moving car.
	vec3 rel = vec3(wind.x * c.w, -spd, wind.z * c.w) - car_vel;
	float rel_len = length(rel);
	vec3 dir = rel / max(rel_len, 0.001);
	float len = clamp(rel_len * exposure, len_range.x, len_range.y);
	vec3 to_cam = p - cam;
	float dist = length(to_cam);
	vec3 view_dir = to_cam / max(dist, 0.001);
	vec3 side = cross(dir, view_dir);
	float side_len = length(side);
	side = side_len > 0.001 ? side / side_len : vec3(1.0, 0.0, 0.0);
	// never thinner than a pixel or so: far drops would flicker away
	float px = 2.0 * dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float w = max(width, min_px * px);
	float near = smoothstep(near_fade.x, near_fade.y, dist);
	float far = 1.0 - smoothstep(far_fade.x, far_fade.y, dist);
	// Lit: dusk grey, sodium under the lamp pools (own side x > 0 every 25 m
	// from 6.25, oncoming from 18.75), amber in the headlight cone.
	float zo = mod(-p.z - lamp_own, lamp_spacing);
	float zn = mod(-p.z - lamp_onc, lamp_spacing);
	float own = smoothstep(-3.0, 3.0, p.x);
	float lamp = own * (1.0 - smoothstep(pool_inner, pool_outer, min(zo, lamp_spacing - zo)))
		+ (1.0 - own) * (1.0 - smoothstep(pool_inner, pool_outer, min(zn, lamp_spacing - zn)));
	// the node is a child of the car: its MODEL_MATRIX is the car's frame
	vec3 head_pos = (MODEL_MATRIX * vec4(head_offset, 1.0)).xyz;
	vec3 head_dir = normalize(-MODEL_MATRIX[2].xyz);
	vec3 to_drop = p - head_pos;
	float hd = length(to_drop);
	float in_cone = smoothstep(beam_cos - 0.08, beam_cos + 0.04, dot(to_drop / max(hd, 0.001), head_dir))
		* (1.0 - smoothstep(beam_range * 0.6, beam_range, hd));
	float lit_beam = head_on * in_cone;
	v_col = dusk * dusk_level + sodium * (lamp_level * lamp) + beam * (beam_level * lit_beam);
	v_alpha = alpha * amount * near * far * (0.6 + 0.4 * c.w);
	float k = v_alpha > 0.003 ? 1.0 : 0.0;   // invisible: collapse, no fill cost
	vec3 world = p + dir * (VERTEX.y * len * k) + side * (VERTEX.x * w * k);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	// soft across the streak, soft ends
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = 1.0 - abs(UV.y * 2.0 - 1.0);
	ALBEDO = v_col;
	ALPHA = v_alpha * across * smoothstep(0.0, 0.25, along);
}
"""

## Pinned rain amount (NEON_RAIN / --rain), or -1 to follow the weather.
static var pin := -1.0

var enabled := true:
	set(v):
		enabled = v
		_apply_visible()

## Rain amount drawn now (0..1): the `amount` uniform.
var amount := 0.0
## Drops the current preset allows (instance_count).
var capacity := 0

var _player: PlayerCar
var _mat: ShaderMaterial
var _vel := Vector3(INF, INF, INF)
var _head_on := -1.0
var _rng := RandomNumberGenerator.new()

func _init(player: PlayerCar) -> void:
	_player = player
	name = "RainFall"

func _ready() -> void:
	var shader := Shader.new()
	shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("box", BOX)
	_mat.set_shader_parameter("box_lift", BOX_LIFT)
	_mat.set_shader_parameter("fall", FALL)
	_mat.set_shader_parameter("exposure", EXPOSURE)
	_mat.set_shader_parameter("len_range", Vector2(LEN_MIN, LEN_MAX))
	_mat.set_shader_parameter("width", WIDTH)
	_mat.set_shader_parameter("min_px", MIN_PX)
	_mat.set_shader_parameter("near_fade", NEAR_FADE)
	_mat.set_shader_parameter("far_fade", FAR_FADE)
	_mat.set_shader_parameter("alpha", ALPHA)
	_mat.set_shader_parameter("dusk", Vector3(DUSK.r, DUSK.g, DUSK.b))
	_mat.set_shader_parameter("sodium", Vector3(SODIUM.r, SODIUM.g, SODIUM.b))
	_mat.set_shader_parameter("beam", Vector3(BEAM.r, BEAM.g, BEAM.b))
	_mat.set_shader_parameter("dusk_level", DUSK_LEVEL)
	_mat.set_shader_parameter("lamp_level", LAMP_LEVEL)
	_mat.set_shader_parameter("beam_level", BEAM_LEVEL)
	_mat.set_shader_parameter("beam_cos", BEAM_COS)
	_mat.set_shader_parameter("beam_range", BEAM_RANGE)
	_mat.set_shader_parameter("lamp_spacing", RoadChunkBuilder.LAMP_SPACING)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The box is wrapped around the camera in the shader, so the mesh's own
	# bounds would cull it: a custom AABB that is never off screen.
	custom_aabb = AABB(Vector3(-4096.0, -4096.0, -4096.0), Vector3(8192.0, 8192.0, 8192.0))
	add_to_group(GraphicsSettings.GROUP)
	_build(_count_for(GraphicsSettings.preset))
	var p := Benchmark.opt("rain") if Benchmark.requested() else ""
	if p == "":
		p = OS.get_environment("NEON_RAIN")
	if p.is_valid_float():
		pin = clampf(float(p), 0.0, 1.0)
	sync()

## Drops for a graphics preset ("custom" keeps Medium's).
static func _count_for(preset: String) -> int:
	return int(COUNT.get(preset, COUNT_DEFAULT))

## (Re)builds the pool: `n` quads, each with its own seed. Done once per
## preset change, never per frame.
func _build(n: int) -> void:
	capacity = n
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = n
	mm.visible_instance_count = 0
	_rng.seed = 77
	for i in n:
		mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf(), _rng.randf(), _rng.randf()))
	multimesh = mm
	_apply_visible()

## Graphics preset changed: the drop count follows it.
func apply_graphics() -> void:
	var n := _count_for(GraphicsSettings.preset)
	if n != capacity:
		_build(n)

## Rain to draw: the pin, else Weather's falling amount.
static func rain_amount() -> float:
	if pin >= 0.0:
		return pin
	return clampf(Weather.rain, 0.0, 1.0)

## Called once per physics tick by FxPack (after Weather.step). Cheap: a few
## compares; uniforms are written only when something moved.
func sync() -> void:
	var en := FxSettings.is_on("rain")
	if en != enabled:
		enabled = en
	var a := rain_amount()
	if a != amount:
		amount = a
		_mat.set_shader_parameter("amount", amount)
		_apply_visible()
	if not visible or _player == null:
		return
	var v := _player.linear_velocity
	if v.distance_squared_to(_vel) >= VEL_STEP * VEL_STEP:
		_vel = v
		_mat.set_shader_parameter("car_vel", v)
	var on := 1.0 if _player.headlights_on else 0.0
	if on != _head_on:
		_head_on = on
		_mat.set_shader_parameter("head_on", on)

## Visible drops: the count follows the rain (drizzle is sparse); the node
## hides altogether when there is none, so a dry night costs no draw call.
func _apply_visible() -> void:
	var on := enabled and amount > RAIN_OFF and capacity > 0
	visible = on
	if multimesh != null:
		multimesh.visible_instance_count = int(round(capacity * clampf(amount, 0.0, 1.0))) if on else 0

## Floating-origin recentre: the drops are placed from the camera in the
## shader and the node rides on the car, so nothing here moves.
func shift_world(_offset: Vector3) -> void:
	pass
