extends RefCounted

# What the garage's tree panel knows about one car (garage step G3a,
# 2026-10-11): which parts are owned, which are fitted, what can be bought
# next and why not, what each part costs and changes, and where every node sits
# on the pegboard. The panel (scripts/ui/mod_tree_panel.gd) only draws this and
# passes the keys on; all the rules are here so they can be tested without it.
#
#   var mods := GarageMods.new()
#   mods.open("p1_coupe", wallet)      # wallet: anything with `bank` and spend_bank(int)
#   mods.buy("service")                # bank pays and the part is saved, one commit
#   mods.swap_to("A")                  # free: the other engine branch becomes the fitted one
#
# Four kinds of node, all read from the data (ModTree, BoltOns):
#   core     the car's own tree: Service, the engine fork, a deep step, a keystone
#   side     the tree's small side nodes
#   chassis  the six parts of the shared ladder, one node per step
#   bolt     the Bolt-on row: any order, no wires
# A keystone (the tree's last level) needs two wires: a deep engine step and
# the chassis steps its node names in "needs".
#
# Owned parts are kept in garage.json as "<car>/<id>", fitted ones in
# mod_tree.json as the plain ids ModTree.build() takes (SaveStore). Mods are
# paid from the BANK only; tonight's cash is never touched.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const SaveStore := preload("res://scripts/save/save_store.gd")
const PlayerTune := preload("res://scripts/car/player_tune.gd")
enum {LOCKED, BUYABLE, OWNED, FITTED}

## The pegboard is taller than wide; moves are judged in these proportions.
const ASPECT := Vector2(6.4, 9.0)
const ROOT_Y := 0.74
const LEVEL_Y := [0.74, 0.58, 0.42, 0.09]
const RUNG_Y := [0.74, 0.58, 0.42, 0.28]
const RAIL_Y := [0.885, 0.95]
const GROUPS := ["Pace", "Control", "Street", "Sound", "Info"]

## US wording for the parts ladder (the data's labels are British).
const PART_NAMES := {"tyres": "Tires"}
## Column heads on the board, where the full label does not fit.
const PART_HEADS := {"tyres": "Tires", "diff": "Diff"}
var car_id := ""
var wallet: Object
var owned := {}                    # id -> true
var chain: Array[String] = []      # the fitted core nodes, Service first
var installed: Array[String] = []  # what mod_tree.json holds for this car
var king_crates := 0
var crate_open := false
var items := {}                    # id -> {id, kind, name, feel, pos, ...}
var wires: Array = []              # {a, b, bus}: drawn a (lower) to b
var root := ""
var bolt_groups: Array = []        # {name, x} for the rail's labels
var revision := 0                  # goes up whenever owned or fitted changes
var _t: Dictionary = {}
var _nav := {}                     # id -> ids one move away along a wire
var _last_child := {}              # core id -> the child last fitted under it
var _cards := {}
var _last_bolt := ""

## Special vehicles and cars without a tree file have no panel.
static func has_panel(car: String) -> bool:
	return not PlayerCars.is_special(car) and ModTree.has_tree(car)

## What the car spawns as: the stock spec with the save's fitted list built on
## it (ModTree.build: spec, windows, sound, effects, problems).
static func spawn_build(car: String) -> Dictionary:
	var fitted_ids: Array = SaveStore.load_mod_tree().cars.get(car, {}).get("installed", [])
	return ModTree.build(CarSpec.player_spec(car), ModTree.fitted(car, fitted_ids))

func open(car: String, bank: Object) -> bool:
	car_id = car
	wallet = bank
	items.clear()
	wires.clear()
	_nav.clear()
	_cards.clear()
	_last_child.clear()
	owned.clear()
	chain.clear()
	installed.clear()
	crate_open = false
	root = ""
	if not has_panel(car):
		return false
	_t = ModTree.tree(car)
	_layout()
	_load()
	return true

# ---- Layout ------------------------------------------------------------------

static func _spread(i: int, n: int, a: float, b: float) -> float:
	return a + (b - a) * (i + 0.5) / maxi(n, 1)

