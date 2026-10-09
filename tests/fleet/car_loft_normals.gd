extends SceneTree

# Geometry test for the coupe's loft meshes (ISSUES G1, G2): every triangle in
# the body and glass lofts must have non-zero area, a unit normal, be wound
# CLOCKWISE seen from that normal (Godot's front face), and face away from the
# mesh's centre. A degenerate section (y0 == y1) used to produce zero-area cap
# quads and zero normals (G2); CCW winding culled every camera-facing panel (G1).
#
# Run (headless is fine, no MultiMesh involved):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/fleet/car_loft_normals.gd

const AREA_EPS := 1e-6

func _initialize() -> void:
	var car := CarBuilder.build_car("coupe", Color(0.8, 0.1, 0.3))
	var fails := 0
	var lofts := 0
	for child in car.get_children():
		if not (child is MeshInstance3D and child.mesh is ArrayMesh):
			continue
		lofts += 1
		var arrays: Array = (child.mesh as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var center: Vector3 = (child.mesh as ArrayMesh).get_aabb().get_center()
		var n_tris := (idx.size() if idx.size() > 0 else verts.size()) / 3
		for t in n_tris:
			var i := [t * 3, t * 3 + 1, t * 3 + 2]
			if idx.size() > 0:
				i = [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]]
			var a: Vector3 = verts[i[0]]
			var b: Vector3 = verts[i[1]]
			var c: Vector3 = verts[i[2]]
			# Outward normal of a clockwise (Godot front-facing) triangle.
			var face := (c - a).cross(b - a)
			if face.length() < AREA_EPS:
				print("FAIL loft %d tri %d: zero area %s %s %s" % [lofts, t, a, b, c])
				fails += 1
				continue
			for k in 3:
				var n: Vector3 = normals[i[k]]
				if absf(n.length() - 1.0) > 1e-3:
					print("FAIL loft %d tri %d: normal %s is not unit length" % [lofts, t, n])
					fails += 1
				elif n.dot(face.normalized()) < 0.99:
					print("FAIL loft %d tri %d: normal %s disagrees with face %s" % [lofts, t, n, face.normalized()])
					fails += 1
			if face.dot((a + b + c) / 3.0 - center) <= 0.0:
				print("FAIL loft %d tri %d: front face %s points inward" % [lofts, t, face.normalized()])
				fails += 1
		print("loft %d: %d triangles" % [lofts, n_tris])
	if lofts != 2:
		print("FAIL expected 2 loft meshes (body + glass), found %d" % lofts)
		fails += 1
	car.free()
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
