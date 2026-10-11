class_name IdleActions
extends RefCounted

# What the driver does on the idle action key (L, 2026-10-11): one puff of a
# vape or one sip of a beer, or nothing. Looks only: no stat, handling, police
# or money effect anywhere. Settings > Game > Driver sets it for now; the
# garage's "You" tab will own it later, so it has its own [driver] section of
# the shared settings.cfg (AudioSettings.path, like CabinMods).
#
#   item               "vape" (default) | "beer" | "cigarette" (a light, three
#                      drags, a flick out of the open window) | "none" (the
#                      key does nothing)
#   beer_while_moving  on (default): a sip any time. Off: only when parked
#                      (engine off, or under PARKED_KMH)
#
# NEON_IDLE="item=beer;moving=0" overrides the file (tests and the screenshot tool).

const SECTION := "driver"

const VAPE := "vape"
const BEER := "beer"
const CIGARETTE := "cigarette"
const NONE := "none"
## Pick order in the settings row.
const IDS: Array[String] = [VAPE, BEER, CIGARETTE, NONE]
const NAMES := {VAPE: "Vape", BEER: "Beer", CIGARETTE: "Cigarette", NONE: "None"}
const DEFAULT_ITEM := VAPE
## Under this speed the car counts as parked for the beer.
const PARKED_KMH := 5.0

static var item := DEFAULT_ITEM
static var beer_while_moving := true

static func set_item(id: String) -> void:
	item = id if IDS.has(id) else DEFAULT_ITEM

static func set_beer_while_moving(on: bool) -> void:
	beer_while_moving = on

static func item_index() -> int:
	return maxi(IDS.find(item), 0)

## Whether the key does anything right now, for a car at `speed` m/s.
static func allowed(speed: float, engine_running: bool) -> bool:
	if item == NONE:
		return false
	if item == BEER and not beer_while_moving:
		return not engine_running or absf(speed) * 3.6 < PARKED_KMH
	return true

## Reads the file (missing or damaged means the defaults), then the NEON_IDLE override.
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	set_item(str(cfg.get_value(SECTION, "item", DEFAULT_ITEM)) if ok else DEFAULT_ITEM)
	set_beer_while_moving(bool(cfg.get_value(SECTION, "beer_while_moving", true)) if ok else true)
	apply_override(OS.get_environment("NEON_IDLE"))

## "item=beer;moving=0" (any subset, any order).
static func apply_override(text: String) -> void:
	for part in text.split(";", false):
		var kv := part.split("=", false)
		if kv.size() != 2:
			continue
		var val := kv[1].strip_edges()
		match kv[0].strip_edges():
			"item":
				set_item(val)
			"moving":
				set_beer_while_moving(val == "1" or val == "true")

## Rewrites only the [driver] section; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value(SECTION, "item", item)
	cfg.set_value(SECTION, "beer_while_moving", beer_while_moving)
	return cfg.save(AudioSettings.path) == OK
