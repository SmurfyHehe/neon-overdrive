extends SceneTree

# Renders the one sound the title's roaches make (menu roaches M7,
# 2026-10-11): a very quiet, dry skitter when two or more of them run for
# cover at once. A short burst of tiny clicks, each a few milliseconds of
# high-passed noise, thinning out as it goes. Synthesised here, nothing
# recorded.
#
#   godot --headless --audio-driver Dummy --path . -s res://tools/render_roach_skitter.gd
#
# Writes assets/ui/sfx/roach_skitter.wav (mono, 44.1 kHz, 0.32 s).

const OUT := "res://assets/ui/sfx/roach_skitter.wav"
const RATE := 44100
const SECS := 0.32
const TICKS := 14
const PEAK := 0.6
const HP_HZ := 2600.0   # the clicks sit above the whistle and the radio

func _init() -> void:
	var n := int(SECS * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# ticks come faster at first (the dash off the mark) and thin out
	var t := 0.004
	for k in TICKS:
		var at := int(t * RATE)
		var len := int((0.0025 + rng.randf() * 0.003) * RATE)
		var amp := (0.5 + rng.randf() * 0.5) * (1.0 - 0.55 * float(k) / float(TICKS))
		for i in len:
			if at + i >= n:
				break
			var env := exp(-float(i) / float(len) * 4.0)
			out[at + i] += (rng.randf() * 2.0 - 1.0) * amp * env
		t += 0.012 + 0.014 * float(k) / float(TICKS) + rng.randf() * 0.006
	# one-pole high-pass, twice: dry, no body
	var a := exp(-TAU * HP_HZ / RATE)
	for pass_i in 2:
		var prev_x := 0.0
		var prev_y := 0.0
		for i in n:
			var y := a * (prev_y + out[i] - prev_x)
			prev_x = out[i]
			prev_y = y
			out[i] = y
	var peak := 0.0001
	for i in n:
		peak = maxf(peak, absf(out[i]))
	for i in n:
		out[i] *= PEAK / peak
	AudioDsp.to_wav(out, RATE, false).save_to_wav(ProjectSettings.globalize_path(OUT))
	print("wrote %s: %.2f s, %d ticks" % [OUT, SECS, TICKS])
	quit()
