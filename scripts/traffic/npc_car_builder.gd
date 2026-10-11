extends RefCounted
class_name NpcCarBuilder

# The traffic cars (stage B step 5): N1 commuter sedan, N2 city hatchback,
# N3 pickup, plus every other B1 sheet car as an AI car (player cars P2-P6,
# cops C1-C3; see the end of KINDS). Like P1CoupeBuilder, each body is the design proxy from
# docs/design/fleet/sheets/<id>.png, exported by tools/fleet_design/game_export.py
# into scripts/<id>_data.gd, so what drives in traffic is exactly what the sheet
# shows, from every angle. Unlike the player's car, each one ships all of its
# sheet builds (stock plus two variants, e.g. the N1 taxi) and traffic picks one
# per car.
#
# Built for many copies on screen at once (draw calls are the limit, see
# docs/design/fleet/README.md "Budget plan"):
#   Body     one MeshInstance3D per car, all cars of a build share ONE mesh
#            and ONE set of materials: body (vertex colours; the paint is an
#            instance uniform, so every colour is the same material), dark
#            glass (opaque: nothing to sort), lights (glow), and the tail
#            flares (additive, see "Night lights" below)
#   wheels   one shared mesh per axle and build, drawn 4 times
# 4 + 4 = 8 draw calls a car, against ~18 for the old box traffic car.
#
# Night lights (2026-10-07): the tail lamps glow at a running level and
# brighten when the car brakes (instance uniform "brake", set by TrafficCar);
# the amber turn lamps blink on one side before and during a lane change, on
# both for a wrecked or hazard-stopped car (instance uniform "turn").
# Each tail lamp also carries a camera-facing flare that never shrinks below
# FLARE_MIN_SCREEN of the screen, so a car 200 m up the road is still two red points
# instead of nothing. It only shows from behind (it fades out as the car turns
# side-on) and lights nothing: the cars, their driving and their collision
# are unchanged, you just get to see them. TrafficSettings.light_glow scales
# the running level and the flares.
#
# Physics: the wheels sit exactly where the sheet draws them (KINDS wheel_r,
# wheel_x, axle_z = fleet.json physics_hint), so nothing is slid or scaled.
# Every car runs the same raycast sim as the player; only its CarSpec dict
# differs (CarSpec.npc_spec).
#
# Adding a car: export its data file, add a KINDS entry and a CarSpec.npc_spec
# branch. Nothing else in traffic changes: traffic only spawns the kinds in
# TrafficManager.MIX, so the other sheet cars here (player cars P2-P6, cops
# C1-C3) are built and driven on demand (rivals, police, photo and sandbox
# modes later) without joining the traffic pool.

