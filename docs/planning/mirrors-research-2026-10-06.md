# Cockpit mirrors: options and recommendation (research only, 2026-10-06)

Nothing is built. This replaces the "rear-view mirror" line of the interior plan (step 1 of `docs/planning/proposal-interior-and-SM-2026-10-06.md`) once Roy signs off.

## What I checked in the repo (origin/main bd7957c)
- Renderer is **Mobile** (`project.godot:177`), physics 120 Hz (`:172`). Target laptop: i5-1235U, Iris Xe (`docs/audit-2026-10-06.md:4`).
- Frame budget is already tight: 40 traffic cars dipped to 11-15 fps while spawning, 44-62 fps after; physics alone is 7-14 ms per tick at 18-22 full-sim cars (`docs/audit-2026-10-06.md:32`, `:84`). Each car builds its own meshes and materials (`car_builder.gd:159-197`), so draw calls are not batched. **A mirror adds render cost, not physics cost**: it draws the scene again from a second camera, which repeats culling and the draw calls of everything it sees.
- Cockpit is a child of the chase camera, toggled with F (`chase_camera.gd:56-61`), FOV 78, far 400 m (`:92`). There are no mirrors, no SubViewports in the game, and no look-back key.

## Roy's pick (2026-10-06 14:29)
Roy chose four of the five options; only "full mirrors, one camera each" is out:
1. **Shared rear camera, sliced** into the rear-view and both door mirrors (the core).
2. **HUD rear-view strip**, reusing the same render, as a setting.
3. **Fake/texture mirror**. Assumption, not confirmed by Roy: it is the "mirrors off" / low-spec look, so the glass shows dim reflective texture instead of going blank, at ~0 cost.
4. **Look-back key + proximity cue.**
Setting proposal: `Mirrors: cockpit (live) / HUD strip / off (fake glass)`, look-back key and proximity cue always available.
Order: 1 first (it carries the perf risk), then 2-4 as small follow-ups. Each still needs Roy's sign-off before build.

## Options

