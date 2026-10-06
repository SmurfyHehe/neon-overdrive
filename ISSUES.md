# Neon Overdrive — Issue List

Audit 2026-09-29, refreshed 2026-10-06 against `origin/main` at `ea71c13` and
`gh issue list --state all`.

**GitHub issues are the live list.** This file keeps the audit's letter IDs
(A1, E7, ...) so older PRs and comments still make sense, and maps each one to
its GitHub issue. For the order to work in, see the triage issue #59 (its text is
frozen at 2026-09-29 and out of date; it is still open).

**Recommend closing (Roy decides; nothing was closed from here):** #18, #55 and
#73 are done in code but still open on GitHub. Evidence is in the Closed table.

---

## Open

| # | Issue | GitHub | Note |
|---|---|---|---|
| C3 | No out-of-bounds handling | #28 | D5 merged into it |
| D5 | `is_off_road()` defined, never called | #28 | Roy: keep it as a scoring hook |
| C6 | Camera had no smoothing | #31 | PR #61 added 3 modes (C key); Roy tunes later |
| E6 | No curves or elevation | #37 | Acknowledged; needs the Path3D rearchitecture |
| E7 | Gear spread is the wrong shape | #62 (closed on GitHub 2026-09-29) | E7–E9 merged into #62. Gearing was evened in `764b3f0` (steps now about 1.3), but no test asserts the spread, so not closed |
| E8 | Torque curve falls off too hard | #62 | Torque shape is now tunable (Auto-Tune 1b, `f5f9361`); Roy's tune not recorded |
| E9 | Top gear set for 230 km/h, target ~200 | #62 | GEVP cuts at 1.1 × `max_rpm`, so the ceiling is ~253. The damp-0.1 cap at 124 km/h is fixed (`8cf2c89`, PR #89): 241.6 km/h at 35 s. `chassis_targets` now asserts 235–250 km/h; Roy likes ~300 through tuning, so the ~200 target is stale |
| G3 | Car model shape needs Roy's direction | #16 | The test car (#63) is closed; the 12-car design sheet is merged (#85, #86) but no game models are built from it |
| G4 | Player car has no self-lit elements | #17 | |

### Filed after the audit

| GitHub | Issue |
|---|---|
| #62 | **Closed on GitHub 2026-09-29** (it was listed open here). Gearing & power: sliders (PR #69, merged), Auto-Tune (#88, #90, #100, merged); Roy's final tune is still not recorded, and the upgrade tree is #70–#74 |
| #70 | Upgrade tree: stop at 200 km/h with a gear limit or a weaker engine? Conflicts with the 235–250 km/h stock target (`chassis_targets`) and Roy's ~300 km/h tuned goal, so it needs a decision or a rewrite |
| #71 | Upgrade tree: one tree for every car, or one per car? (ROADMAP records Roy's decision: one per car; issue not closed here) |
| #72 | Upgrade tree: can the player respec? |
| #74 | Upgrade tree: do tiers cap which races you can enter? |
| #80 | Engine sound changes with the car, engine and upgrades |

#70, #71, #72 and #74 are design questions for Roy about the upgrade tree in #62. #80 is Roy's request for engine sound that
changes with the car and its upgrades; the engine, driveline and turbo sounds exist (`093b3ef`, `8890350`, `65a4303`), but not per-car or per-upgrade, so it stays open.

---

## Closed

