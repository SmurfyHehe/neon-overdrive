class_name DawnCard
extends CanvasLayer

# The dawn card (garage G0, 2026-10-11): one plate between the road and the
# garage. It shows when the night ends (6 a.m.) and when a session boots (after
# the title), over the frozen world, then Continue goes on into the garage.
# What it says: which night it is, the clock, what the night banked and what
# the bank holds. Plain on purpose: the art pass comes with the garage scene.
#
# No key hints on screen: Continue is the focused button, Enter / Space press it.

const SILVER := Color("#C9CED6")
const AMBER := Color("#FFC066")

var game_state: GameState
var wallet: Node
var night_clock: Node
var continue_button: Button
var title_label: Label
var time_label: Label
var banked_label: Label
var bank_label: Label
## What the last 6 a.m. moved into the bank (wallet.banked), 0 at boot.
var last_banked := 0

func _init(state: GameState) -> void:
	game_state = state
	name = "DawnCard"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10   # under Settings and the wash (11), which open over it
	visible = false

	var shade := ColorRect.new()
	shade.color = Color("#0E1424", 0.92)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.theme = UiTheme.font_theme()
	add_child(centre)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiTheme.plate_panel())
	centre.add_child(plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(380, 0)
	plate.add_child(col)

	title_label = UiTheme.title_label("", 44, AMBER)
	col.add_child(title_label)
	time_label = _line(col, "numbers", 24, SILVER)
	col.add_child(UiTheme.floor_tape())
	banked_label = _line(col, "numbers", 22, AMBER)
	bank_label = _line(col, "numbers", 18, UiTheme.DIM)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	col.add_child(gap)
	continue_button = Button.new()
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(240, 40)
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	continue_button.pressed.connect(game_state.dawn_continue)
	col.add_child(continue_button)

	game_state.state_changed.connect(_on_state_changed)

func _line(parent: Control, role: String, size_px: int, colour: Color) -> Label:
	var l := Label.new()
	UiTheme.apply(l, role, size_px)
	l.add_theme_color_override("font_color", colour)
	parent.add_child(l)
	return l

## Called by Game once the wallet exists.
func bind_wallet(w: Node) -> void:
	wallet = w
	if w != null and w.has_signal("banked"):
		w.banked.connect(func(amount: int) -> void: last_banked = amount)

func _on_state_changed(new_state: GameState.State, _old: GameState.State) -> void:
	visible = new_state == GameState.State.DAWN
	if visible:
		_refresh()
		continue_button.grab_focus()

func _refresh() -> void:
	var at_boot := game_state.garage_entry == GameState.ENTRY_BOOT
	var night := game_state.dawn_night
	if at_boot or night <= 0:
		night = int(night_clock.get("night")) if night_clock != null else 1
	title_label.text = "NIGHT %d" % night if at_boot else "NIGHT %d IS OVER" % night
	time_label.text = "Back at the garage" if at_boot else NightClock.clock_text(NightClock.NIGHT_MINUTES)
	banked_label.visible = wallet != null and not at_boot
	bank_label.visible = wallet != null
	if wallet != null:
		banked_label.text = "Banked %s" % wallet.money(last_banked)
		bank_label.text = "Bank %s" % wallet.money(wallet.bank)
