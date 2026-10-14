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

## Rearview mirror fit (mirrors pass, 2026-10-14): the glass is where the eye
## can read it without looking up or round. Measured at build 4, straight
## ahead at the default FOV 62: the pickup's mirror hung 30 degrees above the
## eye (off the top of the screen), the drift coupe's 48 degrees to the right
## (off the right edge), the beater's and tuner's were half out, and even the
## coupe's right edge sat on the edge of the screen. The data point stays the
## car's own; it is slid forward along the windscreen, and down it, until the
## glass centre is within REAR_MIRROR_MAX_UP_DEG of the eye and its outer
## edge within REAR_MIRROR_MAX_EDGE_DEG (a real mirror sits about 30-35
## degrees right of the driver's line and 10-15 up). Together these keep all
## four corners on a 16:9 screen at FOV 62 (its edge is 47 degrees out). The
## housing and stalk (CockpitFrame) follow, since they read the same point.
const REAR_MIRROR_MAX_UP_DEG := 18.0
const REAR_MIRROR_MAX_EDGE_DEG := 41.0   # on the flat; the yawed glass reads about 3 deg further out from the eye
## A glass that moved forward hangs at least this far behind the windscreen.
const REAR_MIRROR_GLASS_GAP := 0.06

## Defaults for the hood camera: above and ahead of the cowl.
const HOOD_CAM_UP := 0.18
const HOOD_CAM_FORWARD := 0.35
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
		return _with_rear_mirror(cab)
	return _with_rear_mirror(data.CABIN)

## The cabin with its rearview mirror fitted (fit_rear_mirror); the data's
## own dictionary when nothing moves.
static func _with_rear_mirror(cab: Dictionary) -> Dictionary:
	if not (cab.has("rear_mirror") and cab.has("eye") and cab.has("cowl") and cab.has("header")):
		return cab
	var fitted := fit_rear_mirror(cab)
	if fitted.is_equal_approx(cab.rear_mirror):
		return cab
	var out := cab.duplicate()
	out.rear_mirror = fitted
	return out

## Where the rearview glass hangs in this cabin: the data's point, slid
## forward along the windscreen until the glass's outer edge is no more than
## REAR_MIRROR_MAX_EDGE_DEG to the side of the eye, and down it until the
## centre is no more than REAR_MIRROR_MAX_UP_DEG above the eye. The glass
## stays REAR_MIRROR_GLASS_GAP behind the windscreen plane (cowl to header)
## when it has moved, and never below the eye line. A point the data already
## has within the angles is returned as it is.
static func fit_rear_mirror(cab: Dictionary) -> Vector3:
	var m: Vector3 = cab.rear_mirror
	var eye: Vector3 = cab.eye
	var cowl: Vector2 = cab.cowl       # (y, z)
	var header: Vector2 = cab.header   # (y, z)
	var dx := absf(m.x - eye.x)
	# to the side: pull the glass forward along the windscreen
	var edge_x := dx + CockpitMirrors.REAR_SIZE_M.x * 0.5
	var side := rad_to_deg(atan2(edge_x, maxf(eye.z - m.z, 0.001)))
	if side > REAR_MIRROR_MAX_EDGE_DEG:
		m.z = eye.z - edge_x / tan(deg_to_rad(REAR_MIRROR_MAX_EDGE_DEG))
		# moved forward: keep it behind the windscreen, whose height at that z
		# is on the line from the cowl to the header
		var slope := (header.x - cowl.x) / maxf(header.y - cowl.y, 0.1)   # dy per dz; the header is behind the cowl (z grows rearward)
		var screen_y := header.x + (m.z - header.y) * slope
		m.y = minf(m.y, screen_y - REAR_MIRROR_GLASS_GAP)
	# too high: slide it down
	var flat := Vector2(dx, eye.z - m.z).length()
	var up := rad_to_deg(atan2(m.y - eye.y, flat))
	if up > REAR_MIRROR_MAX_UP_DEG:
		m.y = eye.y + flat * tan(deg_to_rad(REAR_MIRROR_MAX_UP_DEG))
	m.y = maxf(m.y, eye.y + 0.05)
	return m

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
