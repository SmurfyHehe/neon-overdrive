extends Vehicle
class_name PlayerCar

# Milestone 2 REWRITE (2026-09-13): after two rounds of "physics feel bad"
# feedback and two confirmed structural findings against VehicleBody3D --
# (1) no lever arm for roll torque (lateral tire force applied near
# wheel-mount height, not the real ground contact point -- measured up_dot
# staying at exactly 1.00000 through a hard turn at every suspension setting
# tried), (2) the vehicle solver actively re-levels the chassis every physics
# step, crushing any authored torque within one frame -- tuning the built-in
# system further couldn't fix either problem, they're architectural.
#
# Researched real alternatives (not guessed) and adopted
# github.com/DAShoe1/Godot-Easy-Vehicle-Physics (MIT), vendored unmodified at
# scripts/vendor/gevp/ -- PlayerCar now EXTENDS its Vehicle class instead of
# VehicleBody3D. Its wheels are raycasts that apply spring/tire forces at the
# ACTUAL ground contact point with a real lever arm back to the body's center
# of mass, so roll/pitch/dive/squat are now genuine physics, not a cosmetic
# mesh trick -- the entire cosmetic-tilt system from the previous version is
# gone, deleted, not layered on top. This file only owns: wheel node
# construction (our CFG hardpoints), input wiring (WASD/Space/Q-E, matching
# our existing controls), a torque curve (Vehicle requires one, has no
# default), gear count/ratios (5 gears, an easy array to change later --
# [stated] the exact gear count/drivetrain feel may still change), and the
# thin HUD-compatibility surface (gear/current_speed()) game.gd already reads.
#
# Sidewalk grip (2026-09-13 environment pass) is now handled by the vendored
# Wheel's own per-surface-group system (road_chunk_builder.gd tags sidewalk
# collision "Dirt", the ground plane "Road") instead of our own hand-rolled
# on_sidewalk/grip-multiplier code -- deleted, this is strictly better since
# it's the same mechanism the wheel already needs for its tire model, and it
# also gets a REAL small physical bump for free from the sidewalk's raised
# collision geometry, instead of the old scripted cosmetic jolt.

const KIND := "coupe"
const CFG := {
	"wheel_r": 0.34, "axle_z": 1.05, "wheel_x": 0.88,
}

const SHIFT_FLASH_DURATION := 0.2  # HUD gear-label flash window, matched to Vehicle's own shift_time below

var chassis_visual: Node3D

# Aero (2026-09-13, Roy: "add aerodynamics to the game" -> "full aero model"):
# these live here rather than on the vendored Vehicle class (kept unmodified,
# see header) and get set the same way every other tuning number does, via
# CarSpec.apply()'s generic v.set() loop -- see car_spec.gd/aero.gd for the
# actual force math and why it's structured this way.
var aero_lift_coefficient_front := 0.0
var aero_lift_coefficient_rear := 0.0

