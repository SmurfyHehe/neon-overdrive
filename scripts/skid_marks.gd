extends MultiMeshInstance3D
class_name SkidMarks

# Skid marks (effects pack v1, 2026-10-06): dark rubber strips laid where a
# tyre is sliding, from the same GEVP slip signal CarAudio's squeal uses
# (slide angle slip_vector.x, slip ratio slip_vector.y, weighted by load).
#
# One MultiMesh of flat quads in a ring buffer: a strip is one quad per
# SEG_LEN of travel, so the whole buffer holds MAX_SEGMENTS * SEG_LEN metres of
# rubber across all four wheels. Nothing is rebuilt per frame: a quad's birth
# time and strength ride in INSTANCE_CUSTOM and the shader fades it against a
# `now` uniform, and expired quads are reaped a few per tick by collapsing
# their transform to zero. Drawn with blend_mul, so the mark only darkens road
# that is lit (lamps, headlights) and stays invisible on the black beyond, the
# way rubber on asphalt reads. One draw call, no extra lights, no decals.
#
# Laid in world space on the physics tick; shift_world() moves every quad
# when game.gd recentres the floating origin (issue #26 pattern).

const MAX_SEGMENTS := 512
const SEG_LEN := 0.5      # m of travel per quad
const WIDTH := 0.26       # m, the tyre plus its soft edges (TestCarBuilder.TYRE_WIDTH 0.24)
const LIFT := 0.015       # m above the contact point, against z-fighting
const LIFE := 30.0        # s until a mark is gone (fades over the second half)
const MIN_STRENGTH := 0.2 # slip below this lays nothing
const BREAK_DIST := 4.0   # a jump bigger than this (reset, teleport) starts a new strip
const REAP_PER_TICK := 4

const SHADER := """
shader_type spatial;
render_mode blend_mul, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float now = 0.0;
uniform float life = 30.0;
uniform vec3 rubber : source_color = vec3(0.2, 0.2, 0.22);

varying float v_strength;

void vertex() {
	float age = now - INSTANCE_CUSTOM.x;
	float fade = 1.0 - smoothstep(life * 0.5, life, age);
	v_strength = INSTANCE_CUSTOM.y * fade;
}

void fragment() {
	// soft across the width, so the strip has no hard rails
	float edge = smoothstep(0.0, 0.3, UV.x) * smoothstep(1.0, 0.7, UV.x);
	ALBEDO = mix(vec3(1.0), rubber, v_strength * edge);
	ALPHA = 1.0;
}
"""

var enabled := true:
	set(v):
		enabled = v
		visible = v
		set_physics_process(v)

## Total quads laid so far (tests, HUD).
var laid := 0

var _player: PlayerCar
var _mat: ShaderMaterial
var _t := 0.0
var _next := 0
var _xf: Array[Transform3D] = []       # mirror of the instance transforms (headless drops MultiMesh data)
var _birth: PackedFloat32Array = []
var _live: PackedByteArray = []
var _reap := 0
var _last: Array[Vector3] = []          # per wheel: end of the last laid quad
var _active: Array[bool] = []
var _peak: PackedFloat32Array = []

func _init(player: PlayerCar) -> void:
	_player = player
	name = "SkidMarks"

func _ready() -> void:
	# World-static: the quads never move except on a recentre, where they jump.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)  # local X = width, local Z = length, faces +Y
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = MAX_SEGMENTS
	var zero := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	_xf.resize(MAX_SEGMENTS)
	_birth.resize(MAX_SEGMENTS)
	_live.resize(MAX_SEGMENTS)
	for i in MAX_SEGMENTS:
		mm.set_instance_transform(i, zero)
		_xf[i] = zero
	multimesh = mm
	# The floating origin keeps everything within ~1 km of (0,0,0): never cull.
	custom_aabb = AABB(Vector3(-300.0, -10.0, -2500.0), Vector3(600.0, 20.0, 5000.0))
	var shader := Shader.new()
	shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("life", LIFE)
	material_override = _mat
	var n := _player.wheel_array.size()
	_last.resize(n)
	_active.resize(n)
	_peak.resize(n)
	for i in n:
		_active[i] = false
	enabled = enabled

func _physics_process(delta: float) -> void:
	_t += delta
	_mat.set_shader_parameter("now", _t)
	var static_load := _player.mass * 9.81 / 4.0
	for i in _player.wheel_array.size():
		var w: Wheel = _player.wheel_array[i]
		var strength := 0.0
		if w.is_colliding() and w.surface_type == "Road":
			var lat := smoothstep(CarAudio.LAT_START, CarAudio.LAT_FULL, absf(w.slip_vector.x))
			var lon := smoothstep(CarAudio.LON_START, CarAudio.LON_FULL, absf(w.slip_vector.y))
			var load := clampf(w.spring_force / static_load, 0.0, 1.0)
			strength = maxf(lat, lon) * load
		if strength < MIN_STRENGTH:
			_active[i] = false
			continue
		var p := w.last_collision_point + Vector3(0.0, LIFT, 0.0)
		if not _active[i]:
			_active[i] = true
			_last[i] = p
			_peak[i] = strength
			continue
		_peak[i] = maxf(_peak[i], strength)
		var d := p - _last[i]
		var len := Vector2(d.x, d.z).length()
		if len < SEG_LEN:
			continue
		if len > BREAK_DIST:
			_last[i] = p
			_peak[i] = strength
			continue
		_lay(_last[i], p, _peak[i])
		_last[i] = p
		_peak[i] = strength
	_reap_expired()

func _lay(a: Vector3, b: Vector3, strength: float) -> void:
	var dir := b - a
	var len := dir.length()
	dir /= len
	var side := dir.cross(Vector3.UP).normalized()
	var xf := Transform3D(Basis(side * WIDTH, Vector3.UP, dir * len), (a + b) * 0.5)
	multimesh.set_instance_transform(_next, xf)
	multimesh.set_instance_custom_data(_next, Color(_t, clampf(strength, 0.0, 1.0), 0.0, 0.0))
	_xf[_next] = xf
	_birth[_next] = _t
	_live[_next] = 1
	_next = (_next + 1) % MAX_SEGMENTS
	laid += 1

## Expired quads still rasterise (at ALBEDO 1, invisible); collapse a few per
## tick so a long drive does not leave 512 dead quads in the scene.
func _reap_expired() -> void:
	var zero := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for _k in REAP_PER_TICK:
		var i := _reap
		_reap = (_reap + 1) % MAX_SEGMENTS
		if _live[i] == 1 and _t - _birth[i] > LIFE:
			_live[i] = 0
			_xf[i] = zero
			multimesh.set_instance_transform(i, zero)

## Count of quads currently drawn (tests).
func live_count() -> int:
	var n := 0
	for v in _live:
		n += v
	return n

## Floating-origin recentre (game.gd _shift_origin): every laid quad and every
## strip's last point moves with the world.
func shift_world(offset: Vector3) -> void:
	for i in MAX_SEGMENTS:
		if _live[i] == 1:
			_xf[i].origin += offset
			multimesh.set_instance_transform(i, _xf[i])
	for i in _last.size():
		_last[i] += offset

## Drop every mark (restart, tests).
func clear() -> void:
	var zero := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in MAX_SEGMENTS:
		if _live[i] == 1:
			_live[i] = 0
			_xf[i] = zero
			multimesh.set_instance_transform(i, zero)
	for i in _active.size():
		_active[i] = false
