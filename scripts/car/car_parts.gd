class_name CarParts
extends Node

# Real wheels and brakes (car parts plan 2026-10-09, session 1). One node per
# car that wants them, added by CarParts.attach() right after
# CarSpec.build_wheels() and before CarFx.attach() (which moves every mesh to
# the car render layer).
#
# What it hangs on the car, and what it costs:
# - A new wheel mesh per corner (tyre, open-spoke rim with depth, brake disc),
#   ONE surface and one shared material per rim style, so it costs the same
#   draw call the old closed wheel did. The design's wheel mesh stays in the
#   tree, hidden, so nothing that inspects child 0 of the wheel node changes.
#   The disc is part of the wheel mesh because it spins with the wheel anyway;
#   its faces carry vertex alpha 0.5 and the shader lights them from the
#   per-instance `brake_heat` uniform (0 cold .. 1 orange).
# - All 4 calipers in one MultiMesh (+1 draw call). They sit on the steered
#   Wheel (the RayCast3D), not on the spinning wheel_node, and follow the hub
#   up and down each frame.
# - All 4 spring and damper units in one MultiMesh (+1 draw call), only while
#   the car's CarDetail says they can be seen (stopped with a panel open, the
#   garage, photo mode); built on first need, hidden after. The unit is built
#   1 m long hanging from the top mount (the Wheel's origin) and is scaled
#   each frame to `spring_current_length`, so it compresses with the sim's
#   suspension.
# So the player car pays +1 draw call driving (+2 in detail); traffic pays nothing because it never
# calls attach(). Cop, ally and rival cars opt in with `parts = "full"` in
# their CarSpec dictionary (TrafficCar reads it) and get the same set within
# LOD_RANGE metres, nothing beyond.
#
# Heat: the player reads PowertrainHealth.brake_temp (one number for all four
# discs; the fronts show more of it because they do more of the braking). A
# car without a health object keeps its own estimate here with the same
# constants, so a cop's discs glow after a hard stop too. The glow runs from
# GLOW_START (first dull red) to GLOW_FULL (orange), calibrated like the
# graphics branch's BrakeGlow: one full stop from 200 km/h reaches ~275 degC.
#
# Rim styles (car-look doc section 4): "five" (five-spoke), "mesh" (12 thin
# spokes), "dish" (deep five-spoke, hub set back), "steel" (steelie with a
# hubcap; closed, for the beater). Pick with attach()'s cfg or let
# rim_for_style() map a fleet.json rim name onto one of the four.
#
# Everything here is GDScript primitives (the plan's A1 bridge); the Blender
# kit (B1) replaces the meshes and keeps these parents and hooks.

const GLOW_START := 150.0
const GLOW_FULL := 450.0
const REAR_HEAT_SHARE := 0.6
const LOD_RANGE := 40.0
const HEAT_STEP := 1.0 / 64.0
const CALIPER_ANGLE := 0.6109  # 35 deg above the hub's horizontal, toward the rear

const RIM_STYLES := ["five", "mesh", "dish", "steel"]
const DEFAULT_CFG := {
	"rim": "five",
	"rim_color": Color("#C9CED6"),
	"caliper_color": Color("#B5261E"),
	"tyre_w": 0.245,
	"hub_x": -1.0,   # visual hub x (abs); -1 = the physics wheel x
	"shock_z": 0.42,  # the unit stands this far behind the hub, in the arch, clear of the tyre
	"shock_top": 0.12, # its top mount sits this far above the Wheel origin (the strut is longer than the raycast travel)
	"lod": false,    # true: parts only within LOD_RANGE (cops, rivals, allies)
	# "disc" or "drum" per axle (CarFittings.BRAKES). A drum axle gets a drum
	# shell behind the spokes and no caliper; cheap old cars keep drums at the
	# back, the Bug on all four (Roy 1172).
	"brake_front": "disc",
	"brake_rear": "disc",
	# Rim diameter in inches (CarFittings.TYRES, from the car's class); 0 = the
	# old 70% of the tyre radius.
	"rim_in": 0.0,
	# Car-space height the top of a drawn tyre never rises past, front and
	# rear (CarFittings.TYRES "top", measured on the body; issue #670).
	# 0 = no stop.
	"arch_top_f": 0.0,
	"arch_top_r": 0.0,
	# Vented discs show dark slots across the glow band (CarFittings.VENTED).
	"vented": false,
}

const COL_TYRE := Color("#15171C")
const COL_TYRE_SIDE := Color("#1C1F26")
const COL_BARREL := Color("#0B0E14")
const COL_DISC := Color("#2A2D33")
const COL_HUB := Color("#3A3E46")
const COL_DAMPER := Color("#22252C")
const COL_SPRING := Color("#8A8F99")
const COL_ROD := Color("#C9CED6")

