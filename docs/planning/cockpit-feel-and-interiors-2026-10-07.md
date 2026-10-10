# Cockpit: shift on contact, touch radio, prettier interiors (proposal, 2026-10-07)

Status: **proposal, docs only. No code until Roy signs off.** Interior art stays held
for next week's Fable redesign; sections 3 and 4 are inputs to that brief.
Mockups: https://claude.ai/artifact/AieeHH346Fo9v5PWkTKceu (Cockpit section).
Companion: `ui-direction-blend-2026-10-07.md` (UI layers, screen-matches-the-car rule).

Roy (2026-10-07): "the shifter would change gears only after the hand touches it not
before", the radio should be a 2026 touch screen, and interiors should be prettier.

## 1. Shift on contact

### What happens today (read from the code)

- `player.gd`: `shift_up` / `shift_down` call `manual_shift()` on the key press, so
  the gearbox changes gear **at once** (GEVP `shift_time` 0.3 s starts then).
- `cockpit_frame.gd`: the lever follows the requested gear, so it **starts moving at
  once**.
- `driver_model.gd`: the hand only starts its reach when the lever starts moving, and
  the reach takes `REACH_SECS` 0.22 s. So the lever is already in the gate before the
  hand gets there. That is the bug Roy sees.

### Proposed order

| t | Key press | Hand | Lever | Gearbox | HUD gear |
|---|---|---|---|---|---|
| 0 | `shift_up` | leaves the rim | still | throttle lift starts (feels responsive) | old gear |
| ~0.12 s | | **touches the knob** | starts through the gate | **gear changes** (`manual_shift`) | new gear, flash |
| ~0.12 + gate | | rides the knob | in the new slot | normal shift_time | |
| later | | stays on the knob (see below) or returns | | | |

- **Contact is the trigger.** `DriverModel` emits `hand_contact(kind)` when the hand
  reaches the knob, the paddle or the screen; the player applies the queued action then.
  One code path for shifter, paddles and radio.
- **Reach 0.12 s, not 0.22 s.** Keeps the added latency small. A quick H-pattern shift by a real driver
  takes roughly 0.3 to 0.5 s in total (estimate), so 0.12 s of reach reads as natural.
- **Hand rests on the knob** for about 1 s after a shift. A second shift in that
  window has zero reach (like a run of upshifts in a real car), so quick 2-3-4 changes
  never wait.
- **Queued presses**: a second press while the hand is reaching is queued and applied
  on contact (up to two), so fast tapping never loses a shift.
- **Automatic / semi**: the finger flicks the paddle; the shift happens when the paddle
  clicks (about 0.06 s). Same rule, shorter reach.
- **Refused shift** (MANUAL without enough clutch): the hand still goes to the knob,
  the lever pushes against the gate and springs back, with a short grind sound. The
  player learns why with no on-screen text.
- **Chase cam / hands hidden**: the same timing still applies, so shifting does not
  feel different between views.

### Visual and sound feedback at contact

- Knob dips a few mm under the palm (contact), then the lever moves.
- A soft mechanical clack on contact, the gate click as it enters the slot.
- The HUD gear number changes on contact, not on the key press.

### Tests

Headless test: key press at frame N; assert `current_gear` unchanged until the
`hand_contact` frame, changed after it; lever angle unchanged before contact; two quick
presses give two gears; refused shift leaves the gear unchanged.

### Risk

Added latency in fast driving. Mitigations above (0.12 s reach, rest on knob, queue).
If it still feels slow in a test drive, the reach time is one constant to tune.

## 2. Touch-screen radio

Covered in `ui-direction-blend-2026-10-07.md` section 4. In short: four station
tiles, the playing one framed in sodium; `N` sends the hand to the screen and the
station changes on the tap (same `hand_contact` path as section 1); a physical volume
knob beside it; glare, no scanlines. Today's `driver_model.gd` already reaches the head
unit, but *after* the station has changed; this flips the order.

## 3. Why the interiors look like a demo (read from the code)

