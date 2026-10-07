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
const SURFACE_SHAKE_ROT := 0.008 # kerb/sidewalk rumble ("Dirt" surface)
const SURFACE_SHAKE_POS := 0.02
const IMPACT_SHAKE_ROT := 0.035  # ~2 deg at full trauma
const IMPACT_SHAKE_POS := 0.12
const TRAUMA_DECAY := 1.6        # 1/s
## Velocity change in one physics tick (m/s) above which it counts as a hit.
## Hard braking peaks well under this (see tests/camera_feel.gd); a wall at
## speed is several times over it.
const IMPACT_DV := 0.8
const IMPACT_GAIN := 0.12        # trauma per m/s over the threshold

## Phase C: the cockpit view (F toggles). VIEW_CHASE is everything above; in
## VIEW_COCKPIT the camera sits at the driver's eye, rigid to the car, the body
## is kept off this camera (it stays in the mirrors) and the CockpitFrame (the
## whole interior, wheel, cluster, mirrors) is shown.
## The eye (cockpit milestone, 2026-10-06): seat height in the P1's cabin, just
## ahead of the B-pillar, a hand's width inboard of the seat centre (-0.36) so
## the passenger-side door mirror is still inside the view at the default FOV.
enum View { CHASE, COCKPIT }
const COCKPIT_EYE := Vector3(-0.32, 1.10, 0.30)  # car-local, -x is the driver's side (left-hand drive)
const COCKPIT_FOV_SPEED_GAIN := 6.0  # degrees added at top speed; the base is ViewSettings.cockpit_fov (default 62)
## Head movement in the cockpit (Roy, 2026-10-06): the eye sways with the
## car's forces, capped at HEAD_MAX_M (4 cm) and HEAD_MAX_DEG (2 degrees).
## Lateral g pushes the head outward and rolls it with the body; braking
## brings it forward and dips it, acceleration presses it back. The cap is
## reached at HEAD_G_FULL g and the motion is smoothed at HEAD_RATE, so bumps
## in the sim's speed reading do not twitch the view. FxSettings "head_motion"
## ([fx] in settings.cfg, NEON_FX=0) is the off switch: off, the eye eases
## back to COCKPIT_EYE and stays rigid to the car.
const HEAD_MAX_M := 0.04
const HEAD_MAX_DEG := 2.0
const HEAD_G_FULL := 0.8
const HEAD_RATE := 6.0
var head_offset := Vector3.ZERO   # car-local, metres, current
var head_tilt := Vector2.ZERO     # (pitch, roll) degrees, current
var view := View.CHASE
## Look back (hold the look_back key, B): the chase cam swings to the front
## of the car and looks back at it, the same move as reversing; the cockpit
## eye turns 180 degrees to the rear window.
var look_back := false
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
var surface_t := 0.0   # 0..1, share of wheels on a rough surface (scaled by speed)
var dist_now := DIST
var height_now := HEIGHT
var anchor := Vector3.ZERO  # chase position before shake
var aim := Vector3.ZERO     # point the rig looks at before shake

var _follow := Vector2.ZERO
var _yaw := 0.0
var _started := false
var _prev_vel := Vector3.ZERO
var _prev_speed := 0.0
var _accel := 0.0
var _t := 0.0
var _noise := FastNoiseLite.new()

func _init(car: PlayerCar) -> void:
	target = car
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
	if frame != null:
		frame.set_cockpit(cockpit)
	elif target.chassis_visual != null:
		target.chassis_visual.visible = not cockpit   # no cockpit built: the Phase C behaviour
	perspective.set_cockpit(cockpit)

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
	var v := target.linear_velocity
	var dv := (v - _prev_vel).length()
	_prev_vel = v
	register_impact(dv)
	var speed := target.current_speed()
	_accel = (speed - _prev_speed) / delta
	_prev_speed = speed

## Feeds one tick's velocity change (m/s) into the impact shake. Split out so
## tests/camera_feel.gd can check the tick-rate independence directly.
func register_impact(dv: float) -> void:
	# The per-tick velocity change scales with the tick length, so scale the
	# threshold. The gain stays as is: at twice the rate each tick's excess is
	# half as big and there are twice as many ticks, so the total trauma from
	# one impact is already the same. (It used to be multiplied by rate/60 as
	# well, which made kerb shake ~7x stronger at 120 Hz.)
	var dv_limit := IMPACT_DV * 60.0 / float(Engine.physics_ticks_per_second)
	if dv > dv_limit:
		trauma = minf(1.0, trauma + (dv - dv_limit) * IMPACT_GAIN)

