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

## The player's body: the P1 sports coupe from the B1 design sheet (stage D
## step 1, Roy 2026-10-06). Visual only -- CFG, the collision box and CarSpec
## are the same for both bodies. Set NEON_TEST_CAR=1 to drive the neutral #63
## test box instead, to compare.
const KIND := P1CoupeBuilder.KIND
## Stage D (2026-10-09): the player drives any of PlayerCars.KINDS. The pause
## menu's Car page picks one (PlayerCars.selected, saved in settings.cfg);
## NEON_CAR=<kind> picks one for a test or a shell run; NEON_TEST_CAR=1 wins.
static func chassis_kind() -> String:
	if OS.get_environment("NEON_TEST_CAR") == "1":
		return TestCarBuilder.KIND
	var env := OS.get_environment("NEON_CAR")
	if env != "" and PlayerCars.is_player_kind(env):
		return env
	return PlayerCars.selected

## The sheet build the body wears (NpcCarBuilder kinds; CarSpec._build_wheel
## reads it for the wheel mesh). The player's cars are stock until the garage.
var build := "stock"

## Wheel hardpoints for this car: the P1's CFG, or the sheet car's
## NpcCarBuilder.config (wheel_r, axle_z, wheel_x, plus its collision box).
static func wheel_config(kind: String) -> Dictionary:
	if NpcCarBuilder.is_npc(kind):
		return NpcCarBuilder.config(kind)
	return CFG

const CFG := {
	"wheel_r": 0.34, "axle_z": 1.25, "wheel_x": 0.88,  # Phase B: wheelbase 2.5 m (was 2.1; real coupes 2.4-2.7)
}

## Godot gives every RigidBody3D linear damp 0.1 (a drag of 0.1 per second on
## top of the aero model), which held this car at ~124 km/h in 4th gear no
## matter the tune (found by TuneTrack, Auto-Tune step 2). Roy approved removing
## the cap (2026-10-05); air resistance is AeroModel's job. Replace, not
## combine, so the project/area defaults can't add it back.
const LINEAR_DAMP := 0.0

## Feel pass 1 (2026-10-05): keyboard steering. A key press ramps the steering
## toward full lock instead of jumping there, and the available lock shrinks
## with speed (full lock below ~15 km/h, a quarter of it from ~180 km/h up).
## Starting values from research (docs/research/car-feel.md), to be tuned by feel.
const STEER_ATTACK := 5.0        # per second toward lock at low speed (~0.2 s to full)
const STEER_ATTACK_FAST := 3.0   # same at high speed
const STEER_RELEASE := 8.0       # per second back to centre, and when reversing direction
const STEER_LOCK_MIN := 0.25     # fraction of lock left at STEER_FAST_SPEED
const STEER_SLOW_SPEED := 4.0    # m/s (~15 km/h): full lock below this
const STEER_FAST_SPEED := 50.0   # m/s (180 km/h): minimum lock from here up
## Grip limit on the lock. GEVP's slip assist used to hold the front wheels to about
## 0.27 of lock (~10 deg) from ~8 m/s up, erratically (it is switched off for the
## player now, see _apply_keyboard_steering), and that is what the car felt like at 10 to 20 m/s.
## Keeping it as an explicit cap leaves that range feeling the same. 1.0 turns it
## off, and then the speed cap above alone decides (31 deg at 16 m/s, 21 deg at 30).
const STEER_LOCK_GRIP := 0.27
const STEER_GRIP_FROM := 3.0     # m/s: below this the grip limit does not apply (parking)
const STEER_GRIP_FULL := 8.0     # m/s: it applies in full from here up

const SHIFT_FLASH_DURATION := 0.2  # HUD gear-label flash window, matched to Vehicle's own shift_time below

var chassis_visual: Node3D
var _steer_smooth := 0.0
## Heat and wear (Phase B). Off for sim_only cars so TuneTrack stays clean.
var health := PowertrainHealth.new()
## Fuel and limp mode (Stage C). Off for sim_only cars, like health.
var fuel := FuelTank.new()
var limp := LimpMode.new()
## Broken parts (Stage C damage, slice 1). Off for sim_only cars, like health.
var damage := CarDamage.new()
var _head_share := 1.0

