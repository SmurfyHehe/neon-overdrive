# Side-street mouths and eyes in the headlights (world step 6, 2026-10-10)

Roy said yes to both (project chat, 2026-10-10). Built on PR #369's branch
(pavements steps 2-6, `claude/project-thread-200x7e`, stacked on #352), because
the mouths drop the kerb through the cross-section table's rows.

Contact sheet: `side_streets_2026-10-10.png` (tools/side_street_shots.gd). Rows:
downtown, residential, industrial, strip; columns: the driver's view 70 m
before the mouth, the mouth from the lane beside it, down the street from its
pavement. Last row: an animal's eyes from the road and up close, lit by a
headlight-like spot.

## W7: side-street mouths

- **What**: some gaps between buildings open onto 30-60 m of two-lane road
  with kerbs and pavements, one street lamp with its light pool, a parked car
  and a stop sign (its back to the driver), fading to black at the far end.
  Look only: the invisible boundary wall still runs along the chunk.
- **Where**: 1-3 per district run (16 chunks, 800 m), hashed from the run
  index like everything else in the district map, so a recycled chunk matches
  a fresh one and the road's random sequence is untouched. Never on a
  crossing's chunks or a freeway stretch. A mouth takes one building slot:
  the slot's building is cleared the way a crossing's corner lot is
  (`_clear_for_mouth`, after the draws are taken), the gap walls leave a
  9.6 m opening, the kerb drops across it (`Districts.CROSS` rows through
  `_kerb_heights`), hydrants and drains keep clear of it.
- **Cost**: two MultiMeshes per chunk, drawn only on a chunk with a mouth
  (the kit, and the props with the parked car and the sign in one mesh,
  RoofProps' shape-collapse trick), plus one instance each in the chunk's
  own lamp and pool buffers. 22 + 116 triangles per mouth. CPU per frame 0.
- **Floating support**: the kit's plane is placed with `_xf` (the road's
  pitch carried sideways), the kerb blocks reach FOUNDATION below, and the
  lamp, car and sign stand with `_xf_up` at the station of their own z, so
  on a hill each is on the surface. `tests/world/side_streets.gd` checks
  this on a 4.9 % grade with curves.
- **Sight lines**: everything stands behind the pavement's outer edge
  (behind the setback in the strip and industrial districts); the sign is
  2.2 m tall and 2 m into the street. Nothing is added in front of the
  building line.

## A1: eyes in the headlights

- **What**: a cat (85 %) or dog (135 %) sized dark shape at a side-street
  corner (60 % of mouths) or tucked against a shop, diner or garage front
  (30 % of those). Two eye quads emit amber (`#FFC066` family) scaled by the
  instance's custom data; the body is near black.
- **Beam**: the player's "Headlights" SpotLight3D's aim and `spot_angle`, so
  the lights PR (#361: low beam 32 deg, high beam 20 deg) narrows and widens
  the shine without this code knowing. Lights off (the spot hidden, as
  PlayerCar does) means no shine. Full shine inside the inner half of the
  cone, off at its edge; 3-75 m, fading from 50 m.
- **Behaviour**: after 0.35 s above 60 % shine it bolts (cat 2.4 m/s, dog
  3.2 m/s) along the wall or into the side street for 2 s, then it is gone
  (scaled to nothing) until the chunk is recycled.
- **Cost**: one MultiMesh per chunk with an animal (at most 3). Per frame,
  `StreetAnimals.step` from `game.gd._process`: a distance check per chunk in
  the pool, then one dot product per animal on chunks within 170 m; a
  transform write only while one is fleeing.

## Switches

`NEON_SIDE_STREETS=0` and `NEON_ANIMALS=0` turn each off (before/after runs).

## Measurements (2026-10-10, on PR #369's branch)

See the PR description: the laptop was at 100 % CPU from four orphaned
`find /` scans (CLAUDE.md, "never scan the whole disk") that I was not allowed
to stop, so every number is noisy and marked as such.

## Assumptions

- The street's section (3 m lanes, 0.3 m kerb, 1.5 m pavement, 0.12 m kerb
  height), 30-60 m, 1-3 per run, the car on the left kerb at 30-65 % of the
  length, the lamp at 55 %: mine, not from a sheet.
- Downtown gets mouths too (its `gap` is 0, so the mouth is its only opening).
- The sign faces the side street's traffic, so the driver sees its grey back.
- Animals never cross the road or step onto the main road.
