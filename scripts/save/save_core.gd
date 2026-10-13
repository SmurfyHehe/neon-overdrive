extends RefCounted

# One save per slot (save core S1, 2026-10-11). Auto-save only.
#
#   user://saves/
#     active_slot.json
#     slot_N/
#       meta.json    slot plate + chase flag (tiny; the title screen reads only this)
#       career.json  everything owned and done; written only at commit points
#       night.json   the night in progress; written every 30 s while driving
#       pre_v1/      copy of the slot's old files from before the upgrade
#
# Every file carries "save_version" and is written crash-safely with three
# backups (atomic_json.gd).
#
# career.json blocks: gen (commit counter), world (seed, weather_seed,
# difficulty), wallet (bank, receipts), shop (Walt's board for the day), cars (per car id: parts_owned, fitted, wear, damage, fuel,
# dirt), current_car, tunes (per car id: live, exhaust, slots), story (night,
# act, night_closed), special (unlocked), walt (first_total_used), stats
# (play_secs), freemode (unlocked, entered_night; scripts/core/freemode.gd).
# A block this build does not know is kept and written back
# untouched: a new system adds its own block, it does not get a new file.
#
# night.json: where the run is (SaveDirector.capture), plus base_gen (the
# career gen it sits on), night, cash (tonight's cash), car_live (wear, damage,
# fuel and dirt of the car you are in), tunes_live (tune changes since the last
# commit) and play_secs.
#
# The career is written by commit() only, never while driving and never in a
# chase. A commit goes:
#   1. build the new career with gen + 1 (folding in car_live and tunes_live;
#      at dawn tonight's cash is added to the bank and the night is closed);
#   2. write career.json;
#   3. write night.json with base_gen = the new gen (at dawn and at a run end:
#      without the run);
#   4. write the meta.json plate.
# The game can die between any two steps and money is never lost or doubled.
# On load:
#   - night.night <= story.night_closed: dawn already banked it, the night is
#     dropped (the kill was between steps 2 and 3 of a dawn);
#   - night.base_gen < career.gen: position, clock, cash and radio come from
#     the night, the car's state from the career, which is newer;
#   - equal: resumed exactly.
# A slot whose files are newer than this build knows (save_version higher) is
# not loaded and never written: the game boots as if the slot were empty.
#
# Chases: nothing is saved while one is on. begin_chase() first writes
# chase_open in meta.json, so a quit or crash mid-chase is a bust on return.
#
# In test mode the folder is user://test_saves and `persist` is off: the car,
# tunes, clock and dirt of a test game are not read from or written to the slot
# unless a test turns it on.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const AtomicJson := preload("res://scripts/save/atomic_json.gd")
const SaveUpgrade := preload("res://scripts/save/save_upgrade.gd")
const TestMode := preload("res://scripts/core/test_mode.gd")
const Freemode := preload("res://scripts/core/freemode.gd")

const SLOTS := 3
const DEFAULT_ROOT := "user://saves"
const SAVE_VERSION := SaveUpgrade.CURRENT_SAVE_VERSION
const FILES := ["meta", "career", "night"]
const V1_FILES := ["wallet", "garage", "mod_tree", "run", "meta", "special", "shop"]
const DEFAULT_CAR := SaveUpgrade.DEFAULT_CAR
const DEFAULT_DIFFICULTY := "weekend_warrior"
const NIGHTS_TOTAL := 30   # stand-in for the plate until the story sets it
## What a car carries from night to night.
const LIVE_KEYS := ["wear", "damage", "fuel", "dirt"]
## night.json fields that are not the run itself: kept when the run is cleared.
const NIGHT_KEEP := ["night", "cash", "clock", "play_secs"]
const NIGHT_BOOKKEEPING := ["save_version", "base_gen", "night", "cash", "clock", "play_secs", "car_live", "tunes_live"]

static var _cache := {}      # path -> {"stamp": the file's time on disk, "data": Dictionary, "damaged": bool}
static var _upgraded := {}   # root -> true once its slots were checked for old saves
static var _locked := {}     # slot dir -> true when its files are newer than this build

static var root := TestMode.path(DEFAULT_ROOT):
	set(v):
		root = v
		forget()
