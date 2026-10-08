# Better sound for Neon Overdrive: research (2026-10-08)

Docs only, no code. Asked by Roy: "how can we build even better sound for this game? research."
Source of every repo claim: `main` at `09455e0`, fetched 2026-10-08 ~11:45Z.

## 1. What exists today

Checked by reading `scripts/`, `default_bus_layout.tres`, `assets/` and `PROPOSAL-audio.md`.

| Layer | Status | Where |
|---|---|---|
| Engine | Built. Synthesised in GDScript, sample by sample (firing pulses, two pipe resonances, throttle low-pass, soft clip, limiter cut). One voice per car: 12 voices in `engine_voice.gd` (cylinders, V8 / boxer firing order, pipe tone). | `engine_synth.gd`, `engine_audio.gd`, `engine_voice.gd` |
| Exhaust pops, flames, anti-lag | Built (pops are noise bursts that fire too often: ROADMAP item 10) | `engine_synth.gd`, `exhaust_tune.gd` |
| Turbo whistle and blow-off | Built | #102 |
| Gear whine, shift thump, driveline clunk, landing thud | Built | `driveline_audio.gd` |
| Wind, road roar, tyre squeal, kerb rumble | Built. Baked 2 s loops, volume and pitch per frame | `car_audio.gd` |
| Cockpit vs chase | Built. Low-pass per bus, radio louder inside | `perspective_audio.gd` |
| Radio | Built. 3 stations x 7 generated tracks (ogg), DJ breaks with captions, static, ducking | `radio_manager.gd`, `assets/radio/` |
| Mix | Buses Master / Engine / Tires / World / UI / Music, hard limiter on Master, volume sliders | `default_bus_layout.tres`, `audio_settings.gd` |

**What is missing entirely:**

- **No 3D sound at all.** There is not one `AudioStreamPlayer3D` in `scripts/`. Every sound is the player's own car, played flat.
- **Traffic is silent.** `traffic_car.gd` and `traffic_manager.gd` contain no audio. Cars pass you with no engine, no whoosh, no horn.
- **Crashes are silent.** `chase_camera.gd` already measures impact size (`register_impact(dv)`) to shake the camera, but nothing plays a sound.
- **No reverb anywhere.** No overpass, tunnel or building-canyon echo; the street sounds the same everywhere.
- **No city ambience** (distant traffic, sirens far off, dogs, AC units, rain).
- **No police, siren, scanner or helicopter audio** (heat/police is stage F, not built).
- **No UI sounds** (the UI bus exists but nothing plays on it).

**The exe has no sound (relevant, and first).** The first Windows build from #191 showed no entry in the Windows volume mixer, meaning the audio device was never opened. Every improvement below is worth nothing to a player until that is fixed. Likely causes to check, in order: the export forcing the Dummy driver (all tests run `--audio-driver Dummy`, so a launcher or shortcut copied from a test command would carry it), an export preset excluding `default_bus_layout.tres`, or the Master bus being muted by a saved settings file. The diagnosis is already with the exe thread; this research does not duplicate it.

## 2. How other racing games do it (the useful tricks)

From Ben Minto's Burnout retrospective (Designing Sound, 2017), BOOM Library's engine primer, Audiokinetic's engine modelling article and Godot's docs:

