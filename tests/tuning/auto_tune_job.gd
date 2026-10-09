extends SceneTree

# Auto-Tune job test (step 6): the search runs in a separate headless Godot
# process (scripts/tuning/auto_tune_job.gd + auto_tune_worker.gd). Checks
# - a spec survives the trip as {path: value} (every tunable path, Array[float]
#   kept), including a non-default engine tune
# - the worker's result is IDENTICAL to running the same search in this process
#   (values, base metrics, verified metrics): the process split changes nothing
# - progress is reported while it runs, and a result with "improved" comes back
# - cancel() stops a running worker
# - a request with no goal comes back as a clean "nothing to do", not a failure
#
# Run with a fixed frame time so the in-process comparison search is fast
# (run_tests.bat does this; it also starts the worker processes itself):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . -s res://tests/tuning/auto_tune_job.gd
# Exit code 1 on failure.

const WAIT_SECS := 240.0

var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	_run()

func _run() -> void:
	var exe := AutoTuneJob.find_godot()
	_check(exe != "", "no Godot executable found for the worker")
	if exe == "":
		return _end()

	# --- transport ---
	var spec := CarSpec.coupe_default()
	TuneParams.set_value(spec, "max_torque", 410.0)       # raw-only knob, not default
	TuneParams.set_value(spec, "torque_shape/low_end", 0.55)
	TuneParams.set_value(spec, "final_drive", 3.7)
	var back := AutoTuneJob.spec_from_values(JSON.parse_string(JSON.stringify(AutoTuneJob.values_from_spec(spec))))
	for e in TuneParams.all():
		_check(is_equal_approx(TuneParams.get_value(back, e.path), TuneParams.get_value(spec, e.path)), "%s lost in transport" % e.path)
	_check(back.gear_ratios.is_typed(), "gear_ratios lost Array[float] in transport")

	# --- worker == in-process ---
	var request := {"goals": {"braking": 1.0}, "locks": {}}
	for p in TuneParams.auto_paths():
		if p != "brake_force_multiplier" and p != "gear_ratios/1":
			request.locks[p] = true
	var budget := 6
	var job := AutoTuneJob.new()
	_check(job.start(spec, request, budget), "job did not start: %s" % job.error)
	var saw_progress := false
	var t0 := Time.get_ticks_msec()
	while job.poll() == AutoTuneJob.State.RUNNING and (Time.get_ticks_msec() - t0) / 1000.0 < WAIT_SECS:
		saw_progress = saw_progress or job.progress.done > 0
		OS.delay_msec(200)
		await process_frame
	_check(job.state == AutoTuneJob.State.DONE, "worker did not finish: state %d, %s" % [job.state, job.error])
	print("worker: %d runs in %.1f s, improved=%s, notes %s" % [job.result.get("evals", -1), (Time.get_ticks_msec() - t0) / 1000.0, job.result.get("improved"), job.result.get("notes")])
	_check(saw_progress or job.progress.done > 0, "no progress was ever reported")

	var track := TuneTrack.new()
	root.add_child(track)
	var local: Dictionary = await AutoTuneSearch.new().run(track, spec, request, budget)
	if job.state == AutoTuneJob.State.DONE:
		_check(job.result.improved == local.improved, "worker improved=%s, local %s" % [job.result.improved, local.improved])
		_check(int(job.result.evals) == int(local.evals), "worker did %s evals, local %s" % [job.result.evals, local.evals])
		for p in TuneParams.auto_paths():
			_check(is_equal_approx(job.result.values[p], TuneParams.get_value(local.spec, p)), "%s: worker %s, local %s" % [p, job.result.values[p], TuneParams.get_value(local.spec, p)])
		for key in ["top_speed_kmh", "t_0_100", "brake_dist_100", "peak_lat_g"]:
			_check(is_equal_approx(job.result.base_metrics[key], local.base_metrics[key]), "base %s: worker %s, local %s" % [key, job.result.base_metrics[key], local.base_metrics[key]])
		_check(job.result.improved, "braking search with brake multiplier and gear 2 free found nothing: %s" % str(job.result.notes))
		var applied := job.result_spec(spec)
		_check(applied.gear_ratios.is_typed(), "result_spec lost Array[float]")
		_check(is_equal_approx(applied.max_torque, 410.0), "result_spec lost the engine tune")
		for v in job.result.verified:
			_check(v.metrics.has("peak_lat_g"), "verified candidate lacks the full metrics")
		if local.improved:
			for key in ["top_speed_kmh", "t_0_100", "brake_dist_100", "peak_lat_g"]:
				_check(is_equal_approx(job.result.metrics[key], local.metrics[key]), "result %s: worker %s, local %s" % [key, job.result.metrics[key], local.metrics[key]])

	# --- cancel ---
	var slow := AutoTuneJob.new()
	_check(slow.start(spec, {"goals": {"accel": 1.0}, "locks": {}}, 120), "second job did not start")
	OS.delay_msec(1500)
	_check(slow.poll() == AutoTuneJob.State.RUNNING, "worker should still be running after 1.5 s")
	slow.cancel()
	_check(slow.state == AutoTuneJob.State.CANCELLED, "cancel did not set CANCELLED")
	OS.delay_msec(500)
	_check(not OS.is_process_running(slow.pid), "worker still running after cancel")
	_check(slow.poll() == AutoTuneJob.State.CANCELLED, "poll after cancel should stay CANCELLED")

	# --- no goal: a clean empty result ---
	var none := AutoTuneJob.new()
	_check(none.start(spec, {"goals": {}, "locks": {}}, 10), "no-goal job did not start")
	t0 = Time.get_ticks_msec()
	while none.poll() == AutoTuneJob.State.RUNNING and (Time.get_ticks_msec() - t0) / 1000.0 < 60.0:
		OS.delay_msec(200)
		await process_frame
	_check(none.state == AutoTuneJob.State.DONE and not none.result.improved, "no-goal job: state %d, %s" % [none.state, none.error])
	_end()

func _end() -> void:
	for f in failures:
		printerr("FAIL: ", f)
	print("auto_tune_job: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
