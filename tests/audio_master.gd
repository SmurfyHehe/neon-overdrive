extends SceneTree

# Phase A audio checks (2026-10-05), silent:
# - the Master bus has an enabled hard limiter (no clipping when wind, engine and
#   squeal stack)
# - pausing mutes the Engine bus (its generator stops feeding while paused and
#   would click) and resuming unmutes it
# Exit code 1 on failure. Run (headless, no sound):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/audio_master.gd

const TIMEOUT_TICKS := 600

var tick := 0
var phase := 0
var phase_start := 0
var failures: Array[String] = []

func _initialize() -> void:
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("game_state") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var master := AudioServer.get_bus_index(&"Master")
	var engine := AudioServer.get_bus_index(&"Engine")
	match phase:
		0:
			var found := false
			for i in AudioServer.get_bus_effect_count(master):
				if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter and AudioServer.is_bus_effect_enabled(master, i):
					found = true
			_check(found, "Master bus has no enabled AudioEffectHardLimiter")
			_check(not AudioServer.is_bus_mute(engine), "Engine bus should start unmuted")
			game.game_state.pause()
			_next()
		1:
			if tick - phase_start >= 3:
				_check(AudioServer.is_bus_mute(engine), "pausing should mute the Engine bus")
				game.game_state.resume()
				_next()
		2:
			if tick - phase_start >= 3:
				_check(not AudioServer.is_bus_mute(engine), "resuming should unmute the Engine bus")
				return _end("")
	return false

func _next() -> void:
	phase += 1
	phase_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("audio_master: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
