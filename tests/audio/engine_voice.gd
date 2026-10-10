extends SceneTree

# Per-car engine voice test (ROADMAP #80). Renders every car's voice through
# EngineSynth offline, then boots Game.tscn and checks the player's live synth
# got its voice from the spec.
#
# Asserts (exit code 1 on failure):
# - every preset renders finite audio with a peak in 0.05..1.0 and costs under
#   25% of real time, best of three sweeps (it runs every frame in GDScript)
# - each voice fires the right number of times per cycle; the boxer's gaps are
#   uneven and the straight six's are even
# - the six player voices are pairwise different (at least 8% apart on one of
#   level, brightness, low-end share or low-band pitch)
# - traffic voices are darker on average than player voices
# - wander makes a held rpm vary more than the steady voice does (anti-repetition)
# - the player car's live EngineSynth runs the p1_coupe voice (six cylinders)
# Writes one WAV per voice so they can be compared by ear.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/audio/engine_voice.gd
# Optional: ENGINE_VOICE_DIR=<folder> for the WAVs (default user://engine_voices).

const BLOCK := 512
const LIVE_FRAMES := 120

var fails := 0
var game: Node
var frame := 0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	_check_firing()
	_check_voices()
	_check_wander()
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL: ", msg)

# Renders one frame at a time and records the sample on which each firing
# starts (the synth's time-since-firing resets to 0).
func _check_firing() -> void:
	var expect := {"p1_coupe": 6, "p4_kei": 3, "p5_muscle": 8, "p6_crossover": 4}
	for id in expect:
		var synth := EngineSynth.new()
		synth.apply_voice(EngineVoice.for_car(id))
		var rpm := 3000.0
		var n := int(synth.mix_rate * 0.4)
		var fires := PackedInt32Array()
		for i in n:
			synth.render(1, rpm, 0.5, false)
			if synth._since == 0.0:
				fires.append(i)
		var cycles := rpm / 120.0 * 0.4
		var want: float = cycles * expect[id]
		if absf(fires.size() - want) > expect[id] + 1:
			_fail("%s fired %d times in 0.4 s, expected about %.0f" % [id, fires.size(), want])
		var lo := INF
		var hi := 0.0
		for i in range(1, fires.size()):
			var g := float(fires[i] - fires[i - 1])
			lo = minf(lo, g)
			hi = maxf(hi, g)
		var ratio := hi / lo
		print("%-14s %d firings, gap max/min %.2f" % [id, fires.size(), ratio])
		if id == "p6_crossover" and ratio < 1.2:
			_fail("boxer firing should be uneven (gap ratio %.2f)" % ratio)
		if id == "p1_coupe" and ratio > 1.05:
			_fail("straight-six firing should be even (gap ratio %.2f)" % ratio)

# [rms, brightness, low-end share, low-band zero crossings per second]
func _fingerprint(id: String) -> PackedFloat32Array:
	var synth := EngineSynth.new()
	synth.apply_voice(EngineVoice.for_car(id))
	synth.render(int(synth.mix_rate * 0.3), 3500.0, 0.5, false)  # settle
	var buf := PackedVector2Array()
	var n := int(synth.mix_rate * 1.5)
	while buf.size() < n:
		buf.append_array(synth.render(BLOCK, 3500.0, 0.5, false))
	var e := 0.0
	var ed := 0.0
	var el := 0.0
	var lp := 0.0
	var prev := 0.0
	var prev_lp := 0.0
	var zc := 0
	var lp_k := 1.0 - exp(-TAU * 300.0 / synth.mix_rate)
	for s in buf:
		var x := s.x
		e += x * x
		ed += (x - prev) * (x - prev)
		prev = x
		lp += lp_k * (x - lp)
		el += lp * lp
		if (lp >= 0.0) != (prev_lp >= 0.0):
			zc += 1
		prev_lp = lp
	var rms := sqrt(e / buf.size())
	return PackedFloat32Array([rms, sqrt(ed / maxf(e, 1e-9)), el / maxf(e, 1e-9), zc / 1.5])