## The slot being played, 1..SLOTS. Kept in <root>/active_slot.json.
static var slot := 0
## True while a chase is on: nothing is written.
static var chase_active := false
## The game's own car, tunes, clock and dirt live in the slot. Off in test mode.
static var persist := not TestMode.active()
## Where version 1 kept the tunes, clock, dirt and car pick. "" = not read
## (test mode, so a test never upgrades from Roy's real files).
static var legacy_dir := "" if TestMode.active() else "user://"
## Tests: commit() stops after this step (1..4), as if the game died there.
static var test_stop_after := 0


# ---------- slots ----------

static func slot_dir(n: int = 0) -> String:
	return root.path_join("slot_%d" % (n if n > 0 else active_slot()))

static func file(name: String, n: int = 0) -> String:
	return slot_dir(n).path_join(name + ".json")

static func active_slot() -> int:
	if slot < 1:
		# The newest copy holding a real slot number; a number out of range
		# (a bad hand edit) used to be clamped onto slot 3, so the save in use
		# looked gone.
		slot = 1
		var p := root.path_join("active_slot.json")
		for c in AtomicJson.candidates(p):
			if not FileAccess.file_exists(c):
				continue
			var d: Variant = AtomicJson.decode(FileAccess.get_file_as_string(c))
			var s: Variant = d.get("slot") if d is Dictionary else null
			if _is_whole(s) and int(s) >= 1 and int(s) <= SLOTS:
				slot = int(s)
				break
	return slot

## Switches slots. Refused during a chase.
static func select_slot(n: int) -> bool:
	if chase_active or n < 1 or n > SLOTS:
		return false
	_ensure()   # old saves are upgraded while the slot they were played in is still the active one
	slot = n
	return AtomicJson.write(root.path_join("active_slot.json"), {"slot": n})

## Drops what is held in memory of one slot (its folder was moved away).
static func forget_slot(n: int) -> void:
	for name in FILES:
		_cache.erase(file(name, n))
	_locked.erase(slot_dir(n))

## Drops everything held in memory, as a relaunch does.
static func forget() -> void:
	_cache.clear()
	_upgraded.clear()
	_locked.clear()

## True when the slot was saved by a newer build, or is an old save that could
## not be upgraded: not loaded, never written.
static func locked(n: int = 0) -> bool:
	var d := slot_dir(n)
	if not _locked.has(d):
		var newer := 0
		for name in FILES:
			var v: Variant = _read(file(name, n)).get("save_version", 0)
			if _is_num(v) and int(v) > SAVE_VERSION:
				newer = int(v)
		_locked[d] = newer > 0
		if newer > 0:
			push_warning("SaveCore: %s was saved by a newer version of the game (save version %d, this build knows %d); it is left untouched" % [d, newer, SAVE_VERSION])
	return _locked[d]

## For a slot menu: {"empty", "saved_at", "cash", "bank", "plate"}. Reads meta.json only.
static func summary(n: int) -> Dictionary:
	_ensure()
	var out := {"empty": true, "saved_at": 0, "cash": 0, "bank": 0, "plate": {}}
	if locked(n):
		return out
	for name in FILES:
		if AtomicJson.any_exists(file(name, n)):
			out.empty = false
	if out.empty:
		return out
	var m := _read(file("meta", n))
	var p := _block(m, "plate")
	if p.is_empty():
		p = plate(career(n), night(n))
	out.plate = p
	out.saved_at = _int(m.get("saved_at"))
	out.cash = _int(p.get("cash"))
	out.bank = _int(p.get("bank"))
	return out

# ---------- reading ----------

## The slot's career as it is on disk. A view: do not change it.
static func career(n: int = 0) -> Dictionary:
	_ensure()
	return {} if locked(n) else _read(file("career", n))

static func career_damaged(n: int = 0) -> bool:
	career(n)
	return _cache.get(file("career", n), {}).get("damaged", false)

static func gen(n: int = 0) -> int:
	return _int(career(n).get("gen"))

## The night in progress, after the load rules in the header. A view: do not change it.
static func night(n: int = 0) -> Dictionary:
	_ensure()
	if locked(n):
		return {}
	var raw := _read(file("night", n))
	if raw.is_empty():
		return raw
	var c := career(n)
	if _is_num(raw.get("night")) and int(raw.night) <= _int(_block(c, "story").get("night_closed")):
		return {}   # dawn already banked this night
	if _int(raw.get("base_gen")) < _int(c.get("gen")):
		var out := raw.duplicate()
		out.erase("car_live")     # the career is newer
		out.erase("tunes_live")
		return out
	return raw

