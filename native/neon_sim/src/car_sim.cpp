// Port of scripts/vendor/gevp/gevp_wheel.gd (GEVP, MIT licence: Copyright (c)
// 2024 David Shoemaker, 2021 Dechode, 2024 Baron Wittman; full text in
// scripts/vendor/gevp/LICENSE.txt). See car_sim.h.
#include "car_sim.h"

#include <godot_cpp/classes/ray_cast3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cmath>

using namespace godot;

// The script's signf / clampf / maxf / absf, on doubles as in the script.
static inline double signf(double v) {
	return v > 0.0 ? 1.0 : (v < 0.0 ? -1.0 : 0.0);
}

static inline double clampf(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

static inline double maxf(double a, double b) {
	return a > b ? a : b;
}

// gevp_wheel.gd deviation (12): tyre pressure and camber. Same numbers as the
// script's constants CAMBER_PEAK, CAMBER_FALLOFF and CAMBER_ROLL_GAIN.
static const double CAMBER_PEAK = -1.0;
static const double CAMBER_FALLOFF = 0.008;
static const double CAMBER_ROLL_GAIN = 0.7;

// Wheel.camber_lateral_curve()
static inline double camber_lateral_curve(double effective_deg) {
	double off_peak = effective_deg - CAMBER_PEAK; // deviation (15d): x * x, not pow(x, 2)
	return maxf(1.0 - CAMBER_FALLOFF * (off_peak * off_peak), 0.4);
}

static inline Vector3 read_v3(const double *p) {
	return Vector3((real_t)p[0], (real_t)p[1], (real_t)p[2]);
}

static inline void write_v3(double *p, const Vector3 &v) {
	p[0] = v.x;
	p[1] = v.y;
	p[2] = v.z;
}

CarSim::CarSim() {
	sim_surface_method = StringName("sim_surface");
	out.resize(OUT_HEADER + WHEELS * W_OUT);
}

void CarSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("add_car", "wheels"), &CarSim::add_car);
	ClassDB::bind_method(D_METHOD("remove_car", "car_id"), &CarSim::remove_car);
	ClassDB::bind_method(D_METHOD("get_car_count"), &CarSim::get_car_count);
	ClassDB::bind_method(D_METHOD("set_surface", "collider_id", "surface"), &CarSim::set_surface);
	ClassDB::bind_method(D_METHOD("get_surface_count"), &CarSim::get_surface_count);
	ClassDB::bind_method(D_METHOD("step_wheels", "car_id", "inputs"), &CarSim::step_wheels);
	ClassDB::bind_method(D_METHOD("get_input_size"), &CarSim::get_input_size);
	ClassDB::bind_method(D_METHOD("get_output_size"), &CarSim::get_output_size);
}

int CarSim::add_car(const Array &p_wheels) {
	if (p_wheels.size() != WHEELS) {
		return -1;
	}
	Car car;
	car.used = true;
	for (int i = 0; i < WHEELS; i++) {
		RayCast3D *wheel = Object::cast_to<RayCast3D>(p_wheels[i].operator Object *());
		if (wheel == nullptr) {
			return -1;
		}
		car.wheel_id[i] = wheel->get_instance_id();
	}
	int id;
	if (!free_ids.empty()) {
		id = free_ids.back();
		free_ids.pop_back();
		cars[id] = car;
	} else {
		id = (int)cars.size();
		cars.push_back(car);
	}
	return id;
}

void CarSim::remove_car(int p_car_id) {
	if (p_car_id < 0 || p_car_id >= (int)cars.size() || !cars[p_car_id].used) {
		return;
	}
	cars[p_car_id] = Car();
	free_ids.push_back(p_car_id);
}

int CarSim::get_car_count() const {
	return (int)cars.size() - (int)free_ids.size();
}

