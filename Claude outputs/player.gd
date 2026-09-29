extends VehicleBody3D
class_name PlayerCar

# Milestone 2: real player physics. Replaces the milestone-1 kinematic test
# rig entirely -- this is a genuine VehicleBody3D with real VehicleWheel3D
# suspension, not a hidden physics sandbox puppeting a separate visual (see
# the 2026-09-12 "no faking" decision in memory/ROADMAP.md). The chassis
# visual and each wheel's visual mesh are real children of the real physics
# nodes, so suspension travel/roll/pitch you see is the actual simulation.
#
# Gear/speed governing carries the drivetrain RULES from milestone 1's test
# rig (see game.gd's old _update_drivetrain) but the movement itself is now
# real forces, not position += speed. Top speed per gear is enforced as a
# velocity governor layered on top of real physics -- a deliberate
# simplification instead of simulating engine RPM/redline, flagged here so
# it's not mistaken for full sim: real cars limit gear top speed via RPM
# redline, we just clamp forward speed directly. Cheap, tunable, easy to
# replace with real RPM math later if it doesn't feel right.

const KIND := "coupe"
const CFG := {
	"wheel_r": 0.34, "axle_z": 1.05, "wheel_x": 0.88,
}

const GEAR_TOP_SPEED := [7.0, 12.0, 17.5, 22.0, 26.0]  # m/s, forward gears 1-5
const REVERSE_TOP_SPEED := 6.0
const ENGINE_FORCE_MAG := 1400.0
const BRAKE_FORCE := 45.0
const STEER_MAX := 0.45   # radians, at low speed
const STEER_MIN := 0.12   # radians, at top speed
const SHIFT_SAFE_SPEED := 1.0

var gear := 0  # -1 Reverse, 0 Neutral, 1-5 forward
var shift_flash_t := 0.0

var wheels: Array = []  # VehicleWheel3D, front-left/front-right/rear-left/rear-right

func _ready() -> void:
	mass = 1100.0
	linear_damp = 0.15
	# Zero angular damping left any stray torque (e.g. from asymmetric wheel
	# contact while settling) to build up forever instead of decaying --
	# cheap insurance against the vehicle spinning/flipping under real
	# suspension forces (Bullet-derived vehicle solvers are known-twitchy here).
	angular_damp = 4.0

	var chassis := CarBuilder.build_chassis_visual(KIND, Color(0, 0.96, 1))
	add_child(chassis)

	# Chassis collision shape -- wheels handle ground contact via their own
	# raycasts, but the body itself still needs a shape (side impacts, and
	# milestone 6's crash/damage detection will want this too).
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 0.6, 3.4)
	col.shape = box
	col.position = Vector3(0.0, 0.35, 0.0)
	add_child(col)

	# Mount height must be wheel_rest_length + wheel_radius, NOT just
	# wheel_radius -- Godot's suspension raycast (ported from Bullet's
	# btRaycastVehicle) starts at the wheel node's own local position and
	# reaches down exactly rest_length + radius. Undershooting this pins the
	# suspension fully bottomed-out from frame one instead of resting neutrally.
	var WHEEL_REST_LENGTH := 0.3
	var WHEEL_MOUNT_Y: float = WHEEL_REST_LENGTH + CFG.wheel_r
	var wheel_positions := [
		Vector3(CFG.wheel_x, WHEEL_MOUNT_Y, -CFG.axle_z),   # front-left
		Vector3(-CFG.wheel_x, WHEEL_MOUNT_Y, -CFG.axle_z),  # front-right
		Vector3(CFG.wheel_x, WHEEL_MOUNT_Y, CFG.axle_z),    # rear-left
		Vector3(-CFG.wheel_x, WHEEL_MOUNT_Y, CFG.axle_z),   # rear-right
	]
	for i in range(4):
		var w := VehicleWheel3D.new()
		w.position = wheel_positions[i]
		w.wheel_radius = CFG.wheel_r
		w.wheel_rest_length = WHEEL_REST_LENGTH
		# Must stay below wheel_rest_length -- suspension_travel > rest_length
		# makes the engine's own clamp bounds (rest_length ± travel) go
		# negative, an invalid range that silently kills the supporting force.
		w.suspension_travel = 0.2
		w.suspension_stiffness = 45.0
		w.suspension_max_force = 6000.0
		w.damping_compression = 0.4
		w.damping_relaxation = 0.5
		w.wheel_friction_slip = 1.4
		w.use_as_steering = i < 2  # front two
		w.use_as_traction = true    # AWD for a controllable first pass -- easy to switch to RWD later once handling is being tuned for feel
		add_child(w)
		var visual := CarBuilder.build_wheel_visual(KIND)
		w.add_child(visual)
		wheels.append(w)

func _shift(delta_gear: int) -> void:
	var target := clampi(gear + delta_gear, -1, 5)
	if target == gear:
		return
	var speed := -linear_velocity.z
	if (target == -1 or gear == -1) and abs(speed) > SHIFT_SAFE_SPEED:
		return
	gear = target
	shift_flash_t = 0.2

func current_speed() -> float:
	return -linear_velocity.z  # forward = -Z, matches the road-chunk convention

func _physics_process(delta: float) -> void:
	var throttle := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	var braking := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
	var steer_in := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		steer_in -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		steer_in += 1.0

	var speed := current_speed()
	var speed_frac: float = clamp(abs(speed) / GEAR_TOP_SPEED[GEAR_TOP_SPEED.size() - 1], 0.0, 1.0)
	var steer_max: float = lerp(STEER_MAX, STEER_MIN, speed_frac)
	var target_steer := -steer_in * steer_max
	for w in wheels:
		if w.use_as_steering:
			w.steering = target_steer

	var force := 0.0
	var brake_val := 0.0
	if braking:
		brake_val = BRAKE_FORCE
	elif gear == 0:
		force = 0.0
	elif gear > 0:
		if throttle:
			force = ENGINE_FORCE_MAG
	else:  # reverse
		if throttle:
			force = -ENGINE_FORCE_MAG

	for w in wheels:
		if w.use_as_traction:
			w.engine_force = force
			w.brake = brake_val

	# Governor: hard cap forward/reverse speed per gear (see class comment --
	# deliberate simplification instead of RPM/redline simulation).
	if gear > 0:
		var cap: float = GEAR_TOP_SPEED[gear - 1]
		linear_velocity.z = max(linear_velocity.z, -cap)  # forward = -Z
	elif gear == -1:
		linear_velocity.z = min(linear_velocity.z, REVERSE_TOP_SPEED)

	if shift_flash_t > 0.0:
		shift_flash_t -= delta

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_shift(-1)
		elif event.keycode == KEY_E:
			_shift(1)
