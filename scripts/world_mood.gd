class_name WorldMood
extends Node

# What is happening in the city tonight (living world step 3, 2026-10-08):
# events move the share of rule-breaking drivers (Roy's idea, living world doc
# section 3). NPCs are mostly law-abiding; the share rises and falls with the
# night and is never above 20% (TrafficManager.RULE_BREAKER_CAP).
#
#   Event        When                          Rule breakers   Also
#   Normal       default                        3%
#   Bar close    2:00-2:30 a.m., every night   12%, a third weave   +25% traffic (taxis), Dave warns
#   Meet night   10 p.m.-3 a.m. on meet nights  20%             Dave mentions the meet
#   Crackdown    after high heat or a story beat, for a while    0.5% (everyone behaves) at once
#
# Overlaps take the higher share (meet night through bar close stays at 20%),
# except a crackdown, which beats everything. Meet nights come from the
# weekday (Fri/Sat) in step 4; until then NEON_MEET=1 turns one on. Heat does
# not exist yet (stage F), so start_crackdown() is the hook it will call;
# NEON_CRACKDOWN=1 starts one for testing. Percentages are Roy's starting
# values, changeable.

signal event_started(event: int)

enum Event { NORMAL, BAR_CLOSE, MEET, CRACKDOWN }

const NAMES := ["Normal", "Bar close", "Meet night", "Crackdown"]
const SHARE := [0.03, 0.12, 0.20, 0.005]
const CAP := 0.2
## Game minutes since 8 p.m.
const BAR_CLOSE_START := 360.0   # 2:00 a.m.
const BAR_CLOSE_END := 390.0     # 2:30 a.m.
const MEET_START := 120.0        # 10 p.m.
const MEET_END := 420.0          # 3 a.m. (runs through bar close)
## Share of bar-close rule breakers that weave in their lane.
const BAR_CLOSE_WEAVE := 0.35
## Extra share of the Traffic slider on the road at bar close (the taxi burst):
## eases in over 5 game minutes, holds, eases out from 2:25 to 2:40.
const BAR_CLOSE_TRAFFIC := 0.25
const CRACKDOWN_MINUTES := 60.0

const EVENT_LINES := {
	Event.MEET: "Dave: Word is there's a meet tonight, driver. Expect company, and not the polite kind.",
	Event.CRACKDOWN: "Dave: Cops everywhere tonight. Everybody's driving like their mother's in the back seat.",
}
## Bar close starts on the hour, so it takes over Dave's 2 a.m. time check.
const BAR_CLOSE_LINE := "Dave: Two o'clock. Bars are out. Taxis everywhere, and some of them shouldn't be driving. Watch the left lane."

## Tonight is a meet night (step 4 sets it from the weekday).
var meet_night := false
## Game minute the crackdown ends at; < 0 = none.
var crackdown_until := -1.0
var event := Event.NORMAL

func _ready() -> void:
	name = "WorldMood"
	if OS.get_environment("NEON_MEET") == "1":
		meet_night = true

## Police crackdown from game minute `now` for `minutes` game minutes.
func start_crackdown(now: float, minutes := CRACKDOWN_MINUTES) -> void:
	crackdown_until = now + minutes

## Called every frame with the clock (game.gd); fires event_started on a change.
func update(minutes: float) -> int:
	if crackdown_until >= 0.0 and minutes >= crackdown_until:
		crackdown_until = -1.0
	var e := event_at(minutes, meet_night, crackdown_until >= 0.0)
	if e != event:
		event = e
		event_started.emit(e)
	return e

# ---------- pure helpers (tests use these) ----------

static func event_at(minutes: float, meet: bool, crackdown: bool) -> int:
	if crackdown:
		return Event.CRACKDOWN
	if meet and minutes >= MEET_START and minutes < MEET_END:
		return Event.MEET
	if minutes >= BAR_CLOSE_START and minutes < BAR_CLOSE_END:
		return Event.BAR_CLOSE
	return Event.NORMAL

## Rule-breaker share at that time: the event's, the higher one where bar close
## and a meet overlap, capped at CAP.
static func rule_breaker_share(minutes: float, meet: bool, crackdown: bool) -> float:
	var e := event_at(minutes, meet, crackdown)
	var s: float = SHARE[e]
	if e == Event.MEET and minutes >= BAR_CLOSE_START and minutes < BAR_CLOSE_END:
		s = maxf(s, SHARE[Event.BAR_CLOSE])
	return minf(s, CAP)

## Share of rule breakers that weave: only at bar close (drunk drivers),
## also on a meet night.
static func weave_share(minutes: float, crackdown: bool) -> float:
	if crackdown or minutes < BAR_CLOSE_START or minutes >= BAR_CLOSE_END:
		return 0.0
	return BAR_CLOSE_WEAVE

## Extra traffic share on top of the hour band (bar-close taxis). A crackdown
## does not stop people going home, so it ignores the crackdown.
static func traffic_bonus(minutes: float) -> float:
	if minutes < BAR_CLOSE_START or minutes >= BAR_CLOSE_END + 10.0:
		return 0.0
	if minutes < BAR_CLOSE_START + 5.0:
		return BAR_CLOSE_TRAFFIC * (minutes - BAR_CLOSE_START) / 5.0
	if minutes < BAR_CLOSE_END - 5.0:
		return BAR_CLOSE_TRAFFIC
	return BAR_CLOSE_TRAFFIC * (1.0 - (minutes - (BAR_CLOSE_END - 5.0)) / 15.0)

static func event_name(e: int) -> String:
	return NAMES[clampi(e, 0, NAMES.size() - 1)]
