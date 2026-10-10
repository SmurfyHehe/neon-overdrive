extends SceneTree

# Mod tree (step T1): the template library, the shared file and every car's
# tree file are well formed, and every car that has a tree passes the rules,
# first the ones that need no driving, then on the hidden test track.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/car/mod_tree.gd
#
# Data rules (seconds):
#   - every op's path is a property of the car or a known spec key
#   - no two fitted nodes set one path unless the later says override / replaces
#   - a node changes a number or a sound; no node turns a driven axle on or off
#   - every finished build, fully fitted, lands in the tier its file says and
#     never over the car's ceiling (T5 only on the named big-single builds)
#   - build_base() is order-free, leaves its input alone, survives a broken
#     save, and costs well under 1 ms
# Track rules (a few minutes; MOD_TREE_ONLY=data skips them, =track runs only them):
#   - every node moves its measure number past its threshold
#   - every finished build has something over every other one at launch, top
#     speed, the 100-200 pull, braking or cornering (eight builds cannot each win one of four
#     outright, so the rule checked is that none is level-or-behind another
#     everywhere), and each of the five has a winner
#   - the car's showcase path is its quickest measured 0-200 km/h
# MOD_TREE_CARS (comma list) limits the cars; MOD_TREE_OUT writes the tables.

const TIE := 0.002  # two builds within 0.2% on a metric are level
## The 100-200 pull is here beside the four asked for because top speed on the
## stock gears is set by the redline alone (the coupe has the power for far more
## than its gearing reaches), so a boost build can never win it.
const CATEGORIES := [["launch", "t_0_100", "less"], ["top speed", "top_speed_kmh", "more"], ["pull", "t_100_200", "less"], ["braking", "brake_dist_100", "less"], ["cornering", "peak_lat_g", "more"]]

var failures: Array[String] = []
var report: Array[String] = []

func _initialize() -> void:
	await process_frame
	var only := OS.get_environment("MOD_TREE_ONLY")
	var cars: Array = []
	for p in OS.get_environment("MOD_TREE_CARS").split(",", false):
		cars.append(p.strip_edges())
	if cars.is_empty():
		for id in PlayerCars.ids():
			if ModTree.has_tree(id):
				cars.append(id)
	_check(not cars.is_empty(), "no car has a tree file")
	if only != "track":
		_library()
		_negative()
		for car in cars:
			_data(car)
		_cost(cars)
	if only != "data":
		var track := TuneTrack.new()
		root.add_child(track)
		await process_frame
		for car in cars:
			await _track(track, car)
	var out := OS.get_environment("MOD_TREE_OUT")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(PackedStringArray(report)) + "\n")
			f.close()
	if failures.is_empty():
		print("mod_tree: PASS")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _say(line: String) -> void:
	print(line)
	report.append(line)

# ---- Data ---------------------------------------------------------------------

func _library() -> void:
	for msg in ModTree.validate_library():
		_check(false, msg)
	_check(ModTree.templates().size() >= 20, "about 20 templates, got %d" % ModTree.templates().size())
	for name in ModTree.templates():
		var t: Dictionary = ModTree.templates()[name]
		_check(String(t.get("icon", "")) != "" and String(t.get("minigame", "")) != "", "template %s: icon and minigame" % name)
	# Every boost kind the sim knows has a template that fits it.
	var kinds := {}
	for name in ModTree.templates():
		for op in ModTree.templates()[name].get("ops", []):
			if op.get("path", "") == "boost_kind":
				kinds[op.set] = true
	for k in ForcedInduction.KIND_NAMES:
		_check(kinds.has(k), "no template fits boost kind '%s'" % k)

