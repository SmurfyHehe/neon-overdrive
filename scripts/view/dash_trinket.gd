extends Node3D
class_name DashTrinket

# A small charm hanging from the rear-view mirror stalk (2026-10-09, Roy:
# "a dangling dash trinket that swings with cornering", customisable). A child
# of the CockpitFrame, in car space, visual only: it never touches the car's
# physics.
#
# Motion: a damped pendulum in the car's own frame. The bob's rest direction is
# the apparent gravity (world gravity in car space minus the car's
# acceleration), so cornering swings it outward, braking throws it forward,
# launching pins it back, and a lean or a slope tilts it with the car. The
# acceleration comes from the player's velocity change per physics tick
# (rotated into the car's frame) through a short low-pass, because wheel
# contact makes it noisy. Two angles: PHI side to side (+ toward the car's +x),
# PSI fore and aft (+ toward the rear, +z).
#
# Designs are original, built from CockpitKit boxes, cylinders and triangles
# (flat shaded, vertex colours, ROADMAP palette): no imported assets. The pick
# is CabinMods.trinket (pause menu now, the garage later); this node polls it
# and rebuilds when it changes. "none" shows nothing. Re-applied on the
# scripts/view layout (interior mods batch 1); the knot is CabinSpots
# "mirror_hang".

const NONE := "none"
## Pick order in the pause menu: index 0 is "none".
const IDS: Array[String] = [NONE, "dice", "tree", "wrench", "medal", "crystal"]
const NAMES := {
	NONE: "None", "dice": "Dice", "tree": "Pine tree", "wrench": "Wrench",
	"medal": "Medal", "crystal": "Amber drop",
}
const DEFAULT_ID := "dice"

## Where the cord ties on (CabinSpots "mirror_hang" for the coupe): under the
## rear-view mirror housing, a little toward the driver so the charm is not
## dead centre in the road view.
const ATTACH := Vector3(-0.07, 1.182, -0.145)
## Cord length from the stalk to the top of the charm (m).
const CORD := 0.065

const GRAVITY := 9.81
## Pendulum length used for the swing rate (the cord plus half the charm).
const PENDULUM_L := 0.09
## Damping (1/s) on the angle rates: ~2 s to settle after a corner.
const DAMPING := 3.2
## Low-pass time constant on the car's acceleration (s).
const ACCEL_TAU := 0.04
## Largest acceleration taken from the car (m/s^2): a wall hit is not a sling.
const ACCEL_CAP := 30.0
## Swing limit (rad): the charm hits the windscreen, the mirror and the dash.
const SWING_MAX := 0.9

const CORD_COL := Color("#1A1D24")
const SILVER := Color("#C9CED6")
const BONE := Color("#E9E6DF")
const INK := Color("#15171C")
const SODIUM := Color("#FF8A1F")
const AMBER := Color("#FFC066")
const NAVY := Color("#26314D")
const PINE := Color("#2B4A3A")

var player: Node3D            # the PlayerCar (a RigidBody3D / VehicleBody)
var design := ""              # the id currently built
var phi := 0.0                # side-to-side swing, rad
var psi := 0.0                # fore-aft swing, rad
var phi_rate := 0.0
var psi_rate := 0.0
var accel_local := Vector3.ZERO   # filtered car acceleration, car space

var _pivot: Node3D
var _mesh: MeshInstance3D
var _last_vel := Vector3.ZERO
var _have_vel := false
var _tris := 0

func _init(car: Node3D = null, kind: String = "") -> void:
	player = car
	name = "Trinket"
	position = CabinSpots.cabin(kind, "mirror_hang") if kind != "" else ATTACH
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)

func _ready() -> void:
	set_design(CabinMods.trinket)

## Triangles drawn by the current design (0 for none).
func triangle_count() -> int:
	return _tris

## True while a charm is shown.
func is_shown() -> bool:
	return _mesh != null

## Index in IDS of the id (0, "none", if unknown).
static func index_of(id: String) -> int:
	var i := IDS.find(id)
	return maxi(i, 0)

