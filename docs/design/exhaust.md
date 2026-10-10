# Exhaust (stage B step 2)

Four knobs, each 0..1, all **cosmetic only**: no wear, heat, fuel, police or
physics effect (Roy's stage B decision).

| Knob | Does |
|---|---|
| loudness | scales the whole exhaust note (0.5 = the old prototype level) |
| raspiness | opens the rasp band, adds noise, sharpens each pulse |
| pops | overrun pops and crackles when the throttle is lifted at rpm; also bangs when the rev limiter cuts a firing |
| flame | sizes the flame events pops and limiter bangs produce; 0 = no flames |

- Code: `scripts/tuning/exhaust_tune.gd` (knobs and the 12 per-car presets),
  `scripts/audio/engine_synth.gd` (sound; `take_flames()` hands out flame events).
- Test: `tests/audio/exhaust_tune.gd` (each knob moves what it should, presets in
  range, WAVs written to `user://exhaust_*.wav` for listening; silent).
- **Flame visuals are not built.** `take_flames()` returns the biggest flame
  (0..1) since the last call. Drawing flames at the exhaust tips waits for
  stage B step 5, when the cars are built from `fleet.json` (which already has
  the tip positions).
- **Where it is edited:** the Exhaust page of the Tuner screen (T): loudness, raspiness, pops and flame sliders, plus a reset to the car preset. The old held playtest keys (U/J, I/K, O/L) are gone. Changes save to disk once the game resumes.
- **Presets are mostly judgement calls.** No per-car dB or pop data is
  published. Sources and reasoning are in the comment above `PRESETS`.

## Pop voice (2026-10-07)

Option A of exhaust-sound-research-2026-10-07: a dedicated crackle/pop voice
in `engine_synth.gd`. Every pop request becomes a **cluster** of bangs; each
bang is a noise crack, a low boom and a kick into two decaying resonators (the
tailpipe ringing, tuned off `body_hz`, so each car's pipe rings in its own key).

| Trigger | Cluster |
|---|---|
| overrun lift (pops knob) | burble: 2-4 bangs, 25-70 ms apart |
| rev limiter cut (pops knob) | 1-2 bangs, 15-30 ms apart |
| anti-lag switch on a lift | 3-6 bangs, 12-35 ms apart: machine-gun crackle |
| flat-out upshift | 1-2 hard bangs, longest ring; only at flame >= 0.4 |

- The upshift bang uses the same law and threshold as the upshift flame
  (`ExhaustFlames.upshift_spits`, `UPSHIFT_FLAME_MIN`) and fires in auto, semi
  and manual. It hands out no flame event: the flame node queues its own.
- Flames still come from the pop requests with the 60 ms visual delay, so fire
  and sound stay in sync. Traffic has no engine audio; the C3 interceptor's
  traffic flames are unchanged.
- Test: `tests/audio/exhaust_pops.gd` (WAVs to `user://exhaust_pop_*.wav`).

## Turbo voice (B1, 2026-10-09)

The turbo has its own synth (`scripts/audio/turbo_synth.gd`) on its own stream
and bus (**Turbo**, with a slider next to Engine in the volume settings:
`AudioSettings.CHANNELS` is the hook the Sound page iterates). Until B1 the
whistle was a term inside the engine mix on the Engine bus. All of it is code,
no recordings.

A car's voice is `spec["turbo_voice"]` (`scripts/audio/turbo_voice.gd`, like
`engine_voice`): a **part** and a **valve**, cosmetic only.

| Part | Whistle | Where |
|---|---|---|
| small | 4.2-8.6 kHz, clean, quick flutter | p2 hot hatch |
| medium | 3.0-7.0 kHz, a second partial, some air | p3 tuner, p6 crossover, any Tuner-added turbo |
| big | 2.8-5.4 kHz, airy, a slow heavy flutter | nobody yet |

The whistle climbs with boost (the Tuner's bar slider stretches how far) and
stays above the cockpit mirror whistle's 1.25 / 2.5 kHz tones.

| Valve | Sound | Where |
|---|---|---|
| recirc | a short muffled puff back into the intake (stock) | p2, Tuner-added turbos |
| atmo | the loud bright "pssh", a thin ring off the valve body | p3 |
| flutter | no valve: the compressor surges, a chopped "stu-tu-tu" that drags the whistle down | p6 |

| Trigger | Vent |
|---|---|
| throttle lift on boost (GEVP's one-tick cut, or the eased-off ramp) | 0.3-0.9 s, size and length from the boost dumped |
| between gears on boost (`is_shifting` edge) | the same voice at a bit over half the length |
| both in one 150 ms window | one event: a lift wins over a shift |

- The Turbo bus gets the cockpit low-pass and dB offset like the Engine bus
  (`PerspectiveAudio`) and is muted with it on pause (generator underruns click).
- Test: `tests/car/turbo.gd` (parts whistle at their own pitch, valves differ,
  vent lengths, the fold, the bus and its channel, live lift on the player car).

## Flame visuals v3: look A "shed fire" (2026-10-10)

Roy: the v2 fireball that followed the car looked outdated. Decided look A.
Code: `scripts/fx/exhaust_flames.gd` (ExhaustFlames), `scripts/fx/heat_shimmer.gd`
(HeatShimmer). Test: `tests/fx/exhaust_flames.gd`.

- **What the player sees:** a short tight white-amber tongue at the pipe (two
  crossed strips, so it reads from behind), which breaks into 1-3 ragged
  lobes that **stay on the road where they were spat** (`LOBE_CARRY` 0.05, was
  0.5) and stretch into a streak along the car's travel as it pulls away; the
  edges go dark brown, then a thin grey smoke wisp. Upshift at full throttle
  = one big "bwap" with 3 lobes; anti-lag = a rattling string of small lobes
  left down the road; limiter = short stutters.
- **One quad per lobe, two layers in one pass** (premultiplied blend): a hot
  additive core and a dark see-through soot rim. No separate smoke puff, no
  textures. Animation stepped to about 24 fps (`STEP`) for the PS2 feel. A
  new random shape per lobe.
- **Knobs:** pops = how often (unchanged); flame = size AND lobe count
  (0.1 one small spit, 1.0 three big lobes and a longer tongue).
- **Bone car (ghost style):** the same shaders with a ghost-green set (pale
  white-green core, #B8F28A, dark olive edge), a steady jet while the throttle
  is down, an afterburner (`set_afterburner`) that lengthens it and draws
  shock diamonds, and green V8 pops. `spec.fire_style = "ghost"` or
  `set_style(Style.GHOST)`. The bone car itself is not on main yet.
- **Heat shimmer:** one manager with 6 screen-refraction quads for the 6
  nearest hot cars within 25 m (the player always), re-picked 10 times a
  second; heat = revs x throttle per car, rising over 2.5 s and cooling over
  10 s, stepped in the car's own detailed tick so far cars pay nothing. Never
  in mirrors or the rear strip (render layer 6), off on the Low preset, its
  own switch "heat_shimmer" (pause menu, `--shimmer=0/1` in the benchmark).
