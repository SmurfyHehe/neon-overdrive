extends Camera3D
class_name ChaseCamera

# Chase camera (stage A, 2026-10-04). Moved out of game.gd so the feel layer
# below has one home. Roy's three smoothing modes from #31 are carried over
# unchanged (C cycles them; he tunes them later). New in stage A, from the
# sense-of-speed research (perceived speed comes from how fast things move
# across the screen, not from the number on the speedo):
# - a lower chase position: foreground objects sweep past at a bigger angle;
# - speed FOV with a partial dolly-in, so the world stretches outward while
#   the car keeps roughly its size on screen;
# - shake: a light buzz that grows with speed, a rumble on kerbs and
#   sidewalks, and a kick when the car hits something.
# Every number below is a starting value for Roy to judge by driving.

const MODE_NAMES := ["A: hard snap", "B: light smoothing", "C: smoothing + reverse swing"]
const FOLLOW_RATE := 6.0  # 1/s, how fast the camera catches up sideways/vertically
const SWING_RATE := 5.0   # 1/s, how fast it swings round for reverse (~0.6 s)

# Framing. Was distance 6.0 / height 3.2 / look 10 m ahead at 1.1 / FOV 62.
const DIST := 5.2         # m behind the car at rest
const HEIGHT := 1.85      # m above the car's origin at rest
const LOOK_AHEAD := 12.0  # m ahead of the car the camera aims at
const LOOK_HEIGHT := 0.95
## Per-car framing (special vehicles, S0): kind -> [dist, height, look_ahead,
## look_height], same four numbers as the constants above, which are the
## default for every car not listed. Starting points; the body steps tune them.
const FRAMING := {
	"m1_monster": [10.0, 5.0, 16.0, 2.2],
	"l1_lowrider": [6.2, 1.6, 12.0, 0.7],
}
const SQUAT := 0.2        # m the camera drops at full speed effect

# Speed FOV (vertical degrees; Godot keeps height, so 16:9 is ~1.6x wider).
const FOV_REST := 58.0
const FOV_FAST := 74.0
const FOV_SPEED_LO := 5.0    # m/s (18 km/h): widening starts
const FOV_SPEED_HI := 68.0   # m/s (245 km/h, about the car's top speed): fully wide.
                             # Eased (see _speed_curve), so low speed still widens
                             # noticeably instead of waiting for the top end
const FOV_ACCEL_GAIN := 0.25 # deg per m/s^2 of forward acceleration
const FOV_ACCEL_MIN := -2.0  # braking narrows a little
const FOV_ACCEL_MAX := 3.0   # hard acceleration widens a little more
const FOV_RATE := 3.0        # 1/s smoothing on the speed term
const ACCEL_RATE := 4.0      # 1/s smoothing on the acceleration term
## 0 = distance fixed (car shrinks as FOV widens), 1 = car keeps its rest size.
const DOLLY := 0.7

# Shake. Rotation in radians, position in metres, at full strength.
const SPEED_SHAKE_ROT := 0.008   # ~0.45 deg buzz at FOV_SPEED_HI (top speed)
const SPEED_SHAKE_POS := 0.015
const SURFACE_SHAKE_ROT := 0.008 # kerb/sidewalk rumble ("Kerb" surface)
const SURFACE_SHAKE_POS := 0.02
const IMPACT_SHAKE_ROT := 0.035  # ~2 deg at full trauma
const IMPACT_SHAKE_POS := 0.12
const TRAUMA_DECAY := 1.6        # 1/s
## Velocity change in one physics tick (m/s) above which it counts as a hit.
## Hard braking peaks well under this (see tests/view/camera_feel.gd); a wall at
## speed is several times over it.
const IMPACT_DV := 0.8
const IMPACT_GAIN := 0.12        # trauma per m/s over the threshold
## Road bumps (2026-10-08): a highway joint or a manhole cover under a wheel
## (CarAudio.road_bump) jolts the view up this far at full strength, then it
## settles back in about a tenth of a second.
const BUMP_POS := 0.012
const BUMP_DECAY := 30.0         # 1/s

