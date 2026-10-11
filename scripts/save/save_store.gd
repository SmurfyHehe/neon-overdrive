extends RefCounted

# THE OLD SAVE API. Kept so its callers keep working (wallet, special
# vehicles, run end, the title screen, the garage and work board branches).
# New systems should not use it: add a block to the career and write it through
# SaveCore.commit() (scripts/save/save_core.gd, which also describes the files).
#
# Until save core S1 (2026-10-11) each slot was separate section files
# (wallet, garage, mod_tree, run, meta, special). The same functions now read
# and write the slot's career.json, night.json and meta.json:
#   load_wallet / save_wallet     cash -> the night, bank -> career wallet
#   load_garage / save_garage     career cars[*].parts_owned (all cars together)
#   load_mod_tree / save_mod_tree career cars[*].fitted
#   load_special / save_special   career special.unlocked
#   load_run / save_run / clear_run   the night
#   load_meta / begin_chase / end_chase / take_pending_bust   meta.json
#   first_wreck_used / mark_first_wreck   career walt.first_total_used
# A save_* that changes career data is a commit, so it is refused (false)
# during a chase, as every save was before.
#
# In test mode the folder is user://test_saves (TestMode).
# No class_name on purpose: preload it, so no class cache refresh is needed.

const AtomicJson := preload("res://scripts/save/atomic_json.gd")
const SaveCore := preload("res://scripts/save/save_core.gd")

const SLOTS := SaveCore.SLOTS
const DEFAULT_ROOT := SaveCore.DEFAULT_ROOT

static var root: String:
	get:
		return SaveCore.root
	set(v):
		SaveCore.root = v
## The slot being played, 1..SLOTS. Kept in <root>/active_slot.json.
static var slot: int:
	get:
		return SaveCore.slot
	set(v):
		SaveCore.slot = v
## True while a chase is on: nothing is written.
static var chase_active: bool:
	get:
		return SaveCore.chase_active
	set(v):
		SaveCore.chase_active = v

static func slot_dir(n: int = 0) -> String:
	return SaveCore.slot_dir(n)

## The path of one of the slot's files: "career", "night" or "meta".
static func file(name: String, n: int = 0) -> String:
	return SaveCore.file(name, n)

static func active_slot() -> int:
	return SaveCore.active_slot()

## Switches slots (the title screen calls this). Refused during a chase.
static func select_slot(n: int) -> bool:
	return SaveCore.select_slot(n)

## {"empty": bool, "saved_at": int, "cash": int, "bank": int, "plate": {...}}
## per slot, for a slot menu.
static func summary(n: int) -> Dictionary:
	return SaveCore.summary(n)

## The one way the career is written (see SaveCore.commit).
static func commit(reason: String, changes: Dictionary = {}) -> bool:
	return SaveCore.commit(reason, changes)

# ---------- chases ----------

static func begin_chase() -> bool:
	return SaveCore.begin_chase()

static func end_chase() -> bool:
	return SaveCore.end_chase()

## Reads meta.json and settles a chase left open by a quit or crash: it becomes
## a bust. Returns {"busted": bool, ...meta}.
static func load_meta() -> Dictionary:
	return SaveCore.settle_chase()

static func load_meta_raw() -> Dictionary:
	return SaveCore.meta()

## How many busts are waiting for a penalty; resets the count. For stage F.
static func take_pending_bust() -> int:
	return SaveCore.take_pending_bust()

# ---------- the first wreck ----------

## The first wreck of a slot is free (Moose and Walt, scripts/core/run_end.gd).
## True once it has been used.
static func first_wreck_used() -> bool:
	return SaveCore.meta().first_wreck_used

static func mark_first_wreck() -> bool:
	return SaveCore.mark_first_wreck()

# ---------- money ----------

static func load_wallet(n: int = 0) -> Dictionary:
	return {"cash": SaveCore.cash(n), "bank": SaveCore.bank(n)}