const KINDS := {
	"n1_commuter": {
		"data": preload("res://scripts/traffic/n1_commuter_data.gd"),
		# fleet.json dims and physics_hint
		"length": 4.80, "width": 1.82, "height": 1.51, "clearance": 0.16,
		"front_overhang": 0.98, "rear_overhang": 1.02,
		"wheel_r": 0.31, "wheel_x": 0.78, "axle_z": 1.40,
		## Chassis origin height settled on the springs, flat road (negative:
		## the origin is on the ground with the springs fully extended).
		## Measured by tests/traffic/npc_cars.gd. The body is drawn -rest_y higher so
		## the car stands at the sheet's ride height at rest (P1CoupeBuilder
		## BODY_LIFT, same reason).
		"drive": "fwd",
		"rest_y": -0.121,
		"builds": {"stock": 60, "sport": 25, "taxi": 15},
		## Builds with a fixed paint instead of a random traffic neutral.
		"build_paint": {"taxi": Color("#F2B53A")},
	},
	"n2_cityhatch": {
		"data": preload("res://scripts/traffic/n2_cityhatch_data.gd"),
		"length": 3.95, "width": 1.69, "height": 1.53, "clearance": 0.15,
		"front_overhang": 0.80, "rear_overhang": 0.62,
		"wheel_r": 0.295, "wheel_x": 0.73, "axle_z": 1.265,
		"drive": "fwd",
		"rest_y": -0.12,
		"builds": {"stock": 55, "sport": 25, "rack": 20},
		"build_paint": {},
	},
	"n3_pickup": {
		"data": preload("res://scripts/traffic/n3_pickup_data.gd"),
		"length": 5.30, "width": 1.86, "height": 1.86, "clearance": 0.30,
		"front_overhang": 0.92, "rear_overhang": 1.30,
		"wheel_r": 0.39, "wheel_x": 0.79, "axle_z": 1.54,
		"drive": "rwd",
		"rest_y": -0.12,
		"builds": {"stock": 50, "covered": 30, "sportsbar": 20},
		"build_paint": {},
	},
	# The rest of the B1 sheet (not in the traffic MIX): player cars P2-P6 and
	# the cops C1-C3, as AI-driven cars on the same sim. "sheet_paint": every
	# build wears the sheet's own paint (C1 navy and white, C3 plain dark, the
	# player cars' sheet colours) instead of a random traffic neutral.
	# The beater starter car (stage D, 2026-10-09): one build, the sheet's
	# faded paint. In KINDS so the player and (later) a rival or a parked
	# prologue car share one mesh path.
	"p0_beater": {
		"data": preload("res://scripts/car/p0_beater_data.gd"),
		## Rebuilt from the decided sheet (2026-10-10): stretched to 4.30 x 1.72,
		## wheels filling the arches on a 1.44 m track.
		"length": 4.30, "width": 1.72, "height": 1.61, "clearance": 0.17,
		"front_overhang": 0.85, "rear_overhang": 0.90,
		"wheel_r": 0.30, "wheel_x": 0.72, "axle_z": 1.275,
		## Measured by tests/fleet/player_cars.gd and tests/traffic/npc_cars.gd: the soft,
		## long springs of CarSpec.player_spec sit it 1.6 cm lower than the others.
		"rest_y": -0.136,
		"builds": {"stock": 100},
		"build_paint": {},
		"sheet_paint": true,
		## Rear-engined: the underside has no pipe running the length of the car.
		"engine": "rear",
	},
	"p2_hothatch": {
		"data": preload("res://scripts/car/p2_hothatch_data.gd"),
		"length": 3.97, "width": 1.83, "height": 1.4, "clearance": 0.12,
		"front_overhang": 0.74, "rear_overhang": 0.67,
		"wheel_r": 0.315, "wheel_x": 0.79, "axle_z": 1.28,
		"rest_y": -0.12,
		"builds": {"stock": 50, "street": 30, "full": 20},
		"build_paint": {},
		"sheet_paint": true,
	},
	"p3_tuner": {
		"data": preload("res://scripts/car/p3_tuner_data.gd"),
		"length": 4.48, "width": 1.78, "height": 1.36, "clearance": 0.12,
		"front_overhang": 0.95, "rear_overhang": 0.91,
		"wheel_r": 0.32, "wheel_x": 0.76, "axle_z": 1.31,
		"rest_y": -0.12,
		"builds": {"stock": 50, "street": 30, "full": 20},
		"build_paint": {},
		"sheet_paint": true,
	},
	"p4_kei": {
		"data": preload("res://scripts/car/p4_kei_data.gd"),
		"length": 3.30, "width": 1.40, "height": 1.05, "clearance": 0.12,
		"front_overhang": 0.55, "rear_overhang": 0.48,
		"wheel_r": 0.28, "wheel_x": 0.615, "axle_z": 1.135,
		"rest_y": -0.12,
		"builds": {"stock": 50, "street": 30, "full": 20},
		"build_paint": {},
		"sheet_paint": true,
	},
	"p5_muscle": {
		"data": preload("res://scripts/car/p5_muscle_data.gd"),
		## The two-door hardtop (2026-10-11), built from its parts glb: 35 cm
		## shorter, wheelbase 2.84, one long door a side.
		"length": 5.00, "width": 1.93, "height": 1.33, "clearance": 0.16,
		"front_overhang": 0.90, "rear_overhang": 1.26,
		"wheel_r": 0.35, "wheel_x": 0.80, "axle_z": 1.42,
		"rest_y": -0.12,
		"builds": {"stock": 50, "street": 30, "full": 20},
		"build_paint": {},
		"sheet_paint": true,
	},
	"p6_crossover": {
		"data": preload("res://scripts/car/p6_crossover_data.gd"),
		"length": 4.35, "width": 1.84, "height": 1.61, "clearance": 0.22,
		"front_overhang": 0.92, "rear_overhang": 0.81,
		"wheel_r": 0.345, "wheel_x": 0.78, "axle_z": 1.31,
		"rest_y": -0.12,
		"builds": {"stock": 50, "street": 30, "full": 20},
		"build_paint": {},
		"sheet_paint": true,
	},
	# The work pickup (Camel, P17, 2026-10-10): the 4-door T2 truck Walt sells
	# The shop wagon (sheet p7_wagon, 2026-10-11): front drive, built from
	# its parts glb like the Bug; the sheet mesh is the NEON_PARTS_LEGACY body.
	"p7_wagon": {
		"data": preload("res://scripts/car/p7_wagon_data.gd"),
		"length": 4.30, "width": 1.74, "height": 1.55, "clearance": 0.16,
		"front_overhang": 0.72, "rear_overhang": 0.98,
		"wheel_r": 0.305, "wheel_x": 0.73, "axle_z": 1.30,
		"drive": "fwd",
		"rest_y": -0.12,
		"builds": {"stock": 100},
		"build_paint": {},
		"sheet_paint": true,
	},
	# after act 1. Its own sheet mesh (p17_work_pickup_data.gd), not the
	# traffic pickup's, which stays as it is.
	"p17_work_pickup": {
		"data": preload("res://scripts/car/p17_work_pickup_data.gd"),
		"length": 5.25, "width": 1.80, "height": 1.74, "clearance": 0.28,
		"front_overhang": 0.90, "rear_overhang": 1.17,
		"wheel_r": 0.37, "wheel_x": 0.775, "axle_z": 1.59,
		"drive": "rwd",
		"rest_y": -0.12,
		"builds": {"stock": 50, "street": 30, "full": 20},
		"build_paint": {},
		"sheet_paint": true,
	},
	# The drift coupe (Ashida Levant, P8, MC1 2026-10-11): built from its parts
	# glb (tools/car_pipeline/kit_p8_driftcoupe.py); the sheet mesh is the
	# NEON_PARTS_LEGACY body. 1.80 wide over the bolt-on arches.
	"p8_driftcoupe": {
		"data": preload("res://scripts/car/p8_driftcoupe_data.gd"),
		"length": 4.30, "width": 1.80, "height": 1.34, "clearance": 0.10,
		"front_overhang": 0.78, "rear_overhang": 0.88,
		"wheel_r": 0.30, "wheel_x": 0.75, "axle_z": 1.32,
		"drive": "rwd",
		"rest_y": -0.12,
		"builds": {"stock": 50, "street": 30, "full": 20},
		"build_paint": {},
		"sheet_paint": true,
	},
	# The street truck (Harlan Drover, P10, 2026-10-11): the lowered regular-cab
	# sport truck, built from its parts glb; the sheet mesh is the
	# NEON_PARTS_LEGACY body. Not the Camel (tall) and not the traffic pickup.
	"p10_truck": {
		"data": preload("res://scripts/car/p10_truck_data.gd"),
		"length": 5.05, "width": 1.92, "height": 1.62, "clearance": 0.14,
		"front_overhang": 0.90, "rear_overhang": 1.20,
		"wheel_r": 0.36, "wheel_x": 0.81, "axle_z": 1.475,
		"drive": "rwd",
		"rest_y": -0.12,
		"builds": {"stock": 100},
		"build_paint": {},
		"sheet_paint": true,
	},
	"c1_patrol": {
		"data": preload("res://scripts/car/c1_patrol_data.gd"),
		"length": 5.30, "width": 1.96, "height": 1.6, "clearance": 0.16,
		"front_overhang": 1.08, "rear_overhang": 1.30,
		"wheel_r": 0.335, "wheel_x": 0.81, "axle_z": 1.46,
		"rest_y": -0.12,
		"builds": {"stock": 60, "lowpro": 25, "nobar": 15},
		"build_paint": {},
		"sheet_paint": true,
	},
	"c2_patrolsuv": {
		"data": preload("res://scripts/car/c2_patrolsuv_data.gd"),
		"length": 5.10, "width": 2.00, "height": 2.09, "clearance": 0.23,
		"front_overhang": 0.98, "rear_overhang": 1.09,
		"wheel_r": 0.37, "wheel_x": 0.85, "axle_z": 1.515,
		"rest_y": -0.12,
		"builds": {"stock": 70, "nobar": 30},
		"build_paint": {},
		"sheet_paint": true,
	},
	"c3_interceptor": {
		"data": preload("res://scripts/car/c3_interceptor_data.gd"),
		"length": 4.82, "width": 1.92, "height": 1.38, "clearance": 0.13,
		"front_overhang": 1.02, "rear_overhang": 1.08,
		"wheel_r": 0.34, "wheel_x": 0.8, "axle_z": 1.36,
		"rest_y": -0.12,
		"builds": {"stock": 60, "pursuit": 40},
		"build_paint": {},
		"sheet_paint": true,
	},
}

