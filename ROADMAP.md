# Neon Overdrive — Full Rebuild Roadmap (2026-09-12)

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

**Open conflicts, waiting on Roy (flagged 2026-10-04):**
1. **Direction.** PR #83 (open) records a car-culture plan Roy approved on
   2026-09-29. It parks fuel, stop places and damage-ends-the-run (stage C
   here) and makes rival and traffic cars scripted. This plan builds them.
   Stage A applies to both, so it goes ahead; **stage B needs a decision.**
2. **Cars.** PR #79 (open) moves cars to imported models through a vehicle
   registry. Stage D assumed 12 cars built here. Needs a decision before D.
3. **CPU cost of full-sim traffic.** RESEARCH-cheap-pretty.md warns that the
   i5-1235U has 2 performance cores and that traffic should not get GEVP
   bodies "without a measured reason". Roy's rule above is that reason, so
   stage B measures traffic density against the frame budget before
   committing a number.
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
  narrower shoulder and sidewalk, and buildings closer. `LANE_W` (2.3 m) is
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

Old `main.gd` (treadmill/distance-accumulator architecture) is abandoned, not edited further. `car_builder.gd` (pure mesh construction) is kept and reused. Everything below is built fresh in real world-space.

## Confirmed design decisions

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

## Build order (milestones)

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

## Near-miss / risk-scoring design (finalized 2026-09-12)

Compound formula, not a flat "in zone = point":

`event_value = base × proximity_factor × relative_speed_factor × timing_bonus × streak_multiplier × same_car_decay`

- **Proximity factor:** thin invisible shell just outside each traffic car's collision hull; value scales up the closer the player gets within that shell (capped at the hull edge).
- **Relative speed factor:** scales with player-vs-traffic-car relative speed at closest approach — a fast pass is worth more than a slow squeeze.
- **Timing bonus:** extra multiplier if the player made a lateral steering input shortly (~0.5s) before entering the zone — rewards an active swerve into a gap over already cruising through open space.
- **Streak multiplier ("heat of the moment"):** a rolling risk meter builds while near-misses keep happening in quick succession; while it's elevated, both currency payout *and* heat gain per event scale up together. Decays if the player drives clean for a few seconds. This is also a/the primary feed into the wanted/heat system alongside sustained high speed and mod-level.
- **Same-car decay (anti-cheese, no hard cap):** each traffic car remembers the last time it credited the player a near-miss. A repeat trigger against that *same* car within a short window is worth sharply less (e.g. ~35% the second time, ~10% the third, near-zero after) rather than being blocked — hugging one car's side becomes worthless on its own without needing an arbitrary rule.

## Mods/unlock tree design (finalized 2026-09-12)

Five linear tracks per vehicle: **Engine, Tires/Grip, Suspension, Fuel Tank, Armor/Durability.** Each track tiers up (1→2→3…), and at a fork tier each track splits into **two pathways, chosen independently per category** (mixing Path A on one category with Path B on another is intended, not an edge case). Once a path is picked for a category on a given vehicle, that category locks to that path (respec cost/option is an open question, not decided). Each vehicle has its own independent mod state — a second car later starts its own tree from scratch.

Example pathway identities per track (placeholders — exact numbers TBD when we build milestone 10):
- **Engine:** Top Speed path vs Acceleration/Torque path
- **Tires/Grip:** Race Grip (higher ceiling, less slide) vs Drift Grip (lower ceiling, more controllable slide)
- **Suspension:** Stiff/Track (sharper weight transfer, less roll) vs Soft (more forgiving, more lean)
- **Fuel Tank:** Range (bigger tank) vs Efficiency (slower drain at same size)
- **Armor/Durability:** Heavy (more health, adds weight) vs Light (less health, no weight penalty)

## Balance pass v1 (finalized 2026-09-12 — starting numbers, expect tuning once playable)

