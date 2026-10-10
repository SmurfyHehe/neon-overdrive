extends Node3D
class_name HeatShimmer

# Heat shimmer (2026-10-10, with exhaust flames v3): the air just behind a
# car's tailpipes wobbles, strongest after a long pull or on the limiter, and
# fades over about COOL_TAU once cruising. Behind the bone car's ghost jet a
# big shimmering cone.
#
# One MANAGER with a pool of POOL see-through quads (screen-texture
# refraction with scrolling noise). Every PICK_PERIOD it hands the quads to
# the POOL nearest hot cars on screen within RANGE of the camera; the player's
# car always gets one. Each frame the quads are placed behind their car's
# tips and told its heat. Nothing is per car: an 80-car night pays for the
# pick scan (80 distance checks, 10 times a second) and six quads at most.
#
# Heat per car (`heat` on PlayerCar and TrafficCar, 0..1) = revs x throttle,
# rising over RISE_TAU and cooling over COOL_TAU, stepped by next_heat() from
# the car's own physics tick, which for traffic only runs while the car is
# detailed (inside the draw distance): far cruising cars pay nothing.
#
# Never in the mirrors or the rear strip: the quads live on SHIMMER_LAYER,
# which CockpitFrame.MIRROR_CULL does not include. Off on the Low graphics
# preset (GraphicsSettings.preset) and with its own FxSettings switch,
# "heat_shimmer", read live every pick (so the benchmark's --shimmer and the
# pause menu need no re-apply).
#
# Cost: one screen copy for the whole frame when any quad shows (the Mobile
# renderer's hint_screen_texture), then six small quads. See the PR for the
# benchmark at 16 and 80 cars with it on and off.

