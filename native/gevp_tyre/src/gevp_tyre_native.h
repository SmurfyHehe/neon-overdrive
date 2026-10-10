#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>

namespace godot {

// The tyre maths of scripts/vendor/gevp/gevp_wheel.gd process_tires(), line for
// line, as one native call. Experiment (2026-10-10): the GDScript stays the
// reference; scripts/car/gevp_wheel_native.gd calls this instead when the
// native path is switched on.
class GevpTyreNative : public RefCounted {
	GDCLASS(GevpTyreNative, RefCounted)

	bool limit_spin = false;

protected:
	static void _bind_methods();

public:
	// Returns (force.x, force.y, slip.x, slip.y).
	Vector4 process_tires(Vector3 local_velocity, double spin, double tire_radius, double wheel_moment,
			double delta, double applied_torque, double mass_over_wheel, double tire_stiffness,
			double contact_patch, double pressure_stiffness_mult, double load_sensitivity,
			double spring_force, double cof, double grip_mult, double pressure_grip_mult,
			double tire_width, bool braking, double braking_grip_multiplier,
			double longitudinal_grip_ratio, double lateral_grip_assist, double camber_lateral_mult,
			double camber_long_mult, double rolling_resistance, double pressure_roll_mult);
	bool get_limit_spin() const { return limit_spin; }
};

} // namespace godot
