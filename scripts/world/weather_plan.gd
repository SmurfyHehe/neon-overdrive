extends RefCounted

# The weather plan (W1, extended by WX0): which night is clear, hazy, foggy,
# drizzly, wet, stormy or snowy, decided up front for a whole act like a
# shuffled deck, so it can be forecast, tested and repeated on a reload. Pure
# tables and a seeded generator: no node, no per-tick work, no physics
# bodies, no particles. The only runtime cost is one lookup per night start
# and one per mid-night change. entry() is pure: tonight's plan is never
# saved, only the seed it comes from (weather_seed, game.gd / save_store.gd).
#
#   deck per act    acts are nights 1-10, 11-22, 23-30 (run-structure doc);
#                   after the story, free mode runs in 12-night acts.
#   fixed nights    1, 2, 8 clear; 16 fog; 27 clear (the last clear night);
#                   28 snow in the city, 29 snow on the roads, 30 slush.
#   boss nights     10 12 17 19 21 24 25 26 draw only clear, haze, drizzle or
#                   after-rain. Fronts never land on one: a front ends the
#                   night before, so the boss night starts on a damp road.
#   dealt nights    everything else, from the deck: fixed and boss nights are
#                   pinned FIRST, then fronts, storms, drizzle, haze and one
#                   extra fog night are dealt around them.
#   season by date  the night's season sets how often a front comes. Story
#                   nights (1-30) take it from the calendar month: there is
#                   no story calendar yet, so a night's month is START_MONTH
#                   plus 30 nights per month (month_of). Free-mode nights
#                   (31 on) take it from the 28-night season calendar
#                   (SeasonCalendar, winter first), not from a month.
#   fronts          rain comes as 1-3 night fronts, a dry night between them;
#                   a front's first night may be drizzle, and a one-night
#                   front may be drizzle only.
#   storms          about 1 night in 20 (1 in 30 in a winter act), never
#                   before night 4, never two in a row, always with a rain
#                   night before (the front arriving).
#   freemode winter after night 30, acts in Dec-Feb get a snow night (white
#                   city), a snow night on white roads, and slush after.
#   mid-night       at most ONE change per night, never two steps, never at
#                   8 p.m. or 6 a.m. (the CHANGES table). A race in progress
#                   holds it until the race ends (game.gd).
#   damp            the night after wet weather starts on a damp road.
#   frost           a modifier flag, not a stage: nights 20+, clear or haze,
#                   after 3 a.m. (Weather.frost; visuals come later).
#
# A storm is Weather.Level.DOWNPOUR. No class_name: preload it.

const Weather := preload("res://scripts/world/weather.gd")
const SeasonCalendar := preload("res://scripts/world/season_calendar.gd")

const DRY := Weather.Level.DRY
const RAIN := Weather.Level.RAIN
const STORM := Weather.Level.DOWNPOUR
const DAMP := Weather.Level.DAMP
const HAZE := Weather.Level.HAZE
const FOG := Weather.Level.FOG
const DRIZZLE := Weather.Level.DRIZZLE
const SNOW := Weather.Level.SNOW
const SLUSH := Weather.Level.SLUSH

## Act boundaries on Weekend Warrior: first night of each act.
const ACT_FIRSTS := [1, 11, 23]
const STORY_NIGHTS := 30
const FREE_ACT_LEN := 12
## Placeholder calendar: night 1 falls in this month (October, the repo's
## current date), 30 nights to a month.
const START_MONTH := 10
const NIGHTS_PER_MONTH := 30

## Nights whose weather is set by the story (Roy 976-978).
const FIXED := {1: DRY, 2: DRY, 8: DRY, 16: FOG, 27: DRY, 28: SNOW, 29: SNOW, 30: SLUSH}
## Fixed nights whose snow is white roads (the others are the white city).
const ROADS_NIGHTS := [29]
## Boss nights: only the mild stages.
const BOSS_NIGHTS := [10, 12, 17, 19, 21, 24, 25, 26]
const MILD := [DRY, HAZE, DRIZZLE]

