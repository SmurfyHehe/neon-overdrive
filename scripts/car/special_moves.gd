class_name SpecialMoves
extends Node

# The Ctrl special move of a special vehicle (S1, Roy 2026-10-10). One node per
# special car, a child of the PlayerCar. Today: the monster truck's crab steer.
# The lowrider's dance and hydraulics, the motorcycle's wheelie and the bone
# car's afterburner will hang off this same node.
#
# Crab steer: while the `special` action is held the rear wheels turn the same
# way as the front (GEVP's rear_steering_ratio, set per wheel here so the
# vendored files stay as they are), so the truck slides sideways instead of
# turning about its middle. The ratio eases in and out so the rear does not
# snap.

const CRAB_RATIO := 1.0     # rear steers with the front, same size
const CRAB_RATE := 4.0      # 1/s, how fast the rear ratio follows (about 0.25 s)

var car: Vehicle
var kind := ""
## Set by tests to press the move without an input event; Input is read otherwise.
var forced: Variant = null
var crab := 0.0             # 0..1, how far crab steer has eased in

func _init(vehicle: Vehicle = null, car_kind: String = "") -> void:
	car = vehicle
	kind = car_kind
	name = "SpecialMoves"

func held() -> bool:
	if forced != null:
		return bool(forced)
	return InputMap.has_action("special") and Input.is_action_pressed("special")

func _physics_process(delta: float) -> void:
	if car == null or kind != "m1_monster":
		return
	crab = move_toward(crab, 1.0 if held() else 0.0, CRAB_RATE * delta)
	var ratio := CRAB_RATIO * crab
	car.rear_left_wheel.steering_ratio = ratio
	car.rear_right_wheel.steering_ratio = ratio
