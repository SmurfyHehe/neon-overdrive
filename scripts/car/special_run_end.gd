class_name SpecialRunEnd
extends Node

# Run end hook for the special vehicles (S0, Roy 2026-10-10): the truck lying
# on its side or roof for 2 s ends the night, the lowrider rolling ends the
# run (1 s). "Upside down" is the same read the Tuner's watchdog uses
# (tune_watchdog.gd: the car's up axis, basis.y.y, below zero); here the line
# is per kind, at 0.3 (a car on its side reads about 0). Normal cars have no
# entry and never end a run this way.
#
# The put-back safety net (off_map_rescue.gd, claude/off-map-rescue, PR #356)
# is unrelated: it triggers 60 m above the road and needs no change.

## kind -> [basis.y.y below this, for this many seconds]
const LIMITS := {
	"m1_monster": [0.3, 2.0],
	"l1_lowrider": [0.3, 1.0],
}

signal run_ended(reason: String)

var car: Node3D
var kind := ""
var upside_t := 0.0
var fired := false

func _init(player: Node3D = null, car_kind: String = "") -> void:
	car = player
	kind = car_kind

static func has_limit(k: String) -> bool:
	return LIMITS.has(k)

## One step. Returns true on the step the run ends (once only).
func step(delta: float, up_y: float) -> bool:
	if fired or not LIMITS.has(kind):
		return false
	var lim: Array = LIMITS[kind]
	upside_t = upside_t + delta if up_y < float(lim[0]) else 0.0
	if upside_t >= float(lim[1]):
		fired = true
		run_ended.emit("the %s is on its side" % ("truck" if kind == "m1_monster" else "lowrider"))
		return true
	return false

func _physics_process(delta: float) -> void:
	if car != null and is_instance_valid(car):
		step(delta, car.global_transform.basis.y.y)
