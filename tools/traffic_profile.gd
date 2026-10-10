extends SceneTree

# Traffic frame-time profile (2026-10-10): where one frame goes with N traffic
# cars. Measurement only; it changes nothing in the game.
#
# It boots the real game in benchmark mode (same road, seed, bot driver and
# options as scripts/core/benchmark.gd, so `--traffic`, `--detail`, `--gfx`,
# `--res`, `--hills` ... all work) and adds three things the benchmark line
# does not have:
#
#   1. A wall-clock split of every frame, from timestamps taken at the
#      physics_frame / process_frame signals and from two marker nodes that run
#      last in each phase:
#        physics scripts   every _physics_process of every node, all ticks
#        physics engine    the physics server step (+ transform flush), all ticks
#        process scripts   every _process
#        rest              drawing: render-thread CPU, GPU wait, buffer swap
#      (Performance.TIME_PROCESS / TIME_PHYSICS_PROCESS are not used for this:
#      they are the slowest single step of the last second, not a per-frame sum.)
#   2. Per script class: each node's _physics_process / _process is called
#      directly a few extra times at the end of the run and timed, grouped by
#      class. A full-sim TrafficCar is also split into lane controller (_drive),
#      aero + drafting (AeroModel.apply) and the rest (GEVP wheel sim).
#      These extra calls disturb the cars, which is why they come last.
#   3. A census of what is drawn: draw calls, primitives and objects per frame
#      (Performance monitors, real renderer only), mesh instances, surfaces,
#      unique materials and unique shaders, split player / traffic / world.
#
# Run (windowed, real renderer: GPU ms, draw calls, shaders):
#   <godot> --path . --audio-driver Dummy -s res://tools/traffic_profile.gd -- --benchmark --secs=20 --traffic=40 --detail=1000 --gfx=medium --res=1920x1080
# Run (CPU only):
#   <godot> --headless --fixed-fps 60 --path . --audio-driver Dummy -s res://tools/traffic_profile.gd -- --benchmark --secs=20 --traffic=40 --detail=1000
# tools/traffic-profile.ps1 runs the whole 30 / 40 / 80 ladder with repeats.
#
# Output: one line "TPROF_JSON {...}" on stdout, also appended to --out=<file>.

const WARMUP := 3.0   # s of game time skipped (shader compiles, spawn-in)
const PASSES := 15    # extra timed calls per node; the median pass is reported
const LAST := 1000000 # process priority of the marker nodes: after everything

class Mark extends Node:
	var tool: Object
	func _physics_process(_d: float) -> void:
		tool.call("_physics_scripts_done")
	func _process(_d: float) -> void:
		tool.call("_process_scripts_done")

var game: Node
var game_t := 0.0
var measuring := false
var done := false

# Frame split, microseconds.
var _phase := 0            # 1 = last marker ran in a physics tick, 2 = in _process
var _t_mark := 0
var _tick_start := 0
var _proc_start := 0
var _frame_start := 0
var phys_script_us := 0
var phys_engine_us := 0
var proc_script_us := 0
var ticks := 0
var tick_script: PackedFloat32Array = []   # ms, one per physics tick
var frames: PackedFloat32Array = []        # ms, one per frame
var gpu_ms := 0.0
var render_cpu_ms := 0.0
var draw_calls := 0.0
var primitives := 0.0
var objects := 0.0
var detailed_sum := 0.0
var active_sum := 0.0
var bodies := 0.0
var pairs := 0.0
var monitor_process := 0.0
var monitor_physics := 0.0

func _initialize() -> void:
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var m := Mark.new()
	m.tool = self
	m.name = "TrafficProfileMark"
	m.process_priority = LAST
	m.process_physics_priority = LAST
	m.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(m)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	physics_frame.connect(_on_physics_frame)
	process_frame.connect(_on_process_frame)

func _on_physics_frame() -> void:
	var now := Time.get_ticks_usec()
	if measuring and _phase == 1:
		phys_engine_us += now - _t_mark
	_phase = 0
	_tick_start = now

func _physics_scripts_done() -> void:
	var now := Time.get_ticks_usec()
	if measuring:
		phys_script_us += now - _tick_start
		tick_script.append((now - _tick_start) / 1000.0)
		ticks += 1
	_t_mark = now
	_phase = 1

