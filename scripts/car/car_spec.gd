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
		elif key == "engine_voice":
			continue  # sound only (#80): EngineAudio hands it to EngineSynth
		elif key == "turbo_voice":
			continue  # sound only (B1): EngineAudio hands it to TurboSynth
		elif key == "window_control":
			continue  # cosmetic: how the cockpit's side window is worked (CockpitFrame)
		elif key == "boost_kind":
			ForcedInduction.set_kind(v, String(spec[key]))  # not a Vehicle property (C1)
		elif key == "driver_grip_deg":
			continue  # cosmetic: where the driver's hands rest on the rim (DriverModel)
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
## registry's Advanced hard limits (adv_min..adv_max), writes the spec and the live car, then redoes whatever the
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
	if not is_finite(value):
		# clampf() passes NaN straight through, and one NaN on the car poisons
		# the whole sim. Keep what is there (settings safety, 2026-10-07).
		push_warning("CarSpec.set_param: ignored non-finite %s for '%s'" % [str(value), path])
		return TuneParams.get_value(spec, path)
	# The Advanced hard limits, not the safe range (settings safety part 2).
	value = clampf(value, entry.adv_min, entry.adv_max)
	if path == "front_brake_bias":
		value = -1.0 if value < 0.0 else maxf(value, TuneParams.BIAS_MIN)
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
		# vendored files stay untouched; tests/tuning/tune_params.gd checks these match
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
		remount_wheels(v)

## Puts each wheel's mount at its axle's spring_length + tire_radius above the
## chassis origin, where build_wheels() puts it. apply_suspension() changes the
## spring and ray length but not the mount, so a ride height set in the Tuner
## mid-run dropped the body by the change (6-8 cm at the Tuner's minimum) to
## 2 cm off the road, and it scraped (Roy 2026-10-09, tests/car_scrape.gd
## sweep). A restart rebuilt it at the right height, so the same tune drove
## differently before and after one. The wheel's sim history moves with it,
## so the change is not read as wheel speed.
static func remount_wheels(v: Vehicle) -> void:
	for w in v.wheel_array:
		var y := w.spring_length + w.tire_radius
		var dy := y - w.position.y
		if is_zero_approx(dy):
			continue
		w.position.y = y
		w.previous_global_position += v.global_basis.y * dy

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
		# What the engine itself sounds like (#80): a straight six. Not tunable.
		"engine_voice": EngineVoice.for_car("p1_coupe"),
		# How the driver works the side window in the cockpit (2026-10-09, Roy:
		# "Z to roll up and roll down needs an animation"): "switch" is a rocker
		# on the door armrest pressed with the thumb (modern cars, this coupe);
		# "crank" is a hand crank on the door card the hand turns (old cars, the
		# beater starter). Visual only; the window itself is PerspectiveAudio's.
		"window_control": "switch",
		# Where the driver's hands rest on the wheel, degrees up from 3 o'clock
		# for the right hand (DriverModel, 2026-10-09): nine and three on the
		# coupe's flat-bottom wheel. Per car so each interior keeps its own
		# driver; the sightline cap (DriverModel.GRIP_HIGH_DEG) bounds it.
		"driver_grip_deg": 0.0,
	}

## The starter car (balance slice 1, 2026-10-09): the P1 coupe "as found" under
## the tarp, from docs/planning/rival-and-car-ladder-proposal (option A, which
## Roy has not yet signed off; the data is here so the ladder can be measured).
## Same body, same sim, tired numbers: a worn engine that is down on torque and
## will not rev, a lazy throttle, hard old tyres, glazed brakes, one pop-up stuck
## open (drag). Everything the Act 1 restoration wins back is a stock coupe
## value, so "restored" simply means coupe_default().
static func coupe_worn() -> Dictionary:
	var s := coupe_default()
	s["max_torque"] = 290.0
	s["max_rpm"] = 5800.0
	s["torque_shape"] = {"low_end": 0.45, "peak_pos": 0.45, "plateau": 0.0, "falloff": 0.75}
	s["throttle_speed"] = 5.0
	s["motor_brake"] = 26.0
	s["coefficient_of_drag"] = 0.33
	s["coefficient_of_friction"] = {"Road": 1.0, "Dirt": 0.8}
	s["tire_stiffnesses"] = {"Road": 7.0, "Dirt": 3.0}
	s["lateral_grip_assist"] = {"Road": 0.03, "Dirt": 0.0}
	s["brake_force_multiplier"] = 2.1
	s["front_damping_ratio"] = 0.38
	s["rear_damping_ratio"] = 0.38
	s["aero_downforce_coefficient_front"] = 0.15
	s["aero_downforce_coefficient_rear"] = 0.25
	s["turbo_boost_max"] = 0.0
	return s

