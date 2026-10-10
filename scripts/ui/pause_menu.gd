class_name PauseMenu
extends CanvasLayer

# The pause screen (3.7, 2026-10-10). The world freezes the instant Esc goes
# down; PauseLook (pause_look.gd) dims and softly blurs the frozen frame, circles
# the camera around the car and muffles the radio, and this menu slides in over
# it in 0.15 s with the squelch. Five rows and nothing else:
#
#   Resume, Restart night (Quit race in a race), Settings, Photo mode, Quit to title
#
# Sliders, keys and the garage stand-ins live on the Settings screen
# (settings_screen.gd). Top-right, on a plate: the night, the clock, the cash.
#
# Two things can show with it:
#   - one amber line when the game paused itself (a stall, or alt-tab);
#   - a one-second toast when Esc is pressed while a cop has eyes on the
#     player (the pause is refused, the menu never opens).

const GameInfo := preload("res://scripts/core/game_info.gd")

const SILVER := Color("#C9CED6")
const AMBER := Color("#FFC066")
const TOAST_SECS := 1.0

var game_state: GameState
var resume_button: Button
var lower_look_button: Button
var restart_button: Button
var settings_button: Button
var photo_button: Button
var title_button: Button
var settings: SettingsScreen
var confirm: ConfirmBox
var race_button: Button
var main_page: VBoxContainer
var slide_root: MarginContainer   # what MenuMotion slides in
## The bank (F0, scripts/core/wallet.gd) and the clock, shown on the plate; null in bare tests.
var wallet: Node
var night_clock: Node
var notice_label: Label           # the amber "paused itself" line
var plate_night: Label
var plate_time: Label
var plate_cash: Label
var plate_bank: Label
var toast: Label                  # the chase-lock line
var _toast_tween: Tween

func _init(state: GameState) -> void:
	game_state = state

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10  # above the debug HUD
	visible = false

	# PauseLook does the real dim and blur; this is only enough shade to read
	# the list when it is absent (bare tests).
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.25)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	slide_root = MarginContainer.new()
	slide_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	slide_root.theme = UiTheme.font_theme()   # Menu role for every row and button
	slide_root.add_theme_constant_override("margin_left", 72)
	slide_root.add_theme_constant_override("margin_top", 64)
	slide_root.add_theme_constant_override("margin_bottom", 64)
	add_child(slide_root)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	slide_root.add_child(box)
	main_page = box

	var title := Label.new()
	title.text = "PAUSED"
	UiTheme.apply(title, "display", 56)
	box.add_child(title)

	notice_label = Label.new()
	notice_label.name = "Notice"
	notice_label.add_theme_color_override("font_color", AMBER)
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.custom_minimum_size = Vector2(360, 0)
	notice_label.visible = false
	box.add_child(notice_label)

	# Only after the game paused itself for falling behind (REASON_STALL).
	lower_look_button = _add_button(box, "Lower the look", _lower_look)
	lower_look_button.visible = false
	resume_button = _add_button(box, "Resume", game_state.resume)
	restart_button = _add_button(box, "Restart night", _ask_restart)
	settings_button = _add_button(box, "Settings", show_settings)
	# TEST BUILD: "Race a test rival" and "Wash car" are on Settings > Game (stand-ins),
	# not here: the pause screen keeps to its spec rows. The hidden button stays for
	# tests/core/race_core.gd, which presses it.
	race_button = _add_button(box, "Race a test rival", _race_pressed)
	race_button.visible = false
	photo_button = _add_button(box, "Photo mode", game_state.open_photo_from_pause)
	title_button = _add_button(box, "Quit to title", _ask_quit_to_title)

	# Version line (release readiness, 2026-10-08), so a bug report can name the build.
	var version_label := Label.new()
	version_label.text = GameInfo.title()
	version_label.add_theme_color_override("font_color", SILVER)
	version_label.add_theme_font_size_override("font_size", 12)
	box.add_child(version_label)

	_build_plate()

	confirm = ConfirmBox.new(game_state)
	add_child(confirm)
	settings = SettingsScreen.new(game_state)
	settings.service_action = _service_car
	settings.tow_action = _call_tow
	settings.race_action = _race_pressed
	settings.wash_action = game_state.open_wash
	add_child(settings)
	settings.closed.connect(_on_settings_closed)
	game_state.state_changed.connect(_on_state_changed)
	game_state.pause_refused.connect(_show_refusal)
	_build_toast.call_deferred()

