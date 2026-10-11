extends RefCounted

# Steering wheel picks (W1, 2026-10-11): the shape, the grip material and the
# stitching, each saved per car (CabinMods wheel_<kind>, wheel_grip_<kind>,
# wheel_stitch_<kind>). The race wheel with the LED strip and the screen is the
# default on every car; every shape and grip is offered on every car (Roy
# 2026-10-11, no era limits). Preload this file, it has no class_name:
#   const WheelStyles := preload("res://scripts/view/wheel_styles.gd")
#
# A shape names a size class, not a size: the diameter comes from the car's
# fit row (FIT), so the same shape is a different size in a kei and a muscle
# car. The race wheel stays 35 cm everywhere (Roy 2026-10-11).

const RACE := "race"
const DEFAULT_GRIP := "black_leather"
const DEFAULT_STITCH := "red"
const FALLBACK_KIND := "p1_coupe"

const SMALL := "small"
const MEDIUM := "medium"
const LARGE := "large"

## id -> shape. Order is the pick order in Settings. `dish` is the shape's own
## (metres, hub behind the rim plane); the car's FIT can cap it. `spoke_col`
## is the spoke colour for shapes whose spokes are not the dark plastic.
const SHAPE_IDS: Array[String] = ["race", "suede3", "deepdish", "wood", "banjo4", "qr2", "rally4", "sport3", "big2"]
const SHAPES := {
	"race": {"name": "Race wheel", "size": "", "spokes": [0.0, 180.0, 270.0], "spoke_kind": "flat", "dish": 0.0,
		"flat_y": -0.70, "screen": true, "horn_ring": false, "pad": "race"},
	"suede3": {"name": "Small suede three-spoke", "size": SMALL, "spokes": [0.0, 180.0, 270.0], "spoke_kind": "flat", "dish": 0.01,
		"flat_y": -1.0, "screen": false, "horn_ring": false, "pad": "plain"},
	"deepdish": {"name": "Deep dish", "size": MEDIUM, "spokes": [0.0, 180.0, 270.0], "spoke_kind": "round", "dish": 0.07,
		"flat_y": -1.0, "screen": false, "horn_ring": false, "pad": "button"},
	"wood": {"name": "Wood rim", "size": LARGE, "spokes": [0.0, 180.0, 270.0], "spoke_kind": "drilled", "dish": 0.02,
		"flat_y": -1.0, "screen": false, "horn_ring": false, "pad": "button", "spoke_col": Color("#C9CED6")},
	"banjo4": {"name": "Banjo four-spoke", "size": LARGE, "spokes": [30.0, 150.0, 210.0, 330.0], "spoke_kind": "thin", "dish": 0.01,
		"flat_y": -1.0, "screen": false, "horn_ring": true, "pad": "button", "spoke_col": Color("#C9CED6")},
	"qr2": {"name": "Quick-release two-spoke", "size": SMALL, "spokes": [0.0, 180.0], "spoke_kind": "flat", "dish": 0.02,
		"flat_y": -1.0, "screen": false, "horn_ring": false, "pad": "plain"},
	"rally4": {"name": "Rally four-spoke", "size": MEDIUM, "spokes": [20.0, 160.0, 250.0, 290.0], "spoke_kind": "flat", "dish": 0.03,
		"flat_y": -1.0, "screen": false, "horn_ring": false, "pad": "plain", "stripe": Color("#FFC066")},
	"sport3": {"name": "Leather sport three-spoke", "size": MEDIUM, "spokes": [0.0, 180.0, 270.0], "spoke_kind": "flat", "dish": 0.01,
		"flat_y": -1.0, "screen": false, "horn_ring": false, "pad": "plain"},
	"big2": {"name": "Big two-spoke", "size": LARGE, "spokes": [0.0, 180.0], "spoke_kind": "thin", "dish": 0.0,
		"flat_y": -1.0, "screen": false, "horn_ring": true, "pad": "button", "spoke_col": Color("#C9CED6")},
}

const GRIP_IDS: Array[String] = ["black_leather", "tan_leather", "grey_leather", "black_suede", "grey_suede", "wood", "ivory", "urethane"]
const GRIPS := {
	"black_leather": {"name": "Black leather", "col": Color("#141418"), "rough": 0.6},
	"tan_leather": {"name": "Tan leather", "col": Color("#8A5A3A"), "rough": 0.6},
	"grey_leather": {"name": "Grey leather", "col": Color("#3A3E46"), "rough": 0.6},
	"black_suede": {"name": "Black suede", "col": Color("#16181C"), "rough": 0.95},
	"grey_suede": {"name": "Grey suede", "col": Color("#4A4E56"), "rough": 0.95},
	"wood": {"name": "Wood", "col": Color("#6B3E1E"), "rough": 0.35},
	"ivory": {"name": "Ivory", "col": Color("#D9D2BC"), "rough": 0.45},
	"urethane": {"name": "Urethane", "col": Color("#22252B"), "rough": 0.8},
}

