# Car ladder sweep, slice 1 (2026-10-09)

Stage G, first slice: one headless command that drives every car with physics
data round the hidden test track across setup presets, driver skill and
assists, and prints the tables below. Then the CarSpec data was tuned so the
ladder reads clearly. The vendored GEVP addon is untouched.

Run it:

```
tools\balance_sweep.bat          whole grid, 144 runs, about 8 minutes
tools\balance_sweep.bat quick    Stock / pro / assists on, about 20 seconds
```

`tools/balance_sweep.gd` explains every column. Numbers come from
`TuneTrack` at 60 Hz, the same runs `tests/chassis_targets.gd` guards.

## What exists to balance

Only four cars have physics data today: the P1 coupe (`CarSpec.coupe_default`)
and the three traffic cars (`CarSpec.npc_spec`, N1 commuter, N2 city hatch, N3
pickup), plus the generic `traffic_default` fallback. P2 to P6 and the police
cars are design sheets and audio presets only; their specs land with the
stage D thread (PR #253 and its follow-up). There was no worn starter car and
no Bug-style beater, so this slice adds the worn starter as data
(`CarSpec.coupe_worn`, the "P1 as found" option A from
`docs/planning/rival-and-car-ladder-proposal-2026-10-07.md`, which Roy has not
signed off; it is a measured proposal, not a shipped car) and leaves the beater
for a design pass.

There is no rival AI or driver-skill model in the game yet. "Driver skill"
here is the track's scripted driver with weaker limits (later upshift, less
throttle, less brake), to show how much of a car a novice reaches. There is no
lap circuit either, so "lap" is a synthetic test lap: standing 400 m, two
100-0 stops and four 50 m-radius corners at the car's peak lateral g. It ranks
cars; it is not a time anyone will see in the game.

## Ladder before (main 282343f) and after this PR

Stock setup, pro driver, assists on. Before: the worn coupe did not exist, so
its "before" row is the first draft of the data.

| Car | 0-100 s before | after | Top km/h before | after | 100-0 m before | after | Peak g before | after |
|---|---|---|---|---|---|---|---|---|
| P1 coupe, as found (starter, new) | 8.88 | 9.07 | 200.6 | 194.6 | 62.1 | 55.5 | 1.04 | 1.01 |
| N2 city hatch (traffic) | 11.78 | 11.78 | 169.5 | 169.5 | 50.6 | 50.6 | 0.77 | 0.77 |
| N1 commuter (traffic) | 10.70 | 10.70 | 180.8 | 180.8 | 49.5 | 49.5 | 0.75 | 0.75 |
| N3 pickup (traffic) | 10.35 | 10.90 | 163.8 | 163.7 | 50.4 | 62.8 | 1.20 | spin (0.89 g before the spin) |
| generic traffic (fallback) | 19.52 | 19.52 | 132.1 | 132.1 | 49.2 | 49.2 | 1.01 | 1.01 |
| P1 coupe, stock | 5.60 | 5.60 | 244.1 | 244.1 | 42.7 | 42.7 | 1.30 | 1.30 |

## Data changes

- **New `CarSpec.coupe_worn()`**: 290 Nm (was 460) and a 5800 rpm limit (7000),
  a lazier torque curve and throttle, hard old tyres (road grip 1.0, stiffness
  7), glazed brakes (multiplier 2.1 of 2.5), one pop-up stuck open (drag 0.33
  of 0.26), tired dampers, half the downforce. Every one of these is a stock
  coupe value once restored, so restoring the car in Act 1 is a walk back to
  `coupe_default()`.
- **N3 pickup**: road grip 0.78 (was the coupe's 1.2 via `traffic_default`,
  which is 1.0; the pickup inherited 1.0 and still cornered at 1.20 g on its
  265 mm tyres), and the centre of gravity raised by 0.15 m (was 0.0, the
  coupe is -0.07). Grip of 0.66 read 0.71 g but 75 m braking and a spin at the
  limit, so 0.78 is the compromise: about 0.9 g, 100-0 near 63 m. On the
  corner run (held steering, speed ramping under power) the truck's rear lets
  go at about 55 degrees of slide, so its g shows as "-" in the tables. It did
  that before this pass too (43 degrees at 1.20 g); a stiff front bar and rear
  toe-in did not cure it, so that is left for the traffic thread.
