# Living world: time, people and events (proposal, 2026-10-08)

Status: PROPOSAL, docs only. Roy answered round 1 on 2026-10-08 (section 6). The first build step (L1) waits for Roy to say build. Story is Roy's to write; names are placeholders.

Roy (2026-10-08): "the world doesn't feel real, there's no track of time or any sense of humanity in this game." Also: "what if the rule breaker share changed based off game events?"

Read for this (main `09455e0`, plus open branches): `scripts/game.gd`, `night_sky.gd`, `radio_manager.gd`, `radio_stations.gd`, `road_chunk_builder.gd`, `traffic_settings.gd`, `traffic_manager.gd`; `docs/story-bible.md`; world vision W1-W5 (branch `claude/project-thread-w9ubqr`); narrative fabric (`-nlzblk`, PR #175); traffic decisions (`/mnt/project-files/traffic-decisions.md`).

## One line

**The city keeps its own time, and people live in it whether you are there or not.** You notice the clock moving, the city changing with it, and the city noticing you.

## Why it feels dead today (checked in code)

| What | Where | Effect |
|---|---|---|
| No clock at all. The only thing that varies per run is the moon phase | `game.gd:122` | 3 minutes and 3 hours of driving look identical |
| Every window is a static texture, lit forever | `road_chunk_builder.gd:286` | Buildings are wallpaper, nobody lives behind them |
| Dave says a line every 30 s from a fixed list, unrelated to anything | `radio_stations.gd:24` | Radio is a loop, not a person awake with you |
| Traffic: one behaviour mix, one density, all night | `traffic_settings.gd` | No rush, no lull, no 2 a.m. weirdness |
| No people anywhere, no sound of anyone | (absent) | The city has no inhabitants |

## Steelman and premortem

- Steelman: time is the cheapest "life" there is. One clock number drives windows, traffic mix, radio lines and sky, all of which already exist. Most of this is parameters, not new art, so it fits the i5-1235U laptop.
- Premortem, it failed because:
  1. The clock became a timer that nags. Mitigation: dawn ends the night, it never fails you; free roam can freeze the clock (question 3).
  2. Changes were too subtle to notice. Mitigation: each hour band has at least one change you can't miss (bar-close taxis, the 4 a.m. garbage truck, Dave's top-of-hour line).
  3. People looked like cardboard. Mitigation: people only where you stop (destinations), seen from a car at night, in silhouette. Never on the highway sidewalk at speed.
- Falsification: if a tester drives 20 minutes and can't say roughly what time it is, the clock failed.

## 1. The game clock (plain words)

A **game clock** means the game keeps its own time of night, like a watch that runs faster than a real one. Today there is none.

Proposal:
- A night runs **8 p.m. to 6 a.m.** in game time.
- Speed: **1 real minute of driving = 10 game minutes**, so a full night is about **1 hour of driving**, but **not one sitting** (see "Night length and play sessions" below).
- Where you see it: the **clock on the car's dashboard** and Dave saying the time. No HUD timer, no key hints.
- A **date and weekday**: "Friday, Oct 9". Weekends are busier and have meets; Monday is dead. The story's "debt due at season's end" becomes a real date on the garage calendar.
- **Dawn**: from 5 a.m. the sky slowly goes from navy to pre-dawn blue (world vision W4). Dawn is a soft deadline you feel, never a fail screen.
- **6 a.m. and you're not home (Roy, decided):** a short cutscene of you driving home tired and parking at the garage. You **keep your earnings**. Then the next night starts from the garage. Cheapest form: a few seconds of fixed camera on the existing road with a dawn sky, and the garage door closing (or a still, as the story bible already uses).

### Night length and play sessions (Roy: a real night is much longer than 90 minutes, but nobody plays that long)

The game night (8 p.m. to 6 a.m., 10 hours) is compressed, and **one night can stretch over several play sessions**.

| Option | How it works | Good | Bad |
|---|---|---|---|
| A. One sitting | Night = 60 real min, must finish it in one go | Simple | Forces long sessions; quitting loses the night |
| **B. Compressed + carried over (recommended)** | Clock runs 10x while driving. Quit any time: the time, place and unbanked earnings save, and the next session continues the same night | Play 10 or 90 minutes, the night still feels like one night | Needs save of the clock (small) |
| C. Time jumps only | Clock moves only when you do things (a race = 30 min, a garage job = 1 h) | Very controllable | Driving around never moves time, so the world feels frozen again |

**Recommendation: B, plus small jumps from C.** Driving runs the clock at 10x; stops add time on top (a garage job +1 h, a diner break +20 min, a race +15 min). So a night with a few stops is about **35-45 minutes of actual driving**, spread over as many sessions as you like. Night length is a setting (45 / 60 / 90 min of driving) for anyone who wants it longer.
- Costs: one number in a small `WorldClock` script; zero GPU.
- Assets: none.

