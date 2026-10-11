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
#   - manual gear change (2026-10-09, Roy: the lever must travel the gate and
#     the hand must not pass through the knob): the shift starts the lever's
#     move (CockpitFrame, on the car's shift_time), the hand reaches the knob
#     in a share of that time, wraps it (palm over the ball, fingers down the
#     front, thumb inboard: the hand's grip tube is the knob, so nothing of
#     the hand is inside it) and the lever only travels once the hand holds
#     it; the hand is locked to the knob through the move, so it tilts with
#     the lever and lands in gear as the box engages, then returns to the rim;
#   - sequential stick (SEMI on a car with one): the same, a tap fore or aft;
#   - automatic, and SEMI on a car with paddles: a finger flick on the paddle
#     (right on an upshift, left on a downshift), hands stay on the rim;
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
#   - flip off (2026-10-11, the K key): the left hand leaves the rim, goes out
#     of the open side window and up past the door mirror, back of the hand
#     to whoever it is for, middle finger up, and comes back. A tap is one
#     gesture; while the key is held the hand stays out and pumps. With the
#     window shut it does the same behind the glass. Glove only, like every
#     other hand (no arm, no sleeve), and it changes nothing but the hand;
#   - idle action (2026-10-11, the L key, IdleActions): the left hand reaches
#     down to the pocket on the door, lifts the vape or the beer can to the
#     mouth (the LED brightens and a cloud follows; the head tips back for the
#     sip), puts it back and returns to the rim. One press is one use; a press
#     during a use queues one more. It waits for the window and the flip-off,
#     and they wait for it. Looks only (IdleProps holds the items and the cloud);
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
## The knees fall a little apart (2026-10-10): with them straight up, both
## thighs ran through the bottom of the wheel rim in every car
## (tests/fleet/driver_fit.gd). The IK pole leans this far outboard per leg.
const KNEE_SPLAY := 0.35
## The leg bones are scaled to the car (2026-10-10): full-length legs in a low
## car's short footwell folded the knees up into the wheel rim. A car's legs
## are as long as its furthest pedal needs, plus LEG_SLACK for the pedal's
## travel, never under LEG_SCALE_MIN of the full THIGH + SHIN (leg_lengths).
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
## The coupe's pelvis point (tests); the instance reads its car's seat from the cabin.
const PELVIS := Vector3(CockpitFrame.SEAT_X, 0.50, 0.34)
var pelvis := PELVIS
const RECLINE_DEG := 12.0
const HEAD_Y := 0.49
const REACH_SECS := 0.22
const RETURN_SECS := 0.22
## A manual shift's reach is this share of the car's shift_time, between
## REACH_MIN_SECS and REACH_SECS, so the lever has the rest of the shift to
## travel and lands as the box engages.
const REACH_SHARE := 0.45
const REACH_MIN_SECS := 0.08
const KNOB_LINGER_SECS := 0.08   # the hand stays on the knob this long after it lands
const SHIFT_HOLD_MAX_SECS := 1.2 # and never longer than this in all
## The hand on the knob: its grip tube (local y, see _hand_mesh) runs across
## the car through the ball, the back of the hand up and a little back so
## the fingers drape forward and down over the ball and the cuff stays low
## (KNOB_BACK, car space for an upright lever: the sightline cap), the wrist
## back and out toward the shoulder (KNOB_WRIST); the mitten's hollow is
## not centred on its grip axis (the fingertips curl in under it), so the
## ball sits KNOB_LIFT (negative: above) from the axis to clear the palm and
## the fingertips alike. Leans with the lever by KNOB_TILT_FOLLOW.
const KNOB_BACK := Vector3(-0.10, 0.92, 0.22)
const KNOB_WRIST := Vector3(0.40, 0.0, 0.85)
const KNOB_LIFT := -0.0035
## How much of the lever's tilt the hand takes (1 = it leans with the lever).
const KNOB_TILT_FOLLOW := 1.0
const PRESS_SECS := 0.12
const PADDLE_SECS := 0.25
const BRAKE_REACH_SECS := 0.20
const WINDOW_REACH_SECS := 0.25
const WINDOW_LINGER_SECS := 0.3   # the hand stays this long after the window stops
## Flip off (the left hand, K). The pose comes from the car's own cabin: the
## hand sits on the ray GESTURE_YAW_DEG left of straight ahead from the eye, at
## about eye height, GESTURE_OUT past the door line with the window open or
## GESTURE_IN inside the pane with it shut. Outside the 20 degree road cone
## (tests/view/gesture_flip_off.gd).
const GESTURE_REACH_SECS := 0.25
const GESTURE_RETURN_SECS := 0.25
const GESTURE_MIN_HOLD_SECS := 0.8   # a tap keeps the hand up this long
const GESTURE_PUMP_EVERY := 0.6      # while the key is held
const GESTURE_PUMP_SECS := 0.26
const GESTURE_PUMP := 0.035          # m, how far a pump jabs up
const GESTURE_OUT := 0.13
const GESTURE_IN := 0.085
const GESTURE_BELOW_EYE := 0.04      # the fist's centre under the eye line
const GESTURE_MIRROR_CLEAR := 0.13   # the fist's centre over the door mirror when it is right behind it
const GESTURE_WINDOW_OPEN := 0.5     # the window counts as open from half way down
const GESTURE_FINGER_IN := 0.35      # the fist takes over from the mitten this far into the reach
## Idle action (the left hand, L): rim -> the door pocket -> the mouth -> the
## pocket -> rim, about 2.5 s in all. The mouth pose hangs off the car's eye,
## low enough that no part of the hand or the item comes within 8 degrees of
## the eye line (tests/view/idle_actions.gd).
const IDLE_REACH_SECS := 0.30
const IDLE_LIFT_SECS := 0.40
const IDLE_LOWER_SECS := 0.45
const IDLE_RETURN_SECS := 0.30
const IDLE_HOLD_SECS := {IdleActions.VAPE: 0.85, IdleActions.BEER: 0.95, IdleActions.CIGARETTE: 2.7}
## From the eye. A hand's width to the left of the mouth, so the hand comes up beside the gauges, not over them.
const IDLE_MOUTH := {IdleActions.VAPE: Vector3(-0.07, -0.10, -0.19), IdleActions.BEER: Vector3(-0.07, -0.14, -0.18), IdleActions.CIGARETTE: Vector3(-0.07, -0.10, -0.19)}
const IDLE_YAW_DEG := 20.0     # the item turned in toward the mouth
const IDLE_TILT_DEG := {IdleActions.VAPE: 80.0, IdleActions.BEER: 20.0, IdleActions.CIGARETTE: 80.0}   # the item's lean toward the driver at the mouth
const SIP_TILT_DEG := 40.0     # more, at the top of the sip
const SIP_HEAD_DEG := 14.0     # the head tips back with it (seen from the chase view)
const HOLD_R := {IdleActions.VAPE: 0.012, IdleActions.BEER: IdleProps.CAN_R, IdleActions.CIGARETTE: 0.008}
## The cigarette's hold, from the hand arriving at the mouth: the lighter first
## (a click and a flame), then CIG_DRAGS drags, each one a breath out.
const CIG_LIGHT_SECS := 0.4
const CIG_DRAGS := 3
const CIG_WINDOW := 0.55   # how far the window rolls down by itself for a cigarette
enum { AIM_AHEAD, AIM_LEFT, AIM_BACK }
## Degrees left of straight ahead, by aim (AIM_LEFT with look left held, AIM_BACK with look back).
const GESTURE_YAW_DEG := [35.0, 80.0, 125.0]
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
## The flip-off reached the top: once per gesture (a hold's pumps do not repeat it).
signal gesture_peak(window_open: bool)
## The idle item reached the mouth: once per use ("vape" or "beer").
signal idle_used(item: String)

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
var thigh_len := THIGH       # this car's leg bones (leg_lengths)
var shin_len := SHIN
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
enum LeftAct { GRIP, WINDOW_REACH, WINDOW_HOLD, WINDOW_RETURN, GESTURE_REACH, GESTURE_HOLD, GESTURE_RETURN, IDLE_REACH, IDLE_USE, IDLE_RETURN }
var left_act := LeftAct.GRIP
var left_t := 0.0
var _left_from := Transform3D()
var _left_xf := Transform3D()
var finger_hand: MeshInstance3D  # the left fist with the middle finger up, shown instead of the mitten mid-gesture
var gesture_peaks := 0           # every top the hand reached, pumps included (tests)
var _gesture_key := false        # the key is down
var _gesture_wanted := false     # a press waiting for the window to stop
var _gesture_aim := AIM_AHEAD
var _gesture_open := false       # this gesture goes out of the window
var _pump_t := 0.0               # seconds left of the current pump
var _next_pump := 0.0
var _pump_counted := true
var props: IdleProps             # the vape, the can, their pocket and the cloud
var hold_hands := {}             # item -> the left hand shaped round it, shown instead of the mitten while it is held
var idle_uses := 0               # uses that reached the mouth (tests)
var _idle_key := false           # the key is down
var _idle_pending := 0           # presses waiting for the hand (never more than one)
var _idle_item := ""             # what this use is
var _idle_holding := false       # the item is in the hand
var _idle_counted := false
var _idle_exhaled := false
var _idle_lit := false           # the cigarette has been lit this use
var _idle_drags := 0             # drags already breathed out this use
var _draw := 0.0                 # 0..1 through the draw or the sip
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
var _left_foot := Vector3.ZERO
var _reach_secs := REACH_SECS      # this shift's reach
var _linger := 0.0                 # time on the knob since the lever landed
var _mat: StandardMaterial3D
var tri_count := 0
## How far the shin ends fall short of the ankle targets (0 when the leg can
## reach), per side; tests read these.
var _leg_gap := {-1: 0.0, 1: 0.0}

