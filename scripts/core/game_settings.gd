class_name GameSettings
extends RefCounted

# Settings that belong to no other screen (Settings > Game tab, 2026-10-10).
# Saved as [game] in the same settings.cfg as the rest (AudioSettings.path).
#
#   tips   hint lines on the loading and between-night screens: on by default.
#          Nothing shows them yet; the screen that will reads GameSettings.tips.

const DEFAULT_TIPS := true

static var tips := DEFAULT_TIPS

static func set_tips(on: bool) -> void:
	tips = on

static func reset_defaults() -> void:
	tips = DEFAULT_TIPS

static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	reset_defaults()
	if not ok:
		return
	var t: Variant = cfg.get_value("game", "tips", DEFAULT_TIPS)
	set_tips(t if t is bool else str(t).to_lower() == "true")

## Rewrites only the [game] section; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("game", "tips", tips)
	return cfg.save(AudioSettings.path) == OK
