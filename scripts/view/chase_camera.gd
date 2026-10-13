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
## 1/s, how fast the rig turns to follow the car's heading (smoothing B and C;
## A locks to it). Round the 63 m roundabout at 50 km/h the car turns 25
## deg/s and the rig trails it by about 25/HEADING_RATE degrees.
const HEADING_RATE := 6.0

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
## Throttle and brake give (Roy 1493): full throttle lets the car pull away up to
## GIVE_M, hard braking brings the camera in as much, on a critically damped
## spring (no bounce) with a GIVE_HALF_LIFE half-life, about a quarter second
## to settle. Driven by the forward acceleration (the speed is the dolly's job),
## full at GIVE_ACCEL_FULL m/s^2 forward or GIVE_BRAKE_FULL braking. The
## per-tick acceleration jitters (a settling car reads +-1 m/s^2), so it is
## smoothed at GIVE_ACCEL_RATE first and nothing under GIVE_DEAD counts.
const GIVE_M := 0.5
const GIVE_HALF_LIFE := 0.12
const GIVE_ACCEL_FULL := 4.0
const GIVE_BRAKE_FULL := 8.0
const GIVE_ACCEL_RATE := 10.0   # 1/s
const GIVE_DEAD := 0.6          # m/s^2

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
const START_SHAKE_ROT := 0.006   # ~0.35 deg: the engine rocking as it cranks and catches (PlayerCar.start_shake)
const START_SHAKE_POS := 0.008
const START_SHAKE_CHASE := 0.5   # from behind the car it is half what the driver feels
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
## HOOD (2026-10-11) is the third view: the camera on the bonnet just ahead of the
## windscreen, rigid to the body, looking where the car points. F cycles
## cockpit -> hood -> chase. The body is drawn as in the chase view, the cabin
## is not (CockpitFrame is in its chase state), the mirror cameras are off and
## the HUD rear strip is on; the sound is the outside perspective.
enum View { CHASE, COCKPIT, HOOD }
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
## Drift look (Roy 1492, #640): in a slide the eyes go where the car is going,
## not further into the bend. Past DRIFT_SLIP_LO degrees between the nose and the
## direction of travel the corner look blends toward the travel direction, all
## the way at DRIFT_SLIP_HI, never past DRIFT_LOOK_MAX_DEG. A spin (slip past
## DRIFT_SPIN_LO..HI) fades it back out so it never flips side at 180 degrees.
## Same gates as the corner look (speed, head motion, no key, not reversing);
## the hood gets HOOD_STRENGTH of it.
const DRIFT_SLIP_LO := 5.0
const DRIFT_SLIP_HI := 30.0
const DRIFT_LOOK_MAX_DEG := 20.0
const DRIFT_SPIN_LO := 70.0
const DRIFT_SPIN_HI := 100.0
## Camera upgrade: no drawn frame moves the FOV more than this (degrees); also
## capped at FOV_MAX_RATE degrees/s so a low frame rate does not jump either.
const FOV_MAX_STEP_DEG := 0.5
const FOV_MAX_RATE := 30.0
## Cockpit shake is rotation only (position shake could push the eye through the
## roof or a pillar): a road bump becomes this much pitch instead of a lift.
const BUMP_ROT := 0.006            # radians at full strength (~0.35 deg)
var head_offset := Vector3.ZERO   # car-local, metres, current
var head_tilt := Vector2.ZERO     # (pitch, roll) degrees, current
## The sideways acceleration the head sway follows (#641, m/s^2): the car's real
## acceleration across its right axis (+ = toward its left, the inside of a left
## turn), from the velocity change each physics tick. It used to be yaw rate x
## speed, which in a spin reads several g and pinned the sway at its cap.
var lat_accel := 0.0
## Where the car is going against where it points (degrees, + = to its left),
## and how far apart they are (0..180), for the drift look; tests read them.
var travel_deg := 0.0
var slip_deg := 0.0
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
## Hood view (Roy, 2026-10-11): the look keys turn the camera on the bonnet the
## way they turn the head, with tighter limits (nothing of the cabin is there to
## look into). Horizon levelling, the corner look and the shake run at
## HOOD_STRENGTH of the cockpit's, and there is no head lean. B (look_back)
## swaps to the camera on the roof, which looks straight back while held and
## ignores the arrows. The points are CabinSpec.hood_cam / roof_back_cam.
const HOOD_YAW_MAX := 90.0
const HOOD_PITCH_UP := 20.0
const HOOD_PITCH_DOWN := 15.0
const HOOD_STRENGTH := 0.5
const HoodFit := preload("res://scripts/view/hood_fit.gd")
var hood_cam := Vector3(0.0, 1.0, -1.0)         # car space, from the car's CABIN, fitted to the body on entering the view
var roof_back_cam := Vector3(0.0, 1.4, 1.0)
## Look around outside (Roy, 2026-10-11): in the chase view the arrow keys swing
## the camera round the car on a circle of the usual chase distance. Hold
## Left/Right: out to ORBIT_HOLD_DEG on that side of the CAR (Left always shows
## the car's left flank, also while the rig is in front of it in reverse); tap:
## an ORBIT_TAP_DEG glance, kept LOOK_TAP_LATCH_S, then back. Up lifts the camera
## ORBIT_LIFT_UP_M, Down drops it to ORBIT_LOW_ABOVE_ROAD_M above the road.
## Release eases back at ORBIT_RATE. B wins (the orbit eases to 0 under the
## look-back swing); F, photo mode and a pause clear it (see reset_orbit).
const ORBIT_HOLD_DEG := 100.0
const ORBIT_TAP_DEG := 35.0
const ORBIT_RATE := 8.0            # 1/s, in every smoothing mode: ~0.6 s from full swing to under 2 degrees
const ORBIT_LIFT_UP_M := 2.5
const ORBIT_LOW_ABOVE_ROAD_M := 0.6
const ORBIT_AIM_LO_DEG := 20.0     # the aim slides from "down the road" to the car's centre
const ORBIT_AIM_HI_DEG := 60.0     # between these two orbit angles
## Wall check (camera proposal step 1, #634, #557): the chase rig never sits
## inside the world. Each drawn frame one ray runs from WALL_ROOF_UP above the
## car's roof to the chase point, on the world and wall layers only (road,
## buildings, walls, barriers; never cars or knocked props). On a hit the
## camera moves in along that line at once to WALL_GAP short of it, and eases
## back out at WALL_OUT_RATE once it is clear, so a fence run does not pump it.
## While the orbit swings it to a side, a second ray at WALL_LOW_H above the
## road, from under the car to under the camera, finds a guardrail or a median
## barrier the camera would be looking over (the rail across the wheels, #557).
## Under a tunnel roof (which has no collider) the height is capped
## WALL_GAP under TunnelKit.CLEAR_H, rising WALL_MOUTH_SLOPE m per metre
## outside a mouth, so going in or out never jumps.
const WALL_MASK := (1 << (CarSpec.WORLD_LAYER - 1)) | (1 << (CarSpec.WALL_LAYER - 1))
const WALL_GAP := 0.3
const WALL_ROOF_UP := 0.2
const WALL_MIN_M := 1.0          # never closer than this to the roof point
const WALL_OUT_RATE := 4.0       # 1/s
const WALL_LOW_H := 0.5
const WALL_LOW_ORBIT_DEG := 10.0 # the low ray only past this much orbit
const WALL_MOUTH_SLOPE := 0.5
const RoadMap := preload("res://scripts/world/road_map.gd")
const TunnelKit := preload("res://scripts/world/tunnel_kit.gd")
## Share of the roof-to-chase-point line the camera may use (1 = clear).
var wall_f := 1.0
## Whether the last frame's rays hit (tests read it).
var wall_hit := false
var orbit_yaw := 0.0               # degrees, + = toward the car's left flank
var orbit_lift := 0.0              # -1 (low) .. +1 (high)
var _orbit_dir := 0                # arrow held (-1 right, +1 left), 0 none
var _orbit_hold_t := 0.0
var _orbit_latch_dir := 0
var _orbit_latch_t := 0.0
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
## A window tap made during an idle action (L), kept until the hand is back:
## 0 none, 1 the key went down during the use, above 1 the ticks left of the replayed tap.
const WINDOW_TAP_TICKS := 3
var _window_tap := 0
var trauma := 0.0      # 0..1, impact shake energy
var bump := 0.0        # 0..1, the last road bump, decaying
var surface_t := 0.0   # 0..1, share of wheels on a rough surface (scaled by speed)
var dist_now := DIST
var height_now := HEIGHT
## The throttle / brake give (m, + = farther back) and its spring's speed.
var give := 0.0
var _give_v := 0.0
var _give_accel := 0.0   # the acceleration the give follows, smoothed
## This car's framing (FRAMING, or the constants): set in _init.
var base_dist := DIST
var base_height := HEIGHT
var look_ahead := LOOK_AHEAD
var look_height := LOOK_HEIGHT
var anchor := Vector3.ZERO  # chase position before shake
var aim := Vector3.ZERO     # point the rig looks at before shake

