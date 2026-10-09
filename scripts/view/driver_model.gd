class_name DriverModel
extends Node3D

# The driver (cockpit milestone 2, 2026-10-06): a low-poly humanoid built from
# code in the PS2 way, rigid segments, no skinning. Seated in the driver's seat
# of the CockpitFrame (car space): head with a cap, torso in a dark jacket with
# sodium shoulder stripes, legs in dark jeans, boots on the pedals, and a pair
# of floating gloved hands. No arms: Roy (2026-10-06) "fuck forearms", so the
# hands end in a clean closed cuff, like the first-person racers of the era,
# and nothing reaches up across the view. The glove style follows the car
# (GLOVE_STYLES by PlayerCar.chassis_kind()). The right wrist wears a gold
# Cuban-link bracelet (Roy, same day), modelled as a ring of flat interlocking
# links over the cuff.
#
# Hands grip the wheel rim at the car's grip height (the spec's driver_grip_deg,
# nine and three by default) and steer it push-pull like a driving-school
# driver (2026-10-09, Roy: "hands higher, continuous rolling"): a gripping hand
# rides the rim; when it runs out of room (the top of its range is the
# sightline cap, the bottom is the flat of the wheel) it lets go, slides back
# along the rim to the far end of its range while the other hand keeps pulling,
# and grips again. With the wheel still the free hands settle where they are,
# and once the wheel is near straight both drift back to their grip points.
# The wheel itself rolls through CockpitFrame's spring (never snaps to lock).
# Legs: analytic two-bone IK
# from the hips to the pedals (right foot throttle or brake, whichever is
# pressed; left foot on the clutch with the clutch model on, else on the dead
# pedal).
#
# Animations are a small state machine on the right hand, all procedural and
# interruptible, driven by what the car and radio actually do (not by keys):
#   - manual gear change: when the lever starts moving (CockpitFrame follows
#     the vehicle's requested gear) the hand reaches the knob, rides it through
#     the gate and returns to the rim;
#   - automatic: a finger flick on the paddle (right on an upshift, left on a
#     downshift), hands stay on the rim;
#   - radio (touch screen, 2026-10-07): the next-station key only asks
#     (request_radio); the hand reaches the HeadUnit, taps the next tile (past
#     the last one it presses the knob: off) and returns. The station changes
#     on the finger's contact, not on the key: CockpitFrame runs
#     RadioManager.next_station() from hand_contact. Requests wait while a
#     shift or handbrake pull has the hand;
#   - handbrake: while the handbrake is pulled the hand holds the lever and
#     rides it up and down, then returns to the rim;
#   - steering: a small head yaw into the turn and a body lean from lateral g;
#   - window (2026-10-09, the left hand's one job): while the window is being
#     worked (CockpitFrame.window_direction, from the Z key) the left hand
#     leaves the rim for the door: on a crank car it holds the crank's knob
#     and rides it round as the glass moves, on a switch car it rests on the
#     armrest with the thumb on the rocker; back to the rim once the window
#     has stopped;
#   - idle: breathing, and a head bob from the road.
# Hand contact: one mechanism for every reach. The moment the hand arrives (the
# knob, the handbrake grip) or the finger lands (the screen, the radio knob),
# _contact() emits hand_contact(target); whatever the touch does hangs off that.
# In the cockpit view the head and torso are hidden (the camera is the head);
# in the chase view the whole driver shows through the glass. The hands never
# rise above HAND_TOP_MIN_DEG below the eye, so the road band stays clear
# (tests/view/cockpit_driver.gd).

const SKIN := Color("#B9896A")
const HAIR := Color("#2A1E16")
const CAP := Color("#1B1E25")
const JACKET := Color("#1E2229")
const JACKET_TRIM := Color("#FF8A1F")   # sodium
## Glove per car: colour of the glove and of the closed cuff at the wrist.
## Keyed by PlayerCar.chassis_kind(); DEFAULT_GLOVE for anything unlisted.
const GLOVE_STYLES := {
	"p1_coupe": {"glove": Color("#111216"), "cuff": Color("#8A5A2A")},   # black leather, dull amber band
	"test": {"glove": Color("#2A2E36"), "cuff": Color("#C9CED6")},       # grey fabric, silver band
}
const DEFAULT_GLOVE := "p1_coupe"
const GOLD := Color("#D9A441")
const JEANS := Color("#171C28")
const BOOT := Color("#121318")
const SOLE := Color("#2C3038")

