# Run structure, nights and progression (proposal, 2026-10-09)

Status: PROPOSAL, docs only. Nothing here is built. Roy signs off, then the first slice goes to a laptop session.

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
  5. **The run ends and there is no reason to start again.** Fix: a "new season" mode after the story, plus free roam in the finished save (questions 2 and 3).
- **Falsification:** if a tester stops after night 3 and says "it's the same every night", the per-night variety is too weak and the event table needs to come forward before more content.

## 1. One night (the run)

| Step | What you see | Rules (decided unless marked) |
|---|---|---|
| **Leave the garage** | The garage door opens at 8 p.m., the car is off, X starts it | Tonight's cash is $0. Car is in whatever state the garage left it |
| **Drive** | Clock on the dash, Dave says the hour | 1 real minute = 10 game minutes (living world). **Flag: code today runs 1 game hour per 2 real minutes, so a night is 20 minutes, not ~60.** See question 8 |
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

**What "nights to finish" means.** The story does not end on a fixed night. Story beats unlock by **progress** (races won, crews beaten, money banked), and the night count is the pace the economy is tuned for. A player who struggles takes longer; nobody is thrown out at night 30. The only hard date is the debt's due date in the story, which Roy writes; if it passes, the story takes its "lose" branch (shop sold, crew survives, from the rival doc), the save carries on into free roam, and a new season can be started (question 6).

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

| Thing | Next night | Bust (honest cop) | Bust (bad cop) | New season (after the story) |
|---|---|---|---|---|
| Bank | Kept | Ticket + tow taken, by heat level | Kept | Reset (question 3) |
| Tonight's cash | Banked at dawn | **Kept** | **All gone** | n/a |
| Cars owned | Kept | Kept | Kept | Kept (question 3) |
| Mods and parts | Kept | Kept | Kept | Kept |
| Saved tunes | Kept | Kept | Kept | Kept |
| Damage and fuel | Repaired only at the garage (paid) | Car towed home as is | As is | Fresh |
| Heat | Back to 0 at dawn | 0 | 0 | 0 |
| Story flags and act | Kept | Kept | Kept | Reset to Act 1, rivals one tier stronger |
| Rep (near misses, wins) | Kept | Small loss | Kept | Kept as a total, shown on the title screen |
| Night count, calendar date | +1 | Clock +1 h | none | Back to night 1 |

Bank can drop to zero but never below, and you always keep a car (stops doc: death-spiral guard). Fuel credit for an empty bank comes off tomorrow's bank (decided).

## 4. Instant retry

Two different things, kept apart so retrying never undoes a bust:

- **Race retry:** after losing a race, "Retry" puts you back on the start line right away. No entry fee (decided), but each retry costs **15 minutes of the night**, so retrying all night is a choice with a price (question 1).
- **Night restart:** there is none. A bad night is a bad night; the next one starts at 8 p.m.
- **Crash or sandbox mode and free roam** (chosen extras) have instant reset with R and no stakes, using the existing `restart()` in `game_state.gd`.

## 5. Unlocks

| What | How it unlocks | Why |
|---|---|---|
| Mod tree | Whole tree visible from day one (decided); you buy nodes with bank money | No hidden walls |
| Districts | Open by act: Act 1 two districts, Act 2 all four crew districts, Act 3 the kings' roads (question 7) | Gives each act a new place to see |
| Cars | Story: crew cars, scrapyard rebuilds, cars won from crews (rival doc). No dealership | Every car has a reason |
| Gas station shop items | Scanner etc. bought once from the bank | Stops doc |
| Free roam with time frozen | After night 1 | Living world: setting to stop the clock |
| New season | After the story ends, either branch | Section 6 |
| Photo mode, crash mode | From the start | Chosen extras |

## 6. After the story

- **Free roam in the finished save:** nights keep coming, the city keeps its events, you keep everything. Races pay as in Act 3.
- **New season (question 3):** start again at night 1 with your garage of cars and mods, bank reset, rivals and cops one tier up, story beats replayed short (Dave reads a one-line recap instead of cutscenes). This is the roguelite "one more run".
- Later, from the ideas doc (not in this plan): ghost of your best run (D13), "tonight's city" shared daily seed with a leaderboard (L8). Both reuse the per-night seed from section 1.

## 7. Saving (crash-safe)

What exists today: `night_clock.gd` saves `user://night_clock.cfg` every 15 game minutes and on exit; `tune_slots.gd` saves `user://tune_slots.json` and copies a broken file aside. Two systems, two files, no slots, no version number.

Proposal:

