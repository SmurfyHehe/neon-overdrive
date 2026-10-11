class_name CrossingBenchTool
extends SceneTree

# Engine-call cost per car per physics tick, from C++ (task B1, 2026-10-11).
# Measurement only. Companion to tools/traffic_profile.gd, same options.
#
# Question: if the car sim moves to C++ (GDExtension), what is the floor the
# physics-engine calls alone cost per car, before any sim maths? The C++ class
# CrossingBench (native/neon_sim) does per full-sim car per tick: check the body
# is alive, read transform + linear + angular velocity, cast 4 wheel rays, apply
# one central force and one torque. No maths.
#
# It boots the real game in benchmark mode (road, seed, bot driver, options as
# scripts/core/benchmark.gd: --traffic, --detail, --secs ...) and cycles through
# four phases of 1 s each (120 ticks), so every phase sees the same cars, road
# and machine load:
#
#   off   CrossingBench disabled          -> (a) the GDScript tick as today
#   A     direct body state + intersect_ray on the space
#   B     direct body state + the wheels' own RayCast3D nodes
#   C     body_get_state x3 + intersect_ray (state read alternative)
#
# Per phase it reports: physics scripts ms per tick (all _physics_process of
# every node, as traffic_profile's "physics scripts"), physics engine ms per tick
# (the server step), and from CrossingBench its own per-car sections in ns
# (resolve, state, rays, force, total). "floor" = CrossingBench total per car
# per tick, minus the cost of the timer reads taken inside it.
#
# Run (debug editor binary):
#   <godot> --headless --fixed-fps 60 --path . --audio-driver Dummy -s res://tools/crossing_bench.gd -- --benchmark --secs=34 --traffic=40 --detail=1000
# Release template: copy it into the project folder, put this in override.cfg
# and run it from there (tools/crossing-bench-matrix.ps1 does all of it):
#   [application]
#   run/main_loop_type="CrossingBenchTool"
# Output: one line "CBENCH_JSON {...}" on stdout, also appended to --out=<file>.

const WARMUP := 4.0       # s of game time skipped (spawn-in, shader compiles)
const PHASE_TICKS := 120  # ticks per phase (1 s at 120 Hz)
const LAST := 1000000     # process priority of the marker node: after everything
const PHASES := [
	{"name": "off", "on": false, "ray": 0, "state": 0},
	{"name": "A_direct_space", "on": true, "ray": 0, "state": 0},
	{"name": "B_direct_raycast3d", "on": true, "ray": 1, "state": 0},
	{"name": "C_getstate_space", "on": true, "ray": 0, "state": 1},
]

class Mark extends Node:
	var tool: Object
	func _physics_process(_d: float) -> void:
		tool.call("_physics_scripts_done")

var game: Node
var game_t := 0.0
var measuring := false
var done := false
var bench: Object   # CrossingBench

var _t_mark := 0
var _tick_start := 0
var _after_mark := false
var _phase_i := 0
var _phase_ticks := 0
var _last_tick_phase := -1
var _cars_now := 0
var _no_native := false

# Per phase name: sums over all cycles.
var acc := {}

func _initialize() -> void:
	for c in root.get_children():
		if c.scene_file_path == "res://Game.tscn":
			game = c
	if game == null:
		game = (load("res://Game.tscn") as PackedScene).instantiate()
		root.add_child(game)
	if not ClassDB.class_exists(&"CrossingBench"):
		_no_native = true
	else:
		bench = ClassDB.instantiate(&"CrossingBench")
		bench.name = "CrossingBench"
		root.add_child(bench)
	var m := Mark.new()
	m.tool = self
	m.name = "CrossingBenchMark"
	m.process_priority = LAST
	m.process_physics_priority = LAST
	m.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(m)
	for p in PHASES:
		acc[p.name] = {"ticks": 0, "script_us": 0, "engine_us": 0, "cars": 0, "steps": 0, "car_steps": 0,
			"total_ns": 0, "resolve_ns": 0, "state_ns": 0, "rays_ns": 0, "force_ns": 0, "rays": 0, "hits": 0, "cycles": 0}
	physics_frame.connect(_on_physics_frame)
	process_frame.connect(_on_process_frame)

func _cars() -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is TrafficCar and n.get("detailed") and n.is_physics_processing():
			out.append(n)
	return out

func _set_phase(i: int) -> void:
	_phase_i = i
	_phase_ticks = 0
	var p: Dictionary = PHASES[i]
	if bench == null:
		return
	var cars := _cars()
	var bodies: Array = []
	var wheels: Array = []
	for v in cars:
		bodies.append(v)
		wheels.append(v.front_left_wheel)
		wheels.append(v.front_right_wheel)
		wheels.append(v.rear_left_wheel)
		wheels.append(v.rear_right_wheel)
	bench.call("set_cars", bodies, wheels)
	_cars_now = int(bench.call("get_car_count"))
	bench.call("set_ray_mode", p.ray)
	bench.call("set_state_mode", p.state)
	bench.call("set_enabled", p.on)
	bench.call("reset_stats")

