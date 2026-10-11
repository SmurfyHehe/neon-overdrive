#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/ray_cast3d.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <vector>

namespace godot {

// Measurement only (2026-10-11, task B1): what the physics engine calls a
// native car sim would make cost per car per tick, with no sim maths at all.
// Each physics tick, per car, it does what a ported sim has to do:
//   1. check the body is still alive (instance_from_id),
//   2. read body state (transform, linear and angular velocity),
//   3. cast 4 wheel rays,
//   4. apply one central force and one torque (0.001 N / N*m, harmless).
// Every section is timed with the steady clock (ns); get_stats() returns the
// sums since the last reset_stats(). The GDScript runner
// (tools/crossing_bench.gd) switches the modes between phases.
//
//   state_mode  0 = PhysicsServer3D.body_get_direct_state() getters
//               1 = PhysicsServer3D.body_get_state() x3 (Variant returns)
//   ray_mode    0 = space direct state intersect_ray(), parameters object reused
//               1 = the wheels' own RayCast3D nodes: force_raycast_update(),
//                   is_colliding(), get_collision_point(), get_collision_normal()
class CrossingBench : public Node {
	GDCLASS(CrossingBench, Node)

	struct WheelRay {
		RayCast3D *node = nullptr; // child of the car, valid while the car is
		Vector3 local_from;
		Vector3 local_to;
	};
	struct CarRef {
		uint64_t id = 0;
		RID rid;
		TypedArray<RID> exclude; // the car's own body RID, for intersect_ray
		WheelRay wheels[4];
	};

	std::vector<CarRef> cars;
	RID space;
	Ref<PhysicsRayQueryParameters3D> params;
	bool enabled = false;
	int ray_mode = 0;
	int state_mode = 0;

	int64_t steps = 0;
	int64_t car_steps = 0;
	int64_t total_ns = 0;
	int64_t resolve_ns = 0;
	int64_t state_ns = 0;
	int64_t rays_ns = 0;
	int64_t force_ns = 0;
	int64_t ray_count = 0;
	int64_t hits = 0;
	double sink = 0.0; // keeps the reads from being optimised away

protected:
	static void _bind_methods();

public:
	// bodies: the full-sim car RigidBody3D nodes. wheels: 4 RayCast3D per car,
	// flattened in the same order.
	void set_cars(const Array &bodies, const Array &wheels);
	int get_car_count() const { return (int)cars.size(); }
	void set_enabled(bool p_enabled) { enabled = p_enabled; }
	bool get_enabled() const { return enabled; }
	void set_ray_mode(int p_mode) { ray_mode = p_mode; }
	int get_ray_mode() const { return ray_mode; }
	void set_state_mode(int p_mode) { state_mode = p_mode; }
	int get_state_mode() const { return state_mode; }
	void reset_stats();
	Dictionary get_stats() const;
	// ns for one steady_clock read, so the section sums can be corrected.
	double calibrate_clock(int p_reads);

	void _ready() override;
	void _physics_process(double p_delta) override;
};

} // namespace godot
