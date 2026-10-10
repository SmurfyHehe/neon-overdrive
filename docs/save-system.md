# Save system

Built from the run-structure decisions of 2026-10-09. Code in `scripts/save/`.

## Rules it keeps

| Decision | Where |
|---|---|
| Auto-save only, no save button | `save_director.gd`: every 30 s of driving, on pause / Tuner / photo, at night roll-over, on quit (menu or window close) |
| 3 slots | `save_store.gd`: `user://saves/slot_1..3`, active slot in `active_slot.json` |
| Backups, crash-safe writes | `atomic_json.gd`: write `.tmp`, verify, rotate `.bak1..3`, rename in; SHA-256 header on every file |
| Never save during a chase | `SaveStore.begin_chase()` / `end_chase()`; every write refuses while `chase_active` (night clock too) |
| Quit mid-chase still busts you | `begin_chase()` marks the chase open on disk first; the next load turns it into a bust (`pending_busts`, run not resumed) |
| Resume exactly where you left | run save: which road (its id, the place on the lap, the heading: `scripts/world/road_map.gd`; a save from a road this build does not have starts at the top of the default road), road seed and shape, floating-origin index, nearby barrier rolls, car transform / velocity / spin / gear / rpm, clock, radio |
| Rename keeps the old saves | `user_dir_migration.gd`: copies (never moves) the old user folder on first launch under a new name |
| Tune slots carry no torque / redline | `tune_slots.gd`: engine paths (torque, redline, boost, torque shape) are not saved and not applied |
| Damaged mod tree keeps parts and money | separate files; bought parts live in `garage.json`, the tree only lists fitted ones |

## Slot layout

```
user://saves/
  active_slot.json
  slot_N/
    wallet.json    cash, bank (whole numbers >= 0; each falls back to a backup alone)
    garage.json    owned_parts: every part bought
    mod_tree.json  cars: {car_id: {installed: [owned part ids]}}
    run.json       the run to resume ({} = fresh start)
    meta.json      chase_open, pending_busts, saved_at
```

Each file also has `.bak1..3`, and a `.bad` copy if a broken main file was set aside.

## Not built yet (hooks only)

- Money, garage, mod tree and police do not exist yet. Their save sections and APIs (`save_wallet`, `save_garage`, `save_mod_tree`, `begin_chase`, `take_pending_bust`) are ready for them.
- What a bust costs is for stage F. Today a bust on return only means a fresh run plus a waiting `pending_busts` count.
- No slot menu yet. `SaveStore.select_slot(n)` and `summary(n)` are what one would call.
- Traffic is not saved. It respawns around the car, as on a fresh start.
- The tune (`player_tune.json`), exhaust tune and settings are still global files, not per slot.

## Renaming the game

"Neon Overdrive" is already in `UserDirMigration.LEGACY_NAMES`, so the Boost Simcade rename needs only the `config/name` edit. Any later rename adds the name it replaces to that list in the same change.
