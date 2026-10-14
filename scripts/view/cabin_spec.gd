class_name CabinSpec
extends RefCounted

# Each player car's own cabin (interior pass, 2026-10-09; Roy: "every car must
# have its own individual interior", the beater's was the coupe's and stuck
# out of the body). The numbers live in the car's data file as `CABIN`
# (scripts/car/p*_data.gd, one file per car), measured from that body by
# tools/fleet_design/cabin_measure.gd and hand-tuned there. CockpitFrame, the
# DriverModel, the CockpitMirrors and the cockpit camera all read the car's
# dictionary through here, so nothing of the coupe's cabin is shared.
#
# Keys (car space, the car at rest, lift included; -z forward, -x the
# driver's side):
#   seat_x, seat_h, seat_z   driver's seat: centre x, cushion top y, cushion centre z
#   eye                      the cockpit camera's eye
#   floor_y, belt_y          carpet top; the bottom of the side glass
#   cowl (y, z)              the dash lip under the windshield base
#   dash_face_z              the dash's face toward the driver
#   header (y, z), roof_y    the windshield top; the roof liner
#   open_top                 no roof: no liner, header bar only, no shelf
#   door_x, door_x_rear      door card face |x| by the seat and behind it
#   glass_x                  the door window pane |x|
#   a_pillar [foot, top]     right-hand side; mirrored for the left
#   b_pillar_z, rear_z       the B-pillar; the rear bulkhead
#   shelf {y, z0, z1, half_w} the parcel shelf, {} for none
#   wheel, wheel_tilt_deg    the steering wheel's hub
#   cluster (y, z), cluster_style, speedo_max_kmh
#   gear_window (optional, bool)  a seven-segment gear digit in the tach face
#   head_unit, lever, handbrake, pedals (throttle pivot; brake and clutch step left)
#   crank, switch            the window controls
#   rear_mirror, door_mirror (right side; mirrored)
#   console, seats           "tunnel" | "flat"; "bucket" | "bench" | "flat"
#
# Optional keys (hood view, 2026-10-11; computed here when a car has none):
#   hood_cam      Vector3   the hood camera, on the bonnet ahead of the windscreen
#   roof_back_cam Vector3   the roof camera that looks straight back (B in hood view)

## The arcade eye (#737, Roy 1550): the cockpit camera sits this far from the
## car's CABIN eye, up and toward the windscreen, so the dash and wheel drop to
## the bottom of the screen and the road fills it (coupe: road 14% -> 30% of
## the screen). A car's CABIN may set its own `arcade_eye` offset (the kei:
## 5 cm inboard too, its cabin is 20 cm narrower). The point is kept at least
## ARCADE_EYE_GLASS_GAP behind the windscreen at its height and under the roof.
const ARCADE_EYE_DEFAULT := Vector3(0.0, 0.08, -0.30)
const ARCADE_EYE_GLASS_GAP := 0.15
const ARCADE_EYE_ROOF_GAP := 0.10

## Where the cockpit camera sits in this car (car space).
static func arcade_eye(cab: Dictionary) -> Vector3:
	var off: Vector3 = cab.get("arcade_eye", ARCADE_EYE_DEFAULT)
	var e: Vector3 = (cab.eye as Vector3) + off
	e.y = minf(e.y, float(cab.roof_y) - ARCADE_EYE_ROOF_GAP)
	var cowl: Vector2 = cab.cowl
	var header: Vector2 = cab.header
	# the windscreen's z at the eye's height, between the cowl and the header
	var t := clampf((e.y - cowl.x) / maxf(header.x - cowl.x, 0.01), 0.0, 1.0)
	var glass_z := lerpf(cowl.y, header.y, t)
	e.z = maxf(e.z, glass_z + ARCADE_EYE_GLASS_GAP)
	return e

## Defaults for the hood camera: above and ahead of the cowl. These are the
## coupe's hand-placed offsets (#731): at 0.18 / 0.35 the wagon and the other
## cars without their own point saw the road only from 5 to 6 m ahead and the
## bonnet filled a third of the screen; from here the road starts at 2 to 3 m.
const HOOD_CAM_UP := 0.27
const HOOD_CAM_FORWARD := 0.70
const ROOF_CAM_UP := 0.12

const REQUIRED := ["seat_x", "seat_h", "seat_z", "eye", "floor_y", "belt_y", "cowl", "dash_face_z", "header", "roof_y",
	"open_top", "door_x", "door_x_rear", "glass_x", "a_pillar", "b_pillar_z", "rear_z", "shelf", "wheel", "wheel_tilt_deg",
	"cluster", "cluster_style", "speedo_max_kmh", "head_unit", "lever", "handbrake", "pedals", "crank", "switch",
	"rear_mirror", "door_mirror", "console", "seats"]

## The car's cabin dictionary. Every player car has one; anything else (the
## test car, a traffic kind driven for a test) gets the coupe's, which is at
## least a complete cabin.
static func for_kind(kind: String) -> Dictionary:
	var data: GDScript = null
	if kind == P1CoupeBuilder.KIND:
		data = P1CoupeBuilder.Data
	elif NpcCarBuilder.KINDS.has(kind):
		data = NpcCarBuilder.data_of(kind)
	if data == null or not "CABIN" in data:
		var cab: Dictionary = P1CoupeBuilder.Data.CABIN
		if HOOD_POINTS.has(kind):
			# a car with no cabin of its own but its own bonnet (the pickup's
			# data file is generated, so its points cannot live there)
			cab = cab.duplicate()
			cab.merge(HOOD_POINTS[kind], true)
		return cab
	return data.CABIN

## Hood-view points for kinds whose data file has no CABIN (they wear the
## coupe's cabin): hood_cam / roof_back_cam, car space. The monster and the
## lowrider still wear the coupe's body, so they take the coupe's points.
const HOOD_POINTS := {
	# tall bonnet: the fitted point showed a quarter of the screen as bonnet (2026-10-11)
	"p17_work_pickup": {"hood_cam": Vector3(0.0, 1.33, -1.80)},
}

## Which keys a cabin is missing (tests).
static func missing(cab: Dictionary) -> Array:
	var out := []
	for k in REQUIRED:
		if not cab.has(k):
			out.append(k)
	return out

## Hood view's camera point (car space): the car's own `hood_cam`, or just ahead
## of the windscreen base and a hand above the dash lip (cowl is (y, z)).
static func hood_cam(cab: Dictionary) -> Vector3:
	if cab.has("hood_cam"):
		return cab.hood_cam
	var cowl: Vector2 = cab.cowl
	return Vector3(0.0, cowl.x + HOOD_CAM_UP, cowl.y - HOOD_CAM_FORWARD)

## The roof camera that looks back (B in hood view): over the rear of the roof,
## or just above the header bar at the rear deck of an open car.
static func roof_back_cam(cab: Dictionary) -> Vector3:
	if cab.has("roof_back_cam"):
		return cab.roof_back_cam
	var y: float = float(cab.roof_y) + ROOF_CAM_UP
	if cab.open_top:
		var header: Vector2 = cab.header
		y = header.x + 0.1
	return Vector3(0.0, y, float(cab.rear_z) + 0.1)
