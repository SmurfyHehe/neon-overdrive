# Game narrative fabric: how every system tells one story (proposal, 2026-10-07)

Status: PROPOSAL, docs only. Roy signs off before anything is built. Story is Roy's to write: this is the bridge between the mechanics and his story, not the story. Every name is a placeholder from `docs/story-bible.md`. No loan or penalty mechanics; the debt stays story-only.

Inputs read (all on open branches, none merged yet): `docs/story-bible.md` (main), engine spec (`claude/project-thread-cgvj8u`), landmark research (`-8yyjao`), world vision W1-W5 (`-w9ubqr`), gas station (`-73z87a`), Stage C run loop (`-soqei8`). Car numbers from `scripts/car_spec.gd` on main `9c28d59`.

Roy's calls on 2026-10-07 that this doc follows:
- No "tow to garage or lose the car". Brainstorm instead.
- Cars start switched off, with a warm-up.
- Car power presets come from the story and how much power the player should have.
- Pike Lending storefront becomes a liquor store.
- Landmark list approved, 10 target, no ceiling; landmarks and W1-W4 must be researched.
- Mirrors: no keys. The game does it automatically in first person. Over-the-shoulder may be needed.

## One line

**You are the mechanic, so your power is your work.** Every horsepower the player has, they put there with their hands in the garage, and every place on the map is a person who needs something from the shop.

## Steelman and premortem

- Steelman: one rule (power is earned by wrenching) explains the car presets, the engine system, the garage mini-games and the landmarks at once. The player never asks "why can't I just buy a faster car?", because the story is about a shop that cannot afford one.
- Premortem, it failed because:
  1. Wrenching felt like homework between the fun bits. Mitigation: every mini-game is 20-45 s, skippable at a cost, and always raises something you feel on the next drive.
  2. The start was too slow and testers quit before the car got good. Mitigation: the prologue car is weak for one night only; stock power comes back after the first service (section 3).
  3. Story gates blocked free roam. Mitigation: gates limit **events**, never where you can drive or how you tune.
- Falsification: if playtesters on the starting car say "this is boring" before the first service, the power floor is too low. Raise T0 before touching anything else.

## 1. The shape of a night (the core loop, with story on top)

One in-game **night** is one session's unit. It wraps the Stage C run loop instead of replacing it.

```
 GARAGE (daylight through the roller door, menu scene)
   service own car, customer jobs (mini-games), mods, crew, Dave's back-room rig
        |  start the car (it is OFF), warm-up while rolling out of the lot
        v
 DUSK -> MIDNIGHT -> PRE-DAWN   (W4 hour presets; streets are always night)
   free runs (Stage C pot + bank + heat)
   landmark stops: gas, diner, tow depot, liquor store ... (one person, one verb each)
   story events posted on the garage board or phoned in by a landmark person
        |  drive home, or end the session anywhere (autosave at any landmark)
        v
 GARAGE: Cred banked, wear shows on the car, Dave's summary line
```

**Day and night, a contradiction to settle.** The world vision says "no daytime" because day fights the Gritty PS2 night look. The coordinator's note said "work at the garage by day, race at night". Proposed fix: **daylight exists only inside the garage scene** (light through the roller door and windows, a menu scene, no world lighting cost). Streets are always night. This gives the shift structure without ever rendering the city in daylight.

## 2. Act map: story beats, power tier, places, garage skills

The spine is the story bible's. The other columns are what each system contributes.

| Beat | Power tier (sec. 3) | Places that open | Garage skill unlocked | Engine/feel lesson |
|---|---|---|---|---|
| Prologue: the shop owes $60k; Ledger beats you and mocks Dunmore Auto | T0 "As found" | Garage HQ, one gas station, TV tower on the skyline | Start-up and warm-up (the car is cold, tired, oil overdue) | Cold engine, rough idle, you lose the race on power not skill |
| Act 1: first wins, two recruits, Dave starts broadcasting | T1 "Running right" then T2 "Street" | Diner, Ferris tow depot, Okafor dyno | Oil change, plugs, first bolt-ons; dyno pulls | Service brings back stock power; the first mod you feel |
| Act 2: beat each crew's top driver, take districts; crew drama | T3 "District" | Scrapyard, liquor store, Cutter Canyon tunnel, more gas stations | Cooling (radiator, intercooler), gearbox service, swaps from the scrapyard | Power plus heat: cooling becomes the second purchase (engine spec sec. 6) |
| Turn: the debt and the humiliation were a setup by Ledger's people | T3 | Liquor store changes (Ironbridge cars outside), Dave's tower goes quiet one night | none new | The night the radio goes silent is the tension beat |
| Act 3: beat the kings, season invitational | T4 "Kings" | Airstrip hangar, Ironbridge (needs elevation) | Engine rebuild (the big mini-game), turbo or big-cam build | Knock and limp mode are the real risk now (spec sec. 7) |
| Ending: rematch with Ledger | T5 "Rematch" | Ironbridge finale ground | none | Everything you built shows up in one race |
| After: legends reunion | uncapped | everything | everything | Free play, no caps |

