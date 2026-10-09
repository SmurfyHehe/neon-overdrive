class_name QualityCheck
extends Node

# Automatic quality check (2026-10-09, small-ideas M3). On the very first
# launch (no [graphics] choice saved yet) it quietly measures how long this
# PC's graphics card takes to draw a frame at the Medium preset during the
# first seconds of play, picks Low, Medium or High from that, applies it and
# saves it. The Graphics page's "Test my PC" button runs the same check
# again whenever asked.
#
# The pick is on GPU time at Medium, which on the reference laptop (i5-1235U,
# Iris Xe, 1080p) measured ~9.8 ms with High at ~13.8 ms and Low at ~8.3
# (tests/graphics_perf.gd): High costs about 4 ms more than Medium.
# - Medium under HIGH_BELOW: High still leaves room inside a 60 fps frame
# - Medium over LOW_ABOVE: drop to Low (75% resolution)
# - otherwise Medium. The reference laptop lands on Medium at 1080p.
# It measures at the window size you play at, on purpose: the same laptop in
# a small 1152x648 window drew Medium in 2.8 ms and gets High.
# Not run in the test runner (script main loops), headless, in benchmark
# runs, or when NEON_GFX forces a preset.

signal finished(preset: String, gpu_ms: float)

const HIGH_BELOW := 8.0     # ms GPU at Medium
const LOW_ABOVE := 13.0
const WARMUP_FRAMES := 45   # shader compiles and the first chunk builds stutter
const SAMPLE_FRAMES := 120

var _frame := 0
var _samples := PackedFloat64Array()
var _vp: RID

static func pick(gpu_ms_medium: float) -> String:
	if gpu_ms_medium < HIGH_BELOW:
		return "high"
	if gpu_ms_medium > LOW_ABOVE:
		return "low"
	return "medium"

## True when the game should run the check by itself: nothing chosen yet,
## a real window, and not a test, benchmark or forced preset.
static func should_auto_run() -> bool:
	if DisplayServer.get_name() == "headless" or OS.get_environment("NEON_GFX") != "":
		return false
	if Benchmark.requested():
		return false
	var loop := Engine.get_main_loop()
	if loop != null and loop.get_script() != null:   # -s test scripts
		return false
	var cfg := ConfigFile.new()
	return cfg.load(AudioSettings.path) != OK or not cfg.has_section_key("graphics", "preset")

func _init() -> void:
	name = "QualityCheck"
	process_mode = Node.PROCESS_MODE_ALWAYS   # also runs under the pause menu

func _ready() -> void:
	GraphicsSettings.set_preset("medium")
	GraphicsSettings.apply(get_tree())
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)

func _process(_delta: float) -> void:
	_frame += 1
	if _frame <= WARMUP_FRAMES:
		return
	_samples.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp))
	if _samples.size() < SAMPLE_FRAMES:
		return
	var s := _samples.duplicate()
	s.sort()
	var median := s[s.size() / 2]
	var preset := pick(median)
	GraphicsSettings.set_preset(preset)
	GraphicsSettings.apply(get_tree())
	GraphicsSettings.save_settings()
	print("Quality check: Medium took %.1f ms on the GPU, picked %s" % [median, preset])
	finished.emit(preset, median)
	queue_free()
