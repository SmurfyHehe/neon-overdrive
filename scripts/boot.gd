class_name Boot
extends Control

# Title screen and loading card (2026-10-09). The first scene the game opens:
# the game's name, one prompt, then a loading card while Game.tscn loads in the
# background and the scene changes. Keyboard only, no key hints beyond the one
# prompt (the Controls page lives in the pause menu). No assets: plain colour
# and the default font, in the Amber vs. Dusk palette.
#
# First launch opens fullscreen once (the choice is remembered in the [display]
# section of the settings file; after that the window is left as it is, so a
# player who goes windowed stays windowed). Headless runs and tests never touch
# the window.
#
# NEON_SKIP_TITLE=1 or --benchmark go straight to the game.

signal start_requested
signal game_loaded

const GAME_SCENE := "res://Game.tscn"
const GAME_NAME := "BOOST SIMCADE"
const NAVY := Color("#0E1424")
const NAVY_LIGHT := Color("#1B2A4A")
const ORANGE := Color("#FF8A1F")
const AMBER := Color("#FFC066")
const SILVER := Color("#C9CED6")

var title_page: Control
var loading_page: Control
var bar: ProgressBar
var loading := false
var change_scene_on_load := true

static func skip_title() -> bool:
	return OS.get_environment("NEON_SKIP_TITLE") == "1" or OS.get_cmdline_user_args().has("--benchmark")

## True once, on the first launch. Marks it done in the settings file.
static func first_launch_pending() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	return not bool(cfg.get_value("display", "launched_before", false))

static func mark_launched() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)  # keep the other sections
	cfg.set_value("display", "launched_before", true)
	return cfg.save(AudioSettings.path) == OK

static func apply_first_launch_window() -> bool:
	if DisplayServer.get_name() == "headless" or TestMode_active():
		return false
	if not first_launch_pending():
		return false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	mark_launched()
	return true

static func TestMode_active() -> bool:
	return preload("res://scripts/test_mode.gd").active()

func _ready() -> void:
	name = "Boot"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	DisplayServer.window_set_title("Boost Simcade")
	apply_first_launch_window()
	_build()
	if skip_title():
		start()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = NAVY
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	title_page = _centered_page()
	var title := _label(GAME_NAME, 72, ORANGE)
	title_page.get_child(0).add_child(title)
	var rule := ColorRect.new()
	rule.color = NAVY_LIGHT
	rule.custom_minimum_size = Vector2(0, 4)
	title_page.get_child(0).add_child(rule)
	title_page.get_child(0).add_child(_label("Press Enter to drive", 22, AMBER))
	add_child(title_page)

	loading_page = _centered_page()
	loading_page.visible = false
	loading_page.get_child(0).add_child(_label("LOADING", 40, AMBER))
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(420, 10)
	bar.show_percentage = false
	bar.max_value = 1.0
	loading_page.get_child(0).add_child(bar)
	add_child(loading_page)

func _centered_page() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	return center

func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l

func _unhandled_input(event: InputEvent) -> void:
	if loading or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			start()
		KEY_ESCAPE:
			get_tree().quit()

## Starts loading the game; the loading card replaces the title.
func start() -> void:
	if loading:
		return
	loading = true
	title_page.visible = false
	loading_page.visible = true
	start_requested.emit()
	ResourceLoader.load_threaded_request(GAME_SCENE)

func _process(_delta: float) -> void:
	if not loading:
		return
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(GAME_SCENE, progress)
	if progress.size() > 0:
		bar.value = progress[0]
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		loading = false
		set_process(false)
		bar.value = 1.0
		game_loaded.emit()
		if change_scene_on_load:
			get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(GAME_SCENE))
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		loading = false
		set_process(false)
		push_error("Boot: could not load " + GAME_SCENE)
