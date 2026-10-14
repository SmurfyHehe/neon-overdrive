# Mirrors you can use (2026-10-14)

Roy, 14:21Z: "the mirrors really need love because they just exist but are
useless too." Code read at build 4 (`claude/project-thread-f2fai6` 4164226:
`scripts/view/cockpit_mirrors.gd`, `cabin_spec.gd`, `chase_camera.gd`,
`ui/hud.gd`). Every number below was measured headless in Godot 4.7.2 with
each playable car booted, parked in the cockpit view, straight ahead at the
default FOV (62, 16:9). No physics change anywhere in this plan.

## 1. Why they are useless today

| # | What is wrong | Measured |
|---|---|---|
| 1 | **The rearview mirror is not on the screen** in several cars. It hangs where the car's header is, 25-30 degrees above the eye, and the screen top is 31 degrees. | On screen: pickup **0%**, drift coupe **7%**, beater 44%, tuner 80%, coupe 95% (its right edge clipped), the other six 100%. |
| 2 | **Everything in the glass is tiny.** The rear camera sees 56 degrees wide and that is squeezed into a glass 19 degrees wide (2.9x); the door cameras see 42 degrees squeezed into 9 (4.6x). Real mirrors show about 25-30 (rear) and 15-20 (door). | A car 20 m behind is 37 pixels wide on a 1080p screen, 25 on 720p. A car in the next lane 10 m back shows in the door mirror at 45 / 29 pixels. |
| 3 | **The Low tier halves the render**, to 160x48 (rear) and 80x56 (door). The laptop is bound by the processor; a mirror's cost is the extra pass (culling, draw calls), not its pixels. So Low saved nothing you could feel and made the glass mush. | A car 20 m back: about 15 pixels in the texture. |
| 4 | **The right door mirror is off screen in every car** (55-63 degrees right; the screen edge is 47). Only a look round (right arrow tap, head to 35 degrees) shows it. Its blind-spot dot is invisible with it. | 0% on screen, all 11 cars. |
| 5 | **Each mirror redraws every other frame**, one frame late. At the laptop's 30-40 fps that is 15-20 updates a second: a stutter in the glass. | Code, `_process`. |
| 6 | **The door mirror glass is angled like the coupe's on every car** (`SIDE_GLASS_YAW`, `P1CoupeBuilder.MIRRORS`), which is why mirrors float off the body on five cars (#688). | Glass seen 18-38 degrees off its face. |
| 7 | **The chase view's rear strip** is 320x96 pixels at the top of the screen (17% of a 1080p width) and shows the same squeezed 56 degrees. | `hud.gd` STRIP_SIZE. |
| 9 | **The cop warning sat on the mirror** (Roy, 14:26Z): the police heat icon (96x52) was drawn top centre at y 14, exactly where the chase view's rear strip is (320x96 at y 12). | `heat_icons.gd`, `hud.gd`. |
| 8 | **Look back (B) in the cockpit is "usually blocked"** (Roy): the eye spins 180 degrees where it sits, and the rear window band between the seat tops / parcel shelf and the roof is only 5-10 degrees tall in the hatch (5), crossover (7), coupe (6) and wagon (7.5) out of a 62 degree view. The pickup, truck and beater show 19-23. A real driver leans to the middle and looks over the shoulder; the camera does not. | Geometry from each car's cabin numbers. |

