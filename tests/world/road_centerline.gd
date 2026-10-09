extends SceneTree

# Chunk centreline (#37 step R2): every chunk is laid out along its Path3D
# centreline, cut into STATIONS pieces so it can follow a bend. The curve is
# still straight, so the street must be what it was. Headless, no game scene,
# every lane-count change the game can roll:
# - the centreline frame at every metre is a plain translation to (0, 0, -s):
#   origin within 1 mm, axes within 0.001 of the world's
# - every strip: each vertex sits on the straight line between the strip's
#   own start and end corners (so the pieces trace the old tapered quad),
#   at the strip's height, normals up, and the triangles add up to the old
#   trapezoid's area
# - the out-of-bounds walls: STATIONS boxes at one x, covering the chunk
#   end to end with no gap
# - the barrier: STATIONS pieces (their positions: roadside_detail.gd)
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/road_centerline.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const EPS := 0.001
const STRIPS := [
	"RoadOwn", "RoadOnc", "EdgeLineOwn", "EdgeLineOnc", "ShoulderOwn",
	"ShoulderOnc", "CurbOwn", "CurbOnc", "SidewalkOwn", "SidewalkOnc",
]

var fails := 0

func _initialize() -> void:
	var cases := 0
	for po in [2, 4]:
		for pn in [1, 4]:
			for o in [2, 4]:
				for n in [1, 4]:
					for barrier in [false, true]:
						var prev := {"own_lanes": po, "onc_lanes": pn, "barrier": false}
						var cfg := {"own_lanes": o, "onc_lanes": n, "barrier": barrier}
						var chunk: Node3D = B.build_chunk(cases, prev, cfg)
						var label := "%s -> %s" % [prev, cfg]
						if cases == 0:
							_check_frames(chunk)
						for strip_name in STRIPS:
							_check_strip(chunk.get_node(NodePath(strip_name)), "%s %s" % [strip_name, label])
						for wall_name in ["BoundaryOwn", "BoundaryOnc"]:
							_check_wall(chunk.get_node(NodePath(wall_name)), "%s %s" % [wall_name, label])
						var bar := chunk.get_node(^"Barrier") as MultiMeshInstance3D
						_check(bar.visible == barrier, "barrier shown %s, want %s (%s)" % [bar.visible, barrier, label])
						if barrier:
							# Piece positions are checked in roadside_detail.gd: headless drops
							# MultiMesh instance data, so only the count is visible here.
							_check(bar.multimesh.visible_instance_count == B.STATIONS, "barrier has %d pieces" % bar.multimesh.visible_instance_count)
						chunk.free()
						cases += 1
	print("road_centerline: %d chunk configs, %d failures" % [cases, fails])
	quit(1 if fails > 0 else 0)

func _check_frames(chunk: Node3D) -> void:
	var curve := (chunk.get_node(^"Centerline") as Path3D).curve
	_check(absf(curve.get_baked_length() - B.CHUNK_LEN) < EPS, "centreline is %.4f m, want %.0f" % [curve.get_baked_length(), B.CHUNK_LEN])
	for s in range(0, int(B.CHUNK_LEN) + 1):
		var f: Transform3D = B.station(curve, float(s))
		_check(f.origin.distance_to(Vector3(0.0, 0.0, -float(s))) < EPS, "frame at s=%d sits at %s" % [s, f.origin])
		_check(f.basis.x.distance_to(Vector3.RIGHT) < EPS and f.basis.y.distance_to(Vector3.UP) < EPS and f.basis.z.distance_to(Vector3.BACK) < EPS,
			"frame at s=%d is turned: %s" % [s, f.basis])

func _check_strip(mi: MeshInstance3D, label: String) -> void:
	var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	_check(verts.size() == 6 * B._strip_n, "%s: %d vertices, want %d" % [label, verts.size(), 6 * B._strip_n])
	# The strip's own corners: the two x values at the start (z=0) and at the end.
	var start_x: Array[float] = []
	var end_x: Array[float] = []
	var y := verts[0].y
	for v in verts:
		if absf(v.z) < EPS and not _has(start_x, v.x):
			start_x.append(v.x)
		if absf(v.z + B.CHUNK_LEN) < EPS and not _has(end_x, v.x):
			end_x.append(v.x)
	if start_x.size() != 2 or end_x.size() != 2:
		_check(false, "%s: expected 2 corners at each end, got %s / %s" % [label, start_x, end_x])
		return
	start_x.sort()
	end_x.sort()
	for i in verts.size():
		var v := verts[i]
		var t := -v.z / B.CHUNK_LEN
		var lo := lerpf(start_x[0], end_x[0], t)
		var hi := lerpf(start_x[1], end_x[1], t)
		_check(absf(v.y - y) < EPS, "%s: vertex %d at y %.4f, strip is at %.4f" % [label, i, v.y, y])
		_check(t > -EPS and t < 1.0 + EPS, "%s: vertex %d outside the chunk (z %.3f)" % [label, i, v.z])
		_check(absf(v.x - lo) < EPS or absf(v.x - hi) < EPS, "%s: vertex %d x %.4f is off the strip's edges %.4f / %.4f" % [label, i, v.x, lo, hi])
		_check(normals[i].distance_to(Vector3.UP) < EPS, "%s: normal %d is %s" % [label, i, normals[i]])
	var area := 0.0
	for k in verts.size() / 3:
		area += (verts[k * 3 + 1] - verts[k * 3]).cross(verts[k * 3 + 2] - verts[k * 3]).length() / 2.0
	var want := ((start_x[1] - start_x[0]) + (end_x[1] - end_x[0])) / 2.0 * B.CHUNK_LEN
	_check(absf(area - want) < 0.01, "%s: area %.3f, the old quad was %.3f" % [label, area, want])

func _check_wall(body: StaticBody3D, label: String) -> void:
	var shapes: Array[CollisionShape3D] = []
	for c in body.get_children():
		if c is CollisionShape3D:
			shapes.append(c)
	_check(shapes.size() == B.STATIONS, "%s: %d boxes, want %d" % [label, shapes.size(), B.STATIONS])
	if shapes.is_empty():
		return
	var x := (shapes[0].global_position if shapes[0].is_inside_tree() else shapes[0].position).x
	var covered_to := 0.0  # z covered so far, from 0 down
	var spans := []
	for c in shapes:
		var box := c.shape as BoxShape3D
		var p := c.position + body.position
		_check(absf(p.x - x) < EPS, "%s: box at x %.3f, the first is at %.3f" % [label, p.x, x])
		_check(box.size.y >= 4.0, "%s: box only %.1f m tall" % [label, box.size.y])
		spans.append([p.z + box.size.z / 2.0, p.z - box.size.z / 2.0])
	spans.sort_custom(func(a, b): return a[0] > b[0])
	for sp in spans:
		_check(sp[0] >= covered_to - EPS, "%s: gap in the wall at z %.3f" % [label, covered_to])
		covered_to = minf(covered_to, sp[1])
	_check(covered_to <= -B.CHUNK_LEN + EPS, "%s: wall stops at z %.3f" % [label, covered_to])

func _has(arr: Array[float], x: float) -> bool:
	for a in arr:
		if absf(a - x) < EPS:
			return true
	return false

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		if fails <= 30:
			printerr("FAIL: " + msg)
