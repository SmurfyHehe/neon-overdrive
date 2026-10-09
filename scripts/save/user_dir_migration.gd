extends RefCounted

# Keeps saves across a rename of the game (run structure, 2026-10-09: the
# planned "Boost Simcade" rename must not lose the old save folder).
#
# Godot names the user folder after config/name: %APPDATA%\Godot\app_userdata\
# <name>, or %APPDATA%\<custom_user_dir_name> when use_custom_user_dir is on.
# Renaming the project therefore points user:// at a new, empty folder. On the
# first launch under a new name, run() COPIES the old folder's files into the
# new one (it never moves or deletes the old one, so going back to an older
# build still finds its saves), then writes a marker so it happens once.
#
# It copies only when the new folder has no saves yet: a player who already
# started under the new name is never overwritten. Caches and Auto-Tune job
# files are skipped; everything else (saves, tune files, settings, photos)
# comes along. Add every past name to LEGACY_NAMES when renaming.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const TestMode := preload("res://scripts/test_mode.gd")

## Every name the game has shipped under, newest first.
const LEGACY_NAMES := ["Neon Overdrive"]
const MARKER := ".migrated_from"
const IN_PROGRESS := ".migrating_from"
const SKIP := ["audio_cache", "autotune", "logs", "shader_cache", "vulkan"]

## Copies an older name's folder into this one if needed. Returns the folder it
## copied from, or "" (nothing to do, already done, or in test mode).
static func run() -> String:
	if TestMode.active():
		return ""
	var here := OS.get_user_data_dir()
	for d in legacy_dirs():
		if d.simplify_path() != here.simplify_path() and migrate(d, here):
			return d
	return ""

## Where each legacy name's folder would be, both Godot layouts.
static func legacy_dirs() -> Array[String]:
	var out: Array[String] = []
	var data := OS.get_data_dir()
	for n in LEGACY_NAMES:
		out.append(data.path_join("Godot/app_userdata").path_join(n))
		out.append(data.path_join(n))
	return out

## Copies from_dir into to_dir when from_dir exists, to_dir has no saves and no
## marker. Existing files in to_dir are never replaced. True if it copied.
static func migrate(from_dir: String, to_dir: String) -> bool:
	if not DirAccess.dir_exists_absolute(from_dir):
		return false
	if FileAccess.file_exists(to_dir.path_join(MARKER)):
		return false
	# A copy cut short (crash, full disk) leaves IN_PROGRESS behind and is
	# finished on the next launch; without it, saves here mean a new player.
	var resuming := FileAccess.file_exists(to_dir.path_join(IN_PROGRESS))
	if not resuming and DirAccess.dir_exists_absolute(to_dir.path_join("saves")):
		return false
	DirAccess.make_dir_recursive_absolute(to_dir)
	_write_text(to_dir.path_join(IN_PROGRESS), from_dir)
	if not _copy_tree(from_dir, to_dir, true):
		push_error("UserDirMigration: copying %s to %s failed part way; the old folder is untouched" % [from_dir, to_dir])
		return false
	_write_text(to_dir.path_join(MARKER), from_dir)
	DirAccess.remove_absolute(to_dir.path_join(IN_PROGRESS))
	return true

static func _write_text(p: String, text: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		f.store_string(text)

static func _copy_tree(from_dir: String, to_dir: String, top: bool) -> bool:
	var ok := true
	for sub in DirAccess.get_directories_at(from_dir):
		if top and sub in SKIP:
			continue
		var dest := to_dir.path_join(sub)
		DirAccess.make_dir_recursive_absolute(dest)
		ok = _copy_tree(from_dir.path_join(sub), dest, false) and ok
	for f in DirAccess.get_files_at(from_dir):
		var dest := to_dir.path_join(f)
		if FileAccess.file_exists(dest):
			continue
		ok = DirAccess.copy_absolute(from_dir.path_join(f), dest) == OK and ok
	return ok
