class_name EngineBay
extends Node3D

# Engine bay for the P1 coupe (car-parts plan 8b, item 2, 2026-10-09).
#
# The coupe's hood is part of the one body mesh, so the bay brings its own hood
# panel: while the hood is anything but shut, the body swaps to a copy with the
# hood triangles cut out, the panel swings up on a hinge at the cowl, and the
# bay underneath is shown. Shut, the whole node is hidden, so the drive costs
# nothing.
#
# Rules (the plan, Roy 2026-10-09):
#   - the hood opens anywhere the car is stopped: photo mode today, garage and
#     gas stations when they exist, through request_open();
#   - it closes itself on drive-off (DRIVE_OFF_SPEED);
#   - crashes never open it: nothing here listens to impacts, only to
#     GameState and to request_open().
#
# Every part is its own MeshInstance3D child, named by slot ("engine", "intake",
# "turbo", "hoses", "battery", "fan"), so a later mod tree can swap one with
# swap_part(). Built with CockpitKit (vertex colours, flat shading), palette
# Amber vs. Dusk; the hood panel takes the body's paint material so it recolours
# with the car. Positions are in body-mesh space (P1CoupeBuilder.BODY_LIFT is
# applied to this node), -Z forward, from the design sheet curves in
# docs/design/fleet/fleet.json (p1_coupe).

const STOP_SPEED := 0.5        # m/s: at or below this the car counts as stopped
const DRIVE_OFF_SPEED := 1.0   # m/s: above this an open hood shuts itself
const OPEN_ANGLE := 52.0       # degrees the nose end lifts
const OPEN_TIME := 0.9         # seconds to swing fully open (or shut)

## Sheet geometry (fleet.json p1_coupe), s measured from the nose in metres.
const NOSE_Z := -2.24          # front overhang 0.98 + half wheelbase 1.26
const HOOD_S0 := 0.30          # hood starts just behind the nose cap / pop-ups
const HOOD_S1 := 1.52          # hinge, just ahead of the windshield base (A = 1.55)
const TOP := [[0.05, 0.55], [0.3, 0.64], [1.0, 0.74], [1.55, 0.8]]      # centreline height
const BELT := [[0.0, 0.44], [0.4, 0.61], [1.55, 0.77]]                  # hood edge height
const HALF_W := [[0.1, 0.78], [0.4, 0.88], [0.98, 0.9], [2.2, 0.885]]   # body half width
const FENDER := 0.10           # shoulder kept on each side; the hood is narrower than the body
const HOOD_THICK := 0.022
const HOOD_SEGMENTS := 6

const PART_SLOTS := ["engine", "intake", "turbo", "hoses", "battery", "fan"]

# Colours. Alpha 0 is "paint" to the body shader (P1CoupeBuilder.BODY_SHADER).
const PAINT := Color(1.0, 1.0, 1.0, 0.0)
const HOOD_UNDER := Color("#1A1D23")
const TUB := Color("#111419")
const SEAL := Color("#0B0E14")
const CAST := Color("#3A3F47")
const ALLOY := Color("#B8BEC6")
const CHROME := Color("#C9CED6")
const RUBBER := Color("#0E1013")
const NAVY := Color("#1B2A4A")
const DUSK := Color("#0E1424")
const AMBER := Color("#FFC066")
const BLADE := Color("#20242B")
const FIN := Color("#15181E")

var car: RigidBody3D
var body: MeshInstance3D
var hinge: Node3D
var hood: MeshInstance3D
var tub: MeshInstance3D
var parts := {}                # slot -> MeshInstance3D
## Target: true from request_open() until close(); the hood animates toward it.
var is_open := false
## Current hood angle in degrees, 0 shut .. OPEN_ANGLE.
var angle := 0.0
var _closed_mesh: ArrayMesh
var _open_mesh: ArrayMesh
var _state: GameState

