class_name InteriorStyle
extends RefCounted

# Per-car interior look (interiors pass, 2026-10-08). Roy: every car has its
# OWN interior and its OWN instrument cluster, matched to its era (an old car
# gets an aftermarket head unit and analog dials, a modern one factory
# screens), and the cluster reads that car's own numbers (ClusterFace.scales_for).
#
# CockpitFrame builds the cabin from one of these: the colour story (three
# value steps per cabin: dark floor and lower dash, mid dash and doors, light
# headliner and seat inserts, plus one accent), which surface each part is
# (CockpitKit.SURFACES: hard, soft, cloth, leather, metal, rubber), the
# steering wheel, the cluster layout and look, the head unit and the lights.
# No pure black anywhere: the darkest value stays navy-grey so it reads as a
# surface, not a hole (cockpit-interior-research-2026-10-06.md, section 4).
#
# Ids follow the fleet sheet (docs/design/fleet/fleet.json). NEON_INTERIOR
# overrides the player's own style, for screenshots of a car that has no
# drivable body yet.

const DEFAULT := "p1_coupe"

## P1 coupe: early-90s fastback (Supra A80 / S13 / FD era), a driver's car
## that was looked after. Grey hard plastic with a soft charcoal dash top,
## cloth buckets with silver piping and a thin sodium stripe that ties the
## cabin to the Sodium paint, aluminium pedals, a period aftermarket 3-spoke
## leather wheel, a hooded analog cluster (big centre tach) with amber
## backlight, an aftermarket single-DIN head unit, and a boost gauge pod on
## the driver's A-pillar that only appears once the car has a turbo.
const P1_COUPE := {
	"id": "p1_coupe",
	"label": "Sports coupe, early 90s",
	"colors": {
		"floor": Color("#16191F"),        # dark: carpet, footwell
		"lower": Color("#1F232A"),        # dark: lower dash, knee panel, console sides
		"dash": Color("#2C3038"),         # mid: dash face, centre stack, binnacle
		"dash_top": Color("#262A31"),     # mid-dark soft pad (glare-free, a touch darker than the face)
		"door": Color("#2E323A"),         # mid: door cards
		"door_insert": Color("#3E434C"),  # mid-light cloth insert
		"seat": Color("#2A2E35"),         # mid: seat bolsters
		"seat_insert": Color("#4F545E"),  # light: seat centre cloth
		"piping": Color("#A6ACB5"),       # silver piping on the seats
		"headliner": Color("#464A53"),    # light: roof lining, visors
		"pillar": Color("#383C44"),       # A- and B-pillar cloth, a step under the lining
		"trim": Color("#3A3F48"),         # bezels, vents, door pulls
		"silver": Color("#A9AFB8"),       # bezel rings, gate plate, pedals
		"accent": Color("#FF8A1F"),       # Sodium, the paint: seat stripe, stitch
		"rubber": Color("#15171C"),
		"boot": Color("#1C1E24"),         # shift / handbrake boots (leather)
	},
	"wheel": {
		"kind": "round",
		"radius": 0.175,       # rim centreline: a 35 cm aftermarket wheel
		"grip_r": 0.019,
		"dish": 0.02,         # rim sits this far toward the driver from the hub
		"spokes": [0.0, 180.0, 270.0],
		"spoke_w": 0.040,
		"rim": Color("#1A1C22"),
		"stitch": Color("#A9561A"),     # sodium thread, darkened: a seam, not a ring
		"spoke": Color("#9EA4AD"),      # brushed silver, drilled look from two tones
		"spoke_alt": Color("#6E747D"),
		"pad": Color("#1E2128"),
		"pad_r": 0.052,
		"badge": Color("#FF8A1F"),
		"leds": false,
		"lcd": false,
		"paddles": false,
	},
	"cluster": {
		"plate": Vector2(0.34, 0.13),
		"y": 0.845,            # plate centre: through the wheel's upper opening
		"look": {
			"plate": Color("#141821"),
			"face": Color("#0F131B"),
			"ink": Color("#FFD9A0"),     # cream-amber numerals under amber backlight
			"ring": Color("#8E949C"),
			"ring_dark": Color("#20242B"),
			"red": Color("#E5262B"),
		},
		"needle": Color("#FF8A1F"),
		"gauges": [
			{"id": "tach", "kind": "tach", "at": Vector2(0.0, -0.002), "r": 0.058, "sweep": 270.0},
			{"id": "speedo", "kind": "speedo", "at": Vector2(0.113, -0.010), "r": 0.045, "sweep": 270.0},
			{"id": "water", "kind": "water", "at": Vector2(-0.114, 0.022), "r": 0.024, "sweep": 100.0, "start": 140.0},
			{"id": "fuel", "kind": "fuel", "at": Vector2(-0.114, -0.034), "r": 0.024, "sweep": 100.0, "start": 140.0},
		],
		# The shift lights moved off the wheel into a bar along the top of the
		# cluster (an aftermarket shift light, period-right for this car).
		"shift_bar": true,
		"hood": "arched",
	},
	"pod": {"kind": "boost", "r": 0.030, "needs_boost": true},
	"head_unit": {"kind": "din1", "face": Color("#121519"), "text": Color("#FFC066")},
	"spill": 0.9,       # amber gauge backlight on the wheel and hands
	"cabin_light": 0.55,
}

const STYLES := {
	"p1_coupe": P1_COUPE,
}

static func ids() -> Array:
	return STYLES.keys()

## The style for a car id (PlayerCar.chassis_kind()), or NEON_INTERIOR if set.
static func for_car(id: String) -> Dictionary:
	var forced := OS.get_environment("NEON_INTERIOR")
	if forced != "" and STYLES.has(forced):
		return STYLES[forced]
	return STYLES.get(id, STYLES[DEFAULT])
