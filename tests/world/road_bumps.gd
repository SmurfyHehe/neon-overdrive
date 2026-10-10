extends SceneTree

# Road bumps (Roy 2026-10-10: "I've driven over multiple bumps"): the real
# Game.tscn on the road the game ships (bends and hills on), no traffic, and a
# scripted player holding one lane for 3.5 km: 60 km/h, then 120, then 200,
# slowing for the bends it cannot take, with the floating origin recentring
# every 300 m.
#
# A bump is a tick where the car is shoved along the road's up axis harder
# than the road's own shape explains: the chassis' acceleration along the
# road's normal, less the v^2 / R of the crest or sag it is on, above JOLT.
# Ticks closer than GAP_S together count as one bump.
#
# What it caught (main 0e57c1b, 2026-10-10): the hilly road's collision was
# ten flat 5 m pieces per chunk, so every 5 m the surface folded under the
# wheels (suspension speed stepping 200-480 mm/s in a tick), and the chassis
# shape met those folds whenever a dip pressed the car down at speed (jolts
# of 20-46 m/s^2 at 245 km/h). See RoadChunkBuilder "Road collision".
#
# Asserts (exit code 1 on failure):
# - no bump over the whole run
# - no wheel's suspension speed steps by more than MAX_SPRING_STEP in a tick
#   (a fold in the surface under the wheel)
# - the chassis never touches the road, no wheel leaves it or climbs a kerb
# - no engine or script errors logged
# Prints bumps per km and the worst ones with where in their chunk they were.
#
# BUMP_KMH=<n> drives the whole way at one speed instead (245 = flat out),
# BUMP_DIST=<m> sets how far, NEON_ROAD_SEED picks the road (default 37),
# BUMP_LOG=1 prints every bump.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/world/road_bumps.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RATE := 120
const PLAYER_LANE := 1
const ROAD_SEED := 37
## Speed (km/h) held up to each distance (m).
const PHASES := [[60.0, 500.0], [120.0, 1700.0], [200.0, 3500.0]]
## m/s^2 along the road's normal, the hill's own v^2 / R taken out. Normal
## running stays under 1.0 (this test on a flat road, 245 km/h: p95 0.55).
const JOLT := 3.0
const GAP_S := 0.25
## mm/s from one tick to the next.
const MAX_SPRING_STEP := 150.0
const SETTLE_S := 3.0
## The scripted driver's bends: sideways m/s^2 it will take, and how hard it
## brakes for one ahead, m/s^2.
const BEND_LAT := 6.0
const BEND_BRAKE := 5.0

var logger := Harness.ErrorCounter.new()
var game: Node
var ready_ := false
var tick := 0
var fails: Array[String] = []
var phases: Array = PHASES
var distance := 3500.0
var log_all := false
var lane_driver: Callable

var start_z := 0.0
var travelled := 0.0
var checked_from := -1.0
var prev_vel := Vector3.ZERO
var prev_speed: Array[float] = [0.0, 0.0, 0.0, 0.0]
var prev_comp: Array[float] = [0.0, 0.0, 0.0, 0.0]
var have_prev := false
var bumps := 0
var last_bump_tick := -100000
var worst_jolt := 0.0
var worst_note := ""
var jolts := PackedFloat32Array()
var worst_spring_step := 0.0
var spring_note := ""
var spring_kinks := 0
var body_ticks := 0
var body_note := ""
var air_ticks := 0
var air_note := ""
var kerb_ticks := 0
var kerb_note := ""
var hull_low := INF
var hull_note := ""
var top_speed := 0.0
var shifts := 0
var last_origin := 0
var notes: Array[String] = []

