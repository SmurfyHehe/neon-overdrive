extends RefCounted

# The save system (run structure, decided 2026-10-09). Auto-save only: there is
# no save button; the game writes on its own (SaveDirector says when).
#
# Three slots, user://saves/slot_1..3. Each slot is separate files, each one
# written crash-safely with three backups (atomic_json.gd), so one damaged file
# can never take the others with it:
#   wallet.json    {"cash": int, "bank": int}
#   garage.json    {"owned_parts": [part id, ...]}         every part ever bought
#   mod_tree.json  {"cars": {car_id: {"installed": [node id, ...]}}}
#   run.json       where the run is, to resume it exactly (SaveDirector)
#   special.json   {"unlocked": {vehicle id: bool}}        story-end special vehicles
#   meta.json      {"chase_open": bool, "pending_busts": int, "saved_at": unix}
#
# Bought parts live in garage.json, not in the mod tree: the tree only says
# which owned parts are fitted. If every copy of mod_tree.json is broken the
# tree loads empty (all parts back in the garage, unfitted), and money and
# parts are untouched. An installed id that is not owned is dropped on its own,
# not the whole tree. A wallet value that is not a whole number >= 0 falls
# back to the newest backup that has a good one, then to 0, field by field.
#
# Chases: nothing is saved while one is on (save() refuses). begin_chase()
# first writes chase_open = true in meta.json, so quitting, crashing or
# restarting mid-chase is seen on the way back: load_meta() turns an open
# chase into a bust (pending_busts + 1, the run is not resumed). The bust's
# penalty is for the police stage (F) to define; it reads take_pending_bust().
#
# In test mode the folder is user://test_saves (TestMode).
# No class_name on purpose: preload it, so no class cache refresh is needed.

const AtomicJson := preload("res://scripts/save/atomic_json.gd")
const TestMode := preload("res://scripts/core/test_mode.gd")

const SLOTS := 3
const DEFAULT_ROOT := "user://saves"
const SECTIONS := ["wallet", "garage", "mod_tree", "run", "meta", "special"]

static var root := TestMode.path(DEFAULT_ROOT)
## The slot being played, 1..SLOTS. Kept in <root>/active_slot.json.
static var slot := 0
## True while a chase is on: nothing is written.
static var chase_active := false

static func slot_dir(n: int = 0) -> String:
	return root.path_join("slot_%d" % (n if n > 0 else active_slot()))

static func file(section: String, n: int = 0) -> String:
	return slot_dir(n).path_join(section + ".json")

static func active_slot() -> int:
	if slot < 1:
		var r := AtomicJson.read(root.path_join("active_slot.json"))
		var s: Variant = r.get("data", {}).get("slot", 1)
		slot = clampi(int(s), 1, SLOTS) if (s is int or s is float) else 1
	return slot

## Switches slots (a slot menu will call this). Refused during a chase.
static func select_slot(n: int) -> bool:
	if chase_active or n < 1 or n > SLOTS:
		return false
	slot = n
	return AtomicJson.write(root.path_join("active_slot.json"), {"slot": n})

## {"empty": bool, "saved_at": int, "cash": int} per slot, for a slot menu.
static func summary(n: int) -> Dictionary:
	var empty := true
	for s in SECTIONS:
		if AtomicJson.any_exists(file(s, n)):
			empty = false
	var meta: Dictionary = AtomicJson.read(file("meta", n)).get("data", {})
	return {"empty": empty, "saved_at": int(meta.get("saved_at", 0)), "cash": load_wallet(n).cash}

# ---------- writing ----------

## Writes one section of the active slot. Refused (false) during a chase.
static func save(section: String, data: Dictionary) -> bool:
	if chase_active:
		return false
	return _write(section, data)

static func _write(section: String, data: Dictionary) -> bool:
	if not section in SECTIONS:
		push_error("SaveStore: unknown section %s" % section)
		return false
	return AtomicJson.write(file(section), data)

static func _touch_meta(changes: Dictionary) -> bool:
	var meta := load_meta_raw()
	meta.merge(changes, true)
	meta.saved_at = int(Time.get_unix_time_from_system())
	return _write("meta", meta)

# ---------- chases ----------

## The last write before a chase: marks it open, then blocks saving until
## end_chase(). Call it the moment the police start chasing.
static func begin_chase() -> bool:
	if chase_active:
		return true
	var ok := _touch_meta({"chase_open": true})
	chase_active = true
	return ok

## The chase is over (escaped or busted on the spot): saving is allowed again
## and the open mark is cleared.
static func end_chase() -> bool:
	chase_active = false
	return _touch_meta({"chase_open": false})

## Reads meta.json and settles a chase left open by a quit or crash: it becomes
## a bust (pending_busts + 1, chase_open cleared, written at once so a second
## relaunch does not bust again). Returns {"busted": bool, ...meta}.
static func load_meta() -> Dictionary:
	chase_active = false
	var meta := load_meta_raw()
	var busted := bool(meta.get("chase_open", false))
	if busted:
		meta.chase_open = false
		meta.pending_busts = int(meta.get("pending_busts", 0)) + 1
		meta.saved_at = int(Time.get_unix_time_from_system())
		_write("meta", meta)
	var out := meta.duplicate()
	out.busted = busted
	return out

