extends SceneTree

# Renders the two sounds the title menu adds when W is held for the full six
# seconds (title_screen.gd, "Turbo goes crazy"):
#
#   assets/ui/sfx/menu_blowoff.wav        the loud "pssh" of an atmospheric
#                                         blow-off valve, from TurboSynth's
#                                         "atmo" valve at full boost
#   assets/ui/sfx/menu_overboost_grind.wav  a rough low grind loop that sits
#                                         under the whistle from half boost
#
# Both are synthesised here (no recordings), so they are ours to ship.
#
#   godot --headless --path . -s tools/render_menu_overboost.gd

const OUT_BLOWOFF := "res://assets/ui/sfx/menu_blowoff.wav"
const OUT_GRIND := "res://assets/ui/sfx/menu_overboost_grind.wav"
const RATE := 44100
const BLOCK := 441
const BLOWOFF_SECS := 0.7
const BLOWOFF_PEAK := 0.8
const GRIND_SECS := 1.0       # whole seconds, so the AM below loops exactly
const GRIND_PEAK := 0.5
const GRIND_LOW := 70.0       # Hz, band of the noise
const GRIND_HIGH := 320.0
const GRIND_TOP := 520.0      # Hz, low-pass after the clipping
const GRIND_AM_HZ := [23.0, 37.0]   # integer Hz: periodic over GRIND_SECS

func _init() -> void:
	_blowoff()
	_grind()
	quit()

func _blowoff() -> void:
	var s := TurboSynth.new()
	s.mix_rate = RATE
	s.apply_voice(TurboVoice.build({"part": "big", "valve": "atmo", "valve_level": 1.0}))
	s.boost_max_bar = 1.2
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	var spool := int(0.8 * RATE / BLOCK)
	var tail := int((BLOWOFF_SECS + 0.1) * RATE / BLOCK)
	var started := false
	for i in spool + tail:
		if i < spool:
			s.boost = smoothstep(0.0, 1.0, float(i) / spool)
			s.rpm_norm = lerpf(0.4, 0.95, float(i) / spool)
		elif not started:
			started = true
			s.boost = 0.0
			s.rpm_norm = 0.3
			s.vent(1.0)
		var block := s.render(BLOCK)
		if i >= spool:
			for v: Vector2 in block:
				left.append(v.x)
				right.append(v.y)
	var n := int(BLOWOFF_SECS * RATE)
	left.resize(n)
	right.resize(n)
	var peak := 0.0001
	for i in n:
		peak = maxf(peak, maxf(absf(left[i]), absf(right[i])))
	var fade_out := int(0.12 * RATE)
	var fade_in := int(0.004 * RATE)
	for i in n:
		var g := BLOWOFF_PEAK / peak * minf(1.0, float(i) / fade_in) \
				* minf(1.0, float(n - 1 - i) / fade_out)
		left[i] *= g
		right[i] *= g
	AudioDsp.to_wav(left, RATE, false, right).save_to_wav(ProjectSettings.globalize_path(OUT_BLOWOFF))
	print("wrote %s: %.2f s, raw peak %.3f" % [OUT_BLOWOFF, float(n) / RATE, peak])

## Band-passed noise (two passes of a state-variable filter over the buffer, the
## second pass kept, so the wrap is continuous) with two integer-Hz amplitude
## modulations on top: a periodic, gritty growl.
func _grind() -> void:
	var n := int(GRIND_SECS * RATE)
	var chans: Array[PackedFloat32Array] = []
	for c in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7311 + c * 97
		var noise := PackedFloat32Array()
		noise.resize(n)
		for i in n:
			noise[i] = rng.randf_range(-1.0, 1.0)
		var out := PackedFloat32Array()
		out.resize(n)
		var low := 0.0
		var f_low := 2.0 * sin(PI * GRIND_LOW / RATE)
		var f_high := 2.0 * sin(PI * GRIND_HIGH / RATE)
		var low2 := 0.0
		for pass_i in 2:
			for i in n:
				var x := noise[i]
				# Two cascaded one-pole stages: low-pass at HIGH, then remove
				# below LOW by subtracting a slower low-pass.
				low += f_high * (x - low)
				low2 += f_low * (low - low2)
				var y := low - low2
				if pass_i == 1:
					out[i] = y
		chans.append(out)
	var peak := 0.0001
	for c in 2:
		var o: PackedFloat32Array = chans[c]
		for i in n:
			var t := float(i) / RATE
			var am := 0.55 + 0.25 * sin(TAU * GRIND_AM_HZ[0] * t) + 0.2 * sin(TAU * GRIND_AM_HZ[1] * t + 1.3)
			o[i] = tanh(o[i] * 6.0) * am   # soft clip: rough, not clean
		# Take the clipping's top end off again (two passes so the wrap joins).
		var lp := 0.0
		var lp2 := 0.0
		var f_lp := 2.0 * sin(PI * GRIND_TOP / RATE)
		for pass_i in 2:
			for i in n:
				lp += f_lp * (o[i] - lp)
				lp2 += f_lp * (lp - lp2)
				if pass_i == 1:
					o[i] = lp2
		for i in n:
			peak = maxf(peak, absf(o[i]))
		chans[c] = o
	for c in 2:
		var o: PackedFloat32Array = chans[c]
		for i in n:
			o[i] *= GRIND_PEAK / peak
		chans[c] = o
	# Seam check: the jump from the last sample to the first, against the
	# typical step inside the loop.
	var jump := absf(chans[0][0] - chans[0][n - 1])
	var step := 0.0
	for i in range(1, n):
		step += absf(chans[0][i] - chans[0][i - 1])
	step /= n - 1
	print("grind seam jump %.4f, mean step %.4f" % [jump, step])
	AudioDsp.to_wav(chans[0], RATE, true, chans[1]).save_to_wav(ProjectSettings.globalize_path(OUT_GRIND))
	print("wrote %s: %.2f s, raw peak %.3f" % [OUT_GRIND, float(n) / RATE, peak])
