# Neon Overdrive — Roadmap

**Status synced with `origin/main` at `4bfed10` (PR #110), 2026-10-05.** Checked
against `git log origin/main`, `scripts/` and `tests/run_tests.bat`, not from
memory. Long build logs for stages A, B1 and Auto-Tune were removed from this file;
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
| Traffic (lane-follow, reactive, 4-lane road, detail-distance slider) | **NOT started** | no traffic script exists |
| NPC cars (3) and cop cars (3) | **NOT started** (designs only) | |
| Other 11 fleet cars (5 more player cars) | **NOT started** (`CarSpec` has the coupe only) | |
| Garage + per-car mod trees | **NOT started** | |
| Damage, fuel, stop places | **NOT started** (parked after the garage) | |
| Police / heat / pursuit | **NOT started** | |
| Effects pack | **NOT started** | |
| Currency / scoring / near-miss detection | **NOT started** | |
| Events (rival, dig/roll race, highway run, touge, takeover), The List, meets, night loop | **NOT started** | |

**Next in Roy's order:** stage B steps 3–5 (traffic, finish camera + HUD, NPC cars),
then C (currency/scoring) → D → E → F → G.

## Stage plan (Roy, 2026-10-04) with revisions

Every stage is verified headless with real simulated input, logged here, and
**stops for Roy's sign-off**. Stage D stops after every car.

| Stage | Contents | Status |
|---|---|---|
| A | Feel + environment art | Done |
| B | 1 design sheet · 2 exhaust · 3 traffic (full-sim, 4 lanes/direction, detail slider) · 4 camera + HUD · 5 NPC cars | 1, 2 done; 4 partly; 3, 5 not started |
| C | Currency/scoring (damage, fuel, stops moved after the garage, 2026-10-05) | Not started |
| D | 5 remaining player cars, one at a time | Not started |
| E | Garage + branching mod tree per car | Not started |
| F | Heat/wanted + police, 3 cop cars | Not started |
| G | Integration, balance, bug sweep, Windows export on request | Not started |

Plus outside the original A–G list and already merged: Auto-Tune, the engine
phases A–C, radio and audio.

## Decisions still valid

- **Look:** "Gritty PS2 night", Street-Spec reference, no neon. Palette
  "Amber vs. Dusk" (sky `#1B2A4A`, sodium `#FF8A1F`, no magenta or cyan). Police
  blue `#2E4FD8` is the one off-palette colour.
- **Cars:** 12 original designs, gas only, keyboard only, every car runs the same
  raycast wheel sim told apart by `CarSpec` data. We design them ourselves; PR #79's
  import pipeline is not used. 4 sticker slots per car (door, hood, windshield
  sun strip, rear).
- **Traffic is full-sim (Option C).** Fallback only if measured necessary: a
  "Traffic detail distance" slider. Target 60 fps on the i5-1235U.
- **Exhaust is cosmetic only.**
- **GEVP is open for editing** (Roy, 2026-10-05). Every edit is marked `DEVIATION`
  in `scripts/vendor/gevp/gevp_vehicle.gd`. Physics runs at **120 Hz**; tests run
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
- **Scripted traffic** from PR #83: replaced by full-sim traffic (Option C).
- **Damage ends the run, fuel, stop places** as early milestones: parked after the
  garage. Old numbers (health 100, fuel 1 unit per 20 m) are untested.
- **Heat numbers** (tiers 30/60/90, +2 × streak per near-miss): v1 guesses, not built.
- **Road capped at 3 lanes** (stage A): superseded by 4 lanes per direction in
  stage B step 3.
- **Chase cam only, no cockpit camera** (2026-09-12): a cockpit camera (F) shipped in Phase C.
- **Physics at 60 Hz** and "do not raise the tick rate": 120 Hz since #110.
- **Proposals 2 and 3** from `RESEARCH-cheap-pretty.md` (vertex-colour roads,
  MultiMesh traffic): still not approved. Proposal 1 (dim cool key light) is built.

## Open for Roy

- Which 3 features the game must have on day one; the two idea pages that disagree
  (no-prep, family debt, missed-payment penalties); crew system; setting; game name.
- Stage B step 4 leftovers: RPM-bar shift cue, instrument cluster, visible shifter,
  pause-menu Settings tab beyond volume.
- Police blue vs red/amber light bar. Two stock outline twins (P1/P3, P2/P6).
- Parked, do not touch unless Roy raises: top-speed plateau in `process_clutch()`,
  automatic-vs-manual clutch question.
- Frame time on Roy's laptop (`benchmark.bat`); the exported `.exe` has never been
  launched on Windows by an agent.
