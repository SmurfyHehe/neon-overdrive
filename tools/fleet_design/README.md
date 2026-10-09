# fleet_design: stage B1 design generator

Builds each car's design proxy from its numbers in `cars.py` and `options.py`,
then renders the sheets in `docs/design/fleet/`. It runs on Python 3 with
numpy, scipy and Pillow, and needs no GPU or Godot.

    python sheets.py          # 12 car sheets
    python export.py          # fleet.json
    python godot_export.py    # proxies.json, for the Godot checks in tests/fleet_*.gd
    python audit_sheet.py render <dir>   # renders for the audit before/after sheet
    python palette_check.py   # no magenta or cyan
    python -c "import sheets, json; sheets.overview(); sheets.outline_check(json.load(open('../../docs/design/fleet/verify.json')))"

The game cars are these meshes: `python game_export.py` packs the P1 coupe and
`python game_export.py <id>` a traffic car (every build) into `scripts/`.
