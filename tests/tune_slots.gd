extends SceneTree

# Named tune slots test (Auto-Tune step 7, scripts/tune_slots.gd). Checks
# - save / names / has / values / delete, names sorted, a name is trimmed and
#   cut to 24 characters, an empty name is refused, saving under a name replaces
# - a slot holds EVERY tunable path (engine knobs and torque shape included)
# - it survives a new TuneSlots on the same file (really on disk)
# - apply() puts the tune on a live car through set_param(): spec and car agree,
#   gear_ratios stays Array[float], values outside a range are clamped, a slot
#   missing a path leaves that path alone
# - a corrupt file reads as empty and does not crash; saving then repairs it,
#   after copying the corrupt file to tune_slots.bad.json
# - NaN (null in JSON), strings and arrays in a slot are skipped, the rest of the
#   slot still applies, and set_param() refuses NaN
# - deleting a slot never deletes the file
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/tune_slots.gd

const FILE := "user://autotune/test_tune_slots.json"

var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://autotune"))
	var f := FileAccess.open(FILE, FileAccess.WRITE)  # start empty; the file is only ever overwritten
	f.store_string("")
	f = null

	var slots := TuneSlots.new(FILE)
	_check(slots.names().is_empty(), "a fresh slot file should have no slots")
	var tuned := CarSpec.coupe_default()
	TuneParams.set_value(tuned, "final_drive", 3.4)
	TuneParams.set_value(tuned, "gear_ratios/2", 1.7)
	TuneParams.set_value(tuned, "max_torque", 455.0)            # raw-only
	TuneParams.set_value(tuned, "torque_shape/plateau", 0.3)    # raw-only
	TuneParams.set_value(tuned, "brake_force_multiplier", 1.2)

	_check(not slots.save("   ", tuned), "an empty name should be refused")
	_check(slots.save("  Street  ", tuned), "save failed")
	_check(slots.has("Street") and ",".join(slots.names()) == "Street", "name not trimmed: %s" % str(slots.names()))
	_check(slots.save("Drag", CarSpec.coupe_default()), "second save failed")
	_check(",".join(slots.names()) == "Drag,Street", "names not sorted: %s" % str(slots.names()))
	var long_name := "x".repeat(40)
	slots.save(long_name, tuned)
	_check(slots.names().has("x".repeat(TuneSlots.MAX_NAME_LENGTH)), "long name not cut to %d: %s" % [TuneSlots.MAX_NAME_LENGTH, str(slots.names())])
	slots.delete("x".repeat(TuneSlots.MAX_NAME_LENGTH))

	# every tunable path is in the slot
	var v := slots.values("Street")
	_check(v.size() == TuneParams.all().size(), "slot has %d values, expected %d" % [v.size(), TuneParams.all().size()])
	for e in TuneParams.all():
		_check(v.has(e.path) and is_equal_approx(v[e.path], TuneParams.get_value(tuned, e.path)), "%s not stored" % e.path)

	# replace
	var other := CarSpec.coupe_default()
	TuneParams.set_value(other, "final_drive", 4.9)
	slots.save("Street", other)
	_check(is_equal_approx(slots.values("Street").final_drive, 4.9), "saving under an existing name should replace")
	slots.save("Street", tuned)

	# really on disk
	var again := TuneSlots.new(FILE)
	_check(",".join(again.names()) == "Drag,Street", "slots not read back from disk: %s" % str(again.names()))
	_check(is_equal_approx(again.values("Street").max_torque, 455.0), "engine knob not read back")

	# apply on a live car
	var car := PlayerCar.new()
	root.add_child(car)
	await process_frame
	_check(again.apply("Street", car), "apply failed")
	for e in TuneParams.all():
		_check(is_equal_approx(TuneParams.get_value(car.spec, e.path), TuneParams.get_value(tuned, e.path)), "%s: spec %s, slot %s" % [e.path, TuneParams.get_value(car.spec, e.path), TuneParams.get_value(tuned, e.path)])
		if e.on_car:
			_check(is_equal_approx(TuneParams.get_value(car, e.path), TuneParams.get_value(tuned, e.path)), "%s: live car not updated" % e.path)
	_check(car.gear_ratios.is_typed() and car.spec.gear_ratios.is_typed(), "apply lost Array[float]")
	_check(not again.apply("Nope", car), "apply of a missing slot should say so")
	_check(is_equal_approx(car.spec.final_drive, 3.4), "a missing slot changed the car")

	# clamping and missing paths, from a hand-written file
	var hand := FileAccess.open(FILE, FileAccess.WRITE)
	hand.store_string(JSON.stringify({"version": 1, "slots": {"Odd": {"final_drive": 99.0, "no_such_param": 1.0}}}))
	hand = null
	var odd := TuneSlots.new(FILE)
	var before_torque: float = car.spec.max_torque
	_check(odd.apply("Odd", car), "apply of the hand-written slot failed")
	_check(is_equal_approx(car.spec.final_drive, TuneParams.find("final_drive").max), "99.0 should clamp to the range, got %f" % car.spec.final_drive)
	_check(car.spec.max_torque == before_torque, "a path the slot lacks changed")

	# corrupt file
	var bad := FileAccess.open(FILE, FileAccess.WRITE)
	bad.store_string("{ this is not json")
	bad = null
	var broken := TuneSlots.new(FILE)
	_check(broken.names().is_empty(), "a corrupt file should read as no slots")
	var backup := broken.bad_path()
	_check(broken.save("Fresh", tuned) and ",".join(TuneSlots.new(FILE).names()) == "Fresh", "saving should repair a corrupt file")
	_check(FileAccess.file_exists(backup) and FileAccess.get_file_as_string(backup) == "{ this is not json", "the corrupt file was not backed up to %s before the save" % backup)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))  # this test's own backup

	# non-finite values (JSON writes NaN as null): dropped on load, the rest applies
	var nan_file := FileAccess.open(FILE, FileAccess.WRITE)
	nan_file.store_string(JSON.stringify({"version": 1, "slots": {"Nan": {"final_drive": NAN, "max_torque": "lots", "gear_ratios/0": [1], "max_rpm": 6500.0}}}))
	nan_file = null
	var nan_slots := TuneSlots.new(FILE)
	var fd_before: float = car.spec.final_drive
	var torque_before: float = car.spec.max_torque
	_check(nan_slots.apply("Nan", car), "apply of a slot with bad values failed")
	_check(car.spec.final_drive == fd_before and car.spec.max_torque == torque_before, "a null or string value changed the car")
	_check(is_equal_approx(car.spec.max_rpm, 6500.0), "the good value in a slot with bad ones was not applied")
	_check(is_finite(car.final_drive), "the live car got a non-finite final drive")
	_check(is_equal_approx(CarSpec.set_param(car, car.spec, "final_drive", NAN), fd_before) and car.spec.final_drive == fd_before, "set_param stored a NaN")
	# delete removes the entry, not the file
	_check(broken.delete("Fresh") and not broken.has("Fresh"), "delete failed")
	_check(FileAccess.file_exists(FILE), "delete removed the file")
	_check(TuneSlots.new(FILE).names().is_empty(), "deleted slot came back from disk")
	_check(not broken.delete("Fresh"), "deleting a missing slot should say so")

	for m in failures:
		printerr("FAIL: ", m)
	print("tune_slots: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
