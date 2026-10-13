extends SceneTree

# Max tune (scripts/tuning/max_tune.gd), the test-only flat-out profile. No
# driving here (tests/car/max_tune_speed.gd drives every car):
# - off unless asked for: not in test mode, not by default
# - every player car builds: finite, usable, the stock spec untouched, every
#   normal car boosted, every gear and the final drive inside the Tuner's
#   hard limits, every car in TOP_RATIO with its measured overall ratio
# - in the game (Game.tscn) with it on: the car is the max-tuned spec, no saved
#   tune is read or written, and saving is off for the run (also for the
#   benchmark, #613)
#
#   godot --headless --fixed-fps 120 --audio-driver Dummy --path . -s res://tests/car/max_tune.gd

const MaxTune := preload("res://scripts/tuning/max_tune.gd")
const Harness := preload("res://tests/traffic/traffic_harness.gd")
const PlayerTune := preload("res://scripts/car/player_tune.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")

var failures: Array[String] = []
var game: Node

func _initialize() -> void:
	await process_frame
	_check(not MaxTune.on(), "max tune is on with no flag, no NEON_MAX_TUNE and not forced")
	var lim_g: Array = TuneParams.ADVANCED["gear_ratios/0"]
	var lim_fd: Array = TuneParams.ADVANCED["final_drive"]
	for id: String in PlayerCars.ids():
		var stock := CarSpec.player_spec(id)
		var before := stock.duplicate(true)
		var b := MaxTune.build(id)
		var s: Dictionary = b.spec
		print(MaxTune.spec_report(id))
		_check(CarSpec.player_spec(id) == before, "%s: building it changed the stock spec" % id)
		_check(is_finite(float(s.max_torque)) and float(s.max_torque) > 0.0 and float(s.vehicle_mass) > 300.0
			and float(s.max_rpm) > float(s.idle_rpm) and (s.gear_ratios as Array).size() == (stock.gear_ratios as Array).size(),
			"%s: the max-tuned spec is not usable" % id)
		if not PlayerCars.is_special(id):
			_check(float(s.get("turbo_boost_max", 0.0)) > 0.0, "%s: no boost" % id)
			_check(MaxTune.ladder_top(id) > 0.0, "%s: no ladder top speed for its tier" % id)
		_check(MaxTune.TOP_RATIO.has(id), "%s: not in MaxTune.TOP_RATIO (run tools/top_speed_sweep.gd --calibrate)" % id)
		_check(float(s.final_drive) >= float(lim_fd[0]) and float(s.final_drive) <= float(lim_fd[1]), "%s: final drive %.2f outside the Tuner's limits" % [id, float(s.final_drive)])
		var prev := INF
		for g in s.gear_ratios:
			_check(float(g) >= float(lim_g[0]) and float(g) <= float(lim_g[1]), "%s: gear %.2f outside the Tuner's limits" % [id, float(g)])
			_check(float(g) < prev, "%s: gears not in falling order %s" % [id, str(s.gear_ratios)])
			prev = float(g)
		if MaxTune.TOP_RATIO.has(id):
			var overall := float(s.gear_ratios[(s.gear_ratios as Array).size() - 1]) * float(s.final_drive)
			_check(absf(overall - float(MaxTune.TOP_RATIO[id][0])) < 0.005, "%s: top gear x final %.3f, table says %.3f" % [id, overall, float(MaxTune.TOP_RATIO[id][0])])
	# In the game.
	MaxTune.forced = 1
	PlayerTune.enabled = true   # as in a play session: max tune must still keep it off
	game = Harness.boot(self, 0, 300.0, 777)
	for i in 240:
		await physics_frame
	var p: PlayerCar = game.get("player")
	var want := MaxTune.spec(PlayerCar.chassis_kind())
	_check(p != null and absf(p.final_drive - float(want.final_drive)) < 1e-4 and absf(p.turbo_boost_max - float(want.turbo_boost_max)) < 1e-4,
		"the game's car is not the max-tuned spec")
	_check(p != null and not p._keeps_tune, "the max-tuned car would save its tune")
	_check(p != null and p.mod_build.get("max_tune", false), "the car's mod_build does not say max tune")
	_check(not SaveDirector.enabled, "saving is on with max tune")
	print("max_tune: in game %s, final %.2f, boost %.2f, saving %s" % [PlayerCar.chassis_kind(), p.final_drive, p.turbo_boost_max, "on" if SaveDirector.enabled else "off"])
	for f in failures:
		printerr("FAIL: ", f)
	print("max_tune: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
