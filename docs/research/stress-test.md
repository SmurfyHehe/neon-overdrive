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
