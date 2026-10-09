class_name GarageState
extends RefCounted

# What the player owns in the garage, per car (Stage E foundation; garage
# proposal PR #197, Roy's answers). Saved in user://garage.json:
#   {"version": 1, "cars": {car_id: {
#       "owned":  [node ids],               bought nodes; they stay owned
#       "fitted": [node ids, root first],   the chain on the car now
#       "parts":  {kind: step},             0 = stock
#       "tunes":  {engine_key: {path: float}}  one tune per engine
#   }}}
#
# Rules:
#   - buying is paid from the bank (Wallet.spend_bank); nothing changes when the
#     bank is short. A node needs its parent owned. A bought node is fitted.
#   - swapping between owned nodes is free (fit()).
#   - each engine keeps its own tune: fitting a different engine stores the
#     current tune under the old engine and hands back the new engine's tune,
#     or {} (a fresh tune: the base build as is) the first time.
#   - tunes never hold the paths a node owns (ModTree.OWNED_PATHS).

const DEFAULT_PATH := "user://garage.json"
const TestMode := preload("res://scripts/test_mode.gd")

var path: String
var cars := {}

func _init(file_path := "") -> void:
	path = file_path if file_path != "" else TestMode.path(DEFAULT_PATH)
	_load_file()

## The car's entry, created empty if new.
func car(car_id: String) -> Dictionary:
	if not cars.has(car_id):
		cars[car_id] = {"owned": [], "fitted": [], "parts": {}, "tunes": {}}
	return cars[car_id]

func owned(tree: ModTree) -> Array:
	return car(tree.car_id).owned

func fitted(tree: ModTree) -> Array:
	return car(tree.car_id).fitted

func part_step(tree: ModTree, kind: String) -> int:
	return int(car(tree.car_id).parts.get(kind, 0))

## The base build for the car as it stands.
func base_spec(tree: ModTree, stock: Dictionary) -> Dictionary:
	var c := car(tree.car_id)
	return tree.base_spec(stock, c.fitted, c.parts)

func windows(tree: ModTree, base: Dictionary) -> Dictionary:
	var c := car(tree.car_id)
	return tree.windows(base, c.fitted, c.parts)

## Why the node cannot be bought, or "" if it can.
func why_not_buy(tree: ModTree, id: String, wallet: Wallet, band := 5) -> String:
	if not tree.nodes.has(id):
		return "no such node"
	var c := car(tree.car_id)
	if c.owned.has(id):
		return "owned"
	var parent := str(tree.nodes[id].parent)
	if parent != "" and not c.owned.has(parent):
		return "needs " + parent
	if int(tree.nodes[id].get("band", 0)) > band:
		return "band"
	if not wallet.can_afford(tree.price(id)):
		return "bank"
	return ""

## Buys and fits a node, paid from the bank. Returns {"ok", "reason", "tune"}:
## "tune" is the tune to load (see fit()).
func buy(tree: ModTree, id: String, wallet: Wallet, current_tune: Dictionary, band := 5) -> Dictionary:
	var why := why_not_buy(tree, id, wallet, band)
	if why != "":
		return {"ok": false, "reason": why, "tune": current_tune}
	if not wallet.spend_bank(tree.price(id)):
		return {"ok": false, "reason": "bank", "tune": current_tune}
	car(tree.car_id).owned.append(id)
	var r := fit(tree, id, current_tune)
	r["reason"] = ""
	return r

## Fits an owned node, free. Its ancestors must be owned; they are fitted too.
## Fitted nodes below it stay fitted; a sibling branch comes off. Returns
## {"ok", "tune"}: the tune to load now, the same one if the engine did not
## change, else the new engine's saved tune or {} for a fresh one.
func fit(tree: ModTree, id: String, current_tune: Dictionary) -> Dictionary:
	var c := car(tree.car_id)
	var chain := tree.chain_to(id)
	for n in chain:
		if not c.owned.has(n):
			return {"ok": false, "tune": current_tune}
	var old_key := tree.engine_key(c.fitted)
	var keep: Array = []
	for n in c.fitted:
		if not chain.has(n) and tree.chain_to(n).has(id):
			keep.append(n)
	var new_fitted: Array = []
	new_fitted.append_array(chain)
	new_fitted.append_array(keep)
	return _refit(tree, new_fitted, old_key, current_tune)

## Takes the node (and everything below it) off; its parent stays. Free.
func unfit(tree: ModTree, id: String, current_tune: Dictionary) -> Dictionary:
	var c := car(tree.car_id)
	var i := (c.fitted as Array).find(id)
	if i < 0:
		return {"ok": false, "tune": current_tune}
	return _refit(tree, (c.fitted as Array).slice(0, i), tree.engine_key(c.fitted), current_tune)

func _refit(tree: ModTree, new_fitted: Array, old_key: String, current_tune: Dictionary) -> Dictionary:
	var c := car(tree.car_id)
	c.fitted = new_fitted
	var new_key := tree.engine_key(new_fitted)
	var tune := current_tune
	if new_key != old_key:
		c.tunes[old_key] = _strip(current_tune)
		tune = (c.tunes.get(new_key, {}) as Dictionary).duplicate()
	save()
	return {"ok": true, "tune": tune}

## Stores the current tune for the fitted engine (call before saving the game).
func keep_tune(tree: ModTree, tune: Dictionary) -> void:
	var c := car(tree.car_id)
	c.tunes[tree.engine_key(c.fitted)] = _strip(tune)
	save()

## Buys the next step of a part, paid from the bank.
func buy_part(tree: ModTree, kind: String, wallet: Wallet) -> bool:
	if not tree.parts.has(kind):
		return false
	var step := part_step(tree, kind)
	var cost := tree.part_price(kind, step)
	if cost < 0 or not wallet.spend_bank(cost):
		return false
	car(tree.car_id).parts[kind] = step + 1
	save()
	return true

static func _strip(tune: Dictionary) -> Dictionary:
	var out := {}
	for p in tune:
		if not ModTree.owns(p) and (tune[p] is float or tune[p] is int) and is_finite(float(tune[p])):
			out[p] = float(tune[p])
	return out

func save() -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("GarageState: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify({"version": 1, "cars": cars}, "\t"))
	return true

func _load_file() -> void:
	cars = {}
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return
	var raw: Variant = json.data.get("cars", {})
	if not raw is Dictionary:
		return
	for id in raw:
		var c: Variant = raw[id]
		if not c is Dictionary:
			continue
		var entry := car(str(id))
		for k in ["owned", "fitted"]:
			if c.get(k) is Array:
				for n in c[k]:
					entry[k].append(str(n))
		if c.get("parts") is Dictionary:
			for k in c.parts:
				entry.parts[str(k)] = int(c.parts[k])
		if c.get("tunes") is Dictionary:
			for k in c.tunes:
				if c.tunes[k] is Dictionary:
					entry.tunes[str(k)] = _strip(c.tunes[k])