## Builds the design (an unknown id counts as "none"). Cheap; called when the
## setting changes, not per frame.
func set_design(id: String) -> void:
	if not IDS.has(id):
		id = NONE
	design = id
	if _mesh != null:
		_pivot.remove_child(_mesh)
		_mesh.free()
		_mesh = null
	_tris = 0
	if id == NONE:
		return
	var k := CockpitKit.new()
	var cord_h := CORD
	# cord from the stalk down to the top of the charm (the pivot is the knot)
	k.box(Vector3(0.0035, cord_h, 0.0035), Vector3(0.0, -cord_h * 0.5, 0.0), CORD_COL)
	var charm := CockpitKit.new()
	call("_build_" + id, charm)
	charm.offset(Vector3(0.0, -cord_h, 0.0))
	k.merge(charm)
	_tris = k.tri_count()
	var mat := CockpitKit.material(0.55, 0.15, 0.3)
	_mesh = k.instance(mat, "Charm")
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.layers = CockpitFrame.INTERIOR_BIT
	_pivot.add_child(_mesh)
	_apply_pose()

# ---------- designs: each builds hanging DOWN from y = 0 (the cord's end) ----------

## Fuzzy dice: two cubes on a Y of cord, a dark pip on each outward face.
func _build_dice(k: CockpitKit) -> void:
	for side in [-1.0, 1.0]:
		var cx: float = side * 0.019
		var cy := -0.045
		k.box(Vector3(0.0025, 0.026, 0.0025), Vector3(cx * 0.5, -0.013, 0.0), CORD_COL,
			Basis(Vector3.BACK, side * deg_to_rad(-14.0)))
		var turn := Basis(Vector3.UP, deg_to_rad(side * 22.0)) * Basis(Vector3.RIGHT, deg_to_rad(12.0))
		k.box(Vector3(0.030, 0.030, 0.030), Vector3(cx, cy, 0.0), BONE, turn)
		for face in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0)]:
			var pip_size := Vector3(0.006, 0.006, 0.006)
			k.box(pip_size, Vector3(cx, cy, 0.0) + turn * (face * 0.0155), INK, turn)

## Pine-tree air freshener: three flat tiers, a stub, in dark green with a sodium cap.
func _build_tree(k: CockpitKit) -> void:
	var thick := 0.004
	k.box(Vector3(0.012, 0.012, thick), Vector3(0.0, -0.006, 0.0), SODIUM)   # hanging tab
	var tiers := [[0.030, 0.020, -0.022], [0.042, 0.020, -0.040], [0.054, 0.022, -0.060]]
	for t in tiers:
		var w: float = t[0]
		var h: float = t[1]
		var y: float = t[2]
		# a trapezoid slab: narrow top, wide bottom (built as a wedge-like prism)
		var top := w * 0.4
		var yt := y + h * 0.5
		var yb := y - h * 0.5
		var f := thick * 0.5
		k.quad(Vector3(-w * 0.5, yb, f), Vector3(w * 0.5, yb, f), Vector3(top * 0.5, yt, f), Vector3(-top * 0.5, yt, f), PINE)
		k.quad(Vector3(w * 0.5, yb, -f), Vector3(-w * 0.5, yb, -f), Vector3(-top * 0.5, yt, -f), Vector3(top * 0.5, yt, -f), PINE)
		k.quad(Vector3(-w * 0.5, yb, -f), Vector3(w * 0.5, yb, -f), Vector3(w * 0.5, yb, f), Vector3(-w * 0.5, yb, f), PINE)
		k.quad(Vector3(w * 0.5, yb, f), Vector3(w * 0.5, yb, -f), Vector3(top * 0.5, yt, -f), Vector3(top * 0.5, yt, f), PINE)
		k.quad(Vector3(-w * 0.5, yb, -f), Vector3(-w * 0.5, yb, f), Vector3(-top * 0.5, yt, f), Vector3(-top * 0.5, yt, -f), PINE)
	k.box(Vector3(0.010, 0.014, thick), Vector3(0.0, -0.077, 0.0), CORD_COL)   # trunk

## A little silver spanner (the shop): a shaft and an open jaw.
func _build_wrench(k: CockpitKit) -> void:
	var tilt := Basis(Vector3.BACK, deg_to_rad(18.0))
	k.box(Vector3(0.012, 0.012, 0.004), Vector3(0.0, -0.006, 0.0), SILVER)   # eyelet block
	k.box(Vector3(0.009, 0.05, 0.005), tilt * Vector3(0.0, -0.036, 0.0), SILVER, tilt)
	# open jaw: two prongs and a back bar at the bottom of the shaft
	var jaw := tilt * Vector3(0.0, -0.068, 0.0)
	k.box(Vector3(0.026, 0.008, 0.005), jaw, SILVER, tilt)
	k.box(Vector3(0.008, 0.016, 0.005), jaw + tilt * Vector3(-0.0090, -0.011, 0.0), SILVER, tilt)
	k.box(Vector3(0.008, 0.016, 0.005), jaw + tilt * Vector3(0.0090, -0.011, 0.0), SILVER, tilt)

