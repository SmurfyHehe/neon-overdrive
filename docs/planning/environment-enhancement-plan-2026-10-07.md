# Environment enhancement plan (2026-10-07)

Proposal only. No code. Roy prioritises, then each chosen item gets its own PR.
Sizes: **S** = one small PR, **M** = one focused session plus a perf check, **L** = several PRs or an architecture change. No calendar estimates (the dispatcher can't see how long CI or review takes).

## Premise (steelman and premortem)

- **Steelman:** the road is the game's stage. Stage A made it dark and coherent; "alive" now means light that reacts, surfaces that look used, places that mean something, and things that move that aren't us. Most of that is cheap if built as data in the chunk builder.
- **Premortem:** (1) we chase "next-gen" with real-time lights and shadows and the i5-1235U / Iris Xe drops under 60 fps (traffic is already full-sim). (2) We add clutter that fights the sightline and the Amber vs. Dusk palette, so it reads as noise. (3) We build props for an endless straight road, then curves and elevation (#37) force a rewrite. Mitigation: fake light with additive decals and emissives, budget every item in ms, and put prop placement behind one function that the Path3D rework can reuse.
- **Palette note:** the brief said "neon glow". Memory says no neon, no magenta/cyan. This plan reads it as **sodium and amber glow only**.
- **Locations (Roy, 2026-10-07):** the garage is primary HQ. Gas stations and other places are destinations spread across the districts, and they anchor narrative. Treated as item 8.

## Current state (read from `main` 9c28d59)

| Area | What is there now | Gap |
|---|---|---|
| Lighting | One dim cool `DirectionalLight3D` moon (0.2, no shadows). Ambient from the sky at 0.3. Street lamps are MultiMesh meshes; their light is a **fake additive pool quad** on the road, zero lighting cost. Player headlights plus a blob shadow. Flames use one pooled OmniLight. Glow on levels 0-2, about 0.05 ms. | Lamps light nothing but the road decal: no light on cars, walls, signs or rain. No lit-haze around lamps. Headlights don't throw onto roadside objects. No shadows anywhere (deliberate). |
| Materials | 64 px noise asphalt in three greys. Concrete curb, sidewalk, barrier, gap walls as flat colours. Buildings: dark flat colour plus a 32 px window mask (triplanar, world space, nearest filter). | No wear: no cracks, patches, oil, tyre-lane polish, rust, graffiti, grime. Road paint is clean. No wet or specular response, no reflection source, so glass and puddles can't read. Buildings are identical boxes. |
| Props | Lamps, delineator posts, concrete barrier, gap walls, buildings (12% tagged "garage", not wired). | No signs, fences, hydrants, bins, cones, dumpsters, bus stops, guard rails, wires, trees, scrub, debris. |
| Ambient life | Traffic only (full-sim cars). Radio. | No pedestrians, no parked cars, no lit interiors, no sound beds from the world (hum, distant sirens, wind in wires). |
| Sky and atmosphere | `ProceduralSkyMaterial`, near-black top, sodium horizon glow. Exponential fog 0.009, warm dark. Film grain, vignette, speed lines. Moon phasing and a fog-vs-sky check are **in progress in another thread**. | Sky has no stars, clouds or city-glow dome shape. No time-of-day change. No weather. |
| Track | Flat plane, straight road, lane count tapers. Ground is one infinite plane. Curves and elevation are proposed in their own thread (#37). | Nothing beyond the road reads as terrain. Road surface is flat and uniform. |
| Renderer and budget | `mobile` renderer, 120 Hz physics, shadows off, glow on, MSAA not set in project (checked `project.godot`). | No measured frame budget for new work. `benchmark.bat` exists; the exported exe has not been timed on Windows. |

## Proposal by area

Cost column is the expected hit on Iris Xe, to be measured with `benchmark.bat` per PR.

### 1. Lighting
| Item | What | Cost | Size |
|---|---|---|---|
| 1a Lamp haze | Additive billboard glow sprite on each lamp head (extra MultiMesh), fog-friendly. Makes lamps "bloom" in the distance with no real light. | Very low | S |
| 1b Light on cars | Lamp pools also tint car bodies: a vertex-height shader term or a fixed warm rim from the nearest lamp, driven by one uniform array of the next ~4 lamp positions. | Low | M |
| 1c Pooled real lights | 2-4 OmniLights recycled onto the nearest lamps (no shadows). Gives true light on walls, signs and cars. Only if 1b looks fake. | Medium: Mobile limits lights per object | M |
| 1d Headlight throw | Make the headlight cone hit roadside props and lane paint, with a wet-road streak if rain lands. | Low-medium | S |
| 1e Shadows | One shadow-casting light is a full extra pass. **Recommend not doing.** Keep the blob shadow. Revisit only on a measured spare millisecond. | High | skip |
| 1f Baked vertex light | Write warm/cool vertex colours in the chunk builder: darker under overpasses, warmer near lamps, darker at wall bases. The single best "free" lift (RESEARCH-cheap-pretty item 1). | Zero runtime | M |

### 2. Shaders and materials
| Item | What | Cost | Size |
|---|---|---|---|
| 2a Road wear | Second texture layer (world-space, seamless): cracks, patches, oil, polished tyre lanes, paint wear. One material, so no extra draw calls. | Low | M |
| 2b Wet road variant | Roughness and reflection tint from a cheap fake (sky colour plus lamp streaks as emissive strips). Ties into weather (5c). | Low | M |
| 2c Building variety | 6-8 building variants through the existing triplanar material: different window masks, rust and grime ramps, roof lines, graffiti decals as unlit quads. | Low | M |
| 2d Glass | Fake reflection: a small cube-map from the sky shader plus a lamp-streak texture. No SSR, no probes. | Low | S |
| 2e Road paint | Worn, broken edge lines; stop bars and arrows at junctions and stops; reflective cat's-eye dots (emissive MultiMesh). | Very low | S |

### 3. Environmental detail
Everything is MultiMesh placed by seeded RNG per chunk, with `visibility_range` cutoffs at 40-80 m. Detail kit, ordered by read value at speed:
1. Signs: road signs, shop signs, gantries (lit by a pooled amber emissive). **M**
2. Fencing, guard rail, jersey barriers, cones, bins, dumpsters, hydrants. **M**
3. Overhead wires, billboards, utility poles. **S**
4. Dead scrub, weeds in cracks, a few bare trees on the outer edge (billboard cards, not meshes). **S**
5. Debris: bags, cans, tyre skids already exist. Small instanced scatter. **S**

Budget rule: **under 20 added draw calls** per chunk set, and a prop-density slider in Settings (low / normal / high) so the laptop can opt out.

### 4. Ambient life
| Item | What | Cost | Size |
|---|---|---|---|
| 4a Lit windows that change | Per-building random window flicker and TV glow via a time-offset in the emission mask. Shader-only. | Very low | S |
| 4b Parked cars | Static NPC-car variants from the existing fleet at the kerb. No sim, collision only. | Low | M |
| 4c Pedestrians | Silhouette figures (sprite or 40-tri mesh), few, near stops and shops only. No pathing. | Low | M |
| 4d Sound beds | Transformer hum near poles (reuses `perspective_audio`), distant sirens, wind in wires, dogs. Needs the anti-repetition rule from memory. | Low | M |
| 4e Dialogue and chatter | Radio/Dale lines tied to district and landmark triggers. Story-owned; Roy writes. | Zero GPU | L (content) |
| 4f Moving background | Distant lit plane, train, or crane lights beyond the walls, on a loop. | Low | S |

### 5. Sky and atmosphere
| Item | What | Cost | Size |
|---|---|---|---|
| 5a Sky dome | Stars, a city-glow dome that tints with district, a phasing moon (**already being built in the moon thread; do not duplicate**). | Very low | S after the moon PR |
| 5b Height fog | Switch to `fog_height` style layered haze, denser low and over the harbour, thinner on the freeway. Check against the moon thread's fog-vs-sky finding first. | Low | S |
| 5c Weather | Light rain (particles only near camera, wet road 2b, wiper-free windscreen drops later), fog bank, clear. Per-district weather presets. | Medium for rain particles; cap them | M-L |
| 5d Time variation | Dusk to deep night to pre-dawn sweep over a session: sky colours, lamp on/off, window count. Keep "night" as the baseline; do not add a day. | Very low | M |

### 6. Track modernisation
- **Curves and elevation** are the Path3D rework already proposed in its own thread. Everything in 1f, 2a, 3 and 4 depends on one placement function, so route placement through it now (**S refactor**) and the rework does not orphan the props.
- **Outer terrain:** replace the infinite plane with a cheap shaped ground (verge, ditch, dirt) near the road and fade it into fog beyond. **M**
- **Surface detail:** crown and camber (needs the Path3D work), seams, manhole covers, expansion joints as physics-neutral decals. **S**
- **Districts as palettes:** the same kit re-dressed per district (Docks: containers, cranes; Downtown: tall lit grid; Cutter Canyon: rock walls, guard rail; Route 9: gantries; Airstrip: runway lights). **L** in total, **M** per district.

### 7. Priority and recommended first moves

**Essential for the "alive" feel (do first):**
1. **1f baked vertex light** + **2a road wear** + **2e worn paint**: surfaces stop looking like clean primitives. Near-zero runtime cost.
2. **3 detail kit, items 1-2** (signs, fences, cones) + **1a lamp haze**: the roadside has things in it.
3. **5a/5b sky and height fog** (after the moon thread merges): atmosphere that fits the palette.
4. **8 landmark kit** (below), so places exist for the story.

**Strong second wave:** 2b wet road + 5c rain, 4a lit windows, 4d sound beds, 4b parked cars, 1b/1c light on cars, 2c building variety.

**Nice to have / later:** 4c pedestrians, 4f moving background, 5d time sweep, 1d headlight throw, 2d glass reflections, outer terrain, per-district palettes.

**Skip:** real shadows, SSAO/SSR/SDFGI (not on the Mobile renderer, and heavy), volumetric fog.

### 8. Locations and landmarks (added from Roy's note)
- **The Garage is primary HQ** (Dunmore Auto in the story bible). It needs a distinct, recognisable exterior and a lit forecourt: the one place with warm real light and a sign, so the player always knows "home".
- **Other places are destinations**: gas stations, shops, a diner, a scrapyard, a car park. Each is a **landmark kit** built from the same MultiMesh props plus one unique silhouette piece, placed on a road side. The existing 12% "garage" building tag is the hook the code already reserves; it is not wired.
- A landmark has: a sign, a lit forecourt (one pooled real light), a sound bed, a trigger zone (for stops, story beats and radio lines), and a district palette.
- Gas stations are one landmark type among several, **not** the centre of the plan.
- Size: first landmark kit (Garage + one gas station) **M**; each further type **S** once the kit exists.

## Budget and measurement
- Every PR reports ms/frame from `benchmark.bat` on Roy's laptop against the previous main, with traffic at the default 40 cars.
- Target: **no more than 1.5 ms total added** across lighting, materials, props and ambient life, and draw calls under 100 as the research doc targets. Anything above that gets a Settings toggle.
- The exported exe has never been timed on Windows by an agent; the first PR in this plan should include that run.

## Open questions for Roy
1. Is rain/weather in scope for the first wave, or after the Stage C run loop?
2. Do you want the time-of-day sweep (night to pre-dawn), or does it stay one fixed night?
3. Which landmark types after Garage and gas station: diner, scrapyard, car park, shop?
4. Is per-district re-dressing wanted before the Path3D rework, or after?
5. Is "no real shadows ever" an agreed rule, or only "not now"?
