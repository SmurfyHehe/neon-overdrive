extends SceneTree

# Lane threading test (road lane proposal step 0, 2026-10-08), at the game's
# 120 Hz tick in the real Game.tscn. Traffic keeps its own spot in the lane
# and sometimes makes room for a player lining up a gap between two cars
# (TrafficCar header, docs/planning/road-lane-changes-proposal-2026-10-08.md
# section 0). Three scripted scenes, then the slider sweep:
#
# A "thread": two 80 km/h cars side by side in lanes 1 and 2, the player at
#   130 km/h on the line between them, every driver forced to make room. Both
#   must ease out, the gap must reach 2.4 m before the player gets there, and
#   the player must pass between them with 0.25 m or more either side.
# B "door": a car in lane 1 stuck behind a crawling car, lane 0 its only way
#   round, and the player alongside it on the lane 0/1 line. It must not
#   start a lane change toward the player while the player is alongside, and
#   must go round once the player has passed.
# C "no room": the same pair as A with nobody making room and no lean. The
#   gap must stay under 2.4 m: threading is not free.
# Sweep: every combination of traffic count 0/16/40/80, draw distance
#   50/150/300 m, curviness 0/0.5/1 and hilliness 0/0.5/1 (108 runs), each a
#   NEON_SWEEP_KM km (default 1) run with a scripted player that rides the
#   lane 1/2 line and only goes through a gap with 0.3 m clear each side,
#   otherwise follows. Each run records side-by-side pairs met, how many
#   opened a 2.4 m gap, threads completed, make-room decisions, contacts with
#   the player, and the worst physics tick. Fails on any contact, on no gap
#   at all across the sweep, or on gaps at more than half the pairs.
#   NEON_SWEEP=quick runs the 16 corners (0/80 cars x 50/300 m x curves 0/1 x
#   hills 0/1), NEON_SWEEP=off skips it. NEON_SWEEP_CARS=40,80 runs only
#   those traffic counts (to split the full sweep over two processes);
#   NEON_SWEEP=one runs one flat, straight, 150 m run per traffic count.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/lane_threading.gd

const Harness := preload("res://tests/traffic_harness.gd")

const RATE := 120
const KMH := 1.0 / 3.6
const GAP_NEEDED := 2.4
## The player's body half width (1.8 m car; its index footprint is 1.0).
const P_HALF_W := 0.9
const P_HALF_L := 2.2
## The sweep bot goes through a gap only with this much clear each side.
const BOT_CLEAR := 0.3
const BOT_SPEED := 150.0 * KMH
## Gap the bot closes to behind a car that blocks it.
const BOT_FOLLOW := 12.0
## Physics-tick timing starts this long into a run (the boot frame is long).
const SETTLE_TICKS := 3 * RATE
const SCENE_SECONDS := {"thread": 14.0, "door": 16.0, "no_room": 10.0}
const SCENES := ["thread", "door", "no_room"]

var logger := Harness.ErrorCounter.new()
var game: Node
var traffic: TrafficManager
var p: PlayerCar
var fails: Array[String] = []
var lines: Array[String] = []
var scene := -1
var tick := 0

# Scene state.
var a: TrafficCar
var b: TrafficCar
var max_gap := 0.0
var gap_at_arrival := -1.0
var min_clear := INF
var passed := false
var door_violation := ""
var door_changed_after := false

# Sweep state.
var combos: Array = []
var combo := -1
var booting := false
var run_start_z := 0.0
var pairs_seen := {}
var pair_count := 0
var gap_count := 0
var threads := 0
var contacts := 0
var first_contact := ""
var worst_tick_ms := 0.0
var room_start := 0
var _between := false
var _between_ok := true
var sweep_rows: Array[String] = []
var tot := {"km": 0.0, "pairs": 0, "gaps": 0, "threads": 0, "contacts": 0, "room": 0}
var slow: Array = []

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	game = Harness.boot(self, 0, 300.0, 808, 8000.0)

