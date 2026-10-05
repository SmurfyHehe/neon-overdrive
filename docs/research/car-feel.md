# Making the car feel like a car (research, 2026-10-05)

Roy's playtest of main: "the car doesn't feel like a car." He wants a real
engine, transmission, exhaust and radio, and cars that can fail. Five agents
researched it (engine and drivetrain, handling, failures, audio and radio) and
one read our code.

**Caveats:** the web research was thin (2 to 5 searches per topic, mostly
snippets), the physics is standard textbook knowledge rather than quoted, and
the code audit was a static read. Nothing was run or measured, so every ranking
below is a hypothesis to feel-test, not a fact.

## A. Why it feels wrong today (code audit, ranked)

Paths are under `scripts/`; GEVP is `scripts/vendor/gevp/`. Line numbers for the
vendored files may be a few lines off.

| # | Cause | Where | Fix | Effort |
|---|---|---|---|---|
| 1 | Default gearbox is a clutchless manual shifted by hand: no auto-upshift, no clutch key, reverse via Q-to-neutral-then-Q | `car_spec.gd:130`, `player.gd:159` | Default `automatic_transmission` true, keep manual as an option; brake-while-stopped selects reverse | S / M |
| 2 | Shifts feel wrong: 0.3 s throttle-off shift, no rev-match on upshifts, revs hang then re-engage with a jolt | `gevp_vehicle.gd` `shift()`, `complete_shift()` | Shift time about 0.15 s, more engine drag, rev-match upshifts too | S / M |
| 3 | Launch: clutch stays open until 3000 rpm, then hooks up abruptly; no slip, no stall | `process_motor`, `process_throttle`, `clutch_out_rpm` | Engage progressively around 1500 rpm | M |
| 4 | Hard limiter cuts all throttle (stutter, fixed ceiling, ISSUES E9) | `process_motor` | Fuel cut with hysteresis about 100 rpm | S |
| 5 | Gearing and torque curve mis-shaped: 1st tops out at 61 km/h (ISSUES E7, E8) | `car_spec.gd:118`, `:184` | Even steps about 1.3, about 80 km/h in 1st | S |
| 6 | Steering is digital: full lock at any speed (38 degrees), no keyboard ramp | `player.gd:195-211`, `car_spec.gd:133` | Scale input by speed, smooth the key press | S |
| 7 | Tyre grip: cof 3.0, linear in load, no load sensitivity (about 2.9 g lateral) | `car_spec.gd:158`, `gevp_wheel.gd` | cof about 1.5 first; load sensitivity later | S / M |
| 8 | Short wheelbase (2.1 m) with a wide track: twitchy yaw | `player.gd:37` | `axle_z` about 1.3, match the body | S |
| 9 | Low roll and yaw inertia from a 1.6 x 0.6 x 3.4 box | `gevp_vehicle.gd` | `inertia_multiplier` 1.6 to 2, small `angular_damp` | S |
| 10 | Lift-off coasts floaty: `motor_brake` is declared but never read | `process_motor` | Apply `motor_brake` | S |

