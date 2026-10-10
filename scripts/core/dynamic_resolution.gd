class_name DynamicResolution
extends Node

# Dynamic resolution (2026-10-09, car look doc section 13): holds the frame
# rate inside a graphics tier by lowering the 3D render scale while the GPU is
# over its frame budget, and raising it back when there is room. The HUD is
# drawn after the 3D view, so it stays sharp; only the world gets softer.
#
# It reads the GPU time the viewport measures (the same number benchmark.gd
# reports as gpu=), not the frame time: when the CPU is the slow side (lots
# of traffic), a lower resolution would not help, so it leaves the picture
# alone. That is the CPU side's job (the preset's traffic and mirror values).
#
# Rules: GPU time above DROP_AT of the budget for DROP_SECS -> scale down one
# STEP, to no lower than floor_for(base). Raise one STEP when the predicted
# GPU time at the higher scale (pixels go with scale squared) stays under
# RAISE_AT of the budget for RAISE_SECS. Never above the preset's scale.
# The budget is one frame at the frame cap, or at the display's rate capped
# to 60 (V-sync).
#
# The decision is step() on plain numbers, so tests drive it without a GPU.
# Headless runs measure 0 ms GPU time, so it never moves there.

const STEP := 0.1
const FLOOR := 0.66
const FLOOR_MIN := 0.5
const DROP_AT := 0.9
const RAISE_AT := 0.75
const DROP_SECS := 2.0
const RAISE_SECS := 5.0
## Smoothing of the measured GPU time (seconds to follow a change).
const SMOOTH_SECS := 0.25

var scale := 1.0
var base := 1.0
var budget_ms := 1000.0 / 60.0
var gpu_avg := 0.0
## PerfLadder's hold on the picture: the scale shown is never above this,
## whatever the GPU time says (1.0 = no hold).
var ceiling := 1.0
var _over := 0.0
var _under := 0.0

## The lowest scale for a preset scale: 0.66 from full resolution, lower from
## an already-reduced one (Low starts at 0.75), never under 0.5.
static func floor_for(b: float) -> float:
	return clampf(b - 0.34, FLOOR_MIN, FLOOR)

static func budget_for(cap: int, refresh_hz: float) -> float:
	var fps := float(cap) if cap > 0 else clampf(refresh_hz if refresh_hz > 1.0 else 60.0, 30.0, 60.0)
	return 1000.0 / fps

func _ready() -> void:
	add_to_group(GraphicsSettings.GROUP)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	apply_graphics()

## Settings changed (or first start): back to the preset's scale.
func apply_graphics() -> void:
	reset(GraphicsSettings.render_scale,
		budget_for(GraphicsSettings.fps_cap, DisplayServer.screen_get_refresh_rate()))
	_push()

func reset(b: float, budget: float) -> void:
	base = b
	scale = b
	budget_ms = budget
	gpu_avg = 0.0
	_over = 0.0
	_under = 0.0

## One frame: the GPU time it took (ms) and its length (s). Returns the scale.
func step(gpu_ms: float, dt: float) -> float:
	if not GraphicsSettings.dynamic_res or GraphicsAutoPick.running or dt <= 0.0 or not is_finite(gpu_ms) or gpu_ms <= 0.0 or gpu_ms > 1000.0:
		return scale   # off, or no real measurement (headless, driver garbage)
	var k := clampf(dt / SMOOTH_SECS, 0.0, 1.0)
	gpu_avg = gpu_ms if gpu_avg == 0.0 else lerpf(gpu_avg, gpu_ms, k)
	var lo := floor_for(base)
	if gpu_avg > budget_ms * DROP_AT and scale > lo + 0.001:
		_over += dt
		_under = 0.0
		if _over >= DROP_SECS:
			scale = maxf(lo, snappedf(scale - STEP, 0.01))
			_over = 0.0
			gpu_avg = 0.0   # re-measure at the new scale
	elif scale < base - 0.001:
		_over = 0.0
		var up := minf(base, snappedf(scale + STEP, 0.01))
		var predicted := gpu_avg * (up * up) / (scale * scale)
		if predicted < budget_ms * RAISE_AT:
			_under += dt
			if _under >= RAISE_SECS:
				scale = up
				_under = 0.0
				gpu_avg = 0.0
		else:
			_under = 0.0
	else:
		_over = 0.0
		_under = 0.0
	return scale

func _process(delta: float) -> void:
	var before := scale
	step(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()), delta)
	if scale != before:
		_push()

## PerfLadder: hold the picture at the lowest scale (on), or let go.
func hold_low(on: bool) -> void:
	ceiling = floor_for(base) if on else 1.0
	_push()

func _push() -> void:
	get_viewport().scaling_3d_scale = minf(scale, ceiling)
