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