## The run to resume, or {} when the night holds none.
static func run(n: int = 0) -> Dictionary:
	var nt := night(n)
	for k in nt:
		if not k in NIGHT_BOOKKEEPING:
			return nt
	return {}

static func bank(n: int = 0) -> int:
	if locked(n):
		return 0
	var v: Variant = _block(career(n), "wallet").get("bank")
	if _is_whole(v):
		return int(v)
	return _older_whole(file("career", n), "wallet", "bank")

## Tonight's cash.
static func cash(n: int = 0) -> int:
	var nt := night(n)
	if nt.is_empty() and not _read(file("night", n)).is_empty():
		return 0   # the night was banked
	if _is_whole(nt.get("cash")):
		return int(nt.cash)
	return _older_whole(file("night", n), "", "cash")

static func current_car(n: int = 0) -> String:
	var id: Variant = career(n).get("current_car")
	return id if id is String and id != "" else DEFAULT_CAR

## What the car carries: {"parts_owned", "fitted", "wear", "damage", "fuel",
## "dirt"} (only what was saved), the live state of the night on top.
static func car_state(car_id: String, n: int = 0) -> Dictionary:
	var out := _block(_block(career(n), "cars"), car_id).duplicate(true)
	var live := _block(night(n), "car_live")
	if live.get("car") == car_id:
		for k in LIVE_KEYS:
			if live.has(k):
				out[k] = live[k]
	return out

## The car's tunes: {"live": {path: float}, "exhaust": {knob: float},
## "slots": {name: {path: float}}} (only what was saved).
static func tune(car_id: String, n: int = 0) -> Dictionary:
	var out := _block(_block(career(n), "tunes"), car_id).duplicate(true)
	var live := _block(_block(night(n), "tunes_live"), car_id)
	for k in live:
		out[k] = live[k]
	return out

## {"minutes", "night"}: the night's clock, or the start of the story's night.
static func clock(n: int = 0) -> Dictionary:
	var c := _block(night(n), "clock")
	var night_no := maxi(_int(_block(career(n), "story").get("night", 1)), 1)
	if _is_num(c.get("minutes")):
		return {"minutes": float(c.minutes), "night": maxi(int(c.night), 1) if _is_num(c.get("night")) else night_no}
	return {"minutes": 0.0, "night": night_no}

static func play_secs(n: int = 0) -> int:
	return maxi(_int(_block(career(n), "stats").get("play_secs")), _int(night(n).get("play_secs")))

# ---------- the night ----------

## Writes the night in progress (SaveDirector's capture). Refused in a chase.
## Tonight's cash, the tune changes and the clock stay unless `data` has them.
static func write_night(data: Dictionary) -> bool:
	if not _may_write():
		return false
	var old := night()
	var nt := data.duplicate(true)
	nt.erase("version")   # the run's own number from version 1
	for k in ["cash", "tunes_live", "car_live", "clock", "night", "play_secs"]:
		if not nt.has(k) and old.has(k):
			nt[k] = old[k]
	var c: Variant = nt.get("clock")
	if c is Dictionary and _is_num(c.get("night")):
		nt.night = int(c.night)
	return _put_night(nt) and _write_meta({})

static func set_cash(amount: int) -> bool:
	if not _may_write():
		return false
	var nt := night().duplicate(true)
	nt.cash = maxi(amount, 0)
	return _put_night(nt) and _write_meta({})

static func set_clock(minutes: float, night_no: int) -> bool:
	if not _may_write():
		return false
	var nt := night().duplicate(true)
	nt.clock = {"minutes": minutes, "night": night_no}
	nt.night = night_no
	return _put_night(nt)

## A tune change (`key`: "live", "exhaust" or "slots") is kept with the night
## until the next commit folds it into the career.
static func set_tune(car_id: String, key: String, value: Dictionary) -> bool:
	if not _may_write() or car_id == "":
		return false
	var nt := night().duplicate(true)
	if not nt.get("tunes_live") is Dictionary:
		nt.tunes_live = {}
	if not nt.tunes_live.get(car_id) is Dictionary:
		nt.tunes_live[car_id] = {}
	nt.tunes_live[car_id][key] = value.duplicate(true)
	return _put_night(nt)