func _physics_process(_delta: float) -> bool:
	if booting:
		if game.get("player") == null:
			return false
		booting = false
		_start_run()
		return false
	if traffic == null:
		if game.get("player") == null:
			return false
		traffic = game.get("traffic")
		p = game.get("player")
		_next_scene()
		return false
	if not Harness.finite(p):
		return _end("non-finite player state")
	tick += 1
	if scene < SCENES.size():
		call("_tick_" + SCENES[scene])
		if tick >= int(SCENE_SECONDS[SCENES[scene]] * RATE):
			call("_end_" + SCENES[scene])
			_next_scene()
		return false
	return _tick_sweep()

func _next_scene() -> void:
	scene += 1
	tick = 0
	if scene >= SCENES.size():
		_begin_sweep()
		return
	traffic.set_car_count(0)
	traffic.react_to_player = true
	traffic.detail_distance = 300.0
	traffic.own_lanes_used = []
	traffic.onc_lanes_used = [3]
	traffic.make_room_chance = -1.0
	max_gap = 0.0
	gap_at_arrival = -1.0
	min_clear = INF
	passed = false
	door_violation = ""
	door_changed_after = false
	call("_setup_" + SCENES[scene])

## Own-direction road x of the line between lanes i and i + 1.
static func line_x(i: int) -> float:
	return RoadChunkBuilder.MEDIAN_GAP + float(i + 1) * RoadChunkBuilder.LANE_W

func _put(car: TrafficCar, lane: int, ahead: float, speed: float) -> void:
	car.target_speed = speed
	car.drift_pref = 0.0
	car.rude = false
	car.set_detailed(true)
	car.place(Harness.lane_x(lane), -1.0, p.global_position.z - ahead, TrafficManager.REST_Y, speed)

func _player_on(x: float, speed: float, cap: float) -> void:
	Harness.move_player_to_lane(p, x)
	Harness.launch_player(p, speed)
	p.driver = Harness.lane_driver(x, 1.0, cap)

## Body gap across the road between two cars (positive = clear).
static func body_gap(c1: TrafficCar, c2: TrafficCar) -> float:
	var x1 := RoadFrame.unroll(c1.global_position).x
	var x2 := RoadFrame.unroll(c2.global_position).x
	return absf(x1 - x2) - c1.body_half_w - c2.body_half_w

## Side clearance between the player and a car that overlaps it lengthwise,
## INF if they don't overlap along the road.
func clear_to(car: TrafficCar) -> float:
	var u := RoadFrame.unroll(car.global_position)
	var pu := RoadFrame.unroll(p.global_position)
	if absf(u.z - pu.z) > car.half_l + P_HALF_L:
		return INF
	return absf(u.x - pu.x) - car.body_half_w - P_HALF_W

# ---------- A: thread ----------

func _setup_thread() -> void:
	traffic.own_lanes_used = [1, 2]
	traffic.make_room_chance = 1.0
	traffic.set_car_count(2)
	a = traffic.cars[0]
	b = traffic.cars[1]
	_put(a, 1, 110.0, 80.0 * KMH)
	_put(b, 2, 110.0, 80.0 * KMH)
	_player_on(line_x(1), 130.0 * KMH, 130.0 * KMH)

func _tick_thread() -> void:
	var g := body_gap(a, b)
	if gap_at_arrival < 0.0:
		max_gap = maxf(max_gap, g)
	var pz := RoadFrame.unroll(p.global_position).z
	var tail := RoadFrame.unroll(a.global_position).z + a.half_l
	if gap_at_arrival < 0.0 and pz - P_HALF_L <= tail:
		gap_at_arrival = g
	min_clear = minf(min_clear, minf(clear_to(a), clear_to(b)))
	if pz < RoadFrame.unroll(a.global_position).z - a.half_l - P_HALF_L - 5.0 and pz < RoadFrame.unroll(b.global_position).z - b.half_l - P_HALF_L - 5.0:
		passed = true

func _end_thread() -> void:
	lines.append("A thread: gap at arrival %.2f m, closest side clearance %.2f m, passed %s, room decisions %d, lanes after %d/%d, drift %.2f/%.2f" % [
		gap_at_arrival, min_clear, passed, traffic.make_room_count, a.lane_i, b.lane_i, a.drift, b.drift])
	_check(gap_at_arrival >= GAP_NEEDED, "A: gap at arrival %.2f m < %.1f m" % [gap_at_arrival, GAP_NEEDED])
	_check(min_clear >= 0.25, "A: side clearance %.2f m < 0.25 m" % min_clear)
	_check(passed, "A: player did not get through")