## fleet.json traffic_paints (weights), without Taxi amber: that one is the
## taxi's own colour, so an amber car always reads as a taxi.
const PAINTS := [
	[Color("#C9CED6"), 22], [Color("#E9E6DF"), 18], [Color("#15171C"), 16],
	[Color("#4A505B"), 14], [Color("#26314D"), 8], [Color("#B9AE98"), 7],
	[Color("#8E2A28"), 6], [Color("#2B4A3A"), 5],
]

const GLOW_ENERGY := 2.5
## Tail lamps x (1 + this) with the brake fully on (instance uniform brake = 1).
const BRAKE_GAIN := 2.2
## Tail flare: near radius (m), the radius held at distance (share of the
## screen height: 0.006 is ~4 px at 648 lines, ~6.5 at 1080), and its
## colour (linear; the sheet's tail red pushed a little toward sodium orange).
const FLARE_NEAR_R := 0.14
const FLARE_MIN_SCREEN := 0.006
const FLARE_TINT := Color(1.0, 0.16, 0.05)
const FLARE_ENERGY := 1.1
const PAINT_MATS := ["paint", "roof"]
const RIM_MATS := ["rim", "rim_face"]

## CarPaint's shader with the paint per instance (one material, every car).
static var BODY_SHADER: String:
	get: return CarPaint.code("body_instance", CarPaint.tier())

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float energy = 2.5;
uniform float tail_gain = 1.0;
uniform float brake_gain = 2.2;
const float FLASH_GAIN = 3.5;
instance uniform float brake : instance_index(1) = 0.0;
// Turn lamps: 0 off, 1 left, 2 right, 3 both (hazard). Plus 4: the left tail
// lamp is out (a weaving driver's tell).
instance uniform float turn : instance_index(2) = 0.0;
// 1 while the driver flashes the headlights (at a player who cut in).
instance uniform float flash : instance_index(3) = 0.0;
// 1 while the car is in reverse (player cars: the CarFittings reverse lens).
instance uniform float reverse : instance_index(4) = 0.0;
varying float v_side;
void vertex() {
	v_side = sign(VERTEX.x);  // + = the car's right (it faces -Z)
}
void fragment() {
	vec3 c = COLOR.rgb;
	// Vertex alpha tags the lenses CarFittings adds: 0.7 indicator, 0.8
	// third brake light, 0.9 reverse. 1.0 is a sheet lamp, classed by colour.
	float tag = COLOR.a;
	float t_turn = step(0.65, tag) * (1.0 - step(0.75, tag));
	float t_third = step(0.75, tag) * (1.0 - step(0.85, tag));
	float t_rev = step(0.85, tag) * (1.0 - step(0.95, tag));
	// Linear colours: the tail red is the only lamp with green and blue near 0,
	// the amber turn lamp the only one with green between 0.3 and 0.7.
	float tail = step(0.4, c.r) * step(c.g, 0.06) * step(c.b, 0.06) * (1.0 - t_third);
	float amber = max(step(0.8, c.r) * step(0.3, c.g) * step(c.g, 0.7) * step(c.b, 0.2), t_turn);
	float k = mix(1.0, tail_gain * (1.0 + brake * brake_gain), tail);
	// Third brake light: out until the brake is on.
	k = mix(k, 0.12 + brake * 3.0, t_third);
	// Reverse lamp: a dim lens until the car is in reverse.
	k = mix(k, mix(0.25, 2.2, step(0.5, reverse)), t_rev);
	// Indicators: one side blinks for a turn signal, both for the hazards.
	float blink = step(0.5, fract(TIME * 1.4));
	float lamp_out = step(3.5, turn);
	float sig = turn - 4.0 * lamp_out;
	k *= mix(1.0, 0.03, tail * lamp_out * step(v_side, 0.0));
	float lit = sig > 2.5 ? 1.0 : (sig > 1.5 ? step(0.0, v_side) : (sig > 0.5 ? step(v_side, 0.0) : 0.0));
	k *= mix(1.0, mix(0.15, 2.5, blink), amber * lit);
	// The head lamps (warm white: the only lamp with all three channels up).
	float head = step(0.8, c.r) * step(0.7, c.g) * step(0.3, c.b);
	k *= mix(1.0, FLASH_GAIN, head * flash);
	ALBEDO = c;
	EMISSION = c * energy * k;
}
"""

## The tail flares: one quad per tail lamp, all four corners at the lamp's
## centre with UV = the corner, spread out here facing the camera. The radius
## is the larger of `near_r` metres and `min_screen` of the screen height, so it stays a point
## at any distance; it is pulled 0.25 m toward the camera so the lamp's own
## body never hides it. Additive and depth-tested: no sorting, and a car in
## front still covers the one behind it.
const FLARE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;
uniform vec3 tint = vec3(1.0, 0.16, 0.05);
uniform float energy = 1.1;
uniform float gain = 1.0;
uniform float near_r = 0.14;
uniform float min_screen = 0.006;
instance uniform float brake : instance_index(1) = 0.0;
instance uniform float turn : instance_index(2) = 0.0;
varying float v_face;
void vertex() {
	// The left tail lamp is out (turn carries + 4): no flare on that side.
	float lamp_out = step(3.5, turn) * step(VERTEX.x, 0.0);
	vec3 c = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = max(-c.z, 0.05);
	vec3 rear = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	v_face = smoothstep(0.05, 0.35, dot(-normalize(c), rear));
	// The view's height at distance d is 2d / |P[1][1]| (negative under
	// Vulkan's flipped Y, hence the abs).
	float far_r = min_screen * 2.0 * d / abs(PROJECTION_MATRIX[1][1]);
	float r = max(near_r, far_r) * (1.0 + 0.6 * brake) * v_face * step(0.001, gain) * (1.0 - lamp_out);
	c *= max(d - 0.25, 0.05) / d;
	c.xy += UV * r;
	VERTEX = c;
}
void fragment() {
	// A flat core to half the radius, then a soft edge: a few pixels out
	// there still read as a lamp, not a smear.
	float f = 1.0 - smoothstep(0.45, 1.0, length(UV));
	ALBEDO = tint * energy * gain * (1.0 + 1.5 * brake) * f * v_face;
}
"""

