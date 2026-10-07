# Synthesised engine sound (2026-09-29, Roy picked option C in
# PROPOSAL-audio.md: "give it a try, go for C"). It began as a throwaway
# prototype; it is now the shipped engine voice (EngineAudio, PR #57), shaped
# by the exhaust (#92), turbo (#102) and driveline (#104) work.
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
## Cosmetic exhaust knobs (stage B step 2): loudness, raspiness, overrun
## pops/crackles, flame size. See exhaust_tune.gd.
var tune := ExhaustTune.new()

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
## Overrun bangs per second with the anti-lag switch on (ExhaustTune.anti_lag).
const ANTI_LAG_RATE := 14.0

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
# overrun pops and limiter bangs. _pop_env is a pop REQUEST (its strength
# 0..1); the pop voice turns each request into a cluster of bangs and clears it.
var _pop_env := 0.0
var _pop_wait := 0  # samples until the next overrun pop
var _flame_peak := 0.0
# The pop voice (2026-10-07, exhaust-sound-research-2026-10-07 option A). Real
# overrun pops come in clusters, not single clicks: a burble of a few bangs a
# few tens of ms apart, and each bang rings the tailpipe for a moment after the
# crack. One bang = a sharp noise crack, a low boom, and a kick into two decaying
# resonators (the pipe's ring), tuned off body_hz so each car's pipe rings in
# its own key. Nothing here runs per sample between bangs.
enum PopKind { BURBLE, LIMITER, ANTI_LAG, UPSHIFT }
## Per kind: bangs min, bangs max, gap min s, gap max s, ring level, boom level.
const POP_CLUSTERS := {
	PopKind.BURBLE: [2, 4, 0.025, 0.07, 0.7, 1.0],    # lift-off burble: loose, uneven
	PopKind.LIMITER: [1, 2, 0.015, 0.03, 0.6, 0.8],   # a cut firing or two on the limiter
	PopKind.ANTI_LAG: [3, 6, 0.012, 0.035, 0.5, 0.7], # anti-lag: a tight machine-gun crackle
	PopKind.UPSHIFT: [1, 2, 0.02, 0.04, 1.0, 1.4],    # ignition cut on a flat-out upshift
}
const RING_RATIO := 2.1        # first pipe mode = body_hz x this
const RING2_RATIO := 2.76      # second, tinnier mode = first x this
const RING_DECAY := 0.07       # s, the ring's time constant
const CRACK_DECAY := 0.004     # s
const BOOM_DECAY := 0.025      # s
var _shift_req := 0.0          # upshift-cut request (shift_cut()), 0..1
var _cl_left := 0              # bangs still to come in the current cluster
var _cl_wait := 0              # samples to the next one
var _cl_kind := PopKind.BURBLE
var _cl_amp := 0.0
var _crack_env := 0.0
var _crack_lp := 0.0
var _boom_env := 0.0
var _boom_lp := 0.0
var _ring_live := 0            # samples of ring tail left to render
var _r1 := 0.0                 # pipe resonators: current and previous sample
var _r1p := 0.0
var _r2 := 0.0
var _r2p := 0.0
var _ring_kick1 := 0.0         # resonator kick per unit bang, set per block
var _ring_kick2 := 0.0
var _ring_mix := 0.0
var _boom_mix := 0.0
## Pop-voice counters for tests: clusters started, bangs fired, upshift clusters.
var pop_clusters := 0
var pop_bangs := 0
var upshift_clusters := 0
## Turbo (Phase B): boost 0..1 (fraction of max boost) set by EngineAudio; blow_off()
## fires the vent. The whistle is a rising sine, the vent a short filtered noise burst.
var boost := 0.0
var _whistle_phase := 0.0
var _bov_env := 0.0
var _bov_lp := 0.0

func _init() -> void:
	# Fixed per-cylinder spread: the same cylinder is always a little louder
	# or quieter, so the pattern repeats every cycle like a real engine.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	_cyl_amp.resize(cylinders)
	for i in cylinders:
		_cyl_amp[i] = rng.randf_range(0.8, 1.0)

## The blow-off valve vents: a short "pssh" whose size follows how hot the boost was.
func blow_off(strength: float) -> void:
	_bov_env = maxf(_bov_env, clampf(strength, 0.0, 1.0))

