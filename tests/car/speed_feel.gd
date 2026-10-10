extends SceneTree

# Per-car speed feel (SpeedFeel, 2026-10-10). Pure numbers, no scene.
#
# Asserts (exit code 1 on failure):
# - the stock coupe's top speed reads its measured 244 km/h (the same
#   calibration the Tuner's stat panel uses);
# - every player car gets a dial from SpeedFeel.DIALS that ends at least 10%
#   past its own top speed, and not a whole dial more than it needs;
# - the cars do not all share one dial (the point of the change);
# - more torque moves the top speed up, and a car tuned past its dial gets the
#   next one;
# - rattle is nothing at a cruise, rises toward the car's own top speed, and at
#   the same road speed the beater rattles more than the coupe.
# Prints the table.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/car/speed_feel.gd

var fails := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	var coupe := SpeedFeel.top_kmh(CarSpec.coupe_default(), PlayerCar.CFG.wheel_r)
	_check(absf(coupe - TunerModel.COUPE_MEASURED.top) < 0.5, "stock coupe top speed %.1f, measured %.1f" % [coupe, TunerModel.COUPE_MEASURED.top])
	var dials := {}
	print("car            top km/h  dial  ticks  rattle")
	for kind in PlayerCars.ids():
		var spec := CarSpec.player_spec(kind)
		var wheel_r: float = PlayerCar.wheel_config(kind).wheel_r
		var top := SpeedFeel.top_kmh(spec, wheel_r)
		var dial := SpeedFeel.dial_for(top)
		dials[dial] = true
		print("%-14s %8.1f %5.0f %6d %7.2f" % [kind, top, dial, int(dial / SpeedFeel.DIAL_TICK) + 1, SpeedFeel.rattle_gain(kind)])
		_check(top > 100.0 and top < 400.0, "%s top speed %.1f km/h is not a car's" % [kind, top])
		_check(dial in SpeedFeel.DIALS, "%s dial %.0f is not in DIALS" % [kind, dial])
		_check(dial >= top * SpeedFeel.DIAL_HEADROOM, "%s dial %.0f leaves under 10%% above %.1f" % [kind, dial, top])
		_check(dial - SpeedFeel.DIAL_TICK < top * SpeedFeel.DIAL_HEADROOM, "%s dial %.0f is a step bigger than %.1f needs" % [kind, dial, top])
		# a mod: 60% more torque and a taller final drive
		var modded := CarSpec.clone_spec(spec)
		modded["max_torque"] = float(spec.max_torque) * 1.6
		modded["final_drive"] = float(spec.final_drive) * 0.8
		var top2 := SpeedFeel.top_kmh(modded, wheel_r)
		_check(top2 > top, "%s: more torque and taller gearing did not raise top speed (%.1f -> %.1f)" % [kind, top, top2])
		_check(SpeedFeel.dial_for(top2) >= dial, "%s: the modded dial went down" % kind)
		# rattle against the car's own top speed
		var top_ms := top / 3.6
		_check(SpeedFeel.rattle(kind, 0.4 * top_ms, top_ms) == 0.0, "%s rattles at 40%% of its top speed" % kind)
		_check(SpeedFeel.rattle(kind, 0.8 * top_ms, top_ms) > 0.0, "%s does not rattle at 80%% of its top speed" % kind)
		_check(is_equal_approx(SpeedFeel.rattle(kind, 1.2 * top_ms, top_ms), SpeedFeel.rattle_gain(kind)), "%s rattle does not reach its gain flat out" % kind)
	_check(dials.size() >= 2, "every car got the same dial")
	_check(SpeedFeel.dial_for(250.0) == 280.0 and SpeedFeel.dial_for(260.0) == 320.0, "a car tuned from 250 to 260 km/h should move from the 280 dial to the 320")
	_check(SpeedFeel.dial_for(1000.0) == SpeedFeel.DIALS[SpeedFeel.DIALS.size() - 1], "past the last dial should stay on the last dial")
	var beater_top := SpeedFeel.top_kmh(CarSpec.player_spec("p0_beater"), PlayerCar.wheel_config("p0_beater").wheel_r) / 3.6
	_check(SpeedFeel.rattle("p0_beater", 38.0, beater_top) > SpeedFeel.rattle("p1_coupe", 38.0, coupe / 3.6), "at 137 km/h the beater should rattle more than the coupe")
	print("speed_feel: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(0 if fails == 0 else 1)
