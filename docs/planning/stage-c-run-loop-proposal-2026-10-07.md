# Stage C proposal: the run loop (scoring, currency, replay)

**Status: proposal only. Nothing here is built. Waiting for Roy's sign-off.**
Date 2026-10-07, checked against `origin/main` `9bf4f02` (PR #146).

**Goal:** the 20th run is still fun. A run is one drive on the highway from
spawn until you crash, bank out or quit.

**Falsification check:** if a tester quits after 3 or 4 runs, the core loop is the
problem, not the content. Fix the loop before adding cars, events or districts.

## 0. What is true on main today (not from ROADMAP)

- `ROADMAP.md` says it is synced at `284595c`; main is `9bf4f02`. Since then the
  Tuner redesign 1-4 merged (#143-#146). Stage C items are still "not started"
  there, and that is correct: no scoring, currency, crash or save code exists.
- A restart reloads the whole scene (`scripts/game_state.gd:124`). Normal play
  calls `randomize()`; benchmark mode uses a fixed seed (`scripts/game.gd:73`).
- There is **no weather system**. The fog is one fixed setting (`game.gd:114`).
- The road is straight, 4+4 lanes, from a chunk pool. Curves (#37) are not started.
- Saves already use small JSON files in `user://` and switch off in test mode
  (`tune_slots.gd`, `player_tune.gd` in open PR #156). Stage C follows that pattern.
- The talk station is "The Dave Show" (#134). The project topic still says Dale;
  the code says Dave.

## 1. Near-miss scoring and Cred

The formula already in ROADMAP, unchanged:

`event = 10 × proximity × relative_speed × timing × streak × same_car_decay`

| Factor | Value |
|---|---|
| Shell | 1.5 m around the other car's body |
| Proximity | 1.0× at the shell edge → 2.5× at contact distance |
| Relative speed | 1.0× below 20 km/h → 2.0× above 80 km/h |
| Timing | 1.5× if you steered within 0.5 s before the pass |
| Streak | +0.15× per near-miss within 4 s of the last, cap 3.0× |
| Same-car decay | 100% / 35% within 8 s / 10% / ~2% for the same car |

A near-miss counts when the player leaves another car's shell **without touching
it**. A touch cancels that event and resets the streak.

**Score** is everything you earned in a run (for the best-score table). **Cred** is
the part you banked (the currency). Section 2 explains the difference.

## 2. Risk and reward

Damage, fuel and repair costs are parked until after the garage, so in Stage C the
only things pushing back are **losing what you have not banked** and **heat**.

- **The pot.** Near-miss Cred goes into an unbanked pot. It banks after 6 s with no
  near-miss and no hit. A crash loses the pot. So every streak is a choice: keep
  threading traffic for a bigger multiplier, or ease off and bank.
- **Crash ends the run.** A hit above a speed-change threshold (v1 guess: 25 km/h)
  ends the run. Light scrapes only reset the streak. The wall fix in PR #156 keeps
  the car on its wheels, so a crash is a judgement, not a physics accident.
- **Heat** rises with each near-miss (v1 guess: +2 × streak) and with speed above
  a threshold, and cools slowly while you drive calmly. Tiers 30/60/90 raise the
  payout (×1.25/×1.5/×2.0) **and** the traffic density ahead of you. More heat
  means more money and more cars to hit. No police until Stage F; F reads the same
  heat value.
- **Later, after the garage:** damage costs Cred to repair, fuel costs Cred and
  forces stops, so a big run can still lose money. That is the second pull against
  risk. Not in Stage C.

All of these numbers are untested v1 guesses. They live as constants in **one
file**, `scripts/run_tuning.gd`, and nowhere else, so balancing is one file.

## 3. Variety per run

Every run has an integer **seed**, shown on the summary screen. Each system gets
its own random stream from it, so changing one system does not reshuffle the others.

| Seeded per run | v1 range |
|---|---|
| Road chunks | Order and roadside dressing from the existing pool |
| Traffic density | 0.6× to 1.4× the slider value, plus heat scaling |
| Time of night | Dusk, midnight or pre-dawn; all stay inside Amber vs. Dusk |
| Weather | Clear or haze (fog density) only. Rain needs wet grip and spray, so it is a later item |
| Event type | A list with one entry today ("free run"). Events slot in later |
| Weekly challenge | Stub only: a fixed seed from the calendar week, no UI |

Traffic is full-sim physics, so the same seed gives the same start, not the same
run. That is fine: we are not doing ghosts.

## 4. Mastery and retry

- **Instant retry.** One key from the summary screen restarts on a new seed;
  another retries the same seed. No menu in between, no long crash animation
  (v1: a 1 s slow-mo on impact, then the summary). Target: under 2 s from crash
  to driving. Today's restart is a full scene reload; the PR measures it and
  makes it faster only if it misses the target.
- **Run summary screen:** score, Cred banked, Cred lost in the pot, best streak,
  closest pass, top speed, heat reached, seed, and Dave's line (section 6).
  No key hints on screen; the keys go on the Controls page, as decided.
- **Local best-score table:** top 10 per car, saved to `user://run_records.json`.
- **Rejected, not proposed:** ghost cars and shareable build codes.

## 5. Meta-progression hooks (data only, no UI)

- The **Cred wallet** persists across runs (`user://wallet.json`) and is what the
  garage and per-car mod trees will spend.
- **Mod-tree node format** (data only), one tree per car:
  `id, name, cost, requires, spec_overrides, drives_differently`. `spec_overrides`
  are `CarSpec` changes, as already decided for the trees.
- **Every branch must change how the car drives**, not only numbers like power. A
  test checks that each branch touches at least one handling field (grip, steering,
  diff, weight balance, gearing, brake bias) and states the change in
  `drives_differently`. Which fields count is Roy's call.

## 6. Emergent hooks

- **Dave comments on the summary.** The run report carries tags (crashed on a big
  streak, banked a record, new best, quit early, hot heat). Dave's line is picked
  from tagged lines. The lines are placeholders for Roy to write; text only in v1.
- **Rivals remember you (data stub).** `user://rivals.json` keeps, per rival id,
  runs seen, the player's best and the last outcome. Nothing reads it yet.

## Steelman and premortem

**Steelman:** the pot is the cheapest real risk/reward we can build without
damage, fuel or police. It turns every streak into a bank-or-push decision, and
the one-file constants make balancing quick.

**Premortem (it failed; why?):**
1. **The road is straight.** Seeded density and fog do not make run 20 feel
   different from run 3. Mitigation: heat-driven traffic gives each run its own
   shape. If testers still say "it's the same road", #37 curves moves up.
2. **Heat is a free multiplier.** Without police it has no cost. Mitigation: heat
   adds traffic. If that is not enough, Stage F has to come sooner.
3. **Near-miss detection misfires** in dense full-sim traffic (double counts,
   counts through walls). Mitigation: headless tests with scripted passes before
   any HUD work.
4. **Retry is slow** because of the scene reload. Mitigation: measured in C5.

## Proposed build order (one PR each, each stops for sign-off)

| # | PR | Proof (headless) |
|---|---|---|
| C1 | `run_tuning.gd` constants, run state, crash detection ends the run | Scripted hit above and below the threshold |
| C2 | Near-miss detector and the formula | Scripted passes at set gaps and speeds give the expected values |
| C3 | Streak, pot, banking, heat gain and heat-driven density | Bank after 6 s; crash loses pot; heat tiers |
| C4 | HUD: score, streak, pot, heat (palette test) | `palette` and HUD tests |
| C5 | Instant retry and the summary screen | Crash to driving under 2 s, measured |
| C6 | Run seed and per-run variation, weekly-seed stub | Same seed gives the same start settings |
| C7 | Wallet and best-score table saves (off in test mode) | Save, reboot, read back |
| C8 | Mod-tree data format and the "drives differently" check | Bad branch fails the check |
| C9 | Dave summary lines and rival memory stub | Tags pick the right line |

After C5, a playtest of 20 runs against the falsification check, before C6-C9.

## Decisions for Roy

1. Pot and bank as the Stage C risk/reward (or straight banking with no pot)?
2. Heat adds traffic density in Stage C (or heat is payout only until police)?
3. Time-of-night variation is OK under "gritty PS2 night"?
4. Rain later, haze only now?
5. Which `CarSpec` fields count as "drives differently" for mod branches?
