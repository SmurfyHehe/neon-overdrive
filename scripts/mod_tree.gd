class_name ModTree
extends RefCounted

# A car's performance mod tree and the shared parts ladder (Stage E foundation,
# garage proposal docs/planning/garage-mod-trees-and-player-cars-2026-10-07.md,
# PR #197). Data only, no UI: the tree lives in data/mod_trees/<car_id>.json and
# the ladder in data/mod_trees/parts.json.
#
# Three layers own three kinds of value:
#   - the tree's fitted nodes own the HARDWARE: peak torque and redline
#     (OWNED_PATHS). A tune never stores those, so loading a tune can never undo
#     a node; and an engine node can fix a Tuner slider's range (boost).
#   - the parts ladder sets how far each Tuner slider may move from the base
#     build (windows()). Presets ignore the windows.
#   - the tune (Tuner, tune slots) is everything else, as offsets the player sets
#     on top of the base build.
#
#   var tree := ModTree.load_car("p1_coupe")
#   var base := tree.base_spec(CarSpec.coupe_default(), ["service", "na"], {"tyres": 1})
#   var win := tree.windows(base, ["service", "na"], {"tyres": 1})
#
# The base build is what the Tuner calls its stock: the stock spec, then each
# fitted node from the root down, then each part step's small deltas.

## Paths a fitted node owns. Tune slots and the kept player tune leave them out.
const OWNED_PATHS: Array[String] = ["max_torque", "max_rpm"]
const DIR := "res://data/mod_trees/"

var car_id := ""
var nodes := {}       # id -> node Dictionary
var order: Array[String] = []  # ids as listed in the file
var chassis := {}     # "grip" / "slide" -> {feel, deltas}
var parts := {}       # kind -> part Dictionary (from parts.json)
var notches: Array = [1, 3, -1]
var cred_per_night := 1000.0
## Problems found while loading; empty means the data is good.
var errors: Array[String] = []

static func owns(path: String) -> bool:
	return OWNED_PATHS.has(path)

static func load_car(id: String) -> ModTree:
	var t := ModTree.new()
	t.car_id = id
	var tree: Variant = _read_json(DIR + id + ".json")
	var ladder: Variant = _read_json(DIR + "parts.json")
	var tun: Variant = _read_json(DIR + "tunables.json")
	if not tree is Dictionary or not ladder is Dictionary:
		t.errors.append("cannot read the tree or parts data for %s" % id)
		return t
	for n in tree.get("nodes", []):
		t.nodes[str(n.id)] = n
		t.order.append(str(n.id))
	t.chassis = tree.get("chassis", {})
	t.parts = ladder.get("parts", {})
	t.notches = ladder.get("notches", t.notches)
	if tun is Dictionary:
		t.cred_per_night = float(tun.get("cred_per_night", t.cred_per_night))
	t._validate()
	return t

