class_name DisplaySettings
extends RefCounted

# Display settings (menus A-list, 2026-10-08): fullscreen, window resolution and
# a render-scale slider, in the shared user://settings.cfg ([display] section).
#
# - Fullscreen is the default, so the very first launch opens fullscreen (no
#   [display] section yet). It is Godot's borderless fullscreen, not exclusive,
#   so alt-tab is instant.
# - Resolution is the window size when not fullscreen. Fullscreen always uses
#   the screen's own size; the render scale is the knob for speed there.
# - Render scale draws the 3D world at a fraction of the window's pixels
#   (Viewport.scaling_3d_scale) and stretches it up; the HUD and menus stay
#   sharp. 100% is the old behaviour; 70% is a big win on integrated graphics.
#
# apply() only touches the window in a real play session (player_run()): tests
# and the benchmark keep the window they were started with.

const TestMode := preload("res://scripts/test_mode.gd")

const FULLSCREEN_DEFAULT := true
const RENDER_SCALE_DEFAULT := 1.0
const RENDER_SCALE_MIN := 0.5
const RENDER_SCALE_MAX := 1.0
## Window sizes offered in the menu; ones larger than the screen are hidden.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440)]
const RESOLUTION_DEFAULT := Vector2i(1280, 720)

static var fullscreen := FULLSCREEN_DEFAULT
static var resolution := RESOLUTION_DEFAULT
static var render_scale := RENDER_SCALE_DEFAULT

static func set_fullscreen(on: bool) -> void:
	fullscreen = on

static func set_resolution(r: Vector2i) -> void:
	resolution = r if RESOLUTIONS.has(r) else RESOLUTION_DEFAULT

static func set_render_scale(v: float) -> void:
	render_scale = clampf(v, RENDER_SCALE_MIN, RENDER_SCALE_MAX) if is_finite(v) else RENDER_SCALE_DEFAULT

static func reset_defaults() -> void:
	fullscreen = FULLSCREEN_DEFAULT
	resolution = RESOLUTION_DEFAULT
	render_scale = RENDER_SCALE_DEFAULT

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
	set_render_scale(float(cfg.get_value("display", "render_scale", RENDER_SCALE_DEFAULT)))

## Rewrites only the [display] section; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "resolution", resolution)
	cfg.set_value("display", "render_scale", render_scale)
	return cfg.save(AudioSettings.path) == OK

## Render scale always; window mode and size only in a player run.
static func apply(window: Window) -> void:
	if window == null:
		return
	window.scaling_3d_scale = render_scale
	if not player_run():
		return
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	else:
		if window.mode != Window.MODE_WINDOWED:
			window.mode = Window.MODE_WINDOWED
		window.size = resolution
		window.move_to_center()
