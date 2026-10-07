class_name TunerTabs
extends HBoxContainer

# The two buttons in the Tuner screen's header: "Tuner" shows the screen with
# the Auto-Tune section collapsed, "Auto-Tune" with it expanded. They just
# switch between the TUNING and AUTOTUNE states (the same thing the T and Y keys
# do); the Tuner screen decides what each state looks like. The buttons are
# keyboard-focusable (Tab, then Enter or Space); the screen drops focus on close.

var game_state: GameState
var manual_button: Button
var auto_button: Button

func _init(state: GameState) -> void:
	game_state = state

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_theme_constant_override("separation", 6)
	manual_button = _tab("Tuner", GameState.State.TUNING)
	auto_button = _tab("Auto-Tune", GameState.State.AUTOTUNE)
	game_state.state_changed.connect(_on_state_changed)

func _tab(text: String, target: GameState.State) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void: game_state.switch_tuner(target))
	add_child(b)
	return b

func _on_state_changed(new_state: GameState.State, _old_state: GameState.State) -> void:
	visible = GameState.is_tuner(new_state)
	manual_button.set_pressed_no_signal(new_state == GameState.State.TUNING)
	auto_button.set_pressed_no_signal(new_state == GameState.State.AUTOTUNE)
