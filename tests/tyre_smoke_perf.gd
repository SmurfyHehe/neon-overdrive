extends SceneTree

# Tyre smoke frame cost (2026-10-07). Budget: 0.5 ms. Needs the real renderer
# (not --headless: headless draws nothing and drops MultiMesh data).
#
# Boots Game.tscn with 16 traffic cars (the default), holds the player in a
# burnout on the spot (brakes on, full throttle, traction control off) so the
# pool fills and the cloud sits right in front of the chase camera -- the worst
# case for fill -- then measures, vsync off:
# - GPU and CPU render time of the main viewport (RenderingServer measured
#   render time), alternating 3 s windows with the smoke on and with the
#   tyre_smoke flag off, six of each, the rest identical (the car keeps
#   spinning). The median on-minus-off pair is the smoke's draw cost (the
#   iGPU's clock wanders by about 0.3 ms between windows).
# - CPU: TyreSmoke._physics_process timed directly, averaged over 2000 calls
#   (emission included), against the 120 Hz tick.
# Prints the numbers; fails only on errors or if the pool never filled. Run:
#   Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . -s res://tests/tyre_smoke_perf.gd

const WARM := 3.0
const MEASURE := 3.0
const BUDGET_MS := 0.5

enum Step { BOOT, WARM, SETTLE, MEASURE, DONE }
const CYCLES := 6

var step := Step.BOOT
var t0 := 0
var failures: Array[String] = []
var gpu: Array[float] = []
var cpu: Array[float] = []
var frame: Array[float] = []
var results := {true: [], false: []}   # smoke on? -> per-window stats
var live_max := 0
var window := 0   # even = smoke on, odd = off
var shots := {}

func _initialize() -> void:
	ExhaustTune.save_path = "user://autotune/test_tyre_smoke_perf_exhaust.json"
	seed(99)
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = 1.0
	c.brake_input = 1.0
	c.steering_input = 0.0
	c.handbrake_input = 0.0

func _process(delta: float) -> bool:
	var game := current_scene
	if game == null or game.get("player") == null or game.get("fx") == null:
		return false
	var p: PlayerCar = game.player
	var fx: FxPack = game.fx
	var vp := root.get_viewport_rid()
	var now := Time.get_ticks_msec()
	var on := window % 2 == 0
	match step:
		Step.BOOT:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			RenderingServer.viewport_set_measure_render_time(vp, true)
			FxSettings.set_smoke(1.0, 1.0)
			var traffic: Variant = game.get("traffic")
			if traffic != null:
				traffic.set_car_count(16)
			p.traction_control_max_slip = 0.0
			p.driver = _drive
			_go(Step.WARM)
		Step.WARM:
			if now - t0 > WARM * 1000.0:
				_go(Step.MEASURE)
		Step.SETTLE:
			# the other state's last frames are still in flight
			if now - t0 > 1000.0:
				_go(Step.MEASURE)
		Step.MEASURE:
			_sample(vp, delta)
			if on:
				live_max = maxi(live_max, fx.smoke.live_count())
			if now - t0 > 2000.0 and not shots.has(on):
				shots[on] = true
				_shot("on" if on else "off")
			if now - t0 > MEASURE * 1000.0:
				results[on].append(_stats())
				window += 1
				if window >= CYCLES * 2:
					fx.set_effect("tyre_smoke", true)
					_report(_cpu_cost(fx.smoke))
					_go(Step.DONE)
				else:
					fx.set_effect("tyre_smoke", window % 2 == 0)
					_go(Step.SETTLE)
		Step.DONE:
			pass
	return false

## TYRE_SMOKE_SHOT=<folder> saves a frame from each window, to look at.
func _shot(tag: String) -> void:
	var dir := OS.get_environment("TYRE_SMOKE_SHOT")
	if dir != "":
		root.get_texture().get_image().save_png(dir.path_join("tyre_smoke_%s.png" % tag))

func _sample(vp: RID, delta: float) -> void:
	gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
	frame.append(delta * 1000.0)

func _stats() -> Dictionary:
	var out := {"gpu": _median(gpu), "cpu": _median(cpu), "frame": _median(frame), "n": gpu.size()}
	gpu.clear()
	cpu.clear()
	frame.clear()
	return out

func _median(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2]

## Wall time of one TyreSmoke physics tick while the burnout is pouring.
func _cpu_cost(s: TyreSmoke) -> float:
	var n := 2000
	var start := Time.get_ticks_usec()
	for _k in n:
		s._physics_process(1.0 / 120.0)
	return (Time.get_ticks_usec() - start) / float(n) / 1000.0

func _report(tick_ms: float) -> void:
	var on := _mean_of(results[true])
	var off := _mean_of(results[false])
	print("tyre_smoke_perf: %s / %s, 16 traffic cars, burnout in front of the chase camera" % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method()])
	print("  live puffs (max while on): %d / %d" % [live_max, TyreSmoke.MAX_PUFFS])
	var diffs: Array[float] = []
	for k in results[true].size():
		diffs.append(results[true][k].gpu - results[false][k].gpu)
		print("  pair %d: gpu on %.3f / off %.3f ms (%+.3f)" % [k, results[true][k].gpu, results[false][k].gpu, diffs[k]])
	print("  smoke on : gpu %.3f ms  render cpu %.3f ms  frame %.2f ms" % [on.gpu, on.cpu, on.frame])
	print("  smoke off: gpu %.3f ms  render cpu %.3f ms  frame %.2f ms" % [off.gpu, off.cpu, off.frame])
	# the iGPU's clock wanders by +-0.3 ms between windows: the median pair is the number to read
	print("  draw cost (gpu on - off): median of %d pairs %.3f ms, mean %.3f ms   render cpu: %.3f ms" % [
		CYCLES, _median(diffs), on.gpu - off.gpu, on.cpu - off.cpu])
	print("  physics tick cost: %.4f ms per 120 Hz tick (%.3f ms per 60 fps frame)" % [tick_ms, tick_ms * 2.0])
	print("  budget %.2f ms" % BUDGET_MS)
	if live_max < 30:
		failures.append("the burnout should keep at least 30 puffs in the air (%d live)" % live_max)
	for f in failures:
		printerr("FAIL: ", f)
	print("tyre_smoke_perf: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _mean_of(a: Array) -> Dictionary:
	var out := {"gpu": 0.0, "cpu": 0.0, "frame": 0.0}
	for r in a:
		for k in out:
			out[k] += r[k] / a.size()
	return out

func _go(next: Step) -> void:
	step = next
	t0 = Time.get_ticks_msec()
