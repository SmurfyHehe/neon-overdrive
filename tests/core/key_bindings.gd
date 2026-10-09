extends SceneTree

# Key rebinding (Settings > Controls), headless:
# - set_key puts a key in a slot and keeps the gamepad binding
# - a key already used by another driving action swaps (that action gets the old key)
# - photo mode's camera keys are their own context: giving one W leaves accelerate on W
# - Esc can't be bound
# - save writes only changed actions and keeps the other sections; load applies them
# - Reset brings the defaults back WITHOUT deleting photo mode's run-time actions
#   (InputMap.load_from_project_settings would; photo mode stayed dead after a Reset)
# - a damaged entry is ignored
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/core/key_bindings.gd

var failures: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _pad_events(action: StringName) -> int:
	var n := 0
	for ev in InputMap.action_get_events(action):
		if not (ev is InputEventKey):
			n += 1
	return n

func _initialize() -> void:
	AudioSettings.path = "user://key_bindings_test.cfg"
	DirAccess.remove_absolute(AudioSettings.path)
	KeyBindings.load_settings()
	for action in PhotoMode.KEYS:
		_check(InputMap.has_action(action), "%s should exist after load" % action)
	var w := KeyBindings.keys(&"accelerate")
	_check(w.size() >= 1 and w[0] == KEY_W, "accelerate should default to W, got %s" % [w])
	var pads_before := _pad_events(&"accelerate")
	_check(pads_before >= 1, "accelerate should have a gamepad binding to protect")

	_check(KeyBindings.set_key(&"accelerate", 0, KEY_I), "binding I should work")
	_check(KeyBindings.keys(&"accelerate")[0] == KEY_I, "slot 0 should now be I")
	_check(_pad_events(&"accelerate") == pads_before, "the gamepad trigger must survive a rebind")
	_check(not KeyBindings.set_key(&"accelerate", 0, KEY_ESCAPE), "Esc must be refused")

	# Swap: give accelerate the brake key S; brake should get I (accelerate's old key).
	_check(KeyBindings.set_key(&"accelerate", 0, KEY_S), "binding S should work")
	_check(KeyBindings.keys(&"accelerate")[0] == KEY_S, "accelerate slot 0 should be S")
	_check(not (KEY_S in KeyBindings.keys(&"brake")), "brake must lose S")
	_check(KEY_I in KeyBindings.keys(&"brake"), "brake should get the old key I")
	_check(KeyBindings.action_using(KEY_S, &"accelerate") == &"", "S should belong to one driving action only")
	_check(KEY_S in KeyBindings.keys(&"photo_back"), "photo mode's Back keeps S: separate context")

	# Photo mode: moving its camera keys must not touch driving, and the reverse.
	var photo_w := KeyBindings.keys(&"photo_forward")
	_check(KeyBindings.set_key(&"photo_forward", 0, KEY_T), "binding T on photo_forward should work")
	_check(KeyBindings.keys(&"photo_forward")[0] == KEY_T, "photo_forward slot 0 should be T")
	_check(KeyBindings.set_key(&"photo_forward", 0, photo_w[0]), "putting W back on photo_forward")
	_check(KeyBindings.keys(&"brake").has(KEY_I), "driving keys stay put while photo keys change")

	_check(KeyBindings.save_settings(), "save failed")
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	_check(cfg.has_section_key("keys", "accelerate") and cfg.has_section_key("keys", "brake"), "changed actions should be saved")
	_check(not cfg.has_section_key("keys", "handbrake"), "unchanged actions should not be saved")
	_check(not cfg.has_section_key("keys", "photo_forward"), "an action put back to its default should not be saved")
	_check(KeyBindings.keys(&"accelerate")[0] == KEY_S, "saving must not change the live keys")
	AudioSettings.set_volume("Music", 0.5)
	AudioSettings.save_settings()
	cfg.load(AudioSettings.path)
	_check(cfg.has_section("keys"), "saving the volumes must keep the [keys] section")

	KeyBindings.reset_defaults()
	_check(KeyBindings.keys(&"accelerate")[0] == KEY_W, "reset should bring W back")
	_check(not KeyBindings.differs_from_defaults(), "after a reset nothing differs from the defaults")
	for action in PhotoMode.KEYS:
		_check(InputMap.has_action(action), "Reset must not delete photo mode's %s" % action)
		_check(KeyBindings.keys(action).size() == 1 and KeyBindings.keys(action)[0] == PhotoMode.KEYS[action], "%s should be back on its own key after Reset" % action)
	KeyBindings.load_settings()
	_check(KeyBindings.keys(&"accelerate")[0] == KEY_S, "load should apply the saved S")
	_check(_pad_events(&"accelerate") == pads_before, "load must keep the gamepad trigger")
	for action in PhotoMode.KEYS:
		_check(InputMap.has_action(action), "load must not delete photo mode's %s" % action)

	# Reset, then Save: the file goes back to no [keys] and photo mode still has its keys.
	KeyBindings.reset_defaults()
	_check(KeyBindings.save_settings(), "save after reset failed")
	cfg = ConfigFile.new()   # load() keeps what the object already holds
	cfg.load(AudioSettings.path)
	_check(not cfg.has_section("keys") or cfg.get_section_keys("keys").is_empty(), "Reset then Save should leave no [keys] entries")
	KeyBindings.load_settings()
	_check(KeyBindings.keys(&"accelerate")[0] == KEY_W, "after Reset + Save the next launch has W")
	for action in PhotoMode.KEYS:
		_check(InputMap.has_action(action), "photo action %s survives Reset + Save + load" % action)

	# A damaged entry is ignored, not fatal.
	cfg.set_value("keys", "handbrake", "garbage")
	cfg.set_value("keys", "no_such_action", PackedInt32Array([KEY_Q]))
	cfg.save(AudioSettings.path)
	KeyBindings.load_settings()
	_check(KeyBindings.keys(&"handbrake").size() >= 1, "a damaged entry should leave the default")
	KeyBindings.reset_defaults()
	DirAccess.remove_absolute(AudioSettings.path)
	print("key_bindings: ", "PASS" if failures.is_empty() else "FAIL")
	for f in failures:
		print("  - ", f)
	quit(0 if failures.is_empty() else 1)
