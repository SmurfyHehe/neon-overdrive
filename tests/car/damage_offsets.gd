extends SceneTree

# Damage offsets array (brief DP0, 2026-10-11): the 43-float layout, neutral
# values, the helpers, and that CarDamage builds into it. No car, no road.
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/car/damage_offsets.gd

const DamageOffsets := preload("res://scripts/car/damage_offsets.gd")

var failures: Array[String] = []

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("  FAIL: " + what)

func _initialize() -> void:
	var o := DamageOffsets.new()
	_check(o.data.size() == 43 and DamageOffsets.SIZE == 43, "43 floats (%d)" % o.data.size())
	_check(DamageOffsets.WHEELS * DamageOffsets.WHEEL_FIELDS + 7 == 43, "4 wheels x 9 + 7 per car")
	_check(o.is_neutral(), "a new array is neutral")
	# neutral values by field: mults 1, adds 0
	var one := [DamageOffsets.SPRING_MULT, DamageOffsets.DAMPER_MULT, DamageOffsets.PRESSURE_MULT,
		DamageOffsets.GRIP_MULT, DamageOffsets.BRAKE_MULT]
	var zero := [DamageOffsets.TOE_ADD, DamageOffsets.CAMBER_ADD, DamageOffsets.RIDE_DROP, DamageOffsets.RUNOUT]
	for w in 4:
		for f in one:
			_check(o.get_wheel(w, f) == 1.0, "wheel %d field %d neutral is 1" % [w, f])
		for f in zero:
			_check(o.get_wheel(w, f) == 0.0, "wheel %d field %d neutral is 0" % [w, f])
	for c in [DamageOffsets.STEER_LOCK_MULT, DamageOffsets.COOLING_MULT, DamageOffsets.TORQUE_MULT,
			DamageOffsets.BOOST_MULT, DamageOffsets.DOWNFORCE_REAR_MULT]:
		_check(o.get_car(c) == 1.0, "car index %d neutral is 1" % c)
	for c in [DamageOffsets.STEER_CENTRE, DamageOffsets.DRAG_ADD]:
		_check(o.get_car(c) == 0.0, "car index %d neutral is 0" % c)
	# the indices are all different and in range
	var seen := {}
	for w in 4:
		for f in DamageOffsets.WHEEL_FIELDS:
			seen[w * DamageOffsets.WHEEL_FIELDS + f] = true
	for c in range(DamageOffsets.CAR_BASE, DamageOffsets.SIZE):
		seen[c] = true
	_check(seen.size() == 43, "every index is used once (%d)" % seen.size())
	# set / get touch one slot only
	o.set_wheel(2, DamageOffsets.SPRING_MULT, 0.7)
	_check(is_equal_approx(o.get_wheel(2, DamageOffsets.SPRING_MULT), 0.7), "set_wheel / get_wheel round trip")
	_check(o.get_wheel(3, DamageOffsets.SPRING_MULT) == 1.0 and o.get_wheel(2, DamageOffsets.TOE_ADD) == 0.0, "the neighbours are untouched")
	_check(not o.is_neutral(), "one changed slot is not neutral")
	o.neutral()
	_check(o.is_neutral(), "neutral() puts everything back")
	o.set_wheel(0, DamageOffsets.TOE_ADD, 0.003)
	_check(not o.is_neutral(), "an add of 0.003 is not neutral")
	o.neutral()
	o.set_car(DamageOffsets.COOLING_MULT, 0.5)
	_check(is_equal_approx(o.get_car(DamageOffsets.COOLING_MULT), 0.5) and not o.is_neutral(), "set_car / get_car")
	o.neutral()
	o.set_wheel(1, DamageOffsets.RUNOUT, 0.001)
	_check(not o.is_neutral(), "the last wheel field counts")
	o.neutral()
	o.set_car(DamageOffsets.DOWNFORCE_REAR_MULT, 0.9)
	_check(not o.is_neutral(), "the last car field counts")
	# CarDamage builds into it
	var d := CarDamage.new()
	_check(d.offsets.is_neutral(), "an undamaged CarDamage has neutral offsets")
	d.apply_hit(Vector3(0, 0, 14.0))
	_check(not d.offsets.is_neutral() and d.offsets.get_wheel(0, DamageOffsets.TOE_ADD) > 0.0 and d.offsets.get_wheel(1, DamageOffsets.TOE_ADD) < 0.0, "a front hit bends both front toes, opposite ways")
	var data_before := d.offsets.data.duplicate()
	d.step_values(1.0 / 60.0, Vector3.ZERO, Basis(), false)
	_check(d.offsets.data == data_before, "stepping with no new hit leaves the offsets alone")
	d.garage_repair(null)
	_check(d.offsets.is_neutral(), "the garage puts them back to neutral")
	print("damage_offsets: %s" % ("PASS" if failures.is_empty() else "%d failure(s)" % failures.size()))
	quit(0 if failures.is_empty() else 1)
