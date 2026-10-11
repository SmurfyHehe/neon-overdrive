extends SceneTree

# The season calendar (freemode F1), checked without booting the game:
# weekdays, story vs free-mode nights, the 28-night seasons, the holiday, the
# Cup night, the thaw week, and the cost. season_calendar.gd is pure
# arithmetic on the night number.
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/season_calendar.gd

const Cal := preload("res://scripts/world/season_calendar.gd")

const LAST := 1000
const CALLS := 100000
const BUDGET_MS := 50.0

var fails := 0

func check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: ", what)
	else:
		fails += 1
		printerr("FAIL: ", what)

func _initialize() -> void:
	# weekdays
	check(Cal.weekday_name(1) == "Mon" and Cal.weekday_name(7) == "Sun" and Cal.weekday_name(27) == "Sat" \
		and Cal.weekday_name(30) == "Tue" and Cal.weekday_name(31) == "Wed",
		"weekdays: 1 %s, 7 %s, 27 %s, 30 %s, 31 %s" % [Cal.weekday_name(1), Cal.weekday_name(7), Cal.weekday_name(27), Cal.weekday_name(30), Cal.weekday_name(31)])

	# story nights
	var story_ok := true
	for n in range(1, 31):
		if Cal.is_free(n) or Cal.season_name(n) != "" or Cal.season_index(n) != -1 \
				or Cal.season_number(n) != 0 or Cal.night_in_season(n) != 0 or Cal.is_thaw(n) or Cal.is_winter(n):
			story_ok = false
	check(story_ok, "story: nights 1-30 are not free, season '' / -1 / 0, night-in-season 0, no thaw")
	check(Cal.is_free(31) and not Cal.is_free(30), "story: night 31 is the first free-mode night")

	# seasons
	check(Cal.season_name(31) == "winter" and Cal.season_number(31) == 1 and Cal.night_in_season(31) == 1, "seasons: night 31 is winter, season 1, night 1")
	check(Cal.season_name(58) == "winter" and Cal.season_number(58) == 1 and Cal.night_in_season(58) == 28, "seasons: night 58 is winter, season 1, night 28")
	check(Cal.season_name(59) == "spring" and Cal.season_name(86) == "spring", "seasons: 59-86 spring")
	check(Cal.season_name(87) == "summer" and Cal.season_name(114) == "summer", "seasons: 87-114 summer")
	check(Cal.season_name(115) == "autumn" and Cal.season_name(142) == "autumn", "seasons: 115-142 autumn")
	check(Cal.season_name(143) == "winter" and Cal.season_number(143) == 5, "seasons: night 143 is winter again, season 5")
	var seasons_ok := true
	var prev_k := 1
	for n in range(31, LAST + 1):
		var nis := Cal.night_in_season(n)
		if nis < 1 or nis > 28:
			seasons_ok = false
		var k := Cal.season_number(n)
		if k != prev_k:
			# the season changes exactly at night 1 of the new season, +1 only
			if nis != 1 or k != prev_k + 1:
				seasons_ok = false
			prev_k = k
		elif n > 31 and nis != Cal.night_in_season(n - 1) + 1:
			seasons_ok = false
		if n < Cal.season_first(k) or n > Cal.season_last(k):
			seasons_ok = false
	check(seasons_ok, "seasons: nights 31-%d have night-in-season 1-28 and the season changes exactly every 28 nights" % LAST)

	# holidays
	check(Cal.is_holiday(27) and Cal.is_holiday(55) and Cal.is_holiday(83) and Cal.is_holiday(111), "holidays: 27, 55, 83, 111")
	check(not Cal.is_holiday(28) and not Cal.is_holiday(54) and not Cal.is_holiday(56) and not Cal.is_holiday(1), "holidays: not 1, 28, 54, 56")
	var per_season := {}
	var hol_sat := true
	for n in range(31, LAST + 1):
		if Cal.is_holiday(n):
			var k := Cal.season_number(n)
			per_season[k] = per_season.get(k, 0) + 1
			if Cal.weekday(n) != Cal.SATURDAY:
				hol_sat = false
	var one_each := true
	for k in range(1, Cal.season_number(LAST)):
		if per_season.get(k, 0) != 1:
			one_each = false
	check(one_each and hol_sat, "holidays: exactly one in every full season up to night %d, always a Saturday" % LAST)

	# Cup night (Roy 1280: the Cup is the holiday night)
	var cup_ok := true
	var cup_bad := ""
	for k in range(1, 31):
		var c := Cal.cup_night(k)
		var later_sat := false
		for n in range(c + 1, Cal.season_last(k) + 1):
			if Cal.weekday(n) == Cal.SATURDAY:
				later_sat = true
		var holiday := -1
		for n in range(Cal.season_first(k), Cal.season_last(k) + 1):
			if Cal.is_holiday(n):
				holiday = n
		if Cal.weekday(c) != Cal.SATURDAY or Cal.season_number(c) != k or later_sat or c != holiday:
			cup_ok = false
			cup_bad = "season %d cup %d holiday %d" % [k, c, holiday]
	check(cup_ok, "cup: last Saturday of seasons 1-30, inside the season, no later Saturday, equals the holiday %s" % cup_bad)
	check(Cal.cup_night(1) == 55 and Cal.cup_night(2) == 83 and Cal.cup_night(3) == 111, "cup: season 1-3 on nights %d, %d, %d" % [Cal.cup_night(1), Cal.cup_night(2), Cal.cup_night(3)])

	# thaw and winter
	var thaw_ok := true
	for n in range(59, 66):
		thaw_ok = thaw_ok and Cal.is_thaw(n)
	for n in range(171, 178):
		thaw_ok = thaw_ok and Cal.is_thaw(n)
	check(thaw_ok, "thaw: nights 59-65 and 171-177 are thaw nights")
	check(not Cal.is_thaw(66) and not Cal.is_thaw(31) and not Cal.is_thaw(143) and not Cal.is_thaw(58), "thaw: 66, 31, 143, 58 are not")
	check(Cal.is_winter(31) and Cal.is_winter(58) and Cal.is_winter(143) and not Cal.is_winter(59) and not Cal.is_winter(30), "winter: 31-58 and 143 yes; 30 and 59 no")

	# CPU: CALLS calls in all, four different functions in turn
	var sink := 0
	var t0 := Time.get_ticks_usec()
	for i in CALLS / 4:
		var n := 1 + (i * 7) % 1200
		sink += Cal.weekday(n)
		sink += Cal.season_index(n)
		sink += Cal.night_in_season(n)
		if Cal.is_holiday(n):
			sink += 1
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	check(ms < BUDGET_MS, "CPU: %d mixed calls %.2f ms (budget %.0f ms, sink %d)" % [CALLS, ms, BUDGET_MS, sink])

	print("season_calendar: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
