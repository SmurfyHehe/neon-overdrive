extends Vehicle
class_name TrafficCar

# Milestone 3 lane-follow traffic (stage B step 3, 2026-10-05, Roy: Option C).
#
# A traffic car IS the vendored raycast Vehicle the player drives
# (scripts/vendor/gevp/), built the same way PlayerCar is: CarSpec data,
# CarSpec.build_collision(), CarSpec.build_wheels(), initialize(). What differs
# from the player is only the spec dict (CarSpec.traffic_default() unless the
# spawner hands in another one), the body kind/colour, and who sets
# throttle_input/steering_input -- a lane-follow controller instead of the
# keyboard. There is no cheaper physics path for a car the player can see.
#
# Lane follow: pure pursuit (R. C. Coulter, "Implementation of the Pure Pursuit
# Path Tracking Algorithm", CMU-RI-TR-92-01, 1992): aim at the point on the lane
# centre `lookahead` metres ahead and steer with the curvature of the circular
# arc through it; the lookahead grows with speed so the car does not weave at
# highway speed. Speed hold is a throttle-only P controller on target_speed.
# No brake input, ever, by design: milestone 3 is lane-follow only, braking and
# swerving for other cars is milestone 4 (ROADMAP stage B).
#
# Far cars (TrafficManager.detail_distance): a car that is further from the
# player than the draw distance is hidden and frozen as a kinematic body that
# cruises along its lane; the full sim resumes, with position, speed and heading
# handed over, when it comes back inside. That is the one scoped exception to
# the same-sim rule (ROADMAP stage B, "Traffic fallback"), and it is only for
# cars that are not drawn. Why not "run the sim every other tick" for far cars:
# the Wheel applies its spring and tyre forces per physics step, so a car that
# skips a step gets gravity without suspension on that step and sags; the
# honest cheap path is no sim at all plus a clean handover.

## CarBuilder.KIND_CONFIGS key for the body and wheel visuals. The three NPC
## cars (stage B step 5) swap this and `spec` per car; nothing else changes.
var kind := "coupe"
## Vehicle tune (CarSpec dict). Empty = CarSpec.traffic_default(). Set before
## add_child(), like PlayerCar.spec.
var spec := {}
var color := Color(0.6, 0.6, 0.65)
## No body mesh, lights or shadow (tests and the perf harness).
var sim_only := false

## World x of the lane centre this car holds (RoadChunkBuilder lane maths).
var lane_x := 0.0
## -1.0 drives the player's way (forward is -Z, the road-chunk convention);
## +1.0 is oncoming. Set together with the spawn yaw by TrafficManager.
var direction := -1.0
## Cruise speed, m/s.
var target_speed := 25.0

## Aero, same two plain vars PlayerCar declares: CarSpec.apply() sets them
## through v.set() and AeroModel reads them. Traffic gets small values from
## traffic_default().
var aero_downforce_coefficient_front := 0.0
var aero_downforce_coefficient_rear := 0.0

var chassis_visual: Node3D
var wheelbase := 2.5
## True while the full sim runs (inside the draw distance). See set_detailed().
var detailed := true
var _cruise_speed := 0.0

## Pure-pursuit lookahead: this many seconds of travel, clamped. GEVP turns the
## wheels toward the input at a rate that falls with speed (process_steering),
## so a short lookahead weaves at highway speed: with 0.6 s / 30 m max the
## scripted player oscillated 2 m either side of the lane for 20 s at 150 km/h
## (tests/scratch run, 2026-10-05). 1 s / 60 m is damped; 8 m is the floor so
## a car crawling after a spawn still aims somewhere ahead.
const LOOKAHEAD_SECONDS := 1.0
const LOOKAHEAD_MIN := 8.0
const LOOKAHEAD_MAX := 60.0
## Throttle per m/s of speed error: full throttle from 1.25 m/s under target.
## 0.35 sat 1.4 m/s under target at 85 km/h (drag needs about half throttle
## there); the engine's own drag does the slowing down.
const SPEED_P := 0.8

