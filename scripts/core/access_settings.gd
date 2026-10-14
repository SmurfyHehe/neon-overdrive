class_name AccessSettings
extends RefCounted

# Comfort settings (accessibility spec step 3, 2026-10-13: the first two keys).
# Saved under [access] in the same user://settings.cfg the other settings use,
# so the Accessibility tab can add its rows here later. Shown on the View page.
# - shake_scale: every camera shake (speed buzz, kerb rumble, hits, road bumps,
#   the engine catching) times this, 0 (none) .. 1 (as built).
# - fov_widening: off holds every view at its own FOV whatever the speed (the
#   chase view's acceleration term goes too).

const SHAKE_DEFAULT := 1.0

static var shake_scale := SHAKE_DEFAULT
static var fov_widening := true

static func set_shake_scale(v: float) -> void:
	shake_scale = clampf(v, 0.0, 1.0) if is_finite(v) else SHAKE_DEFAULT   # clampf passes NaN through

## Back to the defaults (the View page's Reset row).
static func reset() -> void:
	shake_scale = SHAKE_DEFAULT
	fov_widening = true

## Reads the file (missing or damaged means the defaults).
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	set_shake_scale(float(cfg.get_value("access", "shake_scale", SHAKE_DEFAULT)) if ok else SHAKE_DEFAULT)
	fov_widening = FxSettings._to_bool(cfg.get_value("access", "fov_widening", true)) if ok else true

## Rewrites only these keys; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("access", "shake_scale", shake_scale)
	cfg.set_value("access", "fov_widening", fov_widening)
	return cfg.save(AudioSettings.path) == OK
