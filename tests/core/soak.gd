extends SceneTree

# Soak (stress layer C, 2026-10-13, notes/stress-test-and-readiness-2026-10-13.md):
# one long drive of the real game, headless, logging what grows. The flee bot
# holds SOAK_SPEED through SOAK_CARS traffic with the police on, heat pushed
# to the top every HEAT_EVERY s, and the night clock run SOAK_CLOCK times fast
# so several nights roll over. Each dawn goes through the real card, Walt's
# board and the garage, and back out onto the road.
#
# Needs a debug build (the editor binary) for the orphan-node monitor, and
# --fixed-fps 60 so each frame is one 60 fps frame of game time and the wall
# time between frames is what the CPU spends on it (as perf_probe.gd):
#
#   <godot> --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/core/soak.gd
#
# Env: SOAK_SECS game seconds (3600), SOAK_CARS (80), SOAK_SPEED km/h (250),
# SOAK_BOT the driver mode (flee), SOAK_CLOCK night clock speed (4.0: a 40 min night in 10 min, 6 nights an
# hour), SOAK_CSV a file for the per-minute rows (default user://soak.csv).
#
# One row every SAMPLE_SECS of game time. Fails on: a script or engine error,
# NaN or the car under the road, memory or node count at the end more than
# GROW_LIMIT above the 5-minute mark, orphan nodes growing, frame time mean
# drifting more than DRIFT_MS between the 5-minute mark and the end, or a dawn
# the game never reached.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const TestDriver := preload("res://scripts/core/test_driver.gd")
const Districts := preload("res://scripts/world/districts.gd")

const RATE := 120
const FPS := 60
const SAMPLE_SECS := 60.0
const BASE_SECS := 300.0      # the 5-minute mark everything is compared to
const GROW_LIMIT := 0.05
const DRIFT_MS := 1.0
const HEAT_EVERY := 120.0
const STUCK_SECS := 20.0
const REFUEL_AT := 0.15

var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var bot: TestDriver
var secs := 3600.0
var frame := 0
var game_t := 0.0
var last_us := 0
var start_us := 0
var frame_ms := PackedFloat64Array()
var rows: Array[Dictionary] = []
var csv: FileAccess
var fails: Array[String] = []
var next_sample := SAMPLE_SECS
var next_heat := 30.0
var stuck_t := 0.0
var rescues := 0
var dawns := 0
var garage_trips := 0
var nights_seen := {}
var districts_seen := {}
var km := 0.0
var max_heat := 0
var pursuits := 0
var busts := 0
var errors_seen := 0
var cranking := false
var refuels := 0

func _initialize() -> void:
	OS.add_logger(logger)
	secs = float(_env("SOAK_SECS", "3600"))
	OS.set_environment("NEON_POLICE", "1")
	OS.set_environment("NEON_CAR", _env("SOAK_CAR", "p1_coupe"))
	game = Harness.boot(self, int(_env("SOAK_CARS", "80")), TrafficSettings.DETAIL_DEFAULT, int(_env("SOAK_SEED", "4242")))
	var path := _env("SOAK_CSV", "user://soak.csv")
	csv = FileAccess.open(path, FileAccess.WRITE)
	csv.store_line("game_min,wall_s,mem_mb,mem_peak_mb,objects,nodes,orphans,resources,game_nodes,chunks,traffic,detailed,ms_mean,ms_p95,ms_max,errors,warnings,kmh,km,night,clock,state,heat,cop,district,rescues,dawns,refuels,fuel_l,limp,torque_mult,hits")
	print("soak: %d s game time, csv %s" % [secs, ProjectSettings.globalize_path(path)])
	process_frame.connect(_frame)
	start_us = Time.get_ticks_usec()

static func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback

func _frame() -> void:
	frame += 1
	var now := Time.get_ticks_usec()
	if frame > 2:
		frame_ms.append((now - last_us) / 1000.0)
	last_us = now

