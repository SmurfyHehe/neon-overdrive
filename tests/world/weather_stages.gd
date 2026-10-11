extends SceneTree

# Weather stages (WX0), checked without booting the game: the one table
# (Weather.STAGE), the live values easing toward it, the version bumps, pay and
# the other accessors, NEON_WEATHER names, and the per-tick cost.
#   1 table     every stage's numbers are the ones decided (Roy's list)
#   2 grip      the grip each stage settles at (fog 97, drizzle 92, rain 85,
#               storm 80, snow city 85, white roads 75, slush 70)
#   3 easing    each live value moves at its rate, within 10% of the time the
#               rate implies, and never jumps
#   4 version   bumps only while something moves
#   5 pay       1.15 for fog, rain, storm, snow, slush; 1.0 otherwise
#   6 accessors traffic / cops / cop sight / wipers / sky read the table
#   7 env       NEON_WEATHER accepts every stage name
#   8 save      capture() and restore() round-trip; bad values fall back
#   9 frost     the flag bumps the version once
#   CPU         step() under 0.01 ms per call
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/weather_stages.gd

const Weather := preload("res://scripts/world/weather.gd")
const L := Weather.Level
const DT := 1.0 / 60.0
const EPS := 1e-6

var fails := 0

func check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: ", what)
	else:
		fails += 1
		printerr("FAIL: ", what)

