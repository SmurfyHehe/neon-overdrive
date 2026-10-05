extends SceneTree

# Hidden test track test (Auto-Tune step 2). Checks, on the real PlayerCar sim:
# - the default coupe gives finite, plausible numbers on all three runs
# - determinism: the same spec five times in a row, and again on a fresh track,
#   gives bit-identical metrics
# - every v1 tunable at both ends of its range gives a run that finishes, doesn't
#   flip and is finite. Gear ratios are taken as far as they can go while the
#   gearbox stays in order (each gear at least 1.05x shorter than the one below):
#   a gear 1 of 0.5 under a gear 2 of 2.4 is not a gearbox, and the car can't
#   launch, which is what the search constraints (step 4) must rule out
# Prints (not asserts):
# - a sensitivity table: how far each tunable moves each metric, both as the
#   game runs (linear damp 0) and with Godot's old default damp of 0.1
# - simulation speed: physics steps per second and wall time per evaluated spec
#
# Meant to run with a fixed frame time so physics steps are not tied to the wall
# clock (tests/run_tests.bat does this; run by hand the same way):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . -s res://tests/tune_track.gd
# Without --fixed-fps it still works but takes real time (~35 s per batch).
#
# Exit code 1 on failure.

const METRICS := ["top_speed_kmh", "t_0_100", "brake_dist_100", "peak_lat_g", "max_slip_deg"]
const GEAR_STEP := 1.05

