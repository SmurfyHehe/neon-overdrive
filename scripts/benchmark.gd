extends Node
class_name Benchmark

# Benchmark mode (ISSUES B7, GitHub #19): a timed, hands-off drive that
# measures frame time in any build, exported ones included.
#
# Only exists when the game is launched with the user arg --benchmark:
#   NeonOverdrive.exe -- --benchmark     (or double-click benchmark.bat)
# game.gd checks for the flag and adds this node; normal play never sees it
# and keeps V-Sync on, so how the game feels is unchanged.
#
# While it runs: V-Sync off and no FPS cap, so frame times are real instead
# of a flat 16.67 ms. A bot holds full throttle and steers to hold heading --
# the same driving as tests/chunk_drive.gd, so the two produce comparable
# numbers. It drives through PlayerCar.driver, not key events: a windowed run
# drops held keys the moment the window loses focus, which left the car parked
# (top_speed 0.8 m/s, 2026-10-08) and the numbers meaningless. The car shifts
# itself (automatic is the launch default). Physics stays on the project tick
# rate (120 Hz).
#
# The report also splits each frame into CPU and GPU render time (the
# viewport's measured render time), so a slow result says which side to fix.
#
# When done it appends one result line to benchmark-results.txt (next to the
# exe in an exported build, in user:// otherwise), prints it, and quits.
# Numbers are machine-dependent: compare runs on the same machine.

const FLAG := "--benchmark"
const RUN_SECS := 45.0
const WARMUP_SECS := 2.0  # skip shader-compile hitches at startup
const SEED := 777  # same road every run, so runs are comparable

var game: Node
var t := 0.0
var started := false
var frames: PackedFloat32Array = []
var draw_calls: PackedInt32Array = []  # one sample per measured frame
var gpu_ms := 0.0  # summed viewport render time, GPU side
var cpu_ms := 0.0  # summed viewport render time, CPU side (render thread)
var process_ms := 0.0  # summed main-thread _process time (scripts)
var physics_ms := 0.0  # summed physics step time (all ticks in the frame)
var max_speed := 0.0

static func requested() -> bool:
	return FLAG in OS.get_cmdline_user_args()

func _ready() -> void:
	game = get_parent()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var hud := CanvasLayer.new()
	add_child(hud)
	var lbl := Label.new()
	lbl.position = Vector2(16, 56)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.54, 0.12))  # sodium #FF8A1F
	lbl.text = "BENCHMARK -- driving itself for %d s, then quits" % int(RUN_SECS + WARMUP_SECS)
	hud.add_child(lbl)

func _process(delta: float) -> void:
	if not started:
		started = true
		var car: PlayerCar = game.get("player")
		car.driver = _drive
		return
	t += delta
	if t > WARMUP_SECS:
		frames.append(delta * 1000.0)
		# The monitor holds the last rendered frame's count, so sample it every
		# frame: a single read at the end only sees whatever the quit frame drew.
		draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		var vp := get_viewport().get_viewport_rid()
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	var p: PlayerCar = game.get("player")
	max_speed = max(max_speed, p.linear_velocity.length())

	if t >= RUN_SECS + WARMUP_SECS:
		set_process(false)
		_report()
		get_tree().quit()

# Called by PlayerCar every physics tick. Heading hold: steer only when yaw
# (relative to the road, RoadFrame) drifts, nudged back toward the lane.
func _drive(c: PlayerCar) -> void:
	var u := RoadFrame.unroll(c.global_position)
	var err: float = (c.global_rotation.y - RoadFrame.heading_at(u.z)) + clampf((TrafficManager.lane_centre(1, false) - u.x) * 0.02, -0.05, 0.05)
	var steer := 0.0
	if err < -0.02:
		steer = -1.0  # left (A)
	elif err > 0.02:
		steer = 1.0   # right (D)
	c.throttle_input = 1.0
	c.brake_input = 0.0
	c.handbrake_input = 0.0
	c.steering_input = -steer  # same sign flip as PlayerCar._read_keyboard

func _report() -> void:
	var s: Array = Array(frames)
	s.sort()
	var n := s.size()
	var sum := 0.0
	for f in s:
		sum += f
	var avg := sum / n
	var p99: float = s[int(n * 0.99)]
	# 1% low: the average of the slowest 1% of frames (the usual definition),
	# not just the 99th-percentile frame, so a few big hitches pull it down.
	var worst := maxi(1, n / 100)
	var worst_sum := 0.0
	for i in range(n - worst, n):
		worst_sum += s[i]
	var low1: float = worst_sum / worst
	var dc_sum := 0
	var dc_max := 0
	for d in draw_calls:
		dc_sum += d
		dc_max = maxi(dc_max, d)
	var dc_avg := float(dc_sum) / maxi(1, draw_calls.size())
	var size := get_viewport().get_visible_rect().size
	var line := "%s  %s %dx%d  frames=%d avg=%.2fms (%d fps) 1%%low=%.2fms (%d fps) p50=%.2f p99=%.2f max=%.2f  gpu=%.2fms render_cpu=%.2fms process=%.2fms physics=%.2fms  traffic=%d@%dm  draw_calls avg=%d max=%d  top_speed=%.1f m/s" % [
		Time.get_datetime_string_from_system(false, true),
		ProjectSettings.get_setting("rendering/renderer/rendering_method"), int(size.x), int(size.y),
		n, avg, int(1000.0 / avg), low1, int(1000.0 / low1), s[n / 2], p99, s[n - 1],
		gpu_ms / n, cpu_ms / n, process_ms / n, physics_ms / n, TrafficSettings.car_count, roundi(TrafficSettings.detail_distance), roundi(dc_avg), dc_max, max_speed]
	print("BENCHMARK ", line)
	# Next to the exe in an exported build, where Roy can find it; user:// when
	# run from the editor, whose "exe" is Godot itself.
	var path := "user://benchmark-results.txt"
	if OS.has_feature("template"):
		path = OS.get_executable_path().get_base_dir().path_join("benchmark-results.txt")
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		push_error("benchmark: could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	f.seek_end()
	f.store_line(line)
	print("BENCHMARK results appended to ", ProjectSettings.globalize_path(path))
