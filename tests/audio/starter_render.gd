extends SceneTree

# The starter, rendered offline (StarterAudio.render_start, no game boot): the
# whole key start for a four-cylinder, a crossplane V8 and the air-cooled flat
# four, cold and warm. Checks:
#
#  - how long it lasts: cold longer than warm, both inside DURATION
#  - the coughs: two cold, one warm
#  - the three engines differ: recipe, strokes a second, and the sound itself
#  - the catch happens: it is as loud as the crank, and the starter has gone
#    by the end of it
#  - no clipping, no NaN
#  - weight: a good share of the energy sits at 120-400 Hz (Roy 2026-10-11:
#    "sounds weak"; a laptop speaker has nothing below that)
#  - level: the crank against the same engine idling (EngineSynth at
#    EngineAudio's volume), inside LEVEL_DB
#  - the fast idle (PlayerCar.fast_idle_add): 1500-1800 rpm off a cold start,
#    never rising, back to the car's own idle at 20 s; a warm one in 3 s
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/audio/starter_render.gd

const StarterAudio := preload("res://scripts/audio/starter_audio.gd")
const ENGINES := {"four_cyl": "p2_hothatch", "v8": "p5_muscle", "flat_four": "p0_beater"}
const ENGINE_VOLUME := 0.5  # EngineAudio.ENGINE_VOLUME
## Seconds, the whole start: [cold min, cold max, warm min, warm max].
const DURATION := [1.7, 3.0, 1.2, 2.2]
const BAND_SHARE_MIN := 0.3
## The crank's rms over the idle's, dB: never under it, not a different world.
const LEVEL_DB := [0.0, 16.0]

var fails: Array[String] = []

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("  FAIL: %s" % what)

static func _rms(s: PackedFloat32Array, from := 0, to := -1) -> float:
	if to < 0:
		to = s.size()
	var sum := 0.0
	for i in range(from, to):
		sum += s[i] * s[i]
	return sqrt(sum / maxi(to - from, 1))

## The share of the energy between lo and hi Hz (fourth order both ends).
static func _band_share(s: PackedFloat32Array, rate: float, lo: float, hi: float) -> float:
	var f := [AudioDsp.hp(rate, lo), AudioDsp.hp(rate, lo), AudioDsp.lp(rate, hi), AudioDsp.lp(rate, hi)]
	var all := 0.0
	var band := 0.0
	for v in s:
		var x := v
		for b: AudioDsp.Biquad in f:
			x = b.step(x)
		all += v * v
		band += x * x
	return band / maxf(all, 1e-12)

func _idle_rms(voice: Dictionary, idle: float) -> float:
	var synth := EngineSynth.new()
	synth.apply_voice(voice)
	synth.idle_rpm = idle
	synth.volume = ENGINE_VOLUME
	synth.render(int(synth.mix_rate * 0.5), idle, 0.0, false)  # settle
	var block := synth.render(int(synth.mix_rate), idle, 0.0, false)
	var sum := 0.0
	for v in block:
		sum += v.x * v.x
	return sqrt(sum / block.size())

