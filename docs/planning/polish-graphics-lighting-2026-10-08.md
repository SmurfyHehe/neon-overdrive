# Polish research: graphics and lighting (2026-10-08)

Docs only, nothing built. Scope: what would make the night city look better on
Roy's laptop (i5-1235U, Iris Xe, 1080p, Godot 4.7 **Mobile** renderer), ranked
by workload: **A** = small (one build session), **B** = medium (1-3 sessions),
**C** = large.

Sources checked: `origin/main` 09455e0 (`scripts/game.gd:97-180`,
`scripts/car_fx.gd`, `scripts/road_chunk_builder.gd`, `project.godot`,
`RESEARCH-cheap-pretty.md`, `docs/audit-2026-10-06.md`), screenshots in the
project folder (`chase_1.png`, `moon_in_game.png`,
`buildings_contact_sheet.png`), the Godot docs (sources at the end) and web
research.

**About the fps numbers.** Every cost below is an *estimate* for 1080p on Iris
Xe, from the Godot docs and how much screen each effect touches. None is
measured. Each item must be measured in the exported build with
`benchmark.bat`, warm, with traffic on, before it ships. Two facts make this
matter more than usual:

- The game is already **CPU-bound** by traffic physics (7-14 ms per tick at
  18-22 full-sim cars, `docs/audit-2026-10-06.md:84`).
- On a 15 W chip the CPU and GPU **share one power budget**. Extra GPU work
  lowers CPU clocks, so a "GPU-only" effect can still slow the physics. Graphics
  polish is not free just because the GPU looks idle.

---

## What the current look is missing (from the code and screenshots)

| What you see | Why (code) |
|---|---|
| Flat, slightly muddy image; lamp pools and the headlight beam clip to flat orange | No tonemapper set, so Godot uses **Linear** (`game.gd` never sets `tonemap_mode`) |
| Jagged lane lines, poles and building edges | **No anti-aliasing** in `project.godot` |
| Car paint looks like brown plastic; no shine or reflections | Nothing to reflect: the sky is near-black and there is no reflection probe; materials have no clearcoat (`car_builder.gd:189`) |
| The car stays dark when it drives under a street lamp | Lamps are fake (glowing quad on the road, `road_chunk_builder.gd:68-71`), so they light the road but never the car |
| Road reads as dry matte noise | Asphalt is roughness 0.9 noise (`road_chunk_builder.gd:213-224`); no wet sheen or light reflections |
| Buildings are plain dark boxes with a window grid | One window texture for all, no ledges, roofs, shopfronts or texture |
| Street is empty near the camera | No parked cars, bins, wires, traffic lights or steam |
| Car floats a little | Blob shadow only (`car_fx.gd:40-48`); fine at distance, weak up close |

What already works and should be kept: the near-black sky with the low orange
city glow, the moon, the tight glow (0.05 ms, `game.gd:134-148`), film grain,
the 12.5 m lamp rhythm, the fog swallowing the distance.

### Mobile renderer limits (Godot docs, renderers page)

Not available on Mobile: screen-space reflections, SSAO, SSIL, SDFGI,
volumetric fog, TAA, FSR2, contact shadows. Available: tonemapping incl. AgX,
glow, colour adjustments + LUT, MSAA, FXAA, SMAA, FSR1 resolution scaling,
decals, light projector textures, reflection probes (8 per mesh), up to 8
omni + 8 spot lights per mesh. So every reflection and shadow trick below is a
"fake" one, which is also what PS2-era racers did.

---

## A: small, recommended to build now

