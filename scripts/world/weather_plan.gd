extends RefCounted

# The weather plan (W1): which night is dry, wet or stormy, decided up front
# for a whole act like a shuffled deck, so it can be forecast, tested and
# repeated on a reload. Pure tables and a seeded generator: no node, no
# per-tick work, no physics bodies, no particles. The only runtime cost is one
# lookup per night start and one per mid-night change.
#
#   deck per act    acts are nights 1-10, 11-22, 23-30 (run-structure doc);
#                   after the story, free mode runs in 12-night acts.
#   season by date  the night's calendar month sets how often a front comes.
#                   There is no story calendar yet, so a night's month is
#                   START_MONTH plus 30 nights per month; one function
#                   (month_of) to swap when the calendar lands.
#   fronts          rain comes as 1-3 night fronts, a dry night between them.
#   storms          about 1 night in 20, never in nights 1-3, never two in a
#                   row, always with a rain night before (the front arriving).
#   mid-night       at most ONE change per night: rain moves in, a front
#                   clears, a storm blows through, or last night's damp road
#                   dries out.
#   damp            the night after rain starts on a damp road (Level.DAMP).
#
# A storm is Weather.Level.DOWNPOUR. No class_name: preload it.

const Weather := preload("res://scripts/world/weather.gd")

const DRY := Weather.Level.DRY
const RAIN := Weather.Level.RAIN
const STORM := Weather.Level.DOWNPOUR
const DAMP := Weather.Level.DAMP

## Act boundaries on Weekend Warrior: first night of each act.
const ACT_FIRSTS := [1, 11, 23]
const STORY_NIGHTS := 30
const FREE_ACT_LEN := 12
## Placeholder calendar: night 1 falls in this month (October, the repo's
## current date), 30 nights to a month.
const START_MONTH := 10
const NIGHTS_PER_MONTH := 30

## Storms per night (Roy, 553), and the first night one may happen on (nights
## 1-3 are storm-free).
const STORM_RATE := 1.0 / 20.0
const STORM_FIRST_NIGHT := 4
## Longest run of wet nights in a row, storms included.
const MAX_WET_RUN := 3

## Chance a dry night starts a front, by season: winter, spring, summer,
## autumn. Picks, not measured; they give roughly a quarter of nights wet in
## winter and one in thirty in summer.
const FRONT_CHANCE := [0.22, 0.12, 0.03, 0.15]
## Front length weights: 1, 2, 3 nights.
const FRONT_LEN_CUM := [0.5, 0.85, 1.0]

## Hours (24 h clock) a mid-night change may land on.
const DRY_OUT_HOURS := [22, 23, 0, 1]
const SHIFT_HOURS := [1, 2, 3, 4]
## Chance of a mid-night change where one is possible.
const ARRIVAL_CHANCE := 0.5
const CLEAR_CHANCE := 0.5
const STORM_BLOW_THROUGH := 0.5

const SEASON_NAMES := ["winter", "spring", "summer", "autumn"]

static var _cache := {}

# ---------- calendar and acts ----------

## Calendar month 1-12 of a night (placeholder calendar, see above).
static func month_of(night: int) -> int:
	return ((START_MONTH - 1) + (maxi(night, 1) - 1) / NIGHTS_PER_MONTH) % 12 + 1

## 0 winter, 1 spring, 2 summer, 3 autumn (northern calendar).
static func season_of(month: int) -> int:
	match month:
		12, 1, 2:
			return 0
		3, 4, 5:
			return 1
		6, 7, 8:
			return 2
	return 3

static func season_name(night: int) -> String:
	return SEASON_NAMES[season_of(month_of(night))]