## Hand space (see _hand_mesh): the wrist runs along +z; the cuff closes it.
## The cuff is glove-coloured with a thin band in the style's accent colour:
## its end cap faces the driver, so a bright cap read as a disc (first probe).
const WRIST_X := 0.03          # wrist centre, outward from the grip axis, times side
const CUFF_R := 0.031
const CUFF_Z0 := 0.065
const CUFF_Z1 := 0.095
const BAND_Z0 := 0.072
const BAND_Z1 := 0.082
## Cuban-link bracelet on the right wrist: LINKS flat oblong links around the
## cuff, each tilted the other way from its neighbour so they read as interlocked.
const LINKS := 8
const LINK_R := 0.037          # chain radius (just outside the cuff)
const LINK_Z := 0.088
const LINK_LEN := 0.028        # along the chain (links overlap: the pitch is 0.029)
const LINK_WIDE := 0.012       # across the chain
const LINK_BAR := 0.0045
const LINK_TILT_DEG := 35.0
const THIGH := 0.47
const SHIN := 0.45
## Where the hands hold the rim at rest, in degrees round the rim for the right
## hand (0 = 3 o'clock, up is positive; the left hand mirrors it about 12
## o'clock). Per car: the spec's "driver_grip_deg" (CarSpec), DEFAULT_GRIP_DEG
## when a car has none. A hand rides the rim between GRIP_LOW_DEG (onto the
## flat bottom) and GRIP_HIGH_DEG, the sightline cap: HAND_TOP_MIN_DEG is the
## budget from docs/planning/cockpit-interior-research-2026-10-06.md, no part
## of a hand above this many degrees below the eye, and GRIP_HIGH_DEG is as
## high as the gloves and cuffs allow under it (tests/view/cockpit_driver.gd and
## tests/view/cockpit_steering_hands.gd measure it). Past either end the hand lets
## go and shuffles (see _step_rim).
const DEFAULT_GRIP_DEG := 0.0
const GRIP_LOW_DEG := -55.0
const GRIP_HIGH_DEG := 21.0
const HAND_TOP_MIN_DEG := 18.0
## Shuffling: a free hand slides along the rim at least SLIDE_MIN_RATE deg/s
## and SLIDE_RATE_MULT times the rim's own speed, lifted SLIDE_LIFT off it
## toward the driver. Once the wheel has been still for REST_SECS and sits
## within HOME_WHEEL_DEG of straight, the hands drift home at HOME_RATE.
const SLIDE_MIN_RATE := 120.0
const SLIDE_RATE_MULT := 1.4
const SLIDE_LIFT := 0.008
const REST_SECS := 0.5
const HOME_WHEEL_DEG := 35.0
const HOME_RATE := 70.0
const STILL_RATE := 6.0          # deg/s: below this the wheel counts as still
## Seated geometry, car space: the pelvis pivot and the head on the torso.
const PELVIS := Vector3(CockpitFrame.SEAT_X, 0.50, 0.34)
const RECLINE_DEG := 12.0
const HEAD_Y := 0.49
const REACH_SECS := 0.22
const RETURN_SECS := 0.22
const PRESS_SECS := 0.12
const PADDLE_SECS := 0.25
const BRAKE_REACH_SECS := 0.20
const WINDOW_REACH_SECS := 0.25
const WINDOW_LINGER_SECS := 0.3   # the hand stays this long after the window stops
const HEAD_YAW_RAD := 0.20       # at full steer fraction
const LEAN_RAD_PER_G := 0.08
const HIP_HALF := 0.09

## hand_contact targets.
const CONTACT_GEAR := &"gear_knob"
const CONTACT_HANDBRAKE := &"handbrake"
const CONTACT_RADIO_TILE := &"radio_tile"
const CONTACT_RADIO_KNOB := &"radio_knob"
## Next-station presses that may wait for the hand at once (more are dropped).
const MAX_RADIO_REQUESTS := 4

## The right hand touched something (one of the CONTACT_ names).
signal hand_contact(target: StringName)

enum Act { GRIP, SHIFT_REACH, SHIFT_HOLD, SHIFT_RETURN, RADIO_REACH, RADIO_PRESS, RADIO_RETURN, BRAKE_REACH, BRAKE_HOLD, BRAKE_RETURN }

var frame: CockpitFrame
var player: PlayerCar
var torso: Node3D            # pivot at the pelvis, reclined like the seat
var torso_mesh: MeshInstance3D
var head: Node3D             # on the neck, yaws into turns
var head_mesh: MeshInstance3D
var hands := {}              # side (-1 left, +1 right) -> MeshInstance3D
var bracelet: MeshInstance3D # on the right hand
var legs := {}               # side -> {thigh, shin, foot}
var glove_style := DEFAULT_GLOVE
var grip_deg := DEFAULT_GRIP_DEG   # this car's rest grip, right hand
## Per hand (side -> {}): "w" the hand's angle round the rim in car space
## (degrees, 0 = 3 o'clock, up positive, unwrapped), "rim" its angle on the
## rim itself (turns with the wheel), "grip" true while it holds the rim,
## "lift" 0..1 how far it is lifted off the rim while sliding, "home" true
## while it is only drifting back to its grip point (it grabs the moment the
## wheel moves again).
var _rim := {}
var _prev_wheel_deg := 0.0
var _wheel_dir := 0              # -1 / +1 the way the wheel last turned, 0 still
var _wheel_rate_deg := 0.0       # the rim's speed this frame, deg/s, as the hands saw it
var _still := 0.0                # seconds the wheel has been still
var shuffle_count := 0           # hands that let go to shuffle (tests)
var act := Act.GRIP
var act_t := 0.0
enum LeftAct { GRIP, WINDOW_REACH, WINDOW_HOLD, WINDOW_RETURN }
var left_act := LeftAct.GRIP
var left_t := 0.0
var _left_from := Transform3D()
var _left_xf := Transform3D()
var _window_idle := 0.0          # seconds since the window last moved
var radio_requests := 0          # next-station presses waiting for the hand
var contact_count := 0
var last_contact := &""
var _radio_target := Vector3.ZERO  # car space, where the finger lands this reach
var _radio_contact := &""
var _pressed := false              # the finger has landed this press
var _brake_was_on := false
var paddle_t := 0.0
var paddle_side := 0
var _hand_from := Transform3D()   # where the right hand left from, for blends
var _hand_xf := Transform3D()     # the right hand's transform this frame (car space)
var _last_gear := 0
var _lever_was_moving := false
var _lat_g := 0.0
var _head_bob := 0.0
var _prev_vy := 0.0
var _breath := 0.0
var _foot_target := Vector3.ZERO
var _mat: StandardMaterial3D
var tri_count := 0
## How far the shin ends fall short of the ankle targets (0 when the leg can
## reach), per side; tests read these.
var _leg_gap := {-1: 0.0, 1: 0.0}

