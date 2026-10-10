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

Add rows to the table (the header and separator lines stay). Example row, not
part of the table so it is ignored:

    | afterglow_01_harlow-drive_dusk | afterglow | dusk | 2:30 | <the exact prompt text you gave Treblo> | yes |

| id | station | hour band | length target | prompt text | instrumental ON |
|---|---|---|---|---|---|
