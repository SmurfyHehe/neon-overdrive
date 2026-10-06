# CarSpec (2026-09-13, Roy: "i want full physics everywhere... we make every
# wheel sim different based off user/npc/cops no mods/mods and how different
# mods change each wheel sim"): every car in the game -- player, traffic NPCs,
# cops later, any mod state -- runs the SAME real vendored raycast Vehicle/
# Wheel simulation (scripts/vendor/gevp/). What differs per car is only DATA:
# mass, torque, gearing, tire grip, suspension. This file is that data layer,
# extracted out of player.gd (which used to hardcode all of this inline) so
# a future NPCCar/CopCar just builds its own spec dict -- possibly starting
# from coupe_default() and overriding a few fields -- and calls the same
# apply()/build_wheels()/build_collision() helpers PlayerCar now uses (TrafficCar
# does, since #113). Mods (the per-car mod trees of stage E, see ROADMAP) plug
# in here too: a mod multiplies/overrides entries in a car's spec dict
# before CarSpec.apply() runs, rather than needing separate code paths per mod.
extends RefCounted
class_name CarSpec

## Every key here is a real property name on the vendored Vehicle class --
## apply() just does v.set(key, value) for each, so ANY subset of Vehicle's
## tunables can be described as a spec dict, including a partial dict a mod
## builds by copying a base spec and changing a few entries.
static func apply(v: Vehicle, spec: Dictionary) -> void:
	for key in spec:
		if key == "torque_shape":
			# Not a Vehicle property: the spec stores the shape and the car gets
			# the curve built from it, so tuning the shape and the curve can't
			# disagree.
			v.torque_curve = _curve_from_shape(spec[key])
		elif key == "exhaust":
			continue  # cosmetic: EngineAudio reads it from the spec, the Vehicle has no such property
		else:
			v.set(key, _own(spec[key]))

## The vehicle gets its own copy of every array and dictionary. Without this the
## spec, the Vehicle and (via Vehicle.initialize()) all four wheels would share
## the same tire dictionaries, so writing the spec would silently change the
## car, and a saved spec would change under you. duplicate(true) keeps
## Array[float] typed.
static func _own(x: Variant) -> Variant:
	if x is Dictionary or x is Array:
		return x.duplicate(true)
	return x

## An independent deep copy of a spec, for snapshots (undo, saved tunes) and for
## building a second car from the same tune.
static func clone_spec(spec: Dictionary) -> Dictionary:
	var out := {}
	for key in spec:
		var x: Variant = spec[key]
		out[key] = x.duplicate() if x is Resource else _own(x)
	return out

## THE write path for tuning (raw panel and Auto-Tune both). Clamps to the
## registry range, writes the spec and the live car, then redoes whatever the
## vendored Vehicle only works out once. Returns the value actually stored, or
## NAN for a path that is not in TuneParams.
##
## Needed because of how gevp reads things: gear ratios, final drive, drag and
## the aero coefficients are read fresh every tick, but each Wheel caches its
## surface's tire numbers (current_*) and the Vehicle derives max_brake_force
## from friction and brake_force_multiplier, both only in initialize(). Before
## the car is ready, initialize() will do all that itself, so only the spec is
## written.
static func set_param(v: Vehicle, spec: Dictionary, path: String, value: float) -> float:
	var entry := TuneParams.find(path)
	if entry.is_empty():
		push_error("CarSpec.set_param: '%s' is not a tunable path" % path)
		return NAN
	value = clampf(value, entry.min, entry.max)
	TuneParams.set_value(spec, path, value)
	if entry.on_car:
		TuneParams.set_value(v, path, value)
	if v.is_ready:
		_rederive(v, spec, entry.rederive)
	return value

static func _curve_from_shape(t: Dictionary) -> Curve:
	return build_torque_curve(t.low_end, t.peak_pos, t.plateau, t.falloff)