var _follow := Vector2.ZERO   # the point the rig follows: across, up (road space)
var _follow_z := 0.0          # and along the road
var _yaw := 0.0               # where the rig looks, road space (0 = down the road, -z)
var _head := 0.0              # the car's heading, eased (HEADING_RATE)
var _flip := 0.0              # 0 behind the car, PI in front (reversing, B), eased in mode C
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
	var cab := CabinSpec.for_kind(PlayerCar.chassis_kind())
	eye = cab.eye   # the car's own eye (CABIN in its data file)
	_hood_points()
	if CockpitFrame.enabled and OS.get_environment("NEON_COCKPIT") != "0":
		frame = CockpitFrame.new(target)
		target.add_child(frame)
	cull_mask &= ~CockpitFrame.MIRROR_ONLY_BIT
	perspective = PerspectiveAudio.new()
	add_child(perspective)
	# The view F left the game in (chase unless the settings file says otherwise).
	var saved := ViewSettings.CAMERA_VIEWS.find(ViewSettings.camera_view) if ViewSettings.remembers_view() else 0
	if saved > 0:
		set_view(saved as View)

## The hood view's two camera points: the car's own CABIN keys, else
## CabinSpec's computed defaults fitted to the body as it is now (a scoop, a
## tall bonnet or a cabin that is not this car's lifts or moves the default).
func _hood_points() -> void:
	var cab := CabinSpec.for_kind(PlayerCar.chassis_kind())
	hood_cam = CabinSpec.hood_cam(cab)
	roof_back_cam = CabinSpec.roof_back_cam(cab)
	if (cab.has("hood_cam") and cab.has("roof_back_cam")) or target.chassis_visual == null:
		return
	var fit = HoodFit.new()
	fit.build(target.chassis_visual, target.global_transform.affine_inverse())
	if not cab.has("hood_cam"):
		hood_cam = fit.fit_hood(hood_cam)
	if not cab.has("roof_back_cam"):
		roof_back_cam = fit.fit_roof(roof_back_cam)