const WHEEL_SHADER := """
shader_type spatial;
render_mode cull_back;
// Vertex alpha: 0 = rim (tinted by `rim`), 0.5 = brake disc or drum (glows with
// brake_heat), 1 = as coloured. UV.x = this wheel's disc radius (m), UV.y = 1 on
// a vented disc, 0 on a solid one, -1 on a drum.
uniform vec3 rim : source_color = vec3(0.79, 0.81, 0.84);
uniform float rim_metallic = 0.8;
uniform float rim_roughness = 0.3;
instance uniform float brake_heat : instance_index(3) = 0.0;
// The inner ring's heat: brake_heat followed behind (CarParts.HEAT_LAG over
// the glow speed setting), so the pad band heats from the edge in and cools
// from the hat out.
instance uniform float brake_heat_lag : instance_index(4) = 0.0;
// Brake glow (Roy 1514, and 2026-10-14: not one flat cherry plate). A real
// disc under heat is a dull cherry only where the pads sweep it, hottest at
// the outer edge where the rubbing speed is highest, scored with fine
// circumferential grooves, blotched with hot spots where pad material has
// built up, and cross-drilled or slotted for cooling. Exaggerated here (an
// arcade on a real base): deeper cherry, brighter spots, a near-orange rim.
const vec3 GLOW_CHERRY = vec3(0.27, 0.012, 0.003);   // #8F1A08
const vec3 GLOW_ORANGE = vec3(1.0, 0.25, 0.014);     // #FF8A1F
const vec3 GLOW_HOT = vec3(1.0, 0.55, 0.12);         // the hottest spots at the top
varying vec3 wheel_pos;
void vertex() {
	wheel_pos = VERTEX;
}
// Cheap value noise on a polar grid: one hash per cell, smoothed, so hot
// spots are blotches rather than tidy sine lobes.
float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
void fragment() {
	float is_rim = 1.0 - step(0.25, COLOR.a);
	float is_disc = step(0.25, COLOR.a) * (1.0 - step(0.75, COLOR.a));
	ALBEDO = mix(COLOR.rgb, rim, is_rim);
	METALLIC = mix(mix(0.1, 0.45, is_disc), rim_metallic, is_rim);
	ROUGHNESS = mix(mix(0.75, 0.55, is_disc), rim_roughness, is_rim);
	SPECULAR = 0.5;
	// Patterns on the disc, all in the wheel's own space so they turn with it.
	float rn = length(wheel_pos.yz) / max(UV.x, 0.01);   // 0 hub .. 1 disc edge
	float ang = atan(wheel_pos.z, wheel_pos.y);
	float drum = step(UV.y, -0.5);
	float vented = step(0.5, UV.y);
	// Edge first, centre last: the outer third reads brake_heat, the inner the lagged copy.
	float h = clamp(mix(brake_heat_lag, brake_heat, smoothstep(0.55, 0.95, rn)), 0.0, 1.0);
	// Pad band: only where the pads rub. The hat (inner 55%) stays cold, the
	// outer lip past the pad is a thin cooler edge. A drum glows all over its
	// face, hottest at its rim.
	float band_in = smoothstep(0.52, 0.62, rn);
	float band = band_in * (1.0 - smoothstep(0.95, 1.0, rn) * 0.7);
	band = mix(band, 0.35 + 0.65 * smoothstep(0.3, 1.0, rn), drum);
	// Hotter towards the edge: rubbing speed grows with radius, so the glow
	// climbs from a dull inner band to its brightest just inside the lip.
	float radial = mix(0.55, 1.15, smoothstep(0.58, 0.93, rn));
	// Score rings: fine circumferential grooves the pads cut, dark hairlines
	// that break the band into rings (the "pattern", not one plate).
	// (Lighter on a vented disc, so the slots and rings do not make a grid.)
	float rings = 1.0 - 0.38 * (1.0 - 0.6 * vented) * smoothstep(0.35, 0.95, sin(rn * 110.0 + 0.4));
	rings *= 1.0 - 0.22 * (1.0 - 0.6 * vented) * smoothstep(0.5, 1.0, sin(rn * 37.0 - 1.1));
	// Hot spots: blotches of pad deposit on a polar grid, two octaves, that
	// creep round the disc as it soaks (a slow drift, so they shimmer).
	vec2 pc = vec2(ang * 2.2 + brake_heat_lag * 1.3, rn * 9.0);
	float spots = vnoise(pc) * 0.65 + vnoise(pc * 2.7 + vec2(3.1, 7.7)) * 0.35;
	spots = 0.45 + 1.3 * smoothstep(0.3, 0.8, spots);
	// A few bright heat blooms that only show at the top of the range, where
	// the hottest deposits flare near orange-white.
	float bloom = smoothstep(0.62, 0.9, vnoise(vec2(ang * 1.6 + 11.0, rn * 6.0)));
	// Cooling holes: cross-drilled on a solid disc (two staggered rows of dark
	// dots), straight vent slots on a vented one (dark radial lines).
	float row = step(0.5, fract(rn * 7.3 + 0.25));
	vec2 hole_cell = vec2(fract((ang / 6.2831853) * 24.0 + row * 0.5) - 0.5, fract(rn * 7.3 + 0.25) - 0.5);
	float holes = 1.0 - smoothstep(0.16, 0.24, length(hole_cell * vec2(1.0, 1.6)));
	holes = 1.0 - holes * band_in * (1.0 - smoothstep(0.90, 0.95, rn));
	float vents = 0.35 + 0.65 * smoothstep(0.45, 0.8, sin(ang * 30.0));
	float cooling = mix(mix(holes, vents, vented), 1.0, drum);
	// Colour: cherry at the bottom, orange across the band at the top, the
	// blooms past that to a near-white. The rings and holes stay dark
	// whatever the heat, so the disc always reads as metal with a pattern.
	float top = smoothstep(0.55, 1.0, h);
	vec3 col = mix(GLOW_CHERRY * 2.2, GLOW_ORANGE * 0.95, top);
	col = mix(col, GLOW_HOT, bloom * smoothstep(0.75, 1.0, h) * 0.8);
	float glow = (h * h) * band * radial * rings * spots * cooling;
	EMISSION = col * glow * is_disc * 1.25;
}
"""

