extends RefCounted

# What the garage's Service car button does (garage G0, 2026-10-11). It moved
# here from the pause menu's old stand-in (PauseMenu._service_car), which had
# moved to Settings > Game on the test build.
#
# Free and total until the bill card exists (Roy 1204, "free fix-everything
# until the bill"): powertrain wear and temperatures back to new, every body
# part and lamp fixed, nothing taken from the bank. When the totalled-meter
# bill card lands it replaces fix_everything() with a priced call
# (CarDamage.garage_repair(wallet)); nothing else needs to change.
#
# No class_name on purpose: preload it, so no class cache refresh is needed.

## Fixes the car completely. Returns false when there is no car to fix.
static func fix_everything(player: Variant) -> bool:
	if player == null:
		return false
	if player.get("health") != null:
		player.health.repair()
	if player.get("damage") != null:
		player.damage.garage_repair(null)   # null bank: free
	return true