func _initialize() -> void:
	OS.add_logger(logger)
	Engine.physics_ticks_per_second = RATE
	# The game's own road, whatever run_tests.bat set for the older tests.
	for knob in [["NEON_CURVES", "BUMP_CURVES"], ["NEON_HILLS", "BUMP_HILLS"]]:
		var v := OS.get_environment(knob[1])
		OS.set_environment(knob[0], v if v.is_valid_float() else "0.5")
	if not OS.get_environment("NEON_ROAD_SEED").is_valid_int():
		OS.set_environment("NEON_ROAD_SEED", str(ROAD_SEED))
	if OS.get_environment("BUMP_DIST").is_valid_float():
		distance = float(OS.get_environment("BUMP_DIST"))
	if OS.get_environment("BUMP_KMH").is_valid_float():
		phases = [[float(OS.get_environment("BUMP_KMH")), INF]]
	log_all = OS.get_environment("BUMP_LOG") == "1"
	game = Harness.boot(self, 0, 300.0, 777, 300.0)

func _setup() -> void:
	var p: PlayerCar = game.get("player")
	lane_driver = Harness.lane_driver(Harness.lane_x(PLAYER_LANE), 1.0)
	p.driver = _drive
	var cam: Node = game.get("camera")
	if cam != null:
		cam.set("shake_enabled", false)
	Harness.launch_player(p, minf(float(phases[0][0]), 200.0) / 3.6)
	ready_ = true

## Holds the lane, at the phase's speed or what the bends ahead allow.
func _drive(c: Vehicle) -> void:
	lane_driver.call(c)
	var want := float(phases[-1][0]) / 3.6
	for ph in phases:
		if travelled < float(ph[1]):
			want = float(ph[0]) / 3.6
			break
	var z := RoadFrame.unroll(c.global_position).z
	var here := RoadFrame._chunk_of(z)
	var s := RoadFrame._s_in_chunk(z, here)
	for n in 8:
		var k := absf(RoadFrame.curvature(here + n))
		if k > 0.0:
			var ahead := maxf(float(n) * RoadChunkBuilder.CHUNK_LEN - s, 0.0)
			want = minf(want, sqrt(BEND_LAT / k + 2.0 * BEND_BRAKE * ahead))
	var v: float = c.current_speed()
	c.throttle_input = 1.0 if v < want else 0.0
	c.brake_input = 0.6 if v > want + 2.0 else 0.0

func _physics_process(delta: float) -> bool:
	if game.get("player") == null:
		return false
	if not ready_:
		_setup()
		return false
	tick += 1
	if tick > RATE * 600:
		return _end("timed out, %.0f m driven" % travelled)
	var p: PlayerCar = game.get("player")
	if not Harness.finite(p):
		return _end("non-finite player state at tick %d" % tick)
	var origin: int = game.get("origin_index")
	if origin != last_origin:
		shifts += 1
		last_origin = origin
	var u := RoadFrame.unroll(p.global_position)
	var road_z := u.z - float(origin) * RoadChunkBuilder.CHUNK_LEN
	if tick == 1:
		start_z = road_z
	travelled = start_z - road_z
	var chunk := RoadFrame._chunk_of(u.z)
	var vel := p.linear_velocity
	if have_prev and tick > int(SETTLE_S * RATE):
		if checked_from < 0.0:
			checked_from = travelled
		top_speed = maxf(top_speed, p.current_speed())
		var road := RoadFrame.basis_at(u.z)
		var along := vel.dot(road * Vector3.FORWARD)
		var jolt := (vel - prev_vel).dot(road.y) / delta - along * along * RoadFrame.vcurve(chunk)
		jolts.append(absf(jolt))
		var where := "%.0f m in, chunk %d + %.1f m, %.0f km/h, %s" % [
			travelled, chunk, RoadFrame._s_in_chunk(u.z, chunk), Harness.kmh(p.current_speed()), _shape(chunk)]
		if absf(jolt) > JOLT:
			if tick - last_bump_tick > int(GAP_S * RATE):
				bumps += 1
				if log_all or notes.size() < 12:
					notes.append("%.1f m/s^2 at %s" % [jolt, where])
			last_bump_tick = tick
		if absf(jolt) > worst_jolt:
			worst_jolt = absf(jolt)
			worst_note = where
		var grounded := 0
		for i in p.wheel_array.size():
			var w: Wheel = p.wheel_array[i]
			if w.is_colliding():
				grounded += 1
				if not (w.get_collider() as Node).is_in_group("Road"):
					kerb_ticks += 1
					if kerb_note == "":
						kerb_note = "%s, %s" % [(w.get_collider() as Node).name, where]
			var step := absf((w.previous_compression - prev_comp[i]) / delta - prev_speed[i])
			if step > MAX_SPRING_STEP:
				spring_kinks += 1
			if step > worst_spring_step:
				worst_spring_step = step
				spring_note = "wheel %d, %s" % [i, where]
		if grounded < p.wheel_array.size():
			air_ticks += 1
			if air_note == "":
				air_note = where
		for cs in p.get_children():
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape is ConvexPolygonShape3D:
				for pt in ((cs as CollisionShape3D).shape as ConvexPolygonShape3D).points:
					var y := RoadFrame.unroll((cs as CollisionShape3D).global_transform * pt).y
					if y < hull_low:
						hull_low = y
						hull_note = where
		for b in p.get_colliding_bodies():
			if b.is_in_group("Road") or b.is_in_group("Dirt"):
				body_ticks += 1
				if body_note == "":
					body_note = "%s/%s, %s" % [b.get_parent().name, b.name, where]
	for i in p.wheel_array.size():
		var w: Wheel = p.wheel_array[i]
		prev_speed[i] = (w.previous_compression - prev_comp[i]) / delta
		prev_comp[i] = w.previous_compression
	prev_vel = vel
	have_prev = true
	if travelled >= distance:
		return _end("")
	return false

