extends RefCounted
class_name RadioStations

# The radio's station list (file radio, 2026-10-06). Stations 1, 2 and 4 play the
# Ogg Vorbis tracks in their folder under assets/radio/ (original, synthesized,
# see assets/radio/CREDITS.md). Station 3 is Dave on The Dave Show: talk only, no
# music, a caption and a chime every DAVE_PERIOD seconds (the DJ-break system the
# generated stations used). Dave's lines are placeholders in the story bible's
# voice (tired night-shift host, "driver", never a name), Roy edits them.

const STATIONS := [
	{"name": "Drift Phonk", "kind": "music", "dir": "res://assets/radio/s1_drift", "dj": []},
	{"name": "Dark Phonk", "kind": "music", "dir": "res://assets/radio/s2_dark", "dj": []},
	{"name": "The Dave Show", "kind": "talk", "dir": "", "dj": [
		"Dave: The Dave Show, coming to you from a back room that smells of coffee and solder. Stay awake, driver.",
		"Dave: Somebody left the garage door open again. If it was you, it still counts as a good night.",
		"Dave: No music on this one. Music costs money, and the crew is spending it on tyres.",
		"Dave: Third shift, fourth coffee. If you can hear this, the leak is still holding.",
		"Dave: Road is wet, the lights are sodium, and nobody is looking. Drive like it.",
		"Dave: This broadcast is not happening. Neither are you. Keep it flat, driver."]},
	{"name": "Synthwave", "kind": "music", "dir": "res://assets/radio/s4_synthwave", "dj": []},
]

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
