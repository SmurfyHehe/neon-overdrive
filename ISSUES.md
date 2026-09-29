# Neon Overdrive — Issue List

Audit 2026-09-29, refreshed 2026-09-29 against `main` at `9ea72c8`.

Every item below was re-checked against the working tree, not carried over on
trust. Line numbers are current. "Acknowledged" means the code already
documents it as a deliberate choice — you may not want to file those at all.

---

## Closed

Verified fixed on `main` at `9ea72c8`.

| # | Issue | Closed by |
|---|---|---|
| A1 | ROADMAP said night lighting was unapproved though built | PR #2 |
| A2 | Nothing pushed, `origin/main` gone | pushed; `origin/main` live |
| A3 | `.claude/` untracked and unignored | `5cccba1` |
| A4 | No staging convention between agents | `5cccba1` (`CLAUDE.md`) |
| B1 | No MultiMesh anywhere | `01a84cb` |
| B2 | `_box()` allocated duplicate `BoxMesh` per dash/pylon | `01a84cb` |
| B3 | Three materials bypassed the file's own cache | `01a84cb` |
| B4 | "Recycling" only reused the chunk root | `01a84cb`, verified |
| D1 | `scripts/main.gd` abandoned, `Main.tscn` pointed at it | PR #3 |
| D2 | Stale duplicates in `Claude outputs/` | PR #3 |
| D3 | `LANE_W` declared in three files | PR #3 (one left) |
| D4 | `SHIFT_SAFE_SPEED` declared, never referenced | PR #3 |
| D6 | Tire radius set twice | PR #3 (`car_spec.gd` only) |

B1–B4 verification: headless boot 600 frames with zero errors, plus a
throwaway harness driving `build_chunk` once then `rebuild_chunk` 300 times
with randomized lane counts and barrier toggling. Child count held at 25
throughout, so the recycle path allocates and frees nothing after first build.
Per-chunk drawing nodes went from ~50–86 to 19; across the 8-chunk pool
~400–690 to ~150. **Still above** the sub-100 target in
RESEARCH-cheap-pretty.md — the ten tapered strips per chunk now dominate.

Not covered by that: how any of it *looks*. Headless renders nothing.

---

## A. Coordination

**A5. Pixel's task is incomplete — F1, F3, F4 never landed.** (NEW)
The task covering A1, F1, F3, F4 and tracking `ISSUES.md` produced only PR #2
(A1). The worker stalled on a permission prompt. Three hygiene issues and the
issue list itself are still open because of it.

**A6. Duplicate diagnosis: two agents fixed the same bug.** (NEW)
The `road_chunk_builder.gd` parse error was independently diagnosed from the
same Godot log and fixed identically by two agents. One fix became PR #4; the
other became an orphaned commit on `main`, discarded by a `git reset`. The
diffs were byte-identical. Pure duplicated spend, and a sign that dispatch
does not know what is already in flight.

**A7. An agent reset the shared root checkout under another agent.** (NEW)
`git reset` to `origin/main` was run in the root checkout while another agent
was mid-debug there holding an unpushed fix. The commit was orphaned and the
tree reverted to a non-parsing `road_chunk_builder.gd`, so the game stopped
booting again while the cause of it not booting was being diagnosed. Nothing
was lost only because the same fix existed on PR #4.
*Fix proposed in PR #5.*

---

## B. Performance

**B5. `cull_mode = CULL_DISABLED` on the asphalt/strip material.**
Doubles rasterised triangles on the largest surfaces in the scene. The comment
admits it exists so triangle winding "never matters" — it covers a
winding-order bug rather than fixing it. There is exactly one real site; the
old `:192` reference was always a comment, not code.
*Where: `road_chunk_builder.gd:155`.*

**B6. Drafting is O(n²) per physics frame.**
`_draft_factor()` walks the entire `aero_vehicles` group for every vehicle at
60 Hz. Inert today (one member), but it lands precisely when milestone 3
traffic arrives — 20–40 cars is 400–1600 distance checks per frame, on 2
P-cores already running GEVP's per-wheel raycasts.
*Where: `scripts/aero.gd:76-91`.*

**B7. Headroom is unmeasurable.**
No vsync setting appears in `project.godot` at all, so it is engine-default on
and every run reads a flat 60 FPS / 16.66 ms regardless of load. No frame-time
harness exists, so the budget in RESEARCH-cheap-pretty.md is unverified — and
that includes the draw-call numbers claimed for B1–B4 above, which are counted,
not timed.
*Update (#19, PR #49):* measuring is now possible in exported builds with
benchmark mode (`benchmark.bat`, or `NeonOverdrive.exe -- --benchmark`).
**Still open:** nobody has timed B1–B4 or B8's glow cost yet. Benchmark mode
is the tool for it; that measurement is a separate task.

**B8. Glow is never enabled.**
`game.gd`'s `Environment` sets fog and sky but no `glow_enabled` — confirmed,
zero `glow` references in the file. So godot#98531 (severe glow cost on the
Mobile renderer, which this project uses) is an unmeasured risk sitting
directly in front of the entire neon aesthetic.
*Where: `scripts/game.gd` Environment setup.*