## Storms per night (Roy, 553), and the first night one may happen on (nights
## 1-3 are storm-free). Winter acts: rarer.
const STORM_RATE := 1.0 / 20.0
const WINTER_STORM_RATE := 1.0 / 30.0
const STORM_FIRST_NIGHT := 4
## Longest run of wet nights in a row, storms and snow included.
const MAX_WET_RUN := 3
## Fog nights in one act, night 16 included.
const MAX_FOG_PER_ACT := 2

## Chance a dry night starts a front, by season: winter, spring, summer,
## autumn. Picks, not measured; they give roughly a quarter of nights wet in
## winter and one in thirty in summer.
const FRONT_CHANCE := [0.22, 0.12, 0.03, 0.15]
## Front length weights: 1, 2, 3 nights.
const FRONT_LEN_CUM := [0.5, 0.85, 1.0]
## WX0 odds (Roy's stage list).
const HAZE_CHANCE := 0.3
const FOG_EXTRA_CHANCE := 0.5      # per act, besides night 16
const DRIZZLE_FIRST_CHANCE := 0.35 # a front's first night
const DRIZZLE_BOSS_CHANCE := 0.15  # a lone drizzle night on a boss night
const HAZE_FROM_CLEAR := 0.5       # a haze night that begins clear
const FOG_FROM_HAZE := 0.35        # a fog night that begins as haze
const FOG_LIFTS := 0.35            # a fog night that lifts to haze
const DRIZZLE_TO_RAIN := 0.3

## Hours (24 h clock) a mid-night change may land on.
const DRY_OUT_HOURS := [22, 23, 0, 1]   # after-rain -> clear, 10 p.m.-1 a.m.
const SHIFT_HOURS := [1, 2, 3, 4]       # clear -> rain, rain -> after-rain, storm -> rain
const HAZE_IN_HOURS := [23, 0, 1, 2]    # clear -> haze, 11 p.m.-2 a.m.
const FOG_IN_HOURS := [0, 1, 2, 3]      # haze -> fog, 12-3 a.m.
const FOG_OUT_HOURS := [3, 4, 5]        # fog -> haze, 3-5 a.m.
const DRIZZLE_UP_HOURS := [23, 0, 1, 2] # drizzle -> rain, 11 p.m.-2 a.m.
## Chance of a mid-night change where one is possible.
const ARRIVAL_CHANCE := 0.5
const CLEAR_CHANCE := 0.5
const STORM_BLOW_THROUGH := 0.5

## The only mid-night changes there are: [from, to].
const CHANGES := [[DRY, RAIN], [DRY, HAZE], [HAZE, FOG], [FOG, HAZE], [DRIZZLE, RAIN],
	[RAIN, DAMP], [STORM, RAIN], [DAMP, DRY]]

## Frost: from this night on, after this hour, on clear or haze.
const FROST_FIRST_NIGHT := 20
const FROST_FROM_HOUR := 3

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

## Season of a night: 0 winter ... 3 autumn. Free-mode nights follow the
## 28-night season calendar, story nights the placeholder month calendar.
static func season_at(night: int) -> int:
	if SeasonCalendar.is_free(night):
		return SeasonCalendar.season_index(night)
	return season_of(month_of(night))

static func season_name(night: int) -> String:
	return SEASON_NAMES[season_at(night)]

static func is_winter(night: int) -> bool:
	return season_at(night) == 0

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
##   night, level (what the night is called), start (stage at 8 p.m.),
##   change_hour (-1 = none, else the hour of the one change), change_to,
##   snow_roads (a SNOW night on white roads), frost (frost possible after
##   3 a.m. if the stage is then clear or haze), boss, pick (a seed-picked
##   number for Dave's line variants).
static func entry(night: int, seed: int) -> Dictionary:
	var r := act_range(night)
	var key := "%d:%d" % [seed, r.x]
	if not _cache.has(key):
		_cache[key] = generate(r.x, r.y, seed)
	return _cache[key][night - r.x]