## Traffic tune (milestone 3, 2026-10-05): coupe_default() with commuter-car
## numbers -- a smaller engine, more drag, street tyres, hardly any downforce.
## Same simulation, different data; the three NPC cars (stage B step 5) replace
## this with their own dicts. Not measured from a real car.
## The player's cars (stage D, 2026-10-09; PlayerCars.KINDS): coupe_default()
## is the P1; each other car is the P1's tune with its own numbers from the
## PR #197 car table (torque and mass are starting values for the D data pass,
## not measured) and fleet.json's tyre widths. The same sim, different data;
## the mod trees (stage E) override these the same way.
## Turbo cars: the table's torque is the peak ON boost. GEVP's turbo multiplies
## engine torque by 1 + turbo_gain (0.45) at full boost, whatever
## turbo_boost_max is, so their max_torque is the table value / TURBO_PEAK.
const TURBO_PEAK := 1.45

static func player_spec(kind: String) -> Dictionary:
	var s := coupe_default()
	match kind:
		"p0_beater":
			# The prologue car (Roy, 2026-10-09): a worn rear-engine, air-cooled
			# flat four. About 290 Nm, power tier T0 (0.29 Nm/kg: under the T1
			# band's 0.30). Nothing is wrong with it on paper; it is just slow:
			# the torque is all low down and gone by 4500 (torque_shape falls
			# early, low redline), five long gears, narrow hard tyres on soft
			# springs, 60% of the weight over the back axle, and the drag of a
			# brick. Stability aids off: it never had any.
			var gears: Array[float] = [3.80, 2.30, 1.55, 1.10, 0.86]
			s["vehicle_mass"] = 1000.0
			s["front_weight_distribution"] = 0.40
			s["front_torque_split"] = 0.0
			s["max_torque"] = 290.0
			s["max_rpm"] = 4800.0
			s["idle_rpm"] = 850.0
			s["torque_shape"] = {"low_end": 0.55, "peak_pos": 0.40, "plateau": 0.1, "falloff": 0.35}
			s["gear_ratios"] = gears
			s["final_drive"] = 4.1
			s["coefficient_of_drag"] = 0.46
			s["frontal_area"] = 2.0
			s["front_tire_width"] = 155.0   # fleet.json physics_hint
			s["rear_tire_width"] = 165.0
			s["coefficient_of_friction"] = {"Road": 0.95, "Dirt": 0.8}
			s["front_damping_ratio"] = 0.32
			s["rear_damping_ratio"] = 0.32
			s["front_arb_ratio"] = 0.05
			s["rear_arb_ratio"] = 0.0
			s["front_spring_length"] = 0.26
			s["rear_spring_length"] = 0.28
			s["center_of_gravity_height_offset"] = 0.02
			s["traction_control_max_slip"] = 0.0
			s["stability_yaw_strength"] = 0.0
			s["brake_force_multiplier"] = 1.8
			s["aero_downforce_coefficient_front"] = 0.0
			s["aero_downforce_coefficient_rear"] = 0.0
			s["shift_time"] = 0.35
			s["automatic_time_between_shifts"] = 1200.0
		"p2_hothatch":
			# Kobo, T1: 2.0 turbo four, front drive, light, short gears. Launches.
			var gears: Array[float] = [3.25, 2.00, 1.45, 1.12, 0.90]
			s["vehicle_mass"] = 1080.0
			s["front_weight_distribution"] = 0.62
			s["front_torque_split"] = 1.0
			s["max_torque"] = 340.0 / TURBO_PEAK
			s["max_rpm"] = 7200.0
			s["gear_ratios"] = gears
			s["final_drive"] = 4.2
			s["coefficient_of_drag"] = 0.34
			s["frontal_area"] = 2.05
			s["front_tire_width"] = 225.0
			s["rear_tire_width"] = 225.0
			s["front_arb_ratio"] = 0.25
			s["rear_arb_ratio"] = 0.32   # a stiff rear bar: lift-off tuck, not plough
			s["turbo_boost_max"] = 0.5
		"p3_tuner":
			# Ronin, T2: 2.6 straight six, rear drive (the tree adds AWD). Revs.
			var gears: Array[float] = [3.20, 1.95, 1.40, 1.07, 0.85]
			s["vehicle_mass"] = 1300.0
			s["front_weight_distribution"] = 0.54
			s["front_torque_split"] = 0.0
			s["max_torque"] = 520.0 / TURBO_PEAK
			s["max_rpm"] = 7800.0
			s["gear_ratios"] = gears
			s["final_drive"] = 4.1
			s["coefficient_of_drag"] = 0.33
			s["frontal_area"] = 2.1
			s["front_tire_width"] = 245.0
			s["rear_tire_width"] = 245.0
			s["turbo_boost_max"] = 0.7
		"p4_kei":
			# Mite, T1: 0.66 triple behind the seats, rear drive, 760 kg, 9500
			# redline. Corners; slow on the straights. No turbo stock: "Small
			# turbo" is a node of its tree (PR #197), and the Tuner's torque floor
			# is 150 Nm, under which a boosted base would have to sit.
			var gears: Array[float] = [3.40, 2.20, 1.60, 1.20, 0.95]
			s["vehicle_mass"] = 760.0
			s["front_weight_distribution"] = 0.42
			s["front_torque_split"] = 0.0
			s["max_torque"] = 180.0
			# 8500 rpm, not the sheet's 9500: with this little torque the engine
			# never got there and the automatic never left 2nd (tests/fleet/player_cars.gd,
			# the same finding as the AI kei's 8000 in npc_spec). The curve
			# holds to the top, so it does reach the shift point.
			s["max_rpm"] = 8500.0
			s["idle_rpm"] = 1100.0
			s["torque_shape"] = {"low_end": 0.35, "peak_pos": 0.7, "plateau": 0.15, "falloff": 0.8}
			s["gear_ratios"] = gears
			s["final_drive"] = 4.6
			s["coefficient_of_drag"] = 0.36
			s["frontal_area"] = 1.6
			s["front_tire_width"] = 175.0
			s["rear_tire_width"] = 185.0
			s["max_steering_angle"] = deg_to_rad(42.0)
			s["center_of_gravity_height_offset"] = -0.12
		"p5_muscle":
			# Marlowe, T3: 5.7 V8, rear drive, lazy 4-speed auto, 1800 kg. Torque.
			# (The sheet's 4-speed, real since gear count is per car: first and
			# top are the old five-speed's, so launch and top speed are unchanged;
			# the two gears between have the long gaps.)
			var gears: Array[float] = [2.60, 1.60, 1.05, 0.72]
			s["vehicle_mass"] = 1800.0
			s["front_weight_distribution"] = 0.55
			s["front_torque_split"] = 0.0
			s["max_torque"] = 820.0
			s["max_rpm"] = 5800.0
			s["idle_rpm"] = 700.0
			s["torque_shape"] = {"low_end": 0.6, "peak_pos": 0.45, "plateau": 0.15, "falloff": 0.6}
			s["gear_ratios"] = gears
			s["final_drive"] = 3.4
			s["coefficient_of_drag"] = 0.36
			s["frontal_area"] = 2.35
			s["front_tire_width"] = 255.0
			s["rear_tire_width"] = 320.0
			s["front_damping_ratio"] = 0.40
			s["rear_damping_ratio"] = 0.40
			s["front_arb_ratio"] = 0.15
			s["rear_arb_ratio"] = 0.10
			s["shift_time"] = 0.3
		"p6_crossover":
			# Cairn, T2: 2.0 turbo flat four, rear drive (Roy, transmissions notes
			# section 9; was AWD 40:60), tall, lifted.
			var gears: Array[float] = [3.30, 2.00, 1.40, 1.07, 0.85]
			s["vehicle_mass"] = 1450.0
			s["front_weight_distribution"] = 0.58
			s["front_torque_split"] = 0.0
			s["max_torque"] = 580.0 / TURBO_PEAK
			s["max_rpm"] = 6800.0
			s["gear_ratios"] = gears
			s["final_drive"] = 4.0
			s["coefficient_of_drag"] = 0.36
			s["frontal_area"] = 2.45
			s["front_tire_width"] = 235.0
			s["rear_tire_width"] = 265.0
			s["coefficient_of_friction"] = {"Road": 1.2, "Dirt": 1.05}
			s["center_of_gravity_height_offset"] = 0.05
			s["turbo_boost_max"] = 0.7
		_:
			return s  # p1_coupe, or an unknown kind: the coupe
	s["exhaust"] = ExhaustTune.for_car(kind).to_dict()
	s["engine_voice"] = EngineVoice.for_car(kind)
	s["turbo_voice"] = TurboVoice.for_car(kind)
	return s

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
	s["engine_voice"] = EngineVoice.for_car("n1_commuter")
	# A commuter's exhaust: no flames (ExhaustFlames reads this; only a car
	# whose flame value is above 0 gets them, today the C3 interceptor).
	s["exhaust"] = ExhaustTune.for_car("n1_commuter").to_dict()
	return s

