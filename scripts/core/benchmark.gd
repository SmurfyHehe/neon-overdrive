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
# the same driving as tests/world/chunk_drive.gd, so the two produce comparable
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
const WARMUP_SECS := 2.0  # skip shader-compile hitches at startup
## Options, as user args after --benchmark, e.g.
##   -- --benchmark --secs=90 --traffic=80 --hills=1 --scale=0.75 --view=cockpit
## secs     run length (default 45)           traffic  car count (default 16)
## detail   traffic sim/draw distance (150)   curves   0..1 road bend (default 0)
## hills    0..1 road elevation (default 0)   weave    1 = keep changing lanes
## scale    3D render scale 0.25..1 (1)       msaa     0, 2, 4 or 8 (project value)
## mirrors  0/1 cockpit mirrors (project)     mirror_q 0 low, 1 medium, 2 high
## view     chase | cockpit (chase)           window   1 = driver window half down
## res      window size, e.g. 1920x1080 (default: the project window)
## gfx      low | medium | high: a graphics tier (GraphicsSettings), whose
##          traffic and draw distance become the defaults (the saved preset)
## dynres   1 = dynamic resolution on (off by default, for fixed-scale numbers)
## Defaults reproduce the old benchmark exactly, so earlier lines still compare.
## The radio always plays (it is part of the game), so every run has it on.
const DEFAULT_SECS := 45.0
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

## Value of --<key>=<value> from the user args, or `fallback` when absent.
static func opt(key: String, fallback: String = "") -> String:
	var prefix := "--%s=" % key
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return fallback

static func opt_float(key: String, fallback: float) -> float:
	var v := opt(key)
	return float(v) if v.is_valid_float() else fallback

static func run_secs() -> float:
	return opt_float("secs", DEFAULT_SECS)

func _ready() -> void:
	game = get_parent()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_apply_options()
	var hud := CanvasLayer.new()
	add_child(hud)
	var lbl := Label.new()
	lbl.position = Vector2(16, 56)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.54, 0.12))  # sodium #FF8A1F
	lbl.text = "BENCHMARK -- driving itself for %d s, then quits" % int(run_secs() + WARMUP_SECS)
	hud.add_child(lbl)

# Render and view options. Traffic, curves and hills are applied earlier, in
# game.gd, because they shape the world before this node exists.
func _apply_options() -> void:
	var vp := get_viewport()
	var res := opt("res").split("x")   # window size, e.g. 1920x1080 (the default window is small, which hides GPU cost)
	if res.size() == 2 and res[0].is_valid_int() and res[1].is_valid_int():
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = Vector2i(int(res[0]), int(res[1]))
	var sc := opt_float("scale", 1.0)
	if sc < 1.0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = clampf(sc, 0.25, 1.0)
	var m := opt("msaa")
	if m.is_valid_int():
		vp.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}.get(int(m), Viewport.MSAA_DISABLED)
	var mir := opt("mirrors")
	if mir != "":
		FxSettings.set_on("mirrors", mir == "1")
		FxSettings.set_on("rear_strip", mir == "1")
	var mq := opt("mirror_q")
	if mq.is_valid_int():
		FxSettings.set_mirror_quality(int(mq))
	_weave = opt("weave") == "1"

var _weave := false

func _setup_view() -> void:
	var cam: ChaseCamera = game.get("camera")
	if cam == null:
		return
	if opt("view") == "cockpit":
		cam.set_view(ChaseCamera.View.COCKPIT)
	if opt("window") == "1" and cam.perspective != null:
		cam.perspective.window = 0.5

func _process(delta: float) -> void:
	if not started:
		started = true
		var car: PlayerCar = game.get("player")
		car.driver = _drive
		_setup_view()
		_diagnose()
		return
	t += delta
	if t > WARMUP_SECS:
		frames.append(delta * 1000.0)
		# The monitor holds the last rendered frame's count, so sample it every
		# frame: a single read at the end only sees whatever the quit frame drew.
		draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		var vp := get_viewport().get_viewport_rid()
		var g := RenderingServer.viewport_get_measured_render_time_gpu(vp)
		gpu_ms += g if g < 1000.0 else 0.0   # the driver sometimes reports garbage on the first frames
		cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	var p: PlayerCar = game.get("player")
	max_speed = max(max_speed, p.linear_velocity.length())

	if t >= run_secs() + WARMUP_SECS:
		set_process(false)
		_report()
		get_tree().quit()

# Called by PlayerCar every physics tick. Heading hold: steer only when yaw
# (relative to the road, RoadFrame) drifts, nudged back toward the lane.
func _drive(c: PlayerCar) -> void:
	var u := RoadFrame.unroll(c.global_position)
	var lane := 1
	if _weave:
		lane = 0 if int(t / 4.0) % 2 == 0 else 1   # a lane change every 4 s
	var err: float = (c.global_rotation.y - RoadFrame.heading_at(u.z)) + clampf((TrafficManager.lane_centre(lane, false) - u.x) * 0.02, -0.05, 0.05)
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
	var spikes33 := 0
	var spikes50 := 0
	for f in s:
		if f > 33.4:
			spikes33 += 1
		if f > 50.0:
			spikes50 += 1
	var dc_sum := 0
	var dc_max := 0
	for d in draw_calls:
		dc_sum += d
		dc_max = maxi(dc_max, d)
	var dc_avg := float(dc_sum) / maxi(1, draw_calls.size())
	var size := get_viewport().get_visible_rect().size
	var line := "%s  %s %dx%d  frames=%d avg=%.2fms (%d fps) 1%%low=%.2fms (%d fps) p50=%.2f p99=%.2f max=%.2f  gpu=%.2fms render_cpu=%.2fms process=%.2fms physics=%.2fms  traffic=%d@%dm  draw_calls avg=%d max=%d  top_speed=%.1f m/s  spikes>33ms=%d >50ms=%d" % [
		Time.get_datetime_string_from_system(false, true),
		ProjectSettings.get_setting("rendering/renderer/rendering_method"), int(size.x), int(size.y),
		n, avg, int(1000.0 / avg), low1, int(1000.0 / low1), s[n / 2], p99, s[n - 1],
		gpu_ms / n, cpu_ms / n, process_ms / n, physics_ms / n, TrafficSettings.car_count, roundi(TrafficSettings.detail_distance), roundi(dc_avg), dc_max, max_speed, spikes33, spikes50]
	line += "  gfx=%s scale_end=%.2f" % [GraphicsSettings.preset, get_viewport().scaling_3d_scale]
	line += "  opts=[%s]" % " ".join(OS.get_cmdline_user_args())
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

# Diagnostics: --off=A,B turns off _process/_physics_process of every node whose
# script class or name matches (case-insensitive), --list=1 prints the nodes
# that have per-frame scripts. For finding what a frame is spent on.
func _diagnose() -> void:
	var off := opt("off").to_lower().split(",", false)
	var list := opt("list") == "1"
	var stack: Array = [game]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n == self or n.get_script() == null:
			continue
		var cls := String((n.get_script() as Script).get_global_name())
		var has_fn := n.has_method("_process") or n.has_method("_physics_process")
		if list and has_fn:
			print("NODE ", cls if cls != "" else n.name, " (", n.name, ")")
		for o in off:
			if cls.to_lower() == o or String(n.name).to_lower() == o:
				n.set_process(false)
				n.set_physics_process(false)
