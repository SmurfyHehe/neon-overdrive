# Cars as the main attraction: look and showcase proposal (2026-10-09)

Docs only. Nothing here is built. Roy's ask: "enhance our design of the cars.
The cars should be the main attraction of the game."

Sources read: `docs/design/fleet/` (12-car design sheet, B1 audit),
`scripts/p1_coupe_builder.gd` (paint shader, vertex-alpha paint mask, rim
material), `scripts/car_builder.gd` (traffic boxes and lofts),
`scripts/photo_mode.gd`, and the notes on garage/body shop, mod tree, tuner
look, cockpit interiors, graphics polish and the car ladder. Screenshots in
`/mnt/project-files/screenshots/cars/` and `/cockpit/`.

Rules already decided and kept here: all assets free for commercial release
with no credit (CC0 or made by us); original designs, no brand names; vented
hood is a separate body-shop item; wide-body is looks only; palette fully
open; ride height stays in the Tuner; 4 sticker slots per car; interiors and
gauge clusters are individual per car; no key hints on screen; Mobile renderer
on an integrated-graphics laptop.

## Steelman and premortem

**Steelman.** In every street racer people remember, the car is the
protagonist: you buy the game to look at your car under lamps, in the garage,
in the photo you post. The sim is already shared and the shapes already read
from every angle (the B1 blind test), so the missing piece is not more
polygons but *light on paint*, *parts that change the silhouette*, *a cabin
that feels owned*, and *moments where the game stops to show the car*. All of
that is material, light and camera work, which is cheap on this renderer.

**Premortem.** Three ways this fails. (1) Reflections: the Mobile renderer
has no screen-space reflections, so paint can only reflect what we fake; if
the fake cubemap looks like a sticker the paint will look worse, not better.
(2) Parts explosion: six cars times ten part slots times three options is 180
meshes; if each is hand-modelled this never ships. (3) Showcase scenes that
run at 20 fps on Roy's laptop make the car look worse than the road does.
Each section below names its guard.

## 1. What the car looks like today (read from code and screenshots)

| What you see | Why |
|---|---|
| Paint reads as coloured plastic, no highlight travel as the car turns | The P1 shader has metallic 0.5 / roughness 0.38 but the sky is near black, so there is nothing to reflect (`p1_coupe_builder.gd:66-72`). Traffic uses `car_builder._mat` with metallic 0.3, roughness 0.5, no clearcoat |
| Car stays the same brightness under every lamp | Lamps are glowing quads on the road; they never light the car (graphics note A/B2) |
| Lights are flat emissive rectangles | Head and tail lamps are emissive boxes with no lens, no bloom shape, no reflector |
| Wheels are a cylinder with a face plate | One rim mesh, no spokes depth, no tyre wall text, no brake behind |
| Cabin is one dark material | `cockpit_frame.gd` builds nearly everything with one roughness 0.85 material (interiors note, section 3) |
| The only showcase is the chase cam and photo mode | No garage view yet, no reveal, no rolling shot |

What is already good and stays: the lofted wedge silhouettes, the one-hero-cue
rule per car, pop-ups that stand up at night, the four decal slots with their
transforms in `fleet.json`, the 2.4-3.3k triangle budgets.

## 2. Body shape and silhouette

The B1 sheet is kept as the base. "Enhance" means three passes on top of
the proxies, not a redesign:

1. **Bevel and crease pass.** One chamfer loop on every hard edge (hood edge,
   belt line, arch lip, decklid). On flat-shaded low-poly this is the single
   biggest "real car" cue; cost is +15-25% triangles, still inside budget. The
   rim-light fake in `car_builder._mat` stays for traffic only.
2. **Panel lines as paint, not geometry.** Door, hood and trunk shut lines
   drawn as dark lines in the paint mask (vertex alpha already marks paint
   faces; a second channel marks shut lines). Reads at 10 m, costs nothing.
3. **Stance.** Wheels pushed to fill the arches, 2-3 degrees of negative
   camber on the rear of player cars, tyres slightly wider than the arch on
   wide-body. Stance is what separates a player car from traffic at a
   glance; traffic keeps the arch gap on purpose.

Per car, the hero cue and the part that should get the extra love:

