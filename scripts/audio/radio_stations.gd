extends RefCounted
class_name RadioStations

# The radio's dial (file radio 2026-10-06; five named stations 2026-10-11, in dial
# order). Four music stations play the Ogg Vorbis tracks in their folder under
# assets/radio/ (see assets/radio/CREDITS.md, tracks.md names each song and its
# made-up artist). Graveyard Radio is Dave: talk only, no music, a caption and a
# chime every DAVE_PERIOD seconds. Dave's lines are placeholders in the story
# bible's voice (tired night-shift host, "driver", never a name), Roy edits them.
# The old Drift Phonk / Dark Phonk / Synthwave folders stay on disk, off the dial.

const STATIONS := [
	{"id": "graveyard", "dial": "88.5", "name": "Graveyard Radio", "kind": "talk", "dir": "", "dj": [
		"Dave: Graveyard Radio, coming to you from a back room that smells of coffee and solder. Stay awake, driver.",
		"Dave: Somebody left the garage door open again. If it was you, it still counts as a good night.",
		"Dave: No music on this one. Music costs money, and the crew is spending it on tyres.",
		"Dave: Third shift, fourth coffee. If you can hear this, the leak is still holding.",
		"Dave: Road is wet, the lights are sodium, and nobody is looking. Drive like it.",
		"Dave: This broadcast is not happening. Neither are you. Keep it flat, driver."]},
	{"id": "slipstream", "dial": "91.3", "name": "Slipstream", "kind": "music", "dir": "res://assets/radio/slipstream", "dj": []},
	{"id": "undertow", "dial": "97.7", "name": "Undertow", "kind": "music", "dir": "res://assets/radio/undertow", "dj": []},
	{"id": "afterglow", "dial": "102.5", "name": "Afterglow", "kind": "music", "dir": "res://assets/radio/afterglow", "dj": []},
	{"id": "greyhour", "dial": "106.1", "name": "Grey Hour", "kind": "music", "dir": "res://assets/radio/greyhour", "dj": []},
]

## Station index the ring starts on (Afterglow, the default station), and the
## talk station (Dave's, the one that breaks in with important lines).
const DEFAULT_STATION := 3
const TALK_STATION := 0
## Old saves (before the five-station dial, 2026-10-11) stored an index into
## the eight-station list; every old index maps to Afterglow.
const LEGACY_COUNT := 8

const DAVE_PERIOD := 30.0   # seconds from one Dave line to the next
const BREAK_SECS := 8.0     # how long a line's caption stays up (and the music, if any, ducks)

## Dave's time checks, read out on the hour (NightClock -> RadioManager.announce_hour).
## Placeholders like his other lines: the story is Roy's to write.
const TIME_LINES := {
	21: "Dave: Nine o'clock. The day crowd is home. The road is ours now.",
	22: "Dave: Ten p.m. Coffee number two. Lights on, eyes open.",
	23: "Dave: Eleven. The city's thinning out. Window by window.",
	0: "Dave: Midnight, driver. Officially tomorrow. Nobody tell the boss.",
	1: "Dave: One a.m. Just us and the sodium lamps.",
	2: "Dave: Two o'clock. Even the vending machines are asleep.",
	3: "Dave: Three a.m. The dead hour. Keep it between the lines.",
	4: "Dave: Four. Bakers are up. So are you, apparently.",
	5: "Dave: Five a.m. One hour of dark left. Make it count.",
	6: "Dave: Six. Sun's coming. That's the night, driver. Go home.",
}

static func time_line(hour24: int) -> String:
	return TIME_LINES.get(hour24, "Dave: Top of the hour. Still here, still awake.")

## A station's DJ rotation: its own lines, plus (talk station, band >= 0) the
## hour band's lines from NightBands, so Dave sounds like it's 3 a.m. at 3 a.m.
static func dj_lines(station: int, band := -1) -> Array:
	var lines: Array = STATIONS[station].dj
	if band < 0 or lines.is_empty():
		return lines
	return lines + NightBands.band_lines(band)

static func station_count() -> int:
	return STATIONS.size()

static func has_music(station: int) -> bool:
	return STATIONS[station].kind == "music"

