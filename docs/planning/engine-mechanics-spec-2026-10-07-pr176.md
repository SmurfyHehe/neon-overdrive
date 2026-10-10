# Engine mechanics specification: system, warmup, death alternatives, presets (2026-10-07)

Status: **Roy's feedback applied.** Rejected: "tow to garage or lose car" as harshly punitive. Proposed: three alternatives that let players avoid the failure state. Engine presets tied to story progression, not arbitrary.

## 1. Engine system overview (existing, from Phase B)

Current implementation (origin/main bd7957c):
- **Heat engine:** `scripts/powertrain_health.gd` tracks engine temperature via brake abuse (dragging brakes = heat, coast/lift-off = cool). Temperature feeds warning lights (ENG light if over 70°C, steady at 85°C).
- **Phases A–C merged:** gearbox upshift rev-match, turbo boost, clutch behavior (manual/auto), tyre model, 120 Hz physics.
- **Redline/peak torque:** currently tunable in the Tuner (Advanced view) and Auto-Tune. Stage E (garage) will lock these as upgrades; they stay as Tuner knobs until then.
- **Exhaust:** cosmetic (loudness, pops, flame), no mechanical effect on performance.
- **No wear or fuel yet:** both deferred to Stage C+ (damage/scoring).

## 2. Engine warmup mechanic (startup-only)

**Definition (Roy, 2026-10-07):** Engine warmup triggers only when:
1. Car first spawns in a session (race start, free roam start), or
2. Car hasn't been driven for a long time (cold start between sessions, if the game tracks this).

**Not:** idle warmup. The engine does not require a warm-up delay at traffic lights or after coasting to a stop mid-session.

### Warmup delay spec

- **Duration:** 3–5 seconds of startup delay before the car can produce full power.
- **Effect during warmup:** reduced power (limiter at ~60% torque), slight lag on throttle response, warning light (NEW: warmup indicator, distinct from the ENG overtemp light).
- **Player feedback:** HUD shows a warmup timer (0–3s, e.g. "Engine warming: 2s"), or just a "Warmup" label that clears when done. Cockpit radio fades in (currently silent on spawn) to add atmosphere.
- **What happens:** player can try to drive, but power is capped. Not a hard brake; they will move slowly but steadily. On manual transmission, they can still upshift but redline is lowered (~3000 rpm instead of 6000). On auto, upshifts are delayed.
- **Cold start detection:** if the game tracks session time, a car left idle for >30 minutes gets a warmup on next spawn. If not tracked, only the initial spawn gets warmup (simpler, sufficient).

### Implementation notes

- Warmup is **per car per session,** not global. Each car that spawns gets its own timer.
- Warmup does not affect the tow-truck or cop cars (out of scope for now; TBD if they spawn often enough to need it).
- The tuner can **not disable or shorten warmup** (it is not a tunable parameter). It is a fixed mechanic, like gear ratios' realism.

### Example flow

1. Player starts a free-roam session in the coupe. Spawn moment: warmup timer starts (3 s).
2. Player mashes throttle immediately. Car revs slowly, power capped at 60%, HUD shows "Engine warming: 3s".
3. At t=1s, player tries to upshift (manual). Allowed, but redline is low (~3000), limiting gear selection.
4. At t=3s, warmup clears. HUD disappears. Power returns to 100%. Player feels the surge.
5. Later, player crashes and respawns at the same location, 30 seconds later. No new warmup (still in session).

## 3. Engine death alternatives (Roy rejected "tow/lose car")

Roy's requirement: **player must feel they can avoid the failure state.** A hard "you lose" is a reset, not engagement. All three alternatives below are resets (the car is back and playable), but they let the player see the failure coming and recover.

### Option A: Overheat → Limp Mode → Cooldown

**Mechanic:** Engine temperature rises with sustained high throttle or brake abuse (existing heat model). At 100°C, the ENG warning light comes on (solid, flashing). The engine enters **limp mode:** power drops to 70% and stays there until the engine cools.

**Player recovery:** Back off throttle, coast, or brake lightly. Temperature falls. Once below 90°C, the car exits limp mode and power returns to 100%. Full cycle ~20–30 seconds.

**Failure consequence:** None (not a death). The limp mode is a handicap; the player is still racing. Good for challenging the player without ending the session.

