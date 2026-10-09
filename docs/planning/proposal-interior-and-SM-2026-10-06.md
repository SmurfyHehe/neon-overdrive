# Proposal: cockpit interior rework + S and M items (for Roy's sign-off)

Nothing is built. Each numbered step is its own PR, and I stop for your sign-off before each one starts and before each one is called done. Approving this page approves the order only, not a batch.

## What is ugly now (read from `scripts/view/cockpit_frame.gd`, 61 lines)
- Everything is flat, unshaded near-black boxes (`SHADING_MODE_UNSHADED`), so there is no depth, no light and no texture. The dash reads as a black slab.
- A-pillars and roof edge are plain tilted boxes; no door cards, mirror, seat, dash hood or centre console.
- The wheel is a thin torus with three stick spokes; no hub, no stitching, no grip shape.
- No gauges at all (only warning lights). The look is a stand-in, as the file header says.

## Interior rework: target look
- "Gritty PS2 night": low-poly, hard shapes, grain and wear painted into vertex colours or small textures; no neon.
- Palette: charcoal/navy base (`#0E1424`, `#1B2A4A`), silver trim, gauge glow sodium orange `#FF8A1F` and amber `#FFC066`. No magenta, no cyan. Police blue stays out.
- Shaded (not unshaded) materials lit by one dim warm dash light plus the existing cool key, so surfaces get form without losing night readability.
- Add: dash hood over a gauge pod, centre console, door cards, rear-view mirror, thicker pillars with headliner, proper wheel (rim, hub, 3 spokes), seat edges.
- **Per car (Roy, 2026-10-06):** each car gets its own interior that references that car's design sheet (dash shape, wheel, console, trim). Step 1 builds the coupe (P1); the other five get theirs in Stage D, one per car PR. A shared builder holds the common parts so each car only supplies its own shapes and colours.
- **Gauges (Roy, 2026-10-06, corrected):** NOT shared. Each car's cluster is its own design (gauge shapes, layout, glow), so the cars feel distinct. Values still read from that car's `CarSpec` (redline, speed range, gears), but the look is per car. Step 4 builds the coupe's cluster; each later car brings its own in Stage D.
- Model: Fable. Effort: M to L (art-heavy, I rate it above the other M items). Needs RC: yes, because I need real rendered screenshots from the cockpit view, not just headless logic.

## Order and effort
| Step | PR | Effort | Model | RC |
|---|---|---|---|---|
| 1 | Interior rework (coupe) | M-L | Fable | Yes + your eyes |
| 2 | RPM-bar shift cue (green to red) | S | Sonnet | Yes |
| 3 | Visible shifter | M | Fable | Yes |
| 4 | Instrument cluster for the coupe (speedo, tach, gauges, existing warning lights); per-car design, values from `CarSpec` | M | Fable | Yes |
| 5 | Audio fatigue pass: exhaust pops too frequent and bad-sounding, then the same check on the other sound layers | M | Opus | Yes + Roy listens |
| 5b | Controls page in pause menu | S | Haiku/Sonnet | Yes |
| 6 | Tuner merge (tuner + exhaust + auto-tune into one raw Tuner) | M | Sonnet | Yes |
| 7 | #31 camera smoothing (3 modes) | S | Sonnet | Yes |
| 8 | #28 out-of-bounds handling | S | Sonnet | Yes |
| 9 | Docs sync (ROADMAP/ISSUES to current main, radio header) | S | Haiku | Yes |
| 10 | #80 engine sound per car (suggest deferring until more cars exist) | M | Sonnet | Yes |

Why this order: steps 3 and 4 live inside the interior, so the rework goes first. The RPM cue follows because the cluster's tach reuses its colour logic. Controls page, Tuner merge and the small fixes are independent and can move earlier if you prefer.

## Steelman
Interior first fixes the thing you see every second in cockpit view, and it gives the shifter and cluster a finished place to live, so they are built once.

## Premortem (why it fails)
- "Ugly" is subjective and I can only judge screenshots; the first pass may miss your taste. Mitigation: one reference look and a screenshot checkpoint before the PR is opened.
- Shaded materials may be too dark at night, or cost frames on the i5-1235U. Mitigation: measure with `benchmark.bat` and keep the old unshaded fallback.
- Per-car interiors multiply cost in Stage D (6 interiors). Mitigation: shared builder in step 1, so each later car supplies only shapes and colours.
- Cockpit camera clipping into new geometry at FOV 78; the existing `cockpit` test must keep passing.
- Several agents in one checkout: each step uses its own worktree; no HEAD moves in the root.

## Questions for you (defaults if you do not answer)
1. Interior reference: a real car category (default: late-90s sports coupe, driver-focused) or a mood board you send?
2. ~~Gauge style~~ Settled by Roy: same layout in every car, driven by `CarSpec`. Analog needles unless you say otherwise.
3. #80 is the GitHub issue "engine sound per car/upgrade" (each car and each engine upgrade sounds different). Defer it (default) until more cars exist?

## Exhaust sound (new, Roy 2026-10-06)
Current pops are in `engine_synth.gd`: random-timed noise bursts (20 ms decay) plus a low thump, rate `pops x (3 + 22 x rpm)` per second. Hypothesis, not yet heard by me: random white-noise bursts read as static, not as crackle. Plan: render before/after WAV clips from headless Godot, rework burst shape (pitched thump, tonal ring, clustered burst timing, per-rpm character), and you pick by ear. The `pops` knob stays cosmetic only. Defer #80 (per-car engine sound) as agreed.

## Model choice
Per task, by what fits, not a fixed rule (Roy, 2026-10-06). I pick the model for each PR and say why when I propose it.
- Interior and cluster: Fable (your rule for Stage B interiors; judging shape and look from screenshots is where it matters).
- Exhaust rework: Opus. Hard to verify without ears, so reasoning about the DSP matters more than volume of code.
- Controls page, Tuner merge, camera smoothing, out-of-bounds, RPM cue, docs sync: Sonnet (Haiku for docs and Controls page). Higher models would cost more without better results.
- Step 3 (shifter) is art-heavy cockpit work: Fable.

## Audio fatigue (Roy, 2026-10-06)
Any repeating sound gets old: pops are too frequent now, and the same risk applies to squeal, wind/road loops, turbo, and radio breaks. Step 5 targets: (1) fewer, more varied pops (rate cap, cooldown, random size and tone, silence between bursts, scaled by how long the throttle was held); (2) a repetition check on each loop layer in `car_audio.gd` (loop length, pitch/gain drift so it never repeats audibly); (3) before/after clips for you to judge. Exhaust stays cosmetic only.
