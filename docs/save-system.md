# Save system

Built from the run-structure decisions of 2026-10-09; one save per slot since save core S1/S2 (2026-10-11). Code in `scripts/save/`.

## Slot layout

```
user://saves/
  active_slot.json
  slot_N/
    meta.json    slot plate + chase flag (tiny; the title screen reads only this)
    career.json  everything owned and done; written only at commit points
    night.json   the night in progress; written every 30 s while driving
    pre_v1/      copy of the slot's old files from before the upgrade
```

Every file has `"save_version": 2`, is written by `atomic_json.gd`, has `.bak1..3`, and a `.bad` copy if a broken main file was set aside.

| File | Holds |
|---|---|
| `meta.json` | `chase_open`, `pending_busts`, `saved_at`, `plate` (mode, car, night, act, nights_total, cash, bank, play_secs, difficulty, freemode_season) |
| `career.json` | `gen` (commit counter), `world` (seed, difficulty, difficulty_next), `wallet` (bank, receipts), `cars` (per car id: parts_owned, fitted, wear, damage, fuel, dirt), `current_car`, `tunes` (per car id: live, exhaust, slots), `story` (night, act, night_closed), `special` (unlocked), `walt` (first_total_used), `stats` (play_secs) |
| `night.json` | the run to resume (road, car transform and motion, clock, radio), `base_gen`, `night`, `cash`, `car_live` (wear, damage, fuel, dirt of the car you are in), `tunes_live` (tune changes since the last commit), `play_secs` |

A new system adds its own block to `career.json` and writes it through `SaveCore.commit()`. A block or field a build does not know is kept and written back untouched. No new files per system.

## Rules it keeps

| Decision | Where |
|---|---|
| Auto-save only, no save button | `save_director.gd` writes the night every 30 s of driving, on pause / Tuner / photo, at night roll-over, on quit |
| The career is written at commit points only | `SaveCore.commit(reason)`: dawn (`Wallet.bank_night`), quit (menu, title, slot switch, window close), run end (restart, bust settled on load), a car switch, and the old `SaveStore.save_*` calls. Never while driving, never in a chase |
| Money is never lost or doubled | commit order below |
| 3 slots, each its own car, tunes, dirt, clock and difficulty | `save_core.gd`; nothing game-state is kept outside the slot any more. Settings (audio, graphics, view, fx, traffic, keys) stay global |
| Backups, crash-safe writes | `atomic_json.gd`: write `.tmp`, verify, rotate `.bak1..3`, rename in; SHA-256 header on every file |
| Never save during a chase | `SaveCore.begin_chase()` / `end_chase()`; every write refuses while `chase_active` |
| Quit mid-chase still busts you | `begin_chase()` marks the chase open in `meta.json` first; the next load turns it into a bust (`pending_busts`, run not resumed) |
| Resume exactly where you left | the run in `night.json`: which road (`road.id`, `road.s`, `road.dir`, `road.act`: `RoadMap.where()`; a save with no road id or one this build does not have starts at the top of the default road), road seed and shape, floating-origin index, nearby barrier rolls, car transform / velocity / spin / gear / rpm, clock, radio |
| A quit is not a free repair | `car_live` goes with every night save; a commit folds it into `cars[id]`; `PlayerCar` reads it back on load |
| Old saves are upgraded, not thrown away | `save_upgrade.gd`, below |
| A save from a newer build is left alone | a slot with a higher `save_version` is not loaded and never written; the game boots as if the slot were empty and logs it |
| Rename keeps the old saves | `user_dir_migration.gd`: copies (never moves) the old user folder on first launch under a new name |
| Tune slots carry no torque / redline | `tune_slots.gd`: engine paths are not saved and not applied |

## Commit order

1. Build the new career with `gen + 1`, folding in `car_live` and `tunes_live`. At dawn tonight's cash is added to `wallet.bank` and `story.night_closed = N`.
2. Write `career.json`.
3. Write `night.json` with `base_gen = gen + 1` (at dawn and at a run end: without the run).
4. Write the `meta.json` plate.

On load:

| What is on disk | What happens |
|---|---|
| `meta.chase_open` | a bust; the night is not resumed |
| `night.json` has no run | the next night starts from the career |
| `night.night <= story.night_closed` | dawn already banked it: the night is dropped (the game died between steps 2 and 3) |
| `night.base_gen < career.gen` | position, clock, cash and radio from the night; the car's state from the career, which is newer |
| equal | resumed exactly |

## Upgrades

`save_upgrade.gd` holds one pure step per version (`upgrade_1_to_2`, later `upgrade_2_to_3`), run in order on load. Version 1 was separate `wallet / garage / mod_tree / run / meta / special` files per slot, with tunes, clock, dirt and the car pick outside the slots.

- The slot's old files are copied to `slot_N/pre_v1/` first and stay in place; once `career.json` exists they are never read again.
- Bank to the career, cash to the night. Each car owns the parts it has fitted; the rest go to the car you drive.
- The saved run becomes the night.
- `player_tune*.json`, `exhaust_tune.json`, `tune_slots.json`, `night_clock.cfg`, `car_dirt.cfg`: into the slot that was being played. Other slots start with none. `settings.cfg [player] car`: into every slot that has a save. Those files stay on disk and are not read again.

To change the format: add the step, bump `CURRENT_SAVE_VERSION`, freeze a save of the old version under `tests/save/fixtures/v<N>/`. `tests/save/save_upgrade.gd` fails if the version is bumped without a step.

## The old API

`save_store.gd` keeps its function names (`load_wallet` / `save_wallet`, `load_garage` / `save_garage`, `load_mod_tree` / `save_mod_tree`, `load_special` / `save_special`, `load_run` / `save_run` / `clear_run`, `load_meta`, `begin_chase`, ...) on top of the new files, so existing callers work. New code should not use it.

## Cost

Measured on Roy's laptop (`tests/save/save_core.gd` prints it): one crash-safe write of a tiny file takes about 6 ms, and a commit is three of them, so a commit takes 25 to 50 ms, more for a big career (18 cars with 4 tunes each is 138 KB). It runs at commit points, not every frame. A named tune is about 1.4 KB; there is no cap on how many a car keeps.

## Not built yet

- Damaged-save screens, the newer-version message, a disk-full line, Delete save.
- Act checkpoints and failed-act replay.
- Whether a run end repairs the car (today S1 only saves wear, damage and fuel).
- What a bust costs is for stage F. Today a bust on return means a fresh run plus a waiting `pending_busts` count.
- Traffic is not saved. It respawns around the car, as on a fresh start.
- The exhaust tune is one entry under the coupe's id whatever car is driven (`EngineAudio.START_PRESET`), as before; it is per slot now.

## Renaming the game

"Neon Overdrive" is already in `UserDirMigration.LEGACY_NAMES`, so the Boost Simcade rename needs only the `config/name` edit. Any later rename adds the name it replaces to that list in the same change.
