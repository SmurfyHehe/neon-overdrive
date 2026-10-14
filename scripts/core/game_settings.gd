class_name GameSettings
extends RefCounted

# Settings that belong to no other screen (Settings > Game tab, 2026-10-10).
# Saved as [game] in the same settings.cfg as the rest (AudioSettings.path).
#
#   tips      hint lines on the loading and between-night screens: on by
#             default. Nothing shows them yet; the screen that will reads
#             GameSettings.tips.
#   critters  "Roaches and rats" (2026-10-11): the roaches, the rats and the
#             flies over the bin bags on the title, and anywhere they are
#             used later. On by default. The moths are not part of it.
#   wrecks    (test build only) "Meter" counts crashes on the totalled meter
#             (scripts/car/totalled_meter.gd); "Off" leaves the wreck sensor off,
#             as the sandbox always did. Outside the test build the sensor is
#             always on and the row is hidden.
#   damage      what a crash does to the driving (brief DP7): Full, Light
#               (every handling effect halved) or Looks only (sparks, steam,
#               sounds, broken lamps and the repair bill stay; the car drives
#               as if undamaged, and the totalled meter never moves, Roy 1437).
#               Changeable any time; the car reads it live.
#   difficulty  Daily Driver / Weekend Warrior / Racer (damage_difficulty.gd).
#               TODO: belongs to the save slot once slots carry one; no row
#               in the settings screen until then.

const TestBuild := preload("res://scripts/core/test_build.gd")
const DamageDifficulty := preload("res://scripts/car/damage_difficulty.gd")

const DEFAULT_TIPS := true
const DEFAULT_CRITTERS := true
## Meter by default in the test build, so the people testing feel it.
const DEFAULT_WRECKS_METER := true
enum Damage { FULL, LIGHT, LOOKS_ONLY }
const DAMAGE_NAMES: Array[String] = ["Full", "Light", "Looks only"]
const DEFAULT_DAMAGE := Damage.FULL
const DEFAULT_DIFFICULTY := DamageDifficulty.DEFAULT

static var tips := DEFAULT_TIPS
static var critters := DEFAULT_CRITTERS
static var wrecks_meter := DEFAULT_WRECKS_METER
static var damage: int = DEFAULT_DAMAGE
static var difficulty: int = DEFAULT_DIFFICULTY

## The test build (the sandbox with the parked start and the stand-in rows).
static func test_build() -> bool:
	return TestBuild.on()

## Whether the game's wreck sensor should be on, ignoring the benchmark and
## tests (Game.wrecks_on handles those): always outside the test build, the
## "Wrecks" row inside it.
static func wrecks_enabled() -> bool:
	return not test_build() or wrecks_meter

static func set_wrecks_meter(on: bool) -> void:
	wrecks_meter = on

static func set_tips(on: bool) -> void:
	tips = on

static func set_critters(on: bool) -> void:
	critters = on

static func set_damage(mode: int) -> void:
	damage = clampi(mode, 0, DAMAGE_NAMES.size() - 1)

static func set_difficulty(index: int) -> void:
	difficulty = clampi(index, 0, DamageDifficulty.NAMES.size() - 1)

static func reset_defaults() -> void:
	tips = DEFAULT_TIPS
	critters = DEFAULT_CRITTERS
	wrecks_meter = DEFAULT_WRECKS_METER
	damage = DEFAULT_DAMAGE
	difficulty = DEFAULT_DIFFICULTY

static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	reset_defaults()
	if not ok:
		return
	var t: Variant = cfg.get_value("game", "tips", DEFAULT_TIPS)
	set_tips(t if t is bool else str(t).to_lower() == "true")
	var c: Variant = cfg.get_value("game", "critters", DEFAULT_CRITTERS)
	set_critters(c if c is bool else str(c).to_lower() == "true")
	var w: Variant = cfg.get_value("game", "wrecks", "meter")
	set_wrecks_meter(str(w).to_lower() != "off")
	# saved by name, so a reordered list never changes what a player picked
	var d := DAMAGE_NAMES.find(str(cfg.get_value("game", "damage", DAMAGE_NAMES[DEFAULT_DAMAGE])))
	set_damage(d if d >= 0 else DEFAULT_DAMAGE)
	var k := DamageDifficulty.NAMES.find(str(cfg.get_value("game", "difficulty", DamageDifficulty.NAMES[DEFAULT_DIFFICULTY])))
	set_difficulty(k if k >= 0 else DEFAULT_DIFFICULTY)

## Rewrites only the [game] section; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("game", "tips", tips)
	cfg.set_value("game", "critters", critters)
	cfg.set_value("game", "wrecks", "meter" if wrecks_meter else "off")
	cfg.set_value("game", "damage", DAMAGE_NAMES[damage])
	cfg.set_value("game", "difficulty", DamageDifficulty.NAMES[difficulty])
	return cfg.save(AudioSettings.path) == OK
