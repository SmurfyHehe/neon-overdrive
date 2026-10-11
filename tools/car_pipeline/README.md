# car_pipeline: cars built from separate parts

The car modelling pipeline decided in
`docs/planning/car-look-showcase-2026-10-09.md` (section 12, Roy 123),
extended by `docs/planning/car-parts-plan-2026-10-09.md` (section 6) and
turned into the **parts build** on 2026-10-10 (cars from parts, pilot: the P1
coupe). One car's body is written as glTF with every real part as its own
named mesh; `scripts/car/car_assembler.gd` merges them back into one mesh
with four surfaces when the game loads the car.

    blender -b --factory-startup --python tools/car_pipeline/build_car.py -- p1_coupe   # -> assets/cars/p1_coupe/body.glb + body.json
    python tools/car_pipeline/build_car.py p1_coupe --backend python                    # the same without Blender (no bevel)
    python tools/car_pipeline/symmetry_check.py p1_coupe                                # left = mirror of right?
    python tools/car_pipeline/parts_sheet.py p1_coupe                                   # -> docs/design/pipeline/p1_coupe_parts.png
    godot --headless --path . -s res://tests/fleet/car_pipeline_p1.gd
    godot --headless --path . -s res://tests/car/car_assembler.gd

After a rebuild, let Godot re-import the glb before running the game or the
tests: `godot --headless --path . --import`.

## Blender

Blender 4.5 LTS, the portable zip from
<https://download.blender.org/release/Blender4.5/> (free, GPL; what it writes
is ours). On Roy's laptop it is unpacked in `C:\Tools\blender-4.5\` (4.5.14,
checksum checked against the release's `.sha256`); nothing is installed, the
folder can simply be moved away.

    set NEON_BLENDER=C:\Tools\blender-4.5\blender.exe
    %NEON_BLENDER% -b --factory-startup --version
    %NEON_BLENDER% -b --factory-startup --python tools/car_pipeline/build_car.py -- p1_coupe

`parts_sheet.py` finds Blender through `NEON_BLENDER`, then that folder, then
`PATH`. `build_car.py` is run BY Blender, so it needs no variable.

Nothing is added to Blender's Python. Its bundled numpy is all the build
needs: `tools/fleet_design/render.py` (which wants Pillow and scipy to draw
the design sheets) is only read for its colour tables, so `build_car.py`
stands those two imports in when they are missing. The check sheet's layout
and labels are done by the system Python, which already has Pillow.

Add `--blend some.blend` to keep the Blender scene to look at in the GUI.

## Where the shape comes from

The same definitions the design sheets and the B1 audit use:
`tools/fleet_design/cars.py` and `options.py`, which `export.py` writes out as
`docs/design/fleet/fleet.json`. The car id is looked up in `fleet.json`, so
the sheet and this model are the same car. `parts.py` rebuilds the sheet's
loft and stops if the right half is not the sheet's, triangle for triangle:
the parts build changes what the car is made of, not its shape. Nothing is
downloaded: every triangle is generated from those numbers (asset rule: all
assets free for a sold game, no credit, no payment).

## Symmetry

Roy, 2026-10-10: "make sure the cars are symmetrical". Only the RIGHT half of
the car is kept from what is generated; the left half is its mirror image,
vertex for vertex, including the normals and the baked `ao`. A part that
straddles the centre line (hood, body, bumpers, windshield) is built as its
right half and mirrored; a right-hand part (`door_r`, `fender_fr`, `tail_r`)
is mirrored into its left twin. `symmetry_check.py` measures it on the glb and
`tests/car/car_assembler.gd` checks it in Godot.

P1 coupe, measured: worst mirror deviation **0.000 mm** over 32 mirrored
parts and pairs. The one-piece sheet proxy the game drew before measures
**30 mm** (its twisted quads are cut along opposite diagonals left and right).

Not mirrored, on purpose (`parts.ASYMMETRIC`, also listed in `body.json`):

| Part | Why |
|---|---|
| `mirror_l`, `mirror_r` | the game aims the two cups differently at the driver (`P1CoupeBuilder.MIRRORS`, yaw 12 and -20 degrees) |
| `wiper_l`, `wiper_r` | wipers park the same way round on both sides, as on a real car |
| `antenna` | one mast, on the left rear quarter |

## What is in body.glb

Godot axes (X right, Y up, -Z forward), origin on the ground midway between
the axles, metres. Names are what Godot keys on.