static var _body_meshes := {}   # "kind|build" -> ArrayMesh
static var _wheel_meshes := {}  # "kind|build|front/rear" -> ArrayMesh
static var _fit_counts := {}    # "kind|build" -> CarFittings counts
static var _fit_points := {}    # "kind|build" -> CarFittings points
static var _fit_frames := {}    # "kind|build" -> windscreen frame and fuel flap site
static var _body_mat: ShaderMaterial
static var _wheel_mat: ShaderMaterial
static var _glass_mat: ShaderMaterial
static var _glow_mat: ShaderMaterial
static var _parts_glow_mat: ShaderMaterial
static var _flare_mat: ShaderMaterial
static var _light_glow := 1.0

## The night-lights setting (TrafficSettings.light_glow): scales the tail
## lamps' running glow and the flares on every traffic car at once.
static func set_light_glow(g: float) -> void:
	_light_glow = g
	if _glow_mat != null:
		_glow_mat.set_shader_parameter("tail_gain", g)
	if _parts_glow_mat != null:
		_parts_glow_mat.set_shader_parameter("tail_gain", g)
	if _flare_mat != null:
		_flare_mat.set_shader_parameter("gain", g)

## Head lamps on full for a flash (TrafficCar: flashing back at the player).
## One instance uniform, written at the start and end of each flash.
static func set_flash(vis: Node3D, on: bool) -> void:
	var mi := vis.get_node_or_null(^"Body") as MeshInstance3D
	if mi != null:
		mi.set_instance_shader_parameter("flash", 1.0 if on else 0.0)

