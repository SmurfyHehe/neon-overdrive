extends SceneTree

# Tyre pressure and camber (Tuner redesign PR 1, 2026-10-06), on the hidden test
# track with the real PlayerCar sim:
# - stock: every wheel factor is exactly 1.0 and the stock spec's metrics are
#   bit-identical to a spec with the new fields removed (so no car's feel moved)
# - calibration sweep: each setting at the ends of its range against stock.
#   Asserted: every run finishes, nothing flips, and no setting moves any metric
#   by more than MAX_SHIFT; the full range of each setting moves at least one
#   metric by MIN_SHIFT or more (a knob you cannot feel is a bug). Printed: the
#   whole table.
# - direction: some negative camber (-1.5 deg) corners harder than none, and
#   high pressure does not cost top speed
# Run (tests/run_tests.bat does):
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . -s res://tests/tyre_model.gd
# Exit code 1 on failure.

const MIN_SHIFT := 0.01   # 1%
const MAX_SHIFT := 0.12   # 12%
const METRICS := ["top_speed_kmh", "t_0_100", "brake_dist_100", "peak_lat_g"]
const NEW_KEYS := ["front_tyre_pressure", "rear_tyre_pressure", "tyre_pressure_stock",
	"front_static_camber", "rear_static_camber", "front_static_camber_stock", "rear_static_camber_stock"]

var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	var base := CarSpec.coupe_default()

	# --- the wheel factors on stock ---
	var w := Wheel.new()
	w.set_tyre_setup(2.2, 2.2, 0.0, 0.0, 1.0)
	_check(w.pressure_stiffness_mult == 1.0 and w.pressure_grip_mult == 1.0 and w.pressure_roll_mult == 1.0
		and w.camber_long_mult == 1.0 and not w.camber_active, "stock setup should give factors of exactly 1.0")
	w.free()

	# --- stock == the car before this PR ---
	var legacy := CarSpec.clone_spec(base)
	for k in NEW_KEYS:
		legacy.erase(k)
	var track := _new_track()
	var pair: Array = await track.evaluate([base, legacy])
	_check(_same(pair[0], pair[1]), "stock setup changed the car:\n  stock  %s\n  before %s" % [_fmt(pair[0]), _fmt(pair[1])])
	track.queue_free()

	# --- calibration sweep ---
	var cases := [
		["camber -4.0 both", {"front_static_camber": -4.0, "rear_static_camber": -4.0}],
		["camber -1.5 both", {"front_static_camber": -1.5, "rear_static_camber": -1.5}],
		["camber +1.0 both", {"front_static_camber": 1.0, "rear_static_camber": 1.0}],
		["pressure 1.6 both", {"front_tyre_pressure": 1.6, "rear_tyre_pressure": 1.6}],
		["pressure 2.8 both", {"front_tyre_pressure": 2.8, "rear_tyre_pressure": 2.8}],
	]
	var specs: Array = [base]
	for c in cases:
		var s := CarSpec.clone_spec(base)
		for k in c[1]:
			s[k] = c[1][k]
		specs.append(s)
	track = _new_track()
	var res: Array = await track.evaluate(specs)
	track.queue_free()
	var stock: Dictionary = res[0]
	print("%-20s %9s %8s %8s %7s" % ["setup", "top km/h", "0-100 s", "100-0 m", "lat g"])
	print(_row("stock", stock))
	var shifts := {}
	for i in cases.size():
		var r: Dictionary = res[i + 1]
		var label: String = cases[i][0]
		print(_row(label, r))
		_check(r.ok, "%s: run problems %s" % [label, str(r.problems)])
		var biggest := 0.0
		for m in METRICS:
			var d := absf(float(r[m]) - float(stock[m])) / maxf(absf(float(stock[m])), 0.001)
			biggest = maxf(biggest, d)
			_check(d <= MAX_SHIFT, "%s moves %s by %.1f%% (max %.0f%%)" % [label, m, d * 100.0, MAX_SHIFT * 100.0])
		shifts[label] = biggest
	_check(maxf(shifts["camber -4.0 both"], shifts["camber +1.0 both"]) >= MIN_SHIFT, "camber's full range moves nothing by %.0f%%" % (MIN_SHIFT * 100.0))
	_check(maxf(shifts["pressure 1.6 both"], shifts["pressure 2.8 both"]) >= MIN_SHIFT, "pressure's full range moves nothing by %.0f%%" % (MIN_SHIFT * 100.0))

	# --- direction ---
	_check(res[2].peak_lat_g > stock.peak_lat_g, "camber -1.5 should corner harder than 0 (%.3f vs %.3f g)" % [res[2].peak_lat_g, stock.peak_lat_g])
	_check(res[5].top_speed_kmh >= stock.top_speed_kmh, "2.8 bar should not lose top speed (%.1f vs %.1f)" % [res[5].top_speed_kmh, stock.top_speed_kmh])

	print("tyre_model: %s" % ("PASS" if failures.is_empty() else "FAIL (%d)" % failures.size()))
	for f in failures:
		print("  ", f)
	quit(0 if failures.is_empty() else 1)

func _new_track() -> TuneTrack:
	var track := TuneTrack.new()
	root.add_child(track)
	return track

func _row(label: String, r: Dictionary) -> String:
	return "%-20s %9.1f %8.2f %8.1f %7.3f" % [label, r.get("top_speed_kmh", NAN), r.get("t_0_100", NAN), r.get("brake_dist_100", NAN), r.get("peak_lat_g", NAN)]

func _fmt(r: Dictionary) -> String:
	return _row("", r).strip_edges()

func _same(a: Dictionary, b: Dictionary) -> bool:
	for m in METRICS + ["max_slip_deg"]:
		if a.get(m) != b.get(m):
			return false
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("FAIL ", msg)
