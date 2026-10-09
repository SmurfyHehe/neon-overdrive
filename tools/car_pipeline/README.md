# car_pipeline: authored car meshes from the fleet numbers

The car modelling pipeline decided in
`docs/planning/car-look-showcase-2026-10-09.md` (section 12, Roy 123) and
extended by `docs/planning/car-parts-plan-2026-10-09.md` (section 6: panels
that open, anchors for the real parts). This folder is **step 1**: one car's
body as a real mesh with the panels that open as separate pieces, material
slots and named empties, exported as glTF for Godot.

    python tools/car_pipeline/build_car.py p1_coupe        # -> assets/cars/p1_coupe/body.glb + body.json
    python tools/car_pipeline/panel_sheet.py p1_coupe      # -> docs/design/pipeline/p1_coupe_panels.png
    godot --headless --path . -s res://tests/car_pipeline_p1.gd

Python 3 with numpy, scipy and Pillow (the same as `tools/fleet_design/`).
No GPU, no Godot needed to build; Godot only to check.

## Where the shape comes from

The same definitions the design sheets and the B1 audit use:
`tools/fleet_design/cars.py` and `options.py`, which `export.py` writes out as
`docs/design/fleet/fleet.json`. The car id is looked up in `fleet.json` so the
sheet, the audit proxies and this model are always the same shape; change the
car's numbers and all three move together. Nothing is downloaded: every
triangle is generated from those numbers (asset rule: all assets free for a
sold game, no credit).

## What is in body.glb

Godot axes (X right, Y up, -Z forward), origin on the ground midway between
the axles, metres. Names are what Godot and the later steps key on.

| Node | What |
|---|---|
| `body` | the paint shell: everything that never moves |
| `hinge_hood` > `hood` | hood on its hinge line (rear edge, at the cowl); turn the empty on its `axis` by `open_sign * open_deg` and the hood rises |
| `hinge_door_l/r` > `door_l/r` | doors with their glass on the A-pillar hinge line, vertical axis, swing outward |
| `hinge_trunk` > `trunk` | the deck lid on its front edge |
| `mirrors`, `spoiler`, `popups`, `exhaust` | the car's own parts, one mesh each (named by the part's tag) |
| `wheel_fl/fr/rl/rr` > `wheel_*_mesh` | empties on the hubs, the sheet's rim and tyre under each with the hub at its origin |
| `slot_door_l/r`, `slot_hood`, `slot_sun`, `slot_rear` | the 4 sticker slots (5 placements), +Z is the outward normal, `size` in extras |
| `tip_0..n` | exhaust tips, +Z the exhaust direction, `r` in extras |
| `mount_front_bumper`, `mount_rear_bumper`, `mount_skirt_l/r`, `mount_wing`, `mount_hood`, `lamp_l/r` | where body-shop parts attach (step 4) |
| `hub_*`, `shock_top_*`, `strut_top_fl/fr`, `bay_engine`, `bay_turbo`, `bay_radiator`, `bay_intercooler`, `exhaust_route_0..3`, `diff`, `tank` | anchors for the real parts (car-parts plan, section 6) |
| `cam_front_quarter`, `cam_rear_quarter`, `cam_side`, `cam_top`, `cam_under`, `cam_wheel` | six camera presets, -Z looking at the car |

`body.json` beside it lists every node, the triangles per mesh, the hinges
(position, axis, open sign and angle), the slots, tips, hubs, dims, the
material colours and the backend that wrote the file. `tests/car_pipeline_p1.gd`
reads both and checks they agree.

Materials: one glTF material per fleet material name (`paint`, `roof`,
`glass`, `trim`, `under`, `chrome`, `rim`, `tire`, `head`, `tail`, ...),
colours from the car's paint set and `render.BASE_MATS`. Step 3 (the one car
shader) replaces them by name.

## How the panels are cut

The loft is one closed surface, so the hood, doors and trunk are cut out of
it with planes (triangles on the cut are split, not dropped), which makes
the shut lines real edges. Regions are in `panel_regions()` and can be
overridden per car with a `panels` dict in its definition:

- hood: up-facing faces from `hood_s0` (0.55 m from the nose) to the A-pillar
  base, within `hood_hw` (0.70 m) of the centreline;
- doors: side faces from the A-pillar base plus 4 cm to the B-pillar, above
  the rocker, including the door glass;
- trunk: up-facing faces from the rear glass line plus 3 cm to 15 cm before
  the tail, within 0.66 m of the centreline.

P1 stock: 3056 triangles in 13 meshes (body 2095, hood 154, trunk 57, doors
27 + 27, mirrors 48, spoiler 88, pop-ups 28, exhaust 60, wheels 4 x 118),
budget 10 000. The sheet proxy was 2760; the panel cuts add the split
triangles.

## Backends

| Backend | What it does | When |
|---|---|---|
| `python` | A small glTF 2.0 writer (numpy only): the scene graph above, flat shaded, one material per name, no bevel | Whenever `import bpy` fails. This is what built the committed `body.glb` |
| `blender` | Blender's Python (`bpy`): welded mesh, **one bevel loop on edges sharper than 30 degrees** (1.2 cm, the car-look "bevel and crease" pass), material slots, empties, exported by Blender's glTF exporter | Picked by itself when `bpy` imports: `blender --background --python tools/car_pipeline/build_car.py -- p1_coupe`, or plain `python` with the `bpy` wheel installed |

Both write the same nodes, names and extras, so Godot and the tests do not
care which one ran; `body.json` says (`backend`, `bevel`).

**Blender status (2026-10-09, Roy's laptop):** not installed (checked
`where blender`, Program Files, winget, the registry). The `blender` backend
is written against the bpy 4.x/5.x API but **has not been run**; the first
run will likely need small fixes. Free ways to get it, no installer needed
for the first two:

1. `pip install bpy` (Blender as a Python module, from PyPI, GPL, about
   350 MB; a wheel for this laptop's Python 3.13 exists, `pip index versions
   bpy` lists 5.1 and 5.2). Headless only, which is all the script uses.
   Best fit for the pipeline; reversible by uninstalling the one package.
2. The portable Blender zip from blender.org (about 350 MB, unzip and run,
   no registry). Also gives the GUI to open and look at the models.
3. `winget install BlenderFoundation.Blender` (MSI, needs admin).

Nothing paid, nothing with a credit requirement; Blender's output is ours.

## Not in step 1

UVs and the wear-mask channel (step 2), the car shader (3), body-shop parts
as separate pieces per option (4), rims and brakes (5), `CarAssembler` and
the game using this file (6). `scripts/p1_coupe_builder.gd` still builds the
car the player drives; this glb is not loaded by the game yet.