## "none" has no colour: the seam takes the rim's own.
const STITCH_IDS: Array[String] = ["none", "amber", "sodium", "silver", "red", "navy"]
const STITCHES := {
	"none": {"name": "None"},
	"amber": {"name": "Amber", "col": Color("#FFC066")},
	"sodium": {"name": "Sodium orange", "col": Color("#FF8A1F")},
	"silver": {"name": "Silver", "col": Color("#C9CED6")},
	"red": {"name": "Red", "col": Color("#E5262B")},
	"navy": {"name": "Navy", "col": Color("#1B2A4A")},
}

## Per-car fit, diameters and dish in centimetres: factory = the wheel the car
## was designed around, lo..hi = the sizes that clear its dash and knees,
## dish = the most the hub may sit behind the rim plane. Lives here, not in the
## p*_data.gd files (the car rebuild sessions own those). A kind missing here
## uses the coupe's row. tests/view/cabin_clearance.gd prints what really
## passes; numbers here are capped to that. The first design values (lo..hi,
## dish) were 33-37 / 34-39 / 31-34 / 35-40 cm; the 15 degree sight line
## (CockpitFrame.WHEEL_TOP_MIN_DEG) caps every car's rim at 36 cm. With the
## cabins as merged for build 4 (2026-10-11) a 36 cm rim comes 1.9 cm
## from the coupe's, the wagon's and the pickup's shins (2.0 needed), and covers
## 38-40% of the hot hatch's tach (30% allowed): those rows stop at 35 cm.
const FIT := {
	"p0_beater": {"factory": 39.0, "lo": 34.0, "hi": 36.0, "dish": 4.0},
	"p1_coupe": {"factory": 36.0, "lo": 33.0, "hi": 35.0, "dish": 4.0},
	"p2_hothatch": {"factory": 36.0, "lo": 33.0, "hi": 35.0, "dish": 4.0},
	"p3_tuner": {"factory": 36.0, "lo": 33.0, "hi": 36.0, "dish": 4.0},
	"p4_kei": {"factory": 33.0, "lo": 31.0, "hi": 33.0, "dish": 4.0},
	"p5_muscle": {"factory": 40.0, "lo": 35.0, "hi": 36.0, "dish": 4.0},
	"p6_crossover": {"factory": 37.0, "lo": 34.0, "hi": 36.0, "dish": 4.0},
	"p17_work_pickup": {"factory": 39.0, "lo": 35.0, "hi": 35.0, "dish": 4.0},
	# its CABIN wheel_fit (35 factory, 33-36, 8 cm dish), the top capped to 35
	"p8_driftcoupe": {"factory": 35.0, "lo": 33.0, "hi": 35.0, "dish": 8.0},
	# its CABIN wheel_fit (39 factory, 35-40, 5 cm dish), capped to what
	# cabin_clearance passes: 38 cm, a 4 cm dish
	"p10_truck": {"factory": 39.0, "lo": 35.0, "hi": 38.0, "dish": 4.0},
}

## The race wheel's diameter, the same on every car (cm).
const RACE_DIAMETER_CM := 35.0

static func shape_names() -> Array:
	var out := []
	for id in SHAPE_IDS:
		out.append(String(SHAPES[id].name))
	return out

static func grip_names() -> Array:
	var out := []
	for id in GRIP_IDS:
		out.append(String(GRIPS[id].name))
	return out

static func stitch_names() -> Array:
	var out := []
	for id in STITCH_IDS:
		out.append(String(STITCHES[id].name))
	return out

## True when the car's cabin is the worn one (the beater): its rim is ivory
## and its stitching grey until a pick says otherwise.
static func is_worn(kind: String) -> bool:
	return String(CabinSpec.for_kind(kind).get("trim", "stock")) == "worn"

## The id the Settings row shows while nothing is stored for the car.
static func default_grip(kind: String) -> String:
	return "ivory" if is_worn(kind) else DEFAULT_GRIP

## The Bug's own stitching is a grey the table does not have; silver is nearest.
static func default_stitch(kind: String) -> String:
	return "silver" if is_worn(kind) else DEFAULT_STITCH

