class_name ViewSettings
extends RefCounted

# View settings (2026-10-06): the cockpit field of view, in the same
# user://settings.cfg AudioSettings uses (its own [view] section). The pause
# menu shows one slider; ChaseCamera reads cockpit_fov every frame, so a change
# applies at once. The speed widening (up to +6 degrees) is added on top.
# Default 76 (was 62, 2026-10-07): the smallest round FOV that keeps both door
# mirrors and the rearview on screen at 16:9 with the cockpit head yaw (73 is
# the bare minimum; the extra covers head sway). Below ~73 the passenger
# mirror starts to leave the edge.

const COCKPIT_FOV_DEFAULT := 76.0
const COCKPIT_FOV_MIN := 55.0
const COCKPIT_FOV_MAX := 78.0

static var cockpit_fov := COCKPIT_FOV_DEFAULT

static func set_cockpit_fov(v: float) -> void:
	cockpit_fov = clampf(v, COCKPIT_FOV_MIN, COCKPIT_FOV_MAX) if is_finite(v) else COCKPIT_FOV_DEFAULT  # clampf passes NaN through

## Reads the file (missing or damaged means the default). Shares AudioSettings.path
## so tests that redirect one redirect all.
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	set_cockpit_fov(float(cfg.get_value("view", "cockpit_fov", COCKPIT_FOV_DEFAULT)) if ok else COCKPIT_FOV_DEFAULT)

## Rewrites only the [view] section; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("view", "cockpit_fov", cockpit_fov)
	return cfg.save(AudioSettings.path) == OK
