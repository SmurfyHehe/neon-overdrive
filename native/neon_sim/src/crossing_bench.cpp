#include "crossing_bench.h"

#include <godot_cpp/classes/physics_direct_body_state3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <chrono>

using namespace godot;

namespace {
inline int64_t now_ns() {
	return std::chrono::duration_cast<std::chrono::nanoseconds>(
			std::chrono::steady_clock::now().time_since_epoch())
			.count();
}
} // namespace

void CrossingBench::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_cars", "bodies", "wheels"), &CrossingBench::set_cars);
	ClassDB::bind_method(D_METHOD("get_car_count"), &CrossingBench::get_car_count);
	ClassDB::bind_method(D_METHOD("set_enabled", "enabled"), &CrossingBench::set_enabled);
	ClassDB::bind_method(D_METHOD("get_enabled"), &CrossingBench::get_enabled);
	ClassDB::bind_method(D_METHOD("set_ray_mode", "mode"), &CrossingBench::set_ray_mode);
	ClassDB::bind_method(D_METHOD("get_ray_mode"), &CrossingBench::get_ray_mode);
	ClassDB::bind_method(D_METHOD("set_state_mode", "mode"), &CrossingBench::set_state_mode);
	ClassDB::bind_method(D_METHOD("get_state_mode"), &CrossingBench::get_state_mode);
	ClassDB::bind_method(D_METHOD("reset_stats"), &CrossingBench::reset_stats);
	ClassDB::bind_method(D_METHOD("get_stats"), &CrossingBench::get_stats);
	ClassDB::bind_method(D_METHOD("calibrate_clock", "reads"), &CrossingBench::calibrate_clock);
}

void CrossingBench::_ready() {
	set_physics_process(true);
}

void CrossingBench::set_cars(const Array &bodies, const Array &wheels) {
	cars.clear();
	params.instantiate();
	for (int i = 0; i < bodies.size(); i++) {
		Object *body_obj = bodies[i];
		RigidBody3D *body = Object::cast_to<RigidBody3D>(body_obj);
		if (body == nullptr || !body->is_inside_tree() || wheels.size() < (i + 1) * 4) {
			continue;
		}
		CarRef car;
		car.id = body->get_instance_id();
		car.rid = body->get_rid();
		car.exclude.push_back(car.rid);
		if (!space.is_valid()) {
			Ref<World3D> world = body->get_world_3d();
			if (world.is_valid()) {
				space = world->get_space();
			}
		}
		Transform3D inv = body->get_global_transform().affine_inverse();
		bool ok = true;
		for (int j = 0; j < 4; j++) {
			Object *wheel_obj = wheels[i * 4 + j];
			RayCast3D *w = Object::cast_to<RayCast3D>(wheel_obj);
			if (w == nullptr) {
				ok = false;
				break;
			}
			car.wheels[j].node = w;
			Transform3D wt = w->get_global_transform();
			car.wheels[j].local_from = inv.xform(wt.origin);
			car.wheels[j].local_to = inv.xform(wt.xform(w->get_target_position()));
		}
		if (ok) {
			cars.push_back(car);
		}
	}
}

void CrossingBench::reset_stats() {
	steps = car_steps = total_ns = resolve_ns = state_ns = rays_ns = force_ns = ray_count = hits = 0;
}

Dictionary CrossingBench::get_stats() const {
	Dictionary d;
	d["steps"] = steps;
	d["car_steps"] = car_steps;
	d["total_ns"] = total_ns;
	d["resolve_ns"] = resolve_ns;
	d["state_ns"] = state_ns;
	d["rays_ns"] = rays_ns;
	d["force_ns"] = force_ns;
	d["rays"] = ray_count;
	d["hits"] = hits;
	d["sink"] = sink;
	return d;
}

double CrossingBench::calibrate_clock(int p_reads) {
	int64_t t0 = now_ns();
	int64_t acc = 0;
	for (int i = 0; i < p_reads; i++) {
		acc += now_ns() & 1;
	}
	int64_t t1 = now_ns();
	sink += (double)acc * 1e-30;
	return p_reads > 0 ? (double)(t1 - t0) / (double)p_reads : 0.0;
}

void CrossingBench::_physics_process(double p_delta) {
	if (!enabled || cars.empty()) {
		return;
	}
	PhysicsServer3D *ps = PhysicsServer3D::get_singleton();
	PhysicsDirectSpaceState3D *ds = nullptr;
	if (ray_mode == 0) {
		ds = ps->space_get_direct_state(space);
		if (ds == nullptr) {
			return;
		}
	}
	const int64_t t_start = now_ns();
	int64_t s_resolve = 0, s_state = 0, s_rays = 0, s_force = 0, n_car = 0, n_ray = 0, n_hit = 0;
	double acc = 0.0;

	for (const CarRef &car : cars) {
		const int64_t c0 = now_ns();
		Object *obj = UtilityFunctions::instance_from_id((int64_t)car.id);
		if (obj == nullptr) {
			continue;
		}
		const int64_t c1 = now_ns();

		Transform3D xf;
		Vector3 lv, av;
		if (state_mode == 0) {
			PhysicsDirectBodyState3D *st = ps->body_get_direct_state(car.rid);
			if (st == nullptr) {
				continue;
			}
			xf = st->get_transform();
			lv = st->get_linear_velocity();
			av = st->get_angular_velocity();
		} else {
			xf = ps->body_get_state(car.rid, PhysicsServer3D::BODY_STATE_TRANSFORM);
			lv = ps->body_get_state(car.rid, PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY);
			av = ps->body_get_state(car.rid, PhysicsServer3D::BODY_STATE_ANGULAR_VELOCITY);
		}
		acc += xf.origin.y + lv.x + av.y;
		const int64_t c2 = now_ns();

		if (ray_mode == 0) {
			params->set_exclude(car.exclude);
			for (int j = 0; j < 4; j++) {
				params->set_from(xf.xform(car.wheels[j].local_from));
				params->set_to(xf.xform(car.wheels[j].local_to));
				Dictionary hit = ds->intersect_ray(params);
				n_ray++;
				if (!hit.is_empty()) {
					n_hit++;
					Vector3 p = hit["position"];
					Vector3 n = hit["normal"];
					acc += p.y + n.y;
				}
			}
		} else {
			for (int j = 0; j < 4; j++) {
				RayCast3D *w = car.wheels[j].node;
				w->force_raycast_update();
				n_ray++;
				if (w->is_colliding()) {
					n_hit++;
					Vector3 p = w->get_collision_point();
					Vector3 n = w->get_collision_normal();
					acc += p.y + n.y;
				}
			}
		}
		const int64_t c3 = now_ns();

		ps->body_apply_central_force(car.rid, Vector3(0.001, 0.0, 0.0));
		ps->body_apply_torque(car.rid, Vector3(0.0, 0.001, 0.0));
		const int64_t c4 = now_ns();

		s_resolve += c1 - c0;
		s_state += c2 - c1;
		s_rays += c3 - c2;
		s_force += c4 - c3;
		n_car++;
	}

	const int64_t t_end = now_ns();
	steps++;
	car_steps += n_car;
	total_ns += t_end - t_start;
	resolve_ns += s_resolve;
	state_ns += s_state;
	rays_ns += s_rays;
	force_ns += s_force;
	ray_count += n_ray;
	hits += n_hit;
	sink += acc * 1e-30;
}