- N1, N2, `traffic_default` and the coupe: unchanged. The commuters already
  read like commuters (10.7 to 11.8 s, 170 to 180 km/h, 0.75 g understeer).
  `traffic_default` is slow (19.5 s, 132 km/h) because it keeps the coupe's
  tall gearing with 170 Nm, but `traffic_car.gd`'s pedal map was measured on
  it, so it stays until that map is re-measured.

## Findings for Roy (not changed here)

1. **The engine light comes on 2 to 7 s into any flat-out pull, on every car.**
   `PowertrainHealth` is constants only (`Q_LOAD` 450, tau 35 s); full load
   from a standing start reaches 100 C in about 4 s, derate in 5 to 8 s. The
   sweep replays the game's own model, so this is what the game does today.
   Either the constants are too hot or the warning is meant to be that
   frequent; it is a feel call, and per-car heat (a cooling budget on CarSpec)
   would make the ladder read in the heat column too.
2. **The brakes never warn.** One 100-0 stop lifts the discs about 100 to
   150 C and the next launch cools them; 30 back-to-back stops never reach the
   300 C light. Brake heat only matters on long downhill or repeated high-speed
   stops, neither of which the track has.
3. **Assists on or off makes no difference in a straight line** for any car
   (traction control at the stock slip of 8 never intervenes at launch), and
   only the pickup and the worn coupe change in the corner. The pickup spins
   with stability off.
4. **Presets are coupe-centric**: the tyre compound choices are absolute
   values, so Street / Grip / Drift on a traffic car hand it coupe tyres and
   its lateral g jumps. Only the coupe rows of the preset table mean what they
   say. A stage E item: compounds as offsets from the car's stock tyre.
5. The novice driver (shift at 80 %, 85 % throttle) is 3 to 5 s slower to
   100 than the pro on every car, and 30 % longer stopping. That is the room a
   "rivals do not rubber-band" ladder has to fit inside.
6. `tests/tuner_test_run.gd` fails on main 282343f as well as on this branch
   ("the second test run should show the pit-wall result"), run alone on a
   clean checkout. Pre-existing, not from this change.

## Full tables (after)

Grid: 6 cars x 4 presets x 3 skills x 2 assists = 144 runs, 527 s, 0 problems. Format of the multi-value cells is in each heading.