func _physics_process(delta: float) -> bool:
	if p == null:
		p = game.get("player")
		if p == null or not p.is_ready or Engine.get_physics_frames() < RATE:
			p = null
			return false
		var gs: GameState = game.get("game_state")
		gs.garage_enabled = true
		var clock: NightClock = game.get("night_clock")
		clock.speed = float(_env("SOAK_CLOCK", "4.0"))
		var police: PolicePatrol = game.get("police")
		if police != null:
			police.pursuit_started.connect(func() -> void: pursuits += 1)
			police.busted.connect(func(_c: Node3D) -> void: busts += 1)
		bot = TestDriver.start(game, _env("SOAK_BOT", "flee"), {"speed": float(_env("SOAK_SPEED", "250"))})
		return false
	var gs: GameState = game.get("game_state")
	_walk_dawn(gs)
	if gs.state != GameState.State.PLAYING:
		return false
	# "Go out" parks the car with the engine off until the starter key (X) is
	# held (GarageFlow.START_HOLD); the bot only drives pedals and wheel, so
	# hold the key for it, through the real input action.
	var flow = game.get("garage_flow")
	if flow != null and flow.parked_off:
		if not cranking:
			Input.action_press("starter")
			cranking = true
	elif cranking:
		Input.action_release("starter")
		cranking = false
	game_t += delta
	km += p.current_speed() * delta / 1000.0
	var police: PolicePatrol = game.get("police")
	if police != null and police.car != null:
		bot.threat = police.car
	var heat: PoliceHeat = game.get("police_heat")
	if heat != null:
		max_heat = maxi(max_heat, heat.level)
		if game_t >= next_heat:
			next_heat += HEAT_EVERY
			heat._raise_to(float(PoliceHeat.MAX_LEVEL))
	# A player stops at a pump; the bot cannot, so the tank is topped up at
	# REFUEL_AT (a dry tank limps the engine: LimpMode FUEL, fuel_tank.gd).
	if p.fuel.enabled and p.fuel.litres < FuelTank.CAPACITY_L * REFUEL_AT:
		p.fuel.litres = FuelTank.CAPACITY_L
		refuels += 1
	var bad := TestDriver.sanity(p)
	if bad != "":
		fails.append("%s at %.1f min" % [bad, game_t / 60.0])
		return _end()
	# Stuck (a wreck, a pile-up the bot cannot leave): the game's own put-back.
	stuck_t = stuck_t + delta if p.current_speed() < 2.0 else 0.0
	if stuck_t > STUCK_SECS:
		stuck_t = 0.0
		var rescue = game.get("rescue")
		if rescue != null and rescue.request():
			rescues += 1
			print("  %.1f min: stuck %d s, put back" % [game_t / 60.0, STUCK_SECS])
	if game_t >= next_sample:
		next_sample += SAMPLE_SECS
		_sample()
		if game_t >= secs:
			return _end()
	return false

# The dawn card -> (Walt's board) -> garage -> back out, as a player would.
func _walk_dawn(gs: GameState) -> void:
	match gs.state:
		GameState.State.DAWN:
			dawns += 1
			gs.dawn_continue()
		GameState.State.WORKBOARD:
			gs.close_workboard()
		GameState.State.GARAGE:
			garage_trips += 1
			gs.leave_garage()

func _chunk() -> int:
	return floori(RoadFrame.unroll(p.global_position).z * -1.0 / RoadChunkBuilder.CHUNK_LEN) + int(game.get("origin_index"))

func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c

