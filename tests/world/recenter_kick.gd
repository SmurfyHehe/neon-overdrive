extends SceneTree

# Recenter-kick regression test: the player at full throttle (~245 km/h) dead
# straight in its lane on an empty road, with the floating origin (game.gd)
# recentering every RECENTER m, so a run crosses many shifts at top speed.
#
# The bug (2026-10-06): at that speed the rear-bottom edge of the chassis
# collision box rides on the ground (aero downforce + squat). The ground was a
# BoxShape3D slab, and box-vs-box on an edge lying flat on a face is
# ill-conditioned: on some ticks Godot's separating-axis test picks an
# edge-edge axis, the contact normal tilts ~1-2 deg, and one physics step
# throws the car up and sideways (-0.5 m/s, rear up +0.4 m/s, yaw 0.17 rad/s).
# The rear springs then over-extend, GEVP drops both rear wheels' tyre force
# for a few ticks and the car weaves at 3-9 m/s^2. Whether a tick goes bad
# depends on float rounding at the car's spot on the slab, and recentering
# sends the car over the same stretch of slab again and again at full speed,
# which is why it showed up ~0.5-1.5 s after a recenter. The ground is now a
# WorldBoundaryShape3D plane (game.gd), which has no edges.
#
# Asserts (exit code 1 on failure), over every tick once the car is above
# FAST:
# - all four wheels carry load (GEVP tyre force is zero on a wheel that has
#   no ground contact or whose spring over-extended)
# - peak lateral acceleration in the car's frame stays under MAX_LAT
#   (normal running, rev-limiter throttle cuts included, is ~0.6)
# - peak yaw rate stays under MAX_YAW (normal running is ~0.014)
# - the per-tick position step, recenter offset taken out, matches one tick
#   of velocity (an unshifted saved position would read as a 1 km/s burst)
# Runs at the game's 120 Hz whatever NEON_TICKS says (run_tests.bat sets 60);
# NEON_KICK_HZ=60 with --fixed-fps 60 runs it at 60. NEON_KICK_LOG=1 prints
# each bad tick.
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 120 --path . -s res://tests/world/recenter_kick.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const RECENTER := 300.0  # m; 300 reproduced the kick on main at both 60 and 120 Hz
const FAST := 200.0 / 3.6  # m/s; checks start above this
const CHECK_SECS := 25.0  # seconds of checked driving above FAST
const MIN_RECENTERS := 5
const MAX_LAT := 1.0  # m/s^2
const MAX_YAW := 0.03  # rad/s
const MAX_STEP_ERR := 0.01  # m

var rate := 60
var logger := Harness.ErrorCounter.new()
var game: Node
var tick := 0
var fast_ticks := 0
var fails: Array[String] = []
var log_ticks := false

var last_origin := 0
var shift_tick := -100000
var recenters_fast := 0
var prev_vel := Vector3.ZERO
var prev_pos := Vector3.ZERO
var have_prev := false

var unloaded_ticks := 0
var unloaded_note := ""
var peak_lat := 0.0
var peak_lat_note := ""
var peak_yaw := 0.0
var peak_yaw_note := ""
var peak_step_err := 0.0
var top_speed := 0.0

func _initialize() -> void:
	OS.add_logger(logger)
	ExhaustTune.save_path = "user://autotune/test_recenter_kick_exhaust.json"
	var hz := OS.get_environment("NEON_KICK_HZ")
	rate = int(hz) if hz.is_valid_int() else 120
	Engine.physics_ticks_per_second = rate
	log_ticks = OS.get_environment("NEON_KICK_LOG") == "1"
	game = Harness.boot(self, 0, 300.0, 4242, RECENTER)