## The traffic cars (stage B step 5, NpcCarBuilder.KINDS): traffic_default()
## with each car's own numbers, picked to feel like its class rather than
## measured from a real car. Same sim as the player, different data. Unknown
## kinds (the old box traffic car) get traffic_default().
static func npc_spec(kind: String) -> Dictionary:
	var s := traffic_default()
	match kind:
		"n1_commuter":
			# Commuter sedan, ~2.5 l four, front drive: 1450 kg, 60% on the
			# nose, soft and quiet. Gearing for ~110 km/h at 3000 rpm in 5th.
			var gears: Array[float] = [3.30, 1.95, 1.35, 1.00, 0.78]
			s["vehicle_mass"] = 1450.0
			s["front_weight_distribution"] = 0.60
			s["front_torque_split"] = 1.0
			s["max_torque"] = 270.0
			s["max_rpm"] = 6200.0
			s["gear_ratios"] = gears
			s["final_drive"] = 3.9
			s["coefficient_of_drag"] = 0.30
			s["frontal_area"] = 2.25
			s["front_tire_width"] = 205.0   # fleet.json physics_hint
			s["rear_tire_width"] = 205.0
			s["front_damping_ratio"] = 0.42
			s["rear_damping_ratio"] = 0.42
			s["front_arb_ratio"] = 0.15
			s["rear_arb_ratio"] = 0.10
		"n2_cityhatch":
			# City hatchback, ~1.5 l four, front drive: light (1100 kg), short
			# gearing that revs high, upright and draggy, narrow tyres.
			var gears: Array[float] = [3.50, 2.05, 1.42, 1.06, 0.84]
			s["vehicle_mass"] = 1100.0
			s["front_weight_distribution"] = 0.62
			s["front_torque_split"] = 1.0
			s["max_torque"] = 215.0
			s["max_rpm"] = 6600.0
			s["gear_ratios"] = gears
			s["final_drive"] = 4.1
			s["coefficient_of_drag"] = 0.33
			s["frontal_area"] = 2.15
			s["front_tire_width"] = 185.0
			s["rear_tire_width"] = 185.0
			s["front_damping_ratio"] = 0.45
			s["rear_damping_ratio"] = 0.45
			s["front_arb_ratio"] = 0.18
			s["rear_arb_ratio"] = 0.12
		"n3_pickup":
			# Double-cab pickup, gas V6, rear drive: heavy (2100 kg), torquey and
			# low-revving, a barn door for drag, wide tyres, soft and floaty,
			# with a higher centre of gravity than the cars.
			var gears: Array[float] = [3.60, 2.20, 1.50, 1.12, 0.85]
			s["vehicle_mass"] = 2100.0
			s["front_weight_distribution"] = 0.56
			s["front_torque_split"] = 0.0
			s["max_torque"] = 380.0
			s["max_rpm"] = 5600.0
			s["gear_ratios"] = gears
			s["final_drive"] = 3.7
			s["coefficient_of_drag"] = 0.42
			s["frontal_area"] = 3.1
			s["front_tire_width"] = 265.0
			s["rear_tire_width"] = 265.0
			s["front_damping_ratio"] = 0.38
			s["rear_damping_ratio"] = 0.38
			s["front_arb_ratio"] = 0.20
			s["rear_arb_ratio"] = 0.10
			# Balance slice 1 (2026-10-09, tools/balance_sweep.gd): with the coupe's
			# road grip the pickup cornered at 1.20 g, harder than the coupe. Truck
			# tyres and a high body bring it to about 0.9 g and 100-0 near 60 m.
			# Lower grip (0.66) read 0.71 g but 75 m braking, so this is the
			# compromise; the sedans understeer at 0.75 g. On the track's corner run
			# (held steering, speed ramping under power) the truck's rear lets go
			# at about 55 degrees of slide; it did that before this pass too (43
			# degrees), and a stiff front bar plus rear toe-in did not cure it.
			s["coefficient_of_friction"] = {"Road": 0.78, "Dirt": 0.72}
			s["center_of_gravity_height_offset"] = 0.15
		# The rest of the B1 sheet as AI cars (NpcCarBuilder.KINDS, not in the
		# traffic MIX). Class numbers, not the player tune: when a player car
		# becomes drivable (stage D) it gets its own spec like coupe_default().
		"p0_beater":
			# The beater as an AI car: the player's own numbers (CarSpec.
			# player_spec), it has no faster version.
			var ps := player_spec("p0_beater")
			for k in ["vehicle_mass", "front_weight_distribution", "front_torque_split", "max_torque", "max_rpm",
					"idle_rpm", "torque_shape", "gear_ratios", "final_drive", "coefficient_of_drag", "frontal_area",
					"front_tire_width", "rear_tire_width", "coefficient_of_friction", "front_damping_ratio",
					"rear_damping_ratio", "front_arb_ratio", "rear_arb_ratio", "front_spring_length",
					"rear_spring_length", "center_of_gravity_height_offset", "engine_voice", "turbo_voice", "exhaust"]:
				s[k] = ps[k]
		"p2_hothatch":
			# Hot hatch (Golf GTI / Civic Si class), 2.0 l four, front drive: light
			# and short-geared, a stiffer rear bar so it rotates rather than ploughs.
			var gears: Array[float] = [3.25, 2.00, 1.45, 1.12, 0.90]
			s["vehicle_mass"] = 1200.0
			s["front_weight_distribution"] = 0.62
			s["front_torque_split"] = 1.0
			s["max_torque"] = 300.0
			s["max_rpm"] = 7200.0
			s["gear_ratios"] = gears
			s["final_drive"] = 4.2
			s["coefficient_of_drag"] = 0.34
			s["frontal_area"] = 2.05
			s["front_tire_width"] = 225.0   # fleet.json physics_hint
			s["rear_tire_width"] = 225.0
			s["front_damping_ratio"] = 0.50
			s["rear_damping_ratio"] = 0.50
			s["front_arb_ratio"] = 0.25
			s["rear_arb_ratio"] = 0.30
		"p3_tuner":
			# Tuner sedan (Skyline / Evo class), turbo six, four-wheel drive
			# with a rear bias, revs high.
			var gears: Array[float] = [3.20, 1.95, 1.40, 1.07, 0.85]
			s["vehicle_mass"] = 1400.0
			s["front_weight_distribution"] = 0.56
			s["front_torque_split"] = 0.4
			s["max_torque"] = 420.0
			s["max_rpm"] = 7500.0
			s["gear_ratios"] = gears
			s["final_drive"] = 4.1
			s["coefficient_of_drag"] = 0.33
			s["frontal_area"] = 2.1
			s["front_tire_width"] = 245.0   # fleet.json physics_hint
			s["rear_tire_width"] = 245.0
			s["front_damping_ratio"] = 0.50
			s["rear_damping_ratio"] = 0.50
			s["front_arb_ratio"] = 0.25
			s["rear_arb_ratio"] = 0.22
		"p4_kei":
			# Kei roadster (Beat / Cappuccino class), tiny mid-mounted three,
			# rear drive: 750 kg, little torque, very short gearing. 8000 rpm, not
			# a real Beat's 9000: with this little torque the engine never reached
			# 9000 and the automatic never left 1st (tests/traffic/npc_cars.gd).
			var gears: Array[float] = [3.40, 2.20, 1.60, 1.20, 0.95]
			s["vehicle_mass"] = 750.0
			s["front_weight_distribution"] = 0.42
			s["front_torque_split"] = 0.0
			s["max_torque"] = 200.0
			s["max_rpm"] = 8000.0
			s["gear_ratios"] = gears
			s["final_drive"] = 4.4
			s["coefficient_of_drag"] = 0.36
			s["frontal_area"] = 1.6
			s["front_tire_width"] = 175.0   # fleet.json physics_hint
			s["rear_tire_width"] = 185.0
			s["front_damping_ratio"] = 0.50
			s["rear_damping_ratio"] = 0.50
			s["front_arb_ratio"] = 0.20
			s["rear_arb_ratio"] = 0.15
		"p5_muscle":
			# Muscle sedan (Impala SS class), big V8, rear drive: heavy and
			# torquey, long gears, fat rear tyres, soft.
			var gears: Array[float] = [2.60, 1.60, 1.15, 0.90, 0.70]
			s["vehicle_mass"] = 1750.0
			s["front_weight_distribution"] = 0.55
			s["front_torque_split"] = 0.0
			s["max_torque"] = 560.0
			s["max_rpm"] = 5800.0
			s["gear_ratios"] = gears
			s["final_drive"] = 3.4
			s["coefficient_of_drag"] = 0.36
			s["frontal_area"] = 2.35
			s["front_tire_width"] = 255.0   # fleet.json physics_hint
			s["rear_tire_width"] = 320.0
			s["front_damping_ratio"] = 0.40
			s["rear_damping_ratio"] = 0.40
			s["front_arb_ratio"] = 0.15
			s["rear_arb_ratio"] = 0.10
		"p6_crossover":
			# Performance crossover (Allroad / Integrale class), turbo four,
			# four-wheel drive, tall and a little draggy.
			var gears: Array[float] = [3.30, 2.00, 1.40, 1.07, 0.85]
			s["vehicle_mass"] = 1500.0
			s["front_weight_distribution"] = 0.58
			s["front_torque_split"] = 0.5
			s["max_torque"] = 400.0
			s["max_rpm"] = 6800.0
			s["gear_ratios"] = gears
			s["final_drive"] = 4.0
			s["coefficient_of_drag"] = 0.36
			s["frontal_area"] = 2.45
			s["front_tire_width"] = 235.0   # fleet.json physics_hint
			s["rear_tire_width"] = 235.0
			s["front_damping_ratio"] = 0.45
			s["rear_damping_ratio"] = 0.45
			s["front_arb_ratio"] = 0.20
			s["rear_arb_ratio"] = 0.18
		"c1_patrol":
			# Patrol sedan (Crown Vic / Charger Pursuit class), V8, rear drive:
			# heavy, police-spec damping, long gears.
			var gears: Array[float] = [2.80, 1.70, 1.20, 0.95, 0.75]
			s["vehicle_mass"] = 1900.0
			s["front_weight_distribution"] = 0.55
			s["front_torque_split"] = 0.0
			s["max_torque"] = 430.0
			s["max_rpm"] = 6000.0
			s["gear_ratios"] = gears
			s["final_drive"] = 3.55
			s["coefficient_of_drag"] = 0.34
			s["frontal_area"] = 2.4
			s["front_tire_width"] = 235.0   # fleet.json physics_hint
			s["rear_tire_width"] = 235.0
			s["front_damping_ratio"] = 0.45
			s["rear_damping_ratio"] = 0.45
			s["front_arb_ratio"] = 0.20
			s["rear_arb_ratio"] = 0.12
		"c2_patrolsuv":
			# Patrol SUV (Interceptor Utility / Tahoe class), twin-turbo V6,
			# four-wheel drive: the heaviest car, tall, a barn door for drag.
			var gears: Array[float] = [3.40, 2.10, 1.45, 1.10, 0.85]
			s["vehicle_mass"] = 2300.0
			s["front_weight_distribution"] = 0.54
			s["front_torque_split"] = 0.4
			s["max_torque"] = 520.0
			s["max_rpm"] = 6000.0
			s["gear_ratios"] = gears
			s["final_drive"] = 3.7
			s["coefficient_of_drag"] = 0.40
			s["frontal_area"] = 3.0
			s["front_tire_width"] = 255.0   # fleet.json physics_hint
			s["rear_tire_width"] = 255.0
			s["front_damping_ratio"] = 0.40
			s["rear_damping_ratio"] = 0.40
			s["front_arb_ratio"] = 0.22
			s["rear_arb_ratio"] = 0.12
			s["center_of_gravity_height_offset"] = 0.0
		"c3_interceptor":
			# Unmarked interceptor (Charger / Mustang pursuit class),
			# supercharged V8, rear drive: the fastest cop, firm and wide-tyred.
			var gears: Array[float] = [2.90, 1.90, 1.35, 1.05, 0.82]
			s["vehicle_mass"] = 1950.0
			s["front_weight_distribution"] = 0.54
			s["front_torque_split"] = 0.0
			s["max_torque"] = 650.0
			s["max_rpm"] = 6200.0
			s["gear_ratios"] = gears
			s["final_drive"] = 3.3
			s["coefficient_of_drag"] = 0.33
			s["frontal_area"] = 2.25
			s["front_tire_width"] = 255.0   # fleet.json physics_hint
			s["rear_tire_width"] = 275.0
			s["front_damping_ratio"] = 0.50
			s["rear_damping_ratio"] = 0.50
			s["front_arb_ratio"] = 0.22
			s["rear_arb_ratio"] = 0.16
	return s

