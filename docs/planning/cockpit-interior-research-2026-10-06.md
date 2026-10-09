# Cockpit interior: research, sightline spec, per-car brief (2026-10-06)

Research only. Nothing is built; Roy signs off before any build. Mirrors are covered in
[mirrors-research-2026-10-06.md](mirrors-research-2026-10-06.md); this file only keeps them out of the sightline.

## 1. What Roy is looking at (read from main @ bd7957c)

- `scripts/view/cockpit_frame.gd` is unchanged since the Phase C commit (0872d0d); no interior branch exists on origin. So the build Roy saw is almost certainly this stand-in (inferred: a local unpushed build would not show up here).
- It is 5 unshaded boxes + a torus wheel, all near-black (`#0D0D12`, `#1A171F`), child of the camera. Camera: eye `(-0.30, 1.05, -0.15)` car-local, vertical FOV **78°** (~110° horizontal at 16:9). The coupe body is hidden in cockpit view, so there is no hood.
- Measured from the code (angles from the eye, looking straight ahead):

| Part | Edge angle | Screen covered at FOV 78 |
|---|---|---|
| Roof edge (bottom edge) | +24.6° | top 22% |
| Wheel rim top (centre column) | −10.4° | bottom 39% |
| Dash lip | −20.8° | bottom 27% (outside the wheel) |
| Left A-pillar | 39° left, 6° wide | slice at left |
| Right A-pillar | 55° right | at the screen edge |

- **Why it reads as "blocked":** in the centre column only ~40% of the screen height is glass. The wheel, not the dash, is the main blocker: its rim pokes 10° above the dash line into the road band. And flat near-black unshaded shapes read as holes in the image, not as objects, so the frame feels heavier than its size.
- **Why it reads as "ugly":** no shading, no texture, no light from the world, box primitives with no bevels, a 3 cm-thick wheel rim. (The proposal file already lists this.)
- Side finding (inferred from the `fleet.json` profile, verify in a screenshot): the coupe's windshield header sits at about z −0.04, so the current eye (z −0.15) is ~0.4 m further forward than a real driver in that body.

## 2. What the research says

- **Real cars** (EU Directive 77/649/EEC, now UNECE R125): the windscreen must be clear from **7° above to 5° below** horizontal, and each **A-pillar may hide at most 6°**. Real dash/hood lines sit only ~5–8° below the eye, so a real car hides the first ~8–10 m of road. A literal real interior would be *more* blocked than ours, so the game must cheat.
- **Sim racers vs. games:** a "correct" FOV for a monitor is ~30–50°; nearly everyone finds that undrivable and widens it (OverTake, GTPlanet threads). Forza players repeatedly ask for seat height and FOV to be adjustable separately (Forza forum threads below). Takeaway: the interior is fixed in angle, so the **FOV decides how much of the screen it eats**. At 78° you see the whole cabin; narrowing the FOV crops the cabin and gives the road more screen.
- **NFS Shift (2009), the reference for "convincing" cockpits:** the interior itself is ordinary; the feel comes from the *head*: g-forces move the camera, the car shakes on rough road, depth of field pulls focus onto the road at speed, crash blur and a cracked windshield, readable working gauges so the HUD can be off (EA interview, TheGamer).
- **PS2-era technique** (general knowledge, no single source): low-poly hard shapes, lighting baked into vertex colours, small bilinear textures, very few dynamic lights. That matches "Gritty PS2 night" and costs nothing on the Iris Xe.

## 3. Sightline spec (proposal; all angles from the eye, car on flat road)