func _init(cockpit: CockpitFrame) -> void:
	frame = cockpit
	player = cockpit.player
	name = "Driver"
	# the seat: pelvis 2 cm over the cushion, 2 cm ahead of its centre (the coupe's 0.50, 0.34)
	pelvis = Vector3(float(cockpit.cab.seat_x), float(cockpit.cab.seat_h) + 0.02, float(cockpit.cab.seat_z) - 0.02)
	var bones := leg_lengths(cockpit.cab)
	thigh_len = bones.x
	shin_len = bones.y

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
	_build_finger_hand()
	_build_idle()
	for n in find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = CockpitFrame.DRIVER_BIT
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # visual only, no shadows on the car
	_last_gear = player.gear
	_hand_xf = _grip_transform(1)
	_left_xf = _grip_transform(-1)
	_foot_target = _pedal_ankle("throttle")
	_left_foot = _pedal_ankle("clutch") if player.realistic_clutch else _dead_pedal_ankle()

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
	torso.position = pelvis
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
	for b in hand_boxes(side):
		k.box(b[0], b[1], glove)
	# the closed cuff: a capped cylinder along +z around the wrist, nothing past
	# it, in the glove colour, with a thin accent band round it
	k.cylinder(CUFF_R, CUFF_Z0, CUFF_Z1, Vector3(sx * WRIST_X, 0.0, 0.0), glove, 10, Basis(Vector3.RIGHT, PI / 2.0))
	var band := CockpitKit.new()
	band.ring_sector(CUFF_R, CUFF_R + 0.003, 0.0, TAU, BAND_Z0, BAND_Z1, cuff, 10)
	band.offset(Vector3(sx * WRIST_X, 0.0, 0.0))
	k.merge(band)

