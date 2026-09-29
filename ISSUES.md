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

**B7. Headroom is unmeasurable. Partly addressed by PR #8, but not closed.**
Originally: no vsync setting existed at all, so it was engine-default on and
every run read a flat 60 FPS / 16.66 ms regardless of load.

PR #8 added `window/vsync/vsync_mode.editor=0`. That is the **`.editor`
feature-tagged override**, so it only takes effect when running from the
editor. The plain `window/vsync/vsync_mode` key is still unset, which means
**vsync remains on in exported builds** — including the standalone build Roy
is now playing, and any build used for benchmarking. Two things still open:

- set the untagged `window/vsync/vsync_mode` as well, or deliberately decide
  that measurement only ever happens in-editor and say so;
- there is still no frame-time harness, so the budget in
  RESEARCH-cheap-pretty.md remains unverified — and that includes the
  draw-call numbers claimed for B1–B4 above, which are counted, not timed.
*Where: `project.godot:23`.*

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

**E3. Nothing had ever been driven — this is now resolved, and it produced
E7-E9 below.** Gearing, torque curve, aero and grip were all
`[stated]`-flagged in-code as needing a real tuning pass once playable. As of
2026-09-29 the game is playable from a standalone build and Roy has driven it.
The first real feel feedback exists; it is filed as E7-E9. Aero and grip are
still untested by feel.

**E4. Sidewalk collision uses untapered average width.** *(Acknowledged.)*

**E5. Interior lane dividers snap to end-of-chunk lane count.** *(Acknowledged.)*

**E6. No curves or elevation.** *(Acknowledged, out of scope — needs the Path3D
rearchitecture.)*

**E7. Gear spread is the wrong shape — 4th and 5th are barely usable.** (NEW)
Roy, after driving: *"the gearing ratio doesnt feel right. there barley any use
for 4th and 5th gear."*

With `wheel_r 0.34`, `final_drive 4.1` and a 7000 rpm redline, the ratios
`[3.6, 2.4, 1.8, 1.4, 0.95]` give:

| Gear | Ratio | km/h at redline | Step to next |
|---|---|---|---|
| 1 | 3.6 | 61 | 1.50 |
| 2 | 2.4 | 91 | 1.33 |
| 3 | 1.8 | 122 | 1.29 |
| 4 | 1.4 | 156 | **1.47** |
| 5 | 0.95 | 230 | — |

Gear steps should shrink as they go up. These shrink (1.50, 1.33, 1.29) and
then jump back to 1.47 for 4->5 — the second-largest step in the box sits at
the top, where there is least power to recover from it.
*Where: `scripts/car_spec.gd` `gear_ratios`.*

**E8. The torque curve falls off too hard to survive that jump.** (NEW)
`default_torque_curve()` peaks at x=0.55 and drops to 0.55 by x=1.0. Treating
x as normalized rpm, torque x rpm puts peak *power* near x=0.85 (~5950 rpm),
and by redline power is about 28% down from peak. Upshifting 4->5 at 6000 rpm
lands at roughly 4070 rpm, which is about **75% of peak power** — so the shift
into 5th costs a quarter of the available power. That is the mechanism behind
E7's symptom, and neither fixes cleanly without the other.
*Where: `scripts/car_spec.gd` `default_torque_curve()`.*

**E9. Top gear is geared for a speed the game does not use.** (NEW)
5th reaches 230 km/h at redline. **Roy's stated target is around 200 km/h.**
Until top speed comes down, 5th is a gear with no reason to be selected and
4th covers only a narrow 122-156 km/h window.
*Depends on E7/E8; changing final drive moves every gear.*

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

## G. Car model and car visuals

