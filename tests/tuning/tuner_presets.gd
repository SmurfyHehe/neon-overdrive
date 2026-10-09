extends SceneTree

# The new Tuner's model (Tuner redesign PR 3, 2026-10-06), headless:
# - every preset finishes the hidden test track's runs, finite and unflipped;
#   none spins (Drift may slide further but not go sideways); Grip corners harder than Stock
# - Stock after any preset is the stock spec again (every TuneParams value)
# - every setting on every page: notch 0 and notch 10 stay inside TuneParams'
#   ranges, and reading the notch back gives the notch that was set
# - the estimates: the stock coupe reads its measured numbers, and they move the
#   right way (longer gearing slower 0-100, more wing more grip and less top
#   speed, a stiffer rear bar toward oversteer)
# Run (tests/run_tests.bat does):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . -s res://tests/tuning/tuner_presets.gd
# Exit code 1 on failure.

const MAX_SLIP := 25.0
## Drift may slide, but not spin round (90 deg = sideways).
const MAX_SLIP_DRIFT := 75.0

var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	var stock := CarSpec.coupe_default()

	# --- every setting's ends ---
	var m := TunerModel.new(null, CarSpec.clone_spec(stock), stock)
	for p in TunerModel.pages():
		for s in p.settings:
			if s.kind == "choice":
				for i in s.options.size():
					m.set_choice(s, i)
					_check(m.choice_index(s) == i, "%s: picked %s, reads back %d" % [s.id, s.options[i], m.choice_index(s)])
				continue
			for n in [0, 5, 10]:
				m.set_notch(s, n)
				_check(m.notch(s) == n, "%s: set notch %d, reads back %d" % [s.id, n, m.notch(s)])
				for path in s.paths:
					var e := TuneParams.find(path)
					var v := TuneParams.get_value(m.spec, path)
					_check(v >= e.min - 0.0001 and v <= e.max + 0.0001, "%s notch %d: %s = %f outside [%f, %f]" % [s.id, n, path, v, e.min, e.max])

	# --- Stock puts everything back ---
	m.apply_preset("Drift")
	m.apply_preset("Stock")
	for e in TuneParams.all():
		_check(is_equal_approx(TuneParams.get_value(m.spec, e.path), TuneParams.get_value(stock, e.path)), "Stock did not restore %s" % e.path)

	# --- presets on the track ---
	var specs: Array = []
	for name in TunerModel.PRESETS:
		var pm := TunerModel.new(null, CarSpec.clone_spec(stock), stock)
		pm.apply_preset(name)
		specs.append(pm.spec)
	var track := TuneTrack.new()
	root.add_child(track)
	var res: Array = await track.evaluate(specs)
	track.queue_free()
	for i in res.size():
		var r: Dictionary = res[i]
		var name: String = TunerModel.PRESETS[i]
		print("%-7s top %.1f km/h, 0-100 %.2f s, 100-0 %.1f m, lat %.3f g, slip %.1f deg   (est. %s)" % [name, r.top_speed_kmh, r.t_0_100, r.brake_dist_100, r.peak_lat_g, r.max_slip_deg, _est(TunerModel.estimate(specs[i]))])
		_check(r.ok, "%s preset: %s" % [name, str(r.problems)])
		var limit := MAX_SLIP_DRIFT if name == "Drift" else MAX_SLIP
		_check(r.max_slip_deg < limit, "%s preset spins the car (%.0f deg)" % [name, r.max_slip_deg])
	_check(res[2].peak_lat_g > res[0].peak_lat_g, "Grip should corner harder than Stock (%.3f vs %.3f g)" % [res[2].peak_lat_g, res[0].peak_lat_g])

	# --- estimates ---
	var e0 := TunerModel.estimate(stock)
	_check(absf(e0.top - TunerModel.COUPE_MEASURED.top) < 0.5 and absf(e0.accel - TunerModel.COUPE_MEASURED.accel) < 0.05
		and absf(e0.brake - TunerModel.COUPE_MEASURED.brake) < 0.5 and absf(e0.grip - TunerModel.COUPE_MEASURED.grip) < 0.01, "stock estimates should read the measured numbers: %s" % _est(e0))
	var long := CarSpec.clone_spec(stock)
	long.final_drive = 2.8
	_check(TunerModel.estimate(long).accel > e0.accel, "longer gearing should estimate a slower 0-100")
	var wing := CarSpec.clone_spec(stock)
	wing.aero_downforce_coefficient_rear = 1.2
	wing.coefficient_of_drag = 0.3
	var ew := TunerModel.estimate(wing)
	_check(ew.grip > e0.grip and ew.top < e0.top, "more wing should estimate more grip and less top speed (%s)" % _est(ew))
	var bar := CarSpec.clone_spec(stock)
	bar.rear_arb_ratio = 0.45
	_check(TunerModel.estimate(bar).balance > e0.balance, "a stiffer rear bar should move balance toward oversteer")

	print("tuner_presets: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	for f in failures:
		print("  ", f)
	quit(0 if failures.is_empty() else 1)

func _est(e: Dictionary) -> String:
	return "top %.1f, 0-100 %.2f, 100-0 %.1f, grip %.3f, balance %+.2f" % [e.top, e.accel, e.brake, e.grip, e.balance]

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)
