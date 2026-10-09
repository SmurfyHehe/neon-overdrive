extends SceneTree

# Audio CPU cost (2026-10-09, Roy's integrated-graphics laptop): how much of
# the main thread and of the whole process the car sounds take.
#
# Two measurements:
# 1. EngineSynth alone: renders SYNTH_SECS of a scripted drive in one go and
#    reports microseconds per sample. Deterministic, so it is the clean
#    before/after number for synth changes.
# 2. The game: boots Game.tscn on an empty road, drives for RUN_SECS at a
#    paced 60 fps and reports the mean and p95 of the main thread's _process
#    time per frame (Performance.TIME_PROCESS: the engine sound render, the
#    wind/road/tyre, driveline and crash updates, the radio). With
#    AUDIO_COST=off the player's four sound nodes are removed after boot, so
#    the difference between the two runs is their main-thread cost. The audio
#    thread's mixing cost is outside GDScript's view: tools/audio_cost.ps1 runs
#    both modes and compares the process's total CPU time.
#
# Asserts (exit code 1): no logged errors, the synth renders faster than real
# time, the car moved. Timings are reported, not asserted (machine dependent).
#
# Run (paced, so the audio thread runs at its real rate; no --fixed-fps):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/audio_cost.gd
#   AUDIO_COST=off  the same run without the player's sound nodes

const Harness := preload("res://tests/traffic_harness.gd")

const SYNTH_SECS := 20.0
const BLOCK := 735  # one 60 fps frame of 44.1 kHz audio
const RUN_SECS := 20.0
const WARMUP_SECS := 3.0

var logger := Harness.ErrorCounter.new()
var game: Node
var t := 0.0
var samples: PackedFloat32Array = []
var start_pos := Vector3.ZERO
var mode := "on"
var fails := 0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.add_logger(logger)
	mode = OS.get_environment("AUDIO_COST")
	if mode == "":
		mode = "on"
	_bench_synth()
	Engine.max_fps = 60
	seed(777)
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _bench_synth() -> void:
	var synth := EngineSynth.new()
	synth.apply_voice(EngineVoice.for_car("p1_coupe"))
	synth.tune = ExhaustTune.for_car("p1_coupe")
	var sr := synth.mix_rate
	var total := int(SYNTH_SECS * sr)
	var done := 0
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_MD5)
	var t0 := Time.get_ticks_usec()
	while done < total:
		var n := mini(BLOCK, total - done)
		var f := float(done) / total
		# idle, a full-throttle pull, limiter, lift-off and coast: all the voice paths
		var rpm := 1000.0 + 6000.0 * clampf(f * 2.5, 0.0, 1.0) * (1.0 if f < 0.7 else (1.0 - f) / 0.3)
		var thr := 1.0 if f > 0.1 and f < 0.7 else 0.0
		var block := synth.render(n, rpm, thr, f > 0.55 and f < 0.7)
		done += n
		digest.update(block.to_byte_array())
	var us := Time.get_ticks_usec() - t0
	var per_sample := float(us) / total
	print("synth: %.1f s of audio in %.1f ms = %.3f us/sample = %.1f%% of real time = %.2f ms per 60 fps frame"
			% [SYNTH_SECS, us / 1000.0, per_sample, 100.0 * us / (SYNTH_SECS * 1e6), per_sample * sr / 60.0 / 1000.0])
	# The same sweep must give the same samples on every branch: a synth change
	# that is only an optimisation keeps this hash.
	print("synth hash: ", digest.finish().hex_encode())
	if us > SYNTH_SECS * 1e6 * 0.5:
		_fail("synth slower than half real time")

func _press(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _process(delta: float) -> bool:
	if game == null:
		return true
	var p: PlayerCar = game.get("player")
	if p == null:
		_finish("game has no player")
		return true
	if t == 0.0:
		start_pos = p.global_position
		_press(KEY_W, true)
		if mode == "off":
			for c in p.get_children():
				if c is EngineAudio or c is CarAudio or c is DrivelineAudio or c is CrashAudio:
					p.remove_child(c)
					c.free()
		print("mode=%s audio nodes on player: %d" % [mode, _audio_nodes(p)])
	t += delta
	if p.gear >= 1 and p.gear < 6 and p.linear_velocity.length() > 9.0 * p.gear and not p.is_shifting:
		_press(KEY_E, true)
		_press(KEY_E, false)
	if t > WARMUP_SECS:
		samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	if t >= WARMUP_SECS + RUN_SECS:
		var s := Harness.stats(samples)
		var travel := p.global_position.distance_to(start_pos)
		print("game: frames=%d process mean=%.3f ms p95=%.3f ms max=%.3f ms travel=%.0f m"
				% [samples.size(), s.mean, s.p95, s.max, travel])
		if travel < 5.0:
			_fail("car only moved %.1f m" % travel)
		_finish("")
		return true
	return false

func _audio_nodes(p: Node) -> int:
	var n := 0
	for c in p.get_children():
		if c is EngineAudio or c is CarAudio or c is DrivelineAudio or c is CrashAudio:
			n += 1
	return n

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL: ", msg)

func _finish(msg: String) -> void:
	if msg != "":
		_fail(msg)
	for e in logger.errors:
		_fail("logged error: " + e)
	print("errors=%d warnings=%d" % [logger.errors.size(), logger.warnings])
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	OS.remove_logger(logger)
	quit(0 if fails == 0 else 1)