| Car | Hero cue (sheet) | Where the detail money goes |
|---|---|---|
| T0 Beater (Bug style, new, in flight on the player-cars session) | Round roof, flat windscreen, separate running boards, round lamps on fenders | Dents, mismatched primer panel, one rusted fender, bumper overriders; it must look *loved*, not broken |
| P1 Sports coupe | Pop-ups, hoop wing | Pop-up mechanism visible (lid, lamp bowl), rear light bar with inner glow |
| P2 Hot hatch | Box blisters, overhanging roof spoiler | Rally mud flaps, driving lamps on the bumper, roof spoiler with gurney lip |
| P3 Tuner sedan | Boxed overfenders, pedestal wing, four round tails | Rivets on the overfenders, wing end plates, round tails with chrome rings |
| P4 Kei roadster | Twin headrest humps | Visible seats and roll hoop from outside, tonneau, tiny mirrors |
| P5 Muscle sedan | Cowl scoop, ducktail, full-width tail bar | Chrome bumpers, hood pins, raised white-letter tyres |
| P6 Perf. crossover | Black cladding, roof rack | Rally pod on the rack, mud, skid plate, tow hooks |

Traffic and police cars do not get this pass; they are meant to recede.

## 3. Paint

Paint is where the "main attraction" feeling is won or lost, and it is all
shader work on the one paint material the P1 already has.

- **Three finishes** (garage note, Roy answer 6): gloss (roughness 0.15,
  clearcoat 1.0), satin (0.4, clearcoat 0.3), matte (0.75, no clearcoat).
  Each is a roughness/clearcoat pair on the same material.
- **Fake night reflections** (graphics note A4): the sky shader draws a band
  of warm city lights only into the reflection pass, so gloss paint shows
  streaks of orange and white that slide along the body as the car turns.
  Guard: the band is blurred and low contrast, so it reads as "city" and not
  as a texture. One `ReflectionProbe` per scene, baked once.
- **Lit by lamps** (graphics note B2, Roy said yes): 2-4 real omni lights
  leapfrog to the nearest street lamps and light the car layer only. The
  car flashes sodium every 12.5 m. This is the classic night-drive rhythm
  and it is what makes the paint finishes readable at all.
- **Fresnel tint.** At grazing angles the paint picks up the navy sky, so a
  sodium car has navy edges and a white car has blue-grey sides. Two
  uniforms on the shader.
- **Flake** for one or two "pearl" paints: a tiny world-space noise added
  to the metallic term; sparkles under lamps, dead cheap.
- **Paint set.** Hero colour plus four alternates per car from the sheet
  stays as the start set; crew colours unlock when a crew is beaten. Palette
  is fully open, so pearls, candy red, british green and gunmetal are all in.
- **Wear.** The beater and "as found" cars carry a wear mask (primer, rust
  at the arches, faded roof) blended over the paint; body-shop paint resets
  it. Same mask gives the scrape marks the damage design asks for later.

## 4. Wheels, brakes, tyres

- **Rim as its own small mesh family.** Four spoke designs (five-spoke,
  mesh, dish, steelie with a hubcap for the beater), one mesh each, drawn
  four times. Spokes have depth so the brake shows through.
- **Brake disc and caliper** behind every player-car wheel: a dark disc, a
  coloured caliper (body-shop colour pick). The brake-glow idea already
  mocked (`brake_glow_cold_hot.png`) lives here: discs glow dull red after
  hard braking and fade.
- **Rim colour** as a uniform: silver, bronze, gold, black, body colour.
- **Tyre wall lettering** as a decal ring on the sidewall for P5 and the
  muscle wheels; a thin stripe option for others.
- **Dish and offset** move with wide-body: the body-shop skirt/wide-body
  option pushes the wheels out so the tyre fills the new arch.

## 5. Lights

- **Lens, not box.** Each lamp becomes a shallow lens mesh over an emissive
  reflector face, so the lamp has depth and a hot centre. Head lamps:
  bright white-amber centre, dim outer ring when parked, full when on.
- **Pop-ups** on the P1 animate (0.4 s), with the lamp bowl lit before the
  lid is fully up, which is how they looked in real life at night.
- **Tail light signature** per car: P1 full-width bar, P3 four rings, P5
  slim bar, P2 tall blocks, P6 split lamps, beater small round. Brake adds
  energy and a bloom halo sprite; reverse adds a white lamp.
- **Interior spill.** The gauge backlight spills onto the driver's face area
  and the inside of the glass (a dim amber omni light inside the cabin), so
  the car looks occupied from outside.
- **Under-lamp glint.** When a passing lamp light hits the car, chrome trim
  (bumpers on P5, rings on P3) catches a hard highlight: metallic 1.0,
  roughness 0.1 on a trim material.