func _end_phase() -> void:
	var p: Dictionary = PHASES[_phase_i]
	var a: Dictionary = acc[p.name]
	a.cycles += 1
	if bench != null and p.on:
		var s: Dictionary = bench.call("get_stats")
		for k in ["steps", "car_steps", "total_ns", "resolve_ns", "state_ns", "rays_ns", "force_ns", "rays", "hits"]:
			a[k] += int(s[k])
	_set_phase((_phase_i + 1) % PHASES.size())

func _on_physics_frame() -> void:
	var now := Time.get_ticks_usec()
	if measuring and _after_mark and _last_tick_phase >= 0:
		acc[PHASES[_last_tick_phase].name].engine_us += now - _t_mark
	_after_mark = false
	_tick_start = now

func _physics_scripts_done() -> void:
	var now := Time.get_ticks_usec()
	if measuring:
		var a: Dictionary = acc[PHASES[_phase_i].name]
		a.script_us += now - _tick_start
		a.ticks += 1
		a.cars += _cars_now if PHASES[_phase_i].on else _count_cars_cached()
		_last_tick_phase = _phase_i
		_phase_ticks += 1
		if _phase_ticks >= PHASE_TICKS:
			_end_phase()
	_t_mark = now
	_after_mark = true

var _cars_cache := 0
var _cars_cache_at := -1
func _count_cars_cached() -> int:
	# The "off" phase has no bench, so count the full-sim cars once per phase.
	if _cars_cache_at != _phase_i * 1000000 + acc["off"].cycles:
		_cars_cache_at = _phase_i * 1000000 + acc["off"].cycles
		_cars_cache = _cars().size()
	return _cars_cache

func _on_process_frame() -> void:
	var now := Time.get_ticks_usec()
	if measuring and _after_mark and _last_tick_phase >= 0:
		acc[PHASES[_last_tick_phase].name].engine_us += now - _t_mark
	_after_mark = false
	game_t += root.get_process_delta_time()
	if not measuring and not done and game_t >= WARMUP:
		measuring = true
		_set_phase(0)
	if measuring and game_t >= Benchmark.run_secs():
		measuring = false
		done = true
		_finish()

func _finish() -> void:
	var clock_ns := 0.0
	if bench != null:
		clock_ns = float(bench.call("calibrate_clock", 200000))
	var phases := {}
	for p in PHASES:
		var a: Dictionary = acc[p.name]
		var t := maxi(a.ticks, 1)
		var r := {
			"cycles": a.cycles,
			"ticks": a.ticks,
			"cars_per_tick": snappedf(float(a.cars) / t, 0.1),
			"script_ms_per_tick": snappedf(a.script_us / 1000.0 / t, 0.0001),
			"engine_ms_per_tick": snappedf(a.engine_us / 1000.0 / t, 0.0001),
		}
		if p.on and a.car_steps > 0:
			var cs: float = a.car_steps
			# 5 timer reads per car inside CrossingBench's own step: the section
			# sums each hold about one read, the total holds all five.
			var floor_ns: float = a.total_ns / cs - 5.0 * clock_ns
			r["bench_cars_per_step"] = snappedf(cs / maxf(a.steps, 1), 0.1)
			r["floor_us_per_car_tick"] = snappedf(floor_ns / 1000.0, 0.001)
			r["floor_ms_per_car_tick"] = snappedf(floor_ns / 1.0e6, 0.0001)
			r["raw_total_us_per_car_tick"] = snappedf(a.total_ns / cs / 1000.0, 0.001)
			r["resolve_us"] = snappedf((a.resolve_ns / cs - clock_ns) / 1000.0, 0.001)
			r["state_us"] = snappedf((a.state_ns / cs - clock_ns) / 1000.0, 0.001)
			r["rays_us"] = snappedf((a.rays_ns / cs - clock_ns) / 1000.0, 0.001)
			r["force_us"] = snappedf((a.force_ns / cs - clock_ns) / 1000.0, 0.001)
			r["us_per_ray"] = snappedf((a.rays_ns / cs - clock_ns) / 1000.0 / 4.0, 0.001)
			r["hit_rate"] = snappedf(float(a.hits) / maxf(a.rays, 1), 0.001)
		phases[p.name] = r
	var off: Dictionary = phases["off"]
	var cars := float(off.cars_per_tick)
	var out := {
		"when": Time.get_datetime_string_from_system(false, true),
		"build": "debug" if OS.is_debug_build() else "release",
		"physics_engine": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"physics_hz": Engine.physics_ticks_per_second,
		"native_available": not _no_native,
		"cars_requested": TrafficSettings.car_count,
		"cars_full_sim": cars,
		"clock_read_ns": snappedf(clock_ns, 0.1),
		"phases": phases,
		# (c) the engine step per full-sim car per tick, bodies in the world
		# counted once: engine_ms_per_tick / cars. It also holds the player,
		# rails cars and statics, so it is an upper bound per car.
		"engine_ms_per_car_tick": snappedf(off.engine_ms_per_tick / maxf(cars, 1.0), 0.0001),
		"script_ms_per_car_tick": snappedf(off.script_ms_per_tick / maxf(cars, 1.0), 0.0001),
		"opts": " ".join(OS.get_cmdline_user_args()),
	}
	var line := JSON.stringify(out)
	print("CBENCH_JSON ", line)
	var path := Benchmark.opt("out")
	if path != "":
		var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(line)
	quit(0)