Not wrong: the mirror image itself (left-right flipped, sees the world,
traffic and the car's own flank, not the interior, no glow, 250 m far clip);
the proximity cue (glass warms as a car closes in) and the blind-spot dots.

## 2. Smallest changes, in order, with laptop cost

| Step | Change | Cost on the laptop | Status |
|---|---|---|---|
| **1** | **Cop warning moved** to the top, just left of the rear strip's place, and a third bigger (128x70): clear of the strip in the chase and hood views and of the rearview glass (right of centre) and door mirrors (far edges, half way down) in the cockpit. **Rearview glass fitted to every cabin**: the car's own point slides forward along the windscreen and down it until the glass's outer edge is within 41 degrees and its centre within 18 above the eye (`CabinSpec.fit_rear_mirror`). Housing and stalk follow. **Mirror cameras narrower**: rear 56 -> 45 degrees wide, door 42 -> 31, so cars in the glass are 1.25-1.4x bigger. **Tiers**: Low keeps the render size and redraws every third frame; Medium every other (as today); High every frame at double size. | None at Medium; Low is a third cheaper than before. | **Draft PR** on the merge branch; test `view/mirror_readable` per car. |
| 2 | **Look back in the cockpit**: B swaps to the roof camera looking straight back (the hood view already does this), or lifts the eye to the roof liner and the middle. | None. | Roy picks (section 4). |
| 3 | **Rearview redraws every frame while a car is within ~15 m behind** (the proximity cue already knows), so a chasing cop reads smoothly. | One extra pass, only during a chase: estimate 0.3-0.6 ms; measure. | After 1. |
| 4 | **Door mirror glass per car**: angle from the car's own `door_mirror` point so the glass faces the eye; closes #688. | None. | Fable, laptop shots. |
| 5 | **Right mirror as a screen** (Roy 1568 yes): in the cockpit, a door mirror whose glass is off screen (the right one, in every car) is drawn as a small screen (220x154) at that window edge, 62% down, like the camera-mirror screens in cars without door glass; it fades out when the head turns and the real glass comes on screen, and while looking back. The blind-spot cue warms and thickens its frame, so a car on the right finally shows. Not the 2026-10-07 automatic glance: that turns the whole view mid-chase and lives in the camera code another thread is changing. | None: the same render the glass shows, one pass per period as before (the off-screen skip no longer applies to it). | **In PR 741**; `view/mirror_readable` + `view/look_around`. |
| 6 | **Chase rear strip** 480x144, drawn 1:1 (the rear renders at the strip's size while only the strip shows it) with the narrower rear camera from step 1. | Pixels only, about free; same pass. | **Roy 1552 yes; in PR 741.** |

Cost basis: the three mirrors cost about 1.05 ms at 3 traffic cars when they
were built (PR #130 notes, alternating frames); with 16 parts-built cars behind
you it is more, and no laptop number exists since. Ask for one benchmark run,
cockpit view, 16 cars, mirrors off / Low / Medium, before and after step 1
(laptop, no other Godot running).

## 3. Step 1 in numbers (before -> after, straight ahead, FOV 62)

| Car | Rear mirror on screen | Right of centre | Above the eye |
|---|---|---|---|
| Pickup (Camel) | 0% -> 100% | 39 -> 34 deg | 30 -> 19 |
| Drift coupe | 7% -> 100% | 48 -> 34 | 25 -> 9 |
| Beater | 44% -> 100% | 36 -> 33 | 25 -> 19 |
| Tuner | 80% -> 100% | 37 -> 34 | 22 -> 18 |
| Coupe | 95% -> 100% | 37 -> 34 | 13 -> 8 |
| Crossover | 100% | 36 -> 34 | 19 -> 19 |
| Wagon, hatch, muscle, kei, truck | 100% (unchanged or within 2 deg) | | |

The kei (open top) keeps its own point: its screen top is a hand above the eye.

## 4. For Roy (the coordinator numbers these)

- Look back in the cockpit: **roof camera looking straight back** (my pick, the hood view already does it) or the eye lifted to the roof liner and the middle (still partly blocked on the hatch and coupe)?
- Mirror camera widths: **1551 narrower, as built.**
- Rear strip in the chase view bigger (480x144): **1552 yes, in PR 741.**

## 5. Needs the laptop (Fable by eye)

Cockpit screenshots in the coupe, wagon, pickup and drift coupe with a car 10 m
and 25 m behind and one alongside on the left, before and after step 1: the
rearview's new place (coupe: 8 cm forward and down, onto the windscreen), the
size of cars in the glass, and the Low tier's 20 Hz glass at the laptop's frame
rate; the chase view's 480x144 strip and the cop warning beside it with a chase on. No cloud screenshots: headless Godot has no renderer.

## 6. Reach (rule 1566, 2026-10-14): what the change must touch, and did

| Where | Reached by | Checked by |
|---|---|---|
| 11 playable cars + monster truck + lowrider (borrow the coupe cabin) | `CabinSpec.for_kind` fits every cabin | `view/mirror_readable` looped over all 13 in `run_tests.bat` |
| NPC / traffic / cop cars | not applicable: no cockpit, no mirrors rendered; they appear *in* the glass, which the fit rule does not change | `fleet/interior_unique` still passes |
| Cockpit view (mirrors on) | glass fitted, cameras 14/22, tier cadence; right-mirror inset when the glass is off screen, gone when looked at or looking back | `mirror_readable` (rule table, live state, inset inside the window and off glass/strip/icon/warning lights at all 5 sizes), `look_around` |
| Chase and hood views (rear strip) | strip 480x144 drawn 1:1, rear renders at strip size | `mirror_readable` strip check |
| Photo mode, garage, title, pause orbit | no mirrors or strip there (set_active only in cockpit, strip only outside it) | unchanged |
| Cop warning (HeatIcons), warning lights, info line | icon left of the strip; warning lights inset 330 (was 400, which started on the strip at 1280x720); info line measured against the icon | `mirror_readable` loops `DisplaySettings.RESOLUTIONS` (1280x720 .. 2560x1440) |
| Graphics tiers Low / Medium / High, mirrors / rear_strip toggles | `FxSettings.mirror_period` 3/2/1, scale 1/1/2 | `mirror_readable` tier checks |
| Modes (free, story, menu) | HUD and cockpit are mode-independent | - |

Missed before this check: the two specials were not in the test loop, and the
warning-lights row overlapped the wider strip at 1280x720 (the default windowed
size). Both fixed in PR 741. Right door mirror off screen: #743, step 5, in
PR 741 (laptop shot still owed). Still open: look back (#742, camera thread),
door glass angles per car (#688).

## Steelman / premortem

Steelman: the mirrors already render the right thing; they fail on geometry
(off screen, squeezed, blurred by the tier the laptop runs). Two constants and
one fit rule mend that for every car, present and future, at no cost.
Premortem: a narrower camera shows less, so a car two lanes over and close may
leave the door mirror sooner; if Roy misses the wide view, widen the glass
rather than the camera. The coupe's rearview moves 8 cm, which Roy will notice
in the car he knows best; `fleet/sight_line` says it stays out of the road
band, but the look is judged on the laptop.