func _init(cockpit: CockpitFrame) -> void:
	frame = cockpit
	player = cockpit.player
	name = "Driver"

func _ready() -> void:
	_mat = CockpitKit.material(0.9, 0.0, 0.05)
	var kind := PlayerCar.chassis_kind()
	glove_style = kind if GLOVE_STYLES.has(kind) else DEFAULT_GLOVE
	grip_deg = float(player.spec.get("driver_grip_deg", DEFAULT_GRIP_DEG))
	_reset_rim()
	_build_torso()
	_build_head()
	for side in [-1, 1]:
		hands[side] = _build_hand(side)
		legs[side] = _build_leg(side)
	_build_bracelet()
	for n in find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = CockpitFrame.DRIVER_BIT
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # visual only, no shadows on the car
	_last_gear = player.gear
	_hand_xf = _grip_transform(1)
	_left_xf = _grip_transform(-1)
	_foot_target = _pedal_ankle("throttle")

## Cockpit view: the camera is the head, so head and torso go.
func set_cockpit(on: bool) -> void:
	head.visible = not on
	torso_mesh.visible = not on

# ---------- building ----------

func _part(kit: CockpitKit, node_name: String, parent: Node = self) -> MeshInstance3D:
	tri_count += kit.tri_count()
	var mi := kit.instance(_mat, node_name)
	parent.add_child(mi)
	return mi

## A limb segment along +y from 0 to `len`, with a joint at the start.
static func _segment(kit: CockpitKit, len: float, r0: float, r1: float, col: Color, sides := 10) -> void:
	# tapered: two stacked cylinders
	kit.cylinder(r0, 0.0, len * 0.55, Vector3.ZERO, col, sides)
	kit.cylinder(r1, len * 0.5, len, Vector3.ZERO, col, sides)
	kit.cylinder(r0 * 1.05, -0.02, 0.02, Vector3.ZERO, col, 8)

func _build_torso() -> void:
	torso = Node3D.new()
	torso.name = "Torso"
	torso.position = PELVIS
	torso.rotation_degrees = Vector3(RECLINE_DEG, 0.0, 0.0)   # reclined with the seat
	add_child(torso)
	var k := CockpitKit.new()
	# pelvis and belly, chest, shoulders: boxes with a jacket colour, trim strips
	k.box(Vector3(0.36, 0.12, 0.24), Vector3(0.0, 0.06, 0.0), JEANS)
	k.box(Vector3(0.015, 0.05, 0.25), Vector3(0.0, 0.12, 0.0), SOLE)             # belt buckle line
	k.box(Vector3(0.38, 0.16, 0.24), Vector3(0.0, 0.20, 0.0), JACKET)
	k.box(Vector3(0.42, 0.12, 0.26), Vector3(0.0, 0.34, 0.0), JACKET)             # chest
	k.box(Vector3(0.46, 0.07, 0.24), Vector3(0.0, 0.41, 0.0), JACKET)             # shoulders
	k.box(Vector3(0.012, 0.26, 0.012), Vector3(0.0, 0.28, 0.13), SOLE)            # zip
	for sx in [-1.0, 1.0]:
		k.box(Vector3(0.05, 0.012, 0.25), Vector3(sx * 0.19, 0.45, 0.0), JACKET_TRIM)    # shoulder stripe
		k.box(Vector3(0.025, 0.07, 0.14), Vector3(sx * 0.10, 0.38, 0.13), JACKET_TRIM)   # chest flash
	k.box(Vector3(0.16, 0.04, 0.16), Vector3(0.0, 0.46, 0.0), JACKET)             # collar
	k.cylinder(0.045, 0.44, 0.50, Vector3.ZERO, SKIN, 8)                          # neck
	torso_mesh = _part(k, "TorsoMesh", torso)

func _build_head() -> void:
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, HEAD_Y, 0.0)
	torso.add_child(head)
	var k := CockpitKit.new()
	k.box(Vector3(0.17, 0.21, 0.19), Vector3(0.0, 0.105, 0.0), SKIN)
	k.box(Vector3(0.04, 0.05, 0.03), Vector3(0.0, 0.08, 0.105), SKIN)             # nose
	k.box(Vector3(0.18, 0.08, 0.20), Vector3(0.0, 0.17, -0.005), HAIR)            # hair
	k.box(Vector3(0.19, 0.045, 0.21), Vector3(0.0, 0.215, 0.0), CAP)              # cap
	k.box(Vector3(0.17, 0.012, 0.09), Vector3(0.0, 0.195, 0.14), CAP)             # peak
	k.box(Vector3(0.05, 0.02, 0.012), Vector3(0.0, 0.215, 0.106), JACKET_TRIM)    # cap mark
	for sx in [-1.0, 1.0]:
		k.box(Vector3(0.03, 0.012, 0.02), Vector3(sx * 0.04, 0.12, 0.096), HAIR)   # brows
		k.box(Vector3(0.025, 0.035, 0.015), Vector3(sx * 0.09, 0.09, 0.0), SKIN)   # ears
	head_mesh = _part(k, "HeadMesh", head)

