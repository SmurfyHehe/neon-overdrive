class_name KeyBindings
extends RefCounted

# Key rebinding (menus A-list, 2026-10-08). The Controls page lets the player
# give each action up to two keyboard keys; gamepad bindings are not touched.
# Bindings are saved as keycodes under [keys] in the shared settings.cfg, one
# entry per action that differs from the project defaults, and applied to the
# InputMap at start. Reset puts the project defaults back
# (InputMap.load_from_project_settings).
#
# Giving a key to an action takes it away from any other action that had it,
# and that action gets the old key instead (a swap), so two actions never share
# a key by accident. Esc is reserved for pause / back and can't be bound.

const SLOTS := 2
const RESERVED: Array[int] = [KEY_ESCAPE]

## Keyboard keycodes of an action, in InputMap order (at most SLOTS shown).
static func keys(action: StringName) -> Array[int]:
	var out: Array[int] = []
	if not InputMap.has_action(action):
		return out
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append(ev.keycode if ev.keycode != 0 else ev.physical_keycode)
	return out

static func key_name(code: int) -> String:
	return OS.get_keycode_string(code) if code != 0 else "-"

## Game actions (not Godot's built-in ui_* ones).
static func game_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for a in InputMap.get_actions():
		if not String(a).begins_with("ui_"):
			out.append(a)
	return out

## The action other than `except` that uses this key, or &"" if none.
static func action_using(code: int, except: StringName = &"") -> StringName:
	for a in game_actions():
		if a != except and code in keys(a):
			return a
	return &""

## Puts `code` in the given slot (0 or 1) of an action. Returns false for a
## reserved key. A key already used elsewhere is swapped (see header).
static func set_key(action: StringName, slot: int, code: int) -> bool:
	if code == 0 or code in RESERVED or not InputMap.has_action(action):
		return false
	var mine := keys(action)
	var old := mine[slot] if slot < mine.size() else 0
	if old == code:
		return true
	var other := action_using(code, action)
	if other != &"":
		var theirs := keys(other)
		var i := theirs.find(code)
		if old != 0 and not (old in theirs):
			theirs[i] = old
		else:
			theirs.remove_at(i)
		_write(other, theirs)
	if code in mine:  # moving it between this action's own slots
		mine.erase(code)
	if slot < mine.size():
		mine[slot] = code
	else:
		mine.append(code)
	_write(action, mine)
	return true

## Replaces an action's keyboard events, keeping its gamepad ones.
static func _write(action: StringName, codes: Array[int]) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	for c in codes:
		var k := InputEventKey.new()
		k.keycode = c as Key
		InputMap.action_add_event(action, k)

## Project defaults for every action (gamepad included, which never changes).
static func reset_defaults() -> void:
	InputMap.load_from_project_settings()

## Applies the saved [keys] section on top of the project defaults.
static func load_settings() -> void:
	InputMap.load_from_project_settings()
	var cfg := ConfigFile.new()
	if cfg.load(AudioSettings.path) != OK or not cfg.has_section("keys"):
		return
	for a in cfg.get_section_keys("keys"):
		if not InputMap.has_action(a):
			continue
		var raw: Variant = cfg.get_value("keys", a, [])
		if not (raw is Array or raw is PackedInt32Array):
			continue
		var codes: Array[int] = []
		for c in raw:
			var code := int(c)
			if code != 0 and not (code in RESERVED) and not (code in codes):
				codes.append(code)
		_write(a, codes)

## Writes the actions whose keys differ from the project defaults; the other
## sections of the file stay.
static func save_settings() -> bool:
	var current := {}
	for a in game_actions():
		current[a] = keys(a)
	InputMap.load_from_project_settings()
	var defaults := {}
	for a in game_actions():
		defaults[a] = keys(a)
	for a in current:
		_write(a, current[a])  # back to what the player has
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	if cfg.has_section("keys"):
		cfg.erase_section("keys")
	for a in current:
		if current[a] != defaults.get(a, []):
			cfg.set_value("keys", String(a), PackedInt32Array(current[a]))
	return cfg.save(AudioSettings.path) == OK