| Node | What |
|---|---|
| `body`, `underbody` | the shell: everything that never moves |
| `fender_fl/fr`, `bumper_f`, `bumper_r` | bolt-on panels (the body-shop swaps; `bumper_r` is the REAR bumper) |
| `hinge_hood` > `hood` | hood on its hinge line (rear edge, at the cowl); turn the empty on its `axis` by `open_sign * open_deg` and the hood rises |
| `hinge_door_l/r` > `door_*`, `glass_door_*`, `seal_door_*`, `handle_*`, `mirror_*` | a door with everything that swings with it, vertical axis on the A-pillar line |
| `hinge_trunk` > `trunk` | the deck lid on its front edge |
| `glass_windshield`, `glass_backlight`, `glass_quarter_l/r` | the fixed glass |
| `seal_*`, `pillar_a_l/r`, `pillar_b_l/r`, `sail_l/r`, `arch_liner_fl/fr/rl/rr` | rubber seals round every glass, the A-pillars (a body-colour strip over the bare glass edge of the sheet's loft), B-pillar and mirror sail trim, wheel arch liners |
| `grille`, `turn_l/r`, `popup_l/r`, `tail_l/r`, `tail_panel`, `bumper_r_insert` | grille slats, turn lamps, pop-up pods (pod + lens + bulb), tail lamps (red lens ring over the lit element), the dark tail panel and bumper insert |
| `plate_f/r`, `wiper_l/r`, `antenna`, `spoiler`, `exhaust` | small parts |
| `wheel_fl/fr/rl/rr` > `wheel_*_mesh` | empties on the hubs with the sheet's rim and tyre (the game draws its own wheels; the assembler skips these) |
| `slot_door_l/r`, `slot_hood`, `slot_sun`, `slot_rear` | the 4 sticker slots (5 placements), +Z is the outward normal, `size` in extras |
| `tip_0..n` | exhaust tips, +Z the exhaust direction, `r` in extras |
| `mount_*`, `lamp_l/r`, `hub_*`, `shock_top_*`, `strut_top_fl/fr`, `bay_*`, `exhaust_route_0..3`, `diff`, `tank` | where body-shop parts and the real parts attach |
| `cam_*` | six camera presets, -Z looking at the car |

`body.json` beside it lists every node, the triangles per mesh, the hinges,
the slots, tips, hubs, dims, lamp centres, the material colours, the shut
gap, the symmetry rule and its exceptions, and the backend that wrote the file.

Materials (one glTF material per name, colours in `parts.COLOURS`):
`paint`, `under_paint`, `plastic`, `chrome`, `rubber`, `plate`, `mirror`,
`lens_red`, `glass`, `glow_head`, `glow_lens`, `glow_tail`, `glow_turn`.

Vertex colour `COLOR_0` on every mesh: red = **ao** (ambient occlusion baked
per vertex, 32 rays, the ground counts, 1 = open), green = **shut** (1 on a
shut line, 0 six millimetres from it). In Blender they are also there as the
float attributes `ao` and `shut`.

## Shut lines

A panel is cut out of the loft with planes (`parts.regions`). Every cut
leaves a real gap of **4 mm** (each side trimmed 2 mm back; measured 3.98 to
4.00 mm in Godot), even all round. Behind it the edge of a panel that opens
turns in **15 mm**; the fixed side carries a dark `under_paint` floor at that
depth reaching under both edges, so a gap is a dark line and never a hole.
At chase distance 4 mm is less than a pixel, so the skin within 6 mm of every
shut line carries `shut` and the paint shader darkens by it.

Creases sharper than 35 degrees get one bevel loop in the Blender backend:
8 mm, and 12 mm on the belt, the shoulder, the hood edge and the wheel arch
lips (each arch edge has an 18 mm return into the well so the bevel has
something to roll over). Everything else is smooth within a part.

P1 stock, Blender backend: **6,068 triangles** in 52 parts without the wheels
(target 5,000 to 6,500, ceiling 7,000), 325 KB. The numpy backend gives 5,104
(no bevel).

## In the game

`CarAssembler.build("p1_coupe")` loads the imported glb, merges the parts by
material into ONE mesh with 4 surfaces (`body`, `trim`, `glass`, `glow`) and
caches it: 9 draw calls for the coupe, the same as the sheet body (the door
mirrors used to be a mesh of their own). `{"panels": "open"}` takes the hood,
doors and trunk out as four one-surface meshes on their hinges (+4 draw
calls). `CarAssembler.swap_part(car, "bumper_f", mesh)` replaces one part.
`P1CoupeBuilder.build_chassis_visual()` uses it whenever the glb is there;
`NEON_COUPE_LEGACY=1` keeps the old one-piece proxy, `NEON_CAR_PANELS=open`
builds the coupe with its panels open (pictures only).

## Backends

| Backend | What it does | When |
|---|---|---|
| `blender` | Blender's Python (`bpy`): the parts, the crease bevels, weighted normals, exported by Blender's glTF exporter. This is what built the committed `body.glb` | Picked by itself when the script runs inside Blender |
| `python` | A small glTF 2.0 writer (numpy only): the same parts, gaps, `ao`, `shut` and symmetry, smooth within 35 degrees, no bevel | Whenever `import bpy` fails, or `--backend python` |

Both write the same nodes, names, materials and attributes, so Godot and the
tests do not care which one ran; `body.json` says (`backend`, `bevel`). Both
were run and pass `symmetry_check.py`, `car_pipeline_p1.gd`,
`car_assembler.gd` and `p1_coupe.gd` (2026-10-10).

## Not done here

UVs and the wear-mask channel, per-option body-shop parts, the other cars,
and anything that opens the panels in the game (the open configuration is
only reachable through `NEON_CAR_PANELS=open` for pictures).
