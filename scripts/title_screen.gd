class_name TitleScreen
extends CanvasLayer

# Title screen (menus A-list, 2026-10-08): shown once per session before the
# first drive (GameState.TITLE). The world is already loaded and frozen behind
# it, so Drive is instant. Drive / Settings / Quit; Settings opens the pause
# menu's pages without the run buttons, Quit asks first. No key hints and no
# tutorial (Roy: no / later).

const NAVY := Color("#0E1424")
const SODIUM := Color("#FF8A1F")
const AMBER := Color("#FFC066")
const SILVER := Color("#C9CED6")

var game_state: GameState
var panel: Control
var drive_button: Button
var confirm: ConfirmBox
var margin: MarginContainer  # the title and buttons; slides in from the left

func _init(state: GameState) -> void:
	game_state = state

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 11  # over the pause menu's layer, under nothing else
	visible = false

	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	# A navy band down the left third, fading into the frozen night road.
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

	col.add_child(_title_label("NEON", AMBER, 72))
	col.add_child(_title_label("OVERDRIVE", SILVER, 44))
	var rule := ColorRect.new()
	rule.color = SODIUM
	rule.custom_minimum_size = Vector2(260, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(rule)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 28)
	col.add_child(gap)

	drive_button = _add_button(col, "Drive", game_state.start_drive)
	_add_button(col, "Settings", _open_settings)
	_add_button(col, "Quit", func() -> void:
		confirm.ask("Quit to desktop?", "Quit", game_state.quit))

	confirm = ConfirmBox.new(game_state)
	add_child(confirm)

	game_state.state_changed.connect(_on_state_changed)

func _title_label(text: String, colour: Color, size_px: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
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
		hud.visible = not visible  # no speedo or hints over the title
	if visible:
		panel.visible = true
		drive_button.grab_focus()
		MenuMotion.slide_in(margin, Vector2.LEFT)
		var sfx: Variant = get_parent().get("menu_sfx")
		if sfx != null:
			sfx.squelch()

func _open_settings() -> void:
	var menu := _pause_menu()
	if menu == null:
		return
	panel.visible = false
	menu.open_title_settings(_back_from_settings)

func _back_from_settings() -> void:
	panel.visible = true
	drive_button.grab_focus()
	MenuMotion.slide_in(margin, Vector2.LEFT)

func _pause_menu() -> PauseMenu:
	return _sibling("PauseMenu") as PauseMenu

func _sibling(cls: String) -> Node:
	for c in get_parent().get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.get_global_name() == cls:
			return c
	return null
