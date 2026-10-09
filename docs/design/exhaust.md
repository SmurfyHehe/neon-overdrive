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