# ---------- the career ----------

## The one way the career is written. Never call it while driving; refused in
## a chase. `reason` is for the log ("dawn", "quit", "run_end", ...).
## changes: "bank": the bank now; "receipts": the shop receipts now (with the
## bank: a pay and its receipt are one write); "cash": tonight's cash now; "close_night": N
## banks night N (dawn; 0 = the story's current night); "clear_run": the run is
## over, the next load starts fresh; "car_live": the car's state now (else the
## night's); "current_car": the car you drive now.
## edit(career) may change the working copy before it is written.
static func commit(reason: String, changes: Dictionary = {}, edit: Callable = Callable()) -> bool:
	if not _may_write():
		return false
	# Step 1: the new career.
	var c := _read(file("career")).duplicate(true)
	fill_career(c)
	var nt := night().duplicate(true)
	var live: Variant = changes.get("car_live", nt.get("car_live"))
	if live is Dictionary and live.get("car") is String and live.car != "":
		var entry := car_entry(c, live.car)
		for k in LIVE_KEYS:
			if live.has(k):
				entry[k] = live[k].duplicate(true) if live[k] is Dictionary else live[k]
		nt.car_live = live
	var tl := _block(nt, "tunes_live")
	for id in tl:
		if tl[id] is Dictionary:
			if not c.tunes.get(id) is Dictionary:
				c.tunes[id] = {}
			for k in tl[id]:
				c.tunes[id][k] = tl[id][k]
	nt.erase("tunes_live")
	c.stats.play_secs = maxi(_int(c.stats.get("play_secs")), _int(nt.get("play_secs")))
	if _yes(_read(file("meta")).get("first_wreck_used")):
		c.walt.first_total_used = true
	if changes.has("bank"):
		c.wallet.bank = maxi(int(changes.bank), 0)
	if changes.get("receipts") is Array:
		c.wallet.receipts = changes.receipts.duplicate()
	if changes.get("current_car") is String and changes.current_car != "":
		c.current_car = changes.current_car
	if edit.is_valid():
		edit.call(c)
	var dawn := changes.has("close_night")
	var entered_night := 0
	var cash_now := maxi(int(changes.get("cash", _int(nt.get("cash")))), 0)
	if dawn:
		if not changes.has("bank"):
			# Tonight's cash goes into the bank, in the same write that closes the night.
			c.wallet.bank = _int(c.wallet.get("bank")) + cash_now
			cash_now = 0
		var closing := int(changes.close_night)
		if closing <= 0:
			closing = _int(c.story.get("night", 1))
		c.story.night_closed = maxi(_int(c.story.get("night_closed")), closing)
		c.story.night = int(c.story.night_closed) + 1
		# Stand-in for the credits screen: the dawn that ends night 30 enters
		# free mode, in the same write that banks the night.
		entered_night = Freemode.dawn_stand_in(c, closing)
	c.gen = _int(c.get("gen")) + 1
	c.save_version = SAVE_VERSION
	if test_stop_after == 1:
		return false
	# Step 2.
	if not _put(file("career"), c):
		push_error("SaveCore: the %s commit could not write the career" % reason)
		return false
	Freemode.refresh(c)
	if entered_night > 0:
		Freemode.fire_entered(entered_night)
	if test_stop_after == 2:
		return false
	# Step 3: the night on the new gen.
	var out := nt
	if dawn or _yes(changes.get("clear_run")):
		out = {}
		for k in NIGHT_KEEP:
			if nt.has(k):
				out[k] = nt[k]
	if dawn:
		out.erase("clock")   # the new night starts at 8 p.m.
		out.night = int(c.story.night)
	out.cash = cash_now
	var ok := _put_night(out)
	if test_stop_after == 3:
		return false
	# Step 4.
	return _write_meta({}) and ok