## Switch between the chase, cockpit and hood views.
func set_view(v: View) -> void:
	view = v
	if v == View.HOOD:
		_hood_points()   # the body may have changed since the last time
	var cockpit := v == View.COCKPIT
	if v == View.CHASE:
		look_yaw = 0.0   # the chase view has no head to turn
		look_pitch = 0.0
	if not cockpit:
		_set_look_focus(0)   # no door mirror is drawn in the chase or hood view
	reset_orbit()   # F: both ways start from the straight chase view
	# F is a cut (#635): the new view takes its own FOV and place on its first
	# frame instead of easing over from the old one.
	_started_fov = false
	_started = false
	wall_f = 1.0
	if frame != null:
		frame.set_cockpit(cockpit)
	elif target.chassis_visual != null:
		target.chassis_visual.visible = not cockpit   # no cockpit built: the Phase C behaviour
	perspective.set_cockpit(cockpit)

## Orbit back to 0 at once and forget which arrow was down (F, photo mode).
func reset_orbit() -> void:
	orbit_yaw = 0.0
	orbit_lift = 0.0
	_clear_orbit_keys()

func _clear_orbit_keys() -> void:
	_orbit_dir = 0
	_orbit_hold_t = 0.0
	_orbit_latch_dir = 0
	_orbit_latch_t = 0.0

## The camera does not process while paused, so an arrow pressed or released
## in a menu would otherwise look like a tap or a hold on the first frame back:
## read the keys fresh on both edges.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		_clear_orbit_keys()

## The driver's side window, 0 closed .. 1 fully down: the one value the glass,
## the driver's hand and the cabin sound all follow (PerspectiveAudio owns it).
func window_openness() -> float:
	return perspective.window

func mode_name() -> String:
	if view == View.HOOD:
		return "HOOD"
	return "COCKPIT" if view == View.COCKPIT else MODE_NAMES[mode]

