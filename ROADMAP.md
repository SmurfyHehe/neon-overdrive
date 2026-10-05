# Neon Overdrive — Full Rebuild Roadmap (2026-09-12)

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

### Step 4 - goals, locks, constraints
**Changed:** `scripts/auto_tune_rules.gd` (`AutoTuneRules`, pure functions, no physics). Goals: `accel` (0-100), `top_speed`, `braking` (100-0), `grip` (peak lateral g), each a weight (0 = off); `score()` is the weighted mean relative improvement over the baseline (0 = unchanged, +0.10 = 10% better), and a candidate missing a goal metric is rejected. Locks: a `path -> true` set; `free_paths()` is what the search may move. Constraints: every Auto-Tune value inside its registry range, and each gear at least `GEAR_STEP` = 1.05x shorter than the one below (the ordering step 2 showed is needed); `repair()` fixes a candidate by moving only unlocked values (raises the lower gear, or shortens the upper one if there is no room) and reports impossible when locks or ranges leave none. `guard_failures()`: a metric nobody asked about may get at most 25% worse in a verified result, so "top speed" cannot quietly wreck braking.
**Verified:** `tests/auto_tune_rules.gd`, headless, PASS (added to `run_tests.bat`): default coupe valid and untouched by `repair()`; every gear at 0.5 and at 4.5 repairable; locked gears never move, two locked gears out of order are reported impossible; scores for baseline / better / worse / weighted / bigger-is-better / missing metric; guard flags the unasked metric only. Mutation check: guard limit 0.25 -> 0.9 and the goal direction ignored each make the test fail.
**Open:** the 1.05 step and 25% guard are my choices, not Roy's; they are named constants. Repair prefers lengthening the lower gear, which keeps top speed. Nothing calls the rules yet (step 5).

### Step 5 - search and top-3 verification
**Changed:** `scripts/auto_tune_search.gd` (`AutoTuneSearch`): deterministic coordinate search with step halving on the real test track, no estimator. Each round probes every active parameter one step up and down (step starts at 12% of the range, halves when a round finds nothing, stops below 2%), takes the best improving move per parameter, tries them all together, and moves to the best of those; after round one only parameters that helped stay active. Candidates pass `AutoTuneRules.repair()` first, so no evaluation is wasted on an invalid tune, and are run only on the scripted runs their goals need (braking = one run, not three). The best 3 candidates are then run on all three runs and must run cleanly, satisfy every rule and lock, stay inside the guard on unasked metrics, and still beat the baseline on the full score; the best that passes is the result, otherwise "no better tune found" and the spec is unchanged. `TuneTrack.evaluate(specs, kinds)` takes a subset of runs; each run keeps its own lane, so numbers do not depend on which runs are along (default-coupe numbers unchanged).
**Verified:** `tests/auto_tune_search.gd`, headless `--fixed-fps 60`, PASS (added to `run_tests.bat`, full run only, ~2.5 min). Default coupe, budgets 20-30 evaluations (about 1.1 s each on the accel run):
- accel (30 evals): 0-100 5.03 -> 4.83 s, by gear 2 2.40 -> 1.92.
- braking (20 evals): 100-0 42.0 -> 38.6 m, by brake force 1.00 -> 1.10.
- top speed (20 evals): 241.6 -> 245.4 km/h; 100-0 42.0 -> 41.8 m, grip 2.80 -> 3.10 g (guard not triggered).
- Verified metrics are bit-identical to a fresh evaluation of the result; the same search twice gives the identical tune; engine values and torque shape untouched; result stays `Array[float]`; no goal / everything locked change nothing.
- Locks: the test locks exactly the parameters the free search moved, so a broken lock shows. Mutation check: with locks disabled the test fails (locked gear 2 changed).
**Open:** these are small budgets; improvements are modest (a few percent) and may grow with a bigger budget, not measured yet. Search speed in-game (inside the running Game, not headless) is unmeasured until step 6. Single-goal runs only in the test; mixed weights are covered by the rules test, not by a search.

