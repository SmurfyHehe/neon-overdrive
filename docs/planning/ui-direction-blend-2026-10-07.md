# UI direction: the blend (proposal, 2026-10-07)

Status: **proposal, docs only. No UI code until Roy signs off.**
Builds on: "Shop & Street" (`ui-direction-shop-and-street-2026-10-07.md`, mockups
https://claude.ai/artifact/JfphnF7NtKRxm3ng3R9SN3). Everything in that kit stays:
colour roles, four typefaces, plate / slab / tape / segmented bar, the eight rules.
Visual mockups for this doc: https://claude.ai/artifact/AieeHH346Fo9v5PWkTKceu

Roy (2026-10-07): the UI should blend Shop & Street, Pit Wall, Shop Floor and 2026
car culture; the radio should be a touch screen like a 2026 car.

## 1. The idea in one line

**Each source gets one job, not a share of every screen.** Mixing all four
everywhere gives a costume; giving each one a layer gives one language.

| Layer | Source | Job | Where it shows |
|---|---|---|---|
| Materials | Shop Floor | What things are made of and where they sit | Every menu: plates, label tape, floor tape, hazard stripe, shadow board |
| Motion and type | Street (Shop & Street) | How selection moves, how numbers read | Every menu and the screen HUD: 12° slabs, huge numbers |
| Data | Pit Wall | How results and comparisons are shown | Tuner test runs, run results, HUD deltas, mechanic radio lines |
| In-car screens | 2026 car culture | Screens that exist inside the car | Cockpit only: head unit (radio), digital clusters, phone |

The story reason: your mechanic runs a **pit wall from the shop bench**. The garage is
the shop floor, the laptop on the bench is the pit wall, the street is outside, and the
car you drive carries whatever screen its owner could afford.

## 2. What each source adds

### Shop Floor (materials)

Real garages organise with 5S floor tape, tool shadow boards and work-order tickets.

- **Floor tape**: thin amber lines separate panels instead of window borders.
- **Hazard stripe** (amber/black, on palette): marks "off limits" areas: the Advanced
  tuner page header, locked mod-tree nodes. Red stays for live danger (redline, wear).
- **Shadow board**: parts inventory in the garage as foam cut-outs; an empty cut-out is
  a part you have not bought. Reads ownership at a glance with no list.
- **Work order ticket**: the card shape for anything you are about to do (a job, a part
  fit, later a Stage C run). Shape only until Stage C is signed off.

### Pit Wall (data)

F1 timing screens show a lot of data fast: monospace columns, deltas, colour-coded
sectors, telemetry traces, team-radio transcripts.

- **Delta column**: every comparison is a signed number in mono, `+0.31` / `-0.12`.
  Better = amber ▲, worse = dim silver ▼, personal best = white with a sodium tick.
  F1 purple is off-palette and is not used.
- **Telemetry trace**: after a Tuner **Test run**, a speed trace of this run over the
  stock run (silver line = stock, amber = yours), plus throttle and brake strips.
  Answers "did my change help?" with evidence instead of an estimate.
- **Timing tower**: a narrow ranked list (P1, P2...). Used for test-run history now;
  reused by Stage C results only if Roy signs that off.
- **Radio lines**: the mechanic's short calls appear as transcript lines on a strip
  ("Fronts are cooked. Bring it in."). Open question for Roy: whether these are voiced
  (ties into the open "Dave audio vs captions" decision).

### 2026 car culture (in-car screens only)

What 2026 cars actually look like inside:

- Big central touch screens and app-like tiles (Tesla, BYD), and very wide displays
  (Mercedes Hyperscreen; BMW Panoramic iDrive, a strip across the base of the
  windscreen, on the 2026 iX3).
- **A backlash towards buttons.** Euro NCAP's 2026 protocol docks points unless
  indicators, hazards, horn, wipers and SOS have physical controls; BMW kept its volume
  knob and stalks. So "2026" means a screen plus a few real buttons, not glass only.
- **Aftermarket Android head units** glued into older cars are a huge street-car thing
  right now. This is the bridge to the PS2 night look: the car is old, the screen is a
  cheap, slightly too-bright 10" tablet in its dash.

**Rule: a car's screen matches the car's era and owner.**

| Car | Screen |
|---|---|
| Starter beater (old VW Beetle-style, Roy 2026-10-07) | No factory screen. Aftermarket tablet head unit in a printed bezel, a phone in a vent clip for maps and messages |
| Older cars (P1 coupe era) | Aftermarket head unit; analog cluster |
| Modern cars | Factory centre screen and digital cluster, designed per car (clusters stay individual, per the interiors rule) |

## 3. Enhance vs clash

| 2026 element | Verdict | Why |
|---|---|---|
| Touch head unit with station tiles | **Use** | Roy asked for it; it is the most "2026" thing in a car |
| Physical volume knob beside it | **Use** | True to 2026 (Euro NCAP, BMW); gives the hand a second target |
| Digital clusters on modern cars | **Use** | Per car, era-matched |
| Dark UI with one accent colour | **Use** | Already our rule 3 (one hot thing) |
| Haptic-style tap sounds | **Use** | Short synthesized ticks; replaces nothing |
| Phone in a vent clip (messages, map) | **Use, later** | Good story surface for the mechanic and Dave; needs story sign-off |
| Glassmorphism, blur, soft gradients | Reject | Fights grain and plates; reads as a phone OS, not the night |
| Thin fonts, pastel, pill buttons everywhere | Reject | Kills "numbers loud" |
| Blue / cyan accent glow | Reject | Off palette (police blue is the only exception) |
| Voice assistant, touch input on menus | Reject | Keyboard only |
| 2026 styling in pause / Tuner / garage | Reject | Menus are the shop; only the car's own screens are 2026 |

## 4. The touch-screen radio

- **Where**: centre stack, low and right of the wheel, inside the clear-glass sightline
  spec (never above the dash top).
- **Screen**: four station tiles (Drift Phonk, Dark Phonk, Synthwave, The Dave Show),
  now-playing line, track art generated from the palette, a small level meter.
  Sodium frame on the playing tile only. Slight glare and fingerprint smudge; no
  scanlines on the screen itself so it reads as newer than the car.
- **Input stays keyboard**: `N` (today's next-station key) makes the right hand leave
  the wheel, reach the screen and tap the next tile. **The station changes on the tap,
  not on the key press**, the same rule Roy set for the shifter. If the hand is busy
  shifting, the radio waits for it.
- **Off**: past the last tile the hand presses the physical knob; the screen dims.
- **Chase cam / no hands view**: the existing radio card on the screen HUD shows the
  change (Shop & Street mockup), same timing as the tap.
- In code terms: `RadioManager.next_station()` is called from the hand animation's
  contact event instead of the key handler. Needs the hands rig from `driver_model.gd`.
- Held with the interiors: the head unit's look is designed in next week's Fable
  interior redesign; this doc fixes its UI rules so that redesign does not invent a
  third style.

## 5. Screens (see mockups)

- **Pause**: Shop & Street pause, plus a floor-tape divider between verbs and settings,
  and the mechanic's last radio line on a strip at the bottom.
- **Tuner**: Shop & Street job sheet. New: Advanced page header in hazard stripe; after
  a Test run the dyno sheet flips to a **pit-wall result**: speed trace vs stock, delta
  column, best-run tick.
- **Garage**: car on the lift, mod tree as before, **shadow board** of owned parts,
  hazard stripe on locked nodes, work-order ticket for the selected part.
- **Cockpit**: head unit touch screen in an aftermarket bezel with the right hand
  reaching for it; analog cluster for an old car. Screen HUD stays Shop & Street.

## 6. Steelman and premortem

- **Strongest case**: one rule per source keeps the kit small (Shop & Street already
  covers 80%), and the "screen matches the car" rule turns the 2026 ask into character
  per car instead of a style clash.
- **How it fails**: the Fable interior redesign gives every car a big modern screen,
  and the old-car look is lost. Prevented by the era table above being part of the
  interior brief.

## 7. Build order (after sign-off)

Unchanged Shop & Street PRs 1-3 (theme + pause, Tuner, HUD), with these additions:

1. PR 2 gains the hazard-stripe Advanced header and the Test run trace (needs the test
   run to record speed / throttle / brake samples; small).
2. Radio touch screen: its own PR after the Fable interior redesign, with the hand
   contact event shared with the shifter-on-contact change.
3. Shadow board, work-order ticket: with the garage (Stage E).

Each verified with headless Godot screenshots at 1280×720 and 1920×1080; `tests/palette.gd`
keeps running.

## 8. Decisions for Roy

1. Layer model (each source one job): **Yes (recommended)** / blend all four everywhere
2. Screens match the car's era, beater gets an aftermarket tablet: **Yes (recommended)** / factory screen in every car
3. Radio station changes when the finger touches the screen: **Yes (recommended)** / instantly on key press
4. Physical volume knob next to the screen: **Yes (recommended)** / screen only
5. Pit-wall speed trace after a Test run: **Yes (recommended)** / numbers only

The four Shop & Street questions (direction, marker notes, scanlines, pause title)
are still open in their own thread.

## Sources

- Euro NCAP 2026 physical-controls requirement: https://autotechinsight.spglobal.com/news/5284766/euro-ncap-tightens-2026-safety-norms-requires-physical-buttons-again ,
  https://www.hagerty.co.uk/articles/news-articles/car-makers-must-bring-back-buttons-says-eu/
- BMW Panoramic iDrive and keeping physical controls: https://www.bmwblog.com/2026/03/23/bmw-explains-why-the-new-cars-have-a-wide-upper-display/ ,
  https://www.motorauthority.com/news/1145561_bmw-boss-screens-disconnect-you-from-the-road
- Timing-screen colour conventions: https://www.overtake.gg/threads/colours-in-timing-screen.38869/
