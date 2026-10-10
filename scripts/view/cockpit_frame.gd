extends Node3D
class_name CockpitFrame

# The inside of the player's car (cockpit milestone, 2026-10-06; replaces the
# Phase C stand-in of a dash slab and a torus). A child of the PlayerCar, in car
# space (origin on the ground between the axles, -z forward, the body drawn
# BODY_LIFT up), laid out from the car's OWN cabin numbers (CabinSpec: the
# `CABIN` dictionary in that car's data file, measured from its body) so it
# fits the car seen from outside. Interior pass 2026-10-09: before it, every
# car got the coupe's cabin moved by an offset, and the beater's stuck out of
# the body. What the layout holds:
#   dashboard with a cluster (tach and speedo needles, warning lamps that mirror
#   PowertrainHealth), the SteeringWheel (LED strip, LCD, paddles) on a column,
#   a centre stack with the touch-screen HeadUnit (station tiles; the driver's
#   hand taps them, the station changes on the tap), a console with a gear
#   lever that follows the gearbox mode (H-gate in MANUAL, sequential stick in
#   SEMI, R-N-D selector in AUTO) and a handbrake that lifts,
#   two seats, door cards, sills, A- and B-pillars, roof liner, sun visors,
#   floor and footwell, three pedals that follow the inputs, and the three
#   CockpitMirrors. Dark materials, one dim amber cabin light, backlit trim.
#
# Everything that never moves is baked into two meshes (plastic, backlit) so the
# whole cabin is about 25 draw calls. Render layers: the interior is on
# INTERIOR; in the cockpit view the player's body moves to MIRROR_ONLY (the
# cockpit camera skips it, the mirror cameras draw it) instead of being hidden,
# so the door mirrors show the car's own flank. The driver (next PR) gets DRIVER.

const PlaceNames := preload("res://scripts/world/place_names.gd")
const Districts := preload("res://scripts/world/districts.gd")

const INTERIOR_LAYER := 3
const DRIVER_LAYER := 4
const MIRROR_ONLY_LAYER := 5
const INTERIOR_BIT := 1 << (INTERIOR_LAYER - 1)
const DRIVER_BIT := 1 << (DRIVER_LAYER - 1)
const MIRROR_ONLY_BIT := 1 << (MIRROR_ONLY_LAYER - 1)
const CAR_BIT := 1 << (CarFx.CAR_LAYER - 1)
## What the mirror cameras draw: the world, every car's layer and the player's own body.
const MIRROR_CULL := 1 | CAR_BIT | MIRROR_ONLY_BIT

## Lock to lock, in turns of the wheel: the rack is quick, like the reference
## wheel's car. Full keyboard lock (steer_fraction 1) is half of this each way.
const LOCK_TO_LOCK_TURNS := 1.5
const WHEEL_LOCK_RAD := LOCK_TO_LOCK_TURNS * TAU / 2.0
## How the wheel rolls (2026-10-09, Roy: continuous steering, not left/right):
## the drawn wheel chases the car's steering through a damped spring, its rim
## speed capped at WHEEL_RATE_DEG (a driver's hands' pace: full lock in half a
## second), so a keyboard tap rolls it round and back instead of snapping it,
## and it eases into lock rather than hitting it. WHEEL_DAMPING a little under
## critical lets it overshoot a touch as it returns through straight, like a
## wheel self-centring under loose hands. The car's own steering (PlayerCar)
## is untouched: this is what the hands and the eye see.
const WHEEL_RATE_DEG := 540.0
const WHEEL_SPRING_HZ := 3.0
const WHEEL_DAMPING := 0.85

## The P1 coupe's numbers, kept as constants for the tests and tools that
## drive the default car; the instance reads its own car's `cab` instead.
const SEAT_X := -0.36
## Wheel hub in car space and its tilt about x. Roy (2026-10-06): the wheel
## must point at the driver without blocking the view. Negative tilts the top
## away from the driver so the face normal rises toward the eye like a real
## column (at -25 the face looks 25 degrees up; the eye is 32 degrees up from
## the hub). The hub is set so the rim top, grip included, sits WHEEL_TOP_MIN_DEG
## below the eye: the LED strip and the LCD stay in view, the road band above
## them stays clear (tests/view/cockpit_interior.gd checks both).
const WHEEL_POS := Vector3(SEAT_X, 0.77, -0.18)
const WHEEL_TILT_DEG := -25.0
const WHEEL_TOP_MIN_DEG := 15.0
## Sightline targets (Roy, 2026-10-06): the dash line (cowl, dash top, outside
## the binnacle and the pillars) at least this far below the eye's horizontal,
## and at least this share of the cockpit view, at the rest FOV, clear glass.
## tests/view/cockpit_interior.gd measures both with rays from the eye.
const DASH_TOP_MIN_DEG := 14.0
const GLASS_MIN_FRACTION := 0.55
const CLUSTER_Z := -0.349
## Cluster centre height. Roy (2026-10-06): the cluster must not block the road.
## From the eye (1.10 m) the ground 10 m ahead of the bumper is 5 degrees
## down; the binnacle hood tops out at 0.995 (9.3 degrees down at its nearest
## edge), the dial tops at 10.6 degrees, and the dials sit under it, seen over
## and through the top of the rim (centres 1 degree above the rim top).
const CLUSTER_Y := 0.93
const DIAL_R := 0.05
## Everything the cockpit adds is visual only; this switch (and NEON_COCKPIT=0)
## leaves it out, for the isolation test and for A/B frame-cost runs.
static var enabled := true
const DIAL_SWEEP := 270.0   # degrees from empty (lower left) to full (lower right)
const SPEEDO_MAX_KMH := 300.0
const LEVER_LEN := 0.23
const LEVER_ROW_TILT := 16.0   # degrees fore/aft for a gear slot
const LEVER_COL_TILT := 11.0   # degrees left/right per column
const LEVER_SPEED := 12.0      # slot units per second along the gate path
## SEMI: the tap waits this long, so the driver's hand (DriverModel.REACH_SECS) is on it first.
const SEQ_WAIT := 0.22
const PEDAL_TRAVEL_DEG := 22.0

## The driver's side window (2026-10-09, Roy: "the Z to roll up and roll down
## needs an animation"). The glass is a pane just inside the door skin that
## slides into the door card by GLASS_TRAVEL as the window opens; below the
## belt line it is inside the card, so it simply disappears. What works it
## follows the car's spec ("window_control": "crank" or "switch"): an old car
## has a crank on the door card the driver's left hand turns (CRANK_TURNS from
## shut to open), a modern one a rocker on the armrest the thumb presses. Both
## are a few dozen triangles; the glass is 4. The window value itself is
## PerspectiveAudio's (ChaseCamera hands it over each tick, set_window()).
const GLASS_X := -0.875
const GLASS_BOTTOM := 0.955
const GLASS_TOP := 1.30
const GLASS_TRAVEL := 0.36
const CRANK_POS := Vector3(-0.826, 0.65, -0.18)   # hub on the door card, forward of and below the armrest (the hand on the knob stays under the sightline)
const CRANK_ARM := 0.085
const CRANK_KNOB_X := 0.03                        # knob mid-length, inward from the arm
const CRANK_TURNS := 2.5
const SWITCH_POS := Vector3(-0.80, 0.787, 0.02)   # rocker on the outboard edge of the armrest
const SWITCH_TILT_DEG := 14.0
const WINDOW_CONTROLS := ["crank", "switch"]
const DEFAULT_WINDOW_CONTROL := "switch"

# Colours (ROADMAP palette; dark cabin plastics around it)
const PLASTIC := Color("#1C1F26")
const PLASTIC_LIGHT := Color("#2A2E36")
const LEATHER := Color("#121318")
const SEAT := Color("#1D1F26")
const SEAT_PANEL := Color("#2A2D35")
const CARPET := Color("#0E1014")
const TRIM := Color("#2C3038")
const SILVER := Color("#C9CED6")
const AMBER := Color("#FFC066")
const SODIUM := Color("#FF8A1F")
const RED := Color("#E5262B")
const DIAL_FACE := Color("#0B0E14")
const BACKLIGHT_ENERGY := 1.6

