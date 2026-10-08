# Traffic overhaul: plan for sign-off (2026-10-08)

Roy's ask: "an overhaul and more sophisticated traffic; the traffic should use
blinkers. The NPCs obey the rules of the road, we don't." Highway first;
junctions once the elevation work has landed.

This is a proposal. Nothing is built until Roy signs off, and then one step at
a time, each as its own PR with a headless test.

Sources: two research rounds and Roy's answers to 21 questions, all on
2026-10-08. The full research, with URLs, is in the project files:
`traffic-research.md` (round 1: code audit, rules, game AI, plan) and
`traffic-decisions.md` (round 2: one card per decision).

## 1. What exists today

The base is good, so this is additions, not a rewrite.

- **Following:** `traffic_car.gd` has a constant-time-gap follower (S0 4 m,
  T 1.5 s) with a braking guard, and a bend speed cap on main.
- **Lane changes:** a simplified MOBIL model with safety checks, yielding to a
  fast player, keeping right after 6 s, and a 3 s S-curve.
- **Wrecks:** wrecks turn the hazards on and get recycled out of view.
- **Lamps:** brake lamps, tail flares and hazards (84 flashes a minute), with
  lamp state written only when it changes. These are in the NPC car stack,
  which is not on main yet; see step T0.

Missing:
- per-driver parameters (everything is a constant)
- left/right blinkers and a signal-before-move phase
- politeness and a speed limit
- perception, horn and flash, swerves, and an offence log

**Bug:** NPCs can pass on the right. Passing on the left is only a +1 score
bonus, so the right-hand lane can still win.

## 2. Roy's decisions (2026-10-08)

| Topic | Decision |
|---|---|
| Side of the road | Right-hand traffic |
| Speed limits | Vary by road type. The actual numbers wait for the speed-feel calibration (see section 5) |
| Driver mix | 25% cautious, 60% average, 15% assertive (pushy but legal) |
| Signal lead | By personality: 3.0 / 2.5 / 2.0 s, never under 2 s, plus up to 4 s more while waiting for a gap |
| Strictness | Visible rules are always obeyed: signal, keep lanes, never pass on the right. Mild speeding (+10%) and short gaps are allowed |
| Reactions to the player | Headlight flash now; horns logged as events until NPC audio exists; safe evasive swerves only; rare NPC-to-NPC crashes, capped when wrecks are already nearby. No road-rage chases |
| Near misses | Always earn rep. Police heat only from offences a cop witnesses (police stage) |
| Offence log | Tracked from day one, hidden behind a debug key |
| Blinkers | Small amber flare, about 1.5-2x the tail flare, fading out past 150 m |
| Density | By road type, plus a night curve: busiest around midnight, thin at 2-4 a.m. |
| Trucks | About 10% of highway traffic: right lanes, about 85 km/h, slow lane changes. Needs a truck model (Fable) |
| Player flash/horn key | Yes, one key. Cautious and average NPCs move over when it is safe. It must fit the one-hand play rule (key proposed in T8) |
| Junctions (later) | Traffic lights first; a blue-green signal green is allowed as a palette exception (like police blue); stop signs on side streets later |

## 3. Overlaps with open PRs (check before building)

- **#228 Living world 2** already thins traffic by hour band. The night
  density curve above should reuse it, not duplicate it.
- **#220 living world proposal** (game clock) and **#225 night clock**: the
  density curve reads that clock.
- **#217 lane adds, drops, splits and exits proposal**: the lane-graph work for
  junctions (J1) must build on whatever Roy accepts there.
- **#234 near-miss whoosh**: the near-miss events in T7 should feed the same
  detection, not a second one.
