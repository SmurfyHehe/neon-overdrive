extends SceneTree

# Game-state test (issue #27): runs the real Game.tscn and checks that
# - Esc pauses: tree paused, menu visible, the car stops moving
# - Esc again resumes: tree unpaused, menu hidden, the car moves again
# - Restart reloads the scene: a fresh Game node, unpaused, in PLAYING
# Quit is not exercised (it would end the test run itself).
#
# Exit code 1 on failure. Run (a window opens for a few seconds):
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/game_state.gd

var frame := 0
var failures: Array[String] = []
var paused_pos := Vector3.ZERO
var first_game: Node

func _initialize() -> void:
	change_scene_to_file("res://Game.tscn")

func _process(_delta: float) -> bool:
	frame += 1
	var game := current_scene
	match frame:
		20:
			first_game = game
			_key(KEY_W, true)
		180:
			_key(KEY_ESCAPE, true); _key(KEY_ESCAPE, false)
		185:
			_check(paused, "Esc should pause the tree")
			_check(game.game_state.state == GameState.State.PAUSED, "state should be PAUSED")
			_check(_menu(game).visible, "pause menu should be visible")
			paused_pos = game.player.global_position
		245:
			_check(game.player.global_position.distance_to(paused_pos) < 0.001,
				"car moved while paused (%s -> %s)" % [paused_pos, game.player.global_position])
			_key(KEY_ESCAPE, true); _key(KEY_ESCAPE, false)
		250:
			_check(not paused, "second Esc should unpause")
			_check(game.game_state.state == GameState.State.PLAYING, "state should be PLAYING")
			_check(not _menu(game).visible, "pause menu should hide on resume")
		330:
			_check(game.player.global_position.distance_to(paused_pos) > 0.5,
				"car should move again after resume")
			_key(KEY_W, false)
			game.game_state.pause()
			game.game_state.restart()
		350:
			_check(game != first_game and is_instance_valid(game), "restart should load a fresh Game")
			_check(not paused, "restart should leave the tree unpaused")
			_check(game.game_state.state == GameState.State.PLAYING, "fresh run starts PLAYING")
			for f in failures:
				printerr("FAIL: ", f)
			print("game_state: ", "PASS" if failures.is_empty() else "FAIL")
			quit(0 if failures.is_empty() else 1)
	return false

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _menu(game: Node) -> PauseMenu:
	for c in game.get_children():
		if c is PauseMenu:
			return c
	return null

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
