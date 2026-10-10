# What traffic costs per frame (measured 2026-10-10)

Measurement only. No game code was changed. Asked for because 40 traffic cars
still feels heavy on Roy's laptop.

## Short answer

1. **The laptop was the biggest cost on the day.** During every run the CPU was
   100% busy with other work (18 Godot processes from other agent sessions and
   four orphaned `find /` scans started on 2026-10-09, each with 5 to 8 hours of
   CPU time), and Windows reported the processor running at about 54% of its
   1.3 GHz base clock. All times below are therefore slow in absolute terms.
   The comments in `traffic_settings.gd` record 0.19 to 0.36 ms per full-sim
   car per tick on the same CPU on 2026-10-06; today the same work took about
   3 to 5 times longer. That ratio is an inference, not a measurement: I had no
   idle laptop to compare against.
2. **The cost is GDScript in the physics tick, not graphics.** At 40 cars on
   main, 25 to 28 ms of a 35 to 39 ms frame is scripts inside
   `_physics_process`. The GPU needs about 4 ms and 430 draw calls at 1152x648,
   with or without traffic.
3. **At 120 Hz the game cannot keep up, so it spirals.** One tick must fit in
   8.3 ms just to run in real time, and in about 4 ms to hold 60 fps. On main
   one tick at 40 cars took 13.5 to 15.5 ms. In the windowed runs the game hit
   the engine's cap of 8 ticks per frame and ran at 7 fps in slow motion.
4. **The other session's unfinished fix is the best build so far**, about 40%
   less frame time than main at 40 cars, but its tick (6.4 to 6.8 ms) is still
   above what 60 fps needs under this load.

## The three biggest wins

