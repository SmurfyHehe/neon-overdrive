class_name PauseMenu
extends CanvasLayer

# Pause overlay (issue #27). Deliberately plain: a dim backdrop and Godot's
# default buttons, no theme or styling. The menu's look is Roy's call later;
# restyle here without touching GameState.

# The Controls page is generated from the InputMap (action_get_events), so the
# list can't drift from the real bindings. GROUPS only decides the order and
# the plain-words labels; an action missing from it still shows up, under
# "Other", so a new binding is never silently left off the page.
const GROUPS := [
	["Drive", [
		["accelerate", "Throttle"], ["brake", "Brake / reverse"], ["handbrake", "Handbrake"],
		["steer_left", "Steer left"], ["steer_right", "Steer right"], ["reverse", "Reverse gear (when stopped)"]]],
	["Gears & Engine", [
		["shift_up", "Shift up (manual)"], ["shift_down", "Shift down (manual)"], ["toggle_gearbox", "Gearbox: auto / semi / manual"],
		["clutch", "Clutch (hold, manual)"], ["starter", "Starter (hold, manual)"]]],
	["Camera", [["camera_cycle", "Camera smoothing"], ["camera_view", "Chase / cockpit view"], ["look_back", "Look back (hold)"], ["look_glance", "Mirror glance (tap; steer picks side)"]]],
	["Audio & Radio", [["mute", "Mute"], ["radio_next", "Next radio station"]]],
	["Menus", [["pause", "Pause / back"], ["tuning_panel", "Tuning panel"], ["autotune_panel", "Auto-Tune panel"]]],
	["Exhaust", [
		["exhaust_loud_up", "Louder"], ["exhaust_loud_down", "Quieter"], ["exhaust_rasp_up", "More rasp"],
		["exhaust_rasp_down", "Less rasp"], ["exhaust_pops_up", "More pops"], ["exhaust_pops_down", "Fewer pops"]]],
]

const SILVER := Color("#C9CED6")
const AMBER := Color("#FFC066")

var game_state: GameState
var resume_button: Button
var volume_sliders := {}   # channel -> HSlider
var fov_slider: HSlider
var car_slider: HSlider
var detail_slider: HSlider
var fullscreen_check: CheckButton
var resolution_option: OptionButton
var display_page: VBoxContainer
var confirm: ConfirmBox
var pages: CenterContainer  # holds every page; slid in on open and page changes
var page_title: Label
var reset_button: Button
var service_button: Button
var restart_button: Button
var quit_button: Button
var title_back_button: Button
## Set while the menu is open as the title screen's Settings; called by Back.
var _title_back: Callable
var display_back_button: Button
var main_page: VBoxContainer
var controls_page: VBoxContainer
var controls_scroll: ScrollContainer
var controls_back_button: Button
var controls_save_button: Button
var controls_status: Label
var _capture := {}        # {action, slot, button} while waiting for a key
var _keys_dirty := false  # rebinds not saved yet
var _was_subpage := false  # Back slides the main page in from the other side

