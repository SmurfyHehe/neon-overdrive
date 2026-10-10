extends SceneTree

# Road bumps (2026-10-10, "I've driven over multiple bumps"): the real
# Game.tscn on the default kind of road (hills 0.5, curves 0.5, fixed seed),
# no traffic, and a scripted player holding the middle lane for 5 km at
# 120 km/h and then 5 km at 200 km/h.
#
# A smooth road moves a wheel's spring smoothly. A bump shows as a jump in the
# spring's speed from one physics tick to the next (that jump, times the
# damper rate, is the kick the body gets), so that is what is measured, for
# every wheel on every tick, with where along the road it happened.
#
# Asserts (exit code 1 on failure), per speed:
# - no wheel's spring speed changes by more than MAX_WHEEL_STEP in one tick
# - the body's vertical speed never changes by more than MAX_BODY_STEP in one
#   tick
# - the larger spring jumps (over SPIKE) are not bunched at one place along
#   the road's old 5 m collision pieces or at the 50 m chunk joins: a faceted
#   road kicks at every facet edge, a smooth one has no favourite spot
# - the player never leaves the ground
# - the road really is hilly (unless the control run below), nothing logged
# Prints the numbers either way, and what one chunk rebuild costs.
#
# Hard cornering is measured apart and not asserted: the script holds 200 km/h
# through bends a driver would lift for (0.8 g on a 390 m bend), the body
# rolls onto its outside springs, and where such a bend flips direction in a
# dip the chassis touches the road. That is the car's ground clearance and
# the bends' abrupt starts, on a flat road's bends too if less; it is printed
# ("while cornering hard") so it is not lost. Nothing at 120 km/h corners
# that hard, so that pass is asserted whole.
#
# HILL_BUMPS_HILLS=0 is the control: the same drive on a flat road (the
# infinite ground plane), which shows the car's own noise floor (worst wheel
# step 30 mm/s at 120 km/h, 56 at 200, 2026-10-10).
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/world/hill_bumps.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const B := preload("res://scripts/world/road_chunk_builder.gd")

const RATE := 120
const SPEEDS: Array[float] = [33.33, 55.56]  # m/s: 120 and 200 km/h
const DISTANCE := 5000.0  # per speed
const SETTLE_TICKS := RATE * 3
const TIMEOUT_TICKS := RATE * 600
const PLAYER_LANE := 1
const ROAD_SEED := 37
## mm/s change in a wheel's spring speed, or in the body's vertical speed,
## within one physics tick.
const MAX_WHEEL_STEP := 150.0
const MAX_BODY_STEP := 150.0
## A spring jump big enough to count when looking for bunching, mm/s.
const SPIKE := 40.0
## Road pieces checked for bunching, m, and how far past a piece's edge a
## jump still belongs to it (the wheel moves up to 0.46 m a tick, and a jump
## shows on the tick after the edge and the one after that).
const FACET := 5.0
const NEAR := 1.0
const MIN_SPIKES := 200
## Share of spikes within NEAR of a FACET edge; an even spread gives 0.2.
const MAX_FACET_SHARE := 0.4
## Same at the chunk joins; an even spread gives 0.02.
const MAX_JOIN_SHARE := 0.15
## Sideways acceleration the bend asks for (speed^2 x curvature), m/s^2, past
## which the car counts as cornering hard, and for how long after.
const HARD_CORNER := 5.0
const HARD_CORNER_TICKS := RATE * 3 / 2

var logger := Harness.ErrorCounter.new()
var game: Node
var ready_ := false
var hilly := true
var phase := 0
var phase_tick := 0
var phase_start_z := 0.0
var travelled := 0.0
var fails: Array[String] = []
var max_grade := 0.0

# This phase's numbers.
var prev_len := PackedFloat32Array([0, 0, 0, 0])
var prev_speed := PackedFloat32Array([0, 0, 0, 0])
var prev_ground := [false, false, false, false]
var prev_vy := 0.0
var wheel_steps := PackedFloat32Array()
var body_steps := PackedFloat32Array()
var worst_wheel := 0.0
var worst_wheel_note := ""
var worst_body := 0.0
var worst_body_note := ""
var spikes := 0
var spikes_at_facet := 0
var spikes_at_join := 0
var air_ticks := 0
var min_kmh := INF
var max_kmh := 0.0
var since_corner := 1 << 30
var corner_ticks := 0
var measured_ticks := 0
var corner_wheel := 0.0
var corner_body := 0.0
var corner_note := ""

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	# Its own knob: run_tests.bat sets NEON_HILLS=0 for the older drive tests.
	var hills := OS.get_environment("HILL_BUMPS_HILLS")
	OS.set_environment("NEON_HILLS", hills if hills.is_valid_float() else "0.5")
	hilly = float(OS.get_environment("NEON_HILLS")) > 0.0
	OS.set_environment("NEON_CURVES", "0.5")
	OS.set_environment("NEON_KICKERS", "0")
	if not OS.get_environment("NEON_ROAD_SEED").is_valid_int():
		OS.set_environment("NEON_ROAD_SEED", str(ROAD_SEED))
	game = Harness.boot(self, 0, 300.0, 777)

