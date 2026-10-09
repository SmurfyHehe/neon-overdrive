extends SceneTree

# Name, version and licence notices (release readiness, 2026-10-08):
# - project.godot has a name and a major.minor.patch version
# - export_presets.cfg leaves the versions empty, so the exe takes them from
#   project.godot, and its product name matches project.godot (the export
#   script copies it across, so renaming stays a one-line change)
# - the notices hold Godot's licence, GEVP's licence and the bundled components
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/core/game_info.gd

const GameInfo := preload("res://scripts/core/game_info.gd")
const Notices := preload("res://tools/write_licence_notices.gd")

var fails := 0

func _initialize() -> void:
	_check(GameInfo.game_name() != "", "project.godot has no application/config/name")
	var re := RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+$")
	_check(re.search(GameInfo.version()) != null, "version '%s' is not major.minor.patch" % GameInfo.version())
	_check(GameInfo.title().begins_with(GameInfo.game_name() + " " + GameInfo.version()), "title() is '%s'" % GameInfo.title())

	var presets := ConfigFile.new()
	_check(presets.load("res://export_presets.cfg") == OK, "export_presets.cfg did not load")
	for key in ["application/file_version", "application/product_version"]:
		_check(str(presets.get_value("preset.0.options", key, "")) == "", "%s is set in export_presets.cfg; leave it empty so project.godot is the only place" % key)
	_check(str(presets.get_value("preset.0.options", "application/product_name", "")) == GameInfo.game_name(),
		"export_presets.cfg product name differs from project.godot; run tools/export-release.ps1 to copy it across")

	var text := Notices.notices()
	for must in ["Godot Engine", "Juan Linietsky", "GEVP", "David Shoemaker", "FreeType", "Licence texts"]:
		_check(text.contains(must), "licence notices lack '%s'" % must)
	_check(text.length() > 20000, "licence notices look too short (%d chars)" % text.length())
	print("game_info: ", "PASS" if fails == 0 else "FAIL")
	quit(1 if fails > 0 else 0)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL: ", msg)