---

## C. Architecture

**C1. No floating origin / world recentering.**
The ground slab is 200,000 units long and chunks sit at `-index × 50`. Single
precision degrades badly that far out, and there is a hard wall at ~200 km —
about an hour at 200 km/h — in a game whose premise is *endless*.

**C2. No pause, restart, or quit. No game-state machine at all.**
You cannot exit without killing the process. Milestones 6–11 (damage ending a
run, fuel stranding, garage stops) every one assume a state machine that does
not exist.

**C3. No out-of-bounds handling.**
Buildings are 22 m apart so there are gaps between them, and past them is flat
drivable slab. Nothing stops the player leaving the road indefinitely.

**C4. No InputMap — raw physical keycodes.**
`Input.is_key_pressed(KEY_W)` means no rebinding, no gamepad, no wheel. Unusual
for a driving game, and it becomes a refactor once menus exist.

**C5. Mixed input paradigms.** Polling in `_physics_process`, events in `_input`.

**C6. Camera hard-snaps with no smoothing.** *(Acknowledged.)*

---

## D. Dead code

**D5. `is_off_road()` defined, never called.**
Comment says it is for future scoring hooks. Needs Roy's call: keep as a hook
or delete.
*Where: `scripts/player.gd:184`.*

---

## E. Tuning and correctness

**E1. Grip target drift.** `coefficient_of_friction {"Road": 3.0}` in
`car_spec.gd`, but HANDOFF.md states the target as "friction ~1.2-1.5". Either
the target moved or GEVP's convention differs from `VehicleBody3D`'s.
Undocumented either way.

**E2. Aero coefficients are named "lift" but used as downforce.**
`aero_lift_coefficient_front/rear` get multiplied by `-basis.y`, so the sign
convention is inverted from the name. Confusing for anyone tuning it later.

**E3. Nothing has ever been driven.** Gearing, torque curve, aero and grip are
all `[stated]`-flagged in-code as needing a real tuning pass once playable.

**E4. Sidewalk collision uses untapered average width.** *(Acknowledged.)*

**E5. Interior lane dividers snap to end-of-chunk lane count.** *(Acknowledged.)*

**E6. No curves or elevation.** *(Acknowledged, out of scope — needs the Path3D
rearchitecture.)*

---

## F. Hygiene

**F1. `project.godot` metadata is inconsistent.** Still open.
`config/features` claims `"Forward Plus"` while `renderer/rendering_method` is
`"mobile"`. The engine reports Forward Mobile at runtime, so the tag misleads.
*Where: `project.godot:19` vs `:23`.*

**F2. No tests, no CI, no performance harness.**
RESEARCH-cheap-pretty.md prescribes a measurement discipline with no mechanism
to run it. The B1–B4 verification above had to build a throwaway harness and
then delete it — that work should be a kept fixture, not disposable.

**F3. Doc sprawl with overlapping authority.** Still open.
CLAUDE.md + ROADMAP.md + HANDOFF.md + RESEARCH-cheap-pretty.md +
PROPOSAL-audio.md + this file. HANDOFF is from Sept 12 and its "Plan, in order"
is superseded by ROADMAP's 11 milestones.

**F4. HANDOFF's "editor run not verified" is false.** Still open.
`HANDOFF.md:23` still reads "Godot editor run has not been verified working
end-to-end this session". It was verified 2026-09-29: the project imports,
boots headless for 600 frames with zero errors, and the chunk harness passes.

**F5. Godot's global class cache goes stale when tracked scripts are deleted.** (NEW)
PR #3 deleted `Claude outputs/`, but `.godot/global_script_class_cache.cfg`
still mapped `PlayerCar` to `res://Claude outputs/player.gd`. That failed
`game.gd` at parse time and the game would not boot — a second, unrelated
breakage immediately after PR #4 fixed the first one. `.godot/` is gitignored,
so this is per-machine: **anyone who pulls PR #3 hits it.**
*Fix: `Godot --headless --editor --quit --path .` regenerates the cache. Worth
recording somewhere a human will find it.*

**F6. This file was untracked.** (NEW, fixed by this change)
The audit driving all of the above lived only in the working tree, unignored
and uncommitted, for the whole session.

---

## What matters most now

**B7 + B8 together are the real exposure.** Glow is never enabled, the project
runs the Mobile renderer with a known severe glow cost bug, and there is no way
to measure frame time because vsync pins everything to 60 FPS. The entire neon
aesthetic rests on an assumption nobody can currently test. B7 gates B8, and
B7 also gates any honest claim about B1–B4.

**B5 is the cheapest remaining perf win**, but it carries visual risk: wrong
winding means invisible road, so it wants an editor check, not just a headless
one.

**B6 should land before milestone 3, not after.** It is free to fix now and
awkward once traffic exists.

**A5–A7 are process, not code**, and they cost real tokens today: one task
stalled, one fix written twice, one working tree reset mid-debug.