# Polled on the physics tick like all game input (#30), and the impact check
# needs exactly one velocity sample per tick.
func _physics_process(delta: float) -> void:
	if ViewSettings.camera_smoothing != _seen_smoothing:   # the Settings slider changed it
		_seen_smoothing = ViewSettings.camera_smoothing
		mode = _seen_smoothing
	if Input.is_action_just_pressed("camera_view"):
		# cockpit -> hood -> chase -> cockpit; remembered for the next start
		set_view(View.HOOD if view == View.COCKPIT else (View.CHASE if view == View.HOOD else View.COCKPIT))
		ViewSettings.set_camera_view(ViewSettings.CAMERA_VIEWS[view])
		if ViewSettings.remembers_view():
			ViewSettings.save_settings()
	look_back = Input.is_action_pressed("look_back")
	# the left hand does one thing at a time: the window key waits while it is out on a gesture
	var gesturing := frame != null and frame.driver != null and frame.driver.is_gesturing()
	# nor during a puff or a sip; a window tap in the middle of one is kept and played once the hand is back
	var idling := frame != null and frame.driver != null and frame.driver.is_idling()
	var window_down := Input.is_action_pressed("window")
	if idling:
		if window_down:
			_window_tap = 1
		elif _window_tap == 1:
			_window_tap = WINDOW_TAP_TICKS + 1   # pressed and let go during the use
	elif _window_tap == 1:
		_window_tap = 0                          # still held: the key itself carries on
	elif _window_tap > 1:
		_window_tap -= 1
		window_down = _window_tap > 1            # the kept tap: down for WINDOW_TAP_TICKS, then up
	perspective.window_key(window_down and not gesturing and not idling, delta)
	if frame != null:
		frame.set_window(perspective.window, perspective.window_direction())
		if frame.driver != null:
			var aim := DriverModel.AIM_BACK if look_back else (DriverModel.AIM_LEFT if Input.is_action_pressed("look_left") else DriverModel.AIM_AHEAD)
			frame.driver.gesture_key(Input.is_action_pressed("flip_off"), aim)
			frame.driver.idle_key(Input.is_action_pressed("idle_action"))
	# where the driver's head points, for the radio and the window's wind
	perspective.head_yaw_deg = look_yaw + (180.0 if look_back else 0.0) if view == View.COCKPIT else 0.0
	if perspective.car_audio == null:
		for c in target.get_children():
			if c is CarAudio:
				perspective.car_audio = c
				c.road_bump.connect(road_bump)
	var v := target.linear_velocity
	var dv := (v - _prev_vel).length()
	if delta > 0.0:
		lat_accel = -(v - _prev_vel).dot(target.global_transform.basis.x) / delta
	_prev_vel = v
	register_impact(dv)
	var speed := target.current_speed()
	_accel = (speed - _prev_speed) / delta
	_prev_speed = speed
	# smoothed here, once per tick: a drawn frame that spans several ticks would
	# otherwise sample the tick-to-tick jitter of a car standing on its brakes
	_give_accel = lerpf(_give_accel, _accel, 1.0 - exp(-GIVE_ACCEL_RATE * delta))

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
		# damage: the drawn wheel rests crooked by the front toe bend x this car's steering ratio
		target.damage.steering_ratio = CockpitFrame.WHEEL_LOCK_RAD / maxf(target.max_steering_angle, 0.01)
		frame.steer_centre = target.steer_centre_view(CockpitFrame.WHEEL_LOCK_RAD)
	if view == View.COCKPIT:
		_place_cockpit(delta)
		if look_back:
			global_transform.basis = global_transform.basis * Basis(Vector3.UP, PI)
		if shake_enabled:
			_shake(delta, false)
			rotate_object_local(Vector3.RIGHT, BUMP_ROT * bump * AccessSettings.shake_scale)
	elif view == View.HOOD and not hood_open():
		_place_hood(delta)
		if shake_enabled:
			_shake(delta, false, HOOD_STRENGTH)
			rotate_object_local(Vector3.RIGHT, BUMP_ROT * bump * HOOD_STRENGTH * AccessSettings.shake_scale)
	else:
		_place(delta)   # the chase rig (also the hood view while the hood is up)
		if shake_enabled:
			_shake(delta, true)
			global_position += global_basis.y * BUMP_POS * bump * AccessSettings.shake_scale
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
	fov = ViewSettings.cockpit_fov + _widening() * COCKPIT_FOV_SPEED_GAIN * speed_t

## On the bonnet: the interpolated body transform, levelled and leaning into
## corners at HOOD_STRENGTH, no head sway, FOV as in the cockpit. B moves it to
## the roof camera looking straight back.
func _place_hood(delta: float) -> void:
	var xf := target.get_global_transform_interpolated()
	_update_look(delta)
	var level := _levelled(xf.basis, HOOD_STRENGTH)
	if look_back:
		global_transform = Transform3D(level * Basis(Vector3.UP, PI), xf * roof_back_cam)
	else:
		var turn := Basis.from_euler(Vector3(deg_to_rad(look_pitch), deg_to_rad(look_yaw + corner_yaw), 0.0))
		global_transform = Transform3D(level * turn, xf * hood_cam)
	fov = ViewSettings.hood_fov + _widening() * COCKPIT_FOV_SPEED_GAIN * speed_t

## 1 with the View page's "Speed FOV widening" on, 0 with it off.
static func _widening() -> float:
	return 1.0 if AccessSettings.fov_widening else 0.0

## True while the hood is up, when the hood view shows the chase camera instead
## (the bonnet camera would be inside the lid). No roadside hood-pop sets one
## yet: CarDetail.panel_open (a hood, door or trunk open) is the flag the
## roadside kit is built to set, so this follows it; nothing sets it in play.
func hood_open() -> bool:
	var d := target.get_node_or_null(CarDetail.NODE_NAME) as CarDetail
	return d != null and d.panel_open