var player: PlayerCar
var cab: Dictionary              # the car's cabin (CabinSpec.for_kind), car space
var dial_sweep := DIAL_SWEEP     # degrees of needle travel for this car's cluster style
var crank_pos := CRANK_POS
var switch_pos := SWITCH_POS
var glass_bottom := GLASS_BOTTOM
var radio: RadioManager          # found lazily; the game adds it after the camera
var wheel: SteeringWheel
var wheel_mount: Node3D          # tilt and place; the wheel turns inside it
var pod: GaugePod                # the bolt-on AFR/PSI pod; fitted with the first boost setup, see _update_pod
var mirrors: CockpitMirrors
var tach_needle: Node3D
var speedo_needle: Node3D
var lamps: MultiMeshInstance3D
var lamp_text: Label3D
var head_unit: HeadUnit         # the touch-screen radio on the centre stack
var lever: Node3D
var lever_knob: Node3D
var handbrake: Node3D
var pedals := {}                 # "throttle" / "brake" / "clutch" -> pivot Node3D
var cabin_light: OmniLight3D
var driver: DriverModel
var steering := 0.0              # -1..1 from the car, set by the camera (tests set it too)
var window := 0.0                # 0 closed .. 1 down, set by the camera (PerspectiveAudio's value)
var window_direction := 0        # +1 rolling down, -1 rolling up, 0 at rest (same source)
var window_control := DEFAULT_WINDOW_CONTROL
var glass: MeshInstance3D        # the sliding pane
var crank: Node3D                # the crank's hub pivot (crank cars), else null
var window_switch: Node3D        # the rocker's pivot (switch cars), else null
var _window_parts: Node3D        # whatever set_window_control() built
var _area_run := -1              # the district run the car was last in (area name on the head unit)
var wheel_angle := 0.0           # the drawn wheel, radians, + = right (chases steering)
var _wheel_vel := 0.0            # rad/s
var cockpit := false
var lever_moving := false
var _lever_gear := 0
var _lever_pos := Vector2.ZERO   # (col, row) in slot units, row -1 forward, +1 back
var _lever_path: Array[Vector2] = []
var lever_mode := -1             # PlayerCar.Transmission the lever shows
var _lever_heads := {}           # mode -> knob mesh
var _gate_labels := {}           # mode -> pattern label on the console
var _lever_wait := 0.0
var _last_gear := 0
var _static_tris := 0

func _init(car: PlayerCar) -> void:
	player = car
	name = "Cockpit"
	cab = CabinSpec.for_kind(PlayerCar.chassis_kind())
	crank_pos = cab.crank
	switch_pos = cab.switch
	glass_bottom = float(cab.belt_y) + 0.025
	dial_sweep = 110.0 if cab.cluster_style == "strip" else DIAL_SWEEP

func _ready() -> void:
	# Always drawn: in the chase view the cabin and driver show through the glass.
	visible = true
	_build_static()
	_build_wheel()
	_build_cluster()
	_build_radio()
	_build_lever()
	_build_handbrake()
	_build_pedals()
	_build_light()
	_build_glass()
	var control := OS.get_environment("NEON_WINDOW_CONTROL")   # tests and the screenshot tool
	if control == "":
		control = str(player.spec.get("window_control", DEFAULT_WINDOW_CONTROL))
	set_window_control(control)
	mirrors = CockpitMirrors.new()
	mirrors.name = "Mirrors"
	mirrors.cab = cab
	mirrors.cull_mask = MIRROR_CULL
	add_child(mirrors)
	_set_layers(self, INTERIOR_BIT)
	# Visual only: nothing in here casts a shadow onto the car or the road.
	for n in find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the shelf is also what the rearview camera sees under the rear glass
	if has_node("Shelf"):
		(get_node("Shelf") as VisualInstance3D).layers = INTERIOR_BIT | MIRROR_ONLY_BIT
	_last_gear = player.gear
	set_lever_mode(player.transmission_mode())
	driver = DriverModel.new(self)
	add_child(driver)
	driver.hand_contact.connect(_on_hand_contact)

## Cockpit view on or off: starts or stops the mirrors, hides the driver's head
## and torso (the camera is the head) and moves the car's own body and wheels
## to the mirror-only layer (back to the car layer when leaving), so the
## cockpit camera does not draw them but the mirrors do.
func set_cockpit(on: bool) -> void:
	cockpit = on
	mirrors.set_active(on)
	driver.set_cockpit(on)
	var bit := MIRROR_ONLY_BIT if on else CAR_BIT
	if player.chassis_visual != null:
		_set_layers(player.chassis_visual, bit)
	for w in player.wheel_array:
		if w.wheel_node != null:
			_set_layers(w.wheel_node, bit)

## True while the player's body is kept off the cockpit camera (tests).
func body_hidden_from_camera() -> bool:
	if player.chassis_visual == null:
		return true
	for n in player.chassis_visual.find_children("*", "VisualInstance3D", true, false):
		if n is Light3D:
			continue
		if (n as VisualInstance3D).layers != MIRROR_ONLY_BIT:
			return false
	return true

static func _set_layers(root: Node, bit: int) -> void:
	if root is VisualInstance3D and not root is Light3D:
		(root as VisualInstance3D).layers = bit
	for n in root.find_children("*", "VisualInstance3D", true, false):
		if n is Light3D:
			continue   # a light's layers decide whether it lights at all
		(n as VisualInstance3D).layers = bit

# ---------- static cabin ----------