## The solid parts of a hand as [size, centre] boxes in hand space (the mesh
## is built from these; tests check nothing it holds is inside one). The
## grip tube along local y through the origin is the hollow between them.
static func hand_boxes(side: int) -> Array:
	var sx := float(side)
	return [
		[Vector3(0.035, 0.085, 0.075), Vector3(sx * 0.038, 0.0, 0.01)],     # palm
		[Vector3(0.06, 0.08, 0.03), Vector3(sx * 0.012, 0.0, -0.038)],      # fingers over the far side
		[Vector3(0.03, 0.075, 0.03), Vector3(-sx * 0.028, 0.0, -0.030)],    # fingertips curling in
		[Vector3(0.05, 0.028, 0.028), Vector3(sx * 0.008, 0.03, 0.036)],    # thumb
		[Vector3(0.025, 0.028, 0.025), Vector3(-sx * 0.02, 0.03, 0.03)],    # thumb tip
		[Vector3(0.05, 0.03, 0.07), Vector3(sx * WRIST_X, 0.0, 0.06)],      # wrist, toward the driver
	]

## The flip-off fist, left hand, in the mitten's hand space so the two swap in
## place: the back of the hand on -x, the wrist and the same closed cuff along
## +z, the knuckles at -z with the middle finger standing straight out of them.
static func _finger_mesh(k: CockpitKit, glove: Color, cuff: Color) -> void:
	k.box(Vector3(0.04, 0.085, 0.075), Vector3(-0.03, 0.0, 0.01), glove)                       # the fist: back of the hand
	k.box(Vector3(0.03, 0.085, 0.045), Vector3(0.005, 0.0, -0.012), glove)                     # curled fingers
	k.box(Vector3(0.022, 0.06, 0.026), Vector3(0.031, -0.006, -0.008), glove)                  # thumb across them
	k.box(Vector3(0.024, 0.021, 0.042), Vector3(-0.028, 0.0, -0.047), glove)                   # middle finger
	k.box(Vector3(0.02, 0.018, 0.036), Vector3(-0.028, 0.0, -0.085), glove)                    # its tip
	k.box(Vector3(0.05, 0.03, 0.07), Vector3(-WRIST_X, 0.0, 0.06), glove)                      # wrist
	k.cylinder(CUFF_R, CUFF_Z0, CUFF_Z1, Vector3(-WRIST_X, 0.0, 0.0), glove, 10, Basis(Vector3.RIGHT, PI / 2.0))
	var band := CockpitKit.new()
	band.ring_sector(CUFF_R, CUFF_R + 0.003, 0.0, TAU, BAND_Z0, BAND_Z1, cuff, 10)
	band.offset(Vector3(-WRIST_X, 0.0, 0.0))
	k.merge(band)

