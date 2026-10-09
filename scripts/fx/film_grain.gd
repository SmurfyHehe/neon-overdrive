extends CanvasLayer
class_name FilmGrain

# Film grain (stage A, 2026-10-04): the "grainy filter" from Look Board
# option B ("Gritty PS2 night"), which Roy picked. A full-screen rect that
# multiplies the 3D view by 1 - strength * noise, so it only ever darkens --
# it can't lift the blacks into grey. The noise changes 24 times a second,
# like film. One cheap pass; no screen read-back.

const STRENGTH := 0.09

const SHADER := """
shader_type canvas_item;
render_mode blend_mul, unshaded;

uniform float strength = 0.09;
uniform float fps = 24.0;

float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	float frame = floor(TIME * fps);
	float n = hash(floor(FRAGCOORD.xy) + frame * vec2(17.0, 59.0));
	COLOR = vec4(vec3(1.0 - strength * n), 1.0);
}
"""

func _ready() -> void:
	layer = 0  # under the HUD (layer 1) and the menus (layer 10)
	var shader := Shader.new()
	shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("strength", STRENGTH)
	var rect := ColorRect.new()
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