func _ready() -> void:
	# Not super._ready(): Vehicle's _ready() is initialize(), which needs the
	# wheels built first (same as PlayerCar).
	if spec.is_empty():
		spec = CarSpec.traffic_default()
	var cfg: Dictionary = CarBuilder.KIND_CONFIGS.get(kind, CarBuilder.KIND_CONFIGS["coupe"])
	wheelbase = float(cfg.axle_z) * 2.0

	if not sim_only:
		chassis_visual = CarBuilder.build_chassis_visual(kind, color)
		add_child(chassis_visual)

	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = PlayerCar.LINEAR_DAMP
	CarSpec.set_collision_layers(self)
	# Box sized from the body config, same height and seat as the player's
	# (CarSpec.build_collision's verified ground clearance).
	CarSpec.build_collision(self, Vector3(float(cfg.main_w), 1.0, float(cfg.main_z1) - float(cfg.hood_z0)), 0.7)
	CarSpec.apply(self, spec)
	CarSpec.build_wheels(self, kind, cfg, front_spring_length, rear_spring_length)
	initialize()
	current_gear = 1
	# Drafting (aero.gd) finds other cars through this group.
	add_to_group("aero_vehicles")
	if not sim_only:
		# Blob shadow only: 80 spotlights would be a rendering bill of their own.
		CarFx.attach(self, chassis_visual.get_meta("half_l", 1.7), false)

func _physics_process(delta: float) -> void:
	if not detailed:
		_cruise(delta)
		return
	_follow_lane()
	super._physics_process(delta)
	AeroModel.apply(self)

## The controller. Sets steering_input and throttle_input for this tick.
func _follow_lane() -> void:
	steering_input = lane_steer(self, lane_x, direction, wheelbase)
	throttle_input = clampf((target_speed - current_speed()) * SPEED_P, 0.0, 1.0)
	brake_input = 0.0
	handbrake_input = 0.0

## Below this speed the bearing uses the body heading, above it the velocity
## direction (see lane_steer).
const VELOCITY_FRAME_MIN_SPEED := 3.0

## Pure-pursuit steering toward the lane centre, as a steering_input in -1..1.
## Shared with the tests' scripted player so there is one lane-keeper. Sign:
## GEVP yaws LEFT for a positive input (see player.gd's keyboard note), so a
## target on the right gives a negative input.
##
## The bearing to the target is taken from the direction the car is MOVING,
## not the way its nose points. A GEVP car runs with a small standing sideslip
## (a few tenths of a degree), and a nose-based bearing then settles with the
## car offset from the lane by lookahead x sideslip: 0.43 m for the player at
## 246 km/h (60 m lookahead), 0.25 m for traffic, measured 2026-10-05. In
## adjacent lanes with 0.6 m between bodies that was a sideswipe at 340 km/h
## closing. An integral term was tried first and swung the player across the
## road at every gain from 0.03 down to 0.0001 per metre-second: at 65 m/s a
## thousandth of lock is 1 m/s^2 sideways. With the velocity frame the car is
## on the lane whenever it is moving along it, whatever its nose does.
static func lane_steer(v: Vehicle, lane: float, dir: float, wb: float) -> float:
	var lookahead := clampf(v.speed * LOOKAHEAD_SECONDS, LOOKAHEAD_MIN, LOOKAHEAD_MAX)
	var target := Vector3(lane, v.global_position.y, v.global_position.z + dir * lookahead)
	var fwd := -v.global_transform.basis.z
	var vel := v.linear_velocity
	vel.y = 0.0
	if vel.length() > VELOCITY_FRAME_MIN_SPEED and vel.dot(fwd) > 0.0:
		fwd = vel.normalized()
	else:
		fwd.y = 0.0
		fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var to_target := target - v.global_position
	var ahead := to_target.dot(fwd)
	var lateral := to_target.dot(right)
	var dist := maxf(Vector2(lateral, ahead).length(), 0.01)
	var alpha := atan2(lateral, ahead)  # bearing to the target, + = right
	var curvature := 2.0 * sin(alpha) / dist
	var steer_angle := atan(wb * curvature)
	var want := clampf(steer_angle / v.max_steering_angle, -1.0, 1.0)
	# GEVP raises the input to steering_exponent (1.5) before it reaches the
	# wheels (process_steering), which squashes small inputs: at 240 km/h the
	# lane-keeper asks for ~0.01 and got 0.001, so the loop went soft and
	# wandered off the lane in a slow 30 s swing (2026-10-05). Undo it here so
	# the wheels get the angle pure pursuit asked for.
	return -signf(want) * pow(absf(want), 1.0 / maxf(v.steering_exponent, 0.1))