## Phase C: the cockpit view (F toggles). VIEW_CHASE is everything above; in
## VIEW_COCKPIT the camera sits at the driver's eye, rigid to the car, the body
## is kept off this camera (it stays in the mirrors) and the CockpitFrame (the
## whole interior, wheel, cluster, mirrors) is shown.
## The eye (cockpit milestone, 2026-10-06): seat height in the P1's cabin, just
## ahead of the B-pillar, a hand's width inboard of the seat centre (-0.36).
## The passenger-side door mirror is NOT in view from here (58 degrees right,
## past the screen edge at every FOV the slider allows); looking around
## (the arrow keys, below) turns the head to it.
enum View { CHASE, COCKPIT }
const COCKPIT_EYE := Vector3(-0.32, 1.10, 0.30)  # car-local, -x is the driver's side (left-hand drive)
## The eye in this car: COCKPIT_EYE moved by the car's cabin offset
## (CabinSpec.for_kind(kind).eye, from the CABIN in that car's data file).
var eye := COCKPIT_EYE
const COCKPIT_FOV_SPEED_GAIN := 6.0  # degrees added at top speed; the base is ViewSettings.cockpit_fov (default 62)
## Head movement in the cockpit (Roy, 2026-10-06; camera upgrade C1,
## 2026-10-10): the eye sways with the car's forces, capped at HEAD_MAX_M (5 cm)
## and HEAD_MAX_DEG (3 degrees). Lateral g pushes the head outward (the body
## slides) but TIPS IT INTO the corner, the way a driver's head does; braking
## brings it forward and dips it, acceleration presses it back. The cap is
## reached at HEAD_G_FULL g and the motion is smoothed at HEAD_RATE, so bumps
## in the sim's speed reading do not twitch the view. FxSettings "head_motion"
## ([fx] in settings.cfg, NEON_FX=0) is the off switch: off, the eye eases
## back to COCKPIT_EYE and stays rigid to the car (and the corner look below
## is off too).
const HEAD_MAX_M := 0.05
const HEAD_MAX_DEG := 3.0
const HEAD_G_FULL := 0.8
const HEAD_RATE := 6.0
## Camera upgrade C2: the horizon. The cabin rolls and pitches with the body,
## the camera does not follow all of it: in a corner the camera's roll against
## the world is (1 - HORIZON_ROLL_LEVEL) of the body roll, so the road stays
## steadier than the cabin. Pitch is levelled less so a hard stop still dips.
## Past HORIZON_FADE_LO_DEG of body tilt the levelling fades out, so a
## rollover or a flip is shown in full (and the Euler wrap never shows).
const HORIZON_ROLL_LEVEL := 0.5
const HORIZON_PITCH_LEVEL := 0.3
const HORIZON_FADE_LO_DEG := 25.0
const HORIZON_FADE_HI_DEG := 50.0
## Camera upgrade C4: look into corners. Through a bend the view turns up to
## CORNER_LOOK_MAX_DEG toward where the road goes, driven by how fast the car is
## turning (yaw rate, rad/s: nothing below CORNER_RATE_DEAD, full at
## CORNER_RATE_FULL), only above CORNER_SPEED_LO..HI m/s so parking turns do not
## swing the view. Never while an arrow key is held (then it eases out at
## LOOK_RATE), never reversing or looking back.
const CORNER_LOOK_MAX_DEG := 6.0
const CORNER_RATE_DEAD := 0.04
const CORNER_RATE_FULL := 0.30
const CORNER_SPEED_LO := 4.0
const CORNER_SPEED_HI := 10.0
const CORNER_LOOK_RATE := 4.0      # 1/s, ~0.75 s to settle; back to 0 well inside 1 s
## Camera upgrade: no drawn frame moves the FOV more than this (degrees); also
## capped at FOV_MAX_RATE degrees/s so a low frame rate does not jump either.
const FOV_MAX_STEP_DEG := 0.5
const FOV_MAX_RATE := 30.0
## Cockpit shake is rotation only (position shake could push the eye through the
## roof or a pillar): a road bump becomes this much pitch instead of a lift.
const BUMP_ROT := 0.006            # radians at full strength (~0.35 deg)
var head_offset := Vector3.ZERO   # car-local, metres, current
var head_tilt := Vector2.ZERO     # (pitch, roll) degrees, current
var view := View.CHASE
## Look back (hold the look_back key, B): the chase cam swings to the front
## of the car and looks back at it, the same move as reversing; the cockpit
## eye turns 180 degrees to the rear window.
var look_back := false
## Look around (Roy, 2026-10-09): hold the arrow keys in the cockpit view to
## turn the head (left/right) and tilt it (up/down); release and it eases back
## straight ahead. This replaces the V mirror glance. Only the camera turns,
## never the car or the interior, so the sightline rules (hands and wheel at or
## below HAND_TOP_MIN_DEG under the eye) are unchanged: they are measured from
## the straight-ahead view. The door mirror the head turns toward is the
## focused one (rendered at twice the size, see CockpitMirrors.set_focus).
const LOOK_YAW_MAX := 110.0        # degrees each way
const LOOK_PITCH_UP := 35.0
const LOOK_PITCH_DOWN := 30.0
const LOOK_RATE := 14.0            # 1/s: ~0.2 s to 95% of the turn
const LOOK_MIRROR_YAW := 35.0      # a tap stops here: the head is "at" a door mirror
const LOOK_FOCUS_YAW := 30.0       # past this the door mirror on that side is drawn at twice the size
## Tap vs hold (camera upgrade): a key held shorter than LOOK_TAP_S sends the
## head to the door mirror and keeps it there LOOK_TAP_LATCH_S after release;
## held longer, the head goes on turning to LOOK_YAW_MAX.
const LOOK_TAP_S := 0.18
const LOOK_TAP_LATCH_S := 0.9
var look_yaw := 0.0                # degrees, current, + = left (about +y)
var look_pitch := 0.0              # degrees, current, + = up
var corner_yaw := 0.0              # degrees, the look-into-corners turn (+ = left), on top of look_yaw
var _hold_dir := 0                 # arrow key held (-1 right, +1 left), 0 none
var _hold_t := 0.0                 # seconds it has been held
var _latch_dir := 0                # a tap's door mirror, held for _latch_t more seconds
var _latch_t := 0.0
var _look_focus := 0               # door mirror the head is turned to (-1 left, +1 right)
var frame: CockpitFrame
var perspective: PerspectiveAudio
var target: PlayerCar
var mode := ViewSettings.camera_smoothing  # follows the saved setting (pause menu, C key); tests may override
var _seen_smoothing := ViewSettings.camera_smoothing
## Tests turn this off to compare the drawn position against the chase offset.
var shake_enabled := true

