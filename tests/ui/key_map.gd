extends SceneTree

# The key map (Roy's decided table, key map K1), headless:
# - no two actions of one context share a physical key
# - Esc is on pause and nothing else; pause has Esc
# - every action has a key (hood_trunk may be missing while unbuilt)
# - mute, high_beam, camera_cycle and autotune_panel are gone
# - every default matches the table below
# - every key is bound by position (physical_keycode), never by letter
# - set_key(pause, ...) refuses; moving a key between an action's two slots
#   swaps them and loses nothing (B2, B3)
# - a settings.cfg written before the new map: the old defaults that moved are
#   dropped, the player's saved key wins a clash, the loser falls back or is
#   left unbound (B4)
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/ui/key_map.gd

const DriveRecorder := preload("res://scripts/core/drive_recorder.gd")
const Wallet := preload("res://scripts/core/wallet.gd")

const MAY_BE_MISSING := [&"hood_trunk"]
const GONE := [&"mute", &"high_beam", &"camera_cycle", &"autotune_panel"]

const TABLE := {
	&"accelerate": KEY_W, &"brake": KEY_S, &"steer_left": KEY_A, &"steer_right": KEY_D,
	&"handbrake": KEY_SPACE, &"reverse": KEY_R, &"starter": KEY_X, &"toggle_gearbox": KEY_G,
	&"shift_up": KEY_E, &"shift_down": KEY_Q, &"clutch": KEY_SHIFT, &"headlights": KEY_H, &"horn": KEY_J,
	&"turn_left": KEY_COMMA, &"turn_right": KEY_PERIOD, &"hazard": KEY_SLASH,
	&"look_left": KEY_LEFT, &"look_right": KEY_RIGHT, &"look_up": KEY_UP, &"look_down": KEY_DOWN,
	&"look_back": KEY_B, &"camera_view": KEY_F, &"window": KEY_Z, &"pause": KEY_ESCAPE,
	&"map": KEY_M, &"tuning_panel": KEY_T, &"radio_next": KEY_N, &"radio_power": KEY_V,
	&"flip_off": KEY_K, &"idle_action": KEY_L, &"photo_mode": KEY_P, &"put_back": KEY_F7,
	&"fix_car": KEY_F6,
}

var failures: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _keys_are(action: StringName, want: Array) -> bool:
	var k := KeyBindings.keys(action)
	if k.size() != want.size():
		return false
	for i in k.size():
		if k[i] != want[i]:
			return false
	return true