| # | Issue | Closed by |
|---|---|---|
| A1 | ROADMAP said night lighting was unapproved though built | PR #2 |
| A2 | Nothing pushed, `origin/main` gone | pushed; `origin/main` live |
| A3 | `.claude/` untracked and unignored | `5cccba1` |
| A4 | No staging convention between agents | `5cccba1` (`CLAUDE.md`) |
| A5 | Pixel's task stalled; F1, F3, F4 never landed | PR #44 |
| A6 | Two agents fixed the same bug (#21) | `CLAUDE.md` rules (PR #5) + check-in-flight dispatch |
| A7 | An agent reset the shared root checkout (#22) | `CLAUDE.md` rules (PR #5) + check-in-flight dispatch |
| B1 | No MultiMesh anywhere | `01a84cb` |
| B2 | `_box()` allocated duplicate `BoxMesh` per dash/pylon | `01a84cb` |
| B3 | Three materials bypassed the file's own cache | `01a84cb` |
| B4 | "Recycling" only reused the chunk root | `01a84cb` |
| B5 | `CULL_DISABLED` on the asphalt/strip material (#23) | PR #54 |
| B6 | Drafting was O(n²) per physics frame (#24) | PR #51 |
| B7 | Headroom unmeasurable (#19) | PR #49 (benchmark mode) |
| B8 | Glow never enabled, cost unmeasured (#25) | PR #67 (tight glow) |
| C1 | No floating origin (#26) | PR #58 |
| C2 | No pause, restart, quit (#27) | PR #56 |
| C4 | No InputMap, raw keycodes (#29) | PR #66 |
| C5 | Mixed input paradigms (#30) | PR #66 |
| D1 | `scripts/main.gd` abandoned | PR #3 |
| D2 | Stale duplicates in `Claude outputs/` | PR #3 |
| D3 | `LANE_W` declared in three files | PR #3 |
| D4 | `SHIFT_SAFE_SPEED` never referenced | PR #3 |
| D6 | Tire radius set twice | PR #3 |
| E1 | Friction 3.0 vs the ~1.2–1.5 target (#33) | PR #52 (GEVP convention documented) |
| E2 | Aero "lift" used as downforce (#34) | PR #53 |
| E3 | Nothing had ever been driven | Roy drove it; feedback became E7–E9 |
| E4 | Sidewalk collision untapered (#35) | PR #60 |
| E5 | Lane dividers snap to end-of-chunk count (#36) | Closed as acknowledged |
| F1 | Feature tag said Forward Plus (#38) | PR #44 |
| F2 | No tests, no CI, no performance harness (#39) | PRs #50, #65 |
| F3 | Doc sprawl (#40) | PR #44 (HANDOFF.md retired) |
| F4 | HANDOFF's "editor run not verified" was false (#41) | PR #44 |
| F5 | Class cache goes stale after deletes (#42) | PR #46 |
| F6 | This file was untracked | tracked since PR #6 |
| G1 | Car rendered as a bare frame, loft winding (#14) | PR #45 |
| G2 | Glass loft zero normals (#15) | PR #43 |
| H1 | No audio at all (#18) | `093b3ef` (engine synth, PR #57), `18e0509` (stage A wind/road/squeal/kerb), `8890350` (Phase B driveline); tests `car_audio`, `audio_master`, `driveline_audio`. Engine-tuning direction is now #80. **GitHub #18 is still open: recommend closing** (the issue says "never built"; audio is built and tested) |
| #55 | Keyboard steering reaches full lock at any speed | `764b3f0`; `tests/feel_pass_1.gd` checks the ramp and the speed cap. **GitHub #55 is still open: recommend closing** |
| #48 | Workers are told to check the queue but `office-queue` refuses them (403) | **Closed on GitHub 2026-09-29** (it was listed open here); docs fix in PR #77 (`3cc3b30`) |
| #63 | Neutral test car | PR #68 (`e4f23cd`); `tests/test_car.gd` |
| #73 | Real turbo lag needs a physics addition | `65a4303` (PR #102); `tests/turbo.gd` (boost lags, blow-off, torque gain). **GitHub #73 is still open: recommend closing** |
| #75 | `brake_force_multiplier` declared but never read | `ee9ee5a` (PR #78); read in `gevp_vehicle.gd:1234` (marked "Local change to vendored GEVP (#75)", **not** `DEVIATION`), set in `car_spec.gd`, and exercised by the brake run in `tests/tune_track.gd` (100-0 m). Closed on GitHub 2026-09-29 |

---

## Details kept for the open audit items

**C3 / D5 (#28).** Buildings are 22 m apart, and past them is a flat slab you
can drive on. Nothing stops the player leaving the road. `is_off_road()`
(`scripts/player.gd:286`) is still not called anywhere on `origin/main`.

**E7–E9 (#62).** Audit-time numbers, before `764b3f0` evened the gearing. With `wheel_r 0.34`, `final_drive 4.1` and a 7000 rpm
redline, the ratios `[3.6, 2.4, 1.8, 1.4, 0.95]` give:

| Gear | Ratio | km/h at redline | Step to next |
|---|---|---|---|
| 1 | 3.6 | 61 | 1.50 |
| 2 | 2.4 | 91 | 1.33 |
| 3 | 1.8 | 122 | 1.29 |
| 4 | 1.4 | 156 | **1.47** |
| 5 | 0.95 | 230 | — |

The 4→5 step is the second-largest in the box. It lands where the torque curve
has already dropped about 28% from peak power. Ratios, curve and top speed
have to be tuned together, and Roy picks the numbers with the #62 sliders.

**H1 (#18).** Engine pitch follows rpm, so final engine audio should wait for
the #62 tune, or it gets tuned twice.
