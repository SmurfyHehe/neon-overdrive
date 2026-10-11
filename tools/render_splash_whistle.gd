extends SceneTree

# Renders the splash sound to assets/ui/sfx/splash_whistle.wav with the game's
# own turbo synth (TurboSynth): a big single turbo spools up, then the throttle
# shuts and the flutter valve chatters. Shipping the WAV means the splash costs
# no synth time at start-up. Synthesised here, so it is ours to ship.
#
# The same pass also renders the title menu's whistle (holding W spins the
# logo's wheel): menu_whistle_loop.wav, the top of the spool as a seamless
# loop, and menu_whistle_flutter.wav, the valve chatter after the throttle
# shuts. All three share one gain so they sit at the same level.
#
#   godot --headless --path . -s tools/render_splash_whistle.gd
#   godot --headless --path . -s tools/render_splash_whistle.gd -- --loop-only
#
# --loop-only rewrites menu_whistle_loop.wav and leaves the other two alone.

const OUT := "res://assets/ui/sfx/splash_whistle.wav"
const OUT_LOOP := "res://assets/ui/sfx/menu_whistle_loop.wav"
const OUT_FLUTTER := "res://assets/ui/sfx/menu_whistle_flutter.wav"
const LOOP_FROM := 1.9      # s into the render: the spool is over by 1.45
const LOOP_SECS := 1.7
const LOOP_XFADE := 0.4     # equal-power: the whistle is mostly noise
const FLUTTER_SECS := 0.8
const RATE := 44100
const BLOCK := 441          # 10 ms
const SPOOL_SECS := 1.45
const TAIL_SECS := 1.0
const HOLD_SECS := 2.6      # steady top-of-spool, the loop's source

func _synth() -> TurboSynth:
	var s := TurboSynth.new()
	s.mix_rate = RATE
	s.apply_voice(TurboVoice.build({"part": "big", "valve": "flutter", "valve_level": 0.9}))
	s.boost_max_bar = 1.2
	return s

func _init() -> void:
	var s := _synth()
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
	if not "--loop-only" in OS.get_cmdline_user_args():
		var wav := AudioDsp.to_wav(left, RATE, false, right)
		wav.save_to_wav(ProjectSettings.globalize_path(OUT))
		print("wrote %s: %.2f s, raw peak %.3f" % [OUT, float(n) / RATE, peak])
	_render_menu(0.7 / peak)
	quit()

## The menu's pair, at the splash's own gain: spool, hold at the top, vent.
func _render_menu(gain: float) -> void:
	var s := _synth()
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	var spool_blocks := int(SPOOL_SECS * RATE / BLOCK)
	var hold_blocks := int(HOLD_SECS * RATE / BLOCK)
	var tail_blocks := int(TAIL_SECS * RATE / BLOCK)
	for i in spool_blocks + hold_blocks + tail_blocks:
		if i < spool_blocks:
			var k := float(i) / spool_blocks
			s.boost = smoothstep(0.0, 1.0, k)
			s.rpm_norm = lerpf(0.35, 0.95, k)
		elif i < spool_blocks + hold_blocks:
			s.boost = 1.0
			s.rpm_norm = 0.95
		elif i == spool_blocks + hold_blocks:
			s.boost = 0.0
			s.rpm_norm = 0.3
			s.vent(1.0)
		for v: Vector2 in s.render(BLOCK):
			left.append(v.x * gain)
			right.append(v.y * gain)
	# Loop: LOOP_SECS long, the last LOOP_XFADE of audio past its end faded
	# into its start, so the join is the same sound and no click. Equal
	# power (sin/cos), not linear: the two ends are different noise, and a
	# linear fade of uncorrelated sound dips ~2 dB at the seam - a pulse
	# every loop that read as the boost letting go while W was held.
	var from := int(LOOP_FROM * RATE)
	var xf := int(LOOP_XFADE * RATE)
	var best := _best_loop_len(left, from, xf)
	var len: int = best[0]
	var rho: float = best[1]
	var ll := PackedFloat32Array()
	var lr := PackedFloat32Array()
	for i in len:
		var a := from + i
		var l := left[a]
		var r := right[a]
		if i < xf:
			var t := float(i) / xf
			# Linear weights, scaled so the power stays level for however
			# alike the two ends are (rho 1: plain linear, 0: equal power).
			var g := 1.0 / sqrt(t * t + (1.0 - t) * (1.0 - t) + 2.0 * rho * t * (1.0 - t))
			l = (l * t + left[a + len] * (1.0 - t)) * g
			r = (r * t + right[a + len] * (1.0 - t)) * g
		ll.append(l)
		lr.append(r)
	AudioDsp.to_wav(ll, RATE, true, lr).save_to_wav(ProjectSettings.globalize_path(OUT_LOOP))
	print("wrote %s: %.2f s" % [OUT_LOOP, float(len) / RATE])
	if "--loop-only" in OS.get_cmdline_user_args():
		return
	# Flutter: from the moment the throttle shuts.
	var vent := (spool_blocks + hold_blocks) * BLOCK
	var fl := PackedFloat32Array()
	var fr := PackedFloat32Array()
	var m := int(FLUTTER_SECS * RATE)
	var out_fade := int(0.1 * RATE)
	for i in m:
		var g := minf(1.0, float(m - 1 - i) / out_fade)
		fl.append(left[vent + i] * g)
		fr.append(right[vent + i] * g)
	AudioDsp.to_wav(fl, RATE, false, fr).save_to_wav(ProjectSettings.globalize_path(OUT_FLUTTER))
	print("wrote %s: %.2f s" % [OUT_FLUTTER, float(m) / RATE])

## The loop length whose end lines up best with its start. The whistle has a
## steady tone under the noise; if the two ends of the crossfade hold that
## tone in opposite phase they cancel and the loop breathes once per cycle.
## Searches around LOOP_SECS for the length where the audio past the end
## correlates best with the start. Returns [length, how alike (0..1)].
func _best_loop_len(left: PackedFloat32Array, from: int, xf: int) -> Array:
	var centre := int(LOOP_SECS * RATE)
	var span := int(0.12 * RATE)
	var best := centre
	var best_c := -INF
	for len in range(centre - span, centre + span, 4):
		var c := 0.0
		for i in range(0, xf, 4):
			c += left[from + i] * left[from + len + i]
		if c > best_c:
			best_c = c
			best = len
	var ea := 0.0
	var eb := 0.0
	for i in range(0, xf, 4):
		ea += left[from + i] * left[from + i]
		eb += left[from + best + i] * left[from + best + i]
	var rho := clampf(best_c / maxf(sqrt(ea * eb), 0.000001), 0.0, 1.0)
	print("loop length %.3f s, ends alike %.2f" % [float(best) / RATE, rho])
	return [best, rho]