Suggested first pass (the audit's pick): items 1, 2, 3 and 6 together, then 4
and 10.

Already good: raycast wheels with real pitch, squat and roll; slip-angle and
slip-ratio saturation; ABS, traction and stability control; interpolated 60 Hz
physics; real aero forces; speed-scaled steering rate and counter-steer assist;
a tune panel and TuneTrack. Checked and fine: camera judder, audio coupling (it
inherits the rev hang), linear damp 0, suspension in a plausible band.

## B. Engine and transmission (how real ones work)

Core idea: the engine is a spinning inertia coupled to the wheels through a
clutch torque; arcade cars derive rpm straight from wheel speed. Check what GEVP
already has (an automatic gearbox and manual clutch controls) before building.

- **Essential:** engine inertia plus torque curve; engine braking on lift-off;
  throttle lag; idle control and stall; stuttering fuel-cut limiter; gear ratios
  with final drive; clutch with bite point; auto shift logic with hysteresis;
  shift time with torque cut and shift thump; open differential; drag and
  rolling resistance. About a day for these, per the research.
- **Nice:** limited-slip differential, torque converter creep, turbo lag and
  blow-off, rev-match on downshift, drivetrain lash, cold-engine idle.
- **Later:** VTEC-style cam switch (per car), full thermodynamic models.

## C. Handling

- **Essential:** slip-angle curve (peak about 4 to 8 degrees, gentle fall-off),
  slip-ratio curve, friction circle; forces at the contact patch with per-wheel
  load; spring and damper sized for the mass (about 1.2 to 2 Hz, damping ratio
  0.6 to 0.8); anti-roll bar; speed-sensitive steering lock plus keyboard ramp
  (do not cut lock too hard at medium speed); slight understeer baseline; drag;
  brakes about 1 g with 60 to 70 percent front bias.
- **Nice:** ABS, traction and stability control (GEVP has them), steer-to-velocity
  assist, handbrake, per-surface grip, load sensitivity.
- **Later:** tyre temperature and wear, force feedback (pointless on keyboard).

## D. Failures (v1 rules)

Players like failures that are telegraphed, caused by their own choices and
recoverable; they dislike random, invisible or run-ending ones (BeamNG's
invisible oil starvation is the main complaint). Already decided: no
damage-ends-the-run and no fuel until after the garage stage; exhaust is
cosmetic.

- **Essential, warn then derate, never kill:** engine temperature, brake fade,
  tyre temperature and wear, clutch wear, rev abuse. Each gets a gauge or light,
  an audible cue, a power or grip derate, and a garage repair later.
- **Nice:** stalling, oil pressure in long hard corners, turbo health, knock,
  limp mode (power capped to about 50 percent) as the universal safe consequence.
- **Later:** fuel faults, exhaust faults, blowouts.

## E. Audio, exhaust, radio, cabin

- **Essential:** engine pitch from rpm with load-dependent timbre (we have it);
  tyre squeal from slip; wind and road noise by speed; separate cockpit and chase
  buses (low-pass the cockpit, about 0.2 s crossfade on camera switch); the radio.
- **Radio:** one looping player per station, all running muted so switching lands
  mid-song; tuning static as noise plus a band-pass sweep; DJ banter and ducking
  later. Free music: Pixabay (CC0), OpenGameArt, itch.io CC0, Incompetech and
  Purple Planet (credit required). Keep a credits screen and a licence log. No
  licensed commercial tracks.
- **Nice:** separate intake, exhaust and engine-bay layers; turbo whistle and
  blow-off; gear whine; suspension thuds; camera shake; per-layout character
  (flat-4 uneven, cross-plane V8 burble). Test Doppler on drive-bys (Godot issue
  38143).
- **Later:** granular or physical engine modelling; adaptive music.

## F. Proposed order (each step ends with a Roy feel-test)

1. **Feel pass 1 (small, mostly tuning):** automatic default, shorter shifts and
   rev-match, earlier clutch engagement, speed-sensitive steering plus keyboard
   ramp, soft limiter, apply `motor_brake`, even gearing.
2. **Feel pass 2:** tyre cof and load sensitivity, wheelbase and inertia,
   anti-roll balance, understeer baseline.
3. **Audio feel:** tyre squeal, wind and road noise, cockpit and chase buses.
4. **Radio:** stations, static, free music with credits.
5. **Heat and wear gauges** with derates and limp mode (after the garage plan).
6. **Clutch and engine model proper** (inertia coupling, stall, LSD) if the
   passes above are not enough.

## Sources (unverified snippets unless noted)

- GEVP: https://github.com/DAShoe1/Godot-Easy-Vehicle-Physics
- Clutch modelling: https://www.gamedev.net/forums/topic/694941-clutch-modelling-help/
- Godot reference vehicles: https://github.com/Dechode/Godot-Advanced-Vehicle ,
  https://jreo.itch.io/rcp4 , https://katfish-whiskers.itch.io/kv-vehicle-godot
- Pacejka: http://www.racer.nl/reference/pacejka.htm
- Keyboard driving: https://yousuckatracing.wordpress.com/2024/10/28/more-on-keyboard-driving/
- BeamNG oil starvation: https://www.beamng.com/threads/oil-starvation-goofiness.91642/
- Forza damage: https://www.gamesradar.com/games/forza-horizon/forza-horizon-6-turn-off-car-damage/
- Engine sound: https://www.audiokinetic.com/en/community/blog/engine-sound-modeling-from-sampling-to-granular-synthesis-in-wwise/
- AudioStreamGenerator: https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html
- Free music: https://gtstu.com/free-royalty-free-music-indie-games/