| # | Item | What Roy would see | Est. cost | Notes |
|---|---|---|---|---|
| A1 | **Tonemapping** (Filmic or AgX) + exposure | Lights glow and fade into the dark instead of clipping to flat orange; richer blacks | ~0.05-0.1 ms | One property. AgX keeps colours truer when bright; on Mobile its "white" is fixed at 2.0. Compare Filmic vs AgX side by side |
| A2 | **Anti-aliasing**: SMAA default, FXAA/MSAA 2x as options | Clean lane lines and poles, no crawling edges | SMAA ~0.3-0.6 ms, FXAA ~0.2 ms, MSAA 2x ~0.5-1.5 ms | SMAA is less blurry than FXAA at 1080p (Godot docs). Add the screen-space roughness limiter (Mobile supports it) to calm sparkly highlights |
| A3 | **Colour grade** with a LUT | One consistent "film" look: amber highlights, blue-navy shadows, red/blue only where lights are | ~0.05 ms | Environment `adjustment_color_correction`, one texture lookup. LUT made by us = no licence issue |
| A4 | **Fake city reflections on car paint** + clearcoat | The car body shows streaks of warm lights and a glossy top coat | ~0 per frame | The sky shader draws a band of fake city lights **only into the reflection pass** (`AT_CUBEMAP_PASS`), so the visible sky does not change. Add `clearcoat` to paint and dark reflective glass |
| A5 | **Headlight beam shape** | A real beam with a bright centre and a hard cut-off line on the road, instead of a round blob | ~0.1 ms | SpotLight `light_projector` texture (Mobile supports it). Optional faint beam cone in the fog (additive mesh) |
| A6 | **Lamp glare** | Each street lamp has a soft halo in the haze; lamps read as lights, not yellow boxes | ~0.1 ms | Camera-facing additive sprite per lamp head, in the existing lamp MultiMesh |
| A7 | **Softer lamp pools** | Light pools fade naturally and overlap, no visible oval edges | ~0 | New gradient texture for the existing pool quad |
| A8 | **Resolution scale with FSR1** (setting) | Nothing, unless the laptop struggles; then a sharp image at fewer pixels | Saves ~20-40% GPU at 0.77 scale | Mobile supports FSR1. Gives back headroom for A2-A6 |
| A9 | **Graphics quality setting** (Low/Medium/High) in pause menu | One switch to trade looks for speed | 0 | Extends `FxSettings`; groups A2, A8 and later B items |

A1-A9 together: est. **~0.6-1.2 ms** per frame before A8's savings. That fits
the 8-10 ms GPU budget in `RESEARCH-cheap-pretty.md`. Suggested model: Sonnet
(mechanical settings work), Fable for judging the final look if available.

---

## B: medium (for Roy to decide)

| # | Item | What Roy would see | Est. cost | Notes |
|---|---|---|---|---|
| B1 | **Wet road** (fake, PS2 style) | Shiny dark asphalt with long streaks of lamp, sign and tail-light reflections stretching toward you; dry patches in between | ~0.3-0.8 ms | The single biggest genre win (NFS Underground 2 look). Road shader: darker albedo, low roughness in a world-space puddle mask, Fresnel. Plus stretched additive "streak" quads under each lamp/sign and each traffic light (MultiMesh). No second camera |
| B2 | **Car lit by passing lamps** | Your car flashes warm orange every time you pass under a lamp; the classic night-drive rhythm | ~0.2-0.5 ms | 2-4 real OmniLights that leapfrog to the lamps nearest the player, lighting only the car layer and nearby road. Stays under the 8-lights-per-mesh limit |
| B3 | **Baked darkness in corners** | Building bases, wall joints and kerbs get soft dark edges; the world looks solid, less "floating boxes" | ~0 | Vertex colours written by `road_chunk_builder.gd` at build time (SSAO is not on Mobile). Same idea as RESEARCH item 2 |
| B4 | **Better buildings** | Textured walls, ledges, rooftop water tanks, AC units, antennas; shopfronts with lit rooms behind the glass; more lit signs (red and blue now allowed) | ~0.2-0.5 ms | Free textures from Poly Haven / ambientCG (both **CC0**: free, commercial, no credit). "Fake room" window shader = depth without geometry. Overlaps the living-world windows phase (L1) |
| B5 | **Street clutter** | Parked cars, bins, bags, traffic lights at junctions, overhead wires, steam from drains | ~0.3-1 ms | MultiMesh with 60-120 m visibility range. Parked cars reuse NPC meshes |
| B6 | **Car material pass** | Tinted glass, rubber tyres, light lenses with a reflector inside, brake lights that bloom | ~0 | Material values only; no new models (cars held for Fable redesign) |
| B7 | **Skyline layers** | Distant towers with lit windows and blinking red aircraft lights against the orange glow | ~0.05 ms | Drawn in the sky shader, no geometry |
| B8 | **Real car shadow** as a High-only option | Sharp shadow under the car from the headlights of cars behind / the moon | ~0.5-1.5 ms | One shadow map, short distance (30 m), 1 split. Keep the blob as default |

---

## C: large (for later)

| # | Item | What Roy would see | Est. cost | Notes |
|---|---|---|---|---|
| C1 | **Rain** | Falling rain, drops and wipers in the cockpit, ripples in puddles, spray from tyres | ~1-2 ms | Needs B1 first. Fits "some nights" weather |
| C2 | **Try the Forward+ renderer** | Real screen reflections, ambient occlusion, volumetric fog, TAA | Unknown; likely +2-5 ms base on Iris Xe | The *test* is small (one setting + a benchmark run); the *switch* is large (everything re-tuned). Only worth it if the test shows headroom |
| C3 | **Mirror-camera road reflections** | Perfect reflections in puddles | Roughly a second full scene render | Not recommended on this laptop; B1 gets most of the look |
| C4 | **New car models / cockpit art** | Better cars | n/a | Already held for the Fable redesign (memory); listed for completeness |

