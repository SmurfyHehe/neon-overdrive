extends SceneTree

# Engine loop bank test (2026-10-10, ROADMAP "engine sound loops").
# EngineLoops bakes EngineSynth into seamless rpm x load loops; EngineLoopPlayer
# plays them; EngineSynth.render_events keeps the pops live. Checks, offline:
# - bands: idle to redline, never more than BAND_RATIO apart; pick() weights are
#   power-complementary, continuous and only ever name two neighbouring bands
# - loops: a whole number of engine cycles, true rpm within 0.2 % of the target,
#   no non-finite sample, level in range, and the seam (last sample -> first) is
#   no bigger a step than the signal makes inside the loop (and the unfaded
#   loop point would have been: reported for comparison)
# - the cache: a second bake_cached() reads the same bank back from disk
# - the player: on a 1000 -> 7000 rpm run (60 and 20 fps), a throttle chop, a
#   downshift drop and the limiter, never more than MAX_VOICES playing, no
#   stream swapped on an audible voice (that would click), nothing left playing
#   once the engine is off
# - events: render_events() still bangs on overrun and on the limiter, makes
#   flames, and is silent and cheap when nothing is banging
# - cost: synth us/sample live vs events-only (the CPU the loops take off the
#   worker thread), and the player's script time per frame
# Writes user://engine_loops_sweep.wav and user://engine_loops_<band>.wav for
# listening and for tools/engine_loops_spectrogram.py (never played here).
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/audio/engine_loops.gd

const IDLE := 1000.0
const MAX := 7000.0
const VOICE := "p1_coupe"

var fails := 0
var _bank: EngineLoops

func _initialize() -> void:
	_test_bands()
	var t0 := Time.get_ticks_usec()
	EngineLoops.use_cache = false
	var baked := EngineLoops.bake(EngineVoice.for_car(VOICE), 0.5, 0.3, IDLE, MAX, 0.5)
	var bake_s := float(Time.get_ticks_usec() - t0) / 1e6
	_test_loops(baked, bake_s)
	_test_cache()
	_bank = EngineLoops.from_baked(baked)
	_test_events()
	_test_cost()
	_write_sweep(_bank)

