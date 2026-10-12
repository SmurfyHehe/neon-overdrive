extends Wheel

# A Wheel that can hand its numbers to CarSim (C++, native/neon_sim) and take
# the results back. It is still the vendored wheel in every other way, and it
# still owns every number: CarSim keeps none of them between ticks, so damage,
# tyre wear, the tuner and the world recentring write to it as before.
# No class_name on purpose: made by path, only by CarSimSwitch.new_wheel().
#
# The slot numbers are CarSim's W_* and O_* (native/neon_sim/src/car_sim.h).
# Keep the three in step.

const W_IN := 44
const W_OUT := 32

func sim_pack(b: PackedFloat64Array, i: int) -> void:
	b[i] = wheel_mass
	b[i + 1] = tire_radius
	b[i + 2] = tire_width
	b[i + 3] = contact_patch
	b[i + 4] = braking_grip_multiplier
	b[i + 5] = spring_length
	b[i + 6] = spring_rate
	b[i + 7] = slow_bump
	b[i + 8] = fast_bump
	b[i + 9] = slow_rebound
	b[i + 10] = fast_rebound
	b[i + 11] = fast_damp_threshold
	b[i + 12] = antiroll
	b[i + 13] = bump_stop_multiplier
	b[i + 14] = wheel_to_body_torque_multiplier
	b[i + 15] = mass_over_wheel
	b[i + 16] = wheel_moment
	b[i + 17] = spin
	b[i + 18] = applied_torque
	b[i + 19] = local_velocity.x
	b[i + 20] = local_velocity.y
	b[i + 21] = local_velocity.z
	b[i + 22] = previous_global_position.x
	b[i + 23] = previous_global_position.y
	b[i + 24] = previous_global_position.z
	b[i + 25] = previous_compression
	b[i + 26] = max_spring_length
	b[i + 27] = current_cof
	b[i + 28] = grip_mult
	b[i + 29] = current_rolling_resistance
	b[i + 30] = pressure_stiffness_mult
	b[i + 31] = pressure_grip_mult
	b[i + 32] = pressure_roll_mult
	b[i + 33] = static_camber
	b[i + 34] = static_camber_stock
	b[i + 35] = camber_side
	b[i + 36] = camber_long_mult
	b[i + 37] = 1.0 if camber_active else 0.0
	b[i + 38] = current_lateral_grip_assist
	b[i + 39] = current_longitudinal_grip_ratio
	b[i + 40] = current_tire_stiffness
	b[i + 41] = 0.0 if _surface_collider_id == 0 else 1.0
	b[i + 42] = spin_velocity_diff
	b[i + 43] = 1.0 if limit_spin else 0.0

## Returns what Wheel.process_forces() returns (the compression, 0 off the ground).
func sim_unpack(o: PackedFloat64Array, i: int) -> float:
	var colliding := o[i + 1] != 0.0
	_tick_colliding = colliding
	tick_has_force = o[i + 2] != 0.0
	spin = o[i + 3]
	wheel_to_body_torque_multiplier = o[i + 4]
	local_velocity = Vector3(o[i + 5], o[i + 6], o[i + 7])
	previous_velocity = Vector3(o[i + 8], o[i + 9], o[i + 10])
	previous_global_position = Vector3(o[i + 11], o[i + 12], o[i + 13])
	previous_compression = o[i + 14]
	max_spring_length = o[i + 15]
	spring_current_length = o[i + 16]
	spring_force = o[i + 17]
	antiroll_force = o[i + 18]
	damping_force = o[i + 19]
	force_vector = Vector2(o[i + 20], o[i + 21])
	slip_vector = Vector2(o[i + 22], o[i + 23])
	spin_velocity_diff = o[i + 24]
	limit_spin = o[i + 25] != 0.0
	if colliding:
		last_collider = get_collider()
		last_collision_point = Vector3(o[i + 26], o[i + 27], o[i + 28])
		last_collision_normal = Vector3(o[i + 29], o[i + 30], o[i + 31])
		_surface_collider_id = 1  # CarSim remembers the collider; 0 here tells it to forget
	else:
		last_collider = null
	return o[i]

## CarSim calls this when the wheel meets a collider it has not read the
## surface of. Same as the surface branch of Wheel.process_forces(): switch if
## it is a different surface and hand back the five numbers, else nothing.
func sim_surface(surface: StringName) -> PackedFloat64Array:
	if surface_type == surface:
		return PackedFloat64Array()
	surface_type = surface
	current_cof = coefficient_of_friction[surface_type]
	current_rolling_resistance = rolling_resistance[surface_type]
	current_lateral_grip_assist = lateral_grip_assist[surface_type]
	current_longitudinal_grip_ratio = longitudinal_grip_ratio[surface_type]
	current_tire_stiffness = 1000000.0 + 8000000.0 * tire_stiffnesses[surface_type]
	return PackedFloat64Array([current_cof, current_rolling_resistance,
			current_lateral_grip_assist, current_longitudinal_grip_ratio, current_tire_stiffness])