## The validator catches what it is there to catch (trees built in memory).
func _negative() -> void:
	var stock := CarSpec.player_spec("p1_coupe")
	var good := _mini_tree()
	_check(ModTree.validate_tree(ModTree.resolve(good), stock).is_empty(),
		"the in-memory tree should pass: %s" % str(ModTree.validate_tree(ModTree.resolve(good), stock)))
	# Two sets on one path with no override.
	var t := _mini_tree()
	t.nodes[4]["ops"] = [{"path": "turbo_gain", "set": 0.3}]
	t.nodes[4]["override"] = false
	_expect(t, stock, "both set turbo_gain")
	# ...and fine once the later node replaces the earlier one.
	t.nodes[4]["replaces"] = "B"
	_check(_problems(t, stock, "both set").is_empty(), "replaces should allow a second set")
	var spec := ModTree._assemble_tree(ModTree.resolve(t), stock, ["service", "B", "B1", "grip"])
	_check(is_equal_approx(float(spec.turbo_gain), 0.3), "the replacing node's number is the one fitted")
	_check(is_equal_approx(float(spec.vehicle_mass), float(stock.vehicle_mass) + 10.0), "a replaced node's ops are dropped (its +20 kg is gone, the pair's own +10 kg stays)")
	# A path the car does not have.
	t = _mini_tree()
	t.nodes[1]["ops"] = [{"path": "warp_drive", "set": 1.0}]
	_expect(t, stock, "'warp_drive' is not a property of the car")
	t = _mini_tree()
	t.nodes[1]["ops"] = [{"path": "coefficient_of_friction/Ice", "mul": 1.1}]
	_expect(t, stock, "no entry 'Ice'")
	t = _mini_tree()
	t.nodes[1]["ops"] = [{"path": "gear_ratios/9", "mul": 1.1}]
	_expect(t, stock, "past the end")
	# A driven axle switched on.
	t = _mini_tree()
	t.nodes[1]["ops"] = [{"path": "front_torque_split", "set": 0.4}]
	_expect(t, stock, "turns a driven axle on or off")
	# A node that changes nothing.
	t = _mini_tree()
	t.side.append({"id": "nothing", "level": "side", "template": "side_voice", "name": "Nothing", "feel": "Nothing.", "cost_nights": 0.1, "band_min": "T0"})
	_expect(t, stock, "changes neither a number nor a sound")
	# A build over the ceiling.
	t = _mini_tree()
	t.nodes[3]["ops"] = [{"path": "max_torque", "mul": 2.0}]
	_expect(t, stock, "over the car's T4 ceiling")
	# A boost kind the sim does not have.
	t = _mini_tree()
	t.nodes[2]["ops"] = [{"path": "boost_kind", "set": "nitrous"}]
	_expect(t, stock, "boost_kind must be set to one of")

## A small valid tree on the coupe: Service, forks A/B, one L2 each, one capstone.
func _mini_tree() -> Dictionary:
	var card := {"name": "N", "feel": "F.", "cost_nights": 1.0, "band_min": "T1"}
	var nodes: Array = [
		{"id": "service", "level": 0, "parent": "", "template": "service"},
		{"id": "A", "level": 1, "parent": "service", "template": "na_breathe"},
		{"id": "B", "level": 1, "parent": "service", "template": "turbo_small"},
		{"id": "A1", "level": 2, "parent": "A", "template": "na_stroker"},
		{"id": "B1", "level": 2, "parent": "B", "template": "turbo_twin"},
		{"id": "grip", "level": 3, "parent": ["A1", "B1"], "template": "capstone_grip"},
	]
	for n in nodes:
		n.merge(card)
	return {"version": 1, "car_id": "mini", "tier": "T3", "ceiling": "T4", "home": ["service", "A", "A1", "grip"],
		"showcase": ["service", "B", "B1", "grip"], "builds": {"A1": "T4", "B1": "T4"}, "nodes": nodes, "side": []}

func _problems(raw: Dictionary, stock: Dictionary, needle: String) -> Array:
	var hits: Array = []
	for msg in ModTree.validate_tree(ModTree.resolve(raw), stock):
		if needle in msg:
			hits.append(msg)
	return hits

func _expect(raw: Dictionary, stock: Dictionary, needle: String) -> void:
	_check(not _problems(raw, stock, needle).is_empty(), "the validator should say '%s'; it said %s" % [needle, str(ModTree.validate_tree(ModTree.resolve(raw), stock))])

