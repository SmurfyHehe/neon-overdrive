class_name SettingsScreen
extends CanvasLayer

# The Settings screen: one place for everything that used to sit in the long
# pause column. Four pages behind a tab row:
#   Sound    Master / Engine / Effects / Music volume, Turbo volume
#   Picture  fullscreen and window size, graphics Low / Medium / High and the
#            settings behind them, traffic detail, night lights
#   Driving  cockpit FOV, camera, tyre smoke
#   Controls key rebinding (two keys per action) with Reset and Save
#
# Opened from the pause menu (PauseMenu) and from the title screen. It has no
# need of a GameState: from the title screen there is none. With one, it holds
# the game's shortcut keys off while open (GameState.set_modal) so Esc closes
# this screen instead of resuming the game. Every change applies at once and is
# saved, except key bindings, which apply at once but stick only after Save.

signal closed

const GameInfo := preload("res://scripts/core/game_info.gd")

const PAGES: Array[String] = ["Sound", "Picture", "Driving", "Controls"]
const SILVER := Color("#C9CED6")
const AMBER := Color("#FFC066")

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
	["Camera", [["camera_cycle", "Camera smoothing"], ["camera_view", "Chase / cockpit view"], ["look_back", "Look back (hold)"], ["look_left", "Look left (cockpit, hold)"], ["look_right", "Look right (cockpit, hold)"], ["look_up", "Look up (cockpit, hold)"], ["look_down", "Look down (cockpit, hold)"], ["window", "Side window (hold: down, tap: up)"]]],
	["Audio & Radio", [["mute", "Mute"], ["radio_next", "Next radio station"]]],
	["Photo mode", [["photo_mode", "Photo mode"], ["photo_forward", "Forward"], ["photo_back", "Back"], ["photo_left", "Left"], ["photo_right", "Right"], ["photo_down", "Down"], ["photo_up", "Up"], ["photo_fast", "Faster (hold)"], ["photo_look_left", "Look left"], ["photo_look_right", "Look right"], ["photo_look_up", "Look up"], ["photo_look_down", "Look down"], ["photo_fov_narrow", "Zoom in"], ["photo_fov_wide", "Zoom out"], ["photo_shot", "Save photo"]]],
	["Menus", [["pause", "Pause / back"], ["tuning_panel", "Tuning panel"], ["autotune_panel", "Auto-Tune panel"]]],
]

var game_state: GameState   # null on the title screen
var tab_buttons: Array[Button] = []
var pages: Array[Control] = []
var current_page := 0

# Sound
var volume_sliders := {}   # channel -> HSlider
# Picture
var fullscreen_check: CheckButton
var resolution_option: OptionButton
var gfx_preset: OptionButton
var gfx_aa: OptionButton
var gfx_scale: HSlider
var gfx_scale_label: Label
var gfx_mirrors: OptionButton
var gfx_dynres: OptionButton
var gfx_cap: OptionButton
var gfx_auto_label: Label
var traffic_cars_slider: HSlider
var traffic_dist_slider: HSlider
var night_lights_slider: HSlider
var city_lights_check: CheckButton
# Driving
var fov_slider: HSlider
var smoothing_slider: HSlider
var smoke_burnout_slider: HSlider
var smoke_drift_slider: HSlider
# Controls
var controls_scroll: ScrollContainer
var controls_status: Label
var controls_save_button: Button
var controls_reset_button: Button
var back_button: Button
var keys_dirty := false   # rebinds not saved yet

var _capture := {}        # {action, slot, button} while waiting for a key
var _syncing := false     # guards widget signals while values are pushed in
var _title: Label