### Car ladder (Stock, pro driver, assists on)
| Car | 0-100 s | 400 m s | Top km/h | Lap s | 100-0 m | Peak g | ENG light after | BRK light after | ok |
|---|---|---|---|---|---|---|---|---|---|
| P1 coupe, as found (starter) | 9.07 | 16.58 | 194.6 | 38.7 | 55.5 | 1.01 | 4 s | >30 stops | yes |
| N2 city hatch (traffic) | 11.78 | 18.22 | 169.5 | 41.7 | 50.6 | 0.77 | 4 s | >30 stops | yes |
| N1 commuter (traffic) | 10.70 | 17.57 | 180.8 | 41.1 | 49.5 | 0.75 | 4 s | >30 stops | yes |
| N3 pickup (traffic) | 10.90 | 18.02 | 163.7 | - | 62.8 | - | 2 s | >30 stops | yes |
| generic traffic (traffic_default) | 19.52 | 22.05 | 132.1 | 43.2 | 49.2 | 1.01 | 7 s | >30 stops | yes |
| P1 coupe, stock | 5.60 | 13.45 | 244.1 | 31.9 | 42.7 | 1.30 | 4 s | >30 stops | yes |
### Presets (pro driver, assists on): 0-100 s / top km/h / lap s / peak g / max slip deg
| Car | Stock | Street | Grip | Drift |
|---|---|---|---|---|
| P1 coupe, as found (starter) | 9.07 / 195 / 38.7 / 1.01 / 18 | 9.05 / 195 / - / - / 61 | 9.55 / 192 / 36.8 / 1.21 / 13 | 8.98 / 196 / - / - / 57 |
| N2 city hatch (traffic) | 11.78 / 170 / 41.7 / 0.77 / 6 | 11.77 / 170 / 41.7 / 0.77 / 6 | 12.00 / 167 / 40.0 / 0.89 / 6 | 11.75 / 170 / 41.2 / 0.81 / 7 |
| N1 commuter (traffic) | 10.70 / 181 / 41.1 / 0.75 / 6 | 10.63 / 181 / 41.1 / 0.75 / 5 | 10.92 / 178 / 39.5 / 0.85 / 6 | 10.65 / 181 / 40.6 / 0.80 / 6 |
| N3 pickup (traffic) | 10.90 / 164 / - / - / 54 | 10.42 / 166 / 37.6 / 1.16 / 39 | 10.48 / 166 / - / - / 46 | 10.28 / 168 / - / - / 49 |
| generic traffic (traffic_default) | 19.52 / 132 / 43.2 / 1.01 / 11 | 19.57 / 132 / 43.3 / 1.00 / 10 | 19.93 / 129 / 42.5 / 1.01 / 8 | 19.30 / 134 / 43.7 / 0.92 / 10 |
| P1 coupe, stock | 5.60 / 244 / 31.9 / 1.30 / 11 | 5.83 / 244 / 32.8 / 1.28 / 12 | 5.65 / 228 / 30.3 / 1.52 / 12 | 5.62 / 244 / 31.6 / 1.36 / 31 |
### Driver skill x assists (Stock): 0-100 s / lap s / 100-0 m / max slip deg
| Car | novice, assists on | novice, assists off | average, assists on | average, assists off | pro, assists on | pro, assists off |
|---|---|---|---|---|---|---|
| P1 coupe, as found (starter) | 12.68 / 44.1 / 75.7 / 18 | 12.68 / 44.1 / 75.7 / 18 | 9.52 / 39.9 / 62.4 / 21 | 9.52 / 39.9 / 62.4 / 21 | 9.07 / 38.7 / 55.5 / 18 | 9.07 / 38.7 / 55.5 / 18 |
| N2 city hatch (traffic) | 15.22 / 46.8 / 67.7 / 6 | 15.22 / 46.8 / 67.7 / 6 | 11.33 / 42.1 / 55.6 / 6 | 11.33 / 42.1 / 55.6 / 6 | 11.78 / 41.7 / 50.6 / 6 | 11.78 / 41.7 / 50.6 / 6 |
| N1 commuter (traffic) | 14.22 / 46.0 / 67.5 / 6 | 14.22 / 46.0 / 67.5 / 6 | 10.53 / 42.0 / 54.6 / 6 | 10.53 / 42.0 / 54.6 / 6 | 10.70 / 41.1 / 49.5 / 6 | 10.70 / 41.1 / 49.5 / 6 |
| N3 pickup (traffic) | 14.28 / 46.1 / 82.7 / 43 | 14.28 / - / 82.2 / 180 | 10.95 / - / 68.9 / 54 | 10.95 / - / 69.0 / 174 | 10.90 / - / 62.8 / 54 | 10.90 / - / 63.5 / 164 |
| generic traffic (traffic_default) | 24.60 / 49.0 / 65.4 / 11 | 24.60 / 49.0 / 65.4 / 11 | 17.75 / 43.8 / 53.9 / 11 | 17.75 / 43.8 / 53.9 / 11 | 19.52 / 43.2 / 49.2 / 11 | 19.52 / 43.2 / 49.2 / 11 |
| P1 coupe, stock | 7.37 / 35.9 / 56.0 / 13 | 7.37 / 35.9 / 56.0 / 14 | 5.70 / 32.2 / 45.9 / 11 | 5.70 / 32.2 / 45.9 / 11 | 5.60 / 31.9 / 42.7 / 11 | 5.60 / 31.9 / 42.4 / 11 |
### Heat (Stock, pro driver, assists on)
| Car | ENG light after flat out | ENG derate after | Brake temp after one 100-0 | BRK light after | Brake fade after |
|---|---|---|---|---|---|
| P1 coupe, as found (starter) | 4 s | 5 s | 106 C | >30 stops | >30 stops |
| N2 city hatch (traffic) | 4 s | 7 s | 98 C | >30 stops | >30 stops |
| N1 commuter (traffic) | 4 s | 7 s | 117 C | >30 stops | >30 stops |
| N3 pickup (traffic) | 2 s | 5 s | 148 C | >30 stops | >30 stops |
| generic traffic (traffic_default) | 7 s | 8 s | 107 C | >30 stops | >30 stops |
| P1 coupe, stock | 4 s | 7 s | 115 C | >30 stops | >30 stops |
144 runs, 0 with problems
