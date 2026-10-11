extends RefCounted

# The season calendar (freemode F1): for any night number, its weekday, whether
# it is a story night or a free-mode night, which 28-night season it belongs
# to, which night of that season it is, whether it is the holiday, and which
# night is the season's Cup night. Pure arithmetic on the night number: no
# node, no state, no save access, no per-tick work.
#
#   story        nights 1-30; night 1 is a Monday, night 27 (the holiday,
#                fireworks) a Saturday, night 30 a Tuesday.
#   free mode    night 31 on. Seasons are 28 nights, winter first so the snow
#                of the last story nights carries on: winter 31-58, spring
#                59-86, summer 87-114, autumn 115-142, then winter again from
#                143 (a year is 112 nights).
#   holiday      every 28th night, as in the story: 27, then 55, 83, 111, ...
#   Cup night    each season ends with a Season Cup on its last Saturday. 28
#                nights are four whole weeks, so that is the holiday night
#                (Roy 1280: the Cup is the season's fireworks night).
#   thaw         spring opens with a thaw week (its first 7 nights).
#
# is_free() is the calendar only; whether the save has unlocked free mode is
# the save's flag. Read by weather_plan.gd. No class_name: preload it.

const STORY_NIGHTS := 30
const FIRST_FREE := 31
const SEASON_LEN := 28
const THAW_NIGHTS := 7
const STORY_HOLIDAY := 27
## Same order as weather_plan.gd's SEASON_NAMES.
const SEASON_NAMES := ["winter", "spring", "summer", "autumn"]
const WEEKDAY_NAMES := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const SATURDAY := 5

## 0 Monday ... 6 Sunday. Night 1 is a Monday.
static func weekday(n: int) -> int:
	return posmod(maxi(n, 1) - 1, 7)

static func weekday_name(n: int) -> String:
	return WEEKDAY_NAMES[weekday(n)]

static func is_free(n: int) -> bool:
	return n > STORY_NIGHTS

## 1 for nights 31-58, 2 for 59-86, ...; 0 for story nights.
static func season_number(n: int) -> int:
	if n < FIRST_FREE:
		return 0
	return (n - FIRST_FREE) / SEASON_LEN + 1

## 0 winter, 1 spring, 2 summer, 3 autumn; -1 for story nights.
static func season_index(n: int) -> int:
	var k := season_number(n)
	return -1 if k == 0 else (k - 1) % 4

static func season_name(n: int) -> String:
	var i := season_index(n)
	return "" if i < 0 else SEASON_NAMES[i]

## 1-28; 0 for story nights.
static func night_in_season(n: int) -> int:
	if n < FIRST_FREE:
		return 0
	return (n - FIRST_FREE) % SEASON_LEN + 1

static func season_first(k: int) -> int:
	return FIRST_FREE + (k - 1) * SEASON_LEN

static func season_last(k: int) -> int:
	return FIRST_FREE + k * SEASON_LEN - 1

static func is_holiday(n: int) -> bool:
	if n == STORY_HOLIDAY:
		return true
	return n > STORY_NIGHTS and (n - STORY_HOLIDAY) % SEASON_LEN == 0

## The last Saturday of season k (k >= 1).
static func cup_night(k: int) -> int:
	var n := season_last(k)
	while weekday(n) != SATURDAY:
		n -= 1
	return n

static func is_thaw(n: int) -> bool:
	return season_index(n) == 1 and night_in_season(n) <= THAW_NIGHTS

static func is_winter(n: int) -> bool:
	return season_index(n) == 0
