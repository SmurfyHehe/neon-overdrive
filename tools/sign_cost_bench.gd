extends SceneTree

# What the area signs, street blades and painted road words cost (world step
# 4, PR #381), measured. Three modes, picked with SIGN_BENCH_MODE:
#
#   drive  (default) boots Game.tscn at night, no traffic, straight flat road,
#          and a bot drives the own lane from road metre 0 to END_S in the
#          normal chase view. That stretch has the advance sign (352 m), SLOW
#          and lane arrows (525 / 568 m), the crossing with its street blades
#          and STOP paint (600 m), the area gantry (792 m) and the speed
#          number (876 m). Every frame it reads the renderer's draw calls,
#          objects and primitives, the process and physics time, and the
#          viewport's measured render time. Run it with --fixed-fps 60: then
#          the drive is the same frame for frame whatever the machine is
#          doing, so the counts of two runs compare exactly.
#          With --headless the counts are 0 and only the CPU times mean
#          anything.
#   build  no game: builds one pooled chunk per NEON-SIGNS variant in
#          SIGN_BENCH_VARIANTS (";"-separated flag lists) and rebuilds each as
#          chunks 0..63 over and over, the variants interleaved in both
#          orders, timing every rebuild. Also times the lettering atlas.
#   shots  boots the game and saves a PNG from fixed driver's-eye spots along
#          the same stretch, to compare a variant by eye.
#
# Which signs are built comes from NEON_SIGNS (road_signs.gd): off, asis, or
# a list of the cheaper options.
#
# Env: SIGN_BENCH_OUT (file a result line is appended to), SIGN_BENCH_DIR
# (shots folder), SIGN_BENCH_LABEL (free text copied into the result).
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy --fixed-fps 60 -s res://tools/sign_cost_bench.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RoadSigns := preload("res://scripts/world/road_signs.gd")
const WordAtlas := preload("res://scripts/world/word_atlas.gd")
const B := preload("res://scripts/world/road_chunk_builder.gd")

const END_S := 1000.0
const SPEED := 40.0      # m/s the bot holds
const WARMUP := 180      # frames before sampling: shader compiles, the launch
const MAX_FRAMES := 4000
const LANE_X := B.MEDIAN_GAP + 1.5 * B.LANE_W

## [name, camera road metre, camera x, camera y, look-at road metre, x, y]
const SHOTS := [
	["advance_60m", 292.0, LANE_X, 1.4, 352.0, 8.0, 4.0],
	["advance_22m", 330.0, LANE_X, 1.4, 352.0, 8.0, 4.2],
	["paint_slow_165m_chase_height", 360.0, LANE_X, 3.0, 525.0, LANE_X, 0.0],
	["crossing_150m", 450.0, LANE_X, 1.4, 600.0, 4.0, 4.0],
	["paint_slow", 507.0, LANE_X, 1.4, 527.0, LANE_X, 0.0],
	["paint_arrows_crossing", 548.0, LANE_X, 1.4, 600.0, LANE_X, 2.5],
	["street_blades", 578.0, LANE_X, 1.4, 600.0, 7.0, 5.5],
	["gantry_70m", 722.0, LANE_X, 1.4, 792.0, 6.0, 5.5],
	["gantry_28m", 764.0, LANE_X, 1.4, 792.0, 6.0, 5.8],
	["gantry_chase_height", 742.0, LANE_X, 3.2, 792.0, 5.0, 4.5],
	["paint_speed_number", 856.0, LANE_X, 1.4, 876.0, LANE_X, 0.0],
]

var mode := "drive"
var game: Node
var frame := 0
var started := false
var last_usec := 0
var rebuild_this_frame := false
var rebuilds := 0
var s := {}   # name -> PackedFloat32Array of per-frame samples
var rebuild_proc := PackedFloat32Array()
var cam: Camera3D
var shot_i := 0
var wait_until := 0
var hud_hidden := false

func _initialize() -> void:
	mode = OS.get_environment("SIGN_BENCH_MODE")
	if mode == "":
		mode = "drive"
	if mode == "build":
		_build_bench()
		quit(0)
		return
	OS.set_environment("NEON_TEST", "1")   # never Roy's real save
	OS.set_environment("NEON_COCKPIT", "0")
	OS.set_environment("NEON_CITY_LIGHTS", "1")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	OS.set_environment("NEON_SEED", "7")
	OS.set_environment("NEON_ROAD_SEED", "7")
	OS.set_environment("NEON_MUTE", "1")
	if OS.get_environment("NEON_CLOCK") == "":
		OS.set_environment("NEON_CLOCK", "23:30")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	game = Harness.boot(self, 0, 300.0, 7)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for k in ["draw", "objects", "prims", "process", "process_plain", "physics", "monitor_process", "monitor_physics", "render_cpu", "setup_cpu", "gpu", "wall"]:
		s[k] = PackedFloat32Array()
	if mode == "shots":
		cam = Camera3D.new()
		cam.fov = 60.0
		cam.far = 1500.0
		# moved by hand between frames: must not be drawn interpolated
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		root.add_child(cam)
		DirAccess.make_dir_recursive_absolute(OS.get_environment("SIGN_BENCH_DIR"))

