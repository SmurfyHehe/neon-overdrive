class_name GarageScreen
extends CanvasLayer

# The garage, plain buttons for now (garage G0, 2026-10-11). The scene, the
# stations and the mod tree come in later steps; this is the room they will
# stand in and the way in and out of it:
#
#   Service car   free fix-everything until the totalled-meter bill card exists
#   Wash car      the scrub game (wash_screen.gd), free; Esc or a clean car
#                 comes back here
#   Go out        back to the road: the car waits outside with the engine off
#   Settings      the same Settings screen as the pause menu
#   Quit to title the run is saved
#
# These replace the stand-ins that sat in Settings > Game (and before that the
# pause menu). Keyboard only; nothing on screen names a key.

const GarageService := preload("res://scripts/car/garage_service.gd")
const WorkOrders := preload("res://scripts/core/work_orders.gd")

const AMBER := Color("#FFC066")
const SILVER := Color("#C9CED6")

var game_state: GameState
var player: PlayerCar
var board_button: Button
var service_button: Button
var wash_button: Button
var out_button: Button
var settings_button: Button
var title_button: Button
var confirm: ConfirmBox
var status_label: Label
var root_box: MarginContainer
var services := 0   # times Service car was pressed (tests read it)
## Walt's board (work board W2): set by Game when the shop is on, null when off.
var shop_day: Node
## How long the "Walt did it" slip shows on the way out, seconds.
var out_delay := 1.4
var _leaving := false

func _init(state: GameState, car: PlayerCar) -> void:
	game_state = state
	player = car
	name = "GarageScreen"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	visible = false

	var bg := ColorRect.new()
	bg.color = Color("#0E1424")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	root_box = MarginContainer.new()
	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_box.theme = UiTheme.font_theme()
	root_box.add_theme_constant_override("margin_left", 72)
	root_box.add_theme_constant_override("margin_top", 64)
	root_box.add_theme_constant_override("margin_bottom", 64)
	add_child(root_box)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	root_box.add_child(box)

	var title := UiTheme.title_label("GARAGE", 56, AMBER)
	box.add_child(title)

	status_label = Label.new()
	status_label.add_theme_color_override("font_color", SILVER)
	status_label.custom_minimum_size = Vector2(360, 0)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)

	board_button = _add_button(box, "Walt's board", game_state.open_workboard)
	board_button.visible = false
	service_button = _add_button(box, "Service car", _service)
	wash_button = _add_button(box, "Wash car", game_state.open_wash)
	out_button = _add_button(box, "Go out", _go_out)
	settings_button = _add_button(box, "Settings", _open_settings)
	title_button = _add_button(box, "Quit to title", _ask_quit)

	confirm = ConfirmBox.new(game_state)
	add_child(confirm)
	game_state.state_changed.connect(_on_state_changed)

func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 40)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _on_state_changed(new_state: GameState.State, old_state: GameState.State) -> void:
	var open := new_state == GameState.State.GARAGE
	var was := visible
	visible = open
	if open:
		# The board row shows while today's board is not settled.
		board_button.visible = shop_day != null and shop_day.can_reopen()
		# Back from the wash or the settings screen: say what happened, keep focus.
		if old_state != GameState.State.WASH:
			status_label.text = ""
		(wash_button if old_state == GameState.State.WASH else out_button).grab_focus()
		if not was and old_state != GameState.State.WASH:
			var sfx: Variant = get_parent().get("menu_sfx")
			if sfx != null:
				sfx.squelch()

## Go out: a day nobody took an order on is Walt's, with his flat pay and a
## slip shown on the way out (once: a second Go out the same day pays nothing).
func _go_out() -> void:
	if _leaving:
		return
	var paid := 0
	if shop_day != null and shop_day.enabled:
		paid = shop_day.settle_for_exit()
	if paid <= 0 or out_delay <= 0.0:
		game_state.leave_garage()
		return
	_leaving = true
	status_label.text = "Walt did it. %s into the bank." % WorkOrders.money(paid)
	var t := get_tree().create_timer(out_delay, true, false, true)
	t.timeout.connect(func() -> void:
		_leaving = false
		game_state.leave_garage())

func _service() -> void:
	if GarageService.fix_everything(player):
		services += 1
		status_label.text = "Everything is fixed. No charge."

func _ask_quit() -> void:
	confirm.ask("Quit to the title? Your run is saved.", "Quit", game_state.quit_to_title)

## The Settings screen lives in the pause menu node (as for the title screen).
func _open_settings() -> void:
	var menu: PauseMenu = null
	for c in get_parent().get_children():
		if c is PauseMenu:
			menu = c
	if menu == null:
		return
	root_box.visible = false
	menu.settings.closed.connect(_back_from_settings, CONNECT_ONE_SHOT)
	menu.show_settings()

func _back_from_settings() -> void:
	root_box.visible = true
	settings_button.grab_focus()
