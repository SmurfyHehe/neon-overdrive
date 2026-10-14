extends RefCounted

# Damage by difficulty (brief DP7, 2026-10-11): one table, read by CarDamage.
# No class_name: preload it.
#
#   damage_mult      damage per hit (wall hits and kerb strikes)
#   auto_trim        share of a steering pull the car trims out by itself
#   effects_at_once  how many handling effects can act at the same time
#   heat_window_s    the radiator heat window: seconds of full-throttle
#                    driving on a 100 % radiator before the engine reaches
#                    PowertrainHealth.LIMP_C. It is how fast the coolant
#                    drains (CarDamage.step_coolant); measured by
#                    tests/car/damage_settings.gd
#
# TODO: the difficulty belongs to the save slot. No slot carries one on this
# branch, so it is a game setting (GameSettings.difficulty) until it does.

const DAILY_DRIVER := 0
const WEEKEND_WARRIOR := 1
const RACER := 2
const DEFAULT := WEEKEND_WARRIOR
const NAMES: Array[String] = ["Daily Driver", "Weekend Warrior", "Racer"]

const TABLE := {
	"Daily Driver": {"damage_mult": 0.6, "auto_trim": 0.85, "effects_at_once": 2, "heat_window_s": 120.0},
	"Weekend Warrior": {"damage_mult": 1.0, "auto_trim": 0.70, "effects_at_once": 3, "heat_window_s": 75.0},
	"Racer": {"damage_mult": 1.3, "auto_trim": 0.40, "effects_at_once": 3, "heat_window_s": 50.0},
}

## The row for a difficulty index; anything out of range reads as the default.
static func row(index: int) -> Dictionary:
	return TABLE[NAMES[index if index >= 0 and index < NAMES.size() else DEFAULT]]
