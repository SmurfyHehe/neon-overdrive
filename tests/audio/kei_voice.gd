extends SceneTree

# Kei engine voice test (rework 2026-10-09, Roy: "the kei car sounds bad").
# Renders the kei (EngineSynth + EngineLayers, as EngineAudio plays it) at
# idle, midrange and on the limiter, next to the two other three-cylinder
# voices (hot hatch, traffic city hatch), writes WAVs for listening and a
# levels file for tools/audio/spectrogram.py, then boots Game.tscn and checks
# the live EngineAudio renders through its layers without trouble.
#
# Asserts (exit code 1 on failure):
# - every kei segment is finite with a peak in 0.05..1.0
# - the layers cost under half of what the synth does (best of three sweeps;
#   the absolute number depends on the laptop's load, so it is only printed)
# - the kei is thinner (less energy under 200 Hz) and brighter than the hot
#   hatch and the city hatch at idle and midrange: "thin, buzzy, high"
# - the gear whine is there: 6 dB more at the mesh frequency with the layer
#   on than off, at midrange
# - the intake whir is there: more 1-4 kHz energy with the layer on, flat out
# - the rattle is densest at idle: more clicks in 2 s of idle than of limiter
# - the kei is at least 8% apart from both other triples on the fingerprint
# - the live player car's EngineAudio has layers and is playing
# Writes: user://kei_voice/<car>_<segment>.wav, kei_sweep.wav, levels.txt
# (KEI_VOICE_DIR overrides the folder).
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/audio/kei_voice.gd

const BLOCK := 512
const LIVE_FRAMES := 120
const SEGMENTS := {
	# name: [rpm, throttle, redline]
	"idle": [1100.0, 0.0, false],
	"mid": [4500.0, 0.6, false],
	"limiter": [8500.0, 1.0, true],
}
const CARS := ["p4_kei", "p2_hothatch", "n2_cityhatch"]
const SECS := 2.0