static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("ModTree: %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data

# ---------- tree shape ----------

func root() -> String:
	for id in order:
		if str(nodes[id].parent) == "":
			return id
	return ""

func children(id: String) -> Array[String]:
	var out: Array[String] = []
	for c in order:
		if str(nodes[c].parent) == id:
			out.append(c)
	return out

## The node and its ancestors, root first.
func chain_to(id: String) -> Array[String]:
	var out: Array[String] = []
	var cur := id
	while cur != "" and nodes.has(cur):
		out.push_front(cur)
		cur = str(nodes[cur].parent)
	return out

func leaves() -> Array[String]:
	var out: Array[String] = []
	for id in order:
		if children(id).is_empty():
			out.append(id)
	return out

## True if `fitted` is a chain from the root down (each node's parent is the one
## before it).
func is_chain(fitted: Array) -> bool:
	for i in fitted.size():
		var id := str(fitted[i])
		if not nodes.has(id):
			return false
		if str(nodes[id].parent) != ("" if i == 0 else str(fitted[i - 1])):
			return false
	return true

## The deepest fitted engine node, or "stock". Each engine keeps its own tune.
func engine_key(fitted: Array) -> String:
	var key := "stock"
	for id in fitted:
		if nodes.has(id) and nodes[id].get("engine", false):
			key = str(id)
	return key

## A node's price in Cred.
func price(id: String) -> int:
	return roundi(float(nodes[id].get("nights", 0.0)) * cred_per_night)

## The price of the next step of a part, or -1 at the top.
func part_price(kind: String, step: int) -> int:
	var nights: Array = parts[kind].nights
	return -1 if step + 1 >= nights.size() else roundi(float(nights[step + 1]) * cred_per_night)

## The node's own deltas, including its chassis direction's.
func node_deltas(id: String) -> Dictionary:
	var n: Dictionary = nodes[id]
	var d: Dictionary = n.get("deltas", {}).duplicate()
	if n.has("chassis"):
		d.merge(chassis.get(n.chassis, {}).get("deltas", {}))
	return d

# ---------- the base build ----------

## Stock spec + fitted nodes (root first) + each part step's deltas. Tunable
## paths are clamped to their hard limits. `stock` is not changed.
func base_spec(stock: Dictionary, fitted: Array, part_steps: Dictionary) -> Dictionary:
	var spec := CarSpec.clone_spec(stock)
	for id in fitted:
		if nodes.has(id):
			_apply_deltas(spec, node_deltas(id))
	for kind in parts:
		var step := clampi(int(part_steps.get(kind, 0)), 0, parts[kind].deltas.size() - 1)
		_apply_deltas(spec, parts[kind].deltas[step])
	return spec

static func _apply_deltas(spec: Dictionary, deltas: Dictionary) -> void:
	for path in deltas:
		var op: Array = deltas[path]
		var cur := TuneParams.get_value(spec, path)
		var v: float
		match str(op[0]):
			"mul": v = cur * float(op[1])
			"add": v = cur + float(op[1])
			_: v = float(op[1])
		var e := TuneParams.find(path)
		if not e.is_empty():
			v = clampf(v, e.adv_min, e.adv_max)
		TuneParams.set_value(spec, path, v)

# ---------- slider windows ----------

## {path: [lo, hi]}: how far the Tuner may move each covered slider. A part's
## step gives the half-width in notches around the base value (a notch is a
## tenth of the path's safe range; -1 = the whole safe range). A fitted node's
## own "windows" entry replaces it (the deepest node wins). Paths not in the
## result are not limited. The base value is always inside its window.
func windows(base: Dictionary, fitted: Array, part_steps: Dictionary) -> Dictionary:
	var out := {}
	for kind in parts:
		var step := clampi(int(part_steps.get(kind, 0)), 0, notches.size() - 1)
		var n := int(notches[step])
		for path in parts[kind].paths:
			var e := TuneParams.find(path)
			if e.is_empty():
				continue
			var b := TuneParams.get_value(base, path)
			if n < 0:
				out[path] = [minf(e.min, b), maxf(e.max, b)]
			else:
				var w: float = n * (e.max - e.min) / 10.0
				out[path] = [minf(maxf(e.min, b - w), b), maxf(minf(e.max, b + w), b)]
	for id in fitted:
		if nodes.has(id):
			var nw: Dictionary = nodes[id].get("windows", {})
			for path in nw:
				out[path] = [float(nw[path][0]), float(nw[path][1])]
	# boost: no turbo node fitted means no boost to tune
	if not out.has("turbo_boost_max") and float(base.get("turbo_boost_max", 0.0)) == 0.0:
		out["turbo_boost_max"] = [0.0, 0.0]
	return out

## A value clamped into its window (unchanged if the path has none).
static func clamp_to(win: Dictionary, path: String, v: float) -> float:
	if not win.has(path):
		return v
	return clampf(v, win[path][0], win[path][1])

# ---------- tunes ----------

## The base build with a tune ({path: float}, owned paths ignored) on top.
static func with_tune(base: Dictionary, tune: Dictionary) -> Dictionary:
	var spec := CarSpec.clone_spec(base)
	for path in tune:
		if owns(path) or TuneParams.find(path).is_empty():
			continue
		var e := TuneParams.find(path)
		TuneParams.set_value(spec, path, clampf(float(tune[path]), e.adv_min, e.adv_max))
	return spec

## A spec's tune as {path: float}: every tunable path except the owned ones.
static func tune_of(spec: Dictionary) -> Dictionary:
	var out := {}
	for e in TuneParams.all():
		if not owns(e.path):
			out[e.path] = TuneParams.get_value(spec, e.path)
	return out

func _validate() -> void:
	var r := root()
	if r == "":
		errors.append("no root node")
	for id in order:
		var n: Dictionary = nodes[id]
		var p := str(n.parent)
		if p != "" and not nodes.has(p):
			errors.append("%s: parent %s does not exist" % [id, p])
		if p == "" and id != r:
			errors.append("%s: a second root" % id)
		if n.has("chassis") and not chassis.has(n.chassis):
			errors.append("%s: unknown chassis %s" % [id, n.chassis])
		for path in node_deltas(id):
			if owns(path) or not TuneParams.find(path).is_empty():
				continue
			errors.append("%s: %s is not a tunable path" % [id, path])
	for kind in parts:
		var part: Dictionary = parts[kind]
		if part.deltas.size() != notches.size() or part.nights.size() != notches.size():
			errors.append("part %s: needs %d steps" % [kind, notches.size()])
