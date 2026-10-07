extends SceneTree

# Settings safety part 1 (docs/planning/settings-safety-design-2026-10-07.md):
# nothing a hand-edited or damaged settings file holds can put a broken value
# into the game, and brake bias can always go back to Auto.
# - settings.cfg with nan / inf / quoted strings: volumes, cars, draw distance
#   and cockpit FOV load as finite values in range, and a quoted "false" turns an
#   effect off (bool("false") is true)
# - the setters refuse NaN the same way
# - Tuner: Bias mode Auto -> Manual keeps the split Auto was giving, Manual ->
#   Auto writes -1 again, and the stock preset reads as Auto
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/settings_safety.gd

var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	# Never touch a real settings file. On 2026-10-07 a run of this test outside
	# test mode wrote the damaged file below over Roy's user://settings.cfg: the
	# check only logged a failure and carried on. Now it stops, and the damaged
	# file gets a path of its own, so the shared test_settings.cfg that other
	# tests load is never touched either.
	if not AudioSettings.path.get_file().begins_with("test_"):
		printerr("FAIL: not in test mode (settings path %s); run it as res://tests/settings_safety.gd. Nothing written." % AudioSettings.path)
		quit(1)
		return
	var real_path := AudioSettings.path
	AudioSettings.path = AudioSettings.path.get_base_dir().path_join("test_settings_safety_damaged.cfg")

	# --- damaged settings file ---
	var f := FileAccess.open(AudioSettings.path, FileAccess.WRITE)
	f.store_string("[audio]\nmaster=nan\nengine=inf\n\n[traffic]\ncar_count=nan\ndetail_distance=nan\n\n[view]\ncockpit_fov=nan\n\n[fx]\nvignette=\"false\"\nspeed_lines=\"true\"\nskid_marks=false\n")
	f = null
	AudioSettings.load_settings()
	TrafficSettings.load_settings()
	ViewSettings.load_settings()
	FxSettings.load_settings()
	for ch in AudioSettings.volumes:
		var v: float = AudioSettings.volumes[ch]
		_check(is_finite(v) and v >= 0.0 and v <= 1.0, "volume %s loaded as %s" % [ch, str(v)])
	_check(TrafficSettings.car_count == TrafficSettings.CAR_COUNT_DEFAULT, "car count from nan: %d" % TrafficSettings.car_count)
	_check(is_finite(TrafficSettings.detail_distance), "draw distance from nan: %s" % str(TrafficSettings.detail_distance))
	_check(is_finite(ViewSettings.cockpit_fov) and ViewSettings.cockpit_fov == ViewSettings.COCKPIT_FOV_DEFAULT, "cockpit FOV from nan: %s" % str(ViewSettings.cockpit_fov))
	_check(not FxSettings.is_on("vignette"), "a quoted \"false\" left the vignette on")
	_check(FxSettings.is_on("speed_lines"), "a quoted \"true\" turned speed lines off")
	_check(not FxSettings.is_on("skid_marks"), "a plain false left skid marks on")

	# --- setters ---
	AudioSettings.set_volume("Master", NAN)
	_check(is_finite(AudioSettings.volumes.Master), "set_volume stored NaN")
	TrafficSettings.set_detail_distance(NAN)
	_check(is_finite(TrafficSettings.detail_distance), "set_detail_distance stored NaN")
	ViewSettings.set_cockpit_fov(NAN)
	_check(is_finite(ViewSettings.cockpit_fov), "set_cockpit_fov stored NaN")

	AudioSettings.path = real_path

	# --- brake bias Auto / Manual ---
	var car := PlayerCar.new()
	car.sim_only = true
	root.add_child(car)
	await physics_frame
	await physics_frame
	var model := TunerModel.new(car, car.spec, CarSpec.coupe_default())
	var mode: Dictionary = {}
	var bias: Dictionary = {}
	for s in TunerModel.page("brakes").settings:
		if s.id == "bias_mode":
			mode = s
		elif s.id == "front_brake_bias":
			bias = s
	_check(not mode.is_empty() and not bias.is_empty(), "Brakes page has no Bias mode / Brake bias")
	if not mode.is_empty():
		_check(model.value_text(mode) == "Auto", "stock should read Auto: %s" % model.value_text(mode))
		var auto_split: float = car.front_axle.brake_bias
		model.nudge(mode, 1)
		_check(model.value_text(mode) == "Manual", "Right should pick Manual: %s" % model.value_text(mode))
		_check(absf(float(car.spec.front_brake_bias) - auto_split) < 0.011, "Manual should start at the Auto split %.3f, got %.3f" % [auto_split, car.spec.front_brake_bias])
		model.nudge(bias, 3)
		_check(car.spec.front_brake_bias > auto_split, "nudging the bias did not move it")
		model.nudge(mode, -1)
		_check(float(car.spec.front_brake_bias) < 0.0 and model.value_text(mode) == "Auto", "Left should go back to Auto (-1), got %s" % str(car.spec.front_brake_bias))
		_check(absf(car.front_axle.brake_bias - auto_split) < 0.001, "back on Auto the car brakes at %.3f, not the Auto split %.3f" % [car.front_axle.brake_bias, auto_split])
	car.queue_free()

	for m in failures:
		printerr("FAIL: ", m)
	print("settings_safety: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
