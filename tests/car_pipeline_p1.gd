extends SceneTree

# Car pipeline step 1 (docs/planning/car-look-showcase-2026-10-09.md, section
# 12): the P1 coupe exported by tools/car_pipeline/build_car.py loads in Godot
# and is the car the design sheet shows.
#   loads     assets/cars/p1_coupe/body.glb opens through GLTFDocument (so the
#             test needs no import cache) and body.json beside it agrees with it
#   nodes     every node body.json lists is in the scene; body, hood, door_l,
#             door_r and trunk are separate meshes with triangles; the panels
#             sit under their hinge empties
#   budget    triangles within the player budget (10k) and at least the sheet's
#             proxy minus the wheels we did not export twice (> 2000)
#   dims      length 4.42 and body width 1.80 within 3 cm, body height 1.24
#             within 5 cm (mirrors and wing excluded from width/height)
#   hinges    turning each hinge by its open angle moves the far edge of its
#             panel away from the body (hood/trunk rise, doors swing out)
#   slots     every sticker-slot empty sits on the body: a ray along -Z (its
#             normal) from 20 cm out meets a body or panel triangle within 23 cm
#   tips      exhaust tips are behind the rear axle and above the floor
#   wheels    wheel empties on the sheet's hubs (x +-0.765, y 0.32, z +-1.26)
#   palette   no magenta or cyan material (same bands as fleet_design_check)
#
# Run (headless is fine):
#   godot --headless --path . -s res://tests/car_pipeline_p1.gd

const GLB := "res://assets/cars/p1_coupe/body.glb"
const META := "res://assets/cars/p1_coupe/body.json"
const PANELS := ["body", "hood", "door_l", "door_r", "trunk"]
const BUDGET := 10000
const MIN_TRIS := 2000

var _fails: Array[String] = []
var _checks := 0


func _init() -> void:
	_run()
	_finish()


func _run() -> void:
	var meta := _load_meta()
	if meta.is_empty():
		_fail("meta", "cannot read %s" % META)
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(GLB, state)
	_check("loads", err == OK, "GLTFDocument.append_from_file: %s" % error_string(err))
	if err != OK:
		return
	var root := doc.generate_scene(state)
	_check("loads", root != null, "generate_scene returned null")
	if root == null:
		return

	var by_name := {}
	_collect(root, by_name)
	for n in meta.nodes:
		_check("nodes", by_name.has(n), "node %s missing from the glb" % n)
	var tri_total := 0
	var mesh_count := 0
	for n in by_name:
		var node: Node = by_name[n]
		if node is MeshInstance3D:
			mesh_count += 1
			tri_total += _tris(node)
	for p in PANELS:
		var node: Node = by_name.get(p)
		_check("nodes", node is MeshInstance3D and _tris(node) > 0, "%s is not a mesh with triangles" % p)
	for hname in meta.hinges:
		var h: Dictionary = meta.hinges[hname]
		var hinge: Node = by_name.get(hname)
		var panel: Node = by_name.get(h.panel)
		_check("nodes", hinge is Node3D and panel != null and panel.get_parent() == hinge,
			"%s should be the parent of %s" % [hname, h.panel])
	_check("budget", tri_total <= BUDGET, "%d triangles, budget %d" % [tri_total, BUDGET])
	_check("budget", tri_total >= MIN_TRIS, "%d triangles, fewer than the sheet proxy (%d)" % [tri_total, MIN_TRIS])
	_check("budget", tri_total == int(meta.tris_total), "glb has %d triangles, body.json says %d" % [tri_total, int(meta.tris_total)])

	# dims from body plus the opening panels only
	var aabb := _world_aabb(by_name, PANELS)
	_near("dims", "length", aabb.size.z, float(meta.dims.L), 0.03)
	_near("dims", "width", aabb.size.x, float(meta.dims.W), 0.03)
	_near("dims", "height", aabb.end.y, float(meta.dims.H_body), 0.05)
	_check("dims", abs(aabb.position.y) < 0.2, "floor at y=%.2f, expected near the ground" % aabb.position.y)

	# hinges: the far edge moves out when opened
	for hname in meta.hinges:
		var h: Dictionary = meta.hinges[hname]
		var hinge: Node3D = by_name.get(hname)
		var panel: MeshInstance3D = by_name.get(h.panel)
		if hinge == null or panel == null:
			continue
		var before := _world_aabb(by_name, [h.panel])
		var axis := Vector3(h.axis[0], h.axis[1], h.axis[2])
		var saved := hinge.transform
		hinge.rotate(axis.normalized(), deg_to_rad(float(h.open_sign) * float(h.open_deg)))
		var after := _world_aabb(by_name, [h.panel])
		hinge.transform = saved
		if h.panel == "door_l":
			_check("hinges", after.position.x < before.position.x - 0.3, "door_l did not swing out (x %.2f -> %.2f)" % [before.position.x, after.position.x])
		elif h.panel == "door_r":
			_check("hinges", after.end.x > before.end.x + 0.3, "door_r did not swing out (x %.2f -> %.2f)" % [before.end.x, after.end.x])
		else:
			_check("hinges", after.end.y > before.end.y + 0.25, "%s did not rise (top %.2f -> %.2f)" % [h.panel, before.end.y, after.end.y])

	# sticker slots sit on the body
	var surface := _world_tris(by_name, PANELS)
	for s in meta.slots:
		var node: Node3D = by_name.get(s.node)
		if node == null:
			continue
		var xf := _world_xf(node)
		var normal := xf.basis.z.normalized()
		var origin := xf.origin + normal * 0.2
		var hit := _ray_hit(surface, origin, -normal, 0.23)
		_check("slots", hit, "%s (%s) is not on the body" % [s.node, s.id])
		var want := Vector3(s.normal[0], s.normal[1], s.normal[2])
		_check("slots", normal.dot(want) > 0.98, "%s empty is not facing its normal" % s.node)

	# exhaust tips behind the rear axle
	var rear_axle := float(meta.wheels.axle_z[1])
	for i in meta.exhaust_tips.size():
		var t: Dictionary = meta.exhaust_tips[i]
		var node: Node3D = by_name.get("tip_%d" % i)
		if node == null:
			_fail("tips", "tip_%d missing" % i)
			continue
		_check("tips", node.position.z > rear_axle, "tip_%d at z=%.2f is not behind the rear axle (%.2f)" % [i, node.position.z, rear_axle])
		_check("tips", node.position.y > 0.1 and node.position.y < 0.6, "tip_%d at y=%.2f" % [i, node.position.y])
		_check("tips", _world_xf(node).basis.z.dot(Vector3(t.dir[0], t.dir[1], t.dir[2])) > 0.98, "tip_%d not pointing its way" % i)

	# wheels on the hubs
	for tag in meta.wheels.hubs:
		var hub: Array = meta.wheels.hubs[tag]
		var node: Node3D = by_name.get("wheel_" + tag)
		if node == null:
			continue
		var want := Vector3(hub[0], hub[1], hub[2])
		_check("wheels", node.position.distance_to(want) < 0.005, "wheel_%s at %s, hub %s" % [tag, node.position, want])
		_check("wheels", abs(abs(want.x) - 0.765) < 0.01 and abs(want.y - 0.32) < 0.005 and abs(abs(want.z) - 1.26) < 0.01,
			"wheel_%s hub %s is off the sheet" % [tag, want])

	# palette
	for m in meta.materials:
		var c := Color(meta.materials[m])
		var bad := c.s > 0.25 and c.v > 0.2 and ((c.h * 360.0 >= 165.0 and c.h * 360.0 <= 200.0) or (c.h * 360.0 >= 285.0 and c.h * 360.0 <= 335.0))
		_check("palette", not bad, "material %s %s is magenta or cyan" % [m, meta.materials[m]])

	print("car_pipeline_p1: %d triangles in %d meshes, %d nodes, dims %.2f x %.2f x %.2f" % [
		tri_total, mesh_count, by_name.size(), aabb.size.z, aabb.size.x, aabb.end.y])