func _parents(id: String) -> Array:
	var p: Variant = _t.nodes[id].get("parent", "")
	if p is Array:
		return p
	return [] if String(p) == "" else [String(p)]

func _wire(a: String, b: String, bus := false) -> void:
	wires.append({"a": a, "b": b, "bus": bus})
	_link(a, b)

func _link(a: String, b: String) -> void:
	for pair in [[a, b], [b, a]]:
		if not _nav.has(pair[0]):
			_nav[pair[0]] = []
		if not pair[1] in _nav[pair[0]]:
			_nav[pair[0]].append(pair[1])

func _layout() -> void:
	# The car's own tree: engine on the left, keystones top centre.
	var levels: Array = [[], [], [], []]
	for id in _t.order:
		levels[int(_t.nodes[id].level)].append(id)
	# Children sit in their parents' order, so wires do not cross.
	for lv in range(1, 3):
		var sorted: Array = []
		for p in levels[lv - 1]:
			for id in levels[lv]:
				if p in _parents(id) and not id in sorted:
					sorted.append(id)
		for id in levels[lv]:
			if not id in sorted:
				sorted.append(id)
		levels[lv] = sorted
	var spans := [[0.20, 0.36], [0.10, 0.46], [0.05, 0.51], [0.29, 0.73]]
	for lv in levels.size():
		for i in levels[lv].size():
			var id: String = levels[lv][i]
			var n: Dictionary = _t.nodes[id]
			items[id] = {"id": id, "kind": "core", "level": lv, "big": true, "stagger": i % 2 if levels[lv].size() > 3 else 0, "keystone": lv == 3,
				"name": String(n.get("name", id)), "feel": String(n.get("feel", "")),
				"pos": Vector2(_spread(i, levels[lv].size(), spans[lv][0], spans[lv][1]), LEVEL_Y[lv])}
	root = levels[0][0] if not levels[0].is_empty() else ""
	for id in _t.order:
		for p in _parents(id):
			_wire(p, id)
	for lv in range(1, 3):  # nodes under one parent are a move apart
		for i in range(1, levels[lv].size()):
			if not _shared(_parents(levels[lv][i - 1]), _parents(levels[lv][i])).is_empty():
				_link(levels[lv][i - 1], levels[lv][i])
	# Side nodes: a short column at the left edge.
	for i in _t.side.size():
		var id: String = _t.side[i]
		var n: Dictionary = _t.nodes[id]
		var req := String(n.get("requires", ""))
		items[id] = {"id": id, "kind": "side", "big": false, "requires": req,
			"name": String(n.get("name", id)), "feel": String(n.get("feel", "")),
			"pos": Vector2(0.05, ROOT_Y - 0.115 * i)}
		_wire(req if req != "" else root, id)
	# Chassis: one column per part off a bus wire from Service.
	var parts: Array = ModTree.shared().get("ladder", {}).get("parts", [])
	var prev_first := ""
	for i in parts.size():
		var part: Dictionary = parts[i]
		var x := 0.60 + 0.072 * i
		var label := String(PART_NAMES.get(part.id, part.label))
		for n in range(1, part.rungs.size()):
			var id := "%s_%d" % [part.id, n]
			items[id] = {"id": id, "kind": "chassis", "big": false, "part": String(part.id), "rung": n, "part_index": i,
				"name": "%s: %s" % [label, part.rungs[n]], "part_label": String(PART_HEADS.get(part.id, label)),
				"ticket": _ticket_name(String(part.id), String(part.rungs[n])),
				"feel": "The Tuner's %s sliders open up %s." % [label.to_lower(), ["", "a little", "a lot", "all the way"][mini(n, 3)]],
				"pos": Vector2(x, RUNG_Y[mini(n, RUNG_Y.size() - 1)])}
			if n == 1:
				_wire(root, id, true)
				if prev_first != "":
					_link(prev_first, id)
				prev_first = id
			else:
				_wire("%s_%d" % [part.id, n - 1], id)
	# Keystones: the second wire comes down from the chassis.
	for id in levels[3]:
		for need in _needs(id):
			if items.has(need):
				_wire(need, id)
	# Bolt-on row: two rows on a rail, grouped, column by column.
	var by_group := {}
	for it in BoltOns.items():
		var g := _group(String(it.get("kind", "")))
		if not by_group.has(g):
			by_group[g] = []
		by_group[g].append(it)
	var cols := 0
	for g in GROUPS:
		cols += ceili(by_group.get(g, []).size() / 2.0)
	var col := 0
	for g in GROUPS:
		var list: Array = by_group.get(g, [])
		if list.is_empty():
			continue
		bolt_groups.append({"name": g, "x": _spread(col, cols, 0.05, 0.95), "narrow": list.size() <= 2})
		for i in list.size():
			var it: Dictionary = list[i]
			var c := col + i / 2
			var prev := ""
			if it.has("step_of") and int(it.step) > 1:
				prev = "%s_%d" % [it.step_of, int(it.step) - 1]
			items[it.id] = {"id": String(it.id), "kind": "bolt", "big": false, "col": c, "row": i % 2, "group": g, "prev": prev,
				"name": String(it.label) + (" %d" % int(it.step) if int(it.step) > 0 else ""),
				"feel": String(it.get("notice", "")),
				"pos": Vector2(_spread(c, cols, 0.05, 0.95), RAIL_Y[i % 2])}
		col += ceili(list.size() / 2.0)