func _physics_process(delta: float) -> bool:
	if Engine.get_physics_frames() > rate * 120:
		return _end("timed out before %.0f s above %.0f km/h (top %.0f km/h)" % [CHECK_SECS, Harness.kmh(FAST), Harness.kmh(top_speed)])
	var p: PlayerCar = game.get("player")
	if p == null or not p.is_ready:
		return false
	if tick == 0:
		p.driver = Harness.lane_driver(TrafficManager.lane_centre(game.PLAYER_SPAWN_LANE, false), 1.0)
	tick += 1
	if not Harness.finite(p):
		return _end("non-finite player state at tick %d" % tick)

	# This script's _physics_process runs before the scene's, so this is the
	# state the last physics step left.
	var origin: int = game.get("origin_index")
	var shifted := origin != last_origin
	var shift_m := float(origin - last_origin) * RoadChunkBuilder.CHUNK_LEN
	if shifted:
		shift_tick = tick
		last_origin = origin
	var vel := p.linear_velocity
	var pos := p.global_position
	var speed := vel.length()
	top_speed = maxf(top_speed, speed)

	if have_prev and speed > FAST:
		fast_ticks += 1
		if shifted:
			recenters_fast += 1
		var since := tick - shift_tick
		var note := "tick %d, %.0f km/h, %.2f s after a recenter, x=%.2f z=%.1f" % [
			tick, Harness.kmh(speed), float(since) / rate, pos.x, pos.z]
		var accel := (vel - prev_vel) / delta
		var lat := absf(p.global_transform.basis.x.dot(accel))
		var yaw := absf(p.angular_velocity.y)
		var unloaded: Array[String] = []
		for i in p.wheel_array.size():
			var w: Wheel = p.wheel_array[i]
			if w.last_collider == null or w.spring_force <= 0.0:
				unloaded.append(["FL", "FR", "RL", "RR"][i])
		if not unloaded.is_empty():
			unloaded_ticks += 1
			if unloaded_note == "":
				unloaded_note = "%s, %s" % [" ".join(unloaded), note]
		if lat > peak_lat:
			peak_lat = lat
			peak_lat_note = note
		if yaw > peak_yaw:
			peak_yaw = yaw
			peak_yaw_note = note
		var step := pos - prev_pos - Vector3(0.0, 0.0, shift_m)
		peak_step_err = maxf(peak_step_err, (step - (vel + prev_vel) * 0.5 * delta).length())
		if log_ticks and (not unloaded.is_empty() or lat > MAX_LAT or yaw > MAX_YAW):
			print("BAD %s: unloaded=%s lat=%.2f yaw=%.4f y=%.4f vy=%.3f" % [note, unloaded, lat, yaw, pos.y, vel.y])
	prev_vel = vel
	prev_pos = pos
	have_prev = true
	if fast_ticks >= int(CHECK_SECS * rate):
		return _end("")
	return false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		fails.append(msg)
	print("recenter_kick: %d Hz, %d ticks above %.0f km/h, top %.0f km/h, %d recenters at speed (every %.0f m)" % [
		rate, fast_ticks, Harness.kmh(FAST), Harness.kmh(top_speed), recenters_fast, RECENTER])
	print("recenter_kick: ticks with a wheel carrying no load %d%s" % [unloaded_ticks, (" (first: %s)" % unloaded_note) if unloaded_note != "" else ""])
	print("recenter_kick: peak lateral accel %.3f m/s^2 (%s)" % [peak_lat, peak_lat_note])
	print("recenter_kick: peak yaw rate %.4f rad/s (%s)" % [peak_yaw, peak_yaw_note])
	print("recenter_kick: worst position step error %.4f m" % peak_step_err)
	_check(recenters_fast >= MIN_RECENTERS, "only %d recenters at speed" % recenters_fast)
	_check(unloaded_ticks == 0, "%d ticks with a wheel carrying no load (first: %s)" % [unloaded_ticks, unloaded_note])
	_check(peak_lat < MAX_LAT, "lateral kick %.2f m/s^2 (limit %.1f) at %s" % [peak_lat, MAX_LAT, peak_lat_note])
	_check(peak_yaw < MAX_YAW, "yaw rate %.4f rad/s (limit %.2f) at %s" % [peak_yaw, MAX_YAW, peak_yaw_note])
	_check(peak_step_err < MAX_STEP_ERR, "position step off its velocity by %.4f m" % peak_step_err)
	for e in logger.errors:
		fails.append("logged error: " + e)
	for f in fails:
		printerr("FAIL: ", f)
	print("recenter_kick: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	OS.remove_logger(logger)
	quit(0 if fails.is_empty() else 1)
	return true