## The plate in the top-right corner: night, clock, cash.
func _build_plate() -> void:
	var corner := MarginContainer.new()
	corner.set_anchors_preset(Control.PRESET_FULL_RECT)
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.theme = UiTheme.font_theme()
	corner.add_theme_constant_override("margin_top", 40)
	corner.add_theme_constant_override("margin_right", 48)
	add_child(corner)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiTheme.plate_panel())
	plate.size_flags_horizontal = Control.SIZE_SHRINK_END
	plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	corner.add_child(plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	plate.add_child(col)
	plate_night = _plate_label(col, "display", 30, AMBER)
	plate_time = _plate_label(col, "numbers", 22, SILVER)
	plate_cash = _plate_label(col, "numbers", 22, AMBER)
	plate_bank = _plate_label(col, "numbers", 14, UiTheme.DIM)
	plate_bank.name = "Bank"
	_refresh_plate()


func _plate_label(parent: Control, role: String, size_px: int, colour: Color) -> Label:
	var l := Label.new()
	UiTheme.apply(l, role, size_px)
	l.add_theme_color_override("font_color", colour)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(l)
	return l

## Race core (RC1): until meet spots exist (RC3) a race starts from here, and
## mid-race the same button is "Give up race" (Roy 88). Either way the game
## resumes at once.
func _race_pressed() -> void:
	var race: RaceController = get_parent().get("race")
	if race == null:
		return
	if race.is_racing():
		race.give_up()
	else:
		race.start_race()
	game_state.resume()

func _refresh_race_button() -> void:
	var race: Variant = get_parent().get("race")
	if race != null:
		race_button.text = "Give up race" if race.is_racing() else "Race a test rival"


## The refusal toast lives on its own layer beside this one, because this layer
## is hidden whenever the game is not paused, which is exactly when it shows.
func _build_toast() -> void:
	var layer_node := CanvasLayer.new()
	layer_node.layer = 12
	layer_node.process_mode = Node.PROCESS_MODE_ALWAYS
	toast = Label.new()
	toast.text = GameState.CHASE_LOCK_TEXT
	UiTheme.apply(toast, "subtitle", 26)
	toast.add_theme_color_override("font_color", AMBER)
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.offset_top = 120
	toast.modulate.a = 0.0
	layer_node.add_child(toast)
	add_sibling(layer_node)

func _show_refusal() -> void:
	if toast == null:
		return
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	toast.modulate.a = 1.0
	_toast_tween = toast.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_toast_tween.tween_interval(TOAST_SECS * 0.7)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, TOAST_SECS * 0.3)

# ---------- the rows ----------
func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 40)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	parent.add_child(b)
	return b

## In a race the second row quits the race instead of restarting the night.
func _ask_restart() -> void:
	if game_state.in_race:
		confirm.ask("Quit this race?", "Quit race", _quit_race)
	else:
		confirm.ask("Restart this night? The run starts over.", "Restart", game_state.restart)

func _quit_race() -> void:
	game_state.race_quit_requested.emit()
	game_state.resume()

func _ask_quit_to_title() -> void:
	var text := "Quit to the title? Your run is saved."
	if GameState.chase_locked():
		text = "Quit to the title mid-chase? That counts as a bust."
	confirm.ask(text, "Quit", game_state.quit_to_title)