### Step 6 - Auto-Tune panel
**Changed:** `scripts/auto_tune_panel.gd` (`AutoTunePanel`): **Y** opens it (new `autotune_panel` input action, `GameState.State.AUTOTUNE`, game paused like the T panel; Y or Esc closes). Goals as 0-3 weight sliders, a lock checkbox per Auto-Tune parameter (shows its current value), a budget (30 / 60 / 120 runs), Run / Cancel / Apply / Undo apply, a status line with progress, and a before/after table (top speed, 0-100, 100-0, peak lateral g), the changes and "verified N of 3". Apply writes through `CarSpec.set_param()`; Undo restores the spec from before. The raw T panel is unchanged in look and controls; the one change is that its sliders now re-read the spec when it opens (otherwise they would show the pre-Auto-Tune values). The controls hint shows "Y auto-tune".
**The search runs in a separate headless Godot process** (`scripts/auto_tune_job.gd` starts it, `scripts/auto_tune_worker.gd` is the process; request/progress/result as JSON files in `user://autotune/`, Cancel kills it). Why: I first hosted the track in the game in a SubViewport world and sped it up with `Engine.time_scale`; that breaks the car (the cars flipped in every run), because `time_scale` makes each physics step longer instead of running more of them, and Godot has no way to step physics by hand. A worker process with `--fixed-fps 60` runs the same sim as `tests/tune_track.gd` at about 1.2 s per candidate and gives identical numbers. Cost: it needs a Godot executable (`$GODOT`, else the running exe if it is Godot's own, else the Documents path `run_tests.bat` uses), so Auto-Tune does not work in an exported game, only in editor/dev runs.
**Verified:** `tests/auto_tune_job.gd` (headless `--fixed-fps 60`, in `run_tests.bat`) PASS: a spec round-trips (non-default engine tune, `Array[float]` kept); the worker's result is identical to the same search run in-process (values, evals, base and verified metrics); progress is reported; cancel kills the worker; no-goal request comes back as a clean "nothing to do". `tests/auto_tune_panel.gd` (windowed, in `run_tests.bat`) PASS: Y pauses and opens only this panel; Run with no goal does nothing; a braking search with everything locked but brake force: locked values unchanged, the baseline the worker measured is the headless one (241.6 km/h, 5.03 s, 42.0 m, within 0.5%), Apply reaches spec and live car, Undo restores both, the raw panel shows a value written to the spec while it was closed, closing the panel mid-search cancels and kills the worker. Mutation check: disabling the Apply write makes the panel test fail. Full `run_tests.bat` PASS (with the `game_state` fix from PR #87 copied in; on this stack the old flaky `game_state` is still present).
**Speed (measured):** 11 runs in 14.8 s wall through the panel with the game window open (about 1.3 s per run), so Quick (30) is about 40 s and Normal (60) about 80 s.
**Open:** the panel is plain default controls, like the raw one, and not styled. The window title/position of the worker console is not hidden on Windows (a console window may flash). Progress only advances per candidate, so the first seconds show "Starting". No Auto-Tune in exported builds (above). `tests/tuning_panel.gd` still uses the same-frame key press that made `game_state` flaky (it passes, but is the same pattern).

### Step 7 - named tune slots
**Changed:** `scripts/tune_slots.gd` (`TuneSlots`): a slot is a name (trimmed, at most 24 characters) and the value of every tunable path (Auto-Tune and raw-only engine ones), one JSON file `user://tune_slots.json`. `save` (same name replaces), `delete` (removes the entry, never the file), `apply` (loads it through `CarSpec.set_param()`, so values are clamped and the live car follows; paths a slot lacks keep their value). A file that will not parse reads as empty and is overwritten by the next save. The Auto-Tune panel (not the raw T panel) gets a slot section: name box + Save, a list, Load, Delete. Load can be reverted with Undo apply. `AutoTunePanel._write()` now writes every tunable path, not only Auto-Tune's (found by the panel test: Undo after loading a slot left an engine value behind).
**Verified:** `tests/tune_slots.gd` headless PASS (added to `run_tests.bat`): save / list / sort / trim / cut / empty name refused / replace; a slot holds all tunable paths; survives a new `TuneSlots` on the same file; `apply` puts the tune on a live car (spec and car agree, `Array[float]` kept), clamps 99.0, leaves paths the slot lacks and ignores unknown ones; corrupt file reads as empty and a save repairs it; delete keeps the file. Mutation check: `apply` writing the spec without `set_param()` fails the test. `tests/auto_tune_panel.gd` PASS, now also: Save with no name asks for one, Save lists the slot, picking fills the name and enables Load, Load restores spec and live car (final drive and peak torque), Undo reverts it, same name replaces, Delete removes. Full `run_tests.bat` run below.
**Open:** the slot file holds the tune only (no car identity, no tier), so a slot saved today loads onto whichever car is active; tiers and per-car slots come with the vehicle registry. Slots live only in the panel opened with Y; the raw T panel has none by design. No confirmation on Delete. Names are not case-folded ("street" and "Street" are two slots).
