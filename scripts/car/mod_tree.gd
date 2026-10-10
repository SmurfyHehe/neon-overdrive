class_name ModTree
extends RefCounted

# The mod tree (step T1, 2026-10-10): what kind of car a car becomes. The data
# is data/mod_trees/: _templates.json (the node kinds, written relative to the
# car), _shared.json (tiers, prices, the Workshop row, the parts ladder) and one
# <car_id>.json per car (which template each slot uses, its own numbers, card
# lines, prices). This file reads them, checks them and builds the car.
#
#   var fitted := ModTree.fitted("p1_coupe", ["service", "B", "B1", "grip", "ecu_unlock", "tyres_2"])
#   var base := ModTree.build_base(CarSpec.player_spec("p1_coupe"), fitted)
#
# `installed` is the save's own list (save_store.gd, mod_tree.json): tree node
# ids, Workshop (bolt-on) item ids, parts ladder rungs ("tyres_2") and options
# ("compound_sport") together. The order of the list does not matter; the build
# order is fixed:
#
#   stock -> core nodes by level (Service, Fork, L2, capstone) -> side nodes
#         -> Workshop items -> ladder rungs and their option  = the BASE BUILD
#
# The player's tune then goes on top through CarSpec.set_param, inside
# windows(). Applied once per spawn or swap: nothing here runs per frame, and
# only the spawned car's file is parsed (and kept).
#
# Not wired into the game's car, the Tuner or the save yet. Rival cars use the
# same call with the rival's named path; traffic and cops never come here.

const DIR := "res://data/mod_trees/"
const OP_KINDS := ["set", "add", "mul", "mul_redline"]
const THRESHOLDS := ["better_by_pct", "better_by_s", "better_by_m", "better_by_deg"]
## Spec keys a node may write that are not properties of the car.
const TORQUE_SHAPE_KEYS := ["low_end", "peak_pos", "plateau", "falloff"]
const LEVEL_NAMES := ["Service", "Fork", "L2", "Capstone"]

static var _templates: Dictionary = {}
static var _shared: Dictionary = {}
static var _trees: Dictionary = {}       # car_id -> resolved tree ({} = no file)
static var _props: Dictionary = {}       # PlayerCar property -> its default
static var _bolt_ons: Dictionary = {}    # item id -> item
static var _bolt_on_order: Array = []
static var _ladder_ids: Dictionary = {}  # every rung id and option id

# ---- Loading ---------------------------------------------------------------