func _start_phase(p: PlayerCar) -> void:
	p.driver = Harness.lane_driver(Harness.lane_x(PLAYER_LANE), 1.0, SPEEDS[phase])
	Harness.launch_player(p, SPEEDS[phase])
	phase_tick = 0
	wheel_steps.clear()
	body_steps.clear()
	worst_wheel = 0.0
	worst_body = 0.0
	spikes = 0
	spikes_at_facet = 0
	spikes_at_join = 0
	air_ticks = 0
	min_kmh = INF
	max_kmh = 0.0
	since_corner = 1 << 30
	corner_ticks = 0
	measured_ticks = 0
	corner_wheel = 0.0
	corner_body = 0.0
	corner_note = ""

func _physics_process(delta: float) -> bool:
	if Engine.get_physics_frames() > TIMEOUT_TICKS:
		fails.append("timed out in phase %d, %.0f m driven" % [phase, travelled])
		return _end()
	var p: PlayerCar = game.get("player")
	if p == null:
		return false
	if not ready_:
		ready_ = true
		var cam: Node = game.get("camera")
		if cam != null:
			cam.set("shake_enabled", false)
		_start_phase(p)
		return false
	if not Harness.finite(p):
		fails.append("non-finite player state in phase %d" % phase)
		return _end()
	phase_tick += 1
	var u := RoadFrame.unroll(p.global_position)
	var road_z := u.z - float(game.get("origin_index")) * B.CHUNK_LEN  # not reset by recentring
	if phase_tick == 1:
		phase_start_z = road_z
	travelled = phase_start_z - road_z
	var ci := RoadFrame._chunk_of(u.z)
	if RoadFrame.align != null:
		max_grade = maxf(max_grade, absf(RoadFrame.align.grade_at(ci, RoadFrame._s_in_chunk(u.z, ci))))
	var speed := p.current_speed()
	var side_g := speed * speed * absf(RoadFrame.curvature(ci))
	since_corner = 0 if side_g > HARD_CORNER else since_corner + 1
	_measure(p, delta, side_g)
	if travelled >= DISTANCE:
		_report()
		phase += 1
		if phase >= SPEEDS.size():
			return _end()
		_start_phase(p)
	return false

func _measure(p: PlayerCar, delta: float, side_g: float) -> void:
	var measuring := phase_tick > SETTLE_TICKS
	var cornering := since_corner < HARD_CORNER_TICKS
	var kmh := Harness.kmh(p.current_speed())
	var origin_s := float(game.get("origin_index")) * B.CHUNK_LEN
	var grounded := 0
	for i in p.wheel_array.size():
		var w = p.wheel_array[i]
		var on_ground: bool = w.is_colliding()
		var length: float = w.spring_current_length
		var speed := (prev_len[i] - length) * 1000.0 / delta  # + = compressing
		if on_ground:
			grounded += 1
		# On the ground this tick and the two before, so both speeds are real.
		if measuring and on_ground and prev_ground[i]:
			var step := absf(speed - prev_speed[i])
			if cornering:
				if step > corner_wheel:
					corner_wheel = step
					corner_note = "%.0f m in, bend asking %.1f m/s^2" % [travelled, side_g]
			else:
				wheel_steps.append(step)
				var s := origin_s - RoadFrame.unroll(w.get_collision_point()).z
				if step > worst_wheel:
					worst_wheel = step
					worst_wheel_note = "wheel %d, %.0f m in, %.2f m into its chunk, %.0f km/h" % [i, travelled, fposmod(s, B.CHUNK_LEN), kmh]
				if step > SPIKE:
					spikes += 1
					if fposmod(s, FACET) < NEAR:
						spikes_at_facet += 1
					if fposmod(s, B.CHUNK_LEN) < NEAR:
						spikes_at_join += 1
		prev_ground[i] = on_ground and prev_len[i] != 0.0
		prev_speed[i] = speed
		prev_len[i] = length
	var vy := p.linear_velocity.y
	if measuring:
		measured_ticks += 1
		min_kmh = minf(min_kmh, kmh)
		max_kmh = maxf(max_kmh, kmh)
		if grounded == 0:
			air_ticks += 1
		var body_step := absf(vy - prev_vy) * 1000.0
		if cornering:
			corner_ticks += 1
			corner_body = maxf(corner_body, body_step)
		else:
			body_steps.append(body_step)
			if body_step > worst_body:
				worst_body = body_step
				worst_body_note = "%.0f m in, %.2f m into its chunk" % [travelled, fposmod(origin_s - RoadFrame.unroll(p.global_position).z, B.CHUNK_LEN)]
	prev_vy = vy

