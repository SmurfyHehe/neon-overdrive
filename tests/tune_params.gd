extends SceneTree

# Tune write path test (Auto-Tune step 1a): checks that CarSpec.set_param() keeps
# the spec and the live car in step, and that doing it live gives the same car
# as building one fresh from the spec.
# - every base value of the default spec sits inside its registry range
# - the car owns its arrays/dictionaries (no aliasing with the spec)
# - gear_ratios stays Array[float] after writes (the silent-assignment bug)
# - every registered path (v1 Auto-Tune ones and the raw-only engine ones): spec
#   value == car value == the clamped request; the torque shape turns into the
#   car's torque curve and max_torque into max_clutch_torque
# - Auto-Tune gets exactly the 14 v1 paths, none of them engine
# - values outside the range are clamped; an unknown path is refused
# - a car tuned live matches a car built from the same spec: gearing, the
#   wheels' cached tire numbers, brake force
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/tune_params.gd

var failures: Array[String] = []

func _initialize() -> void:
	_check_defaults_in_range()

	var live := PlayerCar.new()
	root.add_child(live)
	await process_frame  # add_child from _initialize defers _ready() to the first frame
	_check_ownership(live)

	# A value inside each range, different from the base so a missed write shows.
	for e in TuneParams.all():
		var target: float = lerpf(e.min, e.max, 0.7)
		var stored := CarSpec.set_param(live, live.spec, e.path, target)
		_check(is_equal_approx(stored, target), "%s: stored %f, wanted %f" % [e.path, stored, target])
		_check(is_equal_approx(TuneParams.get_value(live.spec, e.path), target), "%s: spec not written" % e.path)
		if e.on_car:
			_check(is_equal_approx(TuneParams.get_value(live, e.path), target), "%s: car not written" % e.path)
	_check(live.gear_ratios.is_typed(), "live gear_ratios lost its type")
	_check(live.spec.gear_ratios.is_typed(), "spec gear_ratios lost its type")
	_check(live.gear_ratios.size() == 5, "gear count changed")

	_check(live.max_clutch_torque == live.max_torque * live.max_clutch_torque_ratio, "max_clutch_torque not re-derived")
	var shaped := CarSpec.build_torque_curve(live.spec.torque_shape.low_end, live.spec.torque_shape.peak_pos, live.spec.torque_shape.plateau, live.spec.torque_shape.falloff)
	for x in [0.0, 0.2, 0.5, 0.8, 1.0]:
		_check(is_equal_approx(live.torque_curve.sample_baked(x), shaped.sample_baked(x)), "torque curve does not follow the spec's shape at %f" % x)
	var auto := TuneParams.auto_paths()
	_check(auto.size() == 14, "Auto-Tune should have 14 paths, has %d" % auto.size())
	for path in auto:
		_check(not path.begins_with("torque_shape") and path != "max_torque" and path != "max_rpm", "engine path %s should not be Auto-Tune" % path)

	# Clamping.
	var hi := CarSpec.set_param(live, live.spec, "final_drive", 99.0)
	_check(is_equal_approx(hi, 5.5) and is_equal_approx(live.final_drive, 5.5), "final_drive not clamped high")
	var lo := CarSpec.set_param(live, live.spec, "coefficient_of_friction/Road", -1.0)
	_check(is_equal_approx(lo, 2.0) and is_equal_approx(live.coefficient_of_friction["Road"], 2.0), "friction not clamped low")
	CarSpec.set_param(live, live.spec, "final_drive", lerpf(2.5, 5.5, 0.7))
	CarSpec.set_param(live, live.spec, "coefficient_of_friction/Road", lerpf(2.0, 4.0, 0.7))
	_check(TuneParams.find("engine_power").is_empty(), "unknown path should not be in the registry")

	# Live-tuned car vs a car built fresh from the same spec.
	var fresh := PlayerCar.new()
	fresh.spec = CarSpec.clone_spec(live.spec)
	root.add_child(fresh)
	await process_frame
	_check_same_car(live, fresh)

	for f in failures:
		printerr("FAIL: ", f)
	print("tune_params: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check_defaults_in_range() -> void:
	var spec := CarSpec.coupe_default()
	for e in TuneParams.all():
		var v := TuneParams.get_value(spec, e.path)
		_check(v >= e.min and v <= e.max, "%s: default %f outside [%f, %f]" % [e.path, v, e.min, e.max])

func _check_ownership(car: PlayerCar) -> void:
	_check(car.gear_ratios.is_typed(), "gear_ratios not typed after apply")
	_check(car.gear_ratios == car.spec.gear_ratios, "gear_ratios differ from the spec")
	_check(not is_same(car.gear_ratios, car.spec.gear_ratios), "gear_ratios aliased with the spec")
	for key in ["tire_stiffnesses", "coefficient_of_friction", "lateral_grip_assist", "longitudinal_grip_ratio"]:
		_check(not is_same(car.get(key), car.spec[key]), "%s aliased with the spec" % key)
	for w in car.wheel_array:
		_check(is_same(w.coefficient_of_friction, car.coefficient_of_friction), "wheel should share the car's friction table")

func _check_same_car(a: PlayerCar, b: PlayerCar) -> void:
	_check(a.gear_ratios == b.gear_ratios, "gear_ratios differ")
	for g in range(1, 6):
		_check(is_equal_approx(a.get_gear_ratio(g), b.get_gear_ratio(g)), "overall ratio differs in gear %d" % g)
	for i in a.wheel_array.size():
		var wa: Wheel = a.wheel_array[i]
		var wb: Wheel = b.wheel_array[i]
		_check(is_equal_approx(wa.current_cof, wb.current_cof), "wheel %d current_cof %f vs %f" % [i, wa.current_cof, wb.current_cof])
		_check(is_equal_approx(wa.current_tire_stiffness, wb.current_tire_stiffness), "wheel %d tire stiffness differs" % i)
		_check(is_equal_approx(wa.current_lateral_grip_assist, wb.current_lateral_grip_assist), "wheel %d lateral assist differs" % i)
		_check(is_equal_approx(wa.current_longitudinal_grip_ratio, wb.current_longitudinal_grip_ratio), "wheel %d longitudinal ratio differs" % i)
	_check(is_equal_approx(a.max_torque, b.max_torque) and is_equal_approx(a.max_rpm, b.max_rpm), "engine scalars differ")
	_check(is_equal_approx(a.max_clutch_torque, b.max_clutch_torque), "max_clutch_torque differs")
	for x in [0.0, 0.1, 0.3, 0.5, 0.7, 0.9, 1.0]:
		_check(is_equal_approx(a.torque_curve.sample_baked(x), b.torque_curve.sample_baked(x)), "torque curve differs at %f" % x)
	_check(is_equal_approx(a.max_brake_force, b.max_brake_force), "max_brake_force %f vs %f" % [a.max_brake_force, b.max_brake_force])
	_check(is_equal_approx(a.max_handbrake_force, b.max_handbrake_force), "max_handbrake_force differs")
	_check(is_equal_approx(a.coefficient_of_drag, b.coefficient_of_drag), "drag differs")
	_check(is_equal_approx(a.aero_downforce_coefficient_rear, b.aero_downforce_coefficient_rear), "downforce differs")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