## Transform relative to the glb root, composed by hand: the scene is never
## added to the tree, so global_transform is not available here.
func _world_xf(node: Node3D) -> Transform3D:
	var xf := Transform3D()
	var n: Node = node
	while n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _load_meta() -> Dictionary:
	var f := FileAccess.open(META, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _collect(node: Node, out: Dictionary) -> void:
	out[node.name] = node
	for c in node.get_children():
		_collect(c, out)


func _tris(mi: MeshInstance3D) -> int:
	var n := 0
	var mesh := mi.mesh
	if mesh == null:
		return 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if idx.size() > 0:
			n += idx.size() / 3
		else:
			n += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _world_tris(by_name: Dictionary, names: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for nm in names:
		var mi: MeshInstance3D = by_name.get(nm)
		if mi == null or mi.mesh == null:
			continue
		var xf := _world_xf(mi)
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if idx.size() > 0:
				for i in idx:
					out.append(xf * verts[i])
			else:
				for v in verts:
					out.append(xf * v)
	return out


func _world_aabb(by_name: Dictionary, names: Array) -> AABB:
	var pts := _world_tris(by_name, names)
	if pts.is_empty():
		return AABB()
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	return box


func _ray_hit(tris: PackedVector3Array, origin: Vector3, dir: Vector3, max_dist: float) -> bool:
	var best := INF
	for i in range(0, tris.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(origin, dir, tris[i], tris[i + 1], tris[i + 2])
		if hit == null:
			hit = Geometry3D.ray_intersects_triangle(origin, dir, tris[i], tris[i + 2], tris[i + 1])
		if hit != null:
			best = minf(best, origin.distance_to(hit))
	return best <= max_dist


func _near(group: String, what: String, got: float, want: float, tol: float) -> void:
	_check(group, abs(got - want) <= tol, "%s %.3f, sheet %.3f (tolerance %.2f)" % [what, got, want, tol])


func _check(group: String, ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fail(group, msg)


func _fail(group: String, msg: String) -> void:
	_fails.append("%s: %s" % [group, msg])


func _finish() -> void:
	if _fails.is_empty():
		print("PASS car_pipeline_p1 (%d checks)" % _checks)
		quit(0)
	else:
		for f in _fails:
			printerr("FAIL " + f)
		print("FAIL car_pipeline_p1: %d of %d checks failed" % [_fails.size(), _checks])
		quit(1)
