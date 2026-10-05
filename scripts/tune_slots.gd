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
# will not parse is treated as empty and left untouched until the next save.

const DEFAULT_PATH := "user://tune_slots.json"
const MAX_NAME_LENGTH := 24

var path: String
var _slots := {}   # name -> {path: float}

func _init(file_path := DEFAULT_PATH) -> void:
	path = file_path
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
		if v.has(e.path):
			CarSpec.set_param(car, car.spec, e.path, float(v[e.path]))
	return true

func _load_file() -> void:
	_slots = {}
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()  # parse() reports an error code; parse_string() prints an engine error
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return
	var parsed: Variant = json.data
	if not parsed is Dictionary or not parsed.get("slots") is Dictionary:
		return
	for n in parsed.slots:
		if parsed.slots[n] is Dictionary:
			_slots[str(n)] = parsed.slots[n]

func _write_file() -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("TuneSlots: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify({"version": 1, "slots": _slots}, "\t"))
	return true
