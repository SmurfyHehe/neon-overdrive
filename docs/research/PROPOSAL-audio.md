# Neon Overdrive — Audio Proposal (2026-09-29)

> **STATUS UPDATE, 2026-10-06: mostly built; this file is history.** Section 1
> ("there is none") and the line below about audio being backlogged no longer hold.
> Built on `main`: engine option C, synthesised (`engine_synth.gd`, PR #57); stage A
> wind, road roar, tyre squeal and kerb rumble (#84); mute option (#91); exhaust
> loudness, rasp, pops and flames (#92); turbo whistle and blow-off (#102); gear
> whine, shift thump, driveline clunk, landing thud and volume sliders (#104);
> radio with generated synthwave stations (#105, #109, with DJ breaks, captions and
> ducking); cockpit camera and perspective audio (#108). The cockpit view that
> section 6 deferred is built (#108), so "Chase cam only for now" in ROADMAP is
> superseded.
>
> **Not built:** the adaptive heat-driven music of section 5 (music exists only as
> radio stations, and open PR #115 would replace those with file-based ones),
> sampled engine recordings (option A), and per-car or per-upgrade engine sound
> (GitHub #80). Heat and police do not exist yet. See ROADMAP for the current plan.

> **STATUS: DIRECTION CHOSEN (Roy, 2026-09-29), nothing built yet.** Engine: try
> **C** (synthesised) first; if a cheap way to get recordings turns up, **A** is
> the better end state. Music: made in-project, or free / very cheap. Cockpit
> view: later. See §6.
>
> Audio is currently **backlogged**, not scheduled: HANDOFF.md lists
> "engine-pitch/tire-screech audio tied to physics state" under *after core feel
> is right — don't build yet*, and it appears nowhere in ROADMAP.md's numbered
> build order (milestones 1–11). Choosing a direction now does not mean building
> it now — it means the choice is ready when audio earns its slot, and that
> nothing built before then closes the door on it.

---

## 1. Where audio stands today

**There is none.** No code or scene outside the vendored physics folder mentions
`audio`, `sound`, `AudioStream` or `bus`; the only mentions are in docs (the
HANDOFF.md backlog line quoted above). No `AudioStreamPlayer` nodes, no bus
layout, no audio in `project.godot`. This is
genuinely greenfield — which is good news, because it means no prior decision has
to be undone.

## 2. What the physics already gives us

This was the main open risk and it resolved well. The vendored GEVP controller is
a real drivetrain simulation, and it already publishes essentially every signal a
racing-game audio system wants. Nothing needs to be added to the physics to drive
sound.

**From `Vehicle` (`scripts/vendor/gevp/gevp_vehicle.gd`):**

| Variable | Type | What it drives |
|---|---|---|
| `motor_rpm` | float | Engine pitch — the primary signal for everything |
| `throttle_amount` | float 0–1 | Load: on-throttle vs off-throttle timbre |
| `brake_amount`, `is_braking` | float / bool | Brake squeal, weight-shift cues |
| `current_gear` | int | Transmission whine frequency; gear-dependent ratio |
| `is_shifting`, `is_up_shifting` | bool | Shift event, up vs down |
| `complete_shift_delta_time` | float | Shift timing window |
| `motor_is_redline` | bool | Rev limiter bounce |
| `clutch_amount`, `need_clutch` | float / bool | Clutch slip, launch flare |
| `tcs_active` | bool | Traction-control stutter |
| `speed`, `local_velocity` | float / Vector3 | Wind and road roar |
| `torque_output` | float | Engine effort under load |

**From each `Wheel` (`gevp_wheel.gd`) — four of them:**

| Variable | Type | What it drives |
|---|---|---|
| `slip_vector` | Vector2 | **Tire audio.** Longitudinal *and* lateral slip, separately |
| `surface_type` | String | `"Road"` / `"Dirt"` — switches the tire sound. (GEVP also knows `"Grass"`, but nothing in this project is tagged Grass) |
| `spring_force` | float | Suspension thump over bumps and curbs |
| `spin` | float | Wheelspin, lockup |

Plus helpers: `get_is_a_wheel_slipping()`, `get_wheel_contact_count()`,
`get_drivetrain_spin()`.

Three things worth calling out:

- **`slip_vector` is a Vector2, not a bool.** Tire noise can scale continuously
  off real lateral slip rather than triggering at a threshold — the difference
  between a screech that switches on and one that builds as the car loads up.
- **`surface_type` is already tagged.** The sidewalk collision is tagged `"Dirt"`
  and the road slab `"Road"` (done during the environment pass for grip reasons),
  so a different tire sound over the kerb costs nothing extra.
- **`motor_rpm` is confirmed live.** A comment in `player.gd` (line 74) records a
  headless test showing motor RPM climbing normally with the car moving. Engine config — mass, torque,
  gearing — lives in `car_spec.gd` and is applied through `CarSpec.apply()`, so
  audio tuning can hang off the same structure the mods tree (milestone 10) will
  eventually drive.

## 3. The three directions

The fork is entirely about the **engine** sound. Every other layer (§4) is the
same work regardless of which is chosen.

### A. Sampled realism — the industry approach

Record or license an engine at intervals, then crossfade and pitch-shift between
loops by RPM and load.

- **Asset cost: ~16 loops per perspective.** The car runs 1000–7000 RPM
  (`car_spec.gd`); at 250 RPM spacing below 2500, where the ear is less
  forgiving, and 500 RPM above, that's 7 + 9 loops. The three outside
  perspectives — exhaust, engine bay, intake — make **48 files on-throttle**,
  roughly **96** once off-throttle variants exist.
- **Interior perspective: not needed yet.** Cockpit view comes later (Roy,
  2026-09-29: the current car model isn't suitable for first person), and
  ROADMAP.md's "Chase cam only for now" stands. When cockpit view does arrive,
  option A needs a fourth set of recordings: another 16 loops on-throttle, ~32
  with off-throttle.
- **Why so many:** a sample stretched more than about 500 RPM audibly warps. The
  count is forced by that limit, not by ambition.
- **Tuning burden:** every loop needs its true RPM derived (RPM = fundamental
  frequency × 120 ÷ cylinders) or the crossfades drift out of tune, and all loops must
  share matching pitch curves.
- **Verdict:** best possible result, and not realistically solo-achievable without
  buying a commercial engine library. Even then it is days of tuning, not hours.

### B. Hybrid — a few loops, pitch-shifted

Three to five engine loops with crossfade and pitch, plus separate tire, wind and
transmission layers.

- **Asset cost:** 3–5 files, sourced or bought.
- **Quality:** recognisably a car. Will not survive close listening — the
  characteristic tell is that it sounds like one sound being stretched, because it
  is. Pitch-shifting a single loop is the cheapest technique in both disk and CPU
  and also the one most often described as sounding artificial.
- **Verdict:** the safe middle. Defensible, unremarkable, and the direction that
  most closely matches "simcade" as a target.

### C. Synthesised — no samples at all

Build the engine in code from oscillators driven by `motor_rpm`, via Godot's
`AudioStreamGenerator`. A four-stroke's fundamental is `rpm / 60 × cylinders / 2`;
stack harmonics on it, shape the timbre with `throttle_amount`, add noise for
intake and exhaust roughness, and modulate on load.

- **Asset cost: zero.** No files to source, license, record or tune.
- **Controllability:** total. Cylinder count, firing interval, harmonic content
  and redline become numbers in `car_spec.gd` — which means the **mods tree
  (milestone 10) could genuinely change how a car sounds** when you buy an engine
  upgrade, rather than just changing its stats. The Sleeper and top-tier cars
  could sound like different cars because they *are* different parameters, not
  different files.
- **Aesthetic fit:** this is the argument that matters. A synthesised engine in a
  synthwave night racer isn't a compromise standing in for a real recording — it
  is the same instrument family as the soundtrack. It's also exactly the logic the
  graphics research landed on: pay once, in code, instead of in assets.
- **A later cockpit view would cost almost nothing here.** Cockpit view isn't
  planned yet, but when it comes, a cockpit is acoustically a damped, filtered
  version of the same engine, so the interior mix is an EQ and reverb treatment
  of a signal we already have — not a second set of recordings. Under option A
  the same view means another ~32 files.
- **Risk, stated plainly:** it will sound synthetic, because it is. If the target
  is "sounds like a real car," this is the wrong choice and no amount of tuning
  fixes that. It also has real CPU cost per frame (buffer filling in GDScript),
  unlike playing a sample, and it is the option with the most unknowns — it's the
  one I'd want to prototype before committing.

### Not proposed: granular synthesis

Worth knowing it exists, because it's what modern racing sims actually use, and
it collapses the asset problem to **3 files** — one acceleration ramp, one
deceleration ramp, one idle loop — with the expensive analysis done offline.
Godot 4 has no granular engine built in, but that alone isn't a reason to rule
it out: it could be hand-built on the same `AudioStreamGenerator` option C uses,
with no FMOD or Wwise. Left out because it combines the costs of A and C — it
still needs recorded ramps (sourced, cleaned, analysed offline) *and* a custom
real-time playback engine in code — and that's a lot of machinery for where this
project is. Worth revisiting if C's prototype sounds too synthetic and B sounds
too stretched.

### Recommendation

**C, with the prototype gate.** It's the only option with zero asset cost, it's
the only one that lets the mods tree change how a car sounds, and it's the one
whose weakness (sounds synthetic) is arguably this game's aesthetic rather than a
defect. It also ages best if cockpit view arrives later: that view would cost
option A another set of recordings, and option C a filter. But it is
also the option I'm least able to promise on paper — so the
honest form of this recommendation is: build a throwaway synthesised engine
first, listen to it, and fall back to **B** without embarrassment if it doesn't
land. *(Roy chose C, but with **A** rather than B as the preferred alternative
if recordings can be had cheaply — see §6.)* That's a much cheaper experiment than committing to A's asset pipeline.

## 4. The layers beyond the engine

Identical work under all three directions. Roughly in order of how much they'd
add:

| Layer | Driven by | Notes |
|---|---|---|
| **Tire slip** | `slip_vector` per wheel, `surface_type` | Scale off lateral slip magnitude, not a threshold. Different sound per surface, already tagged |
| **Wind / road roar** | `speed` | Simple volume+filter ramp. Cheap, and a large share of the sense of speed |
| **Shift** | `is_shifting`, `is_up_shifting` | Up and down want different sounds. `shift_time` is 0.3s |
| **Rev limiter** | `motor_is_redline` | The bounce off redline — disproportionately satisfying for the effort |
| **Transmission whine** | `current_gear`, `motor_rpm` | Gear-dependent pitch. Optional; adds mechanical credibility |
| **Suspension / kerb** | `spring_force` per wheel | The sidewalk already gives a real physical bump to hang this on |
| **Traction control** | `tcs_active` | Stutter. Only if TCS stays enabled in the final tune |
| **Impacts** | collision + damage system | Blocked on milestone 6 (damage), which doesn't exist yet |
| **Exhaust pops on overrun** | `throttle_amount` falling at high `motor_rpm` | Pure character. Cheap, and very on-genre |

Two structural notes if any of this gets built:

- **Audio buses should exist before the first sound.** A bus layout
  (Master → Engine / Tires / World / UI / Music) costs nothing to set up early and
  is unpleasant to retrofit once a dozen players are addressing Master directly.
- **Everything should be one node the vehicle owns**, reading GEVP state in
  `_process`, in the same spirit as `player.gd`'s existing thin HUD-compatibility
  surface. Audio should not be scattered through the physics.

## 5. Music

**In scope** (Roy, 2026-09-29: "the game needing music is true, audio isn't just
the exhaust"). Music is not a garnish on this genre — for an endless night racer
it carries pacing and tension in a way the engine can't, because the engine only
ever reports what the car is doing, never what the *run* is doing.

### The system: adaptive, not a playlist

Godot 4.3 added native interactive-music types — **`AudioStreamInteractive`**,
`AudioStreamPlaylist` and `AudioStreamSynchronized` — which cover the ground
normally requiring Wwise, FMOD or CRI ADX2. The project is on 4.7.2, so these
are available now, with no middleware dependency.

`AudioStreamInteractive` holds a set of clips plus a **transition table**, and
switches between them on rules — `IMMEDIATE`, `END`, or `NEXT_BEAT`. Beat-aligned
transitions are the important one: the music changes intensity without ever
sounding like a track was cut off.

### What drives it — the heat system, almost exactly

ROADMAP.md's wanted/heat design already defines the tiers this needs. They map
onto music states with no invention required:

| Heat | Roadmap meaning | Music state |
|---|---|---|
| 0–29 | No police | Base — cruise, sparse, wide |
| 30–59 | Tier 1: 1 cop, moderate | Pursuit low — percussion enters |
| 60–89 | Tier 2: 2 cops, aggressive | Pursuit high — full arrangement |
| 90–100 | Tier 3: 3 cops + roadblocks | Peak — everything, fastest harmonic rhythm |
| — | Evasion succeeds (6s clean) | Release — resolve, decay back to base |

Two more hooks worth using: the **near-miss streak multiplier** (builds over a
rolling 4s window, caps at 3.0×) is a natural filter-open or layer-in, since it's
already a number from 1.0 to 3.0 (+0.15 per near-miss until the cap) rather than
an on/off state; and **stop places**
(garage, repair, refuel) want their own calm cue, because they're the only moments
the game stops moving.

This means the music system is blocked on the same milestones as the systems that
drive it — heat/police is milestone 11, near-miss scoring is 9. A base track and
the bus structure can exist long before that, but the adaptive behaviour cannot
be finished ahead of the systems it reacts to.

### Where the music itself comes from

Three routes, and this is a Roy call the same way the engine direction is:

1. **Licensed** — synthwave/outrun libraries are well-served on the usual
   marketplaces. Cheapest in effort, and the tracks won't be exclusive. Needs
   stems, or per-tier separate tracks, for the adaptive system to have anything to
   crossfade.
2. **Commissioned** — a composer writing to the heat tiers, delivered as stems.
   Best fit and genuinely exclusive; real money and real lead time.
3. **Composed in-project** — consistent with option C for the engine, and the two
   would share a sonic world by construction. Slowest, and depends entirely on
   whether that's something you want to spend time on.

Whichever route: **ask for stems, not stereo mixes.** An adaptive system needs
separable layers, and a finished stereo track can't be taken apart afterwards.
This is the decision that's expensive to reverse — the same shape as the MultiMesh
call on the graphics side.

### Mix

Engine and music occupy overlapping low-mid space and will fight. The bus layout
in §4 exists partly for this: sidechain or duck music slightly against engine load
(`throttle_amount`), so full-throttle reads as loud without the music simply being
turned down. Worth designing in from the first bus, not bolted on at the end.

## 6. Decisions (Roy, 2026-09-29)

1. **Engine: C first, A if it gets cheap.** Build the throwaway synthesised
   engine and listen to it. If a cheap source of engine recordings turns up,
   sampled realism (A) is preferred over C. B is no longer the planned fallback.
2. **Music: made in-project, or free / very cheap.** No commissioning. Free or
   cheap tracks need to come as separate layers (stems) or per-heat-level
   tracks, and their licence must allow use in a game.
3. **Cockpit view: later.** The current car model isn't suitable for first
   person, so ROADMAP.md's "Chase cam only for now" and milestone 5 stay as
   they are.

## 7. Sources

- [The Car Engine Sound Primer — BOOM Library / Mike Caviezel](https://www.boomlibrary.com/blog/the-car-engine-sound-primer-mike-caviezel/) — loop counts, RPM spacing, perspectives, the on/off-throttle split
- [Engine Sound Modeling: From Sampling to Granular Synthesis — Audiokinetic](https://www.audiokinetic.com/en/community/blog/engine-sound-modeling-from-sampling-to-granular-synthesis-in-wwise/)
- [Vehicle Engine design: Project CARS, Forza Motorsport 5, REV — Designing Sound](https://designingsound.org/2014/08/11/vehicle-engine-design-project-cars-forza-motorsport-5-and-rev/)
- [Case Study: The Sounds of Racer — web.dev](https://web.dev/racer-sound)
- [AudioStreamGenerator — Godot documentation](https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html)
- [Engine Audio devlog — Imphenzia, "That's Racing"](https://imphenzia.itch.io/thats-racing/devlog/37275/engine-audio) — pitch-shifting a single loop, and why it sounds artificial
- [The new music features in Godot 4.3 explained — Blips](https://blog.blips.fm/articles/the-new-music-features-in-godot-43-explained) — AudioStreamInteractive / Playlist / Synchronized
- [Adaptive Music: Situation-Driven Soundtracks with AudioStreamInteractive — UhiyamaLab](https://uhiyama-lab.com/en/notes/godot/adaptive-music-system/) — transition tables, beat-aligned switching, signal-driven state
- [Add interactive music support — godotengine/godot PR #64488](https://github.com/godotengine/godot/pull/64488)