# ---------- B: door ----------

func _setup_door() -> void:
	traffic.own_lanes_used = [0, 1]
	traffic.set_car_count(2)
	a = traffic.cars[0]   # the one that wants out
	b = traffic.cars[1]   # crawling car ahead of it
	_put(a, 1, 30.0, 90.0 * KMH)
	a.target_speed = 100.0 * KMH
	_put(b, 1, 90.0, 40.0 * KMH)
	# Alongside a at its speed in lane 0, then pull away after 7 s.
	_player_on(Harness.lane_x(0), 90.0 * KMH, 90.0 * KMH)
	var az := RoadFrame.unroll(a.global_position).z
	var off := Vector3(0.0, 0.0, az - p.global_position.z)
	p.global_position += off
	p.previous_global_position += off
	for w in p.wheel_array:
		w.previous_global_position += off
	p.reset_physics_interpolation()

func _tick_door() -> void:
	# The test's player: hold a's speed alongside for 7 s, then go.
	if tick < 7 * RATE:
		var dz := RoadFrame.unroll(p.global_position).z - RoadFrame.unroll(a.global_position).z
		var want := a.current_speed() + clampf(dz * 0.5, -3.0, 3.0)
		p.driver = speed_driver(Harness.lane_x(0), want)
		if a.changing and a.lane_i == 0 and door_violation == "":
			door_violation = "%.1f s: lane change toward the player alongside (dz %.1f m)" % [float(tick) / RATE, dz]
	else:
		p.driver = speed_driver(Harness.lane_x(0), 160.0 * KMH)
		if a.lane_i == 0:
			door_changed_after = true
	min_clear = minf(min_clear, clear_to(a))

func _end_door() -> void:
	lines.append("B door: change toward the player while alongside: %s; changed lane after the player left: %s; closest %.2f m" % [
		door_violation if door_violation != "" else "none", door_changed_after, min_clear])
	_check(door_violation == "", "B: " + door_violation)
	_check(door_changed_after, "B: the car never went round once the player had passed")
	_check(min_clear >= 0.2, "B: side clearance %.2f m" % min_clear)

## Lane-keeper at road x `x` that holds `want` m/s with throttle and brake.
static func speed_driver(x: float, want: float) -> Callable:
	var keep := Harness.lane_driver(x, 1.0)
	return func(c: Vehicle) -> void:
		keep.call(c)
		var v := -c.local_velocity.z
		c.throttle_input = clampf((want - v) * 0.5, 0.0, 1.0)
		c.brake_input = clampf((v - want - 0.5) * 0.15, 0.0, 1.0)

# ---------- C: no room ----------

func _setup_no_room() -> void:
	traffic.own_lanes_used = [1, 2]
	traffic.make_room_chance = 0.0
	traffic.set_car_count(2)
	a = traffic.cars[0]
	b = traffic.cars[1]
	_put(a, 1, 60.0, 80.0 * KMH)
	_put(b, 2, 60.0, 80.0 * KMH)
	# Player behind in lane 1, lined up on the gap but held back at 85 km/h.
	_player_on(line_x(1), 85.0 * KMH, 85.0 * KMH)

func _tick_no_room() -> void:
	max_gap = maxf(max_gap, body_gap(a, b))

func _end_no_room() -> void:
	lines.append("C no room: widest gap %.2f m" % max_gap)
	_check(max_gap < GAP_NEEDED, "C: gap %.2f m opened with nobody making room" % max_gap)

# ---------- sweep ----------