| # | Option | Driving use | Perf cost (Iris Xe, Mobile) | PS2-night fit | Per-car individuality | Effort |
|---|---|---|---|---|---|---|
| A | **Full planar mirrors**: one SubViewport + Camera3D per mirror (3), true reflection maths (e.g. the MIT [Mirror3D](https://store.godotengine.org/asset/joyless/mirror3d/) addon, or [PlanarReflector-CPP](https://godotengine.org/asset-library/asset/4102)) | Best: correct angles and parallax per mirror | Highest: 3 extra scene renders per frame. Not affordable with traffic on this laptop | Fine | Full (each mirror placed per car) | M |
| B | **One shared rear camera, three mirror slices**: one low-res SubViewport behind the driver's head looking back with a wide FOV; the rear mirror and both door mirrors each show a slice of that one image (flipped) | Very good: you see who is behind and who is alongside-behind. Door mirrors lack true parallax, which few players notice at speed | 1 extra render, at low res, throttled to 30 Hz, cockpit view only, trimmed (below). Likely 1-3 ms; must be measured | Strong: low res + nearest filtering + the existing grain reads as PS2 mirror glass | Full: each car supplies mirror shapes and positions as data; the camera is shared | M |
| C | **HUD rear-view strip**: the same low-res rear render shown as a bar at the top of the screen, not in the cockpit geometry (the PS2-era NFS bumper-cam style, from memory, not verified) | Good; always readable, no clutter in the cockpit | Same as B | Strong (very period-correct) | None: same strip for every car | S once B exists |
| D | **Fake mirrors**: a static or scrolling texture, or a screen-space copy of the main view | Useless: shows nothing real behind you | ~0 | — | — | S |
| E | **Look-back key + proximity cue** (hold a key to view rearward; small HUD arrows or glow when a car is close alongside) | Partial: look-back hides the road ahead; proximity cue only says "something is there" | ~0 for the cue; look-back just swaps the main camera | Fine | None | S |

D is ruled out: Roy asked for *usable* mirrors. A is the "correct" answer but costs three renders on a laptop that already drops frames with traffic.

## How other games handle it (sources)
- Industry habit is a cut-down second render: reduced resolution, a small slice of the scene, "a bare minimum version without any fancy extras" ([Unreal forum thread](https://forums.unrealengine.com/t/rear-view-mirror/113452)).
- iRacing exposes separate mirror LOD settings because "every mirror forces the engine to redraw the world from a different angle"; cars in the mirror can be far less detailed and still do their job ([boxthislap.org](https://boxthislap.org/the-hidden-iracing-settings-that-can-give-you-more-fps-without-upgrading-your-pc/)).
- ACC on console shipped low-res, blurry mirrors players complained about, later patched ([traxion.gg](https://traxion.gg/assetto-corsa-competizione-console-update-will-improve-mirror-quality-and-multiplayer/)): too low a resolution makes mirrors unreadable, so the resolution needs a floor.
- Source engine's rear-view mirror is a render-target camera, same idea as B ([Valve wiki](https://developer.valvesoftware.com/wiki/Rear_View_Mirror)).

## Godot 4 levers for B (API facts; each to be confirmed in the prototype)
- `SubViewport.size`: e.g. 384 x 96 for all three mirrors together. Set `TextureFilter` to nearest on the mirror material for crisp PS2 pixels.
- `SubViewport.render_target_update_mode`: `UPDATE_DISABLED` outside cockpit view (zero cost in chase view); in cockpit, request a render every other frame (~30 Hz at 60 fps) via `UPDATE_ONCE`. ([SubViewport docs](https://docs.godotengine.org/en/stable/classes/class_subviewport.html))
- `Camera3D.cull_mask`: put the cockpit and the player's own body on a layer the mirror camera skips. ([Camera3D docs](https://docs.godotengine.org/en/stable/classes/class_camera3d.html))
- `Camera3D.far` ~120-150 m instead of 400 m; traffic beyond that is irrelevant in a mirror.
- `Camera3D.environment`: a cheap Environment for the mirror (no glow; fog kept so the night look matches).
- Viewport MSAA off, positional shadow atlas 0. Directional shadows may still render; check in the prototype.
- Background reading: [Using Viewports](https://docs.godotengine.org/en/stable/tutorials/rendering/viewports.html).

## Recommendation: B, with C as a setting and E's look-back key as a cheap extra
Ship B for the coupe. Add a "Mirrors: cockpit / HUD strip / off" option later, which is almost free once B works (C reuses B's image). Mirrors-off gives the laptop a way out.

**Steelman.** One extra low-res render, only in cockpit view, at 30 Hz, is the cheapest way to get real information about cars behind and alongside. The low resolution is not a compromise in this game: chunky, nearest-filtered mirror glass under the grain fits "Gritty PS2 night" better than a sharp reflection would. Mirror shapes and positions are data per car, so each car's interior keeps its own mirrors without new code, and the cost never multiplies by mirror count.

**Premortem (why it fails).**
1. Cost is higher than expected on Iris Xe because unbatched traffic draw calls repeat in the mirror. Mitigation: measure first; shorter far plane; if still too costly, drop to 20 Hz or HUD-only.
2. 30 Hz mirrors judder against a 60 fps main view, and traffic sliding past may look choppy. Mitigation: try 30 and 60 Hz side by side; keep 60 Hz if it fits the budget.
3. Door mirrors show the wrong angle because they share one camera at the head. Mitigation: aim the slices from the door positions in the shader; if it still feels wrong, give door mirrors a second camera only when the budget allows.
4. Too low a resolution makes cars unreadable (the ACC complaint). Mitigation: fix a floor (a car at 30 m must be at least a few pixels wide) and judge by eye.
5. The mirror ghosts the cockpit or player car (layer setup missed). Covered by the cull mask and a test.

## Prototype plan (needs Roy's sign-off before any build)
- One PR, coupe only, inside or right after interior step 1. Model: Opus for the plumbing, Fable for how it looks in the cockpit. Needs Remote Control on Roy's laptop.
- Build: one `MirrorRig` (SubViewport + rear Camera3D, cockpit-only, update throttle, cull mask) and mirror meshes whose rects come from the coupe's data.
- Measure with `benchmark.bat` / `--print-fps` in cockpit view at 0 and 16 traffic cars: mirrors off vs on at 30 Hz vs 60 Hz, two resolutions. Pass bar to propose: no more than ~10% fps loss at 16 cars.
- Screenshots for Roy: the three mirrors at night with a car behind at 10, 30 and 60 m.
- Test: mirror viewport disabled in chase view; player body and cockpit not in the mirror's cull mask.
- Roy decides: resolution, 30 vs 60 Hz, and whether the HUD-strip setting and look-back key go in.

Effort: M for B. +S for the HUD-strip setting, +S for look-back.