## The .ogg files of a station's folder, sorted. In an exported game the folder
## lists the imported ".ogg.import" / ".ogg.remap" names, so those count too.
static func track_paths(station: int) -> Array[String]:
	var out: Array[String] = []
	var dir: String = STATIONS[station].dir
	if dir == "":
		return out
	for f in DirAccess.get_files_at(dir):
		var name := f.trim_suffix(".import").trim_suffix(".remap")
		if name.ends_with(".ogg") and not out.has(dir + "/" + name):
			out.append(dir + "/" + name)
	out.sort()
	return out

## Talk station: where Dave is at `seconds` on the station clock:
## {"in_break": bool, "line": index into "dj", "into": seconds into the line}.
## Music stations never have a break (empty dj list).
## `band` (NightBands.Band, -1 = none) adds Dave's lines for that part of the
## night to his rotation (dj_lines).
static func break_state(station: int, seconds: float, band := -1) -> Dictionary:
	var lines: Array = dj_lines(station, band)
	if lines.is_empty():
		return {"in_break": false, "line": 0, "into": 0.0}
	var pos := fposmod(seconds, DAVE_PERIOD)
	var n := int(floor(seconds / DAVE_PERIOD))
	return {"in_break": pos < BREAK_SECS, "line": n % lines.size(), "into": pos}

## Where a saved index (and, when the save has one, its station id) lands on the
## dial. A save with an id finds that station; one with only an old index goes
## to Afterglow. -1 stays -1.
static func migrate_saved(index: int, id := "") -> int:
	if id != "":
		for i in STATIONS.size():
			if STATIONS[i].id == id:
				return i
	if index < 0:
		return -1
	return DEFAULT_STATION

static func index_of(id: String) -> int:
	for i in STATIONS.size():
		if STATIONS[i].id == id:
			return i
	return -1

# ---------- song names (tracks.md) ----------

static var _songs_cache := {}   # folder -> {file stem: {"title", "artist"}}

## Title and artist of a track, from its folder's tracks.md (columns File,
## Title, Artist). `file` is the .ogg name or its stem. Never returns a file
## name: a song missing from the table gets its title worked out from the name
## and the station's name as artist.
static func song_info(station: int, file: String) -> Dictionary:
	var dir: String = STATIONS[station].dir
	var stem := file.get_file().trim_suffix(".import").trim_suffix(".remap").trim_suffix(".ogg")
	if dir != "":
		var table := _song_table(dir)
		if table.has(stem):
			return table[stem]
	return {"title": _title_from_stem(stem), "artist": STATIONS[station].name}

static func _song_table(dir: String) -> Dictionary:
	if _songs_cache.has(dir):
		return _songs_cache[dir]
	var out := {}
	var f := FileAccess.open(dir + "/tracks.md", FileAccess.READ)
	if f != null:
		var file_col := -1
		var title_col := -1
		var artist_col := -1
		while not f.eof_reached():
			var line := f.get_line().strip_edges()
			if not line.begins_with("|"):
				continue
			var cells := PackedStringArray()
			for c in line.trim_prefix("|").trim_suffix("|").split("|"):
				cells.append(c.strip_edges())
			if cells.has("File") and cells.has("Title"):
				file_col = cells.find("File")
				title_col = cells.find("Title")
				artist_col = cells.find("Artist")
				continue
			if file_col < 0 or cells.size() <= maxi(file_col, title_col) or not cells[file_col].ends_with(".ogg"):
				continue
			var key := cells[file_col].trim_suffix(".ogg")
			var artist := cells[artist_col] if artist_col >= 0 and artist_col < cells.size() else ""
			out[key] = {"title": cells[title_col], "artist": artist}
	_songs_cache[dir] = out
	return out

## "01_harlow-drive_dusk" or "01_apex_hour" -> "Harlow Drive" / "Apex Hour".
static func _title_from_stem(stem: String) -> String:
	var parts := stem.split("_")
	var words: PackedStringArray = []
	for i in parts.size():
		var p := parts[i]
		if i == 0 and p.is_valid_int():
			continue
		if i == parts.size() - 1 and parts.size() > 2 and p in ["dusk", "late", "dead", "dawn"]:
			continue
		for w in p.split("-"):
			words.append(w.capitalize())
	return " ".join(words)
