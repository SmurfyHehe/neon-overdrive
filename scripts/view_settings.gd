class_name ViewSettings
extends RefCounted

# View settings (2026-10-06): the cockpit field of view, in the same
# user://settings.cfg AudioSettings uses (its own [view] section). The pause
# menu shows one slider; ChaseCamera reads cockpit_fov every frame, so a change
# applies at once. The speed widening (up to +6 degrees) is added on top.
# The driving-feel pass (2026-10-08) adds camera shake strength: one slider,
# 0 (a steady camera) to 1 (the full shake), scaling every camera shake and
# kick (speed buzz, kerbs, hits) in both views.

const COCKPIT_FOV_DEFAULT := 62.0
const COCKPIT_FOV_MIN := 55.0
const COCKPIT_FOV_MAX := 78.0

const SHAKE_DEFAULT := 1.0

static var cockpit_fov := COCKPIT_FOV_DEFAULT
static var shake := SHAKE_DEFAULT

static func set_shake(v: float) -> void:
	shake = clampf(v, 0.0, 1.0) if is_finite(v) else SHAKE_DEFAULT

static func set_cockpit_fov(v: float) -> void:
	cockpit_fov = clampf(v, COCKPIT_FOV_MIN, COCKPIT_FOV_MAX) if is_finite(v) else COCKPIT_FOV_DEFAULT  # clampf passes NaN through

## Reads the file (missing or damaged means the default). Shares AudioSettings.path
## so tests that redirect one redirect all.
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	set_cockpit_fov(float(cfg.get_value("view", "cockpit_fov", COCKPIT_FOV_DEFAULT)) if ok else COCKPIT_FOV_DEFAULT)
	set_shake(float(cfg.get_value("view", "shake", SHAKE_DEFAULT)) if ok else SHAKE_DEFAULT)

## Rewrites only the [view] section; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("view", "cockpit_fov", cockpit_fov)
	cfg.set_value("view", "shake", shake)
	return cfg.save(AudioSettings.path) == OK