## Builds the bay under `chassis` (the P1CoupeBuilder visual) and hangs it on the car.
static func attach(vehicle: RigidBody3D, chassis: Node3D) -> EngineBay:
	var bay := EngineBay.new()
	bay.name = "EngineBay"
	bay.car = vehicle
	bay.body = chassis.get_node_or_null("Body") as MeshInstance3D
	bay.position = Vector3(0.0, P1CoupeBuilder.BODY_LIFT, 0.0)
	bay._build(chassis.get_meta("body_mat") as Material)
	vehicle.add_child(bay)
	return bay

## Opens the hood on the states where the car stands still (photo mode).
func bind_state(state: GameState) -> void:
	_state = state
	state.state_changed.connect(_on_state_changed)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the swing runs while photo mode pauses the tree
	visible = false

func _on_state_changed(new_state: GameState.State, _old: GameState.State) -> void:
	if new_state == GameState.State.PHOTO:
		request_open()

## True at or below STOP_SPEED.
func is_stopped() -> bool:
	return car != null and car.linear_velocity.length() <= STOP_SPEED

## Opens the hood if the car is stopped. Returns whether it is (now) opening.
func request_open() -> bool:
	if not is_stopped():
		return false
	is_open = true
	visible = true
	_show_open_body(true)
	return true

func close() -> void:
	is_open = false

func _physics_process(_delta: float) -> void:
	if is_open and car != null and car.linear_velocity.length() > DRIVE_OFF_SPEED:
		close()

func _process(delta: float) -> void:
	var target := OPEN_ANGLE if is_open else 0.0
	if is_equal_approx(angle, target):
		if not is_open and visible:
			_show_open_body(false)
			visible = false
		return
	angle = move_toward(angle, target, OPEN_ANGLE / OPEN_TIME * delta)
	hinge.rotation.x = deg_to_rad(angle)

## Replaces one part with another node (the mod tree's hook). The old part is freed.
func swap_part(slot: String, node: Node3D) -> void:
	var old: Node3D = parts.get(slot)
	if old != null:
		old.queue_free()
	node.name = slot.capitalize()
	node.set_meta("part_slot", slot)
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = 1 << (CarFx.CAR_LAYER - 1)
	add_child(node)
	parts[slot] = node

# ---------- body with the hood cut out ----------

func _show_open_body(open: bool) -> void:
	if body == null:
		return
	if _closed_mesh == null:
		_closed_mesh = body.mesh as ArrayMesh
	if open and _open_mesh == null:
		_open_mesh = _cut_hood(_closed_mesh)
	body.mesh = _open_mesh if open else _closed_mesh

## True for a point on the hood panel: between the nose cap and the hinge,
## inside the fender shoulders, at or above the hood's edge line.
static func in_hood_region(p: Vector3) -> bool:
	var s := p.z - NOSE_Z
	if s < HOOD_S0 - 0.02 or s > HOOD_S1 + 0.02:
		return false
	if absf(p.x) > _curve(HALF_W, s) - FENDER + 0.01:
		return false
	return p.y >= _curve(BELT, s) - 0.02