## Physics layers (milestone 3). Every car sits on CAR_LAYER and collides with
## the world (WORLD_LAYER: ground slab, sidewalks, buildings) and with other
## cars. A Wheel is a RayCast3D on the default mask, layer 1 only, so a wheel
## never sees a car body. That is not just tidiness: the vendored Wheel takes
## its tyre numbers from the FIRST group of whatever it hits (gevp_wheel.gd
## process_forces), a car's first group is "aero_vehicles", and
## coefficient_of_friction["aero_vehicles"] does not exist.
##
## Walls (WALL_LAYER: the out-of-bounds walls and the buildings) are off layer
## 1 for the same reason (2026-10-07). A car pressed against a wall leans into
## it, its wheel rays tip with it and land on the wall face, and the springs
## then push the car up the wall: Roy's "the car bugs out on the walls", up to
## 4 m in the air and on its roof at 200 km/h (tests/car/wall_hit.gd). Car bodies
## still collide with walls; wheels only ever see the ground and sidewalks.
##
## The sidewalks (KERB_LAYER) are the opposite: wheels see them, car bodies do
## not. The chassis box rides ~4 cm off the road, so crossing the 15 cm kerb
## ramp at speed used to drive the box up it like a ski jump (4 m/s straight
## up at 126 km/h, tests/car/wall_hit.gd) and the car reached the wall airborne and
## tumbled. Now the wheels climb the kerb through the suspension, as on a real
## car, and the box can only touch the road, walls and other cars.
const WORLD_LAYER := 1
const CAR_LAYER := 2
const WALL_LAYER := 3
const KERB_LAYER := 4

