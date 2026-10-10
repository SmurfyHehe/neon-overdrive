extends SceneTree

# The weather plan (W1), checked without booting the game: the deck rules,
# the storm rate, season, the one mid-night change, damp starts, the numbers
# tables and Dave's lines. weather_plan.gd is pure tables and a seeded
# generator, so this is deterministic.
#   1 rules       no deck breaks a rule (wet run, storm adjacency, nights 1-3)
#   2 storm rate  about 1 night in 20 over many acts
#   3 repeatable  same seed, same deck; other seeds differ
#   4 season      winter acts are wetter than summer ones
#   5 mid-night   at most one change a night, some nights have one, the clock
#                 reads start then change; damp follows every wet night
#   6 numbers     dry = 1.0, bad weather fewer cars and cops, better pay
#   7 Dave        every kind of night has a forecast line
#   8 off         rain is still off (ROLL_ON false), nothing rolls by default
#   CPU           one act's deck costs under BUDGET_MS, a lookup is free
# (Storms are a flat 1 in 20 in every season, so summer keeps those; only the
# fronts follow the season.)
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/weather_plan.gd

const Weather := preload("res://scripts/world/weather.gd")
const Plan := preload("res://scripts/world/weather_plan.gd")

const SEEDS := 300
## Acts: the three story acts, then free-mode acts across a year of months.
const ACTS := [[1, 10], [11, 22], [23, 30], [31, 42], [43, 54], [91, 102], [259, 270], [295, 306]]
const BUDGET_MS := 2.0

var fails := 0

func check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: ", what)
	else:
		fails += 1
		printerr("FAIL: ", what)