func _data(car: String) -> void:
	var stock := CarSpec.player_spec(car)
	for msg in ModTree.validate(car, stock):
		_check(false, msg)
	var t := ModTree.tree(car)
	var paths := ModTree.finished_paths(car)
	_check(paths.size() == 8, "%s: 8 finished builds, got %d" % [car, paths.size()])
	_check(t.nodes.size() >= 8, "%s: at least 8 nodes, got %d" % [car, t.nodes.size()])

	# No boost anywhere on the stock car or before the fork.
	_check(float(stock.get("turbo_boost_max", 0.0)) <= 0.0 or car in ["p2_hothatch", "p3_tuner", "p6_crossover"],
		"%s: the stock car has boost" % car)
	var serviced := ModTree.build_base(stock, ModTree.fitted(car, [t.order[0]]))
	_check(is_equal_approx(float(serviced.get("turbo_boost_max", 0.0)), float(stock.get("turbo_boost_max", 0.0))), "%s: Service adds no boost" % car)

	# build_base: the input is left alone, the list's order does not matter.
	var before := var_to_str(stock)
	var full: Array = ModTree.showcase_fit(car).installed
	var a := ModTree.build(stock, ModTree.fitted(car, full))
	_check(var_to_str(stock) == before, "%s: build_base changed the stock spec" % car)
	_check(a.problems.is_empty(), "%s: the showcase build has problems %s" % [car, str(a.problems)])
	var reversed: Array = full.duplicate()
	reversed.reverse()
	var b := ModTree.build_base(stock, ModTree.fitted(car, reversed))
	_check(var_to_str(a.spec) == var_to_str(b), "%s: the order of the installed list changed the build" % car)
	_check(a.nodes.slice(0, 4) == t.showcase, "%s: the showcase fits its four core nodes in level order" % car)
	_check(var_to_str(ModTree.build_base(stock, ModTree.fitted(car, []))) == before, "%s: nothing fitted is the stock car" % car)

	# A broken save still gives a car, and says what it left off.
	var l2 := String(t.showcase[2])
	var broken := ModTree.build(stock, ModTree.fitted(car, [l2, "no_such_part", "tyres_2"]))
	_check(broken.nodes.is_empty() and broken.problems.size() == 2, "%s: an L2 with no parent and an unknown id are left off and reported, got %s" % [car, str(broken.problems)])
	_check(int(broken.rungs.tyres) == 2, "%s: the rest of a broken save is still fitted" % car)
	var both: Array = [t.order[0]]
	for id in t.order:
		if int(t.nodes[id].level) == 1:
			both.append(id)
	var two := ModTree.build(stock, ModTree.fitted(car, both))
	_check(two.nodes.size() == 2 and two.problems.size() >= 1, "%s: two forks fitted at once: one is used, the other reported" % car)

	# Windows: the base sits inside every window; better rungs never narrow one;
	# boost only where a boost node gives it.
	var prev := {}
	for rung in 4:
		var ids: Array = t.home.duplicate()
		if rung > 0:
			for part in ModTree.shared().ladder.parts:
				ids.append("%s_%d" % [part.id, rung])
		var built := ModTree.build(stock, ModTree.fitted(car, ids))
		for path in built.windows:
			var w: Array = built.windows[path]
			var base := TuneParams.get_value(built.spec, path)
			_check(w[0] <= base + 0.00001 and base <= w[1] + 0.00001, "%s rung %d: %s base %.3f outside its window %s" % [car, rung, path, base, str(w)])
			if prev.has(path) and path != "turbo_boost_max":
				_check(w[1] - w[0] >= prev[path] - 0.00001, "%s rung %d: %s window got narrower" % [car, rung, path])
			prev[path] = w[1] - w[0]
	for p in paths:
		var built := ModTree.build(stock, ModTree.fitted(car, p))
		var boosted := float(built.spec.get("turbo_boost_max", 0.0)) > 0.0
		var w: Array = built.windows.turbo_boost_max
		_check(boosted == (w[1] > 0.0), "%s %s: a boost slider needs a boost node, and a boost node gives one" % [car, str(p)])
		_check(boosted == built.spec.has("boost_kind"), "%s %s: a boosted build names its boost kind" % [car, str(p)])
		_check(not boosted or built.sound.has("turbo") or built.sound.has("blower"), "%s %s: a boost node has a sound" % [car, str(p)])
		if built.sound.has("turbo"):
			_check(built.spec.get("turbo_voice", {}) is Dictionary and not built.spec.get("turbo_voice", {}).is_empty(), "%s %s: the turbo sound reaches the spec" % [car, str(p)])

	# Prices: nights times the car's tier factor; everything fittable has one.
	var factor := float(ModTree.shared().tiers.price_factor[t.tier])
	for id in t.nodes:
		_check(is_equal_approx(ModTree.price_nights(car, id), float(t.nodes[id].cost_nights) * factor), "%s/%s: price" % [car, id])
	for id in full:
		_check(ModTree.price_nights(car, id) >= 0.0, "%s: '%s' has no price" % [car, id])
	_check(ModTree.price_nights(car, "no_such_part") < 0.0, "an unknown id has no price")

	# The fleet sheet names the tree and only real nodes and real look options.
	var fleet: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://docs/design/fleet/fleet.json"))
	for c in fleet.cars:
		if c.id != car:
			continue
		_check(String(c.get("tree", "")) == car, "%s: fleet.json has no \"tree\": \"%s\"" % [car, car])
		for node_id in c.get("tree_parts", {}):
			_check(t.nodes.has(node_id), "%s: fleet.json tree_parts names '%s', not a node" % [car, node_id])
			for part in c.tree_parts[node_id]:
				var bits: PackedStringArray = String(part).split(".")
				_check(bits.size() == 2 and c.options.get(bits[0], {}).has(bits[1]), "%s: fleet.json tree_parts '%s' is not a look option" % [car, part])

	_say("")
	_say("## %s: finished builds, fully fitted (path, side nodes, every Workshop item, top parts)" % car)
	_say("")
	_say("| Build | Nm | kg | Nm/kg | Tier | Path price, nights |")
	_say("|---|---|---|---|---|---|")
	for p in paths:
		var spec := ModTree.build_base(stock, ModTree.max_fit(car, p))
		var nights := 0.0
		for id in p:
			nights += ModTree.price_nights(car, id)
		_say("| %s | %.0f | %.0f | %.3f | %s | %.1f |" % ["/".join(PackedStringArray(p)), float(spec.max_torque) * ModTree.boost_mult(spec),
			float(spec.vehicle_mass), ModTree.nm_per_kg(spec), ModTree.tier_of(spec), nights])