- No underglow by default: it is not the look. A body-shop option can exist
  later if Roy wants it since the palette is open.

## 6. Body shop looks (wide-body, hoods, wings)

Design rule to avoid the parts explosion: **each option is a swapped piece
on a fixed attachment loop**, modelled per car but sharing the attachment
scheme, and generated the same way the proxies were (from numbers in
`fleet.json`) wherever a loft can produce it.

| Slot | Options (per player car) | How it reads |
|---|---|---|
| Hood | stock, vented (separate buy), carbon (dark weave, satin) | Vents as dark cut-outs with a lip |
| Front bumper | stock, street (lip + fog lamps), race (splitter, big mouth) | Splitter lowers the visual nose |
| Rear bumper | stock, street, race (diffuser fins) | Diffuser catches the tail bar glow |
| Skirts / wide-body | none, skirts, wide-body (looks only) | Wide-body: rivet-on arches (P3, P2) or blended (P1, P5), wheels pushed out, 60-80 mm wider stance |
| Wing | stock, duckbill, GT wing, none | End plates, uprights, in body or carbon |
| Signature | per car (P1 pop-ups or fixed nose, P4 top, P6 rack) | Looks only, decided |
| Wheels | 4 rims x 5 colours | Section 4 |
| Exhaust tips | single, twin, oval, cannon | Tips glow faint red after a hard run |
| Stickers | 4 slots, set grows with crews | Decals at `slot_transform()` |
| Plate | vanity text | Text to texture |

**Preview rule:** every part preview is live on the car on the turntable, not
an icon. Changing a part plays a one-second swap (old piece drops out, new
one slides in) and the camera cuts to the shot that shows it best (hood from
front three-quarter high, wing from rear low, wheels from side low). Those
six camera presets per car are the same ones the mod tree uses (garage note,
section 2).

## 7. Interiors and gauge clusters (one per car)

Direction from the interiors note is kept: four distinct materials per
cabin, three value steps, amber backlight spill, baked vertex AO. Added here
per car, because each cluster is its own design:

| Car | Dash and seats | Cluster |
|---|---|---|
| T0 Beater | Painted metal dash in body colour, ivory wheel, checked cloth | One big round speedo with a fuel needle inside, red generator lamp, nothing else |
| P1 Coupe | Grey plastic, cloth buckets with silver piping, aluminium pedals | Three deep tunnels: tacho centre and biggest, speedo left, temp/fuel right, amber backlight, orange needles |
| P2 Hot hatch | Red-stitched cloth, upright dash, rally handbrake | Two round dials under a square hood, boost gauge bolted on the A-pillar |
| P3 Tuner sedan | Black, suede wheel, three extra dials in the centre stack | Flat-faced white dials, red redline block, shift light bar on the hood |
| P4 Kei | Tiny bare cabin, body-colour door tops, exposed roll hoop | Single pod: a tacho with a small digital speed window |
| P5 Muscle | Bench-like buckets, wood-look strip, column shifter stub | Long horizontal sweep speedometer, idiot lights, aftermarket tacho on the column |
| P6 Crossover | Rubber floor, grab handles, rally trip computer | Digital bars on a square screen, incline and temperature readouts |

Cluster plumbing is shared (one script reads rpm, speed, fuel, temp from the
car); only the face, needle art and layout are per car, as a small scene
each. The existing HUD bar stays as the fallback when the cockpit camera is
not active.

## 8. Showcase moments

These are where the game *stops to look at the car*. Ordered by what the
player sees first.

1. **Garage turntable** (garage note, section 2): 5 m plate, 30 degree
   steps, idle drift after 4 s, three camera heights. The paint rack is by
   the roller door so paint reads in sun and shade. Already designed; this
   doc only adds that the turntable shot is the *default idle view* of the
   garage so the car is on screen whenever you are not in a menu.
2. **Reveal.** A new car (starter found under the tarp, a crew car won, a
   scrapyard rebuild finished) gets a 6-8 s reveal: dark bay, one work lamp
   swings on, a slow dolly from the rear wheel along the flank to the lamps,
   lamps flick on, hold. Skippable, keyboard only, no text.
3. **Rolling shot before a race.** When a race is accepted, 3 s of a low
   side tracking shot of your car rolling to the line under lamps, then a
   cut to the cockpit. Same camera rig works for the rival's car arriving,
   which is how rival cars get shown off too.