static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("ModTree: cannot read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("ModTree: %s is not a JSON object" % path)
	return {}

static func library() -> Dictionary:
	if _templates.is_empty():
		_templates = _read_json(DIR + "_templates.json")
	return _templates

static func templates() -> Dictionary:
	return library().get("templates", {})

static func shared() -> Dictionary:
	if _shared.is_empty():
		_shared = _read_json(DIR + "_shared.json")
		var ladder: Dictionary = _shared.get("ladder", {})
		for part in ladder.get("parts", []):
			var runs: Array = []
			for ops in part.get("ops", []):
				runs.append(_compile_all(ops))
			part["_run"] = runs
			var ids: Array = [""]
			for n in range(1, part.get("rungs", []).size()):
				ids.append("%s_%d" % [part.id, n])
			part["_ids"] = ids
			for id in ids:
				_ladder_ids[id] = true
		for opt in ladder.get("options", {}):
			if ladder.options[opt] is Dictionary:
				for c in ladder.options[opt]:
					if ladder.options[opt][c] is Dictionary:
						ladder.options[opt][c]["_run"] = _compile_all(ladder.options[opt][c].get("ops", []))
						_ladder_ids["%s_%s" % [opt, c]] = true
	return _shared

static func has_tree(car_id: String) -> bool:
	return car_id != "" and not car_id.begins_with("_") and FileAccess.file_exists(DIR + car_id + ".json")

## The car's tree with every node resolved (its template with the car's fields
## laid over it): {car_id, tier, ceiling, home, showcase, builds, nodes {id:
## node}, order [core ids, level by level], side [ids]}. Empty if the car has
## no tree file. Parsed once and kept.
static func tree(car_id: String) -> Dictionary:
	if not _trees.has(car_id):
		_trees[car_id] = resolve(_read_json(DIR + car_id + ".json")) if has_tree(car_id) else {}
	return _trees[car_id]

## Resolves a raw tree file's contents (tests hand in their own).
static func resolve(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return {}
	var out := {"car_id": String(raw.get("car_id", "")), "tier": String(raw.get("tier", "")), "ceiling": String(raw.get("ceiling", "")),
		"home": raw.get("home", []), "showcase": raw.get("showcase", []), "builds": raw.get("builds", {}),
		"nodes": {}, "order": [], "side": []}
	var by_level: Array = [[], [], [], []]
	for n in raw.get("nodes", []):
		var node := _resolve_node(n)
		out.nodes[node.id] = node
		var lv: Variant = node.get("level", -1)
		if (lv is float or lv is int) and int(lv) >= 0 and int(lv) < by_level.size():
			by_level[int(lv)].append(node.id)
	for ids in by_level:
		out.order.append_array(ids)
	for n in raw.get("side", []):
		var node := _resolve_node(n)
		node["level"] = "side"
		out.nodes[node.id] = node
		out.side.append(node.id)
	return out

static func _resolve_node(raw: Dictionary) -> Dictionary:
	var t: Dictionary = templates().get(String(raw.get("template", "")), {})
	var node: Dictionary = t.duplicate(true)
	node.erase("_note")
	for key in raw:
		if key == "ops":
			continue
		if key == "sound" and node.get("sound") is Dictionary:
			node["sound"].merge(raw[key], true)
		else:
			node[key] = raw[key]
	# The car's op on a path replaces the template's op on that path.
	var ops: Array = node.get("ops", [])
	for op in raw.get("ops", []):
		var at := -1
		for i in ops.size():
			if ops[i].get("path", "") == op.get("path", ""):
				at = i
				break
		if at >= 0:
			ops[at] = op
		else:
			ops.append(op)
	node["ops"] = ops
	node["_run"] = _compile_all(ops)
	node["id"] = String(raw.get("id", ""))
	return node

static func node(car_id: String, id: String) -> Dictionary:
	return tree(car_id).get("nodes", {}).get(id, {})

## Forgets everything read so far (tests that edit data, a future hot reload).
static func clear_cache() -> void:
	_templates = {}
	_shared = {}
	_trees = {}
	_bolt_ons = {}
	_bolt_on_order = []

# ---- Fitted builds ---------------------------------------------------------

static func fitted(car_id: String, installed: Array) -> Dictionary:
	return {"car": car_id, "installed": installed}

## The base build's spec: `stock` (CarSpec.player_spec, left alone) with
## everything in `fitted` applied in the fixed order. A car with no tree gets
## its Workshop items and ladder rungs only.
static func build_base(stock: Dictionary, fitted_build: Dictionary) -> Dictionary:
	return _assemble(stock, fitted_build, false).spec

## The same build with what the rest of the game reads from it:
##   spec      the base build
##   windows   {path: [lo, hi]} how far each Tuner slider may move (presets ignore them)
##   sound     the fitted nodes' sound hooks, later nodes over earlier ones
##   effects   the Workshop items' non-sim levers (BoltOns.effects)
##   nodes     the tree nodes applied, in order; bolt_ons, rungs {part: n}, compound
##   problems  anything in `installed` that could not be fitted, in plain words
static func build(stock: Dictionary, fitted_build: Dictionary) -> Dictionary:
	return _assemble(stock, fitted_build, true)

static func _assemble(stock: Dictionary, fitted_build: Dictionary, with_windows: bool) -> Dictionary:
	var car_id := String(fitted_build.get("car", ""))
	var want := {}
	for id in fitted_build.get("installed", []):
		want[String(id)] = true
	# A deep copy: the spec holds numbers, strings, arrays and dictionaries only.
	var spec := stock.duplicate(true)
	var out := {"spec": spec, "windows": {}, "sound": {}, "effects": {}, "nodes": [], "bolt_ons": [], "rungs": {}, "compound": "", "problems": []}
	var t := tree(car_id)
	var node_windows := {}
	if not t.is_empty():
		var chain := _chain(t, want, out.problems)
		var dropped := {}
		for id in chain:
			var r := String(t.nodes[id].get("replaces", ""))
			if r != "":
				dropped[r] = true
		var applied: Array = []
		for id in chain:
			if not dropped.has(id):
				applied.append(id)
		for id in t.side:
			if not want.has(id):
				continue
			var req := String(t.nodes[id].get("requires", ""))
			if req != "" and not (req in chain):
				out.problems.append("%s needs %s fitted" % [id, req])
				continue
			applied.append(id)
		for id in applied:
			var n: Dictionary = t.nodes[id]
			for c in n._run:
				_run(spec, c)
			out.sound.merge(n.get("sound", {}), true)
			node_windows.merge(n.get("tuner_window", {}), true)
		out.nodes = applied
		if out.sound.has("turbo"):
			var preset: Variant = library().get("sounds", {}).get("turbo", {}).get(String(out.sound.turbo))
			if preset is Dictionary:
				spec["turbo_voice"] = TurboVoice.build(preset)
	# Workshop row
	_load_bolt_ons()
	for id in _bolt_on_order:
		if not want.has(id):
			continue
		var it: Dictionary = _bolt_ons[id]
		for c in it._run:
			_run(spec, c)
		if with_windows:
			_merge_effects(out.effects, it.get("effects", {}))
		out.bolt_ons.append(id)
	# Parts ladder
	var ladder: Dictionary = shared().get("ladder", {})
	for part in ladder.get("parts", []):
		var rung := 0
		var rung_ids: Array = part._ids
		for n in range(rung_ids.size() - 1, 0, -1):
			if want.has(rung_ids[n]):
				rung = n
				break
		out.rungs[part.id] = rung
		for c in part._run[rung]:
			_run(spec, c)
		if part.has("option"):
			var opt := String(part.option)
			var unlocked: Array = part.unlocks[rung]
			var pick := String(unlocked[unlocked.size() - 1])
			for c in unlocked:
				if want.has(opt + "_" + c):
					pick = String(c)
			for c in ladder.options[opt][pick]._run:
				_run(spec, c)
			out[opt] = pick
	if with_windows:
		for id in want:
			if not t.get("nodes", {}).has(id) and not _bolt_ons.has(id) and not _ladder_ids.has(id):
				out.problems.append("%s: nothing by that name fits this car" % id)
		out.windows = _windows(spec, out.rungs, node_windows)
	return out

## The fitted core nodes as a chain from Service down, one per level. A node
## whose parent is not fitted, or a second node at a level, is left off (and
## said so): a broken save still gives a car that drives.
static func _chain(t: Dictionary, want: Dictionary, problems: Array) -> Array:
	var chain: Array = []
	var prev := ""
	var level := 0
	var open := true
	for id in t.order:
		if not want.has(id):
			continue
		var n: Dictionary = t.nodes[id]
		var lv := int(n.level)
		if lv < level:
			problems.append("%s: a %s node is already fitted" % [id, LEVEL_NAMES[lv]])
			continue
		if not open or lv > level or not _is_parent(n, prev):
			problems.append("%s: its parent is not fitted" % id)
			open = open and lv <= level
			continue
		chain.append(id)
		prev = id
		level = lv + 1
	return chain

static func _is_parent(n: Dictionary, prev: String) -> bool:
	var p: Variant = n.get("parent", "")
	return (prev in p) if p is Array else String(p) == prev

## One op on a spec, in place. {"path", "set" | "add" | "mul" | "mul_redline"}.
static func apply_op(spec: Dictionary, op: Dictionary) -> void:
	_run(spec, _compile(op))

const _SET := 0
const _ADD := 1
const _MUL := 2
const _REDLINE := 3
const _TEXT := 4

## An op as [key, sub (null, a list index or a dictionary key), kind, value],
## worked out once when the file is read so fitting a car is a short loop.
static func _compile(op: Dictionary) -> Array:
	var path := String(op.path)
	var slash := path.find("/")
	var key := path if slash < 0 else path.substr(0, slash)
	var sub: Variant = null
	if slash >= 0:
		var s := path.substr(slash + 1)
		sub = int(s) if s.is_valid_int() else s
	if op.has("set"):
		return [key, sub, _TEXT, op.set] if op.set is String else [key, sub, _SET, float(op.set)]
	if op.has("add"):
		return [key, sub, _ADD, float(op.add)]
	if op.has("mul"):
		return [key, sub, _MUL, float(op.mul)]
	return [key, sub, _REDLINE, float(op.get("mul_redline", 0.0))]

static func _compile_all(ops: Array) -> Array:
	var out: Array = []
	for op in ops:
		if op is Dictionary and op.has("path"):
			out.append(_compile(op))
	return out

static func _run(spec: Dictionary, c: Array) -> void:
	var key: String = c[0]
	var kind: int = c[2]
	if kind == _TEXT:
		spec[key] = c[3]
		return
	var sub: Variant = c[1]
	var x: float = c[3]
	if kind == _REDLINE:
		x *= float(spec["max_rpm"]) if spec.has("max_rpm") else float(_default("max_rpm"))
	if sub == null:
		if kind == _ADD:
			x += float(spec[key]) if spec.has(key) else float(_default(key))
		elif kind == _MUL:
			x *= float(spec[key]) if spec.has(key) else float(_default(key))
		spec[key] = x
		return
	if not spec.has(key):
		spec[key] = CarSpec.DEFAULT_TORQUE_SHAPE.duplicate() if key == "torque_shape" else CarSpec._own(_default(key))
	var holder: Variant = spec[key]
	if kind == _ADD:
		x += float(holder[sub])
	elif kind == _MUL:
		x *= float(holder[sub])
	holder[sub] = x

static func _windows(spec: Dictionary, rungs: Dictionary, node_windows: Dictionary) -> Dictionary:
	var out := {}
	var ladder: Dictionary = shared().get("ladder", {})
	var notches: Array = ladder.get("notches", [])
	for part in ladder.get("parts", []):
		var n := int(notches[int(rungs.get(part.id, 0))])
		for path in part.paths:
			var e: Dictionary = _tune_entry(path)
			if e.is_empty():
				continue
			var lo: float = e.min
			var hi: float = e.max
			var base := TuneParams.get_value(spec, path)
			if n >= 0:
				var step := (hi - lo) / 10.0
				lo = maxf(lo, base - n * step)
				hi = minf(hi, base + n * step)
			# The base build always sits inside its own window.
			out[path] = [minf(lo, base), maxf(hi, base)]
	# Boost belongs to the turbo node; no boost node, no boost slider.
	out["turbo_boost_max"] = [0.0, 0.0]
	for path in node_windows:
		out[path] = [float(node_windows[path][0]), float(node_windows[path][1])]
	return out

static var _tune_entries: Dictionary = {}

## TuneParams.find() without the walk down the list.
static func _tune_entry(path: String) -> Dictionary:
	if _tune_entries.is_empty():
		for e in TuneParams.all():
			_tune_entries[e.path] = e
	return _tune_entries.get(path, {})

# ---- Workshop row (bolt-ons) -----------------------------------------------

static func _load_bolt_ons() -> void:
	if not _bolt_on_order.is_empty():
		return
	for it in BoltOns.items():
		var deltas: Dictionary = it.get("deltas", {})
		var runs: Array = []
		for key in deltas:
			runs.append(_compile({"path": key, String(deltas[key][0]): deltas[key][1]}))
		it["_run"] = runs
		_bolt_ons[it.id] = it
		_bolt_on_order.append(it.id)

## Same rule as BoltOns.effects(): *_mul multiply, flags or, other numbers add.
static func _merge_effects(into: Dictionary, fx: Dictionary) -> void:
	for key in fx:
		var val: Variant = fx[key]
		if not into.has(key):
			into[key] = val
		elif val is bool:
			into[key] = bool(into[key]) or bool(val)
		elif String(key).ends_with("_mul"):
			into[key] = float(into[key]) * float(val)
		else:
			into[key] = float(into[key]) + float(val)

## Every Workshop item at once: a stepped item counts as its top step only.
static func all_bolt_ons() -> Array:
	_load_bolt_ons()
	var top := {}
	for id in _bolt_on_order:
		var it: Dictionary = _bolt_ons[id]
		if it.has("step_of"):
			top[it.step_of] = maxi(int(top.get(it.step_of, 0)), int(it.step))
	var out: Array = []
	for id in _bolt_on_order:
		var it: Dictionary = _bolt_ons[id]
		if not it.has("step_of") or int(it.step) == int(top[it.step_of]):
			out.append(id)
	return out

# ---- Paths, builds, the showcase --------------------------------------------

## The finished builds: every chain from Service to a capstone (8 on a full tree).
static func finished_paths(car_id: String) -> Array:
	return _finished_paths(tree(car_id))

static func _finished_paths(t: Dictionary) -> Array:
	var out: Array = []
	if t.is_empty():
		return out
	var open: Array = [[]]
	for level in LEVEL_NAMES.size():
		var next: Array = []
		for chain in open:
			var prev := "" if chain.is_empty() else String(chain[chain.size() - 1])
			for id in t.order:
				var n: Dictionary = t.nodes[id]
				if int(n.level) == level and _is_parent(n, prev):
					next.append(chain + [id])
		open = next
	return open

## A path with everything else the car can carry: its side nodes, every
## Workshop item and the top rung of every part.
static func max_fit(car_id: String, path: Array) -> Dictionary:
	var t := tree(car_id)
	var ids: Array = path.duplicate()
	for id in t.get("side", []):
		var req := String(t.nodes[id].get("requires", ""))
		if req == "" or req in path:
			ids.append(id)
	ids.append_array(all_bolt_ons())
	for part in shared().get("ladder", {}).get("parts", []):
		ids.append("%s_%d" % [part.id, part.rungs.size() - 1])
	return fitted(car_id, ids)

## What the car wears until the garage exists: its showcase path (the build
## with the best measured 0-200 km/h, named in the car's file and re-measured
## by tests/car/mod_tree_track.gd) with everything else fitted.
static func showcase_fit(car_id: String) -> Dictionary:
	var t := tree(car_id)
	return fitted(car_id, []) if t.is_empty() else max_fit(car_id, t.showcase)

# ---- Tiers and prices --------------------------------------------------------

## Torque multiplier at full boost for the spec's boost setup (ForcedInduction's
## own numbers), 1 with no boost.
static func boost_mult(spec: Dictionary) -> float:
	if float(spec.get("turbo_boost_max", 0.0)) <= 0.0:
		return 1.0
	var gain := float(spec.get("turbo_gain", _default("turbo_gain")))
	match ForcedInduction.valid_kind(String(spec.get("boost_kind", "single"))):
		"twin": return 1.0 + gain * ForcedInduction.TWIN_GAIN
		"roots": return 1.0 + gain * ForcedInduction.ROOTS_GAIN - ForcedInduction.ROOTS_DRAG
	return 1.0 + gain

## Peak torque on full boost per kg: the number the tier bands are written in.
static func nm_per_kg(spec: Dictionary) -> float:
	return float(spec.max_torque) * boost_mult(spec) / float(spec.vehicle_mass)

static func tier_names() -> Array:
	return shared().get("tiers", {}).get("names", [])

## 0 (T0) to 5 (T5).
static func tier_index(spec: Dictionary) -> int:
	var floors: Array = shared().get("tiers", {}).get("floor_nm_per_kg", [])
	var x := nm_per_kg(spec)
	var idx := 0
	for i in floors.size():
		if x >= float(floors[i]):
			idx = i
	return idx

static func tier_of(spec: Dictionary) -> String:
	return String(tier_names()[tier_index(spec)])

## The price of anything that can be in `installed`, in nights of play: its own
## nights times the car's tier factor. -1 for an id nothing sells.
static func price_nights(car_id: String, id: String) -> float:
	var t := tree(car_id)
	var car_tier := String(t.get("tier", "")) if not t.is_empty() else String(PlayerCars.info(car_id).tier)
	var factor := float(shared().get("tiers", {}).get("price_factor", {}).get(car_tier, 1.0))
	if t.get("nodes", {}).has(id):
		return float(t.nodes[id].get("cost_nights", 0.0)) * factor
	_load_bolt_ons()
	var shop: Dictionary = shared().get("workshop", {})
	if _bolt_ons.has(id):
		return float(shop.get("nights", {}).get(id, shop.get("default_nights", 0.0))) * factor
	for part in shared().get("ladder", {}).get("parts", []):
		for n in range(1, part.rungs.size()):
			if id == "%s_%d" % [part.id, n]:
				return float(part.cost_nights[n]) * factor
	return -1.0

static func price_cred(car_id: String, id: String) -> int:
	var nights := price_nights(car_id, id)
	return -1 if nights < 0.0 else roundi(nights * float(shared().get("cred_per_night", 1000)))

## The paths the tree owns (hardware): the Tuner stops showing them and saved
## tunes stop storing them once the tree is wired in.
static func owned_paths() -> Array:
	return shared().get("owners", {}).get("tree", [])

# ---- Measure rules -----------------------------------------------------------

## Whether a node moved its measure number far enough. `m_with` and `m_without` are
## TuneTrack metrics of the build with the node and of the same build without
## it. Returns {ok, test, metric, gain, need, unit}: gain and need in the rule's
## own unit (percent of the without number, or s / m / deg), positive = better.
static func measure_result(rule: Dictionary, m_with: Dictionary, m_without: Dictionary) -> Dictionary:
	var def: Dictionary = library().get("measures", {}).get(String(rule.get("test", "")), {})
	var out := {"ok": false, "test": String(rule.get("test", "")), "metric": String(def.get("metric", "")), "gain": NAN, "need": NAN, "unit": ""}
	if def.is_empty() or not m_with.has(def.metric) or not m_without.has(def.metric):
		return out
	var a := float(m_without[def.metric])
	var b := float(m_with[def.metric])
	var better := (a - b) if def.better == "less" else (b - a)
	for key in THRESHOLDS:
		if rule.has(key):
			out.unit = key.trim_prefix("better_by_")
			out.need = float(rule[key])
			out.gain = better / absf(a) * 100.0 if key == "better_by_pct" else better
			out.ok = is_finite(out.gain) and out.gain >= out.need
			break
	return out

# ---- Validator (no sim) ------------------------------------------------------

## The library and shared file on their own. Empty = fine.
static func validate_library() -> Array[String]:
	var bad: Array[String] = []
	var lib := library()
	var measures: Dictionary = lib.get("measures", {})
	if templates().is_empty():
		bad.append("_templates.json has no templates")
	for name in templates():
		_check_node_body(templates()[name], "template %s" % name, bad, {})
	for key in ["tiers", "workshop", "ladder", "owners"]:
		if not shared().has(key):
			bad.append("_shared.json: no '%s'" % key)
	var tiers: Dictionary = shared().get("tiers", {})
	var names: Array = tiers.get("names", [])
	if tiers.get("floor_nm_per_kg", []).size() != names.size():
		bad.append("_shared.json: one tier floor per tier name")
	for n in names:
		if not tiers.get("price_factor", {}).has(n):
			bad.append("_shared.json: no price factor for %s" % n)
	_load_bolt_ons()
	for id in shared().get("workshop", {}).get("nights", {}):
		if not _bolt_ons.has(id):
			bad.append("_shared.json workshop: '%s' is not a bolt-on" % id)
	var ladder: Dictionary = shared().get("ladder", {})
	for part in ladder.get("parts", []):
		var rungs: int = part.get("rungs", []).size()
		if rungs != ladder.get("notches", []).size() or part.get("ops", []).size() != rungs or part.get("cost_nights", []).size() != rungs:
			bad.append("ladder %s: rungs, ops, cost_nights and notches must be the same length" % part.get("id", "?"))
			continue
		for path in part.get("paths", []):
			if TuneParams.find(path).is_empty():
				bad.append("ladder %s: '%s' is not a Tuner path" % [part.id, path])
		for ops in part.ops:
			for op in ops:
				_check_op(op, "ladder %s" % part.id, bad, {})
		if part.has("option"):
			var choices: Dictionary = ladder.get("options", {}).get(String(part.option), {})
			for unlocked in part.get("unlocks", []):
				for c in unlocked:
					if not choices.has(c):
						bad.append("ladder %s: unknown %s '%s'" % [part.id, part.option, c])
	for opt in ladder.get("options", {}):
		if String(opt).begins_with("_"):
			continue
		for c in ladder.options[opt]:
			for op in ladder.options[opt][c].get("ops", []):
				_check_op(op, "%s %s" % [opt, c], bad, {})
	if measures.is_empty():
		bad.append("_templates.json has no measures")
	return bad

## A car's tree against the rules that need no test track. `stock` is the car's
## stock spec. Empty = fine.
static func validate(car_id: String, stock: Dictionary) -> Array[String]:
	if not has_tree(car_id):
		return ["%s has no tree file" % car_id]
	return validate_tree(tree(car_id), stock)

static func validate_tree(t: Dictionary, stock: Dictionary) -> Array[String]:
	var bad: Array[String] = []
	var car := String(t.get("car_id", "?"))
	var tiers: Dictionary = shared().get("tiers", {})
	var names: Array = tiers.get("names", [])
	# Shape
	var per_level := [0, 0, 0, 0]
	_load_bolt_ons()
	for id in t.nodes:
		var n: Dictionary = t.nodes[id]
		var who := "%s/%s" % [car, id]
		if id == "" or _bolt_ons.has(id) or _is_ladder_id(id):
			bad.append("%s: the id is empty or already a Workshop or ladder id" % who)
		if not templates().has(String(n.get("template", ""))):
			bad.append("%s: unknown template '%s'" % [who, n.get("template", "")])
		for key in ["name", "feel"]:
			if String(n.get(key, "")) == "":
				bad.append("%s: no %s" % [who, key])
		if not (n.get("cost_nights") is float) or float(n.cost_nights) < 0.0:
			bad.append("%s: cost_nights must be a number, 0 or more" % who)
		if not (String(n.get("band_min", "")) in names):
			bad.append("%s: band_min must be one of %s" % [who, str(names)])
		_check_node_body(n, who, bad, stock)
		if id in t.side:
			var req := String(n.get("requires", ""))
			if req != "" and not (req in t.order):
				bad.append("%s: requires '%s', which is not a core node" % [who, req])
			continue
		var lv := int(n.level)
		per_level[lv] += 1
		var parents: Array = n.parent if n.get("parent") is Array else [String(n.get("parent", ""))]
		for p in parents:
			if lv == 0:
				if String(p) != "":
					bad.append("%s: Service has no parent" % who)
			elif not t.nodes.has(p) or str(t.nodes[p].get("level", "")) == "side" or int(t.nodes[p].level) != lv - 1:
				bad.append("%s: parent '%s' is not a %s node" % [who, p, LEVEL_NAMES[lv - 1]])
		var rep := String(n.get("replaces", ""))
		if rep != "" and not (rep in parents):
			bad.append("%s: replaces '%s', which is not its parent" % [who, rep])
	if per_level[0] != 1:
		bad.append("%s: exactly one Service node, found %d" % [car, per_level[0]])
	if per_level[1] < 2:
		bad.append("%s: a fork needs two sides, found %d" % [car, per_level[1]])
	var paths := _finished_paths(t)
	if paths.is_empty():
		bad.append("%s: no path reaches a capstone" % car)
	for id in t.order:
		var reached := false
		for p in paths:
			reached = reached or id in p
		if not reached:
			bad.append("%s/%s: on no finished path" % [car, id])
	for key in ["home", "showcase"]:
		if not (t.get(key, []) in paths):
			bad.append("%s: '%s' is not a finished path" % [car, key])
	if not bad.is_empty():
		return bad  # the builds below would only trip over the same mistakes
	# Tiers and the ceiling
	var car_tier := String(t.get("tier", ""))
	var ceiling := String(t.get("ceiling", ""))
	if not (car_tier in names) or not (ceiling in names):
		bad.append("%s: tier and ceiling must be tier names" % car)
		return bad
	if String(tiers.get("ceiling_by_car_tier", {}).get(car_tier, "")) != ceiling:
		bad.append("%s: a %s car's ceiling is %s, the file says %s" % [car, car_tier, tiers.get("ceiling_by_car_tier", {}).get(car_tier, "?"), ceiling])
	var s0 := float(stock.get("front_torque_split", 0.0))
	for p in paths:
		var label := "%s %s" % [car, "/".join(PackedStringArray(p))]
		_check_sets(t, p, label, bad)
		var full := _assemble_tree(t, stock, max_fit_ids(t, p))
		for key in full:
			if full[key] is float and not is_finite(full[key]):
				bad.append("%s: %s is not finite" % [label, key])
		var s1 := float(full.get("front_torque_split", 0.0))
		if (s0 > 0.0) != (s1 > 0.0) or (s0 < 1.0) != (s1 < 1.0):
			bad.append("%s: turns a driven axle on or off (front split %.2f -> %.2f)" % [label, s0, s1])
		var l2 := String(p[2])
		var got := tier_of(full)
		var said := String(t.get("builds", {}).get(l2, ""))
		if got != said:
			bad.append("%s: fully fitted it is %s (%.3f Nm/kg), the file says %s" % [label, got, nm_per_kg(full), said])
		var over: bool = names.find(got) > names.find(ceiling)
		var allowed: bool = ("%s/%s" % [car, l2]) in tiers.get("t5_builds", [])
		if over and not allowed:
			bad.append("%s: %s is over the car's %s ceiling" % [label, got, ceiling])
		if got == names[names.size() - 1] and not allowed:
			bad.append("%s: only the named big-single builds may reach %s" % [label, got])
	return bad

static func _is_ladder_id(id: String) -> bool:
	var ladder: Dictionary = shared().get("ladder", {})
	for part in ladder.get("parts", []):
		if id.begins_with(String(part.id) + "_") or (part.has("option") and id.begins_with(String(part.option) + "_")):
			return true
	return false

## A path's ids with everything else fitted, for a tree that may not be on disk.
static func max_fit_ids(t: Dictionary, path: Array) -> Array:
	var ids: Array = path.duplicate()
	for id in t.side:
		var req := String(t.nodes[id].get("requires", ""))
		if req == "" or req in path:
			ids.append(id)
	ids.append_array(all_bolt_ons())
	for part in shared().get("ladder", {}).get("parts", []):
		ids.append("%s_%d" % [part.id, part.rungs.size() - 1])
	return ids

## build_base() for a tree that is not on disk (the validator, tests).
static func _assemble_tree(t: Dictionary, stock: Dictionary, installed: Array) -> Dictionary:
	var key := "__validate__"
	var had: Variant = _trees.get(key)
	_trees[key] = t
	var spec: Dictionary = _assemble(stock, fitted(key, installed), false).spec
	if had == null:
		_trees.erase(key)
	else:
		_trees[key] = had
	return spec

## Two fitted nodes setting one path is a data error unless the later one says
## override (the op or the node) or replaces the earlier node.
static func _check_sets(t: Dictionary, path: Array, label: String, bad: Array[String]) -> void:
	var dropped := {}
	for id in path:
		var r := String(t.nodes[id].get("replaces", ""))
		if r != "":
			dropped[r] = true
	var ids: Array = path.duplicate()
	for id in t.side:
		var req := String(t.nodes[id].get("requires", ""))
		if req == "" or req in path:
			ids.append(id)
	var setter := {}
	for id in ids:
		if dropped.has(id):
			continue
		var n: Dictionary = t.nodes[id]
		for op in n.get("ops", []):
			if not (op.has("set") or op.has("mul_redline")):
				continue
			var p := String(op.get("path", ""))
			if setter.has(p) and setter[p] != id and not bool(op.get("override", false)) and not bool(n.get("override", false)):
				bad.append("%s: %s and %s both set %s (mark the later one override, or replaces)" % [label, setter[p], id, p])
			setter[p] = id

## The parts of a node that a template and a car's node share: ops, sound,
## measure, tuner_window. `stock` (may be empty for a template) is used to
## check sub-paths.
static func _check_node_body(n: Dictionary, who: String, bad: Array[String], stock: Dictionary) -> void:
	var ops: Array = n.get("ops", [])
	var sound: Dictionary = n.get("sound", {})
	if ops.is_empty() and sound.is_empty() and not who.begins_with("template"):
		bad.append("%s: changes neither a number nor a sound" % who)
	for op in ops:
		_check_op(op, who, bad, stock)
	var known: Dictionary = library().get("sounds", {})
	for key in sound:
		if key == "blow_off":
			continue
		var names: Variant = known.get(key)
		if names == null or not (names.has(sound[key])):
			bad.append("%s: unknown %s sound '%s'" % [who, key, sound[key]])
	var rule: Dictionary = n.get("measure", {})
	if ops.is_empty():
		return
	if rule.is_empty():
		bad.append("%s: changes a number but has no measure rule" % who)
	else:
		if not library().get("measures", {}).has(String(rule.get("test", ""))):
			bad.append("%s: unknown measure test '%s'" % [who, rule.get("test", "")])
		var n_thresholds := 0
		for key in THRESHOLDS:
			if rule.has(key):
				n_thresholds += 1
				if float(rule[key]) <= 0.0:
					bad.append("%s: %s must be above 0" % [who, key])
		if n_thresholds != 1:
			bad.append("%s: a measure rule has exactly one better_by_ threshold" % who)
	for path in n.get("tuner_window", {}):
		var e := TuneParams.find(path)
		var w: Variant = n.tuner_window[path]
		if e.is_empty() or not (w is Array) or w.size() != 2 or float(w[0]) > float(w[1]) or float(w[0]) < e.adv_min or float(w[1]) > e.adv_max:
			bad.append("%s: tuner_window %s must be [lo, hi] inside the Tuner's hard limits" % [who, path])

static func _check_op(op: Variant, who: String, bad: Array[String], stock: Dictionary) -> void:
	if not (op is Dictionary) or not op.has("path"):
		bad.append("%s: an op needs a path" % who)
		return
	var kinds := 0
	for k in OP_KINDS:
		if op.has(k):
			kinds += 1
	if kinds != 1:
		bad.append("%s: %s needs exactly one of %s" % [who, op.path, str(OP_KINDS)])
		return
	var path := String(op.path)
	var parts := path.split("/")
	var key := parts[0]
	if key == "boost_kind":
		if not (op.get("set") is String) or not (op.set in ForcedInduction.KIND_NAMES):
			bad.append("%s: boost_kind must be set to one of %s" % [who, str(ForcedInduction.KIND_NAMES)])
		return
	for k in OP_KINDS:
		if op.has(k) and (not (op[k] is float) or not is_finite(op[k])):
			bad.append("%s: %s must be a finite number" % [who, path])
			return
	if key == "torque_shape":
		if parts.size() != 2 or not (parts[1] in TORQUE_SHAPE_KEYS):
			bad.append("%s: torque_shape/ takes one of %s" % [who, str(TORQUE_SHAPE_KEYS)])
		return
	if not _all_props().has(key):
		bad.append("%s: '%s' is not a property of the car" % [who, key])
		return
	var cur: Variant = stock[key] if stock.has(key) else _props[key]
	if parts.size() == 1:
		if not (cur is float or cur is int):
			bad.append("%s: '%s' is not a number" % [who, key])
	elif parts.size() != 2:
		bad.append("%s: '%s' is too deep" % [who, path])
	elif cur is Array:
		if not parts[1].is_valid_int() or int(parts[1]) < 0 or int(parts[1]) >= cur.size():
			bad.append("%s: '%s' is past the end of the list" % [who, path])
	elif cur is Dictionary:
		if not cur.has(parts[1]):
			bad.append("%s: '%s' has no entry '%s'" % [who, key, parts[1]])
	else:
		bad.append("%s: '%s' has no entries" % [who, key])

# ---- The car's own defaults ----------------------------------------------------

## Every property of the player's car with its default (a spec only carries
## what a car overrides). Read once from a PlayerCar that never enters the tree.
static func _all_props() -> Dictionary:
	if _props.is_empty():
		var car := PlayerCar.new()
		for p in car.get_property_list():
			if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var val: Variant = car.get(p.name)
				if val is float or val is int or val is bool or val is Array or val is Dictionary:
					_props[p.name] = val.duplicate(true) if (val is Array or val is Dictionary) else val
		car.free()
	return _props

static func _default(key: String) -> Variant:
	var props := _all_props()
	if not props.has(key):
		push_error("ModTree: '%s' is not a property of the car" % key)
		return 0.0
	return props[key]