func _build_finger_hand() -> void:
	var k := CockpitKit.new()
	_finger_mesh(k, GLOVE_STYLES[glove_style].glove, GLOVE_STYLES[glove_style].cuff)
	finger_hand = _part(k, "HandLFinger")
	finger_hand.visible = false

## The left hand round a tube of radius r along local y (the vape, the can),
## in the mitten's hand space so they swap in place: the palm on -x, fingers
## over the far side (-z), the thumb on the driver's side, the same closed cuff.
static func _hold_mesh(k: CockpitKit, glove: Color, cuff: Color, r: float) -> void:
	var wrist_x := -(r + 0.01)
	k.box(Vector3(0.035, 0.085, 0.075), Vector3(-(r + 0.0175), 0.0, 0.01), glove)                              # palm
	k.box(Vector3(1.5 * r + 0.035, 0.05 + r, 0.028), Vector3(-(0.5 * r + 0.035) * 0.5, 0.0, -(r + 0.014)), glove)   # fingers over the far side
	k.box(Vector3(0.024, 0.045 + r, 0.024), Vector3(0.5 * r + 0.01, 0.0, -(r + 0.004)), glove)                  # fingertips curling in
	k.box(Vector3(r + 0.04, 0.028, 0.026), Vector3(-(r + 0.02) * 0.5, 0.02, r + 0.013), glove)                  # thumb
	k.box(Vector3(0.05, 0.03, 0.07), Vector3(wrist_x, 0.0, 0.06), glove)                                        # wrist
	k.cylinder(CUFF_R, CUFF_Z0, CUFF_Z1, Vector3(wrist_x, 0.0, 0.0), glove, 10, Basis(Vector3.RIGHT, PI / 2.0))
	var band := CockpitKit.new()
	band.ring_sector(CUFF_R, CUFF_R + 0.003, 0.0, TAU, BAND_Z0, BAND_Z1, cuff, 10)
	band.offset(Vector3(wrist_x, 0.0, 0.0))
	k.merge(band)

func _build_idle() -> void:
	for item in HOLD_R:
		var k := CockpitKit.new()
		_hold_mesh(k, GLOVE_STYLES[glove_style].glove, GLOVE_STYLES[glove_style].cuff, HOLD_R[item])
		var hand := _part(k, "HandLHold" + String(item).capitalize())
		hand.visible = false
		hold_hands[item] = hand
	props = IdleProps.new(self)
	add_child(props)

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
	_segment(th, thigh_len, 0.075, 0.06, JEANS)
	var sh := CockpitKit.new()
	_segment(sh, shin_len, 0.055, 0.045, JEANS)
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

## Which way a knee bends: up, a little forward, and out to its own side.
static func knee_pole(side: int) -> Vector3:
	return Vector3(float(side) * KNEE_SPLAY, 1.0, -0.4)

## Where each foot rests, by side (the right on the throttle or the brake, the
## left on the clutch or the dead pedal): the ankle targets _pedal_ankle and
## _dead_pedal_ankle give with the pedals up.
static func rest_ankles(cab: Dictionary) -> Dictionary:
	var at: Vector3 = cab.pedals
	return {
		1: [at + Vector3(0.0, -0.20, 0.114), at + Vector3(-0.12, -0.20, 0.114)],
		-1: [at + Vector3(-0.24, -0.20, 0.114), at + Vector3(-0.27, -0.21, 0.17)],
	}

const LEG_SLACK := 0.07
const LEG_SCALE_MIN := 0.80

