extends SceneTree

# Water rules (Part 2 of the 2026-10-09 water note), checked without booting
# the game: weather.gd, puddles.gd and the pure parts of wet_grip.gd.
#   1 rain grip      settled rain 0.85, downpour 0.80, dry 1.0
#   2 puddle grip    shallow -10%, deep -20%, nothing when the road is dry
#   3 aquaplaning    none in deep water at 110 km/h, a little above it, none
#                    in shallow water at any speed
#   4 grip floor     no combination of weather, puddle and speed goes under 55%
#   5 left/right     limit_pair keeps an axle's wheels within 10% of each other
#   6 gradual        wetness eases (no tick moves more than its rate), dry to
#                    rain takes 20 s or more, drying is slower than wetting
#   7 puddles fixed  the same chunk gives the same puddles after the cache is
#                    dropped; every puddle lies inside its chunk and the road;
#                    depth_at a puddle's centre is its depth
#   8 AI slows       ai_speed_factor 1 dry, under 0.9 in rain, 0.85 downpour
#   CPU              one car's puddle work per tick under BUDGET_US
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/water_rules.gd

const Weather := preload("res://scripts/world/weather.gd")
const Puddles := preload("res://scripts/world/puddles.gd")
const WetGrip := preload("res://scripts/car/wet_grip.gd")

const EPS := 1e-4
## One car's puddle work per tick (early-out plus wheel lookups), us: 3% of
## the cheapest full-sim car tick, 190 us (docs/planning/world-building-vision
## -2026-10-07.md). Measured 4.3-4.8 us on Roy's laptop (2026-10-09), bench
## loop included. The whole step() is timed on real cars in
## tests/world/water_drive.gd.
const BUDGET_US := 6.0
const NPC_CARS := 40
const BENCH_TICKS := 120 * 20

var fails := 0

func check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: ", what)
	else:
		fails += 1
		printerr("FAIL: ", what)