## This car's tune: the one dictionary Vehicle properties are set from and that
## CarSpec.set_param() keeps in step with the live car. Set it before add_child()
## to build a car from a specific spec (the test track does); left empty it
## becomes the default coupe.
var spec := {}

## Test-track hooks (scripts/tuning/tune_track.gd). `driver`, when set, is called every
## physics tick instead of reading the keyboard and sets throttle_input,
## brake_input, steering_input and gear itself -- same simulation, different
## hands. `sim_only` (set before add_child) skips the chassis mesh and the
## engine audio, which have no effect on the physics.
var driver := Callable()
var sim_only := false

## The tune kept between runs (PlayerTune): only the game's own car, the one
## built from the default spec, loads and saves it.
const PlayerTune := preload("res://scripts/car/player_tune.gd")
const TUNE_CHECK_SECS := 1.0
var _keeps_tune := false
var _saved_tune := {}
var _tune_check_left := TUNE_CHECK_SECS

# Aero (2026-09-13, Roy: "add aerodynamics to the game" -> "full aero model"):
# these live here rather than on the vendored Vehicle class (kept unmodified,
# see header) and get set the same way every other tuning number does, via
# CarSpec.apply()'s generic v.set() loop -- see car_spec.gd/aero.gd for the
# actual force math and why it's structured this way. Sign convention:
# positive = downforce (pushes the axle toward -basis.y); these were named
# aero_lift_coefficient_* before issue #34, same values, same force.
var aero_downforce_coefficient_front := 0.0
var aero_downforce_coefficient_rear := 0.0

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
	# The P1 sports coupe (P1CoupeBuilder), or the neutral #63 test car with
	# NEON_TEST_CAR=1. Same physics either way; see chassis_kind().
	var kind := chassis_kind()
	var cfg := wheel_config(kind)
	if not sim_only:
		if kind == TestCarBuilder.KIND:
			chassis_visual = TestCarBuilder.build_chassis_visual()
		elif NpcCarBuilder.is_npc(kind):
			# A sheet car (P0, P2-P6): the same mesh path as the AI cars, in
			# the sheet's own paint.
			chassis_visual = NpcCarBuilder.chassis_visual(kind, build, NpcCarBuilder.sheet_paint(kind))
		else:
			chassis_visual = P1CoupeBuilder.build_chassis_visual()
		add_child(chassis_visual)

	# BUG FIX (2026-09-13, verified headless): RigidBody3D falls asleep after
	# ~0.5s of low apparent velocity (standard Godot sleep threshold), and
	# once asleep it stops responding to the wheels' continuous apply_force
	# calls -- headless test showed motor RPM climbing normally and real
	# per-wheel forces computed correctly, but `sleeping` flipped true around
	# frame 150 and linear_velocity stayed pinned at ~0 forever after. A
	# player-controlled vehicle should never sleep.
	can_sleep = false
	# Contacts are reported so _integrate_forces can tell a wall hit (see below).
	contact_monitor = true
	max_contacts_reported = 8

	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = LINEAR_DAMP
	# Milestone 3: cars on their own physics layer, so the wheel raycasts never
	# land on another car (see CarSpec.set_collision_layers for why that matters).
	CarSpec.set_collision_layers(self)

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
	# Phase A: 1.0 m tall (was 0.6, bottom face unchanged at y=0.2) so the
	# derived roll inertia is ~460 kg m2 (was ~380; a real 1300 kg coupe is
	# about 400-600). Yaw inertia about 1840 stays in the real 1500-2200 band.
	if NpcCarBuilder.is_npc(kind):
		# The sheet body's own box (NpcCarBuilder.config), as TrafficCar.
		CarSpec.build_collision(self, cfg.col_size, cfg.col_y)
	else:
		CarSpec.build_collision(self, Vector3(1.6, 1.0, 3.4), 0.7)

	# ---- Vehicle-level tuning ----
	# CarSpec refactor (2026-09-13, Roy: "i want full physics everywhere ...
	# every wheel sim different based off user/npc/cops no mods/mods"): every
	# number that used to be hardcoded inline here (mass, torque, gearing,
	# drag, tire grip -- all the tuning notes/history for WHY these specific
	# values live in car_spec.gd's coupe_default() now) is now a shared DATA
	# profile any car type can copy-and-override, so NPCs/cops/mods reuse this
	# exact simulation instead of a separate/cheaper one. Values are UNCHANGED
	# from before this refactor -- verified headless (see ship notes).
	if spec.is_empty():
		spec = CarSpec.player_spec(kind)
		# The game's own car: last run's tune comes back (PlayerTune, one file
		# per car). A car built from a given spec (test track, Auto-Tune
		# worker) keeps it as is.
		PlayerTune.kind = kind
		TuneParams.set_gear_count((spec.gear_ratios as Array).size())  # before the saved tune is read: it walks the registry
		PlayerTune.apply_saved(spec)
		_keeps_tune = true
		_saved_tune = PlayerTune.values_from(spec)
	CarSpec.apply(self, spec)
	TuneParams.set_gear_count(gear_ratios.size())   # the tuner lists one box per gear of this car
	# The realistic automatic: only cars whose spec has an "auto" block (the
	# player's; see CarSpec.PLAYER_AUTO). It runs while the car is in AUTO.
	if spec.has("auto"):
		auto_box = AutoBox.new()
		auto_box.setup(self, spec.auto)
	if not sim_only:
		_apply_keyboard_steering()

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
	CarSpec.build_wheels(self, kind, cfg, front_spring_length, rear_spring_length)

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
	# Traffic cars (stage B step 3, #113) join the same group, so drafting now
	# has something to find.
	add_to_group("aero_vehicles")
	health.enabled = not sim_only
	fuel.enabled = not sim_only
	damage.enabled = not sim_only

	# Engine sound (2026-09-29, prototype of docs/research/PROPOSAL-audio.md option C): a
	# synthesised engine driven by this car's motor_rpm/throttle. Added after
	# CarSpec.apply() so it picks up the real idle/max rpm.
	if not sim_only:
		add_child(EngineAudio.new())
		# Stage A (2026-10-04): wind, road, tyre and kerb sound next to the engine.
		add_child(CarAudio.new())
		add_child(DrivelineAudio.new())
		add_child(CrashAudio.new())  # crashes and scrapes (2026-10-08)
		add_child(DamageAudio.new())  # rattle once parts are broken (damage slice 1)

		# Stage A (2026-10-04): headlights + blob shadow, since the world is dark
		# on purpose now (Look Board B). After the body and wheels exist, because
		# it moves their meshes to the car's own render layer.
		# Real wheels and brakes (car parts plan 2026-10-09, session 1): open
		# rims, glowing discs, calipers and springs. Before CarFx so they land on
		# the car layer. Not on the test car (its wheels are a diagnostic).
		if kind == P1CoupeBuilder.KIND:
			CarParts.attach(self, {"hub_x": P1CoupeBuilder.DESIGN_WHEEL_X})
		CarFx.attach(self, chassis_visual.get_meta("half_l", 2.2))