func _process(_delta: float) -> bool:
	if mode == "build":
		return true
	frame += 1
	if mode == "shots":
		return _shots()
	var player: PlayerCar = game.get("player")
	if not started:
		started = true
		player.driver = Harness.lane_driver(LANE_X, 1.0, SPEED)
		game.set("chunk_event_hook", func(_root: Node3D, _gap: int) -> void: rebuild_this_frame = true)
		last_usec = Time.get_ticks_usec()
		_brackets()
		return false
	var now := Time.get_ticks_usec()
	var at := _road_s(player)
	if frame > WARMUP:
		# The renderer's counters and timers hold the frame before this one;
		# so does proc_ms. The physics ticks are this frame's.
		s.draw.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		s.objects.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)))
		s.prims.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)))
		s.process.append(proc_ms)
		s.physics.append(phys_ms)
		s.monitor_process.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		s.monitor_physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		s.render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		s.setup_cpu.append(RenderingServer.get_frame_setup_time_cpu())
		var g := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		s.gpu.append(g if g < 1000.0 else 0.0)
		s.wall.append(float(now - last_usec) / 1000.0)
		if rebuilt:
			rebuild_proc.append(proc_ms)
		else:
			s.process_plain.append(proc_ms)
	last_usec = now
	phys_ms = 0.0
	if rebuilt:
		rebuilds += 1
	rebuilt = false
	if at >= END_S or frame >= MAX_FRAMES:
		_report(at)
		quit(0)
		return true
	return false

# Script time, measured here because the Performance monitors only change
# once a second (and then hold that second's worst frame): one node that
# processes before everything and one after everything, in both the frame
# step and the physics step.
class Bracket extends Node:
	var cb: Callable
	func _process(_d: float) -> void:
		cb.call(false)
	func _physics_process(_d: float) -> void:
		cb.call(true)

var proc_ms := 0.0
var phys_ms := 0.0
var rebuilt := false
var _t_proc := 0
var _t_phys := 0

func _brackets() -> void:
	var first := Bracket.new()
	first.process_priority = -1000000
	first.process_physics_priority = -1000000
	first.cb = func(physics: bool) -> void:
		if physics:
			_t_phys = Time.get_ticks_usec()
		else:
			_t_proc = Time.get_ticks_usec()
	var last := Bracket.new()
	last.process_priority = 1000000
	last.process_physics_priority = 1000000
	last.cb = func(physics: bool) -> void:
		if physics:
			phys_ms += float(Time.get_ticks_usec() - _t_phys) / 1000.0
		else:
			proc_ms = float(Time.get_ticks_usec() - _t_proc) / 1000.0
			rebuilt = rebuild_this_frame
			rebuild_this_frame = false
	root.add_child(first)
	root.add_child(last)

func _road_s(player: PlayerCar) -> float:
	return float(RoadFrame.origin_index) * B.CHUNK_LEN - RoadFrame.unroll(player.global_position).z

static func _stats(a: PackedFloat32Array) -> Dictionary:
	if a.is_empty():
		return {"n": 0}
	var v := Array(a)
	v.sort()
	var sum := 0.0
	for x in v:
		sum += x
	var n := v.size()
	return {"n": n, "mean": sum / n, "p50": v[n / 2], "p90": v[int(n * 0.9)], "max": v[n - 1], "sum": sum}

func _report(at: float) -> void:
	var out := {
		"label": OS.get_environment("SIGN_BENCH_LABEL"),
		"signs": OS.get_environment("NEON_SIGNS"),
		"headless": DisplayServer.get_name() == "headless",
		"frames": frame, "end_s": snappedf(at, 0.01), "rebuilds": rebuilds,
		"rebuild_process": _stats(rebuild_proc),
	}
	for k in s:
		out[k] = _stats(s[k])
	_emit(out)

func _emit(out: Dictionary) -> void:
	var line := JSON.stringify(out)
	print("SIGNBENCH ", line)
	var path := OS.get_environment("SIGN_BENCH_OUT")
	if path != "":
		var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
		f.seek_end()
		f.store_line(line)

# ---------- chunk build ----------