# Smoothed state the HUD and tests can read.
var speed_t := 0.0     # 0..1, eased speed factor
var accel_fov := 0.0   # current acceleration FOV term, degrees
var trauma := 0.0      # 0..1, impact shake energy
var bump := 0.0        # 0..1, the last road bump, decaying
var surface_t := 0.0   # 0..1, share of wheels on a rough surface (scaled by speed)
var dist_now := DIST
var height_now := HEIGHT
## This car's framing (FRAMING, or the constants): set in _init.
var base_dist := DIST
var base_height := HEIGHT
var look_ahead := LOOK_AHEAD
var look_height := LOOK_HEIGHT
var anchor := Vector3.ZERO  # chase position before shake
var aim := Vector3.ZERO     # point the rig looks at before shake

var _follow := Vector2.ZERO
var _yaw := 0.0
## Whether the car faces back up the road (RoadFrame's +z).
var _up_road := false
var _started := false
var _started_fov := false
var _prev_vel := Vector3.ZERO
var _prev_speed := 0.0
var _accel := 0.0
var _t := 0.0
var _noise := FastNoiseLite.new()

func _init(car: PlayerCar) -> void:
	target = car
	var fr: Array = FRAMING.get(PlayerCar.chassis_kind(), [DIST, HEIGHT, LOOK_AHEAD, LOOK_HEIGHT])
	base_dist = fr[0]
	base_height = fr[1]
	look_ahead = fr[2]
	look_height = fr[3]
	dist_now = base_dist
	height_now = base_height
	fov = FOV_REST
	far = 400.0
	# Moved in _process every rendered frame, so it must not be
	# physics-interpolated itself (ISSUES B7).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = 9431
	_noise.frequency = 1.0
	near = 0.05

