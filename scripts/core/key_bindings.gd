class_name KeyBindings
extends RefCounted

# Key rebinding (Settings > Controls). Each action can have up to SLOTS
# keyboard keys; gamepad bindings are never touched. Changes apply to the
# InputMap at once; Save writes the actions that differ from the defaults as
# key positions under [keys] in the shared settings.cfg, and load_settings()
# puts them back at start. Reset puts the defaults back in memory (Save keeps
# them).
#
# Keys are bound by POSITION (physical_keycode), not by the letter on the cap
# (Roy 1263): W A S D stay under the left hand on an AZERTY keyboard. The codes
# are the US-layout names, so a save written before this still means the same
# physical keys. Every key an action gets is turned into a position binding
# here, whatever script registered it. The Controls page shows the label from
# the player's own layout (key_name).
#
# The defaults are a snapshot taken the first time anything here runs, after
# photo mode has registered its own actions. They are NOT read back with
# InputMap.load_from_project_settings(), which would delete the photo_* actions
# (PhotoMode.ensure_actions adds them at run time, they are not in
# project.godot) and leave photo mode dead until the next launch.
#
# Giving a key to an action takes it away from any other action in the same
# context and that action gets the old key instead (a swap), so two actions
# never share a key by accident. Photo mode's camera keys and the car wash's
# scrubbing keys are their own contexts: they reuse W/A/S/D/arrows on purpose
# and never clash with driving. Esc is reserved for pause / back: it can't be
# given to another action and pause can't be moved off it.

const SLOTS := 2
const RESERVED: Array[int] = [KEY_ESCAPE]
const PAUSE := &"pause"
const CONTEXTS := ["play", "photo", "wash"]

## Keys that were an action's default and then moved (key map K1). A saved key
## equal to one of these is the old default, not a choice: dropped on load so
## the new default applies. (Actions that were removed need no entry: a saved
## key for an action that no longer exists is ignored.)
const OLD_DEFAULTS := {
	&"put_back": [KEY_V],
	&"photo_mode": [KEY_F12],
	# the lowrider moved from the digit row to the numpad
	&"hyd_pump_left": [KEY_7], &"hyd_pump_front": [KEY_8], &"hyd_pump_back": [KEY_9], &"hyd_pump_right": [KEY_0],
	&"hyd_three": [KEY_6],
}

## Numpad keys read "Numpad 7", never just "7": they are a different key from
## the digit row above the letters.
const NUMPAD_NAMES := {
	KEY_KP_0: "Numpad 0", KEY_KP_1: "Numpad 1", KEY_KP_2: "Numpad 2", KEY_KP_3: "Numpad 3",
	KEY_KP_4: "Numpad 4", KEY_KP_5: "Numpad 5", KEY_KP_6: "Numpad 6", KEY_KP_7: "Numpad 7",
	KEY_KP_8: "Numpad 8", KEY_KP_9: "Numpad 9", KEY_KP_ADD: "Numpad +", KEY_KP_SUBTRACT: "Numpad -",
	KEY_KP_MULTIPLY: "Numpad *", KEY_KP_DIVIDE: "Numpad /", KEY_KP_PERIOD: "Numpad .",
	KEY_KP_ENTER: "Numpad Enter",
}

## action -> its key events as they were at start (the defaults).
static var _defaults := {}

## The key position of an event: physical_keycode, or keycode for an event that
## was never converted.
static func code_of(ev: InputEventKey) -> int:
	return ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode

## Key positions of an action, in InputMap order.
static func keys(action: StringName) -> Array[int]:
	var out: Array[int] = []
	if not InputMap.has_action(action):
		return out
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append(code_of(ev))
	return out

## What the key at this position says on the player's keyboard.
static func key_name(code: int) -> String:
	if code == 0:
		return "-"
	if NUMPAD_NAMES.has(code):
		return NUMPAD_NAMES[code]
	var label := 0
	if DisplayServer.get_name() != "headless":   # a headless run has no keyboard layout
		label = DisplayServer.keyboard_get_label_from_physical(code as Key)
	return OS.get_keycode_string((label if label != 0 else code) as Key)

## Game actions (not Godot's built-in ui_* ones).
static func game_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for a in InputMap.get_actions():
		if not String(a).begins_with("ui_"):
			out.append(a)
	return out

## "photo" for the free camera's own keys, "wash" for the car wash's scrubbing
## keys, "play" for everything else (photo mode's on/off key included: it is
## pressed while driving).
static func context(action: StringName) -> String:
	var n := String(action)
	if n.begins_with("photo_") and n != "photo_mode":
		return "photo"
	return "wash" if n.begins_with("wash_") else "play"

## The action other than `except`, in the same context, that uses this key, or &"" if none.
static func action_using(code: int, except: StringName = &"") -> StringName:
	for a in game_actions():
		if a != except and context(a) == context(except) and code in keys(a):
			return a
	return &""

## Turns every key event of an action that was written by letter into a
## position binding (keycode -> physical_keycode). Gamepad events stay.
static func _to_position(action: StringName) -> void:
	var need := false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and ev.keycode != 0 and ev.physical_keycode == 0:
			need = true
	if need:
		_write(action, keys(action))

## The default of one action, taken now.
static func _snapshot(action: StringName) -> void:
	_to_position(action)
	var events: Array = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			events.append(ev.duplicate())
	_defaults[action] = events

## Takes the defaults snapshot once. Safe to call any number of times.
static func ensure_defaults() -> void:
	if not _defaults.is_empty():
		return
	InputMap.load_from_project_settings()   # only here, before anything is rebound
	PhotoMode.ensure_actions()
	SpecialKeys.ensure_actions()
	WashScreen.ensure_actions()
	for a in game_actions():
		_snapshot(a)