4. **Photo mode upgrades** (already in, `photo_mode.gd`): add a turntable
   orbit lock on your car (O), depth of field toggle (Mobile has a DOF
   effect), time-of-night slider within the current night, a "pop-ups up"
   toggle, and hide traffic. Shots keep grain and the film look.
5. **Pause camera.** The pause menu already circles the car; make the circle
   lower and slower, and keep the lamps lighting the car.
6. **Night-end cutscene.** The 6 am tired drive home already decided: it is
   a 10 s rolling shot of your car under dawn-grey sky, the one time the
   paint is seen in flat light.
7. **Shop wall.** A Polaroid board in the garage: the game pins the last
   photo-mode shot of each car you own. Costs one texture per car.

## 9. What the PS2-gritty night style allows

Keep: flat shading, hard edges with one bevel loop, no normal maps except one
shared grain, film grain, fog, low-contrast fake reflections, blob shadow by
default. Allowed and in style: clearcoat and Fresnel (PS2 racers faked these
with env maps), lamp-rhythm lighting, bloom sprites on lamps, decals,
vertex AO. Not in style: raytraced-looking mirror paint, chrome that
reflects the actual road, sub-surface anything, more than ~6k triangles per
player car. Rule of thumb for every item here: it should look like a
screenshot someone could have taken in 2004 and still think was beautiful.

## 10. Game-wide overhaul: what would have to change, and is it worth it

Roy (2026-10-09): "if you need an overhaul for the entire game I'm not
against it." Honest view per area, with cost in laptop sessions and the risk
of making things worse.

| Area | Overhaul option | What it would buy for the cars | Cost | Risk | Verdict |
|---|---|---|---|---|---|
| Renderer | Switch Mobile to Forward+: real screen-space reflections, real shadows, SDFGI | True reflections of the street in the paint, contact shadows under the car | 2-3 sessions to switch, then every effect retuned | High: Forward+ costs 1.5-2x on Iris Xe at 1080p; the game already fights for 60 fps with traffic. Reflections on this GPU would need low resolution and look smeary | **No.** Fake reflections plus lamp lights (A1, A2) give 80% of the look at near-zero cost, which is also how PS2 games did it. Re-ask after the stress-test session reports headroom |
| Car pipeline | Replace the box and loft generators with an authored-mesh pipeline: a script turns `fleet.json` into a Blender model with bevels, UVs, material slots, named attachment points for parts, exported as glb | Every item in sections 2-7 becomes easier: bevels, decals that fit, parts that bolt on, wear masks, interiors sharing one UV scheme | 3-4 sessions for the pipeline and P1, then 1 per car | Medium: Blender is free and scriptable (GPL tool, output is ours), but the pipeline must run on Roy's laptop or in a cloud session; if it drifts from `fleet.json` the audit checks stop meaning anything | **Yes, this is the one overhaul worth doing.** It is the difference between adding detail per car by hand forever and adding it once. Keep the generator for traffic and police |
| Materials | One car shader for every car (paint, trim, glass, lamp, tyre channels) instead of the P1 shader plus `car_builder._mat` | Paint finishes, Fresnel, wear and lamp lighting work on all cars at once, including rivals and crew cars | 1 session | Low | **Yes**, do it inside A1 |
| Lighting | Real street lamps (omni lights that leapfrog), tonemapping, LUT, lamp glare, wet road | The car is lit like a car at night; paint finishes become visible | Already planned as graphics A1-A9 and B1-B2, 2-3 sessions | Low, measured budget ~1 ms | **Yes**, already decided; just order it before the car work |
| Camera | Chase camera lower and closer with a longer lens, so the car fills more of the frame; cockpit as the default view with a one-key switch | The car is on screen bigger, in every shot | Half a session | Low, but it changes the driving feel Roy signed off in Stage A | **Try it** as a setting (Near / Classic), default Classic until Roy drives both |
| World scale and dressing | Buildings closer to the kerb, parked cars, shop signs, wires, steam, so there is something for the paint to reflect and pass under | Context: a car looks best beside things at human scale | 2-3 sessions, overlaps the buildings and shop-signs work already running | Medium: draw calls on an integrated GPU | **Partly**, through the running buildings and signs sessions; no separate overhaul |
| Art style | Drop "PS2 gritty" for a modern clean look | Nothing for the cars; it would cost the identity | Whole game | Very high | **No** |
| Physics and spec | None needed | The shared sim already makes every car drive differently by data | 0 | 0 | **No change** |

