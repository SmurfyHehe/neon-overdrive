# Build phases A, B, C: making the car a real car (2026-10-05)

Roy asked for research on a real engine, transmission, exhaust, radio, turbo and
failures, then to sort the work by how easy it is to build. Six agents read the
web (8 to 21 pages each) and our code (read-only). Effort: S under 1 hour, M a
few hours, L a day or more. Numbers marked "judgement" are engineering
estimates, not sourced. Detail is in `car-feel.md`.

## Phase A: easy, safe, big change in feel per hour

| # | Work | Effort | Risk and notes |
|---|---|---|---|
| A1 | Tyre grip: cof 3.0 to about 1.5 (about 1.4 g). Move the `TuneParams` range from 2.0-4.0 to about 0.8-2.5. Re-baseline Auto-Tune and tune tests. Fix the 245 vs 205 mm tyre comment | S | Wheelspin returns in 1st (long grip about 0.75 g). Brake distance follows automatically |
| A2 | Centre of mass height (offset -0.2 to about -0.07, CoM about 0.5 m, judgement) and inertia (`inertia_multiplier` about 0.9, box height about 1.0 m) | S | Spec edits. Watch chunk_drive tipping |
| A3 | Throttle lag (`throttle_speed` 20 to about 6-10) | S | Spec value. 0-100 about 0.1 s slower |
| A4 | Idle controller (PI, about 950 rpm, anti-windup) replacing the floor clamp | S | GEVP edit, marked DEVIATION. Prerequisite for stall |
| A5 | Throttle-dependent shift maps with hysteresis, kickdown, min time in gear, replacing the hard-coded 100% / 75% | S-M | GEVP edit. Auto-Tune is spared (TuneTrack shifts manually) |
| A6 | Master hard limiter on the Master bus (not the deprecated Limiter); fix the pause click (fade the Engine bus) | S | Test asserts effect exists and master peak under -0.3 dB |
| A7 | Radio groundwork: `CREDITS.md` and `docs/audio-licences.md` (log format below) | S | Must exist before any track is added |

## Phase B: medium, each its own PR with a feel-test

| # | Work | Effort | Notes |
|---|---|---|---|
| B1 | Wheelbase 2.1 to about 2.5 m (`axle_z` 1.05 to about 1.25 in `player.gd` CFG and `car_builder.gd`), body, comments, collision box together | M | Visuals must match. Do after A1/A2 |
| B2 | Springs, dampers, anti-roll (front 0.30, rear 0.20) for an understeer baseline, plus objective tests (skidpad 1.0-1.4 g, brake 36-42 m, understeer 2-4 deg/g) | S-M | Suspension is not in TuneParams, so Auto-Tune is unaffected |
| B3 | Stall and starter key, with an anti-stall guard for the automatic; cars spawn running | M | Medium. TuneTrack settle needs the engine running |
| B4 | Turbo: boost state (tau up 0.4-1.0 s, down 0.15-0.3 s), torque multiplier about 1.35-1.6, blow-off event, gauge. Default boost 0 so baselines stay identical (verify) | M | GEVP edit at `process_motor`. Only tuner cars boosted. Keep out of Auto-Tune (it would max boost) |
| B5 | Turbo whistle, blow-off and flutter in `EngineSynth`; gear whine, shift thump, driveline clunk; landing thuds; better squeal; sidechain ducking | M | Needs a shift signal from GEVP |
| B6 | Volume settings tab (Master, Engine, SFX, Music) | M | Part of Stage B step 4 |
| B7 | Heat v1: `PowertrainHealth` (off in TuneTrack and NPCs), engine temperature plus over-rev heat, torque derate, limp floor, warning-light strip | S-M | Floors: torque 0.5, brakes 0.6, grip 0.8. Never run-ending |
| B8 | Brake temperature and fade; clutch wear | M each | Hooks default to 1.0 |
| B9 | Radio v1: manager (one player, one station clock, R on/off, N next, static burst, HUD toast, Music-bus colouring), one CC0 or Pixabay station | S-M | Licence log first |
| B10 | Generative synthwave station (own sequencer, baked to Ogg) | M for the first, S for each extra | Zero licence risk. Taste, tuned by ear |

## Phase C: large or risky, do last

| # | Work | Effort | Why last |
|---|---|---|---|
| C1 | Bite-point clutch plus automatic launch and creep | M-L | Very high risk: it is the path every metric flows through. Re-baseline Auto-Tune. Make it opt-in through a spec key first |
| C2 | Tyre load sensitivity (vendor patch in `process_tires`, `(Fz/Fz_nom)^-0.15`) | M | `_rederive` mirrors the wheel's tyre cache and `tune_params` tests check it |
| C3 | 120 Hz physics (GEVP recommends it) | S to switch, large retest | Done in #110 (physics at 120 Hz). `tune_track.gd` no longer hard-codes the step: it reads `Engine.physics_ticks_per_second` (`tune_track.gd:57`, `:231`) |
| C4 | Tyre temperature and wear; oil; turbo health | M-L | Tuning-heavy; needs the gauges |
| C5 | Cockpit camera, perspective audio buses, engine layer split (intake, exhaust, bay) | L + M, L | There is no cockpit camera today. The layer split pays off only after it |
| C6 | Traffic engine audio with manual Doppler (Godot issue 38143 breaks the built-in one at speed) | M-L | Comes with traffic (Stage B step 3) |
| C7 | DJ voice (own recording or a vetted Piper voice) | M | Voice-model licences unverified |

## Constraints that cut across phases

- GEVP edits are allowed (Roy, 2026-10-05). Mark each `DEVIATION`, list it in
  ROADMAP "Rules carried forward" (the section was added 2026-10-06).
- Gauges, the volume tab and a cockpit camera all depend on Stage B step 4 (camera
  and HUD). Until then heat shows as a plain warning strip.
- Windowed key tests lose held keys when the window loses focus; write new
  key tests headless.
- All test runs use `--audio-driver Dummy`.

## Licence log format (`docs/audio-licences.md`)

id | file path | title | artist | source URL | licence (name and URL) | date
downloaded | proof (screenshot or receipt path) | modifications (trim, loop,
filter) | exact attribution text | commercial OK (Y/N) | Content ID notes |
approved by

Order of preference: CC0 (OpenGameArt, itch.io CC0 packs, our own tracks), then the
Pixabay Content License (keep receipts), then CC BY (Incompetech, needs a credits
screen and a note when trimmed or looped). Reject non-commercial, no-derivatives,
share-alike, GPL, unlabelled tracks and the YouTube Audio Library. Bensound,
Purple Planet and Free Music Archive terms could not be read: do not use yet.