## The body's orientation with part of its roll and pitch taken out (C2): the
## camera's tilt against the world is (1 - HORIZON_*_LEVEL) of the body's. Yaw
## is untouched. The levelling fades out past HORIZON_FADE_LO_DEG..HI so a
## rollover is shown whole. Once per drawn frame; one Euler decompose and one
## compose, a few hundred nanoseconds.
func _levelled(b: Basis, strength := 1.0) -> Basis:
	var e := b.orthonormalized().get_euler(EULER_ORDER_YXZ)   # (pitch, yaw, roll)
	var roll_f := HORIZON_ROLL_LEVEL * strength * (1.0 - smoothstep(HORIZON_FADE_LO_DEG, HORIZON_FADE_HI_DEG, rad_to_deg(absf(e.z))))
	var pitch_f := HORIZON_PITCH_LEVEL * strength * (1.0 - smoothstep(HORIZON_FADE_LO_DEG, HORIZON_FADE_HI_DEG, rad_to_deg(absf(e.x))))
	return Basis.from_euler(Vector3(e.x * (1.0 - pitch_f), e.y, e.z * (1.0 - roll_f)), EULER_ORDER_YXZ)

## Eases the head toward where the arrow keys point it (or back to straight
## ahead), and focuses the door mirror it has turned to. A key tapped (under
## LOOK_TAP_S) stops at the door mirror and stays there a moment; held, the head
## goes on turning. With no key down, the view leans toward the bend (C4).
func _update_look(delta: float) -> void:
	var hood := view == View.HOOD
	var axis := Input.get_axis("look_right", "look_left")   # + = left
	var up := Input.get_axis("look_down", "look_up")
	if hood and look_back:
		axis = 0.0   # B: the roof camera looks straight back, the arrows wait
		up = 0.0
		_hold_dir = 0
		_hold_t = 0.0
		_latch_t = 0.0
	var want_yaw := 0.0
	if axis != 0.0:
		var dir := 1 if axis > 0.0 else -1
		if dir != _hold_dir:
			_hold_dir = dir
			_hold_t = 0.0
		_hold_t += delta
		_latch_t = 0.0
		want_yaw = axis * (LOOK_MIRROR_YAW if _hold_t < LOOK_TAP_S else (HOOD_YAW_MAX if hood else LOOK_YAW_MAX))
	else:
		if _hold_dir != 0 and _hold_t < LOOK_TAP_S:
			_latch_dir = _hold_dir
			_latch_t = LOOK_TAP_LATCH_S
		_hold_dir = 0
		_hold_t = 0.0
		if _latch_t > 0.0:
			_latch_t -= delta
			want_yaw = _latch_dir * LOOK_MIRROR_YAW
	var want_pitch := up * ((HOOD_PITCH_UP if hood else LOOK_PITCH_UP) if up > 0.0 else (HOOD_PITCH_DOWN if hood else LOOK_PITCH_DOWN))
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
		# the speed along the ground, not along the nose: a car 60 deg sideways
		# is still going fast
		var gate := smoothstep(CORNER_SPEED_LO, CORNER_SPEED_HI, Vector2(target.linear_velocity.x, target.linear_velocity.z).length())
		_update_travel()
		want_corner = drift_look(signf(w) * strength * CORNER_LOOK_MAX_DEG, travel_deg, slip_deg) * gate * (HOOD_STRENGTH if hood else 1.0)
	corner_yaw = lerpf(corner_yaw, want_corner, corner_k)
	_set_look_focus(0 if hood or absf(look_yaw) < LOOK_FOCUS_YAW else (-1 if look_yaw > 0.0 else 1))

## travel_deg / slip_deg from the car's velocity in its own frame. Under 1 m/s
## there is no direction of travel to speak of: both read 0.
func _update_travel() -> void:
	var lv := target.global_transform.basis.inverse() * target.linear_velocity
	if Vector2(lv.x, lv.z).length() < 1.0:
		travel_deg = 0.0
	else:
		travel_deg = rad_to_deg(atan2(-lv.x, -lv.z))   # + = to the car's left (about +y)
	slip_deg = absf(travel_deg)

## The cockpit look's yaw (degrees, + = left) for a corner look of `grip_deg`
## (the yaw-rate turn, C4) while the car travels `travel` degrees off its nose:
## the grip look under DRIFT_SLIP_LO of slip, the travel direction (capped at
## DRIFT_LOOK_MAX_DEG) from DRIFT_SLIP_HI, a blend between, faded out in a spin.
static func drift_look(grip_deg: float, travel: float, slip: float) -> float:
	var t := smoothstep(DRIFT_SLIP_LO, DRIFT_SLIP_HI, slip)
	var drift := clampf(travel, -DRIFT_LOOK_MAX_DEG, DRIFT_LOOK_MAX_DEG) * (1.0 - smoothstep(DRIFT_SPIN_LO, DRIFT_SPIN_HI, slip))
	return lerpf(grip_deg, drift, t)

func _set_look_focus(side: int) -> void:
	if side == _look_focus:
		return
	_look_focus = side
	if frame != null and frame.mirrors != null:
		frame.mirrors.set_focus(side)

