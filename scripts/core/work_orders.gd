extends RefCounted

# Walt's board: the work orders, what they pay, and which three are on the
# board each morning (work board W0, 2026-10-11).
#
# Pure logic, no nodes. Money is whole dollars; pay is worked in thousandths of
# a "night" (NIGHT_VALUE dollars) with integer math, so a half-dollar never
# depends on float rounding. Shop pay goes to the bank only (Wallet.pay_shop).
#
# The numbers below are the only place they live for now. When data/economy.json
# lands, it replaces these constants.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const DATA_PATH := "res://data/work_orders.json"

const NIGHT_VALUE := 1500          # dollars per "night"
const ROUND_TO := 10               # dollars
const BAND_MIN := 0.10             # nights, any order
const BAND_MAX := 0.45
const SKIP_NIGHTS := 0.30          # "Leave it to Walt" flat pay
const STAY_LATE_SHARE := 1.0 / 3.0
const STAY_LATE_MAX := 0.15        # a third of the biggest band
const FAVOUR_COST := 0.05          # a friend's order pays this much less
const STAY_LATE_START_MINUTES := 60.0  # 9 p.m.; a normal night starts at 0 (8 p.m.)

## Percent, so the math stays in integers.
const ACT_PAY := {1: 100, 2: 200, 3: 300, "free": 300}
const DIFFICULTY_PAY := {"daily_driver": 125, "weekend_warrior": 100, "racer": 85}
const DEFAULT_DIFFICULTY := "weekend_warrior"  # until a difficulty setting exists

## Timing bar marks and needle (read by timing_bar.gd).
const MARK_CLEAN := 1.0
const MARK_OK := 0.7
const MARK_MISS := 0.0
const NEEDLE_BASE_PERIOD_S := 1.6
const NEEDLE_MISS_SPEEDUP := 1.15
const NEEDLE_CLEAN_SHARE := 0.25   # of the zone width
const MISSES_TO_GIVE_UP := 2

const STYLES := ["sweep", "bounce", "rush", "hold"]
const KINDS := ["bench", "scrap"]
const GIVERS := ["walt", "moose", "juno", "pilar", "teo", "ferris", "okafor", "jo", "dave", "rookie"]
## Givers away on some nights (inclusive ranges). Teo joins in act 2.
const GIVER_AWAY := {"teo": [[15, 18]]}
const FILL_PREFIX := "walt_regular_"
const FIRST_DAY_CARD := "halloran_brakes"
const CARDS := 3

static var _cache: Array = []

# ---------- the act ----------

## Nights 1-10 act 1, 11-22 act 2, 23-30 act 3, above that "free". Until story
## code exists the night number stands in for the act.
static func act_for_night(n: int) -> Variant:
	if n <= 10:
		return 1
	if n <= 22:
		return 2
	if n <= 30:
		return 3
	return "free"

# ---------- pay ----------

static func _nights_milli(order: Dictionary, score: float, flags: Dictionary) -> int:
	if flags.get("skip", false):
		return roundi(SKIP_NIGHTS * 1000.0)
	var pay: Dictionary = order.get("pay", {"min": BAND_MIN, "max": BAND_MIN})
	var lo := float(pay.get("min", BAND_MIN))
	var hi := float(pay.get("max", lo))
	var nights := lerpf(lo, hi, clampf(score, 0.0, 1.0))
	if order.get("favour", false):
		nights -= FAVOUR_COST
	var milli := roundi(nights * 1000.0)
	if flags.get("stay_late", false):
		milli = roundi(milli * STAY_LATE_SHARE)
		return clampi(milli, 0, roundi(STAY_LATE_MAX * 1000.0))
	return clampi(milli, roundi(BAND_MIN * 1000.0), roundi(BAND_MAX * 1000.0))

## Dollars for an order done at `score` (0..1). flags: {"stay_late", "skip"}.
static func pay_for(order: Dictionary, score: float, act: Variant, difficulty: String = DEFAULT_DIFFICULTY, flags: Dictionary = {}) -> int:
	var milli := _nights_milli(order, score, flags)
	var act_pct: int = ACT_PAY.get(act, 100)
	var diff_pct: int = DIFFICULTY_PAY.get(difficulty, 100)
	var numer: int = milli * NIGHT_VALUE * act_pct * diff_pct
	var denom: int = 1000 * 100 * 100 * ROUND_TO
	return ((numer + denom / 2) / denom) * ROUND_TO

## "Leave it to Walt": the flat pay.
static func skip_pay(act: Variant, difficulty: String = DEFAULT_DIFFICULTY) -> int:
	return pay_for({}, 0.0, act, difficulty, {"skip": true})

## [lowest, highest] dollars a card shows.
static func card_range(order: Dictionary, act: Variant, difficulty: String = DEFAULT_DIFFICULTY) -> Array:
	return [pay_for(order, 0.0, act, difficulty), pay_for(order, 1.0, act, difficulty)]

## "$300-$680"
static func range_text(order: Dictionary, act: Variant, difficulty: String = DEFAULT_DIFFICULTY) -> String:
	var r := card_range(order, act, difficulty)
	return "%s-%s" % [money(r[0]), money(r[1])]

static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return "$" + s + out

# ---------- the data ----------