static func _rederive(v: Vehicle, spec: Dictionary, kind: String) -> void:
	if kind == TuneParams.ENGINE:
		# initialize() derives max_clutch_torque from max_torque once.
		v.max_clutch_torque = v.max_torque * v.max_clutch_torque_ratio
		v.torque_curve = _curve_from_shape(spec.torque_shape)
	if kind == TuneParams.TIRE:
		# Same formulas as Wheel.initialize() / its surface-change branch. The
		# vendored files stay untouched; tests/tune_params.gd checks these match
		# a freshly built car, so a vendor change would show up there.
		for w in v.wheel_array:
			var s: String = w.surface_type
			w.current_cof = w.coefficient_of_friction[s]
			w.current_lateral_grip_assist = w.lateral_grip_assist[s]
			w.current_longitudinal_grip_ratio = w.longitudinal_grip_ratio[s]
			w.current_tire_stiffness = 1000000.0 + 8000000.0 * w.tire_stiffnesses[s]
	if kind == TuneParams.TIRE or kind == TuneParams.BRAKE:
		v.calculate_brake_force()
	if kind == TuneParams.TYRE_SETUP:
		v.apply_tyre_setup()
	if kind == TuneParams.SUSPENSION:
		v.apply_suspension()
		v.calculate_brake_force()

