# Neon Overdrive: remaining work, smallest to largest (origin/main be4a549, 2026-10-06)

Effort: S = one small PR, a few hours of agent time. M = one PR, new script plus tests. L = several PRs or heavy art/audio/AI. XL = a stage of its own, stops for sign-off more than once.
RC = needs a Remote Control session on Roy's laptop (branch, headless Godot, PR). Every code item needs it; only pure design or Roy decisions do not.

| # | Item | Stage | Effort | Why | Depends on | Model | RC |
|---|---|---|---|---|---|---|---|
| 1 | Sync ROADMAP/ISSUES to be4a549 (traffic merged, #113, #112); fix `radio_manager.gd` "three stations" header | docs | S | Text edits only | none | Haiku | Yes (PR) |
| 2 | Controls page in pause menu | B4/UI | S | Static page in existing `pause_menu.gd`; no key hints elsewhere | none | Haiku/Sonnet | Yes |
| 3 | RPM-bar shift cue (green to red) | B4 | S | One HUD widget fed by existing engine RPM/limiter values | none | Sonnet | Yes |
| 4 | #31 camera smoothing (3 modes) | B4 | S | Tunable constants in `chase_camera.gd`; Roy tunes later | none | Sonnet | Yes |
| 5 | #28 out-of-bounds handling, keep `is_off_road()` as scoring hook | A/C | S | Small check plus respawn | none | Sonnet | Yes |
| 6 | Visible shifter (HUD/cockpit; follows the chosen transmission mode) | B4 | M | Needs art plus gearbox state per mode | #T1 transmission modes, #3 style | Fable (cockpit) | Yes |
| 7 | Instrument cluster (speedo, tach, gauges; reuse warning lights) | B4 | M | New cockpit/HUD layer, must read in cockpit and chase views | #3, #6 | Fable | Yes |
| 9 | #80 engine sound per car/upgrade | audio | M | Per-CarSpec synth params; only meaningful once more cars exist | D (partly) | Sonnet | Yes |
| 10 | Reactive traffic (brake, lane change, react to player) | B3 | L | AI behaviour on the full raycast sim; collisions, 60 fps target on i5-1235U | #113 | Fable | Yes |
| 11 | 3 NPC cars (N1 sedan, N2 hatch, N3 pickup) | B5 | L | 3 procedural models from design sheets plus 3 CarSpecs, spawn in traffic, silhouette checks | Design sheets (done), #113 | Fable | Yes |
| 12 | Radio rework to 4 file stations x 7 tracks | audio | L | 28 synthesized tracks (`tools/radio_synth` not on main), station manager rewrite, "The Dave Show" talk-only (DJ Dave, renamed from Dave); Roy must listen | none | Sonnet (Haiku for plumbing) | Yes, plus Roy's ears |
| 13 | Stage C currency and scoring (near-miss formula, speed rep, HUD, save) | C | L | Formula and constants already designed; needs detection against traffic, persistence, UI | #113 (reactive ideal), #5 | Sonnet | Yes |
| T1 | Transmission modes: auto, semi-manual, full manual (new, Roy 2026-10-06) | B4 | L | Repo has only the automatic gearbox; manual gear/clutch input and mode switching touch the vendored GEVP sim (each edit marked `DEVIATION`), key bindings, tests; clutch model exists | none | Opus (sim reasoning) | Yes |
| T2 | Tuner (merge tuner + exhaust + auto-tune into one raw screen, plus camber and tyre pressure modelled) | UI/physics | L | Proposal approved by Roy; merging ~900 lines of panels plus new tyre/alignment physics and tests | #T1 not required; tyre model (`tyres` test) | Opus (physics), Sonnet (UI) | Yes |
| 14 | Damage, fuel, stop places | after E | L | New systems, old numbers untested | E | Sonnet | Yes |
| 15 | Stage G integration, balance, bug sweep, Windows export | G | L | Broad testing; `.exe` never launched by an agent | all | Sonnet | Yes, on Roy's laptop |
| 16 | Stage D: 5 other player cars (P2 to P6), one at a time | D | XL | 5 models, 5 CarSpecs, tuned feel each, sign-off after every car; fix outline twins P1/P3, P2/P6 | B4 done | Fable | Yes |
| 17 | Stage F heat, police, 3 cop cars | F | XL | Pursuit AI, heat tiers, 3 cars, light-bar colour decision (Roy) | C, N-cars, reactive traffic | Fable | Yes |
| 18 | Stage E garage plus per-car mod trees (8-15+ nodes x 6 cars) | E | XL | 50-90 nodes, shape/paint/wheels/stickers per car, UI, save; answers #70-#74 first | C, D | Fable (shapes), Sonnet (UI) | Yes |
| 19 | Events (dig/roll, highway run, touge, takeover), The List, story delivery | beyond G | XL | Not scheduled; story is Roy's to write | C, E, F | Fable | Yes |
| 20 | #37 curves and elevation | beyond G | XL | Rework road builder (865 lines) to Path3D; touches traffic | none, but best before F | Fable | Yes |

Approved by Roy (2026-10-06): interior sightline spec, mirrors (part of interior step 1), exe build, audio pass (pops and loop repetition), Tuner proposal. Each still gets its own sign-off before its PR starts.

Dropped: missed-payment layering is removed from the roadmap. The story bible wins: the debt is story-only, no loan or penalty mechanics.

Needs Roy, not an agent: #62 gearing/top-speed tune (record it), #70-#74 mod-tree questions, police blue vs red/amber, 3 day-one features.

Flags: ROADMAP.md still says traffic "NOT started" (stale, lane-follow is #113). Radio on main has 6 generated stations, target is 4 (not a contradiction, just unbuilt).