static var _wheel_shader: Shader
static var _wheel_mats := {}     # rim colour -> ShaderMaterial
static var _wheel_meshes := {}   # key -> ArrayMesh
static var _caliper_meshes := {}
static var _shock_mesh: ArrayMesh
static var _part_mat: StandardMaterial3D

var vehicle: Vehicle
var cfg := {}
## Own brake heat estimate for cars without a PowertrainHealth, degC.
var brake_temp := PowertrainHealth.AMBIENT_C
var _wheels: Array[Wheel] = []
var _wheel_meshes_inst: Array[MeshInstance3D] = []
var _sides: Array[float] = []
var _calipers: MultiMeshInstance3D
var _shocks: MultiMeshInstance3D
var _disc_x: float = 0.0
var _disc_r := 0.0
var _last_heat: Array[float] = [-1.0, -1.0, -1.0, -1.0]
var _lag_heat: Array[float] = [0.0, 0.0, 0.0, 0.0]
## The drawn edge heat: follows heat_for(disc_temp()) at HEAT_RISE / HEAT_FALL
## per second times FxSettings.brake_glow_speed, so the glow setting changes
## how fast the pattern comes and goes without touching the sim's temperature.
var _vis_heat: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _last_lag: Array[float] = [-1.0, -1.0, -1.0, -1.0]
## Highest car-space hub height each drawn wheel may reach (arch top less the
## tyre radius); INF with no arch data. The sim's wheel keeps its own travel.
var _arch_limit: Array[float] = [INF, INF, INF, INF]
## How far each drawn wheel is held below the sim's hub this frame, m.
var _held: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _mesh_x: Array[float] = []
## "disc" or "drum" at FL FR RL RR, as built (tests/car/required_slots.gd reads it).
var brake_kinds: Array[String] = []
## The transforms last written to the two MultiMeshes, FL FR RL RR in car
## space (the server does not read them back headless; tests and debugging do).
var caliper_xf: Array[Transform3D] = [Transform3D(), Transform3D(), Transform3D(), Transform3D()]
var shock_xf: Array[Transform3D] = [Transform3D(), Transform3D(), Transform3D(), Transform3D()]

## True when a CarSpec dictionary asks for the parts set.
static func wants_parts(spec: Dictionary) -> bool:
	return String(spec.get("parts", "none")) == "full"

## Maps a fleet.json rim name onto one of the four built styles.
static func rim_for_style(style: String) -> String:
	match style:
		"mesh", "10spoke", "turbofan":
			return "mesh"
		"dish":
			return "dish"
		"steel":
			return "steel"
		_:
			return "five"

## Seconds the inner ring of a disc lags its outer ring (the glow's fade), at
## glow speed 1; the setting divides it.
const HEAT_LAG := 2.0
## Fastest the drawn edge heat may rise and fall, per second at glow speed 1
## (0..1 units). At 1 the edge keeps up with any stop the sim can make; the
## fall is slower so a hot disc visibly cools rather than switching off.
const HEAT_RISE := 1.5
const HEAT_FALL := 0.35

## Hangs the parts on a car whose 4 Wheel nodes already exist.
static func attach(v: Vehicle, overrides: Dictionary = {}) -> CarParts:
	var p := CarParts.new()
	p.name = "CarParts"
	p.vehicle = v
	p.cfg = DEFAULT_CFG.duplicate()
	for k in overrides:
		p.cfg[k] = overrides[k]
	v.add_child(p)
	p._build()
	return p

