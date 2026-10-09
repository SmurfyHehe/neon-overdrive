# Police build plan (Stage F), 2026-10-09

Status: PLAN, docs only. Nothing is built. Turns the decided police design into
a PR-by-PR build order the laptop sessions can start on. Every rule marked
"decided" comes from Roy's earlier answers; nothing here re-opens them.

**Inputs read:** corrupt police and Pike (rev 5, decided except the rookie
ending), balance plan (heat pacing table, bust costs), stops proposal (station
lock, heat drain), traffic decisions (offence and near-miss rules), road lanes
proposal (exits, median gaps), sound research (sirens, scanner cast), more
ideas (lights off, roadblocks, search phase), fleet design sheet (c1-c3 police
bodies), project memory (helicopter, corrupt cop and sound decisions).

**Code checked (live clone, `origin/main` = `282343f`, fetched 2026-10-09
07:30Z):** no police, heat, money or fuel scripts exist. Only the engine heat
(`powertrain_health.gd`) uses the word heat. Traffic is a fixed pool of
`TrafficCar`s on a 4+4 lane highway with a median barrier and boundary walls,
streamed in 50 m chunks, 16 chunks per district (`traffic_manager.gd`,
`districts.gd`). There are **no side roads, exits, overpasses or tunnels** yet.
The night clock exists (`night_clock.gd`). The three police bodies (c1 patrol,
c2 patrol SUV, c3 interceptor) exist only as design sheets
(`docs/design/fleet/`), not as cars in the game.