func _physics_process(delta: float) -> void:
	if driver.is_valid():
		driver.call(self)
	else:
		_read_keyboard()
	_update_line_lock()
	# Limp mode: the slowest active cause caps the speed by fading the throttle.
	limp.update(fuel.is_empty(), health.engine_temp if health.enabled else 0.0)
	if limp.is_limping():
		throttle_input *= limp.throttle_scale(current_speed() * 3.6)
	super._physics_process(delta)

	# Aero (2026-09-13): applied AFTER the vendor's own _physics_process so
	# drafting can recompute and partially cancel the drag force it just
	# applied this frame. See aero.gd for the actual force math.
	AeroModel.apply(self)
	damage.step(self, delta, health, limp)
	_apply_lamp_damage()
	health.step(self, delta)
	fuel.step_values(delta, health.engine_load if health.enabled else throttle_amount, engine_running)
	if limp.is_limping():
		torque_mult = limp.torque_mult(health.torque_mult)
	if _keeps_tune:
		_tune_check_left -= delta
		if _tune_check_left <= 0.0:
			_tune_check_left = TUNE_CHECK_SECS
			_save_tune_if_changed()

## A broken head lamp takes its half of the beam (CarFx's one spot light).
func _apply_lamp_damage() -> void:
	var share := damage.headlight_share()
	if share == _head_share:
		return
	_head_share = share
	var spot := get_node_or_null("Headlights") as SpotLight3D
	if spot != null:
		spot.light_energy = CarFx.HEADLIGHT_ENERGY * share
		spot.visible = share > 0.0

