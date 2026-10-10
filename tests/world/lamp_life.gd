extends SceneTree

# Lamp-post life test (living world step 2, 2026-10-10): moths and a bat,
# banners, steam, windblown litter (scripts/world/lamp_life.gd).
#
# Asserts (exit code 1 on failure):
# - placement is a pure function of the chunk index: same chunk, same plan; a
#   different chunk differs; the global random sequence is not touched (the
#   road layout depends on it)
# - caps: at most one swarm and one banner per lamp, one vent per chunk;
#   shares land where the design says (moths on about half the lamps, a banner
#   on every third, a vent in about a quarter of the chunks, a few per district)
# - the four districts get four different banner slots
# - every mesh is small (budget) and its custom AABB covers where the shader
#   moves it, so it is never culled while it is on screen
# - one shared shader material per effect; the wind uniform is one number,
#   read and set through LampLife.wind() / set_wind(), clamped 0..2
# - with a window: a built chunk has the five nodes with a draw range, a
#   rebuilt chunk matches a fresh one, vents sit on the road side of their
#   pole, and NEON_LAMP_LIFE=0 (LampLife.enabled) empties every instance
#
# The instance-data checks need a real renderer (headless drops MultiMesh
# data); everything else runs headless too.
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/lamp_life.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const L := preload("res://scripts/world/lamp_life.gd")
const TRI_BUDGET := 600  # per 50 m chunk, all four effects at their caps

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _initialize() -> void:
	_check_wind()
	_check_plan()
	_check_districts()
	_check_meshes()
	if DisplayServer.get_name() != "headless":
		_check_chunks()
	else:
		print("lamp_life: headless, chunk instance checks skipped")
	print("lamp_life: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	quit(0 if fails == 0 else 1)

func _lamps(chunk: int) -> Array:
	# four poles, 12.5 m apart, alternating sides, as the builder places them
	var out := []
	for k in 4:
		var side := 1.0 if k % 2 == 0 else -1.0
		var turn := Basis() if side > 0.0 else Basis(Vector3.UP, PI)
		out.append(Transform3D(turn, Vector3(side * 9.0, 0.0, -6.25 - 12.5 * float(k))))
	return out

func _check_wind() -> void:
	L.set_wind(0.6)
	if not is_equal_approx(L.wind(), 0.6):
		_fail("wind() = %f after set_wind(0.6)" % L.wind())
	L.set_wind(9.0)
	if not is_equal_approx(L.wind(), 2.0):
		_fail("wind not clamped to 2: %f" % L.wind())
	L.set_wind(-1.0)
	if L.wind() != 0.0:
		_fail("wind not clamped to 0: %f" % L.wind())
	L.set_wind(1.25)
	for m in [L._get_banner_mat(), L._get_steam_mat(), L._get_litter_mat()]:
		var v = (m as ShaderMaterial).get_shader_parameter("wind")
		if v == null or not is_equal_approx(float(v), 1.25):
			_fail("a material did not follow set_wind: %s" % str(v))
		var names := []
		for u in (m as ShaderMaterial).shader.get_shader_uniform_list():
			names.append(u.name)
		if not "wind" in names:
			_fail("shader has no wind uniform: %s" % str(names))
	L.set_wind(L.DEFAULT_WIND)

func _check_plan() -> void:
	seed(31337)
	var expect := randi()
	seed(31337)
	var swarms := 0
	var banners := 0
	var vents := 0
	var chunks := 800
	for c in chunks:
		var p := L.plan(c, "strip", _lamps(c))
		if p.moths.size() > 4 or p.banners.size() > 4 or p.vents.size() > 1:
			_fail("chunk %d over the caps: %d / %d / %d" % [c, p.moths.size(), p.banners.size(), p.vents.size()])
		swarms += p.moths.size()
		banners += p.banners.size()
		vents += p.vents.size()
	if randi() != expect:
		_fail("plan() consumed the global random sequence")
	var swarm_share := float(swarms) / float(chunks * 4)
	if swarm_share < 0.4 or swarm_share > 0.7:
		_fail("moths on %.0f%% of lamps, expected about 55%%" % (swarm_share * 100.0))
	var banner_share := float(banners) / float(chunks * 4)
	if banner_share < 0.28 or banner_share > 0.38:
		_fail("banners on %.0f%% of lamps, expected a third" % (banner_share * 100.0))
	var vent_share := float(vents) / float(chunks)
	if vent_share < 0.15 or vent_share > 0.35:
		_fail("vents in %.0f%% of chunks, expected about 25%%" % (vent_share * 100.0))
	# same chunk, same plan; another chunk, another plan somewhere
	var a := L.plan(77, "downtown", _lamps(77))
	var b := L.plan(77, "downtown", _lamps(77))
	if str(a) != str(b):
		_fail("the plan for one chunk is not stable")
	var differs := false
	for c in range(100, 160):
		if str(L.plan(c, "downtown", _lamps(c))) != str(a):
			differs = true
	if not differs:
		_fail("every chunk got the same plan")
	# vents stand on the road side of their pole, within 9 m of it
	for c in chunks:
		for v in L.plan(c, "strip", _lamps(c)).vents:
			var cover: Transform3D = v.cover_xf
			var nearest := 1e9
			for lx in _lamps(c):
				var rel: Vector3 = cover.origin - lx.origin
				var toward: Vector3 = (lx.basis * Vector3.LEFT)
				if rel.dot(toward) > 0.0:
					nearest = minf(nearest, rel.length())
			if nearest > 9.0:
				_fail("chunk %d vent %.1f m from any pole on its road side" % [c, nearest])
				return

func _check_districts() -> void:
	var slots := {}
	for d in ["downtown", "residential", "strip", "industrial"]:
		slots[L.district_slot(d)] = d
	if slots.size() != 4:
		_fail("districts share banner slots: %s" % str(slots))
	for s in slots:
		if s < 0 or s > 3:
			_fail("banner slot %d outside 0..3" % s)
	# a few vents per 16-chunk district run
	var total := 0
	var runs := 40
	for r in runs:
		for c in range(r * 16, r * 16 + 16):
			total += L.plan(c, "residential", _lamps(c)).vents.size()
	var per_run := float(total) / float(runs)
	if per_run < 2.0 or per_run > 6.5:
		_fail("%.1f vents per district run, expected a few (2..6)" % per_run)
	# the banner carries its district in the custom data
	for c in 30:
		for bn in L.plan(c, "strip", _lamps(c)).banners:
			if int(round(bn.custom.r)) != 2:
				_fail("strip banner has slot %d" % int(round(bn.custom.r)))
				return

func _check_meshes() -> void:
	for pair in [["swarm", L._get_swarm_mesh()], ["banner", L._get_banner_mesh()], ["steam", L._get_steam_mesh()],
			["cover", L._get_cover_mesh()], ["litter", L._get_litter_mesh()]]:
		var m: ArrayMesh = pair[1]
		var arr := m.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if verts.size() == 0 or verts.size() % 3 != 0:
			_fail("%s mesh has %d vertices" % [pair[0], verts.size()])
			continue
		# no degenerate triangles (the shader never needs them)
		for t in range(0, verts.size(), 3):
			var area := (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t]).length() * 0.5
			if area < 1e-6:
				_fail("%s mesh triangle %d has no area" % [pair[0], t / 3])
				break
		if m.custom_aabb.size == Vector3.ZERO:
			_fail("%s mesh has no custom AABB" % pair[0])
	# the AABBs cover what the shaders do
	var head: Vector3 = L.HEAD
	var sw := L._get_swarm_mesh().custom_aabb
	if not sw.has_point(head) or not sw.has_point(Vector3(head.x + 1.6, 6.5, 9.0)) or not sw.has_point(Vector3(head.x - 1.6, 3.5, -9.0)):
		_fail("swarm AABB %s misses the head or the bat's path" % str(sw))
	var bn := L._get_banner_mesh().custom_aabb
	var bot := L.BANNER_TOP - L.BANNER_H
	if not bn.has_point(Vector3(L.BANNER_X - 0.3, bot, L.BANNER_W * 0.6)) or not bn.has_point(Vector3(L.BANNER_X, L.BANNER_TOP, 0.0)):
		_fail("banner AABB %s misses the cloth and its sway" % str(bn))
	if not L._get_steam_mesh().custom_aabb.has_point(Vector3(1.5, 3.0, 0.0)):
		_fail("steam AABB misses the plume")
	if not L._get_litter_mesh().custom_aabb.has_point(Vector3(12.0, 1.0, 18.0)):
		_fail("litter AABB misses the gust")
	# budget
	var tris := L.worst_case_triangles(4)
	if tris > TRI_BUDGET:
		_fail("lamp life is %d triangles per chunk at its caps, budget %d" % [tris, TRI_BUDGET])
	else:
		print("lamp_life: %d triangles per chunk at the caps (budget %d)" % [tris, TRI_BUDGET])
	# one shared material per effect
	if L._get_swarm_mat() != L._get_swarm_mat() or L._get_banner_mat() != L._get_banner_mat():
		_fail("materials are not shared")

