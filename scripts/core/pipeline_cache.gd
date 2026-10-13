extends RefCounted

# Keeps Godot's saved shader pipeline cache from growing for ever (#608).
#
# The engine keeps every shader pipeline it ever compiled in
# user://vulkan/pipelines.<renderer>.<gpu>.cache and loads the whole file at
# every start. Nothing ever takes old entries out, so the file only grows:
# on Roy's laptop it had reached 277 MB (a fresh one is ~22 MB after a drive),
# about +0.5 GB of memory for the whole session (measured 2026-10-13,
# notes/ram-usage-2026-10-13.md).
#
# The game cannot simply delete it: the engine reads it before any script
# runs, and on quit it writes everything it holds back, after the last script
# has run. So when the cache is stale -- a new build (the exe changed), or the
# file is over MAX_MB -- a small helper waits for the game to exit and then
# removes the file. The next start compiles afresh once (the splash warm-up
# covers most of it) and saves a small cache again.
#
# Exported builds only: the editor and tests never touch it. Tests are kept out
# of the player's folder by tests/run_tests.bat (APPDATA set to a test folder).
# No class_name on purpose: preload it, so no class cache refresh is needed.

const DIR := "user://vulkan"
const STAMP := "user://vulkan/pipelines_build.txt"
const MAX_MB := 64.0

static var _stale := false
static var _files: PackedStringArray = []

## Called once at start. Works out whether the cache should go at exit.
static func check_at_start() -> void:
	if not OS.has_feature("template"):
		return
	_files = cache_files()
	var build := build_id()
	var stamp := FileAccess.get_file_as_string(STAMP).strip_edges() if FileAccess.file_exists(STAMP) else ""
	_stale = is_stale(stamp, build, total_mb(_files))

## A new build, or a file grown past MAX_MB. A missing stamp counts as a new build.
static func is_stale(stamp: String, build: String, mb: float) -> bool:
	return stamp != build or mb > MAX_MB

## Called once at exit. Starts the helper that removes the stale cache after
## the game has closed, and stamps the current build.
static func tidy_at_exit() -> void:
	if not OS.has_feature("template"):
		return
	var f := FileAccess.open(STAMP, FileAccess.WRITE)
	if f != null:
		f.store_string(build_id())
		f.close()
	if not _stale or _files.is_empty():
		return
	var pid := OS.get_process_id()
	var paths := PackedStringArray()
	for p in _files:
		paths.append(ProjectSettings.globalize_path(p))
	if OS.get_name() == "Windows":
		var quoted := PackedStringArray()
		for p in paths:
			quoted.append("'%s'" % p.replace("/", "\\").replace("'", "''"))
		OS.create_process("powershell.exe", ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command",
			"Wait-Process -Id %d -ErrorAction SilentlyContinue; Remove-Item -LiteralPath %s -ErrorAction SilentlyContinue" % [pid, ",".join(quoted)]])
	else:
		var quoted := PackedStringArray()
		for p in paths:
			quoted.append("'%s'" % p.replace("'", "'\\''"))
		OS.create_process("/bin/sh", ["-c", "while kill -0 %d 2>/dev/null; do sleep 0.5; done; rm -f %s" % [pid, " ".join(quoted)]])

## The game's pipeline cache files (not the editor's ".editor.cache").
static func cache_files() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(DIR):
		if f.begins_with("pipelines.") and f.ends_with(".cache") and not f.ends_with(".editor.cache"):
			out.append(DIR.path_join(f))
	return out

static func total_mb(files: PackedStringArray) -> float:
	var bytes := 0
	for p in files:
		var f := FileAccess.open(p, FileAccess.READ)
		if f != null:
			bytes += f.get_length()
	return bytes / 1048576.0

## Changes with every export: the version plus the exe's modified time (the
## version is not bumped for every playtest build).
static func build_id() -> String:
	return "%s %d" % [str(ProjectSettings.get_setting("application/config/version", "")),
		FileAccess.get_modified_time(OS.get_executable_path())]