func _build() -> void:
	_wheels = [vehicle.front_left_wheel, vehicle.front_right_wheel, vehicle.rear_left_wheel, vehicle.rear_right_wheel]
	var radius: float = vehicle.front_tire_radius
	var tyre_w: float = cfg.tyre_w
	var rim_r := radius * 0.70
	if float(cfg.rim_in) > 0.0:
		rim_r = clampf(float(cfg.rim_in) * 0.0254 * 0.5, radius * CarFittings.RIM_MIN, radius * CarFittings.RIM_MAX)
	var style := String(cfg.rim)
	var lod: bool = cfg.lod
	var mat := _get_wheel_material(cfg.rim_color)
	for i in 4:
		var w := _wheels[i]
		var side := signf(w.position.x) if w.position.x != 0.0 else 1.0
		_sides.append(side)
		var hub_x: float = cfg.hub_x if float(cfg.hub_x) > 0.0 else absf(w.position.x)
		var mi := MeshInstance3D.new()
		mi.name = "Parts"
		var rear := i >= 2
		var brake := String(cfg.brake_rear if rear else cfg.brake_front)
		brake_kinds.append(brake)
		mi.mesh = wheel_mesh(radius, tyre_w, rim_r, style, rear, brake, bool(cfg.vented))
		mi.set_surface_override_material(0, mat)
		mi.position = Vector3(side * hub_x - w.position.x, 0.0, 0.0)
		if side < 0.0:
			mi.rotation.y = PI
		mi.set_instance_shader_parameter("brake_heat", 0.0)
		mi.set_instance_shader_parameter("brake_heat_lag", 0.0)
		var arch_top := float(cfg.arch_top_r if rear else cfg.arch_top_f)
		if arch_top > 0.0:
			_arch_limit[i] = arch_top - (vehicle.rear_tire_radius if rear else radius)
		var visual := w.wheel_node
		# The design's closed wheel stays as child 0, hidden (tests and the
		# P1 builder still find it there); ours draws in its place.
		for c in visual.get_children():
			if c is VisualInstance3D:
				(c as VisualInstance3D).visible = false
		visual.add_child(mi)
		_wheel_meshes_inst.append(mi)
		_mesh_x.append(mi.position.x)
	_disc_r = _disc_radius(rim_r, false)
	_disc_x = _disc_offset(tyre_w, style)
	var disc_t := _disc_thickness()

	# Calipers: one box each, straddling the disc at the rear of the hub, as
	# one MultiMesh under the car body (transforms in car space).
	_calipers = MultiMeshInstance3D.new()
	_calipers.name = "Calipers"
	_calipers.multimesh = _new_multimesh(caliper_mesh(_disc_r, disc_t, cfg.caliper_color), 4)
	vehicle.add_child(_calipers)

	if lod:
		_calipers.visibility_range_end = LOD_RANGE
	_update_transforms()
	# Spring and damper: one unit each, 1 m long from the top mount, scaled to
	# the live spring length each frame. Nobody sees them in the arches while
	# driving, so they are a detail part (hide-unseen-parts Part 1): built the
	# first time the car is looked at stopped with a panel open, in the garage
	# or in photo mode, hidden again after, through the car's CarDetail node.
	CarDetail.of(vehicle).register("shocks", _build_shocks)

## Builds the Shocks MultiMesh on demand (CarDetail). Copies the calipers'
## render layer, since CarFx.attach has already moved the first set of
## meshes to the car layer by the time this runs.
func _build_shocks() -> Node:
	_shocks = MultiMeshInstance3D.new()
	_shocks.name = "Shocks"
	_shocks.multimesh = _new_multimesh(shock_mesh(), 4)
	_shocks.layers = _calipers.layers
	if cfg.lod:
		_shocks.visibility_range_end = LOD_RANGE
	vehicle.add_child(_shocks)
	_update_transforms()
	return _shocks

static func _new_multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	return mm

func _physics_process(delta: float) -> void:
	# Own heat estimate, same model as PowertrainHealth (one number per car),
	# only for cars without a health object.
	if vehicle.get("health") != null:
		return
	var speed: float = absf(vehicle.speed)
	var heat_in: float = PowertrainHealth.BRAKE_SHARE * vehicle.brake_force * speed
	var cool: float = (PowertrainHealth.BRAKE_COOL_BASE + PowertrainHealth.BRAKE_COOL_SPEED * speed) * (brake_temp - PowertrainHealth.AMBIENT_C)
	brake_temp = clampf(brake_temp + (heat_in - cool) / PowertrainHealth.BRAKE_C * delta, PowertrainHealth.AMBIENT_C, 1000.0)

func _process(delta: float) -> void:
	if not vehicle.visible:
		return
	_update_transforms()
	_update_heat(delta)

## Disc temperature this car's glow reads, degC.
func disc_temp() -> float:
	var h: Variant = vehicle.get("health")
	if h != null and h is PowertrainHealth:
		return (h as PowertrainHealth).brake_temp
	return brake_temp

## 0..1 glow for a disc temperature.
static func heat_for(temp_c: float) -> float:
	return clampf((temp_c - GLOW_START) / (GLOW_FULL - GLOW_START), 0.0, 1.0)

func _update_heat(delta: float) -> void:
	var h := heat_for(disc_temp())
	var speed: float = FxSettings.brake_glow_speed
	var k := clampf(delta * speed / HEAT_LAG, 0.0, 1.0)
	for i in 4:
		var target := h if i < 2 else h * REAR_HEAT_SHARE
		var rate := (HEAT_RISE if target > _vis_heat[i] else HEAT_FALL) * speed
		_vis_heat[i] = move_toward(_vis_heat[i], target, rate * delta)
		var hi := _vis_heat[i]
		_lag_heat[i] = lerpf(_lag_heat[i], hi, k)
		hi = floorf(hi / HEAT_STEP) * HEAT_STEP
		if hi != _last_heat[i]:
			_last_heat[i] = hi
			_wheel_meshes_inst[i].set_instance_shader_parameter("brake_heat", hi)
		var lag := floorf(_lag_heat[i] / HEAT_STEP) * HEAT_STEP
		if lag != _last_lag[i]:
			_last_lag[i] = lag
			_wheel_meshes_inst[i].set_instance_shader_parameter("brake_heat_lag", lag)

