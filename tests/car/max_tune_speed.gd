extends SceneTree

# Max tune, driven (2026-10-13): every player car, max-tuned
# (scripts/tuning/max_tune.gd), flat out on a long flat road until its speed
# stops rising (scripts/tuning/top_speed_run.gd). No game boot.
#
# Fails when a car falls more than SLACK under the top speed measured for it
# when its gearing was set (MaxTune.TOP_RATIO), ends on the rev limiter (the
# gearing no longer fits the engine), flips, or never reaches top gear. Prints
# each car's top speed next to its tier's ladder top (notes/car-sheets) as a
# report: a car under its ladder top is a balance finding, filed as an issue,
# not a failure of the profile.
#
# SLACK is 5%: the table was measured on the GDScript sim (Linux); the C++ sim
# that runs where neon_sim loads is meant to be better, not identical.
#
#   godot --headless --fixed-fps 120 --audio-driver Dummy --path . -s res://tests/car/max_tune_speed.gd
# MAX_TUNE_CARS=p1_coupe,p5_muscle picks cars.

const MaxTune := preload("res://scripts/tuning/max_tune.gd")
const TopSpeedRun := preload("res://scripts/tuning/top_speed_run.gd")
const SLACK := 0.05

var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	var cars: Array = PlayerCars.ids()
	if OS.get_environment("MAX_TUNE_CARS") != "":
		cars = Array(OS.get_environment("MAX_TUNE_CARS").split(","))
	print("%-16s %8s %8s %8s %6s %6s  %s" % ["car", "top", "table", "ladder", "0-100", "0-200", "stopped by"])
	for id: String in cars:
		var spec := MaxTune.spec(id)
		var r: Dictionary = await TopSpeedRun.run(self, id, spec)
		var want := float(MaxTune.TOP_RATIO.get(id, [0.0, 0.0])[1])
		var ladder := MaxTune.ladder_top(id)
		print("%-16s %8.1f %8.1f %8s %6.1f %6s  %s%s" % [id, r.top, want, "-" if ladder <= 0.0 else "%.0f" % ladder, r.t100,
			"-" if r.t200 < 0.0 else "%.1f" % r.t200, r.why, "  (under its ladder top)" if ladder > 0.0 and r.top < ladder else ""])
		_check(r.top >= want * (1.0 - SLACK), "%s: %.1f km/h, %.1f measured when its gearing was set" % [id, r.top, want])
		_check(not String(r.why).begins_with("limiter"), "%s: ends on the rev limiter at %.1f km/h" % [id, r.top])
		_check(r.why != "flipped", "%s: flipped" % id)
		_check(int(r.gear) == (spec.gear_ratios as Array).size(), "%s: top speed in gear %d of %d" % [id, int(r.gear), (spec.gear_ratios as Array).size()])
	for f in failures:
		printerr("FAIL: ", f)
	print("max_tune_speed: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
