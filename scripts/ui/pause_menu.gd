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
		["steer_left", "Steer left"], ["steer_right", "Steer right"], ["reverse", "Reverse gear (when stopped)"], ["headlights", "Headlights on / off"], ["high_beam", "High beam (twice: flash)"]]],
	["Gears & Engine", [
		["shift_up", "Shift up (manual)"], ["shift_down", "Shift down (manual)"], ["toggle_gearbox", "Gearbox: auto / semi / manual"],
		["clutch", "Clutch (hold, manual)"], ["starter", "Starter (hold, manual)"]]],
	["Camera", [["camera_cycle", "Camera smoothing"], ["camera_view", "Chase / cockpit view"], ["look_back", "Look back (hold)"], ["look_left", "Look left (cockpit, hold)"], ["look_right", "Look right (cockpit, hold)"], ["look_up", "Look up (cockpit, hold)"], ["look_down", "Look down (cockpit, hold)"], ["window", "Side window (hold: down, tap: up)"]]],
	["Audio & Radio", [["mute", "Mute"], ["radio_next", "Next radio station"]]],
	["Photo mode", [["photo_mode", "Photo mode"], ["photo_forward", "Forward"], ["photo_back", "Back"], ["photo_left", "Left"], ["photo_right", "Right"], ["photo_down", "Down"], ["photo_up", "Up"], ["photo_fast", "Faster (hold)"], ["photo_look_left", "Look left"], ["photo_look_right", "Look right"], ["photo_look_up", "Look up"], ["photo_look_down", "Look down"], ["photo_fov_narrow", "Zoom in"], ["photo_fov_wide", "Zoom out"], ["photo_shot", "Save photo"]]],
	["Menus", [["pause", "Pause / back"], ["tuning_panel", "Tuning panel"], ["autotune_panel", "Auto-Tune panel"]]],
]

const GameInfo := preload("res://scripts/core/game_info.gd")
const LogFolder := preload("res://scripts/core/log_folder.gd")

const SILVER := Color("#C9CED6")
const AMBER := Color("#FFC066")

var game_state: GameState
var resume_button: Button
var volume_sliders := {}   # channel -> HSlider
var fov_slider: HSlider
var smoothing_slider: HSlider
var smoke_burnout_slider: HSlider
var smoke_drift_slider: HSlider
var main_page: VBoxContainer
var controls_page: VBoxContainer
var controls_scroll: ScrollContainer
var controls_back_button: Button
## The bank (F0, scripts/core/wallet.gd), shown under the title; null in bare tests.
var wallet: Node
var bank_label: Label
var cars_page: VBoxContainer
var graphics_page: VBoxContainer
var graphics_back_button: Button
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
var _gfx_refreshing := false