static func _shared(a: Array, b: Array) -> Array:
	var out: Array = []
	for x in a:
		if x in b:
			out.append(x)
	return out

static func _group(kind: String) -> String:
	var k := kind.to_lower()
	if k.begins_with("pace"):
		return "Pace"
	if k.begins_with("control"):
		return "Control"
	if k.contains("sound"):
		return "Sound"
	if k.begins_with("info"):
		return "Info"
	return "Street"

static func _ticket_name(part: String, rung: String) -> String:
	return rung + " tires" if part == "tyres" else rung

func _needs(id: String) -> Array:
	var n: Variant = _t.nodes[id].get("needs", [])
	return n if n is Array else [String(n)]

# ---- Moving ------------------------------------------------------------------

## The node one arrow press away from `from`: along a wire to the nearest node
## that way; with no wire that way, the nearest node that way at all. Down from
## Service drops into the Bolt-on row, up from its top row comes back.
func move(from: String, dir: Vector2i) -> String:
	if not items.has(from):
		return root
	var it: Dictionary = items[from]
	if it.kind == "bolt":
		return _move_bolt(it, dir)
	var d := Vector2(dir)
	var best := _toward(from, _nav.get(from, []), d, 0.5)
	if best != "":
		return best
	if from == root and dir == Vector2i.DOWN:
		return _enter_rail()
	var others: Array = []
	for id in items:
		if items[id].kind != "bolt" and id != from:
			others.append(id)
	best = _toward(from, others, d, 0.7)
	return best if best != "" else from

func _toward(from: String, among: Array, dir: Vector2, cone: float) -> String:
	var best := ""
	var best_score := INF
	for id in among:
		var delta: Vector2 = (items[id].pos - items[from].pos) * ASPECT
		var dist := delta.length()
		if dist < 0.0001:
			continue
		var along := delta.dot(dir) / dist
		if along <= cone:
			continue
		var score := dist / (along * along)
		if score < best_score:
			best_score = score
			best = id
	return best

func _enter_rail() -> String:
	if items.has(_last_bolt):
		return _last_bolt
	var best := ""
	for id in items:
		var b: Dictionary = items[id]
		if b.kind == "bolt" and b.row == 0 and (best == "" or absf(b.pos.x - items[root].pos.x) < absf(items[best].pos.x - items[root].pos.x)):
			best = id
	return best if best != "" else root