## Adds the blocks and fields `c` is missing, with their defaults. Nothing is
## removed: a block or field this build does not know stays.
static func fill_career(c: Dictionary) -> void:
	var defaults := {
		"world": {"seed": 0, "difficulty": DEFAULT_DIFFICULTY, "difficulty_next": DEFAULT_DIFFICULTY},
		"wallet": {"bank": 0, "receipts": []},
		"cars": {},
		"tunes": {},
		"story": {"night": 1, "act": 1, "night_closed": 0},
		"special": {"unlocked": {}},
		"walt": {"first_total_used": false},
		"stats": {"play_secs": 0},
	}
	if not c.get("world") is Dictionary:
		c.world = {}
	if not c.world.has("seed"):
		c.world.seed = randi()   # a new career: its own world seed
	for block in defaults:
		if not c.get(block) is Dictionary:
			c[block] = {}
		for k in defaults[block]:
			if not c[block].has(k):
				c[block][k] = defaults[block][k]
	Freemode.fill(c, maxi(_int(c.story.get("night", 1)), 1))
	if not c.get("current_car") is String or c.current_car == "":
		c.current_car = DEFAULT_CAR
	if not _is_num(c.get("gen")):
		c.gen = 0
	c.save_version = SAVE_VERSION

## The car's entry in a working career (made if missing).
static func car_entry(c: Dictionary, car_id: String) -> Dictionary:
	if not c.cars.get(car_id) is Dictionary:
		c.cars[car_id] = {}
	var e: Dictionary = c.cars[car_id]
	for k in ["parts_owned", "fitted"]:
		if not e.get(k) is Array:
			e[k] = []
	return e

## The slot plate the title screen shows.
static func plate(c: Dictionary, nt: Dictionary) -> Dictionary:
	var story := _block(c, "story")
	var world := _block(c, "world")
	var car: Variant = c.get("current_car")
	var night_no := maxi(_int(story.get("night", 1)), 1)
	var free := Freemode.active(c)
	return {"mode": "free" if free else "story", "car": car if car is String and car != "" else DEFAULT_CAR,
		"night": night_no, "act": maxi(_int(story.get("act", 1)), 1),
		"nights_total": NIGHTS_TOTAL,
		"cash": _int(nt.get("cash")), "bank": _int(_block(c, "wallet").get("bank")),
		"play_secs": maxi(_int(_block(c, "stats").get("play_secs")), _int(nt.get("play_secs"))),
		"difficulty": str(world.get("difficulty", DEFAULT_DIFFICULTY)),
		"freemode_season": Freemode.season_name(night_no) if free else null}

# ---------- meta: chases, busts, the free wreck ----------

## meta.json with every field this build reads, whatever was on disk.
static func meta(n: int = 0) -> Dictionary:
	_ensure()
	var m := {} if locked(n) else _read(file("meta", n))
	return {"chase_open": _yes(m.get("chase_open")),
		"pending_busts": _int(m.get("pending_busts")),
		"saved_at": _int(m.get("saved_at")),
		"first_wreck_used": _yes(m.get("first_wreck_used")) \
			or _yes(_block(career(n), "walt").get("first_total_used"))}

## The last write before a chase: marks it open, then blocks saving until
## end_chase(). Call it the moment the police start chasing.
static func begin_chase() -> bool:
	if chase_active:
		return true
	var ok := _write_meta({"chase_open": true})
	chase_active = true
	return ok

static func end_chase() -> bool:
	chase_active = false
	return _write_meta({"chase_open": false})

## Reads meta.json and settles a chase left open by a quit or crash: it becomes
## a bust (pending_busts + 1, written at once so a second relaunch does not
## bust again). Returns {"busted": bool, ...meta}.
static func settle_chase() -> Dictionary:
	chase_active = false
	var m := meta()
	var busted: bool = m.chase_open
	if busted:
		m.chase_open = false
		m.pending_busts += 1
		_write_meta({"chase_open": false, "pending_busts": m.pending_busts})
	m.busted = busted
	return m

static func take_pending_bust() -> int:
	var n: int = meta().pending_busts
	if n > 0:
		_write_meta({"pending_busts": 0})
	return n

## The first wreck of a slot is free. Marked in meta.json at once (it may be
## mid-chase) and folded into the career's walt block by the next commit.
static func mark_first_wreck() -> bool:
	var ok := _write_meta({"first_wreck_used": true})
	if not chase_active:
		commit("first_wreck")
	return ok

# ---------- files ----------

static func _may_write() -> bool:
	_ensure()
	return not chase_active and not locked()

