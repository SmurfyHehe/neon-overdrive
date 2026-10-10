extends RefCounted

# Crash-safe JSON files for the save system (run structure, 2026-10-09).
#
# A save is never written over the only good copy. write() goes:
#   1. the new text to <file>.tmp, flushed and closed, then read back and checked;
#   2. backups shift down: .bak2 -> .bak3, .bak1 -> .bak2, <file> -> .bak1;
#   3. <file>.tmp -> <file>.
# A crash (or the power going) at any point leaves at least one whole copy:
# before step 2 the old <file> is untouched; during step 2 the old copy is
# <file> or .bak1; between 2 and 3 the new copy is <file>.tmp. Every file
# starts with a header line holding the SHA-256 of the JSON under it, so a
# torn or hand-broken file is told apart from a good one and skipped.
#
# read() tries <file>, then <file>.tmp, then .bak1..3, and returns the first
# copy whose checksum matches and whose JSON is a Dictionary. Renames are used
# instead of overwriting because a rename is all-or-nothing on NTFS and ext4;
# the target never exists when a rename runs, so no platform needs to replace.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const HEADER := "NEONSAVE1 "
const BACKUPS := 3

## Copies read() tries, newest first.
static func candidates(path: String) -> Array[String]:
	var out: Array[String] = [path, path + ".tmp"]
	for i in range(1, BACKUPS + 1):
		out.append("%s.bak%d" % [path, i])
	return out

static func encode(data: Dictionary) -> String:
	# full_precision: a resumed car must sit where it was, not 0.1 mm off.
	var body := JSON.stringify(data, "\t", true, true)
	return HEADER + body.sha256_text() + "\n" + body

## The Dictionary in `text`, or null if the header, checksum or JSON is wrong.
static func decode(text: String) -> Variant:
	var nl := text.find("\n")
	if not text.begins_with(HEADER) or nl < 0:
		return null
	var sum := text.substr(HEADER.length(), nl - HEADER.length()).strip_edges()
	var body := text.substr(nl + 1)
	if body.sha256_text() != sum:
		return null
	var json := JSON.new()  # parse() reports an error code; parse_string() prints an engine error
	if json.parse(body) != OK or not json.data is Dictionary:
		return null
	return json.data

## Writes `data` to `path` crash-safely (see the header). Returns false, with
## every existing copy left as it was, if the new copy cannot be written whole.
static func write(path: String, data: Dictionary) -> bool:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir) and DirAccess.make_dir_recursive_absolute(dir) != OK:
		push_error("AtomicJson: cannot create %s" % dir)
		return false
	var text := encode(data)
	var tmp := path + ".tmp"
	# A crash between steps 2 and 3 last time left the newest good copy in .tmp
	# and no main file: finish that rename first, or this write would replace it.
	if not FileAccess.file_exists(path) and FileAccess.file_exists(tmp) \
			and decode(FileAccess.get_file_as_string(tmp)) != null:
		DirAccess.rename_absolute(tmp, path)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("AtomicJson: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(text)
	f.flush()
	var write_err := f.get_error()
	f.close()
	if write_err != OK or decode(FileAccess.get_file_as_string(tmp)) == null:
		push_error("AtomicJson: %s did not read back whole; keeping the old save" % tmp)
		return false
	if FileAccess.file_exists(path):
		if decode(FileAccess.get_file_as_string(path)) != null:
			# Shift the backups. The oldest is replaced, never the newest good copy.
			var last := "%s.bak%d" % [path, BACKUPS]
			if FileAccess.file_exists(last):
				DirAccess.remove_absolute(last)
			for i in range(BACKUPS - 1, 0, -1):
				var from := "%s.bak%d" % [path, i]
				if FileAccess.file_exists(from):
					DirAccess.rename_absolute(from, "%s.bak%d" % [path, i + 1])
			DirAccess.rename_absolute(path, path + ".bak1")
		else:
			# A broken main copy is not a backup: kept aside for a look, and the
			# backups stay as they are.
			DirAccess.rename_absolute(path, _free_name(path + ".bad"))
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("AtomicJson: cannot move %s into place (%s)" % [tmp, error_string(err)])
		return false  # the new copy stays in .tmp, which read() also tries
	return true

## {"data": Dictionary, "source": path it came from}, or {} if no copy is good.
## "damaged" is true when a newer copy existed but was broken.
static func read(path: String) -> Dictionary:
	var damaged := false
	for p in candidates(path):
		if not FileAccess.file_exists(p):
			continue
		var data: Variant = decode(FileAccess.get_file_as_string(p))
		if data != null:
			return {"data": data, "source": p, "damaged": damaged}
		damaged = true
	return {"damaged": damaged} if damaged else {}

## True if any copy of the file exists, good or not.
static func any_exists(path: String) -> bool:
	for p in candidates(path):
		if FileAccess.file_exists(p):
			return true
	return false

static func _free_name(base: String) -> String:
	var p := base
	var i := 2
	while FileAccess.file_exists(p):
		p = "%s-%d" % [base, i]
		i += 1
	return p
