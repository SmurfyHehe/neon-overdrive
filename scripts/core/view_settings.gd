class_name ViewSettings
extends RefCounted

# View settings (2026-10-06): the cockpit field of view, in the same
# user://settings.cfg AudioSettings uses (its own [view] section). The pause
# menu shows one slider; ChaseCamera reads cockpit_fov every frame, so a change
# applies at once. The speed widening (up to +6 degrees) is added on top.

const COCKPIT_FOV_DEFAULT := 62.0
const COCKPIT_FOV_MIN := 55.0
const COCKPIT_FOV_MAX := 78.0

const CAMERA_SMOOTHING_DEFAULT := 1   # chase-cam smoothing (#31): 0 A hard snap, 1 B light (default, #119), 2 C smoothing + swing
const CAMERA_SMOOTHING_MAX := 2

## The view F left the game in (2026-10-11): "chase", "cockpit" or "hood". Chase
## is where the game has always started; flip the default here to start elsewhere.
const CAMERA_VIEWS := ["chase", "cockpit", "hood"]
const CAMERA_VIEW_DEFAULT := "chase"

static var cockpit_fov := COCKPIT_FOV_DEFAULT
static var camera_view := CAMERA_VIEW_DEFAULT

## Whether the view F left is remembered across starts. Play only: on the test
## folder's shared settings file one test's last F press would start the next
## one in another view. A test that sets its own AudioSettings.path opts in.
static func remembers_view() -> bool:
	var TestMode := preload("res://scripts/core/test_mode.gd")
	return not TestMode.active() or AudioSettings.path != AudioSettings.default_path()

static func set_camera_view(v: String) -> void:
	camera_view = v if CAMERA_VIEWS.has(v) else CAMERA_VIEW_DEFAULT
static var camera_smoothing := CAMERA_SMOOTHING_DEFAULT

static func set_camera_smoothing(v: int) -> void:
	camera_smoothing = clampi(v, 0, CAMERA_SMOOTHING_MAX)

static func set_cockpit_fov(v: float) -> void:
	cockpit_fov = clampf(v, COCKPIT_FOV_MIN, COCKPIT_FOV_MAX) if is_finite(v) else COCKPIT_FOV_DEFAULT  # clampf passes NaN through

## Reads the file (missing or damaged means the default). Shares AudioSettings.path
## so tests that redirect one redirect all.
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	set_cockpit_fov(float(cfg.get_value("view", "cockpit_fov", COCKPIT_FOV_DEFAULT)) if ok else COCKPIT_FOV_DEFAULT)
	set_camera_smoothing(int(cfg.get_value("view", "camera_smoothing", CAMERA_SMOOTHING_DEFAULT)) if ok else CAMERA_SMOOTHING_DEFAULT)
	set_camera_view(str(cfg.get_value("view", "camera_view", CAMERA_VIEW_DEFAULT)) if ok else CAMERA_VIEW_DEFAULT)

## Rewrites only the [view] section; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("view", "cockpit_fov", cockpit_fov)
	cfg.set_value("view", "camera_smoothing", camera_smoothing)
	cfg.set_value("view", "camera_view", camera_view)
	return cfg.save(AudioSettings.path) == OK