## Problems with one row; an empty list is a good row.
static func validate(o: Dictionary) -> Array[String]:
	var e: Array[String] = []
	for k in ["id", "giver", "customer", "car", "problem", "kind", "steps", "pay", "favour", "lines", "unlock", "away", "weight"]:
		if not o.has(k):
			e.append("missing %s" % k)
	if not e.is_empty():
		return e
	if not (o.id is String and o.id != ""):
		e.append("bad id")
	var giver := str(o.giver)
	if not (giver in GIVERS or giver.begins_with("crew:")):
		e.append("unknown giver %s" % giver)
	if not str(o.kind) in KINDS:
		e.append("unknown kind %s" % str(o.kind))
	if not (o.steps is Array and o.steps.size() >= 1 and o.steps.size() <= 6):
		e.append("needs 1-6 steps")
	else:
		for s in o.steps:
			if not (s is Dictionary and s.has("zone") and s.has("speed") and s.has("style") and s.has("label")):
				e.append("bad step")
				continue
			if float(s.zone) < 0.08 - 0.0001 or float(s.zone) > 0.30 + 0.0001:
				e.append("zone %s out of range" % str(s.zone))
			if float(s.speed) < 0.8 - 0.0001 or float(s.speed) > 1.6 + 0.0001:
				e.append("speed %s out of range" % str(s.speed))
			if not str(s.style) in STYLES:
				e.append("unknown style %s" % str(s.style))
	if not (o.pay is Dictionary and o.pay.has("min") and o.pay.has("max")):
		e.append("bad pay")
	elif not (float(o.pay.min) >= BAND_MIN - 0.0001 and float(o.pay.min) <= float(o.pay.max) and float(o.pay.max) <= BAND_MAX + 0.0001):
		e.append("pay band %s-%s outside %s-%s" % [o.pay.min, o.pay.max, BAND_MIN, BAND_MAX])
	if not o.lines is Dictionary:
		e.append("bad lines")
	if not (o.unlock is Dictionary and o.away is Array):
		e.append("bad unlock/away")
	if not (o.weight is float or o.weight is int):
		e.append("bad weight")
	return e

## All orders, validated. A bad row is reported and left out.
static func load_orders(path: String = DATA_PATH) -> Array:
	if path == DATA_PATH and not _cache.is_empty():
		return _cache
	var out: Array = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Array:
		push_error("work_orders: %s is not a list" % path)
		return out
	for o in parsed:
		if not o is Dictionary:
			continue
		var errs := validate(o)
		if errs.is_empty():
			out.append(o)
		else:
			push_error("work_orders: %s: %s" % [str(o.get("id", "?")), "; ".join(errs)])
	if path == DATA_PATH:
		_cache = out
	return out

static func find(id: String) -> Dictionary:
	for o in load_orders():
		if o.id == id:
			return o
	return {}

# ---------- who is on the board ----------

## True when the order's giver is away that night (its own list or GIVER_AWAY).
static func is_away(order: Dictionary, night: int) -> bool:
	for r in order.get("away", []):
		if r is Array and r.size() == 2 and night >= int(r[0]) and night <= int(r[1]):
			return true
	for r in GIVER_AWAY.get(str(order.get("giver", "")), []):
		if night >= int(r[0]) and night <= int(r[1]):
			return true
	return false

## Unlocked when its night has come and its flag (if any) is set. A flag nobody
## has set yet keeps the order hidden. `flags` is the story flags, {name: true}.
static func is_unlocked(order: Dictionary, day: int, flags: Dictionary = {}) -> bool:
	var u: Dictionary = order.get("unlock", {})
	if day < int(u.get("from_night", 1)):
		return false
	var f: Variant = u.get("flag", null)
	if f != null and f != "" and flags.get(str(f), false) != true:
		return false
	return true

## The three cards for the morning after night `day`: order ids. Seeded by
## [slot, day], so a reload shows the same board. `recent` is the last orders
## taken. Walt's regulars fill the board when there are not enough others.
static func draw(slot: int, day: int, recent: Array, night: int = -1, orders: Array = [], flags: Dictionary = {}) -> Array[String]:
	if night < 0:
		night = day
	if orders.is_empty():
		orders = load_orders()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([slot, day])
	var avail: Array = []
	for o in orders:
		if is_unlocked(o, day, flags) and not is_away(o, night):
			avail.append(o)
	var picked: Array = []
	# Day 1 always opens with Halloran's brakes.
	if day == 1:
		for o in avail:
			if o.id == FIRST_DAY_CARD:
				picked.append(o)
	var pool: Array = []
	var fill: Array = []
	for o in avail:
		if o in picked or str(o.id) in recent:
			continue
		if str(o.id).begins_with(FILL_PREFIX):
			fill.append(o)
		pool.append(o)
	while picked.size() < CARDS:
		var valid: Array = []
		for o in pool:
			if _fits(o, picked):
				valid.append(o)
		if valid.is_empty():
			break
		var o: Dictionary = _weighted(valid, rng)
		picked.append(o)
		pool.erase(o)
	# Too few: Walt's regulars fill the rest (one per giver no longer applies).
	for o in fill:
		if picked.size() >= CARDS:
			break
		if not o in picked:
			picked.append(o)
	# Last resort, never expected: let recent orders back in.
	for o in avail:
		if picked.size() >= CARDS:
			break
		if not o in picked:
			picked.append(o)
	var ids: Array[String] = []
	for o in picked:
		ids.append(str(o.id))
	return ids

static func _fits(o: Dictionary, picked: Array) -> bool:
	for p in picked:
		if p.giver == o.giver:
			return false
		if p.kind == "scrap" and o.kind == "scrap":
			return false
	return true

static func _weighted(list: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for o in list:
		total += float(o.weight)
	var r := rng.randf() * total
	for o in list:
		r -= float(o.weight)
		if r <= 0.0:
			return o
	return list.back()