## Baseline tuning -- currently identical to what PlayerCar shipped with
## (2026-09-13 physics rewrite + power/top-speed passes), NOT yet meaningfully
## different per user/NPC/cop -- that differentiation is milestone 3+ work.
## This is the single object different car types should copy-and-override
## from, not a player-only constant.
static func coupe_default() -> Dictionary:
	# BUG FIX (2026-09-13, found via headless diff against the pre-refactor
	# player.gd, NOT guessed): Vehicle.gear_ratios is declared as a TYPED
	# Array[float]. A plain untyped array literal assigned through the
	# generic v.set(key, value) loop in apply() silently fails Godot's
	# typed-property assignment -- no error, no warning, the property just
	# stays at the vendored script's own default [3.8, 2.3, 1.7, 1.3, 1.0, 0.8]
	# instead of ours. Direct static assignment (gear_ratios = [...]) in the
	# old inline code didn't have this problem because the compiler inserts
	# the typed-array conversion at the assignment site; set() gets no such
	# help. Declaring the array in a locally-typed var first forces the same
	# conversion to happen before it goes in the dict, so apply()'s set()
	# call receives an already-correctly-typed Array[float] and the
	# assignment actually sticks. Verified headless: with this fix,
	# refactored and pre-refactor player.gd now produce IDENTICAL
	# gear_ratios and identical straight-line speed after 4s (was silently
	# using the vendored default gearing before this fix, a real
	# would-have-shipped regression).
	# Feel pass 1 (2026-10-05): even steps of about 1.3 and 1st gear good for
	# ~80 km/h at redline (was 61, ISSUES E7). Same top gear, so top speed is
	# unchanged. A real ~1300 kg coupe pulls 65-85 km/h in 1st (research:
	# docs/research/car-feel.md).
	var gear_ratios_typed: Array[float] = [2.74, 2.10, 1.615, 1.24, 0.95]
	return {
		"vehicle_mass": 1300.0,
		"front_weight_distribution": 0.45,
		"front_torque_split": 0.0,  # RWD
		"max_torque": 460.0,
		"max_rpm": 7000.0,
		"idle_rpm": 1000.0,
		"torque_shape": DEFAULT_TORQUE_SHAPE.duplicate(),  # apply() builds the Vehicle's torque_curve from this
		"gear_ratios": gear_ratios_typed,
		"final_drive": 4.1,
		# Feel pass 1: the car shifts itself by default (G toggles manual). Shifts
		# take 0.2 s (was 0.3), and the clutch takes up at 2000 rpm (was 3000).
		# motor_drag stays at the default 0.005: 0.007 cost ~10 km/h of top speed.
		"automatic_transmission": true,
		"tyre_load_sensitivity": 0.12,  # Phase C: weight transfer costs grip (real tyres 0.1-0.3); 0 = off
		# Tuner redesign PR 1: tyre pressure (bar) and static camber (deg). The
		# *_stock values are this car's factory setup; the tuner moves the others,
		# and every effect is measured against stock (gevp_wheel.gd, item 12).
		"front_tyre_pressure": 2.2,
		"rear_tyre_pressure": 2.2,
		"tyre_pressure_stock": 2.2,
		"front_static_camber": 0.0,
		"rear_static_camber": 0.0,
		"front_static_camber_stock": 0.0,
		"rear_static_camber_stock": 0.0,
		# Tuner redesign PR 2: settings the car always had at GEVP's defaults,
		# now in the spec so the tuner can move them (same values: no change).
		"front_resting_ratio": 0.5,
		"rear_resting_ratio": 0.5,
		"front_toe": 0.01,
		"rear_toe": 0.01,
		"front_locking_differential_engage_torque": 200.0,
		"rear_locking_differential_engage_torque": 200.0,
		"front_brake_bias": -1.0,  # -1 = from the springs (GEVP's auto, ~0.55 on the coupe)
		"traction_control_max_slip": 8.0,  # <= 0 = off
		"stability_yaw_strength": 6.0,
		"front_abs_spin_difference_threshold": 12.0,
		"rear_abs_spin_difference_threshold": 12.0,
		"realistic_clutch": false,  # Phase C: clutch pedal, stall and starter; on in the MANUAL gearbox mode (G cycles auto / semi / manual)
		"turbo_boost_max": 0.0,  # Phase B: 0 = naturally aspirated; the T tuner can add boost
		"brake_selects_reverse": false,  # R picks reverse (Roy); S only brakes
		"automatic_time_between_shifts": 800.0,  # Phase A shift map: min ms between upshifts
		"throttle_speed": 8.0,  # Phase A: throttle lag, ~0.12 s from closed to open (GEVP default 20)
		"center_of_gravity_height_offset": -0.07,  # Phase A: CoG ~0.5 m (was -0.2, ~0.38 m)
		"shift_time": 0.2,
		"clutch_out_rpm": 2000.0,
		"motor_brake": 20.0,  # engine braking when off throttle (pass 1b; GEVP default 10, was unused)
		"coefficient_of_drag": 0.26,
		"frontal_area": 1.9,
		"brake_force_multiplier": 2.5,  # Phase A: GEVP derives max brake force from tyre friction, so halving cof halved braking; x2 puts it back near 1 g (100-0 about 40 m)
		"max_steering_angle": deg_to_rad(38.0),
		# Phase B suspension (research: docs/research/build-phases.md): sporty damping
		# (0.55, GEVP default 0.4) and a stiffer front anti-roll bar than rear, so the
		# car understeers a little when pushed instead of snapping loose.
		"front_damping_ratio": 0.55,
		"rear_damping_ratio": 0.55,
		"front_arb_ratio": 0.30,
		"rear_arb_ratio": 0.20,
		"front_spring_length": 0.22,
		"rear_spring_length": 0.26,
		"tire_stiffnesses": {"Road": 10.0, "Dirt": 3.0},
		# Friction convention (#33): GEVP's coefficient_of_friction is NOT
		# VehicleBody3D's wheel_friction_slip. The old "~1.2-1.5" target in
		# HANDOFF.md was written for VehicleBody3D, which was never built --
		# GEVP replaced it -- so that range does not apply here.
		# In gevp_wheel.gd process_tires(), the tire's force limit is
		#   (cof - 1 / (tire_width_mm * contact_patch * 0.2)) * spring_force
		# and tire_stiffnesses makes the brush model saturate within a few
		# degrees of slip, so that limit is effectively the peak force. With
		# the 245 mm tires and 0.2 contact_patch left at GEVP defaults, the
		# subtracted term is ~0.1, so Road 3.0 means:
		#   - lateral (cornering) peak ~2.9x wheel load, i.e. ~2.9 g, up to
		#     ~5% more at big slip angles from lateral_grip_assist;
		#   - longitudinal (traction) peak ~1.45x load, because
		#     longitudinal_grip_ratio 0.5 halves it -- this is where the
		#     reachable slide comes from (wheelspin / power oversteer);
		#     braking gets up to 2.5x that via braking_grip_multiplier.
		# PHASE A (2026-10-05): Road is now 1.2 (measured peak ~1.5 g with load and
		# downforce; the 3.0 above
		# was GEVP's shipped default and gave ~2.9 g, past the rollover limit
		# of ~1.76 g for a 1.76 m track at 0.5 m CG, research in
		# docs/research/car-feel.md). Real street tyres are ~0.9-1.0, sport
		# ~1.0-1.2, slicks ~1.3-1.6. The numbers in the comment above are for
		# 3.0 and scale with cof. Grip feel is Roy's call -- tune by driving, and
		# note that spring_force includes aero downforce, so grip also
		# rises with speed. Also feeds max_brake_force (gevp_vehicle.gd).
		"coefficient_of_friction": {"Road": 1.2, "Dirt": 0.9},
		"rolling_resistance": {"Road": 1.0, "Dirt": 1.6},
		"lateral_grip_assist": {"Road": 0.05, "Dirt": 0.0},
		"longitudinal_grip_ratio": {"Road": 1.1, "Dirt": 0.45},  # Phase A: with cof 1.2 this keeps launch traction (long grip 1.3)

		# Aero (2026-09-13, Roy: "add aerodynamics to the game" -> full model):
		# these aren't vendored Vehicle properties -- they're plain vars
		# declared on PlayerCar itself (see player.gd) and consumed by
		# aero.gd's AeroModel, applied through this same v.set() loop like
		# everything else here. Rear-biased split matches the coupe's visual
		# rear spoiler (car_builder.gd) and its RWD/rear weight bias -- more
		# rear downforce helps put power down without adding front push that
		# would fight the steering feel already tuned. Not measured from a
		# real car, [stated]-flagged as likely to need retuning once driven.
		"aero_downforce_coefficient_front": 0.35,
		"aero_downforce_coefficient_rear": 0.55,

		# Exhaust sound tune (cosmetic, never Auto-Tune; see TuneParams).
		# Starts on the P1 preset; EngineAudio overlays the player's saved tune.
		"exhaust": ExhaustTune.for_car("p1_coupe").to_dict(),
	}

