# Real car parts in the cars: plan (2026-10-09)

Status: DECIDED 2026-10-09 (Roy answered all 8, his 135-142, section 10). Docs only, nothing built; build order for RC sessions in section 8b. Roy's ask (his 133): "make sure you
actually build the car parts in the car: engine, shocks, brake calipers and
rotor etc etc", and "I want to open the hood and doors at the gas station
too if I wish." Also from Roy via the coordinator: the hood opens in the
garage too; no hood popping open after crashes; parts may break on the road
instead.

Checked against the local clone of `origin/main` at **282343f** (2026-10-09):
`scripts/car_builder.gd` (traffic boxes and lofts, `merge_meshes()`),
`scripts/p1_coupe_builder.gd` (one merged body mesh, 7 draw calls, wheel
mesh per corner), `scripts/car_spec.gd` (`build_wheels()` hangs each wheel
visual under a GEVP `Wheel` node), `scripts/vendor/gevp/gevp_wheel.gd`
(the wheel node already moves up and down with `spring_current_length` and
spins with wheel speed), `scripts/powertrain_health.gd` (engine heat, brake
disc temperature, tyre and clutch wear already simulated),
`docs/design/fleet/fleet.json` (per-car parts, options, builds, wheel sizes,
triangle budgets) and `tools/fleet_design/` (the Python that makes the
proxies). Blender is **not** installed in this cloud container (checked),
so the pipeline either installs it there or runs on Roy's laptop.

Built on: car look and showcase (2026-10-09, decided), car feel and
personality (signed off), mod tree proposal (all 8 answered), garage and body
shop design (all 8 answered), damage and fuel design, stops proposal.

Rules this follows: one raycast-wheel sim, cars differ only by data; mods
never bring look parts (the vented hood is its own body-shop buy); wide-body
is looks only; exhaust mods are cosmetic; whole tree visible from day one;
no dents yet; no hood pop after crashes; all assets made by us (CC0 or
original); gritty PS2 night; Mobile renderer on an integrated-graphics laptop;
Low / Medium / High graphics tiers (decided in the car-look doc, section 13).

## One line

**Every part the player buys, tunes, wears out or breaks is a real piece
of the car you can look at**: behind the wheel spokes every night, under the
hood and under the car when you stop, and swapped in front of you when you
buy the next one.

## Steelman and premortem

**Steelman.** The sim already knows everything about these parts: brake disc
temperature, spring length per wheel every frame, engine heat, tyre wear,
clutch wear, which turbo is fitted, which diff. The mod tree sells them by
name, the mini-games put a wrench on them, the garage camera pans to them,
and the damage design breaks them one by one. All of that is invisible today
because the car is one merged shell with a cylinder for a wheel. Modelling
the parts once as a shared kit, hanging them on named points per car, and
driving them from numbers the sim already has turns a dozen designed systems
into something Roy can *see*, for the cost of small meshes and a few
transforms.

**Premortem: it shipped and failed because...**
1. **The road got slower.** Four brake discs, four calipers, four shocks and
   an engine bay on a car that was 7 draw calls is 30 draw calls, and Iris Xe
   is draw-call bound on the Mobile renderer. Fix: hidden parts are not
   drawn when hidden (the bay only exists while the hood is open), moving
   parts share one material and one mesh each (a `MultiMesh` for the 4
   shocks), and the road set is measured against today's `benchmark.bat`
   number before merge. Section 7 has the budget.
2. **The parts looked like clip art.** A gleaming turbo in a flat-shaded
   PS2 car reads wrong. Fix: parts use the same flat-shaded, vertex-coloured,
   bevel-loop style as the body, one shared grain, three value steps, and the
   bay is lit by the hour (garage) or by the station canopy, never by its own
   light.
3. **Twelve cars times forty parts never shipped.** Fix: a shared kit of
   about 45 part meshes with size variants, and only the *layout* per car
   (where the engine sits, hinge lines, exhaust route). Traffic and police
   cars get wheels and brakes only. Section 5 says what is shared.
4. **Opening the hood became a menu chore.** Fix: one key, the same
   everywhere you can stop (garage, station, photo mode), the car stays
   drivable; drive off and the panels close by themselves (question 2).
