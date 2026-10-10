extends SceneTree

# Renders the splash sound to assets/ui/sfx/splash_whistle.wav with the game's
# own turbo synth (TurboSynth): a big single turbo spools up, then the throttle
# shuts and the flutter valve chatters. Shipping the WAV means the splash costs
# no synth time at start-up. Synthesised here, so it is ours to ship.
#
#   godot --headless --path . -s tools/render_splash_whistle.gd

const OUT := "res://assets/ui/sfx/splash_whistle.wav"
const RATE := 44100
const BLOCK := 441          # 10 ms
const SPOOL_SECS := 1.45
const TAIL_SECS := 1.0

func _init() -> void:
	var s := TurboSynth.new()
	s.mix_rate = RATE
	s.apply_voice(TurboVoice.build({"part": "big", "valve": "flutter", "valve_level": 0.9}))
	s.boost_max_bar = 1.2
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	var spool_blocks := int(SPOOL_SECS * RATE / BLOCK)
	var tail_blocks := int(TAIL_SECS * RATE / BLOCK)
	for i in spool_blocks + tail_blocks:
		if i < spool_blocks:
			var k := float(i) / spool_blocks
			s.boost = smoothstep(0.0, 1.0, k)
			s.rpm_norm = lerpf(0.35, 0.95, k)
		elif i == spool_blocks:
			s.boost = 0.0
			s.rpm_norm = 0.3
			s.vent(1.0)
		for v: Vector2 in s.render(BLOCK):
			left.append(v.x)
			right.append(v.y)
	# Fade the ends and bring the peak to a set level.
	var n := left.size()
	var peak := 0.0001
	for i in n:
		peak = maxf(peak, maxf(absf(left[i]), absf(right[i])))
	var fade := int(0.05 * RATE)
	for i in n:
		var g := 0.7 / peak * minf(1.0, float(i) / fade) * minf(1.0, float(n - 1 - i) / (fade * 4))
		left[i] *= g
		right[i] *= g
	var wav := AudioDsp.to_wav(left, RATE, false, right)
	wav.save_to_wav(ProjectSettings.globalize_path(OUT))
	print("wrote %s: %.2f s, raw peak %.3f" % [OUT, float(n) / RATE, peak])
	quit()
