# Merge plan: open PRs, 2026-10-08

Checked against origin/main `09455e0` (all 50 open PRs). **Main conflict** = merging the PR head onto main. **After earlier** = the conflict when PRs are merged cumulatively in this order. **Boot** = `godot --headless --path . --quit-after 300` after `--editor --quit` import, on main + the PR (or on the PR head when it conflicts). ok* = the first run hit the exit-crash flake (139) and the second run was clean.

| # | PR | What | Risk | Main conflict | After earlier | Depends on | Boot | Recommendation |
|---|---|---|---|---|---|---|---|---|
| 1 | 181 | Tuner tab labels without key hints | low | none | none | – | ok | merge |
| 2 | 148 | Camera smoothing setting | low | none | none | – | ok | merge |
| 3 | 149 | Photo mode | low | none | none | – | ok | merge |
| 4 | 151 | Gear lever follows gearbox mode | low | none | none | – | ok | merge |
| 5 | 150 | Cockpit hands stay under the eye | low | none | none | – | ok | merge |
| 6 | 185 | Lower the driver's hands | med | none | driver_model, cockpit_driver test | 150 | ok | rebase (#191 shows the resolution) |
| 7 | 188 | Touch-screen radio | med | none | cockpit_frame, run_tests | 151 | ok | rebase |
| 8 | 153 | Traffic cars 1/3: N1 sedan | low | none | none | – | ok | merge |
| 9 | 154 | Traffic cars 2/3: N2 hatchback | low | none | none | 153 | ok | merge |
| 10 | 155 | Traffic cars 3/3: N3 pickup | low | none | none | 154 | ok | merge |
| 11 | 178 | Night lights | med | road_chunk_builder | same | 155 | ok (head) | rebase |
| 12 | 201 | Exhaust pop voice (rebased) | low | none | none | – | ok | merge |
| 13 | 182 | Flames follow throttle | low | none | none | 201 | ok | merge |
| 14 | 183 | Anti-lag, turbo only | low | none | run_tests | 201 | ok* | rebase |
| 15 | 159 | Tyre smoke | med | none | pause_menu | 148 | ok | rebase |
| 16 | 205 | Tyre smoke v2 | med | none | pause_menu | 159 | ok* | rebase with 159 |
| 17 | 147 | Exhaust tuning moves to Tuner page | high | engine_audio, tuner_screen, run_tests | same | 201, 183 | ok* (head) | rebase |
| 18 | 186 | Pit-wall speed trace | med | tuner_screen, tuner_test_run test | same | 147 | ok* (head) | rebase |
| 19 | 156 | Wall hits don't flip; tune survives reset | high | road_chunk_builder, tuner_screen, run_tests | same | – | head fails: old cockpit_mirrors parse error (fixed on main by #189) | rebase, then re-boot |
| 20 | 192 | UI blend 1: theme, fonts, pause menu | med | none | pause_menu | 148, 149, 159 | ok | rebase |
| 21 | 194 | UI blend 2: Tuner job sheet | med | none | pause_menu, run_tests | 192 | ok | rebase with 192 |
| 22 | 195 | UI blend 3: HUD plate | med | none | pause_menu, run_tests | 194 | ok | rebase with 192 |
| 23 | 199 | Cockpit mirrors by FOV, no glance keys | high | chase_camera | same | 148 | ok (head); PR says never run | rebase, then test |
| 24–28 | 206–210 | Buildings 1/5 to 5/5 | high | road_chunk_builder, run_tests | same | stacked | head fails: old cockpit_mirrors parse error | rebase stack onto main |
| – | 158 | Same diff as #181 | – | none | – | – | ok* | close as superseded by 181 |
| – | 166 | Pop voice, pre-rebase | – | none | – | – | ok* | close as superseded by 201 |
| – | 184 | Head-look proposal for mirrors | – | none | – | – | ok | close as superseded by 199 (FOV decision) |
| – | 191 | 21 PRs combined | – | fx_settings, road_chunk_builder, tuner_screen, run_tests, tuner_test_run | – | – | ok (head) | close as superseded; merge individually |
| – | 176 | Bundles #171, #172 and the mirror doc | – | mirror-usability doc (already on main via #174) | – | – | ok (head) | close as superseded by 171/172 |
| – | 161 | ROADMAP sync to 9c28d59 | – | none | – | – | ok | close (stale) |
| – | 163 | Remote branch cleanup list | – | none | – | – | ok | close (stale) |
| – | 162, 165 | Design docs for settings safety and curves (both already built and merged) | low | none | – | – | ok | merge |
| – | 157, 167, 168, 169, 170, 171, 172, 173, 175, 177, 179, 187, 197 | Proposal and research docs | low | none | – | – | ok* (169, 197), ok | needs Roy's decision |

**Needs Roy's decision:** (a) the 13 proposal docs above: merging one reads as sign-off; #167 and #168 are two gas station docs, so keep one. (b) #191: close it in favour of this order, or rebase it as a single merge. (c) #150 vs #185: the hand-priority logic from #150 stays under #185 (that is how #191 resolved it); confirm.
Notes:
1. Rows 1–5, 8–10, 12 and 13 merge cleanly in this order, and that combined tree boots with no script errors.
2. Most "after earlier" conflicts are `tests/run_tests.bat` test lists or `pause_menu.gd` sliders: keep both sides.
3. Exit code 139 on quit is a flake: it hit docs-only PRs too (#157, #169, #197), and every rerun was clean.
4. On main, the quick tests have `hud_rear_strip` failing, and `hud`, `camera_feel` and `look_back` crash on exit. Most PR CI runs show CANCELLED, so re-run CI after each rebase.
5. Read-only: no existing PR or branch was touched. Issue #59 (triage, 2026-09-29) predates every PR here and was not used for ordering.
