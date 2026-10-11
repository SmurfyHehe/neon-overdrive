class_name GameSettings
extends RefCounted

# Settings that belong to no other screen (Settings > Game tab, 2026-10-10).
# Saved as [game] in the same settings.cfg as the rest (AudioSettings.path).
#
#   tips   hint lines on the loading and between-night screens: on by default.
#          Nothing shows them yet; the screen that will reads GameSettings.tips.
#   damage      what a crash does to the driving (brief DP7): Full, Light
#               (every handling effect halved) or Looks only (sparks, steam,
#               sounds, broken lamps and the repair bill stay; the car drives
#               as if undamaged). Changeable any time; the car reads it live.
#   difficulty  Daily Driver / Weekend Warrior / Racer (damage_difficulty.gd).
#               TODO: belongs to the save slot once slots carry one; no row
#               in the settings screen until then.

const DamageDifficulty := preload("res://scripts/car/damage_difficulty.gd")

const DEFAULT_TIPS := true
enum Damage { FULL, LIGHT, LOOKS_ONLY }
const DAMAGE_NAMES: Array[String] = ["Full", "Light", "Looks only"]
const DEFAULT_DAMAGE := Damage.FULL
const DEFAULT_DIFFICULTY := DamageDifficulty.DEFAULT

static var tips := DEFAULT_TIPS
static var damage: int = DEFAULT_DAMAGE
static var difficulty: int = DEFAULT_DIFFICULTY

static func set_tips(on: bool) -> void:
	tips = on

static func set_damage(mode: int) -> void:
	damage = clampi(mode, 0, DAMAGE_NAMES.size() - 1)

static func set_difficulty(index: int) -> void:
	difficulty = clampi(index, 0, DamageDifficulty.NAMES.size() - 1)

static func reset_defaults() -> void:
	tips = DEFAULT_TIPS
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
	cfg.set_value("game", "damage", DAMAGE_NAMES[damage])
	cfg.set_value("game", "difficulty", DamageDifficulty.NAMES[difficulty])
	return cfg.save(AudioSettings.path) == OK