| Rule | Number | Now |
|---|---|---|
| Default cockpit vertical FOV | **62°** (~94° horizontal at 16:9), speed widening up to +6° | 78° |
| Eye height (coupe) | ~1.00 m above ground, ≥0.20 m below the roof skin; per car | ~0.99 m |
| Eye lateral | 0.33–0.37 m from centre (left-hand drive); per car | 0.30 m |
| Clear windshield band, centre ±25° horizontal | from **−14° to +24°**: nothing opaque inside it | −10.4° to +24.6° |
| Dash/cowl line | at or below −14° → road visible from ~4 m ahead | −20.8° (2.6 m) |
| Wheel rim top | at or below **−15°** (never above the dash line) | −10.4° |
| Wheel | rim Ø 0.34–0.38 m, grip tube 30–35 mm, 0.55–0.65 m from the eye | thin 3 cm torus |
| Gauges | seen through the wheel's upper opening, band −17° to −28°; tach ≥6° across (~95 px at 1080p), numerals ≥1° (~15 px), needle ≥0.25° | none |
| A-pillars | ≤6° apparent width (the EU rule); driver pillar inner edge ≥28° off-axis; passenger pillar ≥50° (off screen at 62°) | 6°, 39° / 55° |
| Roof/header line | at or above +24° (top ≤13% of screen) | +24.6° |
| Mirrors (other thread) | rear-view lower edge ≥ +14°, centre ≥10° toward the passenger side; door mirrors ≥40° off-axis | none |
| Near clearance | nothing closer than 0.25 m to the eye | ok |
| **Result** | clear glass ≥**55%** of screen height in the centre column (the spec gives 58%) | ~40% |

The cowl at −14° is a deliberate cheat: halfway between a real car (~−6°) and today's −21°. It keeps the road visible from ~4 m and still looks like a dash, not a floor.

**Check it headlessly:** a test projects every interior mesh's bounds through `Camera3D.unproject_position` at the default FOV and fails if anything opaque enters the clear band or the coverage goes over budget. That runs in a headless Godot run; how it *looks* still needs a real rendered screenshot on Roy's laptop.

## 4. Look: what makes it convincing, cheaply

**Light (the biggest win)**
1. **Bake lighting into vertex colours** (PS2 way): lighter where the windshield lights it (dash top, wheel top, pillar edges), dark in seams and the footwell. Keep materials unshaded, so it is free and never too dark. **No pure black**: darkest surface navy `#0E1424`, lit edges ~25–35% brightness. Black reads as a hole, which reads as "blocked".
2. **Sodium streetlight sweep** (signature effect): lamps pass every 12.5 m, so a warm `#FF8A1F` band slides front-to-back over dash, pillars, wheel and headliner once per lamp. One shader uniform driven by distance travelled. **Fade it to a steady glow above ~2.5 sweeps/s** (≈110 km/h) to stay under the 3 flashes/s photosensitivity line.
3. **Gauge spill**: constant amber `#FFC066` glow on the binnacle hood underside and wheel spokes.
4. Later/optional: cool silver wash across the headliner when traffic headlights come up behind.

**Surface (low-res, 64–128 px, bilinear)**
- Dash vinyl grain; wheel leather with one stitch row and **worn silver patches at 10 and 2**; worn gear knob, armrest and door sill; plastic trim with a faint scratch layer.
- Windshield (optional, one quad): edge grime, wiper arc, faint dash-glow reflection at the bottom; alpha ≤0.08 inside the clear band; on a toggle.

**Shape**
- Read the cockpit through **four silhouettes**: cowl line, binnacle hump, pillar rake, wheel. These carry each car's identity.
- Big simple shapes with 2–3 bevel segments on every edge that catches light. No thin clutter inside the clear band.
- Budget: ≤3k triangles, ≤4 draw calls (shell atlas, gauges emissive, wheel so it can turn, glass).