**G1. The player car reads as a bare frame with the body panels missing —
cause: loft face winding.** (FIX IN PR #45, stacked on #43)
`_quad` emitted its triangles counter-clockwise, but Godot treats **clockwise**
as the front face. Every body and glass panel facing the camera was culled, and
the far panels showed their inside, lit from behind, so they rendered black.
The normals themselves were correct (outward); the winding check that found
nothing wrong used the counter-clockwise convention, not Godot's.

Proof: in a brightly lit test scene (key light 1.4 plus ambient) the loft body
and glass were still solid black while the box parts beside them lit normally,
and flipping the loft material's cull mode made the full body appear. PR #45
reverses the triangle order in `_quad` and keeps the normals. The body renders
solid in game afterwards, and `tests/car_loft_normals.gd` now checks the
winding.

The night lighting still matters, but it's secondary. `bbcb12f` dropped the key
light to energy **0.2** with `ambient_light_energy` 0.3, and `body_mat` is
non-emissive, so even with #45 the car reads dark in game. Whether to lift
that is Roy's call (see G4). The skeleton-rig mix-up (`player.gd:68`) was fixed
on 2026-09-13 and is not involved.
*Where: `car_builder.gd` `_quad` (winding); `scripts/game.gd:86-89` (key
light).*

**G2. The glass loft has degenerate end caps with zero normals.** (FIX IN PR #43)
`_add_coupe_glass`'s `glass_sections` first and last entries set
`y0 == y1 == base_y`, so the front and rear cap quads emitted by `_build_loft`
have zero area. `(b-a).cross(c-a).normalized()` on a degenerate triangle
returns `Vector3.ZERO`, so those faces carry a null normal and shade
incorrectly. The same cause gave the front-right and rear-left glass side
triangles zero normals too; #43 fixes all of them. Minor next to G1 but real,
and independent of it.
*Where: `car_builder.gd` `_add_coupe_glass` / `_build_loft`.*

**G3. Roy is unhappy with the car model itself, separate from G1.** (NEW)
Roy: *"our car model sucks atm"*. This is a look-and-feel call and needs his
direction before any work. Worth knowing there have already been two passes:
the body was stacked `BoxMesh` primitives, then was rebuilt as the tapered
loft wedge after Roy's *"replace the sport coupe its hideous"*. A third pass
should start from what specifically still reads wrong, not from another guess.
**G1 should be settled first** — it is likely that some of "sucks" is simply
that the model is nearly invisible.

**G4. The player car has no self-lit elements.** (NEW)
No underglow, no emissive body accents, nothing that survives a dim night key.
Roy already picked a placeholder underglow for the car as part of the lighting
comparison's phase 2, which is on hold. Directly relevant to G1.

---

## H. Audio

**H1. There is no audio in the project at all.** (NEW)
Roy, on the standalone build: *"theres 0 sound on the build"*. This is not a
regression — it was never built. There is no `AudioStreamPlayer`, no
`AudioStream`, no audio file anywhere in the tree.

`PROPOSAL-audio.md` states its own status plainly: *"STATUS: PROPOSAL. Nothing
here is decided and no code has been written."* Audio appears nowhere in
ROADMAP.md's milestones 1-11, and HANDOFF.md lists engine-pitch and
tire-screech audio under *after core feel is right — don't build yet*.

So the gap is expected, but Roy now wants it. Two things block a useful
estimate: a direction has to be chosen from the three in PROPOSAL-audio.md,
and engine sound is coupled to E7-E9 — pitch mapped to rpm will feel wrong
while the gearing itself is wrong.

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

---

### Revised after the first real play session (2026-09-29)

The game became playable from a standalone build and Roy drove it. That
changes the ordering above, because feel feedback now exists where before
there was only static analysis.

**G1 first, and it is cheap.** The car looking like a bare frame was broken
face winding (PR #45, one line), not the model's design. It is very likely
that part of G3 ("our car model sucks") dissolves once the body actually
renders. Diagnosing G3 before #43/#45 merge risks redesigning a model nobody
can currently see.

**E7 + E8 are one issue and must move together.** The 4->5 gear step is the
second-largest in the box and it lands exactly where the torque curve has
already given up 28% of peak power. Fixing the ratios without flattening the
curve, or the reverse, will not fix the symptom Roy reported. E9 (top speed to
~200 km/h, Roy's stated target) rides along with them since final drive moves
every gear.

**H1 depends on E7–E9.** Engine audio is pitch mapped to rpm; building it
against gearing that is known wrong means tuning it twice.

**B7 is still the measurement blocker** and is now known to be only
half-fixed — the vsync override PR #8 added does not apply to exported builds.
Everything claimed about B1–B4 performance, and anything B8 would claim about
glow cost, is unverified until that and a harness exist.
