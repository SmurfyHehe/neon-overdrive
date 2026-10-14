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

## Kits: the cars after the pilot

The coupe is the common recipe (`parts.py`). What one more car adds is its
KIT in `kits.py`: where its panels are cut, its lamps as parts of their own,
its brakes, its fuel flap, what is under its lids, and what on it is one-sided
on purpose. `body.json` lists those under `symmetry.not_mirrored`, and
`symmetry_check.py` and `tests/fleet/car_parts_kits.gd` read them from there.

    blender -b --factory-startup --python tools/car_pipeline/build_car.py -- p0_beater
    python tools/car_pipeline/symmetry_check.py p0_beater
    python tools/car_pipeline/parts_sheet.py p0_beater
    godot --headless --path . --import
    godot --headless --path . -s res://tests/fleet/car_parts_kits.gd

What a kit car has that the pilot does not:

| What | How |
|---|---|
| Brakes | part of each wheel's own mesh (`wheel_fl_mesh`...), so a wheel stays one draw call: `kits.drum` (240 mm), `kits.disc_brake`, `kits.hubcap`, `kits.lug_nuts`. The game draws a kit car's wheels from the glb (`CarAssembler.wheel_mesh`), one mesh per corner |
| Lamps | one part and one glow material each: `head_*`, `turn_f*`, `turn_r*`, `tail_*`, `brake_*` (`glow_brake`), `reverse_*` (`glow_reverse`). The last two are dark until something lights them |
| Fuel flap | `fuel_recess` (dark, with the cap) and `fuel_flap` on `hinge_fuel_flap`. It lies ON the skin: a flap cut into one side would have to be cut into the other to keep the body a mirror image |
| Plates | 520 x 110 mm in a dark recess (`plates` in the kit) |
| Other paints | `paint_primer`, `paint_rust`, `paint_bondo`: fixed colours on the body surface. `panel_mats` paints a whole cut panel, `paint_regions` a stretch of the side skin, split on the region's edges |
| Own panels | `cuts` cuts panels the common recipe does not have (barn doors), `hinge_of` hangs parts on a kit hinge, `no_trunk` drops the deck lid |
| Fewer triangles | `merge_flat`: runs of flat quads along the loft (a wheel arch puts nine stations across the roof and the floor) become one quad when the fourth corner stays within 3 mm of the plane of the other three. Outline and long edges do not move |
| Loft changes | `defn`: keys laid over the car's sheet definition for the parts build only (the tuner's `well_x`, its wheel wells' inner wall). The sheet car and the physics do not see them |
| Stance | `stance`: ride height, arch gap, rake, camber and how far the wheels push out, written to `body.json` for the shared stance pass; nothing applies them yet |

**P0, the Bug** (`p0_beater`): 6,050 body triangles in 69 parts with the
Blender backend, 782 more in the four wheels; worst mirror deviation 0.000 mm
over 38 mirrored parts and pairs. Rear engine under the lid (`engine`), spare
and tank under the front lid (`bay_spare`, `bay_tank`), torsion bar tubes and
swing axles in the wheel wells (`susp_*`), drums on all four wheels, hubcaps
on three (front right shows its wheel nuts). One-sided on purpose, as the
sheet decided (Roy kept them, 2026-10-11): the driver's mirror, the left tail
lamp (the right lens is gone), the filler on the right front quarter, the one
tail pipe.

