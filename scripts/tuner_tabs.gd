class_name TunerTabs
extends CanvasLayer

# The tab strip that makes the manual tuner (T) and Auto-Tune (Y) one menu:
# visible while either is open, two buttons that switch between them. The
# panels themselves are unchanged and still own their state (TUNING, AUTOTUNE).

var game_state: GameState
var manual_button: Button
var auto_button: Button

func _init(state: GameState) -> void:
	game_state = state

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 12
	visible = false
	var bar := HBoxContainer.new()
	bar.position = Vector2(16, 6)
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	manual_button = _tab(bar, "Manual tune (T)", GameState.State.TUNING)
	auto_button = _tab(bar, "Auto-Tune (Y)", GameState.State.AUTOTUNE)
	game_state.state_changed.connect(_on_state_changed)

func _tab(parent: Control, text: String, target: GameState.State) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE  # a focused button would eat game keys
	b.pressed.connect(func() -> void: game_state.switch_tuner(target))
	parent.add_child(b)
	return b

func _on_state_changed(new_state: GameState.State, _old_state: GameState.State) -> void:
	visible = new_state == GameState.State.TUNING or new_state == GameState.State.AUTOTUNE
	manual_button.set_pressed_no_signal(new_state == GameState.State.TUNING)
	auto_button.set_pressed_no_signal(new_state == GameState.State.AUTOTUNE)
