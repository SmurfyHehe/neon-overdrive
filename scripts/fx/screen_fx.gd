extends CanvasLayer
class_name ScreenFx

# Vignette + speed lines (effects pack v1, 2026-10-06). One full-screen rect,
# one shader pass, under the HUD like FilmGrain: no screen read-back, a few
# ALU ops per pixel.
#
# - Vignette: the corners sink toward the palette's shadow blue (#0E1424), a
#   little more the faster the car goes.
# - Speed lines: thin streaks racing outward from the centre, only outside the
#   middle of the frame, from SPEED_LINES_FROM (150 km/h) up to full strength at
#   SPEED_LINES_FULL (400 km/h), racing outward faster the faster the car goes. Tinted silver warmed toward amber --
#   no neon. Kept on in the cockpit (they read like the pillars rushing past),
#   dialled down a bit so the dash stays clean; COCKPIT_LINES = 0 turns them off there.

const VIGNETTE_REST := 0.32   # corner darkening at a standstill
const VIGNETTE_SPEED := 0.28  # extra at VIGNETTE_FULL (0.17 at 245 km/h, about as before)
const VIGNETTE_FULL := SpeedFeel.EFFECTS_FULL  # m/s where the extra is all there (400 km/h)
const SPEED_LINES_FROM := 41.7  # m/s, 150 km/h
const SPEED_LINES_FULL := SpeedFeel.EFFECTS_FULL  # m/s, 400 km/h
const SPEED_LINES_MAX := 0.5    # peak streak opacity (0.31 at 245 km/h, about as before)
## How fast the streaks race outward, in screen-radius cycles per second. Was a
## fixed 6; now it follows the car's speed.
const FLOW_SLOW := 9.0          # at SPEED_LINES_FROM
const FLOW_FAST := 24.0         # at SPEED_LINES_FULL
const FLOW_WRAP := 3600.0
const COCKPIT_LINES := 0.6      # streak strength multiplier in the cockpit view
const RATE := 6.0               # 1/s smoothing so neither effect pops

const SHADER := """
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float vignette = 0.0;
uniform float lines = 0.0;
uniform float flow = 0.0;
uniform vec3 vignette_color : source_color = vec3(0.055, 0.078, 0.141);
uniform vec3 line_color : source_color = vec3(0.86, 0.80, 0.66);

float hash(float p) {
	return fract(sin(p * 127.1 + 311.7) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;  // aspect: corners at r ~ 1.0 on 16:9
	float r = length(uv);
	float v = vignette * smoothstep(0.38, 1.0, r);

	float s = 0.0;
	if (lines > 0.001) {
		float seg = atan(uv.y, uv.x) / 6.2831853 * 110.0;
		float id = floor(seg);
		float h = hash(id);
		// a different quarter of the streaks is lit each 1/24 s, like film frames
		float lit = step(0.74, hash(id + floor(TIME * 24.0 + h * 9.0) * 0.37));
		float w = abs(fract(seg) - 0.5);
		float streak = 1.0 - smoothstep(0.0, 0.04 + 0.06 * h, w);
		// short dashes racing outward
		float dash = fract(r * 4.5 - flow * (1.0 + 0.66 * h) + h * 7.0);
		float along = smoothstep(0.0, 0.25, dash) * smoothstep(0.7, 0.45, dash);
		// only the outer part of the frame; the car and the road ahead stay clean
		float edge = smoothstep(0.42, 0.85, r);
		s = lines * lit * streak * along * edge;
	}

	// out = dst*(1-v)*(1-s) + vignette_color*v*(1-s) + line_color*s
	float a = 1.0 - (1.0 - v) * (1.0 - s);
	vec3 c = vignette_color * v * (1.0 - s) + line_color * s;
	COLOR = vec4(c / max(a, 0.0001), a);
}
"""

var vignette_on := true:
	set(v):
		vignette_on = v
		_update_visible()
var speed_lines_on := true:
	set(v):
		speed_lines_on = v
		_update_visible()

var vignette := 0.0  # current, readable by tests
var lines := 0.0
var flow := 0.0      # streak phase, advanced by speed

var _player: PlayerCar
var _camera: ChaseCamera
var _rect: ColorRect
var _mat: ShaderMaterial

func _init(player: PlayerCar, camera: ChaseCamera) -> void:
	_player = player
	_camera = camera

func _ready() -> void:
	layer = 0  # under the HUD (layer 1) and the menus (layer 10), over the film grain
	var shader := Shader.new()
	shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_update_visible()

func _update_visible() -> void:
	if _rect != null:
		_rect.visible = vignette_on or speed_lines_on

func _process(delta: float) -> void:
	if not _rect.visible:
		return
	var speed := absf(_player.current_speed())
	var k := 1.0 - exp(-RATE * delta)
	var want_v := VIGNETTE_REST + VIGNETTE_SPEED * clampf(speed / VIGNETTE_FULL, 0.0, 1.0) if vignette_on else 0.0
	var want_l := 0.0
	if speed_lines_on:
		# ease-out: most of the rise comes early, but it never stops growing
		var over := clampf((speed - SPEED_LINES_FROM) / (SPEED_LINES_FULL - SPEED_LINES_FROM), 0.0, 1.0)
		want_l = SPEED_LINES_MAX * (1.0 - (1.0 - over) * (1.0 - over))
		flow = fmod(flow + lerpf(FLOW_SLOW, FLOW_FAST, over) * delta, FLOW_WRAP)
		if _camera != null and _camera.view == ChaseCamera.View.COCKPIT:
			want_l *= COCKPIT_LINES
	vignette = lerpf(vignette, want_v, k)
	lines = lerpf(lines, want_l, k)
	_mat.set_shader_parameter("vignette", vignette)
	_mat.set_shader_parameter("lines", lines)
	_mat.set_shader_parameter("flow", flow)