func _pct(a: PackedFloat32Array, share: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[mini(s.size() - 1, int(share * s.size()))]

func _report() -> void:
	var name_ := "%.0f km/h" % (SPEEDS[phase] * 3.6)
	var facet_share := float(spikes_at_facet) / float(maxi(spikes, 1))
	var join_share := float(spikes_at_join) / float(maxi(spikes, 1))
	print("hill_bumps %s: %.0f m at %.0f..%.0f km/h, %d wheel samples" % [name_, travelled, min_kmh, max_kmh, wheel_steps.size()])
	print("  wheel spring-speed step per tick, mm/s: worst %.0f (%s), 99.9%% %.0f, 99%% %.0f, median %.1f" % [
		worst_wheel, worst_wheel_note, _pct(wheel_steps, 0.999), _pct(wheel_steps, 0.99), _pct(wheel_steps, 0.5)])
	print("  body vertical-speed step per tick, mm/s: worst %.0f (%s), 99.9%% %.0f, median %.1f" % [
		worst_body, worst_body_note, _pct(body_steps, 0.999), _pct(body_steps, 0.5)])
	print("  spikes over %.0f mm/s: %d (%.1f per km); %.0f%% within %.1f m after a 5 m multiple (even spread: 20%%), %.0f%% within %.1f m after a chunk join (even: 2%%); air ticks %d" % [
		SPIKE, spikes, float(spikes) / (DISTANCE / 1000.0), facet_share * 100.0, NEAR, join_share * 100.0, NEAR, air_ticks])
	if corner_ticks > 0:
		print("  while cornering hard (%.0f%% of the drive, not asserted): worst wheel step %.0f mm/s (%s), worst body step %.0f mm/s" % [
			100.0 * float(corner_ticks) / float(maxi(measured_ticks, 1)), corner_wheel, corner_note, corner_body])
	_check(min_kmh > SPEEDS[phase] * 3.6 * 0.9, "%s: the car fell to %.0f km/h" % [name_, min_kmh])
	_check(float(corner_ticks) < 0.5 * float(measured_ticks), "%s: cornering hard for %d of %d ticks, too little left to judge" % [name_, corner_ticks, measured_ticks])
	_check(worst_wheel < MAX_WHEEL_STEP, "%s: a wheel's spring speed jumped %.0f mm/s in one tick (%s)" % [name_, worst_wheel, worst_wheel_note])
	_check(worst_body < MAX_BODY_STEP, "%s: the body's vertical speed jumped %.0f mm/s in one tick (%s)" % [name_, worst_body, worst_body_note])
	if spikes >= MIN_SPIKES:
		_check(facet_share < MAX_FACET_SHARE, "%s: %.0f%% of %d spring spikes sit at 5 m multiples along the road" % [name_, facet_share * 100.0, spikes])
		_check(join_share < MAX_JOIN_SHARE, "%s: %.0f%% of %d spring spikes sit at chunk joins" % [name_, join_share * 100.0, spikes])
	_check(air_ticks == 0, "%s: the player was off the ground for %d ticks" % [name_, air_ticks])

## What one chunk rebuild costs on this road, ms (the recycle path game.gd
## runs about once a second at speed), and how many triangles the road
## collision carries.
func _time_rebuilds() -> void:
	var cfg := {"own_lanes": 4, "onc_lanes": 4, "barrier": true}
	var chunk: Node3D = B.build_chunk(0, cfg, cfg, RoadFrame.origin_index)
	root.add_child(chunk)
	var shape := (chunk.get_node(^"RoadCol/Shape") as CollisionShape3D).shape as ConcavePolygonShape3D
	var times := PackedFloat32Array()
	var first: int = RoadFrame.origin_index
	var tris := 0
	var most := 0
	for pass_i in 4:
		for i in 100:
			var t := Time.get_ticks_usec()
			B.rebuild_chunk(chunk, first + i, cfg, cfg, RoadFrame.origin_index)
			if pass_i > 0:  # the first pass warms caches up
				times.append(float(Time.get_ticks_usec() - t) / 1000.0)
			else:
				var n := shape.get_faces().size() / 3
				tris += n
				most = maxi(most, n)
	chunk.free()
	var total := 0.0
	for t in times:
		total += t
	print("  chunk rebuild over %d rebuilds of 100 chunks: mean %.3f ms, median %.3f ms, worst %.3f ms; road collision mean %d triangles a chunk, most %d" % [
		times.size(), total / times.size(), _pct(times, 0.5), _pct(times, 1.0), tris / 100, most])

func _check(ok: bool, msg: String) -> void:
	if not ok and fails.size() < 30:
		fails.append(msg)

func _end() -> bool:
	_time_rebuilds()
	print("  road: hills %s, steepest grade driven %.1f%%" % [OS.get_environment("NEON_HILLS"), max_grade * 100.0])
	if hilly:
		_check(max_grade > 0.03, "the road barely climbed: steepest grade %.1f%%" % (max_grade * 100.0))
	_check(logger.errors.is_empty(), "%d errors logged: %s" % [logger.errors.size(), logger.errors.slice(0, 3)])
	for f in fails:
		printerr("FAIL: " + f)
	print("hill_bumps: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
