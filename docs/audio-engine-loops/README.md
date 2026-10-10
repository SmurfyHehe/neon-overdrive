# Engine sound loops (2026-10-10)

What it is: the steady engine note now plays from short seamless loops baked
from the same synth, instead of being rendered sample by sample in GDScript
every frame. Pops, limiter bangs, upshift cuts, anti-lag and the turbo stay
live. Every sound is synthesised by this project, so there is nothing to
license or credit (row `sfx-engine-loops` in `docs/audio-licences.md`).

## How it fits together

| Piece | File | Job |
|---|---|---|
| Baker | `scripts/audio/engine_loops.gd` | One loop per rpm band (idle to redline, bands 12 % apart, 19 bands for a 1000-7000 rpm car), at lifted and open throttle. Each loop holds a whole number of engine cycles and its tail is cross-faded into its head. Cached in `user://audio_cache`. |
| Player | `scripts/audio/engine_loop_player.gd` | At most 6 looping players (nearest band and its neighbour at two loads, plus any still fading). Pitch from rpm, level from throttle, limiter chop, slow wander so a held rpm does not repeat. |
| Events | `EngineSynth.render_events()` | The pop voice alone: same clusters, pipe ring and flame events, no per-sample tone loop. |
| Hand-over | `scripts/audio/engine_audio.gd` | The live synth plays from frame one. A worker thread bakes (or loads) the bank; the live note then fades out over 0.12 s as the loops fade in. A change to the Tuner's loudness or raspiness re-bakes in the background. |

`NEON_ENGINE_LOOPS=0` keeps the old live synth for everything (A/B and fallback).

## Results (headless, Roy's laptop, other agents' Godot processes running)

| Check | Result |
|---|---|
| Loop seam, step across the loop point / loudest step inside the loop | worst 0.39 over all 38 loops (the same windows with no cross-fade: 2.99) |
| Loop length | whole engine cycles, true rpm within 0.2 % of the band |
| Bank size per voice | 2.4 MB (16-bit mono, 44.1 kHz) |
| Bake time per voice | about 9-10 s on one worker thread, first run only; reading the cache back: 30-130 ms |
| Synth cost while the loops carry the tone | live synth 3.5-4.6 us/sample, events-only 0.01 us/sample (about 400x less when no bang is sounding) |
| Player script cost | about 55-65 us per frame (60 fps and 20 fps runs) |
| Voices | most 6 looping players at once (cap 6); 0 streams swapped under a sounding voice at 60 and 20 fps; 0 left playing with the engine off |
| Loudness | blend of lifted and open loops within about 1 dB of the live synth at 25, 50 and 75 % throttle (1500, 4000, 6500 rpm) |
| In-game run (Engine bus recorded, full-throttle pull with gear shifts and limiter) | hand-over completes, 173 events-only blocks and no full blocks after it; median sample step 0.025 vs 0.023 live |

Spectrograms (0-8 kHz, time left to right, log-brightness): `engine_loops_sweep_spec.png`
is a clean rev sweep mixed from the bank offline: harmonic lines rise smoothly and
no vertical seam shows at any loop point. `engine_loops_live_loops_spec.png` is the
Engine bus in the game: dark vertical bands are the throttle cuts of upshifts and
the limiter chop at the right; `engine_loops_live_live_spec.png` is the same drive
on the live synth. Regenerate with `tests/audio/engine_loops.gd`,
`tests/audio/engine_loops_live.gd` and `tools/engine_loops_spectrogram.py`.

## What is not verified, and known limits

- Nobody has listened to it. The Dummy audio driver mixes but I cannot hear it.
  Seams, steps, level and spectra are checked; character is Roy's ear.
- Whether Godot ramps player volume across each mix chunk (so a level change is
  never a click) comes from reading the engine's behaviour, not from a test here.
- A 0.75 s loop repeats. A held rpm gets a slow pitch and level drift, and each
  band starts at a random cycle, but a steady note may still read as slightly
  mechanical next to the live synth. A second take per band is the next step if so.
- Pops land up to one block (about 10 ms) later than in the live synth.
- Bands cross-fade over a narrow part of the gap (30 %) because two loops that
  are not phase-locked make the note phase in and out; start phase is taken from
  the playing voice, accurate to the audio clock's granularity (a few ms).
- Only the player car plays loops. Traffic is silent today; when NPC engines
  come, the same bank (baked per voice, shared by every car of that voice) is
  the cheap way to do them.
