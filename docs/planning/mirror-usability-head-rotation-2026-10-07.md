# Cockpit mirrors you can actually use: head glance + mirror fixes (proposal, 2026-10-07)

Research only, nothing built. Roy (2026-10-07 16:20): "I can't even see the right mirror in P1 first person... we might need looking right and left mechanics, like a head that rotates with input somehow; needs research." Follows `mirrors-research-2026-10-06.md` (live mirrors, now merged) and the approved sightline spec (FOV slider 55-78, default 62).

## 1. Why the right mirror is invisible (checked against origin/main 9c28d59)

Angles from the cockpit eye (`chase_camera.gd:64`, `COCKPIT_EYE = (-0.32, 1.10, 0.30)`) to each mirror's glass centre (`cockpit_mirrors.gd:41`, `p1_coupe_builder.gd:50-53` + `BODY_LIFT`). Positive = right / up. Screen half-width assumes a 16:9 window.

| Mirror | Yaw | Pitch | Half-width of glass |
|---|---|---|---|
| Rearview | 36.7° right | +12.6° | 9.8° |
| Left door | 39.7° left | -6.3° | 4.6° |
| **Right door** | **58.0° right** | -4.4° | 3.2° |

| Cockpit FOV (vertical) | 55 | **62 (default)** | 68 (62 at top speed) | 78 (max) |
|---|---|---|---|---|
| Screen edge, horizontal | 42.8° | **46.9°** | 50.2° | 55.2° |

- **The right mirror's nearest edge is at 54.8°, so it is fully off screen at every FOV the slider allows**, except a 0.4° sliver at 78. This is geometry, not a bug in the mirror code; the comment at `chase_camera.gd:61-62` saying it is "still inside the view at the default FOV" is wrong for FOV 62.
- The left mirror's outer edge is at 44.3°, just inside the 46.9° edge at FOV 62, and off screen at FOV 55. Whether the A-pillar covers it is not checked yet (needs a render; see the test in section 5).
- It is also true in a real car: a left-hand-drive driver turns their head about 55-60° to read the passenger mirror. So the fix is the head, not moving the mirror into the windscreen.
- **Wasted work today:** the right mirror is rendered every other frame (`cockpit_mirrors.gd:180-186`) although nobody can ever see it.

## 2. How other games do it (from memory and forum threads, not verified hands-on)

| Game | Look left/right | Mirrors | Extras |
|---|---|---|---|
| iRacing | Hold-to-look keys, snap to a set angle; head-tracking hardware | Cockpit mirrors + optional HUD "virtual mirror" | Spotter calls "car left/right" |
| Assetto Corsa Competizione | Look left/right buttons (angle in settings) | Cockpit mirrors + virtual mirror | Radar/spotter, "look to apex" auto-turn into corners |
| Gran Turismo 7 / Forza | Look left/right/back on buttons; Forza free-look on the right stick | Cockpit mirrors, often small; HUD rear-view option | — |
| Euro Truck Sim 2 | Free mouse look + keys that jump straight to each mirror | Mirrors are the main driving tool; mirror cameras adjustable | — |

What carries over to a keyboard-only game: **hold-to-glance keys with a snappy ease** (all of them), **glance straight at the mirror** (ETS2), and **a cue on the mirror when a car is alongside** (spotter/radar, done in-world). Not carried over: mouse free-look and head-tracking hardware (keyboard only), and a virtual HUD mirror for the cockpit (breaks the real-car feel; the chase view already has the HUD strip).

