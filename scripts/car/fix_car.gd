extends RefCounted

# Fix the car: every broken part and lamp back to new, and the engine, brakes,
# tyres and clutch back to new (PowertrainHealth.repair). Free and total. Fuel
# is not touched. The pause menu's test button and the F6 key both call this,
# and the garage's service will call it later.
# No class_name: callers preload this file.

## On in every build for now (the test-build gate is not on this base). Set to
## false at release to hide the pause row and the F6 key.
const FIX_CAR_ENABLED := true

## The sudden spring change after a fix is not read as a hit (see
## off_map_rescue.gd, which does the same after it moves the car).
static func fix(player: Object) -> void:
	if player == null:
		return
	var health = player.get("health")
	if health != null:
		health.repair()
	var damage = player.get("damage")
	if damage != null:
		damage.garage_repair(null)
		damage.forget_motion()