func _move_bolt(it: Dictionary, dir: Vector2i) -> String:
	var out := String(it.id)
	if dir.y != 0:
		var row: int = it.row + dir.y
		if row < 0:
			_last_bolt = it.id
			return root
		out = _bolt_at(it.col, row, 0)
	else:
		out = _bolt_at(it.col, it.row, dir.x)
		if out == "":
			out = _bolt_at(it.col, 1 - it.row, dir.x)
	return out if out != "" else String(it.id)

## The bolt in `row` at `col` (step 0), or the nearest one left or right of it.
func _bolt_at(col: int, row: int, step: int) -> String:
	var best := ""
	for id in items:
		var b: Dictionary = items[id]
		if b.kind != "bolt" or b.row != row:
			continue
		if step == 0:
			if b.col == col:
				return id
		elif (b.col - col) * step > 0 and (best == "" or absi(b.col - col) < absi(items[best].col - col)):
			best = id
	return best

# ---- States ------------------------------------------------------------------

func state(id: String) -> int:
	if owned.has(id):
		return FITTED if id in installed else OWNED
	return BUYABLE if lock_reason(id) == "" else LOCKED

## Why the part cannot be bought yet, in Walt's words. "" = it can.
func lock_reason(id: String) -> String:
	var it: Dictionary = items[id]
	match it.kind:
		"bolt":
			if it.prev != "" and not owned.has(it.prev):
				return "One step at a time. %s first." % items[it.prev].name
			return ""
		"core":
			if id == root:
				return ""
			if not owned.has(root):
				return "Service first. I don't bolt parts to a sick motor."
			var has_parent := false
			for p in _parents(id):
				has_parent = has_parent or owned.has(p)
			if not has_parent:
				if it.keystone:
					return "Finish an engine first. Any deep step."
				return "%s goes on first." % items[_parents(id)[0]].name
			for need in _needs(id):
				if not owned.has(need):
					return "Engine's ready. Chassis isn't: %s." % _item_name(need)
			return ""
		"side":
			if not owned.has(root):
				return "Service first. I don't bolt parts to a sick motor."
			if it.requires != "" and not owned.has(it.requires):
				return "Only goes on with %s." % items[it.requires].name
			return ""
		"chassis":
			if not owned.has(root):
				return "Service first. I don't bolt parts to a sick motor."
			if it.rung > 1 and not owned.has("%s_%d" % [it.part, it.rung - 1]):
				return "One step at a time. %s first." % items["%s_%d" % [it.part, it.rung - 1]].name
			return ""
	return ""

func _item_name(id: String) -> String:
	return String(items[id].name) if items.has(id) else id

## A keystone's two wires: [{label, ok, what}]. Empty for any other node.
func key_wires(id: String) -> Array:
	var it: Dictionary = items.get(id, {})
	if not it.get("keystone", false):
		return []
	var engine := ""
	for p in _parents(id):
		if owned.has(p):
			engine = items[p].name
	var out := [{"label": "Engine wire", "ok": engine != "", "what": engine if engine != "" else "any deep step"}]
	for need in _needs(id):
		out.append({"label": "Chassis wire", "ok": owned.has(need), "what": _item_name(need)})
	return out

## A king crate fits one deep step or keystone.
func crate_fits(id: String) -> bool:
	var it: Dictionary = items.get(id, {})
	return it.get("kind", "") == "core" and int(it.level) >= 2

func price(id: String) -> int:
	if crate_open and crate_fits(id):
		return 0
	return maxi(ModTree.price_cred(car_id, id), 0)

func bank() -> int:
	return int(wallet.bank) if wallet != null else 0

## How far the bank is from the price; 0 when it covers it.
func short_by(id: String) -> int:
	return maxi(price(id) - bank(), 0)

## What "Fit the ..., $X?" calls the part.
func ticket_name(id: String) -> String:
	var name := String(items[id].get("ticket", items[id].name))
	if name.length() > 1 and name[1] == name[1].to_lower():
		name = name[0].to_lower() + name.substr(1)
	return name

func ticket_text(id: String) -> String:
	return "Fit the %s, %s?" % [ticket_name(id), money(price(id))]

static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-$" if n < 0 else "$") + s + out

# ---- Buying and swapping -----------------------------------------------------

