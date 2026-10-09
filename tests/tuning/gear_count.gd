extends SceneTree

# Gear count is per car (transmissions step G1): the tuner registry and the
# cockpit's H-gate follow the car's own number of forward gears, not a fixed
# five (and six on the console label).
# - a stock car (5 gears) lists gear_ratios/0..4 and nothing more
# - a 6-gear car lists gear_ratios/0..5; set_param writes gear 6 to spec and car
#   and clamps it to the Advanced limit
# - a 4-gear car lists 4; the registry is restored for a 5-gear car afterwards
# - the H-gate pattern: 6 gears "1 3 5 / 2 4 6 R", 5 gears a blank under 5 with
#   R still last, 4 gears two columns; the same on a real cockpit label
# - the lever slot of reverse sits right of the last column for each count
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/tuning/gear_count.gd

var failures: Array[String] = []

func _gear_paths() -> Array[String]:
	var out: Array[String] = []
	for e in TuneParams.all():
		if (e.path as String).begins_with("gear_ratios/"):
			out.append(e.path)
	return out

func _car_with_gears(ratios: Array[float]) -> PlayerCar:
	var spec := CarSpec.player_spec(PlayerCar.chassis_kind())
	var typed: Array[float] = ratios.duplicate()
	spec["gear_ratios"] = typed
	var c := PlayerCar.new()
	c.spec = spec
	root.add_child(c)
	return c

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_gear_count_exhaust.json"
	_check_patterns()

	# Stock car: five gears.
	var stock := PlayerCar.new()
	root.add_child(stock)
	await process_frame
	_check(stock.gear_ratios.size() == 5, "stock car should have 5 gears, has %d" % stock.gear_ratios.size())
	_check(_gear_paths().size() == 5, "stock registry should list 5 gears, lists %d" % _gear_paths().size())
	_check(TuneParams.find("gear_ratios/5").is_empty(), "stock registry should not know gear 6")
	_check_cockpit(stock, 5)
	stock.queue_free()
	await process_frame

	# Six gears: the sixth is tunable and reaches spec and car.
	var six := _car_with_gears([3.2, 2.2, 1.6, 1.25, 1.0, 0.8])
	await process_frame
	_check(six.gear_ratios.size() == 6, "six-speed car has %d gears" % six.gear_ratios.size())
	_check(_gear_paths().size() == 6, "registry should list 6 gears, lists %d" % _gear_paths().size())
	var stored := CarSpec.set_param(six, six.spec, "gear_ratios/5", 0.7)
	_check(is_equal_approx(stored, 0.7), "gear 6 stored %f, wanted 0.7" % stored)
	_check(is_equal_approx(six.gear_ratios[5], 0.7), "gear 6 not on the car")
	_check(is_equal_approx(six.spec.gear_ratios[5], 0.7), "gear 6 not in the spec")
	_check(six.gear_ratios.is_typed() and six.spec.gear_ratios.is_typed(), "six-speed gear_ratios lost Array[float]")
	var hi := CarSpec.set_param(six, six.spec, "gear_ratios/5", 99.0)
	_check(is_equal_approx(hi, 5.0), "gear 6 should clamp to 5.0, got %f" % hi)
	_check_cockpit(six, 6)
	six.queue_free()
	await process_frame

	# Four gears.
	var four := _car_with_gears([3.4, 2.0, 1.3, 0.9])
	await process_frame
	_check(_gear_paths().size() == 4, "registry should list 4 gears, lists %d" % _gear_paths().size())
	_check(TuneParams.find("gear_ratios/4").is_empty(), "four-speed registry should not know gear 5")
	_check_cockpit(four, 4)
	four.queue_free()
	await process_frame

	TuneParams.set_gear_count(5)
	_check(_gear_paths().size() == 5, "registry did not return to 5 gears")

	for f in failures:
		printerr("FAIL: ", f)
	print("gear_count: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check_patterns() -> void:
	_check(CockpitFrame.gate_pattern(6) == "1 3 5\n2 4 6 R", "6 gears: %s" % CockpitFrame.gate_pattern(6).replace("\n", "|"))
	var five := CockpitFrame.gate_pattern(5).split("\n")
	_check(five.size() == 2 and five[0] == "1 3 5", "5 gears top line: %s" % str(five))
	_check(five.size() == 2 and five[1].begins_with("2 4") and five[1].ends_with("R") and not five[1].contains("6"), "5 gears bottom line: %s" % str(five))
	_check(CockpitFrame.gate_pattern(4) == "1 3\n2 4 R", "4 gears: %s" % CockpitFrame.gate_pattern(4).replace("\n", "|"))
	_check(CockpitFrame.gate_pattern(7).split("\n")[0] == "1 3 5 7", "7 gears top line")
	_check(CockpitFrame.gate_columns(5) == 3 and CockpitFrame.gate_columns(6) == 3 and CockpitFrame.gate_columns(4) == 2, "gate columns")

## The real cockpit's H label and the lever's reverse slot for this car.
func _check_cockpit(car: PlayerCar, gears: int) -> void:
	var frame := CockpitFrame.new(car)
	car.add_child(frame)
	var label := frame._gate_labels[PlayerCar.Transmission.MANUAL] as Label3D
	_check(label.text == CockpitFrame.gate_pattern(gears), "%d gears: console label is '%s'" % [gears, label.text.replace("\n", "|")])
	if gears < 6:
		_check(not label.text.contains("6"), "%d gears: console still prints a 6th gear" % gears)
	var cols := CockpitFrame.gate_columns(gears)
	frame.lever_mode = PlayerCar.Transmission.MANUAL
	var rev := frame._slot_of(-1)
	_check(is_equal_approx(rev.x, float(cols) - float(cols - 1) / 2.0) and rev.y == 1.0, "%d gears: reverse slot %s" % [gears, str(rev)])
	var last := frame._slot_of(gears)
	_check(last.x < rev.x, "%d gears: top gear not left of reverse (%s vs %s)" % [gears, str(last), str(rev)])
	frame.queue_free()

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
