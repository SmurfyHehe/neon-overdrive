class_name CarSlots
extends RefCounted

# The required-slot list (car-parts-every-vehicle plan 2026-10-10, section 6a):
# every vehicle class names the parts it must carry, and tests/car/required_slots.gd
# fails when a built car leaves one empty. This is what stops "brakes on two
# cars only" from coming back: a new car, or an old one, cannot ship without
# a brake behind every wheel, a lit lamp for every function and its plates.
#
# Slots are read off the BUILT car (its CarParts node and its chassis visual's
# "fittings" meta), not off a data table, so a builder that forgets a part
# fails here instead of passing on paper.
#
# A slot can be declared empty on purpose with a reason (a roadster has no
# rear glass, so no third brake light): CarFittings.NONE. An empty slot with
# no reason is a failure.

const CLASS_PLAYER := "player"
const CLASS_COP := "cop"
const CLASS_TRAFFIC := "traffic"

const BRAKES := ["brake_front", "brake_rear"]
const LAMPS := ["lamp_brake", "lamp_third_brake", "lamp_reverse", "lamp_blinker_front", "lamp_blinker_rear", "lamp_hazard"]
const PLATES := ["plate_front", "plate_rear"]

## Slots per vehicle class. Traffic has no visible brakes (decided, Roy 141);
## it still wears plates and every lamp function (Roy 1174).
const REQUIRED := {
	CLASS_PLAYER: ["brake_front", "brake_rear", "lamp_brake", "lamp_third_brake", "lamp_reverse",
		"lamp_blinker_front", "lamp_blinker_rear", "lamp_hazard", "plate_front", "plate_rear"],
	CLASS_COP: ["brake_front", "brake_rear", "lamp_brake", "lamp_third_brake", "lamp_reverse",
		"lamp_blinker_front", "lamp_blinker_rear", "lamp_hazard", "plate_front", "plate_rear"],
	CLASS_TRAFFIC: ["lamp_brake", "lamp_third_brake", "lamp_reverse",
		"lamp_blinker_front", "lamp_blinker_rear", "lamp_hazard", "plate_front", "plate_rear"],
}

## The class of a vehicle kind: the player's cars, the C-series cops, the rest traffic.
static func class_of(kind: String) -> String:
	if PlayerCars.is_player_kind(kind):
		return CLASS_PLAYER
	if kind.begins_with("c") and NpcCarBuilder.is_npc(kind):
		return CLASS_COP
	return CLASS_TRAFFIC

## Every slot of a built car: slot -> "" when filled, otherwise why it is
## empty ("none: <reason>" for a declared gap, "MISSING" for a real one).
## `vehicle` is the car node (PlayerCar or TrafficCar) with its chassis visual.
static func report(vehicle: Node, kind: String, visual: Node3D) -> Dictionary:
	var out := {}
	var parts := vehicle.get_node_or_null("CarParts") as CarParts
	for s in BRAKES:
		var axle_ok := false
		if parts != null and parts.brake_kinds.size() == 4:
			var i := 0 if s == "brake_front" else 2
			axle_ok = parts.brake_kinds[i] != "" and parts.brake_kinds[i + 1] != ""
		out[s] = "" if axle_ok else "MISSING"
	var fit: Dictionary = visual.get_meta("fittings", {}) if visual != null else {}
	var lamp_driver := _has_lamp_driver(vehicle)
	out["lamp_brake"] = _count_slot(fit, "brake_lamp", kind, "lamp_brake", 2)
	out["lamp_third_brake"] = _count_slot(fit, "third_brake", kind, "lamp_third_brake", 1)
	out["lamp_reverse"] = _count_slot(fit, "reverse", kind, "lamp_reverse", 2)
	out["lamp_blinker_front"] = _count_slot(fit, "blinker_front", kind, "lamp_blinker_front", 2)
	out["lamp_blinker_rear"] = _count_slot(fit, "blinker_rear", kind, "lamp_blinker_rear", 2)
	# Hazards need the four blinkers and something that drives them.
	var hz := "" if lamp_driver and out["lamp_blinker_front"] == "" and out["lamp_blinker_rear"] == "" else "MISSING"
	out["lamp_hazard"] = hz
	out["plate_front"] = _count_slot(fit, "plate_front", kind, "plate_front", 1)
	out["plate_rear"] = _count_slot(fit, "plate_rear", kind, "plate_rear", 1)
	return out

## The slots a car is missing for its class: an array of "slot (why)".
static func missing(vehicle: Node, kind: String, visual: Node3D) -> Array[String]:
	var rep := report(vehicle, kind, visual)
	var out: Array[String] = []
	for s in REQUIRED[class_of(kind)]:
		var why: String = rep.get(s, "MISSING")
		if why != "" and not why.begins_with("none:"):
			out.append("%s (%s)" % [s, why])
	return out

static func _count_slot(fit: Dictionary, key: String, kind: String, slot: String, need: int) -> String:
	if int(fit.get(key, 0)) >= need:
		return ""
	var why := CarFittings.none_reason(kind, slot)
	if why != "":
		return "none: " + why
	return "MISSING"

## A lamp driver is the thing that turns the lamp channels on: the player's
## CarLamps node, or TrafficCar's own brake and hazard update.
static func _has_lamp_driver(vehicle: Node) -> bool:
	if vehicle.get_node_or_null("CarLamps") != null:
		return true
	return vehicle is TrafficCar
