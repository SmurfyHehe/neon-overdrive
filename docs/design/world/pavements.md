# Pavements and kerbs: the cross-section table and its sweep (2026-10-10)

Built on PR #352 (step 1: kerb profile, slab pavement, dropped and yellow kerbs).
The plan file (`notes/pavements-and-kerbs-2026-10-10.md`, all eight questions answered
yes) was not readable from the laptop, so the steps below follow the brief's list:
K2 cross-section table, K3 kerb physics sweep with a Kerb grip group, K4 yellow paint,
drains and bent wheel, K5 freeway without a kerb, K6 benchmark. Numbers marked *pick*
are mine, not measured against anything.

## The table

`Districts.CROSS` (scripts/world/districts.gd) has one row per district. Read it with
`Districts.cross_at(chunk)` / `walk_at` / `shoulder_at` / `kerb_h_at`, never by indexing.
`cross_at(i)` is the section at the **end** of chunk `i`; the builder tapers from
`cross_at(i-1)` to `cross_at(i)` across chunk `i`, so nothing steps at a boundary.

| district | shoulder (parking lane) | pavement | kerb | drops (car-park entrances) |
|---|---|---|---|---|
| downtown | 2.4 m | 3.6 m | 0.15 m | parking |
| residential | 2.2 m | 2.4 m | 0.13 m | parking, garage |
| strip | 1.4 m | 2.0 m | 0.10 m | every building |
| industrial | 1.4 m | 1.5 m | 0.10 m | warehouse, garage, parking |
| freeway (layout "outskirts") | 3.0 m hard shoulder | 1.2 m flat verge | none | none |
| at the crossing | 1.4 m | 2.2 m | 0.10 m | the district's |

- Everything outside the road edge (buildings, boundary walls, lamps, pylons, gap walls,
  the roadside kit) lays itself out from the edges the builder computes, so a reader of
  the table gets the right x by taking `lane_w + shoulder_at(i) + CURB_W + walk_at(i)`.
- A chunk that touches the crossing, and the one before it, hold the crossing's own
  section (`Districts.JUNCTION`), because `Junction` draws its quads at fixed widths.
- `SHOULDER_W` (1.4) and `SIDEWALK_W` (2.2) stay as the standard section; they are not
  what any district uses any more except the crossing. Code that reads them for a
  particular chunk is wrong off the crossing.

## Surfaces

The sidewalk collision is its own surface group, `"Kerb"` (it was `"Dirt"`); a freeway's
verge is `"Grass"`. `CarSpec.apply` adds both to each car's five surface dictionaries
from the car's own `"Dirt"` entry (`KERB_SURFACE` / `GRASS_SURFACE`), so no spec changes
and the vendored wheel code is untouched. Anything that only asked "not Road" (rumble,
skid marks, smoke) behaves as before.

| group | friction | tyre stiffness | rolling resistance | note |
|---|---|---|---|---|
| Road | 1.32 | 11.5 | 1.0 | coupe |
| Kerb | 0.90 | 3.0 | 1.12 | Dirt's grip, concrete rolls easier (x0.7) |
| Grass | 0.72 | 2.1 | 2.88 | x0.8 grip, x1.8 drag *pick* |

Sweep result (tools/kerb_sweep.gd, skid pad: full lock from 50 km/h, coasting, mean
lateral g over seconds 1 to 3): Road 0.75 g, Kerb 0.44 g (59 %), Grass 0.33 g (45 %).
Straight braking on the pavement is the same as on the road (the brakes, not the tyres,
are the limit), so "slippery" shows in cornering only.

## Kerb strikes

A wheel that comes onto the Kerb surface with more than 5 m/s of sideways speed (road
space, toward the kerb) bends that corner (`CarDamage.apply_kerb_strike`): a front
wheel's steering arm (the toe pull a wall hit gives), a rear wheel's spring, plus a
quarter of it as body cost. 0.045 damage per m/s over 5.

Coupe, 100 km/h, residential kerb (0.13 m): 10 degrees = no strike (2.4 m/s sideways),
20 degrees = strike at 8.7 m/s, arm 0.20 (cosmetic, under 0.25), 30 degrees = arm 0.40,
45 degrees = arm 0.66. At 130 km/h 20 degrees is 0.33, 45 degrees 0.92. No run rolled
over; worst lean was 20 degrees (130 km/h, 5 degrees). Downtown's 0.15 m kerb gives the
same strikes with a bit more roll and pitch (peak 19 and 9 degrees). Use
`tools/kerb_sweep.gd` for the whole grid and the other districts.

## Not done / open

- Yellow paint stayed at step 1's rule (crossing mouth and hydrants). No bus stops or
  no-parking runs exist to paint.
- No parked cars in the parking lanes; the lane is only wider road. The roadside kit
  owns props.
- Grass exists only as the freeway verge (flat, no geometry of its own). Nothing else
  in the world is grass.
- The oncoming side mirrors the own side exactly (same table).
- Kerb heights up to 0.15 m put the collision top at 0.20 m; the sweep shows the car
  takes it (no flips), but Roy has not driven it.
