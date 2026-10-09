# Mirror usability and head rotation: automatic first-person mechanic (2026-10-07)

Status: **Roy's feedback applied.** Rejected: Z/C keybinds for look-back. Proposed: automatic first-person mirror activation + look-over-shoulder via steering input + blind-spot HUD indicator. No keys needed.

Based on `mirrors-research-2026-10-06.md` (Option B: one shared rear camera, sliced into three mirrors). This document adds the input mechanic and HUD layer.

## 1. Automatic first-person mirror activation (no keybind)

**Mechanic:** Mirrors are **not an opt-in keybind.** Instead, they activate automatically based on camera mode:
- **Cockpit view (F key):** Mirrors automatically activate when the player enters cockpit view. The shared rear camera spins up, the three mirror slices become visible, HUD elements (blind-spot lights) appear.
- **Chase view (default):** Mirrors are **inactive** (zero cost). The rear camera does not render. If the player switches back to cockpit, mirrors re-engage.

**Why this works:**
- **Zero new keybinds.** Players don't learn a new control; mirrors "just work" in cockpit.
- **Performance simple.** Mirrors cost render time only in cockpit, where the player is paying attention to visibility anyway.
- **Natural UX.** The player enters a view mode (cockpit = interior = needs mirrors) and mirrors appear. Intuitive.

**Implementation:**
- `scripts/chase_camera.gd`: Add a check `if CAMERA_MODE == COCKPIT then activate mirrors else deactivate mirrors`. The MirrorRig (SubViewport + rear Camera3D) is a child of the cockpit frame, so it exists whether active or not; toggling is just `SubViewport.render_target_update_mode = UPDATE_DISABLED` (chase) vs. `UPDATE_ONCE` at ~30 Hz (cockpit).

## 2. Look-over-shoulder via steering input

**Mechanic:** The player's head rotates to look back when steering hard. No keybind; automatic.