func _build_static() -> void:
	var k := CockpitKit.new()
	var lit := CockpitKit.new()
	# Trim set: the stock dark plastics, or the beater's worn cabin (Roy,
	# 2026-10-09: "make the VW a true beater"): faded warm greys, a rusty
	# brown trim, mismatched seats (brown vinyl and a grey one), no backlit strips.
	var worn := String(cab.get("trim", "stock")) == "worn"
	var c_plastic := Color("#3A3630") if worn else PLASTIC
	var c_plastic_light := Color("#4A443B") if worn else PLASTIC_LIGHT
	var c_trim := Color("#5A4A3A") if worn else TRIM
	var c_seat := Color("#4B4036") if worn else SEAT
	var c_seat_pass := Color("#35383F") if worn else SEAT
	var c_seat_panel := Color("#3A3129") if worn else SEAT_PANEL
	var c_leather := Color("#3F362E") if worn else LEATHER
	var c_carpet := Color("#1A1612") if worn else CARPET
	var strip := Color(AMBER, 0.0 if worn else 0.35)
	# the beater's dash is painted metal in the body's faded paint, not moulded plastic
	var c_dash := Color("#6B7668") if worn else c_plastic
	var c_dash_face := Color("#5E6A5C") if worn else c_plastic_light
	var seat_x := float(cab.seat_x)
	var seat_h := float(cab.seat_h)
	var seat_z := float(cab.seat_z)
	var floor_y := float(cab.floor_y)
	var belt := float(cab.belt_y)
	var cowl: Vector2 = cab.cowl          # (y, z) the dash lip under the windshield base
	var face_z := float(cab.dash_face_z)  # the dash face toward the driver
	var header: Vector2 = cab.header      # (y, z) the windshield top
	var roof_y := float(cab.roof_y)
	var open_top: bool = cab.open_top
	var door_x := float(cab.door_x)       # door card face by the seat
	var door_x_r := float(cab.door_x_rear)
	var door_x_f := float(cab.get("door_x_front", door_x))   # the card narrows toward the A-pillar foot
	var pillar_foot: Vector3 = cab.a_pillar[0]
	var pillar_top: Vector3 = cab.a_pillar[1]
	var b_z := float(cab.b_pillar_z)
	var rear_z := float(cab.rear_z)
	var cl: Vector2 = cab.cluster         # (y, z) the dial centres
	var eye: Vector3 = cab.eye
	# Dashboard: a top that falls from the cluster height at the driver's edge
	# to the cowl lip, a face toward the driver, a knee panel, and the cowl lip.
	# Roy (2026-10-06): the dash line sits at least DASH_TOP_MIN_DEG (14) below
	# the eye across the driver's view; the cowl is the top of that line, so
	# each car's CABIN puts its cowl at or under that angle from its own eye.
	var dash_half := minf(door_x_f + 0.04, pillar_foot.x - 0.03)   # the body narrows toward the cowl corners
	var dash_w := dash_half * 2.0
	var dash_depth := face_z - cowl.y
	var top_near := cl.x
	var top_far := cowl.x   # the lip's top is the cowl line itself
	k.wedge(Vector3(dash_w, 0.06, dash_depth), Vector3(0.0, cowl.x - 0.03, (cowl.y + face_z) * 0.5), c_dash, 0.0, top_near - top_far)
	k.box(Vector3(dash_w, 0.36, 0.12), Vector3(0.0, top_near - 0.20, face_z), c_dash_face)
	var knee_depth := minf(0.32, face_z - cowl.y + 0.12)   # never past the firewall (the kei's dash is 6 cm deep)
	k.box(Vector3(dash_w, 0.22, knee_depth), Vector3(0.0, top_near - 0.45, face_z + 0.03 - knee_depth * 0.5), c_plastic)
	k.box(Vector3(dash_w - 0.08, 0.03, 0.06), Vector3(0.0, cowl.x - 0.015, cowl.y), c_trim)  # cowl lip, under the glass line
	lit.box(Vector3(dash_w - 0.14, 0.006, 0.01), Vector3(0.0, top_near - 0.018, face_z + 0.055), strip)   # dash edge strip
	# Cluster binnacle and its hood in front of the driver, then the dial faces.
	_build_cluster_faces(k, lit, seat_x, cl)
	# Centre stack: vents, the radio bezel (the unit itself is built in _build_radio).
	k.box(Vector3(0.30, 0.24, 0.06), Vector3(0.0, top_near - 0.14, face_z + 0.03), c_plastic_light)
	for vx in [-0.09, 0.09]:   # vents under the head unit
		k.box(Vector3(0.09, 0.03, 0.012), Vector3(vx, top_near - 0.218, face_z + 0.063), c_plastic)
	# Centre console with the gate plate and its H slots, tunnel, armrest.
	var lever: Vector3 = cab.lever
	var hb: Vector3 = cab.handbrake
	if cab.console == "tunnel":
		var con_len := (hb.z + 0.20) - (face_z + 0.06)
		var con_z := (face_z + 0.06 + hb.z + 0.20) * 0.5
		k.box(Vector3(0.26, 0.20, con_len), Vector3(0.0, lever.y - 0.095, con_z), c_plastic)
		k.box(Vector3(0.30, 0.18, con_len + 0.38), Vector3(0.0, floor_y + 0.06, con_z - 0.01), c_carpet)   # tunnel
		k.box(Vector3(0.20, 0.05, 0.22), Vector3(0.0, lever.y + 0.03, hb.z - 0.06), c_leather)              # armrest
		lit.box(Vector3(0.006, 0.004, con_len - 0.2), Vector3(-0.133, lever.y + 0.007, con_z - 0.06), Color(strip, strip.a * 0.86))
		lit.box(Vector3(0.006, 0.004, con_len - 0.2), Vector3(0.133, lever.y + 0.007, con_z - 0.06), Color(strip, strip.a * 0.86))
	else:
		# flat floor (rear-engine beater): a low hump with the gate plate on it
		k.box(Vector3(0.24, 0.07, 0.60), Vector3(0.0, lever.y - 0.035, lever.z + 0.18), c_carpet)
		k.box(Vector3(0.16, 0.03, 0.18), Vector3(0.0, lever.y - 0.004, lever.z), c_plastic)
	k.box(Vector3(0.13, 0.012, 0.15), Vector3(0.0, lever.y + 0.011, lever.z), c_trim)
	# one H column per pair of forward gears (3 for a six-speed, 2 for a four)
	var gate_cols := gate_columns(player.gear_ratios.size())
	for c in gate_cols:
		k.box(Vector3(0.012, 0.004, 0.11), Vector3((c - (gate_cols - 1) / 2.0) * 0.035, lever.y + 0.018, lever.z), DIAL_FACE)
	k.box(Vector3((gate_cols - 1) * 0.035 + 0.012, 0.004, 0.012), Vector3(0.0, lever.y + 0.018, lever.z), DIAL_FACE)
	# Seats, driver and passenger.
	var recline := Basis(Vector3.RIGHT, deg_to_rad(12.0))
	var seat_w := minf(0.50, (door_x - 0.02) - 0.14 if cab.console != "tunnel" else door_x - 0.17)
	seat_w = clampf(seat_w, 0.40, 0.50)
	if cab.seats == "bench":
		# one cushion and backrest across the car, a fold-down armrest hump in the middle
		var bw := door_x * 2.0 - 0.06
		k.wedge(Vector3(bw, 0.10, 0.50), Vector3(0.0, seat_h - 0.05, seat_z), c_seat, 0.03, 0.0)
		k.box(Vector3(bw, 0.58, 0.10), Vector3(0.0, seat_h + 0.28, seat_z + 0.25), c_seat, recline)
		k.box(Vector3(bw, 0.06, 0.30), Vector3(0.0, seat_h - 0.12, seat_z + 0.03), c_plastic)
		for sx in [seat_x, -seat_x]:
			k.box(Vector3(0.22, 0.10, 0.08), Vector3(sx, seat_h + 0.62, seat_z + 0.35), c_seat, recline)   # headrests
			k.box(Vector3(0.44, 0.02, 0.44), Vector3(sx, seat_h + 0.01, seat_z + 0.02), c_seat_panel)      # pleats
	else:
		for sx in [seat_x, -seat_x]:
			var c_this := c_seat if sx == seat_x else c_seat_pass
			k.wedge(Vector3(seat_w, 0.10, 0.50), Vector3(sx, seat_h - 0.05, seat_z), c_this, 0.03, 0.0)
			if cab.seats == "bucket":
				k.box(Vector3(0.10, 0.10, 0.46), Vector3(sx - seat_w * 0.42, seat_h + 0.02, seat_z - 0.02), c_seat_panel)  # cushion bolsters
				k.box(Vector3(0.10, 0.10, 0.46), Vector3(sx + seat_w * 0.42, seat_h + 0.02, seat_z - 0.02), c_seat_panel)
				k.box(Vector3(0.09, 0.50, 0.14), Vector3(sx - seat_w * 0.44, seat_h + 0.28, seat_z + 0.23), c_seat_panel, recline)
				k.box(Vector3(0.09, 0.50, 0.14), Vector3(sx + seat_w * 0.44, seat_h + 0.28, seat_z + 0.23), c_seat_panel, recline)
			k.box(Vector3(seat_w, 0.58, 0.10), Vector3(sx, seat_h + 0.28, seat_z + 0.25), c_this, recline)
			k.box(Vector3(0.22, 0.10, 0.08), Vector3(sx, seat_h + 0.62, seat_z + 0.35), c_this, recline)         # headrest
			k.box(Vector3(seat_w, 0.06, 0.30), Vector3(sx, seat_h - 0.12, seat_z + 0.03), c_plastic)              # seat base
	# Door cards, armrests, pulls, sills: the card's face is at door_x, 6 cm thick outward.
	var card_top := belt - 0.02
	var card_h := card_top - (floor_y + 0.26)
	var door_z0 := pillar_foot.z + 0.28
	var door_len := b_z - door_z0
	var door_zc := (door_z0 + b_z) * 0.5
	var front_len := door_len * 0.5
	for side in [-1.0, 1.0]:
		# the front half of the card sits at the narrower front width, the rear half by the seat
		k.box(Vector3(0.06, card_h, front_len), Vector3(side * (minf(door_x, door_x_f) + 0.03), (card_top + floor_y + 0.26) * 0.5, door_z0 + front_len * 0.5), c_plastic_light)
		k.box(Vector3(0.06, card_h, door_len - front_len), Vector3(side * (door_x + 0.03), (card_top + floor_y + 0.26) * 0.5, b_z - (door_len - front_len) * 0.5), c_plastic_light)
		k.box(Vector3(0.06, 0.08, front_len), Vector3(side * (minf(door_x, door_x_f) + 0.03), belt - 0.055, door_z0 + front_len * 0.5), c_leather)   # belt line pad, its top just under the belt (the glass leans in above it)
		k.box(Vector3(0.06, 0.08, door_len - front_len), Vector3(side * (door_x + 0.03), belt - 0.055, b_z - (door_len - front_len) * 0.5), c_leather)
		k.box(Vector3(0.12, 0.04, 0.32), Vector3(side * (door_x - 0.04), seat_h + 0.28, eye.z - 0.22), c_leather)       # armrest
		k.box(Vector3(0.05, 0.03, 0.12), Vector3(side * (door_x - 0.025), seat_h + 0.36, eye.z - 0.52), c_trim)        # door pull
		lit.box(Vector3(0.004, 0.004, door_len - 0.25), Vector3(side * (door_x - 0.002), card_top, door_zc), Color(strip, strip.a * 0.86))
		k.box(Vector3(0.14, 0.12, door_len + 0.10), Vector3(side * (minf(door_x, door_x_f) - 0.04), floor_y + 0.04, door_zc + 0.05), c_plastic)   # sill
		# B-pillar inner face and the rear quarter trim behind the door
		if open_top:
			k.box(Vector3(0.06, 0.08, 0.08), Vector3(side * (door_x_r - 0.05), belt + 0.02, b_z), c_plastic)
		else:   # up the tumblehome to the roof's edge
			_bar(k, Vector3(side * (door_x_r - 0.05), belt, b_z), Vector3(side * (pillar_top.x - 0.04), roof_y - 0.05, b_z), 0.07, c_plastic)
		var q_top := (belt + 0.14) if not open_top else belt + 0.02
		var q_len := minf(rear_z - b_z, 0.35)   # the body tucks in over the rear arch
		k.box(Vector3(0.08, q_top - (floor_y + 0.26), q_len), Vector3(side * (door_x_r - 0.15), (q_top + floor_y + 0.26) * 0.5, b_z + q_len * 0.5), c_plastic_light)
	# A-pillars: from the cowl corners to the roof corners (body lines from the data).
	for side in [-1.0, 1.0]:   # the ends tucked 4 cm in and 3 cm down from the skin's corners
		_bar(k, Vector3(side * (pillar_foot.x - 0.04), pillar_foot.y, pillar_foot.z + 0.02), Vector3(side * (pillar_top.x - 0.13), pillar_top.y - 0.09, pillar_top.z + 0.03), 0.075, c_plastic)
	# Roof liner, windshield header, sun visors. The header's underside sits on
	# the glass-top line, not under it (Roy's clear-glass target, 2026-10-06).
	var liner_half := pillar_top.x - 0.10   # the roof is narrower than the belt line, and crowned
	if open_top:
		# a roadster: the windshield frame's top bar only, and two roll hoops behind the seats
		k.box(Vector3(pillar_top.x * 2.0 - 0.06, 0.05, 0.08), Vector3(0.0, header.x - 0.075, header.y + 0.05), c_plastic)
		for sx in [seat_x, -seat_x]:
			_bar(k, Vector3(sx - 0.14, seat_h + 0.10, seat_z + 0.38), Vector3(sx - 0.10, seat_h + 0.72, seat_z + 0.40), 0.04, c_trim)
			_bar(k, Vector3(sx + 0.14, seat_h + 0.10, seat_z + 0.38), Vector3(sx + 0.10, seat_h + 0.72, seat_z + 0.40), 0.04, c_trim)
			k.box(Vector3(0.30, 0.04, 0.04), Vector3(sx, seat_h + 0.73, seat_z + 0.40), c_trim)
	else:
		var roof_z1 := minf(rear_z, float(cab.get("roof_z1", rear_z)))   # where the roof starts dropping to the rear glass
		var liner_z0 := header.y + 0.10   # the header bar covers the front edge, under the crown
		var liner_len := roof_z1 - liner_z0
		k.box(Vector3(liner_half * 2.0, 0.02, liner_len), Vector3(0.0, roof_y - 0.025, (liner_z0 + roof_z1) * 0.5), c_plastic_light)   # under the crown
		# behind the glass top, its top on the roof line: hung lower it cut the top of the view (tests/view/cockpit_interior.gd)
		k.box(Vector3(pillar_top.x * 2.0 - 0.50, 0.05, 0.08), Vector3(0.0, header.x - 0.03, header.y + 0.06), c_plastic)
		for sx in [seat_x, -seat_x]:   # folded up against the liner, above the view line
			k.box(Vector3(0.36, 0.012, 0.15), Vector3(sx * 0.9, roof_y - 0.05, header.y + 0.16), c_leather, Basis(Vector3.RIGHT, deg_to_rad(-2.0)))
	# Rearview mirror housing and stalk (the glass is a CockpitMirrors quad).
	var rear_pos: Vector3 = cab.rear_mirror
	var rb := Basis(Vector3.UP, deg_to_rad(CockpitMirrors.REAR_YAW)) * Basis(Vector3.RIGHT, deg_to_rad(CockpitMirrors.REAR_PITCH))
	k.box(Vector3(0.215, 0.072, 0.022), rear_pos + rb * Vector3(0, 0, -0.013), c_plastic, rb)
	# a short stalk up to the glass right above the housing (a long slant to the
	# header cut across the clear band: tests/view/cockpit_interior.gd)
	var glass_slope := (header.x - cowl.x - 0.086) / maxf(header.y - cowl.y, 0.1)
	var glass_y := header.x - (header.y - rear_pos.z) * glass_slope - 0.008
	_bar(k, rear_pos + Vector3(0.0, 0.03, 0.0), Vector3(0.0, maxf(glass_y, rear_pos.y + 0.04), rear_pos.z), 0.018, c_plastic)
	# Floor, footwell and firewall; rear bulkhead. (The door mirror cups are on
	# the body; the parcel shelf is its own mesh, see _ready.)
	var floor_half := door_x + 0.02
	var floor_len := rear_z - (cowl.y + 0.12)
	k.box(Vector3(floor_half * 2.0, 0.04, floor_len), Vector3(0.0, floor_y, (cowl.y + 0.12 + rear_z) * 0.5), c_carpet)
	k.wedge(Vector3((minf(door_x, door_x_f) - 0.12) * 2.0, 0.04, 0.30), Vector3(0.0, floor_y + 0.02, cowl.y + 0.09), c_carpet, 0.16, 0.0)   # footwell, between the arches
	k.box(Vector3(minf(dash_half, minf(door_x, door_x_f)) * 2.0, cowl.x - 0.10 - floor_y, 0.04), Vector3(0.0, (cowl.x - 0.10 + floor_y) * 0.5, cowl.y - 0.03), c_plastic)
	var bulk_top := (belt + 0.26) if not open_top else belt - 0.02
	if not (cab.shelf as Dictionary).is_empty():
		bulk_top = minf(bulk_top, float(cab.shelf.y) - 0.02)   # under the shelf
	k.box(Vector3((door_x_r - 0.16) * 2.0, bulk_top - (floor_y + 0.26), 0.04), Vector3(0.0, (bulk_top + floor_y + 0.26) * 0.5, rear_z), c_plastic_light)   # between the rear arches
	if worn:
		# Half stripped (Roy, 2026-10-09: the beater starts with no back seat and
		# torn carpet): bare floor pan showing through three torn patches, and the
		# rear deck is painted steel, not carpet.
		var pan := Color("#4A4A48")
		for patch in [[Vector3(seat_x + 0.05, 0.0, seat_z - 0.55), Vector2(0.34, 0.26)],
				[Vector3(-seat_x - 0.10, 0.0, seat_z - 0.30), Vector2(0.28, 0.40)],
				[Vector3(0.0, 0.0, rear_z - 0.30), Vector2(floor_half * 1.6, 0.30)]]:
			var at: Vector3 = patch[0]
			var sz: Vector2 = patch[1]
			k.box(Vector3(sz.x, 0.006, sz.y), Vector3(at.x, floor_y + 0.022, at.z), pan)
	_static_tris = k.tri_count() + lit.tri_count()
	if not open_top and not (cab.shelf as Dictionary).is_empty():
		var sh: Dictionary = cab.shelf
		var shelf := CockpitKit.new()
		shelf.box(Vector3(float(sh.half_w) * 2.0, 0.04, float(sh.z1) - float(sh.z0)), Vector3(0.0, float(sh.y), (float(sh.z0) + float(sh.z1)) * 0.5), Color("#4A4A48") if worn else c_carpet)
		_static_tris += shelf.tri_count()
		add_child(shelf.instance(CockpitKit.material(), "Shelf"))
	add_child(k.instance(CockpitKit.material(0.85, 0.05), "Cabin"))
	add_child(lit.instance(CockpitKit.glow_material(BACKLIGHT_ENERGY), "Backlight"))