## Opens a king crate: the next deep step or keystone bought costs $0.
func open_king_crate() -> bool:
	if king_crates <= 0:
		return false
	crate_open = true
	_cards.clear()
	return true

func close_king_crate() -> void:
	crate_open = false
	_cards.clear()

## Buys and fits a part from the bank. {ok, price, reason}.
func buy(id: String) -> Dictionary:
	var out := {"ok": false, "price": 0, "reason": ""}
	if not items.has(id) or owned.has(id):
		out.reason = "That's on the shelf already."
		return out
	out.reason = lock_reason(id)
	if out.reason != "":
		return out
	if crate_open and not crate_fits(id):
		out.reason = "The crate's for the deep stuff."
		return out
	var cost := price(id)
	out.price = cost
	if cost > bank():
		out.reason = "Short %s" % money(cost - bank())
		return out
	if SaveStore.chase_active:
		out.reason = "Not with them on your tail."
		return out
	var crates := king_crates
	var was_open := crate_open
	owned[id] = true
	if crate_open:
		king_crates -= 1
		crate_open = false
	if items[id].kind == "core":
		_set_chain_to(id)
	_refit()
	if not _pay_and_save(cost):
		# Nothing was paid or written: back to what the save holds.
		owned.clear()
		chain.clear()
		installed.clear()
		_last_child.clear()
		king_crates = crates
		crate_open = was_open
		_load()
		out.reason = "Short %s" % money(cost - bank()) if cost > bank() else "Not now."
		return out
	out.ok = true
	return out

## The bank pays and the part is saved in ONE commit (Wallet.spend_bank_with):
## a game killed in between used to keep the money and lose the part. A plain
## bank object (tests) pays first, then the parts go in one commit.
func _pay_and_save(cost: int) -> bool:
	var lists := _save_lists()
	if wallet != null and wallet.has_method("spend_bank_with"):
		return wallet.spend_bank_with(cost, "garage", func(c: Dictionary) -> void:
			SaveStore.apply_parts(c, lists[0], lists[1]))
	if cost > 0 and not wallet.spend_bank(cost):
		return false
	SaveStore.save_parts(lists[0], lists[1])
	return true

## Fits an owned core node that is not on the fitted path (the other engine
## branch, the other keystone). Free. The branch left behind keeps its tune and
## gets it back when it is swapped in again.
func swap_to(id: String) -> bool:
	if not owned.has(id) or items[id].kind != "core" or id in chain:
		return false
	if SaveStore.chase_active:
		return false
	_set_chain_to(id)
	_refit()
	_save()
	return true

## The engine side the fitted path runs up (the fork node), "" before the fork.
func branch() -> String:
	return chain[1] if chain.size() > 1 else ""

func _set_chain_to(id: String) -> void:
	var old := chain.duplicate()
	var old_branch := branch()
	var path: Array[String] = [id]
	while not _parents(path[0]).is_empty():
		path.push_front(_pick(_parents(path[0]), old, ""))
	# Carry on down through what was fitted under it before.
	while true:
		var tip: String = path[path.size() - 1]
		var kids: Array = []
		for cid in _t.order:
			if owned.has(cid) and tip in _parents(cid):
				kids.append(cid)
		if kids.is_empty():
			break
		path.append(_pick(kids, old, String(_last_child.get(tip, ""))))
	chain = path
	for i in range(1, chain.size()):
		_last_child[chain[i - 1]] = chain[i]
	if branch() != old_branch:
		_swap_tune(old_branch, branch())

## One of `ids`: the one on the old path, else the remembered one, else an
## owned one, else the first.
func _pick(ids: Array, old: Array, remembered: String) -> String:
	for id in ids:
		if id in old:
			return id
	if remembered in ids:
		return remembered
	for id in ids:
		if owned.has(id):
			return id
	return String(ids[0])

## Rebuilds the fitted list: the core path, then everything else owned that the
## path lets on the car.
func _refit() -> void:
	installed = chain.duplicate()
	for id in items:
		if not owned.has(id) or id in installed:
			continue
		var it: Dictionary = items[id]
		if it.kind == "core" or (it.kind == "side" and it.requires != "" and not it.requires in chain):
			continue
		installed.append(id)
	_cards.clear()
	revision += 1

