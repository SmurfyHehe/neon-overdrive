extends SceneTree

# Palette test: scans scripts/*.gd (not scripts/vendor, not tests) for Color(...)
# literals and fails on cyan or magenta. ROADMAP: palette "Amber vs Dusk", "no
# magenta or cyan"; police blue #2E4FD8 is the one off-palette colour, and the
# RPM bar's green is allowed because Roy asked for green -> red there (and again
# for the tuner's danger zones, scripts/core/setting_danger.gd, 2026-10-07).
#
# What counts (r, g, b in 0..1):
#   cyan     g > 0.6 and b > 0.6 and r < 0.35
#   magenta  r > 0.6 and b > 0.6 and g < 0.35
# Read: Color(r, g, b[, a]) with number arguments, Color8(...), Color("#hex"),
# and the named constants Color.CYAN / MAGENTA / FUCHSIA / AQUA. Colours built
# from variables can't be read and are skipped.
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/core/palette.gd

## Colours that are allowed even if they trip a rule (hex, matched within TOLERANCE per channel).
const ALLOWLIST := ["#2E4FD8", "#3FD060"]  # police blue, RPM bar green
const TOLERANCE := 0.02
const NAMED_BAD := ["CYAN", "MAGENTA", "FUCHSIA", "AQUA", "DARK_CYAN", "DARK_MAGENTA"]

var failures: Array[String] = []

static func is_bad(c: Color) -> String:
	for hex in ALLOWLIST:
		var a := Color(hex)
		if absf(a.r - c.r) <= TOLERANCE and absf(a.g - c.g) <= TOLERANCE and absf(a.b - c.b) <= TOLERANCE:
			return ""
	if c.g > 0.6 and c.b > 0.6 and c.r < 0.35:
		return "cyan"
	if c.r > 0.6 and c.b > 0.6 and c.g < 0.35:
		return "magenta"
	return ""

func _initialize() -> void:
	var files: Array[String] = []
	_collect("res://scripts", files)
	_check(files.size() > 20, "found only %d scripts, the scan is not looking in the right place" % files.size())

	# the rule itself
	_check(is_bad(Color(0.0, 0.96, 1.0)) == "cyan", "the old HUD cyan should be caught")
	_check(is_bad(Color(1.0, 0.0, 0.8)) == "magenta", "magenta should be caught")
	_check(is_bad(Color(0.71, 0.65, 0.84)) == "", "the rule only covers cyan and magenta")
	_check(is_bad(Color("#FF8A1F")) == "" and is_bad(Color("#C9CED6")) == "" and is_bad(Color("#E5262B")) == "", "palette colours must pass")
	_check(is_bad(Color("#2E4FD8")) == "", "police blue is allowlisted")

	var num := RegEx.create_from_string(r"^-?(\d+\.?\d*|\.\d+)$")
	var call := RegEx.create_from_string(r"Color(8?)\(([^()]*)\)")
	var named := RegEx.create_from_string(r"\bColor\.([A-Z_]+)\b")
	var scanned := 0
	for path in files:
		var f := FileAccess.open(path, FileAccess.READ)
		var lineno := 0
		while f != null and not f.eof_reached():
			var line := f.get_line()
			lineno += 1
			var code := line.strip_edges()
			if code.begins_with("#"):
				continue
			var cut := line.find(" #")  # trailing comment (hex strings are quoted, so "\"#" never matches)
			if cut >= 0:
				line = line.substr(0, cut)
			for m in call.search_all(line):
				var args := m.get_string(2).split(",")
				var c := Color()
				var ok := false
				if args.size() == 1 and args[0].strip_edges().begins_with("\""):
					var hex := args[0].strip_edges().trim_prefix("\"").trim_suffix("\"")
					if Color.html_is_valid(hex):
						c = Color(hex)
						ok = true
				elif args.size() >= 3 and args.size() <= 4:
					var vals: Array[float] = []
					ok = true
					for a in args:
						var t := a.strip_edges()
						if not num.search(t):
							ok = false
							break
						vals.append(float(t) / (255.0 if m.get_string(1) == "8" else 1.0))
					if ok:
						c = Color(vals[0], vals[1], vals[2])
				if ok:
					scanned += 1
					var bad := is_bad(c)
					if bad != "":
						failures.append("%s:%d %s (#%s) is %s - use the palette (sodium #FF8A1F, amber #FFC066, silver #C9CED6, tail red #E5262B)" % [path, lineno, m.get_string(), c.to_html(false).to_upper(), bad])
			for m in named.search_all(line):
				if NAMED_BAD.has(m.get_string(1)):
					failures.append("%s:%d Color.%s is cyan or magenta" % [path, lineno, m.get_string(1)])
	_check(scanned > 20, "only read %d Color literals, the scanner is probably broken" % scanned)

	if failures.is_empty():
		print("PASS: palette (%d scripts, %d Color literals read)" % [files.size(), scanned])
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
