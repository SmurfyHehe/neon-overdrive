# Cars as the main attraction: feel, sound and personality (proposal, 2026-10-09)

Status: SIGNED OFF by Roy 2026-10-09 08:36Z (section 9). Nothing built yet. Roy's ask: "enhance our design of the cars. The cars should be the main attraction of the game."

Checked against `origin/main` **282343f** (git, 2026-10-09): `scripts/car_spec.gd` (only `coupe_default()` and the three traffic specs exist as driveable data), `scripts/engine_voice.gd` (12 per-car engine voices already defined), `scripts/engine_synth.gd` (engine made sample by sample in GDScript), `scripts/powertrain_health.gd` (engine heat, brake fade, tyre and clutch wear), `scripts/vendor/gevp/gevp_vehicle.gd` (the knobs listed below), `docs/design/fleet/` (the 12-car design sheet). No `AudioStreamPlayer3D` on main yet, so traffic is still silent there.

Built on: mod tree proposal, balance plan, damage and fuel design, sound research, garage and body shop design, rival and car ladder proposal, cockpit notes, project decisions (all 2026-10-06 to 10-09).

Fixed rules this keeps: gas only; one raycast-wheel sim, cars differ only by `CarSpec` data; keyboard only; exhaust mods are cosmetic; dents later; assets free for sale with no credit (CC0 or our own synthesis); no on-screen key hints; the Bug-style beater is the starter (decided 2026-10-09).

## One line

**Every car should be recognisable with your eyes shut**: by how it pulls, how it slides, how it starts and how it sounds from the cabin. And every car you own should carry its own history.

## Steelman and premortem

**Steelman.** The game already has the hard parts: a real tyre and engine sim, a per-car engine voice, heat and wear, a mod tree that changes hardware, and a story that gives every car a reason to reach you. What it lacks is a rule that keeps cars *different*, and the small touches that make a car feel owned. Most of this is data and sound, not new systems, so it is cheap for how much it changes the game.

**Premortem: it shipped and the cars still felt samey because...**
1. **The keyboard flattened everything.** Keys are on/off, so subtle steering differences vanish. Fix: carry character through what a keyboard player *does* notice: how fast the steering ramps, how the tail behaves when you lift, turbo wait, the cockpit camera's movement, and above all sound.
2. **Balance sanded the edges off.** Tuning every car to hit its tier time made them drive alike. Fix: split ownership. Balance owns power, weight and gearing (the times). Character owns weight split, centre of gravity, inertia, throttle and steering response, diff and tyre widths. Balance never touches the character knobs.
3. **The mod tree turned every car into the same fast car.** Fix: a per-car "fingerprint" test that fails if a finished build loses its car's signature (section 2c).
4. **Personality became chores.** A quirk that breaks your run every night is not charming. Fix: quirks are moments, never penalties; a quirk can cost a second, never a race.
5. **Every NPC engine audible killed the frame rate.** The engine synth runs per sample in GDScript; twenty of those on an integrated-graphics laptop won't hold. Fix: traffic plays pre-made loops rendered from the same synth (section 3d).

**Falsification:** put Roy in two cars with the body hidden (same grey box, same camera). If he can't tell which is which within a minute of driving, the handling work failed. Same test with eyes shut for sound: two seconds of idle and a rev must be enough.

## 1. What each car is (the personality sheet)

Every car gets one card like this, in data, used by the garage, Dave and the tests. The ladder cars still to be designed (wagon, rear-drive 80s coupe, truck, euro sedan, mid-engine, rally homologation) get the same sheet in their own Fable pass.

| Car | Its one line | Hero moment | Quirk (charm, not penalty) | Where it came from |
|---|---|---|---|---|
| **Bug beater (starter, T0)** | "Tired, honest, and it never gives up." | Hanging the light tail out on a wet off-ramp at 70 km/h and catching it | Engine sounds from *behind* you; heater smells of oil; nose goes light and wanders above 110 km/h | Abandoned in the shop for an unpaid bill |
| **P1 sports coupe** | "The honest one: does what you ask, a little more if you're brave." | Pop-up lamps standing up as you leave the garage | A pop-up sometimes sticks half-up after a front hit | Dunmore & Pike demo car under a tarp |
| **P2 hot hatch** | "All revs and no manners." | Lifting mid-corner and feeling the nose tuck in | Wheel tugs under full throttle in 1st and 2nd; hatch rattles over bumps | Juno's car (crew) |
| **P3 tuner sedan** | "Nothing, nothing, then everything." | Boost arriving on a long exit and all four wheels digging in | Turbo flutter on every lift; wastegate chatter | Scrapyard rebuild |
| **P4 kei roadster** | "Slow on paper, fastest thing in a tight street." | Diving through a gap a bigger car can't | No roof: you hear everything (cops too), wind roars above 120 | Pilar's car (crew) |
| **P5 muscle sedan** | "A sofa with a cannon in it." | Lighting the rear tyres from a standstill, the whole body twisting | Lope rocks the car at idle; brakes get tired fast | Won from Diesel Row |
| **P6 crossover** | "Doesn't care what the road is doing." | Taking a kerb or a gravel cut at full speed | Roof rack whistles above 150 km/h | Customer car left for parts, later yours |