## The binnacle and the dial faces for this car's cluster style, in car space:
##   dials   a tach left and a speedo right, the coupe's pair
##   pod     one big speedo pod in front of the driver with a small tach inset
##           low left (the beater's single round binnacle)
##   triple  the pair plus three small aux gauges in a hood on the dash top
##   strip   a wide, shallow horizontal speedo band with a small tach to its
##           left (the muscle sedan); the needles sweep 110 degrees
## tach and speedo needle pivots come from dial_centres().
func _build_cluster_faces(k: CockpitKit, lit: CockpitKit, seat_x: float, cl: Vector2) -> void:
	var style := String(cab.cluster_style)
	var centres := dial_centres()
	var radii := dial_radii()
	var flat := Basis(Vector3.RIGHT, PI / 2.0)
	match style:
		"pod":
			var depth := clampf(cl.y - float((cab.cowl as Vector2).y) - 0.04, 0.03, 0.11)   # never through the cowl
			k.cylinder(0.105, -depth, 0.0, Vector3(seat_x, cl.x, cl.y - 0.052), PLASTIC, 16, flat)
			k.cylinder(0.115, -0.03, 0.0, Vector3(seat_x, cl.x, cl.y - 0.05), TRIM, 16, flat)
		"strip":
			k.box(Vector3(0.62, 0.11, 0.10), Vector3(seat_x + 0.08, cl.x, cl.y - 0.05), PLASTIC)
			k.wedge(Vector3(0.66, 0.012, 0.16), Vector3(seat_x + 0.08, cl.x + 0.054, cl.y - 0.07), PLASTIC_LIGHT, 0.0, -0.02)
		"triple":
			k.box(Vector3(0.34, 0.12, 0.10), Vector3(seat_x, cl.x, cl.y - 0.05), PLASTIC)
			k.wedge(Vector3(0.38, 0.012, 0.16), Vector3(seat_x, cl.x + 0.059, cl.y - 0.07), PLASTIC_LIGHT, 0.0, -0.02)
			# three aux gauges in a hood on the dash top, angled at the driver
			var hood := Vector3(seat_x + 0.02, cl.x + 0.085, cl.y - 0.16)
			k.box(Vector3(0.22, 0.05, 0.07), hood, PLASTIC)
			var tilt := Basis(Vector3.RIGHT, deg_to_rad(70.0))
			for i in 3:
				var c := hood + Vector3(-0.07 + 0.07 * i, 0.006, 0.03)
				lit.cylinder(0.024, -0.004, 0.0, c, Color(DIAL_FACE, 0.15), 12, tilt)
				k.cylinder(0.030, -0.008, -0.002, c + Vector3(0, 0, 0.001), TRIM, 12, tilt)
				lit.box(Vector3(0.003, 0.016, 0.002), c + tilt * Vector3(0.0, 0.012, 0.0), Color(RED, 0.6), tilt)
		_:
			k.box(Vector3(0.34, 0.12, 0.10), Vector3(seat_x, cl.x, cl.y - 0.05), PLASTIC)
			k.wedge(Vector3(0.38, 0.012, 0.16), Vector3(seat_x, cl.x + 0.059, cl.y - 0.07), PLASTIC_LIGHT, 0.0, -0.02)
	# Dial faces (backlit dark), rings and tick marks: 0 = tach, 1 = speedo.
	var a_start := 225.0 if dial_sweep > 180.0 else 90.0 + dial_sweep * 0.5
	for i in 2:
		var c: Vector3 = centres[i]
		var r: float = radii[i]
		if style == "strip" and i == 1:
			# the speedo band: a wide shallow arc face with the pivot low in the middle
			var band := CockpitKit.new()
			band.ring_sector(r * 0.55, r, deg_to_rad(a_start - dial_sweep), deg_to_rad(a_start), -0.004, 0.0, Color(DIAL_FACE, 0.15), 16)
			band.offset(c)
			lit.merge(band)
			var rim := CockpitKit.new()
			rim.ring_sector(r * 0.53, r + 0.008, deg_to_rad(a_start - dial_sweep), deg_to_rad(a_start), -0.008, -0.002, TRIM, 16)
			rim.offset(c + Vector3(0, 0, -0.001))
			k.merge(rim)
		else:
			lit.cylinder(r, -0.004, 0.0, c, Color(DIAL_FACE, 0.15), 16, flat)
			k.cylinder(r + 0.008, -0.008, -0.002, c + Vector3(0, 0, -0.001), TRIM, 16, flat)
		var ticks := 9 if i == 0 else 7
		for t in ticks:
			var a := deg_to_rad(a_start - dial_sweep * float(t) / (ticks - 1))
			var pt := c + Vector3(cos(a), sin(a), 0.0) * (r - 0.012) + Vector3(0, 0, 0.001)
			lit.box(Vector3(0.003, 0.009, 0.002), pt, Color(AMBER, 0.6), Basis(Vector3.BACK, a - PI / 2.0))
		if i == 0:
			# red zone on the tach, from the HUD's red band to the end
			var a0 := deg_to_rad(a_start - dial_sweep * Hud.RED_FROM)
			var a1 := deg_to_rad(a_start - dial_sweep)
			var zone := CockpitKit.new()
			zone.ring_sector(r - 0.019, r - 0.013, a1, a0, 0.0, 0.0015, Color(RED, 0.5), 4)
			zone.offset(c)
			lit.merge(zone)

