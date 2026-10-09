extends RefCounted

# The game's name and version (release readiness, 2026-10-08). Both live in
# project.godot only: application/config/name and application/config/version.
# Renaming the game is that one line; the window title, the pause menu, bug
# reports and the licence notices read it, the exe's version comes from here
# (export_presets.cfg leaves it empty), and tools/export-release.ps1 copies
# the name into the exe's product name.
# Bump the version for every build that leaves this laptop (major.minor.patch).
#
# No class_name on purpose: preload it, so no class cache refresh is needed.

static func game_name() -> String:
	return str(ProjectSettings.get_setting("application/config/name", ""))

static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

## "Neon Overdrive 0.1.0", plus " (dev)" when not running an exported release build.
static func title() -> String:
	var t := "%s %s" % [game_name(), version()]
	if not OS.has_feature("template_release"):
		t += " (dev)"
	return t