| # | Win | Measured size | Cost to build |
|---|---|---|---|
| 1 | Free the laptop before judging: stop the four orphaned `find /` scans, and do not playtest while agents run Godot tests | Not measured directly. Inferred 3 to 5 times faster from the 2026-10-06 figures in `traffic_settings.gd` | Nothing to build. Roy ends four processes. Then one re-run of this sweep (about 75 minutes, unattended) to get clean numbers |
| 2 | Merge near-band traffic (#313) and finish the rails fix now in progress | 40 cars, headless frame: 39.2 / 34.7 ms on main, 31.9 / 28.6 with #313, 22.1 / 21.9 with the unfinished fix. Tick 15.5 down to 6.8 ms | #313 is built and waits for merge. The rails fix is uncommitted work in the other session's worktree; nothing new to start |
| 3 | Run physics at 60 Hz instead of 120 Hz (or tick traffic every other tick) | Not run. Halving the ticks halves the physics buckets: on main at 40 cars about 15 ms of the 39 ms frame, on the fix build about 7 ms of 22 ms | One project setting plus a handling re-test of every car. Project memory says the vendored vehicle breaks at 30 Hz and that 60 Hz needs Roy's call. One agent session and one playtest |

Next after those: **audio**. The engine and turbo synths run on a worker thread
and the main thread waits for them in `EngineAudio._join` (2 to 5 ms per frame
with the profiler on). `TurboSynth.render` (merged 2026-10-09 with #320) is the
largest or second largest single function on both newer builds. PR #315 (engine
synth twice as fast) is open; whether it covers the turbo synth was not
checked. Cost: merge #315, then a small pass on the turbo synth plus a listen.

## Where a frame goes, biggest first

40 cars, headless, script profiler on. The profiler slows the game by about a
third (52 ms per frame against 35 to 39 ms without it), so read these as
shares. Times include everything each system calls.

| System | main | #313 near band | fix in progress | Note |
|---|---|---|---|---|
| Traffic cars' own tick (rails cruise plus the wheel sim of cars near the player) | 22.5 | 16.0 | 10.3 | 80 calls per frame. About 8 ms of it on main is the wheel and vehicle sim of the 9 to 10 cars in the sim |
| Traffic manager (who is drawn, who is in the sim, the lane index) | 8.7 | 8.2 | 3.4 | Mostly `_put` calling `RoadFrame.unroll` |
| Audio synthesis on the worker thread (engine plus turbo) | 12.1 | 8.5 | 6.3 | Not inside the frame, but it occupies a core. Paced by real time, so slower frames show more of it |
| Audio on the main thread (`EngineAudio._process`, car and cabin audio) | 2.9 | 4.4 | 6.2 | Mostly waiting for the worker; 6 to 8 ms at 0 to 20 cars |
| Player car physics | 2.6 | 2.6 | 2.6 | Flat with car count |
| Physics engine step (collisions, solver) | 1.6 | 1.5 | 1.5 | 2.2 to 2.6 ms in the unprofiled runs |
| Camera, cockpit, driver model | 1.2 | 1.2 | 1.2 | |
| HUD | 0.7 | 0.7 | 0.7 | |
| Effects (smoke, flames) | 0.4 | 0.4 | 0.4 | |
| Junctions and lights | 0.0 | 0.0 | 0.0 | City lights are off by default. Not measured with them on |
| Cops | none | none | none | There is no police code on main (PR #325 is open) |
| Rendering | 3 ms CPU, 4 ms GPU, 430 draw calls | same | same | From the windowed runs |

## Builds measured

| Label | What it is |
|---|---|
| main | `origin/main` at `0e57c1b`. Near-band traffic does not exist here, so this is "near band off" |
| #313 near band ON / OFF | `5cf3af4`: main with PR #313 (which contains #311) merged in. OFF pushes `TrafficManager.physics_distance` out so every drawn car is in the sim again |
| fix WIP | `5cf3af4` plus the uncommitted changes in the other session's worktree (`claude/project-thread-nhdubl`), copied at about 03:20 local time. Unfinished work; it may have changed since |

Traffic draw distance 150 m (the default), default road with curves and hills,
road seed 777, the player held at 120 km/h in lane 3 by the test lane driver.
Godot 4.7.2 editor binary, not the exported game, at high process priority.

## Headless runs: CPU only, exactly 2 ticks per frame

`--headless --fixed-fps 60`, 20 seconds of game time after a 3 second warm-up.
Milliseconds per frame, median. Each cell is run 1 / run 2. "In sim" is the
average number of cars running the full wheel sim. "Process CPU" is the whole
process including worker threads. "Spread" is the gap between the two runs.

| build | cars | in sim | frame p50 | frame p10 | phys scripts | phys server | _process | other | tick p50 | tick p95 | process CPU/frame | spread |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| main (no near band) | 0 | 0.0 / 0.0 | 9.6 / 9.3 | 8.8 / 8.5 | 2.9 / 2.8 | 0.9 / 0.9 | 3.7 / 3.6 | 2.1 / 2.0 | 1.90 / 1.83 | 2.31 / 2.04 | 15.3 / 15.0 | 4% |
| #313 near band ON | 0 | 0.0 / 0.0 | 9.5 / 9.5 | 8.6 / 8.6 | 2.8 / 2.8 | 0.9 / 0.9 | 3.6 / 3.7 | 2.0 / 2.0 | 1.86 / 1.86 | 2.10 / 2.10 | 15.2 / 15.5 | 0% |
| fix WIP (near ON) | 0 | 0.0 / 0.0 | 9.6 / 9.3 | 8.8 / 8.3 | 2.8 / 2.7 | 0.9 / 0.9 | 3.8 / 3.6 | 2.1 / 2.0 | 1.85 / 1.79 | 2.17 / 2.04 | 15.9 / 14.7 | 3% |
| main (no near band) | 10 | 2.8 / 0.9 | 18.6 / 14.3 | 13.2 / 12.3 | 9.6 / 6.8 | 1.4 / 1.2 | 4.3 / 3.9 | 2.3 / 2.1 | 5.53 / 4.02 | 7.28 / 4.80 | 25.7 / 20.5 | 26% |
| #313 near band ON | 10 | 0.9 / 0.7 | 15.7 / 15.0 | 12.9 / 12.9 | 7.0 / 6.9 | 1.4 / 1.3 | 4.3 / 4.1 | 2.3 / 2.3 | 4.22 / 4.11 | 6.99 / 5.71 | 22.1 / 22.6 | 4% |
| #313 near band OFF | 10 | 2.7 / 2.4 | 17.3 / 16.9 | 13.0 / 13.1 | 8.7 / 8.7 | 1.4 / 1.3 | 4.0 / 4.1 | 2.2 / 2.2 | 5.06 / 4.99 | 7.57 / 6.93 | 24.8 / 24.6 | 2% |
| fix WIP (near ON) | 10 | 0.6 / 1.1 | 12.0 / 12.4 | 10.4 / 10.2 | 4.1 / 4.6 | 1.2 / 1.2 | 4.0 / 3.8 | 2.2 / 2.2 | 2.71 / 2.95 | 4.47 / 5.97 | 17.9 / 19.9 | 3% |
| main (no near band) | 20 | 4.9 / 4.2 | 23.5 / 21.8 | 17.7 / 16.0 | 14.5 / 12.8 | 1.7 / 1.6 | 4.3 / 4.1 | 2.4 / 2.3 | 8.17 / 7.21 | 10.68 / 10.55 | 31.5 / 29.4 | 7% |
| #313 near band ON | 20 | 1.8 / 2.2 | 20.0 / 19.2 | 16.6 / 15.8 | 10.9 / 10.3 | 1.7 / 1.6 | 4.4 / 4.0 | 2.4 / 2.3 | 6.30 / 5.99 | 10.31 / 9.12 | 29.7 / 27.6 | 4% |
| #313 near band OFF | 20 | 4.3 / 5.7 | 24.1 / 24.1 | 17.1 / 16.0 | 14.0 / 15.0 | 1.8 / 1.7 | 4.5 / 4.1 | 2.5 / 2.4 | 7.92 / 8.32 | 12.62 / 12.48 | 31.8 / 31.5 | 0% |
| fix WIP (near ON) | 20 | 2.1 / 1.4 | 16.5 / 14.7 | 12.6 / 11.9 | 6.9 / 6.2 | 1.6 / 1.5 | 4.2 / 4.1 | 2.4 / 2.3 | 4.29 / 3.87 | 7.94 / 6.79 | 23.6 / 22.5 | 12% |
| main (no near band) | 40 | 10.0 / 9.3 | 39.2 / 34.7 | 26.4 / 23.7 | 28.2 / 24.5 | 2.6 / 2.4 | 5.0 / 4.6 | 3.0 / 2.8 | 15.46 / 13.53 | 20.89 / 18.79 | 52.4 / 45.4 | 12% |
| #313 near band ON | 40 | 4.2 / 4.0 | 31.9 / 28.6 | 24.4 / 23.8 | 20.6 / 18.2 | 2.5 / 2.4 | 5.0 / 4.6 | 2.9 / 2.7 | 11.63 / 10.31 | 17.09 / 15.62 | 43.2 / 40.2 | 11% |
| #313 near band OFF | 40 | 9.8 / 9.6 | 37.3 / 44.3 | 24.8 / 28.7 | 26.6 / 32.5 | 2.6 / 2.7 | 4.8 / 5.1 | 2.9 / 3.0 | 14.60 / 17.60 | 22.62 / 26.14 | 50.9 / 60.4 | 17% |
| fix WIP (near ON) | 40 | 4.0 / 4.1 | 22.1 / 21.9 | 15.8 / 15.1 | 11.2 / 10.5 | 2.3 / 2.2 | 4.7 / 4.5 | 2.8 / 2.6 | 6.80 / 6.36 | 13.93 / 13.23 | 32.9 / 31.5 | 1% |
| main (no near band) | 80 | 22.5 / 22.3 | 66.9 / 64.8 | 42.3 / 40.9 | 52.4 / 50.6 | 4.4 / 4.3 | 5.9 / 5.8 | 3.8 / 3.7 | 28.42 / 27.50 | 37.81 / 36.55 | 86.4 / 83.6 | 3% |
| #313 near band ON | 80 | 8.7 / 8.9 | 49.7 / 50.6 | 38.0 / 37.5 | 36.2 / 37.0 | 4.1 / 4.2 | 5.6 / 5.6 | 3.6 / 3.6 | 20.21 / 20.58 | 29.40 / 29.13 | 69.1 / 69.1 | 2% |
| #313 near band OFF | 80 | 23.1 / 23.7 | 66.7 / 66.6 | 44.5 / 41.4 | 53.0 / 52.9 | 4.2 / 4.2 | 5.7 / 5.6 | 3.7 / 3.6 | 28.61 / 28.56 | 38.38 / 39.02 | 87.6 / 85.6 | 0% |
| fix WIP (near ON) | 80 | 8.8 / 9.3 | 35.7 / 36.6 | 22.0 / 22.1 | 22.7 / 23.7 | 3.9 / 4.0 | 5.4 / 5.5 | 3.5 / 3.6 | 13.22 / 13.83 | 22.54 / 23.33 | 49.6 / 52.3 | 2% |

How noisy: most pairs agree within 12%. The worst are main at 10 cars (26%)
and #313 with the band off at 40 cars (17%). Within a run the fastest tenth of
frames is about a third quicker than the median at 40 cars and up, which is
other processes taking the core.

## Windowed runs: real renderer, real tick count

Window 1152x648, V-Sync off, 15 seconds. Run 1 / run 2.

| build | cars | fps (p50) | frame p50 | ticks/frame | tick p50 | draw calls | GPU ms | render CPU | phys scripts | phys server | _process | spread |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| main (no near band) | 0 | 60 / 48 | 16.6 / 20.6 | 2.2 / 2.5 | 2.08 / 2.24 | 376 / 375 | 3.6 / 3.6 | 1.9 / 2.0 | 3.2 / 4.4 | 1.1 / 1.3 | 4.3 / 4.9 | 22% |
| #313 near band ON | 0 | 46 / 45 | 21.9 / 22.4 | 2.8 / 2.8 | 2.44 / 2.67 | 379 / 380 | 3.4 / 3.6 | 2.1 / 2.0 | 5.1 / 5.1 | 1.5 / 1.4 | 5.3 / 5.8 | 2% |
| fix WIP (near ON) | 0 | 60 / 47 | 16.7 / 21.2 | 2.3 / 2.7 | 2.05 / 2.51 | 379 / 293 | 3.5 / 3.5 | 1.9 / 2.0 | 3.2 / 4.8 | 1.1 / 1.3 | 4.5 / 5.7 | 24% |
| main (no near band) | 10 | 22 / 35 | 46.5 / 28.3 | 5.8 / 4.4 | 5.32 / 4.46 | 315 / 393 | 2.6 / 3.6 | 2.3 / 2.1 | 24.7 / 12.3 | 4.4 / 2.5 | 5.0 / 4.4 | 49% |
| #313 near band ON | 10 | 28 / 39 | 35.4 / 26.0 | 4.6 / 4.0 | 4.80 / 4.11 | 314 / 312 | 3.6 / 3.5 | 2.1 / 2.1 | 16.9 / 10.4 | 3.0 / 2.4 | 5.1 / 4.6 | 31% |
| #313 near band OFF | 10 | 15 / 35 | 68.3 / 28.8 | 7.1 / 4.6 | 6.39 / 4.39 | 395 / 305 | 3.6 / 3.6 | 2.4 / 2.1 | 44.0 / 12.7 | 5.8 / 2.5 | 6.1 / 4.7 | 81% |
| fix WIP (near ON) | 10 | 39 / 48 | 25.9 / 21.0 | 3.1 / 2.8 | 3.50 / 3.03 | 306 / 319 | 3.6 / 3.6 | 2.2 / 2.0 | 8.9 / 5.8 | 2.1 / 1.8 | 4.8 / 4.2 | 21% |
| main (no near band) | 20 | 8 / 12 | 123.9 / 81.0 | 7.7 / 7.5 | 13.22 / 8.26 | 352 / 412 | 3.9 / 3.7 | 2.7 / 2.3 | 95.6 / 59.3 | 7.6 / 6.7 | 6.0 / 4.9 | 42% |
| #313 near band ON | 20 | 12 / 29 | 86.6 / 33.9 | 7.9 / 4.6 | 8.77 / 5.37 | 436 / 325 | 3.7 / 3.7 | 2.5 / 2.1 | 61.0 / 18.3 | 8.0 / 3.3 | 6.0 / 4.2 | 87% |
| #313 near band OFF | 20 | 14 / 10 | 73.7 / 98.9 | 6.6 / 6.9 | 7.65 / 10.32 | 400 / 413 | 3.6 / 3.7 | 2.3 / 2.5 | 54.2 / 74.3 | 6.1 / 7.0 | 4.5 / 5.0 | 29% |
| fix WIP (near ON) | 20 | 30 / 34 | 33.5 / 29.3 | 4.7 / 4.2 | 4.45 / 4.14 | 428 / 427 | 3.8 / 3.7 | 2.4 / 2.2 | 14.1 / 10.8 | 3.5 / 2.9 | 5.1 / 4.4 | 13% |
| main (no near band) | 40 | 7 / 7 | 143.5 / 134.7 | 8.0 / 8.0 | 15.23 / 15.11 | 430 / 443 | 4.3 / 4.1 | 3.0 / 2.6 | 110.9 / 111.8 | 11.1 / 9.4 | 6.4 / 4.7 | 6% |
| #313 near band ON | 40 | 9 / 9 | 116.9 / 107.2 | 8.0 / 8.0 | 12.26 / 11.71 | 434 / 385 | 4.1 / 3.9 | 2.9 / 2.6 | 87.7 / 84.4 | 9.1 / 8.9 | 5.4 / 5.0 | 9% |
| #313 near band OFF | 40 | 8 / 7 | 128.0 / 133.9 | 8.0 / 8.0 | 13.72 / 15.00 | 390 / 423 | 4.2 / 3.6 | 2.8 / 2.8 | 100.2 / 111.6 | 9.4 / 10.4 | 5.2 / 5.7 | 5% |
| fix WIP (near ON) | 40 | 13 / 10 | 75.5 / 97.9 | 6.6 / 6.9 | 7.16 / 9.52 | 453 / 456 | 4.0 / 3.6 | 2.6 / 2.8 | 46.8 / 68.5 | 8.2 / 8.6 | 5.5 / 5.9 | 26% |
| main (no near band) | 80 | 6 / 6 | 155.1 / 171.5 | 8.0 / 8.0 | 17.44 / 19.47 | 479 / 470 | 4.4 / 3.9 | 3.2 / 3.2 | 125.3 / 139.2 | 13.6 / 15.6 | 5.7 / 6.4 | 10% |
| #313 near band ON | 80 | 6 / 6 | 172.2 / 162.8 | 8.0 / 8.0 | 18.90 / 17.93 | 480 / 486 | 4.2 / 3.8 | 3.7 / 3.5 | 133.7 / 129.0 | 15.5 / 16.1 | 6.9 / 6.2 | 6% |
| #313 near band OFF | 80 | 6 / 6 | 171.1 / 172.1 | 8.0 / 8.0 | 19.11 / 19.26 | 473 / 473 | 4.3 / 3.8 | 3.2 / 3.3 | 135.8 / 138.9 | 14.3 / 16.7 | 5.8 / 6.5 | 1% |
| fix WIP (near ON) | 80 | 8 / 9 | 121.3 / 112.6 | 8.0 / 8.0 | 12.51 / 10.99 | 510 / 498 | 5.0 / 4.2 | 4.1 / 3.9 | 84.0 / 72.2 | 15.5 / 15.0 | 7.9 / 7.3 | 7% |

Ticks per frame: 2.2 to 2.8 with no traffic, 3 to 8 at 10 to 20 cars, and the
cap of 8 at 40 cars and above on every build but the fix (6.6 to 6.9 at 40).
At the cap the game runs slower than real time.

How noisy: very, at 10 and 20 cars (spread up to 87%). A run either stays near
4 ticks per frame or falls into the spiral, so those fps figures are not
reliable. The 0, 40 and 80 car rows repeat within 26%. Draw calls and GPU time
are steady throughout.

## Script profiler: top 15 functions by own time

Headless, 15 seconds, one run each, profiler on. "Own" time includes engine
calls a function makes directly.

### main, 40 cars

| # | function | calls/frame | self ms/frame | share of script time | total ms/frame |
|---|---|---|---|---|---|
| 1 | `traffic/traffic_car.gd::302::TrafficCar._physics_process` | 80 | 8.28 | 17% | 22.46 |
| 2 | `audio/turbo_synth.gd::147::TurboSynth.render` | 1 | 6.43 | 13% | 6.43 |
| 3 | `audio/engine_synth.gd::183::EngineSynth.render` | 1 | 3.91 | 8% | 5.65 |
| 4 | `vendor/gevp/gevp_wheel.gd::163::Wheel.process_forces` | 80 | 2.26 | 5% | 4.50 |
| 5 | `audio/engine_audio.gd::143::EngineAudio._join` | 2 | 2.03 | 4% | 2.03 |
| 6 | `audio/engine_synth.gd::432::EngineSynth._rand` | 3643 | 1.43 | 3% | 1.43 |
| 7 | `car/player.gd::284::PlayerCar._physics_process` | 2 | 1.26 | 3% | 2.58 |
| 8 | `world/road_frame.gd::129::RoadFrame.unroll` | 518 | 1.20 | 2% | 5.53 |
| 9 | `vendor/gevp/gevp_wheel.gd::275::Wheel.process_tires` | 80 | 0.98 | 2% | 1.21 |
| 10 | `traffic/traffic_car.gd::685::TrafficCar._cruise` | 62 | 0.82 | 2% | 9.08 |
| 11 | `car/aero.gd::111::AeroModel._draft_factor` | 20 | 0.72 | 1% | 1.20 |
| 12 | `traffic/traffic_manager.gd::230::TrafficManager._physics_process` | 2 | 0.63 | 1% | 8.68 |
| 13 | `vendor/gevp/gevp_wheel.gd::94::Wheel._process` | 164 | 0.60 | 1% | 0.60 |
| 14 | `traffic/traffic_manager.gd::496::TrafficManager._put` | 80 | 0.56 | 1% | 5.17 |
| 15 | `view/view_guard.gd::77::ViewGuard.in_cone` | 515 | 0.55 | 1% | 0.55 |

### #313 near band, 40 cars

| # | function | calls/frame | self ms/frame | share of script time | total ms/frame |
|---|---|---|---|---|---|
| 1 | `audio/turbo_synth.gd::147::TurboSynth.render` | 0 | 5.95 | 16% | 5.95 |
| 2 | `traffic/traffic_car.gd::323::TrafficCar._physics_process` | 80 | 3.64 | 9% | 16.02 |
| 3 | `audio/engine_audio.gd::143::EngineAudio._join` | 2 | 3.54 | 9% | 3.54 |
| 4 | `audio/engine_synth.gd::183::EngineSynth.render` | 1 | 1.78 | 5% | 2.56 |
| 5 | `audio/engine_synth.gd::432::EngineSynth._rand` | 3293 | 1.33 | 3% | 1.33 |
| 6 | `car/player.gd::284::PlayerCar._physics_process` | 2 | 1.25 | 3% | 2.55 |
| 7 | `world/road_frame.gd::129::RoadFrame.unroll` | 508 | 1.16 | 3% | 5.44 |
| 8 | `vendor/gevp/gevp_wheel.gd::163::Wheel.process_forces` | 38 | 1.13 | 3% | 2.26 |
| 9 | `traffic/traffic_car.gd::755::TrafficCar._rail_pose` | 73 | 0.68 | 2% | 4.04 |
| 10 | `traffic/traffic_car.gd::762::TrafficCar._cruise` | 72 | 0.67 | 2% | 9.89 |
| 11 | `traffic/traffic_manager.gd::245::TrafficManager._physics_process` | 2 | 0.67 | 2% | 8.21 |
| 12 | `vendor/gevp/gevp_wheel.gd::94::Wheel._process` | 164 | 0.60 | 2% | 0.60 |
| 13 | `view/view_guard.gd::77::ViewGuard.in_cone` | 515 | 0.58 | 2% | 0.58 |
| 14 | `world/road_frame.gd::225::RoadFrame.pose` | 73 | 0.53 | 1% | 2.91 |
| 15 | `traffic/traffic_manager.gd::519::TrafficManager._put` | 80 | 0.52 | 1% | 4.83 |

### Fix in progress, 40 cars

| # | function | calls/frame | self ms/frame | share of script time | total ms/frame |
|---|---|---|---|---|---|
| 1 | `audio/engine_audio.gd::143::EngineAudio._join` | 2 | 5.30 | 16% | 5.30 |
| 2 | `audio/turbo_synth.gd::147::TurboSynth.render` | 0 | 4.75 | 14% | 4.75 |
| 3 | `traffic/traffic_car.gd::359::TrafficCar._physics_process` | 80 | 3.94 | 12% | 10.34 |
| 4 | `car/player.gd::284::PlayerCar._physics_process` | 2 | 1.26 | 4% | 2.57 |
| 5 | `vendor/gevp/gevp_wheel.gd::163::Wheel.process_forces` | 41 | 1.20 | 4% | 2.42 |
| 6 | `audio/engine_synth.gd::183::EngineSynth.render` | 0 | 1.09 | 3% | 1.57 |
| 7 | `audio/engine_synth.gd::432::EngineSynth._rand` | 2715 | 1.03 | 3% | 1.03 |
| 8 | `traffic/traffic_car.gd::836::TrafficCar._cruise` | 72 | 0.74 | 2% | 3.80 |
| 9 | `view/view_guard.gd::77::ViewGuard.in_cone` | 516 | 0.57 | 2% | 0.57 |
| 10 | `vendor/gevp/gevp_wheel.gd::94::Wheel._process` | 150 | 0.55 | 2% | 0.55 |
| 11 | `vendor/gevp/gevp_wheel.gd::275::Wheel.process_tires` | 41 | 0.51 | 2% | 0.66 |
| 12 | `car/aero.gd::111::AeroModel._draft_factor` | 10 | 0.35 | 1% | 0.79 |
| 13 | `car/aero.gd::96::AeroModel._rebuild_draft_grid` | 2 | 0.33 | 1% | 0.39 |
| 14 | `view/view_guard.gd::125::ViewGuard.chunk_seen` | 1 | 0.32 | 1% | 1.55 |
| 15 | `world/road_frame.gd::225::RoadFrame.pose` | 40 | 0.30 | 1% | 1.65 |

### main, 80 cars

| # | function | calls/frame | self ms/frame | share of script time | total ms/frame |
|---|---|---|---|---|---|
| 1 | `traffic/traffic_car.gd::302::TrafficCar._physics_process` | 160 | 20.07 | 21% | 49.49 |
| 2 | `audio/engine_synth.gd::183::EngineSynth.render` | 1 | 13.51 | 14% | 19.37 |
| 3 | `audio/turbo_synth.gd::147::TurboSynth.render` | 1 | 9.50 | 10% | 9.50 |
| 4 | `vendor/gevp/gevp_wheel.gd::163::Wheel.process_forces` | 187 | 5.30 | 6% | 10.30 |
| 5 | `world/road_frame.gd::129::RoadFrame.unroll` | 1033 | 2.24 | 2% | 10.40 |
| 6 | `vendor/gevp/gevp_wheel.gd::275::Wheel.process_tires` | 187 | 2.22 | 2% | 2.68 |
| 7 | `car/aero.gd::111::AeroModel._draft_factor` | 47 | 2.02 | 2% | 2.91 |
| 8 | `audio/engine_synth.gd::432::EngineSynth._rand` | 5157 | 2.01 | 2% | 2.01 |
| 9 | `traffic/traffic_car.gd::685::TrafficCar._cruise` | 115 | 1.46 | 2% | 16.63 |
| 10 | `car/player.gd::284::PlayerCar._physics_process` | 2 | 1.26 | 1% | 2.87 |
| 11 | `traffic/traffic_manager.gd::230::TrafficManager._physics_process` | 2 | 1.23 | 1% | 16.83 |
| 12 | `traffic/traffic_manager.gd::574::TrafficManager.scan` | 61 | 1.19 | 1% | 1.71 |
| 13 | `vendor/gevp/gevp_wheel.gd::94::Wheel._process` | 324 | 1.18 | 1% | 1.18 |
| 14 | `traffic/traffic_manager.gd::496::TrafficManager._put` | 160 | 1.12 | 1% | 10.21 |
| 15 | `vendor/gevp/gevp_wheel.gd::215::Wheel.process_suspension` | 187 | 1.01 | 1% | 1.01 |

## Per-frame work by entry point

Everything each `_physics_process`, `_process` or audio render call costs,
including what it calls. Profiler on, milliseconds per frame.

### main

| entry point (inclusive ms per frame, profiler on) | 0 cars | 10 cars | 20 cars | 40 cars | 80 cars | calls/frame at 80 |
|---|---|---|---|---|---|---|
| `TrafficCar._physics_process` | 0.00 | 3.85 | 11.12 | 22.46 | 49.49 | 160 |
| `EngineAudio._render` | 15.40 | 1.58 | 16.70 | 7.71 | 27.65 | 1 |
| `Vehicle._physics_process` | 1.16 | 1.96 | 5.31 | 9.37 | 20.99 | 47 |
| `EngineSynth.render` | 14.83 | 1.20 | 1.30 | 5.65 | 19.37 | 1 |
| `TrafficManager._physics_process` | 0.33 | 2.22 | 4.57 | 8.68 | 16.83 | 2 |
| `TurboSynth.render` | 2.34 | 3.46 | 5.04 | 6.43 | 9.50 | 1 |
| `PlayerCar._physics_process` | 2.07 | 2.24 | 2.39 | 2.58 | 2.87 | 2 |
| `Wheel._process` | 0.03 | 0.17 | 0.32 | 0.60 | 1.18 | 324 |
| `Hud._process` | 0.47 | 0.55 | 0.63 | 0.73 | 0.98 | 1 |
| `CarAudio._process` | 0.51 | 0.52 | 0.54 | 0.53 | 0.53 | 1 |
| `CockpitFrame._process` | 0.30 | 0.31 | 0.32 | 0.31 | 0.31 | 1 |
| `PerspectiveAudio._process` | 0.26 | 0.27 | 0.28 | 0.28 | 0.29 | 1 |
| `ChaseCamera._process` | 0.25 | 0.26 | 0.28 | 0.28 | 0.29 | 1 |
| `DriverModel._process` | 0.25 | 0.26 | 0.26 | 0.26 | 0.26 | 1 |
| `_physics_process` | 0.19 | 0.20 | 0.21 | 0.22 | 0.23 | 2 |
| `ExhaustFlames._process` | 0.17 | 0.19 | 0.20 | 0.21 | 0.22 | 1 |
| `TyreSmoke._physics_process` | 0.18 | 0.20 | 0.20 | 0.21 | 0.20 | 2 |
| `Mark._process` | 0.04 | 0.07 | 0.09 | 0.12 | 0.19 | 2 |
| `RpmBar._draw` | 0.13 | 0.14 | 0.14 | 0.14 | 0.15 | 1 |
| `EngineAudio._process` | 5.56 | 6.97 | 6.51 | 2.12 | 0.14 | 1 |
| `Vehicle._integrate_forces` | 0.01 | 0.03 | 0.04 | 0.08 | 0.14 | 162 |
| `ChaseCamera._physics_process` | 0.11 | 0.12 | 0.13 | 0.12 | 0.12 | 2 |

### #313 near band

| entry point (inclusive ms per frame, profiler on) | 0 cars | 10 cars | 20 cars | 40 cars | 80 cars | calls/frame at 80 |
|---|---|---|---|---|---|---|
| `TrafficCar._physics_process` | 0.00 | 3.98 | 10.99 | 16.02 | 33.21 | 160 |
| `EngineAudio._render` | 1.73 | 1.68 | 4.61 | 3.51 | 18.78 | 1 |
| `TrafficManager._physics_process` | 0.34 | 2.35 | 5.91 | 8.21 | 15.91 | 2 |
| `EngineSynth.render` | 1.28 | 1.25 | 3.48 | 2.56 | 13.66 | 1 |
| `Vehicle._physics_process` | 1.18 | 2.10 | 4.04 | 4.74 | 8.96 | 19 |
| `TurboSynth.render` | 2.44 | 3.48 | 5.17 | 5.95 | 8.38 | 1 |
| `PlayerCar._physics_process` | 2.11 | 2.24 | 2.99 | 2.55 | 2.91 | 2 |
| `Wheel._process` | 0.03 | 0.17 | 0.41 | 0.60 | 1.17 | 324 |
| `Hud._process` | 0.48 | 0.55 | 0.81 | 0.72 | 0.99 | 1 |
| `CarAudio._process` | 0.52 | 0.52 | 0.67 | 0.53 | 0.53 | 1 |
| `ChaseCamera._process` | 0.25 | 0.26 | 0.36 | 0.28 | 0.32 | 1 |
| `CockpitFrame._process` | 0.31 | 0.31 | 0.40 | 0.31 | 0.31 | 1 |
| `PerspectiveAudio._process` | 0.27 | 0.27 | 0.38 | 0.28 | 0.29 | 1 |
| `DriverModel._process` | 0.25 | 0.26 | 0.35 | 0.26 | 0.26 | 1 |
| `ExhaustFlames._process` | 0.18 | 0.18 | 0.26 | 0.20 | 0.25 | 1 |
| `_physics_process` | 0.19 | 0.20 | 0.26 | 0.22 | 0.23 | 2 |
| `TyreSmoke._physics_process` | 0.18 | 0.20 | 0.27 | 0.20 | 0.20 | 2 |
| `Mark._process` | 0.04 | 0.07 | 0.11 | 0.12 | 0.18 | 2 |
| `EngineAudio._process` | 5.91 | 6.75 | 6.04 | 3.63 | 0.15 | 1 |
| `RpmBar._draw` | 0.14 | 0.14 | 0.20 | 0.14 | 0.15 | 1 |
| `Vehicle._integrate_forces` | 0.01 | 0.03 | 0.05 | 0.08 | 0.14 | 162 |
| `ChaseCamera._physics_process` | 0.11 | 0.12 | 0.16 | 0.12 | 0.12 | 2 |

### Fix in progress

| entry point (inclusive ms per frame, profiler on) | 0 cars | 10 cars | 20 cars | 40 cars | 80 cars | calls/frame at 80 |
|---|---|---|---|---|---|---|
| `TrafficCar._physics_process` | 0.00 | 2.70 | 4.61 | 10.34 | 22.80 | 160 |
| `Vehicle._physics_process` | 1.19 | 2.19 | 2.94 | 5.07 | 9.44 | 20 |
| `EngineAudio._render` | 2.08 | 1.88 | 1.99 | 2.08 | 8.85 | 1 |
| `TrafficManager._physics_process` | 0.28 | 1.12 | 1.81 | 3.40 | 6.69 | 2 |
| `TurboSynth.render` | 2.38 | 3.06 | 3.67 | 4.75 | 6.56 | 1 |
| `EngineSynth.render` | 1.55 | 1.41 | 1.51 | 1.57 | 6.51 | 1 |
| `PlayerCar._physics_process` | 2.13 | 2.21 | 2.41 | 2.57 | 2.95 | 2 |
| `EngineAudio._process` | 5.76 | 6.48 | 6.52 | 5.39 | 2.44 | 1 |
| `Wheel._process` | 0.03 | 0.15 | 0.30 | 0.55 | 1.12 | 305 |
| `Hud._process` | 0.49 | 0.54 | 0.62 | 0.73 | 0.99 | 1 |
| `CarAudio._process` | 0.52 | 0.52 | 0.54 | 0.53 | 0.55 | 1 |
| `CockpitFrame._process` | 0.30 | 0.30 | 0.32 | 0.31 | 0.32 | 1 |
| `ChaseCamera._process` | 0.25 | 0.26 | 0.28 | 0.28 | 0.30 | 1 |
| `PerspectiveAudio._process` | 0.27 | 0.27 | 0.28 | 0.28 | 0.29 | 1 |
| `DriverModel._process` | 0.26 | 0.26 | 0.27 | 0.26 | 0.27 | 1 |
| `_physics_process` | 0.20 | 0.20 | 0.21 | 0.21 | 0.22 | 2 |
| `ExhaustFlames._process` | 0.18 | 0.18 | 0.19 | 0.20 | 0.21 | 1 |
| `TyreSmoke._physics_process` | 0.18 | 0.19 | 0.20 | 0.20 | 0.21 | 2 |
| `Mark._process` | 0.04 | 0.06 | 0.08 | 0.12 | 0.19 | 2 |
| `RpmBar._draw` | 0.13 | 0.14 | 0.14 | 0.14 | 0.15 | 1 |
| `Vehicle._integrate_forces` | 0.01 | 0.03 | 0.04 | 0.07 | 0.14 | 162 |
| `ChaseCamera._physics_process` | 0.11 | 0.11 | 0.12 | 0.12 | 0.13 | 2 |

## What was not done

- No run on an idle laptop. Every number here was taken at 100% CPU load.
- City lights (junctions) were left off, their default.
- Cops could not be measured: no police code on main.
- The exported game was not measured, only the editor binary.
- The 60 Hz figure in win 3 is arithmetic on the measured buckets, not a run.
- The profiler runs were not repeated.
- The four `find /` processes were left running; they are not mine to stop.

## How it was measured

A stand-alone probe script (not in this PR) boots `Game.tscn` and adds two
marker nodes with the lowest and highest process priority. Their timestamps
split each frame into physics scripts, the rest of each physics tick, `_process`
scripts and everything else. The profiler tables come from Godot's own script
profiler, streamed over `--remote-debug` to a small receiver.

<details><summary>Probe script</summary>

```gdscript
extends SceneTree

# Traffic cost probe (measurement only, 2026-10-10). Boots the real game with
# PROBE_CARS traffic cars and splits every frame's wall-clock time into:
#   phys_scripts  every node's _physics_process, summed over the frame's ticks
#   phys_server   the rest of each tick (physics server step, body callbacks)
#   proc_scripts  every node's _process
#   other         the rest of the frame (render submit/draw, engine idle work)
# Two marker nodes with the lowest and highest process priority take the
# timestamps, so no game code is touched.
#
# Headless + --fixed-fps 60: exactly two 120 Hz ticks per frame, CPU only.
# Windowed (no --headless): real renderer, V-Sync off; adds draw calls, GPU ms
# and the real number of physics ticks per frame.
#
# Env: PROBE_CARS, PROBE_DETAIL (150), PROBE_SECS (20), PROBE_NEAR=0 (push
# TrafficManager.physics_distance out so the near band is off, where it
# exists), PROBE_PROFILE=1 (script profiler to --remote-debug), PROBE_OUT.

const Harness := preload("res://tests/traffic/traffic_harness.gd")

class Mark extends Node:
	var probe: Object
	var first := false
	func _physics_process(_d: float) -> void:
		probe.call("mark_phys", first)
	func _process(_d: float) -> void:
		probe.call("mark_proc", first)

var game: Node
var headless := false
var frame := 0
var measuring := false
var done := false
var secs := 20.0
var t_start_us := 0

var _ta := 0
var _tb := 0
var _tp := 0
var _last_end := 0
var f_phys_scripts := 0
var f_phys_server := 0
var f_ticks := 0

var s_total := PackedFloat64Array()
var s_phys_scripts := PackedFloat64Array()
var s_phys_server := PackedFloat64Array()
var s_proc := PackedFloat64Array()
var s_ticks := PackedInt32Array()
var s_draw := PackedInt32Array()
var s_gpu := PackedFloat64Array()
var s_rcpu := PackedFloat64Array()
var s_detailed := PackedInt32Array()
var s_visible := PackedInt32Array()

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _initialize() -> void:
	headless = DisplayServer.get_name() == "headless"
	var cars := int(_env("PROBE_CARS", "16"))
	var detail := float(_env("PROBE_DETAIL", "150"))
	secs = float(_env("PROBE_SECS", "20"))
	seed(777)
	OS.set_environment("NEON_TEST", "1")
	OS.set_environment("NEON_TRAFFIC", str(cars))
	OS.set_environment("NEON_ROAD_SEED", "777")
	AudioSettings.path = "user://cost_probe_settings.cfg"
	TrafficSettings.set_car_count(cars)
	TrafficSettings.set_detail_distance(detail)
	TrafficSettings.save_settings()
	if not headless:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var a := Mark.new()
	a.probe = self
	a.first = true
	a.process_priority = -1000000
	a.process_physics_priority = -1000000
	root.add_child(a)
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var b := Mark.new()
	b.probe = self
	b.process_priority = 1000000
	b.process_physics_priority = 1000000
	root.add_child(b)

func mark_phys(first: bool) -> void:
	var now := Time.get_ticks_usec()
	if first:
		if _tb > 0:
			f_phys_server += now - _tb
			_tb = 0
		_ta = now
		f_ticks += 1
	else:
		f_phys_scripts += now - _ta
		_tb = now

func mark_proc(first: bool) -> void:
	var now := Time.get_ticks_usec()
	if first:
		if _tb > 0:
			f_phys_server += now - _tb
			_tb = 0
		_tp = now
		return
	_end_frame(now)

func _end_frame(now: int) -> void:
	frame += 1
	if frame == 2:
		var p: Object = game.get("player")
		p.set("driver", Harness.lane_driver(Harness.lane_x(3), 1.0, 33.0))
		if _env("PROBE_NEAR", "1") == "0":
			var tm: Object = game.get("traffic")
			if tm != null and tm.get("physics_distance") != null:
				tm.set("physics_distance", 1.0e9)
	var warm := frame > 180 if headless else (frame > 30 and now - t_start_us > 4000000)
	if t_start_us == 0:
		t_start_us = now
	if warm and not measuring and not done:
		measuring = true
		t_start_us = now
		print("COSTPROBE_START")
		if _env("PROBE_PROFILE", "") == "1" and EngineDebugger.is_active():
			EngineDebugger.profiler_enable("servers", true, [2000])
	elif measuring:
		s_total.append((now - _last_end) / 1000.0)
		s_phys_scripts.append(f_phys_scripts / 1000.0)
		s_phys_server.append(f_phys_server / 1000.0)
		s_proc.append((now - _tp) / 1000.0)
		s_ticks.append(f_ticks)
		var tm2: Object = game.get("traffic")
		if tm2 != null:
			s_detailed.append(int(tm2.call("detailed_count")))
			var vis := 0
			for c in tm2.get("cars"):
				if c.visible:
					vis += 1
			s_visible.append(vis)
		if not headless:
			var vp := root.get_viewport_rid()
			s_draw.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			var g := RenderingServer.viewport_get_measured_render_time_gpu(vp)
			s_gpu.append(g if g < 1000.0 else 0.0)
			s_rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
		var enough := s_total.size() >= int(secs * 60.0) if headless else now - t_start_us >= int(secs * 1000000.0)
		if enough:
			measuring = false
			done = true
			print("COSTPROBE_END")
			if _env("PROBE_PROFILE", "") == "1" and EngineDebugger.is_active():
				EngineDebugger.profiler_enable("servers", false)
			_report()
			quit(0)
	_last_end = now
	f_phys_scripts = 0
	f_phys_server = 0
	f_ticks = 0

func _stats(a: Array) -> Dictionary:
	var s := a.duplicate()
	s.sort()
	var n := s.size()
	if n == 0:
		return {}
	var sum := 0.0
	for x in s:
		sum += x
	return {"mean": sum / n, "p10": s[int(n * 0.10)], "p50": s[n / 2], "p95": s[int(n * 0.95)], "p99": s[int(n * 0.99)], "max": s[n - 1]}

func _report() -> void:
	var n := s_total.size()
	var other := []
	var tick := []
	var hist := {}
	for i in n:
		other.append(s_total[i] - s_phys_scripts[i] - s_phys_server[i] - s_proc[i])
		if s_ticks[i] > 0:
			tick.append((s_phys_scripts[i] + s_phys_server[i]) / s_ticks[i])
		hist[str(s_ticks[i])] = int(hist.get(str(s_ticks[i]), 0)) + 1
	var p: Object = game.get("player")
	var size := root.get_visible_rect().size
	var out := {
		"mode": "headless" if headless else "windowed",
		"cars": TrafficSettings.car_count, "detail": TrafficSettings.detail_distance,
		"near": _env("PROBE_NEAR", "1"), "profile": _env("PROBE_PROFILE", ""),
		"tps": Engine.physics_ticks_per_second, "max_steps": Engine.max_physics_steps_per_frame,
		"frames": n, "window": "%dx%d" % [int(size.x), int(size.y)],
		"speed_kmh": p.get("linear_velocity").length() * 3.6,
		"total": _stats(Array(s_total)), "phys_scripts": _stats(Array(s_phys_scripts)),
		"phys_server": _stats(Array(s_phys_server)), "proc_scripts": _stats(Array(s_proc)),
		"other": _stats(other), "tick": _stats(tick), "ticks_per_frame": _stats(Array(s_ticks)),
		"ticks_hist": hist, "detailed": _stats(Array(s_detailed)), "visible": _stats(Array(s_visible)),
		"draw_calls": _stats(Array(s_draw)), "gpu": _stats(Array(s_gpu)), "render_cpu": _stats(Array(s_rcpu)),
		"bodies": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}
	var js := JSON.stringify(out)
	print("COSTPROBE ", js)
	var path := _env("PROBE_OUT", "")
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(js)
			f.close()

```

</details>