- **One folder per save slot:** `user://saves/slot1/` (three slots, question 4). Inside: `season.json` (story, act, night, difficulty, calendar, bank, flags, rep), `garage.json` (cars, mods, parts, tunes), `night.json` (clock, place, fuel, damage, tonight's cash, heat). Settings (audio, view, keys) stay global, outside slots.
- **Every file has a version number** and a small upgrade step per version, so old saves load after updates.
- **Crash-safe writes:** write `name.json.tmp`, flush, then rename over the old file. Keep the last 3 good copies (`.1`, `.2`, `.3`). On load, a file that fails to parse falls back to the newest good copy and tells you once ("Last save was damaged, loaded the one before"), never silently starts a new game.
- **When it saves:** arriving at a station (decided), landmarks, every 15 game minutes (as today), the end of a night, every garage purchase, and on quit. **Never during a chase** (heat above 0), so quitting can't skip a bust.
- **Autosave only** in story mode (question 4). Free roam and sandbox don't touch the story save.
- **Migration:** on first launch after this ships, the existing `night_clock.cfg` and `tune_slots.json` move into slot 1, so nobody loses their clock or tunes.
- Tests: headless Godot, kill the process mid-write in a loop (a test hook that stops after the temp write) and check the save always loads; load each old file version; sweep all three difficulties.

## 8. How it fits the other docs

| Doc | Overlap | Resolution here |
|---|---|---|
| Stops (S0: cash and bank counter + save) | Same money and save code | **R1 below is S0.** One PR, not two |
| Balance plan | Night pay, act lengths, difficulty table | Taken as-is; the economy model (layer B) reads the same season data file |
| Mod tree (E2: garage save) | Garage save | Writes `garage.json` from R1; E2 only adds its fields |
| Living world | Clock, hour bands, events, dawn | R2 adds the night start/end around the existing clock; events table is R4 |
| Menus A-list (running on the laptop) | Title screen | R3 adds Continue / New season / slot picker to that title screen; coordinate, don't build a second one |
| Corrupt police | Bust rules | R5 is the bust hook; the cops themselves are Stage F |
| Rival and car ladder | Where cars come from, acts | Season table above |

## 9. Build order (one PR each, propose, sign off, build)

| PR | Contents | Size | Needs | Model, why |
|---|---|---|---|---|
| **R1 (first slice)** | Save core: slot folders, versioned JSON, temp-then-rename, 3 backups, migration of the two existing files. Tonight's cash and bank counter (stops S0). Headless crash-write test | S-M | nothing | Opus: the save format is the one thing hard to change later |
| **R2 (first slice)** | Night loop: leave garage at 8 p.m. (placeholder garage screen), "head home" action, 6 a.m. end with a placeholder tired-drive shot, banking, night summary card, clock rate per question 8 | M | R1 | Sonnet: mechanical, built on the existing clock |
| R3 | Season: story progress record (act, night, flags, date/weekday), difficulty picked at new game, Continue / New / slots on the title screen | M | R1, menus title screen | Sonnet |
| R4 | Per-night variety: new road seed each night, fixed named district order, tonight's event table driving traffic mood | M | R2 | Opus for the district map, Sonnet for the table |
| R5 | Bust hooks: honest (bank charge, tow home, +1 h) and bad cop (cash wiped), callable from a test console until police exist | S | R1, R2 | Sonnet |
| R6 | Race retry (+15 min), once racing exists | S | racing | Sonnet |
| R7 | After the story: free roam continue, New season with tier-up | M | story content | Opus |

**First slice = R1 + R2.** After it, you can quit mid-night and come back to the same night, see a night end and the money land in the bank, and the save survives being killed mid-write. Both can start now without police, racing or the garage scene. Then R3-R5 in that order; R6-R7 wait for racing and story.

## 10. Questions for Roy (one word each, recommended first)

Numbered on from the last batch where the coordinator relays them.

1. **After losing a race, can you try it again right away?** **Yes, but it costs 15 minutes of the night** / Yes, free / No.
2. **After the story ends, can you keep driving the same city with everything you own?** **Yes** / No.
3. **After the story, can you start a new season keeping your cars and mods, with tougher rivals and an empty bank?** **Yes** / No, start fresh.
4. **Saving: does the game only save by itself, so a bad bust can't be undone by loading?** **Yes, three save slots** / No, let me load older saves.
5. **If you quit during a police chase, does the bust still happen when you come back?** **Yes** / No.
6. **If you miss the story's last deadline, does the story end on the "lose" branch while you keep playing?** **Yes** / No, retry the act.
7. **Do new parts of the city open as the story goes on?** **Yes, by act** / No, whole city from night 1.
8. **How long is one night of driving?** **About 40 minutes** / 20 minutes (today) / 60 minutes.