## This car's (thigh, shin): the full bones, scaled down to its footwell.
static func leg_lengths(cab: Dictionary) -> Vector2:
	var far := 0.0
	var ankles := rest_ankles(cab)
	for side in ankles:
		for ankle in ankles[side]:
			far = maxf(far, rest_hip(cab, side).distance_to(ankle))
	return Vector2(THIGH, SHIN) * clampf((far + LEG_SLACK) / (THIGH + SHIN), LEG_SCALE_MIN, 1.0)

## A leg's hip in car space for a cabin, as _hip() gives it at rest (the
## torso's recline tips the hip joint 4 mm back). CockpitFrame opens the
## footwell round the legs with it before the driver exists.
static func rest_hip(cab: Dictionary, side: int) -> Vector3:
	return Vector3(float(cab.seat_x) + float(side) * HIP_HALF, float(cab.seat_h) + 0.04, float(cab.seat_z) - 0.016)

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

## The right hand wrapped round the gear knob, car space, riding the lever:
## the grip tube through the ball (KNOB_LIFT up), the pose turned with the
## lever's tilt so the wrist follows the knob through the gate.
func _lever_hand_transform() -> Transform3D:
	var lever: Node3D = frame.lever
	var b := Basis.IDENTITY.slerp(lever.basis, KNOB_TILT_FOLLOW) * _hand_basis(1, KNOB_BACK, KNOB_WRIST)
	var p := lever.transform * (frame.lever_knob.position + Vector3(0.0, KNOB_LIFT, 0.0))
	return Transform3D(b, p)

## The hand holds the knob right now (CockpitFrame starts the lever on this).
func hand_on_knob() -> bool:
	return act == Act.SHIFT_HOLD

## How far the hand's grip is from where it should sit on the knob, metres
## (0 while it holds it; tests).
func knob_grip_error() -> float:
	return (hands[1] as Node3D).position.distance_to(_lever_hand_transform().origin)

## The hand's grip pose on the knob for an upright lever (tests).
static func knob_hand_basis() -> Basis:
	return _hand_basis(1, KNOB_BACK, KNOB_WRIST)

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

## The door line: how far out (|x|) the driver's door and its glass reach at the belt.
func door_line() -> float:
	return maxf(float(frame.cab.door_x), float(frame.cab.glass_x))

## The car has a pane in the driver's door (the open kei has none).
func has_door_glass() -> bool:
	return float(frame.cab.glass_x) > 0.0

## |x| of the door pane at height y (it leans in toward the roof, as CockpitFrame builds it).
func pane_x(y: float) -> float:
	var cab := frame.cab
	if not has_door_glass():
		return float(cab.door_x)
	var top: float = float(cab.belt_y) + 0.30 if cab.open_top else float(cab.get("glass_top", float(cab.roof_y) - 0.03))
	var x_top := minf(float(cab.glass_x), float((cab.a_pillar[1] as Vector3).x) - 0.01)
	var t := clampf((y - frame.glass_bottom) / maxf(top - frame.glass_bottom, 0.01), 0.0, 1.0)
	return lerpf(float(cab.glass_x), x_top, t)

## The flip-off pose, car space; pump 0..1 jabs it up.
func _gesture_transform(pump: float) -> Transform3D:
	var cab := frame.cab
	var eye: Vector3 = cab.eye
	var yaw := deg_to_rad(GESTURE_YAW_DEG[_gesture_aim])
	var y := eye.y - GESTURE_BELOW_EYE
	var x := 0.0
	if _gesture_open:
		x = -(door_line() + GESTURE_OUT)
	else:
		x = -(pane_x(y + 0.06) - GESTURE_IN)
	var z := eye.z - absf(x - eye.x) / tan(yaw)
	if _gesture_open:
		# right behind the door mirror: up past it, not through it
		var dm: Vector3 = cab.door_mirror
		if absf(z - dm.z) < 0.16 and absf(-x - absf(dm.x)) < 0.16:
			y = maxf(y, dm.y + GESTURE_MIRROR_CLEAR)
	var aim := Vector3(-sin(yaw), 0.0, -cos(yaw))
	return Transform3D(_hand_basis(-1, aim, Vector3.DOWN), Vector3(x, y + GESTURE_PUMP * pump, z))

## From one hand transform to another for the gesture, e 0..1. The hand swings
## wide (a curve pulled toward a point just outside the sill, or along the door
## under it with the window shut) instead of cutting across the pillar and the view.
func _gesture_path(from: Transform3D, to: Transform3D, e: float) -> Transform3D:
	var eye: Vector3 = frame.cab.eye
	var via := Vector3(-(door_line() + 0.05), frame.glass_bottom + 0.14, eye.z - 0.25)
	if not _gesture_open:
		via = Vector3(-(pane_x(frame.glass_bottom) - GESTURE_IN), frame.glass_bottom, eye.z - 0.25)   # along the door, under the sill
	var p := from.origin.lerp(via, e).lerp(via.lerp(to.origin, e), e)
	return Transform3D(Basis(from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), e)), p)

