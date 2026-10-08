# Better sound for Neon Overdrive: research (2026-10-08)

Docs only, no code. Asked by Roy: "how can we build even better sound for this game? research."
Source of every repo claim: `main` at `09455e0`, fetched 2026-10-08 ~11:45Z.

## 0. Roy's answers (2026-10-08 12:00Z) and what changed in this doc

- **Asset rule for the whole game:** free, no payment, **no credit or attribution**, OK to sell. Recorded sounds are fine if they meet that. Section 3b lists the sources that pass and the ones that fail.
- Q1 recorded if free under that rule: **yes**. Q2 every traffic car audible: **yes**. Q3 US sirens: **yes**. Q4 captions + squelch: **yes**, plus research police voices, characters and voicelines (section 7). Q5 radio keeps playing with a pursuit layer: **yes**. Q6 engine-sim test first: **yes**. Q7 start order: **yes**.
- **New complaints:** tyre sound, shifting sound and wind sound are poor, and crashes and collisions are too quiet. Section 1b says why each one sounds wrong, from the code, and the fix. The ranking in section 4 now puts these first after the exe fix.

**Round 3 answers (2026-10-08 12:29Z):** police Q1 captions now: **yes**. Q2 cast of 5: **yes, but some of them are corrupt and work with Pike**, allied with Pike yet hostile to the player, because Pike uses racers against us; research it (section 7b; the story side is in another thread). Q3 chatter describes your car: **yes**. Q4 Sonniss download: **yes**. Q5 cockpit window: **an in-game control**, closed-window cockpit sound, a window that opens gradually, fully open approaching outside sound (section 9).

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

## 1b. Why tyres, shifting, wind and crashes sound wrong (from the code)

All four are generated in code from white noise and sine waves (`car_audio.gd`, `driveline_audio.gd`). That kept them free of licences, but it is why they sound thin.

| Sound | What the code does now | Why it sounds wrong | Fix |
|---|---|---|---|
| **Tyres** | One 2 s loop of noise through three fixed tones (820, 1290, 1910 Hz), at 22 kHz. Volume follows the worst-slipping wheel; pitch moves only 0.85-1.1x. | Every slide is the same sound at the same pitch. No difference between a scrub (understeer), a drift, a wheelspin chirp or a brake lock-up. Low sample rate dulls it. Mono, so a slide on the left sounds the same as on the right. | Recorded loops (CC0 / Sonniss) for **four kinds** of tyre noise: scrub, squeal, wheelspin, lock-up, each picked by which slip the physics reports (sideways vs forward, driven vs braking wheel). Crossfade two takes per kind so it never loops audibly. Per-axle left/right pan. Add a short **chirp** one-shot on hard shifts and launches. |
| **Road roar** | Brown noise, pitch rises with speed. | Pitch-shifting noise reads as a tape speeding up, not as a faster car. | Recorded tyre-on-asphalt rolling loop; with speed, raise volume and open a filter instead of raising pitch. Change texture over manholes, painted lines and kerbs. |
| **Wind** | Two filtered noises mixed, 0.5 Hz swell, pitch rises with speed. | Same pitch-shift problem: it sounds like hiss getting higher. Real wind at speed is a low **buffet** plus a **whistle** from the mirrors and pillars, and it gusts. | Recorded wind loop at two speeds, crossfaded by speed; a filter opens with speed instead of pitch. Add random gusts, a faint whistle above about 150 km/h, and a stronger buffet in the cockpit when a window is "open" (or always in chase). Pan slightly in long corners. |
| **Shifting** | A 0.22 s 55 Hz thump, the **same sample every time** (fixed random seed). Up- and down-shifts sound identical. | Real shifts are several sounds in a row: throttle cut, clutch, a mechanical **clack** of the gearbox, the engine note dropping, then load coming back. Ours is one identical bump. | Build each shift from 3 layers: gearbox clack (recorded, 4-6 variants via `AudioStreamRandomizer`), the engine note dip (the synth already sees the throttle cut, make it audible), and for downshifts a **throttle blip**. In the cockpit add the lever's knock. Modded cars get an upshift "blat" from the exhaust pops. |
| **Crashes and collisions** | Nothing. The camera measures how hard you hit (`register_impact(dv)`), but no sound plays. | Silence on impact feels like a bug. | Impact layers scaled by `dv`: light tap, body thud, heavy crunch, glass, plus a looping **metal scrape** while sliding along a wall or car, and a tyre **bump** for kerbs. Recorded, 4-8 variants each, random pitch. Traffic cars you hit play their own crunch from their position (3D). |