func _exit_tree() -> void:
	if _keeps_tune:
		_save_tune_if_changed()  # restart reloads the scene; quit frees it

func _save_tune_if_changed() -> void:
	var now := PlayerTune.values_from(spec)
	if now != _saved_tune and PlayerTune.save(spec):
		_saved_tune = now

# Line lock (2026-10-08, Roy: "check that burnouts work"): brake and throttle
# held together near a standstill put all the brake force on the front axle,
# like a drag car's line lock, so the fronts hold the car and the rears spin.
# Before this the pedal clamped the rears too and the engine bogged at about
# 1,450 rpm with the rears turning at 2.8 m/s; with it, 4,400 rpm and 13.8 m/s
# (headless, stock coupe, tests/car/burnout_line_lock.gd). Lifting either pedal or
# rolling past LINE_LOCK_OFF_SPEED gives the normal split back at once. Player
# only: traffic cars never hold both pedals and are not PlayerCars.
const LINE_LOCK_ON_SPEED := 4.0  # m/s; engages below this
const LINE_LOCK_OFF_SPEED := 7.0  # m/s; releases above this (hysteresis)
var line_lock := false
var _line_lock_bias := Vector2.ZERO  # front, rear brake_bias saved on engage

func _update_line_lock() -> void:
	if front_axle == null or rear_axle == null:
		return
	var want := brake_input > 0.5 and throttle_input > 0.6 and current_gear >= 1
	want = want and speed < (LINE_LOCK_OFF_SPEED if line_lock else LINE_LOCK_ON_SPEED)
	if want == line_lock:
		return
	line_lock = want
	if want:
		_line_lock_bias = Vector2(front_axle.brake_bias, rear_axle.brake_bias)
		front_axle.brake_bias = 1.0
		rear_axle.brake_bias = 0.0
	else:
		front_axle.brake_bias = _line_lock_bias.x
		rear_axle.brake_bias = _line_lock_bias.y

func _read_keyboard() -> void:
	# Input (#29, #30): named InputMap actions (project.godot), all polled
	# here -- no _input handlers. Shifts are one-shot, hence just_pressed.
	if Input.is_action_just_pressed("shift_down"):
		manual_shift(-1)
	if Input.is_action_just_pressed("shift_up"):
		manual_shift(1)
	if Input.is_action_just_pressed("toggle_gearbox"):
		set_transmission_mode((transmission_mode() + 1) % Transmission.size())
	if Input.is_action_just_pressed("reverse"):
		toggle_reverse()
	clutch_input = 1.0 if Input.is_action_pressed("clutch") else 0.0
	starter_input = Input.is_action_pressed("starter")
	var throttle := Input.is_action_pressed("accelerate")
	var braking := Input.is_action_pressed("brake")
	var handbrake := Input.is_action_pressed("handbrake")
	var steer_in := 0.0
	if Input.is_action_pressed("steer_left"):
		steer_in -= 1.0
	if Input.is_action_pressed("steer_right"):
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
	var speed_t := clampf((current_speed() - STEER_SLOW_SPEED) / (STEER_FAST_SPEED - STEER_SLOW_SPEED), 0.0, 1.0)
	var target := steer_in * steer_lock_cap()
	var coming_in := target != 0.0 and (_steer_smooth == 0.0 or signf(target) == signf(_steer_smooth))
	var rate := lerpf(STEER_ATTACK, STEER_ATTACK_FAST, speed_t) if coming_in else STEER_RELEASE
	_steer_smooth = move_toward(_steer_smooth, target, rate * get_physics_process_delta_time())
	# GEVP raises the input to steering_exponent (1.5) before it reaches the
	# wheels, which would turn the speed-capped lock into a fraction of itself
	# (25% at 50 m/s became 12.5%). Undo it so the wheels get the lock the ramp
	# and cap above ask for, the same as traffic_car.gd's lane_steer does.
	steering_input = -signf(_steer_smooth) * pow(absf(_steer_smooth), 1.0 / maxf(steering_exponent, 0.1))