## A copy of the body mesh with the hood region removed from the "body" surface.
## Surfaces keep their order and materials, so the paint override on the
## instance still lands on the body surface.
static func _cut_hood(src: ArrayMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		var arrays := src.surface_get_arrays(i)
		if src.surface_get_name(i) == "body":
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var c: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var kv := PackedVector3Array()
			var kn := PackedVector3Array()
			var kc := PackedColorArray()
			for t in v.size() / 3:
				var centre := (v[t * 3] + v[t * 3 + 1] + v[t * 3 + 2]) / 3.0
				if in_hood_region(centre):
					continue
				for k in 3:
					kv.append(v[t * 3 + k])
					kn.append(n[t * 3 + k])
					kc.append(c[t * 3 + k])
			arrays = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = kv
			arrays[Mesh.ARRAY_NORMAL] = kn
			arrays[Mesh.ARRAY_COLOR] = kc
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_name(i, src.surface_get_name(i))
		var mat := src.surface_get_material(i)
		if mat != null:
			out.surface_set_material(i, mat)
	return out

# ---------- geometry ----------

static func _curve(curve: Array, s: float) -> float:
	if s <= curve[0][0]:
		return curve[0][1]
	for i in range(1, curve.size()):
		if s <= curve[i][0]:
			var a: Array = curve[i - 1]
			var b: Array = curve[i]
			return lerpf(a[1], b[1], (s - a[0]) / (b[0] - a[0]))
	return curve[-1][1]

func _mesh_node(kit: CockpitKit, mat: Material, node_name: String) -> MeshInstance3D:
	var mi := kit.instance(mat, node_name)
	mi.layers = 1 << (CarFx.CAR_LAYER - 1)
	return mi

func _build(paint_mat: Material) -> void:
	var dull := CockpitKit.material(0.85, 0.0, 0.08)
	var metal := CockpitKit.material(0.45, 0.6, 0.3)

	# Hood panel on its hinge at the cowl.
	hinge = Node3D.new()
	hinge.name = "HoodHinge"
	hinge.position = Vector3(0.0, _curve(TOP, HOOD_S1), NOSE_Z + HOOD_S1)
	add_child(hinge)
	var hk := CockpitKit.new()
	_hood_panel(hk, hinge.position)
	hood = _mesh_node(hk, paint_mat if paint_mat != null else metal, "Hood")
	hood.set_meta("part_slot", "hood")
	hinge.add_child(hood)

	# The tub: floor, inner fenders, firewall, radiator support, the seal lip
	# round the opening, and the radiator itself.
	var tk := CockpitKit.new()
	_tub(tk)
	tub = _mesh_node(tk, dull, "Tub")
	add_child(tub)

	var kits := {
		"engine": [CockpitKit.new(), metal], "intake": [CockpitKit.new(), metal],
		"turbo": [CockpitKit.new(), metal], "hoses": [CockpitKit.new(), dull],
		"battery": [CockpitKit.new(), dull], "fan": [CockpitKit.new(), dull],
	}
	_engine(kits.engine[0])
	_intake(kits.intake[0])
	_turbo(kits.turbo[0])
	_hoses(kits.hoses[0])
	_battery(kits.battery[0])
	_fan(kits.fan[0])
	for slot in PART_SLOTS:
		swap_part(slot, _mesh_node(kits[slot][0], kits[slot][1], slot))

## The hood as strips following the sheet's centreline and edge curves, built
## relative to the hinge so it rotates about its rear edge. Top faces are
## paint; the underside and edges are dark.
func _hood_panel(k: CockpitKit, pivot: Vector3) -> void:
	var ss := []
	for i in HOOD_SEGMENTS + 1:
		ss.append(lerpf(HOOD_S0, HOOD_S1, float(i) / HOOD_SEGMENTS))
	var pts := func(s: float, side: float, down: float) -> Vector3:
		# side 0 = centreline crown, +-1 = the edges
		var y := _curve(TOP, s) if side == 0.0 else _curve(BELT, s) + 0.01
		var x := side * (_curve(HALF_W, s) - FENDER)
		return Vector3(x, y - down, NOSE_Z + s) - pivot
	for i in HOOD_SEGMENTS:
		var s0: float = ss[i]      # nearer the nose (more negative z)
		var s1: float = ss[i + 1]
		for side in [-1.0, 1.0]:
			var c0: Vector3 = pts.call(s0, 0.0, 0.0)
			var c1: Vector3 = pts.call(s1, 0.0, 0.0)
			var e0: Vector3 = pts.call(s0, side, 0.0)
			var e1: Vector3 = pts.call(s1, side, 0.0)
			if side > 0.0:
				k.quad(c0, e0, e1, c1, PAINT)
			else:
				k.quad(e0, c0, c1, e1, PAINT)
			var uc0: Vector3 = pts.call(s0, 0.0, HOOD_THICK)
			var uc1: Vector3 = pts.call(s1, 0.0, HOOD_THICK)
			var ue0: Vector3 = pts.call(s0, side, HOOD_THICK)
			var ue1: Vector3 = pts.call(s1, side, HOOD_THICK)
			if side > 0.0:
				k.quad(uc1, ue1, ue0, uc0, HOOD_UNDER)
				k.quad(e0, ue0, ue1, e1, HOOD_UNDER)       # right edge
			else:
				k.quad(ue1, uc1, uc0, ue0, HOOD_UNDER)
				k.quad(ue0, e0, e1, ue1, HOOD_UNDER)       # left edge
	# front edge (nose end) and rear edge (at the hinge)
	for s in [ss[0], ss[-1]]:
		var l: Vector3 = pts.call(s, -1.0, 0.0)
		var c: Vector3 = pts.call(s, 0.0, 0.0)
		var r: Vector3 = pts.call(s, 1.0, 0.0)
		var ul: Vector3 = pts.call(s, -1.0, HOOD_THICK)
		var uc: Vector3 = pts.call(s, 0.0, HOOD_THICK)
		var ur: Vector3 = pts.call(s, 1.0, HOOD_THICK)
		if s == ss[0]:
			k.quad(ul, l, c, uc, HOOD_UNDER)
			k.quad(uc, c, r, ur, HOOD_UNDER)
		else:
			k.quad(l, ul, uc, c, HOOD_UNDER)
			k.quad(c, uc, ur, r, HOOD_UNDER)

func _tub(k: CockpitKit) -> void:
	var z0 := NOSE_Z + HOOD_S0 + 0.02    # radiator support
	var z1 := NOSE_Z + HOOD_S1 - 0.01    # firewall
	var zc := (z0 + z1) / 2.0
	var length := z1 - z0
	k.box(Vector3(1.54, 0.02, length), Vector3(0.0, 0.25, zc), TUB)              # floor
	k.box(Vector3(0.02, 0.44, length), Vector3(-0.77, 0.46, zc), TUB)            # inner fenders
	k.box(Vector3(0.02, 0.44, length), Vector3(0.77, 0.46, zc), TUB)
	k.box(Vector3(1.56, 0.52, 0.02), Vector3(0.0, 0.50, z1), TUB)                # firewall
	k.box(Vector3(1.56, 0.42, 0.02), Vector3(0.0, 0.45, z0), TUB)                # radiator support
	# seal lip round the opening, following the edge line
	var n := 8
	for i in n:
		var sa := lerpf(HOOD_S0, HOOD_S1, float(i) / n)
		var sb := lerpf(HOOD_S0, HOOD_S1, float(i + 1) / n)
		for side in [-1.0, 1.0]:
			var xo_a: float = side * (_curve(HALF_W, sa) - FENDER)
			var xo_b: float = side * (_curve(HALF_W, sb) - FENDER)
			var xi_a: float = xo_a - side * 0.07
			var xi_b: float = xo_b - side * 0.07
			var ya := _curve(BELT, sa) - 0.025
			var yb := _curve(BELT, sb) - 0.025
			var a := Vector3(xi_a, ya, NOSE_Z + sa)
			var b := Vector3(xo_a, ya, NOSE_Z + sa)
			var c := Vector3(xo_b, yb, NOSE_Z + sb)
			var d := Vector3(xi_b, yb, NOSE_Z + sb)
			if side > 0.0:
				k.quad(a, b, c, d, SEAL)
			else:
				k.quad(b, a, d, c, SEAL)
	k.box(Vector3(1.5, 0.03, 0.08), Vector3(0.0, _curve(BELT, HOOD_S0) - 0.03, z0 + 0.03), SEAL)   # front lip
	k.box(Vector3(1.5, 0.03, 0.06), Vector3(0.0, _curve(BELT, HOOD_S1) - 0.03, z1 - 0.03), SEAL)   # cowl lip
	# radiator against the support, fins dark
	k.box(Vector3(0.92, 0.40, 0.05), Vector3(0.0, 0.44, z0 + 0.05), FIN, Basis.IDENTITY, CAST)
	k.box(Vector3(0.92, 0.04, 0.06), Vector3(0.0, 0.66, z0 + 0.05), CAST)   # top tank
	k.box(Vector3(0.92, 0.04, 0.06), Vector3(0.0, 0.22, z0 + 0.05), CAST)   # bottom tank

const ENGINE_Z := -1.24

## Inline engine: sump, block, cam cover, plug cover, oil cap, front pulley.
func _engine(k: CockpitKit) -> void:
	k.box(Vector3(0.34, 0.12, 0.50), Vector3(0.0, 0.21, ENGINE_Z), CAST)
	k.box(Vector3(0.46, 0.32, 0.60), Vector3(0.0, 0.42, ENGINE_Z), CAST)
	k.box(Vector3(0.42, 0.08, 0.56), Vector3(0.0, 0.62, ENGINE_Z), ALLOY)
	k.box(Vector3(0.11, 0.02, 0.50), Vector3(0.0, 0.67, ENGINE_Z), DUSK)
	k.cylinder(0.035, 0.66, 0.70, Vector3(0.14, 0.0, ENGINE_Z + 0.20), DUSK, 8)
	var along_z := Basis(Vector3(1, 0, 0), PI / 2)
	k.cylinder(0.075, -0.03, 0.03, Vector3(0.0, 0.33, ENGINE_Z - 0.33), ALLOY, 10, along_z)
	k.cylinder(0.035, -0.02, 0.02, Vector3(0.0, 0.52, ENGINE_Z - 0.33), ALLOY, 8, along_z)   # cam pulley cover

## Intake on the right: plenum, four runners to the head, throttle body.
func _intake(k: CockpitKit) -> void:
	var along_z := Basis(Vector3(1, 0, 0), PI / 2)
	k.cylinder(0.065, -0.28, 0.28, Vector3(0.34, 0.56, ENGINE_Z), ALLOY, 10, along_z)
	for z in [-0.19, -0.065, 0.065, 0.19]:
		k.box(Vector3(0.14, 0.045, 0.045), Vector3(0.26, 0.56, ENGINE_Z + z), ALLOY)
	k.cylinder(0.045, -0.06, 0.06, Vector3(0.34, 0.56, ENGINE_Z - 0.34), CHROME, 8, along_z)
	k.box(Vector3(0.05, 0.02, 0.10), Vector3(0.34, 0.63, ENGINE_Z - 0.20), DUSK)   # fuel rail cap

## Turbo on the left: compressor housing (alloy), turbine housing (cast),
## centre cartridge, wastegate can, downpipe into the floor.
func _turbo(k: CockpitKit) -> void:
	var along_x := Basis(Vector3(0, 0, 1), PI / 2)
	var tz := ENGINE_Z - 0.04
	k.cylinder(0.09, -0.07, 0.07, Vector3(-0.56, 0.42, tz), ALLOY, 12, along_x)   # compressor
	k.cylinder(0.05, -0.05, 0.05, Vector3(-0.44, 0.42, tz), CAST, 8, along_x)     # cartridge
	k.cylinder(0.085, -0.06, 0.06, Vector3(-0.33, 0.42, tz), CAST, 10, along_x)   # turbine
	k.box(Vector3(0.08, 0.10, 0.12), Vector3(-0.56, 0.52, tz), ALLOY)              # compressor outlet
	k.cylinder(0.035, 0.0, 0.07, Vector3(-0.40, 0.50, tz + 0.10), CAST, 8)         # wastegate
	k.cylinder(0.05, -0.16, 0.0, Vector3(-0.33, 0.42, tz), CAST, 8)                # downpipe
	k.box(Vector3(0.12, 0.06, 0.30), Vector3(-0.30, 0.44, tz + 0.18), CAST)        # exhaust manifold

## Pipes and hoses: charge pipe compressor -> front -> throttle (alloy with
## rubber couplers), coolant hoses to the radiator tanks, battery cables.
func _hoses(k: CockpitKit) -> void:
	var rad_z := NOSE_Z + HOOD_S0 + 0.10
	_tube(k, Vector3(-0.56, 0.58, ENGINE_Z - 0.04), Vector3(-0.56, 0.58, ENGINE_Z - 0.46), 0.03, ALLOY)
	_tube(k, Vector3(-0.56, 0.58, ENGINE_Z - 0.46), Vector3(0.34, 0.58, ENGINE_Z - 0.46), 0.03, ALLOY)
	_tube(k, Vector3(0.34, 0.58, ENGINE_Z - 0.46), Vector3(0.34, 0.56, ENGINE_Z - 0.40), 0.036, RUBBER)
	_tube(k, Vector3(-0.56, 0.58, ENGINE_Z - 0.10), Vector3(-0.56, 0.58, ENGINE_Z - 0.02), 0.036, RUBBER)
	_tube(k, Vector3(0.22, 0.66, rad_z), Vector3(0.14, 0.64, ENGINE_Z - 0.30), 0.024, RUBBER)    # upper coolant
	_tube(k, Vector3(-0.22, 0.22, rad_z), Vector3(-0.18, 0.26, ENGINE_Z - 0.30), 0.024, RUBBER)  # lower coolant
	_tube(k, Vector3(0.46, 0.52, -0.96), Vector3(0.30, 0.50, -0.78), 0.012, RUBBER)             # battery +
	_tube(k, Vector3(0.64, 0.52, -0.96), Vector3(0.70, 0.40, -0.78), 0.012, RUBBER)             # battery - to body
	_tube(k, Vector3(0.0, 0.66, ENGINE_Z + 0.26), Vector3(0.0, 0.62, -0.78), 0.016, RUBBER)       # breather to firewall

## Battery on the right by the firewall: case, lid, two terminals, hold-down.
func _battery(k: CockpitKit) -> void:
	var c := Vector3(0.55, 0.405, -0.96)
	k.box(Vector3(0.26, 0.19, 0.17), c, DUSK, Basis.IDENTITY, NAVY)
	k.cylinder(0.02, 0.50, 0.535, Vector3(0.46, 0.0, -0.96), AMBER, 8)
	k.cylinder(0.02, 0.50, 0.535, Vector3(0.64, 0.0, -0.96), ALLOY, 8)
	k.box(Vector3(0.30, 0.012, 0.03), Vector3(0.55, 0.506, -0.96), SEAL)

## Radiator fan: shroud ring, five pitched blades, hub.
func _fan(k: CockpitKit) -> void:
	var fk := CockpitKit.new()
	fk.ring_sector(0.215, 0.25, 0.0, TAU, -0.015, 0.015, FIN, 20)
	var along_z := Basis(Vector3(1, 0, 0), PI / 2)
	fk.cylinder(0.045, -0.02, 0.035, Vector3.ZERO, BLADE, 8, along_z)
	for i in 5:
		var a := TAU * float(i) / 5.0
		var b := Basis(Vector3(0, 0, 1), a) * Basis(Vector3(1, 0, 0), 0.5)
		fk.box(Vector3(0.16, 0.04, 0.01), Vector3(cos(a), sin(a), 0.0) * 0.125, BLADE, b)
	fk.offset(Vector3(0.0, 0.44, NOSE_Z + HOOD_S0 + 0.11))
	k.merge(fk)

## A cylinder from a to b.
static func _tube(k: CockpitKit, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 1e-4:
		return
	var up := d / length
	var ref := Vector3(0, 0, 1) if absf(up.y) > 0.9 else Vector3(0, 1, 0)
	var x := ref.cross(up).normalized()
	var z := up.cross(x)
	k.cylinder(r, 0.0, length, a, col, 8, Basis(x, up, z))
