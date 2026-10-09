class_name DisplaySettings
extends RefCounted

# Display settings (menus A-list, 2026-10-08): fullscreen and window size, in
# the shared user://settings.cfg ([display] section). The 3D resolution scale
# lives in GraphicsSettings (PR #232, the Graphics page), not here.
#
# - Fullscreen is the default, so the very first launch opens fullscreen (no
#   [display] section yet). It is Godot's borderless fullscreen, not exclusive,
#   so alt-tab is instant.
# - Resolution is the window size when not fullscreen. Fullscreen always uses
#   the screen's own size; the Graphics page's resolution scale is the knob
#   for speed there.
#
# apply() only touches the window in a real play session (player_run()): tests
# and the benchmark keep the window they were started with.

const TestMode := preload("res://scripts/core/test_mode.gd")

const FULLSCREEN_DEFAULT := true
## Window sizes offered in the menu; ones larger than the screen are hidden.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440)]
const RESOLUTION_DEFAULT := Vector2i(1280, 720)

static var fullscreen := FULLSCREEN_DEFAULT
static var resolution := RESOLUTION_DEFAULT

static func set_fullscreen(on: bool) -> void:
	fullscreen = on

static func set_resolution(r: Vector2i) -> void:
	resolution = r if RESOLUTIONS.has(r) else RESOLUTION_DEFAULT

static func reset_defaults() -> void:
	fullscreen = FULLSCREEN_DEFAULT
	resolution = RESOLUTION_DEFAULT

## True in a real play session: not a test, not the benchmark, not headless.
static func player_run() -> bool:
	return not TestMode.active() and not Benchmark.requested() and DisplayServer.get_name() != "headless"

## Resolutions that fit on the current screen (always at least the smallest).
static func available_resolutions() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size()
	var out: Array[Vector2i] = []
	for r in RESOLUTIONS:
		if screen.x <= 0 or (r.x <= screen.x and r.y <= screen.y):
			out.append(r)
	if out.is_empty():
		out.append(RESOLUTIONS[0])
	return out

static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	reset_defaults()
	if not ok:
		return
	var fs: Variant = cfg.get_value("display", "fullscreen", FULLSCREEN_DEFAULT)
	set_fullscreen(fs if fs is bool else str(fs).to_lower() == "true")
	var r: Variant = cfg.get_value("display", "resolution", RESOLUTION_DEFAULT)
	set_resolution(r if r is Vector2i else RESOLUTION_DEFAULT)

## Rewrites only the [display] section; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "resolution", resolution)
	return cfg.save(AudioSettings.path) == OK

## Window mode and size, only in a player run.
static func apply(window: Window) -> void:
	if window == null or not player_run():
		return
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	else:
		if window.mode != Window.MODE_WINDOWED:
			window.mode = Window.MODE_WINDOWED
		window.size = resolution
		window.move_to_center()
