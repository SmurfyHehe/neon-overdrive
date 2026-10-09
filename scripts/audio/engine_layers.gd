# Mechanical layers on top of EngineSynth, per car (kei rework, 2026-10-09).
# EngineSynth is the combustion note: firing pulses through the pipe's
# resonances. Small engines are heard mostly through everything around the
# combustion: the induction whir, the gearbox, a heat shield buzzing, and a
# tailpipe too thin to carry any boom. Those live here, keyed from the same
# "engine_voice" dictionary (engine_voice.gd), and run as a second pass over
# the synth's block so the synth's hot loop (the CPU audio work, PR #315, and
# the turbo voice, PR #312) stays untouched. A voice that sets none of these
# keys skips the pass entirely: every car but the kei costs nothing here.
#
# Keys (all optional; 0 = off):
# - thin 0..1, thin_hz: how much of the engine note goes through a high-pass
#   at thin_hz. A pea-shooter exhaust on a 0.66 l triple has no boom to give.
# - buzz 0..1, buzz_harm, buzz_q: a resonance that TRACKS rpm, sitting on the
#   buzz_harm-th harmonic of the firing rate. The synth's pipe resonances stay
#   put; this one climbs with the revs, which is what makes a small engine
#   sound like it is straining and "buzzy" rather than merely high.
# - intake 0..1: induction whir, band-passed noise whose centre climbs with
#   rpm and whose level follows the throttle (the throttle plate is what
#   opens it).
# - whine 0..1, whine_teeth: gear whine, a tone at engine rev/s x teeth with
#   its second harmonic, louder under load and on overrun (small gearboxes
#   are not quiet). DrivelineAudio has a shared, soft whine for every car at
#   8 teeth; this one is the car's own, higher and nearer.
# - rattle 0..1: sparse metallic clicks (heat shield, valvetrain), densest at
#   idle and light load, gone near the limiter where the note covers them.
extends RefCounted
class_name EngineLayers

const KEYS := ["thin", "thin_hz", "buzz", "buzz_harm", "buzz_q", "intake", "whine",
		"whine_teeth", "rattle"]

var mix_rate := 44100.0
var idle_rpm := 1000.0
var max_rpm := 7000.0
var cylinders := 4
var thin := 0.0
var thin_hz := 180.0
var buzz := 0.0
var buzz_harm := 2.0
var buzz_q := 4.0
var intake := 0.0
var whine := 0.0
var whine_teeth := 21.0
var rattle := 0.0
## True once apply_voice() saw any layer above zero; process() is a no-op otherwise.
var active := false
## Clicks fired so far (tests read it).
var rattle_clicks := 0

var _rpm := -1.0
var _thr := 0.0
var _noise := 7777
# thin: two cascaded one-pole low-passes (hp = x - their sum)
var _thin_lp := 0.0
var _thin_lp2 := 0.0
# buzz band-pass state
var _zx1 := 0.0
var _zx2 := 0.0
var _zy1 := 0.0
var _zy2 := 0.0
# intake band-pass state
var _ix1 := 0.0
var _ix2 := 0.0
var _iy1 := 0.0
var _iy2 := 0.0
var _whine_ph := 0.0
# rattle: samples to the next click, click envelope, its high-pass and ring
var _rt_wait := 0
var _rt_env := 0.0
var _rt_lp := 0.0
var _rt_r := 0.0
var _rt_rp := 0.0
var _rt_kick := 0.0

const RATTLE_DECAY := 0.0025   # s, one click's envelope
const RATTLE_RING_HZ := 3900.0 # the shield's own ping
## One cycle of the whine's waveform (fundamental plus a softer second
## harmonic), read by phase: one table lookup a sample instead of two sin()
## calls, which matters in a GDScript loop.
const WHINE_TABLE_N := 2048
static var _whine_table := _make_whine_table()

static func _make_whine_table() -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(WHINE_TABLE_N)
	for i in WHINE_TABLE_N:
		var ph := TAU * i / WHINE_TABLE_N
		t[i] = sin(ph) * 0.7 + sin(ph * 2.0) * 0.3
	return t

