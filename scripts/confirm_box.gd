class_name ConfirmBox
extends Control

# "Are you sure?" box (menus A-list, 2026-10-08) for Quit, Restart and the
# reset-to-defaults buttons. Covers its parent with a dim, shows a question and
# Yes / No. No has focus, so a stray Enter never quits; Esc also means No.
#
# While it is open, game_state.modal_open is true so the polled Esc (GameState)
# doesn't resume or close the menu underneath at the same time.

signal closed(confirmed: bool)

var game_state: GameState
var question: Label
var yes_button: Button
var no_button: Button
var _on_yes: Callable
var _return_focus: Control

func _init(state: GameState) -> void:
	game_state = state

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0E1424", 0.96)
	sb.border_color = Color("#FFC066")
	sb.set_border_width_all(2)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	question = Label.new()
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.custom_minimum_size = Vector2(320, 0)
	box.add_child(question)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	yes_button = Button.new()
	yes_button.custom_minimum_size = Vector2(120, 0)
	yes_button.pressed.connect(func() -> void: _close(true))
	row.add_child(yes_button)
	no_button = Button.new()
	no_button.text = "No"
	no_button.custom_minimum_size = Vector2(120, 0)
	no_button.pressed.connect(func() -> void: _close(false))
	row.add_child(no_button)

## Shows the box. on_yes runs only if Yes is picked.
func ask(text: String, yes_text: String, on_yes: Callable) -> void:
	_return_focus = get_viewport().gui_get_focus_owner()
	question.text = text
	yes_button.text = yes_text
	_on_yes = on_yes
	visible = true
	if game_state != null:
		game_state.modal_open = true
	no_button.grab_focus()

func is_open() -> bool:
	return visible

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close(false)

func _close(confirmed: bool) -> void:
	if not visible:
		return
	visible = false
	if game_state != null:
		game_state.modal_open = false
		game_state.swallow_pause_press()
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()
	closed.emit(confirmed)
	if confirmed and _on_yes.is_valid():
		_on_yes.call()