# ---- The save ----------------------------------------------------------------

func _load() -> void:
	var prefix := car_id + "/"
	for part in SaveStore.load_garage().owned_parts:
		if part.begins_with(prefix) and items.has(part.substr(prefix.length())):
			owned[part.substr(prefix.length())] = true
	var want := {}
	for id in SaveStore.load_mod_tree().cars.get(car_id, {}).get("installed", []):
		if owned.has(id):
			want[id] = true
	chain.assign(ModTree._chain(_t, want, []))
	for i in range(1, chain.size()):
		_last_child[chain[i - 1]] = chain[i]
	_refit()

func _save() -> bool:
	var lists := _save_lists()
	return SaveStore.save_parts(lists[0], lists[1])

## [every part owned, all cars; every car's fitted list] with this car's now.
func _save_lists() -> Array:
	var prefix := car_id + "/"
	var parts: Array = []
	for part in SaveStore.load_garage().owned_parts:
		if not part.begins_with(prefix):
			parts.append(part)
	for id in owned:
		parts.append(prefix + id)
	var cars: Dictionary = SaveStore.load_mod_tree().cars
	cars[car_id] = {"installed": installed.duplicate()}
	return [parts, cars]

# ---- Branch tunes ------------------------------------------------------------

## The car's tune file (PlayerTune's own rule) and the file next to it that
## keeps the tune of each engine branch not fitted right now.
func tune_file() -> String:
	if car_id == "p1_coupe":
		return PlayerTune.path
	return "%s_%s.%s" % [PlayerTune.path.get_basename(), car_id, PlayerTune.path.get_extension()]

func branch_tunes_file() -> String:
	return "%s_%s_branches.json" % [PlayerTune.path.get_basename(), car_id]

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	return json.data

