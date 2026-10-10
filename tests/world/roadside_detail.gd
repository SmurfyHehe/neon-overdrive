extends SceneTree

# Stage A roadside test (2026-10-04): builds chunks for every lane-count pair
# and checks the new roadside detail lands where it should, plus the look
# rules that are easy to break by accident.
#
# Asserts (exit code 1 on failure):
# - lamps: 2 per side per chunk; each pole stands on the sidewalk just
#   outside the curb, on its own side of the road
# - light pools: one per lamp, centred over that side's road surface
# - posts: every 5 m on both shoulders
# - gap walls + buildings cover each side's 50 m frontage with no overlap,
#   leaving no gap wider than 0.3 m
# - the lamp mesh: every triangle has area, a unit normal that matches its
#   clockwise (Godot front-face) winding
# - look rules: building windows emit only through the facade mask (the
#   white-block bug), and road paint, posts, curb and barrier stay under the 1.0 glow
#   threshold (no neon); lamp heads are above it (they should bloom)
#
# Needs a real window: headless drops MultiMesh instance data.
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/world/roadside_detail.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const EPS := 0.001

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _initialize() -> void:
	seed(4242)
	var cases := 0
	for po in [2, 3, 4]:
		for pn in [1, 2]:
			for o in [2, 3, 4]:
				for n in [1, 2]:
					var prev := {"own_lanes": po, "onc_lanes": pn, "barrier": false}
					var cfg := {"own_lanes": o, "onc_lanes": n, "barrier": n == 2}
					var chunk: Node3D = B.build_chunk(cases, prev, cfg)
					root.add_child(chunk)
					_check_chunk(chunk, prev, cfg, "%s -> %s" % [prev, cfg])
					# The recycle path must produce the same layout rules.
					B.rebuild_chunk(chunk, cases + 100, cfg, prev)
					_check_chunk(chunk, cfg, prev, "rebuilt %s -> %s" % [cfg, prev])
					chunk.free()
					cases += 1
	_check_lamp_mesh()
	_check_materials()
	print("roadside_detail: %d cases, %s" % [cases, "PASS" if fails == 0 else "%d failure(s)" % fails])
	quit(0 if fails == 0 else 1)

func _edges(prev: Dictionary, cfg: Dictionary, key: String, t: float) -> Dictionary:
	var road: float = lerpf(B._lane_w(prev[key]), B._lane_w(cfg[key]), t)
	var curb := road + B.SHOULDER_W + B.CURB_W
	return {"road": road, "curb": curb, "walk": curb + B.SIDEWALK_W}

func _check_chunk(chunk: Node3D, prev: Dictionary, cfg: Dictionary, label: String) -> void:
	var lamps: MultiMesh = (chunk.get_node(^"Lamps") as MultiMeshInstance3D).multimesh
	var pools: MultiMesh = (chunk.get_node(^"LampPools") as MultiMeshInstance3D).multimesh
	if lamps.visible_instance_count != 4 or pools.visible_instance_count != 4:
		_fail("%s: %d lamps / %d pools, expected 4 / 4" % [label, lamps.visible_instance_count, pools.visible_instance_count])
		return
	for i in 4:
		var lamp := lamps.get_instance_transform(i)
		var pool := pools.get_instance_transform(i)
		var side := 1.0 if lamp.origin.x > 0.0 else -1.0
		var key := "own_lanes" if side > 0.0 else "onc_lanes"
		var e := _edges(prev, cfg, key, -lamp.origin.z / B.CHUNK_LEN)
		var x := absf(lamp.origin.x)
		if x < e.curb - EPS or x > e.walk + EPS:
			_fail("%s lamp %d: pole at |x| %.2f, outside sidewalk %.2f..%.2f" % [label, i, x, e.curb, e.walk])
		# The arm must reach over the road, i.e. point toward the centreline.
		var arm_dir := lamp.basis * Vector3.LEFT
		if signf(arm_dir.x) != -side:
			_fail("%s lamp %d: arm points away from the road" % [label, i])
		var px := absf(pool.origin.x)
		if signf(pool.origin.x) != side or px > e.curb or px < 0.5:
			_fail("%s pool %d: centre |x| %.2f is not over its side's road (curb at %.2f)" % [label, i, px, e.curb])
		if absf(pool.origin.z - lamp.origin.z) > EPS:
			_fail("%s pool %d: not under its lamp" % [label, i])
	# posts every PYLON_SPACING m on both sides
	for node_name in ["PylonsOwn", "PylonsOnc"]:
		var mm: MultiMesh = (chunk.get_node(NodePath(node_name)) as MultiMeshInstance3D).multimesh
		var want := int(B.CHUNK_LEN / B.PYLON_SPACING)
		if mm.visible_instance_count != want:
			_fail("%s %s: %d posts, expected %d" % [label, node_name, mm.visible_instance_count, want])
		for i in mm.visible_instance_count - 1:
			var dz := mm.get_instance_transform(i).origin.z - mm.get_instance_transform(i + 1).origin.z
			if absf(dz - B.PYLON_SPACING) > EPS:
				_fail("%s %s: posts %d->%d are %.2f m apart" % [label, node_name, i, i + 1, dz])
	# centre barrier: one piece per centreline station (#37), end to end on the
	# centre line, its base on the road (R1: each type's mesh starts at y = 0)
	var bar := chunk.get_node(^"Barrier") as MultiMeshInstance3D
	if bool(cfg.barrier) != bar.visible:
		_fail("%s: barrier shown %s" % [label, bar.visible])
	if cfg.barrier:
		var seg := B.CHUNK_LEN / B.STATIONS
		for k in B.STATIONS:
			var o := bar.multimesh.get_instance_transform(k).origin
			if absf(o.x) > EPS or absf(o.y) > EPS or absf(o.z + seg * (k + 0.5)) > EPS:
				_fail("%s: barrier piece %d at %s" % [label, k, o])
	_check_frontage(chunk, label)

