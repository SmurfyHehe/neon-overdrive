# Exhaust (stage B step 2)

Four knobs, each 0..1, all **cosmetic only**: no wear, heat, fuel, police or
physics effect (Roy's stage B decision).

| Knob | Does |
|---|---|
| loudness | scales the whole exhaust note (0.5 = the old prototype level) |
| raspiness | opens the rasp band, adds noise, sharpens each pulse |
| pops | overrun pops and crackles when the throttle is lifted at rpm; also bangs when the rev limiter cuts a firing |
| flame | sizes the flame events pops and limiter bangs produce; 0 = no flames |

- Code: `scripts/exhaust_tune.gd` (knobs and the 12 per-car presets),
  `scripts/engine_synth.gd` (sound; `take_flames()` hands out flame events).
- Test: `tests/exhaust_tune.gd` (each knob moves what it should, presets in
  range, WAVs written to `user://exhaust_*.wav` for listening; silent).
- **Flame visuals are not built.** `take_flames()` returns the biggest flame
  (0..1) since the last call. Drawing flames at the exhaust tips waits for
  stage B step 5, when the cars are built from `fleet.json` (which already has
  the tip positions).
- **Where it is edited:** the Exhaust page of the Tuner screen (T): loudness, raspiness, pops and flame sliders, plus a reset to the car preset. The old held playtest keys (U/J, I/K, O/L) are gone. Changes save to disk once the game resumes.
- **Presets are mostly judgement calls.** No per-car dB or pop data is
  published. Sources and reasoning are in the comment above `PRESETS`.