## Traffic tune (milestone 3, 2026-10-05): coupe_default() with commuter-car
## numbers -- a smaller engine, more drag, street tyres, hardly any downforce.
## Same simulation, different data; the three NPC cars (stage B step 5) replace
## this with their own dicts. Not measured from a real car.
static func traffic_default() -> Dictionary:
	var s := coupe_default()
	s["vehicle_mass"] = 1250.0
	s["max_torque"] = 170.0
	s["max_rpm"] = 6200.0
	s["coefficient_of_drag"] = 0.32
	s["frontal_area"] = 2.1
	s["coefficient_of_friction"] = {"Road": 1.0, "Dirt": 0.8}
	s["aero_downforce_coefficient_front"] = 0.05
	s["aero_downforce_coefficient_rear"] = 0.05
	s["automatic_transmission"] = true
	s["realistic_clutch"] = false
	s["turbo_boost_max"] = 0.0
	return s

## Physics layers (milestone 3). Every car sits on CAR_LAYER and collides with
## the world (WORLD_LAYER: ground slab, sidewalks, buildings) and with other
## cars. A Wheel is a RayCast3D on the default mask, layer 1 only, so a wheel
## never sees a car body. That is not just tidiness: the vendored Wheel takes
## its tyre numbers from the FIRST group of whatever it hits (gevp_wheel.gd
## process_forces), a car's first group is "aero_vehicles", and
## coefficient_of_friction["aero_vehicles"] does not exist.
const WORLD_LAYER := 1
const CAR_LAYER := 2

static func set_collision_layers(v: Vehicle) -> void:
	v.collision_layer = 1 << (CAR_LAYER - 1)
	v.collision_mask = (1 << (WORLD_LAYER - 1)) | (1 << (CAR_LAYER - 1))

## Rise-then-taper torque curve, loosely modeled on a real gasoline engine's
## band, not measured from anything specific -- same shape every car uses for
## now. Built from the shape knobs below (#62) so the tuning panel and, later,
## upgrades change the same four numbers instead of hand-placed points.
static func default_torque_curve() -> Curve:
	var t := DEFAULT_TORQUE_SHAPE
	return build_torque_curve(t.low_end, t.peak_pos, t.plateau, t.falloff)

const DEFAULT_TORQUE_SHAPE := {"low_end": 0.35, "peak_pos": 0.55, "plateau": 0.0, "falloff": 0.55}

# Where the in-between points sit, as fractions of the rise and the fall.
# Taken from the hand-placed curve this replaced -- (0.25, 0.75) on the way up
# and (0.85, 0.9) on the way down -- so build_torque_curve(0.35, 0.55, 0.0,
# 0.55) reproduces it point for point.
const RISE_MID_X := 0.25 / 0.55
const RISE_MID_Y := 0.40 / 0.65
const FALL_MID_X := 0.30 / 0.45
const FALL_MID_Y := 0.10 / 0.45

