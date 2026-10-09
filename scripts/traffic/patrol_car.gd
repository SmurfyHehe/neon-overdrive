class_name PatrolCar
extends TrafficCar

# The stand-in patrol car (police build plan F1): a C1 patrol body with the
# cop undercarriage, driven by the traffic controller down one lane. It is
# not in TrafficManager's pool, so it reads the traffic around it (scan) but
# never asks the manager to re-file it: no lane changes. Real cop driving
# (pursuit, roadblocks) is a later stage.

const KIND := "c1_patrol"

## A patrol car ready to add to the tree (TrafficCar's setup runs in _ready).
static func make() -> PatrolCar:
	var c := PatrolCar.new()
	c.kind = KIND
	c.build = "stock"
	c.role = Undercarriage.ROLE_COP
	c.spec = CarSpec.clone_spec(CarSpec.npc_spec(KIND))
	c.spec["parts"] = "full"   # real wheels and brakes, like the fleet's cops
	c.color = NpcCarBuilder.sheet_paint(KIND)
	return c

func _consider_lane_change(_v: float) -> void:
	pass
