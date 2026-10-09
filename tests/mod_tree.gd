extends SceneTree

# Mod tree foundation (Stage E, scripts/mod_tree.gd, garage_state.gd, wallet.gd).
# Checks
# - the P1 tree data loads clean: 15 nodes, one root, binary, 8 capstones, every
#   build 4 nodes deep, every node priced, each L2 its own engine
# - SWEEP: every fitted chain (16, empty included) x every parts combination
#   (3^6 = 729): the base build is finite and inside the hard limits, every
#   window holds its base value and sits inside the path's limits, a better part
#   never narrows a window, boost is 0..0 without a turbo node and open with one
# - SLIDERS: for each chain at all-stock, all-step-1 and all-top parts, every
#   Tuner range setting at every notch stays inside its window; on stock parts a
#   slider reaches at most 1 notch either side of the base; top parts reach the
#   whole range
# - PRESETS ignore the windows: each preset writes the same values with and
#   without windows, and on stock parts at least one lands outside a window
# - tunes never carry node-owned paths (torque, redline)
# - garage + wallet: a short bank refuses and changes nothing; a node needs its
#   parent; buying is paid from the bank and fits the node; swapping between
#   owned nodes is free; each engine keeps its own tune (fresh the first time,
#   the old one back on swapping back); parts step up and are paid; the garage
#   and the bank survive a reload from disk
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/mod_tree.gd

const GARAGE_FILE := "user://autotune/test_mod_tree_garage.json"
const WALLET_FILE := "user://autotune/test_mod_tree_wallet.json"

var failures: Array[String] = []

