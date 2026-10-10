# people_pipeline: every person from one body kit and one data file

People step A1. Male only, no helmets, CPU first. Nothing is downloaded: the
mesh, the faces and the colours are all generated (asset rule: free for a sold
game, no credit), so there is no CREDITS.md row.

    godot --headless --path . -s res://tools/people_pipeline/check_people.gd   # checks people.json, lists the cast
    godot --path . -s res://tools/people_pipeline/people_shots.gd              # -> docs/design/people/a1/*.jpg (needs the real renderer)
    godot --headless --path . -s res://tests/world/person_body.gd

## The three parts

| Part | Where | What it is |
|---|---|---|
| Data | `assets/people/people.json` | the kit numbers, the house style and the cast |
| Body kit | `scripts/world/person_body.gd` (PersonBody) | the one mesh (532 triangles, 17 bones), bone scaling, poses, bake |
| Tools | this folder | the checker and the shots |

## people.json

- **kit**: the reference man (1.78 m), the 7 heights (1.55 to 1.95 m) and the
  3 builds (slim, average, heavy) as girth numbers. Height scales bone lengths,
  build scales girth and shoulder width. 7 x 3 = 21 bodies from the one mesh.
- **style**: the house style. Every colour a person may wear (skin, hair, tops,
  bottoms, shoes: Amber vs. Dusk plus plain street clothes), the 8 painted face
  names in atlas order, and the pose names. Random bystanders
  (`PersonBody.outfit(seed)`) and the cast both pick only from these lists.
- **people**: the cast. One row per named person: height, build, face, colours,
  sleeves (short or long), pose. Names and looks are placeholders.

To add a person, add a row and run `check_people.gd`. A row with a height or a
build the kit does not have, or a colour outside the style, is refused: the
checker says which, and the game draws nothing for that id.

## In the game

    var mesh := PersonBody.bake_person("dale")     # static mesh, cached, one draw call

People are baked to static meshes (about 10 ms once, then cached), so a person
standing around costs nothing per frame. `PersonBody.make_rig` gives a live
skeleton for the few who must move.

`export_presets.cfg` includes `assets/people/*.json` so the file ships with
the exported game.

## Not in A1

Putting people in the cockpit (DriverModel) or in the world.
