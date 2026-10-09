extends SceneTree

# Danger zones and consequence lines (settings safety part 3,
# scripts/core/setting_danger.gd). Checks, no game needed:
# - every zone and line is for a real TuneParams path; thresholds are in order
# - the stock coupe is green on every path
# - every hard limit that spun the car on the test track (tests/tuning/tuner_settings.gd
#   Advanced run, slip over 25 deg, 2026-10-07) reads red
# - the simple pages' ranges never reach red, except the rear wing at zero,
#   which spins the car on the track even inside the safe range
# - lines: "Stock" at stock, different words below and above stock, short
#   enough for one line, and they change to the red wording past red
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/core/setting_danger.gd

## [path, value] that spun the car at its hard limit.
const SPINS := [
	["coefficient_of_friction/Road", 0.5], ["coefficient_of_friction/Road", 3.5],
	["longitudinal_grip_ratio/Road", 0.45],
	["rear_tyre_pressure", 1.0], ["rear_tyre_pressure", 3.6],
	["rear_static_camber", -8.0], ["rear_static_camber", 3.0],
	["rear_toe", -0.03],
	["rear_spring_length", 0.08], ["rear_spring_length", 0.40],
	["rear_resting_ratio", 0.15], ["rear_resting_ratio", 1.0],
	["front_arb_ratio", 0.0], ["rear_arb_ratio", 1.2],
	["aero_downforce_coefficient_front", 2.5],
]
const MAX_LINE := 48

var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	var stock := CarSpec.coupe_default()
	for path in SettingDanger.ZONES:
		_check(not TuneParams.find(path).is_empty(), "zone for unknown path %s" % path)
		var z: Array = SettingDanger.ZONES[path]
		_check(z[0] <= z[1] and z[1] < z[2] and z[2] <= z[3], "%s thresholds out of order: %s" % [path, str(z)])
		var v := TuneParams.get_value(stock, path)
		_check(SettingDanger.level(path, v) == SettingDanger.Level.GREEN, "stock %s = %s is not green" % [path, str(v)])
	for path in SettingDanger.LINES:
		_check(not TuneParams.find(path).is_empty(), "line for unknown path %s" % path)
		var e := TuneParams.find(path)
		var sv := TuneParams.get_value(stock, path)
		_check(SettingDanger.consequence(path, sv, sv) in ["Stock", "Auto: split set from the springs"], "%s at stock: %s" % [path, SettingDanger.consequence(path, sv, sv)])
		var lo := SettingDanger.consequence(path, e.adv_min, sv)
		var hi := SettingDanger.consequence(path, e.adv_max, sv)
		for t in [lo, hi]:
			_check(t.length() <= MAX_LINE, "%s line too long (%d): %s" % [path, t.length(), t])
		if e.adv_min < sv and e.adv_max > sv and path != "front_brake_bias":
			_check(lo != hi and lo != "" and hi != "", "%s: low and high read the same: %s" % [path, lo])
	for s in SPINS:
		_check(SettingDanger.level(s[0], s[1]) == SettingDanger.Level.RED, "%s = %s spins the car but is not red" % [s[0], str(s[1])])
	_check(SettingDanger.consequence("rear_toe", -0.03, 0.01).contains("spins"), "past red the line should use the red wording: %s" % SettingDanger.consequence("rear_toe", -0.03, 0.01))
	_check(SettingDanger.level("front_brake_bias", -1.0) == SettingDanger.Level.GREEN, "Auto bias should be green")
	_check(SettingDanger.level("final_drive", NAN) == SettingDanger.Level.RED, "a non-finite value should be red")

	# simple pages: never red inside their ranges (rear wing at zero excepted)
	for p in TunerModel.pages():
		for s in p.settings:
			if s.kind != "range" or s.paths[0] == "aero_downforce_coefficient_rear":
				continue
			for n in TunerModel.NOTCHES:
				var v := TunerScreen._notch_value(s, n)
				_check(SettingDanger.level(s.paths[0], v) != SettingDanger.Level.RED, "%s notch %d (%s) is red on the simple page" % [s.id, n, str(v)])

	for m in failures:
		printerr("FAIL: ", m)
	print("setting_danger: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