func _ready() -> void:
	current = true
	_prev_vel = target.linear_velocity
	# The interior lives on the car (car space), not on the camera, so the
	# mirrors and (next PR) the driver sit where they are from any view. This
	# camera never draws the mirror-only layer the body moves to in the cockpit.
	eye = CabinSpec.for_kind(PlayerCar.chassis_kind()).eye   # the car's own eye (CABIN in its data file)
	if CockpitFrame.enabled and OS.get_environment("NEON_COCKPIT") != "0":
		frame = CockpitFrame.new(target)
		target.add_child(frame)
	cull_mask &= ~CockpitFrame.MIRROR_ONLY_BIT
	perspective = PerspectiveAudio.new()
	add_child(perspective)

## Switch between the chase and cockpit views.
func set_view(v: View) -> void:
	view = v
	var cockpit := v == View.COCKPIT
	if not cockpit:
		look_yaw = 0.0   # the chase view has no head to turn
		look_pitch = 0.0
		_set_look_focus(0)
	if frame != null:
		frame.set_cockpit(cockpit)
	elif target.chassis_visual != null:
		target.chassis_visual.visible = not cockpit   # no cockpit built: the Phase C behaviour
	perspective.set_cockpit(cockpit)

## The driver's side window, 0 closed .. 1 fully down: the one value the glass,
## the driver's hand and the cabin sound all follow (PerspectiveAudio owns it).
func window_openness() -> float:
	return perspective.window

func mode_name() -> String:
	return "COCKPIT" if view == View.COCKPIT else MODE_NAMES[mode]

# Polled on the physics tick like all game input (#30), and the impact check
# needs exactly one velocity sample per tick.
func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("camera_cycle"):
		ViewSettings.set_camera_smoothing((ViewSettings.camera_smoothing + 1) % MODE_NAMES.size())
		ViewSettings.save_settings()
	if ViewSettings.camera_smoothing != _seen_smoothing:   # menu or C key changed it
		_seen_smoothing = ViewSettings.camera_smoothing
		mode = _seen_smoothing
	if Input.is_action_just_pressed("camera_view"):
		set_view(View.CHASE if view == View.COCKPIT else View.COCKPIT)
	look_back = Input.is_action_pressed("look_back")
	# the left hand does one thing at a time: the window key waits while it is out on a gesture
	var gesturing := frame != null and frame.driver != null and frame.driver.is_gesturing()
	perspective.window_key(Input.is_action_pressed("window") and not gesturing, delta)
	if frame != null:
		frame.set_window(perspective.window, perspective.window_direction())
		if frame.driver != null:
			var aim := DriverModel.AIM_BACK if look_back else (DriverModel.AIM_LEFT if Input.is_action_pressed("look_left") else DriverModel.AIM_AHEAD)
			frame.driver.gesture_key(Input.is_action_pressed("flip_off"), aim)
	# where the driver's head points, for the radio and the window's wind
	perspective.head_yaw_deg = look_yaw + (180.0 if look_back else 0.0) if view == View.COCKPIT else 0.0
	if perspective.car_audio == null:
		for c in target.get_children():
			if c is CarAudio:
				perspective.car_audio = c
				c.road_bump.connect(road_bump)
	var v := target.linear_velocity
	var dv := (v - _prev_vel).length()
	_prev_vel = v
	register_impact(dv)
	var speed := target.current_speed()
	_accel = (speed - _prev_speed) / delta
	_prev_speed = speed

## The car was moved and stopped by the game (off-map rescue): the jump in
## velocity is not an impact.
func forget_motion() -> void:
	_prev_vel = target.linear_velocity
	_prev_speed = target.current_speed()

## Feeds one tick's velocity change (m/s) into the impact shake. Split out so
## tests/view/camera_feel.gd can check the tick-rate independence directly.
func register_impact(dv: float) -> void:
	# The per-tick velocity change scales with the tick length, so scale the
	# threshold. The gain stays as is: at twice the rate each tick's excess is
	# half as big and there are twice as many ticks, so the total trauma from
	# one impact is already the same. (It used to be multiplied by rate/60 as
	# well, which made kerb shake ~7x stronger at 120 Hz.)
	var dv_limit := IMPACT_DV * 60.0 / float(Engine.physics_ticks_per_second)
	if dv > dv_limit:
		trauma = minf(1.0, trauma + (dv - dv_limit) * IMPACT_GAIN)

## A joint or a manhole under a wheel (0..1).
func road_bump(strength: float) -> void:
	bump = maxf(bump, clampf(strength, 0.0, 1.0))

