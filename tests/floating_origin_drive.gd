extends SceneTree

# Floating-origin test (issue #26): drives the real Game.tscn a long way down
# the road and checks the world recentering never shows up as a physics or
# rendering glitch.
#
# Setup:
# - "Far teleport": right after load, the chunk pool is relabelled FAR_CHUNKS
#   chunks down the road (500 km) and origin_index moved to match -- the
#   state the game is in after an hour-plus of driving. With the old code the
#   car would be at z=-500000 here, past the end of the 200 km ground slab.
# - recenter_dist is lowered to 200 so a 45 s drive crosses many recenters.
#
# Asserts (exit code 1 on failure):
# - enough recenters happened to mean something
# - physics, per 60 Hz tick: on a recenter tick, GEVP's speed, the body's
#   velocity and every wheel's suspension length change no more than they do
#   on ordinary ticks (an unshifted saved position would read as a 60 km/s
#   burst), and distance travelled matches speed x dt
# - rendering, per frame: the car's interpolated position moves smoothly in
#   road terms (no 200 m slide across a tick), the chase camera keeps its
#   fixed offset from the car, and every chunk sits exactly where its index
#   says
# - the car stays near the origin and on the ground throughout
#
# Run (real renderer; a window opens for RUN_SECS):
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/floating_origin_drive.gd

const RUN_SECS := 45.0
const FAR_CHUNKS := 10000  # x 50 m = 500 km
const TEST_RECENTER_DIST := 200.0
const MIN_RECENTERS := 5

var game: Node
var t := 0.0
var started := false
var fails := 0

# per-tick physics samples
var last_origin := 0
var prev := {}
var normal_max := {"speed": 0.0, "lin": 0.0, "spring": 0.0}
var shift_max := {"speed": 0.0, "lin": 0.0, "spring": 0.0}
var worst_travel_err := 0.0
var max_abs_z := 0.0
var ticks := 0

# per-frame render samples
var prev_road_z := NAN
var prev_phys_frame := 0
var worst_frame_step := 0.0
var worst_cam_err := 0.0
var max_speed := 0.0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")  # an empty road, whatever run_tests.bat or the saved settings say
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	seed(777)
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	game.set("recenter_dist", TEST_RECENTER_DIST)
	root.add_child(game)
	(game.get("camera") as ChaseCamera).shake_enabled = false
	_teleport_far()
	# Render checks run right before drawing, after every node's _process
	# (the camera moves in game.gd's _process), so they see the drawn frame.
	RenderingServer.frame_pre_draw.connect(_check_drawn_frame)

func _teleport_far() -> void:
	# Relabel every pooled chunk FAR_CHUNKS further on and move the origin by
	# the same amount: world positions stay put, logical position is 500 km.
	game.set("origin_index", FAR_CHUNKS)
	for c in game.get("chunk_pool"):
		c.index += FAR_CHUNKS
		RoadChunkBuilder.rebuild_chunk(c.root, c.index, game.call("_section_at", c.index - 1), game.call("_section_at", c.index), FAR_CHUNKS)
	last_origin = FAR_CHUNKS

