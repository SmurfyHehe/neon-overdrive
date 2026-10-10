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
	"p0_beater": {"strut_bar": {"x": 0.48, "y": 0.93, "z": -1.05}},
	"p1_coupe": {"strut_bar": {"x": 0.595, "y": 0.71, "z": -1.11}},
	"p2_hothatch": {"strut_bar": {"x": 0.62, "y": 0.85, "z": -1.13}},
	"p3_tuner": {"strut_bar": {"x": 0.59, "y": 0.79, "z": -1.16}},
	"p4_kei": {"strut_bar": {"x": 0.445, "y": 0.67, "z": -0.98}},
	"p5_muscle": {"strut_bar": {"x": 0.66, "y": 0.87, "z": -1.33}},
	"p6_crossover": {"strut_bar": {"x": 0.61, "y": 1.00, "z": -1.16}},
}

## A cabin spot for a car (CockpitFrame space). Unknown spot: Vector3.ZERO.
static func cabin(kind: String, spot: String) -> Vector3:
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
