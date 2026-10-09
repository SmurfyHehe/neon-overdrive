class_name TuneSlots
extends RefCounted

# Auto-Tune step 7: named tune slots. A slot is a name and the value of every
# tunable path (TuneParams.all(): the Auto-Tune ones and the raw-only engine
# ones), so loading one gives back the whole tune, not just what Auto-Tune
# touches. Stored as JSON in one file; slots are plain {path: float}, the same
# form AutoTuneJob sends to its worker.
#
#   var slots := TuneSlots.new()
#   slots.save("Street", player.spec)
#   slots.apply("Street", player)      # through CarSpec.set_param()
#
# Deleting a slot only removes its entry; the file is never deleted. A file that
# will not parse is treated as empty and left untouched; the next save copies it
# to tune_slots.bad.json first, so a hand-edit typo never wipes every slot.
# Values that are not finite numbers (JSON writes NaN as null) are dropped on
# load, so a slot applies whole or keeps the current value for that path
# (settings safety, 2026-10-07).

const DEFAULT_PATH := "user://tune_slots.json"
const TestMode := preload("res://scripts/test_mode.gd")
const MAX_NAME_LENGTH := 24

var path: String
var _slots := {}   # name -> {path: float}
var _unreadable := false  # the file exists but did not load: back it up before writing

func _init(file_path := "") -> void:
	path = file_path if file_path != "" else TestMode.path(DEFAULT_PATH)
	_load_file()

## A name as it is stored: trimmed, at most MAX_NAME_LENGTH characters. Empty
## means the name is not usable.
static func clean_name(raw: String) -> String:
	return raw.strip_edges().left(MAX_NAME_LENGTH)

## Slot names, sorted.
func names() -> Array[String]:
	var out: Array[String] = []
	for n in _slots:
		out.append(n)
	out.sort()
	return out

func has(slot_name: String) -> bool:
	return _slots.has(clean_name(slot_name))

## Stores the spec's tune under the name, replacing a slot of that name. Returns
## false (nothing stored) for an unusable name or a file that cannot be written.
func save(slot_name: String, spec: Dictionary) -> bool:
	var n := clean_name(slot_name)
	if n == "":
		return false
	_slots[n] = AutoTuneJob.values_from_spec(spec)
	return _write_file()

## The slot's {path: float}, or {} if there is none.
func values(slot_name: String) -> Dictionary:
	return _slots.get(clean_name(slot_name), {}).duplicate()

func delete(slot_name: String) -> bool:
	var n := clean_name(slot_name)
	if not _slots.has(n):
		return false
	_slots.erase(n)
	return _write_file()

## Loads the slot into the car through the single write path. Paths the slot does
## not have (saved by an older build) keep their current value; paths it has that
## are no longer tunable are ignored; values are clamped by set_param(). Returns
## false if there is no such slot.
func apply(slot_name: String, car: PlayerCar) -> bool:
	var v := values(slot_name)
	if v.is_empty():
		return false
	for e in TuneParams.all():
		if v.has(e.path) and _is_number(v[e.path]):
			CarSpec.set_param(car, car.spec, e.path, float(v[e.path]))
	return true

## Where an unreadable slot file is copied before the next save: .bad.json, or
## .bad-2.json and up so an older backup is never overwritten.
func bad_path() -> String:
	var p := path.get_basename() + ".bad.json"
	var i := 2
	while FileAccess.file_exists(p):
		p = path.get_basename() + ".bad-%d.json" % i
		i += 1
	return p

static func _is_number(x: Variant) -> bool:
	return (x is float or x is int) and is_finite(float(x))

func _load_file() -> void:
	_slots = {}
	_unreadable = false
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges() == "":
		return  # nothing in it to lose
	_unreadable = true
	var json := JSON.new()  # parse() reports an error code; parse_string() prints an engine error
	if json.parse(text) != OK:
		return
	var parsed: Variant = json.data
	if not parsed is Dictionary or not parsed.get("slots") is Dictionary:
		return
	_unreadable = false
	for n in parsed.slots:
		var slot: Variant = parsed.slots[n]
		if not slot is Dictionary:
			continue
		var clean := {}
		for p in slot:
			if _is_number(slot[p]):
				clean[str(p)] = float(slot[p])
		_slots[str(n)] = clean

func _write_file() -> bool:
	if _unreadable:
		var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(bad_path()))
		if err != OK:
			push_error("TuneSlots: %s did not load and cannot be backed up (%s); not overwriting it" % [path, error_string(err)])
			return false
		_unreadable = false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("TuneSlots: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify({"version": 1, "slots": _slots}, "\t"))
	return true
