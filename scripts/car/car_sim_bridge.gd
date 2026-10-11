extends RefCounted

# One car's link to CarSim (C++, native/neon_sim): Vehicle.process_forces()
# hands the tick to step() when the car has one (gevp_vehicle.gd deviation 16).
# step() packs the car's and the four wheels' numbers, makes the one native
# call, writes the results back to the wheels and applies the car's total force
# and torque, exactly where the script applies them.
# No class_name on purpose: this file names CarSim, so it only parses when the
# library is loaded. Made by path, only by CarSimSwitch.attach().
#
# The slot numbers are CarSim's IN_* and OUT_* (native/neon_sim/src/car_sim.h).

const SimWheel := preload("res://scripts/car/car_sim_wheel.gd")

const IN_HEADER := 16
const OUT_HEADER := 8
const W_IN := SimWheel.W_IN
const W_OUT := SimWheel.W_OUT

var _sim: CarSim = null
var _id := -1
var _buf := PackedFloat64Array()
var _w0: SimWheel
var _w1: SimWheel
var _w2: SimWheel
var _w3: SimWheel
## Set when CarSim refuses the car (a wheel was swapped or freed): the car runs
## the script wheels from then on.
var _failed := false
## Ticks stepped by CarSim so far (tools/sim_golden.gd checks the C++ really ran).
var native_ticks := 0

func _register(v: Vehicle) -> bool:
	_sim = CarSimSwitch.sim() as CarSim
	if _sim == null:
		return false
	# The order Vehicle.process_forces() steps them in: each axle's left, then right.
	var wheels: Array = []
	for axle in v.axles:
		wheels.append(axle.wheels[0])
		wheels.append(axle.wheels[1])
	if wheels.size() != 4:
		return false
	for w in wheels:
		if not (w is SimWheel):
			return false
	_id = _sim.add_car(wheels)
	if _id < 0:
		return false
	_w0 = wheels[0]
	_w1 = wheels[1]
	_w2 = wheels[2]
	_w3 = wheels[3]
	_buf.resize(IN_HEADER + 4 * W_IN)
	if _sim.get_input_size() != _buf.size() or _sim.get_output_size() != OUT_HEADER + 4 * W_OUT:
		push_warning("CarSim and car_sim_bridge.gd disagree on the layout (stale library?): this car uses the GDScript physics.")
		_sim.remove_car(_id)
		_id = -1
		return false
	return true

## True when the wheels were stepped natively; false tells the vehicle to run
## its own process_forces().
func step(v: Vehicle, delta: float) -> bool:
	if _failed:
		return false
	if _id < 0 and not _register(v):
		_failed = true
		return false
	var front: Vehicle.Axle = v.axles[0]
	var rear: Vehicle.Axle = v.axles[1]
	var b := _buf
	b[0] = delta
	b[1] = 1.0 if v.is_braking else 0.0
	b[2] = v.mass
	var c := v.tick_center_of_mass
	b[3] = c.x
	b[4] = c.y
	b[5] = c.z
	var g := v.current_gravity
	b[6] = g.x
	b[7] = g.y
	b[8] = g.z
	b[9] = v.tyre_load_sensitivity
	b[10] = v.body_tilt_deg
	b[11] = Wheel.surface_epoch
	b[12] = front.suspension_compression_left
	b[13] = front.suspension_compression_right
	b[14] = rear.suspension_compression_left
	b[15] = rear.suspension_compression_right
	_w0.sim_pack(b, IN_HEADER)
	_w1.sim_pack(b, IN_HEADER + W_IN)
	_w2.sim_pack(b, IN_HEADER + 2 * W_IN)
	_w3.sim_pack(b, IN_HEADER + 3 * W_IN)
	_buf = b

	var o := _sim.step_wheels(_id, b)
	if o.is_empty():
		_failed = true
		_sim.remove_car(_id)
		_id = -1
		return false

	front.suspension_compression_left = _w0.sim_unpack(o, OUT_HEADER)
	front.suspension_compression_right = _w1.sim_unpack(o, OUT_HEADER + W_OUT)
	rear.suspension_compression_left = _w2.sim_unpack(o, OUT_HEADER + 2 * W_OUT)
	rear.suspension_compression_right = _w3.sim_unpack(o, OUT_HEADER + 3 * W_OUT)
	native_ticks += 1
	if o[0] != 0.0:
		v.apply_central_force(Vector3(o[1], o[2], o[3]))
		v.apply_torque(Vector3(o[4], o[5], o[6]))
	return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _id >= 0 and is_instance_valid(_sim):
		_sim.remove_car(_id)