## Turn lamp states for set_lamps.
const TURN_OFF := 0
const TURN_LEFT := 1
const TURN_RIGHT := 2
const TURN_BOTH := 3
## Added to a turn state: the left tail lamp is out.
const TAIL_OUT := 4

## Brake (0..1) and turn lamps for one car's lamps; `vis` is its chassis_visual.
## `turn` is TURN_OFF / LEFT / RIGHT / BOTH (= hazard) + TAIL_OUT for a dead
## left tail lamp, or a bool (true = hazard). The player's cars (and the coupe)
## also have reverse lamps and left/right indicators; the extra arguments
## default to off so traffic's call is unchanged. Instance uniforms on the
## body, no material change.
static func set_lamps(vis: Node3D, brake: float, turn = 0, reverse := false,
		turn_left := false, turn_right := false) -> void:
	var state := 0
	if typeof(turn) == TYPE_BOOL:
		state = TURN_BOTH if turn else TURN_OFF
	else:
		state = int(turn)
	if turn_left:
		state |= TURN_LEFT
	if turn_right:
		state |= TURN_RIGHT
	var mi := vis.get_node_or_null(^"Body") as MeshInstance3D
	if mi != null:
		mi.set_instance_shader_parameter("brake", brake)
		mi.set_instance_shader_parameter("turn", float(state))
		mi.set_instance_shader_parameter("reverse", 1.0 if reverse else 0.0)

static func is_npc(kind: String) -> bool:
	return KINDS.has(kind)

## The keys TrafficCar reads from CarBuilder.KIND_CONFIGS (wheel_r, axle_z,
## wheel_x, main_w, hood_z0 = front tip z, main_z1 = rear tip z), plus this
## car's collision box and rest height.
static func config(kind: String) -> Dictionary:
	var k: Dictionary = KINDS[kind]
	var half_wb: float = k.axle_z
	var lift := -float(k.rest_y)
	# Collision box: the body's footprint, from just above the sheet's ground
	# clearance to most of its height, in chassis space at rest.
	var y0: float = lift + float(k.clearance) + 0.02
	var y1: float = lift + float(k.height) * 0.9
	return {
		"wheel_r": k.wheel_r, "axle_z": k.axle_z, "wheel_x": k.wheel_x,
		"main_w": k.width,
		"hood_z0": -(float(k.front_overhang) + half_wb),
		"main_z1": float(k.rear_overhang) + half_wb,
		"rest_y": k.rest_y,
		"col_size": Vector3(float(k.width) * 0.96, y1 - y0, float(k.length) * 0.97),
		"col_y": (y0 + y1) / 2.0,
	}

static func builds(kind: String) -> Array:
	return (KINDS[kind].data.BUILDS as Dictionary).keys()

## A build by the KINDS weights.
static func pick_build(kind: String) -> String:
	var w: Dictionary = KINDS[kind].builds
	var total := 0
	for b in w:
		total += int(w[b])
	var r := randi() % total
	for b in w:
		r -= int(w[b])
		if r < 0:
			return b
	return "stock"

## The design sheet's paint colour for this car (its data COLORS "paint").
static func sheet_paint(kind: String) -> Color:
	return Color(KINDS[kind].data.COLORS["paint"])

## Paint for a car of this build: the build's own colour, the sheet's paint
## (sheet_paint kinds), or a weighted traffic neutral.
static func pick_paint(kind: String, build: String) -> Color:
	var fixed: Dictionary = KINDS[kind].build_paint
	if fixed.has(build):
		return fixed[build]
	if KINDS[kind].get("sheet_paint", false):
		return sheet_paint(kind)
	var total := 0
	for p in PAINTS:
		total += int(p[1])
	var r := randi() % total
	for p in PAINTS:
		r -= int(p[1])
		if r < 0:
			return p[0]
	return PAINTS[0][0]