## An action a script registered after the first snapshot (the drive recorder,
## the test cash key) gets its snapshot here, the first time it is asked for.
static func default_keys(action: StringName) -> Array[int]:
	ensure_defaults()
	if not _defaults.has(action) and InputMap.has_action(action):
		_snapshot(action)
	var out: Array[int] = []
	for ev in _defaults.get(action, []):
		out.append(code_of(ev))
	return out

## Puts `code` in the given slot (0 or 1) of an action. Returns false for a
## reserved key, for the pause action and for a bad slot. A key already used
## elsewhere is swapped (see header); a key moved between this action's own two
## slots swaps them.
static func set_key(action: StringName, slot: int, code: int) -> bool:
	ensure_defaults()
	if code == 0 or code in RESERVED or action == PAUSE or not InputMap.has_action(action):
		return false
	if slot < 0 or slot >= SLOTS:
		return false
	var mine := keys(action)
	var old := mine[slot] if slot < mine.size() else 0
	if old == code:
		return true
	var own := mine.find(code)
	if own >= 0:
		# It is already in this action's other slot: the two swap, neither is
		# lost. Onto an empty slot there is nothing to move.
		if old == 0:
			return true
		mine[own] = old
		mine[slot] = code
		_write(action, mine)
		return true
	var other := action_using(code, action)
	if other != &"":
		var theirs := keys(other)
		var i := theirs.find(code)
		# the other action gets the key this slot gave up, never a reserved one
		if old != 0 and not (old in RESERVED) and not (old in theirs):
			theirs[i] = old
		else:
			theirs.remove_at(i)
		_write(other, theirs)
	if slot < mine.size():
		mine[slot] = code
	else:
		mine.append(code)
	_write(action, mine)
	return true

## Replaces an action's keyboard events, keeping its gamepad ones.
static func _write(action: StringName, codes: Array[int]) -> void:
	if not InputMap.has_action(action):
		return
	_erase_keys(action)
	for c in codes:
		var k := InputEventKey.new()
		k.physical_keycode = c as Key
		InputMap.action_add_event(action, k)

static func _erase_keys(action: StringName) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)

## The defaults for every action, in memory (gamepad bindings never changed).
static func reset_defaults() -> void:
	ensure_defaults()
	for a in game_actions():
		if not _defaults.has(a):
			_snapshot(a)
	for a in _defaults:
		if not InputMap.has_action(a):
			continue
		_erase_keys(a)
		for ev in _defaults[a]:
			InputMap.action_add_event(a, ev.duplicate())

## True if any action's keys differ from the defaults.
static func differs_from_defaults() -> bool:
	for a in game_actions():
		if keys(a) != default_keys(a):
			return true
	return false

## Applies the saved [keys] section on top of the defaults. Every saved code is
## a key position. Then a clash check per context: the player's saved key wins.
static func load_settings() -> void:
	reset_defaults()
	var cfg := ConfigFile.new()
	if cfg.load(AudioSettings.path) != OK or not cfg.has_section("keys"):
		return
	var saved := {}   # action -> true, for the ones the player set
	for a in cfg.get_section_keys("keys"):
		var action := StringName(a)
		if not InputMap.has_action(action) or action == PAUSE:
			continue
		var raw: Variant = cfg.get_value("keys", a, [])
		if not (raw is Array or raw is PackedInt32Array):
			continue
		var codes: Array[int] = []
		var dropped := false
		for c in raw:
			var code := int(c)
			if code in OLD_DEFAULTS.get(action, []):
				dropped = true   # the old default, which moved: not a choice
			elif code != 0 and not (code in RESERVED) and not (code in codes) and codes.size() < SLOTS:
				codes.append(code)
		if dropped:   # the slot the old default held goes back to the default
			for d in default_keys(action):
				if codes.size() < SLOTS and not (d in codes):
					codes.append(d)
		if codes.is_empty():
			continue
		_write(action, codes)
		saved[action] = true
	resolve_clashes(saved)

## Per context: two actions on one key. The one the player saved keeps it; the
## other goes back to its default key if that is free, otherwise it is left
## without that key. `saved` is action -> true.
static func resolve_clashes(saved: Dictionary) -> void:
	for _pass in 16:
		var clash := _first_clash()
		if clash.is_empty():
			return
		var who: Array = clash.who
		var keeper: StringName = who[0]
		for a in who:
			if saved.has(a):
				keeper = a
				break
		for a in who:
			if a != keeper:
				_free_key(a, clash.code)

## {code, who: [actions]} of the first key two actions of one context share, or {}.
static func _first_clash() -> Dictionary:
	for ctx in CONTEXTS:
		var users := {}   # code -> [actions]
		for a in game_actions():
			if context(a) != ctx:
				continue
			for c in keys(a):
				users[c] = users.get(c, []) + [a]
		for code in users:
			if users[code].size() > 1:
				return {"code": code, "who": users[code]}
	return {}

## Takes `code` away from `action`; its default key fills the gap when nobody
## else in the context uses that key.
static func _free_key(action: StringName, code: int) -> void:
	var mine := keys(action)
	var i := mine.find(code)
	if i < 0:
		return
	var fill := 0
	for d in default_keys(action):
		if d != code and not (d in mine) and action_using(d, action) == &"":
			fill = d
			break
	if fill != 0:
		mine[i] = fill
	else:
		mine.remove_at(i)
	_write(action, mine)

## Writes the actions whose keys differ from the defaults; the other sections
## of the file stay.
static func save_settings() -> bool:
	ensure_defaults()
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	if cfg.has_section("keys"):
		cfg.erase_section("keys")
	for a in game_actions():
		var now := keys(a)
		if now != default_keys(a):
			cfg.set_value("keys", String(a), PackedInt32Array(now))
	return cfg.save(AudioSettings.path) == OK