func _begin_sweep() -> void:
	var mode := OS.get_environment("NEON_SWEEP")
	if mode == "off":
		_finish()
		return
	var counts := [0, 80] if mode == "quick" else [0, 16, 40, 80]
	var draws := [50.0, 300.0] if mode == "quick" else [50.0, 150.0, 300.0]
	var shapes := [0.0, 1.0] if mode == "quick" else [0.0, 0.5, 1.0]
	if mode == "one":
		draws = [150.0]
		shapes = [0.0]
	var only := OS.get_environment("NEON_SWEEP_CARS")
	if only != "":
		counts = Array(only.split(",")).map(func(x): return int(x))
	for c in counts:
		for d in draws:
			for cv in shapes:
				for h in shapes:
					combos.append({"cars": c, "draw": d, "curves": cv, "hills": h})
	_next_run()

func _next_run() -> void:
	combo += 1
	if combo >= combos.size():
		_finish()
		return
	var c: Dictionary = combos[combo]
	game.queue_free()
	traffic = null
	OS.set_environment("NEON_CURVES", str(c.curves))
	OS.set_environment("NEON_HILLS", str(c.hills))
	game = Harness.boot(self, int(c.cars), float(c.draw), 1000 + combo, 8000.0)
	booting = true

func _start_run() -> void:
	traffic = game.get("traffic")
	p = game.get("player")
	tick = 0
	Harness.move_player_to_lane(p, line_x(1))
	Harness.launch_player(p, 120.0 * KMH)
	p.driver = Callable(self, "_bot")
	run_start_z = RoadFrame.unroll(p.global_position).z
	pairs_seen.clear()
	pair_count = 0
	gap_count = 0
	threads = 0
	contacts = 0
	first_contact = ""
	worst_tick_ms = 0.0
	room_start = traffic.make_room_count
	_between = false
	_between_ok = true

## The sweep's scripted player: rides the lane 1/2 line at BOT_SPEED and
## follows (brakes for) any car whose body comes within BOT_CLEAR of its path,
## so it only goes through a gap that has opened.
func _bot(c: Vehicle) -> void:
	var pu := RoadFrame.unroll(c.global_position)
	var v := -c.local_velocity.z
	var block_gap := INF
	var block_v := 0.0
	if traffic != null:
		for car in traffic.cars:
			if car.direction > 0.0:
				continue
			var u := RoadFrame.unroll(car.global_position)
			var ahead := pu.z - u.z - car.half_l - P_HALF_L
			if ahead < -1.0 or ahead > 120.0:
				continue
			if absf(u.x - line_x(1)) - car.body_half_w - P_HALF_W < BOT_CLEAR and ahead < block_gap:
				block_gap = ahead
				block_v = car.lane_speed()
	var want := BOT_SPEED
	if block_gap < INF:
		# Close in on it like a player lining up a gap (a few m/s faster down
		# to BOT_FOLLOW), so the drivers see someone coming.
		want = minf(want, block_v + clampf(0.4 * (block_gap - BOT_FOLLOW), -8.0, 7.0))
	var side_v := RoadFrame.dir_to_road(pu.z, c.linear_velocity).x
	c.steering_input = TrafficCar.lane_steer(c, line_x(1) - side_v * Harness.LAT_DAMP_T, -1.0, 2.5, Harness.PLAYER_UNDERSTEER_FF)
	c.handbrake_input = 0.0
	if v > want + 1.0:
		c.throttle_input = 0.0
		c.brake_input = clampf((v - want) * 0.15, 0.0, 1.0)
	else:
		c.throttle_input = clampf((want - v) * 0.5, 0.0, 1.0)
		c.brake_input = 0.0

