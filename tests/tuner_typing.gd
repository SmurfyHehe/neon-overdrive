extends SceneTree

# Typing in a Tuner text field must not drive the game state. GameState polls
# T, Y and Esc, so typing "t" or "y" in the tune slot name box used to switch
# tabs, and Esc closed the whole screen. Runs the real Game.tscn and checks that
# - with the slot name box focused, typing t and y puts the letters in the box and
#   leaves the screen on the Auto-Tune tab
# - Esc in the box only leaves the box (focus dropped, text kept, screen open)
# - with no text field focused, T switches tab and Esc closes as before
#
# Paced in physics ticks. Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/tuner_typing.gd

const HOLD_TICKS := 6

var failures: Array[String] = []

func _initialize() -> void:
	change_scene_to_file("res://Game.tscn")
	_run()

func _run() -> void:
	if not await _until(func(): return _ready_game() != null, 15.0):
		return _end("Game.tscn never became ready")
	var game := _ready_game()
	var gs: GameState = game.game_state
	var screen: TunerScreen = _find(game, TunerScreen)
	if screen == null:
		return _end("Game has no TunerScreen")
	var edit: LineEdit = screen.auto.slot_name_edit

	await _tap(KEY_Y)
	await _until(func(): return gs.state == GameState.State.AUTOTUNE, 5.0)
	_check(gs.state == GameState.State.AUTOTUNE and screen.auto.is_visible_in_tree(), "Y should open Auto-Tune")
	edit.grab_focus()
	_check(root.gui_get_focus_owner() == edit, "slot name box should take focus")

	# Typing the letters of the tab keys.
	await _tap(KEY_T, "t")
	await _tap(KEY_Y, "y")
	await _ticks(10)
	_check(edit.text == "ty", "the letters should reach the box, it holds '%s'" % edit.text)
	_check(gs.state == GameState.State.AUTOTUNE, "typing t then y switched the tab (state %d)" % gs.state)
	_check(screen.visible and paused, "typing closed the screen or unpaused the game")

	# Esc leaves the box, not the screen.
	await _tap(KEY_ESCAPE)
	await _ticks(10)
	_check(gs.state == GameState.State.AUTOTUNE and screen.visible and paused, "Esc in the box closed the Tuner (state %d)" % gs.state)
	_check(root.gui_get_focus_owner() != edit, "Esc should drop focus from the box")
	_check(edit.text == "ty", "Esc should keep the text")

	# Not typing: the keys work again.
	await _tap(KEY_T)
	await _until(func(): return gs.state == GameState.State.TUNING, 5.0)
	_check(gs.state == GameState.State.TUNING, "T with no text field focused should switch to the Tuner tab")
	await _tap(KEY_ESCAPE)
	await _until(func(): return gs.state == GameState.State.PLAYING, 5.0)
	_check(gs.state == GameState.State.PLAYING and not paused, "Esc with no text field focused should close the Tuner")
	_end("")

func _end(msg: String) -> void:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("tuner_typing: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _ready_game() -> Node:
	var g := current_scene
	if g != null and is_instance_valid(g) and g.get("player") != null and g.get("game_state") != null:
		return g
	return null

func _until(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if (Time.get_ticks_msec() - t0) / 1000.0 > timeout_s:
			return false
		await physics_frame
	return true

func _ticks(n: int) -> void:
	for i in n:
		await physics_frame

# A tap; `character` is the text the key types into a focused text field.
func _tap(code: Key, character := "") -> void:
	_key(code, true, character)
	await _ticks(HOLD_TICKS)
	_key(code, false)
	# Key events reach the GUI when the input buffer is flushed, once per rendered
	# frame; under load several physics ticks can pass in one frame.
	await process_frame
	await process_frame

func _key(code: Key, pressed: bool, character := "") -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	if character != "":
		ev.unicode = character.unicode_at(0)
	Input.parse_input_event(ev)

func _find(game: Node, type) -> Node:
	for c in game.get_children():
		if is_instance_of(c, type):
			return c
	return null

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