## Body, glass and lights (no wheels: those hang under the physics wheels).
## Metas as P1CoupeBuilder's: "kind", "build", "half_w", "half_l",
## "exhaust_tips", "sticker_slots" (centre and normal; no markers, traffic
## has no stickers yet).
## `role` is an Undercarriage role (player, crew, cop, traffic); "" picks
## it from the kind's prefix. Traffic gets no underside: the sheet's own
## dark tray is in the body mesh. The others get the real set, one draw call.
static func chassis_visual(kind: String, build: String, paint: Color, role := "") -> Node3D:
	var k: Dictionary = KINDS[kind]
	var b: Dictionary = k.data.BUILDS[build]
	var lift := Vector3(0.0, -float(k.rest_y), 0.0)
	if role == "":
		role = Undercarriage.role_for_kind(kind)
	var root := Node3D.new()
	root.name = "NpcBody"
	root.set_meta("kind", kind)
	root.set_meta("build", build)
	if uses_parts(kind):
		# Cars from parts: the body is assembled from the real parts in
		# assets/cars/<kind>/body.glb (CarAssembler: one mesh, 4 surfaces).
		var paint_mat := ShaderMaterial.new()
		paint_mat.shader = CarAssembler.paint_shader(P1CoupeBuilder.PARTS_BODY_SHADER)
		paint_mat.set_shader_parameter("paint", paint)
		var body := CarAssembler.build(kind, parts_config(), paint_mat)
		body.position = lift
		# This builder's lamp shader on the glow surface, so brake and hazard
		# (set_lamps) work on a parts car as they do on a sheet car.
		var gi := CarAssembler.surface_index(body.mesh, "glow")
		if gi >= 0:
			body.set_surface_override_material(gi, _get_parts_glow_material())
		root.add_child(body)
		root.set_meta("body_mat", paint_mat)
		root.set_meta("tail_lights", _parts_tail_lamps(kind, lift))
	else:
		var mi := MeshInstance3D.new()
		mi.name = "Body"
		mi.position = lift
		mi.mesh = body_mesh(kind, build)
		mi.set_instance_shader_parameter("paint", paint)
		# The tail flares grow past the body's box at a distance.
		mi.extra_cull_margin = 2.0
		root.add_child(mi)
	var tips := []
	for t in b.tips:
		tips.append({"pos": t.pos + lift, "dir": t.dir, "r": t.r})
	root.set_meta("exhaust_tips", tips)
	var slots := []
	for s in b.slots:
		for p in s.placements:
			slots.append({"id": s.id, "size": s.size, "center": p.center + lift, "normal": p.normal})
	root.set_meta("sticker_slots", slots)
	root.set_meta("half_w", float(k.width) / 2.0)
	root.set_meta("half_l", float(k.length) / 2.0)
	# Which small parts this body carries (CarSlots, tests/car/required_slots.gd).
	root.set_meta("fittings", fittings(kind, build))
	root.set_meta("fitting_points", _fit_points.get("%s|%s" % [kind, build], {}))
	root.set_meta("windscreen", _fit_frames.get("%s|%s" % [kind, build], {}).get("screen", {}))
	root.set_meta("fuel_flap_site", _fit_frames.get("%s|%s" % [kind, build], {}).get("flap", {}))
	Undercarriage.attach(root, undercarriage_params(kind, build), role)
	return root

## True when this kind's body is assembled from a parts glb (the default once
## the glb is in the project). NEON_PARTS_LEGACY=1 keeps every sheet car on
## its one-piece sheet proxy (before-shots, comparisons).
static func uses_parts(kind: String) -> bool:
	return OS.get_environment("NEON_PARTS_LEGACY") != "1" and CarAssembler.has_car(kind)

## What CarAssembler builds: the stock parts, panels closed. NEON_CAR_PANELS=open
## opens the lids, the doors and the fuel flap (pictures; nothing in the game
## opens them yet).
static func parts_config() -> Dictionary:
	return {"panels": "open"} if OS.get_environment("NEON_CAR_PANELS") == "open" else {}

## Centres of the lit tail lamps of a parts car, car space (wet-road smears).
static func _parts_tail_lamps(kind: String, lift: Vector3) -> Array:
	var out := []
	for pname in CarAssembler.part_names(kind):
		var mats := CarAssembler.part_arrays(kind, pname)
		if not mats.has("glow_tail"):
			continue
		var sum := Vector3.ZERO
		var verts: PackedVector3Array = mats["glow_tail"].v
		for v in verts:
			sum += v
		out.append(sum / maxi(verts.size(), 1) + lift)
	return out

## What the underside is built from (Undercarriage.params), car space: the
## ground at rest is -rest_y above the origin, the floor the body's lowest
## point, the wheels the KINDS entry's. "drive" in KINDS, rwd when unset;
## the C3 interceptor is the straight-pipe cop variant.
static func undercarriage_params(kind: String, build: String) -> Dictionary:
	var k: Dictionary = KINDS[kind]
	var b: Dictionary = k.data.BUILDS[build]
	var lift := Vector3(0.0, -float(k.rest_y), 0.0)
	var floor_y: float = body_mesh(kind, build).get_aabb().position.y + lift.y
	var engine := String(k.get("engine", "front"))
	var tips := []
	for t in b.tips:
		tips.append({"pos": t.pos + lift, "dir": t.dir, "r": t.r})
	var variant := "interceptor" if kind.contains("interceptor") else ""
	return Undercarriage.params(float(k.width) / 2.0, float(k.length) / 2.0, floor_y, lift.y,
		float(k.wheel_r), float(k.wheel_x), float(k.axle_z), tips, String(k.get("drive", "rwd")), variant, engine)

