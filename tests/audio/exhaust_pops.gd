extends SceneTree

# Pop voice test (2026-10-07, exhaust-sound-research-2026-10-07 option A).
# Renders EngineSynth offline and checks the new crackle/pop voice:
# - overrun pops come in clusters (a burble: more bangs than requests)
# - the limiter bangs (pops 1, held on the limiter)
# - anti-lag makes a dense crackle on a lift even with the pops knob at 0
# - an upshift cut bangs only at flame >= ExhaustFlames.UPSHIFT_FLAME_MIN, and
#   never hands out a flame event (ExhaustFlames queues its own upshift fire)
# - each bang rings the pipe: sound is still there 60-150 ms after the bang,
#   and the ring follows body_hz (a deeper pipe rings lower)
# - no pops requested: the voice never starts; nothing goes non-finite
# - cost: prints how much the voice adds to render time (anti-lag crackle vs
#   none), and fails if it more than doubles a block
# Writes WAVs to user://exhaust_pop_*.wav for listening (never played).
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/audio/exhaust_pops.gd

const BLOCK := 512

var fails := 0

func _initialize() -> void:
	# --- burble: 3 s of overrun at 5500 rpm, pops 0.3, no anti-lag
	var s := _synth(ExhaustTune.new(0.5, 0.3, 0.3, 0.5))
	var burble := _render(s, 3.0, 5500.0, 0.0, false, "burble")
	print("burble: %d clusters, %d bangs" % [s.pop_clusters, s.pop_bangs])
	_check(s.pop_clusters > 0, "pops 0.3 on a lift should start clusters")
	_check(s.pop_bangs >= s.pop_clusters * 2, "a burble cluster is at least two bangs (%d bangs, %d clusters)" % [s.pop_bangs, s.pop_clusters])
	_check(burble.finite, "burble: non-finite sample")

	# --- limiter: 2 s held on the limiter at full throttle, pops 1
	s = _synth(ExhaustTune.new(0.5, 0.3, 1.0, 0.5))
	var lim := _render(s, 2.0, 7000.0, 1.0, true, "limiter")
	print("limiter: %d clusters, %d bangs" % [s.pop_clusters, s.pop_bangs])
	_check(s.pop_clusters > 0, "the limiter with pops 1 should bang")
	_check(lim.finite, "limiter: non-finite sample")

	# --- anti-lag: pops 0, switch on vs off
	s = _synth(ExhaustTune.new(0.5, 0.3, 0.0, 0.5, 0.0))
	_render(s, 2.0, 6000.0, 0.0, false, "")
	_check(s.pop_clusters == 0 and s.pop_bangs == 0, "pops 0, anti-lag off: the voice must stay silent (%d)" % s.pop_bangs)
	s = _synth(ExhaustTune.new(0.5, 0.3, 0.0, 0.5, 1.0))
	var al := _render(s, 2.0, 6000.0, 0.0, false, "antilag")
	var al_rate := s.pop_bangs / 2.0
	print("anti-lag: %d clusters, %d bangs (%.0f bangs/s)" % [s.pop_clusters, s.pop_bangs, al_rate])
	_check(al_rate >= 20.0, "anti-lag should crackle densely (%.0f bangs/s)" % al_rate)
	_check(al.finite, "anti-lag: non-finite sample")

	# --- upshift cut: gated by the flame setting, sound only
	s = _synth(ExhaustTune.new(0.5, 0.3, 0.3, 0.2))
	s.shift_cut(1.0)
	_render(s, 0.3, 5000.0, 1.0, false, "")
	_check(s.upshift_clusters == 0, "flame 0.2 is below UPSHIFT_FLAME_MIN: no upshift bang (%d)" % s.upshift_clusters)
	s = _synth(ExhaustTune.new(0.5, 0.3, 0.3, 0.6))
	_render(s, 0.2, 5000.0, 1.0, false, "")  # settle
	s.take_flames()
	s.shift_cut(1.0)
	var up := _render(s, 0.4, 5000.0, 1.0, false, "upshift")
	print("upshift: %d clusters, %d bangs, flame %.2f" % [s.upshift_clusters, s.pop_bangs, up.flame])
	_check(s.upshift_clusters == 1, "flame 0.6: one upshift bang cluster (%d)" % s.upshift_clusters)
	_check(up.flame == 0.0, "the upshift bang must not hand out a flame event (%.2f)" % up.flame)

	# --- pipe ring: one bang alone (idle-ish, no engine pulses to mask it)
	var ring := _ring_probe(110.0)
	var ring_low := _ring_probe(70.0)
	print("ring: tail rms %.4f, crossings/s %.0f (body 110) vs %.0f (body 70)" % [ring.tail, ring.hz, ring_low.hz])
	_check(ring.tail > 0.01, "the pipe should still ring 60-150 ms after a bang (rms %.4f)" % ring.tail)
	_check(ring_low.hz < ring.hz, "a deeper pipe (body 70 Hz) should ring lower (%.0f vs %.0f)" % [ring_low.hz, ring.hz])

	# --- flames still come from pop requests (the 60 ms sync path is unchanged)
	s = _synth(ExhaustTune.new(0.5, 0.3, 1.0, 1.0))
	var fl := _render(s, 2.0, 6000.0, 0.0, false, "")
	_check(fl.flame_events > 0 and fl.flame <= 1.0, "pops 1 + flame 1 should still spit flames (%d)" % fl.flame_events)

	# --- cost: anti-lag crackle (busiest) vs the same overrun with the voice idle
	var t_off := _time(ExhaustTune.new(0.5, 0.3, 0.0, 0.5, 0.0))
	var t_on := _time(ExhaustTune.new(0.5, 0.3, 0.0, 0.5, 1.0))
	print("render cost per 512-frame block: idle voice %.0f us, anti-lag crackle %.0f us (+%.0f%%)" % [t_off, t_on, 100.0 * (t_on / t_off - 1.0)])
	_check(t_on < t_off * 2.0, "the pop voice should not double a block's cost (%.0f vs %.0f us)" % [t_on, t_off])

	print("exhaust_pops: ", "PASS" if fails == 0 else "FAIL")
	quit(1 if fails > 0 else 0)