func _build_hand(side: int) -> MeshInstance3D:
	var k := CockpitKit.new()
	_hand_mesh(k, side, GLOVE_STYLES[glove_style].glove, GLOVE_STYLES[glove_style].cuff)
	return _part(k, "Hand" + ("L" if side < 0 else "R"))

## A gloved mitten gripping a tube that runs along local y through the origin:
## the palm sits on the outer side (+x for the right hand at 3 o'clock, -x for
## the left at 9), fingers wrap round the dash side (-z), the thumb round the
## driver side (+z), the wrist runs toward the driver (+z) and ends in a closed
## cuff band. Hand space: x outward from the hub, y up the rim, z toward the driver.
static func _hand_mesh(k: CockpitKit, side: int, glove: Color, cuff: Color) -> void:
	var sx := float(side)
	k.box(Vector3(0.035, 0.085, 0.075), Vector3(sx * 0.038, 0.0, 0.01), glove)                 # palm
	k.box(Vector3(0.06, 0.08, 0.03), Vector3(sx * 0.012, 0.0, -0.038), glove)                  # fingers over the far side
	k.box(Vector3(0.03, 0.075, 0.03), Vector3(-sx * 0.028, 0.0, -0.030), glove)                # fingertips curling in
	k.box(Vector3(0.05, 0.028, 0.028), Vector3(sx * 0.008, 0.03, 0.036), glove)                # thumb
	k.box(Vector3(0.025, 0.028, 0.025), Vector3(-sx * 0.02, 0.03, 0.03), glove)                # thumb tip
	k.box(Vector3(0.05, 0.03, 0.07), Vector3(sx * WRIST_X, 0.0, 0.06), glove)                  # wrist, toward the driver
	# the closed cuff: a capped cylinder along +z around the wrist, nothing past
	# it, in the glove colour, with a thin accent band round it
	k.cylinder(CUFF_R, CUFF_Z0, CUFF_Z1, Vector3(sx * WRIST_X, 0.0, 0.0), glove, 10, Basis(Vector3.RIGHT, PI / 2.0))
	var band := CockpitKit.new()
	band.ring_sector(CUFF_R, CUFF_R + 0.003, 0.0, TAU, BAND_Z0, BAND_Z1, cuff, 10)
	band.offset(Vector3(sx * WRIST_X, 0.0, 0.0))
	k.merge(band)

## Gold Cuban-link bracelet round the right wrist (Roy, 2026-10-06): LINKS flat
## oblong links lying on the cuff, long side along the chain, each tilted the
## opposite way about the chain to its neighbour so they overlap like links.
## Its own mesh: a metallic gold material, not the matte cloth one.
func _build_bracelet() -> void:
	var k := CockpitKit.new()
	var centre := Vector3(WRIST_X, 0.0, LINK_Z)   # right hand: sx = +1
	for i in LINKS:
		var a := TAU * (float(i) + 0.5) / LINKS
		var radial := Vector3(cos(a), sin(a), 0.0)             # out from the wrist axis (z)
		var tangent := Vector3(-sin(a), cos(a), 0.0)           # along the chain
		var axis := Vector3(0.0, 0.0, 1.0)                     # along the wrist
		var tilt := deg_to_rad(LINK_TILT_DEG if i % 2 == 0 else -LINK_TILT_DEG)
		# link space: x along the chain, y along the wrist, z out from the wrist
		var b := Basis(tangent, axis, radial) * Basis(Vector3.RIGHT, tilt)
		var c := centre + radial * LINK_R
		var long := Vector3(LINK_LEN, LINK_BAR, LINK_BAR)
		var short := Vector3(LINK_BAR, LINK_WIDE + LINK_BAR, LINK_BAR)
		k.box(long, c + b * Vector3(0.0, LINK_WIDE * 0.5, 0.0), GOLD, b)
		k.box(long, c + b * Vector3(0.0, -LINK_WIDE * 0.5, 0.0), GOLD, b)
		k.box(short, c + b * Vector3(LINK_LEN * 0.5, 0.0, 0.0), GOLD, b)
		k.box(short, c + b * Vector3(-LINK_LEN * 0.5, 0.0, 0.0), GOLD, b)
	tri_count += k.tri_count()
	var gold := CockpitKit.material(0.3, 0.85, 0.7)
	bracelet = k.instance(gold, "Bracelet")
	(hands[1] as Node3D).add_child(bracelet)

func _build_leg(side: int) -> Dictionary:
	var th := CockpitKit.new()
	_segment(th, THIGH, 0.075, 0.06, JEANS)
	var sh := CockpitKit.new()
	_segment(sh, SHIN, 0.055, 0.045, JEANS)
	sh.box(Vector3(0.09, 0.05, 0.10), Vector3(0.0, 0.02, 0.0), JEANS)             # knee
	var ft := CockpitKit.new()
	# foot along -z from the ankle: boot and sole, toe up a little
	ft.box(Vector3(0.09, 0.07, 0.24), Vector3(0.0, -0.035, -0.09), BOOT)
	ft.box(Vector3(0.095, 0.02, 0.26), Vector3(0.0, -0.08, -0.10), SOLE)
	ft.box(Vector3(0.09, 0.08, 0.08), Vector3(0.0, -0.03, 0.02), BOOT)            # heel/ankle
	var thigh := _part(th, "Thigh" + ("L" if side < 0 else "R"))
	var shin := _part(sh, "Shin" + ("L" if side < 0 else "R"))
	var foot := _part(ft, "Foot" + ("L" if side < 0 else "R"))
	return {"thigh": thigh, "shin": shin, "foot": foot}