func _initialize() -> void:
	# 1 rain grip
	Weather.set_level(Weather.Level.RAIN, true)
	var g_rain := Weather.rain_grip()
	Weather.set_level(Weather.Level.DOWNPOUR, true)
	var g_down := Weather.rain_grip()
	Weather.reset()
	check(absf(g_rain - 0.85) < EPS and absf(g_down - 0.80) < EPS and Weather.rain_grip() == 1.0,
		"1 rain grip: rain %.3f, downpour %.3f, dry %.3f" % [g_rain, g_down, Weather.rain_grip()])

	# 2 puddle grip (rain_grip 1.0 isolates the puddle's share)
	var sh := WetGrip.wheel_target(1.0, 1.0, Puddles.Depth.SHALLOW, 10.0)
	var dp := WetGrip.wheel_target(1.0, 1.0, Puddles.Depth.DEEP, 10.0)
	var dry_dp := WetGrip.wheel_target(1.0, 0.0, Puddles.Depth.DEEP, 10.0)
	check(absf(sh - 0.90) < EPS and absf(dp - 0.80) < EPS and dry_dp == 1.0,
		"2 puddle grip: shallow %.3f, deep %.3f, deep on a dry road %.3f" % [sh, dp, dry_dp])

	# 3 aquaplaning
	var at110 := WetGrip.wheel_target(1.0, 1.0, Puddles.Depth.DEEP, 110.0 / 3.6)
	var at140 := WetGrip.wheel_target(1.0, 1.0, Puddles.Depth.DEEP, 140.0 / 3.6)
	var at200 := WetGrip.wheel_target(1.0, 1.0, Puddles.Depth.DEEP, 200.0 / 3.6)
	var sh200 := WetGrip.wheel_target(1.0, 1.0, Puddles.Depth.SHALLOW, 200.0 / 3.6)
	check(absf(at110 - 0.80) < EPS and at140 < at110 - 0.01 and at200 >= 0.80 * (1.0 - WetGrip.AQUA_LOSS) - EPS
			and absf(sh200 - 0.90) < EPS,
		"3 aquaplaning: deep 110 %.3f, 140 %.3f, 200 %.3f; shallow 200 %.3f" % [at110, at140, at200, sh200])

	# 4 grip floor: every weather x puddle x speed
	var lowest := 1.0
	for wl: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var rg := 1.0 - Weather.GRIP_LOSS * wl
		var fill := clampf(wl / 0.75, 0.0, 1.0)
		for d: int in [Puddles.Depth.NONE, Puddles.Depth.SHALLOW, Puddles.Depth.DEEP]:
			for kmh in range(0, 301, 10):
				lowest = minf(lowest, WetGrip.wheel_target(rg, fill, d, kmh / 3.6))
	# Even with rain grip pushed far past the design range the floor holds.
	lowest = minf(lowest, WetGrip.wheel_target(0.3, 1.0, Puddles.Depth.DEEP, 80.0))
	check(lowest >= WetGrip.MIN_GRIP - EPS, "4 grip floor: lowest %.3f (floor %.2f)" % [lowest, WetGrip.MIN_GRIP])

	# 5 left/right limit
	var worst := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 2000:
		var t := PackedFloat32Array([rng.randf_range(0.55, 1.0), rng.randf_range(0.55, 1.0),
			rng.randf_range(0.55, 1.0), rng.randf_range(0.55, 1.0)])
		var hi_before := maxf(t[0], t[1])
		WetGrip.limit_pair(t, 0, 1)
		WetGrip.limit_pair(t, 2, 3)
		worst = maxf(worst, maxf(absf(t[0] - t[1]), absf(t[2] - t[3])))
		if maxf(t[0], t[1]) != hi_before:
			worst = INF  # the limit must only lift the lower wheel
	check(worst <= WetGrip.MAX_SIDE_DIFF + EPS, "5 left/right: widest pair after the limit %.3f" % worst)

	# 6 gradual
	Weather.reset()
	Weather.set_level(Weather.Level.RAIN)
	var dt := 1.0 / 120.0
	var biggest := 0.0
	var t_wet := 0.0
	while Weather.wetness < Weather.target_wetness() and t_wet < 120.0:
		var before := Weather.wetness
		Weather.step(dt)
		biggest = maxf(biggest, absf(Weather.wetness - before))
		t_wet += dt
	Weather.set_level(Weather.Level.DRY)
	var t_dry := 0.0
	while Weather.wetness > 0.0 and t_dry < 240.0:
		Weather.step(dt)
		t_dry += dt
	check(biggest <= Weather.WET_RATE * dt + 1e-7 and t_wet >= 20.0 and t_dry > t_wet,
		"6 gradual: dry to rain %.1f s, rain to dry %.1f s, biggest tick %.5f" % [t_wet, t_dry, biggest])

	# 7 puddles fixed
	var same := true
	var inside := true
	var centre_ok := true
	var count := 0
	var deep_n := 0
	for c in range(-50, 200):
		var a := Puddles.of_chunk(c)
		Puddles.clear_cache()
		var b := Puddles.of_chunk(c)
		same = same and a == b
		var i := 0
		while i < a.size():
			count += 1
			var s0 := float(c) * Puddles.L
			inside = inside and a[i] - a[i + 2] >= s0 - EPS and a[i] + a[i + 2] <= s0 + Puddles.L + EPS \
				and absf(a[i + 1]) <= Puddles.HALF_SPAN
			centre_ok = centre_ok and Puddles.depth_at(a[i], a[i + 1]) >= int(a[i + 4])
			if int(a[i + 4]) == Puddles.Depth.DEEP:
				deep_n += 1
			i += Puddles.STRIDE
	check(same and inside and centre_ok and count > 100 and deep_n > 0,
		"7 puddles fixed: %d puddles (%d deep) over 250 chunks, repeatable %s, inside %s" % [count, deep_n, same, inside])

	# 8 AI slows
	Weather.reset()
	var f_dry := Weather.ai_speed_factor()
	Weather.set_level(Weather.Level.RAIN, true)
	var f_rain := Weather.ai_speed_factor()
	var b_rain := Weather.ai_bend_factor()
	Weather.set_level(Weather.Level.DOWNPOUR, true)
	var f_down := Weather.ai_speed_factor()
	check(f_dry == 1.0 and f_rain < 0.9 and absf(f_down - 0.85) < EPS and b_rain < 1.0,
		"8 AI slows: dry %.3f, rain %.3f (bends %.3f), downpour %.3f" % [f_dry, f_rain, b_rain, f_down])

	# CPU: one car's puddle work per tick, puddles generated as needed: NPC_CARS cars
	# each driving its own lane at 30 m/s for 20 s at 120 Hz, through the same
	# distance count and puddle list step() uses, wheel by wheel only near one.
	# Best of three: other programs on the laptop swing a single pass 2-3x.
	var per := INF
	var acc := 0.0
	var near_n := 0
	for rep in 3:
		var r := _bench_cars()
		per = minf(per, r.x)
		acc += r.y
		near_n = int(r.z)
	check(per < BUDGET_US and acc > 0.0 and near_n > 0,
		"CPU: %.3f us per car per tick for puddles (budget %.1f, best of 3), over a puddle %.1f%% of ticks" % [per, BUDGET_US, 100.0 * near_n / (BENCH_TICKS * NPC_CARS)])

	Weather.reset()
	quit(1 if fails > 0 else 0)

## One bench pass: (us per car-tick, checksum, car-ticks near a puddle).
func _bench_cars() -> Vector3:
	Puddles.clear_cache()
	var cars: Array[WetGrip] = []
	for k in NPC_CARS:
		cars.append(WetGrip.new())
	var offs := [Vector2(1.3, -0.8), Vector2(1.3, 0.8), Vector2(-1.3, -0.8), Vector2(-1.3, 0.8)]
	var acc := 0.0
	var near_n := 0
	var t0 := Time.get_ticks_usec()
	for tk in BENCH_TICKS:
		for k in NPC_CARS:
			var s := float(k) * 37.0 + float(tk) * 0.25
			var x := float(k % 8) * 3.2 - 11.2
			var wg: WetGrip = cars[k]
			wg._valid -= 0.25  # 30 m/s for one tick, as step() counts it
			wg._free -= 0.25
			if wg._valid <= 0.0:
				wg._valid = Puddles.gather(s, x, WetGrip.CAR_R, WetGrip.NEAR_MARGIN, wg.near)
				wg._free = 0.0
			if not wg.near.is_empty() and wg._free <= 0.0:
				wg._free = Puddles.reach(wg.near, s, x, WetGrip.CAR_R)
			if not wg.near.is_empty() and wg._free <= 0.0:
				near_n += 1
				for o: Vector2 in offs:
					acc += WetGrip.wheel_target(0.8, 1.0, Puddles.depth_in(wg.near, s + o.x, x + o.y), 30.0)
			else:
				acc += 3.2
	return Vector3(float(Time.get_ticks_usec() - t0) / (BENCH_TICKS * NPC_CARS), acc, near_n)