**Motion (Shift's lesson)**
- Head lag: eye moves up to 3–4 cm and 1–2° with braking, throttle and cornering; interior stays rigid to the car. The current camera shake carries over.
- Optional, benchmark first: interior depth-of-field blur at speed.

**Floating hands (Roy, 2026-10-06 15:50: wants hands, but floating)**
- Two gloved/bare hands on the rim with **no forearms or arms**: each ends in a clean cuff, so nothing reaches back toward the body and nothing blocks the interior view.
- Grip at 9 and 3 o'clock, parented to the wheel, so they turn with it (full lock is ~86°, no hand-over-hand needed).
  - Update 2026-10-07: grip lowered to about 8 and 4 (`DriverModel.GRIP_DEG`); hands turn with the wheel only between the flat bottom and about half past 2 and slide past that, so they no longer ride up over the cluster at lock. `tests/view/cockpit_driver.gd` now checks every hand mesh corner against the −18° budget (was 9° at lock, now 19.4°).
- Sightline budget: hand tops at or below **−18°** (inside the wheel's lower area, well under the −14° dash line); together ≤600 triangles, 1 draw call; same vertex-baked light, sodium sweep and gauge spill as the cabin.
- Shifter hand: at FOV 62 the shifter sits below the screen edge (~−40°), so in step 1–2 hands stay on the wheel. When the visible shifter lands (proposal step 3), the right hand hops to the shifter for each manual shift and back (~0.25 s), never crossing the clear band.
- Per car: glove or skin style is a field in the art brief (e.g. coupe: black leather driving gloves with an amber stitch).

**Leave out for now**
- Arms and forearms (ever), pedals, most of the seats, passenger-side detail beyond the dash face, door handles.

**Cheap props that sell it (2–3 per car, never in the clear band)**
- Air freshener swinging with lateral g, radio head unit with an amber LCD showing the station name (ties into the radio), aftermarket boost gauge on the pillar, a parking receipt on the dash, a faded sticker.

## 5. Per-car interior art brief (template)

```
Car: <id, label>                     Body refs: <from fleet.json>
Era/mood (one line):
Eye: height above ground __ m, lateral __ m, behind header __ m
Sightline check: cowl __° (≤−14), wheel top __° (≤−15), header __° (≥+24),
                 driver pillar __° off-axis / __° wide (≤6)
Four silhouettes:
  Cowl line:        <flat / curved / hooded / scooped>
  Binnacle:         <hump shape, how far it rises>
  Pillar rake:      <angle, thickness, trim>
  Wheel:            <diameter, spokes, grip, centre pad>
Cluster (own design): layout, gauge count, faces, needle colour, glow
Materials: base value, trim, one accent from the palette, wear spots
Props (max 3):
Light: sweep strength, gauge spill colour
Hands: glove/skin style, cuff colour
What must NOT be added:
Screenshot checkpoint: straight ahead at 0, 100, 200 km/h + one corner
```

**Filled for P1 coupe (draft, for Roy to change):** late-90s driver-focused coupe. Cowl curved and low, sweeping into a hooded binnacle that wraps toward the driver; centre stack angled ~10° to the driver; slim, steeply raked pillars; 3-spoke leather wheel Ø0.36 m with a thick grip; cluster: big centre tach, speedo right, small boost/oil/fuel left; amber needles, cream-amber numerals on black-navy faces; charcoal vinyl, silver bezel trim, Sodium orange stitch as the one accent; props: boost gauge on the pillar, amber radio LCD; wear on wheel top and gear knob; hands: black leather driving gloves, amber stitch.

How the other five could differ (one line each, to show the template works):
- **Hot hatch:** upright flat dash, tall thin pillars, big glass, 4-spoke wheel, simple 2-dial cluster.
- **Tuner sedan:** squared dash, three aux gauges on the dash top, deep bucket edge visible, 3-spoke suede wheel.
- **Kei roadster:** no roof (header rule void), windshield frame only, tiny round gauges, roll hoop in the mirrors.
- **Muscle sedan:** long flat dash, horizontal strip speedo, big thin wheel (still ≤−15°), column shifter, bench seat edge.
- **Crossover:** high seat, upright pillars, view over a visible hood bulge, chunky rally wheel, compass/inclinometer.

## 6. Steelman and premortem

**Steelman:** "blocked" is a geometry and FOV problem we can fix with numbers and a test, before any art. "Ugly" is mostly light and material (flat black), not polygon count. Baked light plus the sodium sweep ties the cockpit to the street, which is the night-driving feeling the game is about.

**Premortem (why this fails):**
- A low cowl can feel like sitting on a booster seat. Mitigation: −14° is a middle value; tune per car from screenshots.
- FOV 62° can feel slower than 78°. Mitigation: speed widening, and keep 78 as a setting to compare.
- The sweep strobes at speed. Mitigation: fade above 2.5 Hz (photosensitivity).
- Taste miss again. Mitigation: two variants as screenshots before a PR.
- Glass quad or DOF costs frames on the Iris Xe. Mitigation: both optional, measured with `benchmark.bat`.
- Visuals need rendered screenshots, which need a session on Roy's laptop; the headless test only proves the sightline numbers.

## 7. Recommended direction

**"Game-honest cockpit":** real-car shapes with a cheated sightline (FOV 62, cowl ≤−14°, wheel ≤−15°, header ≥+24°), PS2 vertex-baked light with the sodium sweep as the signature, identity from four silhouettes per car. Coupe first.

Build order after sign-off (one PR each):
1. **Sightline PR**: FOV, eye point, re-place the existing parts to the spec, plus the headless coverage test. Fixes "blocked" before any art (Sonnet/Opus).
2. **Coupe interior art pass**: modelled low-poly shell + vertex light + sweep + wheel (Fable, screenshots on Roy's laptop).
3. Coupe cluster (already step 4 of the interior proposal).

## Sources
- EU Directive 77/649/EEC, field of vision (6° pillar, 7° above / 5° below): https://eur-lex.europa.eu/eli/dir/1977/649/oj
- UNECE Regulation 125 (current equivalent): https://lexaris.de/library/tableofcontents/2059117
- Vehicle blind spot (pillar angles, sports-car windshield rake): https://en.wikipedia.org/wiki/Vehicle_blind_spot
- NFS Shift producer interview (head g-forces, DOF, working dash): https://www.ea.com/news/need-for-speed-shift-executive-producer-interview
- Why Shift's cockpit works (head movement, blur, shake, crash effects; screenshots): https://www.thegamer.com/why-need-for-speed-shift-has-a-perfect-cockpit-view/
- Calculated vs. playable FOV: https://www.overtake.gg/threads/fov-calculators-cant-be-right.127343/
- FOV discussion with comparison screenshots: https://www.gtplanet.net/forum/threads/field-of-view-fov-aka-why-does-that-track-look-so-wide.323267/page-9
- Forza players on cockpit camera height vs. FOV: https://forums.forza.net/t/camera-height-angle-independent-of-fov-in-cockpit-view/564438 and https://forums.forza.net/t/driver-camera-position-height-and-distance-from-wheel/809536
- Monitor distance and FOV guide: https://simxpro.com/blogs/guides/sim-racing-monitor-distance-and-fov-the-setup-change-that-makes-everything-feel-real

## 8. Step 1 build plan: sightline PR (Roy approved the spec and direction, 2026-10-06 15:48)

Not started: waits for the first laptop session Roy allows (one request is already pending in the mirror thread; no second card). Base: origin/main bd7957c, own worktree under `.claude/worktrees/`, branch `feat/cockpit-sightline`.

Model: Opus or Sonnet (geometry and a test, no art judgement). The art pass after it is Fable.

Changes (values only, no new art):
- `scripts/view/chase_camera.gd`: `COCKPIT_FOV` 78 → 62 (speed widening +6 stays); `COCKPIT_EYE` lateral −0.30 → −0.35. Eye height and z unchanged in this PR (the frame is camera-local, so z only matters once the hood or body shows).
- `scripts/view/cockpit_frame.gd`, re-placed to the spec:
  - Wheel centre (0, −0.334, −0.62): rim top at −15.5°, below the dash line (now −10.4°). Grip tube 0.03 → 0.034 m.
  - Dash slab and lip top at −14.5° (lip top y ≈ −0.285 at z −1.10; now −20.8°). The dash comes *up* a little because the wheel no longer hides it, and road stays visible from ~4 m.
  - Roof edge bottom at +24° or higher (y ≥ 0.467 at z −1.05; now +24.6°, roughly unchanged).
  - Pillars: unchanged (driver 39° / 6° wide; passenger at 55° falls off screen at 62°).
  - Colours: replace pure black with navy `#0E1424` (dash) and `#1B2A4A`-derived trim, still unshaded. Baked vertex light and the sodium sweep belong to the art pass, not this PR.
- New `tests/cockpit_sightline.gd`, added to `tests/run_tests.bat`: switches to the cockpit view at rest, projects the corners of every frame mesh's AABB through the camera, and fails if:
  - anything opaque lies inside the band −14°..+24° vertical × ±25° horizontal;
  - the wheel rim top is above −15°;
  - a pillar is wider than 6°;
  - clear glass in the centre column is below 55% of screen height.
  It also prints the measured angles so the numbers in this file can be checked.
- `tests/view/cockpit.gd` must keep passing (view switch, wheel turns, audio muffling).
- Hands are built in the art pass (step 2), but the sightline test already reserves their budget: anything tagged as hands must stay at or below −18°.

Verification: real headless Godot runs of `cockpit_sightline` and `cockpit` (plus the full `run_tests.bat`), then one cockpit screenshot at 0 and 100 km/h from the laptop so Roy judges the view before merging.

## 9. Roy's answers (2026-10-06 15:53) and the hand/head plan

Answers: hands **gloved** (style per car), **FOV slider yes**, **head movement on**, and the right hand moves for **every manual shift, the radio, the handbrake and turning the wheel**.

### Hand states (right hand; the left stays on the rim unless noted)
All inputs already exist on main (`shift_up`/`shift_down`, `radio_next`, `handbrake`, steering). Hands are visual only: they never delay or change an input.

| State | Trigger | Motion and timing | Where it goes on screen |
|---|---|---|---|
| Wheel (rest) | default | both hands at 9 and 3, parented to the rim, turn with it | ≤ −18° |
| Wheel shuffle | steering past ~60° of wheel angle | top hand lets go and re-grips lower (0.15 s), the other hand keeps turning; back to 9/3 when the wheel centres | ≤ −18° |
| Radio | `radio_next` | reach 0.18 s → press 0.08 s → return 0.2 s | head unit centre ~−27°, ~22° right: bottom-right of the screen, hand stays under −18° |
| Handbrake | `handbrake` held | drop to the lever 0.12 s, hold while held, return 0.2 s | lever ~−45°: hand leaves the bottom edge of the screen |
| Shift | each manual shift | drop to the shifter 0.12 s, move 0.06 s, stay up to 0.6 s for quick follow-up shifts, return 0.2 s | shifter ~−40°: off the bottom edge at FOV 62, partly visible at 78 |

- **Priority:** handbrake > shift > radio. A new request interrupts a radio reach. While the right hand is away the left hand steers alone (shown by the left hand turning the rim).
- **Path rule:** hands move along a low arc below the wheel hub, never up through the clear band. The test checks the hand bones at every keyframe, not just at rest.
- **Placement per car (art brief fields):** radio unit and handbrake lever positions. Radio top edge at −22° or lower, handbrake and shifter at −35° or lower. The muscle sedan's column shifter is the exception: the hand goes to the column, behind the rim, still ≤ −18°.
- Gloves: one hand mesh, the style is a per-car material (coupe: black leather, amber stitch).

### Head movement
- Eye moves up to 4 cm and pitches/rolls up to 2° with braking, acceleration and cornering, smoothed (~0.15 s). Off switch in the pause menu.
- The sightline test runs at rest **and** at the extreme head offsets, so the clear band holds when the head moves (it effectively adds a ~2° margin).

### FOV slider
- Pause menu, cockpit only: 55–78°, default 62°, saved with the other settings. The test checks the band at 62°; at 78° the band is still clear, but more of the cabin shows (the user chose it).

### PR split (one PR each, sign-off before each; replaces the order in section 7)
| # | PR | Effort | Model | Waits on |
|---|---|---|---|---|
| 1 | Sightline: FOV 62, re-placed parts, sightline test, FOV slider | S | Sonnet | first laptop session |
| 2 | Head movement + off switch, test at extreme offsets | S | Sonnet | 1 |
| 3 | Coupe interior art pass: shell, baked light, sodium sweep, wheel, radio unit, handbrake lever | L | Fable | 1 |
| 4 | Gloved floating hands: rest, wheel shuffle, radio, handbrake | M | Fable (look) | 3 |
| 5 | Shift hand | S | Sonnet | visible shifter + transmission modes |
| 6 | Coupe instrument cluster (proposal step 4) | M | Fable | 3 |

Effort impact: hands and head add about one M and one S PR on top of the earlier plan.