## True when any part of this night is fog (the weather plan owns fog nights;
## the event plan does not roll its own).
static func is_fog_night(night: int, seed: int) -> bool:
	var e := entry(night, seed)
	return e.level == FOG or e.start == FOG or (e.change_hour >= 0 and e.change_to == FOG)

## Any stage with water, snow or slush on the road: runs of these are capped,
## and the night after one starts on a damp road.
static func is_wet_level(level: int) -> bool:
	return level == RAIN or level == STORM or level == DRIZZLE or level == SNOW or level == SLUSH

## The whole act as an Array of entries, one per night.
static func generate(first: int, last: int, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "weather", first])
	var n := last - first + 1
	var lv: Array[int] = []
	lv.resize(n)
	lv.fill(DRY)
	var pinned: Array[bool] = []
	pinned.resize(n)
	pinned.fill(false)
	var boss: Array[bool] = pinned.duplicate()
	var roads: Array[bool] = pinned.duplicate()
	var free_act := first > STORY_NIGHTS
	var winter_act := free_act and is_winter(first + n / 2)

	# 1 Pins: the story's nights, then (free mode, winter) the snow run. Done
	# before anything is dealt so no front, storm or fog can land on them.
	for k in n:
		var night := first + k
		if FIXED.has(night):
			lv[k] = FIXED[night]
			pinned[k] = true
			roads[k] = night in ROADS_NIGHTS
		elif night in BOSS_NIGHTS:
			pinned[k] = true
			boss[k] = true
	if first == STORY_NIGHTS + 1:
		pinned[0] = true  # the night after the finale's slush stays dry
	if free_act:
		# snow (white city), snow (white roads), slush: three winter nights in a
		# row, the slush never the act's last night.
		var windows: Array[int] = []
		for s in range(0, n - 3):
			if is_winter(first + s) and is_winter(first + s + 2) and not (pinned[s] or pinned[s + 1] or pinned[s + 2]):
				windows.append(s)
		if not windows.is_empty():
			var w := windows[rng.randi_range(0, windows.size() - 1)]
			lv[w] = SNOW
			lv[w + 1] = SNOW
			lv[w + 2] = SLUSH
			roads[w + 1] = true
			for j in 3:
				pinned[w + j] = true
			# A dry night either side, so a front never stretches the run.
			if w > 0:
				pinned[w - 1] = true
			pinned[w + 3] = true

	# 2 Fronts. The act's last night stays dry so one act never leaks a run
	# into the next, a pinned night breaks a front, and a dry night follows
	# every front.
	var i := 0
	while i < n - 1:
		if pinned[i]:
			i += 1
			continue
		var p: float = FRONT_CHANCE[season_at(first + i)]
		if rng.randf() < p:
			var roll := rng.randf()
			var flen := 1 if roll < FRONT_LEN_CUM[0] else (2 if roll < FRONT_LEN_CUM[1] else 3)
			flen = mini(flen, n - 1 - i)
			var k := 0
			while k < flen and not pinned[i + k]:
				lv[i + k] = RAIN
				k += 1
			i += k + 1
		else:
			i += 1

	# 3 Storms: floor(n * rate) of them, plus one with the leftover chance, so
	# acts average one night in twenty (one in thirty in a winter act).
	var want := float(n) * (WINTER_STORM_RATE if winter_act else STORM_RATE)
	var count := int(floor(want))
	if rng.randf() < want - float(count):
		count += 1
	var tries := 0
	while count > 0 and tries < 40:
		tries += 1
		var at := rng.randi_range(1, n - 2)  # night before it is in this act
		if first + at < STORM_FIRST_NIGHT or pinned[at] or lv[at] == STORM:
			continue
		if lv[at - 1] == STORM or lv[at + 1] == STORM:
			continue
		# Prefer a night already in a front: try a few picks before settling.
		if lv[at] == DRY and tries < 20:
			continue
		# Try it on a copy: the storm, plus a rain lead-in when the night before
		# is dry (never a pinned night). Refuse it if that makes a wet run too
		# long.
		var trial := lv.duplicate()
		trial[at] = STORM
		if trial[at - 1] == DRY:
			if pinned[at - 1]:
				continue
			trial[at - 1] = RAIN
		if _longest_wet_run(trial) > MAX_WET_RUN:
			continue
		lv = trial
		count -= 1

	# 4 Drizzle: a front's first night, unless a storm follows it (the storm
	# needs its rain night). A one-night front may be drizzle only. Boss nights
	# may draw a lone drizzle night between dry ones.
	for k in n:
		if lv[k] == RAIN and (k == 0 or not is_wet_level(lv[k - 1])):
			if k + 1 < n and lv[k + 1] == STORM:
				continue
			if rng.randf() < DRIZZLE_FIRST_CHANCE:
				lv[k] = DRIZZLE
		elif boss[k] and lv[k] == DRY and k < n - 1:  # the act still ends dry
			var quiet: bool = (k == 0 or not is_wet_level(lv[k - 1])) and (k + 1 >= n or not is_wet_level(lv[k + 1]))
			if quiet and rng.randf() < DRIZZLE_BOSS_CHANCE:
				lv[k] = DRIZZLE

	# 5 Haze: each remaining dry night, bar the story's clear nights and the
	# morning after rain (that one is after-rain, then clear).
	for k in n:
		if lv[k] != DRY or FIXED.has(first + k):
			continue
		if _wet_before(lv, k, first):
			continue
		if rng.randf() < HAZE_CHANCE:
			lv[k] = HAZE

	# 6 One extra fog night per act on a dealt night, not beside another.
	var fog_nights: Array[int] = []
	for k in n:
		if lv[k] == FOG:
			fog_nights.append(k)
	if fog_nights.size() < MAX_FOG_PER_ACT:
		var cands: Array[int] = []
		for k in n:
			if pinned[k] or (lv[k] != DRY and lv[k] != HAZE):
				continue
			var beside := false
			for f in fog_nights:
				if absi(f - k) <= 1:
					beside = true
			if not beside:
				cands.append(k)
		if not cands.is_empty() and rng.randf() < FOG_EXTRA_CHANCE:
			lv[cands[rng.randi_range(0, cands.size() - 1)]] = FOG

	# Entries, then the one mid-night change each night may get.
	var out: Array = []
	for k in n:
		var level := lv[k]
		var night2 := first + k
		var wet_before := _wet_before(lv, k, first)
		var wet_next := k + 1 < n and is_wet_level(lv[k + 1])
		var e := {"night": night2, "level": level, "start": level,
			"change_hour": -1, "change_to": level, "snow_roads": roads[k],
			"frost": night2 >= FROST_FIRST_NIGHT and (level == DRY or level == HAZE),
			"boss": boss[k], "pick": rng.randi() % 1000000}
		match level:
			DRY:
				if wet_before:
					e.start = DAMP
					e.change_hour = _hour(rng, DRY_OUT_HOURS)
					e.change_to = DRY
				elif wet_next and not boss[k]:
					if rng.randf() < ARRIVAL_CHANCE:
						e.change_hour = _hour(rng, SHIFT_HOURS)
						e.change_to = RAIN
			HAZE:
				if rng.randf() < HAZE_FROM_CLEAR:
					e.start = DRY
					e.change_hour = _hour(rng, HAZE_IN_HOURS)
					e.change_to = HAZE
			FOG:
				var r := rng.randf()
				if r < FOG_FROM_HAZE:
					e.start = HAZE
					e.change_hour = _hour(rng, FOG_IN_HOURS)
					e.change_to = FOG
				elif r < FOG_FROM_HAZE + FOG_LIFTS:
					e.change_hour = _hour(rng, FOG_OUT_HOURS)
					e.change_to = HAZE
			DRIZZLE:
				if not boss[k] and rng.randf() < DRIZZLE_TO_RAIN:
					e.change_hour = _hour(rng, DRIZZLE_UP_HOURS)
					e.change_to = RAIN
			STORM:
				if rng.randf() < STORM_BLOW_THROUGH:
					e.change_hour = _hour(rng, SHIFT_HOURS)
					e.change_to = RAIN
			RAIN:
				if not wet_next and rng.randf() < CLEAR_CHANCE:
					e.change_hour = _hour(rng, SHIFT_HOURS)
					e.change_to = DAMP
		out.append(e)
	return out