## build_base once per spawn or swap: well under 1 ms a car.
func _cost(cars: Array) -> void:
	for car in cars:
		var stock := CarSpec.player_spec(car)
		var fit := ModTree.showcase_fit(car)
		ModTree.build_base(stock, fit)  # the first call reads the files
		# The quickest of five batches: other programs on the laptop only ever add time.
		var n := 200
		var per_build := INF
		var per_full := INF
		var t0 := 0
		for batch in 5:
			t0 = Time.get_ticks_usec()
			for i in n:
				ModTree.build_base(stock, fit)
			per_build = minf(per_build, float(Time.get_ticks_usec() - t0) / n)
			t0 = Time.get_ticks_usec()
			for i in n:
				ModTree.build(stock, fit)
			per_full = minf(per_full, float(Time.get_ticks_usec() - t0) / n)
		# A cold start: every cache dropped, files read again.
		ModTree.clear_cache()
		t0 = Time.get_ticks_usec()
		ModTree.build_base(stock, fit)
		var cold := float(Time.get_ticks_usec() - t0)
		_say("")
		_say("%s build cost, showcase fit (%d ids): build_base %.0f us, with windows %.0f us, first call with the three files read %.0f us" % [car, fit.installed.size(), per_build, per_full, cold])
		_check(per_build < 1000.0, "%s: build_base took %.0f us, the budget is under 1 ms" % [car, per_build])
		_check(per_full < 2000.0, "%s: build with windows took %.0f us" % [car, per_full])

