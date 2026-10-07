# Settings safety: show the cost, allow the extremes (2026-10-07)

Status: **proposal, docs only. Nothing built. Needs Roy's sign-off.**
Source read: `origin/main` at `9c28d59`, re-checked against `04466a5` (no setting
ranges changed; the new mirror glance is not a setting). Evidence: two headless sweeps on the
`TuneTrack` (accel, brake, fixed-steer corner on the default coupe), 82 + 25
runs, plus a NaN round-trip check. Scratch scripts, not committed.

## Roy's decisions this builds on (2026-10-07)

1. **Clamp only to keep the car drivable.** Ranges come from what the sim
   survives, not from taste. Fun extremes stay in.
2. **Live consequence line** under each risky setting: one line, real tuning
   terms, changes with the value.
3. **Danger zone:** the bar goes green, amber, red toward the edges; the
   existing before/after stat bars show the cost.
4. **Safety net:** per-page Reset to stock, the Test run, and an auto-revert
   when the car becomes undrivable.
5. **Advanced gate:** extreme values live in Advanced behind a one-time
   confirm. Everything there stays recoverable.

## What "drivable" means here (the hard clamp line)

A value is **clamped out** only if the track run fails: flips, can't reach
100 km/h, or produces a non-finite number. A value that **spins the car**
(slip over 25 deg; stock is 4.6) or costs a lot of pace is **red, not
clamped**. Normal pages keep today's no-spin ranges; Advanced gets the wide
ones.

Danger colours, all already in `hud.gd:19-24`: green `#3FD060` (RPM bar),
amber `#FFC066`, red `#E5262B`. The bar's selection colour stays sodium.
Green = within about 10% of stock on every stat. Amber = one stat 10-30%
worse, or slip 15-25 deg. Red = spins, or a stat over 30% worse.

## Per-setting table: Tuner

"Today" is the UI range (`tuner_model.gd`, `tuning_panel.gd`). "Advanced" is
the proposed hard limit. Evidence = sweep result at the tested value.