func _shape(chunk: int) -> String:
	var vc := RoadFrame.vcurve(chunk)
	var k := RoadFrame.curvature(chunk)
	return "%s, %s" % [
		"even grade" if vc == 0.0 else "%s R %.0f m" % ["sag" if vc > 0.0 else "crest", absf(1.0 / vc)],
		"straight" if k == 0.0 else "bend R %.0f m" % absf(1.0 / k)]

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		fails.append(msg)
	var km := maxf(travelled - checked_from, 1.0) / 1000.0
	print("road_bumps: %.0f m, up to %.0f km/h, seed %s, %d origin shifts" % [travelled, Harness.kmh(top_speed), OS.get_environment("NEON_ROAD_SEED"), shifts])
	print("  bumps over %.1f m/s^2: %d = %.1f per km; worst %.2f m/s^2 (%s)" % [JOLT, bumps, float(bumps) / km, worst_jolt, worst_note])
	print("  jolt along the road's normal, m/s^2: %s" % (Harness.stats(jolts) if jolts.size() > 0 else {}))
	print("  suspension: worst speed step %.0f mm/s in a tick (%s); %d steps over %.0f = %.1f per km" % [
		worst_spring_step, spring_note, spring_kinks, MAX_SPRING_STEP, float(spring_kinks) / km])
	print("  chassis on the road %d ticks (%s); a wheel off it %d ticks (%s); on a kerb %d (%s)" % [body_ticks, body_note, air_ticks, air_note, kerb_ticks, kerb_note])
	print("  underside: lowest %.3f m above the road (%s)" % [hull_low, hull_note])
	for n in notes:
		print("  bump: " + n)
	_check(bumps == 0, "%d bumps (%.1f per km), worst %.1f m/s^2 (%s)" % [bumps, float(bumps) / km, worst_jolt, worst_note])
	_check(spring_kinks == 0, "%d suspension speed steps over %.0f mm/s, worst %.0f (%s)" % [spring_kinks, MAX_SPRING_STEP, worst_spring_step, spring_note])
	_check(body_ticks == 0, "the chassis touched the road for %d ticks (%s)" % [body_ticks, body_note])
	_check(air_ticks == 0, "a wheel left the road for %d ticks (%s)" % [air_ticks, air_note])
	_check(kerb_ticks == 0, "the scripted driver ran onto a kerb (%s)" % kerb_note)
	_check(shifts >= 3, "only %d origin shifts" % shifts)
	_check(logger.errors.is_empty(), "%d errors logged: %s" % [logger.errors.size(), logger.errors.slice(0, 3)])
	for f in fails:
		printerr("FAIL: " + f)
	print("road_bumps: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(1 if not fails.is_empty() else 0)
	return true
