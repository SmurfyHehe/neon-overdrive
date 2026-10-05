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
# of a flat 16.67 ms. A bot holds W, shifts up with E as speed builds, and
# taps A/D to hold heading -- the same driving as tests/chunk_drive.gd, so the
# two produce comparable numbers. Physics stays on the project tick rate (120 Hz).
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
var max_speed := 0.0

static func requested() -> bool:
	return FLAG in OS.get_cmdline_user_args()

func _ready() -> void:
	game = get_parent()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var hud := CanvasLayer.new()
	add_child(hud)
	var lbl := Label.new()
	lbl.position = Vector2(16, 56)
	lbl.add_theme_color_override("font_color", Color(1, 0.3, 0.8))
	lbl.text = "BENCHMARK -- driving itself for %d s, then quits" % int(RUN_SECS + WARMUP_SECS)
	hud.add_child(lbl)

func _press(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _process(delta: float) -> void:
	if not started:
		started = true
		_press(KEY_W, true)
		return
	t += delta
	if t > WARMUP_SECS:
		frames.append(delta * 1000.0)
		# The monitor holds the last rendered frame's count, so sample it every
		# frame: a single read at the end only sees whatever the quit frame drew.
		draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))

	var p: PlayerCar = game.get("player")
	var speed := p.linear_velocity.length()
	max_speed = max(max_speed, speed)
	# Heading hold: steer only when yaw drifts, nudged back toward x=0.
	var err: float = p.global_rotation.y + clampf(-p.global_position.x * 0.02, -0.05, 0.05)
	_press(KEY_A, err < -0.02)
	_press(KEY_D, err > 0.02)
	if p.gear >= 1 and p.gear < 6 and speed > 9.0 * p.gear and not p.is_shifting:
		_press(KEY_E, true)
		_press(KEY_E, false)

	if t >= RUN_SECS + WARMUP_SECS:
		set_process(false)
		_report()
		get_tree().quit()

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
	var line := "%s  %s  frames=%d avg=%.2fms (%d fps) 1%%low=%.2fms (%d fps) p50=%.2f p99=%.2f max=%.2f  draw_calls avg=%d max=%d  top_speed=%.1f m/s" % [
		Time.get_datetime_string_from_system(false, true),
		ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		n, avg, int(1000.0 / avg), low1, int(1000.0 / low1), s[n / 2], p99, s[n - 1],
		roundi(dc_avg), dc_max, max_speed]
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