## How far (m) the drawn wheel i is held under the sim's hub by the arch stop.
func held(i: int) -> float:
	return _held[i]

## Car-space height the drawn hub of wheel i (FL FR RL RR) never rises past
## (INF without arch data).
func arch_limit(i: int) -> float:
	return _arch_limit[i]

func _update_transforms() -> void:
	var cal := _calipers.multimesh
	var shocks_on := _shocks != null and _shocks.visible
	var sh: MultiMesh = _shocks.multimesh if shocks_on else null
	for i in 4:
		var w := _wheels[i]
		var side := _sides[i]
		var mi := _wheel_meshes_inst[i]
		var mesh_x: float = _mesh_x[i]
		# The arch stop (issue #670): the sim's spring can push the hub higher
		# than the arch allows (a bump, a landing); the drawn wheel stops at
		# the arch top instead of passing through the fender. The offset is
		# written in the spinning wheel node's frame so it stays straight down.
		var held := maxf(0.0, w.position.y + w.wheel_node.position.y - _arch_limit[i])
		if held != _held[i] or held > 0.0:
			_held[i] = held
			mi.position = Vector3(mesh_x, 0.0, 0.0) + w.wheel_node.transform.basis.inverse() * Vector3(0.0, -held, 0.0)
		var hub_y: float = w.wheel_node.position.y - held
		# Caliper: behind the hub (toward +z, the car's rear), level with the
		# disc, steering with the Wheel, not spinning with the wheel_node.
		var cal_local := Transform3D(Basis(), Vector3(mesh_x + side * _disc_x, hub_y, 0.0))
		if side < 0.0:
			# Mirror for the left side without a negative scale (that would
			# flip the winding): half a turn round z puts the caliper below
			# and inboard, then twice its angle round x lifts it back up
			# behind the hub.
			cal_local.basis = Basis(Vector3.RIGHT, -2.0 * CALIPER_ANGLE) * Basis(Vector3.BACK, PI)
		caliper_xf[i] = w.transform * cal_local
		if brake_kinds[i] == "drum":
			# A drum has no caliper: the instance collapses to a point.
			cal.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), caliper_xf[i].origin))
		else:
			cal.set_instance_transform(i, caliper_xf[i])
		if not shocks_on:
			continue
		# Spring and damper: from the top mount height (the Wheel origin) down to
		# the hub, standing in the arch behind the tyre where the gap shows it,
		# scaled to the spring's current length. In car space, not the Wheel's:
		# the unit does not swing with the steering.
		var length := maxf(float(cfg.shock_top) - hub_y, 0.02)
		var top := w.position + Vector3(mesh_x, float(cfg.shock_top), float(cfg.shock_z))
		shock_xf[i] = Transform3D(Basis().scaled(Vector3(1.0, length, 1.0)), top)
		sh.set_instance_transform(i, shock_xf[i])

# ---------- counts (tests and the budget) ----------

## Triangles this node adds to a car: 4 wheels, 4 calipers, and the 4 shocks
## once they exist (detail on).
func triangle_count() -> int:
	var n := 0
	for mi in _wheel_meshes_inst:
		n += (mi.mesh as ArrayMesh).surface_get_array_len(0) / 3
	n += 4 * (_calipers.multimesh.mesh as ArrayMesh).surface_get_array_len(0) / 3
	if _shocks != null:
		n += 4 * (_shocks.multimesh.mesh as ArrayMesh).surface_get_array_len(0) / 3
	return n

## Draw calls this node adds on top of the car's: the calipers' MultiMesh
## while driving, plus the shocks' with detail on (the wheel meshes replace
## the design's, one draw call each, as before).
static func extra_draw_calls(detail := false) -> int:
	return 2 if detail else 1

# ---------- materials ----------

static func _get_wheel_material(rim_color: Color) -> ShaderMaterial:
	var key := rim_color.to_html(false)
	if not _wheel_mats.has(key):
		if _wheel_shader == null:
			_wheel_shader = Shader.new()
			_wheel_shader.code = WHEEL_SHADER
		var m := ShaderMaterial.new()
		m.shader = _wheel_shader
		m.set_shader_parameter("rim", rim_color)
		_wheel_mats[key] = m
	return _wheel_mats[key]

static func _get_part_material() -> StandardMaterial3D:
	if _part_mat == null:
		_part_mat = StandardMaterial3D.new()
		_part_mat.vertex_color_use_as_albedo = true
		_part_mat.metallic = 0.5
		_part_mat.roughness = 0.5
	return _part_mat

# ---------- meshes ----------

static func _disc_radius(rim_r: float, rear: bool) -> float:
	return rim_r * (0.72 if rear else 0.80)

static func _disc_thickness() -> float:
	return 0.026