## Tyre and rim for one corner, to parent under its physics Wheel (the pivot
## is what the wheel moves and spins). `hub` is the wheel's position in car
## space; the design's right-hand wheel is turned round for the left side.
static func wheel_visual(kind: String, build: String, hub: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "NpcWheel"
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var corner := ("r" if hub.z > 0.0 else "f") + ("l" if hub.x < 0.0 else "r")
	var parts_wheel: ArrayMesh = CarAssembler.wheel_mesh(kind, corner) if uses_parts(kind) else null
	if parts_wheel != null:
		# A parts car's wheel carries its brake and hubcap, modelled per corner.
		mi.mesh = parts_wheel
		mi.set_surface_override_material(0, CarAssembler.trim_material())
	else:
		mi.mesh = wheel_mesh(kind, build, hub.z > 0.0)
		if hub.x < 0.0:
			mi.rotation.y = PI
	pivot.add_child(mi)
	return pivot

## Triangles of one car as drawn (body plus 4 wheels).
static func triangle_count(kind: String, build: String) -> int:
	if uses_parts(kind):
		var total := CarAssembler.triangle_count(kind, parts_config())
		for corner in ["fl", "fr", "rl", "rr"]:
			total += CarAssembler.wheel_triangle_count(kind, corner)
		return total
	var n := 0
	var m := body_mesh(kind, build)
	for i in m.get_surface_count():
		n += m.surface_get_array_len(i) / 3
	for rear in [false, true]:
		n += 2 * wheel_mesh(kind, build, rear).surface_get_array_len(0) / 3
	# The design's triangles: CarFittings' lenses and plates are counted apart
	# (fittings(kind, build).tris) and cost no draw call.
	return n - int(fittings(kind, build).get("tris", 0))

## Body surfaces, 4 wheels, plus the underside where the class has one
## (Undercarriage.draw_calls; traffic +0).
static func draw_call_count(kind: String, build: String, role := "") -> int:
	if role == "":
		role = Undercarriage.role_for_kind(kind)
	if uses_parts(kind):
		return CarAssembler.draw_call_count(kind, parts_config()) + 4 + Undercarriage.draw_calls(role)
	return body_mesh(kind, build).get_surface_count() + 4 + Undercarriage.draw_calls(role)

# ---------- meshes ----------

static func body_mesh(kind: String, build: String) -> ArrayMesh:
	var key := "%s|%s" % [kind, build]
	if not _body_meshes.has(key):
		var data: GDScript = KINDS[kind].data
		var b: Dictionary = data.BUILDS[build]
		var k: Dictionary = KINDS[kind]
		var hubs := []
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				hubs.append(Vector3(sx * float(k.wheel_x), float(k.wheel_r), sz * float(k.axle_z)))
		var tris := P1CoupeBuilder.decode_points(data.b64(b.body_pos))
		var mats := Marshalls.base64_to_raw(b.body_mat)
		# Reverse and third brake lenses, indicators the sheet lacks and both
		# plates, merged into this body's own surfaces (CarFittings).
		var fit := CarFittings.build(key, tris, mats, data.NAMES, data.GLASS, data.EMISSIVE, data.COLORS)
		_fit_counts[key] = fit.counts
		_fit_points[key] = fit.points
		_fit_frames[key] = {"screen": fit.get("screen", {}), "flap": fit.get("flap", {})}
		var mesh := _build_mesh(data, tris, mats, true, {"wheels": hubs, "wheel_r": float(k.wheel_r), "fit": fit})
		mesh.set_meta("paint_seams", CarPaint.cut_seams(data, tris, mats, int(CarPaint.DOORS.get(kind, 2))))
		_body_meshes[key] = mesh
	return _body_meshes[key]

## What CarFittings added to a body, by slot (CarSlots reads it off the
## chassis visual's "fittings" meta; this is the same dictionary).
static func fittings(kind: String, build: String) -> Dictionary:
	body_mesh(kind, build)
	return _fit_counts["%s|%s" % [kind, build]]

static func wheel_mesh(kind: String, build: String, rear: bool) -> ArrayMesh:
	var key := "%s|%s|%s" % [kind, build, "rear" if rear else "front"]
	if not _wheel_meshes.has(key):
		var data: GDScript = KINDS[kind].data
		var w: Dictionary = data.BUILDS[build].wheels[1 if rear else 0]
		_wheel_meshes[key] = _build_mesh(data, P1CoupeBuilder.decode_points(w.pos), Marshalls.base64_to_raw(w.mat), false)
	return _wheel_meshes[key]

## Same as P1CoupeBuilder._build_mesh (CarPaint.build_groups): surfaces
## "body", "glass", "glow", plus the tail "flare" quads on a body.
static func _build_mesh(data: GDScript, tris: PackedVector3Array, mats: PackedByteArray, is_body: bool, opts := {}) -> ArrayMesh:
	opts["is_wheel"] = not is_body
	var groups := CarPaint.build_groups(data, tris, mats, PAINT_MATS if is_body else RIM_MATS, opts)
	if is_body and opts.has("fit"):
		_append_fittings(groups, opts.fit)
	var mesh := ArrayMesh.new()
	if is_body and "tail" in data.NAMES:
		groups["flare"] = _flare_quads(data, tris, mats)
	for surf in ["body", "glass", "glow", "flare"]:
		if not groups.has(surf):
			continue
		var idx: int
		if surf == "flare":
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = groups[surf][0]
			arrays[Mesh.ARRAY_NORMAL] = groups[surf][1]
			arrays[Mesh.ARRAY_COLOR] = groups[surf][2]
			arrays[Mesh.ARRAY_TEX_UV] = groups[surf][3]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			idx = mesh.get_surface_count() - 1
			mesh.surface_set_name(idx, surf)
		else:
			idx = CarPaint.add_surface(mesh, groups[surf], surf)
		match surf:
			"glass":
				mesh.surface_set_material(idx, _get_glass_material())
			"glow":
				mesh.surface_set_material(idx, _get_glow_material())
			"flare":
				mesh.surface_set_material(idx, _get_flare_material())
			_:
				mesh.surface_set_material(idx, _get_body_material() if is_body else _get_wheel_material(data))
	return mesh

## Adds CarFittings' lenses and plates to the body and glow surfaces (shared
## with P1CoupeBuilder, same group layout: verts, normals, colours).
static func _append_fittings(groups: Dictionary, fit: Dictionary) -> void:
	for surf in ["body", "glow"]:
		var ex: Array = fit[surf]
		if (ex[0] as PackedVector3Array).is_empty():
			continue
		if not groups.has(surf):
			groups[surf] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(),
				PackedVector2Array(), PackedVector2Array(), PackedFloat32Array(), PackedFloat32Array()]
		var g: Array = groups[surf]
		for i in 3:
			g[i].append_array(ex[i])
		# CarPaint's groups also carry finish, occlusion and (body) edge arrays
		# per vertex: the fittings get the default finish, no occlusion, no edges.
		var n_v: int = (ex[0] as PackedVector3Array).size()
		var fin: Array = CarPaint.FINISH_DEFAULT
		for _v in n_v:
			g[3].append(Vector2(fin[0], fin[1]))
			g[4].append(Vector2.ZERO)
			if surf == "body":
				g[5].append_array(CarPaint._NO_EDGES)
				g[6].append_array(CarPaint._NO_EDGES)

