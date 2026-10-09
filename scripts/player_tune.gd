extends RefCounted

# The player's current tune, kept between runs (2026-10-07, Roy: a reset threw
# away the tune he had made). Restart reloads the whole scene (GameState.
# restart), so the car is rebuilt from scratch; this file is how the tune
# survives that, a quit, and a relaunch.
#
# What is kept: the value of every tunable path (TuneParams.all(), the same set
# a tune slot holds) except the exhaust ones, which ExhaustTune already saves
# in its own file. Stored as JSON {"version": 1, "values": {path: float}}.
#
# PlayerCar loads it in _ready() when it builds the default coupe, and saves it
# when the tune has changed (checked once a second while driving, since the
# Tuner pauses the game) and when it leaves the tree (restart, quit).
#
# In test mode (TestMode.active()) it does nothing unless a test turns it on,
# so the many tests that boot Game.tscn keep driving the stock coupe and never
# write a tune file. A file that will not parse is ignored and left untouched
# until the next save.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const DEFAULT_PATH := "user://player_tune.json"
const TestMode := preload("res://scripts/test_mode.gd")

static var path := DEFAULT_PATH
static var enabled := not TestMode.active()

## The paths that are kept: every tunable one except the exhaust's.
static func paths() -> Array[String]:
	var out: Array[String] = []
	for e in TuneParams.all():
		if not e.path.begins_with("exhaust/"):
			out.append(e.path)
	return out

## The spec's tune as {path: float}.
static func values_from(spec: Dictionary) -> Dictionary:
	var out := {}
	for p in paths():
		out[p] = TuneParams.get_value(spec, p)
	return out

## Writes the saved tune over `spec` (clamped to each path's range). Paths the
## file does not have keep their value; paths it has that are no longer tunable
## are ignored. Returns how many values were applied.
static func apply_saved(spec: Dictionary) -> int:
	if not enabled:
		return 0
	var saved := load_values()
	var n := 0
	for p in paths():
		if saved.has(p) and (saved[p] is float or saved[p] is int):
			var e := TuneParams.find(p)
			TuneParams.set_value(spec, p, clampf(float(saved[p]), e.min, e.max))
			n += 1
	return n

static func load_values() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()  # parse() reports an error code; parse_string() prints an engine error
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary or not parsed.get("values") is Dictionary:
		return {}
	return parsed.values

static func save(spec: Dictionary) -> bool:
	if not enabled:
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("PlayerTune: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify({"version": 1, "values": values_from(spec)}, "\t"))
	return true

## The Tuner's header for a restored tune: [preset name, modified]. The name is
## not saved, it is read back off the values: the preset whose values the tune
## is nearest (fewest paths that differ), "modified" unless it matches exactly.
## So a restored Grip tune reads "Grip", and Grip with the rear bar moved reads
## "Grip (modified)", as it did before the restart.
static func preset_of(spec: Dictionary, stock: Dictionary) -> Array:
	var now := values_from(spec)
	var best := "Stock"
	var best_diff := 1 << 30
	for name in TunerModel.PRESETS:
		var scratch := stock.duplicate(true)
		TunerModel.new(null, scratch, stock).apply_preset(name)
		var diff := 0
		for p in now:
			if absf(float(now[p]) - TuneParams.get_value(scratch, p)) > 0.0005:
				diff += 1
		if diff < best_diff:
			best = name
			best_diff = diff
	return [best, best_diff > 0]
