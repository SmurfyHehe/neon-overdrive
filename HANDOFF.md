# Neon Overdrive — Handoff (2026-09-12)

## Where things stand
- Godot version confirmed: **v4.7.2-stable** (read directly from project files) — `VehicleBody3D` is supported, cleared to build on.
- Project path: `C:\Users\Roy\Documents\NeonOverdriveGodot\` — `project.godot`, `Main.tscn`, `scripts/main.gd`, `scripts/car_builder.gd`.
- Current build is a direct Three.js port: lane-position movement (no real physics), boxy placeholder cars, fixed camera, no lighting/atmosphere pass. Untested in-editor as of last check.
- Original browser prototype (source of truth for anything not yet ported): https://claude.ai/code/artifact/56a869ba-c7b6-46d4-9614-86f6760a2df7

## Direction agreed this session
Target feel: **simcade** physics (weighted grip/slide, not lane-snap arcade, not full sim) + **beautiful low-poly** art (deliberate faceted geo + strong lighting, not placeholder boxes), inspired by *Street-Spec: 日本* (osoiDev, Steam — https://store.steampowered.com/app/4230950/StreetSpec/).

Working style: **one milestone at a time**, proposal → sign-off → build. Don't skip ahead.

## Plan, in order
1. **Physics (next up, not yet built):** Replace `main.gd` lane logic with `VehicleBody3D` + 4x `VehicleWheel3D` on the player car only. Targets: ~200 km/h top speed, punchy but not instant 0-100, friction ~1.2-1.5 (grip with reachable slide), speed-sensitive steering. Traffic/AI cars stay on old movement logic for this pass. Add visual tilt (accel/brake/corner) to fake weight transfer.
2. **Environment/atmosphere:** WorldEnvironment fog + directional light + skybox (pick from the Vice Nights / Heat Check / Sunset Vice style bank — Heat Check's neon grid horizon fits best), bloom on emissives, dynamic camera FOV/shake tied to speed.
3. **Art (car models):** rebuild with real panel definition (200-500 tris), emissive trim/underglow, baked AO, simple 2-3 slot livery system.

## Backlog (after core feel is right — don't build yet)
Drift scoring/combo system, tuning menu (hook into `car_builder.gd`), livery/color picker, ghost/replay of best lap, police pursuit (cut from original JS port), checkpoint-sprint vs endless-dodge modes, engine-pitch/tire-screech audio tied to physics state.

## Open items / risks
- Godot editor run has not been verified working end-to-end this session — confirm project opens and runs before investing in physics rework.
- Scope creep is the main risk: simcade physics + beautiful low-poly + open feature backlog is a lot for a solo build — stick to the one-milestone-at-a-time order above.