---

## Reference games (what to steal)

| Game | Look to borrow | Link |
|---|---|---|
| Need for Speed Underground 2 (2004) | Wet road with stretched light streaks, glow, light trails | [Wikipedia](https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2) |
| Midnight Club 3 (2005) | Dense lit storefronts, near-field clutter | [Wikipedia](https://en.wikipedia.org/wiki/Midnight_Club_3:_DUB_Edition) |
| Tokyo Xtreme Racer (2025) | Highway lamp rhythm; car body lit by each passing lamp | [Wikipedia](https://en.wikipedia.org/wiki/Tokyo_Xtreme_Racer_(2025_video_game)) |
| Night-Runners (indie, PS2 style) | Simple environments + detailed cars; VHS filter | [review](https://geeksleeprinserepeat.com/2024/02/29/night-runners-is-for-all-those-tokyo-xtreme-racer-fans/) |
| GTA V | Headlights adding highlights on wet roads; low-res planar reflections only on water/mirrors | [graphics study](https://www.adriancourreges.com/blog/2015/11/02/gta-v-graphics-study-part-2/) |

I did not embed screenshots: they are copyrighted. Search each title + "night"
for images.

**How the PS2 games did wet roads** (gamedev.net thread with a PS2 developer):
a noisy puddle mask, a low-poly flipped copy of nearby bright objects, and
light streaks drawn downward only inside the puddles. **Real-world rule**
(fxguide, Nakamae road model): wet asphalt is ~0.1-0.3x darker and 5-10x
shinier; streaks get longer the lower your view angle; rougher wet = dimmer,
wider streaks.

---

## Recommendation

1. **Build A1-A9 now** in one laptop session, then show Roy before/after
   screenshots and the benchmark number with traffic on.
2. **Next: B1 wet road + B2 car lit by lamps.** Together they are most of the
   "night street racer" look, est. ~0.5-1.3 ms.
3. Then B3 + B4 + B5 (the world looks built, not blocked out), as one
   environment pass.
4. Run the C2 Forward+ test once, early, just to know the number. Do not switch
   without it.

**Premortem.** (a) Costs are estimates; the 15 W shared budget could turn
1 ms of GPU into lost physics time. Mitigation: benchmark with traffic after
each item; every item gets an off switch. (b) Tonemapping changes every colour
already tuned (markings, windows, pools). Mitigation: re-tune exposure first,
compare screenshots before touching anything else. (c) Wet road can make the
lane markings hard to read at speed. Mitigation: keep markings out of the
puddle mask.

**Contradiction to flag.** Project instructions still say "no magenta/cyan;
police blue is the only off-palette colour". Memory says Roy expanded the
palette on 2026-10-08 (red and blue allowed). This doc assumes the expansion;
magenta and cyan stay out.

---

## Questions for Roy (one word each; my pick in brackets)

1. Should the road look rain-wet **every night, some nights, or never**? [some nights]
2. Should your car light up orange as it passes under each street lamp? [yes]
3. Default: **smoother edges** or **more speed**? (both stay in settings) [smoother]
4. Real shadow under your car, or keep the soft dark patch? [patch, real shadow as a High option]
5. Add an old-TV/VHS filter like Night-Runners on top of the grain? [no]
6. More lit shop signs in red and blue? [yes]
7. Falling rain with wipers later on? [yes, after wet roads]

---

## Sources

- Godot docs (master): renderers feature table, environment and
  post-processing (tonemappers, AgX), reflection probes, resolution scaling,
  3D anti-aliasing, decals:
  <https://github.com/godotengine/godot-docs/tree/master/tutorials>
- [Godot glow slowdown on Mobile, godot#98531](https://github.com/godotengine/godot/issues/98531) (already measured fine in-game: 0.05 ms)
- [fxguide: making wet environments](https://www.fxguide.com/fxfeatured/game-environments-partc/)
- [gamedev.net: reflection on wet street at night](https://gamedev.net/forums/topic/280855-reflection-on-wet-street-at-night/)
- [GTA V graphics study part 2](https://www.adriancourreges.com/blog/2015/11/02/gta-v-graphics-study-part-2/)
- [Arm: optimizing 3D scenes in Godot](https://developer.arm.com/community/arm-community-blogs/b/mobile-graphics-and-gaming-blog/posts/optimizing-3d-scenes-in-godot-on-arm-gpus)
- [Poly Haven licence (CC0)](https://polyhaven.com/license), [ambientCG licence (CC0)](https://docs.ambientcg.com/license/)
- [Night-Runners review](https://geeksleeprinserepeat.com/2024/02/29/night-runners-is-for-all-those-tokyo-xtreme-racer-fans/)
