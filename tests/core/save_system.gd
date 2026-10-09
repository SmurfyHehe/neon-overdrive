extends SceneTree

# Save system, file level (run structure 2026-10-09; scripts/save/). Checks
# - atomic writes: a save reads back whole; a crash at each step of a write
#   (torn .tmp, main file moved away, main file torn) still reads the newest
#   good copy; backups stop at three
# - 3 slots are separate; the active slot is remembered
# - a mod tree whose every copy is broken loads empty, and money and bought
#   parts are untouched; a fitted part that is not owned is dropped alone
# - a broken wallet value falls back to the backup's, field by field
# - nothing is written during a chase; a chase left open (quit/crash) is a bust
#   on the next load, once, and the run is cleared
# - the rename migration copies the old folder (never moves it), once, never
#   over a folder that already has saves, and finishes a copy cut short
#
# Exit code 1 on failure. Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/core/save_system.gd

const AtomicJson := preload("res://scripts/save/atomic_json.gd")
const SaveStore := preload("res://scripts/save/save_store.gd")
const UserDirMigration := preload("res://scripts/save/user_dir_migration.gd")

const ROOT := "user://test_save_system"

var failures: Array[String] = []

func _initialize() -> void:
	_wipe(ProjectSettings.globalize_path(ROOT))  # this test's own folder
	SaveStore.root = ROOT.path_join("saves")
	SaveStore.slot = 0
	SaveStore.chase_active = false
	_atomic()
	_slots()
	_mod_tree_damage()
	_wallet_fallback()
	_chase()
	_migration()
	for m in failures:
		printerr("FAIL: ", m)
	print("save_system: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _atomic() -> void:
	var f := ROOT.path_join("atomic/a.json")
	_check(AtomicJson.write(f, {"n": 1, "x": 0.1 + 0.2}), "first write failed")
	var r := AtomicJson.read(f)
	_check(r.get("data", {}).get("n") == 1.0 and r.data.x == 0.1 + 0.2, "write did not read back exactly: %s" % str(r))
	for i in range(2, 7):
		AtomicJson.write(f, {"n": i})
	_check(int(AtomicJson.read(f).data.n) == 6, "newest copy not read")
	_check(FileAccess.file_exists(f + ".bak3") and not FileAccess.file_exists(f + ".bak4"), "backups should stop at 3")
	_check(int(AtomicJson.decode(FileAccess.get_file_as_string(f + ".bak1")).n) == 5, "bak1 should be the previous save")
	_check(not FileAccess.file_exists(f + ".tmp"), ".tmp left behind after a good write")

	# Crash 1: the .tmp was cut short (power off mid-write). Main copy wins.
	_put(f + ".tmp", AtomicJson.encode({"n": 7}).left(20))
	_check(int(AtomicJson.read(f).data.n) == 6, "a torn .tmp should be skipped")
	# Crash 2: main moved to .bak1, .tmp not yet renamed in. The new copy wins.
	_shift_backups(f)
	DirAccess.rename_absolute(f, f + ".bak1")
	_put(f + ".tmp", AtomicJson.encode({"n": 7}))
	_check(int(AtomicJson.read(f).data.n) == 7, "a whole .tmp with no main copy should be read")
	# ...and the next write after that crash still works and keeps going.
	_check(AtomicJson.write(f, {"n": 8}) and int(AtomicJson.read(f).data.n) == 8, "write after a crash failed")
	# Crash 3: main copy torn (bad disk, hand edit). Falls back to .bak1.
	var text := FileAccess.get_file_as_string(f)
	_put(f, text.left(text.length() - 3))
	var back := AtomicJson.read(f)
	_check(back.get("damaged", false) and int(back.data.n) == 7, "a torn main copy should fall back to .bak1: %s" % str(back))
	# One flipped character with a valid shape is caught by the checksum.
	_put(f, AtomicJson.encode({"n": 9}).replace("9", "4"))
	_check(int(AtomicJson.read(f).data.n) == 7, "checksum did not catch an edited file")
	# A write over a torn main copy keeps it aside as .bad, not as a backup.
	_check(AtomicJson.write(f, {"n": 10}) and FileAccess.file_exists(f + ".bad"), "torn main copy not kept aside")
	_check(int(AtomicJson.decode(FileAccess.get_file_as_string(f + ".bak1")).n) == 7, "a torn copy was rotated into the backups")

## Step 2 of a write, done by hand: the oldest backup goes, the rest shift.
func _shift_backups(f: String) -> void:
	DirAccess.remove_absolute(f + ".bak3")  # this test's own file
	DirAccess.rename_absolute(f + ".bak2", f + ".bak3")
	DirAccess.rename_absolute(f + ".bak1", f + ".bak2")

func _slots() -> void:
	_check(SaveStore.active_slot() == 1, "default slot should be 1")
	_check(SaveStore.save_wallet(100, 5), "wallet save slot 1")
	_check(SaveStore.select_slot(2) and SaveStore.save_wallet(200, 0), "wallet save slot 2")
	_check(not SaveStore.select_slot(4) and not SaveStore.select_slot(0), "out-of-range slot accepted")
	_check(SaveStore.load_wallet(1).cash == 100 and SaveStore.load_wallet(2).cash == 200, "slots not separate")
	_check(SaveStore.summary(3).empty and not SaveStore.summary(1).empty, "summary empty flag wrong")
	SaveStore.slot = 0  # as on a relaunch
	_check(SaveStore.active_slot() == 2, "active slot not remembered")
	SaveStore.select_slot(1)

func _mod_tree_damage() -> void:
	SaveStore.save_wallet(1500, 300)
	SaveStore.save_garage(["exhaust_a", "turbo_s1", "wheels_mesh"])
	SaveStore.save_mod_tree({"p1_coupe": {"installed": ["exhaust_a", "turbo_s1", "not_bought"]}})
	var t := SaveStore.load_mod_tree()
	_check(t.cars.p1_coupe.installed == ["exhaust_a", "turbo_s1"], "a fitted part that is not owned should be dropped alone: %s" % str(t))
	# Every copy of the mod tree broken.
	for p in AtomicJson.candidates(SaveStore.file("mod_tree")):
		if FileAccess.file_exists(p):
			_put(p, "{ broken")
	t = SaveStore.load_mod_tree()
	_check(t.damaged and t.cars.is_empty(), "a broken mod tree should load empty: %s" % str(t))
	_check(SaveStore.load_garage().owned_parts == ["exhaust_a", "turbo_s1", "wheels_mesh"], "a broken mod tree lost bought parts")
	var w := SaveStore.load_wallet()
	_check(w.cash == 1500 and w.bank == 300, "a broken mod tree lost money: %s" % str(w))
	_check(SaveStore.save_mod_tree({}) and not SaveStore.load_mod_tree().damaged, "mod tree did not save over a broken one")

func _wallet_fallback() -> void:
	SaveStore.save_wallet(700, 50)
	SaveStore.save_wallet(800, 60)
	# Newest copy has a checksum-valid but bad cash value (an older bug, say).
	_put(SaveStore.file("wallet"), AtomicJson.encode({"cash": -5, "bank": 61}))
	var w := SaveStore.load_wallet()
	_check(w.cash == 700 and w.bank == 61, "wallet should fall back per field: %s" % str(w))

func _chase() -> void:
	SaveStore.save_run({"version": 1, "where": "before"})
	_check(SaveStore.begin_chase(), "begin_chase failed")
	_check(not SaveStore.save_run({"version": 1, "where": "during"}), "run saved during a chase")
	_check(not SaveStore.save_wallet(1, 1), "wallet saved during a chase")
	_check(not SaveStore.select_slot(2), "slot switched during a chase")
	_check(SaveStore.load_run().get("where") == "before", "the pre-chase run was changed")
	# Quit mid-chase: the process ends with the chase open. Relaunch:
	SaveStore.chase_active = false
	var meta := SaveStore.load_meta()
	_check(meta.busted and meta.pending_busts == 1, "a chase left open should bust on return: %s" % str(meta))
	_check(not SaveStore.load_meta().busted, "the same bust counted twice")
	_check(SaveStore.take_pending_bust() == 1 and SaveStore.take_pending_bust() == 0, "pending bust not handed over once")
	# A chase that ends normally is not a bust.
	SaveStore.begin_chase()
	SaveStore.end_chase()
	_check(not SaveStore.load_meta().busted and SaveStore.save_run({"version": 1}), "an ended chase still blocks or busts")

func _migration() -> void:
	var old := ProjectSettings.globalize_path(ROOT.path_join("Neon Overdrive"))
	var new := ProjectSettings.globalize_path(ROOT.path_join("Boost Simcade"))
	DirAccess.make_dir_recursive_absolute(old.path_join("saves/slot_1"))
	DirAccess.make_dir_recursive_absolute(old.path_join("audio_cache"))
	_put(old.path_join("saves/slot_1/wallet.json"), AtomicJson.encode({"cash": 42, "bank": 0}))
	_put(old.path_join("tune_slots.json"), "{}")
	_put(old.path_join("audio_cache/x.res"), "cache")
	_check(UserDirMigration.migrate(old, new), "migration did not copy")
	_check(FileAccess.file_exists(new.path_join("saves/slot_1/wallet.json")) and FileAccess.file_exists(new.path_join("tune_slots.json")), "saves not copied")
	_check(FileAccess.file_exists(old.path_join("saves/slot_1/wallet.json")), "the old folder was not left as it was")
	_check(not DirAccess.dir_exists_absolute(new.path_join("audio_cache")), "caches should not be copied")
	_put(old.path_join("later.json"), "{}")
	_check(not UserDirMigration.migrate(old, new) and not FileAccess.file_exists(new.path_join("later.json")), "migration ran twice")
	# A new-name folder that already has its own saves is never overwritten.
	var fresh := ProjectSettings.globalize_path(ROOT.path_join("Fresh"))
	DirAccess.make_dir_recursive_absolute(fresh.path_join("saves"))
	_check(not UserDirMigration.migrate(old, fresh), "migrated over a folder with saves")
	# A copy cut short is finished next launch, without replacing what is there.
	var cut := ProjectSettings.globalize_path(ROOT.path_join("Cut"))
	DirAccess.make_dir_recursive_absolute(cut.path_join("saves/slot_1"))
	_put(cut.path_join(UserDirMigration.IN_PROGRESS), old)
	_put(cut.path_join("saves/slot_1/wallet.json"), "partial")
	_check(UserDirMigration.migrate(old, cut) and FileAccess.file_exists(cut.path_join("tune_slots.json")), "a cut-short copy was not finished")
	_check(not FileAccess.file_exists(cut.path_join(UserDirMigration.IN_PROGRESS)), "in-progress marker left behind")
	_check(UserDirMigration.legacy_dirs().size() == 2 * UserDirMigration.LEGACY_NAMES.size(), "legacy dirs")

func _put(p: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)

## Clears this test's own folder from a previous run.
func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
