class_name PauseLook
extends Node

# The pause look (menus A-list, decided 2026-10-08):
# - freeze instantly: the tree pause already stops the car mid-motion
# - dim + light blur over the frozen frame (paused only; the title has its band)
# - a slow camera circle around the frozen car (paused and on the title)
# - the radio keeps playing, muffled (paused and title); the engine is cut
#   (GameState already mutes the Engine bus outside PLAYING)
# The Tuner screens keep their old behaviour: no circle, radio muted.
#
# The circle starts from wherever the game camera was and eases out to its
# radius and height over EASE_SECS, so pausing doesn't jump the view.

const ORBIT_SPEED := 0.1       # rad/s: one lap a minute
const ORBIT_RADIUS := 6.5      # metres from the car's centre
const ORBIT_HEIGHT := 2.0
const LOOK_HEIGHT := 0.6       # aim a little above the car's origin
const ORBIT_FOV := 55.0
const EASE_SECS := 1.4
const BLUR_FADE_SECS := 0.25
const MUFFLE_HZ := 520.0
const MUFFLE_DB := -5.0

const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float dim = 0.42;
uniform float radius = 1.6;
uniform float fade = 0.0;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * radius;
	vec3 sum = vec3(0.0);
	float wsum = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float w = 1.0 / (1.0 + float(x * x + y * y));
			sum += textureLod(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px, 1.0).rgb * w;
			wsum += w;
		}
	}
	vec3 sharp = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	COLOR = vec4(mix(sharp, sum / wsum * (1.0 - dim), fade), 1.0);
}
"""

var game_state: GameState
var player: Node3D
var game_camera: Camera3D
var orbit: Camera3D
var blur_layer: CanvasLayer
var blur_rect: ColorRect
var _active := false
var _t := 0.0
var _angle := 0.0
var _r0 := ORBIT_RADIUS
var _h0 := ORBIT_HEIGHT
var _fov0 := ORBIT_FOV
var _muffle: AudioEffectLowPassFilter
var _quieter: AudioEffectAmplify
var _blur_tween: Tween

func _init(state: GameState, car: Node3D, cam: Camera3D) -> void:
	game_state = state
	player = car
	game_camera = cam

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	orbit = Camera3D.new()
	orbit.process_mode = Node.PROCESS_MODE_ALWAYS
	orbit.fov = ORBIT_FOV
	if game_camera != null:
		orbit.cull_mask = game_camera.cull_mask | CockpitFrame.MIRROR_ONLY_BIT  # see the body even from the cockpit view
		orbit.environment = game_camera.environment
		orbit.attributes = game_camera.attributes
		orbit.near = game_camera.near
		orbit.far = game_camera.far
	add_child(orbit)
	blur_layer = CanvasLayer.new()
	blur_layer.layer = 9  # under the pause menu (10) and the title (11)
	blur_layer.visible = false
	add_child(blur_layer)
	blur_rect = ColorRect.new()
	blur_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	mat.shader = sh
	blur_rect.material = mat
	blur_layer.add_child(blur_rect)
	game_state.state_changed.connect(_on_state_changed)
	if game_state.state != GameState.State.PLAYING:
		_on_state_changed(game_state.state, GameState.State.PLAYING)

## True for the states that get the circle and the muffled radio.
static func wants_look(s: GameState.State) -> bool:
	return s == GameState.State.PAUSED or s == GameState.State.TITLE

func _on_state_changed(new_state: GameState.State, _old_state: GameState.State) -> void:
	var on := wants_look(new_state)
	if on and not _active:
		_start()
	elif not on and _active:
		_stop()
	_set_blur(new_state == GameState.State.PAUSED)
	_set_muffle(on)

func _start() -> void:
	_active = true
	_t = 0.0
	var from := game_camera.get_global_transform_interpolated() if game_camera != null else orbit.global_transform
	var off := from.origin - player.global_position
	_angle = atan2(off.x, off.z)
	_r0 = clampf(Vector2(off.x, off.z).length(), 1.0, 20.0)
	_h0 = clampf(off.y, 0.3, 8.0)
	_fov0 = game_camera.fov if game_camera != null else ORBIT_FOV
	_place(0.0)
	orbit.make_current()

func _stop() -> void:
	_active = false
	if game_camera != null and is_instance_valid(game_camera):
		game_camera.make_current()

func _process(delta: float) -> void:
	if _active:
		_place(delta)

func _place(delta: float) -> void:
	_t += delta
	var k := smoothstep(0.0, EASE_SECS, _t)
	_angle += ORBIT_SPEED * delta * k  # starts still, picks up speed as it settles
	var r := lerpf(_r0, ORBIT_RADIUS, k)
	var h := lerpf(_h0, ORBIT_HEIGHT, k)
	var centre := player.global_position
	orbit.global_position = centre + Vector3(sin(_angle) * r, h, cos(_angle) * r)
	orbit.look_at(centre + Vector3.UP * LOOK_HEIGHT, Vector3.UP)
	orbit.fov = lerpf(_fov0, ORBIT_FOV, k)

func is_orbiting() -> bool:
	return _active and orbit.current

func _set_blur(on: bool) -> void:
	if _blur_tween != null and _blur_tween.is_valid():
		_blur_tween.kill()
	var mat := blur_rect.material as ShaderMaterial
	if on:
		blur_layer.visible = true
		mat.set_shader_parameter("fade", 0.0)
		_blur_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_blur_tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("fade", v), 0.0, 1.0, BLUR_FADE_SECS)
	else:
		blur_layer.visible = false

## A deep low-pass and a few dB off the Music bus, added after the radio's own
## filters (PerspectiveAudio and RadioManager each use the first LowPass on the
## bus, so this one, appended later, never becomes theirs).
func _set_muffle(on: bool) -> void:
	var bus := AudioServer.get_bus_index(&"Music")
	if bus < 0:
		return
	if _muffle == null:
		_muffle = AudioEffectLowPassFilter.new()
		_muffle.cutoff_hz = MUFFLE_HZ
		_quieter = AudioEffectAmplify.new()
		_quieter.volume_db = MUFFLE_DB
		AudioServer.add_bus_effect(bus, _muffle)
		AudioServer.add_bus_effect(bus, _quieter)
	for i in AudioServer.get_bus_effect_count(bus):
		var e := AudioServer.get_bus_effect(bus, i)
		if e == _muffle or e == _quieter:
			AudioServer.set_bus_effect_enabled(bus, i, on)

func muffled() -> bool:
	var bus := AudioServer.get_bus_index(&"Music")
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) == _muffle:
			return AudioServer.is_bus_effect_enabled(bus, i)
	return false

func _exit_tree() -> void:
	# The bus outlives the scene (Restart reloads it): take our effects off.
	var bus := AudioServer.get_bus_index(&"Music")
	if bus < 0 or _muffle == null:
		return
	for i in range(AudioServer.get_bus_effect_count(bus) - 1, -1, -1):
		var e := AudioServer.get_bus_effect(bus, i)
		if e == _muffle or e == _quieter:
			AudioServer.remove_bus_effect(bus, i)