func _init(state: GameState) -> void:
	game_state = state

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10  # above the debug HUD
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)
	main_page = box

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	bank_label = Label.new()
	bank_label.name = "Bank"
	bank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(bank_label)
	_refresh_bank()

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
	# the running TrafficManager at once and saved with the volumes. Night
	# lights (2026-10-07): tail lamps, flares and barrier reflectors.
	var traffic_title := Label.new()
	traffic_title.text = "Traffic"
	traffic_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(traffic_title)
	# A graphics tier sets these two as well (GraphicsSettings): moving one by
	# hand makes the Graphics preset read "Custom".
	traffic_cars_slider = _add_slider(box, "Cars", 0.0, TrafficSettings.CAR_COUNT_MAX, 5.0, TrafficSettings.car_count,
		func(v: float) -> void:
			TrafficSettings.set_car_count(int(v))
			TrafficSettings.save_settings()
			GraphicsSettings.refresh_preset()
			var traffic: Variant = get_parent().get("traffic")
			if traffic != null:
				traffic.set_car_count(TrafficSettings.car_count))
	traffic_dist_slider = _add_slider(box, "Draw dist", TrafficSettings.DETAIL_MIN, TrafficSettings.DETAIL_MAX, 10.0, TrafficSettings.detail_distance,
		func(v: float) -> void:
			TrafficSettings.set_detail_distance(v)
			TrafficSettings.save_settings()
			GraphicsSettings.refresh_preset()
			var traffic: Variant = get_parent().get("traffic")
			if traffic != null:
				traffic.detail_distance = TrafficSettings.detail_distance)
	_add_slider(box, "Night lights", TrafficSettings.LIGHT_GLOW_MIN, TrafficSettings.LIGHT_GLOW_MAX, 0.1, TrafficSettings.light_glow,
		func(v: float) -> void:
			TrafficSettings.set_light_glow(v)
			TrafficSettings.save_settings())
	# City lights (2026-10-09, junction.gd): the signalised crossing and red
	# lights for traffic. Off by default; the crossing is part of the road
	# layout, so it appears (or goes) on Restart.
	var lights := CheckButton.new()
	lights.text = "City lights (on restart)"
	lights.button_pressed = TrafficSettings.city_lights
	lights.toggled.connect(func(on: bool) -> void:
		TrafficSettings.city_lights = on
		TrafficSettings.save_settings())
	box.add_child(lights)

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

	smoothing_slider = _add_slider(box, "Camera", 0.0, float(ViewSettings.CAMERA_SMOOTHING_MAX), 1.0, float(ViewSettings.camera_smoothing),
		func(v: float) -> void:
			ViewSettings.set_camera_smoothing(int(v))
			ViewSettings.save_settings())

	# Tyre smoke amounts (2026-10-07): 0 = none, 1 = default, 2 = double.
	# Read live by TyreSmoke each tick, saved with the rest.
	var smoke_title := Label.new()
	smoke_title.text = "Tyre smoke"
	smoke_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(smoke_title)
	smoke_burnout_slider = _add_slider(box, "Burnout", 0.0, FxSettings.SMOKE_MAX, 0.1, FxSettings.smoke_burnout,
		func(v: float) -> void:
			FxSettings.set_smoke(v, FxSettings.smoke_drift)
			FxSettings.save_settings())
	smoke_drift_slider = _add_slider(box, "Drift", 0.0, FxSettings.SMOKE_MAX, 0.1, FxSettings.smoke_drift,
		func(v: float) -> void:
			FxSettings.set_smoke(FxSettings.smoke_burnout, v)
			FxSettings.save_settings())

	resume_button = _add_button(box, "Resume", game_state.resume)
	_add_button(box, "Car: " + PlayerCars.title(PlayerCar.chassis_kind()), show_cars)
	_add_button(box, "Graphics", show_graphics)
	_add_button(box, "Controls", show_controls)
	_add_button(box, "Service car (reset wear)", _service_car)
	_add_button(box, "Open log folder", LogFolder.open)
	_add_button(box, "Restart", game_state.restart)
	_add_button(box, "Quit", game_state.quit)

	# Version line (release readiness, 2026-10-08), so a bug report can name the build.
	var version_label := Label.new()
	version_label.text = GameInfo.title()
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_label.add_theme_color_override("font_color", SILVER)
	version_label.add_theme_font_size_override("font_size", 12)
	box.add_child(version_label)

	_build_controls_page(center)
	_build_cars_page(center)
	_build_graphics_page(center)
	game_state.state_changed.connect(_on_state_changed)

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
	visible = new_state == GameState.State.PAUSED
	if visible:
		show_main()  # always reopen on the main page
		_refresh_bank()

## "Bank $4,200 · tonight $350"
func _refresh_bank() -> void:
	bank_label.visible = wallet != null
	if wallet != null:
		bank_label.text = "Bank %s  ·  tonight %s" % [wallet.money(wallet.bank), wallet.money(wallet.cash)]

# ---------- Graphics page (polish pass, 2026-10-08) ----------
# A preset picker plus each setting on its own (GraphicsSettings). Every change
# applies at once and is saved; changing one setting makes the preset "Custom".
func show_graphics() -> void:
	_refresh_graphics()
	main_page.visible = false
	controls_page.visible = false
	graphics_page.visible = true
	gfx_preset.grab_focus()

func _build_graphics_page(center: CenterContainer) -> void:
	graphics_page = VBoxContainer.new()
	graphics_page.add_theme_constant_override("separation", 8)
	graphics_page.visible = false
	center.add_child(graphics_page)
	var title := Label.new()
	title.text = "GRAPHICS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	graphics_page.add_child(title)
	gfx_preset = _add_option(graphics_page, "Preset", ["Low", "Medium", "High", "Custom"], func(i: int) -> void:
		if i < GraphicsSettings.PRESETS.size():
			GraphicsSettings.set_preset(GraphicsSettings.PRESETS[i])
		_graphics_changed())
	gfx_aa = _add_option(graphics_page, "Edge smoothing", GraphicsSettings.AA_NAMES, func(i: int) -> void:
		GraphicsSettings.set_aa(GraphicsSettings.AA_MODES[i])
		_graphics_changed())
	gfx_scale = _add_slider(graphics_page, "Resolution", GraphicsSettings.SCALE_MIN, GraphicsSettings.SCALE_MAX, 0.05, GraphicsSettings.render_scale,
		func(v: float) -> void:
			GraphicsSettings.set_render_scale(v)
			_graphics_changed())
	gfx_scale_label = Label.new()
	gfx_scale.get_parent().add_child(gfx_scale_label)
	# Tiers (2026-10-09): the CPU side of a preset is the traffic sliders on
	# the main page plus the mirror render size here.
	gfx_mirrors = _add_option(graphics_page, "Mirrors", ["Low", "Medium", "High"], func(i: int) -> void:
		FxSettings.set_mirror_quality(i)
		GraphicsSettings.refresh_preset()
		_graphics_changed())
	gfx_dynres = _add_option(graphics_page, "Dynamic resolution", ["On", "Off"], func(i: int) -> void:
		GraphicsSettings.set_dynamic_res(i == 0)
		_graphics_changed())
	gfx_cap = _add_option(graphics_page, "Frame cap", ["V-sync", "30 fps"], func(i: int) -> void:
		GraphicsSettings.set_fps_cap(GraphicsSettings.FPS_CAPS[i])
		_graphics_changed())
	gfx_auto_label = Label.new()
	gfx_auto_label.text = "Preset picked automatically on first launch"
	gfx_auto_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gfx_auto_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))  # amber #FFC066
	graphics_page.add_child(gfx_auto_label)
	graphics_back_button = _add_button(graphics_page, "Back", show_main)