- **Traffic pass-bys are one-shots, not engines.** Burnout triggered a pre-made "whoosh-by" sample timed from closing speed so its loudest point lands exactly as the car passes you, with a sample per object type (car, truck, racer). Far cheaper than running an engine per car and sounds better.
- **Exaggerated Doppler ("the Minto effect").** Volume raised to a power for sharper attack and decay, pitch sloping up on approach and down after, so passing feels faster than it is.
- **Static near-miss whooshes.** Rays fan forward from the car, wider with speed. A short hit = small whoosh (lamppost), a long hit = big whoosh (bridge, tunnel mouth). Huge sense of speed for very little code.
- **Crashes are a collage plus a bed.** One-shots per physical event (panel hit, glass, scrape, wheel) on top of a longer "mangling" stream whose volume follows crash intensity. Two banks of 20 variants alternated so nothing repeats.
- **Avoid fatigue at speed.** Engine, road, transmission and turbo use different pitch relationships so a long flat-out run is not one tiring whine. Burnout's boost used a Shepard-tone climb that seems to rise forever.
- **Mix states.** Burnout pushed music louder and focused the mix during boost. Modern games call these mix snapshots: cruise, pursuit, crash, pause.
- **Engine realism ladder.** Sampled loops at fixed RPMs (Forza recorded 320+ cars for FH5), then granular synthesis from a few recorded ramps (Audiokinetic, AudioMotors). Our synth sits at the cheap, stylised end, which fits the look.
- **New option for real-sounding engines cheaply:** [engine-sim](https://github.com/ange-yaghi/engine-sim) (MIT licence, Windows, real time) physically simulates an engine and its exhaust. It could be run once, offline, to record loops for each of our 12 car voices: option A from the original proposal ("A if it gets cheap") without buying a library. Unverified: whether its output records cleanly to file; that needs one test.

## 3. What Godot 4.7 gives us cheaply

| Feature | What it does for us | Cost |
|---|---|---|
| `AudioStreamPlayer3D` + `doppler_tracking` (on player and camera) | Positional traffic, sirens, helicopter, with Doppler | Cheap per voice; keep to ~20-30 live voices, always set `max_distance` |
| `Area3D` reverb bus override (`reverb_bus_enabled`) | Drive under an overpass or between tall buildings and the sound changes automatically | One reverb effect on a bus, near free |
| `AudioEffectCompressor` with sidechain | Music dips a little under engine load instead of being turned down | Free |
| `AudioStreamRandomizer` | Random pitch, volume and variant per play: kills repetition (ROADMAP item 10) | Free |
| `AudioStreamPolyphonic` | Many one-shots (crash debris) from one player | Cheap |
| `AudioStreamInteractive` / `Synchronized` (4.3+) | Heat-driven music layers that switch on the beat | Cheap |
| `AudioStreamGenerator` (what the engine and radio static use) | Live synthesis | **The expensive part.** Filled per sample in GDScript. Fine for one engine; not for 12 traffic cars. |
| GDExtension (C++) | Moves the synth out of GDScript; roughly 10-50x faster per sample | One-time setup on Roy's laptop; adds a native build step |
| Steam Audio GDExtension (HRTF, occlusion) | Headphone 3D realism | **Not recommended**: CPU heavy for an i5-1235U with integrated graphics, and the extension's maturity on 4.7 is unknown |

**Key trick for traffic:** `tests/engine_audio_render.gd` already renders the synth to a WAV. The same code can bake a few-second loop per NPC voice at load time, then traffic plays those loops through cheap `AudioStreamPlayer3D`s with pitch following speed. Same character as the player's engine, near-zero CPU.

CPU note: the audio cost of the current game has not been profiled. Before adding many 3D voices, one benchmark run with audio on (not Dummy) should measure it.

## 4. Ranked options

Cost uses the ROADMAP scale (S = one PR, M = a few, L = several or heavy assets). Payoff is how much a player would notice.

| # | Option | Cost | Payoff | Blocked on |
|---|---|---|---|---|
| 0 | **Exe plays sound at all** (fix the build) | S | Everything | Nothing; in the exe thread |
| 1 | **Traffic comes alive**: baked synth loops per NPC voice on `AudioStreamPlayer3D`, exaggerated Doppler, Burnout-style pass-by whoosh timed to closing speed, horns (already decided yes), blinker tick for the 2 s signal | M | Very high: traffic is currently silent and is half of what you hear in a city | Traffic overhaul thread (horn and blinker rules) |
| 2 | **Speed you can hear**: static near-miss whooshes from forward rays (lampposts, parked cars, pillars), reverb zones for overpasses and building canyons | S-M | High: the cheapest big sense-of-speed win | Road needs overpasses or tall-building stretches for reverb to matter (fits the "feels like a map" road change Roy asked for) |
| 3 | **Crashes and scrapes**: impact one-shots scaled by the `dv` the camera already measures, glass and panel layers, a looping metal scrape while touching walls or cars, variants via `AudioStreamRandomizer` | M | High: hitting something silently feels broken | Needs sound sources (question 1). Damage (stage C) adds more events later but is not required to start |
| 4 | **Night city bed**: distant traffic hum, far-off sirens, dogs, AC units, a train, per-district mix later | S-M | Medium: fills silence when stopped or slow; supports district identity | Sources (question 1) |
| 5 | **Mix polish**: sidechain music under engine, mix snapshots (pursuit, crash, pause), repetition pass (ROADMAP 10), UI sounds for menus and the tuner | S | Medium, felt everywhere | Nothing |
| 6 | **Police and heat**: 3D sirens with wail / yelp / hi-lo switching by distance and behaviour, scanner chatter (radio squelch plus captions), helicopter rotor that thumps overhead and muffles at distance, heat-driven music layer | M | Very high once police exist | Stage F; helicopter research thread |
| 7 | **Engine next step**: either (a) port `EngineSynth` to C++ and add intake and induction layers plus fatigue-avoiding pitch relationships, or (b) record our 12 voices from engine-sim and play them as sampled loops (option A) | L | High for car fans, but the current engine already works | A listening test of engine-sim first |
| 8 | **Tyre and surface detail**: painted lines, manholes, wet road hiss (if rain ever comes), brake squeal, suspension creak in the cockpit | S | Low-medium | Nothing |

**Not recommended now:** HRTF / Steam Audio (CPU), fully live synthesis per traffic car (CPU), licensed sample libraries (cost, and the licence log rules).

## 5. Recommendation

1. **Fix the silent exe first** (0). Nothing else is audible to players until then.
2. **Then one "the street comes alive" stage: 1, then 2, then 3**, in that order. Silent traffic and silent crashes are the two most noticeable gaps; both are mostly cheap code on top of systems that already exist (the synth, the camera's impact measure, traffic cars).
3. **Do 5 alongside** as small PRs; it makes everything else sound better.
4. **Police audio (6) waits for stage F**, but its design should land with the helicopter research so the siren, rotor and music plan are one piece.
5. **Engine (7): run one engine-sim listening test** before deciding between polishing the synth and switching to recorded loops. Opus for the C++ port if chosen (DSP plus native build is reasoning-heavy).

**How testing should work (Roy's "play with the sliders" point applies here too).** Tests run on the silent Dummy driver, so they can only check numbers. Each audio PR should also render a short **listen pack**: WAV clips of the same scenario with the sliders swept (volume buses at low, mid, max; chase and cockpit; slow, mid and top speed; each car voice), so Roy can judge by ear without playing. `tests/engine_audio_render.gd` already does this for the engine; the same pattern extends to every layer.

## 6. Questions for Roy

1. **Sound sources for crashes and city ambience:** free recorded packs (CC0, or the Sonniss GDC bundle, which allows commercial use), or synthesised only? *Recommended: recorded. Crashes are very hard to synthesise convincingly.*
2. **Traffic engines:** should every NPC car have its own audible engine as it passes? *Recommended: yes, using baked loops.*
3. **Siren style:** US wail / yelp / hi-lo, matching the US traffic rules? *Recommended: yes.*
4. **Police scanner chatter:** voiced, or radio squelch with captions only? *Recommended: captions plus squelch for now, same as the open Dale audio-vs-captions question.*
5. **Music in a pursuit:** keep the radio playing and add a tension layer under it, or switch to pursuit music? *Recommended: keep the radio, add a layer.*
6. **Engine:** keep polishing the synth, or test engine-sim recordings first? *Recommended: test engine-sim first (one session, no commitment).*
7. **Start order:** traffic sound, then speed whooshes and reverb, then crashes? *Recommended: yes.*

## Sources

- [Burnout: a sound design retrospective with Ben Minto, Designing Sound](https://designingsound.org/2017/08/31/burnout-a-sound-design-retrospective-with-ben-minto/)
- [3D audio and spatial sound in Godot 4, UhiyamaLab](https://uhiyama-lab.com/en/notes/godot/3d-audio-spatial-sound/)
- [Audio streams, Godot docs](https://docs.godotengine.org/en/4.4/tutorials/audio/audio_streams.html)
- [Engine sound modelling: from sampling to granular synthesis, Audiokinetic](https://www.audiokinetic.com/engine-sound-modeling-from-sampling-to-granular-synthesis-in-wwise)
- [How to make racing car engines roar using AudioMotors, MCV](https://www.mcvuk.com/development/how-to-make-racing-car-engines-roar-using-audiomotors-fmod)
- [Forza Horizon 5 audio improvements, 320+ new car recordings, Windows Central](https://www.windowscentral.com/forza-horizon-5-audio-improvements-stream)
- [engine-sim by Ange Yaghi (MIT)](https://github.com/ange-yaghi/engine-sim)
- `PROPOSAL-audio.md` (2026-09-29) for the original engine options A / B / C