func _process(delta: float) -> void:
	_update_feel(delta)
	if view == View.COCKPIT:
		_place_cockpit(delta)
		if look_back:
			global_transform.basis = global_transform.basis * Basis(Vector3.UP, PI)
		if frame != null:
			frame.steering = target.steer_fraction()  # the wheel turns the way the car does
		if shake_enabled:
			_shake(delta)
		return
	_place(delta)
	if shake_enabled:
		_shake(delta)

## At the driver's eye, on the interpolated transform (same reason as the
## chase cam), looking where the car points, plus the head movement; a fixed
## FOV that widens a touch with speed.
func _place_cockpit(delta: float) -> void:
	var xf := target.get_global_transform_interpolated()
	_update_head(delta)
	var tilt := Basis.from_euler(Vector3(deg_to_rad(head_tilt.x), 0.0, deg_to_rad(head_tilt.y)))
	global_transform = Transform3D(xf.basis * tilt, xf * (COCKPIT_EYE + head_offset))
	fov = ViewSettings.cockpit_fov + COCKPIT_FOV_SPEED_GAIN * speed_t

## Head sway from lateral g (yaw rate x speed) and longitudinal g (the speed
## derivative the FOV already uses). +x is the passenger side: a left turn
## (yaw rate +) throws the head right and rolls the body right (negative roll
## about +z); braking (accel -) moves it forward (-z) and dips it (negative
## pitch about +x).
func _update_head(delta: float) -> void:
	var want_offset := Vector3.ZERO
	var want_tilt := Vector2.ZERO
	if FxSettings.is_on("head_motion"):
		var lat_g := clampf(target.angular_velocity.y * target.current_speed() / 9.81 / HEAD_G_FULL, -1.0, 1.0)
		var long_g := clampf(_accel / 9.81 / HEAD_G_FULL, -1.0, 1.0)
		want_offset = Vector3(lat_g, 0.0, long_g).limit_length(1.0) * HEAD_MAX_M
		want_tilt = Vector2(long_g, -lat_g).limit_length(1.0) * HEAD_MAX_DEG
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
	dist_now = DIST * (DOLLY * widen + (1.0 - DOLLY))
	height_now = HEIGHT - SQUAT * speed_t
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
	# Reversing flips the chase cam to the opposite side of the car looking
	# the opposite way (2026-09-13 fix, kept); so does holding look_back.
	var target_yaw := PI if (target.gear == -1 or look_back) else 0.0
	if mode == 0 or not _started:
		_follow = Vector2(p.x, p.y)
		_yaw = target_yaw
		_started = true
	else:
		# Frame-rate independent ease: the same feel at 60 or 300 fps.
		_follow = _follow.lerp(Vector2(p.x, p.y), 1.0 - exp(-FOLLOW_RATE * delta))
		if mode == 2:
			_yaw = lerpf(_yaw, target_yaw, 1.0 - exp(-SWING_RATE * delta))
		else:
			_yaw = target_yaw
	# Distance along the road stays locked to the car (only sideways and
	# height motion is smoothed); the dolly shortens it with speed.
	var back := Vector3(0, 0, dist_now).rotated(Vector3.UP, _yaw)
	var ahead := Vector3(0, 0, -LOOK_AHEAD).rotated(Vector3.UP, _yaw)
	anchor = Vector3(_follow.x + back.x, _follow.y + height_now, p.z + back.z)
	aim = Vector3(_follow.x + ahead.x, _follow.y + LOOK_HEIGHT, p.z + ahead.z)
	global_position = anchor
	look_at(aim, Vector3.UP)

## Smooth noise shake applied on top of the chase transform. Amplitude adds
## the three sources; impact uses trauma^2 so small knocks stay small.
func _shake(delta: float) -> void:
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
	global_position += global_basis * Vector3(pos * _noise.get_noise_2d(_t, 300.0), pos * _noise.get_noise_2d(_t, 400.0), 0.0)
