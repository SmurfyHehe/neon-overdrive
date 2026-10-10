extends SceneTree

# Chunk builder equivalence + budget test (buildings step 1, 2026-10-07).
#
# The building upgrade adds variety (facade tile, tint, floors, later types,
# props and districts) without disturbing anything else the chunk builder
# feeds. This test pins that down.
#
# Asserts (exit code 1 on failure):
# - global RNG: building a chunk consumes exactly 4 global draws per
#   building, as before the upgrade, so game.gd's road layout (lane counts,
#   barrier rolls) is the same for any seed
# - recycle path: a pooled chunk rebuilt to index N matches a chunk built
#   fresh at N -- every building's size, position, collision box, meta and
#   facade parameters
# - one shared building material across the whole pool
# - every building has a type (empty lots are hidden and not solid); every signed building gets a sign; rooftop
#   props and billboards match between rebuild and fresh build
# - districts: the drive starts downtown, all four districts appear, and
#   wherever the setback changes a cross wall closes the step between the
#   two out-of-bounds lines; every building type (special ones included)
#   turns up
# - budget: roadside buildings and furniture stay under 5,000 triangles
#   per 50 m chunk (worst case over many chunks)
#
# Headless is fine: it reads node and shader-parameter state, not MultiMesh
# transforms.
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/chunk_builder_equivalence.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const TRI_BUDGET := 5000
const PARAMS := ["tile", "tint", "size", "floor_h", "lit_density", "seed", "wear"]

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _initialize() -> void:
	_check_rng_consumption()
	_check_rebuild_matches_build()
	_check_budget()
	_check_districts()
	print("chunk_builder_equivalence: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	quit(0 if fails == 0 else 1)

func _cfg(o: int, n: int, barrier: bool) -> Dictionary:
	return {"own_lanes": o, "onc_lanes": n, "barrier": barrier}

func _check_rng_consumption() -> void:
	# warm the static caches first; their one-time setup is not the question
	B.build_chunk(0, _cfg(2, 2, false), _cfg(2, 2, false)).free()
	for s in [1, 777, 4242, 90210]:
		seed(s)
		var c := B.build_chunk(5, _cfg(2, 2, false), _cfg(3, 1, true))
		var after := randi()
		c.free()
		seed(s)
		# the four global calls each building made before the upgrade
		for k in B._building_slots() * 2:
			var garage := randf() < 0.12
			randf_range(4.0, 10.0)
			randf_range(9.0, 18.0)
			if garage:
				randf_range(3.0, 4.5)
			else:
				randf_range(6.0, 22.0)
		var expect := randi()
		if after != expect:
			_fail("seed %d: building a chunk no longer consumes the global RNG exactly as before" % s)
	print("rng: global draws per chunk unchanged")

func _check_rebuild_matches_build() -> void:
	var cases := 0
	for idx in [0, 1, 7, 123, 4096, -3]:
		for pair in [[_cfg(2, 2, false), _cfg(3, 1, true)], [_cfg(4, 2, true), _cfg(1, 1, false)]]:
			seed(1000 + idx)
			var fresh := B.build_chunk(idx, pair[0], pair[1])
			var pooled := B.build_chunk(idx + 55, pair[1], pair[0])
			seed(1000 + idx)
			B.rebuild_chunk(pooled, idx, pair[0], pair[1])
			_compare(fresh, pooled, "chunk %d %s" % [idx, pair])
			fresh.free()
			pooled.free()
			cases += 1
	print("rebuild == build: %d cases" % cases)

func _compare(a: Node3D, b: Node3D, label: String) -> void:
	var shared: Material = null
	for i in B._building_slots() * 2:
		var ma: MeshInstance3D = a.get_node(NodePath("BuildingMesh%d" % i))
		var mb: MeshInstance3D = b.get_node(NodePath("BuildingMesh%d" % i))
		var ba: StaticBody3D = a.get_node(NodePath("BuildingBody%d" % i))
		var bb: StaticBody3D = b.get_node(NodePath("BuildingBody%d" % i))
		if not ma.position.is_equal_approx(mb.position) or not ma.scale.is_equal_approx(mb.scale):
			_fail("%s building %d: mesh %s/%s vs %s/%s" % [label, i, ma.position, ma.scale, mb.position, mb.scale])
		var sa: Vector3 = ((ba.get_node(^"Shape") as CollisionShape3D).shape as BoxShape3D).size
		var sb: Vector3 = ((bb.get_node(^"Shape") as CollisionShape3D).shape as BoxShape3D).size
		if not sa.is_equal_approx(sb) or not ba.position.is_equal_approx(bb.position):
			_fail("%s building %d: collision differs" % [label, i])
		if not sa.is_equal_approx(ma.scale):
			_fail("%s building %d: collision %s does not match the drawn box %s" % [label, i, sa, ma.scale])
		for m in [ma, mb]:
			var meta_keys: Array = m.get_meta_list()
			meta_keys.sort()
			var other: MeshInstance3D = mb if m == ma else ma
			var other_keys: Array = other.get_meta_list()
			other_keys.sort()
			if meta_keys != other_keys:
				_fail("%s building %d: meta keys %s vs %s" % [label, i, meta_keys, other_keys])
				break
		for k in ma.get_meta_list():
			if mb.has_meta(k) and ma.get_meta(k) != mb.get_meta(k):
				_fail("%s building %d: meta %s %s vs %s" % [label, i, k, ma.get_meta(k), mb.get_meta(k)])
		if ma.get_meta("building_type", "") == "lot":
			# an empty lot: hidden, no collision, nothing else to compare
			if ma.visible or mb.visible or not (ba.get_node(^"Shape") as CollisionShape3D).disabled 					or not (bb.get_node(^"Shape") as CollisionShape3D).disabled:
				_fail("%s building %d: an empty lot is still drawn or solid" % [label, i])
			continue
		for p in PARAMS:
			var va = ma.get_instance_shader_parameter(p)
			var vb = mb.get_instance_shader_parameter(p)
			if va == null or str(va) != str(vb):
				_fail("%s building %d: facade %s %s vs %s" % [label, i, p, va, vb])
		if not ma.has_meta("building_type"):
			_fail("%s building %d: no building_type" % [label, i])
		for m in [ma, mb]:
			if shared == null:
				shared = m.material_override
			elif m.material_override != shared:
				_fail("%s building %d: does not share the building material" % [label, i])

	var sa_n: int = (a.get_node(^"Signs") as MultiMeshInstance3D).multimesh.visible_instance_count
	var sb_n: int = (b.get_node(^"Signs") as MultiMeshInstance3D).multimesh.visible_instance_count
	var signed := 0
	for i in B._building_slots() * 2:
		if (a.get_node(NodePath("BuildingMesh%d" % i)) as Node).has_meta("sign_word"):
			signed += 1
	# signs = shop signs + rooftop billboards
	if sa_n != sb_n or sa_n < signed:
		_fail("%s: %d / %d signs drawn for %d signed buildings" % [label, sa_n, sb_n, signed])
	var pa: int = (a.get_node(^"RoofProps") as MultiMeshInstance3D).multimesh.visible_instance_count
	var pb: int = (b.get_node(^"RoofProps") as MultiMeshInstance3D).multimesh.visible_instance_count
	if pa != pb or pa != int(a.get_meta("roof_props", -1)):
		_fail("%s: roof props %d vs %d" % [label, pa, pb])

## Triangles drawn by roadside buildings and furniture (everything outside
## the road surface strips), worst case over a run of chunks.
func _check_budget() -> void:
	seed(31337)
	var worst := 0
	var worst_all := 0
	var chunk := B.build_chunk(0, _cfg(2, 2, false), _cfg(2, 2, false))
	for idx in range(0, 200):
		var o := 1 + idx % 4
		var n := 1 + (idx / 4) % 2
		B.rebuild_chunk(chunk, idx, _cfg(2, 2, false), _cfg(o, n, idx % 3 == 0))
		var roadside := 0
		var total := 0
		for c in chunk.get_children():
			var tris := _tris(c)
			total += tris
			if not (c.name as String).begins_with("Road") and not (c.name as String).begins_with("Edge") \
					and not (c.name as String).begins_with("Shoulder") and not (c.name as String).begins_with("Curb") \
					and not (c.name as String).begins_with("Sidewalk"):
				roadside += tris
		worst = maxi(worst, roadside)
		worst_all = maxi(worst_all, total)
	chunk.free()
	print("budget: worst roadside %d tris per chunk (all geometry %d), limit %d" % [worst, worst_all, TRI_BUDGET])
	if worst >= TRI_BUDGET:
		_fail("roadside geometry %d tris per chunk is over the %d budget" % [worst, TRI_BUDGET])

func _mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	return mesh.get_faces().size() / 3

func _tris(n: Node) -> int:
	if n is MeshInstance3D:
		return _mesh_tris((n as MeshInstance3D).mesh) if (n as MeshInstance3D).visible else 0
	if n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm == null:
			return 0
		var count := mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		return _mesh_tris(mm.mesh) * count
	return 0

func _check_districts() -> void:
	var D := B.Districts
	if D.name_at(0) != "downtown":
		_fail("the drive does not start downtown")
	var seen := {}
	var types := {}
	var steps := 0
	seed(99)
	var c := B.build_chunk(0, _cfg(2, 2, false), _cfg(2, 2, false))
	for idx in range(0, 400):
		seen[D.name_at(idx)] = true
		B.rebuild_chunk(c, idx, _cfg(2, 2, false), _cfg(2, 2, false))
		for i in B._building_slots() * 2:
			types[(c.get_node(NodePath("BuildingMesh%d" % i)) as Node).get_meta("building_type", "?")] = true
		var changed := absf(D.setback_at(idx) - D.setback_at(idx - 1)) > 0.01
		for nm in ["BoundaryStepOwn", "BoundaryStepOnc"]:
			var body: StaticBody3D = c.get_node(NodePath(nm))
			var col: CollisionShape3D = body.get_node(^"Shape")
			if col.disabled == changed:
				_fail("chunk %d %s: step wall %s but setback %s" % [idx, nm, "off" if col.disabled else "on", "changes" if changed else "does not change"])
			if changed:
				steps += 1
				var bound: StaticBody3D = c.get_node(NodePath(nm.replace("Step", "")))
				# the boundary is one box per centreline station (#37); the
				# first one ("Shape") is at the chunk start, where the step is
				var bx := absf((bound.get_node(^"Shape") as Node3D).transform.origin.x + bound.position.x)
				var half := ((col.shape as BoxShape3D).size.x) / 2.0
				var sx := absf(body.position.x)
				if bx < sx - half - 0.6 or bx > sx + half + 0.6:
					_fail("chunk %d %s: step wall %.1f..%.1f misses the boundary at %.1f" % [idx, nm, sx - half, sx + half, bx])
	c.free()
	for n in ["downtown", "residential", "strip", "industrial"]:
		if not seen.has(n):
			_fail("district %s never appears in 400 chunks" % n)
	for t in ["apartment", "shop", "office", "parking", "garage", "warehouse", "gas", "diner", "lot"]:
		if not types.has(t):
			_fail("building type %s never appears in 400 chunks" % t)
	print("districts: %s over 400 chunks, %d step walls; types %s" % [seen.keys(), steps, types.keys()])
