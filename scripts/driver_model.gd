class_name DriverModel
extends Node3D

# The driver (cockpit milestone 2, 2026-10-06): a low-poly humanoid built from
# code in the PS2 way, rigid segments, no skinning. Seated in the driver's seat
# of the CockpitFrame (car space): head with a cap, torso in a dark jacket with
# sodium shoulder stripes, upper and lower arms, mitten hands with a thumb in
# black gloves with amber cuffs, legs in dark jeans, boots on the pedals.
#
# Arms: analytic two-bone IK from fixed shoulder joints to the hands, which
# grip the wheel rim at 9 and 3 and turn with it; past +-120 degrees of wheel
# rotation the rim slides through the hands instead of twisting the arms.
# Legs: the same IK from the hips to the pedals (right foot throttle or brake,
# whichever is pressed; left foot on the clutch with the clutch model on, else
# on the dead pedal).
#
# Animations are a small state machine on the right hand, all procedural and
# interruptible, driven by what the car and radio actually do (not by keys):
#   - manual gear change: when the lever starts moving (CockpitFrame follows
#     the vehicle's requested gear) the hand reaches the knob, rides it through
#     the gate and returns to the rim;
#   - automatic: a finger flick on the paddle (right on an upshift, left on a
#     downshift), hands stay on the rim;
#   - radio: on a station change the hand reaches the head unit, presses, and
#     returns (queued if a shift is in progress);
#   - steering: a small head yaw into the turn and a body lean from lateral g;
#   - idle: breathing, and a head bob from the road.
# In the cockpit view the head and torso are hidden (the camera is the head);
# in the chase view the whole driver shows through the glass.

const SKIN := Color("#B9896A")
const HAIR := Color("#2A1E16")
const CAP := Color("#1B1E25")
const JACKET := Color("#1E2229")
const JACKET_TRIM := Color("#FF8A1F")   # sodium
const GLOVE := Color("#111216")
const GLOVE_CUFF := Color("#8A5A2A")    # a dull amber band
const JEANS := Color("#171C28")
const BOOT := Color("#121318")
const SOLE := Color("#2C3038")

const UPPER_ARM := 0.32
const FOREARM := 0.30
const THIGH := 0.47
const SHIN := 0.45
## Beyond this wheel angle the rim slides through the hands (the arms are at
## full stretch past about 100 degrees from this seat).
const HAND_SLIDE_DEG := 100.0
## Seated geometry, car space: pelvis pivot, and the shoulder joint height on
## the torso. Seated eye height (ChaseCamera.COCKPIT_EYE, 1.06) sits about
## 0.16 m above the shoulders, as in a low sports seat.
const PELVIS := Vector3(CockpitFrame.SEAT_X, 0.50, 0.34)
const RECLINE_DEG := 12.0
const SHOULDER_Y := 0.41
const HEAD_Y := 0.49
const REACH_SECS := 0.22
const RETURN_SECS := 0.22
const PRESS_SECS := 0.12
const PADDLE_SECS := 0.25
const HEAD_YAW_RAD := 0.20       # at full steer fraction
const LEAN_RAD_PER_G := 0.08
const SHOULDER_HALF := 0.19
const HIP_HALF := 0.09

enum Act { GRIP, SHIFT_REACH, SHIFT_HOLD, SHIFT_RETURN, RADIO_REACH, RADIO_PRESS, RADIO_RETURN }

var frame: CockpitFrame
var player: PlayerCar
var torso: Node3D            # pivot at the pelvis, reclined like the seat
var torso_mesh: MeshInstance3D
var head: Node3D             # on the neck, yaws into turns
var head_mesh: MeshInstance3D
var arms := {}               # side (-1 left, +1 right) -> {upper, fore, hand}
var legs := {}               # side -> {thigh, shin, foot}
var act := Act.GRIP
var act_t := 0.0
var queued_radio := false
var paddle_t := 0.0
var paddle_side := 0
var _hand_from := Transform3D()   # where the right hand left from, for blends
var _hand_xf := Transform3D()     # the right hand's transform this frame (car space)
var _last_gear := 0
var _last_station := -2
var _lever_was_moving := false
var _lat_g := 0.0
var _head_bob := 0.0
var _prev_vy := 0.0
var _breath := 0.0
var _foot_target := Vector3.ZERO
var _mat: StandardMaterial3D
var tri_count := 0
## How far the forearm/shin ends fall short of the wrist/ankle targets (0 when
## the arm or leg can reach), per side; tests read these.
var _arm_gap := {-1: 0.0, 1: 0.0}
var _leg_gap := {-1: 0.0, 1: 0.0}
## Forward lean of the torso (m) so the arms reach the rim at full lock, like a
## driver leaning into the wheel; grows by the shortfall, eases back when not needed.
var _lean_fwd := 0.0