func _process(delta: float) -> void:
	var fov_before := fov
	_update_feel(delta)
	bump *= exp(-BUMP_DECAY * delta)
	if frame != null:
		frame.steering = target.steer_fraction()  # the wheel turns the way the car does, in every view
	if view == View.COCKPIT:
		_place_cockpit(delta)
		if look_back:
			global_transform.basis = global_transform.basis * Basis(Vector3.UP, PI)
		if shake_enabled:
			_shake(delta, false)
			rotate_object_local(Vector3.RIGHT, BUMP_ROT * bump)
	else:
		_place(delta)
		if shake_enabled:
			_shake(delta, true)
			global_position += global_basis.y * BUMP_POS * bump
	# No drawn frame moves the FOV by more than FOV_MAX_STEP_DEG.
	if delta > 0.0 and _started_fov:
		var step := minf(FOV_MAX_STEP_DEG, FOV_MAX_RATE * delta)
		fov = fov_before + clampf(fov - fov_before, -step, step)
	_started_fov = true

## At the driver's eye, on the interpolated transform (same reason as the
## chase cam), looking where the car points, plus the head movement; a fixed
## FOV that widens a touch with speed.
func _place_cockpit(delta: float) -> void:
	var xf := target.get_global_transform_interpolated()
	_update_head(delta)
	_update_look(delta)
	var turn := Basis.from_euler(Vector3(deg_to_rad(look_pitch), deg_to_rad(look_yaw + corner_yaw), 0.0))
	var tilt := Basis.from_euler(Vector3(deg_to_rad(head_tilt.x), 0.0, deg_to_rad(head_tilt.y)))
	global_transform = Transform3D(_levelled(xf.basis) * turn * tilt, xf * (eye + head_offset))
	fov = ViewSettings.cockpit_fov + COCKPIT_FOV_SPEED_GAIN * speed_t

## The body's orientation with part of its roll and pitch taken out (C2): the
## camera's tilt against the world is (1 - HORIZON_*_LEVEL) of the body's. Yaw
## is untouched. The levelling fades out past HORIZON_FADE_LO_DEG..HI so a
## rollover is shown whole. Once per drawn frame; one Euler decompose and one
## compose, a few hundred nanoseconds.
func _levelled(b: Basis) -> Basis:
	var e := b.orthonormalized().get_euler(EULER_ORDER_YXZ)   # (pitch, yaw, roll)
	var roll_f := HORIZON_ROLL_LEVEL * (1.0 - smoothstep(HORIZON_FADE_LO_DEG, HORIZON_FADE_HI_DEG, rad_to_deg(absf(e.z))))
	var pitch_f := HORIZON_PITCH_LEVEL * (1.0 - smoothstep(HORIZON_FADE_LO_DEG, HORIZON_FADE_HI_DEG, rad_to_deg(absf(e.x))))
	return Basis.from_euler(Vector3(e.x * (1.0 - pitch_f), e.y, e.z * (1.0 - roll_f)), EULER_ORDER_YXZ)