func _init(state: GameState) -> void:
	game_state = state

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10  # above the debug HUD
	visible = false

	# A light extra dim under the text; PauseLook does the main dim and blur.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.2)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	pages = center

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)  # 8 overflowed a 648 px window once Reset joined
	center.add_child(box)
	main_page = box

	var title := Label.new()
	title.text = "PAUSED"
	page_title = title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	# Volume sliders (Phase B). Keyboard: Tab or arrows to move, Left/Right to change.
	var vol_title := Label.new()
	vol_title.text = "Volume"
	vol_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(vol_title)
	for channel in AudioSettings.CHANNELS:
		var row := HBoxContainer.new()
		box.add_child(row)
		var name_label := Label.new()
		name_label.text = channel
		name_label.custom_minimum_size = Vector2(100, 0)
		row.add_child(name_label)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = AudioSettings.volumes[channel]
		s.custom_minimum_size = Vector2(180, 0)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.value_changed.connect(func(v: float) -> void:
			AudioSettings.set_volume(channel, v)
			AudioSettings.save_settings())
		row.add_child(s)
		volume_sliders[channel] = s

	# Traffic sliders (stage B step 3): car count and draw distance, applied to
	# the running TrafficManager at once and saved with the volumes.
	var traffic_title := Label.new()
	traffic_title.text = "Traffic"
	traffic_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(traffic_title)
	car_slider = _add_slider(box, "Cars", 0.0, TrafficSettings.CAR_COUNT_MAX, 5.0, TrafficSettings.car_count,
		func(v: float) -> void:
			TrafficSettings.set_car_count(int(v))
			TrafficSettings.save_settings()
			var traffic: Variant = get_parent().get("traffic")
			if traffic != null:
				traffic.set_car_count(TrafficSettings.car_count))
	detail_slider = _add_slider(box, "Draw dist", TrafficSettings.DETAIL_MIN, TrafficSettings.DETAIL_MAX, 10.0, TrafficSettings.detail_distance,
		func(v: float) -> void:
			TrafficSettings.set_detail_distance(v)
			TrafficSettings.save_settings()
			var traffic: Variant = get_parent().get("traffic")
			if traffic != null:
				traffic.detail_distance = TrafficSettings.detail_distance)

	# View slider (2026-10-06): the cockpit FOV, 55-78, default 62; the speed
	# widening (up to +6) rides on top of it. Applies at once, saved with the rest.
	var view_title := Label.new()
	view_title.text = "View"
	view_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(view_title)
	fov_slider = _add_slider(box, "Cockpit FOV", ViewSettings.COCKPIT_FOV_MIN, ViewSettings.COCKPIT_FOV_MAX, 1.0, ViewSettings.cockpit_fov,
		func(v: float) -> void:
			ViewSettings.set_cockpit_fov(v)
			ViewSettings.save_settings())

	resume_button = _add_button(box, "Resume", game_state.resume)
	_add_button(box, "Controls", show_controls)
	_add_button(box, "Display", show_display)
	reset_button = _add_button(box, "Reset to defaults", func() -> void:
		confirm.ask("Reset volume, traffic and view to their defaults?", "Reset", reset_main_defaults))
	service_button = _add_button(box, "Service car (reset wear)", _service_car)
	restart_button = _add_button(box, "Restart", func() -> void:
		confirm.ask("Restart the run?", "Restart", game_state.restart))
	quit_button = _add_button(box, "Quit", func() -> void:
		confirm.ask("Quit to desktop?", "Quit", game_state.quit))
	title_back_button = _add_button(box, "Back", close_title_settings)
	title_back_button.visible = false

	_build_controls_page(center)
	_build_display_page(center)
	confirm = ConfirmBox.new(game_state)
	add_child(confirm)  # last, so it draws over every page
	game_state.state_changed.connect(_on_state_changed)

## Display page (menus A-list, 2026-10-08): fullscreen and window size (the
## resolution scale is on the Graphics page, PR #232). Its own page, like Controls, because the main page already fills a
## 648 px window. Each change applies at once and is saved (DisplaySettings).
func _build_display_page(center: CenterContainer) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.visible = false
	center.add_child(box)
	display_page = box
	var title := Label.new()
	title.text = "DISPLAY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	fullscreen_check = CheckButton.new()
	fullscreen_check.text = "Fullscreen"
	fullscreen_check.button_pressed = DisplaySettings.fullscreen
	fullscreen_check.toggled.connect(func(on: bool) -> void:
		DisplaySettings.set_fullscreen(on)
		_apply_display())
	box.add_child(fullscreen_check)
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_label := Label.new()
	name_label.text = "Window size"
	name_label.custom_minimum_size = Vector2(100, 0)
	row.add_child(name_label)
	resolution_option = OptionButton.new()
	resolution_option.custom_minimum_size = Vector2(180, 0)
	for r in DisplaySettings.available_resolutions():
		resolution_option.add_item("%d x %d" % [r.x, r.y])
		resolution_option.set_item_metadata(resolution_option.item_count - 1, r)
	resolution_option.item_selected.connect(func(i: int) -> void:
		DisplaySettings.set_resolution(resolution_option.get_item_metadata(i))
		_apply_display())
	row.add_child(resolution_option)
	_sync_display_controls()
	_add_button(box, "Reset to defaults", func() -> void:
		confirm.ask("Reset the display settings to their defaults?", "Reset", reset_display_defaults))
	display_back_button = _add_button(box, "Back", show_main)