# ---- Track --------------------------------------------------------------------

var _runs := {}
var _evals := 0

func _measure(track: TuneTrack, stock: Dictionary, car: String, ids: Array, kinds: Array = TuneTrack.ALL_KINDS) -> Dictionary:
	var key := "%s|%s|%d" % [car, ",".join(PackedStringArray(ids)), kinds.size()]
	if not _runs.has(key):
		_runs[key] = (await track.evaluate([ModTree.build_base(stock, ModTree.fitted(car, ids))], kinds))[0]
		_evals += 1
	return _runs[key]

func _track(track: TuneTrack, car: String) -> void:
	var stock := CarSpec.player_spec(car)
	var t := ModTree.tree(car)
	var paths := ModTree.finished_paths(car)
	var t0 := Time.get_ticks_msec()
	# The track's usual bend (steer 0.3). The bolt-on sweep's harder 0.7 was picked
	# for the Bug; at 0.7 the coupe spins, and a spin reads as neither grip nor slide.
	track.corner_steer = float(OS.get_environment("MOD_TREE_STEER")) if OS.get_environment("MOD_TREE_STEER") != "" else TuneTrack.CORNER_STEER
	track.driver_profile = TuneTrack.DEFAULT_PROFILE

	# Every node against the same build without it.
	_say("")
	_say("## %s: every node against the same build without it" % car)
	_say("")
	_say("| Node | On top of | Test | Without | With | Gain | Needs | |")
	_say("|---|---|---|---|---|---|---|---|")
	var done := {}
	for p in paths:
		for i in p.size():
			var with_ids: Array = p.slice(0, i + 1)
			var key := ",".join(PackedStringArray(with_ids))
			if done.has(key):
				continue
			done[key] = true
			await _node_row(track, stock, car, String(p[i]), p.slice(0, i), with_ids)
	for id in t.side:
		var n: Dictionary = t.nodes[id]
		if n.get("ops", []).is_empty():
			continue  # sound only: nothing to measure
		var under: Array = [t.order[0]]
		var req := String(n.get("requires", ""))
		if req != "":
			under = _chain_to(paths, req)
		await _node_row(track, stock, car, id, under, under + [id])

	# The eight finished builds against each other.
	_say("")
	_say("## %s: the finished builds (core path only, stock parts)" % car)
	_say("")
	_say("| Build | 0-100 s | 400 m s | 100-200 s | Top km/h | 100-0 m | Corner g | Turn m | Best at |")
	_say("|---|---|---|---|---|---|---|---|---|")
	var ms: Array = []
	for p in paths:
		var m: Dictionary = await _measure(track, stock, car, p)
		_check(m.ok, "%s %s: the track run had problems %s" % [car, str(p), str(m.problems)])
		ms.append(m)
	for i in paths.size():
		var wins: Array = []
		for c in CATEGORIES:
			var best := true
			for j in paths.size():
				if j != i and _cmp(ms[j], ms[i], c) > 0:
					best = false
			if best:
				wins.append(c[0])
		var beaten_by := ""
		for j in paths.size():
			if j == i:
				continue
			# Beaten: the other build is at least level everywhere and ahead somewhere.
			var never_behind := true
			var ahead := false
			for c in CATEGORIES:
				var d := _cmp(ms[j], ms[i], c)
				never_behind = never_behind and d >= 0
				ahead = ahead or d > 0
			if never_behind and ahead:
				beaten_by = "/".join(PackedStringArray(paths[j]))
		_check(beaten_by == "", "%s %s: has nothing over %s at launch, top speed, pull, braking or cornering" % [car, "/".join(PackedStringArray(paths[i])), beaten_by])
		var m: Dictionary = ms[i]
		_say("| %s | %s | %s | %s | %s | %s | %s | %s | %s |" % ["/".join(PackedStringArray(paths[i])), _f(m.get("t_0_100", NAN), 2), _f(m.get("t_400", NAN), 2),
			_f(m.get("t_100_200", NAN), 2), _f(m.get("top_speed_kmh", NAN), 0), _f(m.get("brake_dist_100", NAN), 1), _f(m.get("peak_lat_g", NAN), 2),
			_f(m.get("turn_radius_m", NAN), 1), ", ".join(PackedStringArray(wins)) if not wins.is_empty() else ("beaten by " + beaten_by if beaten_by != "" else "-")])
	for c in CATEGORIES:
		var someone := false
		for i in paths.size():
			var best := true
			for j in paths.size():
				if j != i and _cmp(ms[j], ms[i], c) > 0:
					best = false
			someone = someone or best
		_check(someone, "%s: nobody wins %s" % [car, c[0]])

	# The showcase: quickest 0-200 with everything fitted.
	_say("")
	_say("## %s: 0-200 km/h with everything fitted (the showcase is the quickest)" % car)
	_say("")
	_say("| Build | 0-100 s | 0-200 s | Top km/h |")
	_say("|---|---|---|---|")
	var best_path: Array = []
	var best_t := INF
	for p in paths:
		var m: Dictionary = await _measure(track, stock, car, ModTree.max_fit(car, p).installed, [TuneTrack.Kind.ACCEL])
		_check(m.ok, "%s %s fully fitted: the track run had problems %s" % [car, str(p), str(m.problems)])
		var t200 := float(m.get("t_0_200", INF))
		_say("| %s | %s | %s | %s |" % ["/".join(PackedStringArray(p)), _f(m.get("t_0_100", NAN), 2), _f(t200, 2), _f(m.get("top_speed_kmh", NAN), 0)])
		if t200 < best_t:
			best_t = t200
			best_path = p
	_check(is_finite(best_t), "%s: no fully fitted build reaches 200 km/h" % car)
	_check(best_path == t.showcase, "%s: the quickest 0-200 is %s (%.2f s), the file's showcase is %s" % [car, str(best_path), best_t, str(t.showcase)])
	_say("")
	_say("%s: %d track evaluations in %.0f s." % [car, _evals, (Time.get_ticks_msec() - t0) / 1000.0])
	track.corner_steer = TuneTrack.CORNER_STEER