## When the file on disk was last written (0 = no file). Asking the file
## system for this is cheap; opening the file is not (over 1 ms on Roy's laptop).
static func _stamp(path: String) -> int:
	return FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0

## The file's Dictionary ({} if no copy is good). Held in memory while the file
## on disk is the one this was read from or written to (forget() drops it).
static func _read(path: String) -> Dictionary:
	var stamp := _stamp(path)
	var c: Variant = _cache.get(path)
	if c != null and c.stamp == stamp:
		return c.data
	var r := AtomicJson.read(path)
	var data: Dictionary = r.get("data", {})
	_cache[path] = {"stamp": stamp, "data": data, "damaged": r.get("damaged", false)}
	return data

static func _put(path: String, data: Dictionary) -> bool:
	if not AtomicJson.write(path, data):
		_cache.erase(path)
		return false
	_cache[path] = {"stamp": _stamp(path), "data": data, "damaged": false}
	return true

## Every night write: on the career's gen now, and always with a night number
## (the load rule that stops a banked night's cash coming back needs it).
static func _put_night(nt: Dictionary) -> bool:
	var c := _read(file("career"))
	nt.save_version = SAVE_VERSION
	nt.base_gen = _int(c.get("gen"))
	if not _is_num(nt.get("night")):
		nt.night = maxi(_int(_block(c, "story").get("night", 1)), 1)
	if not _is_num(nt.get("cash")):
		nt.cash = 0
	return _put(file("night"), nt)

## Rewrites meta.json: `changes`, the time, and the plate. Allowed in a chase
## (the chase flag itself is written through here).
static func _write_meta(changes: Dictionary) -> bool:
	_ensure()
	if locked():
		return false
	var m := _read(file("meta")).duplicate(true)
	m.chase_open = _yes(m.get("chase_open"))
	m.pending_busts = _int(m.get("pending_busts"))
	m.merge(changes, true)
	m.save_version = SAVE_VERSION
	m.saved_at = int(Time.get_unix_time_from_system())
	m.plate = plate(_read(file("career")), night())
	return _put(file("meta"), m)

## A whole number >= 0 from the newest older copy that has a good one, else 0
## (a checksum-valid file with a bad money value: fall back field by field).
static func _older_whole(path: String, block: String, key: String) -> int:
	for p in AtomicJson.candidates(path):
		if not FileAccess.file_exists(p):
			continue
		var d: Variant = AtomicJson.decode(FileAccess.get_file_as_string(p))
		if d == null:
			continue
		var v: Variant = (_block(d, block) if block != "" else d).get(key)
		if _is_whole(v):
			return int(v)
	return 0

# ---------- upgrading old saves ----------

## Once per save folder: every slot still in an old format is upgraded.
static func _ensure() -> void:
	if _upgraded.has(root):
		return
	_upgraded[root] = true
	var active := active_slot()
	for n in range(1, SLOTS + 1):
		if _is_v1(n) and not _upgrade_v1(n, n == active):
			# Not upgraded: the old save stays as it is. The slot is closed to
			# this run of the game, so nothing is written next to or over it.
			_locked[slot_dir(n)] = true

## A version 1 slot: no good career.json copy, and any of the old section files.
## A torn career.json.tmp alone (the upgrade killed while writing it) does not
## count: it made the slot look upgraded, and it loaded as an empty save.
static func _is_v1(n: int) -> bool:
	if AtomicJson.read(file("career", n)).has("data"):
		return false
	for s in V1_FILES:
		if s != "meta" and AtomicJson.any_exists(file(s, n)):
			return true
	var m: Dictionary = AtomicJson.read(file("meta", n)).get("data", {})
	return not m.is_empty() and not m.has("save_version")