## Head sway from lateral g (lat_accel, #641) and longitudinal g (the speed
## derivative the FOV already uses). +x is the passenger side: a left turn
## (yaw rate +) slides the head right (outward) but tips it LEFT, into the
## corner (positive roll about +z; it used to roll with the body, outward);
## braking (accel -) moves it forward (-z) and dips it (negative pitch about +x).
func _update_head(delta: float) -> void:
	var want_offset := Vector3.ZERO
	var want_tilt := Vector2.ZERO
	if FxSettings.is_on("head_motion"):
		var lat_g := clampf(lat_accel / 9.81 / HEAD_G_FULL, -1.0, 1.0)
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
	var want_a := clampf(_accel * FOV_ACCEL_GAIN, FOV_ACCEL_MIN, FOV_ACCEL_MAX) * _widening()
	accel_fov = lerpf(accel_fov, want_a, 1.0 - exp(-ACCEL_RATE * delta))
	# The View page's chase FOV is the rest; the widening keeps its 16 degrees.
	var rest := ViewSettings.chase_fov
	fov = rest + (FOV_FAST - FOV_REST) * speed_t * _widening() + accel_fov
	# Dolly: scale the distance by how much the frustum widened, part way.
	var widen := tan(deg_to_rad(rest) * 0.5) / tan(deg_to_rad(fov) * 0.5)
	_update_give(delta)
	dist_now = base_dist * ViewSettings.chase_dist_scale() * (DOLLY * widen + (1.0 - DOLLY)) + give
	height_now = base_height + ViewSettings.chase_dist_lift() - SQUAT * speed_t
	trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)
	# How rough the ground under the wheels is (SurfaceFeel): the pavement and
	# the kerb strip shake fully, the gritty shoulder about a third as much.
	var want_s := target.surface_feel.rough_share() * clampf(speed / 15.0, 0.0, 1.0)
	if not SurfaceFeel.enabled:
		var rough := 0
		var grounded := 0
		for w in target.wheel_array:
			if w.is_colliding():
				grounded += 1
				if w.surface_type != "Road":
					rough += 1
		want_s = float(rough) / float(grounded) * clampf(speed / 15.0, 0.0, 1.0) if grounded > 0 else 0.0
	# a wheel on its rim or a bent rim shakes the car the same way (flat_tyre.gd)
	want_s = maxf(want_s, target.wheel_shake)
	surface_t = lerpf(surface_t, want_s, 1.0 - exp(-12.0 * delta))

## The throttle / brake give: a critically damped spring (exact for any frame
## length, so the same at 60 or 144 fps) toward GIVE_M x the forward
## acceleration's share of full. Nothing while reversing or looking back (the
## rig is in front of the car then).
func _update_give(delta: float) -> void:
	var a := signf(_give_accel) * maxf(0.0, absf(_give_accel) - GIVE_DEAD)
	var want := 0.0
	if target.gear != -1 and not look_back:
		want = GIVE_M * (clampf(a / (GIVE_ACCEL_FULL - GIVE_DEAD), 0.0, 1.0) if a > 0.0 else -clampf(-a / (GIVE_BRAKE_FULL - GIVE_DEAD), 0.0, 1.0))
	var xv := spring(give, _give_v, want, GIVE_HALF_LIFE, delta)
	give = xv.x
	_give_v = xv.y

## One step of a critically damped spring (position x, speed v) toward `goal`:
## the exact solution, so any split of the same time lands in the same place.
## Returns the new (x, v). half_life: seconds to close half the gap.
static func spring(x: float, v: float, goal: float, half_life: float, dt: float) -> Vector2:
	var y := 2.0 * log(2.0) / half_life
	var j0 := x - goal
	var j1 := v + j0 * y
	var e := exp(-y * dt)
	return Vector2(e * (j0 + j1 * dt) + goal, e * (v - j1 * y * dt))

## Eases orbit_yaw / orbit_lift toward the arrow keys (chase view only).
## Tap-or-hold uses the cockpit's constants (LOOK_TAP_S, LOOK_TAP_LATCH_S).
## Holding B keeps the timer running but wants 0 and starts no latch, so an
## arrow still down when B is released carries straight on as a hold.
func _update_orbit(delta: float) -> void:
	var axis := Input.get_axis("look_right", "look_left")   # + = left
	var up := Input.get_axis("look_down", "look_up")
	var want_yaw := 0.0
	if axis != 0.0:
		var dir := 1 if axis > 0.0 else -1
		if dir != _orbit_dir:
			_orbit_dir = dir
			_orbit_hold_t = 0.0
		_orbit_hold_t += delta
		_orbit_latch_t = 0.0
		want_yaw = axis * (ORBIT_TAP_DEG if _orbit_hold_t < LOOK_TAP_S else ORBIT_HOLD_DEG)
	else:
		if _orbit_dir != 0 and _orbit_hold_t < LOOK_TAP_S and not look_back:
			_orbit_latch_dir = _orbit_dir
			_orbit_latch_t = LOOK_TAP_LATCH_S
		_orbit_dir = 0
		_orbit_hold_t = 0.0
		if _orbit_latch_t > 0.0:
			_orbit_latch_t -= delta
			want_yaw = _orbit_latch_dir * ORBIT_TAP_DEG
	if look_back:
		want_yaw = 0.0
		up = 0.0
		_orbit_latch_t = 0.0
	var k := 1.0 - exp(-ORBIT_RATE * delta)
	orbit_yaw = lerpf(orbit_yaw, want_yaw, k)
	orbit_lift = lerpf(orbit_lift, up, k)