## A round medallion: silver disc, sodium centre stamp, facing forward.
func _build_medal(k: CockpitKit) -> void:
	var face := Basis(Vector3.RIGHT, deg_to_rad(90.0))   # cylinder axis +y -> +z
	k.box(Vector3(0.008, 0.01, 0.004), Vector3(0.0, -0.005, 0.0), SILVER)
	var c := Vector3(0.0, -0.032, 0.0)
	k.cylinder(0.022, -0.0025, 0.0025, c, SILVER, 14, face)
	k.cylinder(0.014, 0.0025, 0.0036, c, SODIUM, 14, face)
	k.cylinder(0.006, 0.0036, 0.0046, c, NAVY, 10, face)

## A faceted amber drop: a bipyramid, long below, with a silver cap.
func _build_crystal(k: CockpitKit) -> void:
	k.box(Vector3(0.012, 0.008, 0.012), Vector3(0.0, -0.004, 0.0), SILVER)
	var top := Vector3(0.0, -0.010, 0.0)
	var mid_y := -0.030
	var bot := Vector3(0.0, -0.066, 0.0)
	var r := 0.0155
	var n := 6
	var ring := []
	for i in n:
		var a := TAU * float(i) / n
		ring.append(Vector3(cos(a) * r, mid_y, sin(a) * r))
	for i in n:
		var j := (i + 1) % n
		var shade := AMBER if i % 2 == 0 else SODIUM
		k.tri(top, ring[j], ring[i], shade)   # upper facets, counter-clockwise from outside
		k.tri(bot, ring[i], ring[j], shade)

# ---------- motion ----------

func _physics_process(delta: float) -> void:
	if CabinMods.trinket != design:
		set_design(CabinMods.trinket)
	if player == null or delta <= 0.0:
		return
	var v := _velocity_of(player)
	if not _have_vel:
		_last_vel = v
		_have_vel = true
	var basis_inv := (player.global_transform.basis).orthonormalized().inverse()
	var a_world := (v - _last_vel) / delta
	_last_vel = v
	var a := basis_inv * a_world
	a = a.limit_length(ACCEL_CAP)
	accel_local = accel_local.lerp(a, 1.0 - exp(-delta / ACCEL_TAU))
	step(delta, accel_local, basis_inv * Vector3(0.0, -GRAVITY, 0.0))

## One pendulum step. `accel` is the car's acceleration and `gravity` world
## gravity, both in car space; the bob rests along gravity - accel. Public so a
## test can drive it without a car.
func step(delta: float, accel: Vector3, gravity: Vector3) -> void:
	var g_eff := gravity - accel
	var gl := maxf(g_eff.length(), 1.0)
	var t := g_eff / gl
	# target angles of the rest direction from straight down
	var down := maxf(-t.y, 0.05)
	var phi_t := atan2(t.x, down)
	var psi_t := atan2(t.z, down)   # +psi swings toward +z (the rear)
	var w2 := gl / PENDULUM_L
	# semi-implicit Euler on a linearised spring toward the target, plus damping
	phi_rate += (-w2 * (phi - phi_t) - DAMPING * phi_rate) * delta
	psi_rate += (-w2 * (psi - psi_t) - DAMPING * psi_rate) * delta
	phi = clampf(phi + phi_rate * delta, -SWING_MAX, SWING_MAX)
	psi = clampf(psi + psi_rate * delta, -SWING_MAX, SWING_MAX)
	if absf(phi) >= SWING_MAX:
		phi_rate = 0.0
	if absf(psi) >= SWING_MAX:
		psi_rate = 0.0
	_apply_pose()

func _apply_pose() -> void:
	if _pivot != null:
		# +phi swings toward +x (rotation about +z); +psi toward +z (about -x)
		_pivot.rotation = Vector3(-psi, 0.0, phi)

static func _velocity_of(body: Node3D) -> Vector3:
	var v: Variant = body.get("linear_velocity")
	return v if v is Vector3 else Vector3.ZERO