var fails := 0
var game: Node
var frame := 0
var dir := ""
var levels := PackedStringArray()

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	dir = OS.get_environment("KEI_VOICE_DIR")
	if dir == "":
		dir = "user://kei_voice"
	DirAccess.make_dir_recursive_absolute(dir)
	_check_segments()
	_check_layers()
	_check_cost()
	var f := FileAccess.open(dir.path_join("levels.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(levels) + "\n")
	print("wrote WAVs and levels.txt to ", ProjectSettings.globalize_path(dir))
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL: ", msg)

## A car's live chain: synth + layers from its voice, with optional overrides.
func _chain(id: String, overrides := {}) -> Array:
	var v := EngineVoice.for_car(id)
	for k in overrides:
		v[k] = overrides[k]
	var synth := EngineSynth.new()
	synth.apply_voice(v)
	var layers := EngineLayers.new()
	layers.apply_voice(v)
	layers.mix_rate = synth.mix_rate
	var spec := CarSpec.player_spec(id) if id.begins_with("p") else CarSpec.traffic_default()
	synth.idle_rpm = float(spec.get("idle_rpm", 1000.0))
	synth.max_rpm = float(spec.get("max_rpm", 7000.0))
	layers.idle_rpm = synth.idle_rpm
	layers.max_rpm = synth.max_rpm
	return [synth, layers]

## `secs` of a held state after a 0.3 s settle.
func _render(chain: Array, rpm: float, thr: float, redline: bool, secs: float) -> PackedVector2Array:
	var synth: EngineSynth = chain[0]
	var layers: EngineLayers = chain[1]
	var settle := int(synth.mix_rate * 0.3)
	layers.process(synth.render(settle, rpm, thr, redline), rpm, thr, redline)
	var buf := PackedVector2Array()
	var n := int(synth.mix_rate * secs)
	while buf.size() < n:
		buf.append_array(layers.process(synth.render(BLOCK, rpm, thr, redline), rpm, thr, redline))
	return buf

# [rms, brightness, low share (<200 Hz), band 1-4 kHz share, peak]
func _measure(buf: PackedVector2Array, sr: float) -> PackedFloat32Array:
	var e := 0.0
	var ed := 0.0
	var el := 0.0
	var e1 := 0.0
	var e4 := 0.0
	var lp := 0.0
	var lp1 := 0.0
	var lp4 := 0.0
	var prev := 0.0
	var peak := 0.0
	var k := 1.0 - exp(-TAU * 200.0 / sr)
	var k1 := 1.0 - exp(-TAU * 1000.0 / sr)
	var k4 := 1.0 - exp(-TAU * 4000.0 / sr)
	for s in buf:
		var x := s.x
		peak = maxf(peak, absf(x))
		e += x * x
		ed += (x - prev) * (x - prev)
		prev = x
		lp += k * (x - lp)
		el += lp * lp
		lp1 += k1 * (x - lp1)
		lp4 += k4 * (x - lp4)
		var band := lp4 - lp1
		e1 += band * band
	var n := float(buf.size())
	return PackedFloat32Array([sqrt(e / n), sqrt(ed / maxf(e, 1e-9)), el / maxf(e, 1e-9), e1 / maxf(e, 1e-9), peak])

## Power at one frequency (Goertzel), in dB relative to full scale.
func _goertzel_db(buf: PackedVector2Array, sr: float, hz: float) -> float:
	var w := TAU * hz / sr
	var c := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for s in buf:
		var s0 := s.x + c * s1 - s2
		s2 = s1
		s1 = s0
	var p := s1 * s1 + s2 * s2 - c * s1 * s2
	return 10.0 * log(maxf(p, 1e-12) / (buf.size() * buf.size())) / log(10.0)

func _check_segments() -> void:
	var m := {}
	for id in CARS:
		m[id] = {}
		for seg in SEGMENTS:
			var a: Array = SEGMENTS[seg]
			var chain := _chain(id)
			var buf := _render(chain, a[0], a[1], a[2], SECS)
			var f := _measure(buf, chain[0].mix_rate)
			m[id][seg] = f
			var finite := true
			for s in buf:
				if is_nan(s.x) or is_inf(s.x):
					finite = false
					break
			var line := "%-13s %-8s rms %6.1f dB  peak %.3f  bright %.3f  low<200 %.3f  1-4k %.3f" % [
					id, seg, 20.0 * log(maxf(f[0], 1e-9)) / log(10.0), f[4], f[1], f[2], f[3]]
			print(line)
			levels.append(line)
			if id == "p4_kei":
				if not finite:
					_fail("kei %s: non-finite sample" % seg)
				if f[4] < 0.05 or f[4] > 1.0:
					_fail("kei %s: peak %.3f outside 0.05..1.0" % [seg, f[4]])
			_save_wav(buf, chain[0].mix_rate, dir.path_join("%s_%s.wav" % [id, seg]))
	for other in ["p2_hothatch", "n2_cityhatch"]:
		for seg in ["idle", "mid"]:
			var k: PackedFloat32Array = m["p4_kei"][seg]
			var o: PackedFloat32Array = m[other][seg]
			if k[2] >= o[2]:
				_fail("kei should be thinner than %s at %s (low share %.3f vs %.3f)" % [other, seg, k[2], o[2]])
			if k[1] <= o[1]:
				_fail("kei should be brighter than %s at %s (brightness %.3f vs %.3f)" % [other, seg, k[1], o[1]])
		# fingerprint distance, the same rule as tests/audio/engine_voice.gd
		var a: PackedFloat32Array = m["p4_kei"]["mid"]
		var b: PackedFloat32Array = m[other]["mid"]
		var d := 0.0
		for i in 4:
			d = maxf(d, absf(a[i] - b[i]) / maxf((a[i] + b[i]) * 0.5, 1e-9))
		if d < 0.08:
			_fail("kei and %s sound too alike (max feature difference %.1f%%)" % [other, d * 100.0])
	# the listening sweep: idle, rev to the limiter, bounce, coast down
	var chain := _chain("p4_kei")
	var synth: EngineSynth = chain[0]
	var sweep := PackedVector2Array()
	for seg in [[1.5, 1100.0, 1100.0, 0.0, false], [3.0, 1100.0, 8500.0, 1.0, false],
			[1.0, 8500.0, 8400.0, 1.0, true], [2.5, 8500.0, 1500.0, 0.0, false], [1.0, 1500.0, 1100.0, 0.0, false]]:
		var n := int(seg[0] * synth.mix_rate)
		var done := 0
		while done < n:
			var k := mini(BLOCK, n - done)
			var rpm := lerpf(seg[1], seg[2], float(done + k) / n)
			sweep.append_array(chain[1].process(synth.render(k, rpm, seg[3], seg[4]), rpm, seg[3], seg[4]))
			done += k
	_save_wav(sweep, synth.mix_rate, dir.path_join("kei_sweep.wav"))

func _check_layers() -> void:
	var sr: float = EngineSynth.new().mix_rate
	# gear whine: the mesh tone at 4500 rpm, layer on vs off
	var v := EngineVoice.for_car("p4_kei")
	var hz := 4500.0 / 60.0 * float(v["whine_teeth"])
	var on := _goertzel_db(_render(_chain("p4_kei"), 4500.0, 0.6, false, 1.0), sr, hz)
	var off := _goertzel_db(_render(_chain("p4_kei", {"whine": 0.0}), 4500.0, 0.6, false, 1.0), sr, hz)
	var line := "whine at %.0f Hz: on %.1f dB, off %.1f dB" % [hz, on, off]
	print(line)
	levels.append(line)
	if on - off < 6.0:
		_fail("gear whine should add 6 dB at %.0f Hz (got %.1f)" % [hz, on - off])
	# intake: 1-4 kHz share flat out, layer on vs off
	var wi := _measure(_render(_chain("p4_kei"), 6000.0, 1.0, false, 1.0), sr)[3]
	var wo := _measure(_render(_chain("p4_kei", {"intake": 0.0}), 6000.0, 1.0, false, 1.0), sr)[3]
	line = "intake 1-4 kHz share at 6000 rpm flat out: on %.3f, off %.3f" % [wi, wo]
	print(line)
	levels.append(line)
	if wi <= wo * 1.1:
		_fail("intake whir should lift the 1-4 kHz share by 10%% (on %.3f, off %.3f)" % [wi, wo])
	# rattle: clicks in 2 s of idle vs 2 s on the limiter
	var ci := _chain("p4_kei")
	_render(ci, 1100.0, 0.0, false, 2.0)
	var cl := _chain("p4_kei")
	_render(cl, 8500.0, 1.0, true, 2.0)
	var ni: int = ci[1].rattle_clicks
	var nl: int = cl[1].rattle_clicks
	line = "rattle clicks in 2 s: idle %d, limiter %d" % [ni, nl]
	print(line)
	levels.append(line)
	if ni <= nl or ni < 6:
		_fail("rattle should be densest at idle (idle %d clicks, limiter %d)" % [ni, nl])
	# the layers stay off for a car that sets none
	var coupe := EngineLayers.new()
	coupe.apply_voice(EngineVoice.for_car("p1_coupe"))
	if coupe.active:
		_fail("the coupe's voice should not switch the layers on")

func _check_cost() -> void:
	var best := INF
	var best_layers := INF
	for r in 3:
		var chain := _chain("p4_kei")
		var synth: EngineSynth = chain[0]
		var layers: EngineLayers = chain[1]
		var sr := synth.mix_rate
		var total := 0
		var t_all := 0
		var t_layers := 0
		for seg in [[1.0, 1100.0, 1100.0, 0.0, false], [2.0, 1100.0, 8500.0, 1.0, false],
				[1.0, 8500.0, 8400.0, 1.0, true], [1.5, 8500.0, 1500.0, 0.0, false]]:
			var n := int(seg[0] * sr)
			var done := 0
			while done < n:
				var k := mini(BLOCK, n - done)
				var rpm := lerpf(seg[1], seg[2], float(done + k) / n)
				var t0 := Time.get_ticks_usec()
				var buf := synth.render(k, rpm, seg[3], seg[4])
				var t1 := Time.get_ticks_usec()
				layers.process(buf, rpm, seg[3], seg[4])
				var t2 := Time.get_ticks_usec()
				t_all += t2 - t0
				t_layers += t2 - t1
				done += k
				total += k
		best = minf(best, float(t_all) / 1e6 / (total / sr))
		best_layers = minf(best_layers, float(t_layers) / 1e6 / (total / sr))
	var synth_only := best - best_layers
	var line := "render cost: synth + layers %.1f%% of real time (synth %.1f%%, layers %.1f%%)" % [
			best * 100.0, synth_only * 100.0, best_layers * 100.0]
	print(line)
	levels.append(line)
	# The absolute number swings with whatever else the laptop is running (the
	# synth alone measures 2% on a quiet one and 25% under a full load), so the
	# layers are judged against the synth they ride on: under half its cost.
	if best_layers > synth_only * 0.5:
		_fail("layers cost %.1f%% of real time, over half the synth's %.1f%%" % [best_layers * 100.0, synth_only * 100.0])
	if best > 0.25:
		print("WARN: synth + layers %.1f%% of real time is over 25%%; see tests/audio/engine_voice.gd for the synth alone" % (best * 100.0))

func _save_wav(audio: PackedVector2Array, sr: float, path: String) -> void:
	var bytes := PackedByteArray()
	bytes.resize(audio.size() * 2)
	for i in audio.size():
		bytes.encode_s16(i * 2, int(clampf(audio[i].x, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(sr)
	wav.data = bytes
	if wav.save_to_wav(path) != OK:
		_fail("could not save " + path)

func _process(_delta: float) -> bool:
	frame += 1
	if frame < LIVE_FRAMES:
		return false
	if frame > LIVE_FRAMES:
		if frame == LIVE_FRAMES + 30:
			print("PASS" if fails == 0 else "%d failure(s)" % fails)
			quit(1 if fails > 0 else 0)
		return false
	var p: PlayerCar = game.get("player")
	var audio: EngineAudio = null
	for c in p.get_children():
		if c is EngineAudio:
			audio = c
	if audio == null:
		_fail("player car has no EngineAudio child")
	else:
		if not audio.playing:
			_fail("EngineAudio is not playing")
		if audio.layers == null:
			_fail("EngineAudio has no layers")
	game.queue_free()
	return false
