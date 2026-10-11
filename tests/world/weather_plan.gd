extends SceneTree

# The weather plan (W1, extended by WX0), checked without booting the game:
# the deck rules, the storm rate, season, the one mid-night change, damp
# starts, the fixed and boss nights, haze / fog / drizzle / snow, the numbers
# tables and Dave's lines. weather_plan.gd is pure tables and a seeded
# generator, so this is deterministic.
#   1 rules       no deck breaks a rule (wet run, storm adjacency, nights 1-3,
#                 one-step changes, boss nights mild, act ends dry)
#   2 storm rate  about 1 night in 20 over many acts (1 in 30 in winter)
#   3 repeatable  same seed, same deck; other seeds differ
#   4 season      winter acts are wetter than summer ones
#   5 mid-night   at most one change a night, some nights have one, the clock
#                 reads start then change; damp follows every wet night
#   6 numbers     dry = 1.0, bad weather fewer cars and cops, better pay
#   7 Dave        every kind of night has a forecast line
#   8 off         rain is still off (ROLL_ON false), nothing rolls by default
#   9 fixed       nights 1 2 8 16 27 28 29 30 have their stage
#  10 boss        boss nights draw only clear / haze / drizzle / after-rain
#  11 fog         at most 2 per act incl. night 16, never beside it
#  12 snow        none before night 28; free-mode winter acts: snow, snow on
#                 the roads, slush
#  13 pools       haze, fog and drizzle all get dealt, with their changes
#   CPU           one act's deck costs under BUDGET_MS, a lookup is free
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/weather_plan.gd

const Weather := preload("res://scripts/world/weather.gd")
const Plan := preload("res://scripts/world/weather_plan.gd")
const Cal := preload("res://scripts/world/season_calendar.gd")

const SEEDS := 200
## Acts: the three story acts, then free-mode acts across a year of months.
const STORY_ACTS := [[1, 10], [11, 22], [23, 30]]
const FREE_ACTS := [[31, 42], [43, 54], [55, 66], [67, 78], [79, 90], [91, 102], [103, 114],
	[115, 126], [127, 138], [139, 150], [259, 270], [295, 306]]
## Acts: the three story acts, then free-mode acts across a year of 28-night
## seasons (112 nights). Each free-mode act is wholly inside one season:
## 31-42 and 43-54 winter, 67-78 spring, 91-102 and 103-114 summer, 115-126
## and 127-138 autumn. (12-night acts and 28-night seasons only line up some
## of the time, so acts such as 55-66 that straddle a season are left out.)
## Acts that sit wholly inside one 28-night season (the F1 calendar).
const ACTS := [[1, 10], [11, 22], [23, 30], [31, 42], [43, 54], [67, 78], [91, 102], [103, 114], [115, 126], [127, 138]]
## Group 4 picks, the same number of acts each side.
const WINTER_ACTS := [[31, 42], [43, 54]]
const SUMMER_ACTS := [[91, 102], [103, 114]]
const BUDGET_MS := 2.0

var fails := 0

func check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: ", what)
	else:
		fails += 1
		printerr("FAIL: ", what)

