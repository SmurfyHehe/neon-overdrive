class_name BoltOns
extends RefCounted

# The bolt-on row (mod tree step B1, 2026-10-10): 26 cheap parts that each
# change one number or one sound, in any order, on any car. The data is
# data/bolt_ons/bolt_ons.json; this file only reads it and applies it.
#
#   var spec := BoltOns.fit(CarSpec.player_spec("p0_beater"), ["short_shifter", "brake_pads"])
#
# A delta is relative ("mul" 1.02 = +2% on whatever the car has), so the same
# item fits every car. Levers the track sim cannot see (lamps, tow, heat,
# wear, fuel, sound) come back from effects(): the garage and the game read
# those; BoltOnWorth prices them.
#
# Not wired into the garage, the bank or the game's car yet: that is the mod
# tree's job (PR #267). This is the data and the maths, plus the worth sweep.

const PATH := "res://data/bolt_ons/bolt_ons.json"

static var _data: Dictionary = {}
static var _vehicle_defaults: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f == null:
			push_error("BoltOns: cannot read %s" % PATH)
			return {}
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("BoltOns: %s is not a JSON object" % PATH)
	return _data

## Every item as {id, label, notice, kind, est_worth, flair, giftable, deltas,
## effects, driver, step (0 = whole item, 1-3 for a stepped item), step_of}.
## A stepped item (the cabin strip) appears once per step, with its own id
## "cabin_strip_1" etc.
static func items() -> Array:
	var out: Array = []
	for raw in data().get("items", []):
		var base: Dictionary = raw
		if base.has("steps"):
			var n := 0
			for st in base.steps:
				n += 1
				var it: Dictionary = base.duplicate(true)
				it.erase("steps")
				it.merge(st, true)
				it["id"] = "%s_%d" % [base.id, n]
				it["step"] = n
				it["step_of"] = base.id
				out.append(it)
		else:
			var it2: Dictionary = base.duplicate(true)
			it2["step"] = 0
			out.append(it2)
	return out

static func ids() -> Array[String]:
	var out: Array[String] = []
	for it in items():
		out.append(it.id)
	return out

static func find(id: String) -> Dictionary:
	for it in items():
		if it.id == id:
			return it
	return {}

## The Service node's deltas (the Bug "after Service").
static func service_deltas() -> Dictionary:
	return data().get("service", {}).get("deltas", {})

## The spec with `deltas` applied (a new dictionary; `spec` is left alone). A key
## the spec does not carry (the Vehicle's own default, e.g. motor_moment) starts
## from that default.
static func apply_deltas(spec: Dictionary, deltas: Dictionary) -> Dictionary:
	var out := CarSpec.clone_spec(spec)
	for key in deltas:
		var op: Array = deltas[key]
		var kind := String(op[0])
		var v := float(op[1])
		var cur := float(out[key]) if out.has(key) else _vehicle_default(String(key))
		match kind:
			"mul": out[key] = cur * v
			"add": out[key] = cur + v
			"set": out[key] = v
			_: push_error("BoltOns: unknown op '%s' on %s" % [kind, key])
	return out

## Fits the listed items (by id) on a car's spec, in the order given.
static func fit(spec: Dictionary, item_ids: Array) -> Dictionary:
	var out := CarSpec.clone_spec(spec)
	for id in item_ids:
		var it := find(String(id))
		if it.is_empty():
			push_error("BoltOns.fit: no item '%s'" % id)
			continue
		out = apply_deltas(out, it.get("deltas", {}))
	return out

## The merged non-sim levers of the listed items. Numeric levers named *_mul
## multiply together; flags are or-ed; other numbers are summed.
static func effects(item_ids: Array) -> Dictionary:
	var out := {}
	for id in item_ids:
		var fx: Dictionary = find(String(id)).get("effects", {})
		for key in fx:
			var val: Variant = fx[key]
			if not out.has(key):
				out[key] = val
			elif val is bool:
				out[key] = bool(out[key]) or bool(val)
			elif String(key).ends_with("_mul"):
				out[key] = float(out[key]) * float(val)
			else:
				out[key] = float(out[key]) + float(val)
	return out

## A Vehicle property's default (the spec only carries what a car overrides).
static func _vehicle_default(key: String) -> float:
	if not _vehicle_defaults.has(key):
		var v := Vehicle.new()
		_vehicle_defaults[key] = float(v.get(key))
		v.free()
	return _vehicle_defaults[key]