5. **A hood flapping open after a crash ruined the realism.** Roy already
   said no. Crashes damage parts (the damage design's six numbers) and the
   open hood then *shows* the damage; it never opens itself.

**Falsification:** put the car on the lift with the hood up and the wheel
off, and ask Roy to name the parts he paid for. If he can't tell the big
single turbo from the bolt-on, or the four-pot caliper from stock, at arm's
length, the kit failed.

## 1. What exists today (read from code)

| Today | Where | What it means for this plan |
|---|---|---|
| The P1 body is one merged mesh with surfaces body, glass, glow; 7 draw calls | `p1_coupe_builder.gd:253-300` | The hood and doors are not separate pieces, so nothing can open. The pipeline must export them as separate pieces with hinge points |
| Each wheel is a tyre cylinder plus a rim mesh under a GEVP `Wheel` node; the node rises and falls with the spring and spins | `gevp_wheel.gd:98-104`, `car_spec.gd:445-464` | Shock travel and wheel rotation are already *simulated*; a visible spring and damper only needs to be stretched between two points that already exist |
| Nothing behind the rim: no disc, no caliper, no hub | `p1_coupe_builder.gd:171`, `car_builder.gd:321` | Brake disc and caliper are new meshes; the rim must get open spokes (car-look A4) or they are never seen |
| Brake disc temperature, engine temperature, tyre wear and clutch wear are simulated per frame, with warning and fade thresholds | `powertrain_health.gd:22-64` | Rotor glow, tyre shine and the engine smoke read these numbers; no new sim |
| Damage design: six part numbers (body, engine, cooling, steering, suspension, lights), hit location picks the part | damage-fuel doc section 1b | The open hood and the wheel well show the damaged part; the car never pops its hood |
| `fleet.json` already lists per car: `parts`, `options` (front bumper, rear bumper, hood, skirts, spoiler, lamps, wheels, exhaust, stance), `builds`, `wheel` (radius, widths, track, rim style), `exhaust_tips`, `budget_tris` 10,000 | `docs/design/fleet/fleet.json` | The body-shop pieces are already data; this plan adds a `mechanical` section beside them |
| The pipeline is Python with no GPU: lofts from `fleet.json`, packed proxies, GDScript exporter | `tools/fleet_design/*.py` | The Blender step (car-look section 12) is where parts and hinge points get made; the Python kit here feeds that script |
| `merge_meshes()` merges a car's children into one `ArrayMesh` per material | `car_builder.gd:599` | Static parts of the bay can be merged into one or two draw calls when the hood opens |

## 2. The parts, and where you see them

Four places to look. The road is every night and costs frames; the other
three only happen standing still, so they can afford more.

### 2a. On the road (drawn every frame, within range)

| Part | What Roy sees | Driven by | Per car or shared |
|---|---|---|---|
| **Wheel rim** (4 designs, open spokes) | Spokes with depth; the brake behind | Spins with wheel speed (exists) | Shared kit, sized per car from `wheel.r` |
| **Tyre** with sidewall | Width per axle, lettering option, shiny shoulders when worn | `tire_w_front/rear` from `fleet.json`; wear from `powertrain_health` | Shared, sized per car |
| **Brake disc (rotor)** | Dark disc behind the spokes, vented slots on bigger ones, **glows dull red after hard braking and fades** | Spins with the wheel; colour from `brake_temp` (warn 300 °C, fade 350-650 °C already defined) | Shared, 3 sizes (stock, sport, race) |
| **Caliper and pads** | Coloured caliper on the disc, does not spin, steers with the wheel | Sits on the `Wheel` node, not the spinning `wheel_node`; colour is a body-shop pick | Shared, 1 / 2 / 4 / 6-pot |
| **Shock and spring** (the shocks Roy asked for) | A coil and damper in each wheel well, **compressing and extending as you drive**, visible through the arch gap and from the chase cam on bumps | Top end on the chassis, bottom on the `Wheel` node; length is `spring_current_length` every frame | Shared, stock / sport / coilover (threaded body, coloured spring) |
| **Exhaust tips** | Already placed from `exhaust_tips`; faint red after a hard run | Exists as positions; glow from engine load history | Per car positions, shared tips |
| **Under-car** (seen only from low cameras and when airborne) | Exhaust pipe route, driveshaft, diff, fuel tank, subframes, as dark shapes | Static, merged into one dark draw call | Per car route, shared shapes |

### 2b. Hood open (garage, gas station, photo mode when stopped)

| Part | What Roy sees | Swapped by | Shared or per car |
|---|---|---|---|
| **Engine block and head** | The engine family: inline-4, inline-6, V8, flat-4 (air-cooled, Bug), 3-cylinder (kei), boxer-turbo (crossover); cam cover on top with the car's badge | Engine identity nodes (L1) change the cover and add-ons; a swap node (later ladder cars) replaces the family | 6 families shared; the badge and cover colour per car |
| **Intake** | Air box and pipe (stock), cone filter (cams and intake node), velocity stacks (Screamer) | L1-B, L2-B1 | Shared |
| **Turbo, piping, intercooler** | None (NA); small snail on the manifold plus a small intercooler (bolt-on); **big single** with a fat pipe and a big intercooler seen through the bumper mouth; **twin-scroll** housing with two inlets | L1-A, L2-A1, L2-A2 | Shared, 3 sizes |
| **Radiator and fan** | Radiator at the nose, fan behind it (Bug: cooling fan shroud on the engine) | Cooling damage bends the fan and dents the core | Shared, 2 sizes |
| **Strut tops and brace** | Two strut tops at the back of the bay; a brace bar appears with the suspension parts ladder | Parts ladder (suspension) | Shared |
| **Battery, fluids, wiring** | Battery, washer bottle, coolant bottle, a loom | Static dressing, never swapped | Shared, one group |
| **Exhaust manifold** | Cast log (stock) or tubular header (cams node) | L1-B | Shared |
| **Damage** | Oil mist on the block, a bent fan, a split hose with a drip, a cracked intercooler; steam from the nose when cooling is hurt (exists in the damage doc) | Damage numbers above 30 % | Shared decals and swaps |

The Bug's bay is at the **back**: the engine lid opens instead of a hood and
the trunk is at the front (spare wheel, fuel tank). The kei's engine sits
behind the seats under a small lid. Same kit, different anchor set.

### 2c. Doors open (garage, gas station, photo mode when stopped)

| Part | What Roy sees |
|---|---|
| **Door card and hinge** | Inner door panel in the interior's colours, window winder (crank on old cars) or switch (new), hinge and check strap, sill plate |
| **Interior from outside** | The per-car seats, dash, shifter and pedals that already exist in the cockpit scene, seen from the street side; the weight part strips the rear seats and adds a cage |
| **Trunk** (question 3) | Spare wheel, jack, the fuel cell side node when fitted, a story item |

Doors open outward on the hinge point; the window keeps its roll position
(the Z window animation in flight).

### 2d. On the lift, wheel off (garage only)

| Part | What Roy sees | Swapped by |
|---|---|---|
| **Hub, disc, caliper, pads** at arm's length | The disc size and caliper you bought; pad thickness as a wear bar | Brakes rung of the parts ladder |
| **Suspension arms, spring, damper, anti-roll bar** | Coilover with its threaded body; the ride height you set in the Tuner shows as collar position | Suspension rung; Tuner ride height |
| **Driveshaft, diff, exhaust, tank** from below | Finned diff cover on the diff rung; the exhaust route and tips | Diff rung; body-shop tips |
| **Tyre** | Compound sidewall lettering, wear shine | Tyres rung |

The lift camera is the garage design's six per-car presets; "under the car"
is one of them.

## 3. How the mod tree and parts ladder swap the visible parts

Rule: **the tree changes hardware and the hardware is visible; body panels
stay in the body shop.** That is consistent with "mods never bring look
parts": a turbo is not a look part, a vented hood is. The one soft spot is
the Grip capstone's aero (question 6).

| Node or rung | Visible change | Where you see it |
|---|---|---|
| L0 Service | New plugs and leads, clean cam cover, fresh fluids; the oil mist goes | Hood |
| L1-A Bolt-on turbo | Small turbo on the manifold, small intercooler, blow-off valve | Hood, bumper mouth |
| L1-B Cams and intake | Cone filter, tubular header, cam cover badge | Hood |
| L2-A1 Big single | Big turbo, fat piping, big intercooler filling the bumper mouth | Hood, front of car on the road |
| L2-A2 Twin-scroll | Twin-inlet housing, medium intercooler | Hood |
| L2-B1 Screamer | Velocity stacks, tall cam cover | Hood |
| L2-B2 Stroker | Nothing outside the block is honest to show; a build plaque on the cover and a bigger harmonic damper (question 5) | Hood |
| L3 Grip | Strut brace, race pads; the aero number has no visible part unless question 6 says under-car splitter and flat floor | Hood, under car |
| L3 Slide | Angle-kit steering arms (longer), a hydraulic handbrake in the cabin | Wheel off, door open |
| Side: blind-spot lamp | Amber lamp in the mirror housing (exists in the mirror design) | Outside |
| Side: fuel cell | Red cell strapped in the trunk | Trunk |
| Brakes rung | Disc size S → M → L, caliper 1 → 2 → 4 → 6-pot, slotted and drilled | Behind spokes every night |
| Suspension rung | Stock → sport (coloured spring) → coilover (threaded body), brace | Wheel well every night, hood |
| Tyres rung | Sidewall lettering per compound | Every night |
| Diff rung | Finned cover | Under car |
| Gearbox rung | Short shifter and knob in the cabin | Cockpit, door open |
| Weight rung | Rear seats out, cage, bare door cards | Door open, through the glass |

The mini-game for each part type (garage design, section 3) uses **the same
part mesh**: the hose-and-clamp game shows the actual intercooler pipe being
fitted, the jack-and-swap game shows the actual caliper. One kit feeds both.

## 4. Wear, damage and motion on the parts

| Signal | Source (exists) | What it does to the part | Tier |
|---|---|---|---|
| Brake temperature | `powertrain_health.brake_temp` | Disc emission ramps from 300 °C (faint) to 650 °C (bright, with a heat haze sprite); cools by itself | Medium and up (Low: no glow) |
| Spring length | `Wheel.spring_current_length` | Damper piston slides, spring scales along its axis, every frame | Medium and up (Low: shocks hidden) |
| Wheel speed and steer | `wheel_node.rotation` (exists) | Rim, tyre and disc spin; caliper and shock steer with the hub but do not spin | All tiers |
| Tyre wear | `powertrain_health` tyre wear (0-1) | Sidewall and shoulder roughness drops (shiny), cord texture above 0.8 | Medium and up |
| Engine damage | damage design part number | Oil mist decal, split hose, misfire puffs from the tips; above 80 % a cracked part with a tape label when you look under the hood | All tiers (only shown when the hood is open) |
| Cooling damage | damage design | Bent fan, dented core, steam at the nose (already planned) | All tiers |
| Suspension damage | damage design, per wheel | That corner's spring sits lower, the damper leans, visible camber | All tiers |
| Steering damage | damage design | Front wheels show the toe offset the sim applies | All tiers |
| Lights | damage design | Broken lens piece (car-look A3 lenses) | All tiers |
| Parts breaking on the road | New small rule: a part at 100 % damage can "let go" once per night (a hose, a belt, a brake line on one corner) with a sound and a Dave or HUD line; the car keeps driving on its floor, the open hood shows the broken piece | Design detail for the damage session; no new numbers here |

No hood pop after crashes (decided). Crashes change the *contents* of the
bay, never open it.

**Opening and closing.** One key when stopped (hood), one for the doors,
one for the trunk if yes, usable in the garage, at the station menu, and in
photo mode when the car is stopped (question 1). Hinge animations are 0.6 s
on the named hinge points. Driving off closes them by themselves (question
2) so the sim never has to care about an open panel.

## 5. What the 12 cars share, and what each one needs

| Shared kit (built once) | Count | Per car (from its data file) |
|---|---|---|
| Engine families with cam cover | 6 | Which family, cover colour, badge text, bay position and lean |
| Intake set (box, cone, stacks) | 3 | Mount point |
| Turbo set (small, big single, twin-scroll), intercooler (S, M, L), piping | 6 | Mount points and pipe route |
| Radiator and fan (2 sizes), Bug fan shroud | 3 | Position |
| Strut tops, brace, battery, bottles, loom, manifold (log, header) | 7 | Positions |
| Brake disc (3 sizes), caliper (4 types), hub, pads | 8 | Disc size per axle from `wheel.r` |
| Spring and damper (stock, sport, coilover), arms, anti-roll bar | 5 | Travel length per axle from `spring_length`; arm length from track |
| Rims (4, from car-look A4) and tyre | 5 | Radius, widths, offset (wide-body pushes out) |
| Under-car set (exhaust pipe, driveshaft, diff, finned diff, tank, subframe) | 6 | Route points |
| Door card (crank, switch), hinge, sill, trunk kit, cage | 6 | Hinge points, which window control |
| **Total** | **about 45 meshes** | **One data section per car, about 40 lines** |

Per car, the things that cannot be shared and are modelled with the body in
the pipeline: the hood (or engine lid) and its hinge line, the doors with
their window cut, the trunk lid, the wheel-well shape, and the shut lines
(already in the car-look plan as paint-mask lines; they become real panel
edges here).

| Car | Engine family | Bay | Notes |
|---|---|---|---|
| T0 Bug beater | Flat-4 air-cooled | Rear lid | Front trunk with spare and tank; crank windows; mismatched panels |
| P1 Sports coupe | Inline-6 | Front, long and low | Pop-up mechanism visible with the hood up |
| P2 Hot hatch | Inline-4 | Front, transverse | Hatch opens too (counts as the trunk) |
| P3 Tuner sedan | Inline-6 turbo (AWD) | Front | Big intercooler is its signature |
| P4 Kei roadster | 3-cylinder | Mid, under a small lid behind the seats | Tiny bay, mostly the lid and the engine |
| P5 Muscle sedan | V8 | Front, tall | Hood pins; the cowl scoop sits over the intake |
| P6 Crossover | Boxer-turbo (AWD) | Front, low and wide | Skid plate under the bay |
| Ally cars (crew: Juno's hatch, Pilar's kei, Walt's) and enemy cars (rival crews, Pike's men) | Same as the player car they are built from | Same | Full road set and real undercarriage (Roy 140, 141); bay and opening panels only when the story shows a crew car in the garage |
| Police C1-C3 | none | closed | Wheels, discs with glow, calipers and the real undercarriage (the interceptor gets the big disc so it reads from behind); no bay, no opening |
| Traffic N1-N3 | none | closed | Wheels only; a flat dark under-tray merged into the body, no separate parts |

### 5b. The undercarriage, every class (Roy 140)

Roy wants a real underside on his car, on ally cars and on enemy cars, not a
flat plate. It matters because the chase cam looks down at rivals ahead,
the cockpit mirrors look up at cops behind, jumps and off-ramps show the
underside, and photo mode goes low.

| Piece | Shared mesh | Per car |
|---|---|---|
| Floor pan with sills and the tunnel | one per body class (coupe, hatch, sedan, kei, muscle, crossover, Bug) | shut to the body's outline by the pipeline |
| Front and rear subframes, control arms, anti-roll bars | shared, scaled by track | mount points |
| Exhaust: manifold down-pipe, cat, mid pipe, muffler, tips | shared pieces on a route | `exhaust_route_0..n` points |
| Driveshaft and diff (RWD, AWD), or the transverse box (FWD) | shared, 3 layouts | drive layout from the car data |
| Fuel tank, spare well, skid plate (crossover), fuel cell (side node) | shared | position |
| Springs and dampers (already in the road set) | shared | travel |

How it is drawn: the whole static underside is **one merged mesh with one
dark material** (vertex-coloured, three value steps, no lights of its own),
so it costs one draw call per car. Only the springs and dampers move, and
they are the road set's `MultiMesh` already. Under the car at the lift the
same mesh is seen at arm's length, so it is modelled to read at 1 m, not
just at 10 m.

Per class:

| Class | Underside | LOD rule | Draw calls per car | Triangles |
|---|---|---|---|---|
| Player | Real set, full detail | Always LOD0 | +1 (plus the road set's +2) | about 900 |
| Ally and enemy cars | Real set, same mesh family as the player car they are built from | LOD0 within 40 m, LOD1 (merged dark plate, no pipes) to 80 m, nothing beyond | +1 within 40 m | about 900 |
| Police | Real set, cop variant (push-bar brackets, no muffler on the interceptor) | LOD0 within 40 m (they are behind you, mirrors look up at them), LOD1 to 80 m | +1 within 40 m | about 700 |
| Traffic | Flat dark tray merged into the body mesh | none | +0 | +30 |

Worst case on the road is a chase: player plus 3 enemy cars plus 4 cops in
range is 8 undersides at +1 draw call each, plus discs and glow on all 8
(Roy 141), about **+24 draw calls and +12,000 triangles** over today. That
is inside the draw-call headroom the stress-test session has to report
before A1 merges, and it is the number the undercarriage session measures
first (section 7). Low tier keeps the player's underside and drops the
others to the dark plate.

## 6. How it uses the pipeline and the one-data-file-per-car

The car-look doc (section 12) decided a Blender-plus-Python pipeline, and the
car-feel doc (section 6b) decided one car definition file per car. This plan
slots into both; it does not add a third system.

- **Kit script:** `tools/car_pipeline/parts/` holds one small Python
  function per part that builds it in Blender from primitives (cylinders,
  boxes, a bevel modifier), in the body's flat-shaded style, with size
  parameters. Output: `assets/cars/parts/<part>_<size>.glb`, one material
  slot set shared across the kit (metal, cast, rubber, painted, glow).
  Nothing is downloaded; everything is ours.
- **Body script:** `build_car.py` (car-look step 1) exports the hood, doors,
  trunk and the engine lid as **separate pieces** with named empties:
  `hinge_hood`, `hinge_door_l/r`, `hinge_trunk`, `bay_engine`, `bay_turbo`,
  `bay_intercooler`, `bay_radiator`, `strut_top_fl..rr`, `shock_top_fl..rr`,
  `hub_fl..rr`, `exhaust_route_0..n`, `diff`, `tank`, plus the six camera
  presets the garage already asks for.
- **Car definition file** (car-feel 6b) gets a `mechanical` section: engine
  family, default fitted parts, per-axle disc size, spring travel, window
  control type, which panels open. Mod tree nodes get one `visual` field
  naming the kit parts they fit and remove.
- **Godot:** `CarAssembler` (car-look step 6) reads the body glb, places kit
  parts on the empties, parents the disc to `wheel_node`, the caliper and
  shock bottom to the `Wheel`, the shock top to the chassis, and builds the
  bay as a hidden group that is only added to the tree when the hood opens.
  `PartsState` holds fitted parts, open panels and damage decals and is what
  the garage, the station, the mini-games and photo mode all talk to.
- **Tests (headless):** every car builds in every tree build and parts
  combination; triangle and draw-call counts are checked against the budget
  per tier; the shock length at rest equals `spring_length` minus the sag;
  every mod node's `visual` names parts that exist.
- **Blender in the cloud:** the container has no Blender today. Either the
  pipeline session installs it (a free download, GPL tool, output is ours),
  or steps 1, 4 and 5 run on Roy's laptop where Blender can be installed
  once. The Python kit is written to run either way.

Until the pipeline lands there is a cheap bridge: brake discs, calipers and
shocks can be added today from GDScript primitives on the P1, using the
same parent nodes. That is item A1 below and it is not throwaway: the parent
rules and the health hooks are what the pipeline version reuses.

## 7. Frame cost on the laptop, with tiers and LODs

Mobile renderer, Iris Xe, 1080p. The street is draw-call bound (polish
research), so draw calls are the number to watch, triangles second.

| Set | Draw calls | Triangles | When drawn |
|---|---|---|---|
| P1 today | 7 | about 2,800 | Always |
| Road set, LOD0 (within 20 m, chase cam, photo mode): 4 discs + 4 calipers merged into the wheel mesh's material set, 4 shocks as one `MultiMesh`, under-car as one dark mesh | +3 | +1,600 | Always for the player car; nearby rivals and cops |
| Road set, LOD0 on ally, enemy and police cars within 40 m (Roy 140, 141): discs with glow, calipers, shocks, real underside | +3 each | +1,600 each | Chases and races; the undercarriage session measures the 8-car worst case first |
| Road set, LOD1 (40-80 m): disc as a flat dark face in the rim, no shocks, dark under-plate | +0 | +200 | Allies, enemies and cops at distance |
| LOD2 (beyond 80 m): today's merged body, closed rim | 0 | 0 | Traffic always; far cars |
| Hood open (bay group added to the tree): block, head, intake, turbo, intercooler, radiator, dressing merged into 2 draw calls, plus the hood piece | +3 | +3,500 | Garage, station, photo mode only; never while moving |
| Doors open: 2 door pieces, 2 door cards, interior already loaded | +2 | +900 | Same |
| Wheel off on the lift: hub, pads, arms | +2 | +700 | Garage only |

So the road cost of the plan is about **three draw calls and 1,600
triangles** on the player car, inside the 10,000-triangle budget `fleet.json`
already sets, and nothing on traffic. The garage and the station are standing
still, so their extra is paid when the CPU is idle.

| Tier | Road parts | Open panels | Effects |
|---|---|---|---|
| **Low** | Player: rim with a flat dark disc face, no caliper mesh (a dark paint patch), no shocks, real underside kept. Others: dark under-plate, flat disc | Hood and doors open, bay drawn as one merged mesh without decals | Rotor glow on the player only, no tyre shine |
| **Medium** (Roy's laptop) | Full road set at LOD0 on the player car and on ally, enemy and police cars within 40 m; LOD1 beyond | Full bay with decals | Rotor glow on all of them, tyre shine, shock motion |
| **High** | LOD0 range out to 80 m | Full, plus the one real shadow under the car in the garage so the bay has depth | Heat haze sprite over hot discs, exhaust tip glow |

Measured, not guessed: the stress-test session's `benchmark.bat` line before
and after A1, at Medium, with full traffic. A1 does not merge if the start
line frame time rises by more than 0.3 ms.

## 8. Sorted by workload, with build order and model

**A: small (one laptop session each, in this order)**

| # | Item | What Roy sees | Model, why |
|---|---|---|---|
| A1 | Brake disc, caliper and shock on the P1 from GDScript primitives, parented per section 6, rotor glow from `brake_temp`, shock stretch from the spring; benchmark before and after | Red calipers and glowing discs behind open spokes every night; springs working in the arches | Fable: look judgement, with car-look A4 (rims) in the same session |
| A2 | Hood, doors and trunk as separate pieces on the P1 with hinge points and the open and close animation; one key each when stopped; auto-close on drive-off | Hood and doors open at the station and in the garage | Fable: needs the pipeline step 1 for the P1 body, or a hand split of the merged mesh as a bridge |
| A3 | The P1 engine bay: inline-6, intake, radiator, strut tops, dressing, under-car set, as a hidden group that appears when the hood opens | A real engine under the hood | Fable, in the cloud if Blender is installed there, else on the laptop |
| A4 | `mechanical` section in the car definition file and the `visual` field on the P1 tree nodes; `PartsState`; headless test that every node's parts exist and the budget holds | Nothing yet; makes A5 and B1 data-driven | Opus: data model |
| A5 | Tree and parts-ladder swaps on the P1 (turbo set, intake set, brakes, suspension) wired to `PartsState`, with the live swap in the garage | Buy the big single and see it fill the bumper mouth | Fable |
| A6 | Damage on the parts: oil mist, bent fan, split hose, leaning damper, broken lens, the once-a-night "let go" | A crash that shows under the hood | Opus: ties to the damage session's numbers |

**B: medium (one at a time after A, Roy picks the order)**

| # | Item | Model |
|---|---|---|
| B1 | The parts kit in Blender (about 45 meshes) replacing the A1 and A3 primitives, exported as glb with the shared material set | Fable for the look, Sonnet for the export script |
| B2 | Beater: rear engine lid, flat-4, front trunk, crank window door cards, mismatched panels | Fable, with the player-cars session that owns the Bug |
| B3 | Lift view: wheel off, arms, hub, pads, diff cover, exhaust route; the six camera presets reading real part positions | Fable, after garage slice E4a |
| B4 | Mini-game scenes using the kit meshes (hose and clamp, jack and swap, torque sequence) | Fable |
| B5 | Tyre wear shine, cord texture, sidewall lettering per compound | Sonnet |
| B6 | Rivals and cops at LOD0 within range (High), cop interceptor's big disc | Sonnet |

**C: large (later)**

| # | Item |
|---|---|
| C1 | P2-P6 bays, panels and under-car, one car per PR as each car lands through the pipeline |
| C2 | Engine swaps between families for the ladder cars (wagon, drift coupe, mid-engine, rally), with the bay re-laid out |
| C3 | Interiors seen through open doors matched to the per-car interiors (car-look section 7); weight-rung stripped cabin and cage |
| C4 | Dents on the panels (decided later) using the same separate pieces |

### 8b. Ordered build list for RC sessions (Roy 142: wheels and brakes AND the engine bay, "and more")

One laptop session each. The first three touch different files and can run
at the same time; 4 waits for a split body; 5 is cloud work; 6 and 7 wait
for 5. Every session ends with a real headless run, screenshots for Roy,
and a `benchmark.bat` line.

| Order | Session | What Roy sees when it lands | Files it owns | Model | Can run beside |
|---|---|---|---|---|---|
| 1 | **Wheels and brakes**: open-spoke rims (car-look A4), disc, caliper, shock and spring on the P1; rotor glow from `brake_temp`; the same set on cop, ally and enemy cars within range with LOD1 beyond (Roy 141) | Red calipers and glowing discs behind the spokes on every car that matters, springs working | wheel visual code, a new `car_parts.gd`, `powertrain_health` read-only | Fable | 2, 3 |
| 2 | **Engine bay (P1)**: inline-6, intake, radiator and fan, strut tops, battery and loom, manifold, as a hidden group; a temporary key shows it in photo mode until session 4 opens the hood | A real engine under the hood | new `engine_bay.gd` plus bay meshes; nothing in the body builder | Fable | 1, 3 |
| 3 | **Undercarriage, all classes** (section 5b): floor pan, subframes, arms, exhaust route, driveshaft, diff, tank; one merged dark mesh per car; cop variant; dark plate on traffic; the 8-car chase benchmark | A real underside on you, allies, enemies and cops, from the mirrors, jumps and photo mode | new `undercarriage.gd` plus meshes; `fleet.json` route points | Fable for the look, Sonnet if run as a second session for the cop and traffic variants | 1, 2 |
| 4 | **Hood, doors, trunk**: body split into panels with hinge points (pipeline step 1, or a hand split of the P1 as a bridge), open and close animation, one key each when stopped, anywhere (Roy 135), auto-close on drive-off (136), trunk and hatch too (137); door cards keep the window roll state | Open the hood and doors at the station, in the garage and in photo mode | `p1_coupe_builder.gd` (after the player-cars session lands), `player.gd` input, photo mode | Fable | after 1-3, beside 5 |
| 5 | **Data model** (cloud): `mechanical` section in the car definition file, `visual` field on tree nodes, `PartsState`, headless checks that every node's parts exist and the budget holds per tier | Nothing yet; makes 6 and 7 data-driven | car definition file, mod tree files, tests | Opus | beside 4 |
| 6 | **Swaps**: turbo set, intake set, brakes, suspension, diff cover, plaque for the internal nodes (Roy 139), wired to the tree and the parts ladder with the live swap in the garage | Buy the big single and watch it fill the bumper mouth | `car_parts.gd`, `engine_bay.gd`, garage tree card | Fable | after 5, beside 7 |
| 7 | **Damage visuals**: oil mist, bent fan, split hose, cracked intercooler, leaning damper, broken lens, tape labels (Roy 138), the once-a-night "let go" | A crash that shows under the hood and in the wheel well | damage hooks, decals, `engine_bay.gd` read-only | Opus | after 5, beside 6 |
| 8 | **Beater and the rest**: the Bug's rear lid and flat-4, then P2-P6 one per session as each car comes through the pipeline | Every car with its own bay, panels and underside | per-car builders and data | Fable | after 6 |

Clashes to respect: `p1_coupe_builder.gd` belongs to the player-cars
session until it lands (sessions 1-3 add nodes beside the body, they do
not edit it); the window-roll session owns the door glass state; the
stress-test session owns the benchmark line and must be sent the 8-car
chase number from session 3.

**In flight, not duplicated:** player cars incl. the Bug (owns
`p1_coupe_builder.gd` until it lands; A1 waits for it or branches from it),
window roll animation (door cards must keep its roll state), hands on the
wheel, stress test and speed (owns the benchmark line), damage and fuel
design thread (owns the part numbers A6 reads).

## 9. Contradictions found

- **"Mods never bring look parts" vs hardware you can see.** Settled here as:
  engine-bay and brake hardware *is* the mod and is always visible; body
  panels (vented hood, wing, bumpers) stay body-shop buys. The Grip
  capstone's aero is the one node whose number has no honest part unless Roy
  picks an under-car splitter and flat floor (question 6).
- **Car-look section 12 assumed Blender runs headless in the cloud
  container.** It is not installed there today. The plan works either way;
  the pipeline session must install it or run that step on the laptop.
- **Garage design budgets the car at 7 draw calls.** With the road set it is
  about 10, and about 17 with the hood and doors open. The garage budget
  (about 40 room draw calls) still fits; the garage doc's number should be
  updated when A1 lands.
- **Damage doc has a "lights" part but no brake or wheel damage.** The
  suspension part already covers the corner; this plan reads it and adds no
  new number.
- **Stance (camber) in the car-look doc is a look; here the suspension
  damage also tilts a wheel.** Both are fine together: the look sets the rest
  camber, damage adds to it on one corner.

## 10. Roy's answers (2026-10-09, his 135-142)

| # | Question | Answer | What changed |
|---|---|---|---|
| 135 | Where can you open the hood and doors | **Anywhere** you are stopped, photo mode included | as proposed |
| 136 | Drive off with the hood up | **Closes itself** | as proposed |
| 137 | Trunk and hatch open too | **Yes** | as proposed |
| 138 | Tape labels on broken parts | **Yes** | as proposed |
| 139 | Plaque for the internal engine nodes | **"idk, research"** | section 10a below; recommendation: plaque plus cam cover now, x-ray view on the lift later |
| 140 | Grip aero as under-car splitter and flat floor | **Yes, and a real undercarriage on user, ally and enemy cars** | new section 5b, session 3 in 8b |
| 141 | Glowing discs on which cars | **Me, allies, enemies and cops** (traffic stays plain) | road set at LOD0 on all four classes within range; tiers in section 7 |
| 142 | Build first | **Both, and more** | ordered list in section 8b, sessions 1-3 in parallel |

### 10a. Research for 139: how other games show upgrades you cannot see from outside

Checked 2026-10-09. Web results were thin on the exact "does the model
change" question (sources below), so the game-by-game lines are from my own
knowledge of those games and are marked as such; the recommendation does
not depend on any one of them.

| Game | Engine bay | Internal upgrades (cams, pistons, stroker) | What we can take |
|---|---|---|---|
| Forza Horizon 5 (from memory) | Forzavista opens the hood; an engine swap changes the engine model | Not shown; the parts menu is a list with stat bars | Swaps change the visible block; internals are a card, not a model |
| Need for Speed Heat and Unbound (from memory) | Hood opens in the garage and the engine model follows the swap; turbo and intake kits show on some cars | Not shown | Same |
| Gran Turismo 7 (from memory) | No engine bay view | Not shown | Nothing |
| Car Mechanic Simulator 2021 | Every part is a real object; rebuild orders list pistons, rods, crank and cams one by one (sources below) | Shown, as parts you take out and put in; players complain the internals are not animated | The **mini-game is the place to see internals**: our timing game already opens the engine |
| My Summer Car, Street Legal Racing (from memory) | Every part real, hand-fitted | Shown while fitting, hidden once the engine is closed | Same lesson: internals are seen while working, not after |
| BeamNG.drive (from memory) | Engine and turbo visible as parts; internals are a config choice | Not modelled as geometry | Config card plus the visible block is enough |
| Automation (from memory) | Builds a full engine model per design, with a cutaway view | Shown as a cutaway render | A cutaway or x-ray view is the best way to show internals without opening anything |

**Recommendation (my pick first):** for the stroker, cams and screamer
nodes, (1) a build plaque on the cam cover and a changed cover or intake
piece, so the bay still changes; (2) the timing-marks and torque-sequence
mini-games show the actual cams and crank while you fit them, which is how
the mechanic sims do it; (3) later, a **cutaway view** on the lift (C5
below) that fades the block to show pistons, cams and the crank turning at
idle, the one thing players asked Car Mechanic Simulator for. Alternative:
nothing visible and only the card changes, which every arcade racer does and
which Roy's "actually build the parts" ask argues against.

Sources: [racinggames.gg on FH5 engine audio](https://racinggames.gg/article/forza-horizon-5-to-feature-new-engine-audio-for-each-car), [GTPlanet FH5 thread](https://www.gtplanet.net/forum/threads/forza-horizon-5-general-discussion.399481/post-13448841), [PC Games NFS Unbound review](https://www.pcgames.de/Need-for-Speed-Unbound-Spiel-74062/Tests/Review-Wertung-Gameplay-Release-Criterion-Electronic-Arts-Rennspiel-1408566/3/), [games.gg NFS Unbound](https://games.gg/need-for-speed-unbound/), [CMS 2021 Mayen M8 rebuild guide](https://www.magicgameworld.com/?p=126847), [CMS 2021 Steam discussion on animation](https://steamcommunity.com/app/1190000/discussions/0/4342112975491929332), [CMS 2021 engine swap list](https://www.gameskinny.com/tips/car-mechanic-simulator-2021-engine-swap-list/).

Added to C: **C5** cutaway view on the lift (block fades, internals turn at idle), Fable, after session 6.