func _node_row(track: TuneTrack, stock: Dictionary, car: String, id: String, without_ids: Array, with_ids: Array) -> void:
	var n := ModTree.node(car, id)
	var a: Dictionary = await _measure(track, stock, car, without_ids)
	var b: Dictionary = await _measure(track, stock, car, with_ids)
	_check(a.ok and b.ok, "%s/%s: a track run had problems %s %s" % [car, id, str(a.problems), str(b.problems)])
	var r := ModTree.measure_result(n.get("measure", {}), b, a)
	_check(r.ok, "%s/%s on %s: %s moved %s %s, it needs %s" % [car, id, "/".join(PackedStringArray(without_ids)), r.test, _f(r.gain, 2), r.unit, _f(r.need, 2)])
	_say("| %s (%s) | %s | %s | %s | %s | %s %s | %s %s | %s |" % [id, n.get("name", ""), "/".join(PackedStringArray(without_ids)) if not without_ids.is_empty() else "stock",
		r.test, _f(a.get(r.metric, NAN), 2), _f(b.get(r.metric, NAN), 2), _f(r.gain, 2), r.unit, _f(r.need, 2), r.unit, "ok" if r.ok else "FAIL"])

func _chain_to(paths: Array, id: String) -> Array:
	for p in paths:
		var at: int = p.find(id)
		if at >= 0:
			return p.slice(0, at + 1)
	return []

## > 0 if `a` beats `b` in the category by more than a tie, < 0 if it loses, 0 if level.
func _cmp(a: Dictionary, b: Dictionary, c: Array) -> int:
	var x := float(a.get(c[1], NAN))
	var y := float(b.get(c[1], NAN))
	if not is_finite(x) or not is_finite(y):
		return 0
	var d := (y - x) if c[2] == "less" else (x - y)
	if absf(d) <= TIE * maxf(absf(x), absf(y)):
		return 0
	return 1 if d > 0.0 else -1

func _f(v: float, places: int) -> String:
	if not is_finite(v):
		return "-"
	return ("%." + str(places) + "f") % v