## The tach (0) and speedo (1) centres for this car's cluster style, car space.
func dial_centres() -> Array:
	var seat_x := float(cab.seat_x)
	var cl: Vector2 = cab.cluster
	match String(cab.cluster_style):
		"pod":
			return [Vector3(seat_x - 0.075, cl.x - 0.045, cl.y + 0.002), Vector3(seat_x, cl.x, cl.y)]
		"strip":
			return [Vector3(seat_x - 0.20, cl.x, cl.y), Vector3(seat_x + 0.11, cl.x - 0.03, cl.y)]
		_:
			return [Vector3(seat_x - 0.085, cl.x, cl.y), Vector3(seat_x + 0.085, cl.x, cl.y)]

func dial_radii() -> Array:
	match String(cab.cluster_style):
		"pod":
			return [0.03, 0.085]
		"strip":
			return [0.045, 0.20]
		_:
			return [DIAL_R, DIAL_R]

## A box from a to b, `w` across, for pillars.
static func _bar(k: CockpitKit, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	var len := d.length()
	var y := d / len
	var x := y.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < 0.5:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	k.box(Vector3(w, len, w * 1.2), (a + b) * 0.5, col, Basis(x, y, z))

# ---------- the side window ----------

func _build_glass() -> void:
	var k := CockpitKit.new()
	var tint := Color(Color(P1CoupeBuilder.Data.COLORS.glass), 0.55)
	var gx := -float(cab.glass_x)
	var top := float(cab.get("glass_top", float(cab.roof_y) - 0.03)) if not cab.open_top else float(cab.belt_y) + 0.30
	var gx_top := -minf(float(cab.glass_x), float((cab.a_pillar[1] as Vector3).x) - 0.01)   # tumblehome: the pane leans in
	var z0 := float((cab.a_pillar[0] as Vector3).z) + 0.20   # at the A-pillar foot
	var z1 := float(cab.b_pillar_z) - 0.04                     # at the B-pillar
	var zt := float((cab.a_pillar[1] as Vector3).z) - 0.04     # top front, where the A-pillar meets the roof
	var a := Vector3(gx, glass_bottom, z0)
	var b := Vector3(gx, glass_bottom, z1)
	var c := Vector3(gx_top, top, z1)
	var d := Vector3(gx_top, top, maxf(zt + 0.30, z0 + 0.10))   # the raked pillar: the top edge starts well behind the foot
	k.quad(a, b, c, d, tint)
	k.quad(a, d, c, b, tint)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.6
	m.roughness = 0.08
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass = k.instance(m, "WindowGlass")
	glass.visible = float(cab.glass_x) > 0.0
	add_child(glass)

## Builds (or rebuilds) what works the window: "crank" or "switch". Called at
## build from the car's spec; the screenshot tool switches it live.
func set_window_control(control: String) -> void:
	if not WINDOW_CONTROLS.has(control):
		push_warning("CockpitFrame: unknown window_control '%s', using %s" % [control, DEFAULT_WINDOW_CONTROL])
		control = DEFAULT_WINDOW_CONTROL
	window_control = control
	if _window_parts != null:
		_window_parts.queue_free()
	crank = null
	window_switch = null
	_window_parts = Node3D.new()
	_window_parts.name = "WindowControl"
	add_child(_window_parts)
	var mat := CockpitKit.material(0.6, 0.3, 0.2)
	if control == "crank":
		# Boss on the door card; the arm and its peg knob turn about the door
		# normal (x). Chrome arm, black knob, like a 70s door.
		var boss := CockpitKit.new()
		boss.cylinder(0.02, 0.0, 0.012, crank_pos, TRIM, 10, Basis(Vector3.BACK, -PI / 2.0))
		_window_parts.add_child(boss.instance(mat, "CrankBoss"))
		crank = Node3D.new()
		crank.name = "Crank"
		crank.position = crank_pos
		_window_parts.add_child(crank)
		var k := CockpitKit.new()
		k.box(Vector3(0.014, CRANK_ARM + 0.03, 0.022), Vector3(0.016, CRANK_ARM * 0.5, 0.0), SILVER)
		k.cylinder(0.011, 0.012, 0.022, Vector3(0.0, 0.0, 0.0), SILVER, 8, Basis(Vector3.BACK, -PI / 2.0))   # hub cap
		k.cylinder(0.011, 0.008, 0.052, Vector3(0.0, CRANK_ARM, 0.0), PLASTIC, 10, Basis(Vector3.BACK, -PI / 2.0))   # the peg knob
		crank.add_child(k.instance(mat, "Arm"))
	else:
		# A small bezel let into the armrest with one rocker in it, an amber
		# index mark on the rocker so it reads in the dark.
		var bezel := CockpitKit.new()
		bezel.box(Vector3(0.05, 0.006, 0.07), switch_pos + Vector3(0.0, -0.006, 0.0), PLASTIC)
		bezel.box(Vector3(0.026, 0.004, 0.044), switch_pos + Vector3(0.0, -0.004, 0.0), DIAL_FACE)
		_window_parts.add_child(bezel.instance(mat, "SwitchBezel"))
		window_switch = Node3D.new()
		window_switch.name = "Switch"
		window_switch.position = switch_pos
		_window_parts.add_child(window_switch)
		var k := CockpitKit.new()
		k.box(Vector3(0.018, 0.008, 0.034), Vector3(0.0, 0.004, 0.0), TRIM)
		k.box(Vector3(0.004, 0.002, 0.016), Vector3(0.0, 0.009, 0.0), AMBER)
		window_switch.add_child(k.instance(mat, "Rocker"))
	_set_layers(_window_parts, INTERIOR_BIT)
	for n in _window_parts.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_window()

## The window value and which way it is going, from the camera each physics
## tick (PerspectiveAudio.window). Tests call it directly.
func set_window(openness: float, direction: int) -> void:
	window = clampf(openness, 0.0, 1.0)
	window_direction = direction
	_apply_window()

func _apply_window() -> void:
	if glass != null:
		glass.position = Vector3(0.0, -GLASS_TRAVEL * window, 0.0)
	if crank != null:
		crank.rotation = Vector3(-window * CRANK_TURNS * TAU, 0.0, 0.0)
	if window_switch != null:
		window_switch.rotation_degrees = Vector3(SWITCH_TILT_DEG * float(window_direction), 0.0, 0.0)

## Where the glass's bottom edge is now, car space y (tests).
func glass_bottom_y() -> float:
	return glass_bottom + glass.position.y

## The crank's knob, mid-length, car space: where the hand holds it.
func crank_knob_position() -> Vector3:
	return crank.transform * Vector3(CRANK_KNOB_X, CRANK_ARM, 0.0)

## The top face of the rocker, car space: where the thumb lands.
func switch_press_position() -> Vector3:
	return switch_pos + Vector3(0.0, 0.009, 0.0)

# ---------- wheel and column ----------

func _build_wheel() -> void:
	wheel_mount = Node3D.new()
	wheel_mount.name = "WheelMount"
	wheel_mount.position = cab.wheel
	wheel_mount.rotation_degrees = Vector3(float(cab.wheel_tilt_deg), 0.0, 0.0)
	add_child(wheel_mount)
	wheel = SteeringWheel.new()
	wheel.name = "Wheel"
	if String(cab.get("trim", "stock")) == "worn":
		# the beater: a thin ivory rim, grey seam, painted spokes to match the dash
		wheel.rim_colour = Color("#D9D2BC")
		wheel.seam_colour = Color("#9A947F")
		wheel.spoke_colour = Color("#6B7668")
		wheel.carbon_colour = Color("#7E8A7B")
		wheel.carbon_alt_colour = Color("#6B7668")
	wheel_mount.add_child(wheel)
	# A short column stub behind the hub (the long pole down the middle of the
	# view is gone, Roy 2026-10-06); the shroud is on the dash face, under the cluster.
	var k := CockpitKit.new()
	k.cylinder(0.024, -0.09, -0.03, Vector3.ZERO, PLASTIC_LIGHT, 8, Basis(Vector3.RIGHT, -PI / 2.0))
	wheel_mount.add_child(k.instance(CockpitKit.material(), "Column"))

# ---------- instrument cluster ----------

func _build_cluster() -> void:
	var centres := dial_centres()
	var radii := dial_radii()
	var tach_c: Vector3 = centres[0]
	var speedo_c: Vector3 = centres[1]
	tach_needle = _needle(tach_c + Vector3(0.0, 0.0, 0.004), "TachNeedle", float(radii[0]))
	speedo_needle = _needle(speedo_c + Vector3(0.0, 0.0, 0.004), "SpeedoNeedle", float(radii[1]))
	# The warning lamps sit between the dials (under the speedo pod's tach on the beater).
	var lamp_c := (tach_c + speedo_c) * 0.5 + Vector3(0.0, 0.03, 0.0)
	if cab.cluster_style == "pod":
		lamp_c = speedo_c + Vector3(0.0, -0.055, 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(0.018, 0.009, 0.003)
	mm.mesh = box
	mm.instance_count = 4
	for i in 4:
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(0.7, 0.7, 1.0)), lamp_c + Vector3(-0.027 + 0.018 * i, 0.0, 0.002)))
		mm.set_instance_color(i, Color(AMBER, 0.0))
	lamps = MultiMeshInstance3D.new()
	lamps.name = "Lamps"
	lamps.multimesh = mm
	lamps.material_override = CockpitKit.glow_material(SteeringWheel.LED_ENERGY)
	add_child(lamps)
	lamp_text = _label("ENG BRK TYR CLT", 12, lamp_c + Vector3(0.0, -0.015, 0.002), SILVER, 0.0004)
	lamp_text.name = "LampText"
	_label("x1000 rpm", 22, tach_c + Vector3(0.0, -float(radii[0]) * 0.6, 0.002), AMBER, 0.0004)
	_label("km/h", 22, speedo_c + Vector3(0.0, -float(radii[1]) * 0.6, 0.002), AMBER, 0.0004)

