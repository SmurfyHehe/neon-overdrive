class_name GameSettings
extends RefCounted

# Settings that belong to no other screen (Settings > Game tab, 2026-10-10).
# Saved as [game] in the same settings.cfg as the rest (AudioSettings.path).
#
#   tips   hint lines on the loading and between-night screens: on by default.
#          Nothing shows them yet; the screen that will reads GameSettings.tips.
#   wrecks (test build only) "Meter" counts crashes on the totalled meter
#          (scripts/car/totalled_meter.gd); "Off" leaves the wreck sensor off,
#          as the sandbox always did. Outside the test build the sensor is
#          always on and the row is hidden.

const DEFAULT_TIPS := true
## Meter by default in the test build, so the people testing feel it.
const DEFAULT_WRECKS_METER := true

static var tips := DEFAULT_TIPS
static var wrecks_meter := DEFAULT_WRECKS_METER

## The test build (the sandbox with the parked start and the stand-in rows).
## TODO(PR #402): this reads the neon/test_build project setting; once that
## PR's TestBuild.on() is on the base, return that instead.
static func test_build() -> bool:
	return ProjectSettings.has_setting("neon/test_build") and bool(ProjectSettings.get_setting("neon/test_build"))

## Whether the game's wreck sensor should be on, ignoring the benchmark and
## tests (Game.wrecks_on handles those): always outside the test build, the
## "Wrecks" row inside it.
static func wrecks_enabled() -> bool:
	return not test_build() or wrecks_meter

static func set_wrecks_meter(on: bool) -> void:
	wrecks_meter = on

static func set_tips(on: bool) -> void:
	tips = on

static func reset_defaults() -> void:
	tips = DEFAULT_TIPS
	wrecks_meter = DEFAULT_WRECKS_METER

static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	reset_defaults()
	if not ok:
		return
	var t: Variant = cfg.get_value("game", "tips", DEFAULT_TIPS)
	set_tips(t if t is bool else str(t).to_lower() == "true")
	var w: Variant = cfg.get_value("game", "wrecks", "meter")
	set_wrecks_meter(str(w).to_lower() != "off")

## Rewrites only the [game] section; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("game", "tips", tips)
	cfg.set_value("game", "wrecks", "meter" if wrecks_meter else "off")
	return cfg.save(AudioSettings.path) == OK