func _press(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _road_z(z: float, origin: int) -> float:
	# Distance down the road in metres, independent of the origin.
	return float(origin) * RoadChunkBuilder.CHUNK_LEN - z

func _physics_process(delta: float) -> bool:
	var p: PlayerCar = game.get("player")
	if p == null or not p.is_ready:
		return false
	ticks += 1
	var origin: int = game.get("origin_index")
	var springs: Array = []
	for w in p.wheel_array:
		springs.append(w.spring_current_length)
	var cur := {
		"speed": p.speed,
		"lin": p.linear_velocity.length(),
		"road_z": _road_z(p.global_position.z, origin),
		"vz": -p.linear_velocity.z,
		"springs": springs,
	}
	max_abs_z = max(max_abs_z, absf(p.global_position.z))
	if p.global_position.y < -1.0:
		_fail("car fell through the ground at road z=%.1f" % cur.road_z)

	# Skip the first second: the car is settling onto its springs.
	if not prev.is_empty() and ticks > 60:
		var shifted := origin != last_origin
		var bucket: Dictionary = shift_max if shifted else normal_max
		bucket.speed = max(bucket.speed, absf(cur.speed - prev.speed))
		bucket.lin = max(bucket.lin, absf(cur.lin - prev.lin))
		for i in springs.size():
			bucket.spring = max(bucket.spring, absf(springs[i] - prev.springs[i]))
		var travel: float = cur.road_z - prev.road_z
		var expected: float = (cur.vz + prev.vz) / 2.0 * delta
		worst_travel_err = max(worst_travel_err, absf(travel - expected))
	prev = cur
	last_origin = origin
	return false

func _process(delta: float) -> bool:
	if not started:
		started = true
		_press(KEY_W, true)
		return false
	t += delta

	var p: PlayerCar = game.get("player")
	var speed := p.linear_velocity.length()
	max_speed = max(max_speed, speed)
	var err: float = p.global_rotation.y + clampf((RoadChunkBuilder.LANE_W * 1.5 - p.global_position.x) * 0.02, -0.05, 0.05)
	_press(KEY_A, err < -0.02)
	_press(KEY_D, err > 0.02)
	if p.gear >= 1 and p.gear < 6 and speed > 9.0 * p.gear and not p.is_shifting:
		_press(KEY_E, true)
		_press(KEY_E, false)

	if t >= RUN_SECS:
		_report(p)
		quit(0 if fails == 0 else 1)
		return true
	return false

func _check_drawn_frame() -> void:
	if not started:
		return
	var p: PlayerCar = game.get("player")
	# What is actually drawn: the interpolated car, the camera, the chunks.
	var origin: int = game.get("origin_index")
	var ip := p.get_global_transform_interpolated().origin
	var road_z := _road_z(ip.z, origin)
	var phys_frame := Engine.get_physics_frames()
	if not is_nan(prev_road_z):
		# At most one tick's travel per physics tick this frame spanned; a
		# slide across a recenter would be ~200 m.
		var ticks_spanned := maxi(phys_frame - prev_phys_frame, 1)
		var allowed := p.linear_velocity.length() / 60.0 * float(ticks_spanned) * 1.5 + 0.1
		worst_frame_step = max(worst_frame_step, absf(road_z - prev_road_z) - allowed)
	prev_road_z = road_z
	prev_phys_frame = phys_frame
	var cam: ChaseCamera = game.get("camera")
	# Stage A: the chase offset now shrinks with speed (dolly + squat), so it
	# is read from the camera rather than hard-coded; shake is off for this
	# test (see _initialize), so the drawn position is exactly the offset.
	var back := -cam.dist_now if p.gear == -1 else cam.dist_now
	var want := Vector3(ip.x, ip.y + cam.height_now, ip.z + back)
	worst_cam_err = max(worst_cam_err, cam.global_position.distance_to(want))
	for c in game.get("chunk_pool"):
		var want_z := -float(c.index - origin) * RoadChunkBuilder.CHUNK_LEN
		if absf(c.root.position.z - want_z) > 0.0001:
			_fail("chunk %d at z=%.3f, expected %.3f" % [c.index, c.root.position.z, want_z])

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _report(p: PlayerCar) -> void:
	var recenters: int = game.get("recenter_count")
	var origin: int = game.get("origin_index")
	var driven := _road_z(p.global_position.z, origin) - float(FAR_CHUNKS) * RoadChunkBuilder.CHUNK_LEN
	print("recenters=%d origin_index=%d driven=%.0f m top_speed=%.1f m/s max|z|=%.1f" % [recenters, origin, driven, max_speed, max_abs_z])
	print("per-tick change, ordinary ticks: speed=%.3f lin=%.3f spring=%.4f" % [normal_max.speed, normal_max.lin, normal_max.spring])
	print("per-tick change, recenter ticks: speed=%.3f lin=%.3f spring=%.4f" % [shift_max.speed, shift_max.lin, shift_max.spring])
	print("worst travel-vs-velocity error=%.4f m  worst frame overshoot=%.3f m  worst camera offset error=%.4f m" % [worst_travel_err, worst_frame_step, worst_cam_err])

	if recenters < MIN_RECENTERS:
		_fail("only %d recenters -- not enough driving to test anything" % recenters)
	for k in ["speed", "lin", "spring"]:
		# A recenter tick may be no rougher than the roughest ordinary tick
		# (plus a small floor so a near-zero baseline can't fail on noise).
		if shift_max[k] > normal_max[k] * 1.5 + 0.05:
			_fail("%s jumps on recenter: %.4f vs %.4f on ordinary ticks" % [k, shift_max[k], normal_max[k]])
	if worst_travel_err > 0.05:
		_fail("distance travelled drifted from velocity by %.4f m in one tick" % worst_travel_err)
	if worst_frame_step > 0.0:
		_fail("car jumped %.2f m further than its speed allows in one rendered frame" % worst_frame_step)
	if worst_cam_err > 0.01:
		_fail("camera drifted %.4f m from its chase offset" % worst_cam_err)
	if max_abs_z > TEST_RECENTER_DIST + RoadChunkBuilder.CHUNK_LEN:
		_fail("car got %.1f m from the origin" % max_abs_z)
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