func _needle(at: Vector3, node_name: String, r: float = DIAL_R) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = at
	var k := CockpitKit.new()
	var len := r - 0.006
	k.box(Vector3(0.004, len, 0.002), Vector3(0.0, len * 0.5 - 0.004, 0.0), Color(RED, 1.0))
	k.box(Vector3(0.0035, 0.010, 0.002), Vector3(0.0, -0.008, 0.0), Color(SILVER, 0.3))
	k.cylinder(0.006, -0.001, 0.0015, Vector3.ZERO, Color(SILVER, 0.2), 8, Basis(Vector3.RIGHT, PI / 2.0))
	pivot.add_child(k.instance(CockpitKit.glow_material(SteeringWheel.LED_ENERGY)))
	add_child(pivot)
	return pivot

func _label(text: String, size: int, at: Vector3, col: Color, px: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UiTheme.font("dial")   # Dial numbers role
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = at
	add_child(l)
	return l

# ---------- radio head unit ----------

## The head unit is its own builder (HeadUnit, styled per car), so the
## interior redesign can restyle it without touching the hand or the radio.
## On the stack right of the wheel, its bezel just under the dash top (0.91),
## so the tiles show over the wheel from the seat (lower, they were cut off by
## the bottom of the cockpit view).
const HEAD_UNIT_POS := Vector3(0.0, 0.832, -0.254)

func _build_radio() -> void:
	head_unit = HeadUnit.new(PlayerCar.chassis_kind())
	head_unit.position = cab.head_unit
	add_child(head_unit)

## Next station: the key only asks; the driver's right hand reaches the screen
## and RadioManager.next_station() runs on the finger's contact
## (_on_hand_contact). Waits for the hand if it is busy (a shift, the handbrake).
func request_radio() -> void:
	driver.request_radio()

## Where the finger lands for the next station, car space, and which contact
## that is: the next tile, or past the last one the knob (radio off).
func radio_touch() -> Dictionary:
	var count := RadioStations.station_count()
	var s := _find_radio().station if _find_radio() != null else -1
	if s + 1 < count:
		return {"pos": head_unit.transform * head_unit.tile_point(s + 1), "contact": DriverModel.CONTACT_RADIO_TILE}
	return {"pos": head_unit.transform * head_unit.off_point(), "contact": DriverModel.CONTACT_RADIO_KNOB}

## The one place a hand touching something has an effect.
func _on_hand_contact(target: StringName) -> void:
	if target == DriverModel.CONTACT_RADIO_TILE or target == DriverModel.CONTACT_RADIO_KNOB:
		var r := _find_radio()
		if r != null:
			r.next_station()
		head_unit.tap(target == DriverModel.CONTACT_RADIO_KNOB and head_unit.has_knob)
		_update_radio(0.0)

# ---------- gear lever and handbrake ----------

func _build_lever() -> void:
	lever = Node3D.new()
	lever.name = "Lever"
	lever.position = cab.lever
	var k := CockpitKit.new()
	k.cylinder(0.008, 0.0, LEVER_LEN - 0.02, Vector3.ZERO, SILVER, 8)
	k.cylinder(0.02, 0.0, 0.02, Vector3.ZERO, LEATHER, 8)   # boot collar
	lever.add_child(k.instance(CockpitKit.material(0.35, 0.7)))
	lever_knob = Node3D.new()
	lever_knob.name = "Knob"
	lever_knob.position = Vector3(0.0, LEVER_LEN, 0.0)
	lever.add_child(lever_knob)
	add_child(lever)
	# one head per gearbox mode on the same knob point (the hand's target), and
	# the pattern printed on the console behind the boot; set_lever_mode shows one
	var mat := CockpitKit.material(0.6, 0.2)
	var h := CockpitKit.new()   # MANUAL: leather knob, silver top
	h.box(Vector3(0.040, 0.046, 0.040), Vector3.ZERO, LEATHER)
	h.box(Vector3(0.028, 0.004, 0.028), Vector3(0.0, 0.025, 0.0), SILVER)
	var s := CockpitKit.new()   # SEMI: taller sequential grip, silver collar
	s.cylinder(0.019, -0.03, 0.035, Vector3.ZERO, LEATHER, 10)
	s.cylinder(0.021, -0.034, -0.026, Vector3.ZERO, SILVER, 10)
	var a := CockpitKit.new()   # AUTO: T-handle with the lock button
	a.box(Vector3(0.066, 0.030, 0.034), Vector3(0.0, 0.004, 0.0), LEATHER)
	a.box(Vector3(0.012, 0.006, 0.014), Vector3(-0.02, 0.021, 0.0), SILVER)
	var heads := {
		PlayerCar.Transmission.MANUAL: [h, "KnobH", gate_pattern(player.gear_ratios.size())],
		PlayerCar.Transmission.SEMI: [s, "KnobSeq", "−\n+"],
		PlayerCar.Transmission.AUTO: [a, "KnobAuto", "R\nN\nD"],
	}
	for m in heads:
		var mi: MeshInstance3D = (heads[m][0] as CockpitKit).instance(mat, heads[m][1])
		lever_knob.add_child(mi)
		_lever_heads[m] = mi
		var l := _label(heads[m][2], 40, lever.position + Vector3(0.05, 0.004, 0.0), SILVER, 0.0005)
		l.name = "Gate" + (heads[m][1] as String).trim_prefix("Knob")
		l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # flat on the console, top line forward
		_gate_labels[m] = l

func _build_handbrake() -> void:
	handbrake = Node3D.new()
	handbrake.name = "Handbrake"
	handbrake.position = cab.handbrake
	var k := CockpitKit.new()
	k.box(Vector3(0.024, 0.024, 0.22), Vector3(0.0, 0.012, -0.11), TRIM)
	k.box(Vector3(0.034, 0.034, 0.08), Vector3(0.0, 0.017, -0.21), LEATHER)
	k.box(Vector3(0.016, 0.010, 0.016), Vector3(0.0, 0.034, -0.24), SILVER)     # release button
	handbrake.add_child(k.instance(CockpitKit.material(0.6, 0.3)))
	add_child(handbrake)

## Shows the lever for a gearbox mode (PlayerCar.Transmission) and puts it in
## that mode's slot for the current gear, with no move.
func set_lever_mode(mode: int) -> void:
	lever_mode = mode
	for m in _lever_heads:
		(_lever_heads[m] as Node3D).visible = m == mode
		(_gate_labels[m] as Node3D).visible = m == mode
	_lever_path.clear()
	_lever_wait = 0.0
	lever_moving = false
	_lever_gear = player.gear
	_lever_pos = _slot_of(player.gear)
	_apply_lever(_lever_pos)

## H-gate columns for a gearbox with this many forward gears: two gears each.
static func gate_columns(forward_gears: int) -> int:
	return maxi((forward_gears + 1) / 2, 1)

## The pattern printed on the console for the MANUAL H-gate: odd gears on the
## top line, even gears and R below, R right of the last column. An odd gear
## count leaves the last bottom slot blank, so R still sits where the lever goes.
static func gate_pattern(forward_gears: int) -> String:
	var top: PackedStringArray = []
	var bottom: PackedStringArray = []
	for c in gate_columns(forward_gears):
		top.append(str(2 * c + 1))
		bottom.append(str(2 * c + 2) if 2 * c + 2 <= forward_gears else "  ")
	bottom.append("R")
	return " ".join(top) + "\n" + " ".join(bottom)

## The slot of a gear as (column, row), row -1 forward and +1 back, in the
## current lever mode. MANUAL, the H-gate: odd gears forward, even gears and
## reverse back, 0 the neutral gate, reverse right of the last column. SEMI:
## the sequential stick rests in the centre in every gear. AUTO: one column,
## R forward, N, D back.
func _slot_of(g: int) -> Vector2:
	if lever_mode == PlayerCar.Transmission.SEMI:
		return Vector2.ZERO
	if lever_mode == PlayerCar.Transmission.AUTO:
		return Vector2(0.0, signf(float(g)))
	if g == 0:
		return Vector2.ZERO
	var n_cols := gate_columns(player.gear_ratios.size())
	if g < 0:
		return Vector2(float(n_cols) - float(n_cols - 1) / 2.0, 1.0)
	var col := float((g - 1) / 2) - float(n_cols - 1) / 2.0
	return Vector2(col, -1.0 if g % 2 == 1 else 1.0)

## Lever tilt from a slot position (slot units -> degrees).
func _apply_lever(p: Vector2) -> void:
	lever.rotation_degrees = Vector3(p.y * LEVER_ROW_TILT, 0.0, -p.x * LEVER_COL_TILT)

## Start moving the lever to a gear, through the neutral gate like a hand would.
## SEMI: a tap instead, back for an upshift and forward for a downshift, then
## back to the centre, after SEQ_WAIT so the driver's hand is on it first.
func move_lever_to(g: int) -> void:
	var to := _slot_of(g)
	_lever_path.clear()
	if lever_mode == PlayerCar.Transmission.SEMI:
		_lever_path.append(Vector2(0.0, 1.0 if g > _lever_gear else -1.0))
		_lever_path.append(Vector2.ZERO)
		_lever_wait = SEQ_WAIT
		_lever_gear = g
		lever_moving = true
		return
	if _lever_pos.y != 0.0:
		_lever_path.append(Vector2(_lever_pos.x, 0.0))
	if to.x != _lever_pos.x:
		_lever_path.append(Vector2(to.x, 0.0))
	_lever_path.append(to)
	_lever_gear = g
	lever_moving = true

func lever_knob_position() -> Vector3:
	return lever_knob.global_position

func _step_lever(delta: float) -> void:
	if _lever_path.is_empty():
		lever_moving = false
		return
	if _lever_wait > 0.0:
		_lever_wait -= delta
		return
	var next := _lever_path[0]
	_lever_pos = _lever_pos.move_toward(next, LEVER_SPEED * delta)
	if _lever_pos.is_equal_approx(next):
		_lever_path.remove_at(0)
	_apply_lever(_lever_pos)

# ---------- pedals ----------

func _build_pedals() -> void:
	var at: Vector3 = cab.pedals   # the throttle pivot; brake and clutch step 12 cm left each
	for p in [["throttle", 0.0, 0.045, 0.10], ["brake", -0.12, 0.065, 0.075], ["clutch", -0.24, 0.060, 0.075]]:
		var pivot := Node3D.new()
		pivot.name = String(p[0]).capitalize() + "Pedal"
		pivot.position = at + Vector3(p[1], 0.0, 0.0)
		var k := CockpitKit.new()
		k.box(Vector3(0.018, 0.17, 0.012), Vector3(0.0, -0.085, 0.0), TRIM)
		k.box(Vector3(p[2], p[3], 0.012), Vector3(0.0, -0.17, 0.004), PLASTIC_LIGHT)
		pivot.add_child(k.instance(CockpitKit.material(0.7, 0.3)))
		add_child(pivot)
		pedals[p[0]] = pivot

## Pedal travel 0..1 as it reads from the car.
func pedal_inputs() -> Dictionary:
	var clutch: float
	if player.realistic_clutch:
		clutch = maxf(player.clutch_input, player.clutch_pedal)
	else:
		clutch = player.clutch_amount   # the automatic clutch opens during a shift
	return {"throttle": clampf(player.throttle_amount, 0.0, 1.0), "brake": clampf(player.brake_amount, 0.0, 1.0), "clutch": clampf(clutch, 0.0, 1.0)}

# ---------- cabin light ----------

func _build_light() -> void:
	cabin_light = OmniLight3D.new()
	cabin_light.name = "CabinLight"
	cabin_light.position = (cab.eye as Vector3) + Vector3(0.3, -0.10, -0.25)
	cabin_light.light_color = AMBER
	cabin_light.light_energy = 1.1   # a touch more than the interior branch: the driver shows through the glass
	cabin_light.omni_range = 2.2
	cabin_light.omni_attenuation = 1.2
	cabin_light.shadow_enabled = false
	cabin_light.light_cull_mask = INTERIOR_BIT | DRIVER_BIT
	add_child(cabin_light)

# ---------- per frame ----------

## The drawn wheel chases steering * WHEEL_LOCK_RAD: a spring with its speed
## capped, clamped at lock. Semi-implicit Euler in substeps of at most
## WHEEL_SUBSTEP, so a long frame (a hitch, a loaded machine) cannot make the
## spring overshoot or blow up.
const WHEEL_SUBSTEP := 1.0 / 120.0
func _step_wheel(delta: float) -> void:
	var target := clampf(steering, -1.0, 1.0) * WHEEL_LOCK_RAD
	var w := TAU * WHEEL_SPRING_HZ
	var vmax := deg_to_rad(WHEEL_RATE_DEG)
	var n := maxi(int(ceil(delta / WHEEL_SUBSTEP)), 1)
	var h := delta / n
	for i in n:
		_wheel_vel += (w * w * (target - wheel_angle) - 2.0 * WHEEL_DAMPING * w * _wheel_vel) * h
		_wheel_vel = clampf(_wheel_vel, -vmax, vmax)
		wheel_angle += _wheel_vel * h
		if absf(wheel_angle) >= WHEEL_LOCK_RAD:
			wheel_angle = clampf(wheel_angle, -WHEEL_LOCK_RAD, WHEEL_LOCK_RAD)
			_wheel_vel = 0.0
	wheel.set_angle(wheel_angle)

## The rim's speed right now, radians per second (the hands pace their slides on it).
func wheel_rate() -> float:
	return _wheel_vel

func _process(delta: float) -> void:
	if not visible:
		return
	var p := player
	var max_rpm := maxf(p.max_rpm, 1.0)
	var frac := clampf(p.motor_rpm / max_rpm, 0.0, 1.0)
	var cue := Hud.shift_cue(p, frac)
	var blink := Hud.blink()
	_step_wheel(delta)
	wheel.update(frac, cue, blink, p.motor_rpm, Hud.kmh(p.current_speed()), Hud.gear_text(p.gear))
	var rest := dial_sweep * 0.5   # the needle points at the first tick (lower left, or the band's left end)
	tach_needle.rotation = Vector3(0.0, 0.0, deg_to_rad(rest - dial_sweep * frac))
	var kmh := clampf(absf(p.current_speed()) * Hud.KMH_PER_MS / float(cab.speedo_max_kmh), 0.0, 1.0)
	speedo_needle.rotation = Vector3(0.0, 0.0, deg_to_rad(rest - dial_sweep * kmh))
	_update_lamps()
	_update_pod(delta)
	var inputs := pedal_inputs()
	for key in pedals:
		(pedals[key] as Node3D).rotation_degrees = Vector3(PEDAL_TRAVEL_DEG * float(inputs[key]), 0.0, 0.0)
	handbrake.rotation_degrees = Vector3(28.0 * clampf(p.handbrake_input, 0.0, 1.0), 0.0, 0.0)
	# The lever follows the gearbox mode (G cycles it in the game).
	if p.transmission_mode() != lever_mode:
		set_lever_mode(p.transmission_mode())
	if p.automatic_transmission:
		# the box shifts itself: paddle flicks on the wheel, the selector only
		# moves between R, N and D
		if p.gear != _last_gear:
			wheel.flick(1 if p.gear > _last_gear else -1)
			_last_gear = p.gear
		if not lever_moving and _lever_gear != p.gear:
			if _slot_of(p.gear) != _slot_of(_lever_gear):
				move_lever_to(p.gear)
			else:
				_lever_gear = p.gear
	else:
		# Manual and semi: the lever starts for the requested gear the moment
		# the shift starts (the driver's hand rides it through the shift_time),
		# and is set straight on gear changes that skip is_shifting (out of neutral).
		if p.is_shifting and _lever_gear != p.requested_gear:
			move_lever_to(p.requested_gear)
		if p.gear != _last_gear:
			if _lever_gear != p.gear:
				move_lever_to(p.gear)
			_last_gear = p.gear
		if _lever_gear != p.gear and not lever_moving and not p.is_shifting:
			move_lever_to(p.gear)
	_step_lever(delta)
	_update_radio(delta)

func _update_lamps() -> void:
	var h := player.health
	var on := [
		[h.is_warning(PowertrainHealth.Warn.ENG), h.is_warning(PowertrainHealth.Warn.ENG_DERATE)],
		[h.is_warning(PowertrainHealth.Warn.BRK), h.is_warning(PowertrainHealth.Warn.BRK_FADE)],
		[h.is_warning(PowertrainHealth.Warn.TYRE), false],
		[h.is_warning(PowertrainHealth.Warn.CLUTCH), false],
	]
	var slow_blink := int(Time.get_ticks_msec() / 350) % 2 == 0
	for i in 4:
		var lit: bool = on[i][0] and (not on[i][1] or slow_blink)
		var c: Color = RED if on[i][1] else AMBER
		lamps.multimesh.set_instance_color(i, Color(c, 1.0 if lit else 0.0))

## The AFR/PSI gauge pod (GaugePod) comes free with the car's first boost
## setup (Roy, 2026-10-09): it is fitted the moment the car has one, stock or
## from the Tuner, and stays bolted on after. The PSI face is scaled to the
## setup, so a bigger turbo later swaps the pod for one with the right range.
func _update_pod(delta: float) -> void:
	var p := player
	if GaugeReadouts.has_pod(p) and (pod == null or p.turbo_boost_max > pod.boost_max):
		if pod != null:
			pod.queue_free()
		pod = GaugePod.new(PlayerCar.chassis_kind(), p.turbo_boost_max)
		add_child(pod)
	if pod != null:
		pod.update(p, delta)

func _find_radio() -> RadioManager:
	if radio == null and is_inside_tree():
		var scene := get_tree().current_scene
		if scene != null and scene.get("radio") is RadioManager:
			radio = scene.radio
	return radio

## Crossing into a new district run puts its name on the head unit for a few
## seconds (world step 4, "Names you can read"). The first run seen, at the
## start of a drive or after a resume, shows nothing.
func _update_area() -> void:
	if player == null or head_unit == null or not is_instance_valid(player):
		return
	var s := RoadFrame.s_at(RoadFrame.unroll(player.global_position).z)
	var run := Districts.run_of(maxi(floori(s / RoadChunkBuilder.CHUNK_LEN), 0))
	if _area_run >= 0 and run != _area_run:
		head_unit.show_area(PlaceNames.area_name(Districts.name_of_run(run)))
	_area_run = run

func _update_radio(delta: float) -> void:
	_update_area()
	# The car clock (NightClock) is drawn on the head unit's screen.
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene != null and scene.get("night_clock") is NightClock:
		head_unit.show_clock(scene.night_clock.text())
	var r := _find_radio()
	if r == null:
		return
	var bus := AudioServer.get_bus_index(&"Music")
	var lvl := 0.0
	if bus >= 0 and r.station >= 0:
		var db := maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0))
		lvl = clampf((db + 36.0) / 36.0, 0.0, 1.0)
	head_unit.show_state(r.station, r.now_playing, lvl, delta)

## Triangles drawn by the cabin (static meshes, wheel, moving parts, mirrors).
func triangle_count() -> int:
	var n := 0
	for m in find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (m as MeshInstance3D).mesh
		if mesh is ArrayMesh:
			for s in mesh.get_surface_count():
				n += (mesh as ArrayMesh).surface_get_array_len(s) / 3
		elif mesh is QuadMesh:
			n += 2
	n += 12 * (SteeringWheel.LED_COUNT + 4 + 4)
	return n