## 2. Handling character

### 2a. The knobs that make character (all exist on the Vehicle today)

| What you feel | Knob | Who owns it |
|---|---|---|
| Nose heavy or tail heavy (understeer vs tail-happy) | `front_weight_distribution` | Character |
| Leans and rolls, feels tippy | `center_of_gravity_height_offset`, `front/rear_arb_ratio` | Character |
| Lazy or darty when you turn in | `inertia_multiplier`, `steering_speed`, `steering_speed_decay` | Character |
| Revs snap up or swell slowly | `motor_moment` (flywheel), `throttle_speed` | Character |
| Turbo wait | `turbo_rpm_thresh`, `turbo_tau_up` | Mod tree (hardware); stock value is character |
| Front-, rear- or all-wheel drive; tugging wheel | `front_torque_split`, diff lock torques | Character (mod tree may change on swaps) |
| Grip and how it lets go | Tyre widths, `tire_stiffnesses`, `braking_grip_multiplier` | Character, then parts ladder |
| How fast it is | `max_torque`, `max_rpm`, `vehicle_mass`, gearing | **Balance and mod tree only** |

### 2b. Starting character per car (targets for the test track, not measured)

| Car | Drive | Weight split (front) | CoG | Inertia | Rev response | Steering | Signature behaviour to hit |
|---|---|---|---|---|---|---|---|
| Bug beater | RWD, rear engine | 0.40 | high | low | slow (heavy flywheel, slow throttle) | slow, wanders | Lift-off oversteer; front washes wide when pushed; brakes lock early |
| P1 coupe | RWD | 0.53 | low | medium | medium | medium | Neutral, slides progressively; easiest to read |
| P2 hot hatch | FWD | 0.62 | medium | low | fast | quick | Tucks in on lift; tugs under power (small steering pull at full throttle in low gears) |
| P3 tuner | AWD, rear-biased | 0.55 | medium | high | slow below boost | medium | Understeer off boost, pulls straight on boost; heavy but planted |
| P4 kei | RWD, mid engine | 0.45 | very low | very low | very fast | very quick | Changes direction instantly; snaps if you're rough; low top speed |
| P5 muscle | RWD | 0.56 | high | high | slow, huge low end | slow | Wheelspin from any gear below 3rd; big body roll; long smoky slides |
| P6 crossover | AWD, even | 0.58 | high | medium | medium (turbo) | medium | Shrugs off kerbs and bumps; leans but never bites |

The mod tree's 8 builds per car start from these. The balance thread sets power, weight and gearing to hit the tier times.

### 2c. The fingerprint test (the guardrail)

A headless test drives each car (and each finished mod build) through five fixed manoeuvres and records a few numbers:

| Manoeuvre | Number | Shows |
|---|---|---|
| Lift mid-corner at 80 km/h | Yaw rate jump | Tail-happy vs tucks in vs nothing |
| Full throttle from 30 km/h in 2nd | Wheelspin time, steering pull | Muscle spin, hatch tug |
| Throttle stab at 2,000 rpm | Time to +3,000 rpm | Rev response, turbo wait |
| Slalom at 60 km/h | Body roll, lag between steering and yaw | Lazy vs darty |
| Kerb strike at 100 km/h | Yaw upset | Crossover shrugs, kei snaps |

Rules: (1) no two stock cars may be within 10% on more than two of the five numbers; (2) a finished mod build must stay closer to its own stock car than to any other car. If a build drifts, the node's data gets fixed, not the rule. Runs as a sweep (stock, all 8 builds, Street/Grip/Drift presets), per Roy's testing rule.

### 2d. Feel on a keyboard

- **Steering ramp per car:** how fast a held key reaches full lock already exists (`steering_speed`); give each car its own value. The kei reaches lock in a blink, the muscle car takes its time.
- **Cockpit camera carries weight:** head bob, lean and lag scaled by the car's CoG and suspension: the muscle car sways, the kei barely moves, the Bug shimmies at speed. This is in the cockpit already; it needs per-car numbers.
- **Wheel and hands:** the steering wheel animation (being built) moves at the car's steering speed, so you see the difference too.

