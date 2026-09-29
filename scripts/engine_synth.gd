# Synthesised engine sound (2026-09-29, Roy picked option C in
# PROPOSAL-audio.md: "give it a try, go for C"). THROWAWAY PROTOTYPE -- its
# job is to answer "does a coded engine sound good enough?" by ear, not to be
# the final audio system.
#
# No samples. A four-stroke fires each cylinder once per two crank turns, so
# the firing rate is rpm / 60 * cylinders / 2. Each firing is a short pressure
# pulse; the pulses go through two resonant filters (the exhaust pipe body and
# a higher rasp) plus a low-pass whose cutoff opens with throttle, then soft
# clipping for grit. Per-cylinder loudness differences give the idle its lope,
# and at the rev limiter some firings are dropped, which is what a real
# limiter's stutter is.
#
# Pure DSP, no nodes: EngineAudio feeds it live Vehicle state, and
# tests/engine_audio_render.gd feeds it a scripted sweep to write a WAV.
extends RefCounted
class_name EngineSynth

var mix_rate := 44100.0
var cylinders := 4
var idle_rpm := 1000.0
var max_rpm := 7000.0
var volume := 0.5

## Fraction of each firing interval the pressure pulse lasts.
var pulse_width := 0.35
## Random per-firing loudness wobble on top of the fixed per-cylinder spread.
var fire_jitter := 0.08
## Chance a firing is cut while on the rev limiter.
var limiter_cut := 0.6
var body_hz := 110.0
var body_q := 1.5
var rasp_hz := 1200.0
var rasp_q := 2.0

var _crank := 0.0  # crank position in revolutions, wraps at 2 (one full cycle)
var _last_fire := -1
var _fire_amp := 1.0
var _rpm := -1.0
var _thr := 0.0
var _cyl_amp := PackedFloat32Array()
var _noise := 22222
# filter state: body band-pass, rasp band-pass, low-pass, DC blocker
var _bx1 := 0.0
var _bx2 := 0.0
var _by1 := 0.0
var _by2 := 0.0
var _rx1 := 0.0
var _rx2 := 0.0
var _ry1 := 0.0
var _ry2 := 0.0
var _lp := 0.0
var _dc_x := 0.0
var _dc_y := 0.0

func _init() -> void:
	# Fixed per-cylinder spread: the same cylinder is always a little louder
	# or quieter, so the pattern repeats every cycle like a real engine.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	_cyl_amp.resize(cylinders)
	for i in cylinders:
		_cyl_amp[i] = rng.randf_range(0.8, 1.0)

## Returns `frames` stereo frames. rpm and throttle glide from their previous
## values to these across the block, so per-frame updates don't click.
func render(frames: int, rpm: float, throttle: float, redline: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	if frames <= 0:
		return out
	if _rpm < 0.0:
		_rpm = rpm
	var rpm_step := (rpm - _rpm) / frames
	var thr_step := (throttle - _thr) / frames

	# Filter coefficients once per block; the resonances don't move with rpm.
	var bw := TAU * body_hz / mix_rate
	var ba := sin(bw) / (2.0 * body_q)
	var b_b0 := ba / (1.0 + ba)
	var b_a1 := -2.0 * cos(bw) / (1.0 + ba)
	var b_a2 := (1.0 - ba) / (1.0 + ba)
	var rw := TAU * rasp_hz / mix_rate
	var ra := sin(rw) / (2.0 * rasp_q)
	var r_b0 := ra / (1.0 + ra)
	var r_a1 := -2.0 * cos(rw) / (1.0 + ra)
	var r_a2 := (1.0 - ra) / (1.0 + ra)
	var rpm_norm := clampf((rpm - idle_rpm) / (max_rpm - idle_rpm), 0.0, 1.0)
	var cutoff := 500.0 + 2300.0 * throttle + 1500.0 * rpm_norm
	var lp_k := 1.0 - exp(-TAU * cutoff / mix_rate)
	var fires_per_cycle := cylinders * 0.5

	for i in frames:
		_rpm += rpm_step
		_thr += thr_step
		_crank += _rpm / 60.0 / mix_rate
		if _crank >= 2.0:
			_crank -= 2.0
		var cyc := _crank * fires_per_cycle
		var idx := int(cyc)
		var p := cyc - idx
		if idx != _last_fire:
			_last_fire = idx
			_fire_amp = _cyl_amp[idx % cylinders] * (1.0 + (_rand() * fire_jitter))
			if redline and absf(_rand()) < limiter_cut:
				_fire_amp = 0.0

		var pulse := 0.0
		if p < pulse_width:
			pulse = sin(PI * p / pulse_width) * _fire_amp
		var load := 0.6 + 0.4 * _thr
		var e := pulse * load + _rand() * (0.08 + 0.25 * _thr) * (pulse * 0.8 + 0.2)

		var body := b_b0 * e - b_b0 * _bx2 - b_a1 * _by1 - b_a2 * _by2
		_bx2 = _bx1
		_bx1 = e
		_by2 = _by1
		_by1 = body
		var rasp := r_b0 * e - r_b0 * _rx2 - r_a1 * _ry1 - r_a2 * _ry2
		_rx2 = _rx1
		_rx1 = e
		_ry2 = _ry1
		_ry1 = rasp
		_lp += lp_k * (e - _lp)

		var s := _lp + body * 0.9 + rasp * 0.25 * (0.3 + _thr)
		s = tanh(s * (1.5 + 1.5 * _thr))
		# DC blocker: the pulses are all positive, so strip the offset.
		var dc := s - _dc_x + 0.995 * _dc_y
		_dc_x = s
		_dc_y = dc
		var v := dc * volume * (0.55 + 0.45 * rpm_norm)
		out[i] = Vector2(v, v)
	return out

## White noise in [-1, 1]. Inline LCG: a RandomNumberGenerator call per
## sample is noticeably slower in GDScript.
func _rand() -> float:
	_noise = (_noise * 1103515245 + 12345) & 0x7fffffff
	return _noise / 1073741823.5 - 1.0
