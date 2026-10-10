# People A1: one mesh, 21 bodies (2026-10-09)

`scripts/world/person_body.gd` (PersonBody). Male only, 532 triangles, 17 bones, one material.

- **Bodies:** 7 heights (1.55 to 1.95 m) x 3 builds (slim, average, heavy) from one mesh by bone scaling. Height scales bone lengths, build scales girth and shoulder width; the head grows as sqrt(height), so 1.55 m reads 6.9 heads and 1.95 m reads 7.8.
- **Faces:** 8 painted faces in a 128x64 atlas (plain, heavy brows, moustache, stubble, beard, glasses, tired, goatee and scar), multiplied by the skin colour. No helmets.
- **Arms:** in the seat by two-bone IK (`sit_pose`, `reach`), outside with `smoke` and `hands_on_hips`.
- **CPU:** people are baked to static meshes (`bake`, about 8 ms each, cached), so a bystander costs nothing per frame. `make_rig` gives a live Skeleton3D rig for the few that must move (30 rigs: about 0.2 ms per frame on the laptop).

- **Data:** the kit numbers, the house style (every colour and face a person may have) and the cast live in `assets/people/people.json`. `tools/people_pipeline/check_people.gd` checks it; see `tools/people_pipeline/README.md`.

Shots: `tools/people_pipeline/people_shots.gd` (needs the real renderer); `cast.jpg` is the people.json cast. Test: `tests/world/person_body.gd`.

Not in A1: wiring into DriverModel (the cockpit driver) or placing people in the world.