## 3. Sound identity

### 3a. What already exists

Each car already has its own engine voice (`engine_voice.gd`: straight six coupe, buzzy four hatch, raspy six tuner, thrummy three kei, crossplane V8 muscle, unequal-header boxer crossover, plus quiet traffic voices). Turbo whistle, blow-off, shift thump, gear whine and pops exist. The window (Z) and the camera already change the mix.

### 3b. The sound sheet per car

| Car | Start-up (X) | Idle | Under load | Lift and shift | Cabin |
|---|---|---|---|---|---|
| Bug beater | Long crank, two coughs, catches, rattly settle | Air-cooled flat-four clatter plus cooling-fan whine, **from behind you** | Busy and strained, never loud | Slow, notchy shift clunk; gearbox whine | Thin metal: everything rattles; heater fan hiss |
| P1 coupe | Short crank, clean catch, flare to 1,500 then settle | Smooth, even six | Metallic top end, clean | Crisp shift; pop-up motor whirr at dusk | Firm seat creak, solid door thunk |
| P2 hot hatch | Quick catch, rev flare | Buzzy, slightly lumpy | Nasal, rises fast to a bright wail | Short throw "clack"; intake honk | Hatch rattle over bumps |
| P3 tuner | Catch, then turbo hiss on settle | Deep six with a faint whistle | Wait, then a rising whistle and a hard rasp | Flutter on every lift; wastegate chatter | Boost gauge needle tick (optional) |
| P4 kei | Tiny whirr, instant catch | High three-cylinder thrum | Wails to a high redline | Light flick; open air means all of it is loud | No roof: wind and street always in |
| P5 muscle | Long heavy crank, big catch, **cabin shakes** | Lope; each blip rocks the body | Low boom, deep and dark | Heavy shift thud; burble on overrun | Bench creak, loose trim buzz at idle |
| P6 crossover | Normal catch, boxer rumble | Paired off-beat rumble | Rumble plus turbo | Flutter on lift; gravel ping under the floor | Roof rack whistle above 150 km/h |

All synthesised (engine, turbo, fan whine) or CC0 / Sonniss one-shots (clunks, creaks, rattles), each file logged in `docs/audio-licences.md`.

### 3c. The two-second rule

Each car must be recognisable from a two-second clip of idle plus one rev, eyes shut. A listen pack (like the existing one) renders each car's start-up, idle, a rev and a pass-by for Roy to judge. Same render feeds a check that no two cars' voices are too close (pitch of the main boom and rasp more than about 15% apart).

### 3d. Every NPC engine audible, without killing the frame rate

- **Render, don't run:** at load, render each traffic voice into three to five short loops (idle, cruise, high) with the same synth. At run time each nearby car plays its loops in 3D with pitch and crossfade. Cheap.
- **Distance tiers:** within about 40 m, full loops in 3D with Doppler; 40-150 m, one shared "traffic hum" per lane direction; beyond, nothing. Cap at about 8 voiced cars.
- **Pass-by one-shots** for cars passing fast (the Burnout trick in the sound research).
- **Rivals and cops** get the full treatment within range, so you learn to recognise Kess's car or the dirty sergeant's car behind you **by ear**.
- Flag: the sound mix session in flight may already be building part of this. Check its branch before starting.

### 3e. Sound that tells you about the car

- **Damage and wear you can hear:** rattles and squeaks rise with body damage; a hurt engine misfires now and then; low oil (later) ticks; worn brakes squeal on the last metres. All fade back after the garage.
- **Mods you can hear:** every mod tree node already has a `sound` hook. Use it on every engine node so each step changes the voice: cams add lope, a stroker deepens the boom, a big turbo adds a whistle and a later, harder rush.

## 4. Damage, wear and dirt you can see

The damage design keeps a body number from day one; dents wait. These are the cheap visual layers that make a car look *lived in* before dents arrive.

| Layer | What you see | Reset by | Size |
|---|---|---|---|
| Dirt | Road grime builds on the lower body and wheels through the night; rain makes it streak | Garage wash (free, end of night) | S |
| Patina (beater) | Primer panels, faded paint, rust spots on the Bug as found; Service and the body shop replace them panel by panel | Body shop | M |
| Broken lights | Already in the damage design | Garage | (planned) |
| Engine smoke | Blue-grey puffs on lift when the engine is badly hurt; steam from the nose when cooling is hurt | Station fix / garage | S |
| Hot brakes | Discs glow after hard stops (screenshot exists) | Cools by itself | (exists or in progress) |
| Tyre wear | Shoulders look shiny and corded at high wear | Tyres at the garage | S |
| Scrapes | Silver scuff decals where you scraped a wall | Body shop | S |
| Dents | Later (decided) | Body shop | L |

