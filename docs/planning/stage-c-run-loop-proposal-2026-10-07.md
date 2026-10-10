# Stage C proposal: the run loop (scoring, currency, replay)

**Status: proposal only. Nothing here is built. Roy answered four questions on
2026-10-07; waiting for sign-off on the whole page.**
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
  payout (×1.25/×1.5/×2.0). **Roy, 2026-10-07: more heat brings police into the
  traffic.** Cop cars do not exist yet (Stage F), so in Stage C heat raises payout
  only and records the tier; Stage F spawns police traffic from the same heat value.
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
| Traffic density | 0.6× to 1.4× the slider value |
| Time of night | Dusk, midnight or pre-dawn; all stay inside Amber vs. Dusk |
| Weather | Clear or haze only, and haze only goes **denser** than today's 0.009 (see the fog rule below). Rain needs wet grip and spray, so it is a later item |
| Moon | **Roy, 2026-10-07: a phasing moon**, not always full. The seed picks the phase; a visible moon disc (silver) and the existing moonlight key light (`game.gd:154`) scale with it |
| Event type | A list with one entry today ("free run"). Events slot in later |
| Weekly challenge | Stub only: a fixed seed from the calendar week, no UI |

**Fog rule (the conflict).** The haze is not only weather. Since Stage A it also
hides the short draw distance (`game.gd:100-116`: "a warm dark haze that swallows
the distance", which makes the short draw distance free). Thinner haze would show
road chunks and frozen traffic popping in at the 150 m detail distance and cost
frame rate. So per-run haze may only be the same or denser, never thinner.

**Graphics setting.** Roy wants the night and weather variation in any game mode,
but only on the High graphics setting. There is no global graphics preset today
(only mirror quality in `fx_settings.gd`), so C6 adds a Low/High preset; Low keeps
today's fixed look.

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
  test checks that each branch touches at least one handling field and states the
  change in `drives_differently`. Handling fields (Roy picked the first four; the
  rest come from `scripts/car_spec.gd`):

  | Group | `CarSpec` fields |
  |---|---|
  | Grip / tyres | `coefficient_of_friction`, `tire_stiffnesses`, tyre pressure, camber, toe, `tyre_load_sensitivity` |
  | Steering / diff | `max_steering_angle`, locking-diff engage torque front/rear |
  | Weight / balance | `vehicle_mass`, `front_weight_distribution`, `front_brake_bias`, `center_of_gravity_height_offset` |
  | Gearing | `gear_ratios`, `final_drive`, `shift_time` |
  | Suspension (proposed) | damping ratios, anti-roll bars, spring lengths (ride height) |
  | Aero (proposed) | downforce front/rear, `coefficient_of_drag` |
  | Drivetrain (proposed) | `front_torque_split` (RWD to AWD changes the car most) |
  | Power delivery (proposed) | `torque_shape`, `turbo_boost_max` (turbo lag), `throttle_speed`, `motor_brake` |
  | Driver aids (proposed) | traction control, stability, ABS thresholds |

  Power-only nodes (`max_torque`, `max_rpm`) are allowed inside a branch, never as
  a whole branch. Exhaust stays cosmetic and never counts. Coloured tyre smoke
  (Roy, 2026-10-07, for later) is a cosmetic mod and never counts either.

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
   different from run 3. Mitigation: per-run density and night phase, then
   police traffic in F. If testers still say "it's the same road", #37 curves moves up.
2. **Heat is a free multiplier** until police exist. Roy's answer is police
   traffic, which is Stage F. If heat feels free in the C playtest, F comes sooner.
3. **Near-miss detection misfires** in dense full-sim traffic (double counts,
   counts through walls). Mitigation: headless tests with scripted passes before
   any HUD work.
4. **Retry is slow** because of the scene reload. Mitigation: measured in C5.

## Proposed build order (one PR each, each stops for sign-off)

| # | PR | Proof (headless) |
|---|---|---|
| C1 | `run_tuning.gd` constants, run state, crash detection ends the run | Scripted hit above and below the threshold |
| C2 | Near-miss detector and the formula | Scripted passes at set gaps and speeds give the expected values |
| C3 | Streak, pot, banking, heat gain and payout tiers | Bank after 6 s; crash loses pot; heat tiers |
| C4 | HUD: score, streak, pot, heat (palette test) | `palette` and HUD tests |
| C5 | Instant retry and the summary screen | Crash to driving under 2 s, measured |
| C6 | Run seed and per-run variation, moon phases, Low/High graphics preset, weekly-seed stub | Same seed gives the same start settings; haze never below 0.009 |
| C7 | Wallet and best-score table saves (off in test mode) | Save, reboot, read back |
| C8 | Mod-tree data format and the "drives differently" check | Bad branch fails the check |
| C9 | Dave summary lines and rival memory stub | Tags pick the right line |

After C5, a playtest of 20 runs against the falsification check, before C6-C9.

## Roy's answers (2026-10-07)

1. Pot and bank: **yes**.
2. Heat: **payout, and more heat brings police into traffic** (police in Stage F;
   payout only in C).
3. Time-of-night variation and haze now, rain later: **yes**.
4. Handling fields: grip/tyres, steering/diff, weight/balance, gearing, **plus
   research for more**; the proposed extra groups are in section 5 for sign-off.

5. Second round: pot **A** (pot + bank); heat **yes**; variety **any mode, High
   setting only**; a phasing moon; coloured smoke later as a mod.

Still open: sign-off on the whole page and on the extra field groups.