func show_display() -> void:
	_sync_display_controls()
	main_page.visible = false
	controls_page.visible = false
	display_page.visible = true
	_was_subpage = true
	MenuMotion.slide_in(pages)
	fullscreen_check.grab_focus()

func _apply_display() -> void:
	DisplaySettings.apply(get_window())
	DisplaySettings.save_settings()
	_sync_display_controls()

## Puts the display controls back in step with DisplaySettings (also after a reset).
func _sync_display_controls() -> void:
	fullscreen_check.set_pressed_no_signal(DisplaySettings.fullscreen)
	for i in resolution_option.item_count:
		if resolution_option.get_item_metadata(i) == DisplaySettings.resolution:
			resolution_option.select(i)
	resolution_option.disabled = DisplaySettings.fullscreen  # fullscreen uses the screen's own size

## Resets temperatures, tyre, clutch and brake wear (the garage will own this later).
func _service_car() -> void:
	var player: Variant = get_parent().get("player")
	if player != null and player.get("health") != null:
		player.health.repair()

func _add_slider(parent: Control, text: String, lo: float, hi: float, step: float, value: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_label := Label.new()
	name_label.text = text
	name_label.custom_minimum_size = Vector2(100, 0)
	row.add_child(name_label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(180, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(on_change)
	row.add_child(s)
	return s

func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 0)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _on_state_changed(new_state: GameState.State, _old_state: GameState.State) -> void:
	if _keys_dirty:  # left with Esc instead of Save: drop the unsaved rebinds
		KeyBindings.load_settings()
		_keys_dirty = false
	_set_title_mode(false)
	visible = new_state == GameState.State.PAUSED
	if visible:
		show_main()  # always reopen on the main page
		_squelch()

func _squelch() -> void:
	var sfx: Variant = get_parent().get("menu_sfx")
	if sfx != null:
		sfx.squelch()

## Volume, traffic and view back to their defaults (the Display page has its own reset).
func reset_main_defaults() -> void:
	for channel in AudioSettings.CHANNELS:
		AudioSettings.set_volume(channel, 1.0)
		volume_sliders[channel].set_value_no_signal(1.0)
	AudioSettings.save_settings()
	TrafficSettings.set_car_count(TrafficSettings.CAR_COUNT_DEFAULT)
	TrafficSettings.set_detail_distance(TrafficSettings.DETAIL_DEFAULT)
	TrafficSettings.save_settings()
	var traffic: Variant = get_parent().get("traffic")
	if traffic != null:
		traffic.set_car_count(TrafficSettings.car_count)
		traffic.detail_distance = TrafficSettings.detail_distance
	car_slider.set_value_no_signal(TrafficSettings.car_count)
	detail_slider.set_value_no_signal(TrafficSettings.detail_distance)
	ViewSettings.set_cockpit_fov(ViewSettings.COCKPIT_FOV_DEFAULT)
	ViewSettings.save_settings()
	fov_slider.set_value_no_signal(ViewSettings.cockpit_fov)

func reset_display_defaults() -> void:
	DisplaySettings.reset_defaults()
	_apply_display()

# ---------- opened from the title screen ----------
## The title screen's Settings: the same pages, without Resume / Service /
## Restart / Quit (there is no run yet), and Back returns to the title.
func open_title_settings(on_back: Callable) -> void:
	_title_back = on_back
	_set_title_mode(true)
	visible = true
	show_main()
	_squelch()

func close_title_settings() -> void:
	visible = false
	_set_title_mode(false)
	if _title_back.is_valid():
		_title_back.call()

## Esc is Back while the menu is the title screen's Settings (GameState ignores
## Esc in TITLE); the open "are you sure?" box takes it first.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not title_back_button.visible or confirm.is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if main_page.visible:
			close_title_settings()
		elif controls_page.visible:
			_leave_controls()
		else:
			show_main()

func _set_title_mode(on: bool) -> void:
	for b in [resume_button, service_button, restart_button, quit_button]:
		b.visible = not on
	title_back_button.visible = on
	page_title.text = "SETTINGS" if on else "PAUSED"

# ---------- Controls page ----------
func show_controls() -> void:
	_refresh_controls()
	controls_status.text = ""
	main_page.visible = false
	controls_page.visible = true
	_was_subpage = true
	MenuMotion.slide_in(pages)
	# Cap the list to the window so it scrolls instead of running off-screen.
	controls_scroll.custom_minimum_size = Vector2(700, maxf(get_viewport().get_visible_rect().size.y * 0.7, 160.0))
	controls_scroll.grab_focus()  # arrows / page keys scroll it

func show_main() -> void:
	main_page.visible = true
	controls_page.visible = false
	display_page.visible = false
	MenuMotion.slide_in(pages, Vector2.LEFT if _was_subpage else Vector2.RIGHT)
	_was_subpage = false
	(title_back_button if title_back_button.visible else resume_button).grab_focus()  # keyboard/controller can navigate the menu

func _build_controls_page(center: CenterContainer) -> void:
	controls_page = VBoxContainer.new()
	controls_page.add_theme_constant_override("separation", 8)
	controls_page.visible = false
	center.add_child(controls_page)
	var title := Label.new()
	title.text = "CONTROLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_page.add_child(title)
	controls_scroll = ScrollContainer.new()
	controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	controls_scroll.custom_minimum_size = Vector2(700, 380)
	controls_scroll.focus_mode = Control.FOCUS_ALL
	controls_page.add_child(controls_scroll)
	# Rebinding (menus A-list): click a key, press the new one. Changes apply at
	# once but only stick after Save; Back without Save puts the saved keys back.
	controls_status = Label.new()
	controls_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_status.add_theme_color_override("font_color", SILVER)
	controls_page.add_child(controls_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	controls_page.add_child(row)
	_add_button(row, "Reset", func() -> void:
		confirm.ask("Put every key back to the default?", "Reset", _reset_keys))
	controls_save_button = _add_button(row, "Save", _save_keys)
	controls_back_button = _add_button(row, "Back", _leave_controls)

## Rebuilds the list from the InputMap, so a rebound key shows up next time the page opens.
func _refresh_controls() -> void:
	for c in controls_scroll.get_children():
		c.queue_free()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_scroll.add_child(list)
	for group in controls_groups():
		var heading := Label.new()
		heading.text = group[0].to_upper()
		heading.add_theme_color_override("font_color", AMBER)
		list.add_child(heading)
		var grid := GridContainer.new()
		grid.columns = 2 + KeyBindings.SLOTS
		grid.add_theme_constant_override("h_separation", 16)
		list.add_child(grid)
		for entry in group[1]:
			_grid_label(grid, entry[1], SILVER, 260)
			var codes := KeyBindings.keys(entry[0])
			for slot in KeyBindings.SLOTS:
				var code: int = codes[slot] if slot < codes.size() else 0
				var b := Button.new()
				b.text = KeyBindings.key_name(code)
				b.custom_minimum_size = Vector2(110, 0)
				b.add_theme_color_override("font_color", AMBER)
				b.set_meta("bind", [StringName(entry[0]), slot])
				b.pressed.connect(_start_capture.bind(StringName(entry[0]), slot, b))
				grid.add_child(b)
			_grid_label(grid, gamepad_text(entry[0]), SILVER, 140)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		list.add_child(gap)

# ---------- rebinding ----------
func _start_capture(action: StringName, slot: int, button: Button) -> void:
	if not _capture.is_empty():
		return
	_capture = {"action": action, "slot": slot, "button": button}
	button.text = "Press a key"
	controls_status.text = "Press the new key for this action. Esc cancels."
	game_state.modal_open = true  # Esc cancels the capture, not the pause

## Catches the next key before the GUI does (so Enter or Space can be bound
## instead of pressing the focused button).
func _input(event: InputEvent) -> void:
	if _capture.is_empty() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var code: int = event.keycode if event.keycode != 0 else event.physical_keycode
	var action: StringName = _capture.action
	var slot: int = _capture.slot
	_capture = {}
	game_state.modal_open = false
	game_state.swallow_pause_press()
	if code == KEY_ESCAPE:
		_refresh_controls()
		controls_status.text = _unsaved_text()
		_focus_key(action, slot)
		return
	var other := KeyBindings.action_using(code, action)
	KeyBindings.set_key(action, slot, code)
	_keys_dirty = true
	_refresh_controls()
	controls_status.text = ("%s moved from %s (it got the old key)." % [KeyBindings.key_name(code), _label_for(other)]) if other != &"" else _unsaved_text()
	_focus_key(action, slot)

func _unsaved_text() -> String:
	return "Not saved yet: Save keeps these keys." if _keys_dirty else ""

func _save_keys() -> void:
	KeyBindings.save_settings()
	_keys_dirty = false
	controls_status.text = "Saved."

func _reset_keys() -> void:
	KeyBindings.reset_defaults()
	_keys_dirty = true
	_refresh_controls()
	controls_status.text = "Defaults back. Save to keep them."

## Back: unsaved changes are dropped (the saved keys come back).
func _leave_controls() -> void:
	if _keys_dirty:
		KeyBindings.load_settings()
		_keys_dirty = false
	show_main()

func _label_for(action: StringName) -> String:
	for g in GROUPS:
		for entry in g[1]:
			if entry[0] == String(action):
				return entry[1]
	return String(action).capitalize()

## After a rebuild, focus the key button that was just changed.
func _focus_key(action: StringName, slot: int) -> void:
	await get_tree().process_frame
	for b in _key_buttons(controls_scroll):
		if b.has_meta("bind") and b.get_meta("bind") == [action, slot]:
			b.grab_focus()
			return

func _key_buttons(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_key_buttons(c))
	return out

func _grid_label(parent: Control, text: String, colour: Color, min_w: float) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", colour)
	l.custom_minimum_size = Vector2(min_w, 0)
	parent.add_child(l)

## GROUPS plus an "Other" group for any game action not listed there.
## Built-in ui_* actions are not game controls and are skipped.
static func controls_groups() -> Array:
	var groups: Array = []
	var known := {}
	for g in GROUPS:
		var rows: Array = []
		for entry in g[1]:
			known[entry[0]] = true
			if InputMap.has_action(entry[0]):
				rows.append(entry)
		groups.append([g[0], rows])
	var other: Array = []
	for a in InputMap.get_actions():
		var name := String(a)
		if not known.has(name) and not name.begins_with("ui_"):
			other.append([name, name.capitalize()])
	if not other.is_empty():
		groups.append(["Other", other])
	return groups

## Keyboard bindings of an action, e.g. "W / Up".
static func keyboard_text(action: String) -> String:
	var parts: Array[String] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var t: String = ev.as_text_keycode() if ev.keycode != 0 else ev.as_text_physical_keycode()
			parts.append(t)
	return " / ".join(parts) if not parts.is_empty() else "-"

## Gamepad bindings of an action, e.g. "RT".
static func gamepad_text(action: String) -> String:
	var parts: Array[String] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			parts.append(_pad_button_name(ev.button_index))
		elif ev is InputEventJoypadMotion:
			parts.append(_pad_axis_name(ev.axis, ev.axis_value))
	return " / ".join(parts) if not parts.is_empty() else "-"

static func _pad_button_name(i: int) -> String:
	var names := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 6: "Start", 9: "LB", 10: "RB"}
	return names.get(i, "Button %d" % i)

static func _pad_axis_name(axis: int, value: float) -> String:
	match axis:
		JOY_AXIS_LEFT_X: return "Left stick " + ("right" if value > 0.0 else "left")
		JOY_AXIS_LEFT_Y: return "Left stick " + ("down" if value > 0.0 else "up")
		JOY_AXIS_TRIGGER_LEFT: return "LT"
		JOY_AXIS_TRIGGER_RIGHT: return "RT"
	return "Axis %d" % axis
