# Neon Overdrive — Roadmap

**Status synced with `origin/main` at `ea71c13` (PR #116), 2026-10-06.** Checked
against `git log origin/main`, `scripts/` and `tests/run_tests.bat`, not from
memory. Since the last sync: traffic lane-follow (#113), the flaky `car_audio`
fix (#112), the planning notes in `docs/planning/` (#117) and the Auto-Tune
panel fix for 120 Hz (#116, `ea71c13`). Long build logs for stages A, B1 and Auto-Tune were removed from this file;
they live in the PR descriptions (#84, #85, #86, #88, #90, #100) and in git history.

## What exists today

Roy's 2026-10-04 plan is stages A–G (below). The original 11-milestone
`VehicleBody3D` plan and the car-culture milestone table (1–10) are superseded as
a build order. Nothing in them beyond what is listed as merged has been built.

| Stage / track | Status | Proof |
|---|---|---|
| **A** Feel + environment (camera, FOV, shake, wind/road/squeal audio, lamps, gritty PS2 look) | **Merged**, Roy signed off 2026-10-05 | #84; `camera_feel`, `car_audio`, `roadside_detail` tests |
| **B1** Design sheet for all 12 cars, audit, 4 sticker slots | **Merged** (design only, no game models) | #85, #86, #93; `fleet_design_check`, `fleet_proxies`, `fleet_silhouette_sweep`, `fleet_budget_scene` |
| **B2** Exhaust (loudness, rasp, pops, flames; cosmetic only) | **Merged** | #92 (`af4ce02`); `exhaust_tune`, `exhaust_keys` |
| Flaky-test fix | **Merged** | #87 (`61fe113`); `game_state`, `chunk_drive`, `tuning_panel` |
| Linear damp 0 (car was capped at ~124 km/h) | **Merged** | #89 (`8cf2c89`) |
| **Auto-Tune 0–7** (spec dict, hidden test track, goals/locks, search, panel, slots, exported-game fix, reverse key) | **Merged** | #88, #90, #100; `tune_params`, `tune_track`, `auto_tune_*`, `tune_slots`, `reverse_and_tabs` |
| Feel pass 1 and GEVP engine pass 1b (automatic gearbox, even gearing, steering ramp and speed lock, soft limiter, rev match, engine braking) | **Merged** | #95, #97; `feel_pass_1` |
| **Phase A** (grip, idle controller, shift maps, master limiter) | **Merged** | #99; `phase_a_engine`, `audio_master` |
| **Phase B** turbo, chassis, audio, heat/wear v1, radio v1 | **Merged** | #101–#105; `turbo`, `chassis_targets`, `driveline_audio`, `powertrain_health`, `radio` |
| **Phase C** clutch, tyres, cockpit camera, radio 2, 120 Hz physics | **Merged** | #106–#110; `clutch_model`, `tyres`, `cockpit`, `tick_rate_120` |
| Stage B step 4 (camera + HUD) | **Partly**: cockpit camera and turning steering wheel (`0872d0d`), warning lights, tuner tabs, volume sliders. No RPM-bar shift cue, instrument cluster or visible shifter found in `scripts/` | grep of `scripts/` |
| **Traffic, stage B step 3** (lane-follow cars on a fixed 4+4-lane road, same raycast sim as the player, car-count and draw-distance sliders in the pause menu) | **Merged** (#113, `a9af0ea`). Full sim inside the draw distance; beyond it (150 m default) cars are frozen kinematic and cruise | `scripts/traffic_car.gd`, `traffic_manager.gd`, `traffic_settings.gd`; `traffic_spawn`, `traffic_stability`, `traffic_perf` |
| Traffic milestone 4 (brake, change lane, react to the player) | **NOT started** | `traffic_car.gd` is throttle-only speed hold plus lane keeping |
| NPC cars (3) and cop cars (3) | **NOT started** (designs only) | |
| Other 11 fleet cars (5 more player cars) | **NOT started** (`CarSpec` has the coupe only) | |
| Garage + per-car mod trees | **NOT started** | |
| Damage, fuel, stop places | **NOT started** (parked after the garage) | |
| Police / heat / pursuit | **NOT started** | |
| Effects pack | **NOT started** | |
| Currency / scoring / near-miss detection | **NOT started** | |
| Events (rival, dig/roll race, highway run, touge, takeover), The List, meets, night loop | **NOT started** | |

**Next in Roy's order:** the rest of stage B (traffic milestone 4, finish camera +
HUD, NPC cars), then C (currency/scoring) → **E (garage + per-car mod trees)** →
**D (remaining player cars)** → F → G. Roy changed the order on 2026-10-06 so the
garage and trees come before the other player cars (see "Decisions still valid").
Traffic is lane-follow
only and was not yet playable at speed in the 2026-10-06 audit
(`docs/audit-2026-10-06.md`, open PR #118, not merged): the
player rear-ended or side-swiped oncoming cars within seconds. Roy has
decided the fixes (3.2 m lanes, a 16-car default; in progress on
`feat/traffic-m4`, not merged); see "Decisions still valid".

## Stage plan (Roy, 2026-10-04) with revisions

Every stage is verified headless with real simulated input, logged here, and
**stops for Roy's sign-off**. Stage D stops after every car.

| Stage | Contents | Status |
|---|---|---|
| A | Feel + environment art | Done |
| B | 1 design sheet · 2 exhaust · 3 traffic (full-sim, 4 lanes/direction, detail slider) · 4 camera + HUD · 5 NPC cars | 1, 2, 3 done (3 is lane-follow only, #113); 4 partly; 5 not started |
| C | Currency/scoring (damage, fuel, stops moved after the garage, 2026-10-05) | Not started |
| E | Garage + branching mod tree per car. **Now before D** (Roy, 2026-10-06, overrides the C → D → E order) | Not started |
| D | 5 remaining player cars, one at a time. **Now after E.** The P1 sports coupe game model is being built from the B1 sheet (2026-10-06, not merged) | Not started |
| F | Heat/wanted + police, 3 cop cars | Not started |
| G | Integration, balance, bug sweep, Windows export on request | Not started |

Plus outside the original A–G list and already merged: Auto-Tune, the engine
phases A–C, radio and audio.

## Decisions still valid

- **Look:** "Gritty PS2 night", Street-Spec reference, no neon. Palette
  "Amber vs. Dusk" (sky `#1B2A4A`, sodium `#FF8A1F`, no magenta or cyan). Police
  blue `#2E4FD8` is the one off-palette colour.
- **Cars:** 12 original designs, gas only, every car runs the same
  raycast wheel sim told apart by `CarSpec` data. Input is keyboard-first, but
  gamepad bindings already exist in the InputMap (`project.godot`: throttle and
  brake on axes 5 and 4, steer on axis 0, handbrake, shift up/down, camera and
  pause on buttons). The code reads them as digital `is_action_pressed` only, so
  there is no analogue steering or throttle, and gamepad has not been tested. We design them ourselves; PR #79's
  import pipeline is not used. 4 sticker slots per car (door, hood, windshield
  sun strip, rear).
- **Traffic is full-sim (Option C).** Shipped as: full raycast sim inside the draw
  distance, frozen lane cruise beyond it, with a "Traffic detail distance" slider
  (50–300 m, default 150 m) and a car-count slider (0–80, default 40). Target 60
  fps on the i5-1235U.
- **Roy's decisions of 2026-10-06 (answered in chat; the code changes are not
  merged).**
  - **Sim radius:** the kinematic lane cruise beyond the draw distance is OK and
    counts as "full sim": every car near the player runs GEVP. Rivals, crew and
    cops were not asked; that sub-question stays open.
  - **Lane width:** 2.3 m becomes **3.2 m**. In progress on `feat/traffic-m4`.
  - **Traffic default:** **40 becomes 16 cars**; the slider max stays 80. In
    progress on `feat/traffic-m4`.
  - **Order after traffic:** garage + per-car mod trees (E) come **before** the
    remaining player cars (D). This overrides C → D → E.
  - **P1 sports coupe:** the game model is being built from the B1 design sheet.
  - **Radio (#115):** re-encode smaller (Vorbis q2–3, 32 kHz) and keep it in git,
    not Git LFS.
- **Exhaust is cosmetic only.**
- **GEVP is open for editing** (Roy, 2026-10-05). Every edit is marked `DEVIATION`
  in `scripts/vendor/gevp/gevp_vehicle.gd` (list under "Rules carried forward").
  Physics runs at **120 Hz**; tests run
  at 60 via `NEON_TICKS=60`, plus `tests/tick_rate_120.gd` at the real rate.
- **Top speed ~300 km/h through tuning stays** (Roy). `chassis_targets` asserts the
  stock coupe at 235–250 km/h.
- **Mod trees:** each player car gets its own branching tree, 8–15+ nodes,
  applied as `CarSpec` overrides (answers GitHub #71).
- **Near-miss formula** (design only, nothing built):
  `event_value = base × proximity × relative_speed × timing × streak × same_car_decay`.
  Constants: shell 1.5 m; base 10; proximity 1.0→2.5×; relative speed 1.0× below
  20 km/h → 2.0× above 80 km/h; timing 1.5× if steered within 0.5 s; streak +0.15×
  per event in 4 s, cap 3.0×; same-car decay 100% / 35% within 8 s / 10% / ~2%.
  It now feeds the highway run and respect, and the scoring in stage C.
- **Game concept (car-culture plan, merged in #83, 2026-09-29):** a mechanic by day;
  each night, one main activity plus one small extra. Events ranked pulls (dig,
  roll) > good driving (highway run, touge) > burnouts/takeovers. Ten-name street
  list, speed rep and respect, heat per car. Rivals and crew cars are scripted;
  only the player runs full GEVP. Missed-payment layering and the top-3 scope cut
  are still open for Roy. Not started.
- **Fleet table** (agreed 2026-09-13): players P1 sports coupe, P2 hot hatch,
  P3 tuner sedan, P4 kei roadster, P5 muscle sedan, P6 performance crossover;
  traffic N1 commuter sedan, N2 city hatchback, N3 pickup; cops C1 patrol sedan,
  C2 patrol SUV, C3 unmarked interceptor. Sheets are in `docs/design/fleet/`.

## Superseded

- 11-milestone `VehicleBody3D` plan (2026-09-12) as a build order; the car uses
  the vendored GEVP raycast sim.
- **Shared five-track mod tree, three car tiers, Cred prices, 7,000-Cred max-out,
  1.5× respec** (2026-09-12 balance pass): replaced by per-car branching trees.
  Numbers kept only as reference in git history.
- **Scripted traffic** from PR #83: replaced by full-sim traffic (Option C),
  built in #113.
- **Damage ends the run, fuel, stop places** as early milestones: parked after the
  garage. Old numbers (health 100, fuel 1 unit per 20 m) are untested.
- **Heat numbers** (tiers 30/60/90, +2 × streak per near-miss): v1 guesses, not built.
- **Road capped at 3 lanes** (stage A): superseded by 4 lanes per direction in
  stage B step 3.
- **Chase cam only, no cockpit camera** (2026-09-12): a cockpit camera (F) shipped in Phase C.
- **Physics at 60 Hz** and "do not raise the tick rate": 120 Hz since #110.
- **MultiMesh traffic** (item 3 in `RESEARCH-cheap-pretty.md`'s numbered list;
  this file used to call items 2 and 3 "Proposals 2 and 3") is moot: traffic
  shipped in #113 as individual full-sim raycast cars, not instances.
  **Vertex-colour roads** (item 2) are still not approved. The dim cool key light
  (item 1) is built.

## Rules carried forward

**GEVP edits, all in `scripts/vendor/gevp/`.** Roy allowed editing the vendored
sim on 2026-10-05 ("you can have access to the GEVP and edit it to make it fit our
game"). The numbered header at `gevp_vehicle.gd:767-826` is the canonical list;
each change is marked `DEVIATION` there, with the exceptions noted. There is no
`.patch` against upstream, so re-vendoring means re-applying these by hand.

| # | Change | Where | Source |
|---|---|---|---|
| 1–3 | Soft rev limiter, upshift rev-match, engine braking (`motor_brake`) | `gevp_vehicle.gd:767` | `f1a7d0d` (#97) |
| 4–5 | Idle PI controller; throttle-dependent shift points | `gevp_vehicle.gd:774` | `6b25128` (#99) |
| 6 | Reverse by R key (`brake_selects_reverse`) | `gevp_vehicle.gd:784` | `b71614f` (#100) |
| 7 | Turbo with lag | `gevp_vehicle.gd:788` | `65a4303` (#102) |
| 8 | Heat and wear hooks `torque_mult`, `brake_mult` | `gevp_vehicle.gd:799` | `07b504b` (#103) |
| 9 | Opt-in realistic clutch, stall, starter | `gevp_vehicle.gd:802` | `8933bb7` (#106) |
| 10 | `tyre_load_sensitivity`, `clutch_cap_mult`, per-tyre `grip_mult` | `gevp_vehicle.gd:823`, `gevp_wheel.gd:66` | `3c820cf` (#107) |
| - | Neutral zeroes `clutch_torque` (2026-09-13, Roy's request) | `process_clutch`, `gevp_vehicle.gd:911` | baseline era |
| - | `brake_force_multiplier` is applied (#75). Marked **"Local change"**, not `DEVIATION` | `calculate_brake_force`, `gevp_vehicle.gd:1234` | `ee9ee5a` (#78) |

The declarations of `torque_mult`, `brake_mult` and `clutch_cap_mult` carry no
marker of their own; the header comment above them covers them. A grep for
`DEVIATION` finds 8 lines in `scripts/vendor/gevp/`.

**Tests and runs.** Physics runs at 120 Hz; tests run at 60 via `NEON_TICKS=60`
(set by `tests/run_tests.bat`), plus `tests/tick_rate_120.gd`, `traffic_stability`
and `traffic_perf` at the real rate. All test runs use `--audio-driver Dummy`.
Windowed key tests lose held keys when the window loses focus; write new key tests
headless. Git rules (stage by path, own worktree, PR only) are in `CLAUDE.md`.

## Open for Roy

Raised by the 2026-10-06 audit. Roy answered the sim radius, lane width and
traffic default on 2026-10-06; those moved to "Decisions still valid". What stays
open:

- **Rivals, crew and cops.** The game-concept line above says "rivals and crew cars
  are scripted; only the player runs full GEVP". Roy's 2026-10-06 answer covers
  traffic only (cars past the draw distance run the kinematic lane cruise,
  `scripts/traffic_car.gd:22-23,184-205`, and that counts as full sim). Do rivals,
  crew and cops run full GEVP near the player too, or stay scripted?
- **Debt.** The story bible (`docs/story-bible.md`, only on open PR #114) says
  "debt is story-only, no penalty mechanics"; the game-concept line above and the
  decisions doc still list missed-payment penalties as open.
- **Dale.** The story bible says Dale is audio-only; open PR #115 makes him
  talk-only with 6 caption lines (captions-only). Audio-only or captions-only?

- Which 3 features the game must have on day one; the two idea pages that disagree
  (no-prep, family debt, missed-payment penalties); crew system; setting; game name.
- Stage B step 4 leftovers: RPM-bar shift cue, instrument cluster, visible shifter,
  pause-menu Settings tab beyond volume.
- Police blue vs red/amber light bar. Two stock outline twins (P1/P3, P2/P6).
- Parked, do not touch unless Roy raises: top-speed plateau in `process_clutch()`,
  automatic-vs-manual clutch question.
- Frame time on Roy's laptop (`benchmark.bat`); the exported `.exe` has never been
  launched on Windows by an agent.
