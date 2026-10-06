extends RefCounted
class_name RadioStations

# The radio's station list (file radio, 2026-10-06). Stations 1, 2 and 4 play the
# Ogg Vorbis tracks in their folder under assets/radio/ (original, synthesized,
# see assets/radio/CREDITS.md). Station 3 is Dale on Graveyard TV: talk only, no
# music, a caption and a chime every DALE_PERIOD seconds (the DJ-break system the
# generated stations used). Dale's lines are placeholders in the story bible's
# voice (tired night-shift host, "driver", never a name), Roy edits them.

const STATIONS := [
	{"name": "Drift Phonk", "kind": "music", "dir": "res://assets/radio/s1_drift", "dj": []},
	{"name": "Dark Phonk", "kind": "music", "dir": "res://assets/radio/s2_dark", "dj": []},
	{"name": "Graveyard TV", "kind": "talk", "dir": "", "dj": [
		"Dale: Graveyard TV, coming to you from a back room that smells of coffee and solder. Stay awake, driver.",
		"Dale: Somebody left the garage door open again. If it was you, it still counts as a good night.",
		"Dale: No music on this one. Music costs money, and the crew is spending it on tyres.",
		"Dale: Third shift, fourth coffee. If you can hear this, the leak is still holding.",
		"Dale: Road is wet, the lights are sodium, and nobody is looking. Drive like it.",
		"Dale: This broadcast is not happening. Neither are you. Keep it flat, driver."]},
	{"name": "Synthwave", "kind": "music", "dir": "res://assets/radio/s4_synthwave", "dj": []},
]

const DALE_PERIOD := 30.0   # seconds from one Dale line to the next
const BREAK_SECS := 8.0     # how long a line's caption stays up (and the music, if any, ducks)

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

## Talk station: where Dale is at `seconds` on the station clock:
## {"in_break": bool, "line": index into "dj", "into": seconds into the line}.
## Music stations never have a break (empty dj list).
static func break_state(station: int, seconds: float) -> Dictionary:
	var lines: Array = STATIONS[station].dj
	if lines.is_empty():
		return {"in_break": false, "line": 0, "into": 0.0}
	var pos := fposmod(seconds, DALE_PERIOD)
	var n := int(floor(seconds / DALE_PERIOD))
	return {"in_break": pos < BREAK_SECS, "line": n % lines.size(), "into": pos}