## Tonight's cash goes to the night. A bank that changed is a commit.
static func save_wallet(cash: int, bank: int) -> bool:
	if SaveCore.chase_active:
		return false
	if maxi(bank, 0) != SaveCore.bank():
		return SaveCore.commit("wallet", {"bank": bank, "cash": cash})
	return SaveCore.set_cash(cash)

# ---------- parts ----------

## Every part bought, all cars together.
static func load_garage(n: int = 0) -> Dictionary:
	var owned: Array[String] = []
	var cars := SaveCore._block(SaveCore.career(n), "cars")
	for id in cars:
		if cars[id] is Dictionary:
			for part in _string_list(cars[id].get("parts_owned")):
				if not part in owned:
					owned.append(part)
	return {"owned_parts": owned}

## A part no car owns yet goes to the car you drive; a part left out of the
## list is taken from the car that had it.
static func save_garage(owned_parts: Array) -> bool:
	var want := _string_list(owned_parts)
	return SaveCore.commit("garage", {}, func(c: Dictionary) -> void:
		var elsewhere := {}
		for id in c.cars:
			if id != c.current_car and c.cars[id] is Dictionary:
				var keep: Array[String] = []
				for part in _string_list(c.cars[id].get("parts_owned")):
					if part in want:
						keep.append(part)
						elsewhere[part] = true
				c.cars[id].parts_owned = keep
		var mine: Array[String] = []
		for part in want:
			if not elsewhere.has(part):
				mine.append(part)
		SaveCore.car_entry(c, c.current_car).parts_owned = mine)

## The mod tree, with every installed id checked against the parts owned.
## "damaged" is true when the newest copy of the career was broken.
static func load_mod_tree(n: int = 0) -> Dictionary:
	var owned: Array = load_garage(n).owned_parts
	var out := {}
	var cars := SaveCore._block(SaveCore.career(n), "cars")
	for id in cars:
		if not cars[id] is Dictionary:
			continue
		var fitted: Array[String] = []
		for part in _string_list(cars[id].get("fitted")):
			if part in owned:
				fitted.append(part)
		if not fitted.is_empty():
			out[str(id)] = {"installed": fitted}
	return {"cars": out, "damaged": SaveCore.career_damaged(n)}

## Replaces what every car has fitted: {car id: {"installed": [node id, ...]}}.
static func save_mod_tree(cars: Dictionary) -> bool:
	return SaveCore.commit("mod_tree", {}, func(c: Dictionary) -> void:
		for id in c.cars:
			if c.cars[id] is Dictionary:
				c.cars[id].erase("fitted")
		for id in cars:
			if cars[id] is Dictionary:
				SaveCore.car_entry(c, str(id)).fitted = _string_list(cars[id].get("installed")))

# ---------- special vehicles ----------

## Special vehicles unlocked in this slot (S0). Only true entries are kept.
static func load_special(n: int = 0) -> Dictionary:
	var raw := SaveCore._block(SaveCore._block(SaveCore.career(n), "special"), "unlocked")
	var out := {}
	for k in raw:
		if raw[k] == true:
			out[str(k)] = true
	return {"unlocked": out}

static func save_special(unlocked: Dictionary) -> bool:
	var out := {}
	for k in unlocked:
		if unlocked[k] == true:
			out[str(k)] = true
	return SaveCore.commit("special", {}, func(c: Dictionary) -> void: c.special.unlocked = out)

# ---------- the run ----------

## The run to resume ({} when there is none).
static func load_run(n: int = 0) -> Dictionary:
	return SaveCore.run(n)

## Writes the night and stamps meta.json. Refused during a chase.
static func save_run(data: Dictionary) -> bool:
	return SaveCore.write_night(data)

## A fresh run (restart, or a bust on return): the next launch spawns at the
## start. Money, parts, the clock and the car's wear stay. A commit.
static func clear_run() -> bool:
	return SaveCore.commit("run_end", {"clear_run": true})

# ---------- helpers ----------

static func _string_list(x: Variant) -> Array[String]:
	var out: Array[String] = []
	if x is Array:
		for v in x:
			if v is String and v != "" and not v in out:
				out.append(v)
	return out
