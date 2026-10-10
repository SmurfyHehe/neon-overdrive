extends SceneTree

# Chunk borders must not launch the car (2026-10-10, "the chunks are fighting
# again so you can hit something in the road that sends the car in the air").
#
# The cause that day: on the loop road, RoadAlignment gave each chunk's start
# from the stepped hill profile while the chunks were built from the eased
# one, so wherever the vertical bend changed the end of one chunk sat up to
# 25 cm above or below the start of the next: a kerb across the whole road.
#
# Without a game:
# - on a loop and on an endless road, for several seeds, every chunk ends at
#   the height and grade the next one starts at, computed the way
#   RoadChunkBuilder builds a chunk (start grade, bend, the two eased steps),
#   the lap's closing join included, and RoadAlignment.height_at agrees
# In the game (the default road as played: the loop, hills 0.5, curves 0.5,
# its own seed, no traffic), a scripted player holds the middle lane at
# SPEED for more than a whole lap (LAPS_CHUNKS chunk borders, the join where
# the lap closes among them, every chunk rebuilt at least once on the way):
# - the road's collision has no step at any border: rays dropped just before
#   and just after each join land within MAX_SURFACE_STEP of each other once
#   the grade between them is taken out
# - the car is never launched: its height above the road stays within
#   MAX_HOP of where it settled, it never has all four wheels off the ground
#   for MAX_AIR_TICKS in a row, and its vertical speed across the road never
#   exceeds MAX_UP_SPEED
# - the road really is hilly, the car held its speed, nothing logged
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/world/chunk_border_launch.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const B := preload("res://scripts/world/road_chunk_builder.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")

const L := B.CHUNK_LEN
const RATE := 120
const SPEED := 38.9  # m/s, 140 km/h
const SETTLE_TICKS := RATE * 3
const TIMEOUT_TICKS := RATE * 420
const PLAYER_LANE := 1
## Metres either side of a join the two rays are dropped at.
const PROBE := 0.25
const MAX_SURFACE_STEP := 0.01
const MAX_HOP := 0.15
const MAX_AIR_TICKS := 3
const MAX_UP_SPEED := 1.0

var logger := Harness.ErrorCounter.new()
var game: Node
var ready_ := false
var ticks := 0
var fails: Array[String] = []
var laps_chunks := 0
var start_chunk := 0
var last_chunk := 0
var borders := 0
var probed := 0
var worst_step := 0.0
var worst_step_at := 0
var rest_y := 0.0
var worst_hop := 0.0
var worst_hop_at := 0
var air_run := 0
var worst_air := 0
var worst_up := 0.0
var worst_up_at := 0
var max_grade := 0.0
var min_kmh := INF

func _check(ok: bool, msg: String) -> void:
	if not ok and fails.size() < 30:
		fails.append(msg)

func _initialize() -> void:
	_joins()
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	# The road as played; run_tests.bat sets these to 0 for the older tests.
	OS.set_environment("NEON_HILLS", "0.5")
	OS.set_environment("NEON_CURVES", "0.5")
	OS.set_environment("NEON_KICKERS", "0")
	OS.set_environment("NEON_ROAD", "")
	OS.set_environment("NEON_ROAD_SEED", "")
	game = Harness.boot(self, 0, 300.0, 777)

# ---------- without a game ----------

func _joins() -> void:
	var worst := 0.0
	var bends := 0.0
	for period: int in [128, 0]:
		for road_seed: int in [1, 2, 3, 37, 777, RoadMap.seed_of("loop_1")]:
			for hills: float in [0.5, 0.8]:
				var a := RoadAlignment.new(road_seed, 0.5, hills, 0.0, period)
				var from := -period - 3 if period > 0 else -3
				for i in range(from, 2 * maxi(period, 128) + 3):
					var g := a.start_grade(i)
					var c := a.vcurve(i)
					var dc_in := a.vstep(i)
					var dc_out := a.vstep(i + 1)
					bends = maxf(bends, absf(dc_in))
					# What RoadChunkBuilder puts at the far end of chunk i.
					var end_h := a.start_height(i) + RoadAlignment.ease_rise(g, c, dc_in, dc_out, L)
					var end_g := RoadAlignment.ease_grade(g, c, dc_in, dc_out, L)
					var step := absf(end_h - a.start_height(i + 1))
					var kink := absf(end_g - a.start_grade(i + 1))
					var api := absf(a.height_at(i, L) - a.start_height(i + 1)) + absf(a.grade_at(i, L) - a.start_grade(i + 1))
					worst = maxf(worst, maxf(step, maxf(kink, api)))
					if step > 1e-6 or kink > 1e-9 or api > 1e-6 or absf(dc_in - (c - a.vcurve(i - 1))) > 1e-12:
						_check(false, "%s seed %d hills %.1f: chunk %d ends %.4f m and %.5f grade off the start of chunk %d (height_at/grade_at off by %.4f)" % [
							"loop" if period > 0 else "endless", road_seed, hills, i, step, kink, i + 1, api])
						break
	_check(bends > 0.001, "the roads checked have no vertical bends (largest change %.5f)" % bends)
	print("chunk_border_launch joins: worst mismatch %.9f over loop and endless roads" % worst)

# ---------- in the game ----------

