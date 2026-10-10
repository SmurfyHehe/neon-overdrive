# #37 Curves and elevation: proposal (docs only)

Status: **Roy answered 2026-10-07; final sign-off pending.** No code until then.

Roy's answers:
- **Order:** curves first, hills second.
- **Geometry:** a Path3D spline, as the ROADMAP says. Section 2 is rewritten around that.
- **Timing:** R1 now, R3 onwards after Stage C.
- **Crests:** "think it out". See section 1.
Main at `9c28d59`. Source for every "today" claim is a file:line on main.

## 0. What is true on main today

- The builder says curves are out of scope: `scripts/road_chunk_builder.gd:77-78`.
- **Road:** 50 m chunks (`CHUNK_LEN`, :96), 4+4 lanes of 3.2 m (`LANE_W`, :95),
  0.4 m median gap, 1.4 m shoulder.
  - Every strip is a flat quad from z=0 to z=-50, with normals hard-coded `UP` (:504-524).
  - Chunk roots only ever move along -Z: `_apply` (:760-762).
- **Ground:** there is no road collider. Wheels hit one infinite `WorldBoundaryShape3D`
  at y=0 (`game.gd:172-207`). Its comment reads "revisit if terrain height ever varies".
- **Pool:** 8 chunks, 6 ahead and 1 behind, so 400 m of road (`game.gd:11-13`).
  - Floating origin shifts whole chunks along Z only, at 1 km (`game.gd:253-290`).
- **Traffic is built entirely on "the road is straight down Z, lanes are world X":**
  - Pure-pursuit target `(lane_x, y, z + dir*lookahead)` (`traffic_car.gd:472`).
  - Lane changes are a cosine in x.
  - Wreck check uses `|x - path_x|`.
  - Far cars move with `z += dir*v*dt`.
  - The occupancy index is 1D along Z (`traffic_manager.gd:295-424`).
  - The player's speed is read as `-linear_velocity.z`.
- **Chase camera:** yaw is only 0 or PI, and it locks to the player's z
  (`chase_camera.gd:251-277`). On a curve it would keep staring down -Z.
- **Already fine on a curve:** cockpit view, mirrors, headlights, HUD threat strip,
  aero draft, blob shadow. All of them are car-local.
- **Skid marks:** they follow the contact height, but their quads are flat (`UP` normal)
  and length is measured in xz (`skid_marks.gd:128-153`). Culling covers only y ±10 m (:98).
- **Physics:** runs at **120 Hz** (`project.godot:172`); tests run at 60.
  - GEVP wheels ray-cast along the car's local down and push along the hit normal.
    They are slope-capable as written.
- **Budget:** 16 full-sim traffic cars on an i5-1235U / Iris Xe, with about 4 ms of
  physics per tick (`traffic_settings.gd:13-23`).
