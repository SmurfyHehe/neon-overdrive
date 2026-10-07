extends MultiMeshInstance3D
class_name TyreSmoke

# Tyre smoke (2026-10-07, moon & tyre smoke brainstorm, smoke half): soft puffs
# off a tyre that is sliding hot. Cosmetic only: nothing here touches grip,
# wear or the sim.
#
# When it smokes: a per-wheel "scorch" builds from the same slip signal the
# skid marks use (SkidMarks / CarAudio thresholds, weighted by load) with a
# lag of SCORCH_TAU, and puffs only come once it passes SCORCH_START. So a
# chirp off the line (a tenth of a second of wheelspin) makes none, a burnout
# pours it out within half a second. The tyre's temperature from
# PowertrainHealth scales the amount: a cold tyre smokes thinly, a cooked one
# billows. Wheelspin counts as burnout; slide angle and a locked or
# handbraked wheel count as drift. Roy's call (2026-10-07) is generous on
# burnouts, moderate on drifts, and both are pause-menu sliders
# (FxSettings.smoke_burnout / smoke_drift, 0..2, 1 = the default amounts below). Compound and pressure only change the amount: softer
# rubber and lower pressure smoke a bit more.
#
# How it draws: one shared pool of MAX_PUFFS camera-facing quads in a ring
# buffer, one MultiMesh, one draw call, like the skid marks. Nothing is
# simulated per frame on the CPU: a puff's start point, velocity, size and
# birth ride in its instance data and the shader moves, grows and fades it
# against a `now` uniform. Puffs near a street lamp take the sodium orange of
# its pool (the lamps sit on a fixed 25 m grid, RoadChunkBuilder), the rest
# stay a dim dusk grey. Puffs fade out near the camera and collapse to nothing
# once invisible, so a cloud around the car costs no fill. Unshaded, no
# lights, no shadows.
#
# Colour hook: a car spec may carry "tyre_smoke_colour" (a Color) and the
# smoke is tinted by it. Nothing sets it yet; coloured smoke is a garage mod
# for later.

const MAX_PUFFS := 384
## Two profiles (v2, 2026-10-07 burnout smoke research). Rates are puffs per
## second per wheel at full slip energy, full heat, slider 1; the rest are
## per-puff ranges (min, max). Size is metres across: SIZE_START at birth,
## the profile's end size by the end of the puff's life.
const BURNOUT_RATE := 55.0   # 40..70
const DRIFT_RATE := 22.0     # 15..30
const BURNOUT_LIFE := Vector2(2.5, 4.5)   # s
const DRIFT_LIFE := Vector2(1.5, 2.5)
const BURNOUT_SIZE_END := 4.0
const DRIFT_SIZE_END := 2.5
const SIZE_START := 0.5
const BURNOUT_ALPHA := Vector2(0.45, 0.6)   # peak opacity of a fresh puff
const DRIFT_ALPHA := Vector2(0.25, 0.35)
const BURNOUT_RISE := Vector2(0.5, 1.0)     # m/s
const DRIFT_RISE := Vector2(0.3, 0.6)
const DRIFT_STRETCH := 1.8   # drift puffs are this much longer along the velocity
## One global wind (m/s) every puff drifts with.
const WIND := Vector3(0.7, 0.0, 0.3)
## When the pool is nearly full, new puffs are scaled down to this share of
## their opacity, so a dense cloud does not saturate.
const CROWDED_ALPHA := 0.6
const SCORCH_TAU := 0.35     # s for the scorch to build toward the current slip
const SCORCH_COOL_TAU := 0.8 # slow cool-down: smoke lingers a moment after grip returns
## Heat gate: smoothstep(HEAT_START, HEAT_FULL, heat). Heat is the larger of
## the tyre's temperature share and the fast scorch, because the real tyre
## temperature takes ~25 s to climb and a cold-start burnout must still smoke.
## A chirp's scorch peaks near 0.35, below HEAT_START.
const HEAT_START := 0.5
const HEAT_FULL := 1.0
const TEMP_COLD := 45.0      # degC: 0 on the temperature share
const TEMP_HOT := 110.0      # degC: 1
const DEFAULT_COLOUR := Color(0.78, 0.78, 0.8)

const SHADER := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

uniform float now = 0.0;
uniform vec3 smoke_colour : source_color = vec3(0.78, 0.78, 0.8);
uniform vec3 sodium : source_color = vec3(1.0, 0.54, 0.12);
uniform vec3 amber : source_color = vec3(1.0, 0.75, 0.4);
uniform vec3 dusk : source_color = vec3(0.106, 0.165, 0.29);
uniform float dusk_level = 0.55;
uniform float lamp_level = 0.85;
uniform float lamp_spacing = 25.0;
uniform float lamp_own = 6.25;
uniform float lamp_onc = 18.75;
uniform float pool_inner = 2.5;
uniform float pool_outer = 8.5;
uniform float near_start = 0.8;
uniform float near_end = 2.5;
uniform vec3 wind = vec3(0.0);
// Fill guard: no puff is drawn taller than this share of the screen height,
// however close it drifts to the camera (overdraw is the whole cost here).
uniform float screen_cap = 0.10;