Flag for Roy: the story bible makes Ledger both the Ironbridge leader (an Act 2 crew boss) and the final boss. Proposal: in Act 2 the player beats Ironbridge's **number two**, and Ledger only races at the end. Your call.

## 3. Car power presets (from the story)

**Principle.** The player is never handed power. Power comes from three things the mechanic does: **repair** (restores what the car should have), **mods** (the per-car tree), and **care** (engine health and warm-up). Events in each act have a **power-to-weight band** so a race is a race, not a stomp. Free roam has no cap.

Measure: peak torque per kg (Nm/kg), because that is what `CarSpec` carries (`max_torque`, `vehicle_mass`). Reference points on main today: P1 coupe 460 Nm / 1300 kg = **0.35**; traffic 170 / 1250 = **0.14**.

| Tier | When | Event band (Nm/kg) | Player's P1 coupe | What the player feels |
|---|---|---|---|---|
| T0 As found | Prologue (one night) | 0.20-0.24 | 290 Nm, worn engine (health 55), oil overdue | Clearly faster than traffic (about 1.6x), clearly slower than Ledger |
| T1 Running right | Act 1 start, after first service | 0.30-0.36 | 460 Nm stock (today's car) | "That's what it should feel like." The car you already tested |
| T2 Street | Act 1 end | 0.36-0.42 | 500-540 Nm with intake, exhaust, light tune | Small, felt gains; handling nodes matter more than power |
| T3 District | Act 2 | 0.42-0.52 | 560-660 Nm; cooling required to hold it | Heat appears; a hot car loses power (spec sec. 6) |
| T4 Kings | Act 3 | 0.52-0.62 | 700-800 Nm, turbo or big build, rebuilt engine | Knock and limp are real; driving clean matters |
| T5 Rematch | Ending | 0.60-0.66 (Ledger sits at the top) | Whatever you built, capped at band top for the race | You win on build choices and driving, not on a number |

Rules:
- **Every player car has its own preset per tier**, not one number for all. The crew cars join at the band of the act they arrive in and keep their character: P2 hatch launches (FWD, light), P3 tuner revs (high redline), P4 kei corners (very light, low torque, wins on cornering speed rather than Nm/kg), P6 crossover grips (AWD), P5 muscle torque (heavy, low redline). These are starting values for a later per-car data pass, not measured.
- **Rivals sit inside the same band**, slightly above the player's typical build, so beating them needs skill or a smart node, not grinding.
- **Bands limit events only.** Over the band, the event board says "too much car for this one" and offers a detuned entry (a one-click "race spec" that clamps torque for that event). It never forces you to remove mods. This follows the settings-safety rule: fun extremes are allowed, clamps only where a specific setting needs one.
- **Story events set the band; free runs do not.** Stage C free runs pay more with a stronger car only through heat and speed, as already proposed.
- All numbers live in one file with the other tunables (`scripts/run_tuning.gd` from Stage C, or a sibling `story_tiers.gd`).

Why start weaker than today's car: the prologue loss to Ledger has to be about the car, not the player, and fixing it with your own hands in the first garage visit is the first proof of the "power is your work" rule. One night only, so it costs little.

## 4. The engine is the shop's story

The engine spec (`claude/project-thread-cgvj8u`) is the mechanic system. This section ties it to the story and replaces the parts Roy rejected.

### 4a. Start-up and warm-up (Roy: cars start off, wants the warm-up)

- Every car spawns **OFF**. One press of the existing starter key cranks it (spec sec. 2). With Assist on, throttle while OFF auto-cranks.
- **Cold engine:** high idle (about 1300 rpm, settles to normal), a soft rev cap at about 70% of redline, and about -10% power until coolant reaches about 70 C. A temp needle rises on the cluster; the exhaust note gets smoother as it warms (engine audio already varies by rpm and load).
- **Warm-up time:** about 60-90 s of easy driving, or about 2 min idling. Revving hard while cold adds a little wear (spec sec. 8), never a failure.
- **Story fit:** the warm-up happens on the roll out of the garage lot and the first few blocks; Walt's line on the first night is the tutorial ("Let it warm up. It's older than you."). The block heater is an early, cheap garage mod that shortens warm-up, so the first thing the player buys is something a real mechanic would.
- **Car stays warm** for a while after a run, so restarting at a gas station does not repeat the wait.

### 4b. No death, no tow, no lost car (Roy: tow or lose car is shitty)

Brainstormed options, with a recommendation:

| Option | How it works | Story tie | Cost to the player |
|---|---|---|---|
| **A. Limp floor (recommended base)** | Engine health never reaches "dead". At 10 it locks to limp mode (redline about 4500, half power) and stays there. You can always drive home. | The car is tired, not gone. You are the mechanic who keeps it alive | Slow drive, no money lost |
| **B. Roadside patch (recommended with A)** | Pull over anywhere, open the bonnet: a 20 s mini-game patches the car back to 40 health for this night only. Full fix still needs the garage | You are a mechanic; you carry tools | 20 s and a reminder to service |
| C. Call Ferris | Ferris drives out and patches you, in exchange for a favour (a tip-run or delivery for him later) | Ties the tow-depot landmark into the loop | A future favour, not Cred |
| D. Crew call | Moose (the wrenching crew member) shows up once a night | Crew matters; Moose's drama hits harder if he has helped you | Once per night |
| E. Gas station quick fix | Partial repair at any gas station (already in the gas station doc) | Clerk sells the parts | Small Cred |
| F. Early warning only | Ladder of signs before anything bad: dash lamp, rough audio, Dave says your car sounds sick on air | Dave noticing makes the radio feel alive | Nothing |

**Recommendation: A + B as the system, F always on, C and D as story flavour.** The engine spec's "dead at 0, tow to garage" line should change to the limp floor. Damage only ever costs speed and time, never the car.

### 4c. Service is how the shop survives

- **Your car:** oil, plugs, coolant, gearbox, and later the rebuild (spec sec. 8 mini-games). Doing them well is how you get from T0 to T1, and keeping up with them is how you hold T3-T4 without heat and knock.
- **Customer jobs:** the day shift has 1-3 customer cars. Same mini-games, on traffic models (N1-N3). They pay Cred, and each customer is someone from a landmark (the gas station clerk's hatch, the diner waitress's commuter, a dock worker's pickup). This is how landmarks feed the garage without any loan or penalty mechanic.
- **Mini-game ladder by act:** Act 1 oil, plugs, intake. Act 2 coolant bleed, gearbox flush, radiator and intercooler fit, scrapyard swaps. Act 3 engine rebuild (the longest, about 45 s, the T4 gate). Each one teaches a thing the player then feels on the road.

## 5. Landmarks: why each place matters to the story

Ten, per Roy's approved list and target. No ceiling. Pike Lending storefront is now a liquor store. Rule from the landmark research: one person, one verb, night-readable, cheap to build.

| # | Landmark | Person (placeholder) | Verb | Story job | Opens | World phase |
|---|---|---|---|---|---|---|
| 1 | Garage HQ (Dunmore Auto) | Walt, crew, Dave's rig | Service, mods, customer jobs, event board, save | Home; the photo wall fills with crew and wins; overdue notices on the desk | Prologue | W5 (menu scene first) |
| 2 | Gas stations (repeatable, not counted) | Night clerk | Fuel, quick fix, heat cool-down, rumours | Neutral ground; you overhear Ledger's people first here | Prologue | W2 |
| 3 | Graveyard TV tower | Dave (voice only) | Radio gets clearer as you pass; later a tip-off stop | Skyline anchor; goes silent on the Turn night | Prologue (visible), Act 2 (stop) | W1 |
| 4 | Diner | Waitress, a rival's scout | Crew hangout, rest, side-event board | Recruits are met here in Act 1 | Act 1 | W2 |
| 5 | Ferris Tow Depot | Ferris | Tips for favours; roadside call (option C) | The mentor who knows every road | Act 1 | W1-W2 |
| 6 | Okafor Dyno | Okafor | Dyno pulls; the Tuner screen in the fiction | Proof in numbers that your work made power | Act 1 | W2 (interior menu) |
| 7 | Scrapyard | Parts dealer | Salvage parts, engine swaps, mod-tree unlocks | Where you find what you cannot afford new | Act 2 | W2 |
| 8 | **Liquor store** (replaces Pike Lending) | Night clerk behind bulletproof glass | Buy a cheap item (story flavour), read the board, overhear | Ironbridge's hangout; their cars park out front after the Turn. Gives the debt plot a place without showing a lender | Act 2 | W2 |
| 9 | Cutter Canyon tunnel | Pilar | Touge start and finish | First real set piece; Pilar's turf | Act 2 | W3 (after curves) |
| 10 | Airstrip hangar | Okafor's data bench, the kings | Top-speed pulls, king races | Act 3 home turf of the kings | Act 3 | W3-W4 |
| 11 | Ironbridge | Vance Ledger | Territory gate, finale | The rival crew's name and the final race | Act 3 / Ending | W4 (needs elevation) |

That is 10 counted landmarks plus repeatable gas stations. More can be added at any time.

**Research still owed (Roy asked for it).** The landmark doc made a judgement on the count, with no verified source, and guessed the W1-W4 meaning before the world vision defined them. The world vision now defines W1 look pass, W2 dressing kit, W3 life, W4 night arc, W5 destinations. So landmark builds mostly fall in **W5**, not W1-W4, and the "World phase" column above shows the earliest phase whose kit they reuse. A follow-up research pass should check real reference for each place (US port-city liquor stores, tow yards, small-airfield hangars, 24 h diners at night) before any art. I have not done that research in this doc.

**Debt holder, a question.** Roy replaced the Pike Lending **storefront**. The story bible still names Pike Lending as the **debt holder**. Options: keep Pike Lending as an unseen company (story only), or rename it. Roy's call; this doc does not need the answer.

## 6. Mirrors and first person: the game looks for you

Roy wants no keys. The cockpit already has head movement (on, with an off switch) and the proximity cue (`cockpit_mirrors.gd`).

**What a blind spot indicator is:** a small light in or near the side mirror that turns on when a car is in the zone beside and just behind you, where the mirror cannot see it. Real cars have had them since the mid-2000s.

Proposal, all automatic:

| Trigger | What the camera does | Notes |
|---|---|---|
| You steer toward a lane at speed while a car is in that rear quarter | Head glances toward that mirror and shoulder for about 0.4 s, then back | The over-the-shoulder look Roy mentioned, only when it matters |
| A car closes fast from behind (proximity cue already detects it) | Short glance at the rear-view mirror | Uses the existing proximity cue |
| Reversing | Head turns over the shoulder and stays while reversing | Natural; no key |
| Hard braking with a car close behind | Quick mirror glance | Optional, tune in playtest |

- Glances are short, capped to about one every 2 s, never during a corner at high steering lock, and follow the head-movement setting (off means off). Strength is a slider.
- **Blind spot lamp as a garage mod.** The cars are older designs, so they do not have it stock. Fitting an aftermarket amber blind-spot lamp (palette amber `#FFC066`) is an early, cheap mod. It is the mechanic improving their own car, which is the whole story in one part.
- **Why it matters to the narrative:** first person is where the "mechanic" fantasy lives. The car talks through its gauges, sounds and the warm-up needle, and the driver's head moves like a real driver's. No HUD arrows, no key hints, consistent with the existing rules.

## 7. How the pieces connect (summary map)

```
 STORY BEAT ---> sets ---> EVENT POWER BAND (T0-T5)
     |                          ^
     | opens                    | you reach it by
     v                          |
 LANDMARK (person + verb) --> customer job --> GARAGE mini-game --> Cred + parts
     |                                              |
     | overheard rumours, favours (Ferris)          | repair / mods / care
     v                                              v
 NIGHT RUNS (Stage C pot, bank, heat) <------ ENGINE STATE (warm-up, heat, knock, limp floor)
     |
     v
 DAVE on air: reacts to runs, engine health, story beats (text lines Roy writes)
```

## 8. Build order (each its own proposal and PR, nothing batched)

This doc builds nothing. If approved, it changes these existing proposals before they are built:
1. Engine spec: replace "dead, tow to garage" with the limp floor plus roadside patch; add the cold-engine rules from 4a.
2. Stage C: add the night wrapper (section 1) and story-event bands (section 3) as data only.
3. Landmark doc: swap the Pike storefront for the liquor store; re-map phases to W5; add the research pass.
4. Cockpit/mirrors: auto-glance and the blind-spot lamp mod (section 6), after the interior redesign.
5. Per-car tier presets: one data pass per car when the other 5 player cars are built.

## Open for Roy (one word each, recommendation marked)

1. Daylight only inside the garage, streets always night? **Yes (recommended)** / No
2. Prologue car weaker than today's (T0, one night)? **Yes (recommended)** / No, start at stock
3. Failure system: **limp floor + roadside patch (recommended)** / Ferris call / crew call
4. Event power bands with a one-click race spec? **Yes (recommended)** / No caps at all
5. Act 2 Ironbridge boss is Ledger's number two, Ledger only at the end? **Yes (recommended)** / No
6. Blind-spot lamp as a garage mod rather than stock? **Mod (recommended)** / Stock
7. Debt holder after the storefront change: keep Pike Lending unseen / rename (your words)