## Keyboard steering (steer-feel PR): make the ramp and caps above the only thing
## between the key and the wheels. GEVP turns the wheels toward the input at
## steering_speed / (speed * steering_speed_decay) / max_steering_angle per second
## (countersteer_speed / (speed * decay) back through centre). At the defaults (4.25
## and 11) that is ~1 per second at 30 m/s and ~0.6 at 50 m/s, slower than
## STEER_ATTACK (3 to 5), so the ramp and the cap never reached the wheels in time.
## These values keep GEVP's limit above the ramp up to ~68 m/s.
## GEVP's slip assist (backs the steering off when a front tyre's slip angle passes
## steering_slip_assist, 0.15 rad) used to hold the wheels to ~0.27 of lock, with the
## slow rates a gentle limit; with fast rates it flips the steering by ~0.25 every
## tick (a 60 Hz chatter between 0.16 and 0.40 of lock). It is off here and
## STEER_LOCK_GRIP stands in for it. Only the real, keyboard-driven car gets this:
## sim_only cars (TuneTrack, the tuner's measurements) and traffic (its lane-keeper
## is tuned to the slow wheels) keep GEVP's own numbers.
const KEYBOARD_STEERING_SPEED := 60.0
const KEYBOARD_COUNTERSTEER_SPEED := 150.0
const KEYBOARD_SLIP_ASSIST := 10.0
func _apply_keyboard_steering() -> void:
	steering_speed = KEYBOARD_STEERING_SPEED
	countersteer_speed = KEYBOARD_COUNTERSTEER_SPEED
	steering_slip_assist = KEYBOARD_SLIP_ASSIST

## The most lock (0..1) the keyboard may ask for at the current speed: the speed
## cap (STEER_LOCK_MIN) or the grip limit (STEER_LOCK_GRIP), whichever is smaller.
func steer_lock_cap() -> float:
	var speed := current_speed()
	var speed_t := clampf((speed - STEER_SLOW_SPEED) / (STEER_FAST_SPEED - STEER_SLOW_SPEED), 0.0, 1.0)
	var grip_t := clampf((speed - STEER_GRIP_FROM) / (STEER_GRIP_FULL - STEER_GRIP_FROM), 0.0, 1.0)
	return minf(lerpf(1.0, STEER_LOCK_MIN, speed_t), lerpf(1.0, STEER_LOCK_GRIP, grip_t))

## The share of full lock the wheels are asked for, + = right (D). steering_input
## is pre-distorted so GEVP's exponent comes out even (see _read_keyboard), so this
## is what the HUD, the cockpit wheel and tests should read, not steering_input.
func steer_fraction() -> float:
	return -signf(steering_input) * pow(absf(steering_input), steering_exponent)

## R: drive to reverse and back, only when (nearly) stopped (Roy; ROADMAP stage B
## step 4). In reverse W drives the car backwards and S brakes. Does nothing while
## moving or mid-shift.
const REVERSE_MAX_SPEED := 1.5  # m/s (~5 km/h)
func toggle_reverse() -> bool:
	if is_shifting or current_speed() > REVERSE_MAX_SPEED or not clutch_ready():
		return false
	shift(1 - current_gear if current_gear == -1 else -1 - current_gear)
	return true