func _tick_sweep() -> bool:
	var c: Dictionary = combos[combo]
	if tick > SETTLE_TICKS:
		worst_tick_ms = maxf(worst_tick_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var pu := RoadFrame.unroll(p.global_position)
	# Contacts with the player, and threads: the player between two cars.
	var left := false
	var right := false
	for car in traffic.cars:
		if not car.detailed:
			continue
		var cl := clear_to(car)
		if cl == INF:
			continue
		if cl < 0.02:
			contacts += 1
			if first_contact == "":
				first_contact = "run %d (%s) %.1f s: car x %.2f drift %.2f room %s, player x %.2f, %.0f km/h" % [
					combo, c, float(tick) / RATE, RoadFrame.unroll(car.global_position).x, car.drift, car.making_room,
					pu.x, Harness.kmh(p.current_speed())]
		var dx := RoadFrame.unroll(car.global_position).x - pu.x
		if car.direction < 0.0 and cl < 1.2:
			if dx < 0.0:
				left = true
			else:
				right = true
	if left and right:
		_between = true
	elif _between:
		threads += 1
		_between = false
	# Side-by-side pairs in neighbouring own/oncoming lanes, every 0.25 s.
	if tick % 30 == 0:
		var now := {}
		var n := traffic.cars.size()
		for i in n:
			var c1 := traffic.cars[i]
			if not c1.detailed or c1.changing:
				continue
			for j in range(i + 1, n):
				var c2 := traffic.cars[j]
				if not c2.detailed or c2.changing or c2.direction != c1.direction or absf(c2.lane_i - c1.lane_i) != 1:
					continue
				if absf(RoadFrame.unroll(c1.global_position).z - RoadFrame.unroll(c2.global_position).z) > c1.half_l + c2.half_l:
					continue
				var key := "%d_%d" % [i, j]
				now[key] = true
				if not pairs_seen.has(key):
					pairs_seen[key] = false
					pair_count += 1
				if not pairs_seen[key] and body_gap(c1, c2) >= GAP_NEEDED:
					pairs_seen[key] = true
					gap_count += 1
		for key in pairs_seen.keys():
			if not now.has(key):
				pairs_seen.erase(key)
	var km := (run_start_z - pu.z) / 1000.0
	var limit := float(OS.get_environment("NEON_SWEEP_KM")) if OS.get_environment("NEON_SWEEP_KM").is_valid_float() else 1.0
	if km >= limit or tick > 240 * RATE:
		var room := traffic.make_room_count - room_start
		sweep_rows.append("%2d cars %3.0f m curves %.1f hills %.1f | %.2f km %3d pairs %2d gaps %2d threads %2d room | contacts %d | worst tick %.1f ms" % [
			c.cars, c.draw, c.curves, c.hills, km, pair_count, gap_count, threads, room, contacts, worst_tick_ms])
		tot.km += km
		tot.pairs += pair_count
		tot.gaps += gap_count
		tot.threads += threads
		tot.contacts += contacts
		tot.room += room
		print(sweep_rows[-1])
		slow.append([worst_tick_ms, "%d cars %.0f m curves %.1f hills %.1f" % [c.cars, c.draw, c.curves, c.hills]])
		_check(contacts == 0, "sweep: player contact: " + first_contact)
		_check(km >= limit * 0.5, "sweep run %d (%s): only %.2f km in 240 s" % [combo, c, km])
		_next_run()
	return false

func _finish() -> void:
	if not sweep_rows.is_empty():
		lines.append("Sweep (%d runs):" % sweep_rows.size())
		lines.append_array(sweep_rows)
		lines.append("Total %.1f km: %d side-by-side pairs, %d opened a %.1f m gap (%.2f per km), %d threads, %d make-room decisions, %d contacts" % [
			tot.km, tot.pairs, tot.gaps, GAP_NEEDED, tot.gaps / maxf(tot.km, 0.01), tot.threads, tot.room, tot.contacts])
		slow.sort_custom(func(x, y): return x[0] > y[0])
		lines.append("Slowest physics ticks:")
		for i in mini(5, slow.size()):
			lines.append("  %.1f ms  %s" % [slow[i][0], slow[i][1]])
		_check(tot.pairs == 0 or tot.gaps > 0, "sweep: no gap ever opened")
		_check(tot.pairs == 0 or float(tot.gaps) / float(tot.pairs) <= 0.5, "sweep: gaps at %d of %d pairs, threading is free" % [tot.gaps, tot.pairs])
	_end("")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		fails.append(msg)
	for l in lines:
		print(l)
	print("errors=%d warnings=%d" % [logger.errors.size(), logger.warnings])
	for e in logger.errors.slice(0, 5):
		print("  ", e)
	if not logger.errors.is_empty():
		fails.append("%d engine errors" % logger.errors.size())
	for f in fails:
		printerr("FAIL: ", f)
	print("RESULT: ", "PASS" if fails.is_empty() else "FAIL")
	quit(0 if fails.is_empty() else 1)
	return true