## The flip-off key, from the camera each physics tick (tests call it too):
## a press asks for one gesture, holding keeps the hand out. `aim` is where the
## driver is looking when the key goes down (AIM_).
func gesture_key(down: bool, aim: int = AIM_AHEAD) -> void:
	if down and not _gesture_key and (left_act == LeftAct.GESTURE_RETURN or not is_gesturing()):
		_gesture_wanted = true
		_gesture_aim = clampi(aim, AIM_AHEAD, AIM_BACK)
	_gesture_key = down

## The idle action key, from the camera each physics tick (tests call it too).
func idle_key(down: bool) -> void:
	if down and not _idle_key:
		request_idle()
	_idle_key = down

## One press: a use as soon as the hand is free. Nothing with None picked, or
## with the beer on the move when that is switched off. A press during a use
## queues one more; further presses are dropped.
func request_idle() -> bool:
	if not IdleActions.allowed(player.linear_velocity.length(), player.engine_running):
		return false
	_idle_pending = 1
	return true

func _begin_idle() -> void:
	_idle_pending = 0
	_idle_item = IdleActions.item
	if not HOLD_R.has(_idle_item):
		return   # switched to None while the press waited
	_idle_counted = false
	_idle_exhaled = false
	_idle_lit = false
	_idle_drags = 0
	if _idle_item == IdleActions.CIGARETTE:
		props.cigarette_reset()
		# the window rolls down a little by itself, so there is a window to flick it out of
		if has_door_glass() and PerspectiveAudio.current != null:
			PerspectiveAudio.current.assist_open(CIG_WINDOW)
	_start_left(LeftAct.IDLE_REACH)

## The hand with the item, car space: e 0 at the pocket .. 1 at the mouth,
## `draw` 0..1 through the sip. It comes back along the door first and then up,
## clear of the wheel.
func _idle_transform(e: float, draw: float) -> Transform3D:
	var from := props.holder_xf().origin
	var eye: Vector3 = frame.cab.eye
	var to: Vector3 = eye + IDLE_MOUTH[_idle_item]
	var via := Vector3(lerpf(from.x, to.x, 0.35), from.y + 0.06, eye.z - 0.10)
	var tilt: float = IDLE_TILT_DEG[_idle_item] * e
	if _idle_item == IdleActions.BEER:
		tilt += SIP_TILT_DEG * draw
	var b := Basis(Vector3.UP, deg_to_rad(IDLE_YAW_DEG) * e) * Basis(Vector3.RIGHT, deg_to_rad(tilt))
	return Transform3D(b, from.lerp(via, e).lerp(via.lerp(to, e), e))

## The side window counts as open from half way down, or when the car has no glass there.
func _window_is_open() -> bool:
	return frame.window >= GESTURE_WINDOW_OPEN or not has_door_glass()

func _begin_gesture() -> void:
	_gesture_wanted = false
	_gesture_open = frame.window >= GESTURE_WINDOW_OPEN or not has_door_glass()
	_start_left(LeftAct.GESTURE_REACH)

## Ankle position for a pedal, car space: behind and a little below the pad.
func _pedal_ankle(pedal: String) -> Vector3:
	var pivot: Node3D = frame.pedals[pedal]
	var pad := pivot.transform * Vector3(0.0, -0.17, 0.004)
	return pad + Vector3(0.0, -0.03, 0.11)