Sources: [Forza: look left/right threads](https://forums.forza.net/t/look-left-right-with-steering-wheel/9048), [Forza: look to apex](https://forums.forza.net/t/look-to-apex-camera-function/568424), [ACC discussions](https://steamcommunity.com/app/805550/discussions/0/2263564102374909316), [ETS2 mirror/look discussions](https://steamcommunity.com/app/227300/discussions/0/3194736442558252181).

## 3. Recommendation: tap-to-glance on V, aimed at the mirror

**Input (Roy, 2026-10-07 18:38 and 18:44): one key, V, tap to toggle, side from steering.** Steering, throttle and brakes keep working the whole time: only the camera moves, never the car.

- **V + steering left (A)** turns the head to the left door mirror; **V + steering right (D)** to the right one. The side is read from the steering input at the moment of the tap.
- **V with no steering looks straight ahead.** Tapping V + the same side again also comes back.
- **Double tap V** (two taps within 0.3 s) always resets the head to straight ahead, as a failsafe.
- **Locked once chosen:** steering after the tap does not swing the head across (a correction mid-glance would whip the view).
- No auto-return: the head stays on the mirror until you tap V again.
- **V is free today** (camera cycle is C, view F, look back B, shifting Q/E), so no key moves. Glance works in the cockpit view only.
- **Premortem:** looking left on a straight needs a small A nudge, which also steers a little. Fine in practice: the left mirror is already on screen, and a lane change left means steering left anyway.

Arrow-key players: V is still reachable with the left hand.

**Angle.** Not a fixed 45° or 90°: each glance **centres its door mirror**, computed from the car's mirror data, so every car's interior stays individual and a redesign moves the target with it. P1: left 40°, right 58°. Cap 75°. The head also leans a few cm toward the middle on a right glance, the way a driver's body moves, which keeps the A-pillar from cutting the glass.

**Timing.** Ease in ~0.12 s, out ~0.10 s (a fast head turn, about how long a real glance takes). Head movement (g-sway) keeps running on top. Hands stay on the wheel.

**Shoulder check: later, needs its own research (Roy).** Turning past the mirror (~85-90°) to see the blind spot through the side window is out of the first build.

## 4. Feedback and cost

- **No highlight on the glass, no HUD icon** (real-car HUD, gritty look). The glanced-at mirror instead **renders every frame and at double resolution** while you look at it, so it reads sharply; the other two pause. Cost while glancing is about the same as today.
- **Blind-spot cue on the door mirrors.** Extend today's rearview proximity cue (`hud.gd:242-264`, amber warm-up on the glass) to each door mirror: a small amber dot in the glass corner when a same-direction car is alongside or just behind in that lane. Real cars have exactly this; it is in palette (amber) and makes the mirrors useful even without glancing. Near-free (one more loop over traffic).
- **Skip off-screen mirrors.** Do not render a mirror whose glass is outside the cockpit camera's view this frame. On P1 at FOV 62 that removes the right mirror's render whenever you are not glancing: a perf gain before anything new is added.
- Live mirrors stay as built (rear 320x96, sides 160x112, alternating frames). The 16-traffic-car re-measure from the 10-06 notes is still owed and goes into the first PR.

## 5. Prototype plan (three small PRs, each with headless Godot checks)

1. **Mirror visibility test + skip off-screen mirrors.** A headless test projects each mirror's glass corners through the cockpit camera at FOV 55/62/78 (straight ahead and glancing) and reports how much is on screen and whether the A-pillar covers it; fixes the wrong comment. Off-screen mirrors stop rendering. Measures fps at 16 traffic cars on Roy's laptop.
2. **Glance key.** `look_glance` on V (tap to toggle, side from steering, double tap resets), per-car glance targets from mirror data, ease + lean, focused-mirror boost, Controls page updated. Test: glancing right puts the right glass ≥ 90% on screen at FOV 62.
3. **Blind-spot dots on the door mirrors.**

Separate from the sightline/hands branch (`fix/cockpit-hands-sightline` only touches the hands) so neither blocks the other. The cockpit redesign next week will move mirrors; glance targets come from data, so they follow.

## 6. Roy's decisions (2026-10-07 18:38)

1. Input: **V, tap to toggle, side from steering**; V alone looks ahead; double tap resets. Replaces the two-key hold idea.
2. Blind-spot dot on the door mirrors: **yes**.
3. Shoulder check: **later**, after its own research.

Roy said GO (18:44). Built in the same PR as this doc (section 7).