**Why this works:** 
- Visible (warning light + power loss).
- Avoidable (stop pushing the engine; don't abuse brakes).
- Recoverable (slow down, cool off, rejoin the race).
- Fits the gritty night-driving tone (worn engine needs babying).

**Downside:** Not dramatic. A seasoned player ignores it; it reads more as a "take care of your car" hint than a threat.

### Option B: Seizure → Brief Shutdown → Restart

**Mechanic:** Engine temperature climbs to 105°C (beyond limp mode). The engine **seizes** for 5 seconds: the car stops entirely, revs lock out, player can still brake/steer but cannot accelerate. After 5 seconds, the engine cranks back to life and the car is fully drivable again.

**Player recovery:** Wait 5 seconds (short enough to feel like a hiccup, not a punishment). Engine restarts. No lasting damage; the car is back to 100% power immediately.

**Failure consequence:** Lost 5 seconds, possibly lost the race position. No permanent damage.

**Why this works:**
- More dramatic than limp mode (complete loss of power for a short time).
- Avoidable (watch engine temp, ease off before 105°).
- Recoverable (quick restart, no repair needed, no towing).
- Fits the tone (night-driving wear, mechanical surprise).

**Downside:** Can feel cheap in a close race. Good for difficulty tuning; make seizure threshold a difficulty setting (Easy: never seize; Medium: 105°C; Hard: 100°C).

### Option C: Engine Fault → Accumulating Power Loss → Pit Stop Reset

**Mechanic:** Engine temperature climbs to 102°C. At this point, the engine develops a **fault:** power begins to drop 1% per second. At 120 seconds of faulted operation, power is at 50% and the car is barely drivable. At 150 seconds, power is at 25% (near-stall).

**Player recovery:** Drive to a pit stop / safe area. Pit stop action: hold a button for 3 seconds while parked. The fault clears, power returns to 100%, and the engine cools. Player can rejoin the race.

**Failure consequence:** Lost time at the pit stop (10–15 seconds for the recovery action), likely lost race position. No permanent damage to the car.

**Why this works:**
- Long onset (120+ seconds of warning, not a sudden surprise).
- Gradual effect (player feels power slipping, decision to pit is deliberate).
- Avoidable (maintain temp, ease off sooner).
- Recoverable (pit stop exists; no towing or garage).
- Fits the tone (tired engine needs a breather).

**Downside:** Pit stops must exist in all race/freeplay modes (or this only applies in specific tracks). More complex to code.

### Recommendation: Option A + B (Limp Mode + Seizure)

Combine limp mode (70–100°C: power reduced but drivable, ~20 s recovery) with seizure (105°C+: 5 s shutdown, immediate recovery). This gives:
- **Early warning (limp mode)** with a soft handicap.
- **Hard consequence (seizure)** for ignoring the warning.
- Both are recoverable, not punitive losses.
- Easy to tune difficulty: adjust seizure threshold, or skip seizure on Easy mode.

**Skip Option C** unless pit stops are already a game feature. It is fun if stops are core gameplay (endurance races), but overkill for street racing.

## 4. Car presets derived from story progression

**Principle:** Car presets (Stock, Street, Grip, Drift) are not arbitrary tuning templates. They reflect the player's crew development and story progression. Each preset tells a story beat.

### Story-driven preset strategy

| Preset | Story context | When available | Tuning intent | Example tunes |
|---|---|---|---|---|
| **Stock** | Factory defaults, no upgrades | Always | Baseline. Player hasn't modified the car yet, or is resetting to learn the baseline. | Coupe's factory tune (balanced, safe) |
| **Street** | Crew's "safe" setup for cruising between races; Juno's input (fast launches, forgiving). | Act 1, Scene 2+ (after Juno joins) | Forgiving, street-legal feel. Softer springs, open diff, high assists. | Low-end torque boost, softer suspension, open diff, TC/stability on |
| **Grip** | Pilar's influence (mountain-road specialist); the crew learns high-corner-speed tuning. | Act 2, Scene 1+ (after Pilar joins, takes Cutter Canyon) | Fast lap setup. Sport compound, stiff suspension, medium diff lock, medium downforce. | Sport tyres, stiffer springs, locked diff, reduced assists, rear toe-in |
| **Drift** | Moose's wildcard setup or late-game experimentation; the crew learns slide tuning. | Act 2, Scene 3+ (late, after crew stabilizes) or Stage D (more cars) | Slide-friendly. Locked rear diff, front toe-out, stiff rear ARB, reduced TC/stability. | Locked diff, stiff suspension, rear brake bias, TC off, high steering lock |

### Implementation

1. **Preset availability gates:** presets unlock in the Tuner as crew members join or districts are won.
   - Stock: always.
   - Street: unlocks when Juno joins (Act 1, Scene 2).
   - Grip: unlocks when Pilar joins and player wins Cutter Canyon (Act 2, Scene 1).
   - Drift: unlocks late Act 2 or Act 3 (optional, or tied to Moose's side quest).

2. **Per-car presets:** Each of the 6 player cars has its own Stock preset (from CarSpec). Street, Grip, Drift are offsets applied to Stock, so they work on all cars. Coupe is built first; other cars' presets are balanced in Stage D.

3. **Tuner story line:** When a player selects a preset in the Tuner, a brief text break explains it (Act 1: "Juno says, go easy on the suspension—street driving needs forgiveness"; Act 2: "Pilar's setup for the mountain; stiffer, locked diff"). This ties tuning to the story.

4. **Auto-Tune goals align:** Auto-Tune's "Mechanic" view offers goals (Launch, Top Speed, Braking, Cornering) that match the preset story. Street favors Launch (Juno's specialty). Grip favors Cornering (Pilar's specialty). This makes tuning feel like crew advice, not abstract optimization.

### Example: Coupe presets in Act 2

| Preset | Gearing | Suspension | Tyres | Diff | Assists | Narrative cue |
|---|---|---|---|---|---|---|
| Stock | 3.73 | med springs | road compound | open | TC high, stability on | "The way it shipped." |
| Street (Juno) | 4.10 | soft springs, soft dampers | street compound | open | TC high, stability on | "Juno tweaks it for quick launches; forgiving on the street." |
| Grip (Pilar) | 3.55 | stiff springs, stiff dampers | sport tyres | 50% locked | TC medium, stability off | "Pilar's mountain setup: locked diff for corner grip, stiffer ride." |
| Drift (Moose, late) | 3.80 | stiff rear, soft front | street compound | rear locked, front open | TC off, stability off | "Moose's wildcard: locked rear, open front, ready to slide." |

## 5. Warm-up visual and audio cues

- **HUD:** Small "Warmup: 3s" timer that counts down and disappears.
- **Cockpit:** Radio fades in from mute (real-time audio effect, ~1 second ramp). Fits the "engine coming to life" vibe.
- **Engine sound:** Pitch ramps from idle (slightly rough) to normal over 3 seconds.
- **Exhaust:** No visual pops/flame during warmup (engine power is limited, so no extra fuel dump).

## 6. Steelman

Startup warmup is a small mechanic that adds realism without harshness (only on spawn). Limp mode + seizure give the player meaningful recovery windows: they are not punished for mistakes, just set back a few seconds. Presets tied to crew story make tuning feel like learning from mentors, not tweaking sliders. Together, they make the car feel alive and the crew feel invested.

## 7. Premortem (why this fails)

1. **Warmup is boring.** Players skip tutorial text and just mash throttle. Mitigation: make it short (3s), add audio/visual feedback (radio fade-in, HUD timer), and tie it to the radio broadcast (Dale says something witty about the cold engine).
2. **Limp mode is invisible.** Player doesn't notice the 30% power loss. Mitigation: pair with a visual cue (HUD temperature bar, warning light, cockpit shake on overheat).
3. **Seizure feels unfair.** Player doesn't see it coming. Mitigation: limp mode is the warning; seizure only happens if the player pushes past limp mode (105°C). Clear threshold on the temperature gauge.
4. **Presets feel disconnected from story.** Player doesn't know why Pilar's setup works for the mountain. Mitigation: text breaks in the Tuner when preset is selected; brief, not intrusive.
5. **Difficulty tuning hard.** Easy players hit seizure and feel punished. Mitigation: difficulty setting controls seizure threshold (Easy: never seizure; Medium: 105°C; Hard: 100°C and faster temperature climb).

## Notes for Roy

- Warmup timing (3 vs. 5 seconds): which feels right? Test on your laptop; we can tune by ear.
- Limp mode threshold: 100°C? Or lower (95°C) so the player has more recovery time before seizure?
- Seizure threshold: 105°C, or would 110°C feel more generous?
- Pit stop mechanics: Is Option C (pit stop reset) in scope, or should we skip it?