- **NPC car stack (#153 to #155) and night lights (#178)**: the lamp code that
  blinkers extend. They must be on main first (T0).

## 4. Steps (one PR each, in order)

Every step keeps today's behaviour for an "average" driver, so the existing
`traffic_behaviour`, `traffic_stability` and `traffic_perf` tests stay green.

| Step | What | Headless test (pass rule) |
|---|---|---|
| T0 | Prerequisite: NPC lamps (#155/#178) and curves on one main | Existing traffic tests pass on that main |
| T1 Driver profiles | `DriverProfile` data: time gap, standstill gap, acceleration, braking, speed factor, politeness, signal lead, reaction delay. Mix 25/60/15. Constants become per-car values; "average" equals today's numbers | Follow scene: steady gap cautious > average > assertive; old tests unchanged |
| T2 Rule fixes | Never pass on the right (unless both lanes crawl under 60 km/h); speed = road limit x driver factor x lane bias; politeness in the lane-change gain | 60 s highway: 0 NPC undertakes, right lanes busier than left, 0 contacts |
| T3 Signal phase (logic) | Signal first, re-check the gap at the moment of moving, wait up to 4 s for a gap, then cancel. Never more than 6 s on; a cooldown stops blinker spam | Every lane change is preceded by at least 0.9 x the lead time of the right-side signal; 0 signals over 6 s; at most 1 cancel per car per 20 s |
| T4 Blinker rendering | Left/right/hazard/off per car in the lamp shader; side picked from the lamp's position; a random blink offset so cars don't flash in sync; small amber flare. First check that all three NPC meshes have front and side amber lamps | Shader values asserted headless, plus one real-renderer screenshot for Roy |
| T5 Cooperation | A polite follower that sees a signal into its lane eases off (+0.5 s gap) | Dense scene: more successful merges than T3, no extra contacts |
| T6 More hazards | Hazards at the tail of a sudden queue; hazards override blinkers | Scripted hard stop from 100 km/h: hazards on for 3-5 s, then off |
| T7 Perception + offence log | NPCs only "see" the player in forward, mirror and side zones (a few dot products, no new raycasts). One monitor at 10 Hz logs speeding, undertaking, cut-ins, tailgating, near misses, contact and hit-and-run, each with its NPC witnesses, on an event bus. Hidden counter behind a debug key | A scripted cut-in logs CUT_IN with the victim as witness; the same cut-in outside every zone logs it unwitnessed |
| T8 Reactions | Headlight flash, logged horn events (rate-limited), safe swerves, reaction delay 0.8-1.3 s by driver, rare capped NPC-to-NPC crashes. The player's flash/horn key makes polite NPCs move over | Cut-in: exactly 1 horn event per cooldown; wreck 40 m ahead with a free lane: swerve and 0 contacts; no free lane: full brake |
| T9 Performance gate | `traffic_perf` before and after | Added cost under 5% per car per tick |
| T10 Density + trucks | Density by road type and the night curve (reusing #228's clock work); trucks at ~10% once a truck model exists | Spawn mix and density match the targets over 5 simulated minutes |
| J1-J5 (later) | After the elevation work: lane graph, junction chunk, stop/yield rules, traffic lights, turn routing with turn blinkers 30 m or 3 s before the line | Each its own headless scene |

To avoid rework now, T1-T3 give each car a lane handle and use a blinker API of
LEFT / RIGHT / HAZARD / OFF, so junction turns can plug in later.

## 5. Waiting on other work

- **Speed limit numbers** wait for the speed-feel calibration (blind playtest,
  dashcam side-by-side, headless flow measurement) and for the world-rescale
  decision. T2 ships with the limit as one number per road type that is easy
  to change.
- **Truck model:** a Fable task in the car design pipeline. T10 waits for it.
- **Horn sound:** waits for NPC audio. The events exist from T8.
- **Police heat** from witnessed offences: Stage F. T7 only provides the
  events.

## 6. Cost

- **CPU:** today a full-sim car costs 0.19-0.36 ms per 120 Hz tick against a
  budget of about 4 ms. Everything new runs at the existing 4 Hz decision tick,
  or 10 Hz for the one offence monitor. Blinking runs on the GPU. Expected
  added cost is well under 5%, and T9 enforces it.
- **Laptop:** the integrated graphics only gain a few emissive lamps and small
  flares.

## 7. Premortem (how this fails, and the guard)

- **Jittery lane changes** from a signal-move-abort loop: a lane chosen at
  signal start stays the target; abort only on safety; cooldown after abort.
- **Blinker spam:** a 6 s cap and a cancel count in the T3 test.
- **Too polite and dull** (empty road, no near misses): the 15% assertive
  share, yielding capped by speed difference, and a playtest of the mix.
- **Too hostile** (swerves into the player, horn spam): swerves use the
  existing lane-change safety check, including the player-behind rule, and
  horns are rate-limited.
- **Gap closes while signalling:** re-check at the moment of moving (T3).
- **Witnesses that can't see:** zones only; occlusion is skipped on purpose
  for cost.
- **Performance creep** from writing shader values every tick: the
  change-only pattern, with T9 as the gate.
- **Branch drift** (lamps and curves on different branches): T0 first.
- **Blinkers invisible from the front or side** if a mesh lacks amber lamps
  there: checked before T4.

## 8. Sign-off asked

1. The step order T0-T10 as above, with junctions after the elevation work.
2. Start with T0 (getting the NPC car and lamp PRs merged) and then T1.