## Eases the head toward where the arrow keys point it (or back to straight
## ahead), and focuses the door mirror it has turned to. A key tapped (under
## LOOK_TAP_S) stops at the door mirror and stays there a moment; held, the head
## goes on turning. With no key down, the view leans toward the bend (C4).
func _update_look(delta: float) -> void:
	var axis := Input.get_axis("look_right", "look_left")   # + = left
	var up := Input.get_axis("look_down", "look_up")
	var want_yaw := 0.0
	if axis != 0.0:
		var dir := 1 if axis > 0.0 else -1
		if dir != _hold_dir:
			_hold_dir = dir
			_hold_t = 0.0
		_hold_t += delta
		_latch_t = 0.0
		want_yaw = axis * (LOOK_MIRROR_YAW if _hold_t < LOOK_TAP_S else LOOK_YAW_MAX)
	else:
		if _hold_dir != 0 and _hold_t < LOOK_TAP_S:
			_latch_dir = _hold_dir
			_latch_t = LOOK_TAP_LATCH_S
		_hold_dir = 0
		_hold_t = 0.0
		if _latch_t > 0.0:
			_latch_t -= delta
			want_yaw = _latch_dir * LOOK_MIRROR_YAW
	var want_pitch := up * (LOOK_PITCH_UP if up > 0.0 else LOOK_PITCH_DOWN)
	var k := 1.0 - exp(-LOOK_RATE * delta)
	look_yaw = lerpf(look_yaw, want_yaw, k)
	look_pitch = lerpf(look_pitch, want_pitch, k)
	# Look into the corner: how fast the car is turning, never a key press.
	var key_down := axis != 0.0 or up != 0.0 or _latch_t > 0.0
	var want_corner := 0.0
	var corner_k := 1.0 - exp(-CORNER_LOOK_RATE * delta)
	if key_down:
		corner_k = k
	elif not look_back and target.gear != -1 and FxSettings.is_on("head_motion"):
		var w := target.angular_velocity.y
		var strength := clampf((absf(w) - CORNER_RATE_DEAD) / (CORNER_RATE_FULL - CORNER_RATE_DEAD), 0.0, 1.0)
		var gate := smoothstep(CORNER_SPEED_LO, CORNER_SPEED_HI, absf(target.current_speed()))
		want_corner = signf(w) * strength * gate * CORNER_LOOK_MAX_DEG
	corner_yaw = lerpf(corner_yaw, want_corner, corner_k)
	_set_look_focus(0 if absf(look_yaw) < LOOK_FOCUS_YAW else (-1 if look_yaw > 0.0 else 1))

func _set_look_focus(side: int) -> void:
	if side == _look_focus:
		return
	_look_focus = side
	if frame != null and frame.mirrors != null:
		frame.mirrors.set_focus(side)

## Head sway from lateral g (yaw rate x speed) and longitudinal g (the speed
## derivative the FOV already uses). +x is the passenger side: a left turn
## (yaw rate +) slides the head right (outward) but tips it LEFT, into the
## corner (positive roll about +z; it used to roll with the body, outward);
## braking (accel -) moves it forward (-z) and dips it (negative pitch about +x).
func _update_head(delta: float) -> void:
	var want_offset := Vector3.ZERO
	var want_tilt := Vector2.ZERO
	if FxSettings.is_on("head_motion"):
		var lat_g := clampf(target.angular_velocity.y * target.current_speed() / 9.81 / HEAD_G_FULL, -1.0, 1.0)
		var long_g := clampf(_accel / 9.81 / HEAD_G_FULL, -1.0, 1.0)
		want_offset = Vector3(lat_g, 0.0, long_g).limit_length(1.0) * HEAD_MAX_M
		want_tilt = Vector2(long_g, lat_g).limit_length(1.0) * HEAD_MAX_DEG
	var k := 1.0 - exp(-HEAD_RATE * delta)
	head_offset = head_offset.lerp(want_offset, k)
	head_tilt = head_tilt.lerp(want_tilt, k)

## 0..1 speed factor for FOV, dolly, squat and shake. Ease-out (1 - (1-t)^2):
## the range now runs to top speed (68 m/s), so a straight line would leave
## everyday speeds with a third of the effect. This gives about 0.15 at 10 m/s,
## 0.6 at 28 m/s, 0.85 at 45 m/s and 1.0 at 68 m/s.
static func _speed_curve(speed: float) -> float:
	var t := clampf((speed - FOV_SPEED_LO) / (FOV_SPEED_HI - FOV_SPEED_LO), 0.0, 1.0)
	return 1.0 - (1.0 - t) * (1.0 - t)

func _update_feel(delta: float) -> void:
	var speed := absf(target.current_speed())
	var want_t := _speed_curve(speed)
	speed_t = lerpf(speed_t, want_t, 1.0 - exp(-FOV_RATE * delta))
	var want_a := clampf(_accel * FOV_ACCEL_GAIN, FOV_ACCEL_MIN, FOV_ACCEL_MAX)
	accel_fov = lerpf(accel_fov, want_a, 1.0 - exp(-ACCEL_RATE * delta))
	fov = lerpf(FOV_REST, FOV_FAST, speed_t) + accel_fov
	# Dolly: scale the distance by how much the frustum widened, part way.
	var widen := tan(deg_to_rad(FOV_REST) * 0.5) / tan(deg_to_rad(fov) * 0.5)
	dist_now = base_dist * (DOLLY * widen + (1.0 - DOLLY))
	height_now = base_height - SQUAT * speed_t
	trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)
	var rough := 0
	var grounded := 0
	for w in target.wheel_array:
		if w.is_colliding():
			grounded += 1
			if w.surface_type != "Road":
				rough += 1
	var want_s := 0.0
	if grounded > 0:
		want_s = float(rough) / float(grounded) * clampf(speed / 15.0, 0.0, 1.0)
	surface_t = lerpf(surface_t, want_s, 1.0 - exp(-12.0 * delta))

