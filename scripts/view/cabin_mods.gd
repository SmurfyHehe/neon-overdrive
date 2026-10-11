class_name CabinMods
extends Node

# Interior mods, batch 1 (2026-10-09): which parts are fitted and what they
# do to the car. The pause menu's View page sets them for now; the garage and
# the mod tree (stage E) will own them later, so each is stored by id in its
# own [interior] section of the shared settings.cfg (AudioSettings.path, so a
# test that redirects one file redirects all).
#
# Parts and their effects (Roy's answers, research section 6):
#   trinket        a charm hanging from the rear-view mirror; swings (DashTrinket)
#   shift_knob     the knob on the gear lever: looks only
#   short_shifter  a short-throw lever: a shorter stick and quicker shifts
#                  (shift_time x SHORT_SHIFT_TIME)
#   strut_bar      a brace between the front strut towers: looks, plus a
#                  stiffer front end (front anti-roll ratio + STRUT_BAR_ARB)
#   bobble         the passenger-side dash bobble head, one per car
#                  (BobbleHead, figures in BobbleFigures); default none.
#                  Saved as bobble_<car kind> = figure id.
#
# The sim effects go on the live Vehicle, never on the spec, so the Tuner
# shows and the saved tune (PlayerTune) keeps the stock values. The raw tuner
# writes every tunable path from the spec back to the car when it opens (and
# at boot), so a one-shot write would not last: attach() puts one of these on
# the player car and each physics tick it holds the live values at
# spec + mods (two float compares; a change re-runs the suspension). A change
# in the pause menu bumps `version`; the cockpit's parts poll it and rebuild.
#
# NEON_CABIN_MODS="trinket=dice;knob=ball;short=1;strut=1" overrides the file
# (tests and the screenshot tool).

const SECTION := "interior"
const BOBBLE_PREFIX := "bobble_"

const KNOB_STOCK := "stock"
## Pick order in the pause menu.
const KNOB_IDS: Array[String] = [KNOB_STOCK, "ball", "weighted", "amber"]
const KNOB_NAMES := {
	KNOB_STOCK: "Stock", "ball": "Alloy ball", "weighted": "Weighted", "amber": "Amber ball",
}

## Short shifter: quicker shifts.
const SHORT_SHIFT_TIME := 0.75
## Short shifter: the stick's length against the stock lever.
const SHORT_LEVER_SCALE := 0.72
## Strut bar: added to the front anti-roll ratio (stock coupe 0.30).
const STRUT_BAR_ARB := 0.05

static var trinket := DashTrinket.DEFAULT_ID
static var shift_knob := KNOB_STOCK
static var short_shifter := false
static var strut_bar := false
## Car kind -> BobbleFigures id (a car missing here has none).
static var bobbles := {}
## Bumped on every change; the cockpit parts poll it.
static var version := 0

static func set_trinket(id: String) -> void:
	trinket = id if DashTrinket.IDS.has(id) else DashTrinket.DEFAULT_ID
	version += 1

static func set_shift_knob(id: String) -> void:
	shift_knob = id if KNOB_IDS.has(id) else KNOB_STOCK
	version += 1

static func set_short_shifter(on: bool) -> void:
	short_shifter = on
	version += 1

static func set_strut_bar(on: bool) -> void:
	strut_bar = on
	version += 1

static func bobble_for(kind: String) -> String:
	return str(bobbles.get(kind, BobbleFigures.NONE))

static func set_bobble(kind: String, id: String) -> void:
	if not BobbleFigures.IDS.has(id) or id == BobbleFigures.NONE:
		bobbles.erase(kind)
	else:
		bobbles[kind] = id
	version += 1

static func knob_index() -> int:
	return maxi(KNOB_IDS.find(shift_knob), 0)

## Reads the file (missing or damaged means the defaults), then the
## NEON_CABIN_MODS override.
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	set_trinket(str(cfg.get_value(SECTION, "trinket", DashTrinket.DEFAULT_ID)) if ok else DashTrinket.DEFAULT_ID)
	set_shift_knob(str(cfg.get_value(SECTION, "shift_knob", KNOB_STOCK)) if ok else KNOB_STOCK)
	set_short_shifter(bool(cfg.get_value(SECTION, "short_shifter", false)) if ok else false)
	set_strut_bar(bool(cfg.get_value(SECTION, "strut_bar", false)) if ok else false)
	bobbles.clear()
	if ok and cfg.has_section(SECTION):
		for key in cfg.get_section_keys(SECTION):
			if key.begins_with(BOBBLE_PREFIX):
				set_bobble(key.substr(BOBBLE_PREFIX.length()), str(cfg.get_value(SECTION, key, "")))
	apply_override(OS.get_environment("NEON_CABIN_MODS"))

## "trinket=dice;knob=ball;short=1;strut=1;bobble=pike" (any subset, any
## order). bobble sets the figure for the car being driven (PlayerCar.chassis_kind).
static func apply_override(text: String) -> void:
	for item in text.split(";", false):
		var kv := item.split("=", false)
		if kv.size() != 2:
			continue
		var key := kv[0].strip_edges()
		var val := kv[1].strip_edges()
		match key:
			"trinket":
				set_trinket(val)
			"knob":
				set_shift_knob(val)
			"short":
				set_short_shifter(val == "1" or val == "true")
			"strut":
				set_strut_bar(val == "1" or val == "true")
			"bobble":
				set_bobble(PlayerCar.chassis_kind(), val)

## Rewrites only the [interior] section; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value(SECTION, "trinket", trinket)
	cfg.set_value(SECTION, "shift_knob", shift_knob)
	cfg.set_value(SECTION, "short_shifter", short_shifter)
	cfg.set_value(SECTION, "strut_bar", strut_bar)
	for key in cfg.get_section_keys(SECTION):
		if key.begins_with(BOBBLE_PREFIX):
			cfg.erase_section_key(SECTION, key)
	for kind in bobbles:
		cfg.set_value(SECTION, BOBBLE_PREFIX + str(kind), bobbles[kind])
	return cfg.save(AudioSettings.path) == OK

## Keeps the fitted parts' effects on a player car: a child node that holds
## the live values at spec + mods every physics tick.
static func attach(player: Vehicle) -> CabinMods:
	var n := CabinMods.new()
	n.name = "CabinMods"
	n.car = player
	player.add_child(n)
	return n

var car: Vehicle

func _physics_process(_delta: float) -> void:
	if car == null:
		return
	var s: Variant = car.get("spec")
	apply_sim(car, s if s is Dictionary else {})

## The fitted parts' effects on a car, from the spec's own values: quicker
## shifts and a stiffer front end. Idempotent: the spec is the base, so a call
## every tick, or after a Tuner write, lands on the same numbers.
static func apply_sim(v: Vehicle, spec: Dictionary) -> void:
	var shift := float(spec.get("shift_time", v.shift_time)) * (SHORT_SHIFT_TIME if short_shifter else 1.0)
	if not is_equal_approx(v.shift_time, shift):
		v.shift_time = shift
	var arb := float(spec.get("front_arb_ratio", v.front_arb_ratio)) + (STRUT_BAR_ARB if strut_bar else 0.0)
	if not is_equal_approx(v.front_arb_ratio, arb):
		v.front_arb_ratio = arb
		if v.is_ready:
			v.apply_suspension()
