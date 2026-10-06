class_name TunerScreen
extends CanvasLayer

# The one Tuner screen. T opens it, Y opens it with Auto-Tune expanded, Esc
# closes it; the game is paused while it is open (GameState.TUNING / AUTOTUNE).
#
# Three sections, one scrolling column:
#   Gearing & Power  the raw sliders (TuningPanel). Primary: the tuner is raw.
#   Exhaust          loudness, raspiness, pops, flame (ExhaustPanel), cosmetic.
#   Auto-Tune        collapsible add-on (AutoTunePanel): goals, locks, run,
#                    apply, undo, tune slots. Collapsed on T, expanded on Y.
#
# The sections are child panels that keep their own logic and tests. This node
# only lays them out, shows and hides the screen with the game state, moves
# keyboard focus in on open (so the arrow keys work at once) and out on close
# (a focused slider would eat the arrow keys while driving), and keeps the
# sections in step: a slider move refreshes the Auto-Tune lock labels, an Auto-Tune
# Apply or slot load refreshes the sliders.
#
# Debug tool, deliberately plain Godot default controls, not the game's UI.

const MARGIN := 16

var player: PlayerCar
var game_state: GameState
var manual: TuningPanel
var exhaust: ExhaustPanel
var auto: AutoTunePanel
var tabs: TunerTabs
var scroll: ScrollContainer
var auto_heading: Label

func _init(car: PlayerCar, state: GameState) -> void:
	player = car
	game_state = state

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10  # same layer as the pause menu; they are never open together
	visible = false

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = MARGIN
	panel.offset_top = 8
	panel.offset_right = -MARGIN
	panel.offset_bottom = -MARGIN
	var bg := StyleBoxFlat.new()  # near-opaque: bright buildings behind made the text unreadable
	bg.bg_color = Color(0.03, 0.02, 0.07, 0.95)
	bg.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	column.add_child(header)
	var title := Label.new()
	title.text = "TUNER  -  T or Y or Esc to close, game paused"
	header.add_child(title)
	tabs = TunerTabs.new(game_state)
	header.add_child(tabs)

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var sections := VBoxContainer.new()
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_theme_constant_override("separation", 6)
	scroll.add_child(sections)

	sections.add_child(_heading("Gearing & Power"))
	manual = TuningPanel.new(player, game_state)
	sections.add_child(manual)
	sections.add_child(_heading("Exhaust (sound and flames only; held keys U/J I/K O/L still work while driving)"))
	exhaust = ExhaustPanel.new(player)
	sections.add_child(exhaust)
	auto_heading = _heading("Auto-Tune (add-on, Y to open, T to fold away)")
	sections.add_child(auto_heading)
	auto = AutoTunePanel.new(player, game_state)
	sections.add_child(auto)

	manual.tune_changed.connect(auto.refresh_lock_labels)
	auto.tune_changed.connect(_on_auto_changed)
	_set_auto_expanded(false)
	game_state.state_changed.connect(_on_state_changed)

func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(1.0, 0.54, 0.12))  # the exhaust readout's orange, already in the game
	return l

func _set_auto_expanded(expanded: bool) -> void:
	auto.visible = expanded

func _on_auto_changed() -> void:
	manual.refresh_from_player()
	exhaust.refresh()

func _on_state_changed(new_state: GameState.State, old_state: GameState.State) -> void:
	visible = GameState.is_tuner(new_state)
	if visible:
		var was_open := GameState.is_tuner(old_state)
		if not was_open:
			exhaust.refresh()
		_set_auto_expanded(new_state == GameState.State.AUTOTUNE)
		_focus_in(new_state)
	else:
		# Sliders and buttons keep keyboard focus otherwise and eat the arrow keys.
		var focused := get_viewport().gui_get_focus_owner()
		if focused:
			focused.release_focus()

## Keyboard focus goes to the first control of the section the key asked for:
## the first gearing slider on T, the first Auto-Tune goal slider on Y.
func _focus_in(state: GameState.State) -> void:
	if state == GameState.State.AUTOTUNE:
		var first: Control = auto.goal_sliders.values()[0]
		first.grab_focus()
		_scroll_to.call_deferred(auto_heading)  # after the layout has caught up with the section opening
	else:
		manual.sliders["final_drive"].grab_focus()
		_scroll_to.call_deferred(null)

func _scroll_to(target: Control) -> void:
	scroll.scroll_vertical = 0 if target == null else int(target.position.y)