func _initialize() -> void:
	# act ranges match the acts used below
	for a in ACTS:
		var r := Plan.act_range(a[0])
		if r.x != a[0] or r.y != a[1]:
			check(false, "act_range(%d) = %s, wanted %s" % [a[0], r, a])

	# 1 rules
	var bad := 0
	var first_bad := ""
	var storms := 0
	var nights := 0
	var early_storms := 0
	var changes := 0
	var changes_wrong := 0
	var damp_ok := true
	for sd in SEEDS:
		for a in ACTS:
			var deck := Plan.generate(a[0], a[1], sd)
			var v := Plan.violations(deck)
			if not v.is_empty():
				bad += 1
				if first_bad == "":
					first_bad = "seed %d act %d: %s" % [sd, a[0], v[0]]
			for i in deck.size():
				var e: Dictionary = deck[i]
				nights += 1
				if e.level == Plan.STORM:
					storms += 1
					if e.night <= 3:
						early_storms += 1
				if e.change_hour >= 0:
					changes += 1
					var m := Plan.minutes_of(e.change_hour)
					if Plan.level_at(e, m - 1.0) != e.start or Plan.level_at(e, m) != e.change_to:
						changes_wrong += 1
				var wet_before: bool = i > 0 and deck[i - 1].level != Plan.DRY
				if (e.start == Plan.DAMP) != (e.level == Plan.DRY and wet_before):
					damp_ok = false
	check(bad == 0, "1 rules: %d acts x %d seeds, %d broke a rule %s" % [ACTS.size(), SEEDS, bad, first_bad])
	check(early_storms == 0, "1 rules: storms on nights 1-3: %d" % early_storms)

	# 2 storm rate
	var rate := float(storms) / float(nights)
	check(rate > 0.035 and rate < 0.07, "2 storm rate: %d in %d nights = 1 in %.1f (want about 1 in 20)" % [storms, nights, 1.0 / maxf(rate, 0.0001)])

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

	# 4 season: act 91-102 is January, 259-270 is June (START_MONTH October)
	var wet_winter := 0
	var wet_summer := 0
	for sd in SEEDS:
		for e in Plan.generate(91, 102, sd):
			if e.level != Plan.DRY:
				wet_winter += 1
		for e in Plan.generate(259, 270, sd):
			if e.level != Plan.DRY:
				wet_summer += 1
	check(Plan.season_name(91) == "winter" and Plan.season_name(265) == "summer", "4 season: night 91 is %s, night 265 is %s" % [Plan.season_name(91), Plan.season_name(265)])
	check(wet_winter > 1.5 * wet_summer and wet_summer > 0, "4 season: wet nights winter %d vs summer %d over %d seeds" % [wet_winter, wet_summer, SEEDS])

	# 5 mid-night change
	check(changes_wrong == 0, "5 mid-night: clock reads start before the change hour and the new level from it (%d wrong)" % changes_wrong)
	var share := float(changes) / float(nights)
	check(share > 0.05 and share < 0.6, "5 mid-night: %d of %d nights have a change (%.0f%%), at most one each" % [changes, nights, share * 100.0])
	check(damp_ok, "5 damp: a dry night after a wet one starts damp, and only those do")
	check(Plan.minutes_of(20) == 0.0 and Plan.minutes_of(0) == 240.0 and Plan.minutes_of(4) == 480.0, "5 mid-night: hour to minutes since 8 p.m.")

	# 6 numbers
	var dry_ok: bool = Weather.TRAFFIC_SHARE[0] == 1.0 and Weather.COP_SHARE[0] == 1.0 and Weather.PAY_FACTOR[0] == 1.0
	var damp_same: bool = Weather.TRAFFIC_SHARE[3] == 1.0 and Weather.COP_SHARE[3] == 1.0 and Weather.PAY_FACTOR[3] == 1.0
	var order: bool = Weather.TRAFFIC_SHARE[2] < Weather.TRAFFIC_SHARE[1] and Weather.TRAFFIC_SHARE[1] < 1.0 \
		and Weather.COP_SHARE[2] < Weather.COP_SHARE[1] and Weather.COP_SHARE[1] < 1.0 \
		and Weather.PAY_FACTOR[2] > Weather.PAY_FACTOR[1] and Weather.PAY_FACTOR[1] > 1.0
	check(dry_ok and damp_same, "6 numbers: dry and damp nights change nothing (traffic, cops, pay all 1.0)")
	check(order, "6 numbers: storm < rain < 1 for cars and cops, storm > rain > 1 for pay")
	Weather.set_level(Weather.Level.DOWNPOUR, true)
	var storm_traffic := Weather.traffic_factor()
	var storm_pay := Weather.pay_factor()
	Weather.set_level(Weather.Level.DAMP, true)
	var damp_wet := Weather.wetness
	var damp_grip := Weather.rain_grip()
	Weather.reset()
	check(storm_traffic == Weather.TRAFFIC_SHARE[2] and storm_pay == Weather.PAY_FACTOR[2] and Weather.traffic_factor() == 1.0, "6 numbers: accessors follow the level")
	check(absf(damp_wet - 0.3) < 1e-6 and damp_grip > 0.9, "6 damp: wetness %.2f, grip %.3f (shallow wet, nearly dry grip)" % [damp_wet, damp_grip])

	# 7 Dave
	var lines_ok := true
	var variants := {}
	for sd in 40:
		for e in Plan.generate(11, 22, sd):
			var f := Plan.forecast_line(e)
			variants[f] = true
			if not f.begins_with("Dave: ") or f.length() < 20:
				lines_ok = false
			if e.change_hour >= 0 and Plan.change_line(e) == "":
				lines_ok = false
	check(lines_ok and variants.size() >= 6, "7 Dave: every night kind has a forecast and every change a line (%d forecast variants)" % variants.size())

	# 8 off
	check(Weather.ROLL_ON == false and Weather.tonight.is_empty() and Weather.level == Weather.Level.DRY, "8 off: ROLL_ON %s, nothing planned, road dry" % Weather.ROLL_ON)

	# CPU
	var t0 := Time.get_ticks_usec()
	var reps := 200
	for k in reps:
		Plan.generate(11, 22, k)
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(reps)
	check(per_ms < BUDGET_MS, "CPU: one act's deck %.3f ms (budget %.1f), once per act" % [per_ms, BUDGET_MS])

	print("weather_plan: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
