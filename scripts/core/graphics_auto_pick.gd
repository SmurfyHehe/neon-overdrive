class_name GraphicsAutoPick
extends Node

# First-launch graphics pick (2026-10-09, car look doc section 13). When the
# settings file has no graphics preset yet, the game starts at Medium and
# this node times the first few seconds of driving: WARMUP_SECS skipped
# (shader compiles), then MEASURE_SECS measured. It estimates what frame rate
# the machine could reach at Medium and picks:
#   under LOW_BELOW fps -> Low, over HIGH_ABOVE fps -> High, else Medium.
# Then it applies and saves the choice (marked "auto"; the pause menu's
# Graphics page shows it and any change there replaces it) and frees itself.
#
# V-sync holds a fast machine at 60, so a V-synced frame time cannot tell 60
# from 150. For the measured seconds V-sync is off and the frame cap cleared
# (what benchmark.gd does for its whole run), so the frame time is the real
# cost of the slower side, CPU or GPU; both are restored afterwards. A few
# seconds of tearing on the very first launch is the price. (The engine's
# TIME_PROCESS / TIME_PHYSICS_PROCESS monitors were tried for a V-synced CPU
# estimate and rejected: in a 4.7 headless probe they changed about once a
# second and read above the frame time.)
#
# Benchmark runs, headless runs and runs with NEON_GFX set never auto-pick.

const WARMUP_SECS := 2.0
const MEASURE_SECS := 3.0
const LOW_BELOW := 50.0
const HIGH_ABOVE := 100.0

var t := 0.0
var frame: PackedFloat32Array = []
var gpu: PackedFloat32Array = []
var picked := ""
var _vsync := DisplayServer.VSYNC_ENABLED
var _cap := 0
var _uncapped := false
## True while measuring: DynamicResolution holds still so it does not skew the GPU time.
static var running := false

static func wanted() -> bool:
	return GraphicsSettings.needs_auto_pick() and not Benchmark.requested() \
		and DisplayServer.get_name() != "headless"

## The tier for an estimated frame rate.
static func pick_for(fps: float) -> String:
	if fps < LOW_BELOW:
		return "low"
	if fps > HIGH_ABOVE:
		return "high"
	return "medium"

static func _median(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := Array(a)
	s.sort()
	return s[s.size() / 2]

## Frame rate estimate from uncapped frame times (ms): the median frame.
static func estimate_fps(frame_ms: PackedFloat32Array) -> float:
	return 1000.0 / maxf(_median(frame_ms), 0.1)

func _ready() -> void:
	running = true
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	t += delta
	if t <= WARMUP_SECS:
		return
	if not _uncapped:
		# The first frame after this one is the first uncapped one.
		_uncapped = true
		_vsync = DisplayServer.window_get_vsync_mode()
		_cap = Engine.max_fps
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		return
	frame.append(delta * 1000.0)
	var g := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	if g > 0.0 and g < 1000.0:
		gpu.append(g)
	if t < WARMUP_SECS + MEASURE_SECS:
		return
	_restore()
	var fps := estimate_fps(frame)
	picked = pick_for(fps)
	print("Graphics auto pick: ~%d fps at Medium -> %s (frame %.1f ms, gpu %.1f ms, %d frames)" % [
		roundi(fps), picked, _median(frame), _median(gpu), frame.size()])
	GraphicsSettings.set_preset(picked)
	GraphicsSettings.auto_picked = true
	GraphicsSettings.apply(get_tree())
	GraphicsSettings.save_settings()
	queue_free()

func _restore() -> void:
	running = false
	if _uncapped:
		_uncapped = false
		DisplayServer.window_set_vsync_mode(_vsync)
		Engine.max_fps = _cap

func _exit_tree() -> void:
	_restore()