func _initialize() -> void:
	var rate := StarterAudio.RATE
	var keys := {}
	var cranks := {}
	var chugs := {}
	for label: String in ENGINES:
		var car: String = ENGINES[label]
		var spec := CarSpec.player_spec(car)
		var voice: Dictionary = spec.get("engine_voice", {})
		var rec: Dictionary = StarterAudio.recipe(voice)
		keys[rec.key] = label
		chugs[label] = rec.chugs
		var idle := float(spec.get("idle_rpm", 1000.0))
		var idle_rms := _idle_rms(voice, idle)
		var lens := {}
		for cold: float in [1.0, 0.0]:
			var which := "cold" if cold > 0.5 else "warm"
			var s: PackedFloat32Array = StarterAudio.render_start(rec, cold)
			var hold: float = StarterAudio.hold_for(rec.cylinders, cold)
			var hold_n := int(hold * rate)
			var secs := float(s.size()) / rate
			lens[which] = secs
			var peak := 0.0
			var finite := true
			for v in s:
				finite = finite and is_finite(v)
				peak = maxf(peak, absf(v))
			var crank_rms := _rms(s, int(0.15 * rate), hold_n)
			var catch_rms := _rms(s, hold_n, hold_n + int(0.4 * rate))
			var tail_rms := _rms(s, s.size() - int(0.06 * rate))
			var share := _band_share(s, rate, 120.0, 400.0)
			var level_db := linear_to_db(crank_rms / maxf(idle_rms, 1e-9))
			var n_cough: int = StarterAudio.cough_times(hold, cold).size()
			print("starter_render: %-9s %s  %.2f s (crank %.2f)  %d coughs  peak %.2f  crank rms %.3f  catch rms %.3f  tail %.3f  120-400 Hz %.0f%%  vs idle %+.1f dB" % [
				label, which, secs, hold, n_cough, peak, crank_rms, catch_rms, tail_rms, share * 100.0, level_db])
			var lo: float = DURATION[0] if cold > 0.5 else DURATION[2]
			var hi: float = DURATION[1] if cold > 0.5 else DURATION[3]
			_check(secs >= lo and secs <= hi, "%s %s lasts %.2f s, outside %.1f..%.1f" % [label, which, secs, lo, hi])
			_check(n_cough == (2 if cold > 0.5 else 1), "%s %s has %d coughs" % [label, which, n_cough])
			_check(finite, "%s %s has a non-finite sample" % [label, which])
			_check(peak > 0.3 and peak < 0.98, "%s %s peak %.3f (clipping or silent)" % [label, which, peak])
			_check(catch_rms > crank_rms * 0.8, "%s %s: no catch (rms %.3f against the crank's %.3f)" % [label, which, catch_rms, crank_rms])
			_check(tail_rms < crank_rms * 0.2, "%s %s: still sounding at the end (%.3f)" % [label, which, tail_rms])
			_check(share >= BAND_SHARE_MIN, "%s %s: only %.0f%% of the energy at 120-400 Hz" % [label, which, share * 100.0])
			_check(level_db >= LEVEL_DB[0] and level_db <= LEVEL_DB[1], "%s %s: crank %+.1f dB against the idle" % [label, which, level_db])
			if cold > 0.5:
				cranks[label] = s.slice(int(0.15 * rate), int(1.0 * rate))
		_check(lens.cold > lens.warm + 0.3, "%s: cold start (%.2f s) not longer than warm (%.2f s)" % [label, lens.cold, lens.warm])
	_check(keys.size() == ENGINES.size(), "two engines share a starter recipe: %s" % [keys])
	var labels := cranks.keys()
	for a in labels.size():
		for b in range(a + 1, labels.size()):
			var x: PackedFloat32Array = cranks[labels[a]]
			var y: PackedFloat32Array = cranks[labels[b]]
			var d := PackedFloat32Array()
			d.resize(x.size())
			for i in x.size():
				d[i] = x[i] - y[i]
			var rel := _rms(d) / maxf(_rms(x), 1e-9)
			print("starter_render: %s against %s: difference %.2f of the signal, %.1f and %.1f strokes a second" % [labels[a], labels[b], rel, chugs[labels[a]], chugs[labels[b]]])
			_check(rel > 0.5, "%s and %s sound the same (difference %.2f)" % [labels[a], labels[b], rel])
	_fast_idle()
	print("starter_render: %s" % ("PASS" if fails.is_empty() else "FAIL: %s" % "; ".join(fails)))
	quit(0 if fails.is_empty() else 1)

func _fast_idle() -> void:
	for base: float in [700.0, 850.0, 1000.0, 1100.0]:
		var top := base + PlayerCar.fast_idle_add(base, 1.0, 0.0)
		var mid := base + PlayerCar.fast_idle_add(base, 1.0, 10.0)
		var warm_top := base + PlayerCar.fast_idle_add(base, 0.0, 0.0)
		print("starter_render: idle %.0f: fast idle %.0f cold (%.0f at 10 s), %.0f warm" % [base, top, mid, warm_top])
		_check(top >= 1500.0 and top <= 1800.0, "cold fast idle %.0f rpm off an idle of %.0f" % [top, base])
		_check(mid > base + 50.0 and mid < top, "fast idle at 10 s is %.0f (idle %.0f, top %.0f)" % [mid, base, top])
		_check(PlayerCar.fast_idle_add(base, 1.0, 20.0) == 0.0, "cold fast idle not over at 20 s")
		_check(PlayerCar.fast_idle_add(base, 1.0, 19.0) > 0.0, "cold fast idle over before 19 s")
		_check(warm_top > base and warm_top < top, "warm fast idle %.0f (cold %.0f)" % [warm_top, top])
		_check(PlayerCar.fast_idle_add(base, 0.0, 3.0) == 0.0, "warm fast idle not over at 3 s")
		var last := INF
		for i in 201:
			var v := PlayerCar.fast_idle_add(base, 1.0, i * 0.1)
			_check(v <= last + 0.001, "fast idle rises at %.1f s" % (i * 0.1))
			last = v
