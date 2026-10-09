extends SceneTree

# Sky cost (2026-10-07): GPU frame time of the moon sky against the old one.
# Boots Game.tscn parked on the road (moon in view), V-Sync off, and
# alternates short blocks between three setups so slow drift (heat, clocks)
# hits all of them equally:
#   old    - ProceduralSkyMaterial, fog over the sky (fog_sky_affect 1)
#   moon   - NightSky (gradient + full moon), fog off the sky: what ships
#   aerial - moon plus fog_aerial_perspective 1 (tried and dropped: on the
#            i5-1235U it cost ~0.16 ms for a seam you can barely see)
# Reports the median GPU time per setup and the deltas. Reports, does not
# assert: the numbers are machine-dependent. Compare runs on the same machine.
# Run (real renderer; a window opens for ~40 s):
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tests/sky_perf.gd

const Harness := preload("res://tests/traffic_harness.gd")
const BLOCKS := 16       # per setup
const BLOCK_FRAMES := 60
const SKIP := 15         # frames dropped after each switch (radiance re-render)
const SETUPS := ["old", "moon", "aerial"]

var game: Node
var env: Environment
var old_sky: Sky
var moon_sky: Sky
var vp: RID
var frame := 0
var block := 0
var in_block := 0
var times := {"old": PackedFloat64Array(), "moon": PackedFloat64Array(), "aerial": PackedFloat64Array()}

func _initialize() -> void:
	game = Harness.boot(self, 0, 300.0, 7)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _apply(setup: String) -> void:
	env.sky = old_sky if setup == "old" else moon_sky
	env.fog_sky_affect = 1.0 if setup == "old" else 0.0
	env.fog_aerial_perspective = 1.0 if setup == "aerial" else 0.0

func _process(_delta: float) -> bool:
	frame += 1
	if frame < 90:
		return false
	if env == null:
		for n in game.get_children():
			if n is WorldEnvironment:
				env = n.environment
		moon_sky = env.sky
		NightSky.set_phase(moon_sky, 0.5)
		var mat := ProceduralSkyMaterial.new()
		mat.sky_top_color = NightSky.SKY_TOP
		mat.sky_horizon_color = NightSky.SKY_HORIZON
		mat.ground_bottom_color = NightSky.GROUND_BOTTOM
		mat.ground_horizon_color = NightSky.GROUND_HORIZON
		old_sky = Sky.new()
		old_sky.sky_material = mat
		vp = root.get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		_apply(SETUPS[0])
		return false
	var setup: String = SETUPS[block % SETUPS.size()]
	in_block += 1
	if in_block > SKIP:
		times[setup].append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	if in_block >= BLOCK_FRAMES:
		in_block = 0
		block += 1
		if block >= BLOCKS * SETUPS.size():
			_report()
			quit(0)
			return true
		_apply(SETUPS[block % SETUPS.size()])
	return false

static func _median(a: PackedFloat64Array) -> float:
	var s := a.duplicate()
	s.sort()
	return s[s.size() / 2]

func _report() -> void:
	var m := {}
	for k in SETUPS:
		m[k] = _median(times[k])
		print("%-5s GPU median %.3f ms (n=%d)" % [k, m[k], times[k].size()])
	print("moon sky vs old     : %+.3f ms" % (m.moon - m.old))
	print("aerial perspective  : %+.3f ms" % (m.aerial - m.moon))
