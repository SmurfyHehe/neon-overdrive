class_name PauseMenu
extends CanvasLayer

# Pause overlay (issue #27). Deliberately plain: a dim backdrop and Godot's
# default buttons, no theme or styling. The menu's look is Roy's call later;
# restyle here without touching GameState.
#
# The long column of sliders is gone: volume, graphics, view and key bindings
# live on the Settings screen (scripts/ui/settings_screen.gd), one button away.

const GameInfo := preload("res://scripts/core/game_info.gd")
const LogFolder := preload("res://scripts/core/log_folder.gd")

const SILVER := Color("#C9CED6")
const AMBER := Color("#FFC066")

var game_state: GameState
var resume_button: Button
var settings_button: Button
var settings: SettingsScreen
var main_page: VBoxContainer
var cars_page: VBoxContainer

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
	main_page = box

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	resume_button = _add_button(box, "Resume", game_state.resume)
	_add_button(box, "Car: " + PlayerCars.title(PlayerCar.chassis_kind()), show_cars)
	settings_button = _add_button(box, "Settings", show_settings)
	_add_button(box, "Service car (reset wear)", _service_car)
	_add_button(box, "Open log folder", LogFolder.open)
	_add_button(box, "Restart", game_state.restart)
	_add_button(box, "Quit", game_state.quit)

	# Version line (release readiness, 2026-10-08), so a bug report can name the build.
	var version_label := Label.new()
	version_label.text = GameInfo.title()
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_label.add_theme_color_override("font_color", SILVER)
	version_label.add_theme_font_size_override("font_size", 12)
	box.add_child(version_label)

	_build_cars_page(center)
	settings = SettingsScreen.new(game_state)
	add_child(settings)
	settings.closed.connect(_on_settings_closed)
	game_state.state_changed.connect(_on_state_changed)

## Resets temperatures, tyre, clutch and brake wear (the garage will own this later).
func _service_car() -> void:
	var player: Variant = get_parent().get("player")
	if player != null and player.get("health") != null:
		player.health.repair()

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
		show_main()  # always reopen on the main page

## Opens the Settings screen on top of this menu (a page name, or the first).
func show_settings(page: Variant = 0) -> void:
	settings.open(page)

func _on_settings_closed() -> void:
	if visible:
		settings_button.grab_focus()

func show_main() -> void:
	main_page.visible = true
	cars_page.visible = false
	resume_button.grab_focus()  # keyboard/controller can navigate the menu

# ---------- Car page (stage D, Roy 2026-10-09) ----------
## One button per player car (PlayerCars.KINDS). Picking one saves it and
## restarts the run in that car; the garage replaces this page later.
func show_cars() -> void:
	main_page.visible = false
	cars_page.visible = true
	var first := cars_page.get_child(1)
	if first is Button:
		(first as Button).grab_focus()

func _build_cars_page(center: CenterContainer) -> void:
	cars_page = VBoxContainer.new()
	cars_page.add_theme_constant_override("separation", 8)
	cars_page.visible = false
	center.add_child(cars_page)
	var title := Label.new()
	title.text = "CAR  (restarts the run)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cars_page.add_child(title)
	var now := PlayerCar.chassis_kind()
	for k in PlayerCars.KINDS:
		var text := "%s   %d Nm / %d kg" % [PlayerCars.title(k.id), int(k.nm), int(k.kg)]
		if k.id == now:
			text += "   (driving)"
		var b := _add_button(cars_page, text, _pick_car.bind(String(k.id)))
		b.custom_minimum_size = Vector2(420, 0)
	_add_button(cars_page, "Back", show_main)

func _pick_car(kind: String) -> void:
	PlayerCars.select(kind)
	PlayerCars.save_settings()
	game_state.restart()
