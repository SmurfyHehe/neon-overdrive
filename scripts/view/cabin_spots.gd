class_name CabinSpots
extends RefCounted

# Fixed attach spots for interior mods, per player car (interior mods batch 1,
# 2026-10-09; research: interior-mods-research-2026-10-09.md section 6). Data
# only: where a part ties on, so every part reads one table instead of
# guessing from the cabin mesh. Two frames:
#
# - CABIN spots are in CockpitFrame space (the cabin node sits in each car at
#   PlayerCars.cabin_offset, so the same cabin numbers serve every car that
#   shares the P1 cabin today; a car with its own cabin overrides them here).
# - CAR spots are in car space (the chassis), for parts outside the cabin:
#   the strut bar between the front towers.
#
# Cabin spots (all Vector3):
#   mirror_hang  the knot under the rear-view mirror housing (hanging trinket)
#   shifter      the lever's boot on the console
#   handbrake    the handbrake's pivot
#   dash_pod     a gauge pod's foot on the dash top, driver's side of the
#                binnacle (for the AFR/PSI pod; it may move it)
#   vent_left / vent_right   the dash vents either side of the cluster
#   dash_pass    the bobble head's foot on the passenger-side dash top. Not in
#                the CABIN table: it is worked out from each car's own cabin
#                (dash_pass(), below) so it always sits on that car's dash.
# Car spots:
#   strut_bar    {x: half span between the tower tops, y, z}: the brace's
#                ends in car space. Towers from fleet.json: 0.17 m in from
#                the wheel face, 0.15 m behind the front axle, under the hood
#                skin (top curve at that point, less the hood skin and the
#                tower cap). The rear-engine beater braces its front trunk.

const DEFAULT_KIND := "p1_coupe"

const CABIN := {
	"mirror_hang": Vector3(-0.07, 1.182, -0.145),
	"shifter": Vector3(0.0, 0.615, -0.02),
	"handbrake": Vector3(0.0, 0.615, 0.44),
	"dash_pod": Vector3(-0.56, 0.955, -0.42),
	"vent_left": Vector3(-0.62, 0.90, -0.40),
	"vent_right": Vector3(-0.10, 0.90, -0.40),
}

## Per car: cabin overrides (none yet: one shared cabin) and the car spots.
const CARS := {
	"p0_beater": {"strut_bar": {"x": 0.48, "y": 0.93, "z": -1.05}, "bobble": {"along": 0.8, "scale": 0.65, "tilt": 0.2}},
	"p1_coupe": {"strut_bar": {"x": 0.595, "y": 0.71, "z": -1.11}},
	"p2_hothatch": {"strut_bar": {"x": 0.62, "y": 0.85, "z": -1.13}},
	"p3_tuner": {"strut_bar": {"x": 0.59, "y": 0.79, "z": -1.16}},
	# the kei's dash is a 6 cm ledge a hand's width under the screen: its
	# bobble head stands nearer the cowl and a size smaller (BobbleHead)
	"p4_kei": {"strut_bar": {"x": 0.445, "y": 0.67, "z": -0.98}, "bobble": {"along": 0.05, "scale": 0.45, "tilt": 0.15}},
	"p5_muscle": {"strut_bar": {"x": 0.66, "y": 0.87, "z": -1.33}},
	"p6_crossover": {"strut_bar": {"x": 0.61, "y": 1.00, "z": -1.16}},
	"p8_driftcoupe": {"strut_bar": {"x": 0.60, "y": 0.76, "z": -1.18}},
}

## A cabin spot for a car (CockpitFrame space). Unknown spot: Vector3.ZERO.
static func cabin(kind: String, spot: String) -> Vector3:
	if spot == "dash_pass":
		return dash_pass(kind)
	var car: Dictionary = CARS.get(kind, {})
	var over: Dictionary = car.get("cabin", {})
	if over.has(spot):
		return over[spot]
	return CABIN.get(spot, Vector3.ZERO)

## The strut bar's ends in car space: [left, right]. An unknown car gets the coupe's.
static func strut_bar(kind: String) -> Array[Vector3]:
	var car: Dictionary = CARS.get(kind, CARS[DEFAULT_KIND])
	var s: Dictionary = car.get("strut_bar", CARS[DEFAULT_KIND]["strut_bar"])
	var out: Array[Vector3] = [Vector3(-s.x, s.y, s.z), Vector3(s.x, s.y, s.z)]
	return out

static func has_car(kind: String) -> bool:
	return CARS.has(kind)

## Where the bobble head stands (CockpitFrame space; the foot of its base),
## worked out from the car's cabin so it sits on that car's dash top: this far
## along the dash (0 at the cowl, 1 at the driver's face), and on the line
## DASH_PASS_DEG right of straight ahead from the driver's eye, so it is never
## in front of the driver (the spec asks for more than 20) and well clear of
## the door mirror. A car with a very narrow dash keeps it inside the body.
const DASH_PASS_ALONG := 0.62
const DASH_PASS_DEG := 28.0

static func dash_pass(kind: String) -> Vector3:
	var cab := CabinSpec.for_kind(kind)
	var cowl: Vector2 = cab.cowl          # (y, z)
	var face_z := float(cab.dash_face_z)
	var cluster: Vector2 = cab.cluster    # (y, z): the dash top's height at the driver's face
	var eye: Vector3 = cab.eye
	var along := float(bobble_fit(kind).get("along", DASH_PASS_ALONG))
	var z := lerpf(cowl.y, face_z, along)
	var y := lerpf(cowl.x, cluster.x, along)   # the dash top is a straight slope cowl -> face
	var x := eye.x + tan(deg_to_rad(DASH_PASS_DEG)) * (eye.z - z)
	var door_x := float(cab.door_x)
	var pillar_foot: Vector3 = cab.a_pillar[0]
	var dash_half := minf(float(cab.get("door_x_front", door_x)) + 0.04, pillar_foot.x - 0.03)
	x = minf(x, minf(dash_half - 0.06, door_x - 0.25))
	return Vector3(x, y, z)

## Per-car bobble head fit overrides: {"along", "scale", "tilt"} (empty for most cars).
static func bobble_fit(kind: String) -> Dictionary:
	var car: Dictionary = CARS.get(kind, {})
	return car.get("bobble", {})

## The figure's scale on that car's dash (1.0 unless the dash is tight).
static func dash_pass_scale(kind: String) -> float:
	return float(bobble_fit(kind).get("scale", 1.0))
