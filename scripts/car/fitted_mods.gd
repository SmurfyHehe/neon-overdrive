class_name FittedMods
extends RefCounted

# What the player's car has fitted, read one way everywhere (engine bays B4,
# the hood sheet): the garage's fitted ids from the save, or in a test build
# the car's own mod_build. The bay (CarAssembler.build_bay) and the clash
# checkers want the ids as mod KEYS: a mod tree node's template ("turbo_small",
# "na_breathe") and a workshop bolt-on's id ("strut_bar_front"), which is
# what bay_kit.py names its variant parts by, so every car with the same
# template shares the parts' meaning.

const SaveStore := preload("res://scripts/save/save_store.gd")

## The fitted ids: mod tree node ids and bolt-on ids. The test build's car
## (PlayerCar.mod_build) first, else the garage's list for this car.
static func ids(player: Node, kind: String) -> Array[String]:
	var out: Array[String] = []
	var mb: Variant = player.get("mod_build") if player != null else null
	if mb is Dictionary and not (mb as Dictionary).is_empty():
		for n in (mb as Dictionary).get("nodes", []):
			out.append(String(n))
		for b in (mb as Dictionary).get("bolt_ons", []):
			out.append(String(b))
		return out
	for id in SaveStore.load_mod_tree().cars.get(kind, {}).get("installed", []):
		out.append(String(id))
	return out

## The ids as mod keys: a tree node becomes its template, anything else (a
## bolt-on) stays as it is. No doubles. With the car's spec, the car's tier
## comes along as "tier_T2".. (the cover's finish climbs with it, Roy 1570).
static func keys(kind: String, fitted: Array, spec: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	if not spec.is_empty():
		out.append("tier_" + ModTree.tier_of(spec))
	for id in fitted:
		var sid := String(id)
		var node := ModTree.node(kind, sid)
		var key := String(node.get("template", sid)) if not node.is_empty() else sid
		if key != "" and not out.has(key):
			out.append(key)
	return out

## Every set of keys the car can wear at once, for the checkers and the
## budget (the same sets tools/car_pipeline/fit_check.py bay_combos makes):
## [] (stock), then each path up the car's mod tree with every bay bolt-on
## (a variant key that is no template of the tree) on top. A car with no
## tree: stock and each variant key alone.
static func combos(kind: String, variants: Dictionary) -> Array:
	var out: Array = [[]]
	var nodes: Dictionary = ModTree.tree(kind).get("nodes", {}) if ModTree.has_tree(kind) else {}
	# a "tier_*" key is the car's tier finish: one at a time, on top of every set
	var tiers: Array = []
	for k in variants:
		if String(k).begins_with("tier_"):
			tiers.append(String(k))
	tiers.sort()
	if nodes.is_empty():
		var vkeys: Array = variants.keys()
		vkeys.sort()
		for k in vkeys:
			if not String(k).begins_with("tier_"):
				out.append([String(k)])
		return _with_tiers(out, tiers)
	var templates := {}
	for nid in nodes:
		templates[String(nodes[nid].get("template", ""))] = true
	var bolt_ons: Array = []
	for k in variants:
		if not templates.has(String(k)) and not String(k).begins_with("tier_"):
			bolt_ons.append(String(k))
	bolt_ons.sort()
	var seen := {}
	for nid in nodes:
		var chain: Array = []
		var at := String(nid)
		while nodes.has(at) and not chain.has(at):
			chain.append(at)
			var parent: Variant = nodes[at].get("parent", "")
			at = String(parent[0]) if parent is Array and not (parent as Array).is_empty() else String(parent)
		chain.reverse()
		var keys: Array = []
		for cid in chain:
			var t := String(nodes[cid].get("template", ""))
			if variants.has(t):
				keys.append(t)
		keys.append_array(bolt_ons)
		var tag := ",".join(PackedStringArray(keys))
		if not seen.has(tag):
			seen[tag] = true
			out.append(keys)
	return _with_tiers(out, tiers)

static func _with_tiers(sets: Array, tiers: Array) -> Array:
	var out: Array = sets.duplicate()
	for c in sets:
		for t in tiers:
			var keys: Array = (c as Array).duplicate()
			keys.append(t)
			out.append(keys)
	return out
