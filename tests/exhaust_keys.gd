extends SceneTree

# Exhaust playtest keys: in the real Game.tscn the player car starts on the P1
# preset, holding U raises loudness, J lowers it, and the readout shows. The
# tune lives in the player's spec (the one copy the Tuner screen's sliders use
# too), is mirrored into the synth, and is saved to disk once the keys let go.
# The save goes to a scratch file, never the player's real one.
# Exit code 1 on failure. Run (silent, no window sound):
#   Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . -s res://tests/exhaust_keys.gd

const TIMEOUT_TICKS := 600
const HOLD_TICKS := 30
const SAVE_FILE := "user://autotune/test_exhaust_keys.json"

var tick := 0
var phase := 0
var phase_start := 0
var start := 0.0
var raised := 0.0

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://autotune"))
	var f := FileAccess.open(SAVE_FILE, FileAccess.WRITE)  # start empty (overwrite; never deleted)
	f.store_string("")
	f = null
	ExhaustTune.save_path = SAVE_FILE
	change_scene_to_file("res://Game.tscn")

func _physics_process(_delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var audio: EngineAudio = null
	for c in game.player.get_children():
		if c is EngineAudio:
			audio = c
	if audio == null:
		return _end("player has no EngineAudio")
	var t := audio.synth.tune
	match phase:
		0:
			if absf(t.loudness - ExhaustTune.for_car("p1_coupe").loudness) > 0.001:
				return _end("player did not start on the P1 preset")
			start = t.loudness
			_key(KEY_U, true)
			_next()
		1:
			if tick - phase_start >= HOLD_TICKS:
				_key(KEY_U, false)
				raised = t.loudness
				if raised <= start + 0.05:
					return _end("holding U did not raise loudness (%.3f -> %.3f)" % [start, raised])
				if not audio._label.visible:
					return _end("readout not shown after a change")
				_key(KEY_J, true)
				_next()
		2:
			if tick - phase_start >= HOLD_TICKS:
				_key(KEY_J, false)
				if t.loudness >= raised - 0.05:
					return _end("holding J did not lower loudness")
				if absf(game.player.spec.exhaust.loudness - t.loudness) > 0.0001:
					return _end("synth tune and spec disagree (%.3f vs %.3f)" % [t.loudness, game.player.spec.exhaust.loudness])
				_next()
		3:
			if tick - phase_start >= 10:
				var saved := ExhaustTune.load_saved("p1_coupe")
				if saved.is_empty() or absf(saved.loudness - t.loudness) > 0.002:
					return _end("tune not saved after the keys let go (%s)" % str(saved))
				return _end("")
	return false

func _next() -> void:
	phase += 1
	phase_start = tick

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _end(msg: String) -> bool:
	if msg != "":
		printerr("FAIL: ", msg)
	print("exhaust_keys: ", "PASS" if msg == "" else "FAIL")
	quit(0 if msg == "" else 1)
	return true
