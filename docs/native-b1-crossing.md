# Native B1: engine-call cost per car per tick (2026-10-11)

Question: if the car sim moves to C++, what do the physics-engine calls alone
cost per full-sim car per physics tick, before any sim maths?

Tool: `CrossingBench` (C++, `native/neon_sim`) driven by `tools/crossing_bench.gd`;
matrix runner `tools/crossing-bench-matrix.ps1`. Per car per tick it checks the
body is alive, reads transform + linear + angular velocity, casts 4 wheel rays,
applies one central force and one torque (0.001). Phases of 1 s alternate off /
A / B / C inside one run, so every phase sees the same cars and machine load.

- A: direct body state + `intersect_ray` on the space (parameters object reused)
- B: direct body state + the wheels' own `RayCast3D` (`force_raycast_update`)
- C: `body_get_state` x3 + `intersect_ray`

Setup: headless, `--fixed-fps 60`, 120 Hz physics, `--detail=300`, all cars in
the sim (`physics_distance` 1000), 30 s measured after an 8 s warm-up, 3 rounds,
medians. GDScript tyres (as the game runs today). Debug = the 4.7.2 editor
binary + debug DLL, release = the 4.7.2 release template + release DLL.
godot-cpp 10.0.0-stable (507ed9d), `api_version=4.7`.

## Result: floor per car per tick (ms)

| build / physics / cars in sim | A space ray | B RayCast3D | C get_state | us per ray A / B |
|---|---|---|---|---|
| debug Godot ~23 | 0.0306 | 0.0203 | 0.0299 | 7.2 / 4.7 |
| debug Godot ~45 | 0.0322 | 0.0203 | 0.0305 | 7.6 / 4.7 |
| debug Jolt ~23 | 0.0190 | 0.0099 | 0.0191 | 4.2 / 1.9 |
| debug Jolt ~45 | 0.0153 | 0.0083 | 0.0154 | 3.4 / 1.7 |
| release Godot ~23 | 0.0364 | 0.0221 | 0.0320 | 8.5 / 5.0 |
| release Godot ~44 | 0.0277 | 0.0178 | 0.0305 | 6.6 / 4.1 |
| release Jolt ~24 | 0.0234 | 0.0105 | 0.0238 | 5.1 / 2.0 |
| release Jolt ~42 | 0.0222 | 0.0127 | 0.0255 | 4.8 / 2.4 |

All 24 runs: A between 0.013 and 0.048 ms (median 0.028), B between 0.007 and
0.024 ms (median 0.016). The 0.048 outlier ran with 4 other Godot processes
on the laptop.

Where it goes (median, A): resolve 0.5 us, state 1.0 us, 4 rays 25.7 us,
force + torque 0.6 us. The rays are the cost: about 6 us per `intersect_ray`
(Dictionary result, 3 setter calls), 3 us per RayCast3D read.

For scale (same runs): the GDScript tick today is 0.20-0.35 ms per full-sim car,
and the engine step is 0.023-0.041 ms per full-sim car (an upper bound: it also
holds the player and the world).

## Verdict

GO for the full port: floor <= 0.05 ms at every setting (median max 0.036).
B2 should read the wheels' RayCast3D natively (about 40 % cheaper than space
queries on Godot Physics, about 55 % on Jolt) unless it needs the ray result
without the node. Jolt is cheaper than Godot Physics for ray work.

## Caveats

- Through GDExtension, `intersect_ray` goes through a `Dictionary`; a module
  inside the engine would not. The floor from a GDExtension is what a ported
  sim gets.
- The laptop was shared with other agents' Godots (`others` column in the raw
  files); numbers are noisy at the 0.01 ms level.
- The off/A/B script-time difference is too noisy to use as a cross-check
  (+-0.05 ms per car); the self-timed sections are the number.