## False if the slot could not be upgraded (its old files are untouched).
static func _upgrade_v1(n: int, active: bool) -> bool:
	var dir := slot_dir(n)
	# The old files are copied aside first (copied, never moved).
	var pre := dir.path_join("pre_v1")
	DirAccess.make_dir_recursive_absolute(pre)
	for f in DirAccess.get_files_at(dir):
		var old := false
		for s in V1_FILES:
			old = old or f.begins_with(s + ".json")
		if not old or FileAccess.file_exists(pre.path_join(f)):
			continue
		# Copied under a .part name and renamed in whole: a copy cut short by a
		# crash is never taken for a finished one and skipped next time.
		var part := ProjectSettings.globalize_path(pre.path_join(f + ".part"))
		var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(dir.path_join(f)), part)
		if err == OK:
			err = DirAccess.rename_absolute(part, ProjectSettings.globalize_path(pre.path_join(f)))
		if err != OK:
			push_error("SaveCore: cannot copy %s to pre_v1 (%s); slot %d is not upgraded" % [f, error_string(err), n])
			return false
	var files := {"global": _legacy_globals(active)}
	for s in V1_FILES:
		files[s] = AtomicJson.read(file(s, n)).get("data", {})
	# Version 1 read its money field by field, from the newest copy that had a good value.
	files.wallet = files.wallet.duplicate(true)   # the receipts and anything else it held
	files.wallet.cash = _older_whole(file("wallet", n), "", "cash")
	files.wallet.bank = _older_whole(file("wallet", n), "", "bank")
	var out := SaveUpgrade.upgrade(files, 1)
	if out.is_empty():
		return false
	fill_career(out.career)
	out.meta.plate = plate(out.career, out.night)
	# The career goes in last but one: until it exists the slot still counts as
	# old, so a kill in here runs the upgrade again from the untouched files.
	# meta.json is last because it replaces an old file of the same name.
	if _put(file("night", n), out.night) and _put(file("career", n), out.career) and _put(file("meta", n), out.meta):
		print("SaveCore: slot %d upgraded from save version 1 to %d (old files copied to %s)" % [n, SAVE_VERSION, pre])
		return true
	push_error("SaveCore: slot %d could not be upgraded; its old files are untouched" % n)
	return false

## What version 1 kept outside the slot (see SaveUpgrade.upgrade_1_to_2). The
## car pick goes to every slot, the rest to the active one only.
static func _legacy_globals(active: bool) -> Dictionary:
	var g := {}
	if legacy_dir == "":
		return g
	var cfg := ConfigFile.new()
	if cfg.load(legacy_dir.path_join("settings.cfg")) == OK:
		var car: Variant = cfg.get_value("player", "car", "")
		if car is String and car != "":
			g.car = car
	if not active:
		return g
	var tunes := {}
	for f in DirAccess.get_files_at(legacy_dir):
		var id := ""
		if f == "player_tune.json":
			id = DEFAULT_CAR
		elif f.begins_with("player_tune_") and f.ends_with(".json"):
			id = f.trim_prefix("player_tune_").trim_suffix(".json")
		if id != "":
			var values := _block(_plain_json(legacy_dir.path_join(f)), "values")
			if not values.is_empty():
				tunes[id] = values
	g.player_tune = tunes
	g.exhaust_tune = _block(_plain_json(legacy_dir.path_join("exhaust_tune.json")), "cars")
	g.tune_slots = _block(_plain_json(legacy_dir.path_join("tune_slots.json")), "slots")
	if cfg.load(legacy_dir.path_join("night_clock.cfg")) == OK:
		g.night_clock = {"minutes": cfg.get_value("clock", "minutes", 0.0), "night": cfg.get_value("clock", "night", 1)}
	cfg = ConfigFile.new()
	if cfg.load(legacy_dir.path_join("car_dirt.cfg")) == OK:
		g.car_dirt = cfg.get_value("dirt", "level", 0.0)
	return g

static func _plain_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()  # parse() reports an error code; parse_string() prints an engine error
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	return json.data

# ---------- helpers ----------

static func _block(d: Dictionary, key: String) -> Dictionary:
	var b: Variant = d.get(key)
	return b if b is Dictionary else {}

static func _is_num(x: Variant) -> bool:
	return (x is float or x is int) and is_finite(float(x))

static func _is_whole(x: Variant) -> bool:
	return _is_num(x) and float(x) == floorf(float(x)) and float(x) >= 0.0

## True only for a real true. `x == true` is a script error when a damaged or
## hand-edited file holds a string there (Godot 4 does not compare across
## types), and that error stopped every later write of the slot.
static func _yes(x: Variant) -> bool:
	return x is bool and x

## A whole number >= 0, or 0.
static func _int(x: Variant) -> int:
	return maxi(int(x), 0) if _is_num(x) else 0
