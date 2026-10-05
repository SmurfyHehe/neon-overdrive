class_name PauseMenu
extends CanvasLayer

# Pause overlay (issue #27). Deliberately plain: a dim backdrop and Godot's
# default buttons, no theme or styling. The menu's look is Roy's call later;
# restyle here without touching GameState.

var game_state: GameState
var resume_button: Button
var volume_sliders := {}   # channel -> HSlider

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

	var title := Label.new()
	title.text = "PAUSED"
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
		name_label.custom_minimum_size = Vector2(70, 0)
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

	resume_button = _add_button(box, "Resume", game_state.resume)
	_add_button(box, "Restart", game_state.restart)
	_add_button(box, "Quit", game_state.quit)

	game_state.state_changed.connect(_on_state_changed)

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
		resume_button.grab_focus()  # keyboard/controller can navigate the menu
