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
# The lowrider's hydraulics are on the NUMPAD only (Roy, 2026-10-11): a
# different physical key from the digit row above the letters, so they work
# with Num Lock on or off (keys are bound by position, see KeyBindings).
#   KP8 front   KP2 back   KP4 left   KP6 right     pump that end up (hold)
#   KP0 (hold)  + one of those: drop that side
#   KP0 (tap)   on its own: drop all four
#   KP5         three-wheel pose (tap on / tap off)
# K and L belong to the driver in every car (flip off, idle action: project.godot).
# In every other vehicle these keys do nothing: owner_kind() says which
# vehicle an action belongs to, "" for the shared one.

const KEYS := {
	"special": KEY_CTRL,
	"hyd_pump_front": KEY_KP_8, "hyd_pump_back": KEY_KP_2,
	"hyd_pump_left": KEY_KP_4, "hyd_pump_right": KEY_KP_6,
	"hyd_drop": KEY_KP_0, "hyd_three": KEY_KP_5,
}

const LOWRIDER := "l1_lowrider"

## The plain-words labels the Controls page shows, in order.
const LABELS := [
	["special", "Special move (truck: crab steer, hold / lowrider: dance, tap)"],
	["hyd_pump_front", "Lowrider: pump front up (hold)"], ["hyd_pump_back", "Lowrider: pump back up (hold)"],
	["hyd_pump_left", "Lowrider: pump left up (hold)"], ["hyd_pump_right", "Lowrider: pump right up (hold)"],
	["hyd_drop", "Lowrider: drop (hold + a pump key: that side, tap: all four)"],
	["hyd_three", "Lowrider: three-wheel pose (tap on / off)"],
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
