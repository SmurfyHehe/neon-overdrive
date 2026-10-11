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
	"res://assets/radio/s1_drift/01_apex_hour.ogg": 71.6,
	"res://assets/radio/s1_drift/02_tire_smoke.ogg": 59.7,
	"res://assets/radio/s1_drift/03_late_shift.ogg": 58.7,
	"res://assets/radio/s1_drift/04_sodium_haze.ogg": 67.9,
	"res://assets/radio/s1_drift/05_hairpin.ogg": 60.5,
	"res://assets/radio/s1_drift/06_overpass.ogg": 59.5,
	"res://assets/radio/s1_drift/07_last_lap.ogg": 68.8,
	"res://assets/radio/s2_dark/01_graveyard_shift.ogg": 77.4,
	"res://assets/radio/s2_dark/02_cold_asphalt.ogg": 68.3,
	"res://assets/radio/s2_dark/03_lowlight.ogg": 60.9,
	"res://assets/radio/s2_dark/04_undertow.ogg": 78.5,
	"res://assets/radio/s2_dark/05_black_ice.ogg": 65.4,
	"res://assets/radio/s2_dark/06_dead_lights.ogg": 65.5,
	"res://assets/radio/s2_dark/07_hollow_street.ogg": 74.1,
	"res://assets/radio/s4_synthwave/01_harlow_drive.ogg": 79.1,
	"res://assets/radio/s4_synthwave/02_night_overpass.ogg": 95.9,
	"res://assets/radio/s4_synthwave/03_sodium_skyline.ogg": 72.1,
	"res://assets/radio/s4_synthwave/04_last_exit.ogg": 85.1,
	"res://assets/radio/s4_synthwave/05_dusk_pursuit.ogg": 86.3,
	"res://assets/radio/s4_synthwave/06_canyon_lights.ogg": 76.0,
	"res://assets/radio/s4_synthwave/07_midnight_garage.ogg": 77.7,
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
