extends RefCounted

# THE OLD SAVE API. Kept so its callers keep working (wallet, special
# vehicles, run end, the title screen, the garage and work board branches).
# New systems should not use it: add a block to the career and write it through
# SaveCore.commit() (scripts/save/save_core.gd, which also describes the files).
#
# Until save core S1 (2026-10-11) each slot was separate section files
# (wallet, garage, mod_tree, run, meta, special). The same functions now read
# and write the slot's career.json, night.json and meta.json:
#   load_wallet / save_wallet     cash -> the night, bank and shop receipts ->
#                                 career wallet
#   load_shop / save_shop         career shop (Walt's board for the day, ShopDay)
#   weather_seed / set_weather_seed   career world.weather_seed
#   load_garage / save_garage     career cars[*].parts_owned (all cars together)
#   load_mod_tree / save_mod_tree career cars[*].fitted
#   save_parts                    both in one commit (the garage)
#   commit_wallet                 the wallet plus what it paid for, one commit
#   load_special / save_special   career special.unlocked
#   load_run / save_run / clear_run   the night
#   load_meta / begin_chase / end_chase / take_pending_bust   meta.json
#   first_wreck_used / mark_first_wreck   career walt.first_total_used
#   delete_slot                   moves the whole slot folder aside
# A save_* that changes career data is a commit, so it is refused (false)
# during a chase, as every save was before.
#
# In test mode the folder is user://test_saves (TestMode).
# No class_name on purpose: preload it, so no class cache refresh is needed.

const AtomicJson := preload("res://scripts/save/atomic_json.gd")
const SaveCore := preload("res://scripts/save/save_core.gd")

const SLOTS := SaveCore.SLOTS
const DEFAULT_ROOT := SaveCore.DEFAULT_ROOT
## How many shop receipts the career keeps (as Wallet.RECEIPTS_KEPT).
const RECEIPTS_KEPT := 10

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

## Deletes slot n's save (the title's Load > Delete a save; Roy, 2026-10-10).
## To the game the slot is empty afterwards. The folder is not destroyed: it is
## moved whole, backups included, to <root>/deleted/slot_<n>_<unix time>, where
## nothing reads it, so a save deleted by mistake can still be put back by
## hand. Refused during a chase. True when the slot is empty afterwards.
static func delete_slot(n: int) -> bool:
	if chase_active or n < 1 or n > SLOTS:
		return false
	var dir := slot_dir(n)
	if not DirAccess.dir_exists_absolute(dir):
		return true
	var bin := root.path_join("deleted")
	DirAccess.make_dir_recursive_absolute(bin)
	var to := bin.path_join("slot_%d_%d" % [n, int(Time.get_unix_time_from_system())])
	var k := 1
	while DirAccess.dir_exists_absolute(to if k == 1 else "%s_%d" % [to, k]):
		k += 1
	var ok := DirAccess.rename_absolute(dir, to if k == 1 else "%s_%d" % [to, k]) == OK
	SaveCore.forget_slot(n)
	return ok

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

## {"cash", "bank", "receipts"}. receipts: the last shop payments
## (Wallet.pay_shop), so a pay is never doubled.
static func load_wallet(n: int = 0) -> Dictionary:
	return {"cash": SaveCore.cash(n), "bank": SaveCore.bank(n), "receipts": _receipts(n)}

## Tonight's cash goes to the night. A bank or a receipt list that changed is
## one commit: the pay and its receipt are in the same career write.
## `car_live` (SaveDirector.car_live): the car's state now, written in the
## same commit, so a pump fill is paid and in the tank together.
static func save_wallet(cash: int, bank: int, receipts: Array = [], car_live: Dictionary = {}) -> bool:
	if SaveCore.chase_active:
		return false
	var kept := _kept_receipts(receipts)
	if maxi(bank, 0) != SaveCore.bank() or kept != _receipts():
		return commit_wallet("wallet", cash, bank, kept, car_live)
	return SaveCore.set_cash(cash)

## The wallet as one commit, with `edit` (what the money bought) in the same
## career write: a crash never takes the money without the goods, or the
## other way round.
static func commit_wallet(reason: String, cash: int, bank: int, receipts: Array, car_live: Dictionary = {}, edit: Callable = Callable(), extra: Dictionary = {}) -> bool:
	var changes := {"bank": bank, "cash": cash, "receipts": _kept_receipts(receipts)}
	if not car_live.is_empty():
		changes.car_live = car_live
	changes.merge(extra, true)
	return SaveCore.commit(reason, changes, edit)