## Disc centre x from the hub plane, outboard positive: just behind the spoke
## plane of this rim style (a dished rim puts it deeper in the arch).
static func _disc_offset(tyre_w: float, style: String) -> float:
	# The closed steel face has no spokes to look past, so the disc and its
	# caliper sit well behind the plate instead of touching it.
	var clearance := 0.04 if style == "steel" else 0.006
	return tyre_w * 0.5 - _dish_depth(style, tyre_w) - _spoke_depth(style) * 0.5 - _disc_thickness() * 0.5 - clearance

static func _spoke_depth(style: String) -> float:
	return 0.03 if style == "mesh" or style == "dish" else 0.035

## Tyre, rim and brake disc as one surface. The wheel axis is +x (outboard for
## a right-hand wheel); the left wheel is the same mesh turned round.
static func wheel_mesh(radius: float, tyre_w: float, rim_r: float, style: String, rear: bool, brake := "disc", vented := false) -> ArrayMesh:
	var key := "%.3f|%.3f|%.3f|%s|%s|%s|%s" % [radius, tyre_w, rim_r, style, "r" if rear else "f", brake, "v" if vented else "s"]
	if _wheel_meshes.has(key):
		return _wheel_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat shaded, the PS2 look
	# Every vertex carries the disc radius and the brake kind for the glow's
	# patterns (WHEEL_SHADER): the shader only reads them on the disc faces.
	st.set_uv(Vector2(_disc_radius(rim_r, rear), -1.0 if brake == "drum" else (1.0 if vented else 0.0)))
	var hw := tyre_w * 0.5
	var sh := radius * 0.055          # shoulder bevel
	var bead := rim_r + 0.012
	# Tyre: a closed revolved profile (x, r) read clockwise round the section.
	var tyre_c := Color(COL_TYRE, 1.0)
	var side_c := Color(COL_TYRE_SIDE, 1.0)
	var prof: Array = [
		[Vector2(-hw, bead), side_c],
		[Vector2(-hw * 0.96, radius - sh * 2.2), side_c],
		[Vector2(-hw + sh, radius - sh * 0.4), tyre_c],
		[Vector2(-hw + sh * 1.6, radius), tyre_c],
		[Vector2(hw - sh * 1.6, radius), tyre_c],
		[Vector2(hw - sh, radius - sh * 0.4), tyre_c],
		[Vector2(hw * 0.96, radius - sh * 2.2), side_c],
		[Vector2(hw, bead), side_c],
	]
	_revolve(st, prof, 24, true)
	# Rim: the outer lip face, then the dark drum seen through the spokes (its
	# inside and back wall). Profiles run so the visible side faces out: in
	# the (x, r) plane the face normal is the profile direction turned +90 deg.
	var barrel_c := Color(COL_BARREL, 1.0)
	var rim_c := Color(Color.WHITE, 0.0)   # alpha 0: tinted by the shader
	var lip := 0.02
	var dish := _dish_depth(style, tyre_w)
	var face_x := hw - dish            # spoke plane
	_revolve(st, [[Vector2(hw + 0.002, rim_r), rim_c], [Vector2(hw + 0.002, bead), rim_c]], 24, true)
	_revolve(st, [[Vector2(hw + 0.002, rim_r), rim_c], [Vector2(hw - lip, rim_r - lip), barrel_c],
		[Vector2(-hw * 0.8, rim_r - lip), barrel_c], [Vector2(-hw * 0.8, rim_r * 0.3), barrel_c]], 24, true)
	# Hub and spokes.
	var hub_r := rim_r * 0.26
	var hub_c := Color(COL_HUB, 1.0)
	var hub_prof: Array = [[Vector2(face_x - 0.03, 0.0), hub_c], [Vector2(face_x - 0.03, hub_r), hub_c],
		[Vector2(face_x + 0.02, hub_r), hub_c], [Vector2(face_x + 0.02, 0.0), hub_c]]
	match style:
		"steel":
			# Closed steel wheel: flat face plus a domed hubcap.
			_revolve(st, [[Vector2(face_x, rim_r - lip), rim_c], [Vector2(face_x, hub_r * 1.4), rim_c],
				[Vector2(face_x + 0.025, hub_r * 1.1), rim_c], [Vector2(face_x + 0.04, hub_r * 0.5), rim_c],
				[Vector2(face_x + 0.045, 0.0), rim_c]], 24, true)
		"mesh":
			_revolve(st, hub_prof, 12, true)
			_spokes(st, 12, hub_r * 0.9, rim_r - lip * 0.5, face_x, 0.016, 0.03, 0.0, rim_c)
		"dish":
			_revolve(st, hub_prof, 12, true)
			_spokes(st, 5, hub_r * 0.9, rim_r - lip * 0.5, face_x, 0.045, 0.03, dish * 0.8, rim_c)
		_:
			_revolve(st, hub_prof, 12, true)
			_spokes(st, 5, hub_r * 0.9, rim_r - lip * 0.5, face_x, 0.042, 0.035, 0.0, rim_c)
	# Brake disc, just inboard of the spokes, alpha 0.5 so it glows. With a
	# hat (the smaller drum that bolts to the hub) so it reads as a rotor.
	var disc_c := Color(COL_DISC, 0.5)
	var dr := _disc_radius(rim_r, rear)
	var dt := _disc_thickness()
	var dx := _disc_offset(tyre_w, style)
	if brake == "drum":
		# A drum: a backing plate, then the drum itself (a cup, its outside and
		# its outboard face glow like a disc does) and a dust cap on the hub.
		# Wider than a disc, so it sits a little further in from the spokes.
		var xo := dx - dt * 0.5 - 0.012   # outboard face
		# Each segment takes the colour of the point it starts from.
		_revolve(st, [[Vector2(xo - 0.07, 0.0), hub_c], [Vector2(xo - 0.07, dr * 1.04), disc_c],
			[Vector2(xo, dr * 1.04), disc_c], [Vector2(xo, dr * 0.30), hub_c],
			[Vector2(xo + 0.018, dr * 0.30), hub_c], [Vector2(xo + 0.018, 0.0), hub_c]], 24, true)
	else:
		_revolve(st, [[Vector2(dx - dt * 0.5 - 0.03, 0.0), hub_c], [Vector2(dx - dt * 0.5 - 0.03, dr * 0.45), hub_c],
			[Vector2(dx - dt * 0.5, dr * 0.45), disc_c], [Vector2(dx - dt * 0.5, dr), disc_c],
			[Vector2(dx + dt * 0.5, dr), disc_c], [Vector2(dx + dt * 0.5, 0.0), disc_c]], 24, true)
	st.generate_normals()
	var mesh := st.commit()
	_wheel_meshes[key] = mesh
	return mesh

