# Project state

A snapshot of branches and pull requests. **Check it against git before you rely
on it**: run `git fetch origin`, then `gh pr list --state open`. Every claim below
was checked on 2026-10-09 against `origin/main` **282343f** (the merge of #266,
buildings on main) with `git merge-base --is-ancestor`, `git cherry` and
`git merge-tree`.

Update this file when a PR merges or a stack changes, in the same PR where you can.

## Main

`origin/main` is 282343f. Recent merges: #266 buildings 1–5 (replaces #206–#210),
#223 combined build (replaces #191 and carries 21 PRs), #225 night clock,
#222 sound fixes, the curves and hills stack #202–#213, and settings safety #190–#203.

## 1. Already in main: close these, there is nothing left to merge

Their head commit is already part of main, through the combined build or the
buildings merge, so merging them does nothing.

| PR | What | Came in through |
|---|---|---|
| #154 | Traffic cars 2/3: N2 hatchback | #223 combined build |
| #155 | Traffic cars 3/3: N3 pickup | #223 |
| #178 | Night lights: tail and brake lamps, flares, reflectors | #223 |
| #207–#210 | Buildings 2/5 to 5/5 | #266 |
| #201 | Exhaust pop voice (rebased copy) | #166: the same patch, with no unique commit |

## 2. Ready to merge: not drafts, and they merge cleanly into main today

These are all docs and can merge in any order.

| PR | What | Note |
|---|---|---|
| #157 | Stage C proposal: the run loop | Roy answered 4 questions; it still needs full sign-off |
| #162 | Design note: settings safety | built and merged as #190–#203 |
| #163 | Docs: remote branch cleanup list | may be stale after #223 and #266; reread it first |
| #165 | Curves and elevation proposal | built and merged as #202–#213 |
| #149 | Photo mode | GitHub shows a conflict, but it merges cleanly onto 282343f; refresh the branch first |

`#161` (ROADMAP sync to 9c28d59) conflicts with main, and this file replaces it, so close it.

## 3. Drafts that merge cleanly into main

Their authors have not marked these ready. They are listed so the merge order is
clear once each one is reviewed or playtested.

| PR | What |
|---|---|
| #218 → #226 → #227 | Line lock, then traction control, then the TC lamp (stacked) |
| #238 | Version number and licence notices |
| #251 | Road layout plan, step 1 (not live) |
| #254 | Benchmark drives again, cached road lookups (#268 and the new perf PR both contain it) |
| #267 | Mod tree foundation |
| docs drafts | #167 #168 #169 #170 #171 #172 #173 #175 #177 #179 #184 #187 #197 #214 #216 #217 #220 #221 #224 |

## 4. Stacks whose parent already merged: retarget them to main

The base branch has merged, so each PR should be retargeted to `main`
with `gh pr edit <n> --base main`.

| PR | Old base (merged as) | Merges into main |
|---|---|---|
| #205 Tyre smoke v2 | #159 | cleanly |
| #228 → #250 Living world 2 and 3 | #225 | cleanly |
| #237 Road sounds | #222 | cleanly |
| #253 Fleet cars P2–P6, C1–C3 | #155 (in main) | cleanly |
| #215 Radio volume knob | #191 | **conflicts**, needs a rebase |
| #262 More shop signs | #207 (in main) | **conflicts**, needs a rebase |

## 5. Conflict with main: these need a rebase before review

| PR / stack | What |
|---|---|
| #192 → #194 → #195 | UI blend 1–3 |
| #199, #219 | Cockpit mirrors (#219 supersedes #199, so close #199) |
| #229 → #234 → #240 → #263 | Driving feel 1/2 and 2/2, extras, slide-catch |
| #230 → #235 → #239 → #242 → #243 → #244 | Tuner UI overhaul 1–5, vanity plates |
| #231 → #245 → #246 → #248 → #256 | Menus 1–5 |
| #232 → #236 → #241 → #247 → #257 → #258 → #259 → #260 → #261 | Graphics settings, film look, paint, lamps, brake discs, Test my PC, wet roads |
| #233, #249 | Crash-safe saving; Open log folder button |
| #252 | Interiors 1: P1 cabin and cluster |
| #255 | Lane threading, step 0 |
| #264 | Cleanup plus perf report |
| #268 | Perf: engine sound off the main thread (the new perf PR rebases it onto main, see below) |
| #176 | Proposal docs bundle (2026-10-07) |

Only each stack's first PR was tested against main. The later PRs in a stack
inherit the same rebase.

## Frame rate (game speed optimisation)

- #254 and #268 found the game is CPU-bound on integrated graphics; #268 moves
  engine sound off the main thread.
- A new perf PR (branch `claude/project-thread-9mh8ag`) brings #268 onto today's
  main, with the conflicts resolved, and adds exact-math caches to the road lookups.
  It is in progress.
- Headless CPU ms per 60 fps frame, with 16 cars at 150 m, on the same machine with
  the runs interleaved: main ~18 ms, #268 on main ~11.3–11.6 ms, the new PR ~10.6–11.3 ms.
- Traffic cost by setting (new PR, mean headless CPU ms/frame): 0 cars 5.4; 8 cars
  8.4–11.2; 16 cars 14.3–16.9; 24 cars 18.6–21.0. Car count is the big lever;
  the Draw dist slider changes little. Other agents' Godot runs were loading the
  CPU, so expect about ±10% noise.
- The bigger wins need Roy's call: optimising the vendored GEVP code (with
  identical results), or a 60 Hz physics option.

## Queue

The Agent Office queue only works from the dispatcher's terminal: `office-queue`
needs credentials that workers don't have. Sections 1, 2 and 4 are the list to queue.