- **Seeds:** none per system yet. Building sizes use the global `randf` (:682).
  - Stage C proposal (PR #157, §3) plans one RNG stream per system from a run seed.
  - Stage C's premortem #1 is "the road is straight".

## 1. What Roy would see and feel

A night highway through the city that **bends and breathes**, PS2 highway-battle
style. No hairpins and no junctions.

| Feature | What it looks like | Numbers (v1 limits) |
|---|---|---|
| Long sweepers | Lamp rows and building walls arc away ahead; you hold a little steering for several seconds | Radius 600-1500 m |
| S-bends | Left into right; traffic in the outer lanes swings wide past you | Radius 300-600 m, short straight between |
| Straights | Still most of the road, so top-speed runs still exist | 40-60% of length |
| Rises and dips | Climb a grade and the city glow spreads out below on the far side | Grade at most 5% |
| Crests | You can't see what's over the top. Traffic appears late, which makes overtaking a real decision. Fast cars go light | Crest radius 600 m minimum (see below) |
| Sags | Suspension squats at the bottom and the headlights hit the road close | Sag radius 400 m minimum |
| Banking | **None in v1.** It's a city road | Maybe 2-3% superelevation later, on fast sweepers only |

**Why these limits.**
- Traffic cruises at 18-32 m/s. A radius of 300 m gives at most 3.4 m/s² of cornering,
  which is easy for the AI.
- At 250 km/h (70 m/s), a 600 m sweeper asks for about 0.8 g. Taking it flat out takes
  commitment, which is the fun.
- A crest makes the car weightless when v²/R > g. At 70 m/s that happens on any
  crest tighter than 500 m.
  - A 600 m floor means a stock car stays planted and a fully modded one goes light.
  - Option for Roy: allow a few tighter "jump" crests on purpose.

**Crests, thought out (Roy asked).** Nothing has to be decided now. Hills are R5,
after Stage C, and every crest is generated from knobs:

- **Default:** every crest radius is at least 600 m.
  - Traffic (32 m/s max) needs only 104 m to stay planted, so the AI never goes airborne.
  - A stock car stays planted; a fully modded car above about 250 km/h goes light.
    That's a reward for speed, not a hazard.
- **Jump crests:** a "kicker" chance knob, 0 by default. When it fires, that crest's
  radius drops to 150-250 m, so cars leave the ground at 140-180 km/h.
  - Risk: you land blind into traffic you couldn't see, which feels unfair, not fun.
  - Risk: GEVP landings bottom out the suspension and can bounce the car. That's
    untested on this car.
  - Turn it on for one R6 playtest only.
- **No crests at all:** hilliness 0 gives curves only, with no code change.
  - If R6 shows hills don't add anything, that's the answer.
- **What decides it:** Roy drives R6 with three presets (0, default, kickers on) and picks one.

**Per-run variation (plugs into Stage C).** Each seed gives:
- a curviness value and a hilliness value, so some runs are gentle and some are twisty;
- its own order of segments.

The same seed always gives the same road.

## 2. How the road is generated and how chunks join

### Geometry: a Path3D spline, one per chunk (Roy's pick)

The road follows a `Curve3D` (Bezier spline), as ROADMAP.md:153 says. There is
**one Path3D per chunk, about 50 m long, not one endless curve.** That choice is
what answers the spline's known costs:

| Spline cost | Answer |
|---|---|
| Finding a car's road position (closest point) means searching the baked points | Each car searches only its own chunk's curve: about 50 baked points at a 1 m bake interval. That's 16 cars × 50 points per tick, which is trivial. Each car caches its chunk and offset |
| Distance along the curve is approximate | 1 m bake interval. s is the chunk index × 50 plus the local baked offset, so the error never builds up across chunks |
| Lane edges are offsets of the curve, not splines themselves, and can fold on tight bends | A fold needs a radius smaller than the offset. The widest offset is about 16 m and the minimum radius is 300 m, so it can't happen |
| Smooth joins between chunks | Neighbouring chunks share the end point **and** the tangent handle (mirrored in and out handles), so position and direction are continuous. The seam test checks it |
| Seeded generation needs control points | Each chunk's end point comes from the seed's "road" stream: a heading change and a height change, clamped by heading (±30°), radius (≥ 300 m) and grade (≤ 5%). The generator samples the curve and re-rolls if a bound is broken (a deterministic re-roll, from the same stream) |
| Cost of building the curve | Baked once per chunk recycle, about 50 points, well under 0.1 ms |

**Height lives in the same spline** (control points carry y). Curves-only steps keep
every y at 0. R5 turns hilliness up and adds crests and sags by moving control
points up and down; crest radius is checked the same way as turn radius.

**Banking** would be the curve's tilt (`point_tilt`). It stays at 0 in v1.

Free bonus: chunks get a Path3D node that shows up in the editor, so a curve
is visible while debugging.

### The road-space frame

Everything uses one new class, `RoadFrame`. Here `s` is distance along the road
and `d` is the signed lateral offset from the centre line.

- `sample(s) -> Transform3D`:
  - Wraps `Curve3D.sample_baked_with_rotation`.
  - Origin on the centre line, -Z along the tangent including grade, X to the right.
- `to_road(world_pos) -> Vector2(s, d)`:
  - `get_closest_offset` on the car's cached chunk curve.
  - Steps to the neighbouring chunk when the offset lands at either end.
- `lane_offset(i)` is unchanged, but it now means `d`, not world x.

Lanes become `sample(s).origin + right * lane_offset(i)`. Traffic's `z → s` and
`x → d` is then a mechanical swap: the 1D-along-Z occupancy index becomes 1D along s,
with the same logic.

### Bounded heading (the big simplifier)

The generator keeps the road heading within **±30° of -Z**. In practice it steers
the curvature back toward 0 heading.

- **The road can never cross itself.** Any heading under ±90° guarantees it.
- **"Ahead" stays roughly -Z.** The sky work's moon, fixed "over the road ahead",
  stays in front.
  - Note: the sky shader is in progress in the threads -4yvw5a and -soqei8; it is not on main.
- **The chunk pool still works.** It's indexed by s, with the same 6 ahead and 1 behind.
- **Recentring can stay chunk-quantised.** It shifts a full Vector3 (x, y, z) instead of z only.

Cost: no U-turns or 90° city corners. Those would need junctions, which is a
different feature.

### Chunk joins

- **A chunk is 50 m of s, not 50 m of z.**
  - The builder samples the frame at 11 stations (every 5 m).
  - It extrudes the existing 10-strip cross-section along each station's right vector.
- **Seams are exact.** A chunk's last station is the next chunk's first control
  point: the same Vector3 and the same tangent. Normals come from that shared
  tangent, so shading is continuous too.
- Dashes, pylons and lamps are MultiMesh instances. Each instance gets its station's
  full transform, not just a translation. MultiMesh already supports this, at no draw-call cost.
- **Buildings and walls** are rotated to the local frame.
  - Walls become one box per station segment (10 per side per chunk), overlapped by a
    few cm so no gap opens on the outside of a bend.
  - On hills, buildings get foundations that extend down far enough to never float.
- **Seeding.**
  - The alignment comes from the run seed's "road" stream, generated lazily by segment
    index, so it doesn't depend on driving speed.
  - Building sizes move from global `randf` to `seed ^ chunk_index`. Reaching the same
    chunk again gives the same street.

## 3. What breaks, and the fix

| System | Breaks because | Fix | Step |
|---|---|---|---|
| Traffic lane-follow | Target is `(lane_x, z+L)` | Target is `sample(s + dir*L)` plus lane d, with **curvature feed-forward** (see risk 1) | R1, R3 |
| Traffic spawn and recycle, `in_view`, player speed | All z deltas; `-vel.z` | s deltas; speed along the tangent | R1 |
| Far cars (frozen cruise) | `z += v*dt`, snapped to lane x | `s += v*dt`, pose = `sample(s)` offset by d. This also puts them on the hill | R1 |
| Wreck logic | `|x - path_x|`, heading `-b.z.z` | `|d - lane_d|`, heading = dot(forward, tangent). The `b.y.y < 0.5` upside-down check is fine at 5% grade (3°) | R1 |
| Chunk pool and recentring | Index from `-z/50`; z-only shift | Index from the player's s; Vector3 shift | R1, R3 |
| Benchmark bot | Steers on lane-x error (`benchmark.gd:71`) | Steers on d error | R1 |
| Out-of-bounds walls (#114) | One axis-aligned box per side | One rotated box per station segment | R2 |
| Sidewalk colliders | One prism per chunk | One prism per station segment | R2 |
| Chase camera | Locked to world -Z | Follows the road tangent at the car's s, blended with the car's velocity heading; pitch follows grade, smoothed. Keeps the stable PS2 look | R4 |
| Ground collision | Infinite flat plane at y=0 | **Elevation only:** one trimesh road collider per chunk (road plus shoulder, about 200 tris), group "Road"; the plane goes. Curves alone keep the plane | R5 |
| GEVP wheels on slopes | Nothing breaks: the ray follows the car's down, force follows the hit normal | Verify only: stability torque `basis.y.cross(UP)` (`gevp_vehicle.gd:1152`) must not fight a 3° pitch; parked car holds on a 5% grade | R5 |
| Traffic on hills | Speed control on a flat road | Its speed loop has to absorb grade (gas cars slow on climbs). Check, don't assume | R5 |
| Skid marks | Flat quads, xz length, ±10 m cull | Use the contact normal and 3D length; move the AABB with the recentre | R5 |
| Tyre smoke (PR #159), exhaust smoke | World-space puffs rising along `UP` | Nothing breaks. Only rebase if #159 lands first | n/a |
| Headlights, mirrors, cockpit, HUD, draft | Car-local | Nothing. Headlights pointing at the sky on a crest is correct, and fog covers it | n/a |
| Sky and moon (in progress) | Moon fixed toward -Z | Fine because of the ±30° bounded heading: the moon drifts across the windscreen through bends, which looks right | n/a |

## 4. Options

| Option | What | For | Against |
|---|---|---|---|
| **A. Fake it in a shader** | Vertex shader bends the world visually; physics stays straight | Days, not weeks; zero physics risk | You never steer through a corner, which defeats a simcade. Lights, decals and raycasts don't line up with what you see. **Reject** |
| **B. Curves first, elevation second** (recommended) | R1-R4 ship flat curves; R5 adds hills | Each half is testable alone. Curves keep the ground plane, so no collider change. The traffic refactor is proven before hills add slope physics | Two playtest cycles |
| C. Both at once | One big change | One playtest | The largest diff in the repo, touching traffic, physics ground, camera and builder together. When it breaks, it's hard to tell which part did |
| D. Arcs instead of a spline | Straights plus circular arcs, maths done by hand | Exact lanes, closed-form queries | **Roy picked Path3D.** Per-chunk curves make the spline's costs small (section 2) |

**Plan: B with a Path3D per chunk, ±30° bounded heading, no banking.**

## 5. Build order: one PR per step, each with a headless test

Headless drops MultiMesh data (project memory), so mesh checks read builder arrays,
not the rendered scene.

| PR | Step | Test (headless, `tests/run_one.ps1`) | Pass bar |
|---|---|---|---|
| R1 | Add `RoadFrame` with a **straight** alignment and move every consumer to (s, d): traffic, pool, recentre, benchmark bot. **No visible change** | new `road_frame.gd`: `sample` and `to_road` round-trip; all 13 existing road and traffic tests unchanged; `traffic_perf` | Round-trip < 1 mm; existing tests pass untouched; tick cost within +5% |
| R2 | Builder extrudes along frame stations (still straight); walls, sidewalks and buildings go per-station | new `road_builder_equiv.gd` compares vertex arrays and collider boxes with the old builder (like PR #7's test); `boundary_walls` | Vertices within 1 mm; boundary rays still hit every metre |
| R3 | **Curves on (flat).** Seeded alignment generator, curviness knob, traffic curvature feed-forward | new `road_alignment.gd`: same seed gives the same road, heading within ±30°, R ≥ 300, seam gap < 1 mm and seam angle < 0.1°. New `curve_drive.gd`: bot plus 16 cars drive 3 km through at least 2 recentres | Lane error < 0.5 m on R=300; 0 wrecks; frame time on recycle within today's `chunk_drive` +10% |
| R4 | Chase camera follows the road | extend `curve_drive.gd`: angle from camera forward to tangent | < 10° throughout; no jump at recentre |
| R5 | **Elevation.** Vertical profile, per-chunk road trimesh, plane removed, foundations, skid-mark normals, hilliness knob | new `hill_drive.gd`: wheel rays swept across chunk seams; parked car on 5% with brake; crest at the 600 m floor; 16 cars 3 km on hills; recentre on a slope | Seam step < 1 mm; drift < 5 cm in 10 s; no airtime below 250 km/h; 0 wrecks |
| R6 | Tuning pass and a playtest build for Roy; knobs in the pause menu or debug | `traffic_perf`, `chunk_drive` and `fleet_budget_scene` against the R0 baseline | 16 cars still inside the budget; Roy plays it |

**Rough cost:**
- R1 and R5 are the big ones, about 1-1.5 days of agent time each.
- R2, R3 and R4 are about half a day each.
- R6 depends on Roy.
- Actual tokens and time get reported after each PR, per CLAUDE.md.

**Model:**
- Opus for R1, R3 and R5: geometry and AI-control reasoning.
- Fable for the R6 look pass.
- Sonnet for R2 and R4: mechanical and test-heavy.

## 6. Risks, and what would prove this plan wrong

1. **Pure pursuit cuts corners.**
   - With a 60 m lookahead on R=300, the chord sits 60²/(8·300) = 1.5 m inside the lane.
     That's half a lane, so cars would drift into their neighbours.
   - Fix: curvature feed-forward, plus lookahead capped by curvature.
   - **Proved wrong if** the R3 lane error stays above 0.5 m after both fixes.
     Then traffic needs a proper path tracker (Stanley), which is about one more PR.
2. **The R1 refactor leaks.**
   - If any existing traffic or road test changes result with a straight frame, the
     (s, d) abstraction isn't equivalent. Stop and fix before anything curves.
3. **Recycle hitches.**
   - Today's flat chunk rebuild is cheap. 11 stations plus, in R5, a trimesh build per
     recycle adds CPU on one frame.
   - **Proved wrong if** `chunk_drive` shows a > 2 ms spike on Iris Xe. Then spread
     building over 2-3 frames, since chunks are built 300 m ahead anyway.
4. **Trimesh collisions on wrecks.**
   - Chassis-on-trimesh contacts can catch internal edges at chunk seams. Wheels are
     rays, so they're immune.
   - Mitigation: seam vertices are shared exactly; watch `traffic_stability`.
4b. **Spline queries cost more than expected.**
   - **Proved wrong if** `traffic_perf` after R1 shows `to_road` adding more than
     5% to tick cost.
   - Fix: query every second tick for far cars, or cache s and step it by v·dt
     between queries.
5. **Nobody notices.**
   - If the radii are too gentle, it still reads as "the same road" (Stage C premortem #1).
   - Prove it in R6 by Roy driving, not by numbers.
   - The curviness knob exists so this can be tuned without code.
6. **Merge collisions with work in flight.**
   - Unmerged wall-layer commit `6b4943a` (thread -wkxidv) and PR #156 both rewrite
     wall and building colliders in the same builder.
   - PR #159 (tyre smoke) and the sky shader touch `game.gd`.
   - **R2 should start after #156 lands.**
7. **Sequencing.**
   - ROADMAP puts #37 at item 27 (XL), and Stage C is still waiting on sign-off.
   - The car redesign starts the week of 2026-10-12.
   - R1 is invisible and low-risk, so it can run alongside. R3 onwards should wait for
     Roy's call on where #37 sits against Stage C.

## 7. Decisions for Roy

Answered 2026-10-07: curves first; Path3D; R1 now, the rest after Stage C;
crests settled at the R6 playtest with three presets.

Still open (defaults apply unless Roy objects):
- **Bends:** no hairpins or U-turns; heading kept within ±30°.
- **Banking:** none in v1.
- **Sign-off:** R1 (invisible groundwork) to start.
