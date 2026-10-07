# Fleet design sheet (stage B, step 1)

These are the designs of all 12 cars, as audited in Godot on 2026-10-05.
The game models are these proxies, exported by `tools/fleet_design/game_export.py`:
the P1 coupe (`scripts/p1_coupe_builder.gd`) and the traffic cars, every
variant (`scripts/npc_car_builder.gd`, stage B step 5). The other player cars
come in stage D and the police cars in stage F.

| File | What it is |
|---|---|
| `fleet_overview.png` | All 12 cars, plus the side outlines at true scale |
| `sheets/<car>.png` | One sheet per car, laid out as below |
| `outline_check.png` | Outlines only, in 6 views, with the blind-test results |
| `fleet.json` | Every number the builds need |
| `verify.json` | The blind-test results (B1's 3 rounds and the audit round) |
| `proxies.json` | The proxy meshes packed for Godot (`tools/fleet_design/godot_export.py`) |
| `audit/` | What the Godot checks wrote, plus `audit_sheet.png` (before/after) |

Each car sheet shows:
- the side, front, rear (night) and top views;
- the chase-cam or traffic-ahead view, and both 3/4 views;
- outlines only;
- builds or variants, sticker slots, parts, colours, budget, exhaust tips and the self-critique.

The renders come from `tools/fleet_design/` (Python, no GPU). Each car is one
lofted 3D proxy, so its views can't disagree with each other. To regenerate,
run `python sheets.py`, `python export.py` and `python godot_export.py` in that
folder. The proxies are design references, not the game models.

## Silhouette language per class

- **Player:** low and wide, with the wheels filling the arches. Each car has
  one hero shape cue.
- **Traffic:** taller and softer, with small wheels in big arch gaps and plain
  paint. They recede, so the player's car always pops.
- **Police:** big, slab-sided and upright. Every one carries a police tell in
  its outline: a light bar, a push bar, an A-pillar spotlight or antennas.
  Livery is navy `#1B2A4A` with silver `#C9CED6` doors and roof.

## The 12 cars

Sizes are in metres. H is the overall height, including roof gear.

| Car | L × W × H | Wheelbase | Silhouette rule (short) |
|---|---|---|---|
| P1 Sports coupe | 4.42 × 1.80 × 1.24 | 2.52 | long hood, cabin pushed back, fastback, hoop wing, pop-ups |
| P2 Hot hatch | 4.05 × 1.83 × 1.40 | 2.56 | short brick, narrow upright cabin on box-blistered hips, upright hatch under an overhanging spoiler |
| P3 Tuner sedan | 4.48 × 1.78 × 1.36 | 2.62 | square four-door, boxed overfenders, pedestal wing, 4 round tail lamps |
| P4 Kei roadster | 3.30 × 1.40 × 1.13 | 2.27 | tiny, open, twin headrest humps |
| P5 Muscle sedan | 5.35 × 2.02 × 1.30 | 2.95 | land yacht, tall cowl scoop, chopped cabin, hourglass hips, ducktail, full-width tail bar |
| P6 Perf. crossover | 4.35 × 1.84 × 1.61 | 2.62 | lifted rally hatch, black-clad box flares, roof rack with crossbars past the roof edge |
| N1 Commuter sedan | 4.80 × 1.82 × 1.51 | 2.80 | soft tall cabin, tall nose, short high deck |
| N2 City hatchback | 3.95 × 1.69 × 1.53 | 2.53 | tall cab-forward egg, lamps up the pillars |
| N3 Pickup | 5.30 × 1.86 × 1.86 | 3.08 | double cab plus open bed |
| C1 Patrol sedan | 5.30 × 1.96 × 1.60 | 2.92 | square-backed sedan, light bar, push bar, spotlight |
| C2 Patrol SUV | 5.10 × 2.00 × 2.09 | 3.03 | tall box, light bar, push bar, three side windows |
| C3 Unmarked interceptor | 4.82 × 1.92 × 1.38 | 2.72 | long-hood fastback, spotlight, trunk antennas, no light bar |

N3 is built as a pickup, not an SUV, so traffic can never be mistaken for the
patrol SUV.

## Parts, stickers, exhaust

- **Swappable parts:** front and rear bumpers, hood, skirts or wide-body,
  spoiler, wheels, exhaust tips and ride height, plus one signature slot per
  car:
  - P1: pop-ups or a fixed-lamp nose;
  - P4: open, hardtop or roll bar;
  - P6: roof rack, rally lamp pod or street (crossbars off, low rails kept).

  Every option changes the visible shape, the wheels or the paint. Physics
  effects belong to the stage E mod trees. Traffic and police cars get 2–3
  variants for variety, for example a taxi sign, a bed cover, or a push bar off.
- **Sticker slots:** exactly 4 per car (Roy's step 1 sign-off, 2026-10-05):
  - the door, mirrored on both sides;
  - the hood, seen from above;
  - the windshield sun strip, a banner across the top of the glass between the
    A-pillars, seen from above;
  - the tail panel or tailgate, upright, so the chase cam and low rear views
    both see it (moved there in the audit from rear windows and trunk lids;
    the hot hatch's old one sat under its spoiler).

  Checked in Godot (`tests/fleet_design_check.gd`): every slot lies on the body
  in every build, nothing hovers over it, the chase cam sees the rear one, and
  every orbit camera sees at least one, all 96 of them (the sun strip is what
  covers the 3 ground-level views of the nose that the hood slot missed). Each slot's 3D centre,
  normal and size is in `fleet.json`, ready for a decal projector. On police
  cars the slots hold the livery; on the unmarked car they are empty.
- **Exhaust tips:** position, direction and radius for every exhaust option
  are in `fleet.json` (`exhaust_tips`). Step 2 attaches the flames there. Tips
  belong to the body node, so they drop with the ride-height mods. Godot
  checks that every build and option has tips, behind the rear axle, with
  0.6 m clear in front of each for the flames.

## Colour

- **Palette:** Amber vs. Dusk, as listed in ROADMAP.md.
- **Hero paints:**
  - P1 Sodium `#FF8A1F`
  - P2 Rally red `#C41E24`
  - P3 Pearl white `#E9E6DF` with bronze wheels
  - P4 Signal yellow `#F2B53A`
  - P5 Cherry `#6A1620`
  - P6 Sand `#B8A27A`

  Each car also has four alternates.
- **Traffic:** 9 weighted neutrals, listed in `fleet.json`.
- **Palette check:** `palette_check.py` checked 76 colours, and the Godot
  check 97 (every material, paint, livery and palette entry), with no magenta
  or cyan.
- **Police blue `#2E4FD8` is the one off-palette colour.** Its hue is 228°,
  which is blue, not cyan. Roy kept the red and blue light bars (2026-10-05).

## Budget plan

- **Proxy size:** 2.2k–3.0k triangles per car without the light and grille
  decals, 2.4k–3.3k with them (what Godot draws), against targets of 10k
  (player), 6k (police) and 4k (traffic).
- **Measured in Godot** (`tests/fleet_budget_scene.gd`, the stage A scene from
  the chase cam): 30 traffic cars as separate meshes add 150 draw calls
  (176 → 326, 5 per car); drawn as one MultiMesh per design they add 6.
  At full budget (30 traffic, 3 police, the player) a frame has about 157k
  triangles, which Iris Xe handles easily. Draw calls and physics are the
  real limits, not triangles. Frame time on the laptop is measured with
  traffic in step 3.
- **Fewer parts:** the game model should be one merged mesh with 3 surfaces:
  - opaque body, vertex-coloured, with paint as a tint parameter;
  - dark glass;
  - emissive lights.

  Add one wheel mesh drawn 4 times. That is about 5–7 draw calls per car, and
  swapped parts are merged into the body mesh when the build changes.
  (2026-10-07: the traffic cars add a 4th body surface, the additive tail
  flares that keep a car visible at night, so NpcCarBuilder cars are 8.)

## Verification

- **Audit (2026-10-05), in Godot 4.7.2:**
  - `tests/fleet_silhouette_sweep.gd` renders each car's outline from 96 orbit
    cameras (every 15°, at 2°, 15°, 35° and 60° up) plus the chase view, and
    flags "outline twins": two cars whose outlines nowhere differ by more than
    1% of their size. B1 had 9 such view-pairs; 2 remain, each at one high
    angle (coupe/tuner, hot hatch/crossover), listed in the test for Roy.
  - A fresh blind tester matched outlines from 9 cameras, 3 of them high
    angles B1 never tested: 106 of 109 right. Every miss was the high rear
    view, where the three sedans (tuner, commuter, muscle) blur. The tester
    told both remaining twin pairs apart.
- **B1 blind test:** three rounds, each run by a fresh agent that had never seen
  the designs. It matched shuffled, unlabeled black silhouettes in 6 views to
  the 12 class names.
  - Correct: 72/72 every round.
  - "Sure": 33 → 36 → 39 of 72 as the designs were revised.
  - Final design: side 12/12; 3/4 views 8/12 each; front and traffic-ahead
    5/12; top 1/12.
- **Top view:** from above, every car is a rounded rectangle. Identity there
  comes from the roof graphic, not the outline.