func _initialize() -> void:
	AudioSettings.path = "user://key_map_test.cfg"
	DirAccess.remove_absolute(AudioSettings.path)
	# the scripts that register their own actions in _ready (test cash, recorder)
	var rec := DriveRecorder.new(null)
	rec._ready()   # not in the tree: only the action it registers matters here
	var wallet := Wallet.new()
	wallet._ready()
	KeyBindings.ensure_defaults()
	KeyBindings.reset_defaults()
	_defaults_checks()
	_set_key_checks()
	_saved_checks()
	rec.free()
	wallet.free()
	DirAccess.remove_absolute(AudioSettings.path)
	KeyBindings.reset_defaults()
	print("key_map: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)

func _defaults_checks() -> void:
	var actions := KeyBindings.game_actions()
	_check(actions.size() > 20, "only %d actions: the InputMap is not loaded" % actions.size())
	# every key is a position binding
	for a in actions:
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey:
				_check(ev.physical_keycode != 0 and ev.keycode == 0,
					"%s is bound by letter, not position (keycode %d, physical %d)" % [a, ev.keycode, ev.physical_keycode])
	# no clash inside a context
	for ctx in KeyBindings.CONTEXTS:
		var by_key := {}
		for a in actions:
			if KeyBindings.context(a) != ctx:
				continue
			for c in KeyBindings.keys(a):
				by_key[c] = by_key.get(c, []) + [a]
		for c in by_key:
			_check(by_key[c].size() == 1, "%s context: %s is bound to %s" % [ctx, OS.get_keycode_string(c), by_key[c]])
	# Esc: pause and only pause
	_check(_keys_are(&"pause", [KEY_ESCAPE]), "pause lacks Esc: %s" % [KeyBindings.keys(&"pause")])
	for a in actions:
		if a != &"pause":
			_check(not (KEY_ESCAPE in KeyBindings.keys(a)), "%s is on Esc" % a)
	# every action has a key
	for a in actions:
		if a in MAY_BE_MISSING:
			continue
		_check(not KeyBindings.keys(a).is_empty(), "%s has no key" % a)
	# removed actions stay removed
	for g in GONE:
		_check(not InputMap.has_action(g), "%s still exists" % g)
	# the decided table
	for a in TABLE:
		if InputMap.has_action(a):
			_check(KeyBindings.keys(a)[0] == TABLE[a] if not KeyBindings.keys(a).is_empty() else false,
				"%s should be on %s, is on %s" % [a, OS.get_keycode_string(TABLE[a]), KeyBindings.keys(a)])
	# the lowrider is on the numpad, none of it on the digit row or on P
	for a in SpecialKeys.KEYS:
		if String(a).begins_with("hyd_"):
			var k := KeyBindings.keys(a)
			_check(k.size() == 1 and (k[0] >= KEY_KP_MULTIPLY and k[0] <= KEY_KP_9), "%s is not on the numpad: %s" % [a, k])
	_check(InputMap.has_action(&"put_back") and InputMap.has_action(&"photo_mode"), "put_back / photo_mode missing")
	_check(KeyBindings.key_name(KEY_W) == "W", "key name of W is '%s'" % KeyBindings.key_name(KEY_W))

func _set_key_checks() -> void:
	# B2: pause never moves, Esc is never handed out
	_check(not KeyBindings.set_key(&"pause", 0, KEY_W), "set_key(pause, 0, W) succeeded")
	_check(_keys_are(&"pause", [KEY_ESCAPE]), "pause moved")
	_check(not KeyBindings.set_key(&"handbrake", 0, KEY_ESCAPE), "Esc was given to the handbrake")
	# B3: moving a key between an action's own two slots swaps them
	_check(KeyBindings.action_using(KEY_F4, &"flip_off") == &"", "F4 is not free for the test")
	_check(KeyBindings.set_key(&"flip_off", 1, KEY_F4), "second slot refused")
	_check(_keys_are(&"flip_off", [KEY_K, KEY_F4]), "flip_off is %s" % [KeyBindings.keys(&"flip_off")])
	_check(KeyBindings.set_key(&"flip_off", 0, KEY_F4), "moving F4 to the first slot refused")
	var now := KeyBindings.keys(&"flip_off")
	_check(now.size() == 2 and KEY_K in now and KEY_F4 in now, "a key was lost moving between slots: %s" % [now])
	_check(now[0] == KEY_F4, "F4 is not in the first slot: %s" % [now])
	# a swap with another action still works and still bounds by position
	_check(KeyBindings.set_key(&"idle_action", 0, KEY_K), "taking K refused")
	_check(KeyBindings.keys(&"idle_action")[0] == KEY_K and KeyBindings.keys(&"flip_off").has(KEY_L),
		"swap: idle_action %s flip_off %s" % [KeyBindings.keys(&"idle_action"), KeyBindings.keys(&"flip_off")])
	KeyBindings.reset_defaults()
	# the digit row and the numpad are different keys: binding one never moves the other
	_check(_keys_are(&"hyd_pump_left", [KEY_KP_4]), "hyd_pump_left is %s" % [KeyBindings.keys(&"hyd_pump_left")])
	_check(KeyBindings.set_key(&"idle_action", 1, KEY_4), "digit 4 refused")
	_check(_keys_are(&"hyd_pump_left", [KEY_KP_4]), "binding digit 4 moved the numpad 4 action")
	_check(KeyBindings.action_using(KEY_4, &"flip_off") == &"idle_action", "digit 4 is not on idle_action")
	_check(KeyBindings.set_key(&"flip_off", 1, KEY_KP_1), "numpad 1 refused")
	_check(KeyBindings.keys(&"idle_action").has(KEY_4), "binding numpad 1 moved the digit 4")
	_check(KeyBindings.key_name(KEY_KP_4) != KeyBindings.key_name(KEY_4), "numpad 4 and 4 read the same")
	KeyBindings.reset_defaults()

func _saved_checks() -> void:
	# a save from before the new map: the old defaults, and a player's choice
	# that lands on a key a default now uses
	var cfg := ConfigFile.new()
	cfg.set_value("keys", "put_back", PackedInt32Array([KEY_V]))      # old default: dropped
	cfg.set_value("keys", "photo_mode", PackedInt32Array([KEY_F12]))  # old default: dropped
	cfg.set_value("keys", "mute", PackedInt32Array([KEY_J]))          # action is gone: ignored
	cfg.set_value("keys", "radio_next", PackedInt32Array([KEY_V]))    # the player's choice wins V
	cfg.set_value("keys", "horn", PackedInt32Array([KEY_J]))          # its default: stays
	cfg.set_value("keys", "handbrake", PackedInt32Array([KEY_U]))     # a free key: stays
	cfg.set_value("keys", "hyd_pump_left", PackedInt32Array([KEY_7]))  # the old digit-row default: moves to the numpad
	_check(cfg.save(AudioSettings.path) == OK, "could not write the test settings.cfg")
	KeyBindings.load_settings()
	_check(_keys_are(&"put_back", [KEY_F7]), "put_back kept the old V: %s" % [KeyBindings.keys(&"put_back")])
	_check(_keys_are(&"photo_mode", [KEY_P]), "photo_mode kept F12: %s" % [KeyBindings.keys(&"photo_mode")])
	_check(_keys_are(&"radio_next", [KEY_V]), "the player's V did not win: %s" % [KeyBindings.keys(&"radio_next")])
	_check(KeyBindings.keys(&"radio_power").is_empty(), "radio_power should be unbound (its V is taken): %s" % [KeyBindings.keys(&"radio_power")])
	_check(_keys_are(&"hyd_pump_left", [KEY_KP_4]), "hyd_pump_left kept the old 7: %s" % [KeyBindings.keys(&"hyd_pump_left")])
	_check(_keys_are(&"photo_mode", [KEY_P]), "photo_mode lost P")
	_check(_keys_are(&"handbrake", [KEY_U]), "handbrake lost its saved U: %s" % [KeyBindings.keys(&"handbrake")])
	_check(_keys_are(&"horn", [KEY_J]), "horn lost J: %s" % [KeyBindings.keys(&"horn")])
	for ctx in KeyBindings.CONTEXTS:
		var seen := {}
		for a in KeyBindings.game_actions():
			if KeyBindings.context(a) != ctx:
				continue
			for c in KeyBindings.keys(a):
				_check(not seen.has(c), "after load, %s is on %s and %s" % [OS.get_keycode_string(c), seen.get(c), a])
				seen[c] = a
	# a clash on a default key the player took: the default owner is left unbound
	KeyBindings.reset_defaults()
	cfg = ConfigFile.new()
	cfg.set_value("keys", "radio_next", PackedInt32Array([KEY_H]))     # H is the lights' default
	cfg.save(AudioSettings.path)
	KeyBindings.load_settings()
	_check(_keys_are(&"radio_next", [KEY_H]), "radio_next lost H")
	_check(KeyBindings.keys(&"headlights").is_empty(), "headlights should be unbound, its default H is taken: %s" % [KeyBindings.keys(&"headlights")])
	KeyBindings.reset_defaults()