var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	var base := CarSpec.coupe_default()

	# --- default coupe ---
	var track := _new_track()
	var first: Dictionary = (await track.evaluate([base]))[0]
	print("default coupe: ", _fmt(first))
	_check(first.ok, "default coupe run problems: %s" % str(first.problems))
	_check(first.top_speed_kmh > 80.0 and first.top_speed_kmh < 320.0, "top speed implausible: %f" % first.top_speed_kmh)
	# Guard for PlayerCar.LINEAR_DAMP: Godot's default damp (0.1) held this car at ~124 km/h.
	_check(first.top_speed_kmh > 180.0, "top speed %.1f km/h: linear damping is capping the car again" % first.top_speed_kmh)
	_check(first.get("t_0_100", 99.0) > 1.5 and first.get("t_0_100", 99.0) < 20.0, "0-100 implausible: %s" % str(first.get("t_0_100")))
	_check(first.brake_dist_100 > 10.0 and first.brake_dist_100 < 100.0, "100-0 distance implausible: %f" % first.brake_dist_100)
	_check(first.peak_lat_g > 0.5 and first.peak_lat_g < 5.0, "peak lateral g implausible: %f" % first.peak_lat_g)
	track.queue_free()

	# --- determinism ---
	track = _new_track()
	var repeats: Array = await track.evaluate([base, base, base, base, base])
	var exact := true
	for r in repeats:
		exact = exact and _same(first, r)
	_check(exact, "same spec, five runs in a row: results differ from the first run
  first: %s
  runs:  %s" % [_fmt(first), str(repeats.map(_fmt))])
	track.queue_free()
	track = _new_track()
	var again: Dictionary = (await track.evaluate([base]))[0]
	_check(_same(first, again), "same spec, fresh track: results differ
  %s
  %s" % [_fmt(first), _fmt(again)])
	print("determinism: 5 repeats + fresh track %s" % ("bit-identical" if exact and _same(first, again) else "DIFFER"))
	track.queue_free()

	# --- extremes of every v1 range ---
	var paths := TuneParams.auto_paths()
	var specs: Array = [base]
	var labels: Array[String] = ["base"]
	for path in paths:
		var e := TuneParams.find(path)
		for end in ["min", "max"]:
			var s := CarSpec.clone_spec(base)
			var value: float = e[end]
			if path.begins_with("gear_ratios/"):
				var i := int(path.get_slice("/", 1))
				var gears: Array = base.gear_ratios
				if end == "min" and i < gears.size() - 1:
					value = maxf(value, gears[i + 1] * GEAR_STEP)
				if end == "max" and i > 0:
					value = minf(value, gears[i - 1] / GEAR_STEP)
			TuneParams.set_value(s, path, value)
			specs.append(s)
			labels.append("%s=%s (%.3f)" % [path, end, value])
	for damp in [-1.0, 0.1]:
		track = _new_track()
		track.linear_damp_override = damp
		var t0 := Time.get_ticks_usec()
		var results: Array = await track.evaluate(specs)
		var wall := (Time.get_ticks_usec() - t0) / 1e6
		var car_steps := track.steps_taken * track.cars_simulated
		print("
=== sweep, %s: %d specs, %.1f s wall, %.2f s per spec, %.0f physics steps/s (3 cars), %.0f us per car-step" % [
			"as the game runs (linear damp 0)" if damp < 0.0 else "old Godot default damp 0.1", specs.size(), wall, wall / specs.size(), track.steps_taken / wall, wall * 1e6 / car_steps])
		_report_sweep(labels, results, damp < 0.0)
		track.queue_free()

	# --- cost of one candidate ---
	track = _new_track()
	var t1 := Time.get_ticks_usec()
	await track.evaluate([base])
	var one := (Time.get_ticks_usec() - t1) / 1e6
	print("one spec: %d physics steps (%.0f s of simulated driving), %.2f s wall = %.0fx real time" % [track.steps_taken, track.steps_taken / 60.0, one, track.steps_taken / 60.0 / one])
	t1 = Time.get_ticks_usec()
	await track.evaluate([base, base, base])
	print("three specs (the step-5 verification): %.2f s wall" % ((Time.get_ticks_usec() - t1) / 1e6))
	track.queue_free()

	for f in failures:
		printerr("FAIL: ", f)
	print("tune_track: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _new_track() -> TuneTrack:
	var track := TuneTrack.new()
	root.add_child(track)
	return track

func _report_sweep(labels: Array[String], results: Array, check: bool) -> void:
	var base: Dictionary = results[0]
	print("%-38s %9s %7s %9s %8s %8s" % ["spec", "top km/h", "0-100 s", "100-0 m", "peak g", "slip deg"])
	print(_row("base", base))
	var insensitive: Array[String] = []
	var paths := TuneParams.auto_paths()
	for i in paths.size():
		var moved := false
		for end in 2:
			var idx := 1 + i * 2 + end
			var r: Dictionary = results[idx]
			print(_row(labels[idx], r))
			if check:
				_check(r.ok, "%s: %s" % [labels[idx], str(r.problems)])
			for m in METRICS:
				if absf(r.get(m, 0.0) - base.get(m, 0.0)) > 0.005 * maxf(absf(base.get(m, 0.0)), 1e-6):
					moved = true
		if not moved:
			insensitive.append(paths[i])
	print("no metric moves >0.5%% at either end of its range: %s" % (str(insensitive) if not insensitive.is_empty() else "none"))

func _row(label: String, r: Dictionary) -> String:
	var flag := "" if r.ok else "  !! " + str(r.problems)
	return "%-38s %9.1f %7.2f %9.1f %8.2f %8.1f%s" % [label, r.get("top_speed_kmh", NAN), r.get("t_0_100", NAN), r.get("brake_dist_100", NAN), r.get("peak_lat_g", NAN), r.get("max_slip_deg", NAN), flag]

func _fmt(r: Dictionary) -> String:
	return "top %.1f km/h, 0-100 %.2f s, 100-0 %.1f m, peak %.2f g, slip %.1f deg" % [r.get("top_speed_kmh", NAN), r.get("t_0_100", NAN), r.get("brake_dist_100", NAN), r.get("peak_lat_g", NAN), r.get("max_slip_deg", NAN)]

func _same(a: Dictionary, b: Dictionary) -> bool:
	for m in METRICS:
		if a.get(m) != b.get(m):
			return false
	return true

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