| Page | Setting | Today | Advanced (hard clamp) | Evidence at extremes | Amber / red | Consequence line (low / high) |
|---|---|---|---|---|---|---|
| Tyres | Compound friction | choice ×0.92-1.1 | 0.5-3.5 | 0.4 drives but spins (82 deg); 0.8 spins; 4.0 grips 4.9 g then spins | red <0.9, >2.8 | "Hard compound: slides early, easy to catch" / "Sticky: huge grip, snaps when it lets go" |
| Tyres | Longitudinal grip | hidden | 0.45-2.0 | **0.3 and 0.2 flip** on launch; 0.4 drives, spins | red <0.7 | "Wheels spin up easily, rear light under power" / "Hooks up hard off the line" |
| Tyres | Tyre stiffness | hidden | 4-20 | 2-25 all fine | none | "Soft carcass: progressive, vague" / "Stiff: sharp, less warning" |
| Tyres | Pressure F / R | 1.6-2.8 | 1.0-3.6 | front 0.8-4.0 fine; **rear 0.8 and 4.0 spin** | rear red <1.4, >3.0 | "Low: bigger contact patch, mushy turn-in" / "High: crisp, less grip at the limit" |
| Tyres | Camber F / R | -4..+1 | -8..+3 | front -10 halves lateral g; **rear -10/+4 spin** | red past -6 / +2 | "More negative: grip in long corners, worse braking" |
| Tyres | Toe F | ±0.02 rad | ±0.06 | ±0.08 fine, -7% top speed | amber past ±0.04 | "Toe-in: stable, lazy" / "Toe-out: darty turn-in, wanders" |
| Tyres | Toe R | 0..0.02 | -0.03..+0.05 | **toe-out -0.04 spins** (cut today); +0.06 fine | red <0 | "Toe-out: rear steers itself, loose" / "Toe-in: planted rear" |
| Suspension | Ride height F / R | .16-.28 / .18-.27 | 0.08-0.40 | all drivable; rear 0.45 spins, 0-100 8.6 s | rear red >0.30 | "Low: less roll, bottoms out" / "High: more weight transfer, rolls" |
| Suspension | Springs F / R | .3-.7 / .3-.55 | 0.15-1.0 | rear 0.1 and 1.2 spin; rear 1.2 0-100 15 s; front 1.2 understeers | rear red <0.25, >0.65 | "Soft: grip over bumps, slow response" / "Stiff: sharp, rear steps out on power" |
| Suspension | Dampers F / R | .25-.9 | 0.1-1.5 | 0.02-2.0 no change (track can't see bounce) | amber outside .2-1.2 | "Soft: floaty, bounces after kerbs" / "Hard: skips over bumps" |
| Suspension | Anti-roll bar F / R | .1-.6 / 0-.45 | 0-1.2 | rear 1.5 spins | rear red >0.6 | "Front bar: more understeer" / "Rear bar: rotates, can snap" |
| Gearbox | Final drive | 2.5-5.5 | 2.0-7.0 | 1.5: 0-100 10 s; 8.0: top 127 km/h | amber <2.8, >5.0 | "Long: top speed, slow launch" / "Short: punchy, runs out of gears" |
| Gearbox | Gears 1-5 | 0.5-4.5 | 0.5-5.0, **each gear shorter than the one before** | gear 1 **0.3 never reaches 100**; 0.5 does (22 s) | red gear 1 <1.2 | "Gear N tops out at X km/h" (readout already computes it) |
| Engine | Peak torque | 150-900 | 150-1500 | **120 never reaches 100**; 1500 fine | none (upgrade, not risk) | "More torque: wheelspin in low gears" |
| Engine | Redline | 4000-10000 | 3500-13000 | **2500 never reaches 100**; 3500 fine; 13000 top 294 | amber <4500 | "High redline: longer gears usable" |
| Engine | Boost | 0-1.5 | 0-3.0 | 3.0 fine | none | "More boost: more lag, more power up top" |
| Engine | Torque at redline | 0.2-1.0 | 0.1-1.5 | **0.0 never reaches 100**; 0.1 top 100 km/h | red <0.2 | "Power dies near the limiter" / "Pulls to the limiter" |
| Engine | Low end / peak / plateau | various | 0-1 each | all fine | none | "Torque arrives early / late" |
| Diff | Diff lock rear | 0-1000 | 0-3000 | 0 fine; 1000-3000 fine; **5000 flipped once** (single run, repeat before build) | amber >1500 | "Locked: both wheels push, understeer, easy drifts" / "Open: inside wheel spins" |
| Brakes | Brake pressure | 1-3 | 0.5-6.0 | 0.2 stops in 203 m; 6.0 in 23 m | red <1.0 | "Weak brakes: long stops" / "Strong: easy to lock without ABS" |
| Brakes | Brake bias | .45-.75 | 0.2-0.95, plus an **Auto** notch | 0.0 and 1.0 fine in a straight line; corner braking **not measured** | red <0.4, >0.85 | "Rear-biased: rotates on entry, can spin" / "Front-biased: safe, pushes wide" |
| Aero | Front downforce | 0-1 | 0-2.5 | 1.5 spins (71 deg); 4.0 top 155 | red >1.2 | "Front bite, rear goes light at speed" |
| Aero | Rear wing | 0-1.2 | 0-3.0 | **0 spins** (36 deg); 4.0 top 150 | red <0.15; amber >2 | "No wing: loose at speed" / "Big wing: planted, slow on straights" |
| Assists | Traction control | Off/Low/High | 0-20 | track shows no effect (it doesn't stress TC) | none | "Off: wheelspin is yours to manage" |
| Assists | Stability | Off/Low/High | 0-12 | no effect on track | none | "Off: the car will let you spin" |
| Assists | ABS | Off/On | threshold 4-100, Off = truly off | front 0.5 stops in 67 m | none | "Off: locked wheels don't steer" |
| Assists | Steering lock | 30-50 deg | 20-60 deg | 11-69 deg fine | amber >55 | "More lock: tighter turns, twitchy at speed" |
| Sound | Loudness, rasp, pops, flame, anti-lag | 0-1 | unchanged | cosmetic; load already clamps and type-checks | none | static description only |

Hidden values (drag, lateral grip assist) stay hidden: drag is rewritten by
the aero page, and the assist is a sim crutch, not a tuning term.

## Per-setting table: other settings (pause menu)

Main has only seven sliders (`pause_menu.gd:79-118`). **Graphics, display,
chase-camera FOV, camera, tyre smoke and effects toggles have no UI on main**
(smoke is PR #159, unmerged; FX toggles are file-only in `[fx]`). They get the
same pattern when they are built.

| Setting | Range | Can it break? | Proposal |
|---|---|---|---|
| Volumes ×4 | 0-1 | no | no danger zone |
| Cars | 0-80, step 5 | 80 cars at draw 300 is roughly 15-29 ms physics per tick (budget ~4 ms): a slideshow, menu still works | consequence line "Heavy on the CPU"; amber when cars × draw estimate passes 70% of budget, red past 100%. Fix step (default 16 can't be reselected) |
| Draw distance | 50-300 | multiplies the cars cost | shares the cars estimate |
| Cockpit FOV | 55-78 | no; NaN in the file breaks the cockpit view | no danger zone; "Wider: more side view, feels slower" |

## Safety net

- **Reset to stock on every page**, resetting only that page's paths to the
  car's own stock (today only the global Stock preset does, and Advanced
  "Reset" goes to game-start values).
- **Test run** gains a cancel and a timeout (today a hung worker leaves it on
  "Testing..." forever). It reports "Spins in the corner test" or "Can't reach
  100 km/h" in words, not just numbers.
- **Auto-revert.** After leaving the Tuner with any red value, a watchdog runs
  for the first 20 s of driving. Triggers: a non-finite car state (revert at
  once, no dialog); upside down for 3 s; full throttle for 8 s without passing
  30 km/h. On trigger, a dialog "Tune looks undrivable: car flipped. Keep /
  Revert" counts down 10 s with Revert focused and chosen on timeout. Spins do
  **not** trigger it: spinning is the fun extreme. The same dialog becomes the
  display-settings confirm when resolution settings exist (none on main yet).

## Advanced gate and recoverability

- First entry to Advanced shows one confirm: "Values here can make the car
  spin or crawl. Reset to stock always works." Seen-flag saved in
  `settings.cfg`.
- **Reset to stock never reads saved data**: it rebuilds from `CarSpec`.
- **Every write checks finiteness.** `set_param` and every settings load
  reject NaN and inf and keep the old value. Verified today: `clampf(NaN)`
  returns NaN, a ConfigFile `nan` loads as NaN, and `JSON.stringify` writes NaN
  as `null`, which then makes `TuneSlots.apply` raise a script error mid-way
  (a half-applied tune).
- **Slot loading validates per value** and skips bad entries instead of
  failing part-way.
- **An unreadable `tune_slots.json` is copied aside**
  (`tune_slots.bad.json`) before the next save; today the next save silently
  wipes every slot.

## Bugs the audit found (fixed in the build PR, not here)

1. NaN path above (slots and `settings.cfg`).
2. Slot wipe on a corrupt file.
3. Brake bias 0-0.45 reachable from a slot file; Auto (-1) lost after one nudge.
4. ABS "Off" is threshold 40, not off.
5. Diff "Open" (1000 Nm) still locks in 1st: axle torque there is about 5100 Nm.
6. Gear order not enforced, only flagged.
7. Test run has no timeout or cancel.
8. Cars slider step 5 vs default 16.
9. `[fx]` bools: the string "false" reads as true.

## Premortem

- **The track is blind to some settings.** Dampers, TC, stability and
  corner-braking bias showed no effect, so their thresholds are judgement,
  not measurement. Fix: add a braking-in-a-turn run before building.
- **Thresholds are coupe-only.** Six player cars differ; red lines should be
  stored per car or as offsets from each car's stock, measured by a sweep per
  car.
- **Red everywhere teaches players to ignore red.** Normal pages stay inside
  no-spin ranges, so red appears only in Advanced.
- **The rear diff 5000 flip** was one run; it could be sim noise. Repeat
  before relying on 3000 as the cap.
- `tests/tuner_settings.gd` asserts "no spin" at range ends. It must split:
  Normal ends must not spin; Advanced ends must stay finite, upright and
  reach 100 km/h.

## For Roy

1. Sign off the Advanced ranges in the table (or name ones to widen).
2. Auto-revert triggers: flipped, stuck, non-finite. Spins excluded. OK?
3. Red-zone threshold rule (spin or 30% loss). OK?