## Resets temperatures, tyre, clutch and brake wear (the garage will own this later).
## Reached from the Settings Game tab while the garage does not exist.
func _service_car() -> void:
	var player: Variant = get_parent().get("player")
	if player != null and player.get("health") != null:
		player.health.repair()
		player.damage.garage_repair(null)  # free until the garage and the bank exist

## Ferris's tow (damage slice 1): only for a dead engine, never in a chase.
## The car goes home, the night ends, and the garage at home fixes it; the
## bank pays once it exists (null = free for now). Chases come with Stage F.
func _call_tow() -> void:
	var game := get_parent()
	var player: Variant = game.get("player")
	if player == null or player.get("damage") == null or not player.damage.is_engine_dead():
		return
	if not player.damage.tow(null, false):
		return
	player.damage.garage_repair(null)
	player.health.repair()
	var clock: Variant = game.get("night_clock")
	if clock != null:
		clock.end_night()
	game_state.restart()

func _on_state_changed(new_state: GameState.State, old_state: GameState.State) -> void:
	var was_visible := visible
	visible = new_state == GameState.State.PAUSED
	if visible:
		_refresh_race_button()
		show_main()  # always reopen on the main page
		_refresh_plate()
		_refresh_notice()
		restart_button.text = "Quit race" if game_state.in_race else "Restart night"
		if not was_visible and old_state == GameState.State.PLAYING:
			_open_effects()   # coming back from photo mode stays silent

## Slide in over the frozen frame, with the squelch.
func _open_effects() -> void:
	MenuMotion.slide_in(slide_root, Vector2.LEFT)
	var sfx: Variant = get_parent().get("menu_sfx")
	if sfx != null:
		sfx.squelch()

func _refresh_notice() -> void:
	notice_label.text = game_state.pause_notice
	notice_label.visible = game_state.pause_notice != ""
	if game_state.pause_notice == GameState.REASON_STALL and lower_look_target() == "":
		notice_label.text = STALL_ON_LOW
	lower_look_button.text = "Lower the look to %s" % lower_look_target().capitalize()
	lower_look_button.visible = game_state.pause_notice == GameState.REASON_STALL and lower_look_target() != ""

const STALL_ON_LOW := "Your PC fell behind, so the game paused. The look is already at its lowest."

## The Quality preset one step under the current one ("" when already on Low;
## a hand-tuned Custom set goes to Low).
static func lower_look_target() -> String:
	var i := GraphicsSettings.PRESETS.find(GraphicsSettings.preset)
	if i == 0:
		return ""
	return GraphicsSettings.PRESETS[i - 1] if i > 0 else GraphicsSettings.PRESETS[0]

## The stall line's offer: one Quality step down, saved, and back to the road.
func _lower_look() -> void:
	var target := lower_look_target()
	if target == "":
		return
	GraphicsSettings.set_preset(target)
	GraphicsSettings.auto_picked = false
	GraphicsSettings.apply(get_tree())
	GraphicsSettings.save_settings()
	game_state.resume()

## "NIGHT 7 / 2:14 AM / $350 / Bank $4,200"
func _refresh_plate() -> void:
	var night := 1
	var minutes := 0.0
	if night_clock != null:
		night = int(night_clock.get("night"))
		minutes = float(night_clock.get("minutes"))
	plate_night.text = "NIGHT %d" % night
	plate_time.text = NightClock.clock_text(minutes)
	plate_cash.visible = wallet != null
	plate_bank.visible = wallet != null
	if wallet != null:
		plate_cash.text = wallet.money(wallet.cash)
		plate_bank.text = "Bank %s" % wallet.money(wallet.bank)

## Opens the Settings screen on top of this menu (a page name, or the first).
func show_settings(page: Variant = 0) -> void:
	settings.open(page)

func _on_settings_closed() -> void:
	if visible:
		settings_button.grab_focus()

func show_main() -> void:
	main_page.visible = true
	resume_button.grab_focus()  # keyboard/controller can navigate the menu
