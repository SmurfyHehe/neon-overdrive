# Neon Overdrive — Car Culture Roadmap (approved 2026-09-29)

Roy approved this plan on 2026-09-29. It replaces the endless-highway-survival roadmap, which is kept further down for reference. Research behind it is in two reports ("Car culture game research" and "Car culture game design research"). The proposal page Roy signed off is at https://claude.ai/artifact/282jj5PnGRwxkzsy8jfb4R.

## The game

You're a mechanic by day. Each night you choose how to spend it: work on your own car, go to an event, move the story on, or pick up an extra shift. The events are ranked:

1. **Pulls:** roll races and dig races.
2. **Good driving:** highway runs and touge.
3. **Burnouts and takeovers:** this is what "drifting" means here. It's US street takeovers, donuts and smoke shows, not Japanese angle drifting.

You climb a street list of ten names, one callout at a time.

## The loop

- **Day:** a short shift at the shop. Two or three customer jobs pay the bills and drop tips. A customer's car can belong to a rival you race later, unlock a part at cost, or start a story beat.
- **Night:** **one main activity plus one small extra**, such as a quick tune or a drive past the meet (Roy's pick). A strict one-thing-per-night rule is close to NFS Unbound's calendar, which players hated.
- **Week's end:** rent (and possibly a garage debt) falls due, and a new callout is posted. A family garage debt was suggested as a story hook, but story is parked for Roy to write, so treat it as a placeholder.
- **Money:** a normal shift covers roughly the bills and an extra shift adds about half again. A won event pays more than a shift, and a lost one pays less. These are starting numbers, to be set by playtesting.
- **Missed payments:** Roy wants a layered system that uses all three candidates and possibly more. The candidates are:
  - a capped late fee with a tool held until you pay;
  - replaying the week, keeping upgrades but not cash;
  - a loan-shark rival whose story ends in a race for your car;
  - a race or job you must run for the debt holder.

  The exact layering is still to be designed. One rule is fixed: there is always a floor, meaning a job that pays and a race with no entry fee, so the player can never be stuck broke. Research notes: `C:/SmurfyHehe/neon-overdrive-research/research_notes/debt_penalties.md` (outside the repo).

## The events

| Event | Rules | Notes |
|---|---|---|
| **Dig race** | 1/8 mile from a stop, no handicap. If you jump, you lose. | **Full steering** (Roy's pick). Lane-change-only and correction-only can be added later as settings. Launch with the revs in the green, and a shift light grades each shift (NFS Underground). Hole shots let reaction beat horsepower. A "no prep" low-grip surface was suggested, but Roy did not pick it in the brainstorm, so it is parked. Before building the strip, check that a keyboard dig race takes skill: manual shifting and a launch-rpm window, not just the tune. |
| **Roll race** | Pace side by side at 40 (freeway) or 60 (strip). Three honks, then go. The first to pull clear or reach about 140 mph wins. | Jumping the third honk is a foul. This is where engine upgrades show most. Reuses the dig race code and rival. Rolling through traffic waits for the traffic milestone. |
| **Highway run** | Flash your lights to challenge a rival. Each car has a bar that drains while it's behind, and faster the further back it falls. Hitting traffic or a wall costs a chunk. | This is Tokyo Xtreme Racer's spirit-points duel. There's no hidden AI catch-up. Reuses the road generator and the rival. Needs traffic, which is not built yet. |
| **Touge** | Two runs with lead and chase swapped. The chaser wins by closing the gap and the leader by stretching it. A third run breaks a tie. | An American canyon road with named corners. It needs curves and hills first (#37), and it shares the gap system with the highway run. |
| **Burnouts and takeovers** | Summernats-style scoring out of 100: smoke and car control, minus points for stalling, reversing or hitting the barrier. Takeovers add a crowd hype meter and a police timer. | Always show what ends a combo. PR #82 checks whether the car can do burnouts and donuts at all. |

## Rivals, rep and heat

- **The List:** ten names. You move up only by calling out someone above you and winning, and a callout expires after three nights. Rivals sit in crews by event, each with a boss. Each rival is one row of data.
- **Rep and money:** there's one currency, money. There are two kinds of rep: **speed rep** is your List rank, and **respect** comes from clean conduct at meets. There is no second points currency.
- **Meets:** meets are the hub where you find races and hear rumours. A burnout on the way out wins hype, but it adds heat and can get the next meet shut down.
- **Heat:** stored per car. Getting caught brings a fine and a strike. Three strikes means impound, with a steep buy-back. Respray or plate work lowers heat.
- **Pink slips:** rare story moments only.

## Maps

Separate maps are picked from a menu, and each one is a proper full-size place (Roy asked for bigger than the first draft):

| Map | Size |
|---|---|
| Industrial district (dig and roll strips) | about 3 km of streets |
| Freeway | 25–30 km loop, mostly laid by the road generator |
| Mountain pass | 8–10 km each way |
| Downtown (takeovers and meets) | about 1.2 × 1.2 km |
| The shop | a garage and its block |

## What happens to the current game

- **Keep:**
  - the driving physics (60 Hz, see below), the test car and the gritty PS2 night look;
  - the tuning panel, upgrade tree and vehicle registry (PR #79). The tree's drift branch becomes a burnout branch: torque, rear bias and line lock;
  - the road generator, which lays the freeway;
  - the near-miss formula, which is a design on paper only.
- **Not built yet:** there are **no other cars in the game**: no traffic, no rival, no AI (`player.gd` notes "No traffic exists yet"). Traffic and near-miss detection were planned but never built, so they are milestones of their own below.
- **Park:** the fuel meter and procedural stop places. The code stays, but stop building them.
- **Change:** damage stops ending the run and becomes repair cost and time.
- **Move:** the police chase moves to milestone 7.

## Milestone order

Each milestone follows the same steps: propose, get Roy's sign-off, build, playtest. Then start the next one.

| # | Milestone | Playable result |
|---|---|---|
| 1 | **Rival car + dig race, then roll race** | One scripted rival (follows a speed curve, no GEVP physics, so it is cheap and can't spin out). Dig race on the empty straight first, with full steering, manual shifting and a launch window. Then the roll race: 40 mph pace phase and a three-honk start. |
| 1b | **One-week mock, menus only** (alongside 1) | Day result, night choice, money, rep and bills, with no driving. Tests whether choosing nights feels like freedom or like chores, which is the biggest risk (NFS Unbound's calendar). |
| 2 | **The List** | Ten rivals in crews, callouts with timers, grudge and cash stakes. |
| 3 | **Traffic** | Lane-following traffic on the freeway (MultiMesh per the rendering notes), then near-miss detection. Unlocks roll races through traffic. |
| 4 | **Highway run** | The gap-bar duel on the freeway with traffic. The rival reacts to the gap visibly, never with hidden catch-up. |
| 5 | **Full night loop** | The real day job board, night menu and weekly bills, built on whatever the week mock taught us. |
| 6 | **Touge** | Curves and elevation (#37), then the mountain pass and two-run lead and chase. |
| 7 | **Heat and police** | Heat per car, strikes, impound and escape runs. |
| 8 | **Meet hub** | A lot to hang out in, respect, rumours and raids. |
| 9 | **Burnout pad and takeover** | Design comes from the takeover specialist. PR #82 is the burnout and donut feel check. |
| 10 | **Hands-on day job** | Roy's newest idea: the day job is driving the shop truck (tows and deliveries). Needs a second vehicle setup. |

Rival and crew cars are scripted by default. Only the player's car runs full GEVP physics, to stay under the laptop's CPU ceiling.

Story runs through every milestone as text, stills and phone messages.

## Still open

- **Top 3:** about 90 ideas have been picked across two brainstorm sessions, none ranked. Ask Roy which 3 the game must have on day one before scope grows further.
- **Two idea pages disagree:** this roadmap's proposal page (https://claude.ai/artifact/282jj5PnGRwxkzsy8jfb4R) and the merged brainstorm page (https://claude.ai/artifact/QQNekPUnt5bPcUDVrVWJEV) conflict on no-prep, the family debt and missed-payment penalties. They need one source of truth.
- **Crew system:** anyone who races or earns for the garage gets their own car. Parked for its own brainstorm.
- How the missed-payment penalties layer together (see above).
- Setting: suggested as an American city with a nearby canyon. Not yet confirmed.
- The game's name: "Neon Overdrive" no longer matches the look Roy picked. It stays as a working title.

## Superseded 2026-09-29: endless-highway roadmap (2026-09-12)

Kept for reference. The car-culture roadmap above replaces its goal and build order. Still in use: the physics notes, the near-miss formula (now feeding the highway run and respect), the upgrade-tree structure (drift grip becomes a burnout branch) and the rendering proposals. Fuel, stop places and damage-ends-run are parked.

## Roy's 2026-10-04 plan: stages A–G

**Goal:** a complete playable run loop, built in this order. Every stage is
verified headless with real simulated input, logged here, and **stops for
Roy's sign-off** before the next one starts. Stage D stops after every car.

| Stage | Contents |
|---|---|
| A | Feel + environment art: dynamic FOV, camera shake, lower chase cam, speed-scaled engine/wind/tyre audio, dense roadside detail, narrower road |
| B | Milestones 3–5: lane-follow traffic, reactive traffic, camera + HUD. The 3 NPC cars are built here |
| C | Milestones 6–9: damage, fuel, stop places, currency/scoring |
| D | The 5 remaining player cars, one at a time, each with its CarSpec |
| E | Milestone 10: garage + a real branching mod tree per player car |
| F | Milestone 11: heat/wanted + police pursuit. The 3 cop cars are built here |
| G | Integration: full-loop run, balance, bug sweep, Windows export on request |

**Constraints (Roy, 2026-10-04):** verify by running Godot headless with real
simulated input, and check `run/main_scene` before calling anything hung. Use
original designs only, with no real makes or logos. Log every decision here as
it happens. Flag contradictions instead of picking silently. Never delete Roy's
files. Don't touch the parked top-speed plateau in `process_clutch()` or the
automatic-vs-manual clutch question unless Roy raises them.

**Rules carried forward:**
- **Physics:** GEVP stays vendored and unmodified. The one logged exception is
  `clutch_torque = 0` in Neutral. Extensions live in `aero.gd` and `car_spec.gd`.
- **Every car runs the same raycast wheel sim** (player, NPC, cop, modded),
  told apart only by CarSpec data. Roy, 2026-09-13, restated 2026-10-04.
- **Gas-only powertrain** for all 12 cars (Roy, 2026-09-13).
- **Mod trees:** each player car gets its own branching tree, 8–15+ nodes
  (for example a grip branch and a power branch), applied as CarSpec
  overrides. This answers GitHub #71 and supersedes the shared five-track tree
  and three car tiers further down (2026-09-12).

**Fleet: 12 original designs** inspired by real categories. These and their
reference cars were agreed with Roy on 2026-09-13; they were only in Claude's
notes until now.

| Role | Car | Real-world reference points |
|---|---|---|
| Player 1 | Sports coupe | Supra A80, Silvia S13–S14, RX-7 FD3S |
| Player 2 | Hot hatch (light, agile starter) | Civic Si, Golf GTI, 205 GTI |
| Player 3 | Tuner sedan (JDM, mod-friendly) | Skyline R32–R34, AE86, Lancer Evo |
| Player 4 | Kei-style roadster (light, low power) | Honda Beat, Suzuki Cappuccino, Autozam AZ-1 |
| Player 5 | Muscle sedan (RWD, torque, low grip) | Impala SS, Chevelle SS, Caprice 9C1 |
| Player 6 | Performance crossover (AWD, tall) | Crosstrek/XV, A6 Allroad, Delta Integrale |
| NPC 1 | Commuter sedan | Camry, Accord, Sentra |
| NPC 2 | City hatchback | Yaris, Fit, Swift |
| NPC 3 | Pickup/SUV | Hilux, F-150, Land Cruiser |
| Cop 1 | Patrol sedan | Crown Victoria P71, Charger Pursuit |
| Cop 2 | Patrol SUV | Police Interceptor Utility, Tahoe PPV |
| Cop 3 | Unmarked interceptor | unmarked Charger Hellcat, Mustang GT PI |

**Open conflicts flagged 2026-10-04. Items 1–3 were resolved by Roy on
2026-10-05 (see "Stage B" below):**
1. **Direction.** PR #83 (open) records a car-culture plan Roy approved on
   2026-09-29. It parks fuel, stop places and damage-ends-the-run (stage C
   here) and makes rival and traffic cars scripted. This plan builds them.
   **Resolved, Option C:** traffic stays full-sim. Fuel, stops and
   damage-ends-the-run move to after the garage, and currency/scoring stays
   before it. This supersedes PR #83's scripted traffic.
2. **Cars.** PR #79 (open) moves cars to imported models through a vehicle
   registry. Stage D assumed 12 cars built here. **Resolved:** we design all
   cars ourselves in-engine, and PR #79's import pipeline is not used.
3. **CPU cost of full-sim traffic.** RESEARCH-cheap-pretty.md warns that the
   i5-1235U has 2 performance cores and that traffic should not get GEVP
   bodies "without a measured reason". Roy's rule above is that reason, so
   stage B measures traffic density against the frame budget before
   committing a number. **Resolved:** measure first. If that shows it's
   needed, add a "Traffic detail distance" slider, as a scoped exception
   (B2).
4. **Coupe status.** Not "awaiting judgement": Roy said "our car model sucks
   atm" (#16), but he judged it while it rendered inside out, a winding bug
   fixed after (PR #45). The game currently spawns the neutral test car (#63).

### Stage A plan and decisions (2026-10-04)

**Look:** Look Board option **B, "Gritty PS2 night"**, which Roy picked on
2026-09-29: dark, orange sodium lamps, lamp pools, film grain, heavy shadows,
**no neon**. It also matches the Street-Spec reference ("slightly low-poly and
retro"). So stage A repaints the neon palette (cyan/magenta pylons, purple
fog) instead of adding more neon. Approved night-lighting proposal 1 (dim cool
key, emissives as the visible light) still holds.

**In scope:**
- **Camera:** lower chase cam, speed FOV with a partial dolly so the car keeps
  its size while the world stretches, and speed/surface/impact shake. It goes
  into one ChaseCamera class, and Roy's three smoothing modes (#31) are kept
  as they are.
- **Audio:** wind, rolling-road roar, tyre squeal and kerb/sidewalk rumble,
  driven by speed, slip and surface. The synthesized engine from #57 is reused
  unchanged, since its pitch already follows rpm and therefore speed through
  the gears. Final engine tuning still waits on #62.
- **Road:** narrower overall, with max 3 own-direction lanes (was 4), a
  narrower shoulder, and buildings closer. `LANE_W` (2.3 m) is
  **not** narrowed: it is already narrower than a real lane, and stage B
  traffic needs it.
- **Roadside detail:** sodium street lamps with fake light pools, dense
  delineator posts instead of neon pylons, and walls closing the gaps between
  buildings. All are MultiMesh, with draw calls counted before and after.
- **Look support:** headlights on the player car (the detail has to be
  visible), a blob shadow under it, and a light film grain.

**Deferred, to propose later:** tunnels (part of look B; a new chunk type),
utility poles and wires, overhead signs, vertex-coloured road lighting
(proposal 2, still not approved) and wet-road reflections.

### Stage A log (2026-10-04, as it happened)

- **Baseline on main (25dbf17):** all 9 `run_tests.bat` tests pass in the
  cloud sandbox (Godot 4.7.2 Linux, lavapipe for window tests).
  `floating_origin_drive` (not in the runner) is flaky there before any
  change: frame overshoot 0.000–0.019 m against a 0.0 limit, 1 of 3 runs.
- **Camera:** extracted to `scripts/chase_camera.gd`. Height 3.2 → 1.85 m,
  distance 6.0 → 5.2 m, look 12 m ahead at 0.95 m. FOV goes 58° → 74°
  (vertical), linear from 5 to 45 m/s, so today's ~35 m/s top speed already
  gets ¾ of it. Hard acceleration adds up to +3° and braking takes off 2°.
  The dolly is 70%, so the car keeps most of its size as the FOV widens, and
  the camera drops 0.2 m at speed. Shake has three parts: a speed buzz
  (≤0.46°), kerb/sidewalk rumble, and impact trauma when velocity jumps by
  more than 0.8 m/s in one tick. Hard braking peaks at 0.32 m/s per tick,
  measured, so braking never reads as an impact.
- **Found while looking at Roy's own 2026-09-29 screenshots:** the buildings
  rendered as solid white blocks, even with glow off. The window material
  used the default `EMISSION_OP_ADD` with a white emission colour, so every
  face emitted ≥1.4. **Fixed** (MULTIPLY), with a regression check in
  `tests/roadside_detail.gd`. This was very likely a large part of
  "environment is trash".
- **Environment:**
  - Palette moved to look B: near-black sky with a sodium-orange horizon,
    warm dark fog (density 0.006 → 0.009), and grey asphalt (lighter than
    before, so headlights show on it).
  - Markings are paint, emitting at 0.28, below the glow threshold. Curb and
    median barrier are concrete. Posts every 5 m replace the neon pylons
    every 8 m.
  - Sodium lamps every 25 m per side, staggered, each with an additive light
    pool on the road that fades out between 110 and 170 m.
  - Buildings have longer frontages (9–18 m) at 25 m spacing; their windows
    use world-space mapping on a 25 m tile, which divides the 1 km
    floating-origin shift. Gap walls fill the lots between them.
  - Player car gets a headlight (one spot: 28 energy, 55 m range, 30°) and a
    blob shadow decal. The car's meshes move to render layer 2 so the decal
    skips them.
  - Film grain is a darken-only multiply at 9%, at 24 fps.
- **Gap walls are visual only.** Out-of-bounds collision is #28, and
  uncommitted work for it is sitting in Roy's root checkout, so it is not
  done twice here.
- **Sidewalk width kept at 2.2 m.** I tried 1.8 m, but then the car's
  1.76 m track barely fits, which quietly kills the drivable-sidewalk
  shortcut (a 2026-09-13 design decision). The test bots caught it: they
  could no longer get all four wheels onto the sidewalk.
- **Pre-existing warning, not caused here:** "MultiMesh interpolation is
  being triggered from outside physics process" shows up on main too, when
  a chunk recycles from `_process`. Left alone; noted for #28/#26 owners.
- **Audio:** `scripts/car_audio.gd` drives four looping layers made from
  noise in code, with no audio files:
  - wind, rising with v² on the World bus;
  - road roar, rising with v on the Tires bus;
  - tyre squeal from slip angle or slip ratio, weighted by tyre load;
  - kerb rumble on "Dirt", whose rate follows speed.

  The first squeal was three pure tones (it would have sounded like a synth
  whine) and became noise through three resonators instead. Hard launches
  squeal for real: 460 Nm through 1st and 2nd outruns rear grip in GEVP, so
  this changes if #62 retunes the power.
- **Process incident (fixed):** a read-only `git status` run on Roy's
  checkout from the desktop bridge's Linux shell, where deletes are blocked,
  left a stale `.git/index.lock` there for under a minute. It is moved out
  to `build/stage-a/`, and CLAUDE.md now has a rule for that shell.

### Stage A results (2026-10-04): signed off by Roy, 2026-10-05

**Sign-off (Roy, 2026-10-05):** speed feels fast now. Playability on a busy
road is still untested, so B2 checks it with real traffic. The branch is still
unpushed: Roy chose to stack stage B on top of it and push both later.

**Changed** (branch `feat/stage-a-feel-env`, based on main 25dbf17):
- `scripts/chase_camera.gd` (new): the camera from game.gd, plus the low
  rig, speed FOV and dolly, and shake.
- `scripts/car_audio.gd` (new): wind, road, squeal and kerb layers. The
  engine (#57) is unchanged.
- `scripts/road_chunk_builder.gd` and `scripts/game.gd`:
  - look B palette;
  - narrower road (3-lane cap, 0.9 m shoulder, buildings closer);
  - lamps, light pools, 5 m posts and gap walls;
  - the white-building fix.
- `scripts/car_fx.gd` and `scripts/film_grain.gd` (new): headlight, blob
  shadow and grain. `scripts/player.gd` gains three lines to attach audio
  and FX.
- Tests: new `camera_feel` and `car_audio` (headless) and `roadside_detail`
  (window), all in `run_tests.bat`. `floating_origin_drive` now reads the
  chase offset from the camera.
- `CLAUDE.md`: a git rule for the desktop bridge's Linux shell.

**Verified** in the cloud sandbox (Godot 4.7.2 Linux, real simulated keys,
window tests on a software renderer):
- All 12 runner tests pass (9 existing, 3 new), as do `engine_audio_render`
  and `floating_origin_drive` (2 of 2 runs).
- **Camera:** framing at rest is exact. At 28 m/s the FOV is 67.4° and the
  distance 4.59 m, and FOV follows speed (r = 0.994). The hardest braking
  peaks at 0.32 m/s per tick against a 0.8 threshold, so it never shakes. A
  wall hit at speed gives trauma 0.98, and the cruise buzz stays ≤ 0.13°.
- **Audio:** wind follows speed² (r = 1.000) and road follows speed
  (r = 0.997). Squeal tops out at 0.04 when cruising straight and reaches
  1.0 in a handbrake slide. Kerb rumble comes on. The loops take 115 ms to
  build. The real mix was recorded from the Master bus and checked on a
  spectrogram.
- **Layout:** `roadside_detail` covers 36 lane configs and their rebuilds.
  It was mutation-checked: it fails if the ADD-emission bug or the gap walls
  regress.
- **Draw calls** in benchmark mode, same drive: main averages 147 (max 160),
  stage A averages 171 (max 186), +16%.
- **Windows export:** builds with 0 errors. Its embedded pack loads in Godot
  and passes the smoke test.
- **Clip:** a 23.5 s drive with picture and sound, recorded with Godot's
  movie writer.

**Not verified / open:**
- **Frame time on Roy's laptop.** The software renderer here says nothing
  useful about it. `benchmark.bat` on the stage A build is the real check;
  main ran at about 3.3 ms there (2026-09-29), against a budget of 8–10 ms.
- **The .exe has not been launched on Windows**, since there is no Windows
  here.
- **Feel, look and mix are Roy's call.** Every value is a named constant:
  camera in `chase_camera.gd`, audio in `car_audio.gd`, lights in
  `car_fx.gd`, palette in `game.gd` and `road_chunk_builder.gd`.
- **Merge conflicts:** expect small ones with open PR #79 (`game.gd` HUD
  line, `player.gd` `_ready`). This branch has not been rebased onto it.
- **Not pushed:** the session's GitHub access refused the push (the Claude
  GitHub App isn't installed), so the branch is handed over as a bundle.
- **Waiting on Roy before stage B:** the direction (PR #83 vs this plan),
  the car pipeline (PR #79) and the traffic sim cost (see Open conflicts
  above). *(Resolved 2026-10-05, see Stage B.)*

## Stage B (revised 2026-10-05): design sheet, traffic, camera + HUD, exhaust

Four sub-stages. Each one **stops for Roy's sign-off**, with its results
written here first.

| Sub-stage | Contents |
|---|---|
| B1 | Design sheet for all 12 cars (design only, no modeling) |
| B2 | Milestones 3–4: lane-follow, then reactive traffic on the multi-lane highway, plus the 3 NPC cars built from the B1 sheets |
| B3 | Milestone 5: camera + full dashboard HUD |
| B4 | Exhaust build: synthesized exhaust, pops/crackles, flames, flamethrower tune |

**Decisions (Roy, 2026-10-05):**
- **Direction, Option C:** traffic stays full-sim (the same raycast wheel sim,
  told apart by CarSpec data only). Fuel, stops and damage-ends-the-run move
  to after the garage stage, and currency/scoring stays before the garage.
  This supersedes PR #83's scripted traffic.
- **Cars:** we design all cars ourselves in-engine. PR #79's import pipeline
  is not used. Designs are original, with real-inspired shapes and no
  licensed makes. Gas-only. Keyboard-only input.
- **Mods** change shape, paint, wheels and stickers. Each car has exactly
  **3 fixed sticker slots**.
- **Exhaust is cosmetic only:** loudness, tone, raspiness, pops/crackles,
  flames and a flamethrower tune. It has no wear, heat, fuel or police
  effects.
- **Target:** 60 fps on Roy's i5-1235U with Iris Xe.
- **Look:** "Gritty PS2 night" with the Street-Spec reference, and no neon.
- **Palette, "Amber vs. Dusk":**
  - sky `#1B2A4A`, shadow `#0E1424`;
  - sodium `#FF8A1F`, window amber `#FFC066`;
  - silver `#C9CED6`, taillight red `#E5262B`;
  - no magenta or cyan.
- **Budgets** are estimates, to be measured on the laptop: player ~10k tris,
  cop ~6k, traffic ~4k. Fewer separate parts matters more than raw triangles.
- **Traffic fallback (B2), built only if measurement shows it's needed:**
  - a "Traffic detail distance" slider in Settings;
  - cars beyond it run a cheaper sim and a simpler mesh, and near cars always
    run the full sim;
  - the handoff keeps position, velocity and heading, with no visible pop.

  This is the one scoped exception to the same-sim rule.
- **Stage A is signed off.** Stage B stacks on `feat/stage-a-feel-env`, and
  Roy pushes both later.

**Earlier inputs from Roy that stage B has to honour (chat, 2026-10-04/05):**
- **T menu:** tuning the car, including the transmission choice (automatic or
  semi-manual).
- **Pause menu:** a Settings tab for the other settings (camera, units).
- **Reverse:** R switches to reverse only when nearly stopped.
- **HUD:**
  - a steering wheel with an RPM bar that runs green to red as the shift cue;
  - an instrument cluster;
  - a visible gear shifter.
- **Road:** a multi-lane highway with **4 lanes per direction**. *This
  conflicts with stage A's 3-lane cap*, and B2 resolves it with traffic
  measurements.
- **Cars:** a complete redesign of all 12, "a generation up" in looks
  without losing performance.
  - Silhouettes must read from every angle, because a 360° garage camera is
    coming.
  - Interiors and undersides come later.
- **Top speed:** ~300 km/h through tuning stays; Roy likes it.

### B1 log (2026-10-05, as it happened)

- **Pre-checks:**
  - The real project is `C:\SmurfyHehe\neon-overdrive`; Documents has no
    `NeonOverdriveGodot`.
  - Stage A was neither in the repo (it existed only as a bundle on the
    laptop) nor signed off, so I asked Roy. He signed it off, and B stacks on
    the stage A branch, to be pushed later.
  - Roy's root checkout is on `main` 4c1ddca, 58 commits behind GitHub, with
    uncommitted edits. I reported it and didn't touch it (CLAUDE.md).
- **Method:**
  - Each car is data: profile curves, lofted into one low-poly 3D proxy in
    `tools/fleet_design/` (Python, software renderer). Every view on a sheet
    comes from that one shape, so the views can't disagree.
  - No Godot code or scenes changed in B1.
- **Design decisions (proposals, part of the B1 sign-off):**
  - **NPC 3 is a pickup, not an SUV**, so traffic can't be confused with the
    patrol SUV.
  - **Silhouette language per class:**
    - player: low and wide, wheels fill the arches, one hero cue each;
    - traffic: taller and softer, small wheels in big gaps;
    - police: big and upright, always with a police tell in the outline.
  - **Each car has its own tail-light signature**, for reading cars from behind
    at night.
  - **Sticker slots:** door (mirrored), hood, and one slot seen from behind, so
    every camera sees one.
  - **Police livery:** navy with silver doors and roof.
  - **Police blue `#2E4FD8` is the only off-palette colour** and is flagged for
    Roy.
- **Revisions from the renders and blind tests:**
  - **Decals:** placement fixed. Decals hug the curved panels; flat ones were
    sinking into the body.
  - **P1:** rounder tail, slimmer hoop wing.
  - **P2:** chunkier, with a wider track, blistered arches and a higher belt.
  - **P3:** cabin moved back.
  - **P4:** lower tail.
  - **P5** was the weakest player read. It gained a tall cowl scoop, a chopped
    cabin, a ducktail and coke-bottle hips.
  - **P6** gained rack crossbars.
  - **N3:** longer cab.

### B1 results (2026-10-05): waiting for Roy's sign-off

**Changed** (branch `feat/stage-b1-design-sheet`, stacked on
`feat/stage-a-feel-env`):
- `docs/design/fleet/`:
  - `README.md`;
  - `fleet_overview.png`, 12 per-car sheets in `sheets/`, and
    `outline_check.png`;
  - `fleet.json`, with every number B2–B4 need, and `verify.json`.
- `docs/design/.gdignore`, so Godot doesn't import the PNGs.
- `tools/fleet_design/`: the generator and checks.

**Verified:**
- **Blind test**, 3 rounds, each run by a fresh agent that had never seen the
  designs. It matched shuffled, unlabeled silhouettes in 6 views to the 12
  class names.
  - Correct: 72/72 every round.
  - "Sure": 33 → 36 → 39 of 72 as the designs were revised.
  - Final design: side 12/12 sure, both 3/4 views 8/12.
- **Palette:** 76 colours checked, with no magenta or cyan.
- **Sheets:** every sheet was viewed and self-critiqued. The critique is
  printed on each sheet.

**Not verified / open:**
- **These are proxies, not the game models.** Triangle counts (2.2k–3.0k per
  car) and draw calls get measured on the laptop in B2. The plan is one merged
  mesh per car with 3 surfaces plus one wheel mesh.
- **Weakest reads:** the hot hatch, muscle sedan and commuter are "sure" only
  side-on. That is fine for traffic. P2 and P5 can be pushed further if Roy
  wants.
- **Police blue needs Roy's OK**, or the light bar goes red/amber.
- **Physics wheels will move to each car's drawn wheelbase** (2.27–3.08 m,
  against today's 2.10 m), and that changes handling. Each car's CarSpec is
  tuned when it's built (B2, D).
- **Deferred:** interiors and undersides (Roy, 2026-10-05). Car names wait for
  branding.
- **Waiting on Roy:** B1 sign-off (shapes, parts, stickers, colours) before B2.
- **Review page** (private to Roy): <https://claude.ai/artifact/SvEKcFe1CaWa787K8Gha3m>. It has a 360° viewer of every design and build, plus the sheets.

Old `main.gd` (treadmill/distance-accumulator architecture) is abandoned, not edited further. `car_builder.gd` (pure mesh construction) is kept and reused. Everything below is built fresh in real world-space.

### Confirmed design decisions

**World:** Endless procedural road **plus procedural stop places** (garage/tuning, repair/refuel, and pure visual-variety stops) placed periodically along the route.

**Player physics:** Real `VehicleBody3D` driving through real world-space (not a hidden sandbox, not a treadmill) — see prior session decision on why (real suspension/wheel visuals, no faking).

**Traffic AI:** Reactive — cars brake/swerve near the player, occasional lane changes. Bigger scope than simple lane-follow; scoped as its own milestone.

**Camera:** Chase cam only for now. No cockpit/hood toggle yet.

**Progression / currency**, earned per run from: distance survived, clean driving (no-crash bonus), near-misses / close calls (needs a detection zone around traffic), and successful heat/police evasion. Spent at garage stops on a mods/unlock tree (specifics TBD once we're building it — start simple, expand).

**Damage system (new):** Cumulative — a health/durability meter drops per crash; enough damage ends the run or degrades performance (e.g. lower top speed). Repair stops reset it.

**Fuel system (new):** Real meter, drains over distance. Running out strands you / ends the run. Refuel stops top it off.

**Police / wanted-heat system:** Heat rises from sustained high speed, reckless near-misses, **and** from certain performance mods past a threshold (a loud/aggressive build draws more attention — realistic touch). Once heat is high enough, police spawn and chase; losing them pays out a currency bonus.

**Flavor/terminology** (for HUD text, event names, unlock names — from street-racing slang research):
Burnout, Drift, Donut, Full Send, Hole Shot, Redline, Fish-Tail, Power Slide, Wheelman, Sleeper, Ricer, Beater, Green Light, Slipstream, Dead Hook, Tune, Boost. ("Near-miss"/"close call" itself doesn't have strong established slang beyond "close call" — fine to use plainly.)

### Build order (milestones)

1. **Road-chunk foundation** — world-space road generation, chunks spawn ahead / recycle behind the car. Reuses old lane-width/section-variation math, reimplemented against real positions.
2. **Player physics** — real `VehicleBody3D` + wheels, grip/slip tuning, weight-transfer visuals for free from real suspension.
3. **Basic traffic** — lane-follow only first (get world-space traffic working at all before making it reactive).
4. **Reactive traffic upgrade** — braking/swerving/lane-changes near the player.
5. **Camera + HUD** — chase cam, gear/RPM tach, distance/speed readout (ports old HUD logic to new state).
6. **Damage system** — health meter, crash penalties, performance degradation.
7. **Fuel system** — meter, drain rate, stranding on empty.
8. **Stop places** — procedural placement logic + garage/repair/refuel/visual-variety stop types along the road.
9. **Currency & scoring** — distance + clean-driving + near-miss + heat-evasion formula, near-miss detection zones.
10. **Garage/mods menu** — spend currency, unlock tree, mods actually affect car stats.
11. **Heat/wanted + police pursuit** — heat accumulation (speed, near-misses, mod-level), police AI chase, evasion payout.

Each milestone: propose approach → sign-off → build → confirm before next. No batching ahead of where we've agreed.

### Near-miss / risk-scoring design (finalized 2026-09-12)

Compound formula, not a flat "in zone = point":

`event_value = base × proximity_factor × relative_speed_factor × timing_bonus × streak_multiplier × same_car_decay`

- **Proximity factor:** thin invisible shell just outside each traffic car's collision hull; value scales up the closer the player gets within that shell (capped at the hull edge).
- **Relative speed factor:** scales with player-vs-traffic-car relative speed at closest approach — a fast pass is worth more than a slow squeeze.
- **Timing bonus:** extra multiplier if the player made a lateral steering input shortly (~0.5s) before entering the zone — rewards an active swerve into a gap over already cruising through open space.
- **Streak multiplier ("heat of the moment"):** a rolling risk meter builds while near-misses keep happening in quick succession; while it's elevated, both currency payout *and* heat gain per event scale up together. Decays if the player drives clean for a few seconds. This is also a/the primary feed into the wanted/heat system alongside sustained high speed and mod-level.
- **Same-car decay (anti-cheese, no hard cap):** each traffic car remembers the last time it credited the player a near-miss. A repeat trigger against that *same* car within a short window is worth sharply less (e.g. ~35% the second time, ~10% the third, near-zero after) rather than being blocked — hugging one car's side becomes worthless on its own without needing an arbitrary rule.

### Mods/unlock tree design (finalized 2026-09-12)

Five linear tracks per vehicle: **Engine, Tires/Grip, Suspension, Fuel Tank, Armor/Durability.** Each track tiers up (1→2→3…), and at a fork tier each track splits into **two pathways, chosen independently per category** (mixing Path A on one category with Path B on another is intended, not an edge case). Once a path is picked for a category on a given vehicle, that category locks to that path (respec cost/option is an open question, not decided). Each vehicle has its own independent mod state — a second car later starts its own tree from scratch.

Example pathway identities per track (placeholders — exact numbers TBD when we build milestone 10):
- **Engine:** Top Speed path vs Acceleration/Torque path
- **Tires/Grip:** Race Grip (higher ceiling, less slide) vs Drift Grip (lower ceiling, more controllable slide)
- **Suspension:** Stiff/Track (sharper weight transfer, less roll) vs Soft (more forgiving, more lean)
- **Fuel Tank:** Range (bigger tank) vs Efficiency (slower drain at same size)
- **Armor/Durability:** Heavy (more health, adds weight) vs Light (less health, no weight penalty)

### Balance pass v1 (finalized 2026-09-12 — starting numbers, expect tuning once playable)

Currency name placeholder: **Cred** (change anytime, it's just a label).

#### Mods tree — costs & effects
Tier 1 is a shared baseline upgrade (no fork yet). Tier 2 is the fork — buying into Path A or Path B for that category. Tier 3 extends whichever path was chosen.

**Costs cut to ~1/3 of the original pass (2026-09-12) — goal is players cycling through multiple modded cars, not grinding one forever.**

| Track | Tier 1 (shared) — 170 Cred | Tier 2 fork — 400 Cred | Tier 3 (in chosen path) — 830 Cred |
|---|---|---|---|
| Engine | +8% top speed, +5% accel | **A) Top Speed:** +15% top speed  /  **B) Acceleration:** +20% accel | A) +20% more top speed  /  B) +30% more accel |
| Tires/Grip | +10% grip | **A) Race Grip:** +15% grip, -10% slide angle (harder to drift)  /  **B) Drift Grip:** +5% grip, +25% controllable slide range | A) +25% more grip  /  B) +40% more slide control |
| Suspension | -10% body roll | **A) Stiff/Track:** +20% cornering stability, -15% bump absorption  /  **B) Soft:** +20% bump absorption, +10% roll | A) further stability  /  B) further comfort/forgiveness |
| Fuel Tank | +15% capacity | **A) Range:** +30% more capacity  /  **B) Efficiency:** -20% drain rate | A) further capacity  /  B) further efficiency |
| Armor/Durability | +15% max health | **A) Heavy:** +40% max health, -5% accel  /  **B) Light:** -10% max health, +5% top speed | A) further health  /  B) further speed |

