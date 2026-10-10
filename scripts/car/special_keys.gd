class_name SpecialKeys
extends RefCounted

# Input actions of the special vehicles (S0, Roy 2026-10-10). Registered into
# the InputMap in code, like PhotoMode, so they list on the Controls page
# ("Special vehicles") and rebind like any other action.
#
# `special` is the one shared special-move key (Ctrl): nothing in ordinary
# cars; crab steer (hold) in the monster truck, the dance (tap) in the
# lowrider; the motorcycle wheelie and the bone car's afterburner will share it.
#
# The lowrider's hydraulics are four toggle switches, one per corner or end.
# Each column is one switch: the number key is up, the letter under it is down.
#   pump (up):  7 left   8 front   9 back   0 right
#   dump (down) U left   I front   O back   P right
# plus L (three-wheel pose, tap on / tap off) and K (drop all four, pancake).
# In every other vehicle these keys do nothing: owner_kind() says which
# vehicle an action belongs to, "" for the shared one.

const KEYS := {
	"special": KEY_CTRL,
	"hyd_pump_left": KEY_7, "hyd_pump_front": KEY_8, "hyd_pump_back": KEY_9, "hyd_pump_right": KEY_0,
	"hyd_dump_left": KEY_U, "hyd_dump_front": KEY_I, "hyd_dump_back": KEY_O, "hyd_dump_right": KEY_P,
	"hyd_three": KEY_L, "hyd_dump_all": KEY_K,
}

const LOWRIDER := "l1_lowrider"

## The plain-words labels the Controls page shows, in order.
const LABELS := [
	["special", "Special move (truck: crab steer, hold / lowrider: dance, tap)"],
	["hyd_pump_left", "Lowrider: pump left up (hold)"], ["hyd_pump_front", "Lowrider: pump front up (hold)"],
	["hyd_pump_back", "Lowrider: pump back up (hold)"], ["hyd_pump_right", "Lowrider: pump right up (hold)"],
	["hyd_dump_left", "Lowrider: dump left down (hold)"], ["hyd_dump_front", "Lowrider: dump front down (hold)"],
	["hyd_dump_back", "Lowrider: dump back down (hold)"], ["hyd_dump_right", "Lowrider: dump right down (hold)"],
	["hyd_three", "Lowrider: three-wheel pose (tap on / off)"], ["hyd_dump_all", "Lowrider: drop all four"],
]

static func ensure_actions() -> void:
	for action in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.keycode = KEYS[action]
		InputMap.action_add_event(action, ev)

## The vehicle an action works in: the lowrider for the hydraulics, "" (any
## special vehicle) for `special`.
static func owner_kind(action: String) -> String:
	return LOWRIDER if action.begins_with("hyd_") else ""

## True when `action` does something in `kind`. Nothing in a normal car.
static func applies(action: String, kind: String) -> bool:
	if not KEYS.has(action) or not PlayerCars.is_special(kind):
		return false
	var owner := owner_kind(action)
	return owner == "" or owner == kind