func _init(cockpit: CockpitFrame) -> void:
	frame = cockpit
	player = cockpit.player
	name = "Driver"

func _ready() -> void:
	_mat = CockpitKit.material(0.9, 0.0, 0.05)
	_build_torso()
	_build_head()
	for side in [-1, 1]:
		arms[side] = _build_arm(side)
		legs[side] = _build_leg(side)
	for n in find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = CockpitFrame.DRIVER_BIT
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # visual only, no shadows on the car
	_last_gear = player.gear
	_hand_xf = _grip_transform(1)
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

func _build_arm(side: int) -> Dictionary:
	var up := CockpitKit.new()
	_segment(up, UPPER_ARM, 0.055, 0.045, JACKET)
	up.box(Vector3(0.12, 0.05, 0.12), Vector3(0.0, 0.02, 0.0), JACKET)            # shoulder cap
	var fore := CockpitKit.new()
	_segment(fore, FOREARM, 0.045, 0.036, JACKET)
	fore.cylinder(0.039, FOREARM - 0.045, FOREARM - 0.02, Vector3.ZERO, GLOVE_CUFF, 10)   # glove cuff
	var hand := CockpitKit.new()
	_hand_mesh(hand, side)
	var upper := _part(up, "UpperArm" + ("L" if side < 0 else "R"))
	var forearm := _part(fore, "Forearm" + ("L" if side < 0 else "R"))
	var h := _part(hand, "Hand" + ("L" if side < 0 else "R"))
	return {"upper": upper, "fore": forearm, "hand": h}

## A mitten gripping a tube that runs along local y through the origin: the
## palm sits on the outer side (+x for the right hand at 3 o'clock, -x for the
## left at 9), fingers wrap round the dash side (-z), the thumb round the
## driver side (+z). Hand space: x outward from the hub, y up the rim, z toward
## the driver.
static func _hand_mesh(k: CockpitKit, side: int) -> void:
	var sx := float(side)
	k.box(Vector3(0.035, 0.085, 0.075), Vector3(sx * 0.038, 0.0, 0.01), GLOVE)                 # palm
	k.box(Vector3(0.06, 0.08, 0.03), Vector3(sx * 0.012, 0.0, -0.038), GLOVE)                  # fingers over the far side
	k.box(Vector3(0.03, 0.075, 0.03), Vector3(-sx * 0.028, 0.0, -0.030), GLOVE)                # fingertips curling in
	k.box(Vector3(0.05, 0.028, 0.028), Vector3(sx * 0.008, 0.03, 0.036), GLOVE)                # thumb
	k.box(Vector3(0.025, 0.028, 0.025), Vector3(-sx * 0.02, 0.03, 0.03), GLOVE)                # thumb tip
	k.box(Vector3(0.05, 0.03, 0.07), Vector3(sx * 0.03, 0.0, 0.06), GLOVE)                     # wrist, toward the driver

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

## The shoulder joint of a side, car space (moves with the breathing torso).
func _shoulder(side: int) -> Vector3:
	return torso.transform * Vector3(float(side) * SHOULDER_HALF, SHOULDER_Y, 0.0)

func _hip(side: int) -> Vector3:
	return torso.transform * Vector3(float(side) * HIP_HALF, 0.02, 0.0)

## Where a hand grips the rim, car space: the rim point at 9 or 3 turning
## with the wheel, sliding once the wheel is past HAND_SLIDE_DEG. Hand space
## as in _hand_mesh (x outward, y up the rim, z toward the driver).
func _grip_transform(side: int) -> Transform3D:
	var wheel := frame.wheel
	var wheel_deg := rad_to_deg(wheel.angle)
	var slip := wheel_deg - clampf(wheel_deg, -HAND_SLIDE_DEG, HAND_SLIDE_DEG)
	# the wheel turns the rim by -angle about its z; the hand stays at base + slip
	var base := 0.0 if side > 0 else 180.0
	var local_deg := base + slip
	var p := wheel.rim_point(local_deg)
	# the mesh is already mirrored for the left hand, so both hands use the
	# wheel's axes at their home point, turned only by the slip
	var local_xf := Transform3D(Basis(Vector3.BACK, deg_to_rad(slip)), p)
	return _wheel_to_car(local_xf)

## Wheel space -> car space (the frame is at the car's origin).
func _wheel_to_car(local_xf: Transform3D) -> Transform3D:
	return frame.wheel_mount.transform * frame.wheel.transform * local_xf

