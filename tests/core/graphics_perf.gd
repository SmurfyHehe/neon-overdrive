extends SceneTree

# Graphics cost (polish pass, 2026-10-08): GPU frame time of each graphics
# setting and preset, on the real renderer. Boots Game.tscn with 20 traffic
# cars, the car parked in its lane looking down the road, V-Sync off, and
# alternates short blocks between the setups so slow drift (heat, clocks) hits
# all of them equally. Reports the median GPU time per setup and its delta to
# "base" (everything this pass adds switched off, no edge smoothing, full res).
# Reports, does not assert: the numbers are machine-dependent.
#
# GFX_RES=<w>x<h> sets the window (default 1920x1080, the laptop's screen).
# GFX_SETUPS=a,b,c measures only those setups. GFX_SHOT_DIR=<dir> saves one
# frame per setup there.
# Run (real renderer; a window opens for ~1-2 min):
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tests/core/graphics_perf.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const BLOCKS := 8        # per setup
const BLOCK_FRAMES := 40
const SKIP := 10         # frames dropped after each switch

## Each setup: GraphicsSettings values on top of BASE. Presets take PRESET_VALUES.
const BASE := {"aa": "off", "render_scale": 1.0}
const SETUPS := {
	"base": {},
	"fxaa": {"aa": "fxaa"},
	"msaa2": {"aa": "msaa2"},
	"msaa2_fxaa": {"aa": "msaa2_fxaa"},
	"msaa4": {"aa": "msaa4"},
	"scale75": {"render_scale": 0.75},
	"low": "low",
	"medium": "medium",
	"high": "high",
}

var game: Node
var names: Array = []
var vp: RID
var frame := 0
var block := 0
var in_block := 0
var times := {}
var cpu := {}
var shots := {}

func _initialize() -> void:
	var only := OS.get_environment("GFX_SETUPS")
	for k in SETUPS:
		if only == "" or k in only.split(","):
			names.append(k)
			times[k] = PackedFloat64Array()
			cpu[k] = PackedFloat64Array()
	game = Harness.boot(self, 20, 300.0, 7)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var res := OS.get_environment("GFX_RES")
	var size := Vector2i(1920, 1080)
	if res.contains("x"):
		size = Vector2i(int(res.get_slice("x", 0)), int(res.get_slice("x", 1)))
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(Vector2i.ZERO)

func _apply(setup: String) -> void:
	var s: Variant = SETUPS[setup]
	if s is String:
		GraphicsSettings.set_preset(s)
	else:
		var v := BASE.duplicate()
		v.merge(s, true)
		GraphicsSettings.aa = v.aa
		GraphicsSettings.render_scale = v.render_scale
	GraphicsSettings.apply(self)

func _process(_delta: float) -> bool:
	frame += 1
	if frame < 120:
		return false
	if frame == 120:
		vp = root.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		print("window %s" % [DisplayServer.window_get_size()])
		_apply(names[0])
		return false
	var setup: String = names[block % names.size()]
	in_block += 1
	if in_block > SKIP:
		times[setup].append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		cpu[setup].append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	if in_block == SKIP + 1 and not shots.has(setup):
		shots[setup] = true
		var dir := OS.get_environment("GFX_SHOT_DIR")
		if dir != "":
			root.get_texture().get_image().save_png(dir.path_join("gfx_%s.png" % setup))
	if in_block >= BLOCK_FRAMES:
		in_block = 0
		block += 1
		if block >= BLOCKS * names.size():
			_report()
			quit(0)
			return true
		_apply(names[block % names.size()])
	return false

static func _median(a: PackedFloat64Array) -> float:
	var s := a.duplicate()
	s.sort()
	return s[s.size() / 2]

func _report() -> void:
	var base := _median(times[names[0]])
	for k in names:
		var m := _median(times[k])
		print("%-12s GPU median %6.3f ms  %+6.3f vs %s  CPU frame %6.2f ms  (n=%d)" % [k, m, m - base, names[0], _median(cpu[k]), times[k].size()])
