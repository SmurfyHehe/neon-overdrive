extends SceneTree

# Screenshots and frame cost of the title screen (not a test; nothing is
# asserted). Boots Game.tscn onto the title with the splash and the first-launch
# card on, saves a PNG of each stage to user://title_shots/, then measures the
# frame for MEASURE_FRAMES frames with the frame cap off. Needs the real
# renderer (a window opens). Test mode keeps the real settings and saves
# untouched:
#   set NEON_TEST=1 && godot --path . -s res://tools/title_shots.gd
# NEON_CAR=p3_tuner parks another car; "-- 1280x720" sets the window size.

const MEASURE_FRAMES := 240
var out_dir := "user://title_shots"
var t := 0.0
var done := {}
var title: TitleScreen
var measuring := -1
var cpu_ms: Array[float] = []
var frame_ms: Array[float] = []
var draws: Array[float] = []
var render_cpu_ms: Array[float] = []
var render_gpu_ms: Array[float] = []
var _measure_from := 0.0
var _last_usec := 0

func _initialize() -> void:
	OS.set_environment("NEON_TITLE", "1")
	OS.set_environment("NEON_SPLASH", "1")
	OS.set_environment("NEON_WELCOME", "1")
	DirAccess.make_dir_recursive_absolute(out_dir)
	# The first-launch card shows once; make this run a first launch again
	# (test mode: this is the test settings file, not the player's).
	if TitleScreen.TestMode.active():
		var cfg := ConfigFile.new()
		cfg.load(AudioSettings.path)
		cfg.set_value("title", "welcome_seen", false)
		cfg.save(AudioSettings.path)
	for a in OS.get_cmdline_user_args():
		if "x" in a:
			var wh := a.split("x")
			root.size = Vector2i(int(wh[0]), int(wh[1]))
	change_scene_to_file("res://Game.tscn")

func _shot(name: String) -> void:
	var p := out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(p)
	print("shot: ", ProjectSettings.globalize_path(p))

func _at(name: String, secs: float) -> bool:
	if t >= secs and not done.has(name):
		done[name] = true
		return true
	return false

func _process(delta: float) -> bool:
	var game := current_scene
	if game == null or game.get("game_state") == null:
		return false
	if title == null:
		for c in game.get_children():
			if c is TitleScreen:
				title = c
		return false
	if not title.visible:
		return false
	t += delta
	if _at("splash_spool", 1.0): _shot("1_splash_spool")
	if _at("splash_flutter", 1.85): _shot("2_splash_flutter")
	if _at("welcome", 5.0): _shot("3_first_launch_card")
	if _at("close_welcome", 5.2): title._close_welcome()
	if _at("title", 7.0): _shot("4_title")
	if _at("load", 7.2): title.load_button.pressed.emit()
	if _at("load_shot", 8.0): _shot("5_title_load")
	if _at("extras", 8.2):
		title._show_list(title.main_list)
		title.extras_button.pressed.emit()
	if _at("extras_shot", 9.0): _shot("6_title_extras")
	if _at("back", 9.2):
		title._show_list(title.main_list)
		# Frame cost: cap and vsync off so the frame time is the work itself.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		TitleScreen.cap_fps = false
		Engine.max_fps = 0
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		measuring = 0
		_measure_from = t + 2.0   # the engine's own timers settle over a second or so
		_last_usec = Time.get_ticks_usec()
		return false
	if measuring >= 0:
		var now := Time.get_ticks_usec()
		if t >= _measure_from:
			measuring += 1
			frame_ms.append((now - _last_usec) / 1000.0)
			cpu_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			var vp := root.get_viewport_rid()
			render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
			render_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		_last_usec = now
		if measuring >= MEASURE_FRAMES:
			_report()
			quit()
	return false

func _report() -> void:
	frame_ms.sort()
	cpu_ms.sort()
	draws.sort()
	var n := frame_ms.size()
	print("title frame, uncapped, %d frames at %s:" % [n, root.size])
	print("  whole frame ms: median %.2f  p95 %.2f  max %.2f" % [frame_ms[n / 2], frame_ms[int(n * 0.95)], frame_ms[n - 1]])
	print("  script+engine process ms (Performance.TIME_PROCESS): median %.2f  p95 %.2f" % [cpu_ms[n / 2], cpu_ms[int(n * 0.95)]])
	render_cpu_ms.sort()
	render_gpu_ms.sort()
	print("  render CPU ms: median %.2f  p95 %.2f    render GPU ms: median %.2f  p95 %.2f" % [
		render_cpu_ms[n / 2], render_cpu_ms[int(n * 0.95)], render_gpu_ms[n / 2], render_gpu_ms[int(n * 0.95)]])
	print("  draw calls: %d   objects: %d   primitives: %d" % [int(draws[n / 2]),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	print("  at the 30 fps cap that is %.0f%% of each 33.3 ms frame" % (frame_ms[n / 2] / 33.3 * 100.0))