varying float v_alpha;
varying vec3 v_col;
varying float v_seed;

void vertex() {
	// Instance layout (TyreSmoke._emit): basis X = velocity, basis Y =
	// (start size, growth, 0), basis Z = (stretch along velocity, rise m/s, 0),
	// origin = start point; custom = (birth, life, opacity, seed).
	float age = now - INSTANCE_CUSTOM.x;
	float life = INSTANCE_CUSTOM.y;
	float t = clamp(age / life, 0.0, 1.0);
	float a = max(age, 0.0);
	vec3 vel = MODEL_MATRIX[0].xyz;
	float size = MODEL_MATRIX[1].x + MODEL_MATRIX[1].y * sqrt(a);
	// air drag on the throw-off, then a slow lift as the warm smoke rises
	float stretch = MODEL_MATRIX[2].x;
	vec3 world = MODEL_MATRIX[3].xyz + vel * (1.0 - exp(-1.8 * a)) / 1.8 + vec3(0.0, MODEL_MATRIX[2].y * a, 0.0) + wind * a;
	vec3 view_c = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	float dist = -view_c.z;
	float near = smoothstep(near_start, near_end, dist);
	// PROJECTION_MATRIX[1][1] = 1 / tan(fov / 2): the view height at dist is 2 * dist / it
	size = min(size, screen_cap * 2.0 * dist / PROJECTION_MATRIX[1][1]);
	float alive = step(0.0, age) * step(age, life);
	v_alpha = INSTANCE_CUSTOM.z * smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.3, 1.0, t)) * near * alive;
	float k = v_alpha > 0.02 ? size : 0.0;   // invisible: collapse, no fill cost
	v_seed = INSTANCE_CUSTOM.w;
	float r = v_seed * 6.2832 + a * (v_seed - 0.5);
	vec2 q = VERTEX.xy;
	if (stretch > 0.0) {
		// stretched puff: long axis along the velocity as seen on screen
		vec2 vd = (VIEW_MATRIX * vec4(vel, 0.0)).xy;
		r = length(vd) > 0.01 ? atan(vd.y, vd.x) : r;
		q.x *= 1.0 + stretch;
	}
	mat2 rot = mat2(vec2(cos(r), sin(r)), vec2(-sin(r), cos(r)));
	VERTEX = view_c + vec3(rot * q * k, 0.0);
	// sodium tint from the nearest lamp pool: own-side lamps (x > 0) every
	// 25 m from 6.25, oncoming (x < 0) from 18.75
	float zo = mod(-world.z - lamp_own, lamp_spacing);
	float zn = mod(-world.z - lamp_onc, lamp_spacing);
	float own = smoothstep(-3.0, 3.0, world.x);
	float lamp = own * (1.0 - smoothstep(pool_inner, pool_outer, min(zo, lamp_spacing - zo)))
		+ (1.0 - own) * (1.0 - smoothstep(pool_inner, pool_outer, min(zn, lamp_spacing - zn)));
	vec3 lit = mix(dusk * dusk_level + vec3(0.06), mix(sodium, amber, 0.35) * lamp_level, lamp);
	v_col = smoke_colour * lit;
}

