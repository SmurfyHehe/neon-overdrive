class_name M1MonsterBuilder
extends RefCounted

# The monster truck's body (special vehicles S1, Roy 2026-10-10). A proxy: a
# lifted cab on a frame, square flares and 0.85 m wheels, built from boxes and
# cylinders in the game's own palette. Original shape, no licensed truck. The
# real art comes with the vehicle's design pass; the dimensions here are the
# ones the physics is tuned for (CFG, CarSpec.player_spec("m1_monster")).
#
# Same contract as P1CoupeBuilder: build_chassis_visual() and
# build_wheel_visual(); origin on the ground midway between the axles, X right,
# Y up, -Z forward. The wheel mounts sit at spring_length + wheel_r above the
# chassis origin (CarSpec.build_wheels), so the body is drawn on the ground
# plane and needs no lift.

const KIND := "m1_monster"

## Wheel hardpoints and the collision box (PlayerCar.wheel_config reads this
## for the player; the box is what the RigidBody collides with, between the
## wheels and clear of the ground).
const CFG := {
	"wheel_r": 0.85, "axle_z": 1.9, "wheel_x": 1.35,
	"col_size": Vector3(2.0, 1.5, 4.6), "col_y": 1.5,
}
const TIRE_WIDTH := 0.6
const LENGTH := 5.4
const WIDTH := 2.0

# Palette: Amber vs. Dusk (sodium orange paint, navy-black trim, silver hubs).
const PAINT := Color("#FF8A1F")
const TRIM := Color("#1A1D24")
const GLASS := Color("#151D2E")
const TIRE := Color("#15171C")
const SILVER := Color("#C9CED6")
const HEAD := Color("#FFE7BD")
const TAIL := Color("#E5262B")

static func _mat(c: Color, rough: float = 0.7, metal: float = 0.0, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m

static func _box(parent: Node3D, name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

static func build_chassis_visual(paint: Color = PAINT) -> Node3D:
	var root := Node3D.new()
	root.name = "M1Monster"
	root.set_meta("kind", KIND)
	var paint_mat := _mat(paint, 0.55)
	var trim := _mat(TRIM, 0.8)
	var glass := _mat(GLASS, 0.15, 0.2)
	var head := _mat(HEAD, 0.3, 0.0, 3.0)
	var tail := _mat(TAIL, 0.3, 0.0, 2.0)
	var chrome := _mat(SILVER, 0.3, 0.8)
	# frame, axles, driveshaft housings
	_box(root, "Frame", Vector3(1.1, 0.32, 4.4), Vector3(0, 1.15, 0), trim)
	for z in [-CFG.axle_z, CFG.axle_z]:
		_box(root, "Axle", Vector3(2.5, 0.22, 0.24), Vector3(0, CFG.wheel_r, z), trim)
		_box(root, "Diff", Vector3(0.5, 0.45, 0.5), Vector3(0, CFG.wheel_r + 0.1, z), trim)
	# cab, hood, bed
	_box(root, "Cab", Vector3(1.9, 0.95, 2.1), Vector3(0, 1.95, 0.55), paint_mat)
	_box(root, "Greenhouse", Vector3(1.75, 0.8, 1.7), Vector3(0, 2.75, 0.6), glass)
	_box(root, "Roof", Vector3(1.85, 0.1, 1.9), Vector3(0, 3.19, 0.6), paint_mat)
	_box(root, "Hood", Vector3(1.85, 0.55, 1.5), Vector3(0, 1.95, -1.55), paint_mat)
	_box(root, "Bed", Vector3(1.9, 0.7, 1.4), Vector3(0, 1.8, 1.95), paint_mat)
	# fender flares over each wheel, bumpers, grille
	for s in [-1.0, 1.0]:
		for z in [-CFG.axle_z, CFG.axle_z]:
			_box(root, "Flare", Vector3(0.78, 0.14, 1.9), Vector3(s * CFG.wheel_x, 1.78, z), trim)
	_box(root, "BumperFront", Vector3(2.1, 0.34, 0.3), Vector3(0, 1.1, -2.62), trim)
	_box(root, "BumperRear", Vector3(2.1, 0.34, 0.3), Vector3(0, 1.1, 2.62), trim)
	_box(root, "Grille", Vector3(1.3, 0.4, 0.08), Vector3(0, 1.95, -2.32), trim)
	# lamps (CarFx's spotlight and the tail glow read the metas below)
	var heads: Array[Vector3] = []
	var tails: Array[Vector3] = []
	for s in [-1.0, 1.0]:
		var hp := Vector3(s * 0.7, 2.0, -2.34)
		var tp := Vector3(s * 0.75, 1.95, 2.66)
		_box(root, "Head", Vector3(0.34, 0.2, 0.06), hp, head)
		_box(root, "Tail", Vector3(0.3, 0.16, 0.06), tp, tail)
		heads.append(hp)
		tails.append(tp)
	# twin upright exhaust stacks behind the cab (the flames' tips)
	var tips: Array = []
	for s in [-1.0, 1.0]:
		var stack := MeshInstance3D.new()
		stack.name = "Stack"
		var cm := CylinderMesh.new()
		cm.top_radius = 0.08
		cm.bottom_radius = 0.08
		cm.height = 1.3
		stack.mesh = cm
		stack.material_override = chrome
		stack.position = Vector3(s * 0.8, 3.0, 1.25)
		root.add_child(stack)
		tips.append({"pos": Vector3(s * 0.8, 3.66, 1.25), "dir": Vector3(0, 1, 0), "r": 0.08})
	root.set_meta("headlights", heads)
	root.set_meta("tail_lights", tails)
	root.set_meta("exhaust_tips", tips)
	root.set_meta("sticker_slots", [])
	root.set_meta("body_mat", paint_mat)
	root.set_meta("half_w", WIDTH / 2.0)
	root.set_meta("half_l", LENGTH / 2.0)
	return root

## One wheel: the tyre, a silver hub on the outer face, and lug nuts so the
## spin shows. The sim spins the pivot about X and steers it about Y.
static func build_wheel_visual(radius: float, hub: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "M1Wheel"
	var side := signf(hub.x) if hub.x != 0.0 else 1.0
	var tire := MeshInstance3D.new()
	tire.name = "Tire"
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = TIRE_WIDTH
	cm.radial_segments = 20
	tire.mesh = cm
	tire.rotation.z = PI / 2.0
	tire.material_override = _mat(TIRE, 0.9)
	pivot.add_child(tire)
	var hubm := MeshInstance3D.new()
	hubm.name = "Hub"
	var hm := CylinderMesh.new()
	hm.top_radius = radius * 0.5
	hm.bottom_radius = radius * 0.5
	hm.height = TIRE_WIDTH + 0.04
	hm.radial_segments = 16
	hubm.mesh = hm
	hubm.rotation.z = PI / 2.0
	hubm.material_override = _mat(SILVER, 0.35, 0.7)
	pivot.add_child(hubm)
	var lug := _mat(TRIM, 0.6)
	for i in 6:
		var a := TAU * i / 6.0
		_box(pivot, "Lug", Vector3(0.05, 0.1, 0.1),
			Vector3(side * (TIRE_WIDTH * 0.5 + 0.03), sin(a) * radius * 0.34, cos(a) * radius * 0.34), lug)
	return pivot

## Triangle-ish cost note for tests: node count of one car (body + 4 wheels).
static func part_count() -> int:
	var b := build_chassis_visual()
	var n := b.get_child_count()
	b.free()
	return n + 4 * 8