## Buildings (z spans from their collision boxes) plus gap walls must tile
## each side's frontage from z=0 to z=-CHUNK_LEN without overlapping.
func _check_frontage(chunk: Node3D, label: String) -> void:
	var walls: MultiMesh = (chunk.get_node(^"GapWalls") as MultiMeshInstance3D).multimesh
	for side in [1.0, -1.0]:
		var spans: Array = []
		for i in B._building_slots() * 2:
			var body: StaticBody3D = chunk.get_node(NodePath("BuildingBody%d" % i))
			if signf(body.position.x) != side or (body.get_node(^"Shape") as CollisionShape3D).disabled:
				continue  # other side, or an empty lot the gap walls close
			var d: float = ((body.get_node(^"Shape") as CollisionShape3D).shape as BoxShape3D).size.z
			spans.append([body.position.z + d / 2.0, body.position.z - d / 2.0, "building"])
		for i in walls.visible_instance_count:
			var t := walls.get_instance_transform(i)
			if signf(t.origin.x) != side:
				continue
			if t.basis.get_scale().x > 1.0:
				continue  # a district step wall runs across the lot, not along it
			var length := t.basis.get_scale().z
			spans.append([t.origin.z + length / 2.0, t.origin.z - length / 2.0, "wall"])
		spans.sort_custom(func(a, b): return a[0] > b[0])
		var z := 0.0
		for s in spans:
			if s[0] > z + EPS:
				_fail("%s side %d: %s overlaps the previous piece at z=%.2f" % [label, side, s[2], z])
			elif z - s[0] > 0.3 + EPS:
				_fail("%s side %d: %.2f m open gap before z=%.2f" % [label, side, z - s[0], s[0]])
			z = s[1]
		if z - (-B.CHUNK_LEN) > 0.3 + EPS:
			_fail("%s side %d: %.2f m open at the chunk end" % [label, side, z + B.CHUNK_LEN])

func _check_lamp_mesh() -> void:
	var mesh := B._get_lamp_mesh()
	if mesh.get_surface_count() != 2:
		_fail("lamp mesh has %d surfaces, expected 2 (metal, sodium head)" % mesh.get_surface_count())
		return
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var n_tris := (idx.size() if idx.size() > 0 else verts.size()) / 3
		for t in n_tris:
			var i := [t * 3, t * 3 + 1, t * 3 + 2]
			if idx.size() > 0:
				i = [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]]
			var a: Vector3 = verts[i[0]]
			var b: Vector3 = verts[i[1]]
			var c: Vector3 = verts[i[2]]
			var face := (c - a).cross(b - a)  # outward normal of a clockwise triangle
			if face.length() < 1e-6:
				_fail("lamp surface %d tri %d: zero area" % [s, t])
				continue
			for k in 3:
				var nrm: Vector3 = normals[i[k]]
				if absf(nrm.length() - 1.0) > 1e-3 or nrm.dot(face.normalized()) < 0.99:
					_fail("lamp surface %d tri %d: normal %s does not match winding %s" % [s, t, nrm, face.normalized()])
					break
	print("lamp mesh: %d surfaces checked" % mesh.get_surface_count())

func _check_materials() -> void:
	# Buildings share the facade kit's one shader material; only masked
	# glass emits (scripts/world/building_kit.gd), so no white-block faces.
	var bm := B.BuildingKit.material()
	if bm.shader == null or not bm.shader.code.contains("EMISSION = c * lit"):
		_fail("building facade material lost its window-masked emission")
	var dim := {
		"lane dash": B._get_lane_dash_mat(), "centre dash": B._get_center_dash_mat(),
		"edge line": B._get_edge_line_mat(), "curb": B._get_curb_mat(),
		"barrier (concrete)": RoadBarriers._mat("concrete"), "barrier (guardrail)": RoadBarriers._mat("guardrail"),
		"barrier (cable)": RoadBarriers._mat("cable"), "crash cushion": RoadBarriers._mat("cushion"),
		"post (own)": B._get_pylon_mat_own(),
		"post (oncoming)": B._get_pylon_mat_onc(),
	}
	for k in dim:
		var m: StandardMaterial3D = dim[k]
		if m.emission_enabled and m.emission_energy_multiplier >= 1.0:
			_fail("%s glows (emission energy %.2f >= glow threshold 1.0): neon is out (Look Board B)" % [k, m.emission_energy_multiplier])
	var head := B._get_lamp_mesh().surface_get_material(1) as StandardMaterial3D
	if head == null or not head.emission_enabled or head.emission_energy_multiplier < 1.0:
		_fail("lamp head does not glow")
