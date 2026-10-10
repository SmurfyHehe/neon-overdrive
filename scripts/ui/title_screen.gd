class_name TitleScreen
extends CanvasLayer

# Title screen (menus A-list, 2026-10-08; ported to scripts/ui/ 2026-10-10):
# shown once per session before the first drive (GameState.TITLE). The world is
# already loaded and frozen behind it, so Drive is instant: the live car sits
# behind the band, the radio plays under it, muffled (PauseLook), and the camera
# circles the car. Drive / Settings / Quit; Quit asks first. Settings is the
# same screen the pause menu opens. No key hints, no tutorial, no loading bar:
# the world is built before this shows, there is nothing to wait for.

const GameInfo := preload("res://scripts/core/game_info.gd")

const NAVY := Color("#0E1424")
const SODIUM := Color("#FF8A1F")
const AMBER := Color("#FFC066")
const SILVER := Color("#C9CED6")

var game_state: GameState
var panel: Control
var drive_button: Button
var settings_button: Button
var confirm: ConfirmBox
var margin: MarginContainer  # the title and buttons; slides in from the left

func _init(state: GameState) -> void:
	game_state = state

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10   # over the world; Settings (11) opens above it
	visible = false

	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.theme = UiTheme.font_theme()
	add_child(panel)

	# A navy band down the left side, fading into the frozen night road.
	var band := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(NAVY, 0.92))
	grad.set_color(1, Color(NAVY, 0.0))
	grad.set_offset(1, 1.0)
	grad.add_point(0.55, Color(NAVY, 0.85))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	tex.width = 256
	tex.height = 4
	band.texture = tex
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.anchor_bottom = 1.0
	band.anchor_right = 0.62
	panel.add_child(band)

	margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_top", 64)
	margin.add_theme_constant_override("margin_bottom", 64)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	# The name comes from project.godot (GameInfo), one word per line.
	var words := GameInfo.game_name().to_upper().split(" ", false)
	for i in words.size():
		col.add_child(_title_label(words[i], AMBER if i == 0 else SILVER, 72 if i == 0 else 44))
	var rule := ColorRect.new()
	rule.color = SODIUM
	rule.custom_minimum_size = Vector2(260, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(rule)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 28)
	col.add_child(gap)

	drive_button = _add_button(col, "Drive", game_state.start_drive)
	settings_button = _add_button(col, "Settings", _open_settings)
	_add_button(col, "Quit", func() -> void:
		confirm.ask("Quit to desktop?", "Quit", game_state.quit))

	confirm = ConfirmBox.new(game_state)
	add_child(confirm)

	game_state.state_changed.connect(_on_state_changed)

func _title_label(text: String, colour: Color, size_px: int) -> Label:
	var l := Label.new()
	l.text = text
	UiTheme.apply(l, "display", size_px)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l

func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 40)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _on_state_changed(new_state: GameState.State, old_state: GameState.State) -> void:
	visible = new_state == GameState.State.TITLE
	var hud := _sibling("Hud")
	if hud != null and (visible or old_state == GameState.State.TITLE):
		hud.visible = not visible  # no speedo over the title
	if visible:
		panel.visible = true
		drive_button.grab_focus()
		MenuMotion.slide_in(margin, Vector2.LEFT)
		var sfx: Variant = get_parent().get("menu_sfx")
		if sfx != null:
			sfx.squelch()

func _open_settings() -> void:
	var menu := _sibling("PauseMenu") as PauseMenu
	if menu == null:
		return
	panel.visible = false
	menu.settings.closed.connect(_back_from_settings, CONNECT_ONE_SHOT)
	menu.show_settings()

func _back_from_settings() -> void:
	if not visible:
		return
	panel.visible = true
	settings_button.grab_focus()
	MenuMotion.slide_in(margin, Vector2.LEFT)

func _sibling(cls: String) -> Node:
	for c in get_parent().get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.get_global_name() == cls:
			return c
	return null
