extends RefCounted

# Save upgrades (save core S1/S2, 2026-10-11). Old saves are upgraded, never
# thrown away. One step per version, run in order on load:
#   upgrade_1_to_2, later upgrade_2_to_3, ...
# Each step is a pure function on Dictionaries (no files, no scene), so a
# frozen old save in tests/save/fixtures/ can be run through the whole chain
# (tests/save/save_upgrade.gd). That test also fails when
# CURRENT_SAVE_VERSION is raised without adding the step that reaches it.
#
# A step takes the slot's files by name and returns the next version's files
# by name. SaveCore does the reading, the pre_v1/ copy and the writing.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const CURRENT_SAVE_VERSION := 2
const PATH := "res://scripts/save/save_upgrade.gd"
const DEFAULT_CAR := "p1_coupe"
const RECEIPTS_KEPT := 10

## True when the step from version `from` to the next one exists.
static func has_step(from: int) -> bool:
	var want := "upgrade_%d_to_%d" % [from, from + 1]
	for m in (load(PATH) as Script).get_script_method_list():
		if m.name == want:
			return true
	return false

## Runs every step from version `from` up to CURRENT_SAVE_VERSION. Returns {}
## (and logs) if a step is missing: the caller then leaves the old save alone.
static func upgrade(files: Dictionary, from: int) -> Dictionary:
	var out := files
	for v in range(from, CURRENT_SAVE_VERSION):
		if not has_step(v):
			push_error("SaveUpgrade: no step from save version %d to %d" % [v, v + 1])
			return {}
		out = (load(PATH) as Script).call("upgrade_%d_to_%d" % [v, v + 1], out)
	return out