static func load_meta_raw() -> Dictionary:
	var m: Dictionary = AtomicJson.read(file("meta")).get("data", {})
	return {"chase_open": m.get("chase_open", false) == true,
		"pending_busts": maxi(0, int(m.get("pending_busts", 0))) if _is_whole(m.get("pending_busts", 0)) else 0,
		"saved_at": int(m.get("saved_at", 0)) if _is_whole(m.get("saved_at", 0)) else 0,
		"first_wreck_used": m.get("first_wreck_used", false) == true}

# ---------- the first wreck ----------

## The first wreck of a slot is free (Moose and Walt, scripts/core/run_end.gd).
## True once it has been used.
static func first_wreck_used() -> bool:
	return load_meta_raw().first_wreck_used

static func mark_first_wreck() -> bool:
	return _touch_meta({"first_wreck_used": true})

## How many busts are waiting for a penalty; resets the count. For stage F.
static func take_pending_bust() -> int:
	var meta := load_meta_raw()
	var n: int = meta.pending_busts
	if n > 0:
		_touch_meta({"pending_busts": 0})
	return n

# ---------- sections ----------

static func load_wallet(n: int = 0) -> Dictionary:
	var out := {"cash": 0, "bank": 0}
	var left := out.keys()
	for p in AtomicJson.candidates(file("wallet", n)):
		if left.is_empty():
			break
		if not FileAccess.file_exists(p):
			continue
		var d: Variant = AtomicJson.decode(FileAccess.get_file_as_string(p))
		if d == null:
			continue
		for k in left.duplicate():
			if _is_whole(d.get(k)) and float(d[k]) >= 0.0:
				out[k] = int(d[k])
				left.erase(k)
	return out

static func save_wallet(cash: int, bank: int) -> bool:
	return save("wallet", {"cash": maxi(cash, 0), "bank": maxi(bank, 0)})

static func load_garage(n: int = 0) -> Dictionary:
	var d: Dictionary = AtomicJson.read(file("garage", n)).get("data", {})
	return {"owned_parts": _string_list(d.get("owned_parts", []))}

static func save_garage(owned_parts: Array) -> bool:
	return save("garage", {"owned_parts": _string_list(owned_parts)})

## The mod tree, with every installed id checked against the parts owned. A
## broken file gives an empty tree, never a loss of parts or money.
## "damaged" is true when the newest copy was broken.
static func load_mod_tree(n: int = 0) -> Dictionary:
	var r := AtomicJson.read(file("mod_tree", n))
	var owned: Array = load_garage(n).owned_parts
	var cars := {}
	var raw: Variant = r.get("data", {}).get("cars", {})
	if raw is Dictionary:
		for car_id in raw:
			var entry: Variant = raw[car_id]
			if not entry is Dictionary:
				continue
			var fitted: Array[String] = []
			for id in _string_list(entry.get("installed", [])):
				if id in owned and not id in fitted:
					fitted.append(id)
			cars[str(car_id)] = {"installed": fitted}
	return {"cars": cars, "damaged": r.get("damaged", false)}

static func save_mod_tree(cars: Dictionary) -> bool:
	return save("mod_tree", {"cars": cars})

## Special vehicles unlocked in this slot (S0). Only true entries are kept.
static func load_special(n: int = 0) -> Dictionary:
	var raw: Variant = AtomicJson.read(file("special", n)).get("data", {}).get("unlocked", {})
	var out := {}
	if raw is Dictionary:
		for k in raw:
			if raw[k] == true:
				out[str(k)] = true
	return {"unlocked": out}

static func save_special(unlocked: Dictionary) -> bool:
	var out := {}
	for k in unlocked:
		if unlocked[k] == true:
			out[str(k)] = true
	return save("special", {"unlocked": out})

static func load_run(n: int = 0) -> Dictionary:
	return AtomicJson.read(file("run", n)).get("data", {})

## Writes the run and stamps meta.json. Refused during a chase.
static func save_run(data: Dictionary) -> bool:
	if chase_active:
		return false
	return _write("run", data) and _touch_meta({})

## A fresh run (restart, or a bust on return): the run file is replaced with an
## empty one, so the next launch spawns at the start. Money and parts stay.
static func clear_run() -> bool:
	if chase_active:
		return false
	return _write("run", {})

# ---------- helpers ----------

static func _is_whole(x: Variant) -> bool:
	return (x is int) or (x is float and is_finite(x) and x == floorf(x))

static func _string_list(x: Variant) -> Array[String]:
	var out: Array[String] = []
	if x is Array:
		for v in x:
			if v is String and v != "" and not v in out:
				out.append(v)
	return out