# ---------- IK ----------

## Two-bone IK: joint positions for a chain root -> elbow -> end reaching for
## `target`, bones l1 and l2, bending toward `pole`. Returns [elbow, end].
static func two_bone(root: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Array:
	var d := target - root
	var dist := d.length()
	if dist < 1e-5:
		return [root + Vector3.UP * l1, root]
	var dir := d / dist
	var reach := clampf(dist, absf(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	var cos_a := (l1 * l1 + reach * reach - l2 * l2) / (2.0 * l1 * reach)
	var a := acos(clampf(cos_a, -1.0, 1.0))
	var side := pole - dir * pole.dot(dir)
	if side.length_squared() < 1e-8:
		side = dir.cross(Vector3.UP)
	side = side.normalized()
	var elbow := root + (dir * cos(a) + side * sin(a)) * l1
	var end := root + dir * reach
	return [elbow, end]

## Points a segment node (mesh along +y) from `from` toward `to`, car space.
func _aim(node: Node3D, from: Vector3, to: Vector3, hint: Vector3) -> void:
	var y := (to - from).normalized()
	var x := hint.cross(y)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	node.transform = Transform3D(Basis(x, y, z), from)

func _hip(side: int) -> Vector3:
	return torso.transform * Vector3(float(side) * HIP_HALF, 0.02, 0.0)

## Where a hand is on the rim this frame, car space: the rim point at its
## car-space angle (see _rim), lifted a little while it slides. Hand space as
## in _hand_mesh (x outward, y up the rim, z toward the driver).
func _grip_transform(side: int) -> Transform3D:
	var wheel := frame.wheel
	var h: Dictionary = _rim[side]
	# the wheel turns the rim by -angle about its z, so on the rim the hand is
	# at its car-space angle plus the wheel angle
	var local_deg: float = h.w + rad_to_deg(wheel.angle)
	var p := wheel.rim_point(local_deg) + Vector3(0.0, 0.0, SLIDE_LIFT * h.lift)
	# the mesh is already mirrored for the left hand, so both hands use the
	# wheel's axes at 3 or 9 o'clock, turned round the rim to the grip
	var base := 0.0 if side > 0 else 180.0
	var local_xf := Transform3D(Basis(Vector3.BACK, deg_to_rad(local_deg - base)), p)
	return _wheel_to_car(local_xf)

## A hand's rest angle round the rim, car space (the left mirrors the right).
func home_deg(side: int) -> float:
	return grip_deg if side > 0 else 180.0 - grip_deg

## The angles a hand may hold the rim at, car space: [low, high] in the
## direction of its own w (the right hand's low end is the flat bottom, the
## left hand's low end is its sightline cap, since its w runs the other way).
static func rim_range(side: int) -> Array:
	if side > 0:
		return [GRIP_LOW_DEG, GRIP_HIGH_DEG]
	return [180.0 - GRIP_HIGH_DEG, 180.0 - GRIP_LOW_DEG]

## Both hands home on the rim, gripping.
func _reset_rim() -> void:
	for side in [-1, 1]:
		_rim[side] = {"w": home_deg(side), "rim": home_deg(side) + rad_to_deg(frame.wheel.angle), "grip": true, "lift": 0.0, "home": false}
	_prev_wheel_deg = rad_to_deg(frame.wheel.angle)

## Push-pull steering, one step. The wheel angle is read, never set: the hands
## follow it. A gripping hand rides the rim (its w = rim - wheel). Turning:
## a gripping hand that reaches the end of its range lets go, if the other hand
## is holding on, and slides to the far end of its range (its ready point); a
## sliding hand grips as it gets there, or at once if the wheel reverses. If
## the other hand is not holding on, the rim slips through this one instead
## (it stays clamped at the end of its range) so a hand is always on the
## wheel. Still: sliding hands settle where they are; after REST_SECS near
## straight both drift back to their grip points. Angles in degrees.
func _step_rim(delta: float) -> void:
	var wheel_deg := rad_to_deg(frame.wheel.angle)
	var rate := (wheel_deg - _prev_wheel_deg) / maxf(delta, 1e-4)
	_prev_wheel_deg = wheel_deg
	_wheel_rate_deg = rate
	var moving := absf(rate) > STILL_RATE
	var dir := int(signf(rate)) if moving else 0
	var reversed := moving and _wheel_dir != 0 and dir != _wheel_dir
	if moving:
		_wheel_dir = dir
	_still = 0.0 if moving else _still + delta
	# gripping hands ride the rim
	for side in [-1, 1]:
		var h: Dictionary = _rim[side]
		if h.grip:
			h.w = h.rim - wheel_deg
	if moving:
		# the wheel turning right (dir +1) carries every gripping hand toward
		# lower w; the ready point for a free hand is the end it is carried from
		for side in [-1, 1]:
			var h: Dictionary = _rim[side]
			var other: Dictionary = _rim[-side]
			var span := rim_range(side)
			var run_out: float = span[0] if dir > 0 else span[1]
			var ready: float = span[1] if dir > 0 else span[0]
			if h.grip:
				var past: bool = (h.w < run_out) if dir > 0 else (h.w > run_out)
				if past:
					if other.grip:
						h.grip = false       # let go and shuffle
						shuffle_count += 1
					h.w = run_out            # slip: the rim slides through
					h.rim = h.w + wheel_deg
			if not h.grip:
				if reversed or h.home:
					_grab(h, wheel_deg)      # the wheel came back, or moved while the hand was drifting home: hold it here
					continue
				var slide := maxf(absf(rate) * SLIDE_RATE_MULT, SLIDE_MIN_RATE)
				h.w = move_toward(h.w, ready, slide * delta)
				if absf(h.w - ready) < 1e-3:
					_grab(h, wheel_deg)
	else:
		var go_home := _still > REST_SECS and absf(wheel_deg) < HOME_WHEEL_DEG
		for side in [-1, 1]:
			var h: Dictionary = _rim[side]
			var home := home_deg(side)
			if go_home and absf(h.w - home) > 1e-3:
				h.grip = false
				h.home = true
				h.w = move_toward(h.w, home, HOME_RATE * delta)
				h.rim = h.w + wheel_deg
				if absf(h.w - home) < 1e-3:
					_grab(h, wheel_deg)
			elif not h.grip:
				_grab(h, wheel_deg)          # the wheel stopped: hold it here
	for side in [-1, 1]:
		var h: Dictionary = _rim[side]
		h.lift = lerpf(h.lift, 0.0 if h.grip else 1.0, 1.0 - exp(-18.0 * delta))

static func _grab(h: Dictionary, wheel_deg: float) -> void:
	h.grip = true
	h.home = false
	h.rim = h.w + wheel_deg

## Wheel space -> car space (the frame is at the car's origin).
func _wheel_to_car(local_xf: Transform3D) -> Transform3D:
	return frame.wheel_mount.transform * frame.wheel.transform * local_xf

## The right hand on the gear knob, car space.
func _lever_hand_transform() -> Transform3D:
	var knob := frame.lever.transform * frame.lever_knob.position
	var b := Basis(Vector3.BACK, deg_to_rad(-90.0))   # palm down over the knob, fingers forward
	return Transform3D(b, knob + Vector3(0.0, 0.035, 0.0))

## The right hand on the handbrake grip, car space: palm down over the lever,
## thumb inboard, riding the lever's lift.
func _brake_hand_transform() -> Transform3D:
	var lever: Node3D = frame.handbrake
	var b := Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0))
	return lever.transform * Transform3D(b, Vector3(0.0, 0.047, -0.21))

## The right hand pressing the head unit at _radio_target, car space: at
## pressed = 1 the fingertips touch the glass (or the knob face).
func _radio_hand_transform(pressed: float) -> Transform3D:
	var p := _radio_target + Vector3(0.0, -0.005, 0.075 - 0.02 * pressed)
	var b := Basis(Vector3.BACK, deg_to_rad(-90.0)) * Basis(Vector3.RIGHT, deg_to_rad(15.0))   # palm down, fingers at the buttons
	return Transform3D(b, p)

## A hand basis from where the palm faces and where the wrist points (car
## space), a proper rotation so the mirrored left mesh stays a left hand: the
## palm is on local sx*x, the wrist runs along local +z.
static func _hand_basis(side: int, palm: Vector3, wrist: Vector3) -> Basis:
	var x := (palm * float(side)).normalized()
	var z := (wrist - x * wrist.dot(x)).normalized()
	return Basis(x, z.cross(x), z)

## The left hand on the crank's peg knob, car space: fingers round the peg
## (which runs along x, into the cabin), the wrist up and back toward the
## shoulder. The knob orbits the hub as the crank turns; the hand goes with it.
func _crank_hand_transform() -> Transform3D:
	return Transform3D(_peg_basis(), frame.crank_knob_position())

## Basis for a hand round a peg along +x: local y along the peg, the wrist
## (local +z) up and back, the palm (local -x for the left hand) facing up and
## forward so the fingers curl under the peg.
static func _peg_basis() -> Basis:
	var y := Vector3.RIGHT
	var z := Vector3(0.0, 0.43, 0.90).normalized()
	return Basis(y.cross(z), y, z)

## The left hand resting palm down on the armrest with the thumb on the
## rocker, car space; at pressed = 1 the thumb's underside is on the switch.
func _switch_hand_transform(pressed: float) -> Transform3D:
	var b := _hand_basis(-1, Vector3.DOWN, Vector3(0.45, 0.0, 0.85))
	var thumb := Vector3(-0.033, 0.03, 0.036)   # the thumb's underside, hand space (left hand)
	var p := frame.switch_press_position() - b * thumb + Vector3(0.0, 0.012 * (1.0 - pressed), 0.0)
	return Transform3D(b, p)

## Ankle position for a pedal, car space: behind and a little below the pad.
func _pedal_ankle(pedal: String) -> Vector3:
	var pivot: Node3D = frame.pedals[pedal]
	var pad := pivot.transform * Vector3(0.0, -0.17, 0.004)
	return pad + Vector3(0.0, -0.03, 0.11)

func _dead_pedal_ankle() -> Vector3:
	return Vector3(-0.52, 0.33, -0.33)

# ---------- per frame ----------

func _process(delta: float) -> void:
	var p := player
	_breath += delta
	# lateral g from yaw rate x speed; vertical bob from the car's vertical acceleration
	var want_g := clampf(p.angular_velocity.y * p.current_speed() / 9.81, -1.2, 1.2)
	_lat_g = lerpf(_lat_g, want_g, 1.0 - exp(-6.0 * delta))
	var vy := p.linear_velocity.y
	var bob := clampf((vy - _prev_vy) / maxf(delta, 1e-4) * -0.0015, -0.012, 0.012)
	_prev_vy = vy
	_head_bob = lerpf(_head_bob, bob, 1.0 - exp(-14.0 * delta))
	# torso: recline, lean with lateral g, breathe
	torso.rotation = Vector3(deg_to_rad(RECLINE_DEG), 0.0, -_lat_g * LEAN_RAD_PER_G)
	torso.position = PELVIS + Vector3(0.0, 0.004 * sin(_breath * TAU * 0.25), 0.0)
	# head: yaw into the turn, bob
	var steer := frame.steering
	head.rotation = Vector3(0.0, lerp_angle(head.rotation.y, -steer * HEAD_YAW_RAD, 1.0 - exp(-5.0 * delta)), 0.0)
	head.position = Vector3(0.0, HEAD_Y + _head_bob, 0.0)

	_update_events()
	_step_rim(delta)
	_step_act(delta)
	_step_left(delta)
	_place_hands()
	_place_legs(delta)

## Watch the car and radio for things to animate.
func _update_events() -> void:
	var p := player
	if p.gear != _last_gear:
		if p.automatic_transmission:
			paddle_side = 1 if p.gear > _last_gear else -1
			paddle_t = PADDLE_SECS
		_last_gear = p.gear
	# Priority (sightline spec): handbrake > shift > radio. A higher request
	# takes the hand from a lower one mid-move, and a shift while the hand is
	# on its way back goes straight back to the knob; the radio press is
	# dropped (the station already changed), a shift under a held handbrake
	# moves the lever on its own.
	var moving := frame.lever_moving and not p.automatic_transmission
	if moving and not _lever_was_moving and not _is_brake() and act != Act.SHIFT_REACH and act != Act.SHIFT_HOLD:
		_start(Act.SHIFT_REACH)
	_lever_was_moving = moving
	var brake_on := p.handbrake_input > 0.5
	if brake_on and not _brake_was_on and not _is_brake():
		_start(Act.BRAKE_REACH)
	_brake_was_on = brake_on

## Next station asked for (the key): the hand goes when it is free.
func request_radio() -> void:
	radio_requests = mini(radio_requests + 1, MAX_RADIO_REQUESTS)

## Starts a reach for the screen: picks the touch point now (the next tile, or
## the knob past the last one) so the hand flies to where the tap will land.
func _begin_radio() -> void:
	radio_requests -= 1
	var touch := frame.radio_touch()
	_radio_target = touch.pos
	_radio_contact = touch.contact
	_pressed = false
	_start(Act.RADIO_REACH)

## The hand touched target: the one place contacts are announced.
func _contact(target: StringName) -> void:
	contact_count += 1
	last_contact = target
	hand_contact.emit(target)

func _is_radio() -> bool:
	return act == Act.RADIO_REACH or act == Act.RADIO_PRESS or act == Act.RADIO_RETURN

func _is_brake() -> bool:
	return act == Act.BRAKE_REACH or act == Act.BRAKE_HOLD

func _start(a: Act) -> void:
	act = a
	act_t = 0.0
	_hand_from = _hand_xf

## Blend weight with ease in/out.
static func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

## Advances the right hand's state machine and sets _hand_xf (car space).
func _step_act(delta: float) -> void:
	act_t += delta
	var grip := _grip_transform(1)
	match act:
		Act.GRIP:
			_hand_xf = grip
			if paddle_t > 0.0:
				# finger flick: the hand tips toward the paddle behind the rim and back
				paddle_t = maxf(paddle_t - delta, 0.0)
				var k := sin(paddle_t / PADDLE_SECS * PI)
				_hand_xf = grip * Transform3D(Basis(Vector3.UP, 0.35 * k), Vector3(0.0, 0.0, -0.012 * k))
			if radio_requests > 0:
				_begin_radio()
			elif player.handbrake_input > 0.5:
				_start(Act.BRAKE_REACH)   # pulled while the hand was busy, still held
		Act.SHIFT_REACH:
			var t := clampf(act_t / REACH_SECS, 0.0, 1.0)
			_hand_xf = _hand_from.interpolate_with(_lever_hand_transform(), _ease(t))
			if t >= 1.0:
				_contact(CONTACT_GEAR)
				_start(Act.SHIFT_HOLD)
		Act.SHIFT_HOLD:
			_hand_xf = _lever_hand_transform()
			if (not frame.lever_moving) or act_t > 0.8:
				_start(Act.SHIFT_RETURN)
		Act.SHIFT_RETURN:
			var t := clampf(act_t / RETURN_SECS, 0.0, 1.0)
			_hand_xf = _hand_from.interpolate_with(grip, _ease(t))
			if t >= 1.0:
				_start(Act.GRIP)
		Act.RADIO_REACH:
			var t := clampf(act_t / (REACH_SECS + 0.08), 0.0, 1.0)
			_hand_xf = _hand_from.interpolate_with(_radio_hand_transform(0.0), _ease(t))
			if t >= 1.0:
				_start(Act.RADIO_PRESS)
		Act.RADIO_PRESS:
			var t := clampf(act_t / PRESS_SECS, 0.0, 1.0)
			_hand_xf = _radio_hand_transform(sin(t * PI))
			if t >= 0.5 and not _pressed:
				_pressed = true
				_contact(_radio_contact)   # the station changes here
			if t >= 1.0:
				if radio_requests > 0 and not (frame.lever_moving and not player.automatic_transmission):
					_begin_radio()   # another press waiting: on to the next tile
				else:
					_start(Act.RADIO_RETURN)
		Act.RADIO_RETURN:
			var t := clampf(act_t / (RETURN_SECS + 0.08), 0.0, 1.0)
			_hand_xf = _hand_from.interpolate_with(grip, _ease(t))
			if t >= 1.0:
				_start(Act.GRIP)
		Act.BRAKE_REACH:
			var t := clampf(act_t / BRAKE_REACH_SECS, 0.0, 1.0)
			_hand_xf = _hand_from.interpolate_with(_brake_hand_transform(), _ease(t))
			if t >= 1.0:
				_contact(CONTACT_HANDBRAKE)
				_start(Act.BRAKE_HOLD)
		Act.BRAKE_HOLD:
			_hand_xf = _brake_hand_transform()
			if player.handbrake_input <= 0.5:
				_start(Act.BRAKE_RETURN)
		Act.BRAKE_RETURN:
			var t := clampf(act_t / RETURN_SECS, 0.0, 1.0)
			_hand_xf = _hand_from.interpolate_with(grip, _ease(t))
			if t >= 1.0:
				_start(Act.GRIP)

## The left hand: on the rim, except while the window is being worked.
func _step_left(delta: float) -> void:
	left_t += delta
	var grip := _grip_transform(-1)
	var working := frame.window_direction != 0
	_window_idle = 0.0 if working else _window_idle + delta
	var crank := frame.window_control == "crank"
	match left_act:
		LeftAct.GRIP:
			_left_xf = grip
			if working:
				_start_left(LeftAct.WINDOW_REACH)
		LeftAct.WINDOW_REACH:
			var t := clampf(left_t / WINDOW_REACH_SECS, 0.0, 1.0)
			var to := _crank_hand_transform() if crank else _switch_hand_transform(0.0)
			_left_xf = _left_from.interpolate_with(to, _ease(t))
			if t >= 1.0:
				_start_left(LeftAct.WINDOW_HOLD)
		LeftAct.WINDOW_HOLD:
			if crank:
				_left_xf = _crank_hand_transform()
			else:
				_left_xf = _switch_hand_transform(1.0 if working else 0.0)
			if _window_idle > WINDOW_LINGER_SECS:
				_start_left(LeftAct.WINDOW_RETURN)
		LeftAct.WINDOW_RETURN:
			var t := clampf(left_t / RETURN_SECS, 0.0, 1.0)
			_left_xf = _left_from.interpolate_with(grip, _ease(t))
			if working:
				_start_left(LeftAct.WINDOW_REACH)   # the key again on the way back
			elif t >= 1.0:
				_start_left(LeftAct.GRIP)

func _start_left(a: LeftAct) -> void:
	left_act = a
	left_t = 0.0
	_left_from = _left_xf

func _place_hands() -> void:
	for side in [-1, 1]:
		var hand_xf: Transform3D = _hand_xf if side > 0 else _left_xf
		(hands[side] as Node3D).transform = hand_xf

func _place_legs(delta: float) -> void:
	var p := player
	var want := _pedal_ankle("brake") if p.brake_amount > 0.05 else _pedal_ankle("throttle")
	_foot_target = _foot_target.move_toward(want, 1.6 * delta)
	var targets := {1: _foot_target, -1: _pedal_ankle("clutch") if p.realistic_clutch else _dead_pedal_ankle()}
	for side in [-1, 1]:
		var l: Dictionary = legs[side]
		var hip := _hip(side)
		var ankle: Vector3 = targets[side]
		var ik := two_bone(hip, ankle, THIGH, SHIN, Vector3(0.0, 1.0, -0.4))
		_aim(l.thigh, hip, ik[0], Vector3.RIGHT)
		_aim(l.shin, ik[0], ik[1], Vector3.RIGHT)
		var foot: Node3D = l.foot
		# the boot (built along -z) points from the ankle up at the pedal pad
		var z := -(Vector3(0.0, 0.05, -0.22)).normalized()
		var x := Vector3.RIGHT
		var y := z.cross(x).normalized()
		foot.transform = Transform3D(Basis(x, y, z), ik[1])
		_leg_gap[side] = ik[1].distance_to(ankle)

## Hand position and the rim grip it belongs on, for tests (car space).
func hand_position(side: int) -> Vector3:
	return (hands[side] as Node3D).position

## The wrist end of a hand (the cuff's outer face), car space.
func wrist_position(side: int) -> Vector3:
	return (hands[side] as Node3D).transform * Vector3(float(side) * WRIST_X, 0.0, CUFF_Z1)

func grip_position(side: int) -> Vector3:
	return _grip_transform(side).origin

## A hand's angle round the rim, car space (degrees, 0 = 3 o'clock, up
## positive, unwrapped), and whether it holds the rim (tests).
func rim_deg(side: int) -> float:
	return _rim[side].w

func is_gripping(side: int) -> bool:
	return _rim[side].grip

## How fast the rim turned in the last frame the hands were placed, deg/s (tests).
func wheel_rate_deg() -> float:
	return _wheel_rate_deg

func leg_gap(side: int) -> float:
	return _leg_gap[side]

func is_busy() -> bool:
	return act != Act.GRIP

## The left hand is off the rim, at the window (tests).
func left_at_window() -> bool:
	return left_act == LeftAct.WINDOW_HOLD