func _init(state: GameState = null) -> void:
	game_state = state

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 11   # above the pause menu (10)
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)

	_title = Label.new()
	_title.text = "SETTINGS"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	# The tab row: moving focus onto a tab shows its page (Left / Right), Down
	# goes into the page.
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	box.add_child(tabs)
	for i in PAGES.size():
		var b := Button.new()
		b.text = PAGES[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(110, 0)
		b.pressed.connect(show_page.bind(i))
		b.focus_entered.connect(show_page.bind(i, false))
		tabs.add_child(b)
		tab_buttons.append(b)

	var stack := VBoxContainer.new()
	box.add_child(stack)
	pages.append(_build_sound_page(stack))
	pages.append(_build_picture_page(stack))
	pages.append(_build_driving_page(stack))
	pages.append(_build_controls_page(stack))

	back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(160, 0)
	back_button.pressed.connect(close)
	box.add_child(back_button)

	if game_state != null:
		game_state.state_changed.connect(_on_state_changed)
	show_page(0, false)

# ---------- opening and closing ----------
## Shows the screen on a page (a PAGES name or index).
func open(page: Variant = 0) -> void:
	_sync_all()
	visible = true
	if game_state != null:
		game_state.set_modal(true)
	show_page(PAGES.find(page) if page is String else int(page))

func close() -> void:
	if not visible:
		return
	_cancel_capture()
	if keys_dirty:   # left without Save: the saved keys come back
		KeyBindings.load_settings()
		keys_dirty = false
	visible = false
	if game_state != null:
		game_state.set_modal(false)
	closed.emit()

func show_page(index: int, take_focus := true) -> void:
	if index < 0 or index >= pages.size():
		return
	current_page = index
	for i in pages.size():
		pages[i].visible = i == index
		tab_buttons[i].set_pressed_no_signal(i == index)
	if index == 3:
		_refresh_controls()
	_fit_pages()
	if take_focus and visible:
		tab_buttons[index].grab_focus()

## Pages scroll when the window is short instead of running off the screen.
func _fit_pages() -> void:
	var h := get_viewport().get_visible_rect().size.y if is_inside_tree() else 720.0
	for p in pages:
		(p as ScrollContainer).custom_minimum_size = Vector2(660, clampf(h * 0.55, 160.0, 460.0))

func _on_state_changed(new_state: GameState.State, _old_state: GameState.State) -> void:
	if new_state != GameState.State.PAUSED and visible:
		close()

func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if not _capture.is_empty():
		get_viewport().set_input_as_handled()   # before the GUI: Enter / Space can be bound
		_finish_capture(event.keycode if event.keycode != 0 else event.physical_keycode)
		return
	if event.is_action_pressed(&"ui_cancel") and not _popup_open():
		get_viewport().set_input_as_handled()
		close()

func _popup_open() -> bool:
	for o in find_children("*", "OptionButton", true, false):
		if (o as OptionButton).get_popup().visible:
			return true
	return false

# ---------- widget helpers ----------
func _new_page(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.visible = false
	parent.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	return v

func _page_of(inner: Control) -> Control:
	return inner.get_parent()

func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", AMBER)
	parent.add_child(l)

func _add_slider(parent: Control, text: String, lo: float, hi: float, step: float, value: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_label := Label.new()
	name_label.text = text
	name_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(name_label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(220, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v: float) -> void:
		if not _syncing:
			on_change.call(v))
	row.add_child(s)
	return s

func _add_option(parent: Control, text: String, items: Array, on_select: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_label := Label.new()
	name_label.text = text
	name_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(name_label)
	var o := OptionButton.new()
	for item in items:
		o.add_item(item)
	o.custom_minimum_size = Vector2(220, 0)
	o.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			on_select.call(i))
	row.add_child(o)
	return o

func _add_check(parent: Control, text: String, on: bool, on_toggle: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(func(v: bool) -> void:
		if not _syncing:
			on_toggle.call(v))
	parent.add_child(c)
	return c

func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 0)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

## Pushes every setting's current value into its widget without firing the
## widget's own change handler.
func _sync_all() -> void:
	_syncing = true
	for channel in volume_sliders:
		volume_sliders[channel].value = AudioSettings.volumes[channel]
	fullscreen_check.button_pressed = DisplaySettings.fullscreen
	for i in resolution_option.item_count:
		if resolution_option.get_item_metadata(i) == DisplaySettings.resolution:
			resolution_option.select(i)
	resolution_option.disabled = DisplaySettings.fullscreen   # fullscreen uses the screen's own size
	var idx := GraphicsSettings.PRESETS.find(GraphicsSettings.preset)
	gfx_preset.select(idx if idx >= 0 else GraphicsSettings.PRESETS.size())
	gfx_aa.select(maxi(GraphicsSettings.AA_MODES.find(GraphicsSettings.aa), 0))
	gfx_scale.value = GraphicsSettings.render_scale
	gfx_scale_label.text = "%d%%" % roundi(GraphicsSettings.render_scale * 100.0)
	gfx_mirrors.select(FxSettings.mirror_quality)
	gfx_dynres.select(0 if GraphicsSettings.dynamic_res else 1)
	gfx_cap.select(maxi(GraphicsSettings.FPS_CAPS.find(GraphicsSettings.fps_cap), 0))
	gfx_auto_label.visible = GraphicsSettings.auto_picked
	traffic_cars_slider.value = TrafficSettings.car_count      # a tier may have moved these
	traffic_dist_slider.value = TrafficSettings.detail_distance
	night_lights_slider.value = TrafficSettings.light_glow
	city_lights_check.button_pressed = TrafficSettings.city_lights
	fov_slider.value = ViewSettings.cockpit_fov
	smoothing_slider.value = float(ViewSettings.camera_smoothing)
	smoke_burnout_slider.value = FxSettings.smoke_burnout
	smoke_drift_slider.value = FxSettings.smoke_drift
	_syncing = false

# ---------- Sound ----------
func _build_sound_page(parent: Control) -> Control:
	var page := _new_page(parent)
	_heading(page, "Volume")
	for channel in AudioSettings.CHANNELS:
		volume_sliders[channel] = _add_slider(page, channel, 0.0, 1.0, 0.05, AudioSettings.volumes[channel],
			func(v: float) -> void:
				AudioSettings.set_volume(channel, v)
				AudioSettings.save_settings())
	return _page_of(page)

# ---------- Picture ----------
func _build_picture_page(parent: Control) -> Control:
	var page := _new_page(parent)
	_heading(page, "Display")
	fullscreen_check = _add_check(page, "Fullscreen", DisplaySettings.fullscreen, func(on: bool) -> void:
		DisplaySettings.set_fullscreen(on)
		_display_changed())
	resolution_option = _add_option(page, "Window size", [], func(i: int) -> void:
		DisplaySettings.set_resolution(resolution_option.get_item_metadata(i))
		_display_changed())
	for r in DisplaySettings.available_resolutions():
		resolution_option.add_item("%d x %d" % [r.x, r.y])
		resolution_option.set_item_metadata(resolution_option.item_count - 1, r)

	_heading(page, "Graphics")
	gfx_preset = _add_option(page, "Quality", ["Low", "Medium", "High", "Custom"], func(i: int) -> void:
		if i < GraphicsSettings.PRESETS.size():
			GraphicsSettings.set_preset(GraphicsSettings.PRESETS[i])
		_graphics_changed())
	gfx_aa = _add_option(page, "Edge smoothing", GraphicsSettings.AA_NAMES, func(i: int) -> void:
		GraphicsSettings.set_aa(GraphicsSettings.AA_MODES[i])
		_graphics_changed())
	gfx_scale = _add_slider(page, "Resolution", GraphicsSettings.SCALE_MIN, GraphicsSettings.SCALE_MAX, 0.05, GraphicsSettings.render_scale,
		func(v: float) -> void:
			GraphicsSettings.set_render_scale(v)
			_graphics_changed())
	gfx_scale_label = Label.new()
	gfx_scale.get_parent().add_child(gfx_scale_label)
	# Tiers: the CPU side of a preset is the traffic sliders below plus the mirror render size.
	gfx_mirrors = _add_option(page, "Mirrors", ["Low", "Medium", "High"], func(i: int) -> void:
		FxSettings.set_mirror_quality(i)
		GraphicsSettings.refresh_preset()
		_graphics_changed())
	gfx_dynres = _add_option(page, "Dynamic resolution", ["On", "Off"], func(i: int) -> void:
		GraphicsSettings.set_dynamic_res(i == 0)
		_graphics_changed())
	gfx_cap = _add_option(page, "Frame cap", ["V-sync", "30 fps"], func(i: int) -> void:
		GraphicsSettings.set_fps_cap(GraphicsSettings.FPS_CAPS[i])
		_graphics_changed())
	gfx_auto_label = Label.new()
	gfx_auto_label.text = "Quality picked automatically on first launch"
	gfx_auto_label.add_theme_color_override("font_color", AMBER)
	page.add_child(gfx_auto_label)

	# A graphics tier sets Cars and Draw distance as well: moving one by hand
	# makes Quality read "Custom".
	_heading(page, "Traffic and lights")
	traffic_cars_slider = _add_slider(page, "Cars", 0.0, TrafficSettings.CAR_COUNT_MAX, 5.0, TrafficSettings.car_count,
		func(v: float) -> void:
			TrafficSettings.set_car_count(int(v))
			TrafficSettings.save_settings()
			GraphicsSettings.refresh_preset()
			var traffic: Variant = _game_node("traffic")
			if traffic != null:
				traffic.set_car_count(TrafficSettings.car_count)
			_refresh_quality())
	traffic_dist_slider = _add_slider(page, "Draw distance", TrafficSettings.DETAIL_MIN, TrafficSettings.DETAIL_MAX, 10.0, TrafficSettings.detail_distance,
		func(v: float) -> void:
			TrafficSettings.set_detail_distance(v)
			TrafficSettings.save_settings()
			GraphicsSettings.refresh_preset()
			var traffic: Variant = _game_node("traffic")
			if traffic != null:
				traffic.detail_distance = TrafficSettings.detail_distance
			_refresh_quality())
	night_lights_slider = _add_slider(page, "Night lights", TrafficSettings.LIGHT_GLOW_MIN, TrafficSettings.LIGHT_GLOW_MAX, 0.1, TrafficSettings.light_glow,
		func(v: float) -> void:
			TrafficSettings.set_light_glow(v)
			TrafficSettings.save_settings())
	# City lights: the signalised crossing and red lights for traffic. The
	# crossing is part of the road layout, so it appears (or goes) on Restart.
	city_lights_check = _add_check(page, "City lights (on restart)", TrafficSettings.city_lights, func(on: bool) -> void:
		TrafficSettings.city_lights = on
		TrafficSettings.save_settings())
	return _page_of(page)

func _display_changed() -> void:
	DisplaySettings.apply(get_window())
	DisplaySettings.save_settings()
	resolution_option.disabled = DisplaySettings.fullscreen

func _graphics_changed() -> void:
	GraphicsSettings.auto_picked = false   # a hand choice replaces the automatic one
	GraphicsSettings.apply(get_tree())
	GraphicsSettings.save_settings()
	_sync_all()

## Only the Quality dropdown follows a hand-moved traffic slider.
func _refresh_quality() -> void:
	_syncing = true
	var idx := GraphicsSettings.PRESETS.find(GraphicsSettings.preset)
	gfx_preset.select(idx if idx >= 0 else GraphicsSettings.PRESETS.size())
	_syncing = false

## A node of the running Game ("traffic", "player"); the pause menu is a child of it.
func _game_node(property: String) -> Variant:
	var host := get_parent()
	if host is PauseMenu:
		host = host.get_parent()
	return host.get(property) if host != null else null

# ---------- Driving ----------
func _build_driving_page(parent: Control) -> Control:
	var page := _new_page(parent)
	_heading(page, "View")
	# Cockpit FOV 55-78, default 62; the speed widening (up to +6) rides on top.
	fov_slider = _add_slider(page, "Cockpit FOV", ViewSettings.COCKPIT_FOV_MIN, ViewSettings.COCKPIT_FOV_MAX, 1.0, ViewSettings.cockpit_fov,
		func(v: float) -> void:
			ViewSettings.set_cockpit_fov(v)
			ViewSettings.save_settings())
	smoothing_slider = _add_slider(page, "Camera", 0.0, float(ViewSettings.CAMERA_SMOOTHING_MAX), 1.0, float(ViewSettings.camera_smoothing),
		func(v: float) -> void:
			ViewSettings.set_camera_smoothing(int(v))
			ViewSettings.save_settings())
	# Tyre smoke: 0 = none, 1 = default, 2 = double. Read live by TyreSmoke.
	_heading(page, "Tyre smoke")
	smoke_burnout_slider = _add_slider(page, "Burnout", 0.0, FxSettings.SMOKE_MAX, 0.1, FxSettings.smoke_burnout,
		func(v: float) -> void:
			FxSettings.set_smoke(v, FxSettings.smoke_drift)
			FxSettings.save_settings())
	smoke_drift_slider = _add_slider(page, "Drift", 0.0, FxSettings.SMOKE_MAX, 0.1, FxSettings.smoke_drift,
		func(v: float) -> void:
			FxSettings.set_smoke(FxSettings.smoke_burnout, v)
			FxSettings.save_settings())
	return _page_of(page)

# ---------- Controls ----------
func _build_controls_page(parent: Control) -> Control:
	var page := _new_page(parent)
	controls_scroll = _page_of(page)
	return controls_scroll

## Rebuilds the list from the InputMap, so a rebound key shows up at once.
func _refresh_controls() -> void:
	var scroll := controls_scroll
	var inner: VBoxContainer = scroll.get_child(0)
	for c in inner.get_children():
		c.queue_free()
		inner.remove_child(c)
	controls_status = Label.new()
	controls_status.add_theme_color_override("font_color", SILVER)
	controls_status.text = _unsaved_text()
	inner.add_child(controls_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	inner.add_child(row)
	controls_reset_button = _add_button(row, "Reset", _reset_keys)
	controls_save_button = _add_button(row, "Save", _save_keys)
	for group in controls_groups():
		_heading(inner, String(group[0]).to_upper())
		var grid := GridContainer.new()
		grid.columns = 2 + KeyBindings.SLOTS
		grid.add_theme_constant_override("h_separation", 16)
		inner.add_child(grid)
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
		inner.add_child(gap)

func _grid_label(parent: Control, text: String, colour: Color, min_w: float) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", colour)
	l.custom_minimum_size = Vector2(min_w, 0)
	parent.add_child(l)

# ---------- rebinding ----------
func _start_capture(action: StringName, slot: int, button: Button) -> void:
	if not _capture.is_empty():
		return
	_capture = {"action": action, "slot": slot, "button": button}
	button.text = "Press a key"
	controls_status.text = "Press the new key for this action. Esc cancels."

func _cancel_capture() -> void:
	_capture = {}

## The key the player pressed while a binding waited for one.
func _finish_capture(code: int) -> void:
	var action: StringName = _capture.action
	var slot: int = _capture.slot
	_capture = {}
	if code == KEY_ESCAPE:
		_refresh_controls()
		_focus_key(action, slot)
		return
	var other := KeyBindings.action_using(code, action)
	KeyBindings.set_key(action, slot, code)
	keys_dirty = true
	_refresh_controls()
	if other != &"":
		controls_status.text = "%s moved from %s (it got the old key)." % [KeyBindings.key_name(code), _label_for(other)]
	_focus_key(action, slot)

func _unsaved_text() -> String:
	return "Not saved yet: Save keeps these keys." if keys_dirty else ""

func _save_keys() -> void:
	KeyBindings.save_settings()
	keys_dirty = false
	controls_status.text = "Saved."

func _reset_keys() -> void:
	KeyBindings.reset_defaults()
	keys_dirty = true
	_refresh_controls()
	controls_status.text = "Defaults back. Save to keep them."

func _label_for(action: StringName) -> String:
	for g in GROUPS:
		for entry in g[1]:
			if entry[0] == String(action):
				return entry[1]
	return String(action).capitalize()

## After a rebuild, focus the key button that was just changed.
func _focus_key(action: StringName, slot: int) -> void:
	await get_tree().process_frame
	for b in controls_scroll.find_children("*", "Button", true, false):
		if b.has_meta("bind") and b.get_meta("bind") == [action, slot]:
			b.grab_focus()
			return

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
