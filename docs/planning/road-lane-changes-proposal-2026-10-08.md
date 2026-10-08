# Road that changes: lane adds, drops, splits and exits (proposal)

2026-10-08. Design only, nothing built. Roy signs off before any code.
Read against main `09455e0`.

Roy's ask: "I want to split lanes ... a 4 lane highway doesn't mean it's always
going to be 4 lanes both ways. I want it to change over time a little bit so I
get the feel it's like a map rather than an infinite road." Splitting is a goal,
not a guarantee: this doc says what is feasible and what is not.

## 1. What you would see

Driving a long run, the road stops being one fixed 4+4 strip:

- **Lanes come and go.** An outside lane ends ("RIGHT LANE ENDS" sign, then a
  long taper), or a new lane opens on the outside. Each direction changes on
  its own, so you get 4+3, 3+4, 2+2 stretches.
- **The two directions separate.** The median widens from a paint line to a
  concrete barrier to a 10-30 m gap with lamp posts, bridge pillars or dark
  grass between the carriageways, then they come back together.
- **Exits and on-ramps.** An exit lane peels off to the right, climbs or drops
  away, and (in the cheaper version) rejoins a few hundred metres later as an
  on-ramp. NPCs take the exit and others merge in from the ramp.
- **Named stretches.** Overhead signs with exit numbers and place names (names
  are placeholders, the story is Roy's) so a run has places you pass, not just
  metres.
- **A real fork (later, optional).** The highway splits in two; you pick a side
  and the road you picked becomes the road.

The road still never ends and never dead-ends you. Changes are slow: a lane
taper takes 200-250 m, a stretch holds its layout for 0.6-2 km.

## 2. How the road works today

- The road is a chain of 50 m chunks (`RoadChunkBuilder`), a pool of about 6-9
  recycled as you drive. Each chunk is built from two configs: the previous
  chunk's and its own (`own_lanes`, `onc_lanes`, `barrier`). Road edge,
  shoulder, curb, sidewalk, walls, buildings and lamps are all laid out from
  the lane count, and **the builder already tapers widths from the start
  config to the end config.** That code survived from the Three.js port.
- `game.gd::_section_at()` pins every chunk at 4+4 since stage B step 3,
  because traffic could not leave a lane that narrowed away. Only the centre
  barrier still rolls per chunk, with unseeded `randf()`.
- Shape comes from `RoadAlignment` (curves R3, hills R5): one seeded stream for
  bends, another for hills. `RoadFrame` turns world positions into road space
  (x across, z along), and everything (traffic, chunk pool, bot) goes through it.
- Lanes are numbered from the centre line out: lane 0 is the passing lane,
  lane 3 the slow outside lane. `MAX_OWN_LANES = MAX_ONC_LANES = 4` sizes the
  MultiMesh buffers. `MEDIAN_GAP` (0.4 m) is a constant.
- Traffic: each car holds `lane_x`, changes lane with MOBIL
  (`_consider_lane_change`), and asks `TrafficManager.lane_allowed(lane, oncoming)`,
  which only knows a fixed `own_lanes` / `onc_lanes`. Spawns pick a random lane
  out of that fixed count. Cars beyond the draw distance run a frozen cruise and
  may change lane instantly, unseen.

So: the geometry half of "lanes change" mostly exists. The work is a seeded
layout plan, longer tapers, markings, and teaching traffic that lanes end.

## 3. The plan in one picture

A **layout profile** along the road, generated from the run seed like bends
and hills (a third random stream, so changing it never changes the curves):

```
distance ->  0 km ........ 1.2 km ......... 2.0 km ........ 3.1 km ......
own side     4 lanes  ===\ 3 lanes ==== exit/on-ramp ==/ 4 lanes ========
median       paint      barrier       |  20 m split, pillars  | barrier
oncoming     4 lanes ================ 3 lanes =====\ 2 lanes ===/ 3 ...
```

Each stretch is a record: `{start_z, own_lanes, onc_lanes, median_w, feature}`
with feature one of `none`, `lane_drop`, `lane_add`, `exit_pair`,
`median_split`, later `fork`. Chunks read their start and end widths from the
profile, so a taper can span several chunks instead of one.

### Rules the generator follows (from US highway practice)

| Rule | Value | Why |
|---|---|---|
| Lane drop taper | 225 m (MUTCD L = W x S: 3.2 m lane at 110 km/h) | One 50 m chunk is a swerve at 200 km/h |
| Lane add taper | 100 m | Opening a lane can be quicker |
| Warning before a drop | signs at 450 m and 150 m, arrows on the lane | Players and NPCs both need notice |
| Drops and adds | outside lane only (highest index) | Lane numbers of the other lanes never change; left-lane drops are rare in the US anyway |
| Minimum stretch | 600 m between changes, per side | "A little bit", not constant churn |
| Lane range | 2 to 4 per side (5 as an option, see questions) | Below 2 there is no overtaking |
| No change on | tight bends (radius under 500 m), kicker crests | Real roads avoid it; keeps tapers readable |
| Lane balance | an exit takes the outside lane or adds an exit lane first | Standard interchange design |
| Drift back | after 3 km away from 4+4, bias back toward it | The highway keeps its identity |

## 4. How traffic copes

This is the part that can break, so it is the bulk of the work.

1. **Lanes depend on where you are.** `lane_allowed(lane, oncoming)` becomes
   `lane_allowed(lane, oncoming, z)`, a lookup in the profile (cheap: one array
   search per call, cached per car per tick).
2. **A lane ending is an obstacle.** Treat the end of a dropping lane as a
   stopped car at the taper start, the textbook way (MOBIL already handles
   "obstacle ahead, find a better lane"). Cars start looking 450 m out at the
   first sign and merge left, more urgently the closer they get.
3. **A car that cannot merge** slows and waits at the taper like a real driver.
   If it is still stuck and out of view, it is recycled. In view it must never
   pop.
4. **Hidden cars** (beyond the draw distance) just move over instantly, as they
   already do for a closing player.
5. **Lane adds**: nothing new. The keep-right rule already moves cars into a
   free outside lane.
6. **Spawns** pick a lane that exists at the spawn point and still exists 300 m
   further on, so nobody spawns into a lane that is about to end.
7. **Exits**: a share of cars in the outside lane (say 30%) are flagged as
   exiting, follow the ramp's lane centre and are recycled once out of sight.
   **On-ramps** spawn cars on the ramp that merge with the same MOBIL check,
   giving the player merging traffic to deal with.
8. **Median splits** need nothing from traffic: lane centres move out with the
   median, and lane-follow steers along `lane_x` (which becomes a function of z).

## 5. Options

| | What you get | Work | Risk |
|---|---|---|---|
| **Lanes only** | Lane adds and drops per side, long tapers, signs, a seeded profile, traffic that merges | 3 PRs | Low. Geometry already tapers |
| **Lanes + splits + loop exits** (recommended) | All of the above, plus the median opening up between the directions and exit/on-ramp pairs you can take that rejoin the highway | 6 PRs | Medium. Ramps need their own strips and collision |
| **Real forks** | The highway splits, you choose, the other branch is dropped behind you | 9+ PRs | High. Two alignments live at once, the chunk pool doubles near a fork, traffic on both, police later has to follow you down either one |

Real forks are feasible, by generating both branches for about 500 m and
discarding the unchosen one once you are committed and it is out of view. They
touch almost every system that reads the road, so they come last, after the
recommended option has been played.

## 6. Build order (recommended option, one PR each, each with a headless test)

1. **Seeded layout profile, no visible change.** Profile generator plus
   `_section_at()` reading it; still forced to 4+4. Test: same seed gives the
   same profile, in any request order; every rule in the table holds over a
   200 km run.
2. **Multi-chunk tapers and markings.** Widths come from the profile, interior
   dividers turn solid along a dropping lane, lane-end arrows and the two
   warning signs. Test: road edge continuous to 1 mm at every join; chunk
   rebuild stays under the 0.5 ms budget curves R2 set.
3. **Traffic in changing lanes.** z-aware `lane_allowed`, lane-end obstacle,
   safe spawns. Turn lane drops/adds on. Test: the slider sweep below, zero
   cars left in a lane that ended, zero wrecks caused at tapers.
4. **Median splits.** Variable median, barrier, filler between carriageways
   (pillars, lamp posts, dark ground), all MultiMesh. Test: walls and collision
   follow the split; player bot drives 50 km with no wall hits.
5. **Exit and on-ramp pair.** Ramp strip, ramp collision, NPCs exiting and
   merging. Test: player bot takes the exit and rejoins; merge count and
   no-pop checks.
6. **Overhead signs and exit numbers.** Gantries every interchange, exit
   number counting up, placeholder names. Test: signs readable at 150 m in a
   screenshot, no z-fighting.

### Testing with the sliders, not one setting

Roy's point stands: one default run proves little. Steps 3-5 each run a sweep
in one headless test, every combination:

- traffic count 0 / 16 / 40 / 80
- draw distance 50 / 150 / 300 m
- curviness 0 / 0.5 / 1
- hilliness 0 / 0.5 / 1
- layout busy-ness: constant 4+4 / normal / "change every 600 m"

That is 4 x 3 x 3 x 3 x 3 = 324 runs of 2 km each with the scripted player.
Each run records: stranded cars, wrecks within 100 m of a taper, spawns in
view, player wall hits, worst physics tick. The test fails on any stranded car
or in-view pop, and prints the slowest combinations so the perf budget is
checked where it is tightest, not at the default.

## 7. Performance

- **Chunks:** same count. A lane change costs nothing extra (the strips already
  taper). A median split adds 2-4 strips and a MultiMesh of filler per chunk.
  A ramp chunk roughly doubles that chunk's strips for 4-8 chunks. Expected
  extra draw calls: under 10 per visible chunk, on the Iris Xe budget.
- **Rebuild time:** has to stay under 0.5 ms (curves R2). Ramp chunks are the
  risk; build them from the same strip code, measured in step 5.
- **Traffic:** one profile lookup per car per tick, negligible next to the
  0.19-0.36 ms a full-sim car already costs.
- **Narrower stretches hold fewer cars.** With fixed car counts, 2+2 gets
  crowded. The spawner should scale the target count with the lanes present.

## 8. Risks, and what would prove this wrong

- **Tapers on curves look wrong** or the bot clips the narrowing edge. Seen
  early in step 2 screenshots; fall back to "no change on any bend".
- **NPC merges jam** at 80 cars and the outside lane piles up. The sweep in
  step 3 catches it; fix is earlier merging and fewer spawns before a drop.
- **The out-of-bounds walls and sidewalk collision** were built for one taper
  per chunk. Multi-chunk tapers need checking against #114 and #141's tests.
- **It still feels infinite.** Lane changes alone may not read as a map. The
  thing that would prove it: if, after step 3, a 10-minute run still feels like
  one road, the place-feel has to come from signs, landmarks and districts
  (step 6 and the landmark research), not more lane churn.

## 9. Questions for Roy

1. **What does "split lanes" mean to you?** (a) the road layout changes and
   the directions separate (this doc's reading, recommended), or (b) lane
   splitting: threading your car between two lanes of traffic. (b) already
   works physically (about 1.1 m between cars at 3.2 m lanes) and would be a
   traffic and scoring feature, not a road one.
2. **Which option?** Lanes only / Lanes + splits + loop exits (recommended) /
   Real forks.
3. **Narrowest road?** 2+2 (recommended) or allow 1+1 country stretches.
4. **Widest?** Keep 4 per side (recommended) or allow 5 at interchanges.
5. **How often?** A change every 0.6-2 km (recommended) or rarer, every 3-5 km.
6. **Same every run?** Seeded per run, so each run has its own map
   (recommended), or one fixed map that is the same every time.
7. **Exits:** loop back onto the highway (recommended) or lead nowhere (scenery
   only, cheaper).
8. **Signs:** real US green freeway signs (the palette is open now) or a
   darker in-world style.