func _add_option(parent: Control, text: String, items: Array, on_select: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_label := Label.new()
	name_label.text = text
	name_label.custom_minimum_size = Vector2(140, 0)
	row.add_child(name_label)
	var o := OptionButton.new()
	for item in items:
		o.add_item(item)
	o.custom_minimum_size = Vector2(180, 0)
	o.item_selected.connect(on_select)
	row.add_child(o)
	return o

func _graphics_changed() -> void:
	if _gfx_refreshing:
		return
	GraphicsSettings.auto_picked = false   # a hand choice replaces the automatic one
	GraphicsSettings.apply(get_tree())
	GraphicsSettings.save_settings()
	_refresh_graphics()

## Shows the current values; the guard stops the widgets' own signals re-applying them.
func _refresh_graphics() -> void:
	_gfx_refreshing = true
	var idx := GraphicsSettings.PRESETS.find(GraphicsSettings.preset)
	gfx_preset.select(idx if idx >= 0 else GraphicsSettings.PRESETS.size())
	gfx_aa.select(maxi(GraphicsSettings.AA_MODES.find(GraphicsSettings.aa), 0))
	gfx_scale.value = GraphicsSettings.render_scale
	gfx_scale_label.text = "%d%%" % roundi(GraphicsSettings.render_scale * 100.0)
	gfx_mirrors.select(FxSettings.mirror_quality)
	gfx_dynres.select(0 if GraphicsSettings.dynamic_res else 1)
	gfx_cap.select(maxi(GraphicsSettings.FPS_CAPS.find(GraphicsSettings.fps_cap), 0))
	gfx_auto_label.visible = GraphicsSettings.auto_picked
	_gfx_refreshing = false

# ---------- Controls page ----------
func show_controls() -> void:
	_refresh_controls()
	main_page.visible = false
	cars_page.visible = false
	graphics_page.visible = false
	controls_page.visible = true
	# Cap the list to the window so it scrolls instead of running off-screen.
	controls_scroll.custom_minimum_size = Vector2(640, maxf(get_viewport().get_visible_rect().size.y * 0.7, 160.0))
	controls_scroll.grab_focus()  # arrows / page keys scroll it

func show_main() -> void:
	# A graphics tier (menu or first-launch pick) may have moved the traffic values.
	traffic_cars_slider.set_value_no_signal(TrafficSettings.car_count)
	traffic_dist_slider.set_value_no_signal(TrafficSettings.detail_distance)
	main_page.visible = true
	controls_page.visible = false
	cars_page.visible = false
	graphics_page.visible = false
	resume_button.grab_focus()  # keyboard/controller can navigate the menu

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
	controls_scroll.custom_minimum_size = Vector2(640, 380)
	controls_scroll.focus_mode = Control.FOCUS_ALL
	controls_page.add_child(controls_scroll)
	controls_back_button = _add_button(controls_page, "Back", show_main)

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
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 24)
		list.add_child(grid)
		for entry in group[1]:
			_grid_label(grid, entry[1], SILVER, 280)
			_grid_label(grid, keyboard_text(entry[0]), AMBER, 140)
			_grid_label(grid, gamepad_text(entry[0]), SILVER, 140)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		list.add_child(gap)

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

# ---------- Car page (stage D, Roy 2026-10-09) ----------
## One button per player car (PlayerCars.KINDS). Picking one saves it and
## restarts the run in that car; the garage replaces this page later.
func show_cars() -> void:
	main_page.visible = false
	controls_page.visible = false
	cars_page.visible = true
	var first := cars_page.get_child(1)
	if first is Button:
		(first as Button).grab_focus()

func _build_cars_page(center: CenterContainer) -> void:
	cars_page = VBoxContainer.new()
	cars_page.add_theme_constant_override("separation", 8)
	cars_page.visible = false
	center.add_child(cars_page)
	var title := Label.new()
	title.text = "CAR  (restarts the run)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cars_page.add_child(title)
	var now := PlayerCar.chassis_kind()
	for k in PlayerCars.KINDS:
		var text := "%s   %d Nm / %d kg" % [PlayerCars.title(k.id), int(k.nm), int(k.kg)]
		if k.id == now:
			text += "   (driving)"
		var b := _add_button(cars_page, text, _pick_car.bind(String(k.id)))
		b.custom_minimum_size = Vector2(420, 0)
	_add_button(cars_page, "Back", show_main)

func _pick_car(kind: String) -> void:
	PlayerCars.select(kind)
	PlayerCars.save_settings()
	game_state.restart()