static func _hour(rng: RandomNumberGenerator, hours: Array) -> int:
	return hours[rng.randi_range(0, hours.size() - 1)]

## The night before was wet: this one starts on a damp road. The first night
## after the story follows night 30's slush.
static func _wet_before(lv: Array, k: int, first: int) -> bool:
	if k > 0:
		return is_wet_level(lv[k - 1])
	return first == STORY_NIGHTS + 1

static func _longest_wet_run(lv: Array) -> int:
	var best := 0
	var run := 0
	for l in lv:
		run = run + 1 if is_wet_level(l) else 0
		best = maxi(best, run)
	return best

## What the rules forbid in a deck; empty = fine. Used by the tests and
## cheap enough to run on any generated act.
static func violations(deck: Array) -> Array[String]:
	var bad: Array[String] = []
	var run := 0
	var fogs := 0
	for i in deck.size():
		var e: Dictionary = deck[i]
		var night: int = e.night
		if is_wet_level(e.level):
			run += 1
			if run > MAX_WET_RUN:
				bad.append("night %d: %d wet nights in a row" % [night, run])
		else:
			run = 0
		if e.level == FOG:
			fogs += 1
		if e.level == STORM:
			if night < STORM_FIRST_NIGHT:
				bad.append("night %d: storm before night %d" % [night, STORM_FIRST_NIGHT])
			if i > 0 and deck[i - 1].level == STORM:
				bad.append("night %d: storm after a storm" % night)
			if i > 0 and not is_wet_level(deck[i - 1].level):
				bad.append("night %d: storm with no rain before it" % night)
		if (e.level == SNOW or e.level == SLUSH) and night < 28:
			bad.append("night %d: snow before night 28" % night)
		if FIXED.has(night) and e.level != FIXED[night]:
			bad.append("night %d: fixed night is %d, wanted %d" % [night, e.level, FIXED[night]])
		if night in BOSS_NIGHTS:
			if not e.level in MILD:
				bad.append("night %d: boss night is stage %d" % [night, e.level])
			if e.change_hour >= 0 and not (e.change_to in MILD):
				bad.append("night %d: boss night changes to stage %d" % [night, e.change_to])
			if e.start != DAMP and not (e.start in MILD):
				bad.append("night %d: boss night starts at stage %d" % [night, e.start])
		if e.change_hour >= 0:
			if e.change_hour == 20 or e.change_hour == 6:
				bad.append("night %d: change on the hour the night starts or ends" % night)
			if e.change_to == e.start:
				bad.append("night %d: change to the same level" % night)
			elif not [e.start, e.change_to] in CHANGES:
				bad.append("night %d: change %d to %d is not a one-step change" % [night, e.start, e.change_to])
	if fogs > MAX_FOG_PER_ACT:
		bad.append("%d fog nights in one act" % fogs)
	if deck.size() > 0:
		var last: Dictionary = deck[deck.size() - 1]
		# The finale (night 30) is slush by design; every other act ends dry.
		if is_wet_level(last.level) and last.night != STORY_NIGHTS:
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