const POOL := 6
const PICK_PERIOD := 0.1   # s
const RANGE := 25.0        # m from the camera
const HEAT_MIN := 0.04     # below this a car shows nothing
const RISE_TAU := 2.5      # s, heat climbing under a long pull
const COOL_TAU := 10.0     # s, fading once cruising
## Render layer (6): not in CockpitFrame.MIRROR_CULL.
const SHIMMER_LAYER := 6
const SHIMMER_BIT := 1 << (SHIMMER_LAYER - 1)
## Quad size, m, for a normal tail and the ghost jet's cone.
const SIZE := Vector2(0.7, 0.55)
const GHOST_SIZE := Vector2(2.4, 1.5)
const STRENGTH := 0.016    # screen-UV offset at full heat
const GHOST_STRENGTH := 0.028

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform, fog_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float heat = 0.0;
uniform float tick = 0.0;
uniform float seed = 0.0;
uniform float width = 0.7;
uniform float height = 0.55;
uniform float strength = 0.016;
varying vec2 sv;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	// a camera-facing quad on the node, bottom a little under the pipe
	vec3 o = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	sv = VERTEX.xy + 0.5;
	VERTEX = o + vec3(VERTEX.x * width, (VERTEX.y + 0.3) * height, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	// rising, scrolling wobble, soft-edged so the quad's outline never shows
	float n = vnoise(vec2(sv.x * 6.0 + seed, sv.y * 8.0 - tick * 3.0)) - 0.5;
	float n2 = vnoise(vec2(sv.x * 11.0 - seed, sv.y * 14.0 - tick * 5.0)) - 0.5;
	float mask = (1.0 - smoothstep(0.25, 0.5, abs(sv.x - 0.5))) * (1.0 - smoothstep(0.2, 0.5, abs(sv.y - 0.5)));
	vec2 off = vec2(n * 0.6 + n2 * 0.4, n2 * 0.5 + n * 0.3) * strength * heat * mask;
	ALBEDO = texture(screen_tex, SCREEN_UV + off).rgb;
	ALPHA = mask * clamp(heat * 3.0, 0.0, 1.0);
}
"""

var enabled := true:
	set(v):
		enabled = v
		if not v:
			_release_all()

## Quads handed out right now: [{car, mi, mat}] (tests).
var slots: Array = []
## Picks done so far (tests).
var picks := 0

var _player: Vehicle
var _traffic: Node
var _shader: Shader
var _pool: Array = []      # [{mi, mat, car}]
var _pick_t := 0.0
var _tick := 0.0

func _init(player: Vehicle) -> void:
	_player = player
	name = "HeatShimmer"

func _ready() -> void:
	_shader = Shader.new()
	_shader.code = SHADER
	for i in POOL:
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter("seed", float(i) * 3.7)
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		mi.mesh = quad
		mi.material_override = mat
		mi.layers = SHIMMER_BIT
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		mi.custom_aabb = AABB(Vector3(-1.5, -1.0, -1.5), Vector3(3.0, 3.0, 3.0))
		mi.visible = false
		add_child(mi)
		_pool.append({"mi": mi, "mat": mat, "car": null})

## True when the effect may show at all: its switch on, not the Low preset.
static func allowed() -> bool:
	return FxSettings.is_on("heat_shimmer") and GraphicsSettings.preset != "low"

## The heat law, from a car's physics tick: toward revs x throttle (1 on the
## limiter), up over RISE_TAU, down over COOL_TAU.
static func next_heat(heat: float, car: Vehicle, delta: float) -> float:
	var rpm_norm := clampf((car.motor_rpm - car.idle_rpm) / maxf(car.max_rpm - car.idle_rpm, 1.0), 0.0, 1.0)
	var target := rpm_norm * clampf(car.throttle_amount, 0.0, 1.0)
	if car.motor_is_redline:
		target = 1.0
	var tau := RISE_TAU if target > heat else COOL_TAU
	return heat + (target - heat) * (1.0 - exp(-delta / tau))

static func heat_of(car: Node) -> float:
	var h: Variant = car.get("heat")
	return float(h) if h != null else 0.0

func _process(delta: float) -> void:
	_tick += delta
	_pick_t -= delta
	if _pick_t <= 0.0:
		_pick_t = PICK_PERIOD
		_pick()
	for s in _pool:
		if s.car != null:
			_place(s)

## Hand the quads to the player and the nearest hot traffic within RANGE.
func _pick() -> void:
	picks += 1
	if not enabled or not allowed():
		_release_all()
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_release_all()
		return
	var eye := cam.global_position
	var want: Array = []
	if is_instance_valid(_player) and _player.is_inside_tree():
		want.append(_player)
	if _traffic == null:
		var game := _player.get_parent()
		_traffic = game.get("traffic") if game != null else null
	if _traffic != null:
		var near: Array = []
		for car in (_traffic.get("cars") as Array):
			if not car.visible or not car.detailed or heat_of(car) < HEAT_MIN:
				continue
			var d: float = (car as Node3D).global_position.distance_squared_to(eye)
			if d <= RANGE * RANGE:
				near.append([d, car])
		near.sort_custom(func(a, b): return a[0] < b[0])
		for n in near:
			if want.size() >= POOL:
				break
			want.append(n[1])
	# keep slots whose car is still wanted, free the rest, fill the gaps
	for s in _pool:
		if s.car != null and not want.has(s.car):
			_release(s)
	for car in want:
		if _slot_of(car) != null:
			continue
		for s in _pool:
			if s.car == null:
				s.car = car
				var ghost := _is_ghost(car)
				(s.mat as ShaderMaterial).set_shader_parameter("width", GHOST_SIZE.x if ghost else SIZE.x)
				(s.mat as ShaderMaterial).set_shader_parameter("height", GHOST_SIZE.y if ghost else SIZE.y)
				(s.mat as ShaderMaterial).set_shader_parameter("strength", GHOST_STRENGTH if ghost else STRENGTH)
				break
	slots = _pool.filter(func(s): return s.car != null)

func _slot_of(car: Node) -> Variant:
	for s in _pool:
		if s.car == car:
			return s
	return null

static func _is_ghost(car: Node) -> bool:
	var fl: Variant = car.get("flames")
	return fl is ExhaustFlames and fl.style == ExhaustFlames.Style.GHOST

## Place a quad behind its car's tips, with the car's heat.
func _place(s: Dictionary) -> void:
	var car: Node3D = s.car
	if not is_instance_valid(car) or not car.is_inside_tree():
		_release(s)
		return
	var h := heat_of(car)
	var mi: MeshInstance3D = s.mi
	if h < HEAT_MIN:
		mi.visible = false
		return
	var ghost := _is_ghost(car)
	var back := Vector3(0.0, 0.3, 2.3)
	var out := Vector3(0.0, 0.0, 1.0)
	var vis: Node3D = car.get("chassis_visual")
	if vis != null and vis.has_meta("exhaust_tips"):
		var tips: Array = vis.get_meta("exhaust_tips")
		if not tips.is_empty():
			back = Vector3.ZERO
			for tip in tips:
				back += (tip.pos if tip is Dictionary else tip) as Vector3
			back /= tips.size()
			var t0: Variant = tips[0]
			out = (t0.dir if t0 is Dictionary else Vector3(0.0, 0.0, 1.0)) as Vector3
	var at: Vector3 = car.global_transform * (back + out * (1.3 if ghost else 0.45))
	mi.global_position = at
	mi.visible = true
	var mat: ShaderMaterial = s.mat
	mat.set_shader_parameter("heat", h)
	mat.set_shader_parameter("tick", _tick)

func _release(s: Dictionary) -> void:
	s.car = null
	(s.mi as MeshInstance3D).visible = false

func _release_all() -> void:
	for s in _pool:
		_release(s)
	slots = []