func _place(delta: float) -> void:
	_update_orbit(delta)
	# The interpolated position, not target.position: the car only moves on
	# the 60 Hz physics tick, and with vsync off the camera updates several
	# times per tick. Following the raw position made car and road judder.
	var p := target.get_global_transform_interpolated().origin
	# Road space (RoadFrame, #37): across / up / along the road. Everything
	# below is worked in it and rolled back to the world at the end, so on a
	# straight road it is the old world-axis rig.
	var u := RoadFrame.unroll(p)
	# The rig sits behind the CAR and looks the way the car faces (Roy,
	# 2026-10-13). It used to sit behind the car along the ROAD and look down
	# it, so round a roundabout it stared down the highway while the car
	# circled, up to 120 degrees off, then flipped side at 60 degrees from
	# across the road (tests/view/chase_ring_recenter). Now it follows the
	# car's heading at HEADING_RATE: in a steady turn it trails the car by a
	# few degrees (yaw rate / HEADING_RATE), never by a quarter turn.
	var fwd := RoadFrame.dir_to_road(u.z, -target.global_transform.basis.z)
	var head := _head
	if Vector2(fwd.x, fwd.z).length() > 0.1:   # not pointing straight up or down
		head = atan2(-fwd.x, -fwd.z)
	# Reversing turns the chase cam to the other side of the car looking the
	# other way (2026-09-13 fix, kept); so does holding look_back.
	var want_flip := PI if (target.gear == -1 or look_back) else 0.0
	if mode == 0 or not _started:
		_follow = Vector2(u.x, u.y)
		_follow_z = u.z
		_head = head
		_flip = want_flip
		_started = true
	else:
		# Frame-rate independent ease: the same feel at 60 or 300 fps.
		_head = lerp_angle(_head, head, 1.0 - exp(-HEADING_RATE * delta))
		# Distance along the rig's own line stays locked to the car (the dolly
		# shortens it with speed); only sideways and height motion is smoothed.
		var along := Vector2(-sin(_head), -cos(_head))
		var d := Vector2(u.x - _follow.x, u.z - _follow_z)
		var lock := along * d.dot(along)
		var side := (d - lock) * (1.0 - exp(-FOLLOW_RATE * delta))
		_follow.x += lock.x + side.x
		_follow_z += lock.y + side.y
		_follow.y = lerpf(_follow.y, u.y, 1.0 - exp(-FOLLOW_RATE * delta))
		if mode == 2:
			_flip = lerpf(_flip, want_flip, 1.0 - exp(-SWING_RATE * delta))
		else:
			_flip = want_flip
	_yaw = _head + _flip
	# The orbit goes round the car's own sides: with the rig behind the car
	# (flip 0) Left is minus about +y, in front of it (flip PI: reversing, B)
	# it is plus; it runs through 0 (not a jump) while the rig swings round.
	var orbit := -cos(_flip) * deg_to_rad(orbit_yaw)
	var back := Vector3(0, 0, dist_now).rotated(Vector3.UP, _yaw + orbit)
	var ahead := Vector3(0, 0, -look_ahead).rotated(Vector3.UP, _yaw)
	var h := height_now + ORBIT_LIFT_UP_M * orbit_lift
	if orbit_lift < 0.0:
		h = lerpf(height_now, ORBIT_LOW_ABOVE_ROAD_M - _follow.y, -orbit_lift)
	var anchor_rs := Vector3(_follow.x + back.x, _follow.y + h, _follow_z + back.z)
	if not RoadMap.tunnels().is_empty():
		var depth := RoadMap.tunnel_depth(RoadFrame.s_at(anchor_rs.z))
		anchor_rs.y = minf(anchor_rs.y, TunnelKit.CLEAR_H - WALL_GAP + maxf(0.0, -depth) * WALL_MOUTH_SLOPE)
	anchor = RoadFrame.roll(anchor_rs)
	_wall_check(delta, u, anchor_rs)
	var aim_rs := Vector3(_follow.x + ahead.x, _follow.y + look_height, _follow_z + ahead.z)
	var centre_t := smoothstep(ORBIT_AIM_LO_DEG, ORBIT_AIM_HI_DEG, absf(orbit_yaw))
	if centre_t > 0.0:
		# the middle of the body, not the car's origin: the origin sits at the
		# wheels' axle-line mid point, well behind and above the body's centre
		# on most cars, which put the car off centre side-on (chase_orbit)
		var centre := RoadFrame.unroll(target.get_global_transform_interpolated() * _body_centre())
		aim_rs = aim_rs.lerp(centre, centre_t)
	aim = RoadFrame.roll(aim_rs)
	global_position = anchor
	look_at(aim, Vector3.UP)

