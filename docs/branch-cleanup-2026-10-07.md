# Remote branch cleanup list, 2026-10-07

Read-only audit of `origin` at main `9c28d59`. Nothing was deleted or pushed. Counts: **112 remote branches besides main**: A=94 merged, B=7 unmerged work, C=3 screenshot-only, D=8 auto-named claude/project-thread-* with unmerged work (3 more auto-named ones are already merged and sit in A).

Method: `git rev-list --count origin/main..origin/<b>` for ahead count (0 = fully merged; no branch was squash-merged, so ahead 0 is reliable), PR numbers from `gh pr list --state all` by head branch.

## Keep: branches holding real unmerged work

All have an open PR except the two closed ones in B. Deleting an open-PR branch auto-closes its PR, so do not clean these until Roy has merged or dropped the PR.

### D. claude/project-thread-* (unmerged)

| Branch | Ahead | Work | PR | Last commit |
|---|---|---|---|---|
| claude/project-thread-b9p3pn | 1 | tyre smoke | #159 OPEN | Tyre smoke: heat-driven puff pool with burnout and drift sliders |
| claude/project-thread-cxizd9 | 1 | N1 commuter sedan + NPC plumbing | #153 OPEN | N1 commuter sedan in traffic, plus the shared NPC car plumbing |
| claude/project-thread-cxizd9-n2 | 2 | N2 hatchback (stacked on N1) | #154 OPEN | N2 city hatchback in traffic |
| claude/project-thread-cxizd9-n3 | 4 | N3 pickup (stacked on N2) | #155 OPEN | Add the uid file Godot made for tools/npc_shots.gd |
| claude/project-thread-d1eip6 | 2 | exhaust tuning moved to Tuner screen | #147 OPEN | Restore presets line in exhaust design doc |
| claude/project-thread-fo4arx | 1 | per-car engine voices | #152 OPEN | Per-car engine voices (#80) |
| claude/project-thread-soqei8 | 4 | Stage C proposal doc | #157 OPEN | Stage C proposal: fog rule, moon phases, High-only variation |
| claude/project-thread-wkxidv | 3 | wall fix + tune persistence | #156 OPEN | Wall contact: no tipping past 25 deg; wall_hit accepts 3 wheels down |

Note: -n2 contains N1's commit and -n3 contains N1+N2 (stacked PRs #153 -> #154 -> #155). Merge in order.

### B. Other branches with unmerged commits

| Branch | Ahead | PR | Last commit |
|---|---|---|---|
| feat/camera-smoothing-setting | 1 | #148 OPEN | Camera smoothing: pause-menu setting, saved in settings.cfg (#31) |
| feat/cockpit-shifter-modes | 1 | #151 OPEN | Cockpit gear lever follows the gearbox mode |
| feat/photo-mode | 1 | #149 OPEN | Photo mode: P pauses, free camera, HUD hidden, Enter saves a PNG |
| feat/radio-file-stations | 1 | #115 CLOSED | Radio: file-based stations replace the generated ones |
| feat/vehicle-registry | 1 | #79 CLOSED | Vehicle registry: one list of cars, model import, stock/tuned looks |
| fix/cockpit-hands-sightline | 1 | #150 OPEN | Cockpit hands: keep them 18 deg under the eye, and let urgent moves interrupt |
| fix/tuner-header-no-key-hints | 1 | #158 OPEN | Tuner header: drop (T)/(Y) key hints from the tab buttons |

