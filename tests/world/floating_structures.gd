extends SceneTree

# Floating-structures scan (2026-10-09): builds chunks across the districts, on
# a flat road and on a curvy hilly one, and checks nothing on a building hangs
# in the air. Roy saw roadside structures that belong to a building floating
# in the sky.
#
# Asserts (exit code 1 on failure):
# - every wall sign (band, blade, gas fascia, diner sign) lies within the
#   height of a building beside it, or rests on a roof prop (canopy, pole)
# - every roof prop / billboard pole stands on a building's top face, or on the
#   road (gas station columns, diner pole)
#
# Needs a real window: headless drops MultiMesh instance data.
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/world/floating_structures.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const TOL := 0.15
const CHUNKS := 400
## On a hilly road a roof prop follows the road grade at its own spot while the
## roof is flat, so a prop can stand off its roof by up to grade x half the
## building depth (5% x 9 m, about 0.45 m). Anything bigger is a real bug.
const HILL_SLACK := 0.5

var fails := 0
var checked := 0

func _fail(msg: String) -> void:
	fails += 1
	if fails <= 400:
		print("FAIL ", msg)

func _initialize() -> void:
	seed(9)
	var prev := {"own_lanes": 2, "onc_lanes": 1, "barrier": false}
	var cfg := {"own_lanes": 2, "onc_lanes": 1, "barrier": false}
	for road in ["flat", "curvy+hilly"]:
		RoadFrame.align = null if road == "flat" else RoadAlignment.new(7, 1.0, 1.0)
		for ci in range(0, CHUNKS):
			var chunk: Node3D = B.build_chunk(ci, prev, cfg)
			root.add_child(chunk)
			_check_chunk(chunk, "%s chunk %d" % [road, ci])
			# a pooled chunk is rebuilt in place for a new index: same rules
			B.rebuild_chunk(chunk, ci + 1000, cfg, prev)
			_check_chunk(chunk, "%s chunk %d rebuilt as %d" % [road, ci, ci + 1000])
			chunk.free()
	RoadFrame.align = null
	print("floating_structures: %d chunks x2, %d pieces, %s" % [CHUNKS, checked, "PASS" if fails == 0 else "%d failure(s)" % fails])
	quit(0 if fails == 0 else 1)

## Horizontal distance (ignoring height) from p to a building's footprint.
func _flat_dist(mi: MeshInstance3D, p: Vector3) -> float:
	var t := mi.transform
	var s := t.basis.get_scale().abs()
	var q := (t.affine_inverse() * p).abs() - Vector3(0.5, 0.5, 0.5)
	return Vector2(maxf(q.x, 0.0) * s.x, maxf(q.z, 0.0) * s.z).length()

func _top(mi: MeshInstance3D) -> float:
	return mi.transform.origin.y + mi.transform.basis.get_scale().y * 0.5

func _bottom(mi: MeshInstance3D) -> float:
	return mi.transform.origin.y - mi.transform.basis.get_scale().y * 0.5

func _check_chunk(chunk: Node3D, label: String) -> void:
	var boxes := []
	for c in chunk.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).visible and c.name.begins_with("BuildingMesh"):
			boxes.append(c)
	var signs: MultiMesh = (chunk.get_node(^"Signs") as MultiMeshInstance3D).multimesh
	var props: MultiMesh = (chunk.get_node(^"RoofProps") as MultiMeshInstance3D).multimesh
	var prop_t: Array = []
	for i in props.visible_instance_count:
		prop_t.append(props.get_instance_transform(i))

	# roof props: base on a roof, or on the road (within the foundation depth)
	for i in prop_t.size():
		var o: Vector3 = prop_t[i].origin
		checked += 1
		var ok := false
		for mi in boxes:
			if _flat_dist(mi, o) <= TOL and absf(o.y - _top(mi)) <= (HILL_SLACK if RoadFrame.align != null else TOL):
				ok = true
				break
		if not ok and _on_road(o):
			ok = true
		if not ok:
			# a canopy rests on the tops of its columns
			var half: Vector3 = prop_t[i].basis.get_scale() * 0.5
			for j in prop_t.size():
				var c: Transform3D = prop_t[j]
				if j != i and absf(c.origin.y + c.basis.get_scale().y - o.y) <= (HILL_SLACK if RoadFrame.align != null else TOL) and absf(c.origin.x - o.x) <= half.x and absf(c.origin.z - o.z) <= half.z:
					ok = true
					break
		if not ok:
			var near := ""
			for mi in boxes:
				if _flat_dist(mi, o) < 1.0:
					near += " [%s over by %.2f m]" % [mi.get_meta("building_type"), o.y - _top(mi)]
			_fail("%s: roof prop %d at %s has nothing under it:%s" % [label, i, o, near])

	# wall signs: the first `signs_used`; billboard panels after that stand on
	# the poles checked above
	var used: int = chunk.get_meta("signs_used", signs.visible_instance_count)
	for i in used:
		var t := signs.get_instance_transform(i)
		var half_h := t.basis.get_scale().y * 0.5
		var half_l := t.basis.get_scale().z * 0.5
		checked += 1
		var ok := false
		for mi in boxes:
			# the sign's wall end is near the building and its whole height is
			# inside the building's
			if _flat_dist(mi, t.origin) <= half_l + 0.25 and t.origin.y + half_h <= _top(mi) + TOL and t.origin.y - half_h >= _bottom(mi) - TOL:
				ok = true
				break
		if not ok:
			# pole- or canopy-mounted: resting on / touching a prop
			for pt in prop_t:
				var ps: Vector3 = pt.basis.get_scale()
				if absf(pt.origin.x - t.origin.x) <= half_l + ps.x * 0.5 + 0.3 and absf(pt.origin.z - t.origin.z) <= half_l + ps.z * 0.5 + 0.3 \
						and t.origin.y - half_h <= pt.origin.y + ps.y + TOL and t.origin.y + half_h >= pt.origin.y - TOL:
					ok = true
					break
		if not ok:
			var near := ""
			for mi in boxes:
				if _flat_dist(mi, t.origin) < 4.0:
					near += " [%s dist %.2f top %.2f]" % [mi.get_meta("building_type"), _flat_dist(mi, t.origin), _top(mi)]
			_fail("%s: sign %d at %s (h %.1f, half_l %.2f) hangs clear of every building:%s" % [label, i, t.origin, half_h * 2.0, half_l, near])

## A prop standing on the road: its base is at the road surface height at
## its spot. The road height only depends on how far along it is, so find the
## along-road position whose bent point is closest and read the height there.
func _on_road(o: Vector3) -> bool:
	var best := 1e9
	var road_y := 0.0
	var z := o.z - 6.0
	while z <= o.z + 6.0:
		var p := B._xf_up(o.x, 0.0, z).origin
		var d := Vector2(p.x - o.x, p.z - o.z).length()
		if d < best:
			best = d
			road_y = p.y
		z += 0.1
	return absf(o.y - road_y) <= (HILL_SLACK if RoadFrame.align != null else 0.3)