Full max-out of one vehicle's tree: **7,000 Cred** (was 21,000) — at ~400 Cred/run average, that's **~15-20 runs, roughly 45 min-1 hour** of play per car. Respec still 1.5× total spent per category (now cheaper in absolute terms too, same multiplier).

**Respec:** allowed, costs 1.5× the total Cred spent so far in that one category (not the whole tree) — e.g. respeccing a fully-maxed track (1,400 spent) costs 2,100 Cred.

#### Car tiers (added 2026-09-12)

Three vehicles, each with its own independent mod tree, each harder to fully mod than the last — so moving up tiers is a real escalation, not just a reskin. The 7,000-Cred numbers above are the **Starter** car's baseline; Tier B and Tier A scale both purchase price and mod cost:

| Tier | Purchase price | Mod cost per track (T1/T2/T3) | Full max-out | Runs / time |
|---|---|---|---|---|
| **Starter** ("Beater") | Free (starting car) | 170 / 400 / 830 | 7,000 Cred | ~15-20 runs, ~45min-1hr |
| **Tier B** ("Sleeper") | 5,000 Cred | 340 / 800 / 1,660 (2×) | 14,000 Cred | ~35 runs, ~1.5-2hrs |
| **Tier A** (top tier) | 15,000 Cred | 680 / 1,600 / 3,320 (4×) | 28,000 Cred | ~70 runs, ~3-4hrs |

