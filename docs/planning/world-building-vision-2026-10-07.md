# World-building vision: a city that is awake at 3 a.m.

Status: proposal for Roy's sign-off. No code until approved. 2026-10-07, main `9c28d59`.

**One line:** Harlow Bay should feel like a working port city on the night shift. That means tired but awake, lit by sodium, wet and worn, with people and machines going about their night just off the road. It should never feel like an empty highway in a void.

## Where we are today (checked in code)

- Fixed night: a procedural sky from black to a sodium horizon, warm depth fog at 0.009, and a dim "moon" light (`scripts/game.gd:105-169`). The renderer is **Mobile** (`project.godot:21`), so SSR, SSAO and volumetric fog are not available.
- The road is one straight 4+4-lane highway. It has sodium lamps (emissive heads plus fake light-pool quads, no real lights), and box buildings with lit-window textures and gap walls (`scripts/road_chunk_builder.gd`).
- Traffic is 16 full-sim coupes in 8 colours, with no headlights or tail lights (`scripts/traffic_car.gd:233`). There are no parked cars, no pedestrians and no props, signs or decals.
- **Why it feels dead:** every 50 m looks the same, nothing exists off the road, and no light moves except yours.

## 1. Atmosphere: "lived-in" kit

All of it is MultiMesh, added inside the road builder's pooled chunks. ★ = essential.

| Layer | Items |
|---|---|
| ★ Light that tells a story | About 15% of lamps dim, 5% flicker, 3% dead (dark gaps). Slight sodium colour drift between lamps. Broken traffic lights blinking amber. |
| ★ Ground | Asphalt patches, tar snakes, oil stains, manholes, puddles, all as alpha quads. |
| ★ Buildings | Grime on the lower third and streaks under windows. Roller shutters on shop buildings. Rooftop AC units, water tanks and antennas with red aviation dots. |
| ★ Signs (no neon) | Backlit plastic boxes and front-lit billboards in amber or warm white with block lettering: TIRES, 24 HR, PAWN, CHECKS CASHED. Plus in-world brand placeholders, for example an oil brand, the shop's faded banner, the port authority, and "Graveyard TV". |
| ★ Skyline | Power lines and poles, plus a skyline impostor ring behind the fog with lit windows and a refinery flare. |
| ★ Sound beds | Lamp buzz as you pass, AC hum, a distant train horn, a dog every 30-60 s, rare far sirens, and a district loop such as dock creaks or downtown bass. |
| Nice | Graffiti in palette (silver, orange, navy, white). Litter that gusts in your wake. Steam vents backlit by lamps. Moths around lamps. Chain-link, dumpsters and pallets. Overpass shadow bands. |

## 2. Destinations: the world's anchors

The **Garage is HQ** (primary hub). Every other destination is a small set piece just off the road, and each has three jobs:
- **A mechanical purpose:** why you stop there.
- **A story hook:** a placeholder only, since Roy writes the story.
- **A person:** who you meet. These are roles, not names.

| Place | Purpose | Hook (placeholder) | Who's there |
|---|---|---|---|
| **Garage HQ** | Save, tune, mods, car swap, repairs, event board | Overdue notices on the desk, a crew photo wall that fills up, and Graveyard TV's rig in the back room | Shop owner, crew, the DJ's setup |
| Gas station | Refuel, quick fix, rumour board, cool-down | The night clerk hears things | Clerk, random drivers |
| Parking-garage meet | Downtown meets, car show, challenge entry | A board listing drivers to beat | Organiser, rival crews |
| Docks / container yard | Docks strips, hauler jobs, meets | What's in the containers? | Foreman, rival muscle |
| 24 h diner | Crew hangout, rest/save, callback point | A regular who watches the door | Waitress, a rival's scout |
| Scrapyard | Parts, salvage, mod-tree unlocks | An old wreck in the corner | Parts dealer |
| Radio tower | Signal missions, DJ lore | Why the signal must stay hidden | (DJ, voice only) |
| Overpass / tunnel | Freeway-run start, speed trap | Scorch marks and old flowers | Spotter |

**Build first:** Garage HQ, then the gas station, then the meet garage. The gas station's prop kit (canopy, price pole, pumps) gets reused by the rest.

These destinations match the story-bible districts: Docks, Downtown, Cutter Canyon, Route 9 and the Airstrip.

## 3. "Higher generation" look on Iris Xe

The jump comes from **light, wetness and density**, not polygons. Ranked by payoff per GPU millisecond:

