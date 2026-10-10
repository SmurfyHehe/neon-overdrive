# What the area signs cost (PR #381), measured 2026-10-10

Tool: `tools/sign_cost_bench.gd` (run by `tools/sign-cost-runs.ps1`, summed up by
`tools/sign_cost_summary.py`). Night, chase view, no traffic, straight flat road,
road metres 0 to 1000 at 40 m/s with `--fixed-fps 60` (1734 frames, 20 chunk
rebuilds in every run). Six runs per variant, interleaved in both orders. Raw
result lines are in `data/`.

"Signs" here: area gantry and advance sign, painted road words and arrows, the
street blades and STOP paint at the crossing, and the lettering atlas. Shop
signs are older and stay on in every variant.

| NEON_SIGNS | draw calls (mean / max) | objects (mean) | primitives (mean) | sign work per chunk rebuild |
|---|---|---|---|---|
| off | 237.6 / 254 | 430.1 | 38551 | 0 |
| asis (PR as first built) | +4.4 / +8 | +4.4 | +109 | 0.094 ms (0.18 ms on a chunk with a sign) |
| hide | +3.6 / +9 | +3.6 | +109 | 0.103 ms |
| near | +2.5 / +5 | +2.5 | +90 | not measured alone |
| flat | +4.3 / +7 | +4.3 | +109 | not measured alone |
| cache | not driven alone | | | 0.080 ms (0.115 ms on a chunk with a sign) |
| hide,cache,near (now the default) | +2.1 / +3 | +2.1 | +89 | 0.076 ms (0.114 ms on a chunk with a sign) |

A whole chunk rebuild is about 4.5 ms in the same bench, so the signs are about
2% of it. The lettering atlas takes 38 to 66 ms once at boot (21 layers); the
road font loads in about 8 ms.

Frame times did not separate from the noise. Median per-run delta against
"off", with the lowest and highest run:

| | windowed asis | windowed hide,cache,near | headless asis | headless hide,cache,near |
|---|---|---|---|---|
| script process, ms | -0.11 (-0.55..+0.26) | -0.38 (-0.94..+0.26) | -0.04 (-0.23..+0.13) | -0.03 (-0.22..+0.25) |
| physics, ms | -0.25 (-0.75..+0.20) | -0.41 (-1.48..+0.24) | -0.06 (-0.23..+0.11) | -0.08 (-0.22..+0.30) |
| render thread CPU, ms | 0.00 (-0.29..+0.17) | -0.11 (-0.44..+0.16) | | |
| GPU, ms | +0.07 (+0.01..+0.09) | +0.05 (-0.30..+0.10) | | |

So per frame the signs cost less than this laptop can show (under about
0.2 ms of CPU); the counts are the numbers to trust. The counts differ a
little between runs of one variant (0.2 of a draw call on the mean), and one
"hide" run had a stray frame with 4680 more primitives.

The Performance monitors TIME_PROCESS / TIME_PHYSICS_PROCESS only change once a
second and hold that second's slowest frame, so the bench times the script step
itself with a first and a last node.

"flat" (unshaded road paint) gave no GPU saving that could be measured and makes
the paint ignore headlights and lamps, so it is not in the default.

`before/` is "asis", `after/` is "hide,cache,near", same camera spots.