## Torque curve from four shape knobs (#62). x is rpm / max_rpm, y is the
## fraction of max_torque.
## - low_end: torque at 0 rpm (turbo/big-displacement engines pull harder low)
## - peak_pos: rpm fraction where peak torque ENDS (cams move this up)
## - plateau: width of the flat top before peak_pos (turbos are wide and flat)
## - falloff: torque left at redline (high-rev engines hold on longer)
static func build_torque_curve(low_end: float, peak_pos: float, plateau: float, falloff: float) -> Curve:
	peak_pos = clampf(peak_pos, 0.1, 0.99)
	var peak_start := clampf(peak_pos - plateau, 0.05, peak_pos)
	var c := Curve.new()
	c.add_point(Vector2(0.0, low_end))
	c.add_point(Vector2(peak_start * RISE_MID_X, low_end + (1.0 - low_end) * RISE_MID_Y))
	c.add_point(Vector2(peak_start, 1.0))
	if peak_pos > peak_start:
		c.add_point(Vector2(peak_pos, 1.0))
	c.add_point(Vector2(peak_pos + (1.0 - peak_pos) * FALL_MID_X, 1.0 - (1.0 - falloff) * FALL_MID_Y))
	c.add_point(Vector2(1.0, falloff))
	return c

## Builds all 4 raycast Wheel nodes + their visuals and assigns them onto the
## Vehicle's front_left_wheel/etc. -- wheel_cfg needs wheel_r/axle_z/wheel_x
## (the same shape CarBuilder.KIND_CONFIGS entries already use, so callers
## can pass CarBuilder.KIND_CONFIGS[kind] directly rather than duplicating
## those numbers in a second place, the way player.gd used to). Mount height
## (spring_length + tire_radius above the chassis origin) is computed here so
## every car gets the fix verified during the physics rewrite for free,
## rather than each car type having to remember it.
static func build_wheels(v: Vehicle, kind: String, wheel_cfg: Dictionary, front_spring_length: float, rear_spring_length: float) -> void:
	var wheel_r: float = wheel_cfg.wheel_r
	var axle_z: float = wheel_cfg.axle_z
	var wheel_x: float = wheel_cfg.wheel_x
	var front_mount_y := front_spring_length + wheel_r
	var rear_mount_y := rear_spring_length + wheel_r
	v.front_tire_radius = wheel_r
	v.rear_tire_radius = wheel_r
	v.front_left_wheel = _build_wheel(v, kind, Vector3(-wheel_x, front_mount_y, -axle_z))
	v.front_right_wheel = _build_wheel(v, kind, Vector3(wheel_x, front_mount_y, -axle_z))
	v.rear_left_wheel = _build_wheel(v, kind, Vector3(-wheel_x, rear_mount_y, axle_z))
	v.rear_right_wheel = _build_wheel(v, kind, Vector3(wheel_x, rear_mount_y, axle_z))

static func _build_wheel(v: Vehicle, kind: String, pos: Vector3) -> Wheel:
	var w := Wheel.new()
	w.position = pos
	v.add_child(w)
	var visual: Node3D
	if kind == TestCarBuilder.KIND:
		visual = TestCarBuilder.build_wheel_visual(v.front_tire_radius)
	elif kind == P1CoupeBuilder.KIND:
		visual = P1CoupeBuilder.build_wheel_visual(v.front_tire_radius, pos)
	else:
		# CarBuilder kinds (traffic) share one merged, cached wheel mesh per
		# kind (traffic milestone 4, draw calls).
		visual = CarBuilder.shared_wheel_visual(kind)
	w.wheel_node = visual
	w.add_child(visual)
	return w

## Chassis collision box -- the RigidBody3D always needs one (wheels handle
## ground contact via their own raycasts). y_offset defaults to the value
## verified during the physics rewrite to clear the ground after suspension
## settles; a different car size/mass may need its own value once that's
## tuned, so it's a parameter, not hardcoded here.
static func build_collision(v: Vehicle, size: Vector3, y_offset: float = 0.5) -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = Vector3(0.0, y_offset, 0.0)
	v.add_child(col)