- **One material for the whole cabin.** `cockpit_frame.gd` builds almost every part
  with `CockpitKit.material()` (roughness 0.85, no metal), so dash, seat, carpet and
  trim all react to light the same way.
- **Everything is the same dark value.** The cabin colours run from `#0E1014` to
  `#2C3038`. With no contrast between surfaces, shapes merge into a dark mass.
- **No surface detail.** No grain, stitching, seams, or texture breaks, so large flat
  faces read as untextured blockout.
- **One light.** A single `OmniLight3D` cabin light; nothing picks out edges.

## 4. Prettier interiors: direction for the Fable brief

Keep the sightline spec (clear glass >= 55%, no pure black) and the low-poly PS2 look.
Prettier here means material contrast and light, not more polygons.

### Materials: at least four distinct surfaces per car

| Surface | Look | Godot |
|---|---|---|
| Hard plastic (dash, console) | Fine grain, low sheen | roughness 0.8, tiny grain normal map |
| Soft touch (dash top, door caps) | Matte, slightly lighter | roughness 0.95 |
| Leather / cloth (seat, wheel) | Stitch lines in amber or silver thread | roughness 0.6-0.7, stitch lines as vertex-colour strips |
| Metal (pedals, gate, trim) | Brushed, catches light | metallic 0.7, roughness 0.35 |
| Rubber (mats, pedal pads) | Darkest value, no sheen | roughness 1.0 |
| Glass / screens | Dark with glare | unshaded screen + glare overlay |

One shared grain texture (tileable, about 128 px) covers every plastic, so cost stays low.

### Value and colour

- Three value steps per cabin, not one: dark (floor, lower dash), mid (seats, door
  cards), light accent (one trim line or the seat centre).
- **Per-car colour story**, matched to era:
  - **Beater (old Beetle-style)**: painted metal dash in the body colour, cream or
    ivory wheel and knobs, one big round speedometer, rubber mats, checked cloth seats.
    Real old Beetles had painted dashes, so this is the most characterful interior of
    the lot and costs almost nothing.
  - **P1 coupe (older sports car)**: grey hard plastic, cloth bucket seats with
    silver piping, aluminium pedals, an analog cluster with amber backlight.
  - **Modern cars**: dark leather with amber stitching, soft-touch dash, digital
    cluster, a thin amber ambient line along the dash (never blue or cyan).

### Light

- **Amber gauge backlight** spills onto the wheel rim and the hands (small spot light).
- **Sodium streetlight sweep** across the cabin as you pass lamps (already in the
  sightline spec; fade above 2.5 Hz).
- **Head unit glow** on the right hand and console when the screen is on.
- **Thin rim light** on the dash edge and A-pillar from the night sky, so the
  silhouette reads against the glass.
- Baked ambient occlusion in vertex colours (corners and seams darker): cheap and
  very PS2.

### Windscreen

Roy confirmed "the windshield issue is real". This doc does not cover it; it needs
its own fix (owner: the coordinator to assign). If it involves dash reflections, the
glass layer from section 3 of the blend doc (glare, no tint) applies.

## 5. Build order (after sign-off)

1. **Shift on contact + radio on contact**: one PR (`player.gd`, `driver_model.gd`,
   `cockpit_frame.gd`, `radio_manager.gd` hook), with the headless timing tests.
   Independent of the art redesign, so it can go first.
2. **Interior materials**: one PR for the shared material set and grain texture, then
   per car with the Fable redesign (coupe first, then the beater).
3. **Touch head unit screen**: with the coupe interior PR.

## 6. Decisions for Roy

1. Gear changes on hand contact, reach 0.12 s: **Yes (recommended)** / keep 0.22 s reach
2. Hand rests on the knob about 1 s after a shift: **Yes (recommended)** / always returns
3. Refused shift bounces off the gate with a grind: **Yes (recommended)** / nothing happens
4. Beater gets a painted body-colour dash and ivory wheel: **Yes (recommended)** / dark plastic like the others
5. Thin amber ambient light line in modern cars: **Yes (recommended)** / none
