# AeroModel (2026-09-13, Roy: "add aerodynamics to the game" -> asked to scope
# it, picked "full aero model": downforce, drafting, and speed-dependent
# pitch/lift). Lives OUTSIDE the vendored gevp_vehicle.gd on purpose -- that
# file is kept unmodified (see player.gd header) so future upstream updates
# still drop in cleanly. Instead this hooks in from PlayerCar._physics_process
# AFTER super._physics_process(delta) runs the vendor's own drag/motor/wheel
# processing, using only the vendor's own public fields (speed, air_density,
# frontal_area, front_axle_position, rear_axle_position, coefficient_of_drag,
# linear_velocity) -- same "extend, don't edit" pattern as the rest of this
# project's vendor integration.
#
# Data-driven like car_spec.gd: aero_lift_coefficient_front/rear live as
# plain vars on PlayerCar (not the vendor class) and get set the same way
# CarSpec.apply() sets everything else, via v.set(). Future NPCCar/CopCar
# specs can give themselves different aero numbers (e.g. a heavier cop SUV
# with less downforce) the same way they'll differ in mass or torque.
extends RefCounted
class_name AeroModel

const DRAFT_MIN_DISTANCE := 3.0
const DRAFT_MAX_DISTANCE := 15.0
const DRAFT_MIN_ALIGNMENT := 0.85  # dot-product threshold, ~roughly a 32 degree half-angle forward cone
const MAX_DRAFT_REDUCTION := 0.25  # tucked in close behind another car cancels up to 25% of drag

static func apply(v: Vehicle) -> void:
	_apply_downforce(v)
	_apply_draft(v)

## Real (not scripted) downforce: same dynamic-pressure term (0.5*rho*v^2)
## the vendor's own process_drag() uses for drag, applied as a genuine
## downward FORCE at the front and rear axle positions rather than a fake
## grip multiplier. Because it's a real force at a real lever arm (not at
## the center of mass), it also naturally affects pitch: more downforce at
## speed pushes the axles down harder, which the real raycast suspension
## resists with more spring force -- so hard acceleration/braking pitches
## the chassis LESS at high speed than at low speed, for free, without any
## separate "reduce pitch at speed" code. This is exactly the kind of claim
## that needs headless verification, not just this comment -- see ship notes.
static func _apply_downforce(v: Vehicle) -> void:
	# BUG FIX (2026-09-13, verified headless): aero_lift_coefficient_front/rear
	# are declared on PlayerCar, not on the vendored Vehicle base class this
	# function is statically typed against, so GDScript can't infer a type for
	# `q * v.frontal_area * v.aero_lift_coefficient_front` via `:=` (it treats
	# the unknown member as Variant and refuses to infer) -- a hard parse
	# error that broke script loading entirely, not just a wrong number.
	# Explicit `: float` typing sidesteps the inference and does a normal
	# dynamic property fetch at runtime instead.
	var q := 0.5 * v.air_density * v.speed * v.speed
	var front_force: float = q * v.frontal_area * v.aero_lift_coefficient_front
	var rear_force: float = q * v.frontal_area * v.aero_lift_coefficient_rear
	var down := -v.global_transform.basis.y
	var front_offset := v.to_global(v.front_axle_position) - v.global_position
	var rear_offset := v.to_global(v.rear_axle_position) - v.global_position
	v.apply_force(down * front_force, front_offset)
	v.apply_force(down * rear_force, rear_offset)

## Drafting: cancels part of the vendor's already-applied drag force when
## another Vehicle is directly ahead and close, by recomputing the SAME drag
## formula process_drag() uses (all inputs -- air_density, speed,
## frontal_area, coefficient_of_drag -- are public on the vendor class) and
## applying a forward force that offsets a fraction of it. No traffic cars
## exist yet (milestone 3, not built) -- other vehicles register themselves
## in the "aero_vehicles" group, so until traffic/cops exist this always
## finds nothing and the effect is a real, tested mechanism sitting inert,
## the same "built for real, dormant until it has something to act on"
## pattern as car_spec.gd.
static func _apply_draft(v: Vehicle) -> void:
	var draft_factor := _draft_factor(v)
	if draft_factor <= 0.0:
		return
	var drag := 0.5 * v.air_density * v.speed * v.speed * v.frontal_area * v.coefficient_of_drag
	if drag <= 0.0 or v.linear_velocity.length() < 0.01:
		return
	v.apply_central_force(v.linear_velocity.normalized() * drag * draft_factor)

static func _draft_factor(v: Vehicle) -> float:
	var best := 0.0
	for other in v.get_tree().get_nodes_in_group("aero_vehicles"):
		if other == v:
			continue
		var to_other: Vector3 = other.global_position - v.global_position
		var dist := to_other.length()
		if dist < 0.5 or dist > DRAFT_MAX_DISTANCE:
			continue
		var forward := -v.global_transform.basis.z
		var alignment := forward.normalized().dot(to_other.normalized())
		if alignment < DRAFT_MIN_ALIGNMENT:
			continue
		var closeness := 1.0 - clampf((dist - DRAFT_MIN_DISTANCE) / (DRAFT_MAX_DISTANCE - DRAFT_MIN_DISTANCE), 0.0, 1.0)
		best = maxf(best, closeness * MAX_DRAFT_REDUCTION)
	return best