**P7, the shop wagon** (`p7_wagon`, kit in `kit_p7_wagon.py`, rebuilt for
looks 2026-10-14, Roy 1546): 7,000 body triangles in 96 parts, 776 more in
the wheels; 0.000 mm over 49 mirrored parts and pairs. Everything is laid on
the built skin with the tuner kit's helpers (`_skin_decal`, `_rim`,
`_on_skin`), and the kit's skin list (`SKIN`) adds its own doors and every
glass, so `tests/fleet/exterior_fit.gd` holds it to zero clashes. No deck lid
(`no_trunk`): the tail is two barn doors cut out of the tail (`cuts`: the
bumper band to the header glass, 5 mm apart on the centre line, Roy), each
with its half of the rear glass (`glass_panels`), a handle, and on the right
one the rear wiper. The hinges are exposed, as on a van: the axis 12 mm
outboard of the door's edge and 12 mm behind the tail face (`barn_hinge_*`,
two straps and knuckles a door), so every point of the door is ahead of its
axis and swings back and inward, clear of the lamp column. Black plastic
bumper bands (`bumper_f_band`, `bumper_r_band`): the skin's own faces copied
out along their normals, 3 cm at the face easing to 12 mm along the sides to
the arch, walled back to the skin; the plates, blinkers, reversing lamps and
the plate lamp sit on the band's flat face. Square flush headlamps in chrome
bezels, a slot grille with two slats. Tall lamp columns at the rear corners
(blinker, running lamp, brake lamp, three lit parts a side on one ribbed
housing in two halves round the tail's ledge), a brake lamp on the roof edge
on the fixed header glass; outboard of the doors the loft's backlight is the
columns' pillar in paint (`glass_to_paint`). The 40 mm rub strip just over
the arch lips in three lengths a side (the door's piece opens with the door),
each laid in stretches between the plan's knots. The sheet's wear: the old
shop name sanded nearly off both flanks (`ghost_*`, 5 x 7 block letters in
`paint_bondo`, reading left to right on both sides, so not a mirror pair),
rust bloom round the rear arches (`rust_*`, laid cell by cell), a primer
patch on the right barn door, the left rear hubcap gone. The A-pillar strip
is in two legs: over the windshield it stays on the body, over the door's
glass it rides on the door (`pillar_a_door_*`), since a fixed strip over
glass that swings out is crossed by it. Roof rails (the drip-rail gutter), a
mast on the left front fender. Small discs in the front wheels with the
caliper on the body, 200 mm drums at the rear. Strut and torsion beam ends in
the wheel wells, a transverse engine, radiator and battery under the bonnet;
nothing hangs under the floor (the spare's cradle is an anchor only). The
loft's nose is 8 cm taller than the first build's (cars.py P7 `top`, a
stand-in anyway) so the lamps and grille sit on a face; the body's length,
width, height, wheelbase, collision box, physics and tune are unchanged.

**P2, the hot hatch** (`p2_hothatch`, kit in `kit_p2_hothatch.py`): 4,400 body
triangles in 86 parts, 948 more in the wheels; 0.000 mm over 48 mirrored parts
and pairs. Three doors. No deck lid (`no_trunk`): the tail is one hatch cut out
of the deck and the tail panel (`cuts`), hinged on the roof's rear edge, and
its glass, plate, plate lamp, handle and rear wiper go up with it (`hinge_of`);
the roof spoiler stays on the roof with the third brake lamp (`brake_c`) in
its trailing edge. Four bolted-on box blisters (`blister_*`): a flat outer
face 6.5 cm proud of the doors, a bevel all round, a flat top, a rubber edge
round the arch, seven rivets each. Tall lamp blocks at the rear corners (tail,
brake and reversing lamp as three parts a side, an amber blinker down the
outer edge), slim headlamps with amber corners, two fog lamps, a rub strip
whose door length opens with the door. `alloy_face` opens the sheet's
painted-on spokes into real ones, so the 262 mm discs and the rear drums show
between them; the caliper is a body part on the upright (in a wheel's mesh it
would turn with the wheel). `body.json` carries `required_slots` (the kit's
`slots`): the lamp, brake, plate, wiper and flap counts, readable without the
game.

**P4, the kei roadster** (`p4_kei`, kit in `kit_p4_kei.py`): 4,790 body
triangles in 62 parts, 932 more in the wheels; 0.000 mm over 37 mirrored parts
and pairs. The first open car. The fleet loft already leaves the cockpit open
(a tub: inner walls and a floor, material `interior`, drawn as `plastic`); the
kit makes the rest of an open top out of it: the loft's glass wedge is the
windscreen front and back (no `glass_backlight`), its header and A-pillars are
chrome (the one silver line), the short side pane is fixed to the frame
(`hinge_of: None`), and a rubber seal runs round the opening (`seal_cockpit`).
Two smooth headrest humps (`hump_l/r`), no hoop. Pop-up lamps modelled DOWN,
each on its own hinge (`hinge_popup_l/r`, 18 degrees): the lid lies flush on
the hood and the lamp face hangs under it; `lamps.head` in `body.json` is the
bulb when up. A side intake cut into each rear quarter (`cuts` makes the hole,
the kit builds the recess: four walls, a slatted floor 4 cm in, a lip). Oval
tail lamps with the brake lamp as their core, an amber lamp under each, one
reversing lamp in the bumper centre (`reverse_c`), a third brake lamp in a pod
on the deck's rear edge, 230 mm discs and 180 mm drums behind real spokes.


**P5, the muscle hardtop** (`p5_muscle`, kit in `kit_p5_muscle.py`, imported
by `kits.KITS`): 4,642 body triangles in 72 parts, 1,016 more in the wheels;
0.000 mm over 43 mirrored parts and pairs. One long door a side and no
B-pillar, a rear window between two flying buttresses (`buttress_l/r`, laid
over the loft), two power bulges on the hood (`hood_bulge`, opens with it), a
full-width grille mouth 30 mm deep in a chrome surround with one round lamp a
side, chrome blade bumpers (`bumper_blade_f/r`: flat under the plate, proud
outboard of it), ONE tail lamp bar 1.70 x 0.10 m: `tail_l/r` the lens,
`brake_l/r` a core strip in it, `turn_rl/rr` its red ends; no high brake lamp
(era). Reversing lamps in the rear blade, a lamp over the rear plate
(`plate_lamp`), chrome belt mouldings and bullet mirrors, 280 mm vented discs
in all four wheels with the caliper on the body, the fuel flap on the left
rear quarter, the mast on the right front fender. Under the hood: a dark floor
and the radiator, no engine yet.

**P8, the drift coupe** (`p8_driftcoupe`, kit in `kit_p8_driftcoupe.py`,
imported by `kits.KITS`): 4,485 body triangles in 77 parts, 1,224 more in
the wheels; 0.000 mm over 43 mirrored parts and pairs. A 1983-91 style
rear-drive box coupe on the kei's pop-up recipe (slim lids, 21 degrees on
`hinge_popup_l/r`), four bolt-on overfenders laid on the skin (`flare_*`: a
chrome rolled lip as the inner wall, a painted face with 14 dark rivet heads,
a top wall back to the flank), a thin chrome drip rail a side, three-bar tail
clusters (`tail_*` the top bar and the outer end of the bottom bar, `brake_*`
the middle bar, `turn_r*` its amber outer end, `reverse_*` the white inner end
of the bottom bar) on a dark satin `tail_panel`, no high brake lamp (era), the
plate lamp over the rear plate, the fuel flap on the left rear quarter, one
big oval tip on the right, 260 mm vented discs in all four deep-dish wheels
(a bronze `rim` face behind a polished chrome lip, the spokes well inboard)
with black single-pot calipers on the uprights, a strut and arm in the front
wells, the solid axle's tube, a link and a shock in the rear ones. One-sided
on purpose: the primer-grey front-left fender (`panel_mats`), so the right
front fender is written as it is too; the rear bumper's corners are scuffed
(`paint_regions` in primer, both sides). `_primer_lip` rolls the primer
fender's arch edge, which `parts.add_arch_lips` only does for `paint`.

**P3, the tuner sedan** (`p3_tuner`, kit in `kit_p3_tuner.py`): 6,470 body
triangles in 85 parts, 1,304 more in the wheels; 48 mirrored parts and pairs
within 0.05 mm. Four doors: the kit cuts the rear pair (`door_rl/rr`) on the
B-pillar line, each with its glass, seal and handle on `hinge_door_rl/rr`;
the B-pillar strip stays on the body between the door glasses, and the rear
quarter glass is fixed. Box overfenders laid on the skin (`flare_*`, the rear
ones on the rear doors as `flare_door_*`, so they open with them). Slim bar
headlamps, amber blinkers beside the plate, a slot grille, round tail lamps
on a dark `tail_panel` with the brake, reverse and rear blinker lamps as parts
of their own, a plate lamp, no high brake lamp (era). A pedestal wing on the
deck lid, its feet following the lid's curve; wipers rebuilt on the glass
(the merged windshield is up to 15 mm off the loft); the mirrors on a foot down
to the door top; a short mast on the left rear quarter. 300 mm vented discs
with bronze calipers, a strut and arm in the front wells and a multi-link rear.
Its wheel wells are 30 cm deep instead of the fleet's 16 (`defn`: `well_x`
0.46), so a front tyre at full lock clears the inner wall (on the other cars
it swings 24-30 mm through it).

Two things the tuner does that the next car can copy: lamps, rims, handles
and grilles are laid on the car's own merged panels (`_on_skin`: every way a
merged face can be cut into triangles, so what is laid on it clears it however
Blender splits it), and a flat rect on a folded panel is cut from the panel
itself (`_skin_decal`: each skin face under the rect, clipped and moved out),
not from a grid whose flat cells let the fold through.

