# Races and rival drivers (plan, 2026-10-09)

Status: PLAN, docs only. Nothing here is built. Roy signs off before any build.

Read for this: notes `balance-plan-2026-10-09`, `police-build-plan-2026-10-09`
(3b headlights), `run-structure-2026-10-09`, `income-ideas-2026-10-09`,
`first-ten-minutes-2026-10-09`, `rival-and-car-ladder-proposal-2026-10-07`,
`more-ideas-every-category-2026-10-08` (N1 highway duels),
`living-world-time-and-people-2026-10-08`, and the code on origin/main
`282343f` (`traffic_car.gd`, `traffic_manager.gd`, `road_alignment.gd`,
`districts.gd`, `night_clock.gd`, `game_state.gd`).

## Rules already decided (not reopened here)

| Rule | Source |
|---|---|
| Rivals never slow down when you fall behind (no rubber-banding) | Balance plan, Roy 4 |
| No entry fee; a lost race pays nothing | Balance plan, Roy 6 |
| Side bets: yes, optional stake | Income ideas, Roy 106 |
| Flashing your headlights at a marked racer starts a race on the spot | Police plan 3b |
| Rolling challenges (Tokyo Xtreme Racer style): yes | Income ideas, Roy 102 |
| Highway duels (drain-bar): yes | More ideas, 2026-10-08 |
| Pink-slip races: later | Income ideas, Roy 107 |
| Road jobs (and race wins) pay **cash on you**; a bad cop can take it | Income ideas, Roy 104 |
| Race retry: right away, costs 15 minutes of the night | Run structure, Roy |
| Rivals use the same mod trees; an act opens with the rival one step ahead and closes with you one step ahead | Balance plan 6 |
| Win-rate targets (WW, first try): regular 45-60%, crew bosses 25-35%, finale 20-30% | Balance plan 6 |
| Rival pace: Daily Driver -3%, Weekend Warrior even, Racer +3% (build, not cheating) | Balance plan |
| Races are ~55-60% of a night's money; a win pays ~0.3 night | Balance plan, income ideas |
| First race of the story: a ~90 s sprint against a faster muscle car that flashes you; you lose | First ten minutes, Roy 41 |
| No on-screen key hints | Decisions |

## One line

**Every race is your car against another real car on the same road, in the
same traffic, with the same physics, and the rival's speed comes from its
build and its driver, never from where you are.**

## Steelman and premortem

- **Steelman.** The game already has the hard part: traffic cars are full GEVP
  vehicles with pure-pursuit steering, an adaptive-cruise speed law, MOBIL lane
  changes and an occupancy index (`traffic_car.gd`). A rival is a traffic car
  with a racing brain swapped in. One endless seeded road means a race is just
  "first to distance X", so there is no track-building cost, and every race
  type below is a variation of that one core.
