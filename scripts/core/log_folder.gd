extends RefCounted

# "Open log folder" (release-readiness list, 2026-10-08). Godot already writes
# godot.log (plus a few older rotated copies) into user://logs on desktop, in
# exported releases too; this only finds that folder and opens it in Explorer
# so a player can attach the log to a bug report. Preloaded, no class_name, so
# no class-cache refresh is needed.

## The log file as an absolute OS path, from the project's file-logging setting.
static func log_file() -> String:
	var path := str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	return ProjectSettings.globalize_path(path)

## The folder holding the log, as an absolute OS path.
static func log_dir() -> String:
	return log_file().get_base_dir()

## Whether Godot writes a log file on this platform at all.
static func logging_enabled() -> bool:
	return bool(ProjectSettings.get_setting("debug/file_logging/enable_file_logging.pc", true))

## Opens the log folder in the OS file manager. Creates it first, so the button
## still opens something on a first run before Godot has flushed a log.
static func open() -> Error:
	var dir := log_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	return OS.shell_open(dir)
