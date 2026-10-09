class_name KeyBindings
extends RefCounted

# Key rebinding (Settings > Controls). Each action can have up to SLOTS
# keyboard keys; gamepad bindings are never touched. Changes apply to the
# InputMap at once; Save writes the actions that differ from the defaults as
# keycodes under [keys] in the shared settings.cfg, and load_settings() puts
# them back at start. Reset puts the defaults back in memory (Save keeps them).
#
# The defaults are a snapshot taken the first time anything here runs, after
# photo mode has registered its own actions. They are NOT read back with
# InputMap.load_from_project_settings(), which would delete the photo_* actions
# (PhotoMode.ensure_actions adds them at run time, they are not in
# project.godot) and leave photo mode dead until the next launch.
#
# Giving a key to an action takes it away from any other action in the same
# context and that action gets the old key instead (a swap), so two actions
# never share a key by accident. Photo mode's camera keys are their own
# context: they reuse W/A/S/D/arrows on purpose and never clash with driving.
# Esc is reserved for pause / back and can't be bound.

const SLOTS := 2
const RESERVED: Array[int] = [KEY_ESCAPE]

## action -> its key events as they were at start (the defaults).
static var _defaults := {}

## Keyboard keycodes of an action, in InputMap order.
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

## "photo" for the free camera's own keys, "play" for everything else (photo
## mode's on/off key included: it is pressed while driving).
static func context(action: StringName) -> String:
	var n := String(action)
	return "photo" if n.begins_with("photo_") and n != "photo_mode" else "play"

## The action other than `except`, in the same context, that uses this key, or &"" if none.
static func action_using(code: int, except: StringName = &"") -> StringName:
	for a in game_actions():
		if a != except and context(a) == context(except) and code in keys(a):
			return a
	return &""

## Takes the defaults snapshot once. Safe to call any number of times.
static func ensure_defaults() -> void:
	if not _defaults.is_empty():
		return
	InputMap.load_from_project_settings()   # only here, before anything is rebound
	PhotoMode.ensure_actions()
	for a in game_actions():
		var events: Array = []
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey:
				events.append(ev.duplicate())
		_defaults[a] = events

static func default_keys(action: StringName) -> Array[int]:
	ensure_defaults()
	var out: Array[int] = []
	for ev in _defaults.get(action, []):
		out.append(ev.keycode if ev.keycode != 0 else ev.physical_keycode)
	return out

## Puts `code` in the given slot (0 or 1) of an action. Returns false for a
## reserved key. A key already used elsewhere is swapped (see header).
static func set_key(action: StringName, slot: int, code: int) -> bool:
	ensure_defaults()
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
	if not InputMap.has_action(action):
		return
	_erase_keys(action)
	for c in codes:
		var k := InputEventKey.new()
		k.keycode = c as Key
		InputMap.action_add_event(action, k)

static func _erase_keys(action: StringName) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)

## The defaults for every action, in memory (gamepad bindings never changed).
static func reset_defaults() -> void:
	ensure_defaults()
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

## Applies the saved [keys] section on top of the defaults.
static func load_settings() -> void:
	reset_defaults()
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
			if code != 0 and not (code in RESERVED) and not (code in codes) and codes.size() < SLOTS:
				codes.append(code)
		_write(a, codes)

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