## Frost now: the night allows it, the stage is clear or haze, and it is past
## 3 a.m.
static func frost_at(e: Dictionary, level: int, minutes: float) -> bool:
	return bool(e.get("frost", false)) and (level == DRY or level == HAZE) \
		and minutes >= minutes_of(FROST_FROM_HOUR)

# ---------- Dave's lines ----------
# Same voice as RadioStations.TIME_LINES (placeholders in the story bible):
# tired, dry, kind underneath. Variants are picked by the entry's `pick`.

const HAZE_LINES := [
	"Bit of murk in the air tonight. Lamps look like they're thinking about something.",
	"Haze on the loop. Everything's a little further away than it looks.",
	"There's a film on the air tonight. Nothing dangerous. Just keep your eyes honest.",
]
const FOG_LINES := [
	"Fog on {area} tonight. Watch for the blue in the grey.",
	"Fog's down over {area}. You'll see the car ahead about when it sees you. Leave room.",
	"Thick fog on {area} tonight. Headlights make a wall of it. Dip them and trust the lines.",
]
const DRIZZLE_LINES := [
	"Drizzle. Not enough to stay home. Just enough to ruin your shoes.",
	"Light rain on the way. The kind that doesn't ask permission.",
	"A little drizzle tonight. The road's slicker than it looks.",
]
const SNOW_CITY_LINES := [
	"Snow's coming down. First of the year. Roads are just wet. For now.",
	"It's snowing in the city. Pretty from a window. The roads are only wet so far.",
]
const SNOW_ROADS_LINES := [
	"Ploughs did what they could. Stay in the tracks.",
	"Roads are white tonight. Stay in the tracks and keep your hands gentle.",
]
const SLUSH_LINES := [
	"Ploughed and salted. Grey, wet and slow. Middle of the lane's your friend.",
	"Slush out there. Grey and heavy and not forgiving. Middle of the lane.",
]
const FROST_LINES := [
	"Past three, bridges frost up. If it glitters, it's ice.",
	"After three the bridges go glassy. Glitter means ice. Lift early.",
]
const FOG_IN_LINE := "Dave: Fog's coming in off the water."
const FOG_OUT_LINE := "Dave: Fog's lifting. You can see what you were hiding from."
const DRIZZLE_UP_LINE := "Dave: Drizzle's grown up. Proper rain now."

