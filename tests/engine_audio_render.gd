extends SceneTree

# Engine-sound test: renders a scripted drive through EngineSynth offline,
# writes it to a WAV so it can be listened to without playing the game, then
# boots Game.tscn and checks the live EngineAudio node is attached and playing.
#
# The sweep: idle, full-throttle rev to the limiter, bounce on the limiter,
# lift off and coast down, idle.
#
# Asserts (exit code 1 on failure):
# - no NaN/inf samples, peak between 0.05 and 1.0 (audible, not clipping)
# - rendering costs under 25% of real time (it runs every frame in GDScript)
# - the player car has an EngineAudio child that is playing and bussed to Engine
# Reports: render cost as % of real time, peak level.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/engine_audio_render.gd
# Optional: set ENGINE_WAV=<path.wav> to choose where the WAV goes
# (default user://engine_sweep.wav).

const BLOCK := 512  # frames per render call, about one game frame's worth
const LIVE_FRAMES := 120

var fails := 0
var game: Node
var frame := 0

func _initialize() -> void:
	_render_sweep()
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL: ", msg)

func _render_sweep() -> void:
	var synth := EngineSynth.new()
	var sr := synth.mix_rate
	# [seconds, rpm from, rpm to, throttle, on limiter]
	var segments := [
		[2.0, 1000.0, 1000.0, 0.0, false],
		[4.0, 1000.0, 7000.0, 1.0, false],
		[1.5, 7000.0, 6900.0, 1.0, true],
		[3.0, 7000.0, 1500.0, 0.0, false],
		[1.5, 1500.0, 1000.0, 0.0, false],
	]
	var all := PackedVector2Array()
	var t0 := Time.get_ticks_usec()
	for seg in segments:
		var n := int(seg[0] * sr)
		var done := 0
		while done < n:
			var k := mini(BLOCK, n - done)
			var rpm := lerpf(seg[1], seg[2], float(done + k) / n)
			all.append_array(synth.render(k, rpm, seg[3], seg[4]))
			done += k
	var cost := float(Time.get_ticks_usec() - t0) / 1e6 / (all.size() / sr)

	var peak := 0.0
	for s in all:
		if is_nan(s.x) or is_inf(s.x):
			_fail("non-finite sample")
			break
		peak = maxf(peak, absf(s.x))
	print("render cost: %.1f%% of real time, peak %.3f" % [cost * 100.0, peak])
	if peak < 0.05 or peak > 1.0:
		_fail("peak %.3f outside 0.05..1.0" % peak)
	if cost > 0.25:
		_fail("render cost %.1f%% of real time exceeds 25%%" % (cost * 100.0))

	var bytes := PackedByteArray()
	bytes.resize(all.size() * 4)
	for i in all.size():
		var v := int(clampf(all[i].x, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 4, v)
		bytes.encode_s16(i * 4 + 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = int(sr)
	wav.data = bytes
	var path := OS.get_environment("ENGINE_WAV")
	if path == "":
		path = "user://engine_sweep.wav"
	var err := wav.save_to_wav(path)
	if err != OK:
		_fail("could not save %s (error %d)" % [path, err])
	else:
		print("wrote ", ProjectSettings.globalize_path(path))

func _process(_delta: float) -> bool:
	frame += 1
	if frame < LIVE_FRAMES:
		return false
	if frame > LIVE_FRAMES:
		# Godot leaks a still-playing generator's playback if it quits in
		# the same frame, so the game is freed first and we quit half a
		# second later.
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
		if audio.bus != &"Engine" or AudioServer.get_bus_index(&"Engine") < 0:
			_fail("EngineAudio is not on an existing Engine bus")
	game.queue_free()
	return false
