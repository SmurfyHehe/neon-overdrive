# Turbo voice synth (B1, 2026-10-09): the spool whistle, the valve and the
# between-gears "pssh", rendered in code (no recordings) into its own stream on
# the Turbo bus, so the Turbo volume slider is a real bus fader. Until B1 the
# whistle was a term inside EngineSynth's mix on the Engine bus.
#
# Pure DSP, no nodes: EngineAudio sets boost (0..1 of the car's max) and
# boost_max_bar each frame, calls vent() on a lift and shift_vent() between
# gears, and renders blocks on its worker thread. The per-sample loop is written
# inline like EngineSynth's: a function call per sample is slow in GDScript.
#
# The voice (TurboVoice) sets the whistle's range, its second partial, how airy
# it is, its flutter, and which valve the part has: "recirc", "atmo" or
# "flutter" (see turbo_voice.gd for what each sounds like).
extends RefCounted
class_name TurboSynth

enum Valve { RECIRC, ATMO, FLUTTER, NONE }
const VALVES := {"recirc": Valve.RECIRC, "atmo": Valve.ATMO, "flutter": Valve.FLUTTER, "none": Valve.NONE}
## A vent shorter than this after the last one is the same event seen twice
## (GEVP's one-tick throttle cut and the shift, or the shift and a lift).
const VENT_GAP := 0.15

var mix_rate := 44100.0
var volume := 0.5
## Fraction of max boost, 0..1, set by EngineAudio before each block.
var boost := 0.0
## The Tuner's boost slider (bar): more bar, further the whistle climbs.
var boost_max_bar := 0.7
## Engine rpm as a fraction of max, set by EngineAudio: the blower's pitch and
## the sequential handover follow it (the setups in TurboVoice.KINDS).
var rpm_norm := 0.0

# voice
var hz_low := 3000.0
var hz_span := 4000.0
var partial := 1.37
var partial_mix := 0.45
var air := 0.5
var flutter_hz := 6.5
var flutter_depth := 0.012
var level := 1.0
var valve := Valve.RECIRC
var valve_level := 0.6
var detune := 0.0          # twin: a second whistle this far above the first, beating
var blower := 0.0          # roots / twincharger: whine level
var blower_hz_max := 1500.0
var blower_off_from := 2.0 # twincharger: the blower is bypassed between these rpm fractions
var blower_off_to := 2.0
var stage2_at := 2.0       # sequential: the big turbo joins above this rpm fraction
var stage2_hz_low := 2800.0
var stage2_hz_span := 2600.0

# spool state
var _boost_s := 0.0
var _rpm_s := 0.0
var _ph1 := 0.0
var _ph2 := 0.0
var _ph3 := 0.0  # the twin's second whistle
var _ph4 := 0.0  # the sequential's big turbo
var _bph := 0.0  # the blower
var _stage2_s := 0.0
var _blower_s := 0.0
var _flutter_ph := 0.0
var _air_lp := 0.0
# vent state
var _vent_env := 0.0
var _vent_decay := 1.0
var _vent_att := 1.0
var _vent_att_step := 1.0
var _vent_lp := 0.0
var _vent_hiss_ph := 0.0
var _stutter_ph := 0.0
var _since_vent := 9.0  # seconds since the last vent started
var _vent_is_shift := false
var _noise := 12345
## Counters for tests: lift vents, shift vents.
var vents := 0
var shift_vents := 0

func apply_voice(v: Dictionary) -> void:
	hz_low = float(v.get("hz_low", hz_low))
	hz_span = float(v.get("hz_span", hz_span))
	partial = float(v.get("partial", partial))
	partial_mix = float(v.get("partial_mix", partial_mix))
	air = float(v.get("air", air))
	flutter_hz = float(v.get("flutter_hz", flutter_hz))
	flutter_depth = float(v.get("flutter_depth", flutter_depth))
	level = float(v.get("level", level))
	valve = VALVES.get(String(v.get("valve", "recirc")), Valve.RECIRC)
	valve_level = float(v.get("valve_level", valve_level))
	detune = float(v.get("detune", 0.0))
	blower = float(v.get("blower", 0.0))
	blower_hz_max = float(v.get("blower_hz_max", 1500.0))
	blower_off_from = float(v.get("blower_off_from", 2.0))
	blower_off_to = float(v.get("blower_off_to", 2.0))
	stage2_at = float(v.get("stage2_at", 2.0))
	stage2_hz_low = float(v.get("stage2_hz_low", 2800.0))
	stage2_hz_span = float(v.get("stage2_hz_span", 2600.0))

