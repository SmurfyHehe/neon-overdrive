extends SceneTree

# No-stray-fonts test. Every text takes one role through UiTheme.font(role); the
# game never ships a system font or Godot's built-in default font.
#
# Fails when:
#   - any script or tool uses SystemFont, ThemeDB.fallback_font or get_theme_default_font
#   - a script that builds Label / Button / CheckBox / OptionButton / Label3D or
#     calls draw_string does not reference UiTheme
#   - project.godot has no gui/theme/custom_font (the default for anything missed)
#   - a role font fails to load, or a bundled font file has no licence entry
#
# Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/ui/fonts.gd

const BANNED := ["SystemFont", "ThemeDB.fallback_font", "get_theme_default_font", "get_theme_font("]
const MAKERS := ["Label.new(", "Button.new(", "CheckBox.new(", "CheckButton.new(", "OptionButton.new(", "LineEdit.new(", "RichTextLabel.new(", "Label3D.new(", "draw_string("]
const FAMILY_NOTES := {
	"BarlowCondensed": "Barlow", "BarlowSemiCondensed": "Barlow", "BigShouldersDisplay": "Big Shoulders",
	"ShareTechMono": "Share Tech", "DSEG7Classic": "DSEG", "VT323": "VT323", "Caveat": "Caveat", "Overpass": "Overpass",
}

var failures: Array[String] = []

func _initialize() -> void:
	var files: Array[String] = []
	_collect("res://scripts", files)
	_collect("res://tools", files)
	_check(files.size() > 50, "found only %d scripts, the scan is not looking in the right place" % files.size())
	var themed := 0
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for b in BANNED:
			if text.contains(b) and not path.ends_with("ui_theme.gd"):
				failures.append("%s uses %s - take a font role from UiTheme.font()" % [path, b])
		var makes := false
		for m in MAKERS:
			if text.contains(m):
				makes = true
		if makes:
			if text.contains("UiTheme"):
				themed += 1
			else:
				failures.append("%s builds text but never mentions UiTheme (assign a role font)" % path)
	_check(themed >= 10, "only %d text-building scripts use UiTheme" % themed)

	var project := FileAccess.get_file_as_string("res://project.godot")
	_check(project.contains("theme/custom_font="), "project.godot has no gui/theme/custom_font, so unstyled text would use Godot's default font")

	for role in UiTheme.ROLES:
		var f := UiTheme.font(role)
		_check(f != null, "role '%s' did not load a font" % role)
	for alias in UiTheme.ALIASES:
		_check(UiTheme.font(alias) == UiTheme.font(UiTheme.ALIASES[alias]), "alias '%s' is not its role" % alias)

	var licences := FileAccess.get_file_as_string("res://THIRD_PARTY_LICENSES.txt")
	var d := DirAccess.open("res://assets/fonts")
	_check(d != null, "assets/fonts is missing")
	if d != null:
		var n := 0
		for f in d.get_files():
			if f.ends_with(".ttf") or f.ends_with(".otf"):
				n += 1
				var covered := false
				for key in FAMILY_NOTES:
					if f.begins_with(key) and licences.contains(FAMILY_NOTES[key]):
						covered = true
				_check(covered, "font file %s has no entry in THIRD_PARTY_LICENSES.txt" % f)
		_check(n >= 8, "expected at least 8 font files, found %d" % n)

	if failures.is_empty():
		print("PASS: fonts (%d scripts scanned, %d text-building scripts themed, %d roles)" % [files.size(), themed, UiTheme.ROLES.size()])
		quit(0)
	else:
		for m in failures:
			printerr("FAIL: ", m)
		quit(1)

func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for sub in d.get_directories():
		if sub != "vendor":
			_collect(dir_path.path_join(sub), out)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
