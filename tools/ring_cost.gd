extends SceneTree

# What a ring site costs (ring sites R1, 2026-10-11), measured. Boots
# Game.tscn at night on the loop, no traffic, the Low graphics tier (or
# RING_COST_GFX), and a bot drives the outside lane at 30 m/s over three
# stretches, sampling every frame:
#
#   site      1.1 km through exit 3's site: slip lanes, ramps, pad, gantry
#   site_off  the same road with RoadRamps switched off (no ramps or pad; the
#             buildings stand there again)
#   plain     the middle of district 6, which has no ring site
#
# Prints one line per stretch: frames, mean and worst-1% frame time, process
# and physics time, the viewport's CPU and GPU render time, draw calls and
# primitives. V-Sync off, no fps cap. Numbers are this machine's: compare
# stretches of one run, and say what else was running.
#
# Run (real window):
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tools/ring_cost.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadRamps := preload("res://scripts/world/road_ramps.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")

const L := 50.0
const LANE_X := 11.6
const SPEED := 30.0
const SETTLE := 90   # frames after a move before sampling

## [name, from (m round the loop), to, ramps on]
var legs: Array = [["site", 1450.0, 2550.0, true], ["site_off", 1450.0, 2550.0, false], ["plain", 4050.0, 4750.0, true]]
var leg := -1
var game: Node
var frame := 0
var leg_frame := 0
var last_usec := 0
var s := {}

func _initialize() -> void:
	OS.set_environment("NEON_TEST", "1")
	OS.set_environment("NEON_COCKPIT", "0")
	OS.set_environment("NEON_CITY_LIGHTS", "1")
	OS.set_environment("NEON_MUTE", "1")
	OS.set_environment("NEON_ROAD_SEED", "7")
	if OS.get_environment("NEON_CLOCK") == "":
		OS.set_environment("NEON_CLOCK", "23:30")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# RING_COST_REVERSE=1: the other order (the first stretch driven also pays
	# for warming up, so run both orders).
	if OS.get_environment("RING_COST_REVERSE") == "1":
		legs.reverse()
	game = Harness.boot(self, 0, 300.0, 7)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)

func _start_leg(p: PlayerCar) -> bool:
	leg += 1
	if leg >= legs.size():
		return false
	RoadRamps.enabled = bool(legs[leg][3])
	var z := float(RoadFrame.origin_index) * L - float(legs[leg][1])
	var t := RoadFrame.pose(LANE_X, 0.45, z, 0.0)
	game.saver.restore_car(p, {"xform": SaveDirector.xform_to_array(t), "lin_vel": [0.0, 0.0, 0.0], "ang_vel": [0.0, 0.0, 0.0], "gear": 1})
	game.call("_update_chunk_pool", RoadFrame.unroll(p.global_position).z)
	game.call("flush_rebuilds")
	p.driver = Harness.lane_driver(LANE_X, 1.0, SPEED)
	leg_frame = 0
	for k in ["wall", "process", "physics", "render_cpu", "gpu", "draw", "prims"]:
		s[k] = PackedFloat32Array()
	return true

func _process(_delta: float) -> bool:
	frame += 1
	var p: PlayerCar = game.get("player")
	if frame < 10:
		return false
	if frame == 10:
		var tier := OS.get_environment("RING_COST_GFX")
		GraphicsSettings.set_preset(tier if tier != "" else "low")
		GraphicsSettings.apply(self)
		_start_leg(p)
		last_usec = Time.get_ticks_usec()
		return false
	leg_frame += 1
	var now := Time.get_ticks_usec()
	if leg_frame > SETTLE and p.linear_velocity.length() > SPEED - 3.0:
		s.wall.append(float(now - last_usec) / 1000.0)
		s.process.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		s.physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		s.render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		var g := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		s.gpu.append(g if g < 1000.0 else 0.0)
		s.draw.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		s.prims.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)))
	last_usec = now
	var at := RoadMap.wrap_s(RoadFrame.s_at(RoadFrame.unroll(p.global_position).z))
	if at >= float(legs[leg][2]) or leg_frame > 40000:
		_report()
		if not _start_leg(p):
			RoadRamps.enabled = true
			quit(0)
			return true
	return false

func _mean(a: PackedFloat32Array) -> float:
	var t := 0.0
	for v in a:
		t += v
	return t / maxf(float(a.size()), 1.0)

func _report() -> void:
	var w: PackedFloat32Array = s.wall.duplicate()
	w.sort()
	var worst := w[int(float(w.size()) * 0.99)] if w.size() > 0 else 0.0
	print("ring_cost %-8s gfx=%s frames=%d  frame %.2f ms (%.0f fps), worst 1%% %.2f ms  process %.2f  physics %.2f  render cpu %.2f  gpu %.2f  draws %.0f  prims %.0f" % [
		legs[leg][0], GraphicsSettings.preset, s.wall.size(), _mean(s.wall), 1000.0 / maxf(_mean(s.wall), 0.001), worst,
		_mean(s.process), _mean(s.physics), _mean(s.render_cpu), _mean(s.gpu), _mean(s.draw), _mean(s.prims)])
