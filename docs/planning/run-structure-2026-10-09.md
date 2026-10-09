# Run structure, nights and progression (proposal, 2026-10-09)

Status: PROPOSAL, docs only. Nothing here is built. Roy answered all 8 questions on 2026-10-09 (07:47Z and 08:18Z, see "Decided" at the end). The first slice goes to a laptop session when Roy says build.

Roy (2026-10-09): use all the usage today, make a gameplan. This is the "repeatability" part of Stage C: what one night is, what a whole story run is, what you keep and what you lose, and how the game saves.

Read for this: notes `living-world-time-and-people-2026-10-08`, `rival-and-car-ladder-proposal-2026-10-07`, `balance-plan-2026-10-09`, `stops-proposal-2026-10-09`, `mod-tree-proposal-2026-10-09`, `more-ideas-every-category-2026-10-08`, `decisions-gas-engine-landmarks-2026-10-08`, project memory. Code checked on live `origin/main` **282343f** (git fetch 2026-10-09 ~07:30Z): `night_clock.gd`, `game_state.gd`, `game.gd`, `districts.gd`, `tune_slots.gd`.

## One line

**A night is the run; the story is the season.** Every night you leave the garage at 8 p.m. with tonight's pot at zero, risk it on the road, and bank it at home. Thirty nights (on Weekend Warrior) make one story season. What you build in the garage stays; what you carry on the road can be lost.

## Steelman and premortem

- **Steelman.** Almost every piece is already decided in other docs (night clock, dawn cutscene, bank vs cash, busts, 30 nights, mod tree paid from the bank, fixed districts with per-night bends and traffic). What is missing is one place that says how they fit and one save system they all write to. Getting that right early is cheap; bolting saving on after five systems each wrote their own file is not (today there are already two separate save files).
- **Premortem, it shipped and felt wrong because:**
  1. **Nothing was ever at stake.** If you can reload after a bad bust, the bank/cash split means nothing. Fix: autosave only, one story save per slot, no "load older save" (question 4).
  2. **Nights blurred together.** 30 identical highways. Fix: every night has a weekday, an event (bar close, meet night, crackdown, crash ahead) and a fresh road seed, while districts, stations and landmarks stay put so you can plan.
  3. **The save file broke and the player lost 20 nights.** Fix: write to a temp file, then swap; keep the last 3 good copies; a broken file falls back to the previous one, never to a new game.
  4. **The first nights were a slog in the slow Bug.** Fix: first-night pay comes from easy wins (short races against beaters, a parts run), and the Bug's first Service (0.5 night) lands by night 2.
  5. **The run ends and there is no reason to start again.** Fix: free mode in the finished save (Roy: decided), with the city's events and nights still running.
- **Falsification:** if a tester stops after night 3 and says "it's the same every night", the per-night variety is too weak and the event table needs to come forward before more content.

## 1. One night (the run)

| Step | What you see | Rules (decided unless marked) |
|---|---|---|
| **Leave the garage** | The garage door opens at 8 p.m., the car is off, X starts it | Tonight's cash is $0. Car is in whatever state the garage left it |
| **Drive** | Clock on the dash, Dave says the hour | **A night is about 40 minutes of driving** (Roy, 2026-10-09), so 1 real minute = 15 game minutes. **Code change needed:** `night_clock.gd` has `REAL_SECONDS_PER_HOUR = 120.0` (a 20-minute night); it becomes `240.0`. Part of R2 |
| **Earn** | Races, rolling challenges, side jobs | Money goes into **tonight's cash** (at risk) |
| **Stop** | Gas station: fuel, quick fix, heat drains, autosave | Fuel and fixes are paid from the **bank** (stops decision) |
| **Get busted** | Honest cop: ticket + tow, towed home, clock +1 h. Bad cop: all tonight's cash taken, you keep driving | Decided (corrupt police, balance) |
| **End the night** | 6 a.m. arrives, or you choose "head home" | Tired drive home cutscene, **you keep tonight's cash**, it goes into the bank (decided) |
| **Garage (day)** | Night summary card, then the garage: repair, mods, tune, paint, day job | Spend from the bank. Day job is a menu choice that pays and skips the day, not a minigame (first version) |