func _dead_pedal_ankle() -> Vector3:
	return (frame.cab.pedals as Vector3) + Vector3(-0.27, -0.21, 0.17)   # left of the clutch, on the floor

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
	torso.position = pelvis + Vector3(0.0, 0.004 * sin(_breath * TAU * 0.25), 0.0)
	# head: yaw into the turn, bob
	var steer := frame.steering
	var sip := deg_to_rad(SIP_HEAD_DEG) * _draw if _idle_holding and _idle_item == IdleActions.BEER else 0.0
	head.rotation = Vector3(sip, lerp_angle(head.rotation.y, -steer * HEAD_YAW_RAD, 1.0 - exp(-5.0 * delta)), 0.0)
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
		# AUTO flicks a paddle only on a paddle box; SEMI on a paddle car always does
		if (p.automatic_transmission and p.has_paddles()) or (not p.automatic_transmission and not frame.lever_needs_hand()):
			paddle_side = 1 if p.gear > _last_gear else -1
			paddle_t = PADDLE_SECS
		_last_gear = p.gear
	# Priority (sightline spec): handbrake > shift > radio. A higher request
	# takes the hand from a lower one mid-move, and a shift while the hand is
	# on its way back goes straight back to the knob; the radio press is
	# dropped (the station already changed), a shift under a held handbrake
	# moves the lever on its own.
	var moving := frame.lever_moving and frame.lever_needs_hand()
	if moving and not _lever_was_moving and not _is_brake() and act != Act.SHIFT_REACH and act != Act.SHIFT_HOLD:
		_reach_secs = clampf(REACH_SHARE * p.shift_time, REACH_MIN_SECS, REACH_SECS)
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
			var t := clampf(act_t / _reach_secs, 0.0, 1.0)
			_hand_xf = _hand_from.interpolate_with(_lever_hand_transform(), _ease(t))
			if t >= 1.0:
				_contact(CONTACT_GEAR)
				_start(Act.SHIFT_HOLD)
		Act.SHIFT_HOLD:
			# locked to the knob: the lever moves under the hand (CockpitFrame
			# waits for hand_on_knob, then travels), the hand goes with it
			_hand_xf = _lever_hand_transform()
			if not frame.lever_moving:
				_linger += delta
			if (_linger >= KNOB_LINGER_SECS and not frame.lever_moving) or act_t > SHIFT_HOLD_MAX_SECS:
				_linger = 0.0
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
				if radio_requests > 0 and not (frame.lever_moving and frame.lever_needs_hand()):
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
	# a flip-off waits for the window to stop, then takes the hand from wherever it is
	if _gesture_wanted and not working and not is_idling() and (left_act == LeftAct.GESTURE_RETURN or not is_gesturing()):
		_begin_gesture()
	# an idle action waits for the window and the flip-off, and starts from the rim
	if _idle_pending > 0 and not working and left_act == LeftAct.GRIP:
		_begin_idle()
	match left_act:
		LeftAct.IDLE_REACH:
			var t := clampf(left_t / IDLE_REACH_SECS, 0.0, 1.0)
			_left_xf = _left_from.interpolate_with(props.holder_xf(), _ease(t))
			if t >= 1.0:
				_idle_holding = true
				_start_left(LeftAct.IDLE_USE)
		LeftAct.IDLE_USE:
			var hold: float = IDLE_HOLD_SECS[_idle_item]
			var up := clampf(left_t / IDLE_LIFT_SECS, 0.0, 1.0)
			var down := clampf((left_t - IDLE_LIFT_SECS - hold) / IDLE_LOWER_SECS, 0.0, 1.0)
			var into := left_t - IDLE_LIFT_SECS   # seconds into the hold
			if _idle_item == IdleActions.CIGARETTE:
				# lighter first, then CIG_DRAGS humps of draw, a breath out after each
				if into >= 0.0 and not _idle_lit:
					_idle_lit = true
					props.light_up()
				var v := clampf((into - CIG_LIGHT_SECS) / (hold - CIG_LIGHT_SECS), 0.0, 1.0)
				_draw = absf(sin(v * PI * CIG_DRAGS)) if into > CIG_LIGHT_SECS else 0.0
				props.set_burn(1.0 - (1.0 - IdleProps.BURN_END) * v)   # shorter with every drag
				var done := CIG_DRAGS if v >= 1.0 else int(v * CIG_DRAGS)
				while _idle_drags < done:
					_idle_drags += 1
					props.exhale(_window_is_open(), IdleProps.CIG_PUFFS)
			else:
				_draw = sin(clampf(into / hold, 0.0, 1.0) * PI)
			_left_xf = _idle_transform(_ease(up) - _ease(down), _draw)
			if up >= 1.0 and not _idle_counted:
				_idle_counted = true
				idle_uses += 1
				idle_used.emit(_idle_item)
			if down > 0.0 and not _idle_exhaled:
				_idle_exhaled = true
				if _idle_item == IdleActions.VAPE:
					props.exhale(_window_is_open())
				elif _idle_item == IdleActions.CIGARETTE:
					props.flick_butt()
					if PerspectiveAudio.current != null:
						PerspectiveAudio.current.release_assist()   # back up, if the driver opened it
			if down >= 1.0:
				_idle_holding = false
				_draw = 0.0
				_start_left(LeftAct.IDLE_RETURN)
		LeftAct.IDLE_RETURN:
			var t := clampf(left_t / IDLE_RETURN_SECS, 0.0, 1.0)
			_left_xf = _left_from.interpolate_with(grip, _ease(t))
			if t >= 1.0:
				_start_left(LeftAct.GRIP)
		LeftAct.GESTURE_REACH:
			var t := clampf(left_t / GESTURE_REACH_SECS, 0.0, 1.0)
			_left_xf = _gesture_path(_left_from, _gesture_transform(0.0), _ease(t))
			if t >= 1.0:
				gesture_peaks += 1
				gesture_peak.emit(_gesture_open)
				_pump_t = 0.0
				_next_pump = GESTURE_PUMP_EVERY
				_start_left(LeftAct.GESTURE_HOLD)
		LeftAct.GESTURE_HOLD:
			if _gesture_key and left_t >= _next_pump and _pump_t <= 0.0:
				_next_pump += GESTURE_PUMP_EVERY
				_pump_t = GESTURE_PUMP_SECS
				_pump_counted = false
			var pump := 0.0
			if _pump_t > 0.0:
				_pump_t = maxf(_pump_t - delta, 0.0)
				pump = sin((1.0 - _pump_t / GESTURE_PUMP_SECS) * PI)
				if not _pump_counted and _pump_t <= GESTURE_PUMP_SECS * 0.5:
					_pump_counted = true
					gesture_peaks += 1
			_left_xf = _gesture_transform(pump)
			if not _gesture_key and left_t >= GESTURE_MIN_HOLD_SECS and _pump_t <= 0.0:
				_start_left(LeftAct.GESTURE_RETURN)
		LeftAct.GESTURE_RETURN:
			var t := clampf(left_t / GESTURE_RETURN_SECS, 0.0, 1.0)
			_left_xf = _gesture_path(_left_from, grip, _ease(t))
			if t >= 1.0:
				_start_left(LeftAct.GRIP)
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
	# the fist with the finger up stands in for the left mitten through the middle of a gesture
	var fist := left_act == LeftAct.GESTURE_HOLD \
		or (left_act == LeftAct.GESTURE_REACH and left_t >= GESTURE_REACH_SECS * GESTURE_FINGER_IN) \
		or (left_act == LeftAct.GESTURE_RETURN and left_t < GESTURE_RETURN_SECS * (1.0 - GESTURE_FINGER_IN))
	finger_hand.transform = _left_xf
	finger_hand.visible = fist
	# and the hand shaped round the vape or the can while it holds one
	for item in hold_hands:
		var hand: MeshInstance3D = hold_hands[item]
		hand.transform = _left_xf
		hand.visible = _idle_holding and item == _idle_item
	(hands[-1] as Node3D).visible = not fist and not _idle_holding
	props.place(_idle_item if _idle_holding else "", _left_xf, _draw if _idle_item == IdleActions.VAPE or _idle_item == IdleActions.CIGARETTE else 0.0)

