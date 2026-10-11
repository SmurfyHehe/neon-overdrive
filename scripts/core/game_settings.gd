class_name GameSettings
extends RefCounted

# Settings that belong to no other screen (Settings > Game tab, 2026-10-10).
# Saved as [game] in the same settings.cfg as the rest (AudioSettings.path).
#
#   tips      hint lines on the loading and between-night screens: on by
#             default. Nothing shows them yet; the screen that will reads
#             GameSettings.tips.
#   critters  "Roaches and rats" (2026-10-11): the roaches, the rats and the
#             flies over the bin bags on the title, and anywhere they are
#             used later. On by default. The moths are not part of it.

const DEFAULT_TIPS := true
const DEFAULT_CRITTERS := true

static var tips := DEFAULT_TIPS
static var critters := DEFAULT_CRITTERS

static func set_tips(on: bool) -> void:
	tips = on

static func set_critters(on: bool) -> void:
	critters = on

static func reset_defaults() -> void:
	tips = DEFAULT_TIPS
	critters = DEFAULT_CRITTERS

static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	reset_defaults()
	if not ok:
		return
	var t: Variant = cfg.get_value("game", "tips", DEFAULT_TIPS)
	set_tips(t if t is bool else str(t).to_lower() == "true")
	var c: Variant = cfg.get_value("game", "critters", DEFAULT_CRITTERS)
	set_critters(c if c is bool else str(c).to_lower() == "true")

## Rewrites only the [game] section; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("game", "tips", tips)
	cfg.set_value("game", "critters", critters)
	return cfg.save(AudioSettings.path) == OK
