class_name RadioLengths
extends RefCounted

# Song lengths in seconds, so RadioManager can build a station's playlist without
# loading every song to ask (R0, 2026-10-10). The table between the markers is
# written by tools/radio_lengths.gd; run it after adding or re-rendering a song.
# A song missing from the table still works (the radio measures it in the
# background); a wrong entry shifts that station's clock, so tests/audio/radio.gd
# checks the table against the real files.

const TOLERANCE := 0.05   # s

## What differs between `found` (path -> length, from the real files) and LENGTHS.
static func stale_entries(found: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for path in found:
		if not LENGTHS.has(path):
			out.append("missing: %s" % path)
		elif absf(float(LENGTHS[path]) - float(found[path])) > TOLERANCE:
			out.append("wrong length: %s (table %.3f, file %.3f)" % [path, LENGTHS[path], found[path]])
	for path in LENGTHS:
		if not found.has(path):
			out.append("no such song: %s" % path)
	return out

# BEGIN TABLE
const LENGTHS := {
	"res://assets/radio/afterglow/01_harlow-drive_dusk.ogg": 202.736,
	"res://assets/radio/afterglow/02_night-overpass_late.ogg": 168.847,
	"res://assets/radio/afterglow/04_orange-skyline_late.ogg": 179.204,
	"res://assets/radio/afterglow/05_orange-lamps_dusk.ogg": 168.366,
	"res://assets/radio/afterglow/06_canyon-lights_late.ogg": 152.675,
	"res://assets/radio/afterglow/09_empty-car-park_dead.ogg": 166.605,
	"res://assets/radio/afterglow/10_first-light_dawn.ogg": 217.432,
	"res://assets/radio/greyhour/01_wet-road_late.ogg": 197.995,
	"res://assets/radio/greyhour/03_home-before-light_dawn.ogg": 202.5,
	"res://assets/radio/greyhour/04_wipers_late.ogg": 126.6,
	"res://assets/radio/greyhour/05_slow-lane_dead.ogg": 175.7,
	"res://assets/radio/greyhour/07_salt-on-the-bridge_dawn.ogg": 163.135,
	"res://assets/radio/slipstream/02_hairpin-heat_late.ogg": 146.08,
	"res://assets/radio/slipstream/03_last-lap_dawn.ogg": 157.905,
	"res://assets/radio/slipstream/04_midnight-laps_late.ogg": 165.313,
	"res://assets/radio/slipstream/05_open-tarmac_dusk.ogg": 165.031,
	"res://assets/radio/slipstream/08_cold-apex_dead.ogg": 143.607,
	"res://assets/radio/undertow/01_cold-asphalt_dead.ogg": 135.7,
	"res://assets/radio/undertow/02_dead-lights_dead.ogg": 156.458,
	"res://assets/radio/undertow/04_black-water_late.ogg": 209.281,
	"res://assets/radio/undertow/05_low-tide_dusk.ogg": 141.2,
	"res://assets/radio/undertow/07_undercurrent_dead.ogg": 130.907,
	"res://assets/radio/undertow/09_fog-bank_dawn.ogg": 134.658,
}
# END TABLE