## 5. Making you care about each car

| Idea | What Roy would see | Size |
|---|---|---|
| **Odometer and logbook** | The dash odometer is real and saved. The car card shows km driven, top speed, wins, cop escapes, crashes, nights owned | S |
| **Nickname** | You give the car a nickname from a list of about 30 that Dave has recorded lines for; he uses it on air ("The Toaster took Ironbridge tonight") | M (needs voiced lines, MIT/Apache TTS) |
| **Trophy stickers** | Beating a crew earns their crew's sticker for one of the car's 4 sticker spots. The car shows its history | S (sticker spots exist in the design) |
| **Dash trinket** | One story item per car hangs from the mirror or sits on the dash (Walt's keyring in the Bug, Juno's air freshener in the hatch) | S per car |
| **Its own radio memory** | Each car remembers its last station; the Bug's head unit starts stuck on Dave's AM band | S |
| **Dave knows the car** | Dave recognises the car by its sound the first night you drive it ("Haven't heard that one in twenty years") | S (lines) |
| **Garage shows them all** | Owned cars parked in the bays under covers; the one you drive tonight is uncovered | (in garage design) |
| **Never lost** | You always keep your cars (decided). No selling in v1 | (decided) |
| **History card** | Short text and one photo per car: where it came from, its previous owner, one line from Walt | S per car |

## 6. Showing the cars off

- **Stats in measured numbers, not made-up bars:** the car card shows 0-100, 0-200, top speed, 100-0 and corner speed from the car's own test runs, plus the dyno curve (from the tuner overhaul) and its feel line. Personal bests per car.
- **Before and after:** buying a node runs the test track in the background and shows the old and new number side by side (green up, red down arrows, decided).
- **Start-up ritual:** pressing X in the garage is a moment: lights, crank, idle settle, the cockpit gauges sweep.
- **Turntable and photo mode:** already planned in the garage design and photo mode; add a "listen" button on the turntable that revs the engine.

## 6b. Game-wide changes (Roy: "if you need an overhaul for the entire game I'm not against it")

Checked on main 282343f before judging. The tyre model already has load sensitivity, camber and pressure (`gevp_wheel.gd` process_tires, `tyre_load_sensitivity` 0.12 in `car_spec.gd`), and friction was recalibrated in Phase A. So the physics is not the bottleneck. The gaps are in how cars are *described* and in the cost of sound.