func _check_voices() -> void:
	var dir := OS.get_environment("ENGINE_VOICE_DIR")
	if dir == "":
		dir = "user://engine_voices"
	DirAccess.make_dir_recursive_absolute(dir)
	var prints := {}
	for id in EngineVoice.PRESETS:
		var synth := EngineSynth.new()
		synth.apply_voice(EngineVoice.for_car(id))
		var all := _sweep(synth)
		# Best of three: the laptop runs other work, and one busy moment would
		# otherwise fail a voice that renders well inside budget.
		var cost: float = all[1]
		for r in 2:
			var again := EngineSynth.new()
			again.apply_voice(EngineVoice.for_car(id))
			cost = minf(cost, _sweep(again)[1])
		var audio: PackedVector2Array = all[0]
		var peak := 0.0
		for s in audio:
			if is_nan(s.x) or is_inf(s.x):
				_fail("%s: non-finite sample" % id)
				break
			peak = maxf(peak, absf(s.x))
		if peak < 0.05 or peak > 1.0:
			_fail("%s: peak %.3f outside 0.05..1.0" % [id, peak])
		if cost > 0.25:
			_fail("%s: render cost %.1f%% of real time exceeds 25%%" % [id, cost * 100.0])
		_save_wav(audio, synth.mix_rate, dir.path_join(id + ".wav"))
		prints[id] = _fingerprint(id)
		var f: PackedFloat32Array = prints[id]
		print("%-14s peak %.3f cost %4.1f%%  rms %.3f bright %.3f low %.2f zc %5.0f" % [id, peak, cost * 100.0, f[0], f[1], f[2], f[3]])
	print("wrote WAVs to ", ProjectSettings.globalize_path(dir))

	var players := ["p1_coupe", "p2_hothatch", "p3_tuner", "p4_kei", "p5_muscle", "p6_crossover", "p17_work_pickup"]
	for i in players.size():
		for j in range(i + 1, players.size()):
			var a: PackedFloat32Array = prints[players[i]]
			var b: PackedFloat32Array = prints[players[j]]
			var d := 0.0
			for k in a.size():
				d = maxf(d, absf(a[k] - b[k]) / maxf((a[k] + b[k]) * 0.5, 1e-9))
			if d < 0.08:
				_fail("%s and %s sound too alike (max feature difference %.1f%%)" % [players[i], players[j], d * 100.0])
	var pb := 0.0
	for id in players:
		pb += prints[id][1] / players.size()
	var tb := 0.0
	for id in ["n1_commuter", "n2_cityhatch", "n3_pickup"]:
		tb += prints[id][1] / 3.0
	print("mean brightness: player %.3f, traffic %.3f" % [pb, tb])
	if tb >= pb:
		_fail("traffic voices should be darker than player voices")

# Idle, rev to the limiter, bounce, coast down, idle. Returns [audio, cost].
func _sweep(synth: EngineSynth) -> Array:
	var sr := synth.mix_rate
	var segments := [
		[1.0, 1000.0, 1000.0, 0.0, false],
		[2.5, 1000.0, 7000.0, 1.0, false],
		[1.0, 7000.0, 6900.0, 1.0, true],
		[2.0, 7000.0, 1500.0, 0.0, false],
	]
	var all := PackedVector2Array()
	var t0 := Time.get_ticks_usec()
	for seg in segments:
		var n := int(seg[0] * sr)
		var done := 0
		while done < n:
			var k := mini(BLOCK, n - done)
			all.append_array(synth.render(k, lerpf(seg[1], seg[2], float(done + k) / n), seg[3], seg[4]))
			done += k
	return [all, float(Time.get_ticks_usec() - t0) / 1e6 / (all.size() / sr)]

# Level variation across 0.25 s windows of a held 3000 rpm, as a coefficient
# of variation. With wander the note should drift; without, only noise moves it.
func _window_cv(wander_on: bool) -> float:
	var synth := EngineSynth.new()
	synth.apply_voice(EngineVoice.for_car("p1_coupe"))
	if not wander_on:
		synth.wander = 0.0
	synth.render(int(synth.mix_rate * 0.5), 3000.0, 0.4, false)
	var win := int(synth.mix_rate * 0.25)
	var vals := PackedFloat32Array()
	for w in 40:
		var buf := synth.render(win, 3000.0, 0.4, false)
		var e := 0.0
		for s in buf:
			e += s.x * s.x
		vals.append(sqrt(e / win))
	var mean := 0.0
	for v in vals:
		mean += v / vals.size()
	var var_ := 0.0
	for v in vals:
		var_ += (v - mean) * (v - mean) / vals.size()
	return sqrt(var_) / mean

func _check_wander() -> void:
	var steady := _window_cv(false)
	var drift := _window_cv(true)
	print("held 3000 rpm level variation: steady %.2f%%, with wander %.2f%%" % [steady * 100.0, drift * 100.0])
	if drift < steady * 1.5:
		_fail("wander should make a held note vary (%.2f%% vs steady %.2f%%)" % [drift * 100.0, steady * 100.0])

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
		# freed first, quit later: a playing generator leaks if freed on quit
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
		var v := EngineVoice.for_car("p1_coupe")
		if audio.synth.cylinders != v.cylinders or not is_equal_approx(audio.synth.body_hz, v.body_hz):
			_fail("live synth runs %d cylinders at %.0f Hz body, expected the p1_coupe voice" % [audio.synth.cylinders, audio.synth.body_hz])
	game.queue_free()
	return false