## The exterior fit test

`tests/fleet/exterior_fit.gd` holds a car from parts to zero clashes (a car
joins its `CARS` list when its kit passes):

- no two parts cross by more than 2 mm. The depth of a crossing is how far
  one triangle goes through the other within the other's outline, so a part
  that only touches an edge is not a clash. A shut line's turned-in edge and
  dark floor reaching up to 15 mm into another's in the gap is how the shut
  line is built and does not count
- every open edge of a glass is in its seal or against an opaque part
- doors, lids and the fuel flap swing open (every 10 degrees) without going
  through anything
- the tyres clear the body at rest, rise at least 5 mm before they touch, and
  clear it at full steering lock (the car's own `max_steering_angle`); the arch
  edge sits no more than arch gap + 10 mm over the tyre
- nothing floats (every outside part within 3 mm of another), nothing below
  the ground, the tail lamps apart and tall enough

    godot --headless --path . -s res://tests/fleet/exterior_fit.gd

A new car's kit goes in a file of its own (`kit_<id>.py`, a dict `KIT`) with
one import line in `kits.py`.

In the game a kit car is built by `NpcCarBuilder` like any sheet car; when its
glb is there the body comes from `CarAssembler` instead. `NEON_PARTS_LEGACY=1`
keeps the one-piece sheet body, `NEON_CAR_PANELS=open` opens the lids, the
doors and the flap (pictures).

## Not done here

UVs and the wear-mask channel, per-option body-shop parts, the other cars,
and anything that opens the panels in the game (the open configuration is
only reachable through `NEON_CAR_PANELS=open` for pictures).