## The valve opens on a throttle lift: a "pssh" of 0.3 to 1 s whose size and
## length follow how hot the boost was (strength 0..1). False when it is the
## vent already playing, seen again within VENT_GAP. A lift that lands in the
## same gap as a shift vent (GEVP shifts on the lift) upgrades it to the long
## lift vent: one event, the longer voice.
func vent(strength: float) -> bool:
	if _since_vent < VENT_GAP:
		if not _vent_is_shift:
			return false
		shift_vents -= 1
		_vent_env = 0.0  # the restart below takes it over
	_start_vent(strength, 1.0)
	_vent_is_shift = false
	vents += 1
	return true

## The valve between gears, on boost: the same voice, shorter and sharper (the
## throttle is only off for the shift). One per shift; a lift vent right after
## it is folded in by VENT_GAP.
func shift_vent(strength: float) -> bool:
	if _since_vent < VENT_GAP:
		return false
	_start_vent(strength, 0.55)
	_vent_is_shift = true
	shift_vents += 1
	return true

func _start_vent(strength: float, length: float) -> void:
	var st := clampf(strength, 0.0, 1.0)
	_since_vent = 0.0
	if valve == Valve.NONE:
		return  # a blower has nothing to vent
	if st <= _vent_env:
		return
	_vent_env = st
	# Level falls below 0.01 after about 4.6 time constants: 0.3 s at the
	# weakest lift vent, 0.9 s at the strongest; a shift vent is a bit over half.
	var tau := (0.07 + 0.12 * st) * length
	if valve == Valve.FLUTTER:
		tau *= 1.25  # the surge takes a few beats to die
	_vent_decay = exp(-1.0 / (tau * mix_rate))
	_vent_att = 0.0
	_vent_att_step = 1.0 / ((0.002 if length < 1.0 else 0.004) * mix_rate)
	_stutter_ph = 0.0