**Closed, never merged:** `feat/radio-file-stations` (#115, 55 files, +1899/-104) and `feat/vehicle-registry` (#79, 21 files, +541/-35). Radio files shipped via #125, so these are probably superseded, but they are the only unmerged work with no open PR. Roy should decide before they go.

### C. Screenshot/asset-only branches (not for merging)

| Branch | Ahead | Last commit |
|---|---|---|
| pr-assets/g1-loft-winding | 1 | Screenshots for the G1 loft winding PR (not for merging) |
| pr-assets/g2-glass-normals | 1 | Screenshots for the G2 glass loft normals PR (not for merging) |
| screenshots/23 | 1 | Screenshots for PR (issue #23): driver camera before/after road winding fix. Not for merging. |

These carry images linked from PR descriptions. Deleting them breaks those images, so they are left out of the A delete command.

## A. Fully merged into main (safe to delete)

| Branch | PR |
|---|---|
| chore/dale-to-dave | #134 |
| claude/inspiring-wright-ddf8a6 | #160 |
| claude/project-thread-4dh1kq | #132 |
| claude/project-thread-53k0oc | #117 |
| claude/project-thread-j3zpos | #133 |
| cleanup/dead-code-section-d | #3 |
| docs/33-friction-convention | #52 |
| docs/42-class-cache | #46 |
| docs/48-queue-access | #77 |
| docs/audio-proposal | #9 |
| docs/audit-2026-10-06 | #118 |
| docs/build-phases | #98 |
| docs/car-feel-research | #94 |
| docs/car-feel-research-2 | #96 |
| docs/g1-winding-diagnosis | #47 |
| docs/issues-add-80 | #81 |
| docs/issues-resolved | #64 |
| docs/issues-sync-main | #76 |
| docs/pr-workflow | #1 |
| docs/retire-handoff | #44 |
| docs/roadmap-car-culture | #83 |
| docs/roadmap-merged-prs | #136 |
| docs/roadmap-night-lighting-approved | #2 |
| docs/sync-oct6 | #120 |
| docs/sync-roadmap-issues | #111 |
| feat/27-game-state | #56 |
| feat/31-camera-smoothing | #61 |
| feat/62-tuning-panel | #69 |
| feat/63-test-car | #68 |
| feat/autotune | #88 |
| feat/autotune-4-goals | #90 |
| feat/cockpit-driver | #131 |
| feat/cockpit-head-motion | #138 |
| feat/cockpit-interior | #130 |
| feat/cockpit-sightline | #137 |
| feat/feel-pass-1 | #95 |
| feat/feel-quickwins | #119 |
| feat/fov-setting | #135 |
| feat/fx-pack-1 | #124 |
| feat/gevp-engine-1b | #97 |
| feat/hud-rear-strip | #139 |
| feat/hud-v1 | #121 |
| feat/look-back | #140 |
| feat/mute-option | #91 |
| feat/p1-coupe-model | #123 |
| feat/phase-a | #99 |
| feat/phase-b-audio | #104 |
| feat/phase-b-chassis | #101 |
| feat/phase-b-heat | #103 |
| feat/phase-b-radio | #105 |
| feat/phase-b-turbo | #102 |
| feat/phase-c-120hz | #110 |
| feat/phase-c-clutch | #106 |
| feat/phase-c-cockpit | #108 |
| feat/phase-c-radio2 | #109 |
| feat/phase-c-tyres | #107 |
| feat/radio-files-small | #125 |
| feat/road-space | #141 |
| feat/stage-a-feel-env | #84 |
| feat/stage-b1-4-stickers | #93 |
| feat/stage-b1-audit | #86 |
| feat/stage-b1-design-sheet | #85 |
| feat/stage-b2-exhaust | #92 |
| feat/steer-cap-and-boundary | #114 |
| feat/steer-feel | #126 |
| feat/takeover-feel-test | #82 |
| feat/traffic-lanes | #113 |
| feat/traffic-m4 | #127 |
| feat/transmission-modes | #142 |
| feat/tuner-1-tyre-model | #143 |
| feat/tuner-2-settings | #144 |
| feat/tuner-3-screen | #145 |
| feat/tuner-4-mechanic | #146 |
| feat/tuner-one-screen | #122 |
| feat/tuner-reverse | #100 |
| fix-75-brake-multiplier | #78 |
| fix/19-benchmark-mode | #49 |
| fix/23-road-winding | #54 |
| fix/26-floating-origin | #58 |
| fix/34-aero-downforce-names | #53 |
| fix/35-sidewalk-collision-taper | #60 |
| fix/auto-tune-panel | #116 |
| fix/car-audio-flaky | #112 |
| fix/chunk-builder-nodepath | #4 |
| fix/flaky-tests | #87 |
| fix/linear-damp-zero | #89 |
| fix/recenter-wheel-kick | #129 |
| fix/test-hygiene | #128 |
| perf/24-draft-grid | #51 |
| perf/25-glow | #67 |
| perf/39-benchmark-stats | #65 |
| proto/synth-engine-audio | #57 |
| refactor/29-30-inputmap | #66 |
| test/39-smoke-test | #50 |

### Commands for Roy (not run)

Deleting a remote branch does not move HEAD, so any checkout works.

```
git push origin --delete \
  chore/dale-to-dave \
  claude/inspiring-wright-ddf8a6 \
  claude/project-thread-4dh1kq \
  claude/project-thread-53k0oc \
  claude/project-thread-j3zpos \
  cleanup/dead-code-section-d \
  docs/33-friction-convention \
  docs/42-class-cache \
  docs/48-queue-access \
  docs/audio-proposal \
  docs/audit-2026-10-06 \
  docs/build-phases \
  docs/car-feel-research \
  docs/car-feel-research-2 \
  docs/g1-winding-diagnosis \
  docs/issues-add-80 \
  docs/issues-resolved \
  docs/issues-sync-main \
  docs/pr-workflow \
  docs/retire-handoff \
  docs/roadmap-car-culture \
  docs/roadmap-merged-prs \
  docs/roadmap-night-lighting-approved \
  docs/sync-oct6 \
  docs/sync-roadmap-issues \
  feat/27-game-state \
  feat/31-camera-smoothing \
  feat/62-tuning-panel \
  feat/63-test-car \
  feat/autotune \
  feat/autotune-4-goals \
  feat/cockpit-driver \
  feat/cockpit-head-motion \
  feat/cockpit-interior \
  feat/cockpit-sightline \
  feat/feel-pass-1 \
  feat/feel-quickwins \
  feat/fov-setting \
  feat/fx-pack-1 \
  feat/gevp-engine-1b \
  feat/hud-rear-strip \
  feat/hud-v1 \
  feat/look-back \
  feat/mute-option \
  feat/p1-coupe-model \
  feat/phase-a \
  feat/phase-b-audio \
  feat/phase-b-chassis \
  feat/phase-b-heat \
  feat/phase-b-radio \
  feat/phase-b-turbo \
  feat/phase-c-120hz \
  feat/phase-c-clutch \
  feat/phase-c-cockpit \
  feat/phase-c-radio2 \
  feat/phase-c-tyres \
  feat/radio-files-small \
  feat/road-space \
  feat/stage-a-feel-env \
  feat/stage-b1-4-stickers \
  feat/stage-b1-audit \
  feat/stage-b1-design-sheet \
  feat/stage-b2-exhaust \
  feat/steer-cap-and-boundary \
  feat/steer-feel \
  feat/takeover-feel-test \
  feat/traffic-lanes \
  feat/traffic-m4 \
  feat/transmission-modes \
  feat/tuner-1-tyre-model \
  feat/tuner-2-settings \
  feat/tuner-3-screen \
  feat/tuner-4-mechanic \
  feat/tuner-one-screen \
  feat/tuner-reverse \
  fix-75-brake-multiplier \
  fix/19-benchmark-mode \
  fix/23-road-winding \
  fix/26-floating-origin \
  fix/34-aero-downforce-names \
  fix/35-sidewalk-collision-taper \
  fix/auto-tune-panel \
  fix/car-audio-flaky \
  fix/chunk-builder-nodepath \
  fix/flaky-tests \
  fix/linear-damp-zero \
  fix/recenter-wheel-kick \
  fix/test-hygiene \
  perf/24-draft-grid \
  perf/25-glow \
  perf/39-benchmark-stats \
  proto/synth-engine-audio \
  refactor/29-30-inputmap \
  test/39-smoke-test
```

Optional afterwards: `git fetch --prune`.
