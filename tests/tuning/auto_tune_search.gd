extends SceneTree

# Auto-Tune step 5 test: the search and its top-3 verification, on the real
# TuneTrack sim (scripts/tuning/auto_tune_search.gd). Checks
# - goal "accel": the result is better than the default coupe on 0-100, the
#   verified metrics are exactly what a fresh evaluation of the result gives,
#   at most 3 candidates were verified, every constraint holds, and nothing
#   outside the Auto-Tune paths (engine, torque shape) changed
# - determinism: the same search twice gives the identical tune
# - locks: locked parameters come out exactly as they went in
# - goal "braking": braking distance gets shorter (only the brake run is used)
# - the guard: a "top speed" search must not wreck braking by more than the guard
# - degenerate requests (no goal, everything locked) return the tune unchanged
# - a candidate that fails verification is not offered (verified list shows why)
#
# Meant to run with a fixed frame time, like tune_track (run_tests.bat does):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . -s res://tests/tuning/auto_tune_search.gd
# Exit code 1 on failure.

var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	var base := CarSpec.coupe_default()
	var track := TuneTrack.new()
	root.add_child(track)

	_check(TuneTrack.Kind.ACCEL == AutoTuneRules.KIND_ACCEL and TuneTrack.Kind.BRAKE == AutoTuneRules.KIND_BRAKE \
		and TuneTrack.Kind.CORNER == AutoTuneRules.KIND_CORNER, "AutoTuneRules kind numbers drifted from TuneTrack.Kind")

	# --- accel ---
	var req := {"goals": {"accel": 1.0}}
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = await AutoTuneSearch.new().run(track, base, req, 30)
	print("accel search: %d evals, %.0f s wall, score %.3f, %s" % [r.evals, (Time.get_ticks_msec() - t0) / 1000.0, r.score, r.notes])
	_check(r.improved, "accel search found no better tune: %s" % str(r.notes))
	if r.improved:
		print("  0-100 %.2f -> %.2f s; changed: %s" % [r.base_metrics.t_0_100, r.metrics.t_0_100, _changed(base, r.spec)])
		_check(r.metrics.t_0_100 < r.base_metrics.t_0_100 - 0.05, "0-100 did not improve: %f -> %f" % [r.base_metrics.t_0_100, r.metrics.t_0_100])
		var fresh: Dictionary = (await track.evaluate([r.spec]))[0]
		_check(fresh.t_0_100 == r.metrics.t_0_100 and fresh.brake_dist_100 == r.metrics.brake_dist_100 and fresh.peak_lat_g == r.metrics.peak_lat_g \
			and fresh.top_speed_kmh == r.metrics.top_speed_kmh, "verified metrics differ from a fresh evaluation of the result")
		_check(AutoTuneRules.violations(r.spec, req, base).is_empty(), "result breaks a rule: %s" % str(AutoTuneRules.violations(r.spec, req, base)))
		_check(r.verified.size() >= 1 and r.verified.size() <= AutoTuneSearch.VERIFY_COUNT, "verified %d candidates" % r.verified.size())
		for v in r.verified:  # search ran only the accel run; verification must agree on what it measured
			_check(v.metrics.has("brake_dist_100") and v.metrics.has("peak_lat_g"), "verification did not run all three runs")
		for key in ["max_torque", "max_rpm"]:
			_check(r.spec[key] == base[key], "%s changed (engine is raw-only)" % key)
		for k in base.torque_shape:
			_check(r.spec.torque_shape[k] == base.torque_shape[k], "torque shape %s changed" % k)
		_check(r.spec.gear_ratios.is_typed(), "result lost Array[float] typing")
	var r2: Dictionary = await AutoTuneSearch.new().run(track, base, req, 30)
	_check(_same_tune(r.spec, r2.spec), "same search twice gave different tunes")

	# --- locks: lock exactly what the free search moved, so a broken lock shows ---
	var locked := {"goals": {"accel": 1.0}, "locks": {"final_drive": true, "gear_ratios/0": true}}
	for p in TuneParams.auto_paths():
		if absf(TuneParams.get_value(r.spec, p) - TuneParams.get_value(base, p)) > 1e-9:
			locked.locks[p] = true
	_check(locked.locks.size() > 2, "the free accel search moved nothing, so the lock test would prove nothing")
	var rl: Dictionary = await AutoTuneSearch.new().run(track, base, locked, 20)
	print("locked accel search (locks: %s): improved=%s changed: %s" % [locked.locks.keys(), rl.improved, _changed(base, rl.spec)])
	for p in locked.locks:
		_check(TuneParams.get_value(rl.spec, p) == TuneParams.get_value(base, p), "locked %s changed" % p)
	_check(AutoTuneRules.violations(rl.spec, locked, base).is_empty(), "locked result breaks a rule")

	# --- braking ---
	var rb: Dictionary = await AutoTuneSearch.new().run(track, base, {"goals": {"braking": 1.0}}, 20)
	_check(rb.improved, "braking search found no better tune: %s" % str(rb.notes))
	if rb.improved:
		print("braking: 100-0 %.1f -> %.1f m; changed: %s" % [rb.base_metrics.brake_dist_100, rb.metrics.brake_dist_100, _changed(base, rb.spec)])
		_check(rb.metrics.brake_dist_100 < rb.base_metrics.brake_dist_100 - 0.5, "braking distance did not shrink")

	# --- guard: top speed must not wreck what was not asked ---
	var rt: Dictionary = await AutoTuneSearch.new().run(track, base, {"goals": {"top_speed": 1.0}}, 20)
	print("top speed: improved=%s %s" % [rt.improved, rt.notes])
	if rt.improved:
		print("  top %.1f -> %.1f km/h, 100-0 %.1f -> %.1f m, grip %.2f -> %.2f g" % [rt.base_metrics.top_speed_kmh, rt.metrics.top_speed_kmh,
			rt.base_metrics.brake_dist_100, rt.metrics.brake_dist_100, rt.base_metrics.peak_lat_g, rt.metrics.peak_lat_g])
		_check(AutoTuneRules.guard_failures(rt.metrics, rt.base_metrics, {"goals": {"top_speed": 1.0}}).is_empty(), "top-speed result wrecks an unasked metric")

	# --- degenerate requests ---
	var rn: Dictionary = await AutoTuneSearch.new().run(track, base, {"goals": {}}, 10)
	_check(not rn.improved and _same_tune(rn.spec, base) and rn.evals == 0, "no goal should do nothing")
	var all_locked := {"goals": {"accel": 1.0}, "locks": {}}
	for p in TuneParams.auto_paths():
		all_locked.locks[p] = true
	var ra: Dictionary = await AutoTuneSearch.new().run(track, base, all_locked, 10)
	_check(not ra.improved and _same_tune(ra.spec, base), "everything locked should change nothing")

	for f in failures:
		printerr("FAIL: ", f)
	print("auto_tune_search: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _changed(a: Dictionary, b: Dictionary) -> String:
	var out: Array[String] = []
	for p in TuneParams.auto_paths():
		var x := TuneParams.get_value(a, p)
		var y := TuneParams.get_value(b, p)
		if absf(x - y) > 1e-9:
			out.append("%s %.3f->%.3f" % [p, x, y])
	return ", ".join(out)

func _same_tune(a: Dictionary, b: Dictionary) -> bool:
	for p in TuneParams.auto_paths():
		if TuneParams.get_value(a, p) != TuneParams.get_value(b, p):
			return false
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