func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks > TIMEOUT_TICKS:
		fails.append("timed out after %d of %d chunk borders" % [borders, laps_chunks])
		return _end()
	var p: PlayerCar = game.get("player")
	if p == null:
		return false
	if not ready_:
		ready_ = true
		var cam: Node = game.get("camera")
		if cam != null:
			cam.set("shake_enabled", false)
		_check(RoadFrame.align != null and RoadFrame.align.period > 0, "the default road is not a loop")
		laps_chunks = (RoadFrame.align.period if RoadFrame.align != null else 128) + 12
		p.driver = Harness.lane_driver(Harness.lane_x(PLAYER_LANE), 1.0, SPEED)
		Harness.launch_player(p, SPEED)
		ticks = 0
		start_chunk = _chunk(p)
		last_chunk = start_chunk
		return false
	if not Harness.finite(p):
		fails.append("non-finite player state after %d chunk borders" % borders)
		return _end()
	var ci := _chunk(p)
	if ci > last_chunk:
		last_chunk = ci
		borders = ci - start_chunk
		_probe_join(ci, p)
	if ticks == SETTLE_TICKS:
		rest_y = RoadFrame.unroll(p.global_position).y
	if ticks > SETTLE_TICKS:
		_watch(p, ci)
	return _end() if borders >= laps_chunks else false

func _chunk(p: PlayerCar) -> int:
	return RoadFrame._chunk_of(RoadFrame.unroll(p.global_position).z)

func _watch(p: PlayerCar, ci: int) -> void:
	var u := RoadFrame.unroll(p.global_position)
	var hop := u.y - rest_y
	if hop > worst_hop:
		worst_hop = hop
		worst_hop_at = ci
	var grounded := 0
	for w in p.wheel_array:
		if w.is_colliding():
			grounded += 1
	air_run = air_run + 1 if grounded == 0 else 0
	worst_air = maxi(worst_air, air_run)
	# Speed away from the road surface: up, less what the grade asks for.
	var up := p.linear_velocity.dot(RoadFrame.basis_at(u.z).y)
	if up > worst_up:
		worst_up = up
		worst_up_at = ci
	max_grade = maxf(max_grade, absf(RoadFrame.align.grade_at(ci, RoadFrame._s_in_chunk(u.z, ci))))
	min_kmh = minf(min_kmh, Harness.kmh(p.current_speed()))

## The road collision either side of the start of chunk ci, under the car's
## lane and under the far lanes: both chunks are built by now (the car has
## just crossed), so their surfaces must meet.
func _probe_join(ci: int, p: PlayerCar) -> void:
	var z := -float(ci - RoadFrame.origin_index) * L
	var space := p.get_world_3d().direct_space_state
	for x: float in [Harness.lane_x(0), Harness.lane_x(PLAYER_LANE), Harness.lane_x(3)]:
		var before: float = _surface(space, x, z + PROBE, p)
		var after: float = _surface(space, x, z - PROBE, p)
		if is_nan(before) or is_nan(after):
			_check(false, "no road under the join into chunk %d at x %.1f" % [ci, x])
			continue
		probed += 1
		var step := absf(after - before)
		if step > worst_step:
			worst_step = step
			worst_step_at = ci

## Height of whatever a ray dropped at road-space (x, z) lands on, above the
## road surface RoadFrame describes there. NAN = nothing.
func _surface(space: PhysicsDirectSpaceState3D, x: float, z: float, p: PlayerCar) -> float:
	var top := RoadFrame.roll(Vector3(x, 3.0, z))
	var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 8.0)
	q.exclude = [p.get_rid()]
	q.hit_back_faces = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	return RoadFrame.unroll(hit.position).y

func _end() -> bool:
	print("chunk_border_launch: %d chunk borders at %.0f km/h or more, %d surface probes" % [borders, min_kmh, probed])
	print("  road collision step across a join: worst %.1f mm (into chunk %d)" % [worst_step * 1000.0, worst_step_at])
	print("  car above its settled height: worst %.0f mm (chunk %d); all wheels off the ground for at most %d ticks; fastest away from the road %.2f m/s (chunk %d); steepest grade %.1f%%" % [
		worst_hop * 1000.0, worst_hop_at, worst_air, worst_up, worst_up_at, max_grade * 100.0])
	_check(borders >= laps_chunks, "only %d of %d chunk borders crossed" % [borders, laps_chunks])
	_check(probed >= borders * 3 - 6, "only %d surface probes landed for %d borders" % [probed, borders])
	_check(worst_step < MAX_SURFACE_STEP, "the road collision steps %.1f mm at the join into chunk %d" % [worst_step * 1000.0, worst_step_at])
	_check(worst_hop < MAX_HOP, "the car rose %.0f mm above the road in chunk %d" % [worst_hop * 1000.0, worst_hop_at])
	_check(worst_air < MAX_AIR_TICKS, "all four wheels were off the ground for %d ticks in a row" % worst_air)
	_check(worst_up < MAX_UP_SPEED, "the car left the road at %.2f m/s in chunk %d" % [worst_up, worst_up_at])
	_check(max_grade > 0.02, "the road barely climbed: steepest grade %.1f%%" % (max_grade * 100.0))
	_check(min_kmh > SPEED * 3.6 * 0.85, "the car fell to %.0f km/h" % min_kmh)
	_check(logger.errors.is_empty(), "%d errors logged: %s" % [logger.errors.size(), logger.errors.slice(0, 3)])
	for f in fails:
		printerr("FAIL: " + f)
	print("chunk_border_launch: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
