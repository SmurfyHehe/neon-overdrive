extends SceneTree

# Top speed of every player car, flat out on a long flat road (2026-10-13,
# Roy: "tune cars and add turbo and things like that to max the car"). No game
# boot: each car is a sim-only PlayerCar on its own ground, full throttle,
# shifting at 97% of redline like TuneTrack's driver, until the speed stops
# rising (under 0.5 km/h gained in 10 s) or RUN_SECS runs out.
#
# Which build is measured (--build=<name>, default all three):
#   stock      CarSpec.player_spec
#   everything ModTree.everything_fit (the test build's sandbox car)
#   max        MaxTune.spec (the test-only max-tune profile)
# --cars=a,b picks cars (default every PlayerCars id). --secs=<s> run length.
# --calibrate: for each car, finds the max-tune top-gear ratio (MaxTune.TOP_RATIO)
# by driving: from the sums' ratio, taller while it ends on the limiter, else
# the ratio that puts the engine at its peak-power rpm at the speed it reached,
# until it lands within 2% of it; prints the fastest run with the engine at or
# under REDLINE_SHARE of redline at top speed. Paste the lines into
# max_tune.gd's TOP_RATIO.
#
#   godot --headless --audio-driver Dummy --path . -s res://tools/top_speed_sweep.gd -- --build=max
#
# Prints one row per car and build: top km/h, the gear and rpm it got there in,
# 0-100 and 0-200 s, what stopped it (drag: still under redline; limiter: on
# the cut in top gear). Physics on the project tick rate (120 Hz). On Linux the
# GDScript GEVP runs (no neon_sim library), as in every cloud test.

const MaxTune := preload("res://scripts/tuning/max_tune.gd")
const TopSpeedRun := preload("res://scripts/tuning/top_speed_run.gd")
const REDLINE_SHARE := 1.02

func _initialize() -> void:
	await process_frame
	var builds := ["stock", "everything", "max"]
	var want := Benchmark.opt("build")
	if want != "":
		builds = want.split(",")
	var cars: Array = PlayerCars.ids()
	if Benchmark.opt("cars") != "":
		cars = Array(Benchmark.opt("cars").split(","))
	var secs := Benchmark.opt_float("secs", TopSpeedRun.RUN_SECS)
	print("top_speed_sweep: %d cars x %s, %.0f s max, %d Hz" % [cars.size(), ",".join(PackedStringArray(builds)), secs, Engine.physics_ticks_per_second])
	if Benchmark.opt("calibrate") != "" or "--calibrate" in OS.get_cmdline_user_args():
		for id: String in cars:
			await _calibrate(id, secs)
		quit(0)
		return
	print("%-16s %-10s %8s %5s %7s %6s %6s %6s %s" % ["car", "build", "top", "gear", "rpm", "0-100", "0-200", "secs", "stopped by"])
	for id: String in cars:
		for b: String in builds:
			var spec := _spec(id, b)
			var r: Dictionary = await _run(id, spec, secs)
			print("%-16s %-10s %8.1f %5d %7.0f %6s %6s %6.0f %s" % [id, b, r.top, r.gear, r.rpm,
				"-" if r.t100 < 0.0 else "%.1f" % r.t100, "-" if r.t200 < 0.0 else "%.1f" % r.t200, r.t, r.why])
	quit(0)

func _spec(id: String, build: String) -> Dictionary:
	var stock := CarSpec.player_spec(id)
	TuneParams.set_gear_count((stock.gear_ratios as Array).size())
	match build:
		"everything":
			return ModTree.build_base(stock, ModTree.everything_fit(id))
		"max":
			return MaxTune.spec(id)
	return stock

func _calibrate(id: String, secs: float) -> void:
	var s0: Dictionary = MaxTune.build(id).spec
	var r := MaxTune.wheel_radius(id)
	var x_want := minf(float(MaxTune.peak_power(s0)[1]), MaxTune.TOP_RPM_SHARE)
	var ratio := MaxTune.overall_for_top(s0, r)
	var best := [0.0, ratio, ""]
	for i in 6:
		var r_spec: Dictionary = MaxTune.build(id, ratio).spec
		var res: Dictionary = await _run(id, r_spec, secs)
		var x: float = res.rpm / float(r_spec.max_rpm)
		print("  %s ratio %.3f -> %.1f km/h at %.0f rpm (%.2f of redline, want %.2f), %s" % [id, ratio, res.top, res.rpm, x, x_want, res.why])
		var on_limiter := String(res.why).begins_with("limiter")
		if not on_limiter and x <= REDLINE_SHARE and res.top > best[0]:
			best = [res.top, ratio, res.why]
		if on_limiter:
			ratio *= 0.93
		elif res.gear == (r_spec.gear_ratios as Array).size() and absf(x - x_want) > 0.02:
			ratio = x_want * float(r_spec.max_rpm) * TAU / 60.0 / (res.top / 3.6 / r)
		else:
			break
	print("TOP_RATIO \"%s\": [%.3f, %.1f]," % [id, best[1], best[0]])

func _run(id: String, spec: Dictionary, secs: float) -> Dictionary:
	return await TopSpeedRun.run(self, id, spec, secs)