## Reads this car's layer keys from its "engine_voice" dictionary.
func apply_voice(v: Dictionary) -> void:
	cylinders = maxi(int(v.get("cylinders", cylinders)), 1)
	thin = clampf(float(v.get("thin", thin)), 0.0, 1.0)
	thin_hz = clampf(float(v.get("thin_hz", thin_hz)), 20.0, 2000.0)
	buzz = clampf(float(v.get("buzz", buzz)), 0.0, 1.0)
	buzz_harm = clampf(float(v.get("buzz_harm", buzz_harm)), 0.5, 8.0)
	buzz_q = clampf(float(v.get("buzz_q", buzz_q)), 0.5, 20.0)
	intake = clampf(float(v.get("intake", intake)), 0.0, 1.0)
	whine = clampf(float(v.get("whine", whine)), 0.0, 1.0)
	whine_teeth = clampf(float(v.get("whine_teeth", whine_teeth)), 4.0, 60.0)
	rattle = clampf(float(v.get("rattle", rattle)), 0.0, 1.0)
	active = thin > 0.0 or buzz > 0.0 or intake > 0.0 or whine > 0.0 or rattle > 0.0

## Band-pass coefficients [b0, a1, a2] for a centre and Q (same form as EngineSynth's).
func _bp(hz: float, q: float) -> PackedFloat64Array:
	var w := TAU * clampf(hz, 20.0, mix_rate * 0.45) / mix_rate
	var a := sin(w) / (2.0 * q)
	return PackedFloat64Array([a / (1.0 + a), -2.0 * cos(w) / (1.0 + a), (1.0 - a) / (1.0 + a)])