## First and last night of the act this night belongs to.
static func act_range(night: int) -> Vector2i:
	var n := maxi(night, 1)
	if n > STORY_NIGHTS:
		var first := STORY_NIGHTS + 1 + ((n - STORY_NIGHTS - 1) / FREE_ACT_LEN) * FREE_ACT_LEN
		return Vector2i(first, first + FREE_ACT_LEN - 1)
	for i in ACT_FIRSTS.size():
		var last: int = ACT_FIRSTS[i + 1] - 1 if i + 1 < ACT_FIRSTS.size() else STORY_NIGHTS
		if n <= last:
			return Vector2i(ACT_FIRSTS[i], last)
	return Vector2i(ACT_FIRSTS[ACT_FIRSTS.size() - 1], STORY_NIGHTS)

# ---------- the deck ----------

## Tonight's entry:
##   night, level (what the night is called), start (level at 8 p.m.),
##   change_hour (-1 = none, else the hour of the one change), change_to.
static func entry(night: int, seed: int) -> Dictionary:
	var r := act_range(night)
	var key := "%d:%d" % [seed, r.x]
	if not _cache.has(key):
		_cache[key] = generate(r.x, r.y, seed)
	return _cache[key][night - r.x]

## The whole act as an Array of entries, one per night.
static func generate(first: int, last: int, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "weather", first])
	var n := last - first + 1
	var lv: Array[int] = []
	lv.resize(n)
	lv.fill(DRY)

	# Fronts. The act's last night stays dry so one act never leaks a run into
	# the next, and a dry night follows every front.
	var i := 0
	while i < n - 1:
		var p: float = FRONT_CHANCE[season_of(month_of(first + i))]
		if rng.randf() < p:
			var roll := rng.randf()
			var flen := 1 if roll < FRONT_LEN_CUM[0] else (2 if roll < FRONT_LEN_CUM[1] else 3)
			flen = mini(flen, n - 1 - i)
			for k in flen:
				lv[i + k] = RAIN
			i += flen + 1
		else:
			i += 1

	# Storms: floor(n / 20) of them, plus one with the leftover chance, so
	# acts average one night in twenty.
	var want := float(n) * STORM_RATE
	var count := int(floor(want))
	if rng.randf() < want - float(count):
		count += 1
	var tries := 0
	while count > 0 and tries < 40:
		tries += 1
		var at := rng.randi_range(1, n - 2)  # night before it is in this act
		if first + at < STORM_FIRST_NIGHT or lv[at] == STORM:
			continue
		if lv[at - 1] == STORM or lv[at + 1] == STORM:
			continue
		# Prefer a night already in a front: try a few picks before settling.
		if lv[at] == DRY and tries < 20:
			continue
		# Try it on a copy: the storm, plus a rain lead-in when the night before
		# is dry. Refuse it if that makes a wet run too long.
		var trial := lv.duplicate()
		trial[at] = STORM
		if trial[at - 1] == DRY:
			trial[at - 1] = RAIN
		if _longest_wet_run(trial) > MAX_WET_RUN:
			continue
		lv = trial
		count -= 1

	# Entries, then the one mid-night change each night may get.
	var out: Array = []
	for k in n:
		var level := lv[k]
		var wet_before := k > 0 and lv[k - 1] != DRY
		var wet_next := k + 1 < n and lv[k + 1] != DRY
		var e := {"night": first + k, "level": level, "start": level,
			"change_hour": -1, "change_to": level}
		if level == DRY and wet_before:
			e.start = DAMP
			e.change_hour = DRY_OUT_HOURS[rng.randi_range(0, DRY_OUT_HOURS.size() - 1)]
			e.change_to = DRY
		elif level == DRY and wet_next:
			if rng.randf() < ARRIVAL_CHANCE:
				e.change_hour = SHIFT_HOURS[rng.randi_range(0, SHIFT_HOURS.size() - 1)]
				e.change_to = RAIN
		elif level == STORM:
			if rng.randf() < STORM_BLOW_THROUGH:
				e.change_hour = SHIFT_HOURS[rng.randi_range(0, SHIFT_HOURS.size() - 1)]
				e.change_to = RAIN
		elif level == RAIN and not wet_next:
			if rng.randf() < CLEAR_CHANCE:
				e.change_hour = SHIFT_HOURS[rng.randi_range(0, SHIFT_HOURS.size() - 1)]
				e.change_to = DAMP
		out.append(e)
	return out

