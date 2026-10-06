# Decision: turning Neon Overdrive into a car-culture game

> **Status note, 2026-10-06 (the record below is unchanged).** Three lines in
> section 1 are out of date:
> - "a 60 Hz physics tick" is superseded: physics has run at **120 Hz** since
>   PR #110 (tests run at 60 via `NEON_TICKS=60`; see ROADMAP).
> - "the vehicle registry (PR #79)" was never merged: #79 is closed and its
>   import pipeline is not used (ROADMAP "Decisions still valid").
> - "the tuning panel and upgrade tree": the tuning panel (#69) and Auto-Tune
>   shipped; the single shared upgrade tree is replaced by one branching mod tree
>   per car (ROADMAP; answers GitHub #71). Nothing of the tree is built.
>
> Also since then: traffic shipped as full-sim lane-follow cars (#113), which
> bears on section 3 ("rival and crew cars stay scripted"); that is an open
> question for Roy in ROADMAP "Open for Roy".

**Meeting:** 58d57ceb, 2 rounds (chair, pragmatist, skeptic, simplifier, nerd). Written 2026-09-30.
**Prompt (Roy):** "I wish to create a car game. i want it to be about car culture. pulls, good driving, some drifting"
**Status:** these are the meeting's recommendations. Roy has approved the direction but not the build order below. Nothing here is built until he signs off.

## What was decided

### 1. Reshape Neon Overdrive; don't start a new project (unanimous, Roy confirmed)

- **Keep:** the GEVP car at a 60 Hz physics tick (it breaks at 30 Hz), the vehicle registry (PR #79), the tuning panel and upgrade tree, the chunk-built road, and the gritty PS2 night look Roy chose.
- **Replace:** the endless-highway survival loop.
- **Park, don't delete:** fuel, stop places and damage-ends-run.

### 2. Priorities are pulls first, good driving second, takeovers third (unanimous, Roy confirmed)

- **Pulls:** dig races and roll races.
- **Good driving:** highway runs and touge.
- **Takeovers:** "drifting" means US burnouts, donuts and street takeovers, not Japanese angle drifting. The simplifier owns takeover design, and Roy has asked for that to go bigger than plain drifting.
- **Why:** these are Roy's own rankings, given twice in two sessions.

### 3. The first build is a scripted rival car, not a full night loop

The nerd checked `origin/main`. **The game has no other cars: no traffic, no rival and no AI** (`player.gd:135`). Every race idea needs at least one other car, so that is the real first cost.

- The rival follows a speed-over-time curve along a lane. It does not run its own GEVP physics.
- **Why:** it's cheap, it can't spin out, and difficulty is easy to tune. It also fits two other constraints:
  - Roy said skill events must be forgiving.
  - The laptop has a CPU ceiling of about 70–75%. Several full-physics cars at 60 Hz is a real risk, so rival and crew cars stay scripted by default.
- **For roll races and bar battles**, the rival gets a small layer that reacts to the gap, so the race doesn't feel like racing a ghost (the skeptic's point). That reaction must stay **visible and fair**, like Tokyo Xtreme Racer's bar, never hidden catch-up. The research showed players have resented hidden catch-up AI for twenty years.

### 4. Milestone 1 is a dig race, then a roll race, on the empty straight against that rival

- **Dig first:**
  - It has the fewest parts: start, countdown, finish, and the rival's curve.
  - It uses the launch hooks GEVP already has: `clutch_out_rpm` and traction control.
  - Roy picked full steering for dig races.
- **Roll next:** the same race plus a 40 mph pace phase and a three-honk start.
- **Skill check before building the strip (the skeptic's point):** a keyboard throttle is on or off. The dig race needs **manual shifting and a launch-rpm window**, or the tune decides the winner and it's a stat check. The spike checks this first.

### 5. In parallel, a menu-only mock of one week (no driving)

- **What it is:** day result → night choice → money, rep and bills → next day, all on menus.
- **Why:** the skeptic's argument won this one. A racing slice only proves the part we already believe in. The unproven bet is the loop itself: choosing how to spend each night. The other session's research names **NFS Unbound's calendar**, which players hated, as the closest thing to it.
- **Payoff:** a cheap mock lets Roy judge whether choosing nights feels like freedom or like chores, before any of it is built properly.

### 6. The takeover feel check runs on the side

- **What it is:** can the current car hold a burnout and spin a donut on a keyboard? This is a tuning spike, with line lock as a small GEVP patch.
- **Status:** it is already open as **PR #82**.
- **Why:** if the car can't do it, the takeover pillar needs physics work, and we should know that early.

### 7. Traffic becomes its own milestone, before any event that needs it

The following all need traffic, so none of them come before the traffic milestone:
- roll races threaded through traffic;
- highway runs in traffic;
- near-miss scoring;
- police.

## Options that lost, and why

| Option | Proposed by | Why it lost |
|---|---|---|
| **Full one-week slice as milestone 1** (day job board, night menu, bills, dig and roll) | Chair (PR #83 roadmap) | Too many systems at once: they get playtested as half-finished things. Split into the rival and races (4) plus the menu-only week mock (5). |
| **Roll race in highway traffic as the whole slice** | Simplifier | Right instinct to cover pulls and good driving in one event, but **traffic doesn't exist**. It needs a milestone of its own first. |
| **Dig race plus a drift lot** | Pragmatist | Written before Roy moved drifting to third place and redefined it as takeovers. |
| **Timed near-miss highway run** | Chair's open question | Needs traffic *and* near-miss detection, and it is the old survival loop again. The bar battle needs only the rival, so it wins on cost and on fit. |
| **Police heat in the first slice** | Chair's open question | Unanimous no. Cops are chasing AI, which is harder than a scripted rival. It comes after traffic, and belongs with takeovers. |
| **Day-job minigame, or the shop truck, in the slice** | Chair's open question | Roy's newest input makes the day job **driving the shop truck** (tows and deliveries), which needs a second vehicle setup. The week mock stands in for it for now. |
| **Full-physics AI rivals** | (implied) | CPU ceiling, and punishing. Roy wants forgiving skill events. |

## Still open (Roy decides)

1. **Forced top 3.** Across two sessions Roy has picked about 90 ideas and said "and more" each round, with nothing ranked. The skeptic's recommendation is one question before any slice goes to him: "which 3 things must the game have on day one?" Otherwise "measure it out at the end" never arrives.
2. **PR #83 needs amending before merge.** Two problems:
   - It says the road generator, **traffic** and near-miss work are kept and reused. Traffic and near-miss were never built.
   - Its milestone 1 is the full one-week slice that this meeting split up (decisions 4 and 5).

   Roy should see both corrections before merging.
3. **Two idea pages disagree in places:**
   - The proposal page: https://claude.ai/artifact/282jj5PnGRwxkzsy8jfb4R
   - The merged brainstorm page: https://claude.ai/artifact/QQNekPUnt5bPcUDVrVWJEV

   Examples:
   - PR #83 keeps a "no prep" option, but the brainstorm lists no-prep as *not picked*.
   - PR #83 has a family garage debt as a story hook, while **story is parked** for Roy to write himself.
   - Roy told one session he wants all the missed-payment penalties ("all 3 and more"). The other session recorded loans and penalties for skipped nights as *not picked*.

   One source of truth is needed. Any agent asking Roy design questions reads both pages and `car-culture-pivot.md` first, so he isn't asked twice.
4. **The crew system.** Anyone who races or earns for the garage gets their own car. That multiplies builds, tuning and on-track cars. It is parked for its own brainstorm, and scripted crew cars are the default.
5. **Takeover design:** waiting on the simplifier's research (five researchers) and PR #82's feel check.
6. **Setting and name:** suggested as an American city with a nearby canyon. The name "Neon Overdrive" no longer matches the look, so it stays as a working title.
7. **Map sizes:** Roy asked for bigger maps: industrial district about 3 km, freeway 25–30 km, mountain pass 8–10 km, downtown about 1.2 km square. Milestone 1 only needs a straight, so this doesn't block anything yet.