static func fit_for(kind: String) -> Dictionary:
	return FIT.get(kind, FIT[FALLBACK_KIND])

## Diameter in cm for a shape on a car (the race wheel is 35 everywhere).
static func diameter_cm(kind: String, shape: String) -> float:
	var sh: Dictionary = SHAPES.get(shape, SHAPES[RACE])
	if shape == RACE or String(sh.size) == "":
		return RACE_DIAMETER_CM
	var fit := fit_for(kind)
	var d := float(fit.factory) - 1.0
	match String(sh.size):
		SMALL:
			d = float(fit.lo)
		LARGE:
			d = float(fit.hi)
	return clampf(d, float(fit.lo), float(fit.hi))

## Rim tube radius (m) for a wheel of this diameter: fat on small wheels, thin
## on big ones, 0.019 m at 31 cm down to 0.012 m at 41 cm.
static func tube_radius(diameter_cm_: float) -> float:
	return remap(clampf(diameter_cm_, 31.0, 41.0), 31.0, 41.0, 0.019, 0.012)

## The SteeringWheel.style dictionary for a shape on a car. `radius_m` and
## `dish_m` (>= 0) override the table; the clearance test searches with them.
static func style_for(kind: String, shape: String, radius_m := -1.0, dish_m := -1.0) -> Dictionary:
	if not SHAPES.has(shape):
		shape = RACE
	var sh: Dictionary = SHAPES[shape]
	var st := {
		"spokes": (sh.spokes as Array).duplicate(), "spoke_kind": sh.spoke_kind, "flat_y": float(sh.flat_y),
		"screen": bool(sh.screen), "horn_ring": bool(sh.horn_ring), "pad": sh.pad,
		"stripe": sh.get("stripe", Color(0, 0, 0, 0)),
	}
	if shape == RACE:
		st["radius"] = SteeringWheel.RADIUS
		st["grip_r"] = SteeringWheel.GRIP_R
		st["thin_r"] = SteeringWheel.CARBON_R
		st["dish"] = 0.0
		return st
	var r := diameter_cm(kind, shape) * 0.005 if radius_m < 0.0 else radius_m
	var tube := tube_radius(r * 200.0)
	st["radius"] = r
	st["grip_r"] = tube
	st["thin_r"] = tube * (SteeringWheel.CARBON_R / SteeringWheel.GRIP_R)
	st["dish"] = minf(float(sh.dish), float(fit_for(kind).dish) * 0.01) if dish_m < 0.0 else dish_m
	return st

## Sets the wheel's style and colours for a car and a set of picks
## ({shape, grip, stitch}; "" or a missing key = not picked). Call before the
## wheel is added, or before rebuild(). It starts from the stock colours every
## time, so a pick that is cleared goes back to the stock look.
static func apply(w: SteeringWheel, kind: String, picks: Dictionary) -> void:
	var worn := is_worn(kind)
	w.rim_colour = SteeringWheel.LEATHER
	w.seam_colour = SteeringWheel.STITCH
	w.spoke_colour = SteeringWheel.SPOKE
	w.carbon_colour = SteeringWheel.CARBON
	w.carbon_alt_colour = SteeringWheel.CARBON_ALT
	w.rim_roughness = SteeringWheel.DEFAULT_ROUGHNESS
	if worn:
		# the beater: a thin ivory rim, grey seam, painted spokes to match the dash
		w.rim_colour = Color("#D9D2BC")
		w.seam_colour = Color("#9A947F")
		w.spoke_colour = Color("#6B7668")
		w.carbon_colour = Color("#7E8A7B")
		w.carbon_alt_colour = Color("#6B7668")
	var shape := String(picks.get("shape", ""))
	if not SHAPES.has(shape):
		shape = RACE
	var grip := String(picks.get("grip", ""))
	if GRIPS.has(grip):
		w.rim_colour = GRIPS[grip].col
		w.rim_roughness = float(GRIPS[grip].rough)
	var stitch := String(picks.get("stitch", ""))
	if STITCHES.has(stitch):
		w.seam_colour = STITCHES[stitch].col if stitch != "none" else w.rim_colour
	elif GRIPS.has(grip) and worn:
		w.seam_colour = (w.rim_colour as Color).darkened(0.25)
	if shape != RACE and (SHAPES[shape] as Dictionary).has("spoke_col"):
		w.spoke_colour = SHAPES[shape].spoke_col
	w.style = style_for(kind, shape)
