class_name AssistSettings
extends RefCounted

# Driving assists the player switches (2026-10-08), in the same
# user://settings.cfg AudioSettings uses (its own [assist] section). For now
# the slide-catch help (SlideHelp), on by default; the pause menu has the
# switch. Traction control stays on the Tuner, per car.

const SLIDE_HELP_DEFAULT := true

static var slide_help := SLIDE_HELP_DEFAULT

## Reads the file (missing or damaged means the defaults).
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	slide_help = FxSettings._to_bool(cfg.get_value("assist", "slide_help", SLIDE_HELP_DEFAULT)) if ok else SLIDE_HELP_DEFAULT

## Rewrites only the [assist] section; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("assist", "slide_help", slide_help)
	return cfg.save(AudioSettings.path) == OK