## The ignition cut of a flat-out upshift (EngineAudio calls it on GEVP's
## is_up_shifting edge, in every gearbox mode): one or two hard bangs with a
## long pipe ring. Only on high-flame cars, the same rule as the upshift flame
## (ExhaustFlames.UPSHIFT_FLAME_MIN). No flame event: ExhaustFlames queues its
## own upshift burst with the same delay, so the two land together.
func shift_cut(strength := 1.0) -> void:
	if tune.flame >= ExhaustFlames.UPSHIFT_FLAME_MIN:
		_shift_req = maxf(_shift_req, clampf(strength, 0.0, 1.0))

## Largest flame (0..1) the exhaust has spat since the last call, then resets.
## Pops on overrun and rev-limiter cuts make flames, scaled by tune.flame.
## Cosmetic: a flame visual reads this, nothing in the sim does.
func take_flames() -> float:
	var f := _flame_peak
	_flame_peak = 0.0
	return f

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
	# Tune: loudness scales the whole note, raspiness opens the rasp band, adds
	# noise and sharpens the pulse. Pops need a lifted throttle at rpm.
	var gain := 0.35 + 1.3 * tune.loudness
	var rasp_gain := 0.25 + 1.1 * tune.raspiness
	var noise_gain := 1.0 + 2.5 * tune.raspiness
	var width := pulse_width * (1.0 - 0.35 * tune.raspiness)
	var overrun := throttle < 0.08 and rpm_norm > 0.3
	var pop_rate := 0.0  # pops per second
	if overrun and tune.pops > 0.0:
		pop_rate = tune.pops * (3.0 + 22.0 * rpm_norm)
	if overrun and tune.anti_lag >= 0.5:
		# Anti-lag crackle (cosmetic switch): a steady volley of bangs on every
		# lift, whatever the pops knob says. Uses the existing pop voice; the
		# dedicated crackle sound is separate work.
		pop_rate = maxf(pop_rate, ANTI_LAG_RATE)
	var pop_p := pop_rate / mix_rate
	var pop_decay := exp(-1.0 / (0.02 * mix_rate))
	# A pop request this block becomes this kind of cluster.
	var pop_kind := PopKind.BURBLE
	if redline:
		pop_kind = PopKind.LIMITER
	elif overrun and tune.anti_lag >= 0.5:
		pop_kind = PopKind.ANTI_LAG
	# Pipe resonators: y = 2r cos(w) y1 - r^2 y2, so a kick of a*sin(w) rings
	# at about amplitude a and dies away with RING_DECAY.
	var ring_r := exp(-1.0 / (RING_DECAY * mix_rate))
	var w1 := TAU * clampf(body_hz * RING_RATIO, 60.0, 4000.0) / mix_rate
	var w2 := minf(w1 * RING2_RATIO, PI * 0.5)
	var ring_r2 := exp(-1.0 / (0.7 * RING_DECAY * mix_rate))  # the higher mode dies sooner
	var k1 := 2.0 * ring_r * cos(w1)
	var k2 := 2.0 * ring_r2 * cos(w2)
	var k1b := ring_r * ring_r
	var k2b := ring_r2 * ring_r2
	_ring_kick1 = sin(w1)
	_ring_kick2 = sin(w2)
	var crack_k := exp(-1.0 / (CRACK_DECAY * mix_rate))
	var boom_k := exp(-1.0 / (BOOM_DECAY * mix_rate))

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
				# an unburnt charge going out the pipe: a bang at the limiter
				if tune.pops > 0.0 and absf(_rand()) < tune.pops:
					_pop_env = maxf(_pop_env, 0.6 + 0.4 * absf(_rand()))
					_flame_peak = maxf(_flame_peak, tune.flame * (0.5 + 0.5 * absf(_rand())))

		var pulse := 0.0
		if p < width:
			pulse = sin(PI * p / width) * _fire_amp
		var load := 0.6 + 0.4 * _thr
		var e := pulse * load + _rand() * (0.08 + 0.25 * _thr) * noise_gain * (pulse * 0.8 + 0.2)

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

		if pop_p > 0.0:
			# count down to the next pop instead of rolling dice every sample
			_pop_wait -= 1
			if _pop_wait <= 0:
				var amp := 0.4 + 0.6 * absf(_rand())
				_pop_env = maxf(_pop_env, amp)
				_flame_peak = maxf(_flame_peak, tune.flame * amp)
				_pop_wait = int((0.3 + 1.4 * absf(_rand())) / pop_p)
		if _pop_env > 0.0:
			_start_cluster(pop_kind, _pop_env)
			_pop_env = 0.0
		if _shift_req > 0.0:
			_start_cluster(PopKind.UPSHIFT, _shift_req)
			_shift_req = 0.0
		var pop := 0.0
		if _cl_left > 0 or _ring_live > 0:
			# The pop voice, inline (a function call per sample is slow in GDScript).
			if _cl_left > 0:
				_cl_wait -= 1
				if _cl_wait <= 0:
					_fire_bang()
			var pn := _rand()
			# crack: high-passed noise (noise minus its own low-pass), 4 ms envelope
			_crack_lp += 0.2 * (pn - _crack_lp)
			# boom: low-passed noise under a slower envelope, the thump of the bang
			_boom_lp += 0.03 * (pn - _boom_lp)
			var r1 := k1 * _r1 - k1b * _r1p
			_r1p = _r1
			_r1 = r1
			var r2 := k2 * _r2 - k2b * _r2p
			_r2p = _r2
			_r2 = r2
			pop = (pn - _crack_lp) * _crack_env * 0.9 + _boom_lp * 10.0 * _boom_env * _boom_mix + (r1 * 0.8 + r2 * 0.45) * _ring_mix
			_crack_env *= crack_k
			_boom_env *= boom_k
			_ring_live -= 1
			if _ring_live <= 0 and _cl_left <= 0:
				_r1 = 0.0
				_r1p = 0.0
				_r2 = 0.0
				_r2p = 0.0
		var turbo := 0.0
		if boost > 0.02:
			# whistle: pitch and level rise with boost
			_whistle_phase += TAU * (1800.0 + 5200.0 * boost) / mix_rate
			turbo = sin(_whistle_phase) * 0.2 * boost * boost
		if _bov_env > 0.01:
			var bn := _rand()
			_bov_lp += 0.25 * (bn - _bov_lp)
			turbo += (bn - _bov_lp) * 0.8 * _bov_env
			_bov_env *= pop_decay
		var s := _lp + body * 0.9 + rasp * rasp_gain * (0.3 + _thr) + pop * (0.5 + 0.5 * tune.loudness) + turbo * (0.5 + 0.5 * tune.loudness)
		s = tanh(s * (1.5 + 1.5 * _thr))
		# DC blocker: the pulses are all positive, so strip the offset.
		var dc := s - _dc_x + 0.995 * _dc_y
		_dc_x = s
		_dc_y = dc
		var v := dc * volume * gain * (0.55 + 0.45 * rpm_norm)
		out[i] = Vector2(v, v)
	return out

