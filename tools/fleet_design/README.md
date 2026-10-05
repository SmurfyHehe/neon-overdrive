# fleet_design: stage B1 design generator

Builds each car's design proxy from its numbers in `cars.py` and `options.py`,
then renders the sheets in `docs/design/fleet/`. It runs on Python 3 with
numpy, scipy and Pillow, and needs no GPU or Godot.

    python sheets.py          # 12 car sheets
    python export.py          # fleet.json
    python palette_check.py   # no magenta or cyan
    python -c "import sheets, json; sheets.overview(); sheets.outline_check(json.load(open('../../docs/design/fleet/verify.json')))"

The game cars are not built from these meshes. Stage B2/D model them in
Godot from the same numbers in `fleet.json`.
