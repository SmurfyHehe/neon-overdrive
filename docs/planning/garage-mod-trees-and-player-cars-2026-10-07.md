# Garage, mod trees and the other 5 player cars (proposal, 2026-10-07)

Status: PROPOSAL, docs only. No code until Roy signs off. Car names are
placeholders; the story is Roy's to write.

Covers ROADMAP item 22 (Stage E garage plus per-car mod trees, which comes
before Stage D) and item 23 (Stage D, the other 5 player cars). It also gives a
recommended answer to each of the open tree issues #70-#74.

Builds on:
- `docs/design/fleet/` (12-car sheet, parts, 4 sticker slots, hero paints);
- `docs/planning/tuner-redesign-proposal-2026-10-06.md` (pages, presets, stat panel);
- the Stage C proposal (PR #157: Cred, pot and bank, `user://wallet.json`);
- the narrative fabric (PR #175: power bands T0-T5, service mini-games);
- the rival and car ladder proposal (PR #177: where cars come from);
- the UI blend proposal (PR #179: shop look, shadow board, era-matched screens);
- the tree vision Roy gave on 2026-09-29 (two choices per level, ending in
  different builds, every upgrade felt, NPC up to S tier).

Fixed constraints: gas only. Every car runs the same raycast-wheel sim and
differs only by `CarSpec` data. Exhaust mods are cosmetic. 4 sticker slots per
car. Original designs that read from every angle. Gritty PS2 night, Amber vs
Dusk, no magenta or cyan. The player is the mechanic, so power is earned in the
garage. Input is keyboard plus controller, playable with one or two hands (Roy,
2026-10-07).

## Steelman and premortem

**Steelman.** The garage is where the game's promise ("you are the mechanic")
becomes something you do. Each tree is one data file of `CarSpec` overrides, so
it costs no new physics. The Tuner, Cred and the power bands already exist on
paper, and this ties them together: the tree decides what kind of car it is,
parts decide how far the Tuner can push it, Cred pays for both, and the bands
decide which events it can enter.

**Premortem: it shipped and failed because...**
1. **Too many systems.** A tree plus parts plus a Tuner plus bands confuses
   players. Mitigation: one screen per job (lift = tree, shadow board = parts,
   bench = Tuner). Each node card says in one line what you'll feel.
2. **Upgrades weren't felt** (Roy's "every upgrade must mean something").
   Mitigation: each node must move a measured number past a threshold, for
   example 0-100 by 0.3 s or more, or lateral g by 0.03 or more. The E7 test
   checks that on the hidden test track and fails any node that doesn't.
3. **A dominant path.** One branch is best everywhere, so the fork is fake.
   Mitigation: every fork trades something away (response against peak power,
   grip against slide), and the E7 test checks that each capstone wins at least
   one of the four Mechanic goals (launch, top speed, braking, cornering).
4. **Grind.** Prices are set before Stage C payouts are measured. Mitigation:
   every price lives in one tunables file and is set in "nights of play", not
   absolute numbers, then rescaled once Stage C is measured.
5. **Five new cars stall on art.** Mitigation: Stage E is built and tested on P1
   alone. Each D car is its own small stack, one at a time, after the Fable
   redesign pass (from the week of 2026-10-12) sets the style.

## 1. Garage scene and flow

**Place:** Dunmore Auto (placeholder), one bay at night under sodium tubes. The
car sits on a two-post lift. Around it are a workbench, a parts shadow board, a
desk with the event board and overdue notices, the key board, and Dave's rig
through the back door. It looks like a PS2 menu scene: fixed camera shots, with
the camera gliding between stations, not a walkable room (narrative fabric W5:
menu scene first).

**Stations** (Left/Right moves between them, Up/Down and Enter inside, Esc goes
back; the same actions on the controller's D-pad and A/B; no on-screen key hints):

| Station | Camera | What you do |
|---|---|---|
| Lift | Low 3/4, car raised | **Mod tree** (performance). Buy, fit or swap nodes |
| Shadow board | Wall, car in background | **Parts ladder** (tyres, suspension, diff, brakes, gearbox, weight). An empty foam cut-out shows a part you don't own |
| Body shop | Turntable, 360° orbit | **Looks:** paint, swappable parts, 4 stickers, wheels, stance, signature slot. The orbit is also the "readable from every angle" check |
| Bench | Over-shoulder at the laptop | **Tuner** (the redesigned one: presets, pages, Test run, dyno sheet). Sound page = cosmetic exhaust |
| Key board | Wall of hooks, owned cars under tarps outside | **Switch car**, see each car's tier and tree progress |
| Desk | Top-down on the desk | **Cred wallet**, event board (shows each event's band), save, **"Go out"** |

**The day and night loop** (Roy, 2026-10-07):
```
Sunrise -> GARAGE (day): service, customer jobs*, buy/fit nodes and parts, tune, Test run
        -> Desk: "Go out" -> NIGHT: free run / events (Stage C pot and bank)
        -> sunrise or quit -> GARAGE with banked Cred
```
*Customer jobs and service mini-games are the engine spec and PR #175's job, not
this proposal's. This one only leaves room for them: a "Jobs" tab on the desk,
empty in v1.

**Fitting is instant in v1.** No build timers. Ordered parts arriving later
would be a story-paced extra, not in v1.

## 2. Mod tree structure

Three layers, each with one job:

| Layer | Job | Physics? | Where |
|---|---|---|---|
| **Tree** (15 nodes per car) | What kind of car it becomes | Yes: changes the car's **base spec** | Lift |
| **Parts ladder** (about 12 buys per car) | How far the Tuner can push it | Yes: widens **Tuner ranges** and moves the base a little | Shadow board |
| **Looks** | How it looks and sounds | **Never** | Body shop, Tuner Sound page |

### 2a. The tree: Roy's binary shape, 15 nodes

```
                         [Service]                      L0  stock restored (T0 -> T1 on a tired car)
                     /               \
              [Fork A]               [Fork B]           L1  the car's identity question
             /       \               /       \
          [A1]      [A2]          [B1]      [B2]        L2  how far, which way
          /  \      /  \          /  \      /  \
        G    S    G    S        G    S    G    S        L3  capstones: Grip or Slide (8)
```

- 1 + 2 + 4 + 8 = **15 nodes**. One path is 4 nodes, so 8 finished builds per car.
- **L1** is the car's identity question (table in 2d). **L2** is a deeper engine
  or drivetrain step. **L3** decides the chassis direction: **Grip** (stiffer,
  sticky, more downforce) or **Slide** (locked rear, more lock, a looser rear end).
- A node is data: CarSpec field deltas, Cred cost, minimum story band, optional
  skill gate (a later mini-game such as "engine rebuild"), and a one-line feel
  description. Stored in `data/mod_trees/<car_id>.tres` (or JSON), never in code.
- **Owned nodes stay owned.** Taking the other branch means buying it. Swapping
  between owned nodes at the lift is free (see Q2). Owned parts sit on the shadow
  board, so this matches how a real shop keeps parts on the shelf.
- Turbo nodes depend on #73 (turbo lag): they ship with today's boost model and
  gain lag when #73 lands. Anti-lag stays turbo-only (PR #183).
- **Sound follows the node** (#80): a turbo node adds whistle and blow-off, a
  high-rev node raises the voice's pitch ceiling. The cosmetic exhaust settings
  stay as they are.

### 2b. Parts ladder (linear, every car)

| Part | Steps (stock → 1 → 2) | Unlocks in the Tuner |
|---|---|---|
| Tyres | Street → Sport → Semi-slick | Compound choices; friction and stiffness |
| Suspension | Stock → Coilovers → Adjustable coilovers | Ride height, springs, dampers, ARBs: ±1 notch → ±3 → full 11 |
| Differential | Open → LSD → Plate LSD | Diff lock range |
| Brakes | Stock → Pads and lines → Big brake kit | Brake pressure ceiling, fade later |
| Gearbox | Stock → Close-ratio → Sequential | Final drive range; sequential changes the shift time and the lever (#151) |
| Weight | Stock → Strip interior → Carbon panels | No slider: −mass on the base (and a stripped cockpit look) |

**The Tuner hook:** every Tuner slider still shows. On stock parts it moves
only a notch or two either side of the base. Better parts open more notches, and
the top part opens the full range plus Advanced. Presets (Stock / Street / Grip /
Drift) stay offsets from the car's base. **"Stock" is renamed "Base build"**:
the stock spec plus the fitted tree nodes and parts. Test run and the dyno sheet
(PR #186, #194) are how you check that a node did something.

### 2c. Looks (cosmetic only)

- **Parts from the fleet sheet:** front and rear bumpers, hood, skirts or
  wide-body, spoiler, wheels, exhaust tips, stance, plus the signature slot
  (P1 lamps, P4 roof, P6 rack). Cosmetic parts never change physics.
- **Matching looks come free:** a tree node that implies a look (a Grip capstone
  implies a big wing) gives you that look's part for free, but never forces it on.
- **Paint:** hero paint plus 4 alternates at start. More come from story wins and
  crews (the palette check runs on every paint).
- **Stickers:** 4 slots (door mirrored, hood, sun strip, tail). The sticker set
  grows as you beat crews (their stickers), with Dave's station sticker and your
  shop's own. Decal projectors at the `fleet.json` slot positions.
- **Exhaust sound:** loudness, rasp, pops, flames. These stay on the Tuner's Sound
  page (Roy merged the tuners). Buying a different exhaust tip in the body shop
  sets that page's defaults for the car.

### 2d. Per-car L1 and L2 (the identity questions)

L3 is always Grip or Slide.

| Car | L1 fork | L2 under A | L2 under B |
|---|---|---|---|
| P1 coupe | **Turbo** / **Stay NA** | Big single turbo (peak) / Twin-scroll (response) | Screamer (revs) / Stroker (torque) |
| P2 hatch | **Boost** / **Light** | Bigger turbo + front LSD / Hybrid turbo (flat torque) | Lightweight flywheel + close gears / Seam-weld and strip |
| P3 tuner | **RWD** / **AWD conversion** | Straight-six big turbo / High-rev cams | AWD rally split 40:60 / Torque-vectoring split 30:70 |
| P4 kei | **Spin it** / **Swap it** | Twin-cam head, 11k redline / Small turbo | Bigger engine swap (heavier, more torque) / Mid-mount bike engine (light, peaky) |
| P5 muscle | **Supercharger** / **Big block** | Roots blower (bottom end) / Centrifugal (top end) | Stroker crank / Nitrous-free race cam |
| P6 crossover | **Rally** / **Track** | Raised long-travel + gravel gearing / Anti-lag rally turbo | Lowered, wide tyres / Rear-biased AWD (20:80) |

Each fork trades something: the turbo branch gives peak power but loses
response, the NA branch gives revs but loses low end, and so on. The P1 branch
names come from the 2026-09-29 draft tree page (Screamer, Stroker, Big turbo,
Supercharger).

### 2e. Money and bands

- **Currency is Cred** (Stage C), banked from the pot into `user://wallet.json`.
  Garage ownership goes to `user://garage.json`.
- **Prices in nights of play** (one Act 1 night ≈ 1 unit; v1 guesses, all in
  one tunables file, rescaled once Stage C payouts are measured):

| Item | Nights |
|---|---|
| Service (L0) | 0.5 |
| L1 node | 1-2 |
| L2 node | 3-4 |
| L3 capstone | 5-7 |
| Part step 1 / step 2 | 1 / 3 |
| Looks (paint, sticker, cosmetic part) | 0.2-1 |

  One full path on one car costs about 10-13 nights plus parts, so the player maxes
  1-2 cars per act and has to choose.
- **Story bands cap events, not builds** (PR #175's rule, the recommended answer
  to #74). Over the band, the event offers a one-click "race spec" detune. No mod
  is ever removed.

## 3. The 5 player cars

These are the fleet sheet's P2-P6, which already have silhouettes, parts and
hero paints. This adds names, era, drivetrain, band, personality, interior and
how you get each one. Torque and mass are **starting values** for the D data
pass, not measured. Bands follow PR #175 (Nm/kg): T1 0.30-0.36, T2 0.36-0.42,
T3 0.42-0.52, T4 0.52-0.62, T5 0.60-0.66.

| | P2 Hot hatch | P3 Tuner sedan | P4 Kei roadster | P5 Muscle sedan | P6 Perf. crossover |
|---|---|---|---|---|---|
| Working name | **Kobo** | **Ronin** | **Mite** | **Marlowe** | **Cairn** |
| Era | Late 80s | Mid 90s | Early 90s | Mid 90s | 2010s (the one modern car) |
| Drivetrain | FWD | RWD (AWD by tree) | Mid-engine RWD | FR, 4-speed auto | AWD 40:60 |
| Engine (feel) | 2.0 turbo four | 2.6 straight-six | 0.66 turbo triple, 9.5k redline | 5.7 V8, 5.8k redline | 2.0 turbo flat-four |
| Start (Nm / kg) | 340 / 1,080 | 520 / 1,300 | 180 / 760 | 820 / 1,800 | 580 / 1,450 |
| Arrives at band | **T1** | **T2** | **T1** (cornering exception, #175) | **T3** | **T2** |
| Tree ceiling | T4 | T5 | T4 (by cornering) | T4 | T4 |
| Personality | Launches; light, darty, lift-off tuck | Revs; the builder's car, most branches | Corners; slow on straights, untouchable in turns | Torque; heavy, lazy, huge mid-range shove | Grips; any weather, any surface, safe and fast |
| Cluster | Red-needle analog, tach in the middle, LCD odometer | 5 white-face dials with amber backlight, plus a 3-pod boost/oil/volt cluster on the console | Motorbike-style 3 pods, big tach in the middle | Wide sweep speedo with an aftermarket "monster tach" clamped to the column | Factory digital cluster, rally shift lights |
| Cockpit | Upright dash, thin pillars, big glass, cassette head unit | Bucket seat, harness bar, aftermarket head unit | Open top, sky overhead, roll bar in the mirror | Bench seat, long hood out the glass, column lever (R-N-D) | Tall seat, factory centre screen (the only 2026 screen), rally lamp switch panel |
| Lever (#151) | H-gate 5 | H-gate 5 | H-gate 5, short throw | R-N-D auto | Sequential |
| Mirrors | Square doors, tiny wide interior | Small sedan doors | Small round doors | Big chrome doors | Big modern doors with an indicator strip |
| How you get it (#177) | Crew car (Juno), Act 1, free | Scrapyard rebuild, start of Act 2: 6 nights of parts + a Ferris favour | Crew car (Pilar), end of Act 1, free | Won from a crew leader (Act 2 boss), free; or a lien sale, 12 nights | Lien car (customer never paid), mid Act 2: 9 nights |

P1 coupe for reference: early-90s fastback, RWD, starter "as found" at T0 (PR #177
recommendation), tree ceiling T5.

Interiors follow the UI blend rule (a car's screens match its era and owner) and
Roy's rule (every car has its own cockpit, cluster and mirrors). They are designed
in the same Fable pass style as the P1 redesign, so no car's interior and exterior
clash again.

## 4. Build order (small PRs, one at a time, Roy signs off each)

Stage E is built and proven on P1 alone. Stage D then adds a car at a time.

| # | PR | Size | Model (why) |
|---|---|---|---|
| E1 | Tree data model: node schema, P1 tree data, loader, headless tests | M | Opus: the data model everything else sits on |
| E2 | Garage save: owned nodes and parts, Cred spend, respec rule (reuses Stage C's wallet; adds a minimal one if C isn't merged yet) | S | Sonnet: mechanical |
| E3 | Build application: nodes and parts → base spec at spawn, Tuner ranges gated by parts, "Base build" preset | M | Opus: touches CarSpec and the Tuner model, the riskiest step |
| E4 | Garage scene v1: lift, 6 stations, camera glides, keyboard and controller nav | M-L | Fable: layout, light, mood |
| E5 | Tree and shadow board screens in the shop style (#179 theme) | M | Fable: look; Sonnet can wire it after |
| E6 | Body shop: paint, P1 part swaps, 4 sticker decals, 360° turntable | L | Fable: visual judgement |
| E7 | Feel test: every node path on the hidden test track; each node moves a number past its threshold; each capstone wins a goal; bands hold | M | Opus: measurement design |
| D-n.1 | Car n exterior game model from its fleet sheet | L | Fable |
| D-n.2 | Car n interior, cluster, mirrors, lever mode | M-L | Fable |
| D-n.3 | Car n CarSpec, tree data, engine voice, exhaust defaults, E7 run | M | Opus for the spec feel; Sonnet for data entry |

D order follows the story: P2, P4, P3, P6, P5. D waits for the P1 redesign style
(week of 2026-10-12) and fixes the outline twins P1/P3 and P2/P6 as it goes
(ROADMAP item 23).

Sizes: S about 1-2 h and about 150k tokens; M about 3-5 h and 300-500k tokens;
L about a day and 600k-1M tokens. These are estimates; actual cost is reported
after each PR.

## 5. Decisions for Roy (one word each, recommendation marked)

1. **Tree shape:** a 15-node binary tree per car (4 picks per build, 8 builds),
   plus a parts ladder that opens up the Tuner? **Yes (recommended)** / tree only
2. **Respec (#72):** owned nodes stay owned, swapping between them is free, a new
   branch costs Cred? **Yes (recommended)** / no respec / paid respec
3. **Parts gate the Tuner's range** (stock parts allow ±1 notch)? **Yes
   (recommended)** / Tuner stays fully open
4. **200 km/h cap (#70):** close it; ~300 km/h through tuning stays (ROADMAP)?
   **Close (recommended)** / cap
5. **Bands cap events, not builds (#74),** with a one-click "race spec" detune?
   **Yes (recommended)** / bands lock cars out
6. **Looks never change physics;** a node's matching look comes free but is never
   forced? **Yes (recommended)** / looks carry small physics
7. **Tier scale:** use PR #175's T0-T5 power bands, with a car's tier meaning the
   band it arrives at (PR #177's T0-T4 table becomes arrival bands)? **Yes
   (recommended)** / other
8. **Ceilings:** every car can reach T4, and P1 and P3 reach T5? **Yes
   (recommended)** / every car to T5 / ceilings by personality only
9. **One currency:** Cred buys everything; respect and rep stay as standing, not
   money? **Yes (recommended)** / a separate cash currency
10. **Garage v1 is a menu scene** (fixed shots), walkable later if ever? **Yes
    (recommended)** / walkable now
11. **Names:** Kobo, Ronin, Mite, Marlowe, Cairn as placeholders until you name
    them? **Yes (recommended)** / name them now

## Contradictions found while writing this

- The project's notes say **keyboard only**. Roy's newer rule (2026-10-07) is keyboard
  plus controller, playable with one or two hands. This proposal follows the newer rule.
- **Tier scales differ:** PR #175 uses T0-T5 power bands by act; PR #177 gives a
  T0-T4 table by car. Q7 settles it.
- **The P1 starter "as found"** (PR #177) depends on the P1 redesign that starts the
  week of 2026-10-12. The "as found" look should be part of that redesign brief.
