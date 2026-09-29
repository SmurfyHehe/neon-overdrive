extends SceneTree

# Old-vs-new RoadChunkBuilder equivalence test.
#
# 01a84cb rewrote the chunk build path (shared meshes, MultiMesh dashes and
# pylons, in-place recycling) with "no visual change intended". This checks
# that claim: it builds the same chunks with the frozen pre-rewrite builder in
# tests/fixtures/ and with the live one, under the same random seed, and
# compares every visible mesh (geometry, world transform, material
# properties, meta) and every collision shape (size, transform, groups).
# MultiMesh instances are expanded so they compare 1:1 with the old
# per-node MeshInstance3D.
#
# It also pushes ONE pooled root through 400 recycles, comparing each against
# a fresh old build, and asserts the child count never changes.
#
# Run (needs the real renderer -- NOT --headless, see below):
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tests/chunk_builder_equivalence.gd
# Exit code 0 = pass. A window opens for a few seconds.
#
# Why not headless: the headless dummy renderer does not store MultiMesh
# instance transforms, so get_instance_transform() returns identity for every
# instance and this test would fail on data it cannot see. It refuses to run
# headless rather than report a false failure.
#
# Lifespan: this guards the 01a84cb refactor only. The first deliberate
# visual change to the road (e.g. fixing CULL_DISABLED, ISSUES B5) will fail
# it by design -- retire this test and the fixture at that point, don't
# re-freeze the fixture to make it pass.

const OldBuilder := preload("res://tests/fixtures/road_chunk_builder_pre_01a84cb.gd")

var fails := 0

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("chunk_builder_equivalence: run without --headless (MultiMesh data is not stored by the dummy renderer)")
		quit(2)
		return

	var holder := Node3D.new()
	root.add_child(holder)

	# 1) Fresh build: every (previous config -> config) pair the game can roll.
	var cases := 0
	for po in [2, 3, 4]:
		for pn in [1, 2]:
			for o in [2, 3, 4]:
				for n in [1, 2]:
					for b in [false, true]:
						var prev := {"own_lanes": po, "onc_lanes": pn, "barrier": false}
						var cfg := {"own_lanes": o, "onc_lanes": n, "barrier": b}
						seed(1000 + cases)
						var old_root: Node3D = OldBuilder.build_chunk(cases - 3, prev, cfg)
						seed(1000 + cases)
						var new_root: Node3D = RoadChunkBuilder.build_chunk(cases - 3, prev, cfg)
						_check("fresh %s -> %s" % [prev, cfg], _collect(old_root), _collect(new_root))
						old_root.free()
						new_root.free()
						cases += 1
	print("fresh-build cases: %d" % cases)

	# 2) One pooled root recycled repeatedly, each step vs a fresh old build.
	var start := {"own_lanes": 3, "onc_lanes": 2, "barrier": false}
	var pooled: Node3D = RoadChunkBuilder.build_chunk(0, start, start)
	holder.add_child(pooled)
	var child_count := pooled.get_child_count()
	seed(42)
	var cfgs := []
	for i in 401:
		cfgs.append({"own_lanes": randi_range(2, 4), "onc_lanes": randi_range(1, 2), "barrier": randf() < 0.3})
	var prev_cfg: Dictionary = start
	for i in 400:
		var cfg: Dictionary = cfgs[i]
		seed(5000 + i)
		RoadChunkBuilder.rebuild_chunk(pooled, i + 1, prev_cfg, cfg)
		seed(5000 + i)
		var ref: Node3D = OldBuilder.build_chunk(i + 1, prev_cfg, cfg)
		_check("recycle step %d" % i, _collect(ref), _collect(pooled))
		ref.free()
		if pooled.get_child_count() != child_count:
			_fail("child count changed at recycle step %d: %d -> %d" % [i, child_count, pooled.get_child_count()])
		prev_cfg = cfg
	print("recycle steps: 400, child count %d" % child_count)

	# 3) Out-of-range lane counts clamp instead of overrunning the buffers.
	RoadChunkBuilder.rebuild_chunk(pooled, 999, {"own_lanes": 6, "onc_lanes": 5, "barrier": false}, {"own_lanes": 6, "onc_lanes": 5, "barrier": false})

	# 4) Informational: drawing nodes per chunk and rebuild cost, old vs new.
	var widest := {"own_lanes": 4, "onc_lanes": 2, "barrier": false}
	var old_root2: Node3D = OldBuilder.build_chunk(0, widest, widest)
	RoadChunkBuilder.rebuild_chunk(pooled, 0, widest, widest)
	print("drawing nodes per chunk at max lanes: old=%d new=%d" % [_count_geometry(old_root2), _count_geometry(pooled)])
	holder.add_child(old_root2)
	var t0 := Time.get_ticks_usec()
	for i in 200:
		OldBuilder.rebuild_chunk(old_root2, i, cfgs[i], cfgs[i + 1])
		for c in old_root2.get_children():
			if c.is_queued_for_deletion():
				c.free()
	var t_old := (Time.get_ticks_usec() - t0) / 200.0
	t0 = Time.get_ticks_usec()
	for i in 200:
		RoadChunkBuilder.rebuild_chunk(pooled, i, cfgs[i], cfgs[i + 1])
	var t_new := (Time.get_ticks_usec() - t0) / 200.0
	print("avg rebuild_chunk: old=%.0f us new=%.0f us" % [t_old, t_new])

	holder.free()
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)