func _on_process_frame() -> void:
	var now := Time.get_ticks_usec()
	if measuring and _phase == 1:
		phys_engine_us += now - _t_mark
	_phase = 0
	if measuring and _frame_start > 0:
		frames.append((now - _frame_start) / 1000.0)
		_sample()
	_proc_start = now
	game_t += root.get_process_delta_time()
	if not measuring and not done and game_t >= WARMUP:
		measuring = true
		_frame_start = 0
	if measuring:
		_frame_start = now
	if measuring and game_t >= Benchmark.run_secs():
		measuring = false
		done = true
		_finish()

func _process_scripts_done() -> void:
	var now := Time.get_ticks_usec()
	if measuring and _frame_start > 0:
		proc_script_us += now - _proc_start
	_t_mark = now
	_phase = 2

func _sample() -> void:
	var vp := root.get_viewport_rid()
	var g := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	gpu_ms += g if g < 1000.0 else 0.0
	render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	bodies += Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)
	pairs += Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)
	monitor_process += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	monitor_physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var tm: TrafficManager = game.get("traffic")
	if tm != null:
		detailed_sum += tm.detailed_count()
		active_sum += tm.active_count()

func _finish() -> void:
	var n := maxi(frames.size(), 1)
	var s := Array(frames)
	s.sort()
	var sum := 0.0
	for f in s:
		sum += f
	var avg := sum / n
	var worst := maxi(1, n / 100)
	var worst_sum := 0.0
	for i in range(n - worst, n):
		worst_sum += s[i]
	var ts := Array(tick_script)
	ts.sort()
	var phys_script := phys_script_us / 1000.0 / n
	var phys_engine := phys_engine_us / 1000.0 / n
	var proc_script := proc_script_us / 1000.0 / n
	var size := root.get_visible_rect().size
	var out := {
		"when": Time.get_datetime_string_from_system(false, true),
		"renderer": DisplayServer.get_name() + "/" + str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"headless": DisplayServer.get_name() == "headless",
		"adapter": RenderingServer.get_video_adapter_name(),
		"res": "%dx%d" % [int(size.x), int(size.y)],
		"gfx": GraphicsSettings.preset,
		"scale_3d": root.scaling_3d_scale,
		"msaa": root.msaa_3d,
		"physics_hz": Engine.physics_ticks_per_second,
		"cars": TrafficSettings.car_count,
		"detail_m": roundi(TrafficSettings.detail_distance),
		"cars_full_sim_avg": snappedf(detailed_sum / n, 0.1),
		"cars_active_avg": snappedf(active_sum / n, 0.1),
		"frames": frames.size(),
		"frame_ms_avg": snappedf(avg, 0.01),
		"frame_ms_p50": snappedf(s[n / 2] if frames.size() > 0 else 0.0, 0.01),
		"frame_ms_p99": snappedf(s[int(n * 0.99)] if frames.size() > 0 else 0.0, 0.01),
		"frame_ms_1pct_low": snappedf(worst_sum / worst, 0.01),
		"fps_avg": snappedf(1000.0 / maxf(avg, 0.001), 0.1),
		"ticks_per_frame": snappedf(float(ticks) / n, 0.01),
		"physics_scripts_ms": snappedf(phys_script, 0.01),
		"physics_engine_ms": snappedf(phys_engine, 0.01),
		"process_scripts_ms": snappedf(proc_script, 0.01),
		"rest_ms": snappedf(avg - phys_script - phys_engine - proc_script, 0.01),
		"tick_scripts_ms_p10": snappedf(ts[ts.size() / 10] if ts.size() > 0 else 0.0, 0.001),
		"frame_ms_p10": snappedf(s[n / 10] if frames.size() > 0 else 0.0, 0.01),
		"tick_scripts_ms_p50": snappedf(ts[ts.size() / 2] if ts.size() > 0 else 0.0, 0.001),
		"tick_scripts_ms_p99": snappedf(ts[int(ts.size() * 0.99)] if ts.size() > 0 else 0.0, 0.001),
		"gpu_ms": snappedf(gpu_ms / n, 0.01),
		"render_cpu_ms": snappedf(render_cpu_ms / n, 0.01),
		"draw_calls": roundi(draw_calls / n),
		"primitives": roundi(primitives / n),
		"objects": roundi(objects / n),
		"physics_bodies_active": roundi(bodies / n),
		"collision_pairs": roundi(pairs / n),
		"monitor_time_process_ms": snappedf(monitor_process / n, 0.01),
		"monitor_time_physics_ms": snappedf(monitor_physics / n, 0.01),
		"opts": " ".join(OS.get_cmdline_user_args()),
	}
	out["census"] = _census()
	out["groups"] = _time_groups()
	var line := JSON.stringify(out)
	print("TPROF_JSON ", line)
	var path := Benchmark.opt("out")
	if path != "":
		var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(line)
	quit(0)