- **Premortem: it shipped and felt wrong because...**
  1. **Rivals crashed into traffic every race**, so wins felt free. Fix: the
     rival plans speed against the occupancy index like traffic does, with a
     per-driver risk setting; a test sweeps 100 races per driver and caps the
     rival wreck rate (target under 10% per race).
  2. **Rivals were unbeatable on bends and slow on straights**, or the reverse,
     so every race was decided in one place. Fix: corner speed comes from the
     same grip and curvature limit for both cars (rival uses a share of the
     car's real limit), measured on the tune track before races ship.
  3. **No rubber-banding made blowouts boring**: 400 m ahead after 20 s, then
     nothing. Fix: short races (60-120 s), a "gap too big" early finish, and
     the act ladder (rival a step ahead, then a step behind), not catch-up.
  4. **Races and cops fought each other**: a cop arrived and the race became
     meaningless. Fix: clear rules for what a chase does to a race (section 5).
  5. **Far-away rivals teleported**: `traffic_car.gd` freezes cars past the
     draw distance into a kinematic cruiser. Fix: a racing rival is never
     frozen while the race is live; it stays full sim (one car, affordable).
- **Falsification:** if a tester's first-try win rate on regular Act 1 races is
  under 30% or over 80% across all three driver settings, the driver model is
  wrong, not the payouts, and races do not ship.

## 1. Race types

All of them run on today's endless road: a race is **from here to a point
further along the road**. Circuits wait for the junctions plan's loops.

| Type | What you see | How it starts | Win | Length | Pays | Size |
|---|---|---|---|---|---|---|
| **Sprint** (core) | You and one rival side by side to a landmark (a lit bridge, an exit sign) | Meet spot or story | First past the line | 60-120 s | ~0.3 night (Act 1 WW) | B |
| **Rolling challenge** | You flash a marked racer on the road; they flash their hazards back and go | Headlight flash | First to the next landmark | 45-90 s | 0.1-0.25 night | A once sprint exists |
| **Highway duel** | Both cars get a bar; yours drains while you are behind, faster the bigger the gap | Headlight flash on a highway stretch | Their bar empties first | Until a bar empties (cap 3 min) | 0.2-0.4 night | B |
| **Crew boss race** | A sprint against a crew's top driver, crew cars parked at the start, Dave calls it | Story beat at a meet | First past the line | 90-150 s | ~0.5 night + the crew's business | B (content on top of sprint) |
| **Drag** | Standing start on a straight, 400 m, lights or a flashlight drop | Meet spot | First past 400 m | 10-15 s | 0.1-0.2 night | B (launch and shift feel) |
| **Pink slip** (later) | A sprint where the stake is the cars | Story, one per act at most | First past the line | 90-150 s | A car | C |
| Time trial / circuit (later) | Ghost to beat, or laps once loops exist | Landmark | Beat the time | - | small | later |

**Recommended first set:** sprint, then rolling challenge, then side bets,
then duel. Drag and boss races after the rival roster exists.

## 2. How a race starts

### a. Meet spots (sprint, drag, boss)
- A lit pull-off with a few parked racer cars, hazards on, people standing
  around (no faces needed: silhouettes against the lamps). Dave mentions it on
  air earlier in the night. Meet spots sit at fixed landmarks per district.
- Stop in the meet spot: a small paper flyer card shows tonight's races there
  (rival, car, distance, pay). Pick one, or drive off. If side bets are on,
  the same card has a stake slider (cash on you only).
- **Standing start** on the line: a person in the road with a flashlight,
  arm up, three flashes, drop. No on-screen countdown text; a lamp and a
  sound. Jumping the start = the rival wins by default.

### b. Headlight flash (rolling challenge, duel)
- Pull up behind a **marked racer** within ~30 m and flash (the T1 key).
- Marked racers are told apart **in the world**, not by an icon: crew paint
  and stickers, aftermarket wheels, a loud exhaust you hear before you see
  them. Plain traffic just moves over (T1 rule).
- **Accept:** the racer flashes its hazards twice and pulls level with you.
  **Rolling start:** both cars side by side, three honks, go. **Decline:** it
  ignores you (it has raced you tonight, or it is a Pike setup not ready yet).
- A racer flashed during a cop chase always declines.

### c. Story races
- Triggered by story beats on their night (first race of the prologue, crew
  bosses, finale). Same sprint core, staged start.

## 3. How a race ends

| Ending | Rule |
|---|---|
| **Win** | Cross the finish first. Duel: their bar empties first |
| **Lose** | They cross first, or your bar empties |
| **Gap too big** | One car leads by over ~400 m for 5 s: race called early for the leader. Stops a blowout dragging on |
| **Wreck** | A car flipped, stopped or facing the wrong way for 8 s is out; the other wins |
| **Give up** | Stop the car for 3 s (no key needed, fits "no key hints") |
| **Busted** | Busted mid-race = loss, plus the normal bust rules |

After the finish:
- A short caption (rival's line, the pay), money into **cash on you**,
  side bet settled, night clock +15 min (living-world rule: a race = +15 min).
- On a loss: **Retry** (back on the start line, +15 min more) or drive on.
  Rolling challenges have no retry: that racer is gone for the night.
- Dave mentions wins and big losses later in the night (scoreboard).
- The rival drives off into traffic; it does not vanish in front of you.

## 4. Rival AI

A rival is a `TrafficCar` with a **race controller** in place of the
traffic controller. Same CarSpec, same raycast wheels, same occupancy index.

### What the race controller does
1. **Speed plan.** Looks ahead along the road (`RoadAlignment` curvature)
   and computes the fastest speed for each bend from the car's real grip:
   `v = sqrt(skill_grip x mu x g / curvature)`. Brakes early enough to make
   it. On straights: flat out, shifting like the player's auto box.
2. **Traffic.** Uses the occupancy index like traffic does, but with racing
   numbers: smaller gaps, harder braking, lane changes when the gap in the next
   lane is safe by its own risk setting. Can use the shoulder only if the
   driver is "reckless".
3. **The player.** The player is a car in the index. Rivals block a little
   (move into your lane when you are close behind) only if the driver has
   that trait. No ramming except Pike's setup races (police plan F9).
4. **Mistakes.** A small chance per bend of braking late or running wide,
   set per driver. Real mistakes, not slowdowns tied to the gap.

### Driver settings (per rival, fixed for the race)

| Setting | What it changes | Range |
|---|---|---|
| Corner commitment | Share of the car's real grip limit used in bends | 0.80-0.97 |
| Brake point | How late it brakes | early-late |
| Traffic risk | Gap it accepts when threading traffic | careful-reckless |
| Blocking | Moves over to stay in front of you | none-often |
| Mistake rate | Late brakes, wide lines per bend | 0-6% |
| Launch | Reaction at the start | 0.2-0.6 s |

Crews get a personality from these (Kasumi Run clean and fast in bends,
Diesel Row slow in bends and reckless in traffic, and so on). Names stay
placeholders.

### No rubber-banding, written as a test
- The controller **never reads the gap to the player** for speed. A unit test
  checks the controller's inputs are identical whether the player is 300 m
  ahead or 300 m behind on the same road.
- Difficulty changes the rival's **build** (±3%), not its driving.
- Far rivals stay full sim during a race (one extra full car, inside the
  traffic budget) instead of the kinematic freeze traffic uses.

### Where rivals come from
- Rival cars are the player cars and NPC sheet cars with crew builds from the
  same mod trees (decided). Until those exist, the first rival uses the P1
  coupe or P5 muscle sedan spec with a "step ahead" tune.
- Act ladder: first race of an act, rival build one tier step ahead of your
  expected build; last race, one step behind (balance plan 6).

## 5. Races and cops

- A race adds heat only if a cop sees it (the normal speeding rule).
- **A cop joins mid-race: the race goes on.** The rival keeps racing unless
  heat gets to level 3, then it bails off an exit (later) or pulls over. If it
  bails, you win half the pay.
- Busted mid-race = loss and the normal bust rules.
- **Pike setups (F9):** some racers you flash are Pike's; win, and the bad cops
  are waiting a minute later. Stays in the police plan.

## 6. Money and time (targets, re-measure when built)

| | Pay (WW) | Night time |
|---|---|---|
| Sprint win | ~0.3 night | +15 min |
| Rolling challenge win | 0.1-0.25 | +15 min |
| Duel win | 0.2-0.4 | +15 min |
| Boss win | ~0.5 + story | +15 min |
| Loss | 0 (no fee) | +15 min, retry +15 more |
| Side bet | Win doubles your stake, lose loses it; stake max = cash on you, capped at ~0.3 night | - |

Difficulty: pay x1.25 / x1.0 / x0.85 (decided).

## 7. What exists and what is missing (origin/main `282343f`)

| Needed | Exists? |
|---|---|
| A full-sim AI car on the road | **Yes** (`traffic_car.gd`, lane follow, braking, MOBIL lane changes, wrecks) |
| Occupancy index to see traffic | **Yes** (`traffic_manager.gd`) |
| Road curvature ahead | **Yes** (`road_alignment.gd`) |
| Landmarks and meet spots | No (districts are building mixes only) |
| Cash on you, bank | No (stops S0 / run structure R1 / police F0) |
| Headlight flash key (T1) | No (police plan) |
| Race state, finish line, results | No |
| Racing controller | No |
| Rival roster / crew builds | No (needs cars and mod trees) |

## 8. Build order (one PR each; propose, sign off, build)

| # | What Roy will see | Size | Needs | Model |
|---|---|---|---|---|
| **RC1** | Race core: a `RACING` state, a finish line at a distance down the road, win/lose/give-up/wreck/gap-too-big rules, a result caption, +15 min. Tested with a scripted dummy rival | B | - (pays into a stub until cash exists) | Sonnet |
| **RC2** | Racing driver: the rival corners at its grip limit, brakes for bends, threads traffic, makes mistakes; the no-rubber-band test; headless sweeps of 100 races | C | RC1 | **Opus** (control and tuning reasoning) |
| **RC3** | First real sprint: a meet spot with the flyer card, the flashlight start, a small gap/distance readout. This is also the prologue race (first ten minutes F7) | B | RC1, RC2 | Sonnet build; Fable for the meet spot look |
| **RC4** | Rolling challenge: flash a marked racer, hazards back, rolling start | A | RC3, T1 flash | Sonnet |
| **RC5** | Retry (+15 min) | A | RC3, run structure R2 | Sonnet (= run structure R6) |
| **RC6** | Side bets on the flyer card | A | RC3, cash (R1) | Sonnet |
| **RC7** | Highway duel with the drain bars | B | RC4 | Sonnet logic, Fable for the bars' look |
| **RC8** | Rival roster: crews, personalities, crew paint, Dave's scoreboard lines | B | RC2, cars, mod trees | Fable (looks), Opus (driver numbers) |
| **RC9** | Drag race: standing start, launch, 400 m | B | RC3 | Opus (launch feel) |
| **RC10** | Races and cops (cop joins, rival bails, Pike setups) | B | RC3, police F1-F3 | Opus |
| **RC11** | Win-rate balance sweep per act and difficulty | B | RC8, balance harness | Opus |
| RC12 | Pink slips (later, Roy 107) | C | RC8, garage | Opus |

**A-list (small, do when ready):** RC4, RC5, RC6.
**B-list (medium):** RC1, RC3, RC7, RC8, RC9, RC10, RC11.
**C-list (large):** RC2, RC12.

Suggested first slice: **RC1 + RC2 together in one session (Opus)**, since the
core is untestable without a driver, then RC3 as the prologue race.

## 9. Questions for Roy (one word each, my pick first)

1. During a race, a small number on screen showing the gap to the rival? **Yes** / No
2. A rival you flash answers by blinking its hazards, then you both go from a rolling start? **Yes** / Instant start
3. A cop shows up mid-race: the race keeps going? **Yes** / Race is called off
4. The rival wrecks in traffic: you win if they are still stuck after 8 seconds? **Yes** / Must still cross the line
5. Giving up a race: just stop the car for 3 seconds? **Yes** / Pause menu option
6. Racer cars on the road stand out by crew paint, stickers and a loud exhaust, no icon over them? **Yes** / Add a small marker
7. Rivals thread through traffic as riskily as you can? **Depends on the crew** / Always careful / Always reckless
8. First race type after the sprint: **rolling challenge** / highway duel / drag

## Sources

Design patterns from knowledge of the games (not a fresh web check): Tokyo
Xtreme Racer (flash to challenge, drain bars), NFS Unbound (side bets), NFS
Most Wanted (pink slips). Tokyo Xtreme Racer on Steam:
https://store.steampowered.com/app/2634950/