func _cfg(o: int, n: int) -> Dictionary:
	return {"own_lanes": o, "onc_lanes": n, "barrier": n == 2}

func _check_chunks() -> void:
	L.enabled = true
	var any_moth := false
	var any_banner := false
	var any_vent := false
	for i in 24:
		var c0 := 40 + i
		var chunk: Node3D = B.build_chunk(c0, _cfg(2, 2), _cfg(2 + i % 3, 1 + i % 2))
		root.add_child(chunk)
		for n in ["LampMoths", "LampBanners", "SteamVents", "VentCovers", "WindLitter"]:
			var mmi := chunk.get_node_or_null(NodePath(n)) as MultiMeshInstance3D
			if mmi == null:
				_fail("chunk %d has no %s" % [c0, n])
				continue
			if mmi.visibility_range_end <= 0.0:
				_fail("%s has no draw range" % n)
			if mmi.material_override == null:
				_fail("%s has no material" % n)
		var moths: MultiMesh = (chunk.get_node(^"LampMoths") as MultiMeshInstance3D).multimesh
		var banners: MultiMesh = (chunk.get_node(^"LampBanners") as MultiMeshInstance3D).multimesh
		var steam: MultiMesh = (chunk.get_node(^"SteamVents") as MultiMeshInstance3D).multimesh
		var covers: MultiMesh = (chunk.get_node(^"VentCovers") as MultiMeshInstance3D).multimesh
		var lit: MultiMesh = (chunk.get_node(^"WindLitter") as MultiMeshInstance3D).multimesh
		any_moth = any_moth or moths.visible_instance_count > 0
		any_banner = any_banner or banners.visible_instance_count > 0
		any_vent = any_vent or steam.visible_instance_count > 0
		if steam.visible_instance_count != covers.visible_instance_count:
			_fail("chunk %d: %d steam puffs, %d covers" % [c0, steam.visible_instance_count, covers.visible_instance_count])
		if lit.visible_instance_count != 1:
			_fail("chunk %d: %d litter sets, expected 1" % [c0, lit.visible_instance_count])
		# banners hang on a pole: every banner transform is a lamp's
		var lamps: MultiMesh = (chunk.get_node(^"Lamps") as MultiMeshInstance3D).multimesh
		for k in banners.visible_instance_count:
			var bx := banners.get_instance_transform(k)
			var found := false
			for j in lamps.visible_instance_count:
				if lamps.get_instance_transform(j).origin.is_equal_approx(bx.origin):
					found = true
			if not found:
				_fail("chunk %d banner %d hangs on no lamp pole" % [c0, k])
		# vents are on the road side of a pole, at road height
		for k in covers.visible_instance_count:
			var cv := covers.get_instance_transform(k)
			var ok := false
			for j in lamps.visible_instance_count:
				var lx := lamps.get_instance_transform(j)
				var rel := cv.origin - lx.origin
				if rel.dot(lx.basis * Vector3.LEFT) > 0.5 and rel.length() < 9.0 and absf(rel.y) < 0.5:
					ok = true
			if not ok:
				_fail("chunk %d vent %d is not on the road side of any pole" % [c0, k])
		# the recycle path gives the same instances as a fresh build
		var again: Node3D = B.build_chunk(c0 + 900, _cfg(2, 2), _cfg(2, 2))
		root.add_child(again)
		B.rebuild_chunk(again, c0, _cfg(2, 2), _cfg(2 + i % 3, 1 + i % 2))
		var moths2: MultiMesh = (again.get_node(^"LampMoths") as MultiMeshInstance3D).multimesh
		var banners2: MultiMesh = (again.get_node(^"LampBanners") as MultiMeshInstance3D).multimesh
		var steam2: MultiMesh = (again.get_node(^"SteamVents") as MultiMeshInstance3D).multimesh
		if moths2.visible_instance_count != moths.visible_instance_count or banners2.visible_instance_count != banners.visible_instance_count \
				or steam2.visible_instance_count != steam.visible_instance_count:
			_fail("chunk %d: rebuilt placement differs from a fresh build" % c0)
		again.free()
		chunk.free()
	if not any_moth or not any_banner or not any_vent:
		_fail("24 chunks produced no moths (%s), banners (%s) or vents (%s)" % [any_moth, any_banner, any_vent])
	# the switch
	L.enabled = false
	var off: Node3D = B.build_chunk(40, _cfg(2, 2), _cfg(2, 2))
	root.add_child(off)
	for n in ["LampMoths", "LampBanners", "SteamVents", "VentCovers", "WindLitter"]:
		var mm: MultiMesh = (off.get_node(NodePath(n)) as MultiMeshInstance3D).multimesh
		if mm.visible_instance_count != 0:
			_fail("%s still shows %d with lamp life off" % [n, mm.visible_instance_count])
	off.free()
	L.enabled = true