static func _write(path: String, data: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("GarageMods: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true

func _swap_tune(from_branch: String, to_branch: String) -> void:
	var kept := _read(branch_tunes_file())
	if from_branch != "":
		var now: Variant = _read(tune_file()).get("values", {})
		kept[from_branch] = now if now is Dictionary else {}
	if to_branch != "":
		var back: Variant = kept.get(to_branch, {})
		_write(tune_file(), {"version": 1, "values": back if back is Dictionary else {}})
	_write(branch_tunes_file(), kept)

# ---- The card ----------------------------------------------------------------

const _LINES := [
	# label, unit, decimals, +1 if more is better
	["Torque", "Nm", 0, 1], ["Redline", "rpm", 0, 1], ["Weight", "kg", 0, -1], ["Boost", "bar", 2, 1],
	["Brakes", "%", 0, 1], ["Shift", "s", 2, -1], ["Downforce", "", 2, 1], ["Tire grip", "%", 0, 1],
]

func _numbers(spec: Dictionary) -> Array:
	return [float(spec.max_torque) * ModTree.boost_mult(spec), _num(spec, "max_rpm"), _num(spec, "vehicle_mass"),
		_num(spec, "turbo_boost_max"), _num(spec, "brake_force_multiplier") * 100.0, _num(spec, "shift_time"),
		_num(spec, "aero_downforce_coefficient_front") + _num(spec, "aero_downforce_coefficient_rear"),
		_num(spec, "coefficient_of_friction", "Road") * 100.0]

static func _num(spec: Dictionary, key: String, sub: Variant = null) -> float:
	var v: Variant = spec[key] if spec.has(key) else ModTree._all_props().get(key, 0.0)
	if sub != null:
		v = v.get(sub, 0.0) if v is Dictionary else 0.0
	return float(v) if (v is float or v is int) else 0.0

## The fitted lists with and without the part, everything else as owned.
func _with_without(id: String) -> Array:
	var it: Dictionary = items[id]
	var rest: Array = []
	for o in owned:
		if items[o].kind != "core" and o != id:
			rest.append(o)
	if it.kind == "core":
		var path: Array = [id]
		while not _parents(path[0]).is_empty():
			path.push_front(_pick(_parents(path[0]), chain, ""))
		if it.keystone:
			rest.append_array(_needs(id))
		return [path + rest, path.slice(0, path.size() - 1) + rest]
	if it.kind == "chassis":
		var base: Array = []
		for o in rest:
			if items[o].kind != "chassis" or items[o].part != it.part:
				base.append(o)
		var below: Array = []
		for n in range(1, it.rung):
			below.append("%s_%d" % [it.part, n])
		return [chain + base + below + [id], chain + base + below]
	return [chain + rest + [id], chain + rest]

## Everything the card shows for a node:
##   name, feel, state, price, short (dollars the bank is short, 0 = fine),
##   lines [{label, from, to, unit, good (+1 better, -1 worse)}] real numbers the part changes,
##   bars  [{label, now, was}] 0..1 with and without the part,
##   wires (keystones: key_wires), note (why it is locked, Walt's words)
func card(id: String) -> Dictionary:
	if _cards.has(id):
		var kept: Dictionary = _cards[id]
		kept.short = short_by(id)
		return kept
	var it: Dictionary = items[id]
	var stock := CarSpec.player_spec(car_id)
	var sets := _with_without(id)
	var spec_with: Dictionary = ModTree.build_base(stock, ModTree.fitted(car_id, sets[0]))
	var spec_without: Dictionary = ModTree.build_base(stock, ModTree.fitted(car_id, sets[1]))
	var a := _numbers(spec_without)
	var b := _numbers(spec_with)
	for i in [4, 7]:  # brakes and tire grip read as a percentage of what the car has now
		b[i] = 100.0 * b[i] / maxf(a[i], 0.001)
		a[i] = 100.0
	var lines: Array = []
	for i in _LINES.size():
		var dec: int = _LINES[i][2]
		var step := pow(10.0, -dec)
		if absf(b[i] - a[i]) < step * 0.5:
			continue
		lines.append({"label": _LINES[i][0], "unit": _LINES[i][1], "from": _fmt(a[i], dec), "to": _fmt(b[i], dec),
			"good": int(signf(b[i] - a[i])) * int(_LINES[i][3])})
	var s := _numbers(stock)
	var bars: Array = []
	for row in [["Power", 0.6], ["Grip", 1.5], ["Brakes", 2.0], ["Light", 3.0]]:
		var k: String = row[0]
		bars.append({"label": k, "now": _bar(k, spec_with, stock, s, row[1]), "was": _bar(k, spec_without, stock, s, row[1])})
	var st := state(id)
	var out := {"name": it.name, "feel": it.feel, "state": st, "price": price(id), "short": short_by(id),
		"lines": lines, "bars": bars, "wires": key_wires(id), "note": lock_reason(id) if st == LOCKED else ""}
	_cards[id] = out
	return out

static func _fmt(x: float, decimals: int) -> String:
	if decimals > 0:
		return String.num(x, decimals).pad_decimals(decimals)
	var n := roundi(x)
	return money(n).substr(1) if n >= 0 else "-" + money(-n).substr(1)

func _bar(kind: String, spec: Dictionary, stock: Dictionary, stock_numbers: Array, gain: float) -> float:
	var ratio := 1.0
	match kind:
		"Power":
			ratio = ModTree.nm_per_kg(spec) / maxf(ModTree.nm_per_kg(stock), 0.001)
		"Grip":
			var n := _numbers(spec)
			ratio = (n[7] * (1.0 + n[6])) / maxf(stock_numbers[7] * (1.0 + stock_numbers[6]), 0.001)
		"Brakes":
			ratio = _num(spec, "brake_force_multiplier") / maxf(_num(stock, "brake_force_multiplier"), 0.001)
		"Light":
			ratio = _num(stock, "vehicle_mass") / maxf(_num(spec, "vehicle_mass"), 1.0)
	return clampf(0.4 + (ratio - 1.0) * gain, 0.02, 1.0)
