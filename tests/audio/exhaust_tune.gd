extends SceneTree

# Exhaust tune test (stage B step 2): renders EngineSynth offline and checks
# each cosmetic knob does what it says, and nothing else.
# - loudness: louder tune, higher RMS
# - raspiness: more high-frequency energy (sample-to-sample change)
# - pops: none at 0; on a lifted throttle at rpm, more at 1 (counted as bursts)
# - flame: no flame events at 0; events at 1 from pops; flame never exceeds 1
# - presets: all 12 fleet ids have a tune with every knob in 0..1
# Writes a WAV per case to user://exhaust_*.wav for listening (never played).
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/audio/exhaust_tune.gd

const BLOCK := 512

var fails := 0

func _initialize() -> void:
	var quiet := _drive(ExhaustTune.new(0.1, 0.3, 0.0, 0.0), "quiet")
	var loud := _drive(ExhaustTune.new(0.9, 0.3, 0.0, 0.0), "loud")
	_check(loud.rms > quiet.rms * 1.5, "loudness 0.9 should be well louder than 0.1 (%.3f vs %.3f)" % [loud.rms, quiet.rms])
	var smooth := _drive(ExhaustTune.new(0.5, 0.0, 0.0, 0.0), "smooth")
	var rasp := _drive(ExhaustTune.new(0.5, 1.0, 0.0, 0.0), "raspy")
	_check(rasp.edge > smooth.edge * 1.1, "raspiness 1 should add high-frequency edge (%.4f vs %.4f)" % [rasp.edge, smooth.edge])
	var nopops := _drive(ExhaustTune.new(0.5, 0.3, 0.0, 1.0), "nopops")
	var pops := _drive(ExhaustTune.new(0.5, 0.3, 1.0, 1.0), "pops")
	_check(pops.flames > 0 and pops.max_flame <= 1.0, "pops 1 + flame 1 should spit flames, capped at 1 (%d, %.2f)" % [pops.flames, pops.max_flame])
	_check(pops.bursts > nopops.bursts, "pops 1 should add overrun bursts (%d vs %d)" % [pops.bursts, nopops.bursts])
	var noflame := _drive(ExhaustTune.new(0.5, 0.3, 1.0, 0.0), "noflame")
	_check(noflame.flames == 0, "flame 0 should never make a flame event (%d)" % noflame.flames)
	for id in ["p1_coupe", "p2_hothatch", "p3_tuner", "p4_kei", "p5_muscle", "p6_crossover", "n1_commuter",
			"n2_cityhatch", "n3_pickup", "c1_patrol", "c2_patrolsuv", "c3_interceptor"]:
		var t := ExhaustTune.for_car(id)
		for v in [t.loudness, t.raspiness, t.pops, t.flame]:
			_check(v >= 0.0 and v <= 1.0, "%s preset knob %.2f outside 0..1" % [id, v])
		_check(ExhaustTune.PRESETS.has(id), "no preset for %s" % id)
	print("exhaust_tune: ", "PASS" if fails == 0 else "FAIL")
	quit(1 if fails > 0 else 0)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)

# Rev to 6500 at full throttle, then lift and coast down 3 s (the overrun).
func _drive(tune: ExhaustTune, label: String) -> Dictionary:
	var synth := EngineSynth.new()
	synth.tune = tune
	var sr := synth.mix_rate
	var segs := [[1.5, 3000.0, 6500.0, 1.0], [3.0, 6500.0, 1500.0, 0.0]]
	var all := PackedFloat32Array()
	var flames := 0
	var max_flame := 0.0
	for seg in segs:
		var n := int(seg[0] * sr)
		var done := 0
		while done < n:
			var k := mini(BLOCK, n - done)
			var rpm := lerpf(seg[1], seg[2], float(done + k) / n)
			for f in synth.render(k, rpm, seg[3], false):
				all.append(f.x)
			var fl := synth.take_flames()
			if fl > 0.0:
				flames += 1
				max_flame = maxf(max_flame, fl)
			done += k
	var sum := 0.0
	var edge := 0.0
	var bursts := 0
	var prev := 0.0
	var hot := false
	for i in all.size():
		var v := all[i]
		if is_nan(v) or is_inf(v):
			_check(false, "%s: non-finite sample" % label)
			break
		sum += v * v
		edge += absf(v - prev)
		prev = v
		# a burst = the sample-to-sample jump crossing a sharp-crackle level
		var j := absf(v - all[maxi(i - 1, 0)])
		if j > 0.5 and not hot:
			bursts += 1
			hot = true
		elif j < 0.1:
			hot = false
	var bytes := PackedByteArray()
	bytes.resize(all.size() * 2)
	for i in all.size():
		bytes.encode_s16(i * 2, int(clampf(all[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(sr)
	wav.data = bytes
	wav.save_to_wav("user://exhaust_%s.wav" % label)
	return {"rms": sqrt(sum / all.size()), "edge": edge / all.size(), "flames": flames, "max_flame": max_flame, "bursts": bursts}
