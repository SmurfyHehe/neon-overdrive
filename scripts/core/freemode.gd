extends RefCounted

# Free mode, step F0 (2026-10-11): the endless mode after the story. One flag in
# the career (career.json "freemode" block) turns the story off and keeps every
# other system running. The same slot goes on after the credits: no new file, no
# locked copy. A new story is a new slot.
#
# This script is the one place every later system asks "is the story on?":
#   Freemode.is_active()        cached after load (refresh) and after a commit
#   Freemode.stops("pike_debt") true in free mode for the ids in STOPS
#   Freemode.road_act()         the act the road is built for (the whole city)
#
# Save block (career.json "freemode"): {"unlocked": bool, "entered_night": int}.
# F2-F4 add their own fields (season, standings, cup_history, regulars, legend);
# nothing here writes them. A missing field reads as its default, an unknown
# field is kept (SaveCore.fill_career only adds what is missing).
# meta.json plate: "mode" "story"|"free", "freemode_season" (null in the story).
#
# Seasons are 28 nights, winter first, from night 31: nights 31-58 winter, then
# spring, summer, autumn, repeating. Local rule until the F1 calendar lands
# (switch season_name() to season_calendar.gd then).
#
# Free mode adds no key and no screen. No class_name: preload it.

const RoadMap := preload("res://scripts/world/road_map.gd")
const TestMode := preload("res://scripts/core/test_mode.gd")

const FIRST_NIGHT := 31          # the night after the story's last
const SEASON_NIGHTS := 28
const SEASONS := ["Winter", "Spring", "Summer", "Autumn"]
const LAST_STORY_NIGHT := 30

## What free mode stops (the story's own machinery).
const STOPS := ["pike_debt", "deadlines", "story_beats", "act_unlocks", "boss_races", "failed_act_replay"]
## What keeps running, unchanged.
const KEEPS := ["cars", "mods", "tunes", "cash", "bank", "rep", "calendar", "weather", "police", "fuel",
	"repairs", "franchise", "work_board", "achievements", "difficulty", "wrecks"]

## Callables(night: int) run once when free mode is entered. The achievements
## core appends AC51 "After Hours" here; no achievement code lives in this step.
static var on_entered: Array[Callable] = []

static var _free := false


# ---------- reading ----------

## True when the career's freemode block says unlocked (default false).
static func active(career: Dictionary) -> bool:
	var b: Variant = career.get("freemode")
	return b is Dictionary and b.get("unlocked") is bool and b.unlocked

## The cached answer for runtime reads. Set by refresh() on load and after a commit.
static func is_active() -> bool:
	return _free

## Re-reads the flag from a career (the game calls it at boot). NEON_FREEMODE=1
## makes a test game free from the start (test mode only).
static func refresh(career: Dictionary) -> bool:
	_free = active(career) or _test_override()
	return _free

static func stops(id: String) -> bool:
	return _free and id in STOPS

## The act the road is built for: the whole city (the top act) in free mode,
## -1 ("let the story decide") otherwise.
static func road_act() -> int:
	return RoadMap.MAX_ACT if _free else -1

static func season_index(night: int) -> int:
	return maxi(night - FIRST_NIGHT, 0) / SEASON_NIGHTS

## "Winter", "Spring", ... for a free-mode night; "" before night 31.
static func season_name(night: int) -> String:
	if night < FIRST_NIGHT:
		return ""
	return SEASONS[season_index(night) % SEASONS.size()]

## "Free mode · Winter · night 47"
static func plate_line(night: int) -> String:
	return "Free mode · %s · night %d" % [season_name(maxi(night, FIRST_NIGHT)), maxi(night, FIRST_NIGHT)]


# ---------- writing ----------

## Sets the flag in a working career (SaveCore commits it). Entering twice
## changes nothing. Returns true when this call is the one that entered.
static func apply(career: Dictionary, night: int) -> bool:
	if active(career):
		return false
	var b: Variant = career.get("freemode")
	var block: Dictionary = b if b is Dictionary else {}
	block.unlocked = true
	block.entered_night = night
	career.freemode = block
	return true

## Runs the on_entered hooks. Called after the career holding the flag is written.
static func fire_entered(night: int) -> void:
	_free = true
	for cb in on_entered:
		if cb.is_valid():
			cb.call(night)

## apply() + fire_entered(): for a caller that commits the career itself.
static func enter(career: Dictionary, night: int) -> Dictionary:
	if apply(career, night):
		fire_entered(night)
	return career

## Stand-in: the credits screen calls enter() once the finale exists
## (run-structure R7). Until then the dawn that ends night 30 is the unlock.
## Called inside SaveCore.commit's dawn, on the working career, before it is
## written; returns the night entered (0 = not entered now).
static func dawn_stand_in(career: Dictionary, closed_night: int) -> int:
	if closed_night >= LAST_STORY_NIGHT and apply(career, closed_night + 1):
		return closed_night + 1
	return 0

## Test mode, NEON_FREEMODE=1: a fresh career starts in free mode.
static func _test_override() -> bool:
	return TestMode.active() and OS.get_environment("NEON_FREEMODE") == "1"

## Fills the freemode block's defaults in a working career.
static func fill(career: Dictionary, current_night: int) -> void:
	if not career.get("freemode") is Dictionary:
		career.freemode = {}
	var b: Dictionary = career.freemode
	if not b.has("unlocked"):
		b.unlocked = false
	if not b.has("entered_night"):
		b.entered_night = 0
	if _test_override() and b.unlocked != true:
		b.unlocked = true
		b.entered_night = maxi(current_night, FIRST_NIGHT)
