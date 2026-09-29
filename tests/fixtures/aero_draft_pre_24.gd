# Frozen copy of AeroModel._draft_factor() as it was before issue #24
# (scripts/aero.gd at 4c1ddca). Used only by tests/aero_draft_equivalence.gd
# as the "before" reference. The body is verbatim; the only change is that
# the parameter is typed Node3D instead of Vehicle, so the test can use plain
# Node3D stand-ins (the body only touches Node3D API).
extends RefCounted

const DRAFT_MIN_DISTANCE := 3.0
const DRAFT_MAX_DISTANCE := 15.0
const DRAFT_MIN_ALIGNMENT := 0.85
const MAX_DRAFT_REDUCTION := 0.25

static func _draft_factor(v: Node3D) -> float:
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
