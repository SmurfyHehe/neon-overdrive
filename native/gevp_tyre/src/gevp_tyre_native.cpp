#include "gevp_tyre_native.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>

using namespace godot;

// GDScript floats are doubles, Vector2/Vector3 components are 32-bit floats.
// force_vector and slip_vector are Vector2 in the script, so every store into
// them rounds to float; the casts below keep that rounding in the same places.

static inline double sign_of(double v) {
	return v > 0.0 ? 1.0 : (v < 0.0 ? -1.0 : 0.0);
}

static inline double clamp_of(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

void GevpTyreNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("process_tires", "local_velocity", "spin", "tire_radius", "wheel_moment",
								 "delta", "applied_torque", "mass_over_wheel", "tire_stiffness",
								 "contact_patch", "pressure_stiffness_mult", "load_sensitivity",
								 "spring_force", "cof", "grip_mult", "pressure_grip_mult",
								 "tire_width", "braking", "braking_grip_multiplier",
								 "longitudinal_grip_ratio", "lateral_grip_assist", "camber_lateral_mult",
								 "camber_long_mult", "rolling_resistance", "pressure_roll_mult"),
			&GevpTyreNative::process_tires);
	ClassDB::bind_method(D_METHOD("get_limit_spin"), &GevpTyreNative::get_limit_spin);
}

Vector4 GevpTyreNative::process_tires(Vector3 lv, double spin, double tire_radius, double wheel_moment,
		double delta, double applied_torque, double mass_over_wheel, double tire_stiffness,
		double contact_patch, double pressure_stiffness_mult, double load_sensitivity,
		double spring_force, double cof, double grip_mult, double pressure_grip_mult,
		double tire_width, bool braking, double braking_grip_multiplier,
		double longitudinal_grip_ratio, double lateral_grip_assist, double camber_lateral_mult,
		double camber_long_mult, double rolling_resistance, double pressure_roll_mult) {
	// Vector2(lv.x, lv.z).normalized() * clampf(lv.length(), 0.0, 1.0)
	float px = lv.x;
	float pz = lv.z;
	float pl = px * px + pz * pz;
	if (pl != 0.0f) {
		pl = std::sqrt(pl);
		px /= pl;
		pz /= pl;
	}
	float lv_len = std::sqrt(lv.x * lv.x + lv.y * lv.y + lv.z * lv.z);
	float planar_x = px * (float)clamp_of((double)lv_len, 0.0, 1.0);

	float slip_x = (float)std::asin(clamp_of(-(double)planar_x, -1.0, 1.0));
	float slip_y = 0.0f;

	double lvx = (double)lv.x;
	double lvz = (double)lv.z;
	double wheel_velocity = spin * tire_radius;
	double spin_velocity_diff = wheel_velocity + lvz;
	double needed_rolling_force = ((spin_velocity_diff * wheel_moment) / tire_radius) / delta;
	double max_y_force = 0.0;
	if (std::abs(applied_torque) > std::abs(needed_rolling_force)) {
		max_y_force = std::abs(applied_torque / tire_radius);
	} else {
		max_y_force = std::abs(needed_rolling_force / tire_radius);
	}

	double max_x_force = std::abs(mass_over_wheel * lvx) / delta;

	double z_sign = sign_of(-lvz);
	if (lvz == 0.0) {
		z_sign = 1.0;
	}

	slip_y = (float)((std::abs(lvz) - (wheel_velocity * z_sign)) / (1.0 + std::abs(lvz)));

	// Vector2.is_zero_approx()
	if (std::abs(slip_x) < 0.00001f && std::abs(slip_y) < 0.00001f) {
		slip_x = 0.0001f;
		slip_y = 0.0001f;
	}
	double sx = (double)slip_x;
	double sy = (double)slip_y;

	double cornering_stiffness = 0.5 * tire_stiffness * std::pow(contact_patch, 2.0) * pressure_stiffness_mult;
	double load_factor = 1.0;
	if (load_sensitivity > 0.0 && spring_force > 1.0) {
		double ref = mass_over_wheel * 9.81;
		if (ref < 1.0) {
			ref = 1.0;
		}
		load_factor = std::pow(clamp_of(spring_force / ref, 0.25, 4.0), -load_sensitivity);
	}
	double friction = cof * grip_mult * pressure_grip_mult * load_factor * spring_force - (spring_force / (tire_width * contact_patch * 0.2));
	double deflect = 1.0 / (std::sqrt(std::pow(cornering_stiffness * sy, 2.0) + std::pow(cornering_stiffness * sx, 2.0)));

	double braking_help = 1.0;
	if (sy > 0.3 && braking) {
		braking_help = (1 + (braking_grip_multiplier * clamp_of(std::abs(sy), 0.0, 1.0)));
	}

	float force_x = 0.0f;
	float force_y = 0.0f;
	double crit_length = friction * (1.0 - sy) * contact_patch * (0.5 * deflect);
	if (crit_length >= contact_patch) {
		force_y = (float)(cornering_stiffness * sy / (1.0 - sy));
		force_x = (float)(cornering_stiffness * sx / (1.0 - sy));
	} else {
		double brushx = (1.0 - friction * (1.0 - sy) * (0.25 * deflect)) * deflect;
		force_y = (float)(friction * longitudinal_grip_ratio * cornering_stiffness * sy * brushx * braking_help * z_sign);
		force_x = (float)(friction * cornering_stiffness * sx * brushx * (std::abs(sx * lateral_grip_assist) + 1.0));
	}

	// The script only multiplies when camber_active; the wrapper passes 1.0 otherwise.
	force_x = (float)((double)force_x * camber_lateral_mult);
	force_y = (float)((double)force_y * camber_long_mult);

	if (std::abs((double)force_y) > std::abs(max_y_force)) {
		force_y = (float)(max_y_force * sign_of((double)force_y));
		limit_spin = true;
	} else {
		limit_spin = false;
	}

	if (std::abs((double)force_x) > max_x_force) {
		force_x = (float)(max_x_force * sign_of((double)force_x));
	}

	// process_rolling_resistance()
	double rolling_resistance_coefficient = 0.005 + (0.5 * (0.01 + (0.0095 * std::pow(lvz * 0.036, 2))));
	double rolling = rolling_resistance_coefficient * spring_force * rolling_resistance * pressure_roll_mult;
	force_y = (float)((double)force_y - rolling * sign_of(lvz));

	return Vector4(force_x, force_y, slip_x, slip_y);
}