void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d) * 2.0;
	float soft = clamp(1.0 - r * r, 0.0, 1.0);
	// a lopsided centre per puff, so the cloud is not a stack of perfect discs
	float lump = 1.0 - 0.3 * clamp(dot(d, vec2(cos(v_seed * 6.2832), sin(v_seed * 6.2832))) * 2.0, 0.0, 1.0);
	ALBEDO = v_col;
	ALPHA = v_alpha * soft * soft * lump;
}
"""

var enabled := true:
	set(v):
		enabled = v
		visible = v
		set_physics_process(v)
		set_process(v)

## Total puffs emitted so far (tests).
var emitted := 0
## Puffs emitted as burnout / drift (tests: which kind the slip read as).
var emitted_burnout := 0
var emitted_drift := 0

var _player: PlayerCar
var _mat: ShaderMaterial
var _t := 0.0
var _next := 0
# Mirrors of the instance data (headless drops MultiMesh data, and shift_world
# needs the start points).
var _xf: Array[Transform3D] = []
var _birth: PackedFloat32Array = []
var _life: PackedFloat32Array = []
var _scorch: PackedFloat32Array = []
var _carry: PackedFloat32Array = []   # fractional puffs owed per wheel
var _stock_stiffness := 10.0
var _crowd := 0.0   # live puffs / pool, 0..1, refreshed each tick

func _init(player: PlayerCar) -> void:
	_player = player
	name = "TyreSmoke"

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = MAX_PUFFS
	var dead := _dead_xf()
	_xf.resize(MAX_PUFFS)
	_birth.resize(MAX_PUFFS)
	_life.resize(MAX_PUFFS)
	for i in MAX_PUFFS:
		mm.set_instance_transform(i, dead)
		mm.set_instance_custom_data(i, Color(-100.0, 1.0, 0.0, 0.0))
		_xf[i] = dead
		_birth[i] = -100.0
		_life[i] = 1.0
	multimesh = mm
	custom_aabb = AABB(Vector3(-300.0, -10.0, -2500.0), Vector3(600.0, 60.0, 5000.0))
	var shader := Shader.new()
	shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("lamp_spacing", RoadChunkBuilder.LAMP_SPACING)
	_mat.set_shader_parameter("lamp_own", RoadChunkBuilder.LAMP_SPACING * 0.25)
	_mat.set_shader_parameter("lamp_onc", RoadChunkBuilder.LAMP_SPACING * 0.75)
	_mat.set_shader_parameter("pool_outer", RoadChunkBuilder.POOL_ALONG * 0.5)
	_mat.set_shader_parameter("wind", WIND)
	material_override = _mat
	set_colour(colour_from_spec(_player.spec))
	var stock_road: Variant = CarSpec.coupe_default().get("tire_stiffnesses", {}).get("Road")
	if stock_road != null:
		_stock_stiffness = float(stock_road)
	var n := _player.wheel_array.size()
	_scorch.resize(n)
	_carry.resize(n)
	enabled = enabled

## The garage hook: the smoke colour a car spec asks for, white-grey if none.
static func colour_from_spec(spec: Dictionary) -> Color:
	var c: Variant = spec.get("tyre_smoke_colour")
	return c if c is Color else DEFAULT_COLOUR

func set_colour(c: Color) -> void:
	_mat.set_shader_parameter("smoke_colour", c)

func _process(_delta: float) -> void:
	# Render-rate clock between physics ticks, so puffs drift smoothly at any fps.
	var f := Engine.get_physics_interpolation_fraction() / float(Engine.physics_ticks_per_second)
	_mat.set_shader_parameter("now", _t + f)

func _physics_process(delta: float) -> void:
	_t += delta
	var static_load := _player.mass * 9.81 / 4.0
	var mods := amount_mods()
	_crowd = float(live_count()) / float(MAX_PUFFS)
	var fwd := -_player.global_transform.basis.z
	var health := _player.health
	for i in _player.wheel_array.size():
		var w: Wheel = _player.wheel_array[i]
		var lat := 0.0
		var lon := 0.0
		if w.is_colliding() and w.surface_type == "Road":
			var load := clampf(w.spring_force / static_load, 0.0, 1.0)
			# GEVP slip ratio is negative when the tyre spins faster than the
			# road (wheelspin: burnout smoke) and positive when it drags behind
			# (a locked or handbraked wheel: counted with the slide, as drift).
			var spin := maxf(-w.slip_vector.y, 0.0)
			var drag := maxf(w.slip_vector.y, 0.0)
			lat = smoothstep(CarAudio.LAT_START, CarAudio.LAT_FULL, maxf(absf(w.slip_vector.x), drag)) * load
			lon = smoothstep(CarAudio.LON_START, CarAudio.LON_FULL, spin) * load
		var temp := health.tyre_temp[i] if i < health.tyre_temp.size() else PowertrainHealth.AMBIENT_C
		var rate := puff_rate(lat, lon, step_scorch(i, maxf(lat, lon), delta), temp,
			FxSettings.smoke_burnout, FxSettings.smoke_drift) * mods[0 if i < 2 else 1]
		if rate <= 0.0:
			_carry[i] = 0.0
			continue
		_carry[i] += rate * delta
		var burnout := lon >= lat
		while _carry[i] >= 1.0:
			_carry[i] -= 1.0
			_emit(w, fwd, lat, lon, burnout)

## Advance wheel i's scorch toward the current slip strength and return it.
func step_scorch(i: int, strength: float, dt: float) -> float:
	var tau := SCORCH_TAU if strength > _scorch[i] else SCORCH_COOL_TAU
	_scorch[i] += (strength - _scorch[i]) * (1.0 - exp(-dt / tau))
	return _scorch[i]

## Puffs per second for one wheel (pure, for tests): base rate x slider x
## smoothstep(0.5, 1.0, heat) x slip energy. lat / lon are the slide and
## wheelspin strengths 0..1 (the slip energy), scorch the lagged slip, temp the
## tyre in degC, burnout / drift the two sliders.
static func puff_rate(lat: float, lon: float, scorch: float, temp: float, burnout: float, drift: float) -> float:
	var heat := maxf(scorch, clampf(inverse_lerp(TEMP_COLD, TEMP_HOT, temp), 0.0, 1.0))
	var gate := smoothstep(HEAT_START, HEAT_FULL, heat)
	if gate <= 0.0:
		return 0.0
	return gate * (lon * BURNOUT_RATE * burnout + lat * DRIFT_RATE * drift)

## Amount multipliers [front, rear] from the tyre setup: compound (the tuner
## scales tire_stiffnesses by 0.85 / 1.0 / 1.15 for Street / Sport /
## Semi-slick) and pressure (lower smokes more). Amount only, never colour or
## timing.
func amount_mods() -> Array[float]:
	var stiff := float(_player.tire_stiffnesses.get("Road", _stock_stiffness)) / maxf(_stock_stiffness, 0.001)
	var compound := clampf(1.0 + 2.0 * (stiff - 1.0), 0.6, 1.4)
	var stock_p := _player.tyre_pressure_stock
	return [compound * clampf(1.0 - 0.5 * (_player.front_tyre_pressure - stock_p), 0.7, 1.3),
		compound * clampf(1.0 - 0.5 * (_player.rear_tyre_pressure - stock_p), 0.7, 1.3)]

func _emit(w: Wheel, fwd: Vector3, lat: float, lon: float, burnout: bool) -> void:
	var p := w.last_collision_point + Vector3(randf_range(-0.15, 0.15), 0.25, randf_range(-0.2, 0.2))
	# Carried along a little by the car, flung back off a spinning tyre, spread sideways.
	var vel := _player.linear_velocity * 0.25 - fwd * (2.0 * lon) \
		+ Vector3(randf_range(-0.9, 0.9), randf_range(0.2, 0.7), randf_range(-0.9, 0.9))
	var life := randf_range(BURNOUT_LIFE.x, BURNOUT_LIFE.y) if burnout else randf_range(DRIFT_LIFE.x, DRIFT_LIFE.y)
	var alpha := randf_range(BURNOUT_ALPHA.x, BURNOUT_ALPHA.y) if burnout else randf_range(DRIFT_ALPHA.x, DRIFT_ALPHA.y)
	alpha *= lerpf(1.0, CROWDED_ALPHA, smoothstep(0.6, 1.0, _crowd))
	var rise := randf_range(BURNOUT_RISE.x, BURNOUT_RISE.y) if burnout else randf_range(DRIFT_RISE.x, DRIFT_RISE.y)
	var size_end := BURNOUT_SIZE_END if burnout else DRIFT_SIZE_END
	var grow := (size_end - SIZE_START) / sqrt(life)
	var xf := Transform3D(Basis(vel, Vector3(SIZE_START * randf_range(0.9, 1.1), grow * randf_range(0.9, 1.1), 0.0),
		Vector3(0.0 if burnout else DRIFT_STRETCH, rise, 0.0)), p)
	multimesh.set_instance_transform(_next, xf)
	multimesh.set_instance_custom_data(_next, Color(_t, life, alpha, randf()))
	_xf[_next] = xf
	_birth[_next] = _t
	_life[_next] = life
	_next = (_next + 1) % MAX_PUFFS
	emitted += 1
	if burnout:
		emitted_burnout += 1
	else:
		emitted_drift += 1

## Puffs still in the air (tests).
func live_count() -> int:
	var n := 0
	for i in MAX_PUFFS:
		if _t - _birth[i] <= _life[i]:
			n += 1
	return n

## Start point of puff i (tests).
func puff_origin(i: int) -> Vector3:
	return _xf[i].origin

## Floating-origin recentre (game.gd _shift_origin via FxPack): live puffs move
## with the world.
func shift_world(offset: Vector3) -> void:
	for i in MAX_PUFFS:
		if _t - _birth[i] <= _life[i]:
			_xf[i].origin += offset
			multimesh.set_instance_transform(i, _xf[i])

## Drop every puff (restart, tests).
func clear() -> void:
	var dead := _dead_xf()
	for i in MAX_PUFFS:
		_birth[i] = -100.0
		_xf[i] = dead
		multimesh.set_instance_transform(i, dead)
		multimesh.set_instance_custom_data(i, Color(-100.0, 1.0, 0.0, 0.0))
	for i in _scorch.size():
		_scorch[i] = 0.0
		_carry[i] = 0.0

static func _dead_xf() -> Transform3D:
	return Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