int CarSim::surface_index(const StringName &p_name) {
	for (int i = 0; i < (int)surface_names.size(); i++) {
		if (surface_names[i] == p_name) {
			return i;
		}
	}
	surface_names.push_back(p_name);
	return (int)surface_names.size() - 1;
}

void CarSim::set_surface(uint64_t p_collider_id, const StringName &p_surface) {
	surface_of[p_collider_id] = surface_index(p_surface);
}

int CarSim::get_surface_count() const {
	return (int)surface_of.size();
}

PackedFloat64Array CarSim::step_wheels(int p_car_id, const PackedFloat64Array &p_inputs) {
	if (p_car_id < 0 || p_car_id >= (int)cars.size() || !cars[p_car_id].used) {
		return PackedFloat64Array();
	}
	if (p_inputs.size() != IN_HEADER + WHEELS * W_IN) {
		return PackedFloat64Array();
	}
	Car &car = cars[p_car_id];
	RayCast3D *wheels[WHEELS];
	for (int i = 0; i < WHEELS; i++) {
		wheels[i] = Object::cast_to<RayCast3D>(ObjectDB::get_instance(car.wheel_id[i]));
		if (wheels[i] == nullptr) {
			return PackedFloat64Array();
		}
	}

	const double *in = p_inputs.ptr();
	double *o = out.ptrw();

	const double delta = in[IN_DELTA];
	const bool braking = in[IN_BRAKING] != 0.0;
	const double vehicle_mass = in[IN_MASS];
	const Vector3 center = read_v3(in + IN_CENTER);
	const Vector3 gravity = read_v3(in + IN_GRAVITY);
	const double load_sensitivity = in[IN_LOAD_SENSITIVITY];
	const double body_tilt_deg = in[IN_BODY_TILT_DEG];
	const int64_t epoch = (int64_t)in[IN_SURFACE_EPOCH];

	// Wheel.surface_epoch moved: a ground body changed its group, so nothing
	// remembered about colliders can be trusted (deviation 15a). Also keeps the
	// table from growing without bound as chunks come and go.
	if (epoch != table_epoch || surface_of.size() > 8192) {
		surface_of.clear();
		table_epoch = epoch;
	}

	Vector3 total_force;
	Vector3 total_torque;
	bool any_force = false;

	for (int i = 0; i < WHEELS; i++) {
		RayCast3D *wheel = wheels[i];
		const double *w = in + IN_HEADER + i * W_IN;
		double *r = o + OUT_HEADER + i * W_OUT;
		// Vehicle.process_forces(): the left wheel is given the right wheel's
		// compression of last tick and the other way round.
		const double opposite_compression = in[IN_COMPRESSION + (i ^ 1)];

		const double wheel_mass = w[W_WHEEL_MASS];
		const double tire_radius = w[W_TIRE_RADIUS];
		const double tire_width = w[W_TIRE_WIDTH];
		const double contact_patch = w[W_CONTACT_PATCH];
		const double braking_grip_multiplier = w[W_BRAKING_GRIP_MULT];
		const double spring_length = w[W_SPRING_LENGTH];
		const double spring_rate = w[W_SPRING_RATE];
		const double slow_bump = w[W_SLOW_BUMP];
		const double fast_bump = w[W_FAST_BUMP];
		const double slow_rebound = w[W_SLOW_REBOUND];
		const double fast_rebound = w[W_FAST_REBOUND];
		const double fast_damp_threshold = w[W_FAST_DAMP_THRESHOLD];
		const double antiroll = w[W_ANTIROLL];
		const double bump_stop_multiplier = w[W_BUMP_STOP_MULT];
		double wheel_to_body_torque_multiplier = w[W_BODY_TORQUE_MULT];
		const double mass_over_wheel = w[W_MASS_OVER_WHEEL];
		const double wheel_moment = w[W_WHEEL_MOMENT];
		double spin = w[W_SPIN];
		const double applied_torque = w[W_APPLIED_TORQUE];
		double max_spring_length = w[W_MAX_SPRING_LENGTH];
		double current_cof = w[W_COF];
		const double grip_mult = w[W_GRIP_MULT];
		double current_rolling_resistance = w[W_ROLLING_RESISTANCE];
		const double pressure_stiffness_mult = w[W_PRESSURE_STIFFNESS_MULT];
		const double pressure_grip_mult = w[W_PRESSURE_GRIP_MULT];
		const double pressure_roll_mult = w[W_PRESSURE_ROLL_MULT];
		double current_lateral_grip_assist = w[W_LATERAL_GRIP_ASSIST];
		double current_longitudinal_grip_ratio = w[W_LONGITUDINAL_GRIP_RATIO];
		double current_tire_stiffness = w[W_TIRE_STIFFNESS];
		double spin_velocity_diff = w[W_SPIN_VELOCITY_DIFF];
		bool limit_spin = w[W_LIMIT_SPIN] != 0.0;
		if (w[W_SURFACE_KNOWN] == 0.0) {
			car.surface_collider[i] = 0; // Wheel.initialize() forgot it
		}

		// ---------- Wheel.process_forces() ----------
		wheel->force_raycast_update();
		// (15c) the wheel does not move inside this call: read its transform once
		const Transform3D wheel_transform = wheel->get_global_transform();
		const Vector3 wheel_origin = wheel_transform.origin;
		const Basis wheel_basis = wheel_transform.basis;
		const bool colliding = wheel->is_colliding();
		const Vector3 previous_velocity = read_v3(w + W_LOCAL_VELOCITY);
		// (origin - previous_global_position) / delta * basis
		const Vector3 local_velocity = wheel_basis.xform_inv((wheel_origin - read_v3(w + W_PREVIOUS_POSITION)) / (real_t)delta);

		// Determine the surface the tire is on. Uses node groups
		Object *last_collider = nullptr;
		Vector3 last_collision_point;
		Vector3 last_collision_normal;
		if (colliding) {
			last_collider = wheel->get_collider();
			last_collision_point = wheel->get_collision_point();
			last_collision_normal = wheel->get_collision_normal();
			// (15a) only look the surface up when the ground under the wheel is a
			// different collider, or someone changed a ground body's group
			if (last_collider != nullptr) {
				const uint64_t collider_id = last_collider->get_instance_id();
				if (collider_id != car.surface_collider[i] || car.surface_epoch[i] != epoch) {
					car.surface_collider[i] = collider_id;
					car.surface_epoch[i] = epoch;
					int surface = -1;
					auto found = surface_of.find(collider_id);
					if (found != surface_of.end()) {
						surface = found->second;
					} else {
						// Not told at spawn: ask for the groups, once per collider.
						Node *ground = Object::cast_to<Node>(last_collider);
						if (ground != nullptr) {
							TypedArray<StringName> groups = ground->get_groups();
							if (groups.size() > 0) {
								surface = surface_index(groups[0]);
							}
						}
						surface_of[collider_id] = surface;
					}
					if (surface >= 0) {
						// The wheel's per-surface numbers live in its script
						// dictionaries; it switches itself and hands back the five
						// numbers when the surface really changed (rare).
						PackedFloat64Array numbers = wheel->call(sim_surface_method, surface_names[surface]);
						if (numbers.size() == 5) {
							current_cof = numbers[0];
							current_rolling_resistance = numbers[1];
							current_lateral_grip_assist = numbers[2];
							current_longitudinal_grip_ratio = numbers[3];
							current_tire_stiffness = numbers[4];
						}
					}
				}
			}
		}
		const bool contact = colliding && last_collider != nullptr;

		// ---------- Wheel.process_suspension() ----------
		double spring_current_length;
		if (contact) {
			spring_current_length = (double)last_collision_point.distance_to(wheel_origin) - tire_radius;
		} else {
			spring_current_length = spring_length;
		}

		bool no_contact = false;
		if (spring_current_length > max_spring_length) {
			spring_current_length = max_spring_length;
			no_contact = true;
		}

		bool bottom_out = false;
		if (spring_current_length < 0.0) {
			spring_current_length = 0.0;
			bottom_out = true;
		}

		const double compression = (spring_length - spring_current_length) * 1000.0;

		const double spring_speed_mm_per_seconds = (compression - w[W_PREVIOUS_COMPRESSION]) / delta;

		double spring_force = compression * spring_rate;
		const double antiroll_force = antiroll * (compression - opposite_compression);
		spring_force += antiroll_force;

		// If the suspension is bottomed out, apply some additional forces to help
		// keep the vehicle body from colliding with the surface.
		double bottom_out_damping = 0.0;
		double bottom_out_damping_fast = 0.0;
		double bottom_out_force = 0.0;
		if (bottom_out) {
			const double gravity_on_spring = clampf((double)wheel_basis.get_column(1).dot(-gravity.normalized()), 0.0, 1.0);
			bottom_out_force = (((mass_over_wheel * clampf(spring_speed_mm_per_seconds * 0.001, 0.0, 5.0)) / delta) + (mass_over_wheel * (double)gravity.length() * gravity_on_spring)) * bump_stop_multiplier;
			bottom_out_damping = -slow_bump;
			bottom_out_damping_fast = -fast_bump;
		}

		double damping_force;
		if (spring_speed_mm_per_seconds >= 0) {
			if (spring_speed_mm_per_seconds > fast_damp_threshold) {
				damping_force = ((spring_speed_mm_per_seconds - fast_damp_threshold) * (fast_bump + bottom_out_damping_fast)) + (fast_damp_threshold * (slow_bump + bottom_out_damping));
			} else {
				damping_force = spring_speed_mm_per_seconds * (slow_bump + bottom_out_damping);
			}
		} else {
			if (spring_speed_mm_per_seconds < -fast_damp_threshold) {
				damping_force = ((spring_speed_mm_per_seconds + fast_damp_threshold) * fast_rebound) + (-fast_damp_threshold * slow_rebound);
			} else {
				damping_force = spring_speed_mm_per_seconds * slow_rebound;
			}
		}

		spring_force += damping_force;

		spring_force = maxf(0, spring_force + bottom_out_force);

		max_spring_length = clampf((((spring_force / wheel_mass) - spring_speed_mm_per_seconds) * delta * 0.001) + spring_current_length, 0.0, spring_length);

		if (no_contact) {
			spring_force = 0.0;
		}

		// force_vector and slip_vector are Vector2 in the script: 32-bit.
		Vector2 force_vector;
		Vector2 slip_vector;
		bool has_force = false;
		double returned_compression = 0.0;

		if (contact) {
			// ---------- Wheel.process_tires() ----------
			// A modified brush tire model without the friction falloff beyond the
			// peak grip level.
			const Vector2 local_planar = Vector2(local_velocity.x, local_velocity.z).normalized() * (real_t)clampf((double)local_velocity.length(), 0.0, 1.0);
			// asin() and pow() go through the engine so both paths get the very
			// same function (the C runtime's may round the last bit differently).
			slip_vector.x = (real_t)UtilityFunctions::asin(clampf(-(double)local_planar.x, -1.0, 1.0));
			slip_vector.y = 0.0;

			const double lvx = (double)local_velocity.x;
			const double lvz = (double)local_velocity.z;
			const double wheel_velocity = spin * tire_radius;
			spin_velocity_diff = wheel_velocity + lvz;
			const double needed_rolling_force = ((spin_velocity_diff * wheel_moment) / tire_radius) / delta;
			double max_y_force = 0.0;

			// The force the tire applies comes from slip, so cap it by the applied
			// engine torque to stop the tire making too much force.
			if (std::abs(applied_torque) > std::abs(needed_rolling_force)) {
				max_y_force = std::abs(applied_torque / tire_radius);
			} else {
				max_y_force = std::abs(needed_rolling_force / tire_radius);
			}

			double max_x_force = 0.0;
			max_x_force = std::abs(mass_over_wheel * lvx) / delta;

			double z_sign = signf(-lvz);
			if (lvz == 0.0) {
				z_sign = 1.0;
			}

			slip_vector.y = (real_t)((std::abs(lvz) - (wheel_velocity * z_sign)) / (1.0 + std::abs(lvz)));

			if (slip_vector.is_zero_approx()) {
				slip_vector = Vector2(0.0001, 0.0001);
			}
			const double slip_x = (double)slip_vector.x;
			const double slip_y = (double)slip_vector.y;

			const double cornering_stiffness = 0.5 * current_tire_stiffness * (contact_patch * contact_patch) * pressure_stiffness_mult; // (15d)
			// Deviation (10), load sensitivity: grip per unit of load falls as the
			// load rises. load_sensitivity is the exponent loss (0 = off); the
			// reference load is this wheel's share of the static weight.
			double load_factor = 1.0;
			if (load_sensitivity > 0.0 && spring_force > 1.0) {
				load_factor = UtilityFunctions::pow(clampf(spring_force / maxf(mass_over_wheel * 9.81, 1.0), 0.25, 4.0), -load_sensitivity);
			}
			// Deviation (10) grip_mult: tyre temperature and wear; (12) pressure_grip_mult.
			const double friction = current_cof * grip_mult * pressure_grip_mult * load_factor * spring_force - (spring_force / (tire_width * contact_patch * 0.2));
			const double stiff_slip_y = cornering_stiffness * slip_y; // (15d)
			const double stiff_slip_x = cornering_stiffness * slip_x;
			const double deflect = 1.0 / (std::sqrt(stiff_slip_y * stiff_slip_y + stiff_slip_x * stiff_slip_x));

			// Adds in additional longitudinal grip when braking
			double braking_help = 1.0;
			if (slip_y > 0.3 && braking) {
				braking_help = (1 + (braking_grip_multiplier * clampf(std::abs(slip_y), 0.0, 1.0)));
			}

			const double crit_length = friction * (1.0 - slip_y) * contact_patch * (0.5 * deflect);
			if (crit_length >= contact_patch) {
				force_vector.y = (real_t)(cornering_stiffness * slip_y / (1.0 - slip_y));
				force_vector.x = (real_t)(cornering_stiffness * slip_x / (1.0 - slip_y));
			} else {
				const double brushx = (1.0 - friction * (1.0 - slip_y) * (0.25 * deflect)) * deflect;
				force_vector.y = (real_t)(friction * current_longitudinal_grip_ratio * cornering_stiffness * slip_y * brushx * braking_help * z_sign);
				force_vector.x = (real_t)(friction * cornering_stiffness * slip_x * brushx * (std::abs(slip_x * current_lateral_grip_assist) + 1.0));
			}

			// Deviation (12): camber. Lateral grip against stock at the current
			// body roll (Wheel._camber_lateral_mult()), launch and braking grip
			// by static camber.
			if (w[W_CAMBER_ACTIVE] != 0.0) {
				const double roll = w[W_CAMBER_SIDE] * body_tilt_deg * CAMBER_ROLL_GAIN;
				const double lateral_mult = camber_lateral_curve(w[W_STATIC_CAMBER] + roll) / camber_lateral_curve(w[W_STATIC_CAMBER_STOCK] + roll);
				force_vector.x = (real_t)((double)force_vector.x * lateral_mult);
				force_vector.y = (real_t)((double)force_vector.y * w[W_CAMBER_LONG_MULT]);
			}

			if (std::abs((double)force_vector.y) > std::abs(max_y_force)) {
				force_vector.y = (real_t)(max_y_force * signf((double)force_vector.y));
				limit_spin = true;
			} else {
				limit_spin = false;
			}

			if (std::abs((double)force_vector.x) > max_x_force) {
				force_vector.x = (real_t)(max_x_force * signf((double)force_vector.x));
			}

			// Wheel.process_rolling_resistance(); (12) pressure_roll_mult
			const double speed_term = lvz * 0.036; // (15d)
			const double rolling_resistance_coefficient = 0.005 + (0.5 * (0.01 + (0.0095 * (speed_term * speed_term))));
			const double rolling = rolling_resistance_coefficient * spring_force * current_rolling_resistance * pressure_roll_mult;
			force_vector.y = (real_t)((double)force_vector.y - rolling * signf(lvz));

			// ---------- back in Wheel.process_forces() ----------
			// (15b) this wheel's forces as one force and one torque about the
			// car's centre of mass
			const Vector3 contact_arm = last_collision_point - center;
			Vector3 force;
			Vector3 torque;
			if (spring_force > 0.0) {
				force = last_collision_normal * (real_t)spring_force;
				torque = contact_arm.cross(force);
			} else {
				// Apply a small amount of downward force if there is no spring force
				force = -wheel_basis.get_column(1) * (real_t)vehicle_mass;
				torque = (wheel_origin - center).cross(force);
			}

			const Vector3 tire_force = wheel_basis.get_column(0) * force_vector.x + wheel_basis.get_column(2) * force_vector.y;
			force += tire_force;
			torque += contact_arm.cross(tire_force);

			// A torque on the body centred on the wheel: more weight transfer when
			// the centre of gravity is really low.
			if (braking) {
				wheel_to_body_torque_multiplier = 1.0 / (braking_grip_multiplier + 1.0);
			}
			// (15b) upstream's two equal and opposite forces, kept as their torque
			torque += wheel_basis.get_column(2).cross(wheel_basis.get_column(1)) * (real_t)(tire_radius * (double)force_vector.y * wheel_to_body_torque_multiplier);

			total_force += force;
			total_torque += torque;
			any_force = true;
			has_force = true;
			returned_compression = compression;
		} else {
			spin -= signf(spin) * delta * 2.0 / wheel_moment;
		}

		r[O_COMPRESSION] = returned_compression;
		r[O_COLLIDING] = colliding ? 1.0 : 0.0;
		r[O_HAS_FORCE] = has_force ? 1.0 : 0.0;
		r[O_SPIN] = spin;
		r[O_BODY_TORQUE_MULT] = wheel_to_body_torque_multiplier;
		write_v3(r + O_LOCAL_VELOCITY, local_velocity);
		write_v3(r + O_PREVIOUS_VELOCITY, previous_velocity);
		write_v3(r + O_PREVIOUS_POSITION, wheel_origin);
		r[O_PREVIOUS_COMPRESSION] = compression;
		r[O_MAX_SPRING_LENGTH] = max_spring_length;
		r[O_SPRING_CURRENT_LENGTH] = spring_current_length;
		r[O_SPRING_FORCE] = spring_force;
		r[O_ANTIROLL_FORCE] = antiroll_force;
		r[O_DAMPING_FORCE] = damping_force;
		r[O_FORCE_VECTOR] = force_vector.x;
		r[O_FORCE_VECTOR + 1] = force_vector.y;
		r[O_SLIP_VECTOR] = slip_vector.x;
		r[O_SLIP_VECTOR + 1] = slip_vector.y;
		r[O_SPIN_VELOCITY_DIFF] = spin_velocity_diff;
		r[O_LIMIT_SPIN] = limit_spin ? 1.0 : 0.0;
		write_v3(r + O_COLLISION_POINT, last_collision_point);
		write_v3(r + O_COLLISION_NORMAL, last_collision_normal);
	}

	o[OUT_ANY_FORCE] = any_force ? 1.0 : 0.0;
	write_v3(o + OUT_FORCE, total_force);
	write_v3(o + OUT_TORQUE, total_torque);
	o[7] = 0.0;
	return out;
}
