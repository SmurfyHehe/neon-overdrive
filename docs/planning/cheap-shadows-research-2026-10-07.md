# Cheap shadows research (2026-10-07)

Status: research only, decision is **not now**. Revisit when other optimisations
free GPU time on the target laptop (i5-1235U, Iris Xe). No code in this PR.

## Where we start

- Renderer is **Mobile** (`project.godot`). That rules out several built-ins.
  Per the Godot renderer table: **no SSAO, no volumetric fog, no built-in
  contact shadows, no SSIL/SDFGI** on Mobile. LightmapGI, decals, depth/height
  fog, glow and CompositorEffects are supported.
- Today's shadows: the moon (`game.gd`, energy 0.2) casts none on purpose. Every
  car gets one radial blob `Decal` (`car_fx.gd`), player and traffic. Lamp light
  is faked with additive pool quads (`road_chunk_builder.gd`), so lamps cast
  nothing either.
- Measured anchors: glow ~0.05 ms, live mirrors ~1.05 ms at 3 traffic cars.
  Every other cost below is an **estimate**, not measured. Each must be A/B'd
  with `benchmark.bat` before it ships.

**Risk found on the way (unverified):** on Mobile only **8 decals apply per Mesh
resource**; extra ones silently don't render. A road chunk is one mesh 50 m
long, so in dense traffic (9+ cars on one chunk) some blob shadows likely
vanish. Worth a headless count test before adding any more decals.

## Options

| # | Technique | Mobile? | GPU cost (est.) | Look gain | Verdict |
|---|---|---|---|---|---|
| 1a | Screen-space contact shadows (custom shader) | Built-in no; custom via depth texture | 0.4-1.0 ms full screen | Low at night, small dark gaps | No |
| 1b | Raycast-informed blob (CPU ray per wheel drives blob size/opacity, darker when close) | Yes | ~0 GPU, tiny CPU | Medium: car "sits" on kerbs, ramps | Yes, cheap add |
| 2a | Lamp-aware blob: second stretched decal pointing away from the nearest lamp, fades between lamps | Yes | ~0.01-0.02 ms per car; player + nearest 4-6 traffic | **High**: shadows sweep under each lamp as you pass | **Best per ms** |
| 2b | Static shadow quads (multiply blend, MultiMesh, like `skid_marks.gd`): building bases, under barriers, alley mouths, under parked cars | Yes, no decal limit | ~0.02-0.05 ms total, one draw call per chunk | Medium-high: world feels grounded | Yes |
| 3a | SSAO | **Not on Mobile** | Forward+ switch costs more than any shadow here | High in day, low at night | No |
| 3b | Baked vertex AO / AO in textures (the approved baked-shading pass) | Yes | 0 ms | High on buildings, interiors, cars | Do first, already approved |
| 4a | Volumetric fog / light shafts | **Not on Mobile** | n/a | n/a | No |
| 4b | Fake light cones: additive, unshaded, fresnel-faded cone under each lamp, MultiMesh | Yes | 0.1-0.3 ms (overdraw near camera) | High: defines light, so dark reads as shadow | Yes, cap count |
| 4c | Height fog tuned low and dark | Yes | ~0 | Medium: alleys and road edges sink into dark | Yes, just settings |
| 5 | LightmapGI per hand-built location (garage, gas station, landmarks) | Yes | ~0 ms runtime, a few MB VRAM | **High** inside those places | Yes when those scenes exist; not for procedural road |
| 6a | Shadowed moon: 1 cascade, max distance 40 m, cars only | Yes | 0.4-0.8 ms at 16 cars | Low: moon is 0.2 energy | No |
| 6b | One shadowed "hero lamp" omni near the player | Yes | 0.5-1.5 ms (cube shadow) | Medium, but pops between lamps | No |

Notes:

- **1b** reuses the wheel raycasts the sim already does; no new physics.
- **2a** is the classic racing-game trick. Driving under a sodium lamp, the car's
  shadow stretches out ahead, swings round and shortens as the lamp passes. The
  lamp positions are already known (fixed spacing per chunk), so the nearest
  one is a cheap lookup. It must respect the 8-decal limit: player always,
  traffic only within ~30 m.
- **2b** should be generated in `road_chunk_builder.gd` next to the lamp pools,
  so it follows the road automatically, including future curves and
  elevation.
- **5**: lightmaps need UV2 and a bake on Roy's laptop; dynamic cars get no
  shadow from baked lights, so the blob stays. Baking lets us delete the real
  lights in those scenes, which can make them cheaper than today. Vertex-colour
  baking is the PS2-faithful alternative if UV2 is a pain.

## Use cases

- **Under lamps:** 2a (car shadow swings with each lamp) + 4b (visible cone
  makes the pool read as light) + the existing pool quad.
- **Behind buildings:** 3b (darkened building bases and recesses) + 2b (dark
  strip on the sidewalk along the base, darker in the gaps between buildings).
- **On terrain** (when curves and elevation land): decals project onto slopes
  for free; 2b quads must be built on the terrain mesh by the chunk builder;
  lightmaps don't apply to procedural road.
- **Gas station, garage, landmarks:** 5 (baked lightmap or vertex bake) + blob
  for cars, so the hand-made places look the most lived-in.

## Recommendation

**Zero-ms tier (do regardless of budget, part of normal art work):** 3b baked
vertex AO, 4c height fog, 5 baked lighting for each hand-built location.

**"If we had 0.5 ms to spare":**

| Item | Budget |
|---|---|
| 2a lamp-aware blob, player + nearest 4-6 traffic | 0.10 ms |
| 2b static multiply shadow quads per chunk | 0.05 ms |
| 4b fake light cones, nearest ~12 lamps only | 0.25 ms |
| 1b raycast-informed blob | ~0 GPU |
| Headroom for measurement error | 0.10 ms |

Skip SSAO, volumetrics, real shadow maps and contact shadows: on Mobile they
are unavailable or cost more than the whole budget for little visible change
at night.

## Before building any of it

1. Headless test: count cars per road chunk in heavy traffic and confirm the
   8-decal limit drops blobs (if so, fix that first, e.g. traffic blobs as
   multiply quads instead of decals).
2. Each item behind its own `FxSettings` flag, A/B'd with `benchmark.bat` on
   Roy's laptop at 16 traffic cars; ship only if it stays inside its budget.
3. Roy signs off the look from screenshots before any second item is built.

Source for renderer limits: Godot docs, "Overview of renderers" and "Using
decals" (godot-docs master, read 2026-10-07).