Unlock gating: buying a higher-tier car is gated on **currency saved**, not on fully maxing the previous car first — a player can buy Tier B the moment they've saved 5,000 Cred even mid-mod on the Starter, so "move on to another car" can happen well before a car is finished. Each car's mod progress is independent and persists — you can own and swap between all three, modding each on its own track.

#### Near-miss / risk formula constants
- Detection shell: 1.5m outside each traffic car's collision hull
- Base value: 10 Cred/event
- Proximity factor: 1.0x (outer edge of shell) → 2.5x (grazing the hull)
- Relative speed factor: 1.0x below 20 km/h relative speed → 2.0x above 80 km/h (linear between)
- Timing bonus: 1.5x if a lateral steering input happened within 0.5s before entering the zone, else 1.0x
- Streak multiplier: starts 1.0x, +0.15x per event within a rolling 4-second window, caps at 3.0x, decays to 1.0x after 4s clean
- Same-car decay: 1st trigger = 100% value, 2nd within 8s = 35%, 3rd = 10%, 4th+ = ~2% (not blocked, just not worth it)

#### Heat & police
- Heat gain: +2 × current streak multiplier per near-miss event; +1/sec while above 85% of current top speed; +0.5/sec passively per Tier-3 performance mod owned (Engine/Tires) — a loud build draws attention just by existing
- Heat decay: -3/sec while under speed threshold with no recent near-miss/mod triggers
- Tiers: 0-29 no police · 30-59 (Tier 1: 1 cop, moderate) · 60-89 (Tier 2: 2 cops, aggressive) · 90-100 (Tier 3: 3 cops + roadblock/spike-strip event)
- Evasion: heat must stay below the current tier's floor for 6s with no police nearby → chase ends, pays 50 × tier-reached Cred bonus
- Note: tier count/roadblock complexity is capped by actual CPU/engine performance once we're building it — may need to trim at that point