## Pulls `anchor` in toward the car's roof when the world is in the way (see
## WALL_MASK). Two rays at most per drawn frame; with nothing hit and wall_f
## back at 1 the anchor is exactly the rig's.
func _wall_check(delta: float, u: Vector3, anchor_rs: Vector3) -> void:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return
	var xf := target.get_global_transform_interpolated()
	_body_centre()
	var from := xf * Vector3(_centre_local.x, _roof_local + WALL_ROOF_UP, _centre_local.z)
	var line := anchor - from
	var full := line.length()
	var want := 1.0
	wall_hit = false
	if full > WALL_MIN_M:
		var q := PhysicsRayQueryParameters3D.create(from, anchor, WALL_MASK)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			want = ((hit.position as Vector3).distance_to(from) - WALL_GAP) / full
			wall_hit = true
		if absf(orbit_yaw) > WALL_LOW_ORBIT_DEG:
			var lo_from := RoadFrame.roll(Vector3(u.x, WALL_LOW_H, u.z))
			var lo_to := RoadFrame.roll(Vector3(anchor_rs.x, WALL_LOW_H, anchor_rs.z))
			var lo_len := lo_from.distance_to(lo_to)
			if lo_len > WALL_MIN_M:
				q = PhysicsRayQueryParameters3D.create(lo_from, lo_to, WALL_MASK)
				hit = space.intersect_ray(q)
				if not hit.is_empty():
					want = minf(want, ((hit.position as Vector3).distance_to(lo_from) - WALL_GAP) / lo_len)
					wall_hit = true
		want = clampf(want, WALL_MIN_M / full, 1.0)
	if want < wall_f:
		wall_f = want   # in at once: not one frame inside the wall
	else:
		wall_f = lerpf(wall_f, want, 1.0 - exp(-WALL_OUT_RATE * delta))
		if wall_f > 0.999:   # 5 mm at the chase distance: the last bit snaps
			wall_f = 1.0
	if wall_f < 1.0:
		anchor = from + line * wall_f

## The middle of the car's drawn body in the car's own frame (the box round
## every visible part of chassis_visual), for the orbit's aim. Worked out once
## per body; the origin with look_height when there is no body yet.
var _centre_of: Node3D = null
var _centre_local := Vector3.ZERO
var _roof_local := 1.4   # top of that box (the wall check's ray starts above it)

func _body_centre() -> Vector3:
	var vis := target.chassis_visual
	if vis == null or not is_instance_valid(vis):
		_centre_local = Vector3(0.0, look_height, 0.0)
		return _centre_local
	if vis == _centre_of:
		return _centre_local
	var to_car := target.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for n in vis.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if not vi.is_visible_in_tree():
			continue
		var b := (to_car * vi.global_transform) * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		_centre_local = Vector3(0.0, look_height, 0.0)
		return _centre_local
	_centre_of = vis
	_centre_local = box.get_center()
	_roof_local = box.end.y
	return _centre_local

## Smooth noise shake applied on top of the chase transform. Amplitude adds
## the three sources; impact uses trauma^2 so small knocks stay small. In the
## cockpit it is rotation only (with_position false): the eye never leaves the
## cabin on a hit.
func _shake(delta: float, with_position: bool, strength := 1.0) -> void:
	strength *= AccessSettings.shake_scale   # the View page's Camera shake row
	var buzz := pow(speed_t, 1.5)
	var start := target.start_shake * (START_SHAKE_CHASE if with_position else 1.0)
	var rot := (SPEED_SHAKE_ROT * buzz + SURFACE_SHAKE_ROT * surface_t + IMPACT_SHAKE_ROT * trauma * trauma + START_SHAKE_ROT * start) * strength
	var pos := (SPEED_SHAKE_POS * buzz + SURFACE_SHAKE_POS * surface_t + IMPACT_SHAKE_POS * trauma * trauma + START_SHAKE_POS * start) * strength
	if rot <= 0.0 and pos <= 0.0:
		return
	# Faster wobble for rough surface and hits than for the speed buzz.
	_t += delta * (6.0 + 10.0 * surface_t + 14.0 * trauma + 12.0 * start)
	rotate_object_local(Vector3.RIGHT, rot * _noise.get_noise_2d(_t, 0.0))
	rotate_object_local(Vector3.UP, rot * 0.6 * _noise.get_noise_2d(_t, 100.0))
	rotate_object_local(Vector3.BACK, rot * 0.8 * _noise.get_noise_2d(_t, 200.0))
	if with_position:
		global_position += global_basis * Vector3(pos * _noise.get_noise_2d(_t, 300.0), pos * _noise.get_noise_2d(_t, 400.0), 0.0)