func _sample() -> void:
	var s := Array(frame_ms)
	frame_ms.clear()
	s.sort()
	var n := s.size()
	var mean := 0.0
	for x in s:
		mean += x
	mean = mean / n if n > 0 else 0.0
	var clock: NightClock = game.get("night_clock")
	var heat: PoliceHeat = game.get("police_heat")
	var police: PolicePatrol = game.get("police")
	var tm: TrafficManager = game.get("traffic")
	var gs: GameState = game.get("game_state")
	var district := Districts.name_at(_chunk())
	districts_seen[district] = true
	nights_seen[clock.night] = true
	var cop := "-"
	if police != null and police.brain != null:
		cop = CopBrain.State.keys()[police.brain.state]
	var r := {
		"game_min": roundi(game_t / 60.0),
		"wall_s": (Time.get_ticks_usec() - start_us) / 1e6,
		"mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"mem_peak_mb": Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"game_nodes": _count_nodes(game),
		"chunks": (game.get("chunk_pool") as Array).size(),
		"traffic": tm.cars.size() if tm != null else 0,
		"detailed": tm.detailed_count() if tm != null else 0,
		"ms_mean": mean,
		"ms_p95": s[int(n * 0.95)] if n > 0 else 0.0,
		"ms_max": s[n - 1] if n > 0 else 0.0,
		"errors": logger.errors.size(),
		"warnings": logger.warnings,
		"kmh": p.current_speed() * 3.6,
		"km": km,
		"night": clock.night,
		"clock": clock.text(),
		"state": GameState.State.keys()[gs.state],
		"heat": heat.level if heat != null else -1,
		"cop": cop,
		"district": district,
		"rescues": rescues,
		"dawns": dawns,
		"refuels": refuels,
		"fuel_l": p.fuel.litres,
		"limp": p.limp.active_causes,
		"torque_mult": p.limp.torque_mult,
		"hits": p.damage.hits,
	}
	rows.append(r)
	var line := PackedStringArray()
	for k in r:
		line.append(("%.2f" % r[k]) if r[k] is float else str(r[k]).replace(",", " "))
	csv.store_line(",".join(line))
	csv.flush()
	print("  %3d min  wall %5.0f s  fuel %4.1f l  limp %d  hits %d  mem %6.1f MB  nodes %5d  orphans %4d  res %5d  ms %.2f/%.2f  err %d  %3.0f km/h  %5.1f km  night %d %s  heat %d %s  %s" % [
		r.game_min, r.wall_s, r.fuel_l, r.limp, r.hits, r.mem_mb, r.nodes, r.orphans, r.resources, r.ms_mean, r.ms_p95, r.errors,
		r.kmh, r.km, r.night, r.clock, r.heat, r.cop, r.district])
	if logger.errors.size() > errors_seen:
		for i in range(errors_seen, mini(logger.errors.size(), errors_seen + 5)):
			printerr("  error: " + logger.errors[i])
		errors_seen = logger.errors.size()

func _end() -> bool:
	if rows.size() >= 2:
		var base: Dictionary = rows[0]
		for r in rows:
			if r.game_min <= BASE_SECS / 60.0:
				base = r
		var last: Dictionary = rows[-1]
		for k in ["mem_mb", "nodes", "objects", "resources", "game_nodes"]:
			if float(last[k]) > float(base[k]) * (1.0 + GROW_LIMIT):
				fails.append("%s grew %.0f -> %.0f (%+.1f%%) from minute %d to %d" % [k, base[k], last[k],
					(float(last[k]) / float(base[k]) - 1.0) * 100.0, base.game_min, last.game_min])
		if last.orphans > base.orphans:
			fails.append("orphan nodes grew %d -> %d" % [base.orphans, last.orphans])
		if last.chunks != base.chunks:
			fails.append("chunk pool changed %d -> %d" % [base.chunks, last.chunks])
		if last.ms_mean - base.ms_mean > DRIFT_MS:
			fails.append("frame time drifted %.2f -> %.2f ms" % [base.ms_mean, last.ms_mean])
	if secs >= 1200.0 and dawns == 0:
		fails.append("no dawn in %.0f min with the clock at x%s" % [game_t / 60.0, _env("SOAK_CLOCK", "4.0")])
	if not logger.errors.is_empty():
		fails.append("%d errors, first: %s" % [logger.errors.size(), logger.errors[0]])
	print("soak: %.1f min, %.1f km, nights %s, dawns %d, garage %d, districts %d %s, max heat %d, pursuits %d, busts %d, put back %d, refuels %d, %s" % [
		game_t / 60.0, km, nights_seen.keys(), dawns, garage_trips, districts_seen.size(), districts_seen.keys(),
		max_heat, pursuits, busts, rescues, refuels, bot.summary() if bot != null else ""])
	for f in fails:
		printerr("FAIL: " + f)
	print("soak: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	csv.close()
	quit(1 if not fails.is_empty() else 0)
	return true
