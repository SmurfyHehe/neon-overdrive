extends SceneTree

# Writes THIRD_PARTY_NOTICES.txt, the licence notices that ship next to the exe
# (release readiness, 2026-10-08). Godot's MIT licence asks for its notice, and
# its bundled libraries' notices, in every copy of the engine; GEVP's MIT
# licence asks the same. A file, not on-screen credits.
#
# The Godot part comes from the running engine (Engine.get_license_text,
# get_copyright_info, get_license_info), so it always matches the Godot that
# exports the game. tools/export-release.ps1 runs this; by hand:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tools/write_licence_notices.gd
# Writes res://THIRD_PARTY_NOTICES.txt, or the path given after "--".

const GameInfo := preload("res://scripts/game_info.gd")
const GEVP_LICENCE := "res://scripts/vendor/gevp/LICENSE.txt"

func _initialize() -> void:
	var out := "res://THIRD_PARTY_NOTICES.txt"
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		out = user_args[0]
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		printerr("write_licence_notices: cannot write %s (%s)" % [out, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	f.store_string(notices())
	f.close()
	print("write_licence_notices: wrote ", ProjectSettings.globalize_path(out))
	quit(0)

static func notices() -> String:
	var lines: PackedStringArray = []
	lines.append("%s %s uses the third-party software below." % [GameInfo.game_name(), GameInfo.version()])
	lines.append("Their licences ask that these notices ship with every copy.")
	lines.append("")
	lines.append(_rule("Godot Engine %s" % Engine.get_version_info().string))
	lines.append("https://godotengine.org")
	lines.append("")
	lines.append("This game uses Godot Engine, available under the following license:")
	lines.append("")
	lines.append(Engine.get_license_text().strip_edges())
	lines.append("")
	lines.append(_rule("GEVP (Godot Easy Vehicle Physics)"))
	lines.append("https://github.com/DAShoe1/Godot-Easy-Vehicle-Physics")
	lines.append("")
	lines.append(FileAccess.get_file_as_string(GEVP_LICENCE).strip_edges())
	lines.append("")
	lines.append(_rule("Third-party components inside Godot Engine"))
	lines.append("")
	var licences := Engine.get_license_info()
	var used := {}
	for c in Engine.get_copyright_info():
		lines.append(str(c.name))
		for part in c.parts:
			for holder in part.copyright:
				lines.append("  Copyright (c) %s" % holder)
			lines.append("  License: %s" % part.license)
			for id in licences:
				if str(part.license).contains(id):
					used[id] = true
		lines.append("")
	lines.append(_rule("Licence texts for the components above"))
	var ids := used.keys()
	ids.sort()
	for id in ids:
		lines.append("")
		lines.append("--- %s ---" % id)
		lines.append("")
		lines.append(str(licences[id]).strip_edges())
	lines.append("")
	return "\n".join(lines)

static func _rule(title: String) -> String:
	return "=".repeat(72) + "\n" + title + "\n" + "=".repeat(72)
