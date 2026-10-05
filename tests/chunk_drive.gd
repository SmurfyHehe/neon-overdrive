extends SceneTree

# Drive test: runs the real Game.tscn with the throttle held and checks the
# chunk pool survives sustained recycling.
#
# A bot holds W, shifts up with E as speed builds (the gearbox is manual), and
# taps A/D to hold heading so the car stays on the road instead of wandering
# into buildings. V-Sync is switched off so the frame times mean something
# (with V-Sync on everything reads a flat 16.67 ms -- ISSUES B7).
#
# Asserts (exit code 1 on failure):
# - chunks actually recycled (the car got far enough to exercise the path)
# - every pooled chunk keeps the same child count throughout
# - no orphan nodes at the end
# Reports, does not assert: frame-time avg/p50/p99/p99.9/max, top speed,
# draw calls. Those are machine-dependent; compare runs on the same machine.
#
# Run (real renderer; a window opens for RUN_SECS):
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/chunk_drive.gd
# Optional: set QA_SHOT=<path.png> to save a screenshot 20 s in.

const RUN_SECS := 45.0
const WARMUP_SECS := 2.0  # skip shader-compile hitches at startup
const SHIFT_HOLD_TICKS := 3

var game: Node
var t := 0.0
var started := false
var frames: PackedFloat32Array = []
var last_index := {}
var child_counts := {}
var recycles := 0
var max_speed := 0.0
var fails := 0
var shot_taken := false
var tick := 0
var shift_release_tick := 0
var steer_left := false
var steer_right := false

func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	seed(777)
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _press(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

# Render frames: timing only. The bot must NOT live here -- Game polls input in
# _physics_process (#30), so a key pressed and released inside one render frame
# is invisible to it, and the number of render frames per physics tick depends
# on the machine. That made shifts and steering (and so top speed and distance
# driven) vary run to run.
func _process(delta: float) -> bool:
	if not started:
		started = true
		return false
	t += delta
	if t > WARMUP_SECS:
		frames.append(delta * 1000.0)

	var p: PlayerCar = game.get("player")
	for c in game.get("chunk_pool"):
		var id: int = c.root.get_instance_id()
		if last_index.has(id) and last_index[id] != c.index:
			recycles += 1
		last_index[id] = c.index
		var n: int = c.root.get_child_count()
		if not child_counts.has(id):
			child_counts[id] = n
		elif child_counts[id] != n:
			_fail("chunk %d child count changed %d -> %d" % [c.index, child_counts[id], n])
			child_counts[id] = n

	if t > 20.0 and not shot_taken and OS.get_environment("QA_SHOT") != "":
		shot_taken = true
		root.get_viewport().get_texture().get_image().save_png(OS.get_environment("QA_SHOT"))

	if t >= RUN_SECS:
		_report(p)
		quit(0 if fails == 0 else 1)
		return true
	return false

# Physics ticks (fixed 60 Hz): the bot, now a driver callable on the player car
# (no key events). A windowed run loses held keys the moment the window loses
# focus, which made this test's distance driven vary wildly (3 to 46 recycles);
# a driver does not depend on focus. The game shifts itself (automatic default).
func _physics_process(_delta: float) -> bool:
	if not started or game == null:
		return false
	tick += 1
	var p: PlayerCar = game.get("player")
	if not p.driver.is_valid():
		p.driver = _drive
	max_speed = max(max_speed, p.linear_velocity.length())
	return false

func _drive(c: PlayerCar) -> void:
	# Heading hold: steer only when yaw drifts, nudged back toward x=0.
	var err: float = c.global_rotation.y + clampf(-c.global_position.x * 0.02, -0.05, 0.05)
	var steer := 0.0
	if err < -0.02:
		steer = -1.0  # left (A)
	elif err > 0.02:
		steer = 1.0   # right (D)
	c.throttle_input = 1.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = -steer  # same sign flip as PlayerCar._read_keyboard

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _report(p: PlayerCar) -> void:
	var s: Array = Array(frames)
	s.sort()
	var n := s.size()
	var sum := 0.0
	for f in s:
		sum += f
	print("frames=%d avg=%.2fms p50=%.2f p99=%.2f p99.9=%.2f max=%.2f" % [n, sum / n, s[n / 2], s[int(n * 0.99)], s[int(n * 0.999)], s[n - 1]])
	print("recycles=%d top_speed=%.1f m/s gear=%d final_pos=%s" % [recycles, max_speed, p.gear, p.global_position])
	print("draw_calls=%d objects=%d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	if recycles == 0:
		_fail("no chunk recycled -- the car never got far enough to test anything")
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	if orphans != 0:
		_fail("%d orphan nodes" % orphans)
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