**What stays synthesised:** the engine (it is the game's character, and engine-sim is being tested), turbo, gear whine and the radio. Sirens can also be synthesised: a siren is a swept tone, so a code-made wail, yelp and hi-lo sound real and need no licence check.

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

## 3b. Free sound sources that pass the asset rule

Rule: free, no payment, no credit, OK in a sold game. Checked against each licence page on 2026-10-08.

| Source | Passes? | Why | Good for |
|---|---|---|---|
| **Sonniss GDC Game Audio Bundle** (free yearly, tens of GB, 2015 onward) | **Yes** | Licence v2.0: royalty-free, commercial use including games, "without attribution". Limits: do not resell the raw sounds as a pack, do not use them to train AI. Both fine for us. | Car crashes, glass, metal, tyres, wind, city ambience, sirens, helicopters. The best single source. |
| **Freesound.org, CC0 filter only** | **Yes, CC0 files only** | CC0 = public domain, no credit. Must filter by licence: many Freesound files are CC-BY (credit) and fail. Needs a free account to download. | Specific gaps: a particular gearbox clack, a manhole clunk. |
| **Pixabay sound effects** | **Yes** | "Use content without having to attribute the author"; only ban is reselling the sound by itself. Some uploads can trigger YouTube Content ID claims on gameplay videos, so log each file. | Ambience, impacts. |
| **Kenney audio packs** | **Yes** (CC0) | Small, more UI and arcade. | UI clicks for menus and the tuner. |
| **OpenGameArt** | **Only CC0 entries** | Per-file licences; many are CC-BY or GPL. | Occasional. |
| Our own synthesis | **Yes** | We made it. | Engine, sirens, turbo, gear whine, radio. |
| BBC Sound Effects, YouTube Audio Library, Zapsplat free tier, Incompetech, anything CC-BY | **No** | Need credit or forbid commercial use. | - |

**How the files get in:** `docs/audio-licences.md` already requires one row per file before it is added. That log gets a column "credit required: no" and the rule above. Sonniss bundles are big; Roy (or a laptop session) downloads one year's bundle once, and a session picks the needed files out of it.

## 4. Ranked options

Cost uses the ROADMAP scale (S = one PR, M = a few, L = several or heavy assets). Payoff is how much a player would notice.

| # | Option | Cost | Payoff | Blocked on |
|---|---|---|---|---|
| 0 | **Exe plays sound at all** (fix the build) | S | Everything | Nothing; in the exe thread |
| 0b | **Fix what Roy hears now**: tyres (4 kinds, recorded), road roar and wind (filter, not pitch), shifting (3-layer, varied), crashes and scrapes (section 1b) | M | Very high: these are the sounds you hear every second | Sonniss download (no other blocker) |
| 1 | **Traffic comes alive**: baked synth loops per NPC voice on `AudioStreamPlayer3D`, exaggerated Doppler, Burnout-style pass-by whoosh timed to closing speed, horns (already decided yes), blinker tick for the 2 s signal | M | Very high: traffic is currently silent and is half of what you hear in a city | Traffic overhaul thread (horn and blinker rules) |
| 2 | **Speed you can hear**: static near-miss whooshes from forward rays (lampposts, parked cars, pillars), reverb zones for overpasses and building canyons | S-M | High: the cheapest big sense-of-speed win | Road needs overpasses or tall-building stretches for reverb to matter (fits the "feels like a map" road change Roy asked for) |
| 3 | ~~Crashes and scrapes~~: moved into 0b | | | |
| 4 | **Night city bed**: distant traffic hum, far-off sirens, dogs, AC units, a train, per-district mix later | S-M | Medium: fills silence when stopped or slow; supports district identity and Roy's "the world doesn't feel real" point | Sonniss download |
| 5 | **Mix polish**: sidechain music under engine, mix snapshots (pursuit, crash, pause), repetition pass (ROADMAP 10), UI sounds for menus and the tuner | S | Medium, felt everywhere | Nothing |
| 6 | **Police and heat**: synthesised 3D sirens with wail / yelp / hi-lo switching by distance and behaviour, scanner chatter (section 7), helicopter rotor that thumps overhead and muffles at distance, heat-driven music layer | M | Very high once police exist | Stage F; helicopter research thread |
| 7 | **Engine next step**: either (a) port `EngineSynth` to C++ and add intake and induction layers plus fatigue-avoiding pitch relationships, or (b) record our 12 voices from engine-sim and play them as sampled loops (option A) | L | High for car fans, but the current engine already works | A listening test of engine-sim first |
| 8 | **Surface extras**: wet road hiss (if rain ever comes), brake squeal, suspension creak in the cockpit | S | Low-medium | Nothing |

**Not recommended now:** HRTF / Steam Audio (CPU), fully live synthesis per traffic car (CPU), licensed sample libraries (cost, and the licence log rules).

## 5. Recommendation

1. **Fix the silent exe first** (0). Nothing else is audible to players until then.
2. **Then fix the sounds Roy hears every second (0b):** tyres, wind, road roar, shifting, crashes. One stage, a few PRs, using Sonniss recordings.
3. **Then "the street comes alive": 1, then 2** (traffic, then whooshes and reverb), the order Roy approved.
4. **Do 5 alongside** as small PRs; it makes everything else sound better.
5. **Police audio (6) waits for stage F**, but its design should land with the helicopter research so the siren, rotor and music plan are one piece.
6. **Engine (7): run one engine-sim listening test** (approved) before deciding between polishing the synth and switching to recorded loops. Opus for the C++ port if chosen (DSP plus native build is reasoning-heavy).

**How testing should work (Roy's "play with the sliders" point applies here too).** Tests run on the silent Dummy driver, so they can only check numbers. Each audio PR should also render a short **listen pack**: WAV clips of the same scenario with the sliders swept (volume buses at low, mid, max; chase and cockpit; slow, mid and top speed; each car voice), so Roy can judge by ear without playing. `tests/engine_audio_render.gd` already does this for the engine; the same pattern extends to every layer.

## 6. Answered questions (round 1)

All seven answered yes (section 0). Kept here for the record: recorded sounds under the asset rule; every traffic car audible; US wail / yelp / hi-lo sirens; scanner chatter as captions plus squelch, with voices researched; radio keeps playing with a pursuit layer; engine-sim test first; build order traffic, whooshes and reverb, crashes (crashes now moved up into 0b because Roy flagged them).

## 7. Police voices, characters and voicelines

**How the best games do it.** Need for Speed: Most Wanted (2005) is still the reference: a dispatcher and several unit officers talk over a radio filter, and the lines are assembled from pieces (unit call sign + what they see + your car's colour and type + street or direction), so the chatter describes *your* chase. Officers have personalities (calm veteran, nervous rookie, angry sergeant), and the tone climbs with heat: routine, then "suspect fleeing", then roadblocks and spike strips, then the helicopter. Losing them is its own set of lines ("lost visual", "search the area").

**Cast (placeholders; names and writing are Roy's):**

| Character | Role | Voice |
|---|---|---|
| Dispatcher | Calm, tired night-shift voice; reads plates, assigns units | Even, flat, the steady centre |
| Unit 1 (veteran) | First car on you at low heat | Dry, unhurried |
| Unit 2 (rookie) | Joins at heat 2, makes mistakes, over-excited | Fast, breathless |
| Sergeant | Calls roadblocks and spike strips at heat 3 | Hard, short |
| Air unit | Helicopter observer at max heat; calls your turns from above | Clipped, rotor noise behind the voice |

**Line categories** (each needs 3-6 variants so nothing repeats): spotted you, describe car (colour, type), direction of travel, you sped up, near miss or you hit a car, you hit a cop, requesting backup, roadblock set, spike strip set, air unit on scene, lost visual, searching, regained visual, pursuit called off, busted. Plus fill-ins: street or district name, colour, car type, so lines can be stitched. Real US scanner style is mostly plain language plus a few codes like "10-4" that vary by department; keeping it plain is easier to follow.

**How we make the voices, within the asset rule:**

- **Text to speech, run offline, then a radio filter.** From the existing `voice-ai-research.md`: **Chatterbox** (MIT licence) passes the rule: free, sold games fine, and the audio it produces needs no credit. It runs on the laptop's CPU in batches and has an emotion knob (calm dispatcher low, rookie high). **Kokoro** (Apache 2.0) also passes and is fine for the flat dispatcher. **Orpheus fails the rule** (its Llama licence needs a "Built with Llama" credit), so it is out. ElevenLabs free tier fails (credit required, no commercial use).
- **Reference voices** for Chatterbox must be synthetic or Roy's own recordings (or a friend with signed consent), never a real actor or streamer.
- **The radio filter hides most TTS flaws:** band-pass 300-3400 Hz, light distortion, squelch click and static at start and end. A police radio is supposed to sound rough, which makes this the best place in the game to use TTS.
- **Steam note:** Steam asks for an AI-content disclosure on the store page for pre-made AI voices. That is a store checkbox, not a credit, so it does not break the rule.
- **Recorded voice packs:** no free, no-credit police chatter pack of usable size was found. Sonniss has some radio squelch and static, which we need anyway.

**Captions:** every line also shows as a caption (already decided), so voices can come later without changing the system.

## 7b. Corrupt cops working with Pike (voices, characters, lines)

Story is Roy's to write; everything here is placeholder structure for him to pick from.

**How other games did it.** Need for Speed Heat (2019) is the closest match: a police task force run by a corrupt lieutenant who uses the badge to steal racers' cars and money, while ordinary officers just chase you. GTA San Andreas does the same with a corrupt officer who leans on the player. The pattern that works: **most cops are honest and just doing their job; a small, named group is dirty**, and the player slowly learns who. That keeps chases fair while giving the story a villain inside the police.

**Why would cops side with Pike and hate us?** Three motives the story can use (one or mixed):

| Motive | How it works | Why they hate the player |
|---|---|---|
| **Pike pays them** | Cash or free repairs for looking away from Pike's crew | The player costs Pike money, so the payments are at risk |
| **Pike feeds them arrests** | Pike's racers bait rival racers (including you) into police traps; the cops get easy busts and promotions, Pike loses competition | Every time you escape, their numbers and their deal look bad |
| **Pike owns them** | A debt or a secret Pike holds over them | You might expose the arrangement |

**Who's who in the cast of 5 (a starting proposal):**

| Character | Honest or Pike's? | How it shows in the radio chatter |
|---|---|---|
| Dispatcher | Honest, unaware | By the book; occasionally confused when units ignore her calls |
| Veteran unit | **Pike's man** | Goes quiet or "loses visual" when Pike's racers pass; personal and nasty toward you ("this one's mine") |
| Rookie | Honest | Over-eager; notices things that don't add up ("Sarge, wasn't that Pike's car?"). A possible ally later |
| Sergeant | **Runs the dirty side** | Orders roadblocks that happen to trap you and let others through; switches units to "channel 2" |
| Air unit | Honest | Calls everything it sees from above, including things the dirty units would rather it didn't |

**Ways the player hears the corruption (sound and captions):**
- **Off-channel talk:** the sergeant says "switch to two", and a few lines later the player's radio catches a crackly private exchange ("Pike says the blue coupe goes down tonight"). Captions mark it as a different channel, with a different caption colour.
- **Tell-tale orders:** dirty units call off the chase when a Pike racer is involved, or pile extra units onto you.
- **Scanner as an item:** a police scanner bought from a gas station vendor (ties into the vendor-items research) lets the player hear the private channel at all. Without it, only the public channel.
- **Line categories to add** to section 7's list: talking about Pike in code, letting a Pike racer go, singling you out, honest unit questioning a dirty one, dirty unit shutting them down.

**Voices:** same TTS-plus-radio-filter plan as section 7. The dirty units' private channel gets a slightly different filter (narrower, more static) so the ear learns it.

## 8. Round 2 questions: answered

Captions now; cast of 5 with some corrupt; chatter describes your car; Sonniss download yes; cockpit window as an in-game control (section 9).

## 9. Cockpit window control

Roy wants the window in-game: closed-window cockpit sound, a window that opens gradually, and fully open sounding close to outside. The game already has the pieces: `perspective_audio.gd` blends every bus between "cockpit" and "chase" with a low-pass filter. The window adds a second dial inside the cockpit.

**What changes as the window opens (0% closed to 100% open):**

| Layer | Closed (0%) | Cracked (10-30%) | Fully open (100%) |
|---|---|---|---|
| Wind | Quiet seal whistle above about 120 km/h | **Throb**: the low pulsing pressure real cars make with one window cracked; loudest here | Loud full rush and buffet, gusting |
| Engine and exhaust | Muffled (cabin low-pass, about 3.6 kHz) | Slightly brighter | Exhaust much clearer, close to the chase sound |
| Tyres and road | Low rumble through the floor | Some hiss returns | Full road roar and squeal from outside |
| Traffic, sirens, city | Faint | Clearer | **Heard much sooner and in direction.** Gameplay effect: you hear cops coming earlier |
| Radio | Clear, the loudest thing in the cabin | Slightly masked | Competes with the wind; quieter by comparison (the player can turn it up) |

**The trade-off makes it a choice, not a setting:** window up = quiet, clear radio; window down = you hear the world and the police first, at the cost of noise.

**Controls (keyboard only, no on-screen hints):** one key rolls the window down while held and back up with a tap. The window glass animates in the cockpit so you can see the level. The chase camera always uses outside sound, whatever the window does. The level is remembered per drive.

**Cost:** S. One extra value in `perspective_audio.gd`, a wind-throb layer, the glass animation, a key. Testable on the silent driver by asserting filter cutoffs and levels at 0%, 25% and 100%, and a listen pack at those three positions.

## 10. New questions for Roy

1. **Window key:** Z (hold to roll down, tap to roll up)? Z is currently unused. *Recommended: Z.*
2. **Corrupt cops:** start with the sergeant and the veteran as Pike's men (dispatcher, rookie and air unit honest)? *Recommended: yes. Story details stay yours.*
3. **Scanner item:** should hearing the dirty cops' private channel need a scanner bought at a gas station? *Recommended: yes. It gives the vendor a meaningful item.*

## Sources

- [Burnout: a sound design retrospective with Ben Minto, Designing Sound](https://designingsound.org/2017/08/31/burnout-a-sound-design-retrospective-with-ben-minto/)
- [3D audio and spatial sound in Godot 4, UhiyamaLab](https://uhiyama-lab.com/en/notes/godot/3d-audio-spatial-sound/)
- [Audio streams, Godot docs](https://docs.godotengine.org/en/4.4/tutorials/audio/audio_streams.html)
- [Engine sound modelling: from sampling to granular synthesis, Audiokinetic](https://www.audiokinetic.com/engine-sound-modeling-from-sampling-to-granular-synthesis-in-wwise)
- [How to make racing car engines roar using AudioMotors, MCV](https://www.mcvuk.com/development/how-to-make-racing-car-engines-roar-using-audiomotors-fmod)
- [Forza Horizon 5 audio improvements, 320+ new car recordings, Windows Central](https://www.windowscentral.com/forza-horizon-5-audio-improvements-stream)
- [engine-sim by Ange Yaghi (MIT)](https://github.com/ange-yaghi/engine-sim)
- [Sonniss GDC bundle licence v2.0](https://sonniss.com/gdc-bundle-license/)
- [Pixabay content licence summary](https://pixabay.com/service/license-summary/)
- [Need for Speed Heat (2019), Wikipedia](https://en.wikipedia.org/wiki/Need_for_Speed_Heat)
- [Need for Speed: Most Wanted (2005), Wikipedia](https://en.wikipedia.org/wiki/Need_for_Speed:_Most_Wanted_(2005_video_game))
- `voice-ai-research.md` (project files, 2026-10-07) for TTS licences
- `PROPOSAL-audio.md` (2026-09-29) for the original engine options A / B / C