static func _dish_depth(style: String, tyre_w: float) -> float:
	match style:
		"dish":
			return tyre_w * 0.42
		"steel":
			return tyre_w * 0.18
		_:
			return tyre_w * 0.22

## A box spoke from the hub to the barrel, n of them round the axis, lying
## on the spoke plane x = face_x; `lean` pulls the hub end inboard (dish).
static func _spokes(st: SurfaceTool, n: int, r0: float, r1: float, face_x: float, width: float, depth: float, lean: float, c: Color) -> void:
	for i in n:
		var a := TAU * float(i) / float(n)
		var basis := Basis(Vector3.RIGHT, a)
		var p0 := basis * Vector3(face_x - lean, r0, 0.0)
		var p1 := basis * Vector3(face_x, r1, 0.0)
		_bar(st, p0, p1, basis * Vector3(0.0, 0.0, 1.0), width, depth, c)

## A box from a to b: `across` is the box's width direction, `w` its width
## and `d` its depth along the axis-normal plane.
static func _bar(st: SurfaceTool, a: Vector3, b: Vector3, across: Vector3, w: float, d: float, c: Color) -> void:
	var axis := (b - a).normalized()
	var u := across.normalized() * (w * 0.5)
	var v := axis.cross(across).normalized() * (d * 0.5)
	var corners := [a - u - v, a + u - v, a + u + v, a - u + v, b - u - v, b + u - v, b + u + v, b - u + v]
	var faces := [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]
	var mid := (a + b) * 0.5
	for f in faces:
		var p0: Vector3 = corners[f[0]]
		var p1: Vector3 = corners[f[1]]
		var p2: Vector3 = corners[f[2]]
		var p3: Vector3 = corners[f[3]]
		# Wind each face so it looks away from the bar's middle.
		if (p1 - p0).cross(p2 - p0).dot((p0 + p2) * 0.5 - mid) > 0.0:
			_quad(st, p0, p1, p2, p3, c)
		else:
			_quad(st, p0, p3, p2, p1, c)

static func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, c: Color) -> void:
	st.set_color(c)
	st.add_vertex(p0)
	st.add_vertex(p2)
	st.add_vertex(p1)
	st.add_vertex(p0)
	st.add_vertex(p3)
	st.add_vertex(p2)

## Revolves a profile of [Vector2(x, r), Color] pairs round the x axis. Open
## profiles get a strip between each pair of points; a closed one also joins
## the last point to the first. Faces point outward for a profile that runs
## from -x to +x along the outside (clockwise seen from +z).
static func _revolve(st: SurfaceTool, prof: Array, segs: int, open: bool) -> void:
	var n := prof.size()
	var last := n - 1 if open else n
	for i in last:
		var p0: Vector2 = prof[i][0]
		var c: Color = prof[i][1]
		var p1: Vector2 = prof[(i + 1) % n][0]
		for s in segs:
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float(s + 1) / float(segs)
			var q0 := Vector3(p0.x, p0.y * cos(a0), p0.y * sin(a0))
			var q1 := Vector3(p0.x, p0.y * cos(a1), p0.y * sin(a1))
			var q2 := Vector3(p1.x, p1.y * cos(a1), p1.y * sin(a1))
			var q3 := Vector3(p1.x, p1.y * cos(a0), p1.y * sin(a0))
			if p0.y <= 0.0:
				_tri(st, q0, q3, q2, c)
			elif p1.y <= 0.0:
				_tri(st, q0, q1, q2, c)
			else:
				_quad(st, q0, q1, q2, q3, c)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)

