# Project state

Snapshot of every remote branch and open PR, so a new session (or Roy) can
see what is in the game, what is waiting, and what order to merge it in.

- **Taken:** 2026-10-09 05:30 UTC, from a fresh `git fetch --prune` and `gh pr list`.
- **main:** `282343f` (Merge #266, buildings 1-5 on main).
- **Remote branches:** 441. **Merged into main:** 274. **Not merged:** 167
  (83 of them are `pr/<n>` mirror copies of PR heads).
- **Open PRs:** 83.
- This file goes stale the moment anything merges. Re-run the commands at the
  bottom before trusting it.

## What is in the game (main 282343f)

Merged since 2026-10-06, newest last (source: `gh pr list --state merged`):

- Cockpit stack (#137-#140), Tuner 1-4 (#143-#146), exhaust flames v2 (#160),
  per-car engine voices (#152), mirror glance on V (#174), sky fog + moon (#164).
- Boot fix (#189), settings safety 1-4 (#190, #193, #198, #203).
- Curves and hills R1-R5 (#202, #204, #211, #212, #213).
- Photo mode test hardening (#200, into #149's branch).
- Sound fixes (#222), night clock + building windows (#225).
- Combined build #223 (= #191), which brought in: #189, #158, #150, #151,
  #148, #153, #154, #155, #178, #149, #147, #156, #159, #164, #166, #181,
  #182, #183, #185, #186, #188.
- Buildings 1-5 on main (#266, replaces #206-#210).

## MERGE QUEUE

Everything below merges into today's main **without conflicts, in this order**
(checked by merging each one on top of the previous with `git merge-tree`),
and each PR's own last CI run was green unless noted. The whole queue was
also merged together locally and the quick test suite run on the result;
see "Queue test run" below.

| # | PR | What it adds to the game | CI (own last run) | Notes |
|---|----|--------------------------|-------------------|-------|
| 1 | #238 | Version number, one-line game name, licence notices next to the exe | green | |
| 2 | #251 | Road layout plan, step 1: lane adds, drops, splits and exits in data | green | |
| 3 | #254 | Benchmark drives again, CPU/GPU split, cached road lookups | green | #268 contains this commit |
| 4 | #218 | Line lock: proper burnouts from a standstill | green | |
| 5 | #228 | Living world 2: hour bands thin traffic, Dave's lines change by hour | green | base is #225's merged branch: retarget to main |
| 6 | #250 | Living world 3: tonight's events change how many drivers break rules | green | stacked on #228 |
| 7 | #237 | Road sounds: highway joints, bridge hum, manholes, radio dropouts | green | base is #222's merged branch: retarget to main |
| 8 | #205 | Tyre smoke v2: burnout and drift profiles, wind, stretch | none ran | base is #159's merged branch: retarget to main |
| 9 | #149 | Photo mode test: car resumes exactly, PNG verified (test only; photo mode itself is already in) | cancelled + green | |
| 10 | #253 | The other 8 sheet cars (P2-P6, cops C1-C3) as AI-ready car kinds | none ran | base is #155's merged branch: retarget to main |

**Pulled from the queue: #226 (traction control) and #227 (TC lamp, stacked on
it).** They merge cleanly, but #226 breaks `powertrain_health` on today's main:
the car no longer sits on the limiter long enough to overheat ("never
overheated on the limiter, peak 97-99 C"). Bisected: main + #238 + #251 + #254
+ #218 passes; adding #226 fails (4 runs out of 4). #226's own CI was green
because its base predates that test. Fix: the test should turn TC off, or TC
should stand aside when the car is held on the limiter. Then re-test and add
both back after #218.

**Ready, but needs your sign-off first:**

| PR | What it adds | Why it waits |
|----|--------------|--------------|
| #267 | Mod tree foundation: P1 coupe 15-node tree in data, garage save, wallet | Stage E code. Merges clean after the queue and CI is green, but memory says the Stage E proposal (#197) still has 11 open decisions. Confirm you signed off. |

Retargeting: when a stacked PR's base branch is already merged, GitHub does not
move it to main by itself. Use "Edit" next to the PR title and pick `main`.

### Queue test run

First run: all 10 queue PRs plus #226, #227 and #267 merged together locally
(commit `ef845db`, not pushed), `tests\run_tests.bat quick` with Godot 4.7.2,
2026-10-08 23:29-23:53 MDT: 67 passed, `camera_feel` passed then crashed on
exit (known exit-crash flake), `powertrain_health` **failed** (see #226 above).

Second check: the same chain without #226 and #227 (commit `94ee744`, not
pushed): `powertrain_health` PASS, `camera_feel` PASS. The full quick suite
was not re-run on this second chain; the 67 tests that passed in the first
run did not depend on #226/#227 passing.

## Stacks that need a conflict resolve first

All of these were built on an older main. Since #223 and #266 merged they
conflict. Each needs one "merge main into the bottom branch" pass, then the
stack re-tested, before it can join the queue. Most conflicts are in
`tests/run_tests.bat` (the test list, trivial) and `scripts/pause_menu.gd`
(touched by four stacks, so resolve those one stack at a time).

| Stack | Order | Conflicts with main | CI |
|-------|-------|---------------------|----|
| Graphics polish | #232 → #236 → #241 → #247 → #257 → #258 → #259 → #260 → #261 | #232-#241: run_tests.bat only. #247 on: also road_chunk_builder.gd (curves) | green |
| Tuner overhaul (contains UI blend #192 + #194) | #230 → #235 → #239 → #242 → #243 → #244 (vanity plates) | pause_menu, tuner_screen, run_tests, tuner_test_run | green |
| Menus A-list | #231 → #245 → #246 → #248 → #256 | pause_menu, game, game_state, run_tests, audio-licences | green |
| Driving feel | #229 → #234 → #240 → #263 | fx_pack, fx_settings, pause_menu, view_settings | green |

Single PRs that need a resolve:

| PR | What it adds | Conflicts | CI |
|----|--------------|-----------|----|
| #219 | Cockpit mirrors all on screen and live (contains #199) | run_tests.bat only | green |
| #249 | Pause menu: Open log folder button | run_tests.bat only | green |
| #233 | Crash-safe saving: settings and tunes keep a backup | fx/traffic/view settings, run_tests | green |
| #264 | Cleanup: drop dead TunerTabs, radio sample rate, cleanup report | tuner_tabs.gd modify/delete (keep the delete) | green |
| #268 | Perf: engine sound off the main thread, fewer wasted casts (+20% avg fps) | car_spec, engine_audio, engine_synth. Contains #254 | none ran |
| #255 | Lane threading: NPCs keep their own spot in the lane | road_chunk_builder, traffic_car | green |
| #262 | More shop signs in more colours | building_signs, palette test. Base is a merged buildings branch | cancelled |
| #215 | Radio volume knob in play (hold , or .) | cockpit_frame, game, head_unit, pause_menu. Base merged (#191's): retarget | green |
| #195 | UI blend 3: HUD gauge-cluster plate | pause_menu, run_tests. Not inside #230 | cancelled |
| #252 | Interiors 1: P1 cabin, cluster, hood shift strip | cockpit_frame, cockpit_interior test | **red** |

Suggested order once resolved: #219, #249, #264, #232 stack, #233, #268,
#255, then the four pause_menu stacks one at a time (tuner, menus, driving
feel, #215), #262, #195. #252 waits on the car redesign (memory: no
interior polish before the Fable redesign, week of 2026-10-12).

## Close without merging (already in main or superseded)

| PR | Why |
|----|-----|
| #154, #155, #178 | Heads already in main (came in via #223); open only because their base was a stack branch |
| #207, #208, #209, #210 | Heads already in main (via #266) |
| #201 | Same patch as #166, which is merged |
| #199 | Contained in #219 |
| #192, #194 | Contained in #230 (tuner overhaul) |
| #161 | ROADMAP sync to an old main; conflicts; replaced by this file |
| #163 | Branch cleanup list from 2026-10-07; replaced by this file |
| #214 | Merge plan for 50 PRs from 2026-10-08; replaced by this file |

## Docs-only proposals (open, merge = sign-off)

These change only `.md` files. Merging one reads as "Roy approved this", so
they stay out of the queue. Merge or close each when you decide.

| PR | Topic | Status (source) |
|----|-------|-----------------|
| #162 | Settings safety design note | Signed off as is 2026-10-07 and built (memory). Safe to merge |
| #165 | Curves and elevation proposal | Answered and built R1-R5 (memory). Safe to merge |
| #157 | Stage C run loop | Two rounds answered, full sign-off pending (memory) |
| #197 | Garage, mod trees, other 5 player cars (Stage E + D) | 11 decisions open (memory) |
| #175 | Game narrative fabric | CI green, not reviewed |
| #177 | Rival shop, Kess rewrite, car ladder | Story, Roy's to write |
| #179 | UI blend + cockpit proposals | Answered 2026-10-07 (memory) |
| #184 | Automatic head look for mirrors | Answered (PR #219 went another way) |
| #187 | Free AI voice options | Research |
| #167, #168 | Gas station as a world destination | Duplicates of each other: keep one |
| #169, #170 | Environment plan, world-building vision | Not reviewed |
| #171, #172 | Engine mechanics spec, landmark types | Not reviewed |
| #176 | Landmarks, engine, mirrors (bundle) | Overlaps #171/#172; conflicts with main on the mirror doc |
| #173 | Cheap shadows research | "For later" |
| #216 | Sound research | Not reviewed |
| #217 | Road lane adds, drops, splits, exits | Decisions recorded; #251 builds step 1 |
| #220 | Living world proposal | Answers recorded; #225/#228/#250 build it |
| #221 | Corrupt police and Pike | Not reviewed |
| #224 | Graphics and lighting polish research | Answered 2026-10-09; graphics stack builds it |

## Branches with no open PR (not merged)

| Branch | What it is |
|--------|------------|
| `claude/project-thread-j00xpn-4` | "Rename the game to Boost Simcade" (4 files, 2026-10-08). No PR. Ask before using |
| `claude/project-thread-c0wygj-traffic-plan` | Traffic overhaul plan, docs only. No PR; the plan sign-off is still pending (memory) |
| `feat/radio-file-stations`, `pr/115` | Closed PR #115 (file-based radio). Abandoned |
| `feat/vehicle-registry`, `pr/79` | Closed PR #79. Abandoned |
| `verify-149-photo-mode-test` | Merged into #149's branch via #200; nothing extra |
| `pr-assets/g1-loft-winding`, `pr-assets/g2-glass-normals`, `screenshots/23` | Screenshot-only branches with no shared history; old PRs link their images. Keep |
| `pr/<n>` (83 unmerged) | Mirror copies of PR heads. Safe to delete once that PR is merged or closed |

## Safe to delete (merged into main)

274 remote branches are fully contained in main. Nothing was deleted. List
them with:

```
git branch -r --merged origin/main
```

They break down as 136 `pr/<n>` mirrors, 52 `feat/`, 42 `claude/`, 19
`docs/`, 15 `fix/`, 3 `perf/`, 6 others, and `main` itself. Keep the screenshot branches
above even though some PRs are merged: deleting them breaks images in old PRs.

## Known flakes (not regressions)

From memory, observed on main itself:

- Exit crash on quit in some tests (`cockpit`, `tune_persist`, `traffic_spawn`).
- `hud_rear_strip` fails about 1 run in 3 under load.
- `fx_pack` exhaust-flame check flaky on the graphics branches.
- `wall_hit` can show a single red from issue #265 (wall-box seams).
- CI "cancelled" runs: earlier runs hung on the mirrors parse error until the
  30-minute timeout; a later push to the same branch also cancels the run.

## How this was built

```
git fetch origin --prune
git branch -r --merged origin/main          # merged
git branch -r --no-merged origin/main       # not merged
git rev-list --left-right --count origin/main...<branch>
gh pr list --state open --json number,headRefName,baseRefName,isDraft,statusCheckRollup
git merge-tree --write-tree origin/main <branch>   # conflict check, no checkout
```