Quitting mid-night saves the clock, place, fuel, damage and **tonight's cash**, and the next session continues the same night (decided: carried over). Quitting is never a way to dodge a bust: if a cop is chasing you when you quit, the bust is applied on load (question 5).

### What changes each night, what doesn't

| Same every night (you can plan around it) | Different every night (keeps it fresh) |
|---|---|
| District order and names along the road | Road bends and hills (new seed per night) |
| Gas stations, exits, landmarks (fixed places) | Traffic mix and rule-breaker share (hour bands + tonight's event) |
| Your cars, mods, tunes, bank | Tonight's event: normal, bar close, meet night, crackdown, crash ahead, holiday |
| Story beats on their set nights | Which races and rolling challenges show up, and who is driving |
| Weekday calendar | Weather later (rain is planned for later) |

**Flag (code vs decision):** `districts.gd` today picks each district from a hash of the run index, so the district order is random-looking, not a fixed map with names. Making it a fixed, named sequence (Docks, Ironbridge, downtown, ...) is part of slice R4 below.

## 2. One season (the story run)

| | Daily Driver | Weekend Warrior | Racer |
|---|---|---|---|
| Nights to finish (target) | ~25 | **30** (decided) | ~36 |
| Pay | ×1.25 | ×1.0 | ×0.85 |
| Rival pace vs your expected build | −3% | even | +3% |
| Bust chance per chase | ~10% | ~20% | ~35% |
| Fuel range and price | generous | normal | tight |
| Assists | On | Slide help on | Off |

Numbers are the balance plan's targets, not measured. Acts on Weekend Warrior: Act 1 nights 1-10, Act 2 nights 11-22, Act 3 nights 23-30.

**What "nights to finish" means.** The story does not end on a fixed night. Story beats unlock by **progress** (races won, crews beaten, money banked), and the night count is the pace the economy is tuned for. A player who struggles takes longer; nobody is thrown out at night 30. The hard dates are the story's debt deadlines, which Roy writes. **Missing one means retrying the act** (Roy, 2026-10-09); see "Failed deadline" below for how.

### Failed deadline: how similar games do it (research, from knowledge of the games, not a fresh web check)

| Game | Deadline | What happens when you miss it | Kept on retry |
|---|---|---|---|
| Recettear | Weekly debt payment to a loan shark | Short "game over" scene, then back to day 1 | Shop level, items and adventurer levels (it's the game's intended loop) |
| Persona 5 | Each palace has a calendar due date | Bad ending scene, then "return to a day about a week before the deadline" | Everything up to that day |
| Dead Rising | Story cases on a 72-hour clock | Story ends; restart from the start or the last save | Player level and skills carry into a restart |
| Majora's Mask | 3 days before the moon falls | Time resets to day 1 | Key items, songs, masks; money only if banked |
| Pikmin | 30 days to find ship parts | Bad ending; start the whole game again | Nothing |

What works: the games players remember kindly (Recettear, Majora's Mask, Dead Rising) **keep what you built** and send you back in time, so the retry is faster and feels like progress, not punishment. Pikmin's "start over from nothing" is the one most often called harsh.

**Recommendation: retry the act from its first night, keeping what you built.**
- Before each act's first night the game makes a hidden act checkpoint.
- Miss the deadline: Pike's scene plays (the shop's lights go off, Walt hands over the keys), then a short "not like this" beat from Dave, and you are back at the act's first night.
- **Kept:** cars, mods, parts, tunes, rep. **Reset to the checkpoint:** bank, story flags and rival progress for that act, calendar date.
- Why: you lose the nights and the money, so missing still hurts, but you are never back in a weaker car, and the second try is quicker because your build is ahead of the rivals.
- Daily Driver and Weekend Warrior work this way. Racer could reset everything to the checkpoint (a harder option), decided later.

### The car ladder over a season

| When (WW) | Car and tier | Where it comes from |
|---|---|---|
| Night 1 | **Bug beater, T0** (as found, ~110 Nm per the balance plan, about traffic pace) | Abandoned at the shop for an unpaid bill |
| Night 2-3 | Bug serviced, T0+ (keeps up with traffic) | Service node, 0.5 night |
| Act 1 end | Bug fully built, T1; first second car within reach | Mod tree; crew car or scrapyard rebuild |
| Act 2 | T2-T3, one finished build | One finished car per act (balance plan recommendation) |
| Act 3 | T4, the big-turbo coupe path to T5 for the finale | Only big-turbo coupe builds reach T5 (decided) |

**Flag:** the narrative fabric memory says the prologue car is "~290 Nm"; the balance plan's Bug spec says ~110 Nm. 110 Nm fits a Bug-style car and the "about traffic pace" goal; 290 Nm was written for the P1 coupe "as found", which Roy replaced with the Bug. This doc uses 110 Nm. No question needed unless Roy disagrees.

## 3. What carries over, what resets

| Thing | Next night | Bust (honest cop) | Bust (bad cop) | Free mode (after the story) |
|---|---|---|---|---|
| Bank | Kept | Ticket + tow taken, by heat level | Kept | Kept |
| Tonight's cash | Banked at dawn | **Kept** | **All gone** | n/a |
| Cars owned | Kept | Kept | Kept | Kept |
| Mods and parts | Kept | Kept | Kept | Kept |
| Saved tunes | Kept | Kept | Kept | Kept |
| Damage and fuel | Repaired only at the garage (paid) | Car towed home as is | As is | Kept, same rules |
| Heat | Back to 0 at dawn | 0 | 0 | 0 |
| Story flags and act | Kept | Kept | Kept | Story finished; no more story beats or deadlines |
| Rep (near misses, wins) | Kept | Small loss | Kept | Kept |
| Night count, calendar date | +1 | Clock +1 h | none | Keeps counting |

Bank can drop to zero but never below, and you always keep a car (stops doc: death-spiral guard). Fuel credit for an empty bank comes off tomorrow's bank (decided).

## 4. Instant retry

Two different things, kept apart so retrying never undoes a bust:

- **Race retry:** after losing a race, "Retry" puts you back on the start line right away. No entry fee (decided), and each retry costs **15 minutes of the night** (Roy, 2026-10-09), so retrying all night is a choice with a price.
- **Night restart:** there is none. A bad night is a bad night; the next one starts at 8 p.m.
- **Crash or sandbox mode and free roam** (chosen extras) have instant reset with R and no stakes, using the existing `restart()` in `game_state.gd`.

## 5. Unlocks

| What | How it unlocks | Why |
|---|---|---|
| Mod tree | Whole tree visible from day one (decided); you buy nodes with bank money | No hidden walls |
| Districts | Open by act: Act 1 two districts, Act 2 all four crew districts, Act 3 the kings' roads (Roy: yes) | Gives each act a new place to see |
| Cars | Story: crew cars, scrapyard rebuilds, cars won from crews (rival doc). No dealership | Every car has a reason |
| Gas station shop items | Scanner etc. bought once from the bank | Stops doc |
| Free roam with time frozen | After night 1 | Living world: setting to stop the clock |
| Free mode | After the story ends | Section 6 |
| Photo mode, crash mode | From the start | Chosen extras |

## 6. After the story: free mode (Roy, 2026-10-09)

**Keeps:** your save carries on with every car, mod, tune, the bank and rep; nights, money, cops, fuel and city events all keep running, and races pay as in Act 3.
**Drops:** story beats, debt deadlines and act unlocks (the whole city is open); there is no "start the story again with your garage" mode, a new story is a new save slot from the Bug.

Later, from the ideas doc (not in this plan): ghost of your best run (D13), "tonight's city" shared daily seed with a leaderboard (L8). Both reuse the per-night seed from section 1.

## 7. Saving (crash-safe)

What exists today: `night_clock.gd` saves `user://night_clock.cfg` every 15 game minutes and on exit; `tune_slots.gd` saves `user://tune_slots.json` and copies a broken file aside. Two systems, two files, no slots, no version number.

Proposal:

- **One folder per save slot:** `user://saves/slot1/` (three slots, question 4). Inside: `season.json` (story, act, night, difficulty, calendar, bank, flags, rep), `garage.json` (cars, mods, parts, tunes), `night.json` (clock, place, fuel, damage, tonight's cash, heat). Settings (audio, view, keys) stay global, outside slots.
- **Every file has a version number** and a small upgrade step per version, so old saves load after updates.
- **Crash-safe writes:** write `name.json.tmp`, flush, then rename over the old file. Keep the last 3 good copies (`.1`, `.2`, `.3`). On load, a file that fails to parse falls back to the newest good copy and tells you once ("Last save was damaged, loaded the one before"), never silently starts a new game.
- **When it saves:** arriving at a station (decided), landmarks, every 15 game minutes (as today), the end of a night, every garage purchase, and on quit. **Never during a chase** (heat above 0), so quitting can't skip a bust.
- **Autosave only**, three slots (Roy: yes). Free roam and sandbox don't touch the story save.
- **Migration:** on first launch after this ships, the existing `night_clock.cfg` and `tune_slots.json` move into slot 1, so nobody loses their clock or tunes.
- Tests: headless Godot, kill the process mid-write in a loop (a test hook that stops after the temp write) and check the save always loads; load each old file version; sweep all three difficulties.

## 8. How it fits the other docs

| Doc | Overlap | Resolution here |
|---|---|---|
| Stops (S0: cash and bank counter + save) | Same money and save code | **R1 below is S0.** One PR, not two |
| Balance plan | Night pay, act lengths, difficulty table | Taken as-is; the economy model (layer B) reads the same season data file |
| Mod tree (E2: garage save) | Garage save | Writes `garage.json` from R1; E2 only adds its fields |
| Living world | Clock, hour bands, events, dawn | R2 adds the night start/end around the existing clock; events table is R4 |
| Menus A-list (running on the laptop) | Title screen | R3 adds Continue / New game / slot picker to that title screen; coordinate, don't build a second one |
| Corrupt police | Bust rules | R5 is the bust hook; the cops themselves are Stage F |
| Rival and car ladder | Where cars come from, acts | Season table above |

## 9. Build order (one PR each, propose, sign off, build)

| PR | Contents | Size | Needs | Model, why |
|---|---|---|---|---|
| **R1 (first slice)** | Save core: slot folders, versioned JSON, temp-then-rename, 3 backups, migration of the two existing files. Tonight's cash and bank counter (stops S0). Headless crash-write test | S-M | nothing | Opus: the save format is the one thing hard to change later |
| **R2 (first slice)** | Night loop: leave garage at 8 p.m. (placeholder garage screen), "head home" action, 6 a.m. end with a placeholder tired-drive shot, banking, night summary card, clock slowed to a 40-minute night (`REAL_SECONDS_PER_HOUR` 120 → 240) | M | R1 | Sonnet: mechanical, built on the existing clock |
| R3 | Season: story progress record (act, night, flags, date/weekday), difficulty picked at new game, Continue / New / slots on the title screen | M | R1, menus title screen | Sonnet |
| R4 | Per-night variety: new road seed each night, fixed named district order, tonight's event table driving traffic mood | M | R2 | Opus for the district map, Sonnet for the table |
| R5 | Bust hooks: honest (bank charge, tow home, +1 h) and bad cop (cash wiped), callable from a test console until police exist | S | R1, R2 | Sonnet |
| R6 | Race retry (+15 min) and the act checkpoint retry for a missed deadline, once racing and story beats exist | M | racing, R3 | Sonnet |
| R7 | Free mode after the story: story off, whole city open, everything kept | S | story content | Sonnet |

**First slice = R1 + R2.** After it, you can quit mid-night and come back to the same night, see a night end and the money land in the bank, and the save survives being killed mid-write. Both can start now without police, racing or the garage scene. Then R3-R5 in that order; R6-R7 wait for racing and story.

## 10. Decided (Roy, 2026-10-09 07:47Z, his numbers 33-40)

1. Race retry right away: **yes, costs 15 minutes of the night.**
2. Keep driving the city after the story: **yes.**
3. After the story: **free mode** (Roy, 08:18Z). No new-season mode; see section 6.
4. Autosave only, three slots: **yes.**
5. Quit during a chase, bust still happens: **yes.**
6. Missed story deadline: **retry the act** (research above; recommendation: back to the act's first night, keeping cars, mods and rep).
7. City opens by act: **yes.**
8. One night of driving: **about 40 minutes.**
