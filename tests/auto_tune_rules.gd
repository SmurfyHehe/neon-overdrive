extends SceneTree

# Auto-Tune step 4 test: goals, locks and constraints (scripts/auto_tune_rules.gd).
# Pure data, no physics. Checks
# - the default coupe satisfies every constraint and repair() leaves it alone
# - gear order: any gear pushed out of order is repaired to >= GEAR_STEP, or
#   reported impossible when locks / ranges leave no room; locked values never move
# - scoring: baseline = 0, weights respected, direction per metric, missing = reject
# - the guard flags unasked metrics that got much worse, not asked ones
# - violations() catches out-of-range values, bad order and changed locks
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/auto_tune_rules.gd

var failures: Array[String] = []

func _initialize() -> void:
	var base := CarSpec.coupe_default()
	var none := {}

	# --- default coupe is valid and untouched by repair ---
	_check(AutoTuneRules.violations(base, none, base).is_empty(), "default coupe violates its own constraints: %s" % str(AutoTuneRules.violations(base, none, base)))
	var same := CarSpec.clone_spec(base)
	_check(AutoTuneRules.repair(same, none), "repair failed on the default coupe")
	for path in TuneParams.auto_paths():
		_check(is_equal_approx(TuneParams.get_value(same, path), TuneParams.get_value(base, path)), "repair moved %s on a valid spec" % path)

	# --- gear order ---
	var s := CarSpec.clone_spec(base)
	TuneParams.set_value(s, "gear_ratios/0", 0.5)  # under a 2.4 second gear: cannot launch
	_check(not AutoTuneRules.violations(s, none, base).is_empty(), "gear 1 = 0.5 under gear 2 = 2.4 not flagged")
	_check(AutoTuneRules.repair(s, none), "repair should fix gear 1 = 0.5")
	_check(s.gear_ratios[0] >= s.gear_ratios[1] * AutoTuneRules.GEAR_STEP - 1e-6, "gear 1 not repaired above gear 2")
	_check(AutoTuneRules.violations(s, none, s).is_empty(), "repaired spec still violates: %s" % str(AutoTuneRules.violations(s, none, s)))
	_check(s.gear_ratios.is_typed(), "repair lost Array[float] typing")

	s = CarSpec.clone_spec(base)
	TuneParams.set_value(s, "gear_ratios/4", 4.5)  # top gear at the ceiling: gear 4 cannot rise above 4.5
	_check(AutoTuneRules.repair(s, none), "repair should find room by lowering gear 5")
	_check(_ordered(s), "gears out of order after repairing a huge gear 5: %s" % str(s.gear_ratios))
	_check(is_equal_approx(s.gear_ratios[0], base.gear_ratios[0]) or s.gear_ratios[0] > base.gear_ratios[0] - 1e-6, "gear 1 should not have dropped")

	# every single-gear extreme, both ends: always repairable with no locks
	for i in 5:
		for v in [0.5, 4.5]:
			var t := CarSpec.clone_spec(base)
			TuneParams.set_value(t, "gear_ratios/%d" % i, v)
			_check(AutoTuneRules.repair(t, none) and _ordered(t), "gear %d = %.1f not repairable: %s" % [i + 1, v, str(t.gear_ratios)])

	# --- locks ---
	var locks := {"locks": {"gear_ratios/0": true, "final_drive": true}}
	_check(not AutoTuneRules.free_paths(locks).has("final_drive") and AutoTuneRules.free_paths(locks).size() == 12, "free_paths ignores locks")
	s = CarSpec.clone_spec(base)
	TuneParams.set_value(s, "gear_ratios/1", 4.0)  # above locked gear 1 (3.6)
	_check(AutoTuneRules.repair(s, locks), "repair should shorten gear 2 under a locked gear 1")
	_check(is_equal_approx(s.gear_ratios[0], 3.6), "locked gear 1 moved")
	_check(s.gear_ratios[1] <= 3.6 / AutoTuneRules.GEAR_STEP + 1e-6, "gear 2 not brought under locked gear 1")
	_check(_ordered(s), "order broken: %s" % str(s.gear_ratios))
	var both := {"locks": {"gear_ratios/0": true, "gear_ratios/1": true}}
	s = CarSpec.clone_spec(base)
	TuneParams.set_value(s, "gear_ratios/1", 3.59)  # both locked, out of order: impossible
	_check(not AutoTuneRules.repair(s, both), "two locked gears out of order should be impossible")
	var changed := CarSpec.clone_spec(base)
	TuneParams.set_value(changed, "final_drive", 3.0)
	_check(not AutoTuneRules.violations(changed, locks, base).is_empty(), "changed locked final_drive not caught")
	var oob := CarSpec.clone_spec(base)
	TuneParams.set_value(oob, "coefficient_of_drag", 9.0)
	_check(not AutoTuneRules.violations(oob, none, base).is_empty(), "out-of-range drag not caught")
	_check(AutoTuneRules.repair(oob, none) and is_equal_approx(oob.coefficient_of_drag, 0.40), "repair should clamp drag to its range")

	# --- scoring ---
	var bm := {"t_0_100": 5.0, "top_speed_kmh": 240.0, "brake_dist_100": 40.0, "peak_lat_g": 2.8}
	var req := {"goals": {"accel": 1.0}}
	_check(is_zero_approx(AutoTuneRules.score(bm, bm, req)), "baseline should score 0")
	var faster := bm.duplicate()
	faster.t_0_100 = 4.5
	_check(is_equal_approx(AutoTuneRules.score(faster, bm, req), 0.1), "10%% faster 0-100 should score 0.1, got %f" % AutoTuneRules.score(faster, bm, req))
	var slower := bm.duplicate()
	slower.t_0_100 = 5.5
	_check(AutoTuneRules.score(slower, bm, req) < 0.0, "slower 0-100 should score below 0")
	var mixed := {"goals": {"accel": 3.0, "braking": 1.0}}
	var m2 := bm.duplicate()
	m2.t_0_100 = 4.5       # +10%
	m2.brake_dist_100 = 44.0  # -10%
	_check(is_equal_approx(AutoTuneRules.score(m2, bm, mixed), (3.0 * 0.1 - 1.0 * 0.1) / 4.0), "weights not respected: %f" % AutoTuneRules.score(m2, bm, mixed))
	var top := {"goals": {"top_speed": 1.0, "grip": 1.0}}
	var m3 := bm.duplicate()
	m3.top_speed_kmh = 264.0  # +10%
	m3.peak_lat_g = 3.08      # +10%
	_check(is_equal_approx(AutoTuneRules.score(m3, bm, top), 0.1), "bigger-is-better goals mis-scored")
	var missing := bm.duplicate()
	missing.erase("t_0_100")
	_check(AutoTuneRules.score(missing, bm, req) < -1e8, "missing goal metric should reject the tune")
	_check(is_zero_approx(AutoTuneRules.score(bm, bm, {"goals": {}})), "no goals should score 0")
	_check(Array(AutoTuneRules.kinds_needed({"goals": {"accel": 1, "top_speed": 1}})) == [AutoTuneRules.KIND_ACCEL], "accel + top speed need only the accel run")
	_check(Array(AutoTuneRules.kinds_needed({"goals": {"braking": 1, "grip": 2, "accel": 0}})) == [AutoTuneRules.KIND_BRAKE, AutoTuneRules.KIND_CORNER], "kinds for braking + grip (accel weight 0 is off)")

	# --- guard ---
	var wrecked := bm.duplicate()
	wrecked.top_speed_kmh = 270.0
	wrecked.brake_dist_100 = 60.0  # 50% worse, not asked about
	var g := AutoTuneRules.guard_failures(wrecked, bm, {"goals": {"top_speed": 1.0}})
	_check(g.size() == 1 and g[0].begins_with("brake_dist_100"), "guard should flag only braking: %s" % str(g))
	wrecked.brake_dist_100 = 48.0  # 20% worse, inside the guard
	_check(AutoTuneRules.guard_failures(wrecked, bm, {"goals": {"top_speed": 1.0}}).is_empty(), "20% worse is inside the guard")
	wrecked.brake_dist_100 = 80.0
	_check(AutoTuneRules.guard_failures(wrecked, bm, {"goals": {"braking": 1.0}}).is_empty(), "an asked-for metric is not guarded")

	for f in failures:
		printerr("FAIL: ", f)
	print("auto_tune_rules: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _ordered(spec: Dictionary) -> bool:
	for i in spec.gear_ratios.size() - 1:
		if spec.gear_ratios[i] < spec.gear_ratios[i + 1] * AutoTuneRules.GEAR_STEP - 1e-6:
			return false
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
