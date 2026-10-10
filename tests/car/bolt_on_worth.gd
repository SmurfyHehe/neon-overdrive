extends SceneTree

# Bolt-on worth sweep (mod tree step B1): every item fitted on the Bug after
# Service, run on the hidden test track with the scripted driver, scored and
# printed against the design estimates. See scripts/car/bolt_on_worth.gd for
# what each column means. Takes a few minutes on a quiet machine.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/car/bolt_on_worth.gd
#   tools\bolt_on_worth.bat
#
# Environment (optional): BOLT_CAR (a PlayerCars id, default p0_beater),
# BOLT_ONLY (comma list of item ids), BOLT_OUT (a path to write the table to).
# Asserts only what must always hold: every run is ok, every number is finite,
# and the headline physics directions (lighter, stronger, shorter shifts, firmer
# brakes) are not backwards. It prints, not asserts, the worth numbers.

var failures: Array[String] = []

func _initialize() -> void:
	var car := OS.get_environment("BOLT_CAR")
	if car == "":
		car = "p0_beater"
	var only: Array = []
	for p in OS.get_environment("BOLT_ONLY").split(",", false):
		only.append(p.strip_edges())
	var track := TuneTrack.new()
	root.add_child(track)
	await process_frame
	var t0 := Time.get_ticks_msec()
	var rows: Array = await BoltOnWorth.sweep(track, car, only)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var base := BoltOnWorth.base_spec(car)
	print("")
	print("## Bolt-on worth, %s after Service (torque %.0f Nm, %.0f kg), 90 s reference loop" % [car, base.max_torque, base.vehicle_mass])
	print("")
	print(BoltOnWorth.table(rows))
	print("")
	print("%d items swept in %.0f s. Pace and Control are measured on the sim; Street is priced from the assumed night ledger; Flair is authored." % [rows.size(), secs])
	var out := OS.get_environment("BOLT_OUT")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(BoltOnWorth.table(rows) + "\n")
			f.close()

	for r in rows:
		_check(r.ok, "%s: a run had problems %s" % [r.id, str(r.problems)])
		for k in ["pace_s", "pace", "control", "street", "worth"]:
			_check(is_finite(r[k]), "%s: %s is not finite" % [r.id, k])
	var by := {}
	for r in rows:
		by[r.id] = r
	if only.is_empty():
		_check(rows.size() == 28, "expected 28 rows, got %d" % rows.size())
		_check(by.has("cabin_strip_3") and float(by.cabin_strip_3.pace_s) > float(by.cabin_strip_1.pace_s) - 0.0001,
			"cabin strip 3 should save at least as much as step 1")
		_check(float(by.short_shifter.pace_s) > 0.0, "short shifter should save time")
		_check(float(by.brake_pads.brake_m) > 0.0, "pads should shorten 100-0")
		_check(float(by.light_battery.pace_s) >= 0.0, "a lighter car is not slower")
		_check(float(by.ecu_unlock.pace_s) > 0.0, "more torque should save time")
		_check(float(by.straight_pipe.street) < 0.0, "straight pipe should cost on the street")
	if failures.is_empty():
		print("bolt_on_worth: PASS")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