func _place_legs(delta: float) -> void:
	var p := player
	var want := _pedal_ankle("brake") if p.brake_amount > 0.05 else _pedal_ankle("throttle")
	_foot_target = _foot_target.move_toward(want, 1.6 * delta)
	# the left foot: on the clutch with the clutch model on, and for a shift on
	# a stick car (the box opens its own clutch, the foot shows it), else the dead pedal
	var clutching := p.realistic_clutch or (frame.lever_needs_hand() and (p.clutch_amount > 0.05 or frame.lever_moving))
	_left_foot = _left_foot.move_toward(_pedal_ankle("clutch") if clutching else _dead_pedal_ankle(), 2.0 * delta)
	var targets := {1: _foot_target, -1: _left_foot}
	for side in [-1, 1]:
		var l: Dictionary = legs[side]
		var hip := _hip(side)
		var ankle: Vector3 = targets[side]
		var ik := two_bone(hip, ankle, thigh_len, shin_len, knee_pole(side))
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

## The left hand is off the rim on a flip-off (reach, hold or the way back).
func is_gesturing() -> bool:
	return left_act >= LeftAct.GESTURE_REACH and left_act <= LeftAct.GESTURE_RETURN

## The left hand is off the rim on an idle action (reach, use or the way back).
func is_idling() -> bool:
	return left_act >= LeftAct.IDLE_REACH

## An idle press is waiting for the hand (tests).
func idle_waiting() -> bool:
	return _idle_pending > 0

## The left hand is off the rim, at the window (tests).
func left_at_window() -> bool:
	return left_act == LeftAct.WINDOW_HOLD
