extends SceneTree

# Bolt-on row data (mod tree step B1): the JSON is well formed, applies to every
# player car, and every delta moves the number it names the way its notice says.
# No sim runs here; the worth sweep (tests/car/bolt_on_worth.gd) does those.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/car/bolt_ons.gd

var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	var items := BoltOns.items()
	_check(items.size() == 28, "26 items with the cabin strip stepped x3 is 28 entries, got %d" % items.size())
	var seen := {}
	var base_items := {}
	for it in items:
		_check(not seen.has(it.id), "duplicate id %s" % it.id)
		seen[it.id] = true
		base_items[String(it.get("step_of", it.id))] = true
		_check(String(it.get("label", "")) != "" and String(it.get("kind", "")) != "", "%s: label and kind are set" % it.id)
		_check(it.has("est_worth"), "%s: est_worth" % it.id)
		_check(not it.get("deltas", {}).is_empty() or not it.get("effects", {}).is_empty() or not it.get("driver", {}).is_empty(),
			"%s changes nothing" % it.id)
		for key in it.get("deltas", {}):
			var op: Array = it.deltas[key]
			_check(op.size() == 2 and String(op[0]) in ["mul", "add", "set"], "%s: bad op on %s" % [it.id, key])
	_check(base_items.size() == 26, "26 distinct items, got %d" % base_items.size())

	# Every item fits every player car, finite and without touching the input.
	for car in PlayerCars.ids():
		var spec := CarSpec.player_spec(car)
		var before := var_to_str(spec)
		var all := BoltOns.fit(spec, BoltOns.ids())
		_check(var_to_str(spec) == before, "%s: fit() changed the spec it was given" % car)
		for key in all:
			if all[key] is float:
				_check(is_finite(all[key]), "%s: %s not finite after every bolt-on" % [car, key])
		_check(float(all.vehicle_mass) < float(spec.vehicle_mass), "%s: mass items should lower vehicle_mass" % car)
		_check(float(all.max_torque) > float(spec.max_torque), "%s: torque items should raise max_torque" % car)

	# Each pace/control delta goes the way its notice says, on the Bug.
	var bug := CarSpec.player_spec("p0_beater")
	_check(float(BoltOns.fit(bug, ["short_shifter"]).shift_time) < float(bug.shift_time), "short shifter shortens shift_time")
	_check(float(BoltOns.fit(bug, ["throttle_body"]).throttle_speed) > float(bug.throttle_speed), "throttle body raises throttle_speed")
	_check(float(BoltOns.fit(bug, ["brake_pads"]).brake_force_multiplier) > float(bug.brake_force_multiplier), "pads raise brake force")
	_check(float(BoltOns.fit(bug, ["strut_bar_front"]).front_arb_ratio) > float(bug.front_arb_ratio), "front strut bar stiffens the front")
	_check(float(BoltOns.fit(bug, ["strut_bar_rear"]).rear_arb_ratio) > float(bug.rear_arb_ratio), "rear strut bar stiffens the rear")
	_check(float(BoltOns.fit(bug, ["underdrive_pulley"]).motor_moment) < 0.5, "underdrive pulley lowers motor_moment from the Vehicle default 0.5")
	_check(is_equal_approx(float(BoltOns.fit(bug, ["cabin_strip_3"]).vehicle_mass), float(bug.vehicle_mass) - 45.0), "cabin strip 3 is -45 kg")

	# Effects merge: multipliers multiply, flags or.
	var fx := BoltOns.effects(["quiet_muffler", "straight_pipe", "ecu_unlock"])
	_check(is_equal_approx(float(fx.noise_heat_mul), 0.85 * 1.15), "noise_heat_mul multiplies")
	_check(bool(fx.crackle), "crackle flag carried")

	# Order does not matter.
	var a := BoltOns.fit(bug, ["ecu_unlock", "light_battery", "brake_pads"])
	var b := BoltOns.fit(bug, ["brake_pads", "ecu_unlock", "light_battery"])
	_check(is_equal_approx(float(a.max_torque), float(b.max_torque)) and is_equal_approx(float(a.vehicle_mass), float(b.vehicle_mass))
		and is_equal_approx(float(a.brake_force_multiplier), float(b.brake_force_multiplier)), "order of fitting does not matter")

	if failures.is_empty():
		print("bolt_ons: PASS (%d entries, %d items)" % [items.size(), base_items.size()])
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