## One caliper: a block over the disc edge, split by a slot the disc runs
## through, plus two pad lugs. Local origin at the hub, x outboard, +z the
## car's rear; the body sits behind the axle just above the disc's centre line.
static func caliper_mesh(disc_r: float, disc_t: float, color: Color) -> ArrayMesh:
	var key := "%.3f|%.3f|%s" % [disc_r, disc_t, color.to_html(false)]
	if _caliper_meshes.has(key):
		return _caliper_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat shaded, the PS2 look
	var c := Color(color, 1.0)
	var dark := Color(COL_DAMPER, 1.0)
	var basis := Basis(Vector3.RIGHT, -CALIPER_ANGLE)
	var rc := basis * Vector3(0.0, 0.0, disc_r - 0.012)   # radial centre on the disc edge
	var tangent := basis * Vector3(0.0, 1.0, 0.0)
	var radial := basis * Vector3(0.0, 0.0, 1.0)
	var half_len := disc_r * 0.34
	var body_t := disc_t + 0.05
	# Outer and inner halves of the housing, either side of the disc.
	for s: float in [-1.0, 1.0]:
		var x_c := s * (disc_t * 0.5 + 0.013)
		var a := rc + tangent * -half_len + Vector3(x_c, 0.0, 0.0)
		var b := rc + tangent * half_len + Vector3(x_c, 0.0, 0.0)
		_bar(st, a, b, radial, 0.05, 0.026, c)
	# Bridge over the disc edge.
	var ba := rc + tangent * -half_len + radial * 0.022
	var bb := rc + tangent * half_len + radial * 0.022
	_bar(st, ba, bb, radial, 0.012, body_t, c)
	# Mounting lugs toward the hub.
	for t: float in [-0.6, 0.6]:
		var la := rc + tangent * (half_len * t) + Vector3(-disc_t * 0.5 - 0.02, 0.0, 0.0)
		var lb := la - radial * 0.05
		_bar(st, la, lb, tangent, 0.02, 0.02, dark)
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _get_part_material())
	_caliper_meshes[key] = m
	return m

## One spring and damper unit, 1 m long from the origin (top mount) down -y,
## scaled to the live spring length by the caller: a top seat, a coil as a
## square-section helix, the damper tube on the lower half and the rod above.
static func shock_mesh() -> ArrayMesh:
	if _shock_mesh != null:
		return _shock_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat shaded, the PS2 look
	var spring_c := Color(COL_SPRING, 1.0)
	var tube_c := Color(COL_DAMPER, 1.0)
	var rod_c := Color(COL_ROD, 1.0)
	var coil_r := 0.055
	# Seats.
	_revolve_y(st, [[Vector2(0.0, 0.0), tube_c], [Vector2(coil_r + 0.01, 0.0), tube_c], [Vector2(coil_r + 0.01, -0.04), tube_c], [Vector2(0.0, -0.04), tube_c]], 10)
	_revolve_y(st, [[Vector2(0.0, -0.96), tube_c], [Vector2(coil_r + 0.01, -0.96), tube_c], [Vector2(coil_r + 0.01, -1.0), tube_c], [Vector2(0.0, -1.0), tube_c]], 10)
	# Rod (upper half) and damper tube (lower half).
	_revolve_y(st, [[Vector2(0.012, -0.03), rod_c], [Vector2(0.012, -0.55), rod_c]], 8)
	_revolve_y(st, [[Vector2(0.03, -0.45), tube_c], [Vector2(0.03, -0.97), tube_c], [Vector2(0.0, -0.97), tube_c]], 10)
	# Coil: a square-section helix, 5 turns between the seats.
	var turns := 5
	var per_turn := 10
	var wire := 0.013
	var y0 := -0.06
	var y1 := -0.94
	var prev: Vector3
	var n := turns * per_turn
	for i in n + 1:
		var t := float(i) / float(n)
		var a := TAU * float(turns) * t
		var p := Vector3(coil_r * cos(a), lerpf(y0, y1, t), coil_r * sin(a))
		if i > 0:
			_bar(st, prev, p, Vector3.UP, wire, wire, spring_c)
		prev = p
	st.generate_normals()
	_shock_mesh = st.commit()
	_shock_mesh.surface_set_material(0, _get_part_material())
	return _shock_mesh

## Revolves a profile of [Vector2(r, y), Color] round the y axis (a lathe).
static func _revolve_y(st: SurfaceTool, prof: Array, segs: int) -> void:
	for i in prof.size() - 1:
		var p0: Vector2 = prof[i][0]
		var p1: Vector2 = prof[i + 1][0]
		var c: Color = prof[i][1]
		for s in segs:
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float(s + 1) / float(segs)
			var q0 := Vector3(p0.x * cos(a0), p0.y, p0.x * sin(a0))
			var q1 := Vector3(p0.x * cos(a1), p0.y, p0.x * sin(a1))
			var q2 := Vector3(p1.x * cos(a1), p1.y, p1.x * sin(a1))
			var q3 := Vector3(p1.x * cos(a0), p1.y, p1.x * sin(a0))
			if p0.x <= 0.0:
				_tri(st, q0, q3, q2, c)
			elif p1.x <= 0.0:
				_tri(st, q0, q1, q2, c)
			else:
				_quad(st, q0, q1, q2, q3, c)
