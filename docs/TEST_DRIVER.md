# The shared test driver

One bot drives the player car for the headless tests, the benchmark, stress
runs and for watching in the game. Code: `scripts/core/test_driver.gd`. It
drives through `PlayerCar.driver`, the hook the older per-test bots already use.

Roy, 2026-10-10: "when you test you're not a good driver, you hit walls, cars
etc" and "sometimes there is a need to test those but not at all times, there
are different tests". So the driver has named modes, and every test says which
one it uses.

## Modes

| Mode | What it does | Touches things? |
|---|---|---|
| `clean` | Holds a lane at a set speed, brakes for traffic, changes lane only into a checked gap, slows for bends, recovers from a spin | No (that is the point) |
| `weave` | `clean`, plus a lane change every 4 s when a real gap is there | No |
| `grip` | `clean` at the grip limit in bends (8 m/s² instead of 4), easing the throttle when the car slides | No |
| `aim` | Steers at a point or a node and holds a speed: crashing on purpose | Yes, on purpose |
| `brake_to` | `clean`, slowing to a set speed at a set point along the road | No |
| `flee` | Full speed in whichever lane has the most free road, away from a threat's side | No |
| `fuzz` | Seeded random key presses through the real key path | Yes, whatever happens |
| `replay` | Plays recorded keys back (an F9 recording or a fuzz run's log) | Whatever the recording did |
| `hold` | Fixed pedals and wheel | Depends on the test |
| `legacy_bench` | The benchmark's old bot: full throttle, bang-bang heading hold, never brakes. `legacy_weave` = its blind 4 s lane swap | Yes, by accident |
| `legacy_lane` | The old traffic-harness lane keeper: fixed throttle under a cap, never brakes, never looks at traffic | Yes, by accident |

The eight shared behaviours behind the modes are plain methods a test can call
on their own: `steer_to` and `pedals_for` (hold a lane at a speed), `gap_free`
and `lane_pace` (lane change into a checked gap), `speed_to_reach` (brake to a
point), `steer_at` (aim at a target), `bend_speed` (grip limit), the `flee`
mode, `random_keys` (seeded), and `keys` + `replay` with
`scripts/core/drive_recorder.gd` (record and replay). `place()` puts the car on
the road at any lane, angle and speed, on bends and hills too.

## Starting it: one switch

```gdscript
const TestDriver := preload("res://scripts/core/test_driver.gd")
var bot := TestDriver.start(game, "clean", {"speed": 150})   # km/h
```

The game calls the same function, so the bot can be watched in a window or run
hidden with the same options:

| Where | How |
|---|---|
| In the game, in a window | `NeonOverdrive.exe -- --bot=clean --speed=150` (or `weave`, `grip`, `fuzz --seed=4`) |
| Headless, any shell | add `--headless`, or set `NEON_BOT=clean` and `NEON_BOT_SPEED=150` |
| Benchmark | `-- --benchmark --speed=150` (clean), `--weave=1` (weave with real gaps), `--bot=<mode>`. No option = `legacy_bench`, so old result lines still compare; `--bot=legacy_bench --weave=1` is the old blind weave |
| A test | `TestDriver.start(game, mode, opts)` |

While a bot or a replay drives, the saved run is neither resumed nor
overwritten. A small "BOT: clean at 150 km/h" label shows on screen.

After a run, `bot.summary()` and the fields `wall_contacts`, `car_contacts`,
`spins`, `lane_changes`, `refused_changes`, `max_lane_err`, `min_gap` say what
happened. The benchmark adds them to its result line.

## Record my drive (F9)

The game always keeps the last 60 s of driving keys and, every 5 s, where the
car and the road were. **F9** writes that to
`user://drives/drive_<time>.json` (next to the saves). Play it back with:

```
NeonOverdrive.exe -- --replay=last          (or --replay=<path to the file>)
```

The game boots on the recording's road with the same car, puts the car where
it was at the start of the kept stretch, and presses the same keys on the same
ticks.

Limits, so nobody trusts it too far:

- Traffic is **not** restored. A hit on a traffic car will not repeat; a hit on
  a wall, a kerb or the road usually will.
- Position, speed, gear and rpm are restored; tyre, suspension, damage and
  fuel state are not. The replay lands close, not on the same millimetre:
  1.3 m and 5.2 m apart after 6 and 8 s of random keys in
  `tests/core/drive_replay.gd` (both runs ended sliding along a wall).
- The tune is whatever is saved now, not what it was when recording.

## The tests

Quick driving set, on every PR (`tests\run_tests.bat quick` and CI):

| Test | Mode | What it proves |
|---|---|---|
| `core/drive_clean` | `clean` | 150 and 300 km/h among 24 cars with a slow car put in its lane: no wall or car contact, no spin, stays in lane. Then spin recovery and a turn-round |
| `core/drive_crash` | `aim` | Wall at 30° and square on, kerb, centre line, traffic car from behind, from the side and head-on: the hit happens and the game stays sane |
| `core/drive_fuzz` | `fuzz` | Two seeds of random keys in traffic: no engine error, no NaN, car never under the road; same seed = same keys |
| `core/drive_spawn` | `clean` + `place()` | Spawning at 0, 50, 100, 200, 300, 400 km/h: no speed jump, no spin, upright, in lane |
| `core/drive_replay` | `fuzz` then `replay` | F9's file is written, loads, and replays to within 15 m |

Long driving set, full tier only (before a big merge): `drive_clean` for 90 s
per speed among 40 cars; `core/drive_bends` (the clean run on bends and
hills); `drive_fuzz` with 8 seeds of 30 s; `drive_crash` at 60, 150, 250 and
350 km/h; `drive_spawn` on bends and hills.

The P1 coupe tops out near 250 km/h, so "300 km/h" means launched at 300 and
held as fast as the car goes.

## Which existing test uses which mode

Nothing was changed in how the older tests drive; this names what each one
already does. "inline" = the test has its own few lines of driver code.

| Mode | Tests |
|---|---|
| `legacy_lane` (via `Harness.lane_driver`, which now forwards to the shared driver) | `world/curve_drive`, `world/hill_drive`, `world/recenter_kick`, `traffic/traffic_spawn`, `traffic/traffic_stability`, `traffic/traffic_behaviour`, `traffic/traffic_perf`, `traffic/no_visible_spawn`, `fleet/player_cars`, `core/perf_probe` |
| `legacy_bench` (inline copy) | `world/chunk_drive`; the benchmark with no options |
| `hold` (inline: fixed pedals, wheel straight or fixed) | `car/wall_hit`, `car/car_damage`, `car/burnout_line_lock`, `car/fuel_limp`, `car/powertrain_health`, `car/turbo`, `car/tyres`, `car/transmission_modes`, `car/clutch_model`, `car/phase_a_engine`, `car/reverse_and_tabs`, `world/junction_lights`, `world/hill_park`, `core/save_resume`, `traffic/npc_cars`, the `audio/*`, `fx/*`, `view/*` and `ui/*` tests that move the car |
| inline lane keeper with scripted phases | `car/car_scrape` and its three variants |
| real key events | `core/smoke`, `world/floating_origin_drive`, `car/feel_pass_1`, `core/tick_rate_120`, `tuning/tuner_safety_net` |
| TuneTrack's own driver (its own flat track, not the road) | `tuning/tune_track`, `tuner_settings`, `tuner_presets`, `auto_tune_*`, `car/tyre_model`, `car/chassis_targets`, `car/forced_induction`, `tools/balance_sweep` |
| `clean`, `aim`, `fuzz`, `replay` | the `core/drive_*` tests above |

Tests that hit things on purpose and must keep doing so: `car/wall_hit`,
`car/car_damage`, `audio/sound_fixes`, `audio/crash_variety` (walls) and
`traffic/traffic_stability` phase 2 (rear-ends traffic). None of them was
touched.

## Cost

Only the steering runs every physics tick (the same pure pursuit each traffic
car runs). Traffic, bends ahead and spin checks run 20 times a second and are
cached. Contact watching reads a counter and only lists contacts while
something is touching. Measured on Roy's laptop at 120 Hz, 24 traffic cars,
with the laptop at 100% CPU from other sessions: `clean` about 0.23 ms per
tick, the same as the old harness lane keeper (0.20 to 0.38 ms in the same
runs); `fuzz` and `legacy_bench` about 0.1 ms. The recorder is one array write
per tick and one snapshot every 5 s.
