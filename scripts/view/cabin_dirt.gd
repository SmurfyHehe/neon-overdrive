class_name CabinDirt
extends RefCounted

# How lived-in each car's cabin is (MA6, Y1 + Roy 1370). Looks only: nothing
# here touches grip, wear, money or the sim. All static, like CarDirt and
# CabinMods; CabinClutter reads it and draws it.
#
# Four levels, saved per car: Clean, Lived-in, Messy, Filthy. Each level adds
# to the one before:
#   Lived-in   receipts on the far side of the dash (one per fuel stop, up to 5)
#   Messy      dust on the dash and a stain on the seat
#   Filthy     smeared glass on the inside (outside the centre 20 degrees) and
#              a crumpled food bag in the footwell
# Beer cans are not a level: every beer finished on L drops its can in the
# passenger footwell (at most 6, a seventh replaces the oldest) whatever the
# level. Walt's clean empties all of it.
#
# What raises it: one level every NIGHTS_PER_LEVEL nights of driving, and one
# level sooner for every BEERS_PER_LEVEL beers. What lowers it: clean(), "Clean
# the car" on the Garage page (a free row for now; Roy can say if it should
# cost money).
#
# Saved in one cfg (AudioSettings-style, one section per car id), reloadable
# for tests with reload_from_disk().

const CLEAN := 0
const LIVED_IN := 1
const MESSY := 2
const FILTHY := 3
const NAMES := ["Clean", "Lived-in", "Messy", "Filthy"]
const NIGHTS_PER_LEVEL := 3
const BEERS_PER_LEVEL := 4
const MAX_CANS := 6
const MAX_RECEIPTS := 5

const TestMode := preload("res://scripts/core/test_mode.gd")
static var path: String = TestMode.path("user://cabin_dirt.cfg")
## Bumped on every change, so a drawn cabin knows to redraw.
static var revision := 0
static var _cars := {}   # car id -> {level, nights, beers, cans, receipts}
static var _loaded := false

static func _rec(kind: String) -> Dictionary:
	_load()
	if not _cars.has(kind):
		_cars[kind] = {"level": 0, "nights": 0, "beers": 0, "cans": 0, "receipts": 0}
	return _cars[kind]

static func level(kind: String) -> int:
	return int(_rec(kind).level)

static func level_name(kind: String) -> String:
	return NAMES[level(kind)]

static func cans(kind: String) -> int:
	return int(_rec(kind).cans)

static func receipts(kind: String) -> int:
	return int(_rec(kind).receipts)

## Nights driven since the last level change (0 .. NIGHTS_PER_LEVEL - 1).
static func nights(kind: String) -> int:
	return int(_rec(kind).nights)

## Beers since the last level change (0 .. BEERS_PER_LEVEL - 1).
static func beers(kind: String) -> int:
	return int(_rec(kind).beers)

## A night of driving ended (NightClock.night_ended).
static func night_ended(kind: String) -> void:
	var r := _rec(kind)
	r.nights = int(r.nights) + 1
	if int(r.nights) >= NIGHTS_PER_LEVEL:
		r.nights = 0
		_raise(r)
	_changed()

## A beer was finished: its can stays in the car.
static func beer_drunk(kind: String) -> void:
	var r := _rec(kind)
	r.cans = mini(int(r.cans) + 1, MAX_CANS)
	r.beers = int(r.beers) + 1
	if int(r.beers) >= BEERS_PER_LEVEL:
		r.beers = 0
		_raise(r)
	_changed()

## A fuel stop was paid for: one more receipt on the dash.
static func fuel_stop(kind: String) -> void:
	var r := _rec(kind)
	r.receipts = mini(int(r.receipts) + 1, MAX_RECEIPTS)
	_changed()

## Walt's clean: back to Clean, cans and receipts gone, counters at zero.
static func clean(kind: String) -> void:
	_load()
	_cars[kind] = {"level": 0, "nights": 0, "beers": 0, "cans": 0, "receipts": 0}
	_changed()

static func _raise(r: Dictionary) -> void:
	r.level = mini(int(r.level) + 1, FILTHY)

static func _changed() -> void:
	revision += 1
	save_state()

## Throws away what is in memory and reads the file again (tests).
static func reload_from_disk() -> void:
	_cars = {}
	_loaded = false
	_load()

## Forgets everything, in memory and on disk (tests).
static func wipe() -> void:
	_cars = {}
	_loaded = true
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for id in cfg.get_sections():
		_cars[id] = {
			"level": clampi(int(cfg.get_value(id, "level", 0)), CLEAN, FILTHY),
			"nights": clampi(int(cfg.get_value(id, "nights", 0)), 0, NIGHTS_PER_LEVEL - 1),
			"beers": clampi(int(cfg.get_value(id, "beers", 0)), 0, BEERS_PER_LEVEL - 1),
			"cans": clampi(int(cfg.get_value(id, "cans", 0)), 0, MAX_CANS),
			"receipts": clampi(int(cfg.get_value(id, "receipts", 0)), 0, MAX_RECEIPTS),
		}

static func save_state() -> bool:
	var cfg := ConfigFile.new()
	for id in _cars:
		var r: Dictionary = _cars[id]
		for k in r:
			cfg.set_value(String(id), String(k), int(r[k]))
	return cfg.save(path) == OK