## Transmission modes (2026-10-06, Roy's list). G cycles them:
## - AUTO: the car shifts itself (GEVP's automatic box), no clutch pedal.
## - SEMI: you shift (Q/E), the clutch works itself, as on a paddle-shift car.
## - MANUAL: you shift AND work the clutch: the realistic clutch model (pedal on
##   C, stall, starter on X) and a gear change needs the pedal pressed.
## The mode is not a third flag: it is read off automatic_transmission and
## realistic_clutch, so specs, the tuner and tests that set those still agree
## with the HUD. It replaces the old V "clutch model on/off" key. Every launch
## starts in AUTO, like before (the car spec's default).
enum Transmission { AUTO, SEMI, MANUAL }
const TRANSMISSION_LETTERS := ["A", "S", "M"]
## Clutch input (0..1) that counts as "clutch in" for a MANUAL gear change. It
## reads the input, not GEVP's smoothed clutch_pedal: that one only moves while
## the car is in gear with the engine running, so from neutral or after a stall
## it would never let you select a gear.
const SHIFT_CLUTCH_MIN := 0.6

func transmission_mode() -> int:
	if automatic_transmission:
		return Transmission.AUTO
	return Transmission.MANUAL if realistic_clutch else Transmission.SEMI

func set_transmission_mode(mode: int) -> void:
	automatic_transmission = mode == Transmission.AUTO
	realistic_clutch = mode == Transmission.MANUAL
	# Same reset the old V toggle did: never hand over a stalled engine or a
	# half-pressed pedal from the other model.
	engine_running = true
	clutch_pedal = 0.0
	if auto_box != null:
		auto_box.reset()

## In MANUAL a gear change needs the clutch in; in the other modes it always may.
func clutch_ready() -> bool:
	return transmission_mode() != Transmission.MANUAL or clutch_input >= SHIFT_CLUTCH_MIN

func manual_shift(count: int) -> void:
	if clutch_ready():
		super.manual_shift(count)

## HUD compatibility -- game.gd reads player.gear (int, -1/0/1..N) and
## player.current_speed(); both map directly onto what Vehicle already
## tracks, so game.gd needed no changes beyond this.
var gear: int:
	get: return current_gear

## Vehicle exposes is_shifting (true for the shift_time window) instead of a
## countdown timer -- this getter keeps game.gd's existing ">0.0 means flash
## now" HUD check working unchanged.
var shift_flash_t: float:
	get: return SHIFT_FLASH_DURATION if is_shifting or (auto_box_on and auto_box.shifting) else 0.0

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

## Wall hits (2026-10-07, Roy: the car bugs out on the out-of-bounds walls). The
## centre of mass sits ~16 cm under the road (CarSpec's stability choice), and
## the chassis box meets a wall ~0.9 m above it, so a wall contact rolls or
## pitches the car with a lever no tyre force ever has: a 200 km/h glancing hit
## put it on its roof (tests/car/wall_hit.gd). While the body touches a wall, the
## roll and pitch rates are held to WALL_TILT_RATE, and past WALL_MAX_TILT it
## cannot tip any further (sliding along the wall at 200 km/h, a steady roll at
## the capped rate still put it on its side in 3 s). Righting is never limited,
## and yaw is left alone, so the car still bounces and slides off naturally.
const WALL_TILT_RATE := 0.5  # rad/s
const WALL_MAX_TILT := deg_to_rad(25.0)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	super(state)
	if _touching_wall(state):
		var b := state.transform.basis
		var w := state.angular_velocity
		var yaw := b.y * w.dot(b.y)
		var roll := b.z * clampf(w.dot(b.z), -WALL_TILT_RATE, WALL_TILT_RATE)
		var pitch := b.x * clampf(w.dot(b.x), -WALL_TILT_RATE, WALL_TILT_RATE)
		var tip := roll + pitch
		# Turning about `axis` (positive) brings the car's up back to world up.
		var tilt := b.y.angle_to(Vector3.UP)
		if tilt > 0.001:
			var axis := b.y.cross(Vector3.UP).normalized()
			var limit := WALL_TILT_RATE * clampf(1.0 - tilt / WALL_MAX_TILT, 0.0, 1.0)
			var r := tip.dot(axis)
			if r < -limit:
				tip += axis * (-limit - r)
		state.angular_velocity = yaw + tip

func _touching_wall(state: PhysicsDirectBodyState3D) -> bool:
	var wall_bit := 1 << (CarSpec.WALL_LAYER - 1)
	for i in state.get_contact_count():
		var other := state.get_contact_collider_object(i) as CollisionObject3D
		if other != null and other.collision_layer & wall_bit:
			return true
	return false