**Recommendation.** Not a whole-game overhaul. Two targeted overhauls, both
under the hood of the art rather than the game: the **car authoring
pipeline** (authored, bevelled, UV-mapped meshes from the same fleet
numbers) and the **lighting pass** already decided. Everything else in this
doc then becomes cheap. If Roy wants one big bet, it is the pipeline: about
four sessions before the first car comes out the other end looking clearly
better, and that is the risk to accept.

Order if approved: lighting A1-A9 (Sonnet, one session) -> pipeline with P1
as the proof (Fable, 3-4 sessions, Opus for the export script design) -> the
A items in section 11 on top of the new P1 -> beater and the rest.

## 11. Sorted by workload, with build order and model

**A: small (build next, each one laptop session)**

| # | Item | What Roy sees | Model |
|---|---|---|---|
| A1 | Paint finish uniforms + Fresnel + fake city reflection band + clearcoat (sections 3 and graphics A4) | Gloss car with sliding warm streaks and navy edges | Fable |
| A2 | Car lit by passing lamps (graphics B2) | Car flashes sodium under every lamp | Sonnet |
| A3 | Lamp lenses and tail signatures for P1 and the beater, pop-up animation | Lamps with depth and a hot centre, pop-ups rising | Fable |
| A4 | Rim family (4 designs), rim colour, brake disc and caliper, brake glow | Wheels with depth, red calipers, glowing discs | Fable |
| A5 | Photo mode: orbit lock, DOF, hide traffic, pop-ups toggle | Better photos of the car | Sonnet |
| A6 | Panel shut lines in the paint mask, stance camber on player cars | Doors and hood read as panels, planted rear | Fable |

**B: medium (one at a time after A, Roy picks the order)**

| # | Item | Model |
|---|---|---|
| B1 | Bevel pass on P1 and the beater, then per car as each lands | Fable |
| B2 | Body-shop parts for P1 (hood, bumpers, skirts/wide-body, wing, tips) with the live swap preview; depends on the garage slice E4a | Fable |
| B3 | P1 and beater interiors with their own clusters (section 7); sets the pattern for the rest | Fable |
| B4 | Reveal and pre-race rolling shot camera rig | Opus for the rig (timing, skip, state), Fable for the shots |
| B5 | Wear mask (primer, rust, scrapes) on the beater and "as found" cars | Fable |
| B6 | Sticker decals in the 4 slots plus vanity plate text | Sonnet |

**C: large (later)**

| # | Item | Model |
|---|---|---|
| C1 | Parts and interiors for P2-P6 (five cars x sections 6 and 7) | Fable, one car per PR |
| C2 | Polaroid board, night-end dawn shot, rival car reveals | Fable |
| C3 | Real shadow under the car as a High option, DOF in the garage | Sonnet |
| C4 | New ladder cars (T1 wagon, T2 drift coupe, T4 mid-engine and rally) each as a full design sheet pass | Fable, with Roy sign-off per car |

Build order: A1 + A2 first together (they are what make every later item
visible), then A3, A4, A6, A5; B2 waits for the garage slice; B3 can start
in parallel on a second laptop session since it touches only cockpit files.

In flight right now and not duplicated here (from project memory): player
cars including the Bug beater (Fable), window roll animation, hands on the
wheel. A1-A6 touch materials, lights and wheels, so they can run beside
those without file clashes except `p1_coupe_builder.gd`, which the player-cars
session owns until it lands.

## 12. Contradictions found

- The fleet sheet lists ride height under swappable body parts; the garage
  note moved it to the Tuner. This doc follows the garage note.
- Interiors note says "colour-blind toggle" in one place; Roy later decided
  no colour-blind setting. Arrows and signs stay.
- Graphics note calls the paint item "A4" and this doc reuses the number for
  wheels; the tables above are this doc's own numbering.

## 13. Questions for Roy (one word each, my pick first)

1. Default paint finish on your car at the start: **gloss**, satin or matte?
2. Should your car flash orange every time it passes under a street lamp? **Yes** / no.
3. Red brake discs that glow after hard braking: **yes** / no.
4. Pop-up headlamps rising with a short animation when you turn lights on: **yes** / instant.
5. A short slow camera reveal the first time you get a new car: **yes** / no.
6. A few seconds of your car rolling to the start line before each race: **yes** / no.
7. Rust and primer patches on the starter beater: **yes** / clean.
8. Wheel rims: **four** designs to start, or two?
9. Rebuild the cars through a proper modelling pipeline (about four sessions before the first better-looking car): **yes** / no.