#### Damage & fuel numbers
- Max health: 100 (before Armor mods). Traffic clip: -15. Head-on/high-speed crash: -40. Barrier/environment hit: -25. At 0 health, run ends.
- Performance degradation: top speed scales down linearly, 100%→80% as health goes 100→0
- Repair stop: full heal, ~3s stopped
- Fuel: 100 units base, drains 1 unit/20m traveled (~2km baseline range before Fuel mods)
- Refuel stop: full refill, ~3s stopped
- Empty tank: run ends (stranded)

### Carried over from HANDOFF.md (retired 2026-09-29)

`HANDOFF.md` (2026-09-12) was retired on Roy's decision (#40) - this file is the one source of truth for plan and order. Its old "Plan, in order" is superseded by the build order above. What was still useful:

**Target feel:** **simcade** physics (weighted grip/slide - not lane-snap arcade, not full sim) plus **beautiful low-poly** art (deliberate faceted geometry and strong lighting, not placeholder boxes), inspired by *Street-Spec: 日本* (osoiDev, https://store.steampowered.com/app/4230950/StreetSpec/).

**Physics targets from the old plan** (for milestone 2 tuning): ~200 km/h top speed, punchy but not instant 0-100, friction ~1.2-1.5 (grip with a reachable slide), speed-sensitive steering, visible tilt under accel/brake/cornering. Note `car_spec.gd` currently uses `coefficient_of_friction` 3.0 - see E1 in `ISSUES.md`.

**Original browser prototype** (reference for anything not yet ported): https://claude.ai/code/artifact/56a869ba-c7b6-46d4-9614-86f6760a2df7

**Ideas from the old plan, not yet scheduled:**
- Environment: skybox from the Vice Nights / Heat Check / Sunset Vice style bank (Heat Check's neon grid horizon fit best), bloom on emissives. (Camera FOV/shake tied to speed belongs with milestone 5, camera + HUD.)
- Car art: real panel definition (200-500 tris), emissive trim/underglow, baked AO, simple 2-3 slot livery system.

**Backlog (after core feel is right - don't build yet):** drift scoring/combo system, tuning menu (hook into `car_builder.gd`), livery/colour picker, ghost/replay of best run, checkpoint-sprint vs endless-dodge modes, engine-pitch/tyre-screech audio tied to physics state. (Police pursuit is milestone 11.)

**Main risk:** scope creep - simcade physics, beautiful low-poly and an open feature backlog is a lot for a solo build. Stick to one milestone at a time.

### Open items still remaining
- Whether damage affects handling (not just top speed) once physics exists to hook into — revisit once milestone 2 physics is real
- These are v1 numbers for a game that doesn't run yet — expect a real tuning pass once milestone 9-11 are playable, not treated as final

### Proposals, pending Roy (2026-09-29)

**Status:** proposal 1 is **approved and built** (`bbcb12f`, on Roy's direct instruction) - do not re-propose or revert it. Proposals 2 and 3 are **not approved**. Look-and-feel calls are Roy's; a side-by-side comparison is being prepared so he can choose from screenshots. Do not build 2 or 3 as decisions.


Full reasoning and sources in `RESEARCH-cheap-pretty.md`. These three are called
out here because each blocks or biases an upcoming milestone, and two of them get
expensive to reverse later.

1. **[Approved and done - `bbcb12f`.] The directional light contradicts the palette.** `game.gd` `_setup_world()`
   sets a warm white sun (`light_energy = 1.1`, colour `1.0, 0.95, 0.86`) — a
   daylight key sitting inside a purple night sky and violet fog. Committing to a
   dim cool key and letting *emissives* be the visible light source (markings,
   signage, street lights, tail lights, underglow) makes the existing sky/fog
   coherent and licenses a shorter draw distance. **Belongs to milestone 2
   (environment/atmosphere) in the retired HANDOFF plan - not ROADMAP's milestone 2, which is player physics — decide before art work starts.**

2. **Vertex-colour the road chunks at build time.** Endless procedural worlds
   normally forfeit baked lighting — there's no static scene for `LightmapGI` to
   bake. But `road_chunk_builder.gd` constructs its meshes in code, so light
   pools under lamps, darker shoulders and curb highlights can be written into
   vertex colours *during construction*, at zero runtime lighting cost. This is
   the technique that made Spyro's world look lit on a PS1, and it's available to
   us specifically *because* the road is procedural. **Affects milestone 1's
   builder; cheapest to add while that code is still being touched.**

3. **Build traffic as `MultiMeshInstance3D` + per-instance colour from day one.**
   Milestone 3 is next. Two or three car meshes with palette-swapped instance
   colours gives real visual variety at roughly one draw call; the same traffic as
   individual nodes is one draw call each. **This is the reversal that gets
   expensive** — retrofitting MultiMesh after reactive AI (milestone 4), near-miss
   detection zones (milestone 9) and police (milestone 11) are all reading and
   writing per-car state is significantly harder than starting there.

Also recorded in that doc, and deliberately contrary to standard mobile advice:
**do not drop `physics_ticks_per_second` to 30.** The vendored GEVP controller
integrates suspension and tire forces per physics step; halving the rate degrades
the exact simcade feel the milestone 2 rewrite existed to achieve. Find savings in
rendering instead.

## Auto-Tune (started 2026-10-05)

An Auto-Tune layer on top of the raw T-menu tuner. The raw tuner stays raw; both write the same per-car spec dict through `CarSpec.set_param()`.

**v1 scope (Roy, 2026-10-05):** gearing (`final_drive`, `gear_ratios`), aero (drag, front/rear downforce), brakes (`brake_force_multiplier`) and the four Road tire keys. Engine and suspension, and the mod-tier cap stub, are deferred. Steps 0-2 first; step 3 (analytic estimator) only if the real sim turns out too slow to search directly.

Steps: 0 setup -> 1a spec dict + registry + write path -> 1b rewire tuning_panel to it -> 2 hidden test track -> (3 estimator, conditional) -> 4 goals/locks/constraints -> 5 search + top-3 verification -> 6 panel UI -> 7 named slots.

### Step 1a - spec dict, registry, single write path
**Changed:** `scripts/tune_params.gd` (new): registry of the 14 v1 paths with absolute ranges. `CarSpec.set_param()` clamps, writes spec and live car, then re-derives what the vendored Vehicle only computes in `initialize()` (each Wheel's cached `current_*` tire numbers, `max_brake_force`). `CarSpec.apply()` now gives the car its own copy of every array/dict (the spec, Vehicle and all four wheels used to share the same tire dictionaries). `CarSpec.clone_spec()`. `PlayerCar.spec` holds the tune. `brake_force_multiplier: 1.0` added to `coupe_default()` (the vendor's own default, no behaviour change).
**Verified:** `tests/tune_params.gd`, headless, PASS: defaults inside range; no aliasing; `gear_ratios` stays `Array[float]`; all 14 paths spec == car == clamped request; clamping; a car tuned live matches a car built fresh from the same spec (gearing, wheel tire cache, brake force). Mutation check: with the re-derive step disabled the test fails on the tire cache, as it should.
**Open:** the raw tuning panel still writes Vehicle properties directly, so for now there are two write paths (1b removes that). Ranges are provisional until the step 2 sweep.

### Step 1b - raw tuning panel writes the spec
**Changed:** `scripts/tuning_panel.gd` now reads from and writes to `player.spec` through `CarSpec.set_param()`; it keeps no tune of its own. Its look, controls and knob keys are unchanged; slider ranges come from `TuneParams`. The engine knobs (peak torque, redline, the four torque-shape values) are registered as raw-only (`auto: false`), so they use the same write path but Auto-Tune cannot touch them. The torque shape now lives in the spec (`torque_shape`) and `CarSpec.apply()` / `set_param()` build the Vehicle's `torque_curve` from it; `coupe_default()` no longer carries a separate `torque_curve` (same curve, built from the same shape). `set_param()` also re-derives `max_clutch_torque` for engine edits.
**Verified:** `tests/tune_params.gd` PASS (adds: engine paths written to spec and car, torque curve follows the spec's shape, `max_clutch_torque` re-derived, fresh car built from the spec matches the live-tuned one, Auto-Tune has exactly the 14 v1 paths and none is an engine path). `tests/tuning_panel.gd` PASS (windowed; adds: after slider moves the player's spec holds the same values, `gear_ratios` still `Array[float]`). All headless tests and `chunk_drive` PASS.
**Open:** `tests/game_state.gd` (windowed) FAILS on a clean `origin/main` too, and gives different partial results between runs ("Esc should pause the tree" and later checks). Not caused by this branch; looks focus/timing dependent. Not fixed here.

### Step 2 - hidden test track (real sim, scripted drivers)
**Changed:** `scripts/tune_track.gd` (new, `TuneTrack`): flat "Road" ground plus three scripted runs per spec on a real `PlayerCar` built from the spec - `accel` (full throttle, auto-shift at 97% of the spec's redline -> `t_0_100`, `top_speed_kmh` over 35 s), `brake` (to 100 km/h, then full brake -> `brake_dist_100`), `corner` (fixed steering, rising speed -> `peak_lat_g`, `max_slip_deg`). `evaluate(specs)` runs specs one after another in the same lanes. `PlayerCar` gained two hooks, `driver` (a Callable that replaces the keyboard polling; keyboard code moved unchanged into `_read_keyboard()`) and `sim_only` (skips chassis mesh and engine audio, which don't affect physics). `TuneTrack.linear_damp_override` is a what-if switch, off by default.
**Verified:** `tests/tune_track.gd`, headless with `--fixed-fps 60` (added to `run_tests.bat`, full run only, ~2 min), PASS:
- Same spec five times in a row and again on a fresh track: bit-identical metrics. (Batching specs across lanes kilometres apart gave up to 2.3% different slide metrics - single-precision position noise - so specs are evaluated sequentially in fixed lanes. Batching saved no time anyway: a car-step costs the same however many cars run.)
- Fidelity: the track's default coupe tops out at 124.28 km/h; the real `Game.tscn` driven the same way (scratch script, not kept) reads 124.3 km/h.
- All 14 Auto-Tune v1 tunables at both ends of their ranges (gears kept in order): every run finishes, no flip, all finite.
- Sensitivity tables (printed by the test): every tunable moves at least one metric except as noted below.
**Sim speed (measured):** one spec = 3 runs, 2161 physics steps (36 s of driving). Wall time for that, same code, on this laptop (i5-1235U; on battery at 12%, CPU at 60-70% performance, power state varied during the session): **0.72 s to 2.0 s per spec**, i.e. 1,100-3,000 steps/s, 19-50x real time, ~210-310 us per car-step. Three specs (the step-5 verification): 2.2 s (fast) to 5.8 s (slow). The 14-field sweep (29 specs) took 39-58 s. Direct search budget: at 0.7 s per spec 100 evaluations ~1.2 min and a 1,400-evaluation hill climb ~16 min; at 2 s, ~3 min and ~47 min. These are headless `--fixed-fps` numbers (CPU-bound, an upper bound on in-game speed).
**Findings:**
- **The game's real top speed is ~124 km/h, not ~250.** The project never sets damping, so Godot's default linear damp (0.1 per second, ~4.5 kN at 124 km/h) holds the car in 4th gear at 6,373 rpm. With damping replaced by 0 the same car reaches 241.6 km/h at 36 s (and 0-100 drops from 7.2 s to 5.0 s). Under game damping top speed barely responds to tuning: final drive 120-131 km/h, drag 123-125, gear 5 never engages (no effect at all). So a "Top Speed" Auto-Tune goal is nearly meaningless until this is decided. Not changed - it is a feel decision for Roy. ISSUES E9 ("stock top speed is really ~253") assumed no damping.
- Gear ratios need an ordering constraint: with gears 1-3 at the registry minimum (0.5) under a 2.4 gear 2, the car cannot launch (never reaches 100 km/h). Range limits alone are not safe for gears; step 4 must enforce "each gear shorter than the one below" (the sweep used >=1.05x steps).
- Registry range edges are not all gentle: Road friction 4.0 gives 4.6 g peak and a 31 m 100-0 with damping removed. Provisional ranges, Roy's call.
- Brake: 100-0 is 36.6 m at the default (about 1.1 g average); `brake_force_multiplier` 0.7 -> 48 m, 1.5 -> 32 m (not proportional, tire-limited at the top).
**Open:** full `run_tests.bat` run: `tune_track` PASS, `tuning_panel` PASS, all headless PASS; `chunk_drive` failed once inside the full run ("no chunk recycled") but passed 2/2 standalone on this branch and 2/2 on clean `origin/main`, so intermittent, not tied to this branch; `game_state` fails as on clean `origin/main`. The hidden track is not yet hosted in its own physics world inside the game (it runs under the test's root); in-game verification speed is unmeasured (headless `--fixed-fps` numbers are an upper bound). Drivers are simple and fixed (open-loop steering for `corner`; no step-steer stability or drift-hold metric yet). Step 3 (analytic estimator) is not started - see the budget above.

### Linear damp removed (Roy approved 2026-10-05)
**Changed:** `PlayerCar.LINEAR_DAMP := 0.0`, applied in `_ready()` with `DAMP_MODE_REPLACE`. `TuneTrack.linear_damp_override` now applies after the car's `_ready()`; `tests/tune_track.gd` compares "as the game runs" (0) against Godot's old 0.1 instead of 0 against the game.
**Verified:** `tests/tune_track.gd`, headless `--fixed-fps 60`, default coupe, same code before/after:

| | before (damp 0.1) | after (damp 0) |
|---|---|---|
| top speed (35 s) | 124.3 km/h | 241.6 km/h |
| 0-100 | 7.22 s | 5.03 s |
| 100-0 | 36.6 m | 42.0 m |
| peak lateral g | 2.91 | 2.80 |

Determinism check still bit-identical. New assertion: top speed > 180 km/h, so the cap can't come back unnoticed.
**ISSUES E9 re-check:** the "~253" in E9 is the rev-cut ceiling (1.1 x redline); the car measures 241.6 km/h, between the 230 km/h redline speed and that ceiling, so a ~200 target is overshot by ~40 km/h. Ratios stay Roy's call (#62 / Auto-Tune). Braking is ~5 m longer and peak lateral g slightly lower because damping used to help slow the car.
**Open:** step 2's "game damping" sensitivity numbers above are the old capped car; the sweep now prints both. Registry ranges are still provisional.