func _initialize() -> void:
	await process_frame
	var t0 := Time.get_ticks_msec()
	var tree := ModTree.load_car("p1_coupe")
	var stock := CarSpec.coupe_default()
	_check(tree.errors.is_empty(), "tree data errors: %s" % str(tree.errors))

	# --- shape ---
	_check(tree.nodes.size() == 15, "P1 tree has %d nodes, expected 15" % tree.nodes.size())
	var r := tree.root()
	_check(r == "service", "root is '%s'" % r)
	for id in tree.order:
		var kids := tree.children(id)
		_check(kids.size() == 0 or kids.size() == 2, "%s has %d children (binary tree)" % [id, kids.size()])
		_check(tree.price(id) > 0, "%s has no price" % id)
		_check(int(tree.nodes[id].level) == tree.chain_to(id).size() - 1, "%s: level does not match depth" % id)
	var leaves := tree.leaves()
	_check(leaves.size() == 8, "%d capstones, expected 8" % leaves.size())
	var engines := {}
	for leaf in leaves:
		var chain := tree.chain_to(leaf)
		_check(chain.size() == 4 and tree.is_chain(chain), "%s: build is %s" % [leaf, str(chain)])
		engines[tree.engine_key(chain)] = true
	_check(engines.size() == 4, "the 4 L2 engines should each have their own key: %s" % str(engines.keys()))
	_check(tree.engine_key([]) == "stock" and tree.engine_key(["service"]) == "stock", "no engine node should read 'stock'")

	# --- sweep: chains x parts ---
	var chains: Array = [[]]
	for id in tree.order:
		chains.append(tree.chain_to(id))
	var kinds: Array = tree.parts.keys()
	var combos := _combos(kinds, 0)
	_check(combos.size() == 729, "%d parts combinations, expected 729" % combos.size())
	var checked := 0
	var bad := 0
	for chain in chains:
		var turbo: bool = chain.has("turbo")
		for steps in combos:
			var base := tree.base_spec(stock, chain, steps)
			var win := tree.windows(base, chain, steps)
			checked += 1
			var msg := _sweep_one(tree, base, win, chain, steps, turbo)
			if msg != "":
				bad += 1
				if bad <= 10:
					_check(false, msg)
	_check(bad == 0, "%d of %d builds failed the sweep" % [bad, checked])
	# a better part never narrows a window
	for kind in kinds:
		for path in tree.parts[kind].paths:
			var widths: Array = []
			for step in 3:
				var steps := {kind: step}
				var base := tree.base_spec(stock, [], steps)
				var w: Array = tree.windows(base, [], steps)[path]
				widths.append(w[1] - w[0])
			_check(widths[0] <= widths[1] + 1e-6 and widths[1] <= widths[2] + 1e-6, "%s/%s window narrows with a better part: %s" % [kind, path, str(widths)])
	# the engine nodes really own torque and redline
	var na: Dictionary = tree.base_spec(stock, tree.chain_to("screamer"), {})
	var bt: Dictionary = tree.base_spec(stock, tree.chain_to("big_turbo"), {})
	_check(na.max_rpm > stock.max_rpm and bt.max_torque > stock.max_torque * 1.4, "screamer revs %d, big turbo %d Nm" % [na.max_rpm, bt.max_torque])
	print("sweep: %d builds in %d ms" % [checked, Time.get_ticks_msec() - t0])

	# --- sliders and presets ---
	var levels := [0, 1, 2]
	var outside_seen := false
	for chain in chains:
		for lvl in levels:
			var steps := {}
			for k in kinds:
				steps[k] = lvl
			var base := tree.base_spec(stock, chain, steps)
			var win := tree.windows(base, chain, steps)
			var m := TunerModel.new(null, CarSpec.clone_spec(base), base)
			m.windows = win
			for p in TunerModel.pages():
				for s in p.settings:
					if s.kind != "range":
						continue
					var lo_v := INF
					var hi_v := -INF
					for n in TunerModel.NOTCHES:
						m.set_notch(s, n)
						for path in s.paths:
							var v := TuneParams.get_value(m.spec, path)
							if win.has(path):
								_check(v >= win[path][0] - 1e-5 and v <= win[path][1] + 1e-5, "%s lvl %d %s notch %d: %f outside %s" % [str(chain), lvl, path, n, v, str(win[path])])
						var v0 := TuneParams.get_value(m.spec, s.paths[0])
						lo_v = minf(lo_v, v0)
						hi_v = maxf(hi_v, v0)
					m.reset_page(p.id)
					var path0: String = s.paths[0]
					if not win.has(path0) or path0 == "turbo_boost_max":
						continue
					var e0 := TuneParams.find(path0)
					var b0 := TuneParams.get_value(base, path0)
					var notch_w: float = (e0.max - e0.min) / 10.0
					if lvl == 0:
						_check(b0 - lo_v <= notch_w + 1e-4 and hi_v - b0 <= notch_w + 1e-4,
							"%s on stock parts moves %f..%f around base %f (one notch is %f)" % [s.id, lo_v, hi_v, b0, notch_w])
					elif lvl == 2:
						_check(lo_v <= s.lo + 1e-4 and hi_v >= s.hi - 1e-4, "%s on top parts reaches only %f..%f" % [s.id, lo_v, hi_v])
			# nudge stops at the window's edge
			var gear: Dictionary = TunerModel.page("gearbox").settings[0]
			var moves := 0
			while m.nudge(gear, 1) and moves < 20:
				moves += 1
			_check(moves < 20, "nudge never stopped at the window edge")
			# presets ignore the window
			for name in TunerModel.PRESETS:
				var free := TunerModel.new(null, CarSpec.clone_spec(base), base)
				free.apply_preset(name)
				m.apply_preset(name)
				for e in TuneParams.all():
					var a := TuneParams.get_value(m.spec, e.path)
					var b := TuneParams.get_value(free.spec, e.path)
					_check(is_equal_approx(a, b), "%s preset differs with windows on %s: %f vs %f" % [name, e.path, a, b])
					if lvl == 0 and win.has(e.path) and (a < win[e.path][0] - 1e-5 or a > win[e.path][1] + 1e-5):
						outside_seen = true
	_check(outside_seen, "no preset ever went outside a stock-parts window, so 'presets ignore the window' was not exercised")

	# --- tunes never carry owned paths ---
	var tuned := CarSpec.clone_spec(stock)
	tuned.max_torque = 999.0
	tuned.final_drive = 3.3
	var tune := ModTree.tune_of(tuned)
	_check(not tune.has("max_torque") and not tune.has("max_rpm") and is_equal_approx(tune.final_drive, 3.3), "tune_of kept an owned path or lost final drive")
	var back := ModTree.with_tune(bt, {"max_torque": 100.0, "final_drive": 3.3})
	_check(back.max_torque == bt.max_torque and is_equal_approx(back.final_drive, 3.3), "with_tune applied an owned path")

	# --- garage + wallet ---
	await _garage(tree, stock)

	print("mod_tree: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	for f in failures:
		printerr("FAIL: ", f)
	quit(0 if failures.is_empty() else 1)

func _sweep_one(tree: ModTree, base: Dictionary, win: Dictionary, chain: Array, steps: Dictionary, turbo: bool) -> String:
	var where := "%s %s" % [str(chain), str(steps)]
	for e in TuneParams.all():
		var v := TuneParams.get_value(base, e.path)
		if not is_finite(v) or v < e.adv_min - 1e-5 or v > e.adv_max + 1e-5:
			return "%s: %s = %f outside [%f, %f]" % [where, e.path, v, e.adv_min, e.adv_max]
	if not (float(base.vehicle_mass) > 500.0):
		return "%s: mass %f" % [where, base.vehicle_mass]
	for path in win:
		var w: Array = win[path]
		var b := TuneParams.get_value(base, path)
		var e := TuneParams.find(path)
		if w[0] > w[1] or b < w[0] - 1e-5 or b > w[1] + 1e-5:
			return "%s: %s window %s does not hold base %f" % [where, path, str(w), b]
		if w[0] < e.adv_min - 1e-5 or w[1] > e.adv_max + 1e-5:
			return "%s: %s window %s past the hard limits" % [where, path, str(w)]
	var boost: Array = win.get("turbo_boost_max", [0.0, 0.0])
	if turbo != (boost[1] > 0.0):
		return "%s: boost window %s with turbo=%s" % [where, str(boost), turbo]
	return ""

func _combos(kinds: Array, i: int) -> Array:
	if i == kinds.size():
		return [{}]
	var out: Array = []
	for rest in _combos(kinds, i + 1):
		for step in 3:
			var c: Dictionary = rest.duplicate()
			c[kinds[i]] = step
			out.append(c)
	return out

func _garage(tree: ModTree, stock: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://autotune"))
	for f in [GARAGE_FILE, WALLET_FILE]:
		var h := FileAccess.open(f, FileAccess.WRITE)
		h.store_string("")
		h = null
	var wallet := Wallet.new(WALLET_FILE)
	var garage := GarageState.new(GARAGE_FILE)
	_check(wallet.bank == 0, "a new wallet should be empty")

	var r := garage.buy(tree, "service", wallet, {})
	_check(not r.ok and r.reason == "bank" and garage.owned(tree).is_empty(), "an empty bank should refuse: %s" % str(r))
	wallet.deposit_bank(50000)
	r = garage.buy(tree, "turbo", wallet, {})
	_check(not r.ok and r.reason == "needs service" and wallet.bank == 50000, "a node without its parent should be refused: %s" % str(r))
	_check(garage.buy(tree, "service", wallet, {}).ok, "buying service failed")
	_check(wallet.bank == 50000 - tree.price("service"), "service not paid from the bank: %d" % wallet.bank)
	_check(not garage.buy(tree, "service", wallet, {}).ok, "buying an owned node should be refused")
	_check(not garage.buy(tree, "turbo_unknown", wallet, {}).ok, "unknown node bought")
	_check(garage.why_not_buy(tree, "big_turbo_grip", wallet, 5) == "needs big_turbo", "capstone without its L2 should need it")
	_check(garage.why_not_buy(tree, "turbo", wallet, 0) == "band", "band gate not checked")

	# turbo engine, tune it
	r = garage.buy(tree, "turbo", wallet, {"final_drive": 4.1})
	_check(r.ok and r.tune.is_empty(), "first turbo fit should hand back a fresh tune: %s" % str(r))
	var turbo_tune := {"final_drive": 3.6, "rear_arb_ratio": 0.3, "max_torque": 800.0}
	# NA engine: fresh tune; the turbo tune is kept without its owned path
	var bank_before := wallet.bank
	r = garage.buy(tree, "na", wallet, turbo_tune)
	_check(r.ok and r.tune.is_empty(), "first NA fit should be a fresh tune: %s" % str(r))
	_check(wallet.bank == bank_before - tree.price("na"), "NA not paid")
	_check(garage.fitted(tree) == ["service", "na"], "fitted after NA: %s" % str(garage.fitted(tree)))
	var na_tune := {"final_drive": 4.6}
	# swap back to turbo: free, the turbo tune comes back (minus torque)
	bank_before = wallet.bank
	r = garage.fit(tree, "turbo", na_tune)
	_check(r.ok and wallet.bank == bank_before, "swapping to an owned node should be free")
	_check(r.tune.get("final_drive") == 3.6 and r.tune.get("rear_arb_ratio") == 0.3 and not r.tune.has("max_torque"), "turbo tune not restored: %s" % str(r.tune))
	r = garage.fit(tree, "na", r.tune)
	_check(r.tune.get("final_drive") == 4.6, "NA tune not restored: %s" % str(r.tune))
	# deeper: screamer, then refit na keeps screamer fitted; fitting service keeps the chain below
	r = garage.buy(tree, "screamer", wallet, r.tune)
	_check(r.ok and r.tune.is_empty() and garage.fitted(tree) == ["service", "na", "screamer"], "screamer: %s %s" % [str(r), str(garage.fitted(tree))])
	r = garage.fit(tree, "na", r.tune)
	_check(garage.fitted(tree) == ["service", "na", "screamer"] and r.tune.is_empty(), "refitting na should keep screamer and its tune")
	r = garage.unfit(tree, "screamer", {"final_drive": 3.9})
	_check(r.ok and garage.fitted(tree) == ["service", "na"] and r.tune.get("final_drive") == 4.6, "unfit screamer should go back to the NA tune: %s" % str(r))
	_check(not garage.fit(tree, "big_turbo", {}).ok, "fitting an unowned node should fail")
	# parts
	bank_before = wallet.bank
	_check(garage.buy_part(tree, "tyres", wallet) and garage.part_step(tree, "tyres") == 1, "tyres step 1")
	_check(wallet.bank == bank_before - tree.part_price("tyres", 0), "tyres not paid")
	_check(garage.buy_part(tree, "tyres", wallet) and not garage.buy_part(tree, "tyres", wallet), "tyres should stop at step 2")
	var poor := Wallet.new("user://autotune/test_mod_tree_poor.json")
	poor.bank = 0
	_check(not garage.buy_part(tree, "brakes", poor) and garage.part_step(tree, "brakes") == 0, "a part bought with no Cred")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://autotune/test_mod_tree_poor.json"))
	# base build follows the garage
	var base := garage.base_spec(tree, stock)
	_check(base.max_rpm == stock.max_rpm + 500.0 and base.coefficient_of_friction.Road > stock.coefficient_of_friction.Road, "garage base build does not show NA + semi-slicks")
	# disk
	var again := GarageState.new(GARAGE_FILE)
	_check(again.owned(tree).size() == 4 and again.fitted(tree) == ["service", "na"] and again.part_step(tree, "tyres") == 2, "garage not read back: %s" % str(again.cars))
	_check(again.car(tree.car_id).tunes.get("turbo", {}).get("final_drive") == 3.6, "kept turbo tune not read back")
	_check(Wallet.new(WALLET_FILE).bank == wallet.bank, "bank not read back")
	var corrupt := FileAccess.open(GARAGE_FILE, FileAccess.WRITE)
	corrupt.store_string("{ nope")
	corrupt = null
	_check(GarageState.new(GARAGE_FILE).cars.is_empty(), "a corrupt garage file should read as empty")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
