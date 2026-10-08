extends SceneTree

# Key rebinding (menus A-list, 2026-10-08):
# - set_key puts a key in a slot and keeps the gamepad binding
# - a key already used elsewhere swaps (the other action gets the old key)
# - Esc can't be bound
# - save writes only changed actions, load applies them, reset restores defaults
# - the Controls page: click a key, press a new one, Save; Back without Save reverts
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/key_bindings.gd

var failures: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	AudioSettings.path = "user://key_bindings_test.cfg"
	DirAccess.remove_absolute(AudioSettings.path)
	KeyBindings.load_settings()
	var w := KeyBindings.keys(&"accelerate")
	_check(w.size() >= 1 and w[0] == KEY_W, "accelerate should default to W, got %s" % [w])
	var pads_before := _pad_events(&"accelerate")

	_check(KeyBindings.set_key(&"accelerate", 0, KEY_I), "binding I should work")
	_check(KeyBindings.keys(&"accelerate")[0] == KEY_I, "slot 0 should now be I")
	_check(_pad_events(&"accelerate") == pads_before, "the gamepad trigger must survive a rebind")
	_check(not KeyBindings.set_key(&"accelerate", 0, KEY_ESCAPE), "Esc must be refused")

	# Swap: give accelerate the brake key S; brake should get I (accelerate's old key).
	_check(KeyBindings.set_key(&"accelerate", 0, KEY_S), "binding S should work")
	_check(KeyBindings.keys(&"accelerate")[0] == KEY_S, "accelerate slot 0 should be S")
	_check(not (KEY_S in KeyBindings.keys(&"brake")), "brake must lose S")
	_check(KEY_I in KeyBindings.keys(&"brake"), "brake should get the old key I")
	_check(KeyBindings.action_using(KEY_S, &"accelerate") == &"", "S should belong to one action only")

	_check(KeyBindings.save_settings(), "save failed")
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	_check(cfg.has_section_key("keys", "accelerate") and cfg.has_section_key("keys", "brake"), "changed actions should be saved")
	_check(not cfg.has_section_key("keys", "handbrake"), "unchanged actions should not be saved")
	_check(KeyBindings.keys(&"accelerate")[0] == KEY_S, "saving must not change the live keys")

	KeyBindings.reset_defaults()
	_check(KeyBindings.keys(&"accelerate")[0] == KEY_W, "reset should bring W back")
	KeyBindings.load_settings()
	_check(KeyBindings.keys(&"accelerate")[0] == KEY_S, "load should apply the saved S")
	_check(_pad_events(&"accelerate") == pads_before, "load must keep the gamepad trigger")

	# A damaged entry is ignored, not fatal.
	cfg.set_value("keys", "handbrake", "garbage")
	cfg.set_value("keys", "no_such_action", PackedInt32Array([KEY_Q]))
	cfg.save(AudioSettings.path)
	KeyBindings.load_settings()
	_check(KeyBindings.keys(&"handbrake").size() >= 1, "a damaged entry should leave the default")
	KeyBindings.reset_defaults()
	DirAccess.remove_absolute(AudioSettings.path)

var _step := 0
var _menu: PauseMenu
var _state: GameState

func _process(_delta: float) -> bool:
	_step += 1
	match _step:
		1:
			_state = GameState.new()
			root.add_child(_state)
			_menu = PauseMenu.new(_state)
			root.add_child(_menu)
		2:
			_state.pause()
			_menu.show_controls()
			var b := _key_button(&"handbrake", 0)
			_check(b != null, "Controls page should have a handbrake key button")
			if b != null:
				b.pressed.emit()
				_check(b.text == "Press a key", "clicking a key should wait for a new one")
				_press(KEY_K)
		3:
			_check(KeyBindings.keys(&"handbrake")[0] == KEY_K, "pressing K should bind the handbrake to K")
			_check(not _state.modal_open, "the capture should end after the key")
			_menu._leave_controls()  # Back without Save
			_check(KeyBindings.keys(&"handbrake")[0] == KEY_SPACE, "Back without Save should restore Space")
			_menu.show_controls()
			_key_button(&"handbrake", 0).pressed.emit()
			_press(KEY_K)
		4:
			_menu.controls_save_button.pressed.emit()
			_menu._leave_controls()
			_check(KeyBindings.keys(&"handbrake")[0] == KEY_K, "after Save, K should stay")
			var cfg := ConfigFile.new()
			cfg.load(AudioSettings.path)
			_check(cfg.has_section_key("keys", "handbrake"), "Save should write the file")
			_menu.show_controls()
			_key_button(&"handbrake", 0).pressed.emit()
			_press(KEY_ESCAPE)
		5:
			_check(KeyBindings.keys(&"handbrake")[0] == KEY_K, "Esc during capture should cancel, not bind")
			_check(_state.state == GameState.State.PAUSED, "Esc during capture must not resume the game")
			KeyBindings.reset_defaults()
			DirAccess.remove_absolute(AudioSettings.path)
			print("key_bindings: ", "FAIL" if not failures.is_empty() else "PASS")
			for f in failures:
				print("  - ", f)
			quit(1 if not failures.is_empty() else 0)
	return false

func _press(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)

func _key_button(action: StringName, slot: int) -> Button:
	for b in _menu._key_buttons(_menu.controls_scroll):
		if b.has_meta("bind") and b.get_meta("bind") == [action, slot] and not b.is_queued_for_deletion():
			return b
	return null

func _pad_events(action: StringName) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if not (ev is InputEventKey):
			out.append(ev.as_text())
	return out