Currency name placeholder: **Cred** (change anytime, it's just a label).

### Mods tree — costs & effects
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

### Car tiers (added 2026-09-12)

Three vehicles, each with its own independent mod tree, each harder to fully mod than the last — so moving up tiers is a real escalation, not just a reskin. The 7,000-Cred numbers above are the **Starter** car's baseline; Tier B and Tier A scale both purchase price and mod cost:

| Tier | Purchase price | Mod cost per track (T1/T2/T3) | Full max-out | Runs / time |
|---|---|---|---|---|
| **Starter** ("Beater") | Free (starting car) | 170 / 400 / 830 | 7,000 Cred | ~15-20 runs, ~45min-1hr |
| **Tier B** ("Sleeper") | 5,000 Cred | 340 / 800 / 1,660 (2×) | 14,000 Cred | ~35 runs, ~1.5-2hrs |
| **Tier A** (top tier) | 15,000 Cred | 680 / 1,600 / 3,320 (4×) | 28,000 Cred | ~70 runs, ~3-4hrs |

Unlock gating: buying a higher-tier car is gated on **currency saved**, not on fully maxing the previous car first — a player can buy Tier B the moment they've saved 5,000 Cred even mid-mod on the Starter, so "move on to another car" can happen well before a car is finished. Each car's mod progress is independent and persists — you can own and swap between all three, modding each on its own track.

### Near-miss / risk formula constants
- Detection shell: 1.5m outside each traffic car's collision hull
- Base value: 10 Cred/event
- Proximity factor: 1.0x (outer edge of shell) → 2.5x (grazing the hull)
- Relative speed factor: 1.0x below 20 km/h relative speed → 2.0x above 80 km/h (linear between)
- Timing bonus: 1.5x if a lateral steering input happened within 0.5s before entering the zone, else 1.0x
- Streak multiplier: starts 1.0x, +0.15x per event within a rolling 4-second window, caps at 3.0x, decays to 1.0x after 4s clean
- Same-car decay: 1st trigger = 100% value, 2nd within 8s = 35%, 3rd = 10%, 4th+ = ~2% (not blocked, just not worth it)

### Heat & police
- Heat gain: +2 × current streak multiplier per near-miss event; +1/sec while above 85% of current top speed; +0.5/sec passively per Tier-3 performance mod owned (Engine/Tires) — a loud build draws attention just by existing
- Heat decay: -3/sec while under speed threshold with no recent near-miss/mod triggers
- Tiers: 0-29 no police · 30-59 (Tier 1: 1 cop, moderate) · 60-89 (Tier 2: 2 cops, aggressive) · 90-100 (Tier 3: 3 cops + roadblock/spike-strip event)
- Evasion: heat must stay below the current tier's floor for 6s with no police nearby → chase ends, pays 50 × tier-reached Cred bonus
- Note: tier count/roadblock complexity is capped by actual CPU/engine performance once we're building it — may need to trim at that point

### Damage & fuel numbers
- Max health: 100 (before Armor mods). Traffic clip: -15. Head-on/high-speed crash: -40. Barrier/environment hit: -25. At 0 health, run ends.
- Performance degradation: top speed scales down linearly, 100%→80% as health goes 100→0
- Repair stop: full heal, ~3s stopped
- Fuel: 100 units base, drains 1 unit/20m traveled (~2km baseline range before Fuel mods)
- Refuel stop: full refill, ~3s stopped
- Empty tank: run ends (stranded)

## Carried over from HANDOFF.md (retired 2026-09-29)

`HANDOFF.md` (2026-09-12) was retired on Roy's decision (#40) - this file is the one source of truth for plan and order. Its old "Plan, in order" is superseded by the build order above. What was still useful:

**Target feel:** **simcade** physics (weighted grip/slide - not lane-snap arcade, not full sim) plus **beautiful low-poly** art (deliberate faceted geometry and strong lighting, not placeholder boxes), inspired by *Street-Spec: 日本* (osoiDev, https://store.steampowered.com/app/4230950/StreetSpec/).

**Physics targets from the old plan** (for milestone 2 tuning): ~200 km/h top speed, punchy but not instant 0-100, friction ~1.2-1.5 (grip with a reachable slide), speed-sensitive steering, visible tilt under accel/brake/cornering. Note `car_spec.gd` currently uses `coefficient_of_friction` 3.0 - see E1 in `ISSUES.md`.

**Original browser prototype** (reference for anything not yet ported): https://claude.ai/code/artifact/56a869ba-c7b6-46d4-9614-86f6760a2df7

**Ideas from the old plan, not yet scheduled:**
- Environment: skybox from the Vice Nights / Heat Check / Sunset Vice style bank (Heat Check's neon grid horizon fit best), bloom on emissives. (Camera FOV/shake tied to speed belongs with milestone 5, camera + HUD.)
- Car art: real panel definition (200-500 tris), emissive trim/underglow, baked AO, simple 2-3 slot livery system.

**Backlog (after core feel is right - don't build yet):** drift scoring/combo system, tuning menu (hook into `car_builder.gd`), livery/colour picker, ghost/replay of best run, checkpoint-sprint vs endless-dodge modes, engine-pitch/tyre-screech audio tied to physics state. (Police pursuit is milestone 11.)

**Main risk:** scope creep - simcade physics, beautiful low-poly and an open feature backlog is a lot for a solo build. Stick to one milestone at a time.

## Open items still remaining
- Whether damage affects handling (not just top speed) once physics exists to hook into — revisit once milestone 2 physics is real
- These are v1 numbers for a game that doesn't run yet — expect a real tuning pass once milestone 9-11 are playable, not treated as final

## Proposals, pending Roy (2026-09-29)

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
