# Treblo prompt sheet

One row per song. `tools/radio_import/import_treblo.py` only imports a WAV whose
file name (without `.wav`) is an `id` in the table below, and whose station and
hour band match the row.

**File name:** `<station>_<NN>_<song-slug>_<band>.wav`, for example
`afterglow_01_harlow-drive_dusk.wav`. The song slug uses lowercase letters,
digits and hyphens. Drop the file in `C:\SmurfyHehe\treblo-inbox\`.

- **Stations:** `slipstream`, `undertow`, `afterglow`, `greyhour`
- **Hour bands:** `dusk`, `late`, `dead`, `dawn`
- **Length target:** 2:00 or longer (the importer rejects anything shorter)
- **Instrumental ON:** keep Treblo's instrumental switch on for every song

**Prompt column is empty on purpose.** The 40 ids, stations and hour bands below
come from the music day plan (2026-10-10). The prompt text lives in that plan and
in Roy's saved `.txt` files, which the session that wrote this table could not
read. The session that does the real import (Stage B) fills the prompt column
from Roy's `.txt` files or from the plan pasted to it. The importer warns about a
row with an empty prompt but does not block on it.

Add rows to the table (the header and separator lines stay). Example row, not
part of the table so it is ignored:

    | afterglow_01_harlow-drive_dusk | afterglow | dusk | 2:30 | <the exact prompt text you gave Treblo> | yes |

| id | station | hour band | length target | prompt text | instrumental ON |
|---|---|---|---|---|---|
| afterglow_01_harlow-drive_dusk | afterglow | dusk | 3:00 |  | yes |
| afterglow_02_night-overpass_late | afterglow | late | 3:00 |  | yes |
| afterglow_03_midnight-garage_dead | afterglow | dead | 3:00 |  | yes |
| afterglow_04_orange-skyline_late | afterglow | late | 3:00 |  | yes |
| afterglow_05_orange-lamps_dusk | afterglow | dusk | 3:00 |  | yes |
| afterglow_06_canyon-lights_late | afterglow | late | 3:00 |  | yes |
| afterglow_07_last-exit_late | afterglow | late | 3:00 |  | yes |
| afterglow_08_dusk-pursuit_late | afterglow | late | 3:00 |  | yes |
| afterglow_09_empty-car-park_dead | afterglow | dead | 3:00 |  | yes |
| afterglow_10_first-light_dawn | afterglow | dawn | 3:00 |  | yes |
| undertow_01_cold-asphalt_dead | undertow | dead | 3:00 |  | yes |
| undertow_02_dead-lights_dead | undertow | dead | 3:00 |  | yes |
| undertow_03_hollow-street_dead | undertow | dead | 3:00 |  | yes |
| undertow_04_black-water_late | undertow | late | 3:00 |  | yes |
| undertow_05_low-tide_dusk | undertow | dusk | 3:00 |  | yes |
| undertow_06_rust-belt_late | undertow | late | 3:00 |  | yes |
| undertow_07_undercurrent_dead | undertow | dead | 3:00 |  | yes |
| undertow_08_pursuit_late | undertow | late | 3:00 |  | yes |
| undertow_09_fog-bank_dawn | undertow | dawn | 3:00 |  | yes |
| undertow_10_grave-light_dawn | undertow | dawn | 3:00 |  | yes |
| slipstream_01_late-shift_late | slipstream | late | 3:00 |  | yes |
| slipstream_02_hairpin-heat_late | slipstream | late | 3:00 |  | yes |
| slipstream_03_last-lap_dawn | slipstream | dawn | 3:00 |  | yes |
| slipstream_04_midnight-laps_late | slipstream | late | 3:00 |  | yes |
| slipstream_05_open-tarmac_dusk | slipstream | dusk | 3:00 |  | yes |
| slipstream_06_rear-wheels_dusk | slipstream | dusk | 3:00 |  | yes |
| slipstream_07_smoke-signal_late | slipstream | late | 3:00 |  | yes |
| slipstream_08_cold-apex_dead | slipstream | dead | 3:00 |  | yes |
| slipstream_09_sideways_dead | slipstream | dead | 3:00 |  | yes |
| slipstream_10_overpass-echo_dawn | slipstream | dawn | 3:00 |  | yes |
| greyhour_01_wet-road_late | greyhour | late | 3:00 |  | yes |
| greyhour_02_fog-light_dead | greyhour | dead | 3:00 |  | yes |
| greyhour_03_home-before-light_dawn | greyhour | dawn | 3:00 |  | yes |
| greyhour_04_wipers_late | greyhour | late | 3:00 |  | yes |
| greyhour_05_slow-lane_dead | greyhour | dead | 3:00 |  | yes |
| greyhour_06_streetlamp_dead | greyhour | dead | 3:00 |  | yes |
| greyhour_07_salt-on-the-bridge_dawn | greyhour | dawn | 3:00 |  | yes |
| greyhour_08_cold-coffee_dawn | greyhour | dawn | 3:00 |  | yes |
| greyhour_09_tail-lights_dusk | greyhour | dusk | 3:00 |  | yes |
| greyhour_10_night-bus_dusk | greyhour | dusk | 3:00 |  | yes |