**Steering-to-head mapping:**
- **Steering angle threshold:** When steering input exceeds ~60° lock (left or right), the head automatically rotates to look toward the **opposite rear quarter** (look over the shoulder you're leaning away from).
  - Steering hard left (>60°) → head yaws right, looking over the right shoulder into the mirror and beyond.
  - Steering hard right (>60°) → head yaws left, looking over the left shoulder.
- **Head rotation (yaw):** 0° (straight ahead) to ~45° (hard over-shoulder). Smooth interpolation over ~0.2 seconds, decays back to 0° when steering returns to center.
- **Head pitch:** Slight upward tilt (~5°) when shoulder-looking, to see the side mirror better and the road ahead less.

**Example:**
1. Player drives straight. Head is at 0° (looking ahead through the windscreen).
2. Player starts a hard left turn (steering >60° left), braking into a corner. Head automatically yaws right 45° over the right shoulder, pitch up 5°.
3. Player now sees:
   - The right mirror in clear view (showing the road and any cars alongside-behind).
   - The B-pillar and right mirror housing at the edge of the screen.
   - Enough of the road ahead (still in peripheral view) to not crash.
4. Player returns to neutral steering. Head smoothly interpolates back to 0°.

**Why this works:**
- **Intuitive:** In real driving, a driver looks over their shoulder when turning hard. The game mirrors the action.
- **No keybind needed.** Pure steering input drives head rotation; it is organic.
- **Context-appropriate.** Look-back happens when the driver needs it (hard turn, high-speed situation).
- **Recoverable.** If head rotation breaks visibility (e.g., in a tight street), player can ease off steering and the view returns to normal.

**Risks and mitigations:**
- **Disorienting at high speed.** Head snap to 45° might cause motion sickness. Mitigation: use smooth interpolation (0.2 s ramp), not instant rotation. Option: add a toggle in pause menu to disable or reduce max head yaw (default 45°, options: 0° off, 22°, 45°, 60°).
- **Obscures the road ahead.** Hard shoulder-look can hide the apex of a tight corner. Mitigation: keep peripheral view of the road (the head rotates but the cockpit frame stays visible), and the player's steering input is visible on the wheel so they know the turn angle.
- **Doesn't work in all views.** This is cockpit-only. Chase view has no head rotation (camera is third-person, no "head"). Acceptable.

## 3. Blind-spot awareness (HUD indicator)

**Problem:** Mirrors alone don't show what's beside the car (true blind spot: between the A-pillar and the rear-quarter). The shared rear camera can't see directly alongside; door mirrors show parallax-challenged angles.

**Solution:** A **blind-spot proximity indicator** on the HUD that lights up when a car is within a dangerous zone beside or behind the player.

### Blind-spot zones

```
        [Player car (coupe)]
            |  |  |
Blind-spot (green zone):
    LEFT:   █    vehicle detection
Alongside  █
         ┌─┴─┐
         │ P │  Rear-view mirror shows this
         │ L │
         │ Y │
         │ R │
         └───┘
    RIGHT: █
Alongside  █
```

Define two **alert zones** (per axle):
- **Alongside-rear:** Any car within a 3 m radius, laterally ±0.5 m (door mirror zone), 0–3 m behind the rear axle. This is the blind spot proper.
- **Immediate rear:** Any car 0–1 m directly behind (the mirror shows this, but a warning light is reassuring).

### HUD indicator design

**Position:** One small light per side, mounted at the edge of each mirror's onscreen rect, or on the A-pillar edge (low-intrusion).

**Visual:**
- **Off (no car):** Dim amber triangle or light (barely visible, not distracting).
- **Car detected (alongside-rear or immediate-rear):** Bright amber/red light, solid.
- **High alert (car within 1 m alongside):** Red light, pulsing (~1 Hz).

**Logic:**
1. **Proximity detection:** Physics raycast or spatial query per frame. Check for traffic/NPC cars in the two zones.
2. **Hysteresis:** Light stays on for 0.5 s after a car leaves the zone (prevents flickering as a car passes).
3. **Visual falloff:** Light dims if the car moves into the mirror's field of view (since the mirror now shows it, the HUD indicator is less urgent).

**No audio cue.** (Avoid annoyance; visual is enough.)

### Example: Player entering a lane change

1. Coupe is driving straight at 80 km/h. Blind-spot lights are dim.
2. Player steers left (lane-change attempt). Head automatically yaws right, shoulder-looking. Right mirror becomes visible.
3. There's a sedan 1.5 m behind and slightly right, in the true blind spot (not in the mirror). Right-side amber light flashes: **"Car there!"**
4. Player aborts lane change and straightens the wheel. Head returns to center. Light fades.
5. Player checks the mirror (still visible in cockpit), sees the sedan, and waits for it to pass.

### Implementation notes

- **Blind-spot zones are hard-coded per car** (or read from CarSpec). Coupe's alongside zone: ±0.5 m lateral, 0–3 m back. Adjust per car shape if needed.
- **Lights are toggleable in pause menu.** Player can disable them if they feel like relying on mirrors alone. (Default: on.)
- **Cop cars and player crew cars** are ignored (the player is friendly with them). Only traffic and rivals light the indicators.
- **Cost:** One spatial query per side, per frame, in cockpit view only. Negligible (Iris Xe can handle it alongside the mirror render).

## 4. Head and eye movement details

### Steering-to-head mapping formula

```
steering_input = joystick.x or button state (-1 to 1, full left to full right)
steering_angle_deg = steering_input * max_steering_angle (e.g., 86°)

if abs(steering_angle_deg) > 60:
  target_head_yaw = sign(steering_angle_deg) * -45  # opposite direction
  target_head_pitch = 5
else:
  target_head_yaw = 0
  target_head_pitch = 0

current_head_yaw = lerp(current_head_yaw, target_head_yaw, delta_time / 0.2)
current_head_pitch = lerp(current_head_pitch, target_head_pitch, delta_time / 0.2)
```

**Params for Roy to tune:**
- **Steering threshold:** 60° lock? (Can go down to 45° for earlier shoulder looks, or up to 75° for late look-ahead.)
- **Head yaw max:** 45°? (Can go to 30° for subtle, 60° for aggressive.)
- **Pitch:** 5°? (Or 0° if shoulder-look feels unnatural with pitch.)
- **Interpolation time:** 0.2 seconds (smooth ramp). Can go 0.1 s (snappy) or 0.3 s (sluggish).

### Head movement vs. body roll

The player's body also rolls with lateral g-forces (from the cockpit-interior proposal, PR #1: head lag up to 4 cm lateral, 1–2° roll). This is separate from the steering-driven yaw. The head should be able to do both:

- **Steering-driven yaw** (0–45° left-right): dominates when steering hard.
- **G-force roll** (±1°): added to the yaw. At high lateral g, the head tilts with the car's body.
- **Yaw decay:** If steering returns to center, the head yaw fades to the g-force roll, smoothly.

This is a matrix multiplication in the camera update, not complex.

## 5. Integration with mirror rendering (from mirrors-research)

The mirrors themselves are **unchanged** from Option B:
- **One shared rear camera** at the driver's head, 1.05 m up, ~0.20 m behind the eyepoint.
- **Throttled to 30 Hz** in cockpit, `UPDATE_ONCE` per-frame-skip.
- **Three slices:** rear-view mirror (center), left door mirror (left edge), right door mirror (right edge, mirrored).
- **Low resolution:** 384 × 96 combined for all three, nearest-filtered for PS2 grain.

**New element:** the blind-spot HUD lights. They are 2D quads on the HUD layer, not part of the mirror render. They light up based on the spatial query, independent of what the mirror actually shows. This means:
- If a car is in the blind spot, the light glows even if the mirror can't see it (because the mirror's field is limited and has a far plane ~120 m away).
- If a car moves into the mirror's view, the light dims (hysteresis) but the mirror image shows it directly, which is more informative.