func _build_bench() -> void:
	var variants := OS.get_environment("SIGN_BENCH_VARIANTS").split(";", false)
	if variants.is_empty():
		variants = PackedStringArray(["off", "asis"])
	var reps := 12
	if OS.get_environment("SIGN_BENCH_REPS").is_valid_int():
		reps = int(OS.get_environment("SIGN_BENCH_REPS"))
	var out := {"label": OS.get_environment("SIGN_BENCH_LABEL"), "mode": "build", "reps": reps}
	# the lettering: the font first, on its own, then the atlas
	var t0 := Time.get_ticks_usec()
	UiTheme.font("road")
	var t1 := Time.get_ticks_usec()
	WordAtlas.texture()
	var t2 := Time.get_ticks_usec()
	out["font_ms"] = float(t1 - t0) / 1000.0
	out["atlas_ms"] = float(t2 - t1) / 1000.0
	out["atlas_layers"] = WordAtlas.layer_count()

	RoadFrame.align = null
	RoadFrame.origin_index = 0
	Junction.enabled = true   # so the crossing's SLOW and arrows are painted
	var cfg := {"own_lanes": 2, "onc_lanes": 2, "barrier": false}
	var roots := []
	for v in variants:
		RoadSigns.set_flags(v)
		var r := B.build_chunk(0, cfg, cfg)
		root.add_child(r)
		roots.append(r)
	var nv := variants.size()
	var all := []      # per variant: ms per rebuild, every chunk
	var signed := []   # per variant: ms per rebuild, chunks with an area sign
	var totals := []   # per variant: ms for one pass over the 64 chunks
	for i in nv:
		all.append(PackedFloat32Array())
		signed.append(PackedFloat32Array())
		totals.append(PackedFloat32Array())
	for rep in reps + 2:
		# A B .. then .. B A on the next pass
		var order := range(nv)
		if rep % 2 == 1:
			order.reverse()
		for i in order:
			RoadSigns.set_flags(variants[i])
			var pass_usec := 0
			for c in 64:
				var a := Time.get_ticks_usec()
				B.rebuild_chunk(roots[i], c, cfg, cfg)
				var d := Time.get_ticks_usec() - a
				pass_usec += d
				if rep >= 2:   # the first two passes warm everything up
					all[i].append(float(d) / 1000.0)
					if B.name_sign_kind(c) != "":
						signed[i].append(float(d) / 1000.0)
			if rep >= 2:
				totals[i].append(float(pass_usec) / 1000.0 / 64.0)
	var res := {}
	for i in nv:
		res[variants[i]] = {"chunk_ms": _stats(all[i]), "sign_chunk_ms": _stats(signed[i]), "pass_mean_ms": _stats(totals[i])}
	# The sign part on its own (a whole rebuild is ~5 ms and swings by more
	# than the signs add): just the two calls _apply makes for them, ms.
	var walk := B.MEDIAN_GAP + 2.0 * B.LANE_W + 3.0
	for i in nv:
		if variants[i] == "off":
			continue
		RoadSigns.set_flags(variants[i])
		var names_plain := PackedFloat32Array()
		var names_sign := PackedFloat32Array()
		var paint_plain := PackedFloat32Array()
		var paint_marks := PackedFloat32Array()
		var per_chunk := PackedFloat32Array()
		for rep in 220:
			var pass_usec := 0
			for c in 64:
				var a := Time.get_ticks_usec()
				B._update_names(roots[i], c, walk, walk)
				var b := Time.get_ticks_usec()
				B._update_paint(roots[i], c, false, 2)
				var d := Time.get_ticks_usec()
				pass_usec += d - a
				if rep < 20:
					continue
				(names_sign if B.name_sign_kind(c) != "" else names_plain).append(float(b - a) / 1000.0)
				var shown: int = (roots[i].get_node(^"RoadPaint") as MultiMeshInstance3D).multimesh.visible_instance_count
				(paint_marks if shown > 0 else paint_plain).append(float(d - b) / 1000.0)
			if rep >= 20:
				per_chunk.append(float(pass_usec) / 1000.0 / 64.0)
		res[variants[i]]["parts"] = {
			"names_plain": _stats(names_plain), "names_sign": _stats(names_sign),
			"paint_plain": _stats(paint_plain), "paint_marks": _stats(paint_marks),
			"per_chunk_mean": _stats(per_chunk),
		}
	out["variants"] = res
	_emit(out)

# ---------- shots ----------

func _shots() -> bool:
	var player: PlayerCar = game.get("player")
	if shot_i >= SHOTS.size():
		quit(0)
		return true
	var shot: Array = SHOTS[shot_i]
	var o := float(RoadFrame.origin_index) * B.CHUNK_LEN
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.freeze = true
	player.visible = false
	player.global_transform = RoadFrame.pose(LANE_X, 0.6, o - (float(shot[1]) - 6.0), 0.0)
	player.reset_physics_interpolation()
	o = float(RoadFrame.origin_index) * B.CHUNK_LEN
	var from := RoadFrame.pose(float(shot[2]), float(shot[3]), o - float(shot[1]), 0.0).origin
	var to := RoadFrame.pose(float(shot[5]), float(shot[6]), o - float(shot[4]), 0.0).origin
	cam.global_transform = Transform3D(Basis(), from).looking_at(to, Vector3.UP)
	cam.current = true
	if wait_until == 0:
		wait_until = frame + (150 if shot_i == 0 else 60)
	if frame < wait_until:
		return false
	if not hud_hidden:
		_hide_hud(root)
		hud_hidden = true
		wait_until = frame + 5
		return false
	var img := root.get_viewport().get_texture().get_image()
	var path := OS.get_environment("SIGN_BENCH_DIR").path_join("%s.png" % shot[0])
	img.save_png(path)
	print("shot ", path)
	shot_i += 1
	wait_until = 0
	return false

func _hide_hud(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
	for c in n.get_children():
		_hide_hud(c)
