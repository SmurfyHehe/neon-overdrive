# Native B2: the wheels in C++ (2026-10-11)

Step 1 of moving the car physics to C++. `CarSim` (C++, `native/neon_sim`) does
the per-wheel half of a GEVP tick in one call per car: ray cast, surface
lookup, suspension, tyres, and the four wheels' pushes summed to one force and
one torque. Off by default (`neon/sim/native`, or `NEON_SIM_NATIVE=1`). The
vendored GDScript is the reference and the fallback.

## Same driving?

`powershell -File tools/sim-golden.ps1 -Repeat`: four cars (Bug, coupe, a
traffic car's spec, a cop's spec), 20 s each at 120 Hz over a flat launch, a
hill, a kerb at an angle, a bend, a hard stop and a handbrake turn; every tick
logged on both paths.

| car | ticks | position, speed | gear | wheel contacts | first tick that differs |
|---|---|---|---|---|---|
| bug | 2400 | 0 | same | same | none |
| coupe | 2400 | 0 | same | same | none |
| traffic | 2400 | 0 | same | same | none |
| cop | 2400 | 0 | same | same | none |

The two CSV files are byte for byte the same (14 decimals per number), and so
are two GDScript recordings of each other. The cars are sim-only `PlayerCar`s
on each kind's CarSpec, so "traffic" and "cop" are those cars' physics data
without the lane-keeping AI; the real traffic cars are covered by
`traffic_stability` and `npc_cars` below.

Why it is exact, not just close: doubles for scalars and 32-bit vectors in the
same places as GDScript, the same order of operations, and `asin` / `pow`
called through the engine so both paths use one implementation.

## Tests, both paths

Each test once plain and once with `NEON_SIM_NATIVE=1`, flags and environment
as `tests/run_tests.bat` sets them. "same" = the two runs' output is identical
line for line (times aside).

| test | GDScript | C++ | output |
|---|---|---|---|
| car/tyres | PASS | PASS | same |
| car/tyre_model | PASS | PASS | same |
| car/chassis_targets | PASS | PASS | same |
| car/feel_pass_1 | PASS | PASS | same |
| car/kerb_strike | PASS | PASS | same |
| core/tick_rate_120 | PASS | PASS | same |
| traffic/traffic_stability | PASS | PASS | same |
| car/wall_hit | FAIL | FAIL | same |
| car/gearbox_per_car | FAIL | FAIL | same error |
| core/drive_clean | FAIL | FAIL | same |
| core/drive_bends | FAIL | FAIL | same |
| traffic/npc_cars | FAIL | FAIL | same |
| core/smoke, DLL renamed away, switch on | | PASS | one warning, GDScript used |
| core/smoke, switch on | | PASS | |

The five failures fail the same way on the base without this change (a plain
export of the B0 branch, run in a scratch folder):

- `wall_hit`: 5 failures ("never reached the wall" at 55 m/s). On the known-flaky list.
- `gearbox_per_car`: script error, its `GEARS` table has no `p17_work_pickup`; the test then hangs until the timeout.
- `drive_clean`: "spin: hit a wall recovering".
- `drive_bends` (DRIVE_SECS=90, DRIVE_CARS=40): 6 failures (impact counts at 300 km/h, the spin).
- `npc_cars`: `p0_beater/stock` is over the triangle budget and has 6 flare vertices. A model check, not physics; every drive number matches on both paths.

## Cost

`tools/gevp-tick-matrix.ps1 -Tyres gd,sim -Cars 22 -Physics godot -Rounds 3 -Secs 12`
(Godot Physics, 120 Hz, headless; 22 traffic cars spawned, 11 to 13 of them in
the full sim when measured). The laptop was shared with 0 to 6 other Godot
processes, and whole runs differ by up to 2x from that, so the number to trust
is the same-cars A/B: `Vehicle.process_forces()` timed on the same cars in the
same process, bridge on then off, 60 passes.

| build | GDScript wheels, ms per car per tick | C++ wheels | saved |
|---|---|---|---|
| debug (editor binary) | 0.034 / 0.036 / 0.037 | 0.023 / 0.025 / 0.025 | about 0.011 ms, 32 % |
| release template | 0.032 / 0.027 / 0.083 | 0.021 / 0.018 / 0.049 | about 0.010 ms, 35 % |

(three rounds each; the third release round ran beside 6 other Godots.)

For scale, the whole GDScript tick of a full-sim car was 0.11 ms in the quiet
runs (0.19 to 0.28 ms in the busy ones), so this step takes about a tenth off a
car's tick. What is left in the C++ wheel call: the four ray casts (about
0.009 ms, 2.2 us each through the wheels' own RayCast3D, as B1 measured) and
handing the wheels' numbers across and back every tick (44 in, 32 out per
wheel). The maths itself is now small.

The hand-over is the price of leaving every number on the Wheel nodes in this
step (damage, tyre wear, the tuner and the world recentring all write to
them). It goes away when the vehicle level moves to C++ and the state lives
there; the rays stay.

## Not done here

- The quick and full test suites were not run on the laptop (one Godot at a
  time, named tests only). CI runs the quick suite.
- Jolt was not measured (B1 found its rays about half the cost).
- 22 cars all in the full sim at once was not reached: the manager only keeps
  cars within the detail distance in the sim, 11 to 13 at the moment measured.
