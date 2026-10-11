extends RefCounted

# What the game says it is doing, for a Discord rich-presence hook (garage G0,
# 2026-10-11). The Discord SDK is not in the project, so this is only the hook:
# a late integration sets `sink` to a Callable taking the activity string and
# gets called on every change. Today GarageFlow sets "Garage" on the dawn card
# and in the garage, and "Driving" when the player goes out.
#
# No class_name on purpose: preload it, so no class cache refresh is needed.

const GARAGE := "Garage"
const DRIVING := "Driving"

static var activity := ""
## Called with the new activity string when it changes. Unset = nobody listens.
static var sink := Callable()

static func set_activity(value: String) -> void:
	if value == activity:
		return
	activity = value
	if sink.is_valid():
		sink.call(value)
