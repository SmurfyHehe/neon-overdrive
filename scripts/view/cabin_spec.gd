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
#   head_unit, lever, handbrake, pedals (throttle pivot; brake and clutch step left)
#   crank, switch            the window controls
#   rear_mirror, door_mirror (right side; mirrored)
#   console, seats           "tunnel" | "flat"; "bucket" | "bench" | "flat"

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
		data = NpcCarBuilder.KINDS[kind].data
	if data == null or not "CABIN" in data:
		return P1CoupeBuilder.Data.CABIN
	return data.CABIN

## Which keys a cabin is missing (tests).
static func missing(cab: Dictionary) -> Array:
	var out := []
	for k in REQUIRED:
		if not cab.has(k):
			out.append(k)
	return out