> Flag: project memory says main was `6ea5969` at 04:20Z. My fetch at 07:30Z
> returns `282343f` (merge of #266, 05:18Z). Worth a check by the merge
> session; the plan does not depend on it.

## One line

Build police in nine small PRs, each one something you can see on the road:
first a patrol car that sees you speed and lights up, then one that chases,
then busts that cost money, then the radio and sirens, roadblocks, hiding
spots, the bad cops, the helicopter and finally Pike's tricks.

## Steelman and premortem

- **Steelman:** police are the game's main pressure. Building them as a ladder
  (see you, chase you, catch you, make it sound real, escalate, then the
  story cops) means each PR is playable, and the bad cops land on top of a
  chase that already feels fair, which is what makes them scary instead of
  cheap.
- **Premortem, it failed because:**
  1. **The road has nowhere to go.** Today the world is one walled highway. A
     chase is a drag race, hiding is impossible, and "never spawn the bad cops
     where you can't leave" can't be met. Fix: hiding pockets come with the
     police track (F6) and use the road exits when they land; the bad cops wait
     for at least one way off the road (section 4).
  2. **Cops on the same sim as everyone are bad drivers.** Traffic AI only
     follows lanes. A cop that rear-ends traffic and flips looks stupid. Fix: a
     separate chase driver on the same GEVP car, tested in headless sweeps for
     flips, stuck cars and crashes into traffic before anyone plays it.
  3. **Busts feel unfair.** Fix: a visible bust timer that only fills when
     you are nearly stopped and boxed in, never while you are moving.
  4. **The laptop can't draw it.** Integrated graphics only. Fix: emissive
     light bars, at most 2 real lights per cop and 1 spotlight in the world,
     checked with the existing fleet budget test (30 traffic + 3 police).
  5. **We balanced police on paper.** Fix (balance plan rule): heat numbers
     are targets until F2 runs; the chase sweep sets the real ones.
- **Falsification:** if the scripted fleeing driver escapes 100% (or 0%) of
  chases at heat 2 across the sweep, the chase AI is not working and nothing
  after F2 should start.

## 1. What already exists and what police needs

| Police needs | Exists? | Where it comes from | Blocks |
|---|---|---|---|
| Cars on the same sim | Yes | GEVP raycast car, CarSpec data | Nothing |
| Lane and occupancy index | Yes | `TrafficManager.scan()` | Nothing; cops register in it |
| Night clock | Yes | `night_clock.gd` | Tow "clock jumps an hour" |
| Police car bodies (c1-c3) | Design only | Fleet sheet | Looks only; F1 uses a stand-in |
| **Cash tonight + bank** | **No** | Stage C money (also needed by stops S2) | Busts (F3), bad-cop shakedown (F7) |
| Fuel | No | Stops S1 | Nothing. Police never need fuel |
| Gas station | No | Stops S2/S3 | Only the "cop sees you" lock and double heat drain, which use F1's hook |
| **Side roads, exits, median gaps** | **No** | Road lanes proposal, PRs 4-5 | Better hiding (F6), bad-cop placement (F7), cops crossing over |
| **Overpasses / tunnels (cover)** | **No** | Road work, not yet proposed | Helicopter escapes (F8) |
| Racing AI, event board | No | Later stages | Pike tip-offs, setup races, box-ins (F9) |
| Story acts, "Pike reach" | No | Story system | F7 uses a plain number in the tunables file until then |
| Difficulty modes | No | Balance | Multipliers live in the tunables file from day one |
| Traffic lights / junctions | No | Decided "now", not built | Red-light offences hook in when they land |
| Scanner item (bought at the station) | No | Stops S6 | F4 shows captions always until the shop exists |

**Money is the one hard block.** Proposed: **F0, a small cash + bank counter**,
built once and used by both police and stops. Whoever starts first owns it.

## 2. The build order

Sizes: S (a day's session), M, L. Model per PR with the reason.

| PR | What you see in the game | Needs | Size | Model |
|---|---|---|---|---|
| **F0 Money counter** | A small cash number on the HUD. Cash grows from a test command (no races yet). At 6 a.m. (or "head home") cash moves into the bank. Bank shown on the pause screen. Both saved with the night | Night clock | S | Sonnet: plain bookkeeping |
| **F1 Heat and the first patrol car** | A patrol car (stand-in body: a traffic car in police colours with a light bar) cruising in traffic. Speed past it or hit a car in front of it and its lights and siren come on, a heat bar appears, heat 1. Drive out of its sight and the bar drains over ~30 s. It does not chase yet | Nothing | M | Opus: perception, heat rules, the hooks everything else uses |
| **F2 Honest pursuit** | The patrol car chases you: pulls out, catches up, follows your lane, tries to get alongside. Heat 2 sends a second car from behind. Lose them out of sight: cars slow and sweep, the bar drains, they leave. Honest cops **give up** when the chase gets too dangerous for traffic (decided) | F1 | L | Opus: chase driving on a real physics car is the hardest step |
| **F3 Busts: ticket and tow** | When you are nearly stopped with a cop beside you, a bust ring fills over ~3 s. Busted: a short card "Ticket $X, tow $Y", money leaves the **bank** (by heat level, decided table), you keep tonight's cash, the screen fades, you restart an hour later (decided) | F0, F2 | S-M | Sonnet: rules already fixed in the balance plan |
| **F4 Sirens, scanner and tension music** | Real siren sounds (wail, yelp, hi-lo) that change with distance and pass you with Doppler. Scanner captions with squelch at the bottom of the screen: "Unit 4, suspect northbound, grey coupe". Radio music gets a tension layer at heat 2+ | F1 (F2 for most lines) | M | Sonnet: synthesis and caption table, patterns exist in `engine_synth.gd` |
| **F5 Heat 3-4: roadblocks and spikes** | At heat 3, cars across the lanes ahead with one gap. At heat 4, a spike strip in the gap: hit it and your tyres go soft (slower, pulls to one side). Ramming a cop jumps you to heat 4. More units | F2 | M | Opus: placing blocks fairly on a moving, bending road |
| **F6 Hiding spots and lights off** | Dark pull-off pockets beside the road (closed lot, behind a billboard, under a sign gantry). Stop in one with your lights off: cops drive past, heat drains faster. Never in a dead end (decided). When exits land, pockets also sit on the ramps | F2; exits make it better | M | Sonnet: road builder feature plus a rule; Opus not needed |
| **Cop bodies (parallel)** | The real c1 patrol, c2 SUV and c3 interceptor from the design sheet replace the stand-in | Fleet sheet | M | Fable: car shapes and silhouettes |
| **F7a Bad cops: behaviour** | One bad pair (sergeant + veteran) can join a chase at heat 3+ (decided). They creep up with lights off, ram and push, never give up, are faster on straights and worse in tight turns. Caught by them: **all of tonight's cash** is gone, no ticket, you drive on (decided). The scanner shows the dispatcher calling "Unit 12?" with no answer | F0, F3, F4, F5; exits for fair placement | M-L | Opus: behaviour rules and fairness tuning |
| **F7b Bad cops: the look and the scare** | Ghost livery, scraped push bar, A-pillar spotlight, grille strobes with no roof bar, dark tint (decided first set). The "oh f\*\*\*" moment: dark car, then high beams + spotlight + wig-wag + red-heavy broken strobes all in one frame, one deep rumble that shakes the cockpit | F7a, cop bodies | M | Fable: lights and visual judgement |
| **F8 Helicopter** | At heat 5 only (decided) a helicopter arrives, its beam lights the road around you. Escapes (decided): shake the beam with hard turns, chain cover, outrun it. Rotor thump overhead. It can catch the bad cops on camera (a clue) | F2, F5; **cover** (overpasses/tunnels) from the road work | L | Opus for perception and escapes, Fable for the beam look |
| **F9 Pike's tricks and story beats** | The free pass (bad cops chase a Pike racer, let him go, turn on you), tip-offs after you beat a Pike racer, setup races, box-ins, the prologue pull-over | Racing AI, event board, story system | L, split later | Opus for story logic |

**Order and what runs in parallel:**

```
F0 money ───────────────┐
F1 heat + patrol ── F2 chase ── F3 busts ── F5 blocks ── F7a bad cops ── F7b scare ── F8 heli ── F9 Pike
                 └── F4 sound (after F1, parallel with F2-F3)
                          └── F6 hiding (after F2, parallel with F5)
Cop bodies (Fable) ── any time, must land before F7b
```

F0 and F1 can start today in two sessions. F4 and the cop bodies can each run
in parallel once F1 lands. Everything in the long chain waits for the PR
before it, because each one is tuned on top of the last.

## 3. How each piece works (for the builder)

### Heat (F1)

- One node, `PoliceHeat`, owns **heat 0-5**, a cool-down timer and signals
  (`heat_changed`, `pursuit_started`, `pursuit_ended`, `busted`). One heat
  meter, no second bar (decided).
- **Offences only count when a cop sees them** (traffic decision 5): speeding
  well over the flow, contact with a car, driving in the oncoming lanes,
  ramming a cop. Near misses never add heat (decided). Red lights hook in when
  junctions exist.
- **Seeing:** distance (~120 m, less with your lights off), a view cone, and
  one ray for line of sight, checked a few times a second per cop, not every
  tick.
- **Heat ladder** (balance plan targets, re-measured in F2):

  | Heat | How you get there | What shows up | Cool-down |
  |---|---|---|---|
  | 1 | A cop sees you speed | 1 patrol car | ~30 s out of sight |
  | 2 | Run from heat 1, or a cop sees contact | 2 cars | ~60 s |
  | 3 | A long chase | Roadblocks; bad pair can appear | ~90 s |
  | 4 | Rammed a cop, very long chase | Spike strips, more units | ~2 min |
  | 5 | Top heat only | Helicopter | ~3 min, must break sight |

- **Hook for everything else:** `PoliceHeat.cop_can_see_player()`. The gas
  station menu lock (decided) and the double drain while parked at a station
  (decided) call this; police does not need to know stations exist.
- All numbers live in one tunables file with difficulty multipliers (Daily
  Driver ×1.4 cool-down, Racer ×0.75; bust chance targets ~10 / 20 / 35%).

### Police cars (F1, F2)

- A police car is a normal car on the same sim (decided rule: every car runs
  the same raycast-wheel sim, only CarSpec data differs). It lives in the
  traffic pool and the occupancy index, so traffic brakes for it and it
  brakes for traffic.
- **Two drivers on one car:** cruising uses the existing traffic lane driver;
  a chase hands the car to a **chase driver** that picks a target point
  (behind you, then beside you), a lane from the occupancy index, and a speed
  that closes the gap without rear-ending traffic.
- **Where cops come from:** the road is a corridor, so spawning is the design.
  Ahead of you in your direction (you catch up to them), behind you out of
  sight (they catch up), or **parked on the shoulder** with lights off. Cops
  on the other side of the median can't cross until the road has median gaps
  (question 7).
- **Call-off (honest only, decided):** a "danger" number from your speed and
  how much traffic is around. Above the line for a few seconds, honest units
  radio "pursuit terminated" and peel off. Heat then cools as if you were out
  of sight. Bad cops ignore it.
- Budget: max 3 police cars at once (fleet sheet), emissive light bar plus at
  most 2 real lights per car, flashing done in the shader.

### Busts (F3)

- **Bust ring:** fills only when you are under ~10 km/h, a cop is within
  ~6 m, and you are not moving away. Any real movement empties it. Takes ~3 s.
- **Honest bust (decided):** ticket + tow from the **bank**, size by heat
  level (balance table: 0.08 / 0.15 / 0.25 / 0.4 / 0.55 nights, ×0.75 easy,
  ×1.25 hard). Cash kept. Clock +1 hour. Bank never goes below zero.
- **Where you wake up:** the garage scene does not exist yet. Until it does,
  you restart at the start of the road (question 3).
- **Bad-cop bust (decided, F7a):** all tonight's cash, no card, no clock jump,
  you drive on.

### Sound (F4)

- Synthesised sirens (wail, yelp, hi-lo, switching with chase state), 3D with
  Doppler, `max_distance` set (sound research). No downloads needed; any
  recorded sound must pass the asset rule (free, commercial, no credit).
- Scanner: captions + squelch now, voices later (decided). Five-role cast,
  lines stitched from pieces (unit + what + your colour and car + direction).
- The scanner is a station purchase (decided). Until the shop exists, captions
  are always on.

### Roadblocks and spikes (F5)

- Placed 300-500 m ahead, out of sight, **always with a gap** you can thread,
  never right after a bend you can't see around.
- Spike strip: soft tyres = lower grip and a pull to one side until a station
  quick fix or the garage (question 5). Needs a small tyre-damage value in the
  car; no tyre damage exists today.

### Hiding spots (F6)

- A "pocket" feature in the road builder: a dark bay off the shoulder with
  cover (wall, billboard, parked truck). Fixed per district, like stations
  (decided: fixed landmarks, new bends and traffic each night).
- Rule: stopped in a pocket, out of direct sight, lights off: heat drains
  faster and cops passing need to be close to see you.
- Never a pocket with no way back onto the road (decided).

### The bad cops (F7)

All of this is decided in the corrupt police doc; the build points:
- One flag on a police car, `on_pikes_payroll`, plus behaviour switches.
- **Only one bad pair in the world at a time**, gated by a hidden "Pike reach"
  number (a plain value in the tunables file until the story system exists).
- **Fair placement:** lurk spots anywhere (decided), but never where you
  can't leave. On today's walled highway that means: only within reach of a
  hiding pocket or, once built, an exit. This is why F7 waits for F6.
- **Faster on straights, worse in tight turns** (heavy push bar). The
  counterplay is twisty roads, so the bend tuning must give some.
- **The scare sequence** (F7b): lights off creep, then everything in one
  frame at 20-30 m. One SpotLight3D in the whole world, used by them or the
  helicopter, never both.

### Helicopter (F8)

- Heat 5 only, spots only, escapes by driving (decided). Beam lights the road
  (decided). Honest; its camera can catch the bad cops for a clue.
- **Needs cover** (overpasses, tunnels, sign gantries) that the road does not
  have. A small road PR adds overpasses before F8, or F8 ships with "outrun
  and shake the beam" only. Garage tools against it come later (decided).

## 4. Tests: headless sweeps, never one setting

Roy's rule: sweep sliders and settings, not one config. All runs are real
headless Godot (`tests/run_one.ps1`), reusing `tests/traffic_harness.gd`
(error logger, scripted lane-keeping driver, stats).

**New harness: `tests/chase_harness.gd`** with a scripted **fleeing driver**
at three skills (clean / average / sloppy) that speeds past a cop and then
tries to escape.

| PR | Test | Sweep | Fails if |
|---|---|---|---|
| F0 | Cash in, dawn banks it, save and load | 3 amounts × bank / no bank × reload | Any money lost or doubled |
| F1 | Cop sees speeding, contact, oncoming lane; ignores near misses and anything behind a wall | Lights on/off × 3 speeds × traffic count (0, 16, 30) × 5 seeds | A missed offence in clear view, or any heat from a near miss or from out of sight |
| F2 | Chase from heat 1 and 2 | Traffic count × 3 skills × 3 player cars × difficulty × 20 seeds | Escape rate outside 75-85% (average skill, middle difficulty), any cop flipped or stuck > 5 s, cop-into-traffic crashes above a set rate, frame time over the fleet budget |
| F2 | Call-off | Traffic count × player speed | Honest cops never call off in heavy traffic, or call off in empty traffic |
| F3 | Bust only when stopped | Fleeing driver that slows to 5, 10, 20 km/h | Any bust while moving over ~10 km/h; bank below zero; cash touched by an honest bust |
| F4 | Siren voices and caption rate | Heat 1-5 × 3 cops | Over the live voice cap, a caption repeating within 30 s |
| F5 | Roadblock placement | Bends × lane counts × seeds | No gap in a block, a block inside sight distance, a block right after a blind bend |
| F6 | Hiding works | Pocket × lights on/off × heat 1-4 | Found while hidden and out of sight at normal range; any pocket with no way out |
| F7a | Bad pair fairness | 3 skills × traffic × twisty vs straight district × 20 seeds | Average-skill escape under ~50% on twisty roads, or a spawn with no way off |
| F8 | Helicopter | Heat 5 × skill × road with and without cover | Never escaped, or escaped by doing nothing |

Each PR also runs the existing `fleet_budget_scene` and `traffic_perf` with
police in the scene, so the laptop's frame budget is checked every time.

## 5. The first slice (recommended start)

**Two laptop sessions in parallel:**

1. **F1: heat and the first patrol car (Opus).** Stand-in police car in
   traffic, perception, heat 0-5 node with cool-down, HUD heat bar, light bar
   and a placeholder siren tone, `cop_can_see_player()` hook, tunables file,
   and the F1 sweep in the table. **What Roy sees:** a police car in traffic
   that lights up when you speed past it, a heat bar that fills and then
   drains once you are out of its sight.
2. **F0: money counter (Sonnet).** Cash on the HUD, bank on the pause screen,
   dawn banks the night, saved. Also unblocks stops S2.

F2 (the chase) starts the moment F1 is merged; it is the step everything else
stands on.

## 6. Flags

- **Main hash:** memory says `6ea5969`, my fetch says `282343f` (top of this
  doc).
- **Escape reward is not decided** anywhere. The balance plan has no money from
  chases. Question 6.
- **The walled highway is the biggest risk to police.** Hiding, fair bad-cop
  placement and helicopter cover all want side roads, exits and overpasses.
  The road exits work (decided, not built) should run before or alongside F6.
- **Spike strips need tyre damage**, which no part of the car has today.
- **Stops and police share two hooks** (money, cop-in-view). F0 is listed here
  but serves both; only one session should build it.

## 7. Questions for Roy

Recommended answer first in each.

1. **Heat on screen:** a small bar on the HUD while cops are after you, or
   nothing on screen (only lights, sirens and radio)? **Bar** / None
2. **Before the real police cars are made:** start with a stand-in police car
   (a plain car with a light bar), or wait for the real one? **Stand-in** /
   Wait
3. **After an honest bust**, until the garage exists: restart at the start of
   the road an hour later? **Yes** / No
4. **Turn your headlights off to hide:** cops see you less, you see the road
   less. **Yes** / No
5. **Spike strips:** soft tyres until a gas station fix, or only for a few
   seconds? **Station** / Seconds
6. **Escaping a chase pays** a little cash by heat level (cash the bad cops
   can take), or nothing? **Cash** / Nothing
7. **Cops from the other side of the road** cross over through gaps in the
   middle barrier once the road has them? **Yes** / No
8. **Start now:** the patrol car and the money counter in two laptop
   sessions? **Yes** / Wait