static func set_collision_layers(v: Vehicle) -> void:
	v.collision_layer = 1 << (CAR_LAYER - 1)
	v.collision_mask = (1 << (WORLD_LAYER - 1)) | (1 << (CAR_LAYER - 1)) | (1 << (WALL_LAYER - 1))

## Puts a wall body on WALL_LAYER with a frictionless surface, so a car that
## hits it slides along or bounces off instead of being grabbed and rolled.
static func make_wall(body: StaticBody3D) -> void:
	body.collision_layer = 1 << (WALL_LAYER - 1)
	body.collision_mask = 0
	body.physics_material_override = _wall_material()

static var _wall_mat: PhysicsMaterial

static func _wall_material() -> PhysicsMaterial:
	if _wall_mat == null:
		_wall_mat = PhysicsMaterial.new()
		_wall_mat.friction = 0.0
		_wall_mat.bounce = 0.1
	return _wall_mat

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
	# GEVP casts each wheel itself (force_raycast_update() in process_forces)
	# every tick. Left enabled, RayCast3D also casts on its own right after,
	# from the same spot, and a frozen traffic car's wheels kept casting with
	# no sim reading them: half the wheel raycasts were wasted (frame-rate
	# pass, 2026-10-08). is_colliding() and friends still read the last cast.
	w.enabled = false
	w.collision_mask = (1 << (WORLD_LAYER - 1)) | (1 << (KERB_LAYER - 1))
	v.add_child(w)
	var visual: Node3D
	if kind == TestCarBuilder.KIND:
		visual = TestCarBuilder.build_wheel_visual(v.front_tire_radius)
	elif kind == P1CoupeBuilder.KIND:
		visual = P1CoupeBuilder.build_wheel_visual(v.front_tire_radius, pos)
	elif NpcCarBuilder.is_npc(kind):
		# Traffic cars (TrafficCar.build names the sheet variant).
		visual = NpcCarBuilder.wheel_visual(kind, String(v.get("build")), pos)
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
	col.shape = chassis_hull(size)
	col.position = Vector3(0.0, y_offset, 0.0)
	v.add_child(col)