## The layers, in place over one of EngineSynth's blocks; returns the same
## block. rpm and throttle glide across it like the synth's do. `redline` is
## unused today (the limiter's stutter is the synth's), kept for symmetry.
func process(buf: PackedVector2Array, rpm: float, throttle: float, _redline: bool) -> PackedVector2Array:
	var frames := buf.size()
	if not active or frames <= 0:
		return buf
	if _rpm < 0.0:
		_rpm = rpm
	# rpm glides across the block (the whine's pitch must not step); the
	# throttle-driven gains are held for the block, 11 ms at 512 frames.
	var rpm_step := (rpm - _rpm) / frames
	var thr_c := 0.5 * (_thr + throttle)
	_thr = throttle
	var rpm_norm := clampf((rpm - idle_rpm) / (max_rpm - idle_rpm), 0.0, 1.0)

	# Per block: the tracking resonance and the intake band follow rpm.
	var thin_k := 1.0 - exp(-TAU * thin_hz / mix_rate)
	# what the high-pass takes away in level comes back as makeup gain, so a
	# thin car is thin, not quiet; at idle, where nearly everything sits under
	# the cut, it needs the most
	var thin_makeup := 1.0 + thin * (0.4 + 0.8 * (1.0 - rpm_norm))
	var firing_hz := rpm / 120.0 * cylinders
	var z := _bp(firing_hz * buzz_harm, buzz_q)
	var zb0 := z[0]
	var za1 := z[1]
	var za2 := z[2]
	var ic := _bp(500.0 + 2600.0 * rpm_norm, 2.0)
	var ib0 := ic[0]
	var ia1 := ic[1]
	var ia2 := ic[2]
	var intake_gain := intake * 1.4 * (0.3 + 0.7 * rpm_norm) * (0.12 + 0.88 * thr_c)
	var overrun := throttle < 0.1 and rpm_norm > 0.25
	var whine_gain := whine * 0.16 * (0.15 + 0.85 * rpm_norm) * (0.35 + 0.65 * maxf(throttle, 0.6 if overrun else 0.0))
	# Rattle: clicks per second, dense at idle and light load, thin near the top.
	var rt_rate := rattle * (5.0 + 16.0 * (1.0 - rpm_norm) * (1.0 - rpm_norm)) * (1.0 - 0.5 * throttle)
	var rt_p := rt_rate / mix_rate
	var rt_k := exp(-1.0 / (RATTLE_DECAY * mix_rate))
	var rt_ring_r := exp(-1.0 / (0.004 * mix_rate))
	var rt_w := TAU * RATTLE_RING_HZ / mix_rate
	var rt_k1 := 2.0 * rt_ring_r * cos(rt_w)
	var rt_k2 := rt_ring_r * rt_ring_r
	_rt_kick = sin(rt_w)
	var rt_gain := rattle * 0.35
	var buzz_mix := buzz * 1.1 * (0.5 + 0.5 * thr_c)

	var rpm_c := _rpm
	var noise := _noise
	var thin_lp := _thin_lp
	var thin_lp2 := _thin_lp2
	var tbl := _whine_table
	var tbl_scale := WHINE_TABLE_N / TAU
	var zx1 := _zx1
	var zx2 := _zx2
	var zy1 := _zy1
	var zy2 := _zy2
	var ix1 := _ix1
	var ix2 := _ix2
	var iy1 := _iy1
	var iy2 := _iy2
	var wph := _whine_ph
	var rt_wait := _rt_wait
	var rt_env := _rt_env
	var rt_lp := _rt_lp
	var rt_r := _rt_r
	var rt_rp := _rt_rp
	var dthin := thin > 0.0
	var dbuzz := buzz > 0.0
	var dintake := intake > 0.0
	var dwhine := whine > 0.0
	var drattle := rattle > 0.0
	var wstep0 := TAU * whine_teeth / 60.0 / mix_rate
	for i in frames:
		rpm_c += rpm_step
		var x := buf[i].x
		var s := x
		if dthin:
			# two one-pole stages: 12 dB/oct, the boom really goes
			thin_lp += thin_k * (x - thin_lp)
			thin_lp2 += thin_k * (thin_lp - thin_lp2)
			s = (x - thin * (2.0 * thin_lp - thin_lp2)) * thin_makeup
		if dbuzz:
			var zy := zb0 * s - zb0 * zx2 - za1 * zy1 - za2 * zy2
			zx2 = zx1
			zx1 = s
			zy2 = zy1
			zy1 = zy
			s += zy * buzz_mix
		# one noise sample a frame, shared by the intake and the clicks
		noise = (noise * 1103515245 + 12345) & 0x7fffffff
		var n := noise / 1073741823.5 - 1.0
		if dintake:
			var iy := ib0 * n - ib0 * ix2 - ia1 * iy1 - ia2 * iy2
			ix2 = ix1
			ix1 = n
			iy2 = iy1
			iy1 = iy
			s += iy * intake_gain
		if dwhine:
			wph += wstep0 * rpm_c
			if wph > TAU:
				wph -= TAU
			s += tbl[int(wph * tbl_scale) & (WHINE_TABLE_N - 1)] * whine_gain
		if drattle:
			if rt_p > 0.0:
				rt_wait -= 1
				if rt_wait <= 0:
					var a := 0.3 + 0.7 * absf(n)
					rt_env = maxf(rt_env, a)
					rt_r += a * _rt_kick
					rattle_clicks += 1
					# gaps vary a lot: a shield buzzes in bursts, not on a clock
					noise = (noise * 1103515245 + 12345) & 0x7fffffff
					rt_wait = maxi(int((0.15 + 1.7 * (noise / 2147483647.0)) / rt_p), 1)
			if rt_env > 0.001 or absf(rt_r) > 0.001:
				rt_lp += 0.3 * (n - rt_lp)
				var r := rt_k1 * rt_r - rt_k2 * rt_rp
				rt_rp = rt_r
				rt_r = r
				s += ((n - rt_lp) * rt_env + r * 0.6) * rt_gain
				rt_env *= rt_k
		# the layers can stack over the synth's clip; round the top softly
		if s > 0.8:
			s = 0.8 + 0.2 * tanh((s - 0.8) * 5.0)
		elif s < -0.8:
			s = -0.8 - 0.2 * tanh((-s - 0.8) * 5.0)
		buf[i] = Vector2(s, s)
	_rpm = rpm_c
	_noise = noise
	_thin_lp = thin_lp
	_thin_lp2 = thin_lp2
	_zx1 = zx1
	_zx2 = zx2
	_zy1 = zy1
	_zy2 = zy2
	_ix1 = ix1
	_ix2 = ix2
	_iy1 = iy1
	_iy2 = iy2
	_whine_ph = wph
	_rt_wait = rt_wait
	_rt_env = rt_env
	_rt_lp = rt_lp
	_rt_r = rt_r
	_rt_rp = rt_rp
	return buf