## Version 1 (separate wallet / garage / mod_tree / run / meta / special files
## per slot, tunes, clock, dirt and the car picked kept outside the slot) to
## version 2 (career + night + meta, everything in the slot).
##
## Build 3 saves are version 1 with more in them: a shop.json (Walt's board),
## wallet.receipts, meta.weather_seed, and a run with weather, known_stops and
## the gearbox fields. All of it is carried over.
##
## files: {"wallet", "garage", "mod_tree", "run", "meta", "special", "shop": the
## old sections as read; "global": what lived outside the slot: {"car": id,
## "player_tune": {car id: {path: float}}, "exhaust_tune": {car id: {knob: float}},
## "tune_slots": {name: {path: float}}, "night_clock": {"minutes", "night"},
## "car_dirt": float}}. SaveCore hands the tunes, clock and dirt to the active
## slot only (a slot that was not being played starts with no saved tunes) and
## the car to every slot.
## Returns {"career", "night", "meta"}. Nothing owned is dropped.
static func upgrade_1_to_2(files: Dictionary) -> Dictionary:
	var wallet := _dict(files.get("wallet"))
	var garage := _dict(files.get("garage"))
	var tree := _dict(_dict(files.get("mod_tree")).get("cars"))
	var run := _dict(files.get("run")).duplicate(true)
	var meta := _dict(files.get("meta"))
	var special := _dict(_dict(files.get("special")).get("unlocked"))
	var g := _dict(files.get("global"))
	var car := str(g.get("car", DEFAULT_CAR))
	if car == "":
		car = DEFAULT_CAR

	var career := {"save_version": 2, "gen": 1, "current_car": car}
	# Money: the bank is owned, the cash belongs to the night in progress.
	career.wallet = {"bank": _whole(wallet.get("bank")), "receipts": []}
	for k in wallet:
		if not k in ["cash", "bank", "receipts"]:
			career.wallet[k] = wallet[k]   # a field this build does not know: kept
	# Shop receipts (build 3): the last RECEIPTS_KEPT, so no pay can be doubled.
	var receipts := _strings(wallet.get("receipts"))
	while receipts.size() > RECEIPTS_KEPT:
		receipts.remove_at(0)
	career.wallet.receipts = receipts
	# Walt's board for the day (build 3's shop.json).
	var shop := _dict(files.get("shop"))
	if not shop.is_empty():
		career.shop = shop.duplicate(true)
	# The weather seed (build 3 kept it in meta.json): once per game.
	if _whole(meta.get("weather_seed")) > 0:
		career.world = {"weather_seed": _whole(meta.weather_seed)}

	# Parts: each car owns what it has fitted and its own "<car>/<id>" parts; the
	# rest go to the car you drive.
	var owned := _strings(garage.get("owned_parts"))
	var placed := {}
	var cars := {}
	for id in tree:
		var fitted: Array[String] = []
		var mine: Array[String] = []
		for part in _strings(_dict(tree[id]).get("installed")):
			# As version 1 loaded it: fitted but never bought is not fitted. The
			# garage keeps a car's own parts as "<car>/<id>" (GarageMods).
			var own := part if part in owned else "%s/%s" % [id, part]
			if not own in owned:
				continue
			fitted.append(part)
			if not placed.has(own):
				placed[own] = true
				mine.append(own)
		cars[str(id)] = {"parts_owned": mine, "fitted": fitted}
	for part in owned:
		if not placed.has(part):
			# A car's own part ("<car>/<id>") stays with that car.
			var home := part.get_slice("/", 0) if part.contains("/") else car
			if home == "":
				home = car
			if not cars.has(home):
				cars[home] = {"parts_owned": [], "fitted": []}
			cars[home].parts_owned.append(part)
	if _is_num(g.get("car_dirt")):
		if not cars.has(car):
			cars[car] = {"parts_owned": [], "fitted": []}
		cars[car].dirt = clampf(float(g.car_dirt), 0.0, 1.0)
	career.cars = cars

	# Tunes: the per-car files to their cars, the named slots to the car you drive.
	var tunes := {}
	var live := _dict(g.get("player_tune"))
	for id in live:
		if live[id] is Dictionary and not live[id].is_empty():
			_tune(tunes, str(id)).live = live[id].duplicate(true)
	var exhaust := _dict(g.get("exhaust_tune"))
	for id in exhaust:
		if exhaust[id] is Dictionary and not exhaust[id].is_empty():
			_tune(tunes, str(id)).exhaust = exhaust[id].duplicate(true)
	var slots := _dict(g.get("tune_slots"))
	if not slots.is_empty():
		_tune(tunes, car).slots = slots.duplicate(true)
	career.tunes = tunes

	var unlocked := {}
	for k in special:
		if special[k] is bool and special[k]:
			unlocked[str(k)] = true
	career.special = {"unlocked": unlocked}
	career.walt = {"first_total_used": meta.get("first_wreck_used") is bool and meta.first_wreck_used}

	# The night: the saved run wins, then the old clock file, then night 1.
	var clock := _dict(run.get("clock"))
	if not _is_num(clock.get("night")):
		clock = _dict(g.get("night_clock"))
	var night_no := maxi(int(clock.night), 1) if _is_num(clock.get("night")) else 1
	career.story = {"night": night_no, "act": 1, "night_closed": night_no - 1}

	var night := run   # the run as it was, upgraded, not thrown away
	night.erase("version")
	night.save_version = 2
	night.base_gen = 1
	night.night = night_no
	night.cash = _whole(wallet.get("cash"))
	if not night.get("clock") is Dictionary and _is_num(clock.get("minutes")):
		night.clock = {"minutes": float(clock.minutes), "night": night_no}

	var new_meta := {}
	for k in meta:
		if not k in ["first_wreck_used", "weather_seed"]:
			new_meta[k] = meta[k]
	new_meta.save_version = 2
	new_meta.chase_open = meta.get("chase_open") is bool and meta.chase_open
	new_meta.pending_busts = _whole(meta.get("pending_busts"))
	new_meta.saved_at = _whole(meta.get("saved_at"))
	return {"career": career, "night": night, "meta": new_meta}

# ---------- helpers ----------

static func _tune(tunes: Dictionary, id: String) -> Dictionary:
	if not tunes.has(id):
		tunes[id] = {}
	return tunes[id]

static func _dict(x: Variant) -> Dictionary:
	return x if x is Dictionary else {}

static func _is_num(x: Variant) -> bool:
	return (x is float or x is int) and is_finite(float(x))

## A whole number >= 0, or 0.
static func _whole(x: Variant) -> int:
	return maxi(int(x), 0) if _is_num(x) else 0

static func _strings(x: Variant) -> Array[String]:
	var out: Array[String] = []
	if x is Array:
		for v in x:
			if v is String and v != "" and not v in out:
				out.append(v)
	return out
