# Engine mechanics spec (proposal, 2026-10-07)

Status: PROPOSAL. Roy signs off before any code. Roy approved the feature list on 2026-10-07: turn on before driving, stall on extreme impact, die if not serviced (garage mini-games), cooling tied to mods, realistic RPM logic, engine braking on downshift, grinding gears on wrong-speed shifts, knock/detonation damage.

Numbers below come from general automotive knowledge (typical street and tuned cars), tuned for controller play. They are starting values, all tunable constants in one file (`scripts/engine_health.gd`, new). Nothing here was measured on a real car or run in Godot yet.

## What exists today (checked in the repo)
- `CarSpec` has `max_rpm`, `idle_rpm` (1000), turbo (`turbo_boost_max`), and the vendored Vehicle has `engine_running`, `starter_input`, stall (450 rpm for 0.25 s), idle controller, rev limiter with hysteresis, `motor_brake` engine braking (10 Nm off throttle).
- Stall and starter only work in MANUAL mode (`realistic_clutch`). AUTO and SEMI always start running.
- Nothing models damage, heat, knock, or service.

## Steelman / premortem
- Steelman: a living engine makes the garage, mods and story matter (the mechanic's shop). Every item reuses existing sim hooks.
- Premortem: it fails by being punishing on a controller. Mitigations: nothing kills the engine in one mistake; every failure has a warning stage first; an "Assist" setting (default on) softens stalls, grinding and neglect, per the layered safety rule.

## 1. Rev limits and idle (per class)
| Class | Cars | Idle | Redline / limiter | Notes |
|---|---|---|---|---|
| Commuter / hatch | N1, N2, P2 | 800-900 | 6200-7000 | soft limiter, fuel cut |
| Kei | P4 | 1000-1100 | 8000-9000 | small high-revving engine, thin torque |
| Pickup / SUV / crossover | N3, P6, C2 | 650-800 | 5000-5800 | low redline, torquey |
| Sport coupe (P1) | P1 | 900-1000 | 7000 (stock), up to 8000 tuned | current: idle 1000, max 7000 |
| Tuner | P3 | 950-1100 | 7500 stock, up to 9000 tuned | tuned street cars rarely exceed 9000 |
| Muscle V8 | P5 | 600-750 | 5500-6500 | lumpy idle, big torque low |
| Police interceptor | C3 | 750-850 | 6500 | |

Playability rules: idle never below 600 (audio and stall margin); redline at least 5000 so gears last long enough on a controller; stock-to-tuned redline gain capped at +1000 so gearing stays sane. Limiter is a fuel cut with 150 rpm hysteresis (already built). Sitting on the limiter is free for 3 s, then adds heat (section 7).

## 2. Turn on before driving
- New state `engine_state`: OFF, CRANKING, RUNNING, STALLED.
- Key X (existing starter key) cranks: 0.6-1.2 s, random +-0.2 s, longer when cold or neglected. Hold to crank, release when it fires.
- Spawn: car starts OFF with the key in (one keypress to start). Assist on: pressing throttle while OFF auto-cranks. Assist off: you must press X.
- AUTO and SEMI also stall and restart now (this is the real change: stall is no longer MANUAL-only). Assist on makes AUTO unstallable except by impact.

## 3. Extreme impact stall
Use the change in body speed over one physics step (delta-v, m/s), not force.
| Delta-v | Meaning | Result |
|---|---|---|
| < 4 (about 15 km/h) | scrape, curb | nothing |
| 4-9 | hard hit | engine dips; 20 percent chance stall (Assist on: 0) |
| 9-14 (about 50 km/h) | **extreme** | stall guaranteed; restart in 1.5 s |
| > 14 | wreck | stall + engine health -15 percent (feeds section 8 wear) |
Real cars: a fuel-cut inertia switch trips around 20-30 km/h-equivalent crash decel, so stalling at 9+ m/s is generous. Defaults for threshold: 9 m/s extreme, tunable.

## 4. Engine braking on downshift
GEVP already adds constant `motor_brake` (10 Nm) off throttle. Add rpm-scaled braking plus a rev-match on downshift.
- Off throttle: brake torque = `motor_brake * (0.4 + 0.6 * rpm/max_rpm)`, so higher rpm drags harder, like real pumping loss.
- Resulting decel at the wheels roughly: 1st 0.20 g, 2nd 0.14 g, 3rd 0.10 g, 4th 0.07 g, 5th 0.05 g (tops out when rpm sits near redline). Roy can scale all with one "Engine braking" multiplier in the Tuner (default 1.0).
- Downshift jump: rpm after shift = wheel speed x new ratio. If that is under redline, the car decelerates smoothly (this is the engine braking you feel). Heel-toe/rev-match (SEMI/MANUAL, optional Assist) blips throttle so the jump is smooth and a flame/pop can fire.
- Over-rev guard (section 5) covers downshifts that would exceed redline.

## 5. Grinding gears and over-rev
Predicted rpm after shift = wheel rpm x new gear x final drive. Mismatch ratio = predicted / max_rpm.
| Predicted rpm | Mode | Outcome |
|---|---|---|
| under 1.0 x redline | all | clean shift |
| 1.0-1.15 | AUTO / SEMI | shift refused (like most auto boxes); SEMI shows a "too fast" blip |
| 1.0-1.15 | MANUAL | allowed, over-rev; rpm bounces off limiter; heat + wear |
| over 1.15 | MANUAL | **grind**: shift fails, grind sound + shake, `gearbox_wear` + 3 percent; 3rd grind in 10 s locks to neutral for 0.5 s |
| Clutch not in (MANUAL) | MANUAL | grind regardless of speed |
Grinding can **not** stall the engine by itself (real synchros wear, the engine keeps turning). It stalls only if the player dumps the clutch below stall rpm afterward. Damage cost: 3 percent gearbox wear per grind, fixed at the garage (gearbox service is a cheap mini-game). Over-rev (>1.0 redline held) adds 1 percent engine wear per second above 1.05.

## 6. Cooling
- `coolant_temp` (C), idle ~90, safe up to 105, boiling 120. Rises with rpm and load (about +0.5 C/s at full throttle near redline), falls with airflow (speed) and radiator size.
- Cooling is a mod stat: `cooling_capacity` from radiator, intercooler (turbo), oil cooler. Stock = 1.0; mods 1.2-1.6. Turbo adds heat load ~+30 percent; muscle V8 +15 percent.
- Over 105 C: power drops 10 percent per 5 C and a gauge warning shows. Over 120 C: knock risk x3 and "engine health" drains 2 percent/s until cooled. Pull over and idle with the bonnet visual to cool.
- Assist on: warning shows 15 C earlier and temp falls faster when parked.

## 7. Knock / detonation
Knock value 0..1. Rises when: boost over 85 percent of `turbo_boost_max` AND coolant over 100 C; or rpm above 95 percent redline with a hot engine; or "wrong fuel" later (low-octane fuel purchase, fuel system is a future item). Falls at 0.2/s when conditions clear.
| Knock | Feedback | Effect |
|---|---|---|
| 0.0-0.3 | none | none |
| 0.3-0.6 | faint metallic "ping" in audio, small gauge flicker | power -5 percent |
| 0.6-1.0 | loud ping, screen edge shake, dash knock lamp | power -15 percent, 2 percent engine health per second |
| 1.0 (sustained 2 s) | engine knocks, smoke, **limp mode**: redline cut to 4500 | engine health -10 percent chunk |
Player options to fix: lift off, shift up, cool down. Tuner shows a "Knock risk" line under boost/redline sliders (live consequence line from the settings-safety decision).

## 8. Death by neglect and maintenance (garage mini-games)
`engine_health` 0-100, plus `oil_life`, `gearbox_wear`, `coolant_condition` (0-100 each), all stored in the car's save data.
| Item | Interval (driving time) | Neglect effect |
|---|---|---|
| Oil change | every 45 min of driving (about 90 min on free-roam sessions) | oil_life < 25: +heat, wear x2; 0: engine seizes over 3 minutes (death) |
| Coolant | 90 min | worse cooling; boil quicker |
| Gearbox fluid | 120 min | grind chance up |
| Spark plugs / air filter | 60 min | misfire pops, -5 to -10 percent power (cosmetic tie to crackle voice) |
Death: engine_health 0 = **dead**, car won't start, tow to the garage (costs currency, no permanent car loss; story bible has no loan or penalty mechanics). Warning ladder: dash lamp at 40, engine rough audio at 25, limp mode at 10, dead at 0. Assist on slows wear 50 percent.
Mini-games, kept short (20-45 s) and keyboard only: oil change (drain, fill to the marked line), coolant bleed (hold to the air bubbles), plug swap (timing taps), gearbox flush (sequence keys). Fits the shop story. Mini-game score only changes the quality of the service (+/-), never blocks a basic service; a skipped mini-game can be paid for at 2x.

## Feedback loops (summary)
- Heat -> knock -> health loss -> limp -> garage -> service restores.
- Over-rev/grind -> wear -> garage; Assist can soften each stage.
- Mods raise power and heat together, so cooling mods become the rational second purchase (a mod-tree hook).

## Build order (each its own PR, Roy signs off per step)
1. `engine_state` + start flow + stall in all modes (Assist setting).
2. Impact stall via delta-v.
3. Engine braking curve + rev-match.
4. Grind/over-rev rules.
5. Heat/knock.
6. Health, wear, save data, warning ladder.
7. Garage mini-games (needs the garage UI to exist first).

## Open questions for Roy
- Is "dead engine" tow-only (recommended) or a permanent loss?
- Should start-up be the default OFF at spawn (recommended, with auto-crank on throttle under Assist)?
- Assist default ON (recommended).