static func _kept_receipts(receipts: Array) -> Array[String]:
	var kept := _string_list(receipts)
	while kept.size() > RECEIPTS_KEPT:
		kept.remove_at(0)
	return kept

static func _receipts(n: int = 0) -> Array[String]:
	return _string_list(SaveCore._block(SaveCore.career(n), "wallet").get("receipts"))

# ---------- Walt's board ----------

## Walt's board state for the day (ShopDay). {} when there is none yet.
static func load_shop(n: int = 0) -> Dictionary:
	return SaveCore._block(SaveCore.career(n), "shop").duplicate(true)

## A commit, so refused (false) during a chase.
static func save_shop(data: Dictionary) -> bool:
	var shop := data.duplicate(true)
	return SaveCore.commit("shop", {}, func(c: Dictionary) -> void: c.shop = shop)

# ---------- the weather seed (WX0) ----------

## The slot's weather seed (weather_plan.gd draws every night's weather from
## it plus the night number), 0 = none picked yet. Lives in the career's world
## block, so each slot has its own weather and it lasts the whole game.
static func weather_seed(n: int = 0) -> int:
	return SaveCore._int(SaveCore._block(SaveCore.career(n), "world").get("weather_seed"))

static func set_weather_seed(s: int) -> bool:
	var v := maxi(s, 1)
	return SaveCore.commit("weather_seed", {}, func(c: Dictionary) -> void: c.world.weather_seed = v)

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

## A part no car owns yet goes to the car you drive, or, when its id is
## "<car>/<id>" (GarageMods keeps a car's own parts that way), to that car; a
## part left out of the list is taken from the car that had it.
static func save_garage(owned_parts: Array) -> bool:
	return SaveCore.commit("garage", {}, apply_garage.bind(owned_parts))

## save_garage's change to a working career (for one commit with others).
static func apply_garage(c: Dictionary, owned_parts: Array) -> void:
	var want := _string_list(owned_parts)
	var placed := {}
	for id in c.cars:
		if c.cars[id] is Dictionary:
			var keep: Array[String] = []
			for part in _string_list(c.cars[id].get("parts_owned")):
				if part in want and not placed.has(part):
					keep.append(part)
					placed[part] = true
			c.cars[id].parts_owned = keep
	for part in want:
		if not placed.has(part):
			var home: String = part.get_slice("/", 0) if part.contains("/") else c.current_car
			SaveCore.car_entry(c, home if home != "" else c.current_car).parts_owned.append(part)

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
			# The garage keeps a car's own parts as "<car>/<id>" (GarageMods).
			if part in owned or ("%s/%s" % [id, part]) in owned:
				fitted.append(part)
		if not fitted.is_empty():
			out[str(id)] = {"installed": fitted}
	return {"cars": out, "damaged": SaveCore.career_damaged(n)}

## Replaces what every car has fitted: {car id: {"installed": [node id, ...]}}.
static func save_mod_tree(cars: Dictionary) -> bool:
	return SaveCore.commit("mod_tree", {}, apply_mod_tree.bind(cars))

## save_mod_tree's change to a working career.
static func apply_mod_tree(c: Dictionary, cars: Dictionary) -> void:
	for id in c.cars:
		if c.cars[id] is Dictionary:
			c.cars[id].erase("fitted")
	for id in cars:
		if cars[id] is Dictionary:
			SaveCore.car_entry(c, str(id)).fitted = _string_list(cars[id].get("installed"))

## The parts owned and the fitted lists in one commit (the garage). Two
## commits left a part owned but not fitted when the game died between them.
static func save_parts(owned_parts: Array, cars: Dictionary) -> bool:
	return SaveCore.commit("garage", {}, apply_parts.bind(owned_parts, cars))

static func apply_parts(c: Dictionary, owned_parts: Array, cars: Dictionary) -> void:
	apply_garage(c, owned_parts)   # parts first: the fitted lists are checked against them on load
	apply_mod_tree(c, cars)

# ---------- special vehicles ----------

## Special vehicles unlocked in this slot (S0). Only true entries are kept.
static func load_special(n: int = 0) -> Dictionary:
	var raw := SaveCore._block(SaveCore._block(SaveCore.career(n), "special"), "unlocked")
	var out := {}
	for k in raw:
		if SaveCore._yes(raw[k]):
			out[str(k)] = true
	return {"unlocked": out}

static func save_special(unlocked: Dictionary) -> bool:
	var out := {}
	for k in unlocked:
		if SaveCore._yes(unlocked[k]):
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