## One block. Silent at boost 0 with no vent playing (and no blower turning).
func render(frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	_since_vent += frames / mix_rate
	var blower_on := blower > 0.0 and (rpm_norm > 0.01 or _blower_s > 0.001)
	if boost < 0.005 and _boost_s < 0.005 and _vent_env < 0.01 and not blower_on:
		_boost_s = boost
		_rpm_s = rpm_norm
		return out  # zeros
	var rate := mix_rate
	var boost_k := 1.0 / (0.02 * rate)
	var slow_k := 1.0 / (0.08 * rate)
	var bar_k := clampf(0.6 + 0.4 * boost_max_bar / 0.7, 0.6, 1.5)
	var span := hz_span * bar_k
	var span2 := stage2_hz_span * bar_k
	# the sequential handover and the twincharger bypass follow rpm, per block
	var stage2_target := clampf((rpm_norm - stage2_at) / 0.1, 0.0, 1.0)
	var blower_target := 0.0
	if blower > 0.0:
		blower_target = blower
		if rpm_norm > blower_off_from and rpm_norm < blower_off_to:
			blower_target = 0.0
	var flutter_step := TAU * flutter_hz / rate
	var vent_k := 0.06 if valve == Valve.RECIRC else 0.2
	var vent_gain := (0.5 if valve == Valve.RECIRC else 0.7) * valve_level
	var hiss_step := TAU * 5500.0 / rate
	var bs := _boost_s
	var rs := _rpm_s
	var ph1 := _ph1
	var ph2 := _ph2
	var ph3 := _ph3
	var ph4 := _ph4
	var bph := _bph
	var st2 := _stage2_s
	var bl := _blower_s
	var fph := _flutter_ph
	var alp := _air_lp
	var env := _vent_env
	var att := _vent_att
	var vlp := _vent_lp
	var hph := _vent_hiss_ph
	var sph := _stutter_ph
	var noise := _noise
	for i in frames:
		bs += (boost - bs) * boost_k
		rs += (rpm_norm - rs) * boost_k
		st2 += (stage2_target - st2) * slow_k
		bl += (blower_target - bl) * slow_k
		noise = (noise * 1103515245 + 12345) & 0x7fffffff
		var n := noise / 1073741823.5 - 1.0
		var s := 0.0
		# the valve: noise shaped by the kind, on a fast attack and a set decay
		var gate := 0.0
		if env > 0.01:
			att = minf(att + _vent_att_step, 1.0)
			vlp += vent_k * (n - vlp)
			var e := env * att
			if valve == Valve.RECIRC:
				# a dull puff back into the intake
				s += vlp * 2.0 * vent_gain * e
			elif valve == Valve.ATMO:
				# bright hiss plus a thin tone that rings off the valve body
				hph += hiss_step
				s += ((n - vlp) + 0.25 * sin(hph) * e * e) * vent_gain * e
			else:
				# compressor surge: the noise chopped at a rate that falls as
				# the surge dies (26 Hz down to 14), and the whistle dragged down
				sph += TAU * (14.0 + 12.0 * e) / rate
				var g := 0.5 + 0.5 * sin(sph)
				gate = g * g * g
				s += (n - vlp) * 1.6 * gate * vent_gain * e
			env *= _vent_decay
		# the spool: a whistle whose pitch and level climb with boost, a second
		# inharmonic partial (turbine vs compressor wheel), a slow flutter and air
		if bs > 0.005:
			fph += flutter_step
			var f0 := (hz_low + span * bs) * (1.0 + flutter_depth * sin(fph))
			if gate > 0.0:
				f0 *= 1.0 - 0.3 * gate * env
			ph1 += TAU * f0 / rate
			ph2 += TAU * f0 * partial / rate
			alp += 0.3 * (n - alp)
			var w := sin(ph1) + partial_mix * sin(ph2) + (n - alp) * air
			if detune > 0.0:
				# the twin's other turbo, a shade sharper: the two beat
				ph3 += TAU * f0 * (1.0 + detune) / rate
				w += 0.7 * sin(ph3)
			if st2 > 0.001:
				# the sequential's big turbo under the small one
				ph4 += TAU * (stage2_hz_low + span2 * bs) * (1.0 + 1.6 * flutter_depth * sin(fph * 0.7)) / rate
				w += (sin(ph4) + (n - alp) * 0.9) * 1.3 * st2
			s += w * 0.2 * bs * bs * level
		if bl > 0.001 and rs > 0.005:
			# the blower: lobes passing the housing, a buzz whose pitch follows
			# the crank; present off boost, fuller on it
			bph += TAU * blower_hz_max * rs / rate
			var b := sin(bph) + 0.5 * sin(2.0 * bph) + 0.25 * sin(3.0 * bph)
			s += b * 0.12 * bl * rs * (0.35 + 0.65 * bs)
		s = tanh(s * 1.5)
		var v := s * volume
		out[i] = Vector2(v, v)
	if ph1 > 1.0e6 or bph > 1.0e6:  # keep the phases small; a large float loses the fraction
		ph1 = fmod(ph1, TAU)
		ph2 = fmod(ph2, TAU)
		ph3 = fmod(ph3, TAU)
		ph4 = fmod(ph4, TAU)
		bph = fmod(bph, TAU)
		hph = fmod(hph, TAU)
	_boost_s = bs
	_rpm_s = rs
	_ph1 = ph1
	_ph2 = ph2
	_ph3 = ph3
	_ph4 = ph4
	_bph = bph
	_stage2_s = st2
	_blower_s = bl
	_flutter_ph = fmod(fph, TAU)
	_air_lp = alp
	_vent_env = env
	_vent_att = att
	_vent_lp = vlp
	_vent_hiss_ph = hph
	_stutter_ph = sph
	_noise = noise
	return out