## Underbody lift (m) at the box's ends and sides, and the half-size of the flat
## patch left at full depth in the middle (fractions of the box's half length
## and half width, capped in metres).
const HULL_LIFT := 0.18
const HULL_PATCH_Z := 0.3
const HULL_PATCH_X := 0.4

## The chassis shape: the `size` box with its underside lifted towards the
## ends and sides, like a real car's approach and departure angles. The box's
## bottom corners sat 3-8 cm off the road, and throttle squat (about 3 deg) or
## brake dive (about 1.6 deg) over 1.7 m of half length put one in the road at
## 2 m/s: a body contact, so CrashAudio's metal scrape played on a clean road
## (Roy 2026-10-09, tests/car/car_scrape.gd). The hull keeps the box's exact
## bounding box, which is all the physics engine reads for mass distribution
## (GodotPhysics takes a convex shape's inertia from its AABB), so inertia, the
## centre of mass, and every side and top face are unchanged.
static func chassis_hull(size: Vector3) -> ConvexPolygonShape3D:
	var h := size * 0.5
	var lift := minf(HULL_LIFT, size.y * 0.3)
	var px := minf(h.x * HULL_PATCH_X, 0.35)
	var pz := minf(h.z * HULL_PATCH_Z, 0.6)
	var pts := PackedVector3Array()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			pts.append(Vector3(sx * h.x, h.y, sz * h.z))                 # roof corners
			pts.append(Vector3(sx * h.x, -h.y + lift, sz * h.z))         # lifted underside corners
			pts.append(Vector3(sx * px, -h.y, sz * pz))                  # the flat patch at full depth
	var hull := ConvexPolygonShape3D.new()
	hull.points = pts
	return hull
