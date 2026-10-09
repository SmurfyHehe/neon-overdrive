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
# Data-driven like car_spec.gd: aero_downforce_coefficient_front/rear live as
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
	# BUG FIX (2026-09-13, verified headless): aero_downforce_coefficient_front/rear
	# are declared on PlayerCar, not on the vendored Vehicle base class this
	# function is statically typed against, so GDScript can't infer a type for
	# `q * v.frontal_area * v.aero_downforce_coefficient_front` via `:=` (it treats
	# the unknown member as Variant and refuses to infer) -- a hard parse
	# error that broke script loading entirely, not just a wrong number.
	# Explicit `: float` typing sidesteps the inference and does a normal
	# dynamic property fetch at runtime instead.
	var q := 0.5 * v.air_density * v.speed * v.speed
	var front_force: float = q * v.frontal_area * v.aero_downforce_coefficient_front
	var rear_force: float = q * v.frontal_area * v.aero_downforce_coefficient_rear
	var down := -v.global_transform.basis.y
	var front_offset := v.to_global(v.front_axle_position) - v.global_position
	var rear_offset := v.to_global(v.rear_axle_position) - v.global_position
	v.apply_force(down * front_force, front_offset)
	v.apply_force(down * rear_force, rear_offset)

## Drafting: cancels part of the vendor's already-applied drag force when
## another Vehicle is directly ahead and close, by recomputing the SAME drag
## formula process_drag() uses (all inputs -- air_density, speed,
## frontal_area, coefficient_of_drag -- are public on the vendor class) and
## applying a forward force that offsets a fraction of it. Other vehicles
## register themselves in the "aero_vehicles" group; traffic cars (stage B
## step 3, #113) do, so the player can now draft them. Cars hidden beyond the
## traffic draw distance leave the group (traffic_manager.gd).
static func _apply_draft(v: Vehicle) -> void:
	var draft_factor := _draft_factor(v)
	if draft_factor <= 0.0:
		return
	var drag := 0.5 * v.air_density * v.speed * v.speed * v.frontal_area * v.coefficient_of_drag
	if drag <= 0.0 or v.linear_velocity.length() < 0.01:
		return
	v.apply_central_force(v.linear_velocity.normalized() * drag * draft_factor)

## Drafting lookup scales with traffic (issue #24). The old version walked
## the whole "aero_vehicles" group for every vehicle, every physics frame:
## O(n^2), 1600 checks at 40 cars. Now the group is bucketed ONCE per physics
## frame into a flat XZ grid, and each vehicle only looks at the cells its
## DRAFT_MAX_DISTANCE circle touches. Cells are twice DRAFT_MAX_DISTANCE wide,
## so that circle always fits in a 2x2 block (4 lookups, not 9). The block
## holds every car the full scan would have accepted -- same result, not an
## approximation (tests/car/aero_draft_equivalence.gd checks it against a frozen
## copy of the old code). Grid, not lane buckets, so curves and lane changes
## need no special cases.
##
## Distances still use each car's LIVE global_position; the grid only decides
## who is a candidate. Cars move by physics integration, which happens after
## every _physics_process call, so positions don't change within a frame.
## Something that teleports a car mid-frame (a respawn) could leave it in a
## stale cell for that one frame -- harmless for a draft effect.
const _DRAFT_CELL := DRAFT_MAX_DISTANCE * 2.0

static var _draft_grid := {}  # Vector2i -> Array of Node3D
static var _draft_grid_frame := -1

static func _rebuild_draft_grid(tree: SceneTree) -> void:
	_draft_grid.clear()
	for other in tree.get_nodes_in_group("aero_vehicles"):
		var p: Vector3 = other.global_position
		var cell := Vector2i(floori(p.x / _DRAFT_CELL), floori(p.z / _DRAFT_CELL))
		if _draft_grid.has(cell):
			_draft_grid[cell].append(other)
		else:
			_draft_grid[cell] = [other]

## Forces the next lookup to rebuild the grid. Only tests need this: they move
## cars several times inside one physics frame.
static func invalidate_draft_grid() -> void:
	_draft_grid_frame = -1

static func _draft_factor(v: Node3D) -> float:
	var frame := Engine.get_physics_frames()
	if frame != _draft_grid_frame:
		_rebuild_draft_grid(v.get_tree())
		_draft_grid_frame = frame
	var best := 0.0
	var pos := v.global_position
	var forward := (-v.global_transform.basis.z).normalized()
	var x0 := floori((pos.x - DRAFT_MAX_DISTANCE) / _DRAFT_CELL)
	var x1 := floori((pos.x + DRAFT_MAX_DISTANCE) / _DRAFT_CELL)
	var z0 := floori((pos.z - DRAFT_MAX_DISTANCE) / _DRAFT_CELL)
	var z1 := floori((pos.z + DRAFT_MAX_DISTANCE) / _DRAFT_CELL)
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var bucket = _draft_grid.get(Vector2i(cx, cz))
			if bucket == null:
				continue
			for other in bucket:
				if other == v or not is_instance_valid(other):
					continue
				var to_other: Vector3 = other.global_position - pos
				var dist := to_other.length()
				if dist < 0.5 or dist > DRAFT_MAX_DISTANCE:
					continue
				var alignment := forward.dot(to_other.normalized())
				if alignment < DRAFT_MIN_ALIGNMENT:
					continue
				var closeness := 1.0 - clampf((dist - DRAFT_MIN_DISTANCE) / (DRAFT_MAX_DISTANCE - DRAFT_MIN_DISTANCE), 0.0, 1.0)
				best = maxf(best, closeness * MAX_DRAFT_REDUCTION)
	return best