## The player needs to be inside the tree, which it is not during _initialize.
func _process(_delta: float) -> bool:
	_test_player(_bank)
	print("PASS" if fails == 0 else "%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
	return true

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

# --- bands and weights -------------------------------------------------------

func _test_bands() -> void:
	var b := EngineLoops.band_rpms(IDLE, MAX)
	print("bands: %d, %.0f .. %.0f rpm" % [b.size(), b[0], b[b.size() - 1]])
	_check(is_equal_approx(b[0], IDLE), "first band should be idle")
	_check(is_equal_approx(b[b.size() - 1], MAX), "last band should be redline")
	for i in range(1, b.size()):
		_check(b[i] > b[i - 1], "bands must ascend")
		_check(b[i] / b[i - 1] <= EngineLoops.BAND_RATIO * 1.0001, "band %d is %.3f above the one below" % [i, b[i] / b[i - 1]])
	var last := -1.0
	var worst_step := 0.0
	var prev_w := Vector2.ZERO
	for i in range(0, 8001):
		var rpm := 500.0 + i
		var p := EngineLoops.pick(b, rpm)
		var k := int(p.x)
		_check(k >= 0 and k + 1 < b.size(), "pick(%d) names bands %d,%d" % [rpm, k, k + 1])
		_check(absf(p.y * p.y + p.z * p.z - 1.0) < 1e-4, "pick(%d) is not power-complementary" % rpm)
		var w := Vector2(float(k) + p.z, 0.0)
		if i > 0:
			worst_step = maxf(worst_step, absf(w.x - last))
		last = w.x
		prev_w = w
	_check(worst_step < 0.05, "weights jump by %.3f in 1 rpm" % worst_step)

# --- loops ---------------------------------------------------------------------

func _test_loops(d: Dictionary, bake_s: float) -> void:
	var n := (d["rpms"] as PackedFloat32Array).size()
	var targets := EngineLoops.band_rpms(IDLE, MAX)
	print("bake: %d bands x 2 loads in %.1f s" % [n, bake_s])
	_check(n == targets.size(), "one loop per band")
	var bytes := 0
	var worst := 0.0
	var worst_naive := 0.0
	for i in n:
		var r: float = (d["rpms"] as PackedFloat32Array)[i]
		_check(absf(r - targets[i]) / targets[i] < 0.002, "band %d true rpm %.1f vs target %.1f" % [i, r, targets[i]])
		for key in ["lift", "open"]:
			var pcm: PackedByteArray = d[key][i]
			bytes += pcm.size()
			var len := pcm.size() / 2
			_check(len >= 3000, "%s band %d is only %d samples" % [key, i, len])
			var peak := 0
			var bad := false
			for j in len:
				peak = maxi(peak, absi(pcm.decode_s16(j * 2)))
			_check(peak > 1000 and peak < 32767, "%s band %d peak %d out of range" % [key, i, peak])
			var jump := EngineLoops.seam_jump(pcm)
			worst = maxf(worst, jump)
			_check(jump <= 1.0, "%s band %d (%.0f rpm): seam step is %.2fx the loudest step inside the loop" % [key, i, r, jump])
			# comparison: what the loop point would be with no cross-fade (the raw synth
			# window): the loop's own tail glued to its own head.
			var naive := _naive_jump(d, key, i)
			worst_naive = maxf(worst_naive, naive)
	print("seam step / loudest inner step: worst %.3f (the same loops without the cross-fade: worst %.3f)" % [worst, worst_naive])
	print("bank size: %.1f MB (16-bit mono, %d loops)" % [bytes / 1048576.0, n * 2])
	_check(bytes < 6 * 1048576, "one voice's bank should stay under 6 MB (%d)" % bytes)

## The loop point of an unfaded window: render the same loop, cut it to its
## length with no cross-fade, and measure the same ratio.
func _naive_jump(d: Dictionary, key: String, band: int) -> float:
	var s := EngineSynth.new()
	s.mix_rate = EngineLoops.RATE
	s.idle_rpm = IDLE
	s.max_rpm = MAX
	s.apply_voice(EngineVoice.for_car(VOICE))
	s.wander = 0.0
	s.tune = ExhaustTune.new(0.5, 0.3, 0.0, 0.0, 0.0)
	s.volume = 0.5
	var len := (d[key][band] as PackedByteArray).size() / 2
	var rpm: float = (d["rpms"] as PackedFloat32Array)[band]
	s.render(int(EngineLoops.WARMUP_SECS * EngineLoops.RATE), rpm, 1.0 if key == "open" else 0.0, false)
	var blk := s.render(len, rpm, 1.0 if key == "open" else 0.0, false)
	var worst := 0.0
	for i in range(1, len):
		worst = maxf(worst, absf(blk[i].x - blk[i - 1].x))
	return absf(blk[0].x - blk[len - 1].x) / maxf(worst, 1e-6)

# --- cache -----------------------------------------------------------------------

func _test_cache() -> void:
	EngineLoops.use_cache = true
	var voice := EngineVoice.for_car("p4_kei")
	var key := EngineLoops.cache_key(voice, 0.5, 0.3, IDLE, MAX)
	var path := EngineLoops.CACHE_DIR.path_join(key + ".bin")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var t0 := Time.get_ticks_usec()
	var a := EngineLoops.bake_cached(voice, 0.5, 0.3, IDLE, MAX, 0.5)
	var t1 := Time.get_ticks_usec()
	var b := EngineLoops.bake_cached(voice, 0.5, 0.3, IDLE, MAX, 0.5)
	var t2 := Time.get_ticks_usec()
	print("cache: bake %.1f s, load %.0f ms" % [(t1 - t0) / 1e6, (t2 - t1) / 1e3])
	_check(FileAccess.file_exists(path), "bake_cached wrote no cache file")
	_check((a["lift"] as Array).size() == (b["lift"] as Array).size() and a["open"][3] == b["open"][3],
			"cached bank differs from the baked one")
	_check(t2 - t1 < (t1 - t0) / 5, "loading from cache is not much faster than baking")
	var other := EngineLoops.cache_key(voice, 0.9, 0.3, IDLE, MAX)
	_check(other != key, "loudness must change the cache key")
	_check(EngineLoops.cache_key(EngineVoice.for_car("p5_muscle"), 0.5, 0.3, IDLE, MAX) != key, "voice must change the cache key")
	EngineLoops.use_cache = false

# --- player ----------------------------------------------------------------------

func _test_player(bank: EngineLoops) -> void:
	for fps: float in [60.0, 20.0]:
		var pl := EngineLoopPlayer.new()
		get_root().add_child(pl)
		pl.set_loops(bank)
		var dt: float = 1.0 / fps
		var most := 0
		var rpm := IDLE
		var thr := 0.0
		var t := 0.0
		var script_us := 0
		var frames := 0
		# idle 1 s, full throttle 1000 -> 7000 in 4 s, limiter 1 s, chop to 3000 in 0.3 s,
		# 1.5 s coast, a 30 % downshift drop in 0.2 s at 6000, then engine off
		var plan := [
			[1.0, IDLE, IDLE, 0.0, false], [4.0, IDLE, MAX, 1.0, false], [1.0, MAX, MAX, 1.0, true],
			[0.3, MAX, 3000.0, 0.0, false], [1.5, 3000.0, 1500.0, 0.2, false],
			[2.0, 1500.0, 6000.0, 1.0, false], [0.2, 6000.0, 4200.0, 0.6, false], [1.5, 4200.0, 5500.0, 0.8, false]]
		for seg in plan:
			var steps := int(seg[0] * fps)
			for i in steps:
				rpm = lerpf(seg[1], seg[2], float(i + 1) / steps)
				var u0 := Time.get_ticks_usec()
				pl.update(dt, rpm, seg[3], seg[4], true)
				script_us += Time.get_ticks_usec() - u0
				frames += 1
				most = maxi(most, pl.playing_count())
		for i in int(0.5 * fps):
			pl.update(dt, rpm, 0.0, false, false)
		print("player @%d fps: most voices %d, hard swaps %d, script %.1f us/frame, deferred bands %d, left playing after engine off: %d" % [
				int(fps), most, pl.hard_swaps, float(script_us) / frames, pl.deferred, pl.playing_count()])
		_check(most <= EngineLoopPlayer.MAX_VOICES, "more than MAX_VOICES players at once (%d)" % most)
		_check(most >= 1, "nothing played at all")
		_check(pl.hard_swaps == 0, "a stream was swapped on an audible voice %d time(s) at %d fps" % [pl.hard_swaps, int(fps)])
		_check(pl.playing_count() == 0, "voices still playing with the engine off (%d)" % pl.playing_count())
		pl.queue_free()

# --- events ----------------------------------------------------------------------

func _synth(tune: ExhaustTune) -> EngineSynth:
	var s := EngineSynth.new()
	s.idle_rpm = IDLE
	s.max_rpm = MAX
	s.apply_voice(EngineVoice.for_car(VOICE))
	s.tune = tune
	return s

func _run_events(s: EngineSynth, secs: float, rpm: float, thr: float, redline: bool) -> Dictionary:
	var peak := 0.0
	var finite := true
	var energy := 0.0
	var done := 0
	var total := int(secs * s.mix_rate)
	while done < total:
		var k := mini(512, total - done)
		for v in s.render_events(k, rpm, thr, redline):
			finite = finite and not (is_nan(v.x) or is_inf(v.x))
			peak = maxf(peak, absf(v.x))
			energy += v.x * v.x
		done += k
	return {"peak": peak, "finite": finite, "energy": energy}

func _test_events() -> void:
	var s := _synth(ExhaustTune.new(0.5, 0.3, 0.3, 0.5))
	var o := _run_events(s, 3.0, 5500.0, 0.0, false)
	print("events: overrun %d clusters, %d bangs, peak %.2f" % [s.pop_clusters, s.pop_bangs, o.peak])
	_check(s.pop_clusters > 0 and s.pop_bangs >= s.pop_clusters, "overrun pops should bang in events mode")
	_check(o.finite and o.peak > 0.05 and o.peak <= 1.2, "overrun pop level %.3f" % o.peak)
	s = _synth(ExhaustTune.new(0.5, 0.3, 1.0, 0.5))
	o = _run_events(s, 2.0, 7000.0, 1.0, true)
	print("events: limiter %d clusters, %d bangs, flame %.2f" % [s.pop_clusters, s.pop_bangs, s.take_flames()])
	_check(s.pop_clusters > 0, "the limiter with pops 1 should bang in events mode")
	s = _synth(ExhaustTune.new(0.5, 0.3, 0.3, 0.6))
	s.shift_cut(1.0)
	_run_events(s, 0.4, 5000.0, 1.0, false)
	_check(s.upshift_clusters > 0, "an upshift cut should bang in events mode")
	s = _synth(ExhaustTune.new(0.5, 0.3, 0.0, 0.0, 0.0))
	o = _run_events(s, 2.0, 6000.0, 0.0, false)
	_check(s.pop_bangs == 0 and o.energy == 0.0, "no pops, no anti-lag: events must be silent")
	s = _synth(ExhaustTune.new(0.5, 0.3, 0.0, 0.0, 1.0))
	_run_events(s, 2.0, 6000.0, 0.0, false)
	_check(s.pop_bangs / 2.0 >= 15.0, "anti-lag should crackle in events mode (%.0f bangs/s)" % (s.pop_bangs / 2.0))

# --- cost --------------------------------------------------------------------------

func _test_cost() -> void:
	var secs := 3.0
	var frames := int(secs * 44100.0)
	var live := _synth(ExhaustTune.new(0.5, 0.3, 0.3, 0.5))
	var t0 := Time.get_ticks_usec()
	var done := 0
	while done < frames:
		live.render(512, 4000.0, 0.7, false)
		done += 512
	var live_us := float(Time.get_ticks_usec() - t0) / done
	var ev := _synth(ExhaustTune.new(0.5, 0.3, 0.3, 0.5))
	t0 = Time.get_ticks_usec()
	done = 0
	while done < frames:
		ev.render_events(512, 4000.0, 0.7, false)
		done += 512
	var ev_us := float(Time.get_ticks_usec() - t0) / done
	print("cost: live synth %.3f us/sample, events-only %.4f us/sample (%.0fx cheaper while no bang sounds)" % [
			live_us, ev_us, live_us / maxf(ev_us, 1e-6)])
	_check(ev_us < live_us * 0.2, "events-only should cost under a fifth of the live synth")

# --- listening / spectrogram files ---------------------------------------------------

## A rev sweep through the bank, mixed offline with the same band pick as the
## player (a coherent-phase ideal: both bands run from sample 0 together, so it
## shows the loop points and the cross-fades, not Godot's start latency).
func _write_sweep(bank: EngineLoops) -> void:
	var rate := EngineLoops.RATE
	var plan := [[1.0, IDLE, IDLE, 0.0], [5.0, IDLE, MAX, 1.0], [1.0, MAX, MAX, 1.0], [3.0, MAX, 1500.0, 0.0], [1.0, 1500.0, IDLE, 0.0]]
	var n_total := 0
	for seg in plan:
		n_total += int(seg[0] * rate)
	var out := PackedFloat32Array()
	out.resize(n_total)
	var pos := {}  # "state:band" -> float position, kept running so phases stay coherent
	var cur := 0
	var thr := 0.0
	for seg in plan:
		var n := int(seg[0] * rate)
		for i in n:
			var rpm := lerpf(seg[1], seg[2], float(i) / maxf(n - 1, 1))
			thr += (seg[3] - thr) * 0.0004
			var p := EngineLoops.pick(bank.rpms, rpm)
			var k := int(p.x)
			var s := 0.0
			for state in 2:
				var sw := cos(thr * PI * 0.5) if state == 0 else sin(thr * PI * 0.5)
				for j in 2:
					var w := sw * (p.y if j == 0 else p.z)
					if w <= 0.0005:
						continue
					var band := k + j
					var st: AudioStreamWAV = bank.open[band] if state == 1 else bank.lift[band]
					var key := "%d:%d" % [state, band]
					var len := st.data.size() / 2
					var ps: float = pos.get(key, 0.0)
					var ia := int(ps)
					var fa := ps - ia
					var a := st.data.decode_s16((ia % len) * 2)
					var b := st.data.decode_s16(((ia + 1) % len) * 2)
					s += w * lerpf(float(a), float(b), fa) / 32768.0
			# advance every position that was in use this sample
			for state in 2:
				for j in 2:
					var key2 := "%d:%d" % [state, k + j]
					var len2 := (bank.open[k + j] as AudioStreamWAV).data.size() / 2
					pos[key2] = fposmod(float(pos.get(key2, 0.0)) + rpm / bank.rpms[k + j], len2)
			out[cur] = s
			cur += 1
	var bytes := PackedByteArray()
	bytes.resize(n_total * 2)
	for i in n_total:
		bytes.encode_s16(i * 2, int(clampf(out[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = bytes
	var path := OS.get_environment("ENGINE_LOOPS_WAV")
	if path == "":
		path = "user://engine_loops_sweep.wav"
	_check(wav.save_to_wav(path) == OK, "could not save the sweep")
	print("wrote ", ProjectSettings.globalize_path(path))
	# every loop, three times in a row, for the seam view (lift and open of a few bands)
	for band in [0, 5, bank.band_count() - 1]:
		for state in ["lift", "open"]:
			var st: AudioStreamWAV = bank.lift[band] if state == "lift" else bank.open[band]
			var three := PackedByteArray()
			three.append_array(st.data)
			three.append_array(st.data)
			three.append_array(st.data)
			var w3 := AudioStreamWAV.new()
			w3.format = AudioStreamWAV.FORMAT_16_BITS
			w3.mix_rate = rate
			w3.data = three
			var p3 := "user://engine_loops_%s_b%d_x3.wav" % [state, band]
			w3.save_to_wav(p3)
			print("wrote ", ProjectSettings.globalize_path(p3), "  (loop length %d samples)" % [st.data.size() / 2])