func _initialize() -> void:
	var acts: Array = STORY_ACTS + FREE_ACTS
	# act ranges match the acts used below
	for a in acts:
		var r := Plan.act_range(a[0])
		if r.x != a[0] or r.y != a[1]:
			check(false, "act_range(%d) = %s, wanted %s" % [a[0], r, a])

	var bad := 0
	var first_bad := ""
	var storms_n := 0      # storms and nights in non-winter acts
	var nights_n := 0
	var storms_w := 0      # ... and in winter acts (free mode)
	var nights_w := 0
	var early_storms := 0
	var changes := 0
	var changes_wrong := 0
	var damp_ok := true
	var fixed_bad := 0
	var boss_bad := 0
	var snow_early := 0
	var fog_over := 0
	var fog_beside := 0
	var winter_acts := 0
	var winter_no_run := 0
	var roads_no_slush := 0
	var kinds := {}
	var change_kinds := {}
	var snow_in_act3 := 0
	var frost_nights := 0
	var frost_early := 0
	for sd in SEEDS:
		for a in acts:
			var deck := Plan.generate(a[0], a[1], sd)
			var v := Plan.violations(deck)
			if not v.is_empty():
				bad += 1
				if first_bad == "":
					first_bad = "seed %d act %d: %s" % [sd, a[0], v[0]]
			var winter: bool = a[0] > 30 and Plan.is_winter(a[0] + 6)
			var fogs := 0
			var saw_snow := false
			var saw_roads := false
			var saw_slush_after := false
			for i in deck.size():
				var e: Dictionary = deck[i]
				kinds[e.level] = int(kinds.get(e.level, 0)) + 1
				if winter:
					nights_w += 1
				else:
					nights_n += 1
				if e.level == Plan.STORM:
					if winter:
						storms_w += 1
					else:
						storms_n += 1
					if e.night <= 3:
						early_storms += 1
				if e.level == Plan.FOG:
					fogs += 1
					for j in [i - 1, i + 1]:
						if j >= 0 and j < deck.size() and e.night != 16 and deck[j].night == 16:
							fog_beside += 1
						if j >= 0 and j < deck.size() and e.night == 16 and deck[j].level == Plan.FOG:
							fog_beside += 1
				if e.level == Plan.SNOW or e.level == Plan.SLUSH:
					if e.night < 28:
						snow_early += 1
					if e.night >= 23 and e.night <= 27:
						snow_in_act3 += 1
				if e.level == Plan.SNOW and e.snow_roads:
					saw_roads = true
					if i + 1 < deck.size() and deck[i + 1].level == Plan.SLUSH:
						saw_slush_after = true
				if e.level == Plan.SNOW and not e.snow_roads:
					saw_snow = true
				if Plan.FIXED.has(e.night) and e.level != Plan.FIXED[e.night]:
					fixed_bad += 1
				if e.night in Plan.BOSS_NIGHTS:
					var mild: bool = e.level in Plan.MILD and e.change_to in Plan.MILD \
						and (e.start == Plan.DAMP or e.start in Plan.MILD)
					if not mild:
						boss_bad += 1
				if e.frost:
					frost_nights += 1
					if e.night < 20:
						frost_early += 1
				if e.change_hour >= 0:
					changes += 1
					var key := "%d>%d" % [e.start, e.change_to]
					change_kinds[key] = int(change_kinds.get(key, 0)) + 1
					var m := Plan.minutes_of(e.change_hour)
					if Plan.level_at(e, m - 1.0) != e.start or Plan.level_at(e, m) != e.change_to:
						changes_wrong += 1
				var wet_before: bool = (i > 0 and Plan.is_wet_level(deck[i - 1].level)) or (i == 0 and a[0] == 31)
				if (e.start == Plan.DAMP) != (e.level == Plan.DRY and wet_before):
					damp_ok = false
			if fogs > 2:
				fog_over += 1
			if winter:
				winter_acts += 1
				# acts with three winter nights in a row must hold the run
				if not (saw_snow and saw_roads and saw_slush_after):
					winter_no_run += 1
				if saw_roads and not saw_slush_after:
					roads_no_slush += 1
	check(bad == 0, "1 rules: %d acts x %d seeds, %d broke a rule %s" % [acts.size(), SEEDS, bad, first_bad])
	check(early_storms == 0, "1 rules: storms on nights 1-3: %d" % early_storms)

	# 2 storm rate
	var rate := float(storms_n) / float(nights_n)
	check(rate > 0.025 and rate < 0.07, "2 storm rate: %d in %d nights = 1 in %.1f (want about 1 in 20)" % [storms_n, nights_n, 1.0 / maxf(rate, 0.0001)])
	var rate_w := float(storms_w) / float(maxi(nights_w, 1))
	check(nights_w > 0 and rate_w < rate and rate_w > 0.01, "2 storm rate: winter acts rarer, %d in %d nights = 1 in %.1f (want about 1 in 30)" % [storms_w, nights_w, 1.0 / maxf(rate_w, 0.0001)])

	# 3 repeatable
	var d1 := Plan.generate(11, 22, 12345)
	var d2 := Plan.generate(11, 22, 12345)
	var same := str(d1) == str(d2)
	var differs := false
	for sd in range(1, 20):
		if str(Plan.generate(11, 22, 12345 + sd)) != str(d1):
			differs = true
			break
	check(same and differs, "3 repeatable: same seed same deck %s, other seeds differ %s" % [same, differs])
	check(str(Plan.entry(15, 99)) == str(Plan.entry(15, 99)) and Plan.entry(15, 99).night == 15, "3 entry(): cached lookup returns the night asked for")

	# 4 season: winter acts 31-54 against summer acts 91-114, same number of
	# acts each side, seasons from the 28-night calendar
	var wet_winter := 0
	var wet_summer := 0
	for sd in SEEDS:
		for a in WINTER_ACTS:
			for e in Plan.generate(a[0], a[1], sd):
				if e.level != Plan.DRY:
					wet_winter += 1
		for a in SUMMER_ACTS:
			for e in Plan.generate(a[0], a[1], sd):
				if e.level != Plan.DRY:
					wet_summer += 1
	check(Plan.season_name(31) == "winter" and Plan.season_name(91) == "summer", "4 season: night 31 is %s, night 91 is %s" % [Plan.season_name(31), Plan.season_name(91)])
	check(wet_winter > 1.5 * wet_summer and wet_summer > 0, "4 season: wet nights winter %d vs summer %d over %d seeds" % [wet_winter, wet_summer, SEEDS])
	var acts_whole := true
	for a in ACTS:
		if a[0] > Plan.STORY_NIGHTS and Cal.season_number(a[0]) != Cal.season_number(a[1]):
			acts_whole = false
	var picks_ok := true
	for a in WINTER_ACTS:
		picks_ok = picks_ok and Cal.season_index(a[0]) == 0 and Cal.season_index(a[1]) == 0
	for a in SUMMER_ACTS:
		picks_ok = picks_ok and Cal.season_index(a[0]) == 2 and Cal.season_index(a[1]) == 2
	check(acts_whole and picks_ok, "4 season: every free-mode act is inside one season, winter picks are winter, summer picks summer")
	# story nights keep the month calendar (season_at is the old season_of(month_of))
	var story_same := true
	for n in range(1, Plan.STORY_NIGHTS + 1):
		if Plan.season_at(n) != Plan.season_of(Plan.month_of(n)):
			story_same = false
	check(story_same, "4 season: story nights 1-30 take their season from the month calendar exactly as before")
	var free_same := true
	for n in range(31, 400):
		if Plan.season_at(n) != Cal.season_index(n):
			free_same = false
	check(free_same, "4 season: free-mode nights take theirs from the 28-night calendar")
	# 5 mid-night change
	check(changes_wrong == 0, "5 mid-night: clock reads start before the change hour and the new level from it (%d wrong)" % changes_wrong)
	var share := float(changes) / float(nights_n + nights_w)
	check(share > 0.05 and share < 0.7, "5 mid-night: %d of %d nights have a change (%.0f%%), at most one each" % [changes, nights_n + nights_w, share * 100.0])
	check(damp_ok, "5 damp: a dry night after a wet one starts damp, and only those do")
	check(Plan.minutes_of(20) == 0.0 and Plan.minutes_of(0) == 240.0 and Plan.minutes_of(4) == 480.0, "5 mid-night: hour to minutes since 8 p.m.")
	var allowed_seen := true
	for k in change_kinds:
		var parts: PackedStringArray = k.split(">")
		if not [int(parts[0]), int(parts[1])] in Plan.CHANGES:
			allowed_seen = false
	check(allowed_seen, "5 mid-night: only one-step changes were dealt (%s)" % str(change_kinds.keys()))

	# 6 numbers (the table is Weather.STAGE; weather_stages.gd checks every row)
	var S := Weather.STAGE
	var dry_ok: bool = S[Weather.Level.DRY].traffic == 1.0 and S[Weather.Level.DRY].cop == 1.0 and S[Weather.Level.DRY].pay == 1.0
	var damp_same: bool = S[Weather.Level.DAMP].traffic == 1.0 and S[Weather.Level.DAMP].cop == 1.0 and S[Weather.Level.DAMP].pay == 1.0
	var order: bool = S[Weather.Level.DOWNPOUR].traffic < S[Weather.Level.RAIN].traffic and S[Weather.Level.RAIN].traffic < 1.0 \
		and S[Weather.Level.DOWNPOUR].cop < S[Weather.Level.RAIN].cop and S[Weather.Level.RAIN].cop < 1.0 \
		and S[Weather.Level.RAIN].pay > 1.0 and S[Weather.Level.DOWNPOUR].pay == S[Weather.Level.RAIN].pay
	check(dry_ok and damp_same, "6 numbers: dry and damp nights change nothing (traffic, cops, pay all 1.0)")
	check(order, "6 numbers: storm < rain < 1 for cars and cops; pay is the same +15% for both")
	Weather.set_level(Weather.Level.DOWNPOUR, true)
	var storm_traffic := Weather.traffic_factor()
	var storm_pay := Weather.pay_factor()
	Weather.set_level(Weather.Level.DAMP, true)
	var damp_wet := Weather.wetness
	var damp_grip := Weather.rain_grip()
	Weather.reset()
	check(storm_traffic == S[Weather.Level.DOWNPOUR].traffic and storm_pay == 1.15 and Weather.traffic_factor() == 1.0, "6 numbers: accessors follow the level (storm pay %.2f)" % storm_pay)
	check(absf(damp_wet - 0.3) < 1e-6 and damp_grip > 0.9, "6 damp: wetness %.2f, grip %.3f (shallow wet, nearly dry grip)" % [damp_wet, damp_grip])

	# 7 Dave
	var lines_ok := true
	var variants := {}
	var change_line_missing := 0
	for sd in 40:
		for e in Plan.generate(11, 22, sd) + Plan.generate(55, 66, sd):
			var f := Plan.forecast_line(e)
			variants[f] = true
			if not f.begins_with("Dave: ") or f.length() < 20 or f.contains("{area}"):
				lines_ok = false
			if e.change_hour >= 0 and Plan.change_line(e) == "":
				# the one line-less change is clear to haze
				if not (e.start == Plan.DRY and e.change_to == Plan.HAZE):
					change_line_missing += 1
	check(lines_ok and change_line_missing == 0 and variants.size() >= 12,
		"7 Dave: every night kind has a forecast, every change but clear-to-haze a line (%d forecast variants, %d lines missing)" % [variants.size(), change_line_missing])

	# 8 off
	check(Weather.ROLL_ON == false and Weather.tonight.is_empty() and Weather.level == Weather.Level.DRY, "8 off: ROLL_ON %s, nothing planned, road dry" % Weather.ROLL_ON)

	# 9 fixed nights
	check(fixed_bad == 0, "9 fixed: nights 1 2 8 16 27 28 29 30 had their stage in every deck (%d wrong)" % fixed_bad)
	var f1 := Plan.entry(1, 777)
	var f2 := Plan.entry(2, 777)
	var f28 := Plan.entry(28, 777)
	var f29 := Plan.entry(29, 777)
	var f30 := Plan.entry(30, 777)
	check(f1.level == Plan.DRY and f2.level == Plan.DRY and Plan.entry(8, 777).level == Plan.DRY and Plan.entry(27, 777).level == Plan.DRY, "9 fixed: nights 1, 2, 8, 27 are clear")
	check(Plan.entry(16, 777).level == Plan.FOG and Plan.is_fog_night(16, 777), "9 fixed: night 16 is fog, and is_fog_night says so")
	check(f28.level == Plan.SNOW and not f28.snow_roads and f28.start == Plan.SNOW and f28.change_hour == -1, "9 fixed: night 28 is snow in the city from 8 p.m.")
	check(f29.level == Plan.SNOW and f29.snow_roads and f30.level == Plan.SLUSH, "9 fixed: night 29 snow on the roads, night 30 slush")

	# 10 boss nights
	check(boss_bad == 0, "10 boss: boss nights drew only clear, haze, drizzle or after-rain (%d broke it)" % boss_bad)

	# 11 fog
	check(fog_over == 0 and fog_beside == 0, "11 fog: at most 2 per act incl. night 16 (%d over), none beside 16 (%d)" % [fog_over, fog_beside])
	var extra_fog := 0
	for sd in SEEDS:
		for e in Plan.generate(11, 22, sd):
			if e.level == Plan.FOG and e.night != 16:
				extra_fog += 1
	check(extra_fog > SEEDS * 0.25 and extra_fog < SEEDS * 0.75, "11 fog: an extra fog night in about half of act 2 (%d of %d seeds)" % [extra_fog, SEEDS])

	# 12 snow
	check(snow_early == 0 and snow_in_act3 == 0, "12 snow: none before night 28 (%d), none in act 3 before 28 (%d)" % [snow_early, snow_in_act3])
	check(winter_acts > 0 and winter_no_run == 0 and roads_no_slush == 0,
		"12 snow: %d winter acts, each with snow, snow on the roads, then slush (%d without, %d roads night with no slush after)" % [winter_acts, winter_no_run, roads_no_slush])
	check(frost_early == 0 and frost_nights > 0, "5 frost: flagged only from night 20 (%d flagged, %d early)" % [frost_nights, frost_early])
	var fe := {"frost": true}
	check(Plan.frost_at(fe, Plan.DRY, Plan.minutes_of(3)) and not Plan.frost_at(fe, Plan.DRY, Plan.minutes_of(3) - 1.0) \
		and Plan.frost_at(fe, Plan.HAZE, Plan.minutes_of(4)) and not Plan.frost_at(fe, Plan.RAIN, Plan.minutes_of(4)) \
		and not Plan.frost_at({"frost": false}, Plan.DRY, Plan.minutes_of(4)), "5 frost: clear or haze, after 3 a.m., on frost nights only")

	# 13 pools: the new stages all get dealt, with their mid-night changes
	var pool_ok: bool = kinds.has(Plan.HAZE) and kinds.has(Plan.FOG) and kinds.has(Plan.DRIZZLE) and kinds.has(Plan.SNOW) and kinds.has(Plan.SLUSH)
	check(pool_ok, "13 pools: stages dealt %s" % str(kinds))
	var want_changes := ["0>1", "0>4", "4>5", "5>4", "6>1", "1>3", "2>1", "3>0"]
	var missing := []
	for w in want_changes:
		if not change_kinds.has(w):
			missing.append(w)
	check(missing.is_empty(), "13 pools: every change kind appears in the decks (missing %s)" % str(missing))
	var haze_share := float(kinds.get(Plan.HAZE, 0)) / float(nights_n + nights_w)
	check(haze_share > 0.1 and haze_share < 0.35, "13 pools: haze is about 0.3 of the dry nights left (%.0f%% of all nights)" % (haze_share * 100.0))

	# CPU
	var t0 := Time.get_ticks_usec()
	var reps := 200
	for k in reps:
		Plan.generate(11, 22, k)
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(reps)
	check(per_ms < BUDGET_MS, "CPU: one act's deck %.3f ms (budget %.1f), once per act" % [per_ms, BUDGET_MS])

	print("weather_plan: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
