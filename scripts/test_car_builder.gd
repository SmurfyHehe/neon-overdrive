extends RefCounted
class_name TestCarBuilder

# Neutral test car (GitHub #63): a plain low-poly coupe for judging handling
# and camera. It is NOT the starter car and not the final look -- that stays
# in #16 -- so it is deliberately bland: grey body, one orange stripe down the
# centreline, bright headlights, red tail lights. The stripe and the lights
# are there so the nose and tail, and therefore the car's yaw, read at a
# glance from the chase cam.
#
# Spec (Roy approved): about 4.4 m long x 1.8 m wide x 1.3 m tall, wheelbase
# and track matching the physics wheels. The physics wheels (player.gd CFG)
# sit 2.5 m apart front to back (Phase B, was 2.1) and 1.76 m side to side, so
# the body has ~0.95 m overhangs and the tyres stand ~8 cm proud of the 1.8 m
# body. That is intentional: the visuals show exactly where the physics wheels are.
#
# Forward is -Z, up is +Y, ground at y = 0 with the springs fully extended
# (the body settles a few cm lower once the suspension loads). Reuses
# CarBuilder's loft and material helpers (winding/normals fixed in #43/#45).

const KIND := "test"

const LENGTH := 4.4
const WIDTH := 1.8
const HEIGHT := 1.3
const TYRE_WIDTH := 0.24

const BODY_COLOR := Color(0.62, 0.64, 0.67)
const STRIPE_COLOR := Color(1.0, 0.45, 0.0)
const STRIPE_W := 0.34

## Lower body, nose (-Z) to tail (+Z). Each section is {z, w, y0, y1}.
const BODY_SECTIONS := [
	{"z": -2.2, "w": 1.62, "y0": 0.20, "y1": 0.56},
	{"z": -2.0, "w": 1.80, "y0": 0.15, "y1": 0.70},
	{"z": -0.6, "w": 1.80, "y0": 0.15, "y1": 0.84},
	{"z": 1.75, "w": 1.80, "y0": 0.15, "y1": 0.86},
	{"z": 2.2, "w": 1.66, "y0": 0.22, "y1": 0.78},
]

## Greenhouse on top of the body: raked windshield, flat roof, sloped
## backlight. Starts and ends at zero height so it blends into the body.
const CABIN_SECTIONS := [
	{"z": -0.6, "w": 1.50, "y0": 0.82, "y1": 0.82},
	{"z": 0.15, "w": 1.30, "y0": 0.82, "y1": HEIGHT},
	{"z": 0.95, "w": 1.30, "y0": 0.82, "y1": HEIGHT},
	{"z": 1.75, "w": 1.50, "y0": 0.84, "y1": 0.84},
]

static func build_chassis_visual() -> Node3D:
	var root := Node3D.new()
	root.set_meta("kind", KIND)

	var body_mat := CarBuilder._mat(BODY_COLOR, 0.0, 0.3, 0.45)
	var glass_mat := CarBuilder._mat(Color(0.05, 0.07, 0.09), 0.0, 0.8, 0.15)
	var stripe_mat := CarBuilder._mat(STRIPE_COLOR, 0.6, 0.1, 0.5)
	var head_mat := CarBuilder._mat(Color(1.0, 0.98, 0.9), 3.0)
	var tail_mat := CarBuilder._mat(Color(1.0, 0.08, 0.05), 2.5)

	root.add_child(CarBuilder._build_loft(BODY_SECTIONS, body_mat))
	root.add_child(CarBuilder._build_loft(CABIN_SECTIONS, glass_mat))

	# Stripe: a thin skin over the body top on the hood and deck, and over the
	# roof, skipping the glass. Lofted from the same sections, so it follows
	# the body's slopes exactly.
	root.add_child(CarBuilder._build_loft(_stripe(BODY_SECTIONS.slice(0, 3)), stripe_mat))
	root.add_child(CarBuilder._build_loft(_stripe(CABIN_SECTIONS.slice(1, 3)), stripe_mat))
	root.add_child(CarBuilder._build_loft(_stripe(BODY_SECTIONS.slice(3, 5)), stripe_mat))

	var nose: Dictionary = BODY_SECTIONS[0]
	var tail: Dictionary = BODY_SECTIONS[BODY_SECTIONS.size() - 1]
	for x in [-0.55, 0.55]:
		var hl := CarBuilder._box(Vector3(0.38, 0.11, 0.04), head_mat)
		hl.position = Vector3(x, 0.46, nose.z + 0.015)
		root.add_child(hl)
		var tl := CarBuilder._box(Vector3(0.44, 0.12, 0.04), tail_mat)
		tl.position = Vector3(x, 0.64, tail.z - 0.015)
		root.add_child(tl)

	# Twin tailpipes under the tail (effects pack v1): short dark stubs flush
	# with the tail face (the 4.4 m length is a tested spec), and the
	# "exhaust_tips" meta ExhaustFlames reads to know where to draw its bursts.
	var pipe_mat := CarBuilder._mat(Color(0.2, 0.2, 0.22), 0.0, 0.7, 0.4)
	var tips: Array[Vector3] = []
	for x in [-0.5, 0.5]:
		var tip := Vector3(x, 0.3, tail.z)
		var pipe := CylinderMesh.new()
		pipe.top_radius = 0.04
		pipe.bottom_radius = 0.04
		pipe.height = 0.16
		pipe.radial_segments = 8
		var mi := MeshInstance3D.new()
		mi.mesh = pipe
		mi.material_override = pipe_mat
		mi.rotation.x = PI / 2.0  # along Z
		mi.position = tip - Vector3(0.0, 0.0, 0.08)
		root.add_child(mi)
		tips.append(tip)
	root.set_meta("exhaust_tips", tips)

	root.set_meta("body_mat", body_mat)
	root.set_meta("half_w", WIDTH / 2.0)
	root.set_meta("half_l", LENGTH / 2.0)
	return root

## A 1.2 cm skin STRIPE_W wide sitting on the top edge of each section.
static func _stripe(sections: Array) -> Array:
	var out := []
	for s in sections:
		out.append({"z": s.z, "w": STRIPE_W, "y0": float(s.y1) - 0.002, "y1": float(s.y1) + 0.01})
	return out

## Tyre plus a light hub with one bright bar across it, so spin reads from
## the chase cam (a plain dark cylinder looks the same at any rotation).
## Symmetric left/right: the same visual goes on all four wheels.
static func build_wheel_visual(radius: float) -> Node3D:
	var root := Node3D.new()
	var tyre_mat := CarBuilder._mat(Color(0.06, 0.06, 0.07), 0.0, 0.1, 0.85)
	var hub_mat := CarBuilder._mat(Color(0.55, 0.57, 0.6), 0.0, 0.6, 0.35)
	var bar_mat := CarBuilder._mat(Color(1.0, 1.0, 1.0), 0.8, 0.0, 0.5)

	root.add_child(_disc(radius, TYRE_WIDTH, tyre_mat))
	root.add_child(_disc(radius * 0.62, TYRE_WIDTH + 0.01, hub_mat))
	var bar := CarBuilder._box(Vector3(TYRE_WIDTH + 0.02, radius * 1.2, radius * 0.2), bar_mat)
	root.add_child(bar)
	return root

## A cylinder lying along X (the axle).
static func _disc(radius: float, width: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	mesh.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.rotation.z = PI / 2.0
	return mi
