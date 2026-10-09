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
# Spike attribution (spike_log.gd): per measured frame, the engine's own
# process / physics split, how many physics ticks it ran, and what the game's
# hot spots logged. The report prints the slowest frames with all of it.
const TOP_FRAMES := 12
var proc_ms: PackedFloat32Array = []
var phys_ms: PackedFloat32Array = []
var ticks: PackedInt32Array = []
var events: Array = []  # per measured frame: Array of [tag, ms]
var _last_tick := 0

static func requested() -> bool:
	return FLAG in OS.get_cmdline_user_args()

func _ready() -> void:
	game = get_parent()
	SpikeLog.enabled = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var hud := CanvasLayer.new()
	add_child(hud)
	var lbl := Label.new()
	lbl.position = Vector2(16, 56)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.54, 0.12))  # sodium #FF8A1F
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
	var ev := SpikeLog.take()
	var tick := Engine.get_physics_frames()
	if t > WARMUP_SECS:
		frames.append(delta * 1000.0)
		proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		ticks.append(tick - _last_tick)
		events.append(ev)
	_last_tick = tick
		# The monitor holds the last rendered frame's count, so sample it every
		# frame: a single read at the end only sees whatever the quit frame drew.
		draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))

	var p: PlayerCar = game.get("player")
	var speed := p.linear_velocity.length()
	max_speed = max(max_speed, speed)
	# Heading hold: steer only when yaw (relative to the road, RoadFrame)
	# drifts, nudged back toward the lane.
	var u := RoadFrame.unroll(p.global_position)
	var err: float = (p.global_rotation.y - RoadFrame.heading_at(u.z)) + clampf((TrafficManager.lane_centre(1, false) - u.x) * 0.02, -0.05, 0.05)
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
	_report_spikes()
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

## The slowest frames, each with the engine's process/physics time, the
## physics ticks it ran and what the hot spots logged (SpikeLog), then a
## per-tag total so a cost spread over many frames shows up too.
func _report_spikes() -> void:
	var order := []
	for i in frames.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return frames[a] > frames[b])
	print("BENCHMARK slowest %d frames (of %d):" % [TOP_FRAMES, frames.size()])
	for r in mini(TOP_FRAMES, order.size()):
		var i: int = order[r]
		var parts := PackedStringArray()
		for e in events[i]:
			parts.append("%s %.2f" % [e[0], e[1]])
		print("  #%d frame=%.2fms process=%.2f physics=%.2f ticks=%d  %s" % [
			i, frames[i], proc_ms[i], phys_ms[i], ticks[i], " ".join(parts)])
	var totals := {}
	var counts := {}
	var worst := {}
	for ev in events:
		for e in ev:
			totals[e[0]] = float(totals.get(e[0], 0.0)) + float(e[1])
			counts[e[0]] = int(counts.get(e[0], 0)) + 1
			worst[e[0]] = maxf(float(worst.get(e[0], 0.0)), float(e[1]))
	var tags := totals.keys()
	tags.sort()
	for tag in tags:
		print("  %-18s n=%-5d total=%.1fms avg=%.3fms max=%.2fms" % [tag, counts[tag], totals[tag], totals[tag] / counts[tag], worst[tag]])
