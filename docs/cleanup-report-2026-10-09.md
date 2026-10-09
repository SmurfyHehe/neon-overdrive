# Cleanup and performance report, 2026-10-09

Snapshot of `main` at `215e4cf`. Read-only audit plus one small PR. This PR
only touches files that no open PR edits, except `tuner_tabs.gd` (see below).
With 98 PRs open, bigger moves are listed here as proposals, not done.

## Done in this PR

| Change | Evidence |
|---|---|
| Removed `scripts/tuner_tabs.gd` (+ `.uid`) | `class_name TunerTabs` has 0 references in scripts, tests or scenes. Its last caller went in `0a459c6` (Tuner PR 3). A copy is in Roy's `TO DELETE - Warehouse`. |
| `assets/radio/CREDITS.md`: 44.1 kHz -> 32 kHz | All 21 `.ogg` headers say 32000 Hz stereo; `tools/radio_synth/README` says q3 at 32 kHz. |

The open PRs #158, #181 and #223 still edit `tuner_tabs.gd`, so each of them
gets a modify/delete conflict. Resolve it by keeping the delete, because the
file has no caller.

## Proposed, not done (Roy decides)

### Code

1. **Duplicate helpers.**
   - `_mono_font()` is identical in `auto_tune_panel.gd` and `tuning_panel.gd`.
   - `triangle_count()` is identical in `cockpit_frame.gd` and `steering_wheel.gd`.
   - `static func stream(layer)` is near-identical in `car_audio.gd`, `crash_audio.gd` and `driveline_audio.gd`.

   Merge each one into a shared helper after the tuner and cockpit stacks land, since those files are in open PRs.
2. **Unused functions kept on purpose.**
   - `player.is_off_road()`: Roy said to keep it as a scoring hook (ISSUES.md D5).
   - `road_alignment.height_at()`: this is API and pairs with `grade_at`.
   - `cockpit_frame.lever_knob_position()`: an accessor, and the file is in 7 open PRs.
   - `cockpit_mirrors.set_enabled()` and `powertrain_health.to_dict()/from_dict()`: marked "later".
3. **Settings save/load is copied four times.** `audio_`, `fx_`, `traffic_` and `view_settings.gd` share one ConfigFile skeleton. A small base helper would replace it.
4. **No TODO/FIXME/HACK comments in the code.** The "later" notes still match the code.

### Tests

5. **Two real tests never run in CI.** `tests/engine_voice.gd` and `tests/engine_audio_render.gd` both PASS headless today (2026-10-09). Add them to `run_tests.bat` once the 49 open PRs that edit that file have settled.
6. **`tests/takeover_feel.gd` looks stale.** It is a measurement tool with 0 references, last touched 2026-09-29. It could be archived.

### Docs layout

7. **Move three history docs from the root to `docs/`.** `PROPOSAL-audio.md` (its banner says "history"), `RESEARCH-cheap-pretty.md` (banner: "partly overtaken") and `ISSUES.md` (GitHub is the live list). Code comments mention them by name, so update those comments in the same change.
8. **Duplicate decisions doc.** `docs/decisions/i-wish-to-create-a-car-game-i-wa.md` equals the `-roy.md` copy plus a 14-line status banner, and ROADMAP links the `-roy` copy. Keep one copy.
9. **Snapshots with no inbound links.** `docs/planning/repo-digest-2026-10-06.md` and `cockpit-interior-research-2026-10-06.md` could move to `docs/archive/`.

### Licences

All third-party content is covered: only GEVP, whose licence ships in `scripts/vendor/gevp/LICENSE.txt`. There are no fonts, models or outside images. These gaps are in our own notes:

10. **CREDITS.md** says "Music and sound: None yet". It should say the radio tracks and sounds are generated in-house.
11. **`docs/audio-licences.md`** has no row for the synthesized engine, exhaust, turbo or wind sounds, or for the generated moon texture. Every row still says "approved by: pending Roy".
12. **Talk station name.** `assets/radio/CREDITS.md` names it "Dave", but the project notes say "Dale". It's a placeholder, so Roy picks.

Items 10 and 11 are left for later because #192, #230, #231 and #248 edit those files.

## Performance hotspots (for the iGPU laptop)

The code is already careful in the main places. Road chunks are pooled and MultiMeshed, traffic meshes are cached, no light casts shadows and audio players are pooled. Ranked:

| # | Where | Cost | Fix |
|---|---|---|---|
| 1 | `engine_synth.gd:205-280` | HIGH (CPU) | Synth runs per sample in GDScript. Measured 7-8% of real time **per voice** (engine_voice test). Hoist `tune.*` reads out of the loop, render at 22 kHz, cap voices to the nearest 2-3 cars |
| 2 | `traffic_manager.gd:42,196` | HIGH (physics) | `detail_distance` 300 m keeps almost every car on full sim. Try 120-150 m or a cheap far tier |
| 3 | `project.godot:182` | HIGH (CPU) | 120 Hz physics doubles #2. Low preset at 60 Hz, or traffic on alternate ticks. The physics engine is not set in project.godot; pin it explicitly (unverified which default 4.7 picks) |
| 4 | `cockpit_mirrors.gd:247-265` | MED-HIGH (GPU) | Up to 3 extra scene renders at 250 m. Cut FAR to ~100 m, slimmer cull mask, 1/3 rate; rear strip off on low |
| 5 | `hud.gd:345,356,359`, `warning_lights.gd:50` | MED | `add_theme_color_override` every frame forces relayout. Only set on change |
| 6 | `hud.gd:334-369` | MED | 7 labels reformatted each frame plus an O(n) `detailed_count()`. Compare values first; slow text at 4 Hz |
| 7 | `steering_wheel.gd:226` | MED (cockpit) | Label3D text rebuilt every frame. Round rpm, set only on change |
| 8 | `game.gd:161`, `screen_fx.gd:95` | MED (fill rate) | Two full-screen passes. Merge grain + vignette + speed lines into one |
| 9 | `hud.gd:306` | LOW-MED | StyleBox written each frame. Write on change |
| 10 | `hud.gd:270-300` | LOW-MED | Two traffic loops per frame. Merge, run at 20-30 Hz |
| 11 | `car_audio.gd:161-190` | LOW-MED | Dicts + string keys each frame. Use packed arrays |
| 12 | `aero.gd:95-102` | LOW-MED | `get_nodes_in_group` + new buckets every tick. Reuse arrays |
| 13 | `cockpit_frame.gd:531-555`, `traffic_manager.gd:209` | LOW | Per-frame small array allocs. Use consts/caches |
| 14 | Rendering settings | LOW | Mobile renderer is right. Add a 0.75 FSR1 render-scale low preset (overlaps #232) |

Open perf work to check first: PR #254 (benchmark, cached road lookups) and #232 (render scale).
Suggested order: 1 -> 2 -> 3 as one "CPU budget" stage, measured with the
benchmark before and after; then 5-7 as a small "HUD churn" PR.
