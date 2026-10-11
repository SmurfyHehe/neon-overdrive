extends SceneTree

# Writes the song-length table in scripts/audio/radio_lengths.gd, so RadioManager
# can build a playlist without loading the songs (R0, 2026-10-10). Loads one song
# at a time and drops it, so memory stays flat.
#
# Run after adding, removing or re-rendering a song:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tools/radio_lengths.gd
# Check only (exit 1 when the table is stale):
#   ... -s res://tools/radio_lengths.gd -- --check

const FILE := "res://scripts/audio/radio_lengths.gd"
const BEGIN := "# BEGIN TABLE\n"
const END := "# END TABLE\n"

func _initialize() -> void:
	var check := "--check" in OS.get_cmdline_user_args()
	var found := {}
	for s in RadioStations.station_count():
		for path in RadioStations.track_paths(s):
			var stream := load(path) as AudioStream
			if stream == null:
				printerr("radio_lengths: cannot load ", path)
				quit(1)
				return
			found[path] = snappedf(stream.get_length(), 0.001)
	var stale := RadioLengths.stale_entries(found)
	if check:
		for m in stale:
			printerr("radio_lengths: ", m)
		print("radio_lengths: ", "OK" if stale.is_empty() else "STALE (%d)" % stale.size())
		quit(0 if stale.is_empty() else 1)
		return
	var paths := found.keys()
	paths.sort()
	var table := "const LENGTHS := {\n"
	for p in paths:
		table += "\t\"%s\": %s,\n" % [p, str(found[p])]
	table += "}\n"
	var real := ProjectSettings.globalize_path(FILE)
	var text := FileAccess.get_file_as_string(real).replace("\r\n", "\n")
	var a := text.find(BEGIN)
	var b := text.find(END)
	if a < 0 or b < a:
		printerr("radio_lengths: markers not found in ", FILE)
		quit(1)
		return
	text = text.substr(0, a + BEGIN.length()) + table + text.substr(b)
	var f := FileAccess.open(real, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("radio_lengths: wrote %d songs (%d changed)" % [paths.size(), stale.size()])
	quit(0)