### Hour bands (what each part of the night feels like)

| Band | Hours | Traffic | Rule breakers (see 3) | City | Radio |
|---|---|---|---|---|---|
| Dusk | 8-10 p.m. | Busiest, buses, commuters | Low | Most windows lit, shops open | Dave starts the shift, traffic report |
| Late | 10 p.m.-1 a.m. | Medium, taxis, meet cars on weekends | Medium on weekends | Windows going dark one by one, bars loud | Callers, requests |
| Dead hours | 1-4 a.m. | Thin. Bar close at 2 a.m. gives a burst of taxis and a few weaving drivers | Highest at 2 a.m. | Few windows, 24 h places only, neon-free signs flicker | Dave tired, longest talk, coffee-machine bit |
| Pre-dawn | 4-6 a.m. | Delivery vans, a garbage truck, early workers | Low | Bakery and diner lights on, first kitchen windows come back | "Go home, driver." |

Traffic counts can only go **down** from today's 16-car budget, so the dead hours also save CPU (traffic decisions §9, option C there).

## 2. People: humanity without a crowd

Ranked by life per cost. Every row says where assets come from and the licence. **Roy's rule: free, commercial use, no credit, no payment.**

| # | Idea | Cost on laptop | Assets and licence |
|---|---|---|---|
| P1 | **Windows switch on and off** through the night, on a per-window random time, shader uniform from the clock. A few show a moving TV glow, a few a silhouette | ~0 ms | Original (shader), no assets |
| P2 | **Traffic you can read as people**: taxi with roof sign, delivery van, bus, garbage truck, a car with one headlight out. Behaviour per type (taxi stops at the curb, bus pulls in) | Same 16-car budget | Original models by us, or Kenney Car Kit (CC0) / Quaternius Cars and Public Transport packs (QAL: free, commercial, no credit) |
| P3 | **Dave knows the time and the night**: top-of-hour lines ("It's two. Bars are out. Watch the left lane."), weather, what happened tonight | Audio files only | Voice: Kokoro TTS (Apache-2.0, run offline once; we ship only the audio, so no credit needed - inferred from the licence, it covers the model, not its output) |
| P4 | **Callers**: 2 crew, 2 random listeners (story bible). The night-shift nurse, the trucker, the insomniac | Audio files only | Kokoro voices, different presets per caller, phone EQ filter |
| P5 | **News on the hour**: 20 s bulletin. Some items are flavour (port strike, mayor), some are **true in the world** ("crash on Route 9, right lane closed" and the lane really is closed) | Audio files + a lane flag | Kokoro, original text |
| P6 | **Police scanner** murmur when heat is up, plus police voice lines (Roy asked for research) | Audio files only | Kokoro + radio crackle filter; scanner phrases written by us. Recorded radio squelch from Sonniss GDC bundle (royalty-free, commercial, no attribution; can't be used for AI training) |
| P7 | **Sounds of other lives**: dog bark, a train horn, a distant siren, muffled bar music on the bar strip, a garbage truck beeping at 4 a.m., a car alarm | Tiny | Freesound **CC0-filtered only** (check each file), Sonniss GDC bundle, or synthesised |
| P8 | **People at stops only**: gas station clerk behind glass, two people smoking outside the diner, a meet crowd of 10-30. Silhouette-lit, idle loops | Only drawn at destinations | Quaternius Animated Men/Women and "Background Posed Humans" packs (QAL, no credit), or Mixamo animations (free, commercial, no credit; Adobe terms forbid shipping the raw files on their own, fine inside a game). Kenney (CC0) for props |
| P9 | **Your phone**: texts from crew with timestamps ("01:12 Juno: you up? meet at the docks"), Pike's reminders | UI only | Original |
| P10 | **The city remembers you**: Dave mentions your near-miss, the news reports "a street race on Route 9 last night", the clerk says you're back again | Logic only | Original |

Not proposed: pedestrians walking along the highway (cost, and nobody walks a freeway at 3 a.m.), live AI-generated voices at runtime (CPU, and weirdness).

## 3. Events that change the world (and the rule-breaker idea)

**Plain words first.** In the traffic study, "rule breakers" are NPC drivers who speed, don't signal or tailgate. The traffic study's option "C" for this question was a *realistic mix*: about half the cars break rules all the time. It was not recommended because then you can't predict any car, and you stop feeling like the only outlaw. (The word "Option C" is also used elsewhere for "every traffic car runs the full physics sim"; the traffic thread is explaining that one.)

**Roy's idea is better than any of the study's options:** keep NPCs mostly law-abiding, and let **the share of rule breakers move with what is happening**. The world gets a single "mood" value per stretch of night.

| Event | When | Rule breakers | Other changes |
|---|---|---|---|
| Normal weeknight | Default | 3% | - |
| Bar close | 2-2:30 a.m., all nights | 12% (weaving, late braking, no signal) | Taxi burst, Dave warns |
| Meet night | Fri/Sat, story-driven | 20% (other racers speeding, cutting in) | Racer cars with loud exhausts; Dave advertises the meet |
| Police crackdown | After you had high heat, or a story event | 0-1% (everyone behaves) | More cops parked, scanner chatter, news item |
| Crash ahead | Random or news-driven | Unchanged | Lane closed, flares, slow rubberneckers, a tow truck (Ferris?) |
| Rain | Random (phase 2, needs wet road) | Unchanged | Everyone 10-15% slower, longer gaps |
| Game night / concert out | Rare | 5% | 10 min traffic wave, Dave mentions the score |
| Holiday (New Year, July 4) | Calendar | 8% | Fireworks on the skyline, party traffic |
| Port strike / power cut | Story or rare | - | A district's windows and lamps go dark |

Every rule breaker is visibly odd (weaving, a lane cut, flashing headlights) so it reads as a character, not a bug. This is the study's option D, driven by events.

Costs: a lookup table and the existing behaviour presets on `traffic_car.gd`. The crash and the cops reuse traffic cars. Assets: flares and cones from Kenney (CC0) or original.

## 4. Fit with what's already planned

- **World vision W4 (night arc)** already proposes 3-4 hour presets. The clock is what drives them; this doc adds the people and events layer. No conflict.
- **Narrative fabric** already uses "Dusk, Midnight, Pre-dawn" as the shape of a night, autosave at landmarks, and the garage as the daylight scene. The clock and dawn fit it directly.
- **Stage C** run loop: dawn is a natural "bank the pot" moment.
- **Gas station / landmarks**: each gets opening hours (diner 24 h, liquor store closes at 2 a.m.), so time changes where you can go.

## 5. Build order (each one: propose, Roy signs off, build)

| Phase | Contents | Size |
|---|---|---|
| L1 Clock | WorldClock, dashboard clock, date, dawn sky fade, windows on/off (P1) | Small |
| L2 Radio knows the time | Top-of-hour Dave lines, news bulletins, callers (P3-P5), Kokoro render pipeline | Small-medium (mostly writing) |
| L3 Hour bands + mood | Traffic count and type per band, rule-breaker share by event (section 3), sounds of other lives (P7) | Medium |
| L4 People at stops | Clerk, diner smokers, meet crowd (P8), needs W5 destinations | Medium-large |
| L5 Memory | City remembers you, phone texts (P9-P10) | Medium |

All performance claims are estimates; each phase is measured with the headless benchmark before it ships.

## 6. Roy's answers (2026-10-08)

"Changeable" = my pick, used until Roy says otherwise.

| # | Question | Answer |
|---|---|---|
| 1 | Game clock 8 p.m. to 6 a.m. | **Yes** (Roy) |
| 2 | Night length | **Compressed and carried over across sessions** (Roy: a night is longer than 90 min but you don't play that long). Section 1, option B |
| 3 | Time moves in free roam | **Yes** (Roy), with a setting to stop it |
| 4 | 6 a.m. not home | **Cutscene: drive home tired, park, keep earnings** (Roy) |
| 5 | Weekdays and dates, busier weekends | **Yes**, changeable (Roy: don't know) |
| 6 | Rule breakers change with events | **Yes**, changeable (Roy: don't know). Percentages in section 3 are starting values |
| 7 | People only where you stop | **Yes**, changeable (Roy: don't know) |
| 8 | Kokoro voices | **Open**: decided once the voice approach is chosen (sound and police threads) |
| 9 | Free, no-credit assets that aren't strictly public domain | **Yes** (Roy) |
| 10 | First step L1 (clock + windows switching on and off) | **Yes** (Roy), when Roy says build |

## Sources

- Kenney licence (CC0, no attribution, commercial): https://kenney.nl/support
- Quaternius Asset License v1.0 (no attribution, commercial, no reselling raw assets): https://quaternius.com/license.html
- Sonniss GDC bundle (royalty-free, commercial, no attribution, no AI training): https://gdc.sonniss.com/ , full terms https://sonniss.com/gdc-bundle-license/
- Kokoro TTS (Apache-2.0) and why Orpheus is out under the no-credit rule ("Built with Llama" credit): `/mnt/project-files/voice-ai-research.md`
- Traffic rule options A-D and night density curve: `/mnt/project-files/traffic-decisions.md` §3 and §9