static func _longest_wet_run(lv: Array) -> int:
	var best := 0
	var run := 0
	for l in lv:
		run = run + 1 if l != DRY else 0
		best = maxi(best, run)
	return best

## What the rules forbid in a deck; empty = fine. Used by the tests and
## cheap enough to run on any generated act.
static func violations(deck: Array) -> Array[String]:
	var bad: Array[String] = []
	var run := 0
	for i in deck.size():
		var e: Dictionary = deck[i]
		if e.level != DRY:
			run += 1
			if run > MAX_WET_RUN:
				bad.append("night %d: %d wet nights in a row" % [e.night, run])
		else:
			run = 0
		if e.level == STORM:
			if e.night < STORM_FIRST_NIGHT:
				bad.append("night %d: storm before night %d" % [e.night, STORM_FIRST_NIGHT])
			if i > 0 and deck[i - 1].level == STORM:
				bad.append("night %d: storm after a storm" % e.night)
			if i > 0 and deck[i - 1].level == DRY:
				bad.append("night %d: storm with no rain before it" % e.night)
		if e.change_hour >= 0 and (e.change_hour == 20 or e.change_hour == 6):
			bad.append("night %d: change on the hour the night starts or ends" % e.night)
		if e.change_hour >= 0 and e.change_to == e.start:
			bad.append("night %d: change to the same level" % e.night)
	if deck.size() > 0 and deck[deck.size() - 1].level != DRY:
		bad.append("act ends wet")
	return bad

# ---------- inside a night ----------

## Game minutes since 8 p.m. at an hour of the clock.
static func minutes_of(hour24: int) -> float:
	return float((((hour24 - 20) % 24) + 24) % 24) * 60.0

## The level at a time of the night (minutes since 8 p.m.): the start level
## until the change hour, the changed level after it.
static func level_at(e: Dictionary, minutes: float) -> int:
	if e.change_hour >= 0 and minutes >= minutes_of(e.change_hour):
		return e.change_to
	return e.start

static func is_wet(level: int) -> bool:
	return level == RAIN or level == STORM

# ---------- Dave's lines ----------
# Same voice as RadioStations.TIME_LINES (placeholders in the story bible).

static func hour_words(hour24: int) -> String:
	if hour24 == 0:
		return "midnight"
	if hour24 == 12:
		return "noon"
	if hour24 >= 20:
		return "%d p.m." % (hour24 - 12)
	return "%d a.m." % hour24

## Said at 8 p.m. (decision 561).
static func forecast_line(e: Dictionary) -> String:
	var ch: int = e.change_hour
	match e.start:
		DAMP:
			return "Dave: Roads are still wet from last night. Should dry out around %s." % hour_words(ch)
		RAIN:
			if ch >= 0 and e.change_to == DAMP:
				return "Dave: Rain tonight, easing off around %s." % hour_words(ch)
			return "Dave: Rain tonight. Slow down out there. You won't, but I said it."
		STORM:
			if ch >= 0:
				return "Dave: Storm warning. Worst of it before %s, then it blows through." % hour_words(ch)
			return "Dave: Storm warning for tonight. Heavy rain all night. Stay home if you can."
	if ch >= 0 and e.change_to == RAIN:
		return "Dave: Dry for now. Rain moves in around %s." % hour_words(ch)
	return "Dave: Clear and dry tonight. Enjoy it."

## Said when the one mid-night change lands.
static func change_line(e: Dictionary) -> String:
	match e.change_to:
		RAIN:
			return "Dave: That's the rain now. Told you."
		DAMP:
			return "Dave: Rain's done. Roads are wet, though."
		DRY:
			return "Dave: Roads are drying out. Good."
	return ""
