# Lamp-post life (living world step 2, 2026-10-10)

Four small things that make a lamp-lit street look inhabited. Rule for all of
them: on or over the road, in a lamp pool or in the headlights, never on wires.

| Item | What | Where in the code |
|---|---|---|
| A4 | Moths swirl under the head of about half the lamps; on half of those a bat crosses the pool every 14 to 34 s | `LampMoths`, one swarm instance per lamp |
| A6 | Banner on every third lamp post, flaps in the wind, district colour and emblem | `LampBanners` |
| A2 | Steam from a manhole (70%, in a lane) or a gutter drain (30%), in a lamp pool, about 4 per 16-chunk district | `SteamVents` + `VentCovers` |
| A5 | Newspaper and leaves tumble across the road in gusts, one gust every 17 to 32 s per chunk | `WindLitter`, one instance per chunk |

All code is in `scripts/world/lamp_life.gd`. The chunk builder only calls
`create_nodes` once per pooled chunk and `apply` on every rebuild.

## Banners (Amber vs Dusk, no magenta or cyan)

| District | Field | Emblem |
|---|---|---|
| downtown | dusk navy | silver diamond |
| residential | amber | navy ring |
| strip | charcoal | sodium orange chevrons |
| industrial | silver | navy bars |

## Wind

One number: `LampLife.wind()` / `LampLife.set_wind(w)`, 0 still, 1 steady
breeze, 2 gale, default 0.6. It sways the banners, leans the steam and sets
how long and how hard the litter gusts blow (no gust at 0). The wind blows
across the road, from the player's side. A weather system sets it later.

## Cost

- No per-frame script work: motion is in vertex shaders (TIME, per-instance
  custom data, one `wind` uniform). The litter is not the "0.02 ms" the brief
  allowed; it is zero per frame, because it is chunk-local and shader-driven.
- Triangles: 302 per 50 m chunk at the caps (4 swarms, 4 banners, 1 vent, 1
  litter set); test budget 600.
- Draw calls: +5 draw-call candidates per chunk, all with a draw range
  (moths 85 m, banners 110 m, steam and covers 90 m, litter 70 m). Measured
  +9 to +11 draws at 16 cars, +4 to +11 at 80 cars (below).
- Chunk rebuild: +0.3 to 0.5 ms (about 4.5%) once per 50 m of driving,
  `tools/lamp_life_cost.gd` (interleaved on/off, median of 6 rounds).

### Benchmark, interleaved off / on / off / on, 30 s each

The laptop was running other sessions' tests the whole time (every run
15 to 21 fps, the 80-car runs stuck at the 66.7 ms physics catch-up cap), so
fps and script ms say nothing about this change. Draw calls and GPU ms are the
usable columns.

| Cars | Lamp life | Draws avg | GPU ms | Render CPU ms |
|---|---|---|---|---|
| 16 | off (2 runs) | 391, 393 | 3.58, 3.70 | 2.34, 2.02 |
| 16 | on (2 runs) | 400, 401 | 3.71, 4.56 | 2.02, 2.44 |
| 80 (hills, curves, weave, 300 m) | off (2 runs) | 579, 579 | 5.62, 5.10 | 2.83, 3.26 |
| 80 (hills, curves, weave, 300 m) | on (2 runs) | 583, 590 | 5.01, 5.32 | 3.06, 2.81 |

## Shots

Street view from the chase height, same chunks in the same process, nodes
hidden then shown: `<district>_street_before.png` / `_street_after.png`.
Close-ups (after): `_steam`, `_banner`, `_moths`, `_bat` (held mid-flight),
`_litter` (held mid-gust). Made by `tools/lamp_life_shots.gd`.

## Known gaps

- Flickering and dead lamps (PR #257) are not on main: the moths pick lamps by
  a stable roll, not by lamp state. When #257 lands, only lit lamps should get
  a swarm.
- Steam is a fixed lit amber, not lit by the player's headlights.
- Shader `TIME` wraps once an hour, so moths and banners jump once then.
- Banners are not on junction signal masts; the emblems are placeholders.
- Vent offsets use the pole-to-road distance from the chunk builder
  (`POLE_TO_ROAD`); the kerbs PR (#352) may move the kerb by a few cm.
