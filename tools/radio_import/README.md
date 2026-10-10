# Treblo import

`import_treblo.py` turns WAVs Roy downloads from Treblo into game-ready Ogg files.
Full usage is in the script's docstring (`python tools/radio_import/import_treblo.py -h`).

1. Save the Treblo terms page into `docs/audio-licences-proof/treblo-<date>/` (the script refuses to import while that folder is empty).
2. Add a row per song to `docs/audio/treblo-prompts.md`.
3. Drop `<station>_<NN>_<song-slug>_<band>.wav` into `C:\SmurfyHehe\treblo-inbox\`.
4. Run the script. Rejects stay in the inbox with a reason; keepers go to `done\`.

## Making songs through the official API (`treblo_batch.py`)

Reads `prompts.csv`, asks Treblo's v3 API for an instrumental WAV twice per row and
saves `<file>.wav` and `<file>_b.wav` into the inbox. The game never calls the API.

- Key from the `TREBLO_API_KEY` environment variable only (set it in your own shell).
- 1 call = 100 credits. Hard cap `--credit-cap` (default 15000), counted from `batch-log.txt`.
- `--dry-run` prints the plan and needs no key. `--only afterglow_01` makes one row.
- Restart-safe: finished files are skipped, in-flight task ids live in `batch-state.json`.
- Rejects (silence, clipping, under 2:30, ends mid-note) move to `rejected/`. No voice detector: listen.
- Each WAV gets a `.api.json` next to it; `import_treblo.py` then logs source "Treblo API" and the task id.
- API Terms s6 (attribution) is about apps that call the API. See `docs/audio-licences-proof/treblo-2026-10-10/`.
- `--pairs` picks the plain `<file>.wav`; the `_b` version stays in the inbox for comparison.
- Test: `python tests/audio/test_treblo_batch.py` (fake local API, no key, no network).

## Blind test (before the real import)

`python tools/radio_import/import_treblo.py --pairs` reads the 9-pair table in the script
(a Treblo song vs our song already in `assets/radio`), cuts 45 s from 0:15 for both,
matches both to -16 LUFS and writes `C:\SmurfyHehe	reblo-inboxlind-test\`:
`pair_NN_A.wav` / `pair_NN_B.wav` (Treblo is randomly A or B), `solo_10..12.wav`
(Grey Hour songs 01-03, no pair) and `key.txt` with the answers. Pairs whose Treblo
WAV is not in the inbox yet are skipped and listed. Re-running keeps earlier A/B
answers. It only reads the game's files and never writes into the repo.

Tempo targets per station live in `stations.json` (set by Roy 2026-10-10).
Test: `python tests/audio/test_import_treblo.py` (needs ffmpeg, no Godot).
