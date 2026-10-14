extends SceneTree

# Song names (R3, 2026-10-11): every .ogg on the dial has a title and a made-up
# artist from its folder's tracks.md, and the radio never shows a file name.
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --audio-driver Dummy -s res://tests/audio/song_names.gd

func _initialize() -> void:
	var failures: Array[String] = []
	var songs := 0
	var artists := {}
	for s in RadioStations.station_count():
		for path in RadioStations.track_paths(s):
			songs += 1
			var stem := path.get_file().get_basename()
			var info := RadioStations.song_info(s, path.get_file())
			var title: String = info.title
			var artist: String = info.artist
			var table := RadioStations._song_table(RadioStations.STATIONS[s].dir)
			if not table.has(stem):
				failures.append("%s is not in its tracks.md" % stem)
			if title == "" or artist == "":
				failures.append("%s: empty title or artist" % stem)
			if title == stem or title.contains("_") or title.contains(".ogg") or title.contains("-"):
				failures.append("%s: the title looks like a file name (%s)" % [stem, title])
			if artist == RadioStations.STATIONS[s].name:
				failures.append("%s: no artist" % stem)
			artists[artist] = true
	if songs != 23:
		failures.append("expected 23 songs on the dial, found %d" % songs)
	# the fallback never shows a file name either
	var fb := RadioStations.song_info(1, "99_some-new-song_late.ogg")
	if fb.title != "Some New Song":
		failures.append("fallback title: %s" % fb.title)
	# a saved index from before the dial lands on Afterglow
	if RadioStations.migrate_saved(5) != RadioStations.DEFAULT_STATION or RadioStations.migrate_saved(-1) != -1:
		failures.append("old save indices should map to Afterglow, -1 stays off")
	if RadioStations.migrate_saved(0, "undertow") != 2:
		failures.append("a saved station id finds its station")
	print("songs: %d, artists: %s" % [songs, str(artists.keys())])
	for f in failures:
		printerr("FAIL: ", f)
	print("song_names: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