## Starts a cluster of bangs, or tops up the running one (never shortens it).
func _start_cluster(kind: int, strength: float) -> void:
	var c: Array = POP_CLUSTERS[kind]
	var n := mini(int(c[0]) + int(absf(_rand()) * (int(c[1]) - int(c[0]) + 1)), int(c[1]))
	if _cl_left <= 0 or kind == PopKind.UPSHIFT:
		# first bang on the next sample; an upshift cuts in at once, even into a
		# running limiter cluster, so it lands with its flame
		_cl_wait = 0
		pop_clusters += 1
		if kind == PopKind.UPSHIFT:
			upshift_clusters += 1
	if _cl_left <= 0 or kind == PopKind.UPSHIFT or strength >= _cl_amp:
		_cl_kind = kind
		_cl_amp = clampf(strength, 0.0, 1.0)
	_cl_left = maxi(_cl_left, n)

## The cluster's next bang: crack, boom and a kick into the two pipe modes.
func _fire_bang() -> void:
	var c: Array = POP_CLUSTERS[_cl_kind]
	var a := _cl_amp * (0.6 + 0.4 * absf(_rand()))
	_crack_env = maxf(_crack_env, a)
	_boom_env = maxf(_boom_env, a)
	_ring_mix = float(c[4])
	_boom_mix = float(c[5])
	# a random split between the modes keeps repeats from sounding stamped out
	var split := 0.5 + 0.25 * _rand()
	_r1 += a * _ring_kick1 * split
	_r2 += a * _ring_kick2 * (1.0 - split)
	_ring_live = int(5.0 * RING_DECAY * mix_rate)
	_cl_left -= 1
	pop_bangs += 1
	_cl_amp *= 0.85  # each bang of a burble a little softer than the last
	_cl_wait = maxi(int(lerpf(float(c[2]), float(c[3]), absf(_rand())) * mix_rate), 1)

## White noise in [-1, 1]. Inline LCG: a RandomNumberGenerator call per
## sample is noticeably slower in GDScript.
func _rand() -> float:
	_noise = (_noise * 1103515245 + 12345) & 0x7fffffff
	return _noise / 1073741823.5 - 1.0