# --- what is drawn ----------------------------------------------------------

var _tri_cache := {}

func _tris(mesh: Mesh, surface: int) -> int:
	var key := [mesh.get_rid().get_id(), surface]
	if not _tri_cache.has(key):
		var arr := mesh.surface_get_arrays(surface)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		var count := 0
		if idx != null and idx.size() > 0:
			count = idx.size() / 3
		elif arr[Mesh.ARRAY_VERTEX] != null:
			count = arr[Mesh.ARRAY_VERTEX].size() / 3
		_tri_cache[key] = count
	return _tri_cache[key]

func _census() -> Dictionary:
	var parts := {}
	var all_mats := {}
	var all_shaders := {}
	var per_kind := {}
	var stack: Array = [[root, "world", ""]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var tag: String = item[1]
		var kind: String = item[2]
		if n is TrafficCar:
			tag = "traffic"
			kind = String(n.get("kind"))
			if not per_kind.has(kind):
				per_kind[kind] = {"cars": 0, "nodes": 0, "mesh_instances": 0, "surfaces": 0, "tris": 0, "mats": {}}
			per_kind[kind].cars += 1
		elif n is PlayerCar:
			tag = "player"
		for c in n.get_children():
			stack.append([c, tag, kind])
		if kind != "":
			per_kind[kind].nodes += 1
		var mesh: Mesh = null
		var copies := 1
		var override: Material = null
		if n is MeshInstance3D:
			mesh = n.mesh
			override = n.material_override
		elif n is MultiMeshInstance3D and n.multimesh != null:
			mesh = n.multimesh.mesh
			copies = n.multimesh.visible_instance_count if n.multimesh.visible_instance_count >= 0 else n.multimesh.instance_count
			override = n.material_override
		if mesh == null:
			continue
		if not parts.has(tag):
			parts[tag] = {"mesh_instances": 0, "visible": 0, "surfaces": 0, "tris": 0, "mats": {}, "shaders": {}}
		var p: Dictionary = parts[tag]
		var shown: bool = (n as Node3D).is_visible_in_tree()
		p.mesh_instances += 1
		if shown:
			p.visible += 1
		if kind != "":
			per_kind[kind].mesh_instances += 1
		for si in mesh.get_surface_count():
			var mat: Material = override
			if mat == null and n is MeshInstance3D:
				mat = n.get_active_material(si)
			if mat == null:
				mat = mesh.surface_get_material(si)
			var t := _tris(mesh, si) * copies
			p.surfaces += 1
			if shown:
				p.tris += t
			if kind != "":
				per_kind[kind].surfaces += 1
				per_kind[kind].tris += t
			if mat == null:
				continue
			var mid := mat.get_rid().get_id()
			var sid := _shader_key(mat)
			p.mats[mid] = true
			p.shaders[sid] = true
			all_mats[mid] = true
			all_shaders[sid] = true
			if kind != "":
				per_kind[kind].mats[mid] = true
	var res := {"unique_materials": all_mats.size(), "unique_shaders": all_shaders.size(), "parts": {}, "per_car_kind": {}}
	for tag in parts:
		var p: Dictionary = parts[tag]
		res.parts[tag] = {"mesh_instances": p.mesh_instances, "visible": p.visible, "surfaces": p.surfaces,
			"visible_tris": p.tris, "unique_materials": p.mats.size(), "unique_shaders": p.shaders.size()}
	for kind in per_kind:
		var k: Dictionary = per_kind[kind]
		var c: int = maxi(k.cars, 1)
		res.per_car_kind[kind] = {"cars": k.cars, "nodes_per_car": k.nodes / c, "mesh_instances_per_car": k.mesh_instances / c,
			"surfaces_per_car": k.surfaces / c, "tris_per_car": k.tris / c, "unique_materials_all_cars": k.mats.size()}
	return res

# Which shader a material compiles to. A ShaderMaterial names its shader. A
# StandardMaterial3D does not expose the one Godot generates for it, so this is
# an estimate: Godot builds that shader from the material's switches (every
# bool and enum property), not from its colours, numbers or textures, so two
# materials with the same switches share one shader.
func _shader_key(mat: Material) -> String:
	if mat is ShaderMaterial:
		return "shader:%d" % (mat.shader.get_rid().get_id() if mat.shader != null else 0)
	var key := mat.get_class()
	for prop in mat.get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if prop.type == TYPE_BOOL or (prop.type == TYPE_INT and prop.hint == PROPERTY_HINT_ENUM):
			key += "|%s" % mat.get(prop.name)
	return key

# --- per script class -------------------------------------------------------

func _group_of(n: Node) -> String:
	var sc := n.get_script() as Script
	var g := String(sc.get_global_name())
	if g == "":
		g = sc.resource_path.get_file()
	if n is TrafficCar:
		g += ":full" if n.get("detailed") else ":frozen"
	return g

func _time_groups() -> Dictionary:
	var phys: Array[Node] = []
	var proc: Array[Node] = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n.get_script() == null or n is Mark or n is Benchmark:
			continue
		if n.has_method("_physics_process") and n.is_physics_processing():
			phys.append(n)
		if n.has_method("_process") and n.is_processing():
			proc.append(n)
	var dt_p := 1.0 / Engine.physics_ticks_per_second
	var dt_f := 1.0 / 60.0
	var counts := {}
	var runs := {}   # key -> Array of per-pass totals (us)
	for pass_i in PASSES:
		var tot := {}
		for n in phys:
			if not is_instance_valid(n):
				continue
			var key := "physics " + _group_of(n)
			var t0 := Time.get_ticks_usec()
			n.call("_physics_process", dt_p)
			tot[key] = tot.get(key, 0) + Time.get_ticks_usec() - t0
			if pass_i == 0:
				counts[key] = counts.get(key, 0) + 1
			if n is TrafficCar and n.get("detailed"):
				# The same car again, piece by piece.
				t0 = Time.get_ticks_usec()
				n.call("_drive", dt_p)
				var t1 := Time.get_ticks_usec()
				AeroModel.apply(n)
				var t2 := Time.get_ticks_usec()
				tot["physics TrafficCar:full > lane controller (_drive)"] = tot.get("physics TrafficCar:full > lane controller (_drive)", 0) + t1 - t0
				tot["physics TrafficCar:full > aero + drafting (AeroModel.apply)"] = tot.get("physics TrafficCar:full > aero + drafting (AeroModel.apply)", 0) + t2 - t1
		for n in proc:
			if not is_instance_valid(n):
				continue
			var key := "process " + _group_of(n)
			var t0 := Time.get_ticks_usec()
			n.call("_process", dt_f)
			tot[key] = tot.get(key, 0) + Time.get_ticks_usec() - t0
			if pass_i == 0:
				counts[key] = counts.get(key, 0) + 1
		for key in tot:
			if not runs.has(key):
				runs[key] = []
			runs[key].append(tot[key])
	var res := {}
	for key in runs:
		var a: Array = runs[key]
		a.sort()
		var us: float = a[a.size() / 2]
		var c: int = counts.get(key, counts.get("physics TrafficCar:full", 1))
		# us_per_call: one call of one node. ms_per_step: all nodes of the group,
		# once (one physics tick for "physics", one frame for "process").
		# us_per_call_best: the fastest pass, the nearest thing to an undisturbed
		# reading when other programs are taking CPU time.
		res[key] = {"nodes": c, "us_per_call": snappedf(us / maxi(c, 1), 0.1), "us_per_call_best": snappedf(float(a[0]) / maxi(c, 1), 0.1), "ms_per_step": snappedf(us / 1000.0, 0.001)}
	return res