func _initialize() -> void:
	# 1 table: wet, fog, rain, snow_fall, snow_cover, road_snow, sky, traffic,
	# npc, cop, sight, pay, wipers (the stage list as decided)
	var want := {
		L.DRY: [0.0, 1.0, 0.0, 0.0, 0.0, 0.0, "per_night", 1.0, 1.0, 1.0, 1.0, 1.0, "off"],
		L.HAZE: [0.0, 1.8, 0.0, 0.0, 0.0, 0.0, "broken", 1.0, 1.0, 1.0, 0.9, 1.0, "off"],
		L.FOG: [0.15, 4.0, 0.0, 0.0, 0.0, 0.0, "hidden", 0.9, 0.90, 0.75, 0.5, 1.15, "intermittent"],
		L.DRIZZLE: [0.4, 1.3, 0.25, 0.0, 0.0, 0.0, "overcast", 1.0, 0.95, 1.0, 0.9, 1.0, "intermittent"],
		L.DAMP: [0.3, 1.2, 0.0, 0.0, 0.0, 0.0, "broken", 1.0, 0.95, 1.0, 1.0, 1.0, "off"],
		L.RAIN: [0.75, 1.5, 0.7, 0.0, 0.0, 0.0, "overcast", 0.9, 0.8875, 0.9, 0.85, 1.15, "normal"],
		L.DOWNPOUR: [1.0, 2.4, 1.0, 0.0, 0.0, 0.0, "overcast", 0.65, 0.85, 0.5, 0.6, 1.15, "fast"],
		L.SNOW: [0.75, 2.0, 0.0, 0.6, 1.0, 0.0, "overcast", 0.8, 0.85, 0.8, 0.75, 1.15, "normal"],
		L.SLUSH: [0.6, 1.4, 0.0, 0.1, 1.0, 0.4, "overcast", 0.85, 0.85, 0.9, 0.9, 1.15, "normal"],
	}
	var cols := ["wet", "fog", "rain", "snow_fall", "snow_cover", "road_snow", "sky", "traffic", "npc", "cop", "sight", "pay", "wipers"]
	var bad := []
	for st in want:
		for i in cols.size():
			var got: Variant = Weather.STAGE[st][cols[i]]
			var w: Variant = want[st][i]
			var same: bool = (str(got) == str(w)) if w is String else absf(float(got) - float(w)) < EPS
			if not same:
				bad.append("%d.%s=%s want %s" % [st, cols[i], str(got), str(w)])
	check(bad.is_empty() and Weather.STAGE.size() == 9, "1 table: nine stages, every column as decided %s" % str(bad))
	var r: Dictionary = Weather.SNOW_ROADS
	check(r.wet == 0.0 and r.fog == 2.0 and r.snow_fall == 0.6 and r.snow_cover == 1.0 and r.road_snow == 1.0 \
		and r.traffic == 0.75 and r.npc == 0.75 and r.cop == 0.8 and r.sight == 0.75 and r.pay == 1.15 and r.wipers == "normal",
		"1 table: snow on white roads has its own row")
	check(int(L.DRY) == 0 and int(L.RAIN) == 1 and int(L.DOWNPOUR) == 2 and int(L.DAMP) == 3 and int(L.HAZE) == 4 \
		and int(L.FOG) == 5 and int(L.DRIZZLE) == 6 and int(L.SNOW) == 7 and int(L.SLUSH) == 8, "1 table: stage ints are the saved numbers")

	# 2 grip
	var grips := {L.DRY: 1.0, L.FOG: 0.97, L.DRIZZLE: 0.92, L.RAIN: 0.85, L.DOWNPOUR: 0.80, L.SNOW: 0.85, L.SLUSH: 0.70}
	var grip_bad := []
	for st in grips:
		Weather.set_level(st, true)
		if absf(Weather.rain_grip() - grips[st]) > 0.011:
			grip_bad.append("%d: %.3f want %.2f" % [st, Weather.rain_grip(), grips[st]])
	Weather.set_level(L.SNOW, true, true)
	if absf(Weather.rain_grip() - 0.75) > 0.011 or Weather.road_snow != 1.0 or Weather.wetness != 0.0:
		grip_bad.append("white roads: %.3f road_snow %.1f wet %.2f" % [Weather.rain_grip(), Weather.road_snow, Weather.wetness])
	check(grip_bad.is_empty(), "2 grip: each stage settles at its grip %s" % str(grip_bad))
	Weather.set_level(L.RAIN, true)
	var ai_rain := Weather.ai_speed_factor()
	Weather.set_level(L.DOWNPOUR, true)
	var ai_storm := Weather.ai_speed_factor()
	Weather.set_level(L.SNOW, true, true)
	var ai_roads := Weather.ai_speed_factor()
	check(absf(ai_rain - 0.8875) < 0.001 and absf(ai_storm - 0.85) < 0.001 and absf(ai_roads - 0.75) < 0.001,
		"2 grip: NPC speed rain %.4f, storm %.3f, white roads %.2f" % [ai_rain, ai_storm, ai_roads])

	# 3 easing: seconds from a dry start to each value's target, vs the rate
	var cases := [
		["wetness", L.RAIN, 0.75 / Weather.WET_RATE],
		["fog", L.FOG, (4.0 - 1.0) / Weather.FOG_RATE],
		["rain", L.RAIN, 0.7 / Weather.RAIN_RATE],
		["snow_fall", L.SNOW, 0.6 / Weather.SNOW_FALL_RATE],
		["snow_cover", L.SNOW, 1.0 / Weather.SNOW_COVER_RATE],
	]
	for c in cases:
		Weather.reset()
		Weather.set_level(c[1])
		var t := 0.0
		var prev := _val(c[0])
		var biggest := 0.0
		var target: float = Weather.row()[{"wetness": "wet", "fog": "fog", "rain": "rain", "snow_fall": "snow_fall", "snow_cover": "snow_cover"}[c[0]]]
		while absf(_val(c[0]) - target) > 1e-9 and t < 600.0:
			Weather.step(DT)
			t += DT
			var now := _val(c[0])
			biggest = maxf(biggest, absf(now - prev))
			prev = now
		var ratio: float = t / float(c[2])
		check(ratio > 0.9 and ratio < 1.1, "3 easing: %s reaches %.2f in %.1f s (rate says %.1f s)" % [c[0], target, t, c[2]])
	# road_snow is fixed with the stage, not eased
	Weather.reset()
	Weather.set_level(L.SNOW, false, true)
	var rs_now := Weather.road_snow
	Weather.step(DT)
	check(rs_now == 1.0 and Weather.road_snow == 1.0, "3 easing: road_snow is set with the stage and does not ease")
	# drying is slower than wetting, and wet -> fog does not jump
	Weather.set_level(L.RAIN, true)
	Weather.set_level(L.DRY)
	var t_dry := 0.0
	while Weather.wetness > 0.0 and t_dry < 600.0:
		Weather.step(DT)
		t_dry += DT
	check(t_dry > 0.75 / Weather.WET_RATE * 1.5, "3 easing: drying %.0f s is slower than wetting %.0f s" % [t_dry, 0.75 / Weather.WET_RATE])

	# 4 version: only while something moves
	Weather.reset()
	Weather.set_level(L.RAIN, true)
	var v0 := Weather.version
	for k in 600:
		Weather.step(DT)
	var still := Weather.version == v0
	Weather.set_level(L.DRY)    # eased: the level change alone moves nothing yet
	var v1 := Weather.version
	Weather.step(DT)
	var moved := Weather.version > v1
	Weather.set_level(L.RAIN, true)
	var v2 := Weather.version
	Weather.set_level(L.RAIN, true)
	check(still and moved, "4 version: no bump while settled (%s), a bump when a value moves (%s)" % [still, moved])
	check(Weather.version > v2 - 1, "4 version: an instant set bumps it")

	# 5 pay
	var pay_ok := true
	var pay_txt := []
	for st in [L.FOG, L.RAIN, L.DOWNPOUR, L.SNOW, L.SLUSH]:
		Weather.set_level(st, true)
		pay_txt.append("%d:%.2f" % [st, Weather.pay_factor()])
		if Weather.pay_factor() != 1.15:
			pay_ok = false
	Weather.set_level(L.SNOW, true, true)
	if Weather.pay_factor() != 1.15:
		pay_ok = false
	for st in [L.DRY, L.HAZE, L.DAMP, L.DRIZZLE]:
		Weather.set_level(st, true)
		pay_txt.append("%d:%.2f" % [st, Weather.pay_factor()])
		if Weather.pay_factor() != 1.0:
			pay_ok = false
	check(pay_ok, "5 pay: 1.15 for fog, rain, storm, snow, slush; 1.0 for clear, haze, damp, drizzle %s" % str(pay_txt))

	# 6 accessors
	Weather.set_level(L.FOG, true)
	var a_ok: bool = Weather.cop_sight() == 0.5 and Weather.cop_factor() == 0.75 and Weather.traffic_factor() == 0.9 \
		and Weather.wipers() == "intermittent" and Weather.sky() == "hidden"
	Weather.set_level(L.DOWNPOUR, true)
	a_ok = a_ok and Weather.cop_sight() == 0.6 and Weather.cop_factor() == 0.5 and Weather.traffic_factor() == 0.65 \
		and Weather.wipers() == "fast"
	Weather.set_level(L.DRY, true)
	a_ok = a_ok and Weather.cop_sight() == 1.0 and Weather.wipers() == "off" and Weather.sky() == "per_night"
	check(a_ok, "6 accessors: cop sight, cops, traffic, wipers and sky read the table")

	# 7 env
	var names := {"dry": L.DRY, "clear": L.DRY, "rain": L.RAIN, "downpour": L.DOWNPOUR, "storm": L.DOWNPOUR,
		"damp": L.DAMP, "haze": L.HAZE, "fog": L.FOG, "drizzle": L.DRIZZLE, "snow": L.SNOW,
		"snow_roads": L.SNOW, "slush": L.SLUSH, "7": L.SNOW, "plan": -1, "nonsense": -1, "": -1}
	var env_bad := []
	for n in names:
		OS.set_environment("NEON_WEATHER", n)
		if Weather.env_level() != int(names[n]):
			env_bad.append("%s -> %d" % [n, Weather.env_level()])
	OS.set_environment("NEON_WEATHER", "snow_roads")
	var roads_env := Weather.env_snow_roads()
	OS.set_environment("NEON_WEATHER", "snow")
	var city_env := not Weather.env_snow_roads()
	OS.set_environment("NEON_WEATHER", "")
	check(env_bad.is_empty() and roads_env and city_env, "7 env: NEON_WEATHER takes every stage name %s" % str(env_bad))

	# 8 save
	Weather.reset()
	Weather.set_level(L.RAIN, true)
	Weather.wetness = 0.6
	var cap := Weather.capture(true)
	Weather.reset()
	Weather.set_level(L.RAIN, false)
	Weather.restore(cap)
	var round_ok: bool = int(cap.stage) == 1 and absf(Weather.wetness - 0.6) < EPS and cap.change_done == true \
		and absf(Weather.rain - 0.7) < EPS and absf(Weather.fog - 1.5) < EPS
	Weather.restore({"wet": "x", "fog": NAN, "rain": 5.0})
	var bad_ok: bool = absf(Weather.wetness - 0.75) < EPS and absf(Weather.fog - 1.5) < EPS and Weather.rain == 1.0
	check(round_ok and bad_ok, "8 save: capture/restore round-trip; bad values fall back to the stage (%s, %s)" % [round_ok, bad_ok])

	# 9 frost
	Weather.reset()
	var vf := Weather.version
	Weather.set_frost(true)
	var v_on := Weather.version
	Weather.set_frost(true)
	check(Weather.frost and v_on == vf + 1 and Weather.version == v_on, "9 frost: the flag bumps the version once")
	Weather.reset()
	check(not Weather.frost, "9 frost: reset clears it")

	# CPU: a settled step and an easing step, per call
	Weather.reset()
	Weather.set_level(L.RAIN, true)
	var reps := 100000
	var t0 := Time.get_ticks_usec()
	for k in reps:
		Weather.step(DT)
	var settled_us := float(Time.get_ticks_usec() - t0) / float(reps)
	Weather.set_level(L.SNOW, true)
	Weather.set_level(L.DRY)
	t0 = Time.get_ticks_usec()
	for k in reps:
		Weather.step(0.0001)
	var easing_us := float(Time.get_ticks_usec() - t0) / float(reps)
	check(settled_us < 10.0 and easing_us < 10.0, "CPU: step() %.2f us settled, %.2f us easing (budget 10 us = 0.01 ms)" % [settled_us, easing_us])

	Weather.reset()
	print("weather_stages: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)

func _val(name: String) -> float:
	match name:
		"wetness":
			return Weather.wetness
		"fog":
			return Weather.fog
		"rain":
			return Weather.rain
		"snow_fall":
			return Weather.snow_fall
	return Weather.snow_cover
