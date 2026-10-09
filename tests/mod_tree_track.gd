extends SceneTree

# Mod tree builds on the hidden test track (scripts/tune_track.gd): the stock
# coupe and all 8 P1 capstone builds on top parts, each with no tune and with
# every slider pushed to the ends of its window (the hardest a player can push
# the parts they own; presets are covered by tests/tuner_presets.gd). Checks
# - every build runs clean (TuneTrack's ok: no flip, reaches 100 km/h, finite)
# - every capstone build launches 0-100 faster than stock (the engine nodes and
#   parts add power and grip)
# - the Grip capstones corner harder than stock
# It prints each build's numbers. This is the foundation's sanity run, not the
# E7 feel test (each node past a threshold, each capstone winning a goal).
#
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . -s res://tests/mod_tree_track.gd

var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	var tree := ModTree.load_car("p1_coupe")
	var stock := CarSpec.coupe_default()
	var top := {}
	for k in tree.parts:
		top[k] = 2
	var names: Array[String] = ["stock"]
	var specs: Array = [stock]
	for leaf in tree.leaves():
		var chain := tree.chain_to(leaf)
		var base := tree.base_spec(stock, chain, top)
		names.append(leaf)
		specs.append(base)
	# sliders at the window ends (low, then high), on two of the builds
	for leaf in ["big_turbo_slide", "screamer_grip"]:
		var chain := tree.chain_to(leaf)
		var base := tree.base_spec(stock, chain, {})
		var win := tree.windows(base, chain, {})
		for end in [0, 1]:
			var m := TunerModel.new(null, CarSpec.clone_spec(base), base)
			m.windows = win
			for p in TunerModel.pages():
				for s in p.settings:
					if s.kind == "range" and win.has(s.paths[0]):
						m.set_notch(s, 0 if end == 0 else TunerModel.NOTCHES - 1)
			names.append("%s stock parts, sliders %s" % [leaf, "low" if end == 0 else "high"])
			specs.append(m.spec)

	var track := TuneTrack.new()
	root.add_child(track)
	var res: Array = await track.evaluate(specs)
	track.queue_free()
	var s0: Dictionary = res[0]
	for i in res.size():
		var r: Dictionary = res[i]
		print("%-40s top %.1f km/h, 0-100 %.2f s, 100-0 %.1f m, lat %.3f g, slip %.1f deg, %d Nm, %d rpm" % [names[i], r.top_speed_kmh, r.t_0_100, r.brake_dist_100, r.peak_lat_g, r.max_slip_deg, specs[i].max_torque, specs[i].max_rpm])
		_check(r.ok, "%s: %s" % [names[i], str(r.problems)])
		if i > 0 and i <= 8:
			_check(r.t_0_100 < s0.t_0_100, "%s is not quicker to 100 than stock (%.2f vs %.2f s)" % [names[i], r.t_0_100, s0.t_0_100])
			if names[i].ends_with("_grip"):
				_check(r.peak_lat_g > s0.peak_lat_g, "%s corners no harder than stock (%.3f vs %.3f g)" % [names[i], r.peak_lat_g, s0.peak_lat_g])

	print("mod_tree_track: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	for f in failures:
		printerr("FAIL: ", f)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
