extends CanvasLayer
class_name WindscreenDrops

# Rain on the windscreen, cockpit view (WX1 step 2, 2026-10-14, weather spec
# section 8b). Drops bead up on the glass, bend what is behind them, and the
# wipers clear two arcs that fill back in with the rain. Arcade: the drops
# are bigger and the arcs cleaner than a real screen.
#
# How it draws, and why it costs the CPU nothing:
# - One full-screen rect under the HUD (like FilmGrain), shown only in the
#   cockpit view. The shader grows the drops from a hash of a cell grid, so
#   every car's screen gets them with no per-car glass mesh or data; the
#   two wiper arcs are drawn in screen space from where the wipers sit in
#   every cockpit (pivots under the bottom edge, parked to the right,
#   sweeping up; the eye is close to the glass, so the exterior arm's 68
#   degrees fills about 100 degrees of the view), timed by the real wipers'
#   phase, not drawn from the exterior arms, so they line up by eye rather
#   than by the millimetre.
# - Stateless wiping: a drop in a cell is shown only if it appeared after
#   the blade last crossed that cell's angle. With the blade's phase and
#   stroke rate as uniforms the last crossing time is a formula, so nothing
#   has to be remembered between frames (no mask texture, no read-back).
# - Per physics tick FxPack.tick writes `now` and the wiper phase (two
#   floats) and, when they moved, the rain amount and the view; the clock
#   stops with the game (pause, photo mode).
# - Refraction is one screen-texture read per pixel, the same read
#   HeatShimmer does. Off on Low (the rect hides): the Low preset keeps the
#   falling rain and the wipers, as the spec says.
#
# Pins: NEON_RAIN / --rain (RainFall.pin) drive this too; the FxSettings
# "rain" switch turns it off with the streaks.

const STRENGTH := 0.022      # refraction, screen UV at a drop's edge
const DROP_DENSITY := 0.55   # share of cells that hold a drop at full rain
const REGROW := 0.35         # new drops per second per cell at full rain

const SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;
uniform float now = 0.0;
uniform float phase = 0.0;
uniform float rate = 0.0;
uniform float sweep = 1.75;
uniform float strength = 0.022;
uniform float density = 0.55;
uniform float regrow = 0.35;
uniform vec2 pivot_l = vec2(0.22, 1.12);
uniform vec2 pivot_r = vec2(0.62, 1.12);
uniform float reach = 1.05;
uniform vec2 cells = vec2(18.0, 10.0);

float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

// Seconds since the blade last stood at angle `a` (huge when it never did).
float since_wiped(float a) {
	if (rate <= 0.0 || a < 0.0 || a > sweep) {
		return 1e9;
	}
	float pa = acos(clamp(1.0 - 2.0 * a / sweep, -1.0, 1.0)) / 6.2831853;
	float d1 = mod(phase - pa, 1.0);
	float d2 = mod(phase - (1.0 - pa), 1.0);
	return min(d1, d2) / rate;
}

// How long ago the blade whose pivot is `pv` last passed over `p`.
float wiped_at(vec2 p, vec2 pv) {
	vec2 d = p - pv;
	float r = length(d);
	if (r > reach || r < 0.06) {
		return 1e9;
	}
	float a = atan(-d.y, d.x);
	return since_wiped(a);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x;
	vec2 p = vec2(UV.x * aspect, UV.y);
	float wiped = min(wiped_at(p, vec2(pivot_l.x * aspect, pivot_l.y)), wiped_at(p, vec2(pivot_r.x * aspect, pivot_r.y)));
	vec2 offset = vec2(0.0);
	float bead = 0.0;
	// two drop layers: big beads and a fine mist
	for (int layer = 0; layer < 2; layer++) {
		vec2 g = cells * (layer == 0 ? 1.0 : 2.3);
		vec2 cp = p * g;
		vec2 id = floor(cp);
		vec2 f = fract(cp);
		float h1 = hash(id + float(layer) * 7.1);
		float h2 = hash(id + 3.3 + float(layer) * 7.1);
		float h3 = hash(id + 5.7 + float(layer) * 7.1);
		// the drop's age: cells refill at `regrow` per second, scaled by rain
		float cycle = max(regrow * amount, 0.02);
		float age = mod(now * cycle + h3, 1.0) / cycle;
		if (age > wiped || h3 > density * amount + 0.02 * amount) {
			continue;
		}
		vec2 c = vec2(0.15 + 0.7 * h1, 0.15 + 0.7 * h2);
		float rad = (layer == 0 ? 0.14 : 0.07) + (layer == 0 ? 0.2 : 0.06) * hash(id + 9.1);
		// a drop sags as it ages, then runs a little
		float sag = min(age * 0.06, 0.25);
		vec2 d = f - c - vec2(0.0, sag);
		d.y *= 0.8;
		float r = length(d) / rad;
		if (r < 1.0) {
			float dome = sqrt(1.0 - r * r);
			offset += d * dome * strength * (layer == 0 ? 1.0 : 0.5) / rad;
			bead = max(bead, dome * (layer == 0 ? 1.0 : 0.45));
		}
	}
	vec3 col = texture(screen_tex, SCREEN_UV + offset).rgb;
	// a soft rim on each bead so it reads even on a dark road
	col += vec3(0.06, 0.05, 0.04) * bead * bead;
	COLOR = vec4(col, clamp(bead * 2.0, 0.0, 1.0) * step(0.001, amount));
}
"""

var enabled := true:
	set(v):
		enabled = v
		_apply_visible()

var amount := 0.0
var now := 0.0
var in_cockpit := false
var _mat: ShaderMaterial
var _rect: ColorRect
var _player: PlayerCar
var _camera: ChaseCamera
var _phase_prev := -1.0

func _init(player: PlayerCar, camera: ChaseCamera) -> void:
	_player = player
	_camera = camera
	name = "WindscreenDrops"

func _ready() -> void:
	layer = 0  # under the HUD (layer 1) and the menus (layer 10)
	var shader := Shader.new()
	shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("strength", STRENGTH)
	_mat.set_shader_parameter("density", DROP_DENSITY)
	_mat.set_shader_parameter("regrow", REGROW)
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	add_to_group(GraphicsSettings.GROUP)
	_apply_visible()

## Low keeps the falling rain and the wipers but not the glass pass.
func apply_graphics() -> void:
	_apply_visible()

func tier_allows() -> bool:
	return GraphicsSettings.preset != "low"

## Once per physics tick (FxPack.tick): the clock, the wiper phase and
## stroke rate, and the rain amount when it moved.
func sync() -> void:
	var en := FxSettings.is_on("rain")
	if en != enabled:
		enabled = en
	var a := RainFall.rain_amount()
	var cockpit := _camera != null and _camera.view == ChaseCamera.View.COCKPIT
	if a != amount or cockpit != in_cockpit:
		amount = a
		in_cockpit = cockpit
		_mat.set_shader_parameter("amount", amount)
		_apply_visible()
	if not visible:
		return
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	now += dt
	_mat.set_shader_parameter("now", now)
	var w := _player.get_node_or_null("CarWipers") as CarWipers if _player != null else null
	var phase := w.phase if w != null else 0.0
	var rate := 0.0
	if _phase_prev >= 0.0 and phase != _phase_prev:
		rate = fposmod(phase - _phase_prev, 1.0) / dt
	_phase_prev = phase
	_mat.set_shader_parameter("phase", phase)
	_mat.set_shader_parameter("rate", rate)

func _apply_visible() -> void:
	visible = enabled and in_cockpit and amount > RainFall.RAIN_OFF and tier_allows()