func _place(delta: float) -> void:
	# The interpolated position, not target.position: the car only moves on
	# the 60 Hz physics tick, and with vsync off the camera updates several
	# times per tick. Following the raw position made car and road judder.
	var p := target.get_global_transform_interpolated().origin
	# Road space (RoadFrame, #37): across / up / along the road. The rig sits
	# behind the car ALONG THE ROAD and looks down it, so it swings round
	# bends with the road instead of staring down world -Z; on a straight
	# road this is exactly the old world-axis rig.
	var u := RoadFrame.unroll(p)
	# Reversing flips the chase cam to the opposite side of the car looking
	# the opposite way (2026-09-13 fix, kept); so does holding look_back.
	# The road goes both ways (the map, 2026-10-10): the rig looks the way the
	# car faces along the road. It changes side only once the car is well
	# round (past 60 degrees from across the road), so a slide or a spin does
	# not swing it back and forth.
	var facing := RoadFrame.dir_to_road(u.z, -target.global_transform.basis.z).z
	if absf(facing) > 0.5:
		_up_road = facing > 0.0
	var target_yaw := PI if (target.gear == -1 or look_back) != _up_road else 0.0
	if mode == 0 or not _started:
		_follow = Vector2(u.x, u.y)
		_yaw = target_yaw
		_started = true
	else:
		# Frame-rate independent ease: the same feel at 60 or 300 fps.
		_follow = _follow.lerp(Vector2(u.x, u.y), 1.0 - exp(-FOLLOW_RATE * delta))
		if mode == 2:
			_yaw = lerpf(_yaw, target_yaw, 1.0 - exp(-SWING_RATE * delta))
		else:
			_yaw = target_yaw
	# Distance along the road stays locked to the car (only sideways and
	# height motion is smoothed); the dolly shortens it with speed.
	var back := Vector3(0, 0, dist_now).rotated(Vector3.UP, _yaw)
	var ahead := Vector3(0, 0, -look_ahead).rotated(Vector3.UP, _yaw)
	anchor = RoadFrame.roll(Vector3(_follow.x + back.x, _follow.y + height_now, u.z + back.z))
	aim = RoadFrame.roll(Vector3(_follow.x + ahead.x, _follow.y + look_height, u.z + ahead.z))
	global_position = anchor
	look_at(aim, Vector3.UP)

## Smooth noise shake applied on top of the chase transform. Amplitude adds
## the three sources; impact uses trauma^2 so small knocks stay small. In the
## cockpit it is rotation only (with_position false): the eye never leaves the
## cabin on a hit.
func _shake(delta: float, with_position: bool) -> void:
	var buzz := pow(speed_t, 1.5)
	var rot := SPEED_SHAKE_ROT * buzz + SURFACE_SHAKE_ROT * surface_t + IMPACT_SHAKE_ROT * trauma * trauma
	var pos := SPEED_SHAKE_POS * buzz + SURFACE_SHAKE_POS * surface_t + IMPACT_SHAKE_POS * trauma * trauma
	if rot <= 0.0 and pos <= 0.0:
		return
	# Faster wobble for rough surface and hits than for the speed buzz.
	_t += delta * (6.0 + 10.0 * surface_t + 14.0 * trauma)
	rotate_object_local(Vector3.RIGHT, rot * _noise.get_noise_2d(_t, 0.0))
	rotate_object_local(Vector3.UP, rot * 0.6 * _noise.get_noise_2d(_t, 100.0))
	rotate_object_local(Vector3.BACK, rot * 0.8 * _noise.get_noise_2d(_t, 200.0))
	if with_position:
		global_position += global_basis * Vector3(pos * _noise.get_noise_2d(_t, 300.0), pos * _noise.get_noise_2d(_t, 400.0), 0.0)
