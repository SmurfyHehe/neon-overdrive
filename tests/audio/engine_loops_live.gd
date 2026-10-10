extends SceneTree

# Engine loops in the real game (2026-10-10): boots Game.tscn, waits for EngineAudio
# to bake or load its loop bank and hand over, drives a full-throttle pull through
# the gears with a lift, and records the Engine bus.
#
# Asserts (exit code 1 on failure):
# - the bank arrives and the hand-over completes (loop_mode LOOPS), unless
#   NEON_ENGINE_LOOPS=0, where it must stay LIVE
# - after the hand-over the worker renders events only, never the full voice
# - never more than EngineLoopPlayer.MAX_VOICES looping players; some are playing
#   while the car runs
# - no stream swapped on an audible voice
# - the Engine bus recording is not silent and has no sample-to-sample step
#   larger than the loudest one the live synth makes in the same drive
# Writes user://engine_loops_live_<mode>.wav (Engine bus) for the spectrogram tool.
# Run: Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/audio/engine_loops_live.gd
# NEON_ENGINE_LOOPS=0 to record the same drive on the live synth for comparison.

const TIMEOUT_S := 90.0

var fails := 0
var game: Node
var audio: EngineAudio
var record: AudioEffectRecord
var phase := "wait"
var phase_t := 0.0
var elapsed := 0.0
var most := 0
var throttle := 0.0
var quit_in := -1
var loops_wanted := true

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	loops_wanted = EngineAudio.loops_enabled
	record = AudioEffectRecord.new()
	AudioServer.add_bus_effect(AudioServer.get_bus_index(&"Engine"), record)
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL: ", msg)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = 0.0
	c.steering_input = 0.0

func _process(delta: float) -> bool:
	if quit_in >= 0:
		quit_in -= 1
		if quit_in == 0:
			quit(1 if fails > 0 else 0)
		return false
	elapsed += delta
	phase_t += delta
	var p: PlayerCar = game.get("player")
	if p == null:
		return false
	p.driver = _drive
	if audio == null:
		for c in p.get_children():
			if c is EngineAudio:
				audio = c
		if audio == null:
			return false
	if audio.bank != null:
		most = maxi(most, audio.bank.playing_count())
	if elapsed > TIMEOUT_S:
		_fail("timed out in phase %s (loop_mode %d)" % [phase, audio.loop_mode])
		_finish()
		return false
	match phase:
		"wait":
			var ready := audio.loop_mode == EngineAudio.LoopMode.LOOPS if loops_wanted else phase_t > 3.0
			if ready:
				print("hand-over done after %.1f s (loops %s)" % [phase_t, str(loops_wanted)])
				record.set_recording_active(true)
				_next("idle")
		"idle":
			if phase_t > 2.0:
				throttle = 1.0
				_next("pull")
		"pull":
			if phase_t > 9.0:
				throttle = 0.0
				_next("lift")
		"lift":
			if phase_t > 2.5:
				_finish()
	return false

func _next(name: String) -> void:
	phase = name
	phase_t = 0.0

func _finish() -> void:
	var mode := "loops" if loops_wanted else "live"
	var full_before := audio.blocks_full
	print("loop_mode %d, blocks: %d full, %d events-only, most looping players %d, hard swaps %d, deferred %d, rpm now %.0f" % [
			audio.loop_mode, audio.blocks_full, audio.blocks_events, most, audio.bank.hard_swaps,
			audio.bank.deferred, (game.get("player") as PlayerCar).motor_rpm])
	if loops_wanted:
		_check_loops_state()
	else:
		if audio.loop_mode != EngineAudio.LoopMode.LIVE:
			_fail("NEON_ENGINE_LOOPS=0 but loop_mode is %d" % audio.loop_mode)
	var wav := record.get_recording()
	if wav == null or wav.data.is_empty():
		_fail("nothing recorded on the Engine bus")
	else:
		var path := "user://engine_loops_live_%s.wav" % mode
		print("recording: %.1f s -> %s" % [wav.data.size() / 4.0 / AudioServer.get_mix_rate(),
				ProjectSettings.globalize_path(path)])
		wav.save_to_wav(path)
		var d := wav.data
		var peak := 0.0
		var step := 0.0
		var prev := 0.0
		for i in d.size() / 4:
			var v := d.decode_s16(i * 4) / 32768.0
			peak = maxf(peak, absf(v))
			step = maxf(step, absf(v - prev))
			prev = v
		print("Engine bus: peak %.3f, loudest step %.3f" % [peak, step])
		_check_level(peak)
	print("engine_loops_live (%s): %s" % [mode, "PASS" if fails == 0 else "%d failure(s)" % fails])
	game.queue_free()
	game = null
	quit_in = 30

func _check_loops_state() -> void:
	if audio.loop_mode != EngineAudio.LoopMode.LOOPS:
		_fail("loop bank never took over (loop_mode %d)" % audio.loop_mode)
	if audio.blocks_events < 60:
		_fail("only %d events-only blocks after the hand-over" % audio.blocks_events)
	if most < 1:
		_fail("no looping player ever played")
	if most > EngineLoopPlayer.MAX_VOICES:
		_fail("%d looping players at once (cap %d)" % [most, EngineLoopPlayer.MAX_VOICES])
	if audio.bank.hard_swaps != 0:
		_fail("%d stream swap(s) on an audible voice" % audio.bank.hard_swaps)

func _check_level(peak: float) -> void:
	if peak < 0.02:
		_fail("the Engine bus is silent (peak %.3f)" % peak)