func _ready() -> void:
	# NOTE: we deliberately do NOT call super._ready() here -- Vehicle's own
	# _ready() just calls initialize(), and initialize() requires the wheel
	# nodes (front_left_wheel etc.) to already be built and assigned, which
	# has to happen in THIS _ready() first. We call initialize() ourselves at
	# the end instead.

	# BUG FIX (2026-09-13, Roy: "the player model car and surroundings are
	# horrendous, they don't even make me feel like im in beam.ng"): this was
	# still calling build_skeleton_visual() -- the physics-testing wireframe
	# rig, not a car -- left over from the physics rewrite and never swapped
	# back. No amount of physics/road polish reads as a real game while the
	# player is driving a glowing stick frame. Back to a real body now,
	# upgraded with actual panel/bumper/mirror/spoiler/alloy-wheel detail (see
	# car_builder.gd's _add_body_details/_add_glass/_build_alloy_wheel) instead
	# of the old flat-box look.
	chassis_visual = CarBuilder.build_chassis_visual(KIND, Color(0, 0.96, 1))
	add_child(chassis_visual)

	# BUG FIX (2026-09-13, verified headless): RigidBody3D falls asleep after
	# ~0.5s of low apparent velocity (standard Godot sleep threshold), and
	# once asleep it stops responding to the wheels' continuous apply_force
	# calls -- headless test showed motor RPM climbing normally and real
	# per-wheel forces computed correctly, but `sleeping` flipped true around
	# frame 150 and linear_velocity stayed pinned at ~0 forever after. A
	# player-controlled vehicle should never sleep.
	can_sleep = false

	# Vehicle body collision shape -- the RigidBody3D still needs one (wheels
	# handle ground contact via their own raycasts).
	# BUG FIX (2026-09-13, verified headless): with the raycast-wheel
	# suspension settling the chassis ORIGIN down by its resting compression
	# (~0.06m here), the old y=0.35 box position put this box's own bottom
	# face slightly BELOW ground level -- the chassis's real collision shape
	# was embedded in the ground, and that unwanted second contact was
	# generating enough resistance to pin the car at ~0 velocity even under
	# full throttle (confirmed: motor RPM and per-wheel tire forces were both
	# real and correct, only actual movement was blocked). y_offset=0.5 keeps
	# the bottom face comfortably clear of the ground after settling --
	# CarSpec.build_collision() defaults to this same verified value.
	CarSpec.build_collision(self, Vector3(1.6, 0.6, 3.4))

	# ---- Vehicle-level tuning ----
	# CarSpec refactor (2026-09-13, Roy: "i want full physics everywhere ...
	# every wheel sim different based off user/npc/cops no mods/mods"): every
	# number that used to be hardcoded inline here (mass, torque, gearing,
	# drag, tire grip -- all the tuning notes/history for WHY these specific
	# values live in car_spec.gd's coupe_default() now) is now a shared DATA
	# profile any car type can copy-and-override, so NPCs/cops/mods reuse this
	# exact simulation instead of a separate/cheaper one. Values are UNCHANGED
	# from before this refactor -- verified headless (see ship notes).
	CarSpec.apply(self, CarSpec.coupe_default())

	# BUG FIX (2026-09-13, verified headless): a wheel's raycast starts AT its
	# own node position and extends DOWN by spring_length+tire_radius (set
	# inside Vehicle.initialize()). Leaving wheel.position.y at 0 (the
	# chassis origin's own height) put the raycast's start point already
	# below the ground surface at rest, so it never found a sane resting
	# contact -- headless test showed motor RPM climbing to redline while
	# speed stayed exactly 0.00 the whole time (wheels spinning, effectively
	# not grounded). Each wheel's local Y must be its OWN axle's
	# spring_length + tire_radius above the chassis origin, same pattern the
	# old VehicleWheel3D mount height used. CarSpec.build_wheels() computes
	# this the same way, from the same CFG shape, for every car type.
	CarSpec.build_wheels(self, KIND, CFG, front_spring_length, rear_spring_length)

	initialize()

	# BUG FIX (2026-09-13, Roy: "you messed up the controls"): Vehicle's
	# gearbox starts in Neutral (current_gear = 0) by default -- that's correct
	# for a real manual car, but it means W did nothing at all until the
	# player first pressed E to shift into 1st, with zero indication why
	# (the debug HUD's "GEAR N" is easy to miss). Every prior version of this
	# game moved as soon as you pressed forward. Starting already in 1st
	# matches that expectation; manual Q/E shifting still works normally from
	# here (E->2nd, Q->neutral->reverse) once moving.
	current_gear = 1

	# Aero (2026-09-13): registers this car for AeroModel's drafting lookup.
	# No traffic exists yet (milestone 3), so today this group only ever has
	# one member and drafting always finds nothing -- built for real ahead of
	# time, same pattern as CarSpec, not dead code.
	add_to_group("aero_vehicles")

	# Engine sound (2026-09-29, prototype of PROPOSAL-audio.md option C): a
	# synthesised engine driven by this car's motor_rpm/throttle. Added after
	# CarSpec.apply() so it picks up the real idle/max rpm.
	add_child(EngineAudio.new())

func _physics_process(delta: float) -> void:
	var throttle := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	var braking := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
	var handbrake := Input.is_key_pressed(KEY_SPACE)
	var steer_in := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		steer_in -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		steer_in += 1.0

	throttle_input = 1.0 if throttle else 0.0
	brake_input = 1.0 if braking else 0.0
	handbrake_input = 1.0 if handbrake else 0.0
	# BUG FIX (2026-09-13, Roy: "controls are still backwards w/d" -- verified
	# headless): steering_input=+1 (D) actually yawed the chassis LEFT (rotation.y
	# went positive, which rotates the -Z nose toward -X, the car's own left) and
	# drifted the car left, not right -- the vendored Wheel's steer()/ackermann
	# math is built for the opposite input sign convention from our A/D mapping.
	# Negating here (rather than swapping which key does what) keeps A=left/D=right
	# reading naturally in the code while matching what the asset expects.
	steering_input = -steer_in

	super._physics_process(delta)

	# Aero (2026-09-13): applied AFTER the vendor's own _physics_process so
	# drafting can recompute and partially cancel the drag force it just
	# applied this frame. See aero.gd for the actual force math.
	AeroModel.apply(self)

## HUD compatibility -- game.gd reads player.gear (int, -1/0/1..N) and
## player.current_speed(); both map directly onto what Vehicle already
## tracks, so game.gd needed no changes beyond this.
var gear: int:
	get: return current_gear

## Vehicle exposes is_shifting (true for the shift_time window) instead of a
## countdown timer -- this getter keeps game.gd's existing ">0.0 means flash
## now" HUD check working unchanged.
var shift_flash_t: float:
	get: return SHIFT_FLASH_DURATION if is_shifting else 0.0

func current_speed() -> float:
	return -local_velocity.z  # forward = -Z, matches the road-chunk convention

## Whether any wheel is currently on a non-"Road" surface -- single source of
## truth for gameplay hooks (future heat/scoring) instead of re-deriving lane
## position math separately; reads the same surface_type the tire model
## already computes every frame.
func is_off_road() -> bool:
	for w in wheel_array:
		if w.surface_type != "Road":
			return true
	return false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			manual_shift(-1)
		elif event.keycode == KEY_E:
			manual_shift(1)
