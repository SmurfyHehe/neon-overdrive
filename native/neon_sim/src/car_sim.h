// The per-wheel maths in this file and car_sim.cpp is a port of
// scripts/vendor/gevp/gevp_wheel.gd (GEVP, Godot Easy Vehicle Physics), which is
// under the MIT licence:
//
//   Copyright (c) 2024 David Shoemaker
//   Copyright (c) 2021 Dechode
//   Copyright (c) 2024 Baron Wittman
//
// The full licence text is in scripts/vendor/gevp/LICENSE.txt and ships in
// THIRD_PARTY_NOTICES.txt.
#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/string_name.hpp>

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace godot {

// Car physics in C++, step 1 (2026-10-11): the per-wheel half of a GEVP tick.
// One step_wheels() call per car per tick does what Vehicle.process_forces()
// does with four Wheel.process_forces() calls in the script: ray cast, surface
// lookup, suspension, tyres, and the four wheels' pushes summed to one force
// and one torque about the car's centre of mass.
//
// The script stays the reference and the fallback. The Wheel nodes stay, and
// stay the owner of every number: the caller (scripts/car/car_sim_bridge.gd)
// packs each wheel's settings and state into `inputs` every tick and writes
// the results back, so anything else that reads or writes a Wheel (damage,
// tyre wear, the tuner, the world recentring) keeps working unchanged. The
// only state kept here is which collider each wheel last read its surface
// from (gevp_wheel.gd deviation 15a).
//
// Number types follow the script exactly: GDScript floats are 64-bit, Vector2 /
// Vector3 / Basis components are 32-bit, so doubles and godot::Vector3 are used
// in the same places and results stay equal tick for tick.
class CarSim : public Node {
	GDCLASS(CarSim, Node)

public:
	// Layout of `inputs` (doubles). Keep in step with car_sim_bridge.gd and
	// car_sim_wheel.gd.
	enum {
		IN_DELTA = 0,
		IN_BRAKING = 1,
		IN_MASS = 2,
		IN_CENTER = 3, // x y z: the car's centre of mass, world space
		IN_GRAVITY = 6, // x y z
		IN_LOAD_SENSITIVITY = 9,
		IN_BODY_TILT_DEG = 10,
		IN_SURFACE_EPOCH = 11,
		IN_COMPRESSION = 12, // last tick's compression, one per wheel
		IN_HEADER = 16,

		W_WHEEL_MASS = 0,
		W_TIRE_RADIUS = 1,
		W_TIRE_WIDTH = 2,
		W_CONTACT_PATCH = 3,
		W_BRAKING_GRIP_MULT = 4,
		W_SPRING_LENGTH = 5,
		W_SPRING_RATE = 6,
		W_SLOW_BUMP = 7,
		W_FAST_BUMP = 8,
		W_SLOW_REBOUND = 9,
		W_FAST_REBOUND = 10,
		W_FAST_DAMP_THRESHOLD = 11,
		W_ANTIROLL = 12,
		W_BUMP_STOP_MULT = 13,
		W_BODY_TORQUE_MULT = 14,
		W_MASS_OVER_WHEEL = 15,
		W_WHEEL_MOMENT = 16,
		W_SPIN = 17,
		W_APPLIED_TORQUE = 18,
		W_LOCAL_VELOCITY = 19, // x y z
		W_PREVIOUS_POSITION = 22, // x y z
		W_PREVIOUS_COMPRESSION = 25,
		W_MAX_SPRING_LENGTH = 26,
		W_COF = 27,
		W_GRIP_MULT = 28,
		W_ROLLING_RESISTANCE = 29,
		W_PRESSURE_STIFFNESS_MULT = 30,
		W_PRESSURE_GRIP_MULT = 31,
		W_PRESSURE_ROLL_MULT = 32,
		W_STATIC_CAMBER = 33,
		W_STATIC_CAMBER_STOCK = 34,
		W_CAMBER_SIDE = 35,
		W_CAMBER_LONG_MULT = 36,
		W_CAMBER_ACTIVE = 37,
		W_LATERAL_GRIP_ASSIST = 38,
		W_LONGITUDINAL_GRIP_RATIO = 39,
		W_TIRE_STIFFNESS = 40,
		W_SURFACE_KNOWN = 41, // 0 = forget the collider the surface was read from
		W_SPIN_VELOCITY_DIFF = 42,
		W_LIMIT_SPIN = 43,
		W_IN = 44,

		// Layout of the returned array.
		OUT_ANY_FORCE = 0,
		OUT_FORCE = 1, // x y z
		OUT_TORQUE = 4, // x y z
		OUT_HEADER = 8,

		O_COMPRESSION = 0, // what Wheel.process_forces() returns
		O_COLLIDING = 1,
		O_HAS_FORCE = 2,
		O_SPIN = 3,
		O_BODY_TORQUE_MULT = 4,
		O_LOCAL_VELOCITY = 5, // x y z
		O_PREVIOUS_VELOCITY = 8, // x y z
		O_PREVIOUS_POSITION = 11, // x y z
		O_PREVIOUS_COMPRESSION = 14,
		O_MAX_SPRING_LENGTH = 15,
		O_SPRING_CURRENT_LENGTH = 16,
		O_SPRING_FORCE = 17,
		O_ANTIROLL_FORCE = 18,
		O_DAMPING_FORCE = 19,
		O_FORCE_VECTOR = 20, // x y
		O_SLIP_VECTOR = 22, // x y
		O_SPIN_VELOCITY_DIFF = 24,
		O_LIMIT_SPIN = 25,
		O_COLLISION_POINT = 26, // x y z, only written while colliding
		O_COLLISION_NORMAL = 29, // x y z, only written while colliding
		W_OUT = 32,

		WHEELS = 4,
	};

private:
	struct Car {
		bool used = false;
		uint64_t wheel_id[WHEELS] = {};
		uint64_t surface_collider[WHEELS] = {};
		int64_t surface_epoch[WHEELS] = { -1, -1, -1, -1 };
	};

	std::vector<Car> cars;
	std::vector<int> free_ids;
	PackedFloat64Array out;

	// Collider id -> index into surface_names, or -1 for "no groups".
	std::unordered_map<uint64_t, int> surface_of;
	std::vector<StringName> surface_names;
	int64_t table_epoch = -1;
	StringName sim_surface_method;

	int surface_index(const StringName &p_name);

protected:
	static void _bind_methods();

public:
	CarSim();

	// `wheels`: the car's four Wheel nodes in the order the script steps them
	// (each axle's left wheel, then its right). Returns the car's id.
	int add_car(const Array &p_wheels);
	void remove_car(int p_car_id);
	int get_car_count() const;

	// Tells the sim which surface a ground collider is, so the first wheel to
	// touch it does not have to ask for its groups.
	void set_surface(uint64_t p_collider_id, const StringName &p_surface);
	int get_surface_count() const;

	// Empty result = the car could not be stepped (unknown id, a wheel is gone,
	// wrong input size): the caller runs the script wheels instead.
	PackedFloat64Array step_wheels(int p_car_id, const PackedFloat64Array &p_inputs);

	int get_input_size() const { return IN_HEADER + WHEELS * W_IN; }
	int get_output_size() const { return OUT_HEADER + WHEELS * W_OUT; }
};

} // namespace godot