# ---------- signatures ----------

func _r(v: float) -> String:
	return "%.4f" % v

func _rv(v: Vector3) -> String:
	return "(%s,%s,%s)" % [_r(v.x), _r(v.y), _r(v.z)]

func _rt(t: Transform3D) -> String:
	return "%s|%s|%s|%s" % [_rv(t.basis.x), _rv(t.basis.y), _rv(t.basis.z), _rv(t.origin)]

func _mat_sig(m: Material) -> String:
	if m == null:
		return "null"
	var parts := []
	for p in m.get_property_list():
		if not (p.usage & PROPERTY_USAGE_STORAGE):
			continue
		if p.name in ["resource_name", "resource_path", "resource_local_to_scene", "script"]:
			continue
		var v = m.get(p.name)
		if v is Texture2D:
			v = "tex%dx%d" % [v.get_width(), v.get_height()]
		parts.append("%s=%s" % [p.name, str(v)])
	return ",".join(parts)

## BoxMesh by size; anything else by its expanded triangle list, so the old
## SurfaceTool strips and the new add_surface_from_arrays strips compare
## equal whether or not either side is indexed.
func _mesh_sig(mesh: Mesh) -> String:
	if mesh is BoxMesh:
		return "box" + _rv(mesh.size)
	var s := "arr%d" % mesh.get_surface_count()
	for i in mesh.get_surface_count():
		var a: Array = mesh.surface_get_arrays(i)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var idx = a[Mesh.ARRAY_INDEX]
		var order: Array = Array(idx) if idx != null and idx.size() > 0 else range(vs.size())
		for k in order:
			s += "v%sn%su(%s,%s)" % [_rv(vs[k]), _rv(ns[k]), _r(uv[k].x), _r(uv[k].y)]
		s += "p%d" % mesh.surface_get_primitive_type(i)
	return s

## Sorted list of everything visible or collidable under a chunk root.
## Transforms are accumulated by hand because these roots are never in the
## scene tree (global_transform would error).
func _collect(chunk: Node3D) -> Array:
	var out := []
	_walk(chunk, chunk.transform, out)
	out.sort()
	return out

func _walk(n: Node, parent_t: Transform3D, out: Array) -> void:
	for c in n.get_children():
		if c.is_queued_for_deletion():
			continue
		var t: Transform3D = parent_t * (c as Node3D).transform if c is Node3D else parent_t
		if c is MultiMeshInstance3D:
			if c.visible:
				var mm: MultiMesh = c.multimesh
				var count: int = mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
				for i in count:
					out.append("MESH %s @%s mat{%s} meta=" % [_mesh_sig(mm.mesh), _rt(t * mm.get_instance_transform(i)), _mat_sig(c.material_override)])
		elif c is MeshInstance3D:
			if c.visible:
				out.append("MESH %s @%s mat{%s} meta=%s" % [_mesh_sig(c.mesh), _rt(t), _mat_sig(c.material_override), str(c.get_meta("building_type", ""))])
		elif c is CollisionShape3D:
			out.append("COL %s size%s @%s groups=%s" % [c.shape.get_class(), _rv(c.shape.size), _rt(t), str(c.get_parent().get_groups())])
		_walk(c, t, out)

func _count_geometry(chunk: Node3D) -> int:
	var n := 0
	for c in chunk.get_children():
		if c is GeometryInstance3D and c.visible:
			n += 1
	return n

# ---------- reporting ----------

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _check(label: String, old_items: Array, new_items: Array) -> void:
	if old_items == new_items:
		return
	_fail("%s (old %d items, new %d)" % [label, old_items.size(), new_items.size()])
	if fails > 5:
		return
	var shown := 0
	for x in old_items:
		if not new_items.has(x) and shown < 3:
			print("  only in old: ", x.substr(0, 200))
			shown += 1
	shown = 0
	for x in new_items:
		if not old_items.has(x) and shown < 3:
			print("  only in new: ", x.substr(0, 200))
			shown += 1
