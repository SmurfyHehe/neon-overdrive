# Treblo import

`import_treblo.py` turns WAVs Roy downloads from Treblo into game-ready Ogg files.
Full usage is in the script's docstring (`python tools/radio_import/import_treblo.py -h`).

1. Save the Treblo terms page into `docs/audio-licences-proof/treblo-<date>/` (the script refuses to import while that folder is empty).
2. Add a row per song to `docs/audio/treblo-prompts.md`.
3. Drop `<station>_<NN>_<song-slug>_<band>.wav` into `C:\SmurfyHehe\treblo-inbox\`.
4. Run the script. Rejects stay in the inbox with a reason; keepers go to `done\`.

Tempo targets per station live in `stations.json` (placeholder values, edit them).
Test: `python tests/audio/test_import_treblo.py` (needs ffmpeg, no Godot).
