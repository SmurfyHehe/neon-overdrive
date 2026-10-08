extends RefCounted

# Crash-safe saving (release readiness, 2026-10-08). Every save file in the
# user folder goes through here, so a crash, a power cut or a full disk in the
# middle of a save can never leave the player with a half-written file and
# nothing else.
#
# A save writes <file>.tmp first and checks it reads back whole. Only then is
# the old file moved to <file>.bak and the .tmp moved into place. A crash at
# any point leaves either the old file, or the .bak plus the new .tmp, and the
# loaders here fall back to the .bak when the main file is missing or will not
# parse. The .bak is always the previous good save.
#
# No class_name on purpose: preload it, so no class cache refresh is needed.

const BAK := ".bak"
const TMP := ".tmp"

static func backup_path(path: String) -> String:
	return path + BAK

## Writes text to path through a .tmp file, keeping the previous file as .bak.
## Returns false (and leaves the existing file alone) if anything fails.
static func write_text(path: String, text: String) -> bool:
	var tmp := path + TMP
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SafeSave: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(text)
	f.flush()
	var write_err := f.get_error()
	f.close()
	if write_err != OK or FileAccess.get_file_as_string(tmp) != text:
		push_error("SafeSave: %s did not write whole (%s); the old save is untouched" % [tmp, error_string(write_err)])
		DirAccess.remove_absolute(_abs(tmp))
		return false
	var bak := backup_path(path)
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(_abs(bak))
		var err := DirAccess.rename_absolute(_abs(path), _abs(bak))
		if err != OK:
			push_error("SafeSave: cannot move %s to %s (%s)" % [path, bak, error_string(err)])
			return false
	var err2 := DirAccess.rename_absolute(_abs(tmp), _abs(path))
	if err2 != OK:
		push_error("SafeSave: cannot move %s into place (%s); %s still holds the last save" % [tmp, error_string(err2), bak])
		return false
	return true

## Reads path, or its .bak when path is missing or empty. "" when neither has text.
## Callers that parse the text should use read_json or load_config, which also
## fall back when the main file is there but damaged.
static func read_text(path: String) -> String:
	for p in [path, backup_path(path)]:
		if FileAccess.file_exists(p):
			var text := FileAccess.get_file_as_string(p)
			if text.strip_edges() != "":
				return text
	return ""

## The parsed JSON in path, or in its .bak when path is missing, empty or
## damaged. null when neither parses.
static func read_json(path: String) -> Variant:
	for p in [path, backup_path(path)]:
		if not FileAccess.file_exists(p):
			continue
		var json := JSON.new()  # parse() reports an error code; parse_string() prints an engine error
		if json.parse(FileAccess.get_file_as_string(p)) == OK:
			return json.data
	return null

static func write_json(path: String, data: Variant, indent := "\t") -> bool:
	return write_text(path, JSON.stringify(data, indent))

## Loads path into cfg, or its .bak when path is missing, empty or damaged.
## (ConfigFile loads an empty file as OK with no values, so empty counts as damaged.)
static func load_config(cfg: ConfigFile, path: String) -> Error:
	var err := ERR_FILE_NOT_FOUND
	if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).strip_edges() != "":
		err = cfg.load(path)
	if err == OK:
		return OK
	if FileAccess.file_exists(backup_path(path)):
		cfg.clear()
		if cfg.load(backup_path(path)) == OK:
			return OK
	return err

static func save_config(cfg: ConfigFile, path: String) -> bool:
	return write_text(path, cfg.encode_to_text())

static func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)
