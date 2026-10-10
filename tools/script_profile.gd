extends SceneTree

# Per-function GDScript profile (2026-10-10), measurement only: which script
# functions the CPU time goes to, by self time (time in the function's own
# lines, not in the functions it calls).
#
# It boots the real game in benchmark mode (same options as
# scripts/core/benchmark.gd: --traffic, --detail, --secs ...), skips a warm-up,
# then switches on Godot's own script profiler (the one behind the editor's
# Debugger > Profiler tab) for the rest of the run. When it is switched off the
# engine prints every function's total time, self time and call count;
# tools/script-profile.ps1 runs this and turns that into a ranked table.
#
# The engine's local debugger must be on (-d), or there is no profiler:
#   <godot> -d --headless --fixed-fps 60 --path . --audio-driver Dummy -s res://tools/script_profile.gd -- --benchmark --secs=63 --traffic=80 --detail=300
# Profiling slows every script call, so read the shares, not the milliseconds.

const WARMUP := 3.0

var game_t := 0.0
var measuring := false
var done := false
var frames := 0
var ticks := 0
var t_start := 0

func _initialize() -> void:
	var game: Node = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	process_frame.connect(_on_process_frame)
	physics_frame.connect(func() -> void:
		if measuring:
			ticks += 1)

func _on_process_frame() -> void:
	game_t += root.get_process_delta_time()
	if measuring:
		frames += 1
	if not measuring and not done and game_t >= WARMUP:
		if not EngineDebugger.is_active():
			printerr("SPROF no debugger: run with -d")
			quit(2)
			return
		measuring = true
		t_start = Time.get_ticks_usec()
		print("SPROF_BEGIN")
		EngineDebugger.profiler_enable(&"scripts", true)
	elif measuring and game_t >= Benchmark.run_secs():
		measuring = false
		done = true
		var wall := (Time.get_ticks_usec() - t_start) / 1000000.0
		EngineDebugger.profiler_enable(&"scripts", false)
		print("SPROF_END ", JSON.stringify({"game_secs": snappedf(game_t - WARMUP, 0.01), "wall_secs": snappedf(wall, 0.01),
			"frames": frames, "ticks": ticks, "physics_hz": Engine.physics_ticks_per_second,
			"cars": TrafficSettings.car_count, "detail_m": roundi(TrafficSettings.detail_distance),
			"renderer": DisplayServer.get_name() + "/" + str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
			"opts": " ".join(OS.get_cmdline_user_args())}))
		quit(0)
