# CarSpec (2026-09-13, Roy: "i want full physics everywhere... we make every
# wheel sim different based off user/npc/cops no mods/mods and how different
# mods change each wheel sim"): every car in the game -- player, traffic NPCs,
# cops later, any mod state -- runs the SAME real vendored raycast Vehicle/
# Wheel simulation (scripts/vendor/gevp/). What differs per car is only DATA:
# mass, torque, gearing, tire grip, suspension. This file is that data layer,
# extracted out of player.gd (which used to hardcode all of this inline) so
# a future NPCCar/CopCar just builds its own spec dict -- possibly starting
# from coupe_default() and overriding a few fields -- and calls the same
# apply()/build_wheels()/build_collision() helpers PlayerCar now uses. Mods
# (milestone 10) plug in here too: a mod multiplies/overrides entries in a
# car's spec dict before CarSpec.apply() runs, rather than needing separate
# code paths per mod.
extends RefCounted
class_name CarSpec

## Every key here is a real property name on the vendored Vehicle class --
## apply() just does v.set(key, value) for each, so ANY subset of Vehicle's
## tunables can be described as a spec dict, including a partial dict a mod
## builds by copying a base spec and changing a few entries.
static func apply(v: Vehicle, spec: Dictionary) -> void:
	for key in spec:
		v.set(key, spec[key])

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
	var gear_ratios_typed: Array[float] = [3.6, 2.4, 1.8, 1.4, 0.95]
	return {
		"vehicle_mass": 1300.0,
		"front_weight_distribution": 0.45,
		"front_torque_split": 0.0,  # RWD
		"max_torque": 460.0,
		"max_rpm": 7000.0,
		"idle_rpm": 1000.0,
		"torque_curve": default_torque_curve(),
		"gear_ratios": gear_ratios_typed,
		"final_drive": 4.1,
		"automatic_transmission": false,
		"coefficient_of_drag": 0.26,
		"frontal_area": 1.9,
		"max_steering_angle": deg_to_rad(38.0),
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
		# For scale, real street tires are ~1.0 and slicks ~1.6, so 3.0 is
		# arcade-high cornering grip. It is GEVP's own shipped Road default,
		# not a leftover. Grip feel is Roy's call -- tune by driving, and
		# note that spring_force includes aero downforce, so grip also
		# rises with speed. Also feeds max_brake_force (gevp_vehicle.gd).
		"coefficient_of_friction": {"Road": 3.0, "Dirt": 2.0},
		"rolling_resistance": {"Road": 1.0, "Dirt": 1.6},
		"lateral_grip_assist": {"Road": 0.05, "Dirt": 0.0},
		"longitudinal_grip_ratio": {"Road": 0.5, "Dirt": 0.45},

		# Aero (2026-09-13, Roy: "add aerodynamics to the game" -> full model):
		# these aren't vendored Vehicle properties -- they're plain vars
		# declared on PlayerCar itself (see player.gd) and consumed by
		# aero.gd's AeroModel, applied through this same v.set() loop like
		# everything else here. Rear-biased split matches the coupe's visual
		# rear spoiler (car_builder.gd) and its RWD/rear weight bias -- more
		# rear downforce helps put power down without adding front push that
		# would fight the steering feel already tuned. Not measured from a
		# real car, [stated]-flagged as likely to need retuning once driven.
		"aero_lift_coefficient_front": 0.35,
		"aero_lift_coefficient_rear": 0.55,
	}

## Rise-then-taper torque curve, loosely modeled on a real gasoline engine's
## band, not measured from anything specific -- same shape every car uses for
## now; giving different car types their own curve shape is an easy future
## knob once this matters.
static func default_torque_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.35))
	c.add_point(Vector2(0.25, 0.75))
	c.add_point(Vector2(0.55, 1.0))
	c.add_point(Vector2(0.85, 0.9))
	c.add_point(Vector2(1.0, 0.55))
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
	var visual := CarBuilder.build_wheel_visual(kind)
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