## One flare quad per side at the area-weighted centre of that side's tail
## lamp faces (two triangles, all corners at the centre, UV = the corner).
## Arrays as _build_mesh's groups, plus UVs.
static func _flare_quads(data: GDScript, tris: PackedVector3Array, mats: PackedByteArray) -> Array:
	var tail: int = data.NAMES.find("tail")
	var sums := {-1: Vector3.ZERO, 1: Vector3.ZERO}
	var areas := {-1: 0.0, 1: 0.0}
	for t in mats.size():
		if mats[t] != tail:
			continue
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var area := (b - a).cross(c - a).length() / 2.0
		var side := 1 if (a + b + c).x > 0.0 else -1
		sums[side] += (a + b + c) / 3.0 * area
		areas[side] += area
	var out := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array()]
	var col := Color(data.COLORS["tail"]).srgb_to_linear()
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for side in [-1, 1]:
		if float(areas[side]) <= 0.0:
			continue
		var centre: Vector3 = sums[side] / float(areas[side])
		for uv in corners:
			out[0].append(centre)
			out[1].append(Vector3(0.0, 0.0, 1.0))
			out[2].append(col)
			out[3].append(uv)
	return out

# ---------- materials (one of each for every traffic car) ----------

static func _get_body_material() -> ShaderMaterial:
	if _body_mat == null:
		_body_mat = ShaderMaterial.new()
		_body_mat.shader = CarPaint.body_shader(true)
	return _body_mat

## Wheels: the body shader with a plain uniform set to the rim colour, so the
## rim faces get the glossy finish without taking the car's paint. All three
## traffic cars share the same rim colour (proxies.json).
static func _get_wheel_material(data: GDScript) -> ShaderMaterial:
	if _wheel_mat == null:
		_wheel_mat = ShaderMaterial.new()
		_wheel_mat.shader = CarPaint.body_shader(false)
		_wheel_mat.set_shader_parameter("paint", Color(data.COLORS.rim))
		_wheel_mat.set_shader_parameter("paint_metallic", 0.8)
		_wheel_mat.set_shader_parameter("paint_roughness", 0.3)
	return _wheel_mat

static func _get_glass_material() -> ShaderMaterial:
	if _glass_mat == null:
		_glass_mat = ShaderMaterial.new()
		_glass_mat.shader = CarPaint.glass_shader(false)
		_glass_mat.set_shader_parameter("glass", Color("#151D2E"))
	return _glass_mat

## The same lamp shader for a body assembled from parts, one-sided: a parts
## lamp is wound outward, and a lamp laid on the rear glass (the wagon's tall
## columns) must not shine into the cabin and the rear-view mirror.
static func _get_parts_glow_material() -> ShaderMaterial:
	if _parts_glow_mat == null:
		var sh := Shader.new()
		sh.code = GLOW_SHADER.replace("unshaded, cull_disabled", "unshaded, cull_back")
		_parts_glow_mat = ShaderMaterial.new()
		_parts_glow_mat.shader = sh
		_parts_glow_mat.set_shader_parameter("energy", GLOW_ENERGY)
		_parts_glow_mat.set_shader_parameter("tail_gain", _light_glow)
		_parts_glow_mat.set_shader_parameter("brake_gain", BRAKE_GAIN)
	return _parts_glow_mat

static func _get_glow_material() -> ShaderMaterial:
	if _glow_mat == null:
		var sh := Shader.new()
		sh.code = GLOW_SHADER
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = sh
		_glow_mat.set_shader_parameter("energy", GLOW_ENERGY)
		_glow_mat.set_shader_parameter("brake_gain", BRAKE_GAIN)
		_glow_mat.set_shader_parameter("tail_gain", _light_glow)
	return _glow_mat

static func _get_flare_material() -> ShaderMaterial:
	if _flare_mat == null:
		var sh := Shader.new()
		sh.code = FLARE_SHADER
		_flare_mat = ShaderMaterial.new()
		_flare_mat.shader = sh
		_flare_mat.set_shader_parameter("tint", Vector3(FLARE_TINT.r, FLARE_TINT.g, FLARE_TINT.b))
		_flare_mat.set_shader_parameter("energy", FLARE_ENERGY)
		_flare_mat.set_shader_parameter("near_r", FLARE_NEAR_R)
		_flare_mat.set_shader_parameter("min_screen", FLARE_MIN_SCREEN)
		_flare_mat.set_shader_parameter("gain", _light_glow)
	return _flare_mat