| Overhaul | What it gives the cars | Cost | Risk | Verdict |
|---|---|---|---|---|
| **One "car definition" per car** that holds everything about it: spec, character knobs, engine voice, sound sheet, quirks, history card, mod tree file, interior and cluster, fingerprint targets. Today these are spread over `car_spec.gd`, `engine_voice.gd`, builder scripts and fleet.json | Adding a car becomes filling in one file; nothing about a car can be forgotten; the garage, Dave, tests and AI all read the same place | M | Low: a wrapper around what exists, moved car by car | **Do it**, first, before the new cars land. Opus (data model) |
| **Tyre "let-go" shape per car** (how sharply grip falls after its peak): a peak-and-falloff curve per tyre instead of one shape for all | The biggest single source of handling personality: the kei snaps, the muscle car slides long and lazy, the coupe is progressive | M | Medium: every tune and Auto-Tune result must be re-run | **Do it**, right after the fingerprint test exists so the change is measured. Opus |
| **Engine sound moved out of GDScript** (native code, or pre-rendered loops for every car including the player's) | Frees CPU for traffic engines, more layers per car (intake, turbo, mechanical noise), no crackle under load | M (pre-render) / L (native code) | Native code needs a C++ build on the laptop and in exports; pre-render loses a little of the live synth's smoothness | **Pre-render for traffic now** (section 3d). Measure the player synth's CPU in the stress test; go native only if it shows up |
| **engine-sim style physical engine sound** (already decided: test it) | The most realistic engine voices possible | L | Licence check for any code used; heavy CPU | Keep as the planned test; don't block anything on it |
| **Car lighting and paint quality**: a "hero" paint shader (flake, clear coat sheen under street lamps), better reflections on the player car only | Cars look like the star in every screenshot and in the garage | M | Integrated graphics: must stay player-car-only and switch off on Low | **Do it** with the garage work. Fable |
| **Full physics rewrite or a different engine** (Unity, Unreal) | Nothing the current sim can't do | XL | Months lost, all tuning and tests thrown away | **No** |

Recommendation: no rewrite. Do three targeted game-wide changes, in this order: (1) the car definition file, (2) the fingerprint test (A1), (3) the tyre let-go shape. Then pre-render traffic sound and add the hero paint as their parent work comes up. Together that's about 4-5 PRs, and each one can be undone on its own.

## 7. Workload: A / B / C, build order, model

### A: small, build first (after sign-off)

| # | Item | Model, why |
|---|---|---|
| A1 | Fingerprint test (section 2c): headless manoeuvres, numbers per car and build, the two rules | Opus: measurement design everything else leans on |
| A2 | Character data for the Bug and P1 (section 2b), proven by A1 | Fable: feel judgement |
| A3 | Per-car start-up sequence (crank, catch, settle, cabin shake) in the engine synth | Opus: audio code in the synth |
| A4 | Odometer, logbook and history card data, saved per car | Sonnet: mechanical |
| A5 | Per-car cockpit camera sway and steering ramp numbers | Fable: feel |
| A6 | Listen pack and the two-second check for all car voices | Sonnet: render plus report |
| A7 | Dirt layer and a garage wash mini-game (decided) | Fable: look and play |

### B: medium, for Roy to know about

| # | Item | Model |
|---|---|---|
| B1 | Quirks system: data-driven moments per car (pop-up sticks, hatch rattle, idle rock) | Fable |
| B2 | Damage and wear sounds (rattles, misfire, brake squeal) tied to the damage numbers | Opus |
| B3 | Traffic engines by pre-rendered loops with distance tiers (if the sound mix session isn't already on it) | Opus |
| B4 | Car card screen with measured stats, dyno, personal bests and before/after | Fable |
| B5 | Bug patina panels replaced by Service and the body shop | Fable |
| B6 | Nickname list with Dave's recorded lines | Sonnet plus TTS |
| B7 | Engine smoke, steam, tyre shine, scrape decals | Fable |

### C: large, for Roy to know about

| # | Item |
|---|---|
| C1 | Character and sound sheet passes for P2-P6 and each new ladder car, one car per PR (comes with each car's build) |
| C2 | Dents and panel deformation (decided: later) |
| C3 | Rival and cop cars with their own learned-by-ear sound (needs racing AI and Stage F) |
| C4 | Cabin sound per car interior (each interior is its own, decided), recorded material sets |

**Order:** car definition file (6b) → A1 → tyre let-go shape (6b) → A2 → A3 → A5 → A4 → A6 → A7, then B as their parent systems land (B2 after damage, B4 with the garage, B3 checked against the sound mix session). Every step is its own PR with real headless Godot runs.

**Overlaps to check before building:** the player cars session (Fable, incl. Bug), balance car speeds (Fable), sound mix (Opus) and hands/wheel animation sessions are in flight. A2 must use the Bug's data from the player cars session; balance keeps the speed knobs, this keeps the character knobs.

## 8. Contradictions found

- **Starter car:** the 10-07 ladder proposal recommends "P1 as found"; the later decision (10-09) is the Bug beater. This doc follows the Bug; P1 keeps its demo-car history and arrives later.
- **Balance vs character:** the balance plan tunes "car speeds" but does not say which knobs it may move. Proposed split in section 2a; needs to be told to the balance session.
- **"Every NPC engine audible" vs frame rate:** decided yes, but the current synth can't run per traffic car. Section 3d keeps the decision and makes it cheap.
- **Exhaust cosmetic only** stays true: exhaust mods change sound and looks, not speed.

## 9. Decided (Roy, 2026-10-09 08:36Z, his numbers 106-113 and 122)

All yes, with two changes:
- **Bug tail steps out on lift-off:** yes.
- **Each car starts its own way:** yes.
- **One small habit per car** (pop-up that sticks etc.): yes.
- **Mods and the Bug:** a Bug stays a Bug, but it can become an **enhanced Bug**. Its tree makes it faster and sharper, while the fingerprint test (2c) keeps its rear-engine character.
- **Dirt:** yes, but cleaning is a **cleaning mini-game** at the garage, not an automatic wash. A7 changes to: dirt layer plus a short wash mini-game (Fable).
- **Rattles grow with damage:** yes. **Logbook:** yes. **Nicknames Dave says on air:** yes.
- **Change how each car loses grip (tyre let-go shape, 6b):** yes, re-test every tune once.
- Status: **signed off, ready to build** in the order in section 7.
