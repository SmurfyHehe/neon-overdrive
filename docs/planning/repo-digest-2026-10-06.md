# Neon Overdrive: repo digest (origin/main be4a549, 2026-10-06)

Sources: ROADMAP/ISSUES/CLAUDE `-origin-main-2026-10-06.md`, `docs/story-bible.md`, `docs/radio-tracklist.md`, plus read-only `git show origin/main:` checks. Note: the ROADMAP file says it was synced at `4bfed10` (#110), so it predates #113 and #112.

## Status per stage
| Stage | State |
|---|---|
| A Feel + environment | Merged, signed off 2026-10-05 (#84) |
| B1 12-car design sheet, 4 sticker slots | Merged, design only (#85, #86, #93) |
| B2 Exhaust (cosmetic) | Merged (#92) |
| B3 Traffic | Lane-follow merged (#113: 4+4 highway, same raycast sim, Traffic sliders in pause menu). Reactive traffic not started. ROADMAP still says "NOT started" |
| B4 Camera + HUD | Partly: cockpit camera, turning wheel, warning lights, tuner tabs, volume sliders. Missing RPM-bar shift cue, instrument cluster, visible shifter |
| B5 NPC cars (3) | Not started |
| C Currency/scoring | Not started (damage/fuel/stops moved after the garage) |
| D 5 remaining player cars | Not started; `CarSpec` has the coupe only |
| E Garage + per-car mod trees (8-15+ nodes) | Not started |
| F Heat/police, 3 cop cars | Not started |
| G Integration, balance, Windows export | Not started |
| Outside A-G, merged | Auto-Tune 0-7, engine phases A-C (gearbox, turbo, clutch, tyres, heat/wear v1), radio v1/v2, 120 Hz |

## Open issues (GitHub)
- #28 no out-of-bounds handling; `is_off_road()` never called (keep as scoring hook)
- #31 camera smoothing (3 modes, Roy tunes later)
- #37 no curves/elevation (needs Path3D rework)
- #62 gearing/power: Roy's tune not recorded; ~200 km/h target stale (Roy wants ~300 via tuning; stock asserted 235-250)
- #16 car model shape needs direction; #17 player car has no self-lit elements
- #48 workers get 403 from office-queue (expected)
- #70, #71, #72, #74 upgrade-tree design questions (#71 answered: one tree per car, issue still open)
- #80 engine sound per car/upgrade

## Repo rules (CLAUDE.md)
- Every change via PR; never commit or push to `main`; only Roy merges.
- Work in your own worktree under `.claude/worktrees/`; never move HEAD in the root checkout (no reset, checkout, switch, stash, force-pull). `pull --ff-only` in root is Roy's.
- Wrong commit in root: report it, don't repair.
- Stage by explicit path, commit promptly, check `git status` first, describe only what you staged.
- From the desktop bridge Linux shell: read-only git with `--no-optional-locks`; no fetch/add/commit/worktree; stale lock: rename out of `.git` and tell Roy.
- After a pull that moves `.gd` files: refresh class cache (`tools/refresh-godot-cache.ps1`); never commit `.godot/`.
- Workers don't run office-queue; report actual token/time cost per PR.

## Art look
"Gritty PS2 night", Street-Spec reference, no neon. Amber vs. Dusk (sky #1B2A4A, sodium #FF8A1F), no magenta/cyan. Police blue #2E4FD8 is the only off-palette colour. Open: police blue vs red/amber light bar.

## Physics
Vendored GEVP raycast sim, open for editing; each edit marked `DEVIATION` in `scripts/vendor/gevp/gevp_vehicle.gd`. Physics at 120 Hz; tests at 60 via `NEON_TICKS=60` plus `tests/tick_rate_120.gd`. Parked: top-speed plateau in `process_clutch()`, auto-vs-manual clutch.

## Radio
- main: `radio_sequencer.gd` has six generated stations (Neon FM, Night Drive, Open Road, Chrome Radio, Sunset Drive, Midnight Run) with DJ text breaks; no audio files. `radio_manager.gd` header still says "Three generated stations".
- Target: 4 file stations in `assets/radio/` (s1_drift, s2_dark, s3 Dale talk-only, s4_synthwave). `radio-tracklist.md` (Pixabay picks) is marked superseded by synthesized originals from `tools/radio_synth`; neither `assets/radio` nor `tools/radio_synth` is on origin/main.

## Story bible essentials (v0, all names placeholders)
Harlow Bay port city (Docks, Downtown, Cutter Canyon, Route 9, Airstrip). Shop Dunmore Auto, owner Walt, $60k debt held by Pike Lending (tied to Ledger). Debt is story-only: no loan/penalty mechanics. Player is an unnamed mechanic in the coupe. Crew: Juno, Teo, Pilar, Moose. Rivals: Ironbridge (Vance Ledger, final boss), Kasumi Run, Gruppe 9, Diesel Row; 5 kings TBD. Mentors Ferris, Okafor, NULL; no father figure. Dale runs underground "Graveyard TV" from the Garage; radio carries it as a pirate leak, audio-only, deadpan. Delivery: texts, stills, Dale broadcasts; no cutscenes; only Dale voiced (Kokoro suggested). Spine: Ledger humiliation, recruit, take districts, Pike/Ledger reveal, kings, Ledger rematch (win keeps shop, lose sells it).
