extends Wheel

# A Wheel whose tyre maths runs in C++ (GevpTyreNative, native/gevp_tyre).
# Experiment, 2026-10-10. Everything else is the vendored GDScript wheel.
# No class_name on purpose: this file only parses when the native library is
# loaded, so it is loaded by path, and only by NativeTyres.new_wheel().

var _tyre := GevpTyreNative.new()

func process_tires(braking : bool, delta : float):
	var r := _tyre.process_tires(local_velocity, spin, tire_radius, wheel_moment,
			delta, applied_torque, mass_over_wheel, current_tire_stiffness,
			contact_patch, pressure_stiffness_mult, vehicle.tyre_load_sensitivity,
			spring_force, current_cof, grip_mult, pressure_grip_mult,
			tire_width, braking, braking_grip_multiplier,
			current_longitudinal_grip_ratio, current_lateral_grip_assist,
			_camber_lateral_mult() if camber_active else 1.0,
			camber_long_mult if camber_active else 1.0,
			current_rolling_resistance, pressure_roll_mult)
	force_vector = Vector2(r.x, r.y)
	slip_vector = Vector2(r.z, r.w)
	spin_velocity_diff = spin * tire_radius + local_velocity.z
	limit_spin = _tyre.get_limit_spin()