1. ★ **Render scale 0.67-0.75**, which is not set today. It saves 30-45% of fill rate and pays for everything below. The softness reads as PS2 under the grain.
2. ★ **Fake wet road:** stretched additive reflection streaks under lamps and tail lights, with asphalt roughness lowered from 0.9 to about 0.55. About 0.3 ms. This is the single biggest "night city" cue.
3. ★ **Tonemapper (AgX/Filmic) plus a colour-grade LUT** locked to Amber vs. Dusk. About 0.1 ms. This makes everything read as one palette.
4. ★ **Light-shaft cone cards under lamps plus height fog**, as a cheap stand-in for the volumetric fog that Mobile lacks. About 0.3 ms.
5. ★ **Emissive head and tail lights plus glare cards on traffic**, with no real lights. About 0.1 ms.
6. **Baked vertex AO** at curbs, building bases and the median. About 0 ms. Needs Roy's OK: it is RESEARCH item 2, which is not yet approved.
7. Grime quads (not Decal nodes, which cut out on 50 m strips on Mobile), and the skyline impostor.
- **Skip:** real lights per lamp, shadow maps, switching to Forward+ (about 2-4 ms more), and PS2 vertex jitter.

## 4. Ambient life: the "not dead" minimum

These are ranked by life per cost. Full-sim traffic is the expensive one at 0.19-0.36 ms per car per tick (`scripts/traffic_settings.gd:13-21`).

1. ★ Parked cars on shoulders and lots (static MultiMesh), a few with dim interior lights.
2. ★ Far-road headlight and tail-light sprites on a parallel freeway and cross streets, about 200 billboards at near-zero cost.
3. ★ Lit kinematic cars at 150-300 m, beyond the full-sim ring. This reuses the existing frozen `_cruise()` path.
4. ★ Windows that switch on and off slowly through the night.
5. Varied bodies (N1-N3 are already planned), plus a few buses, trucks and taxis.
6. Pedestrian impostor cards **at destinations only**: 10-30 per place, never along the highway.
7. Static tableaux: an idling cop, a racer meet. These are best saved for Stage F (heat).

**Iris Xe caps:**
- Physics and traffic ≤ 8 ms per frame. Full-sim cars stay around 10-12 by default, with 16 as the upper end.
- At most 4 real lights at once, no shadows.
- ≤ 350 draw calls.
- ≤ 2,000 particles.
- Target 60 fps.

These are estimates. Each one gets measured with the headless benchmark before it ships.

## 5. Time and weather

- **A night that advances across a session**: dusk navy, then 2 a.m. black, then pre-dawn blue. There are 3-4 presets that crossfade fog, colour grade, lamp and window density, and traffic volume. It is not a free-running cycle, and there is **no daytime**, because day fights "Gritty PS2 night" and the night-shift story.
  - Each hour gives hooks: busy streets at dusk, meets at midnight, empty touge runs at pre-dawn, the DJ's patter changing by hour, and cops later.
- **The phasing moon** sets each night's brightness: a full moon is brighter and safer, a new moon is darker. It stays below the sodium lamps so the look never turns blue.
- **Fog/mist:** near-free presets. Nice-to-have.
- **Rain:** wetness drives the reflection streaks already listed in section 3. Add a screen-streak pass or one camera particle emitter, tyre hiss, and lower grip through the existing `grip_mult` hook (`gevp_wheel.gd:66`). **Phase 2**, after the wet-road look proves itself.

## Scope and phases (each one: propose → Roy signs off → build)

Size is a rough relative effort, not a time estimate.

| Phase | Contents | Size |
|---|---|---|
| **W1: Look pass** | Render scale, tonemap and LUT, fake wet road, lamp cones and height fog, traffic light cards, lamp variety | Small to medium |
| **W2: Dressing kit** | Ground grime, shutters, plastic signs, power lines, rooftop clutter, skyline ring, sound beds | Medium |
| **W3: Life** | Parked cars, far-road sprites, kinematic mid-ring, window timers | Medium |
| **W4: Night arc** | Hour presets plus the phasing moon (the moon session is already working), fog presets | Small |
| **W5: Destinations** | Garage HQ set, then the gas station, then the meet garage. Gated by Stage E (garage) | Large |
| Later | Rain plus wet grip, pedestrians at destinations, buses and trucks, cop tableaux (Stage F) | Medium |

**Premortem: how this fails**
- Dressing on a straight road still feels repetitive. Curves and elevation (the proposal is in progress) and per-district kits are what really break up the sameness.
- Additive cards stack overdraw when lamps line up, so each card fades with distance and is capped in size.

## Flags for Roy

1. About 30% of lit windows are cool blue-white `(0.62, 0.8, 1.0)` (`road_chunk_builder.gd:292`), which is close to cyan. I propose shifting them to warm white and silver.
2. The story bible names the DJ "Dale", but memory and the radio station say "Dave". Which is current?
3. The "Synthwave" station and "Neon…" track titles sit against the no-neon look. This connects to the open "Neon FM" rename.
4. The vertex-baked AO in section 3, item 6, needs your yes.

**To approve:** phases W1 to W4 as the next world work, the destination list, and the build-first order (Garage, gas station, meet garage).