static func hour_words(hour24: int) -> String:
	if hour24 == 0:
		return "midnight"
	if hour24 == 12:
		return "noon"
	if hour24 >= 20:
		return "%d p.m." % (hour24 - 12)
	return "%d a.m." % hour24

static func _variant(lines: Array, e: Dictionary) -> String:
	return lines[int(e.get("pick", 0)) % lines.size()]

## Said at 8 p.m. (decision 561). `area` is the name for fog lines ("the
## Harbour Flats"); empty says "the road".
static func forecast_line(e: Dictionary, area: String = "") -> String:
	var ch: int = e.change_hour
	var line := ""
	match e.level:
		HAZE:
			line = "Dave: " + _variant(HAZE_LINES, e)
		FOG:
			line = "Dave: " + _variant(FOG_LINES, e).replace("{area}", area if area != "" else "the road")
		DRIZZLE:
			line = "Dave: " + _variant(DRIZZLE_LINES, e)
			if ch >= 0 and e.change_to == RAIN:
				line += " Might turn to proper rain around %s." % hour_words(ch)
		SNOW:
			line = "Dave: " + _variant(SNOW_ROADS_LINES if e.get("snow_roads", false) else SNOW_CITY_LINES, e)
		SLUSH:
			line = "Dave: " + _variant(SLUSH_LINES, e)
		_:
			line = _classic_forecast(e)
	if bool(e.get("frost", false)):
		line += " " + _variant(FROST_LINES, e)
	return line

static func _classic_forecast(e: Dictionary) -> String:
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

## Said when the one mid-night change lands. Clear to haze has no line.
static func change_line(e: Dictionary) -> String:
	match e.change_to:
		RAIN:
			if e.start == DRIZZLE:
				return DRIZZLE_UP_LINE
			return "Dave: That's the rain now. Told you."
		DAMP:
			return "Dave: Rain's done. Roads are wet, though."
		DRY:
			return "Dave: Roads are drying out. Good."
		FOG:
			return FOG_IN_LINE
		HAZE:
			if e.start == FOG:
				return FOG_OUT_LINE
	return ""
