# Stress test and optimisation notes (2026-10-09)

## Run it

    powershell -File tools/bench-sweep.ps1                       # quick set, 6 configs
    powershell -File tools/bench-sweep.ps1 -Set full -Secs 60 -Repeat 3
    powershell -File tools/bench-sweep.ps1 -Set custom -Custom "--traffic=80 --hills=1","--scale=0.75"

Real renderer, a window opens per run. Same seed and road every run. Options
are listed at the top of `scripts/benchmark.gd`. Tables land in `bench-results/`.
Run it with nothing else busy: other Godot/agent processes on the laptop swing
fps by 2-3x (see below). `tests/synth_perf.gd` times the engine synth and
prints a fingerprint that must not change when the loop is optimised.

Not covered yet: cops (Stage F not built) and quality presets (#232 not on this
base; render scale, MSAA and mirror quality stand in for them).

## What the profiling showed (i5-1235U, integrated graphics)

- Traffic dominates. 0 cars ran 73 fps, 16 cars 24-45 fps, 40 cars 15 fps.
  A full-sim car costs about 340 us per physics tick in the vendored GEVP
  vehicle (left unmodified), 73 us in its lane controller, 47 us in the
  drafting model. A frozen far car costs about 46 us per tick.
- GPU time at the default 1152x648 window is about 4.8 ms, but 11.3 ms at
  1920x1080, so the default window hides GPU cost. Render scale 0.75 cut it
  to 3.4 ms at the small window.
- Engine sound synth is about 3-4 us per sample in script (a worker thread).
  Keeping its state in locals gives ~7%, output bit-identical (fingerprint
  2646253550 before and after).

## Caveat on the numbers

The 2026-10-09 sweep ran while other agents kept the CPU near 87%. Every row
hit ~13 fps 1% lows, and scale 0.5 even read slower than 1.0, so frame-rate
comparisons from that sweep are not trustworthy. The GPU ms column and the
per-car microsecond costs are the usable numbers. Re-run on a quiet machine.

## Options that change behaviour (need a decision)

- Physics at 60 Hz instead of 120 Hz roughly halves traffic cost.
- `detail_distance` 150 m to ~100 m freezes more far cars.
- Engine synth at a lower sample rate cuts its cost but changes the sound.

## Graphics tiers (2026-10-09)

Low / Medium / High (`GraphicsSettings`, pause menu > Graphics) set the GPU
side (edge smoothing, render scale) and the CPU side (traffic car count,
traffic sim/draw distance, cockpit mirror render size), because traffic is
most of the frame on this laptop.

| Tier | AA | Scale | Cars | Sim distance | Mirrors |
|---|---|---|---|---|---|
| Low | MSAA 2x | 0.75 | 10 | 100 m | low (half size) |
| Medium | MSAA 2x | 1.0 | 16 | 150 m | medium |
| High | MSAA 4x | 1.0 | 25 | 200 m | high (double) |

- **First launch** (no preset saved): the game starts at Medium, skips 2 s,
  then times 3 s with V-sync off. Median frame under 50 fps picks Low, over
  100 picks High (`GraphicsAutoPick`). The menu shows it was automatic.
- **Dynamic resolution** (on by default, `DynamicResolution`): GPU time over
  90% of the frame budget for 2 s drops the render scale 0.1 (floor 0.66, or
  0.5 from Low's 0.75); it climbs back when the predicted GPU time at the
  higher scale is under 75% of budget for 5 s. It reads GPU time, so when
  the CPU is the slow side it leaves the picture alone.
- **Frame cap**: V-sync or 30 fps.
- Measure: `powershell -File tools/bench-sweep.ps1 -Set tiers`.
- Not in any tier (behaviour changes, Roy's call): physics at 60 Hz instead
  of 120 Hz, a lower engine-synth sample rate.