func current_speed() -> float:
	return -local_velocity.z  # own forward, whichever way the car points

## Places the car in a lane, pointing along `dir`, moving at `speed`, with the
## sim's own history (previous positions, wheel spin) made consistent so the
## next tick does not read the teleport as a velocity burst (same care as
## game.gd's floating-origin shift).
func place(lane: float, dir: float, z: float, y: float, speed: float) -> void:
	lane_x = lane
	direction = dir
	var yaw := 0.0 if dir < 0.0 else PI
	global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(lane, y, z))
	_hand_over(speed)
	reset_physics_interpolation()
	if not detailed:
		_cruise_speed = speed

## Full sim on (inside the draw distance) or the frozen lane cruise (outside).
func set_detailed(on: bool) -> void:
	if on == detailed:
		return
	detailed = on
	visible = on and not sim_only
	if on:
		freeze = false
		_hand_over(_cruise_speed)
	else:
		_cruise_speed = maxf(current_speed(), 0.0)
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		# Snap to the lane, upright; nothing is drawn out here.
		var yaw := 0.0 if direction < 0.0 else PI
		global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(lane_x, global_position.y, global_position.z))
		reset_physics_interpolation()

## Frozen cruise: straight down the lane at the speed it had when it left the
## draw distance, nudged toward target_speed.
func _cruise(delta: float) -> void:
	_cruise_speed = move_toward(_cruise_speed, target_speed, 2.0 * delta)
	global_position.z += direction * _cruise_speed * delta
	previous_global_position = global_position

## Velocity, saved positions and wheel spin for a car that is now at its
## current transform moving `speed` m/s along its own forward.
func _hand_over(speed: float) -> void:
	var v := -global_transform.basis.z * speed
	linear_velocity = v
	angular_velocity = Vector3.ZERO
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	previous_global_position = global_position - v * dt
	local_velocity = Vector3(0.0, 0.0, -speed)
	for w in wheel_array:
		w.previous_global_position = w.global_position - v * dt
		w.local_velocity = Vector3(0.0, 0.0, -speed)
		w.spin = speed / w.tire_radius
	# The gear this speed belongs in, so the automatic does not start a
	# placed car in 1st at 100 km/h and bang off the limiter through four shifts.
	if is_ready and speed > 0.5 and not is_shifting:
		var wheel_spin := speed / average_drive_wheel_radius
		current_gear = 1
		for g in range(gear_ratios.size(), 0, -1):
			var rpm: float = wheel_spin * gear_ratios[g - 1] * final_drive * ANGULAR_VELOCITY_TO_RPM
			if rpm >= idle_rpm * 1.5 or g == 1:
				current_gear = g
				motor_rpm = clampf(rpm, idle_rpm, max_rpm)
				break

## Floating origin (game.gd _shift_origin): the same bookkeeping the player
## gets. Not `shift`: that is Vehicle's gear change.
func shift_world(offset: Vector3) -> void:
	global_position += offset
	previous_global_position += offset
	for w in wheel_array:
		w.previous_global_position += offset
		w.last_collision_point += offset
	reset_physics_interpolation()