func _synth(t: ExhaustTune) -> EngineSynth:
	var s := EngineSynth.new()
	s.tune = t
	return s

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)

# Renders `secs` at a fixed rpm/throttle; returns stats, writes a WAV if labelled.
func _render(s: EngineSynth, secs: float, rpm: float, thr: float, redline: bool, label: String) -> Dictionary:
	var all := PackedFloat32Array()
	var n := int(secs * s.mix_rate)
	var done := 0
	var flame := 0.0
	var flame_events := 0
	var finite := true
	while done < n:
		var k := mini(BLOCK, n - done)
		for f in s.render(k, rpm, thr, redline):
			if is_nan(f.x) or is_inf(f.x):
				finite = false
			all.append(f.x)
		var fl := s.take_flames()
		if fl > 0.0:
			flame_events += 1
			flame = maxf(flame, fl)
		done += k
	if label != "":
		_wav(all, s.mix_rate, label)
	return {"finite": finite, "flame": flame, "flame_events": flame_events, "samples": all}

# One upshift bang on a near-silent engine: rms of 60-150 ms after it, and the
# tail's zero crossings per second (twice the ring frequency, roughly).
func _ring_probe(body: float) -> Dictionary:
	var s := _synth(ExhaustTune.new(0.5, 0.0, 0.0, 1.0))
	s.body_hz = body
	s.volume = 0.5
	s._cl_kind = EngineSynth.PopKind.UPSHIFT
	s._start_cluster(EngineSynth.PopKind.UPSHIFT, 1.0)
	s._cl_left = 1  # exactly one bang
	var out: PackedFloat32Array = _render(s, 0.2, 1000.0, 0.0, false, "ring_%d" % int(body)).samples
	# the engine idles underneath; subtract a bang-free render of the same engine
	var base := _synth(ExhaustTune.new(0.5, 0.0, 0.0, 1.0))
	base.body_hz = body
	var ref: PackedFloat32Array = _render(base, 0.2, 1000.0, 0.0, false, "").samples
	var a := int(0.06 * s.mix_rate)
	var b := int(0.15 * s.mix_rate)
	var sum := 0.0
	var cross := 0
	var prev := 0.0
	for i in range(a, b):
		var v := out[i] - ref[i]
		sum += v * v
		if (v > 0.0) != (prev > 0.0):
			cross += 1
		prev = v
	return {"tail": sqrt(sum / (b - a)), "hz": cross / (0.09 * 2.0)}

func _time(t: ExhaustTune) -> float:
	var s := _synth(t)
	for i in 20:
		s.render(BLOCK, 6000.0, 0.0, false)  # warm up into the overrun
	var t0 := Time.get_ticks_usec()
	var blocks := 200
	for i in blocks:
		s.render(BLOCK, 6000.0, 0.0, false)
	return float(Time.get_ticks_usec() - t0) / blocks

func _wav(all: PackedFloat32Array, sr: float, label: String) -> void:
	var bytes := PackedByteArray()
	bytes.resize(all.size() * 2)
	for i in all.size():
		bytes.encode_s16(i * 2, int(clampf(all[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(sr)
	wav.data = bytes
	wav.save_to_wav("user://exhaust_pop_%s.wav" % label)
