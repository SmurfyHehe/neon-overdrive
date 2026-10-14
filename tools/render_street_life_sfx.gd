extends SceneTree

# Renders the three small sounds of the title's street life (menu street
# life M8 + rats M9, 2026-10-11), synthesised here, nothing recorded:
#
#   blind_snap.wav   the neighbour's blind snapping up: a short cord zip and a
#                    soft clack with a little thump (0.28 s)
#   wing_clap.wav    the pigeons lifting off: five soft wing claps, quick and
#                    then thinning, with a low whump under each (0.55 s)
#   rat_squeak.wav   a rat bolting: a few claws scratching, then a thin
#                    two-note squeak (0.42 s)
#
#   godot --headless --audio-driver Dummy --path . -s res://tools/render_street_life_sfx.gd
#
# Writes assets/ui/sfx/*.wav (mono, 44.1 kHz). Played very quietly on the UI
# bus (title_kerbside.gd sets the dB).

const OUT := "res://assets/ui/sfx/"
const RATE := 44100

func _init() -> void:
	_write("blind_snap", _blind_snap(), 0.55)
	_write("wing_clap", _wing_clap(), 0.6)
	_write("rat_squeak", _rat_squeak(), 0.5)
	quit()

func _write(name: String, s: PackedFloat32Array, peak: float) -> void:
	s = AudioDsp.normalise(s, peak)
	var path := OUT + name + ".wav"
	AudioDsp.to_wav(s, RATE, false).save_to_wav(ProjectSettings.globalize_path(path))
	print("wrote %s: %.2f s" % [path, float(s.size()) / RATE])

func _buf(secs: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(secs * RATE))
	return out

## A burst of noise at `at` seconds, `len` seconds long, exponential decay.
func _burst(out: PackedFloat32Array, rng: RandomNumberGenerator, at: float, len: float, amp: float, decay := 4.0) -> void:
	var i0 := int(at * RATE)
	var n := int(len * RATE)
	for i in n:
		if i0 + i >= out.size():
			break
		out[i0 + i] += (rng.randf() * 2.0 - 1.0) * amp * exp(-float(i) / float(n) * decay)

## A decaying sine at `at`.
func _thump(out: PackedFloat32Array, at: float, len: float, hz: float, amp: float) -> void:
	var i0 := int(at * RATE)
	var n := int(len * RATE)
	for i in n:
		if i0 + i >= out.size():
			break
		var t := float(i) / RATE
		out[i0 + i] += sin(TAU * hz * t) * amp * exp(-float(i) / float(n) * 5.0)

func _filter(s: PackedFloat32Array, f) -> PackedFloat32Array:
	for i in s.size():
		s[i] = f.step(s[i])
	return s

func _blind_snap() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# the cord: a zip, 70 ms of noise rising through a band-pass
	var zip := _buf(0.28)
	var n := int(0.07 * RATE)
	for i in n:
		zip[i] = (rng.randf() * 2.0 - 1.0) * 0.5 * (0.3 + 0.7 * float(i) / float(n))
	var f := AudioDsp.bp(RATE, 1800.0, 2.0)
	var zip_hz := 900.0
	for i in n:
		# the band slides up as the blind winds faster
		if i % 64 == 0:
			zip_hz = 900.0 + 1800.0 * float(i) / float(n)
			f = AudioDsp.bp(RATE, zip_hz, 2.5)
		zip[i] = f.step(zip[i])
	# the clack at the top: a click, a soft thump, a touch of rattle after
	_burst(zip, rng, 0.072, 0.008, 0.9, 3.0)
	_thump(zip, 0.072, 0.05, 160.0, 0.35)
	_burst(zip, rng, 0.095, 0.03, 0.18, 6.0)
	_burst(zip, rng, 0.14, 0.02, 0.08, 6.0)
	return _filter(zip, AudioDsp.hp(RATE, 300.0))

func _wing_clap() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var out := _buf(0.55)
	# five claps, the first two hard and close, then thinning out; each a
	# short band-passed noise with a low whump of air under it
	var t := 0.01
	var gaps := [0.07, 0.075, 0.09, 0.11, 0.13]
	for k in 5:
		var amp := 1.0 - 0.14 * float(k)
		var clap := _buf(0.05)
		_burst(clap, rng, 0.0, 0.016, amp, 3.5)
		clap = _filter(clap, AudioDsp.bp(RATE, 1100.0 + rng.randf() * 300.0, 1.2))
		var i0 := int(t * RATE)
		for i in clap.size():
			if i0 + i < out.size():
				out[i0 + i] += clap[i]
		_thump(out, t, 0.04, 85.0, 0.5 * amp)
		t += gaps[k]
	# a soft flutter tail: the last beats as the birds clear the arm
	for k in 3:
		_burst(out, rng, t, 0.012, 0.22 - 0.05 * float(k), 3.0)
		_thump(out, t, 0.03, 80.0, 0.12)
		t += 0.06
	return _filter(out, AudioDsp.hp(RATE, 120.0))

func _rat_squeak() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	var out := _buf(0.42)
	# claws: four quick scratches, dry and high
	var t := 0.005
	for k in 4:
		var scr := _buf(0.03)
		_burst(scr, rng, 0.0, 0.014 + rng.randf() * 0.01, 0.6 - 0.08 * float(k), 3.0)
		scr = _filter(scr, AudioDsp.hp(RATE, 3200.0))
		var i0 := int(t * RATE)
		for i in scr.size():
			if i0 + i < out.size():
				out[i0 + i] += scr[i]
		t += 0.028 + rng.randf() * 0.012
	# the squeak: a thin chirp, up then a short second note, with vibrato
	var s0 := int(0.19 * RATE)
	var len := int(0.11 * RATE)
	var ph := 0.0
	for i in len:
		var f := float(i) / float(len)
		var hz := 3300.0 + 1300.0 * smoothstep(0.0, 0.5, f) - 500.0 * smoothstep(0.6, 1.0, f)
		hz += 120.0 * sin(TAU * 38.0 * float(i) / RATE)
		ph += TAU * hz / RATE
		var env := sin(PI * f)
		env *= env
		var v := sin(ph) * 0.28 + sin(ph * 2.0) * 0.05
		if s0 + i < out.size():
			out[s0 + i] += v * env
	# a second, shorter note a little lower
	s0 = int(0.325 * RATE)
	len = int(0.06 * RATE)
	ph = 0.0
	for i in len:
		var f := float(i) / float(len)
		var hz := 3900.0 - 600.0 * f + 100.0 * sin(TAU * 41.0 * float(i) / RATE)
		ph += TAU * hz / RATE
		var env := sin(PI * f)
		if s0 + i < out.size():
			out[s0 + i] += sin(ph) * 0.2 * env * env
	return out