## Wrist point of a hand transform (the forearm's end), car space.
static func _wrist_of(hand_xf: Transform3D, side: int) -> Vector3:
	return hand_xf * Vector3(float(side) * 0.03, 0.0, 0.075)

## The right hand on the gear knob, car space.
func _lever_hand_transform() -> Transform3D:
	var knob := frame.lever.transform * frame.lever_knob.position
	var b := Basis(Vector3.BACK, deg_to_rad(-90.0))   # palm down over the knob, fingers forward
	return Transform3D(b, knob + Vector3(0.0, 0.035, 0.0))

## The right hand pressing the radio, car space.
func _radio_hand_transform(pressed: float) -> Transform3D:
	var p := frame.radio_button_position() + Vector3(0.0, -0.005, 0.075 - 0.02 * pressed)
	var b := Basis(Vector3.BACK, deg_to_rad(-90.0)) * Basis(Vector3.RIGHT, deg_to_rad(15.0))   # palm down, fingers at the buttons
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
	var need := maxf(_arm_gap[-1], _arm_gap[1])
	if need > 0.001:
		_lean_fwd = minf(_lean_fwd + need, 0.12)
	else:
		_lean_fwd = maxf(_lean_fwd - 0.03 * delta, 0.0)
	torso.rotation = Vector3(deg_to_rad(RECLINE_DEG) - _lean_fwd * 0.8, 0.0, -_lat_g * LEAN_RAD_PER_G)
	torso.position = PELVIS + Vector3(0.0, 0.004 * sin(_breath * TAU * 0.25), -_lean_fwd)
	# head: yaw into the turn, bob
	var steer := frame.steering
	head.rotation = Vector3(0.0, lerp_angle(head.rotation.y, -steer * HEAD_YAW_RAD, 1.0 - exp(-5.0 * delta)), 0.0)
	head.position = Vector3(0.0, HEAD_Y + _head_bob, 0.0)

	_update_events()
	_step_act(delta)
	_place_arms()
	_place_legs(delta)

## Watch the car and radio for things to animate.
func _update_events() -> void:
	var p := player
	if p.gear != _last_gear:
		if p.automatic_transmission:
			paddle_side = 1 if p.gear > _last_gear else -1
			paddle_t = PADDLE_SECS
		_last_gear = p.gear
	var moving := frame.lever_moving and not p.automatic_transmission
	if moving and not _lever_was_moving and act == Act.GRIP:
		_start(Act.SHIFT_REACH)
	_lever_was_moving = moving
	if frame.radio != null:
		if _last_station == -2:
			_last_station = frame.radio.station
		elif frame.radio.station != _last_station:
			_last_station = frame.radio.station
			if act == Act.GRIP:
				_start(Act.RADIO_REACH)
			else:
				queued_radio = true

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
			if queued_radio:
				queued_radio = false
				_start(Act.RADIO_REACH)
		Act.SHIFT_REACH:
			var t := clampf(act_t / REACH_SECS, 0.0, 1.0)
			_hand_xf = _hand_from.interpolate_with(_lever_hand_transform(), _ease(t))
			if t >= 1.0:
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
			if t >= 1.0:
				_start(Act.RADIO_RETURN)
		Act.RADIO_RETURN:
			var t := clampf(act_t / (RETURN_SECS + 0.08), 0.0, 1.0)
			_hand_xf = _hand_from.interpolate_with(grip, _ease(t))
			if t >= 1.0:
				_start(Act.GRIP)

func _place_arms() -> void:
	for side in [-1, 1]:
		var hand_xf: Transform3D = _hand_xf if side > 0 else _grip_transform(-1)
		var a: Dictionary = arms[side]
		(a.hand as Node3D).transform = hand_xf
		var shoulder := _shoulder(side)
		var wrist := _wrist_of(hand_xf, side)
		var pole := Vector3(float(side) * 0.5, -1.0, 0.15)
		var ik := two_bone(shoulder, wrist, UPPER_ARM, FOREARM, pole)
		_aim(a.upper, shoulder, ik[0], Vector3.FORWARD)
		_aim(a.fore, ik[0], ik[1], Vector3.FORWARD)
		_arm_gap[side] = ik[1].distance_to(wrist)

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

## Right hand position and the rim grip it belongs on, for tests (car space).
func hand_position(side: int) -> Vector3:
	return (arms[side].hand as Node3D).position

func grip_position(side: int) -> Vector3:
	return _grip_transform(side).origin

func arm_gap(side: int) -> float:
	return _arm_gap[side]

func leg_gap(side: int) -> float:
	return _leg_gap[side]

func is_busy() -> bool:
	return act != Act.GRIP