## 6. Steelman

No keybinds needed. Mirrors appear automatically in cockpit view, shoulder-looks happen naturally during hard turns, and blind-spot lights give the player instinctive awareness. The mechanic is **reactive, not proactive:** the player doesn't hunt for mirrors; they appear when needed. Steering input drives head rotation, so look-back is a consequence of the player's driving, not a separate skill. Blind-spot awareness is a safety net, not a replacement for mirrors—it encourages mirror-checking habit.

## 7. Premortem (why this fails)

1. **Automatic head rotation is disorienting.** Player doesn't expect the view to shift when steering. Mitigation: make threshold high (75° lock) or disable by toggle, and ensure smooth interpolation (0.2 s, not instant).
2. **Shoulder-look obscures too much road.** Hard turns become blind at 45° yaw. Mitigation: keep cockpit frame visible in peripheral, use head pitch to look up slightly (helps depth perception), and test with Roy on a tight slalom.
3. **Blind-spot light is too noisy.** Flashing lights cause distraction or motion sickness. Mitigation: dim when mirror shows the car, use a hysteresis delay (don't flicker), and toggle in pause menu.
4. **Mirror rendering cost is higher than expected.** 30 Hz on an already-tight Iris Xe. Mitigation: lower mirror resolution (384 × 96 → 256 × 64), drop to 20 Hz, or measure first with `benchmark.bat`.
5. **Players ignore the mirrors in freeplay.** No mechanical penalty, so casual players don't look. Mitigation: it is fine; mirrors are optional. Players who want them have them. Enforce mirror-use in racing via difficulty settings (Sim mode: no hud indicator, mirrors only).

## 8. Roy's decisions needed

1. **Steering threshold for shoulder-look:** 60°, 75°, or tunable in settings? (Default: 60°.)
2. **Head yaw max:** 45° (full over-shoulder), 30° (subtle), or tunable? (Default: 45°.)
3. **Blind-spot light pulsing:** Pulse when car is within 1 m alongside (alert mode), or always solid? (Default: pulse only in alert.)
4. **Disable option:** Allow players to turn off automatic shoulder-looks? (Default: toggle in pause menu.)
5. **Freeplay vs. race:** Should mirrors be required in race mode (Sim setting) but optional in freeplay? (Default: optional in both; players choose.)

## Implementation order

1. **Phase 1 (S):** Automatic mirror activation on cockpit view. Reuses existing MirrorRig from mirrors-research build; just toggle render mode based on camera.
2. **Phase 2 (S):** Steering-driven head yaw and pitch. Update `chase_camera.gd` to read steering input and apply head rotation smoothly.
3. **Phase 3 (S):** Blind-spot spatial query and HUD lights. One raycast query per side per frame; two small quads on the HUD layer.
4. **Phase 4 (S):** Testing and tuning with Roy on laptop (thresholds, feel, visual feedback).

Total: S + S + S = M, one PR after mirrors-research is merged. Depends on mirrors-research (Option B) being built first.
