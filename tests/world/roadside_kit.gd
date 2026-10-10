extends SceneTree

# Roadside kit test (RoadsideKit, 2026-10-09): builds chunks across every
# district and checks, from the chunk's placement record (headless Godot
# returns identity from MultiMesh getters, so the record is the source):
# - every piece stands in its band: hydrants and bins on the sidewalk,
#   cones and jersey barriers on the shoulder, the guardrail on the kerb,
#   dumpsters in a lot the car can enter (behind the sidewalk, in front of
#   the lot wall), all inside the chunk and clear of the crossing's mouth;
# - pieces in the same band never overlap along the road;
# - the collision bodies match the record: one enabled box per rail piece,
#   dumpster and jersey piece, sized to it, nothing else enabled;
# - the table holds: guardrail only in industrial, dumpsters only where the
#   lot is deep (strip, industrial), hydrants and bins where the table says,
#   and work zones appear somewhere;
# - a chunk built twice gives the same record (pool rebuilds match), and the
#   kit never touches the global random sequence (the road layout);
# - density 0 draws nothing and enables no collision;
# - meshes: one surface each, unit normals that match the winding, the one
#   material below the glow threshold (no neon).
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/roadside_kit.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const Kit := preload("res://scripts/world/roadside_kit.gd")
const Districts := preload("res://scripts/world/districts.gd")
const EPS := 0.01

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _initialize() -> void:
	Kit.density = 1.0
	Kit.force = {}
	var per_district := {}
	for c in range(0, 1200):
		var d := Districts.name_at(c)
		if not per_district.has(d):
			per_district[d] = []
		if per_district[d].size() < 32:
			per_district[d].append(c)
	for d in Kit.BY_DISTRICT:
		if not per_district.has(d):
			_fail("no chunk of district %s in the first 1200" % d)
	var totals := {}
	var cases := 0
	for d in per_district:
		totals[d] = {}
		for k in Kit.KINDS:
			totals[d][k] = 0
		for c in per_district[d]:
			var prev := {"own_lanes": 3, "onc_lanes": 2, "barrier": true}
			var cfg := {"own_lanes": 2 if c % 3 == 0 else 3, "onc_lanes": 2, "barrier": true}
			# The buildings take their footprints from the global sequence
			# (game.gd seeds it per chunk), so both builds start from one seed.
			seed(c)
			var chunk: Node3D = B.build_chunk(c, prev, cfg)
			root.add_child(chunk)
			var rec: Array = chunk.get_meta("kit")
			_check_record(chunk, c, prev, cfg, rec, "%s chunk %d" % [d, c])
			for r in rec:
				totals[d][r.kind] = int(totals[d][r.kind]) + 1
			# the same chunk rebuilt into another pool slot: the same record
			var other: Node3D = B.build_chunk(c + 7, prev, cfg)
			root.add_child(other)
			seed(c)
			B.rebuild_chunk(other, c, prev, cfg)
			if str(other.get_meta("kit")) != str(rec):
				_fail("%s: rebuilt record differs" % c)
			chunk.free()
			other.free()
			cases += 1
	_check_table(totals)
	_check_global_rng()
	_check_density_zero()
	_check_meshes()
	print("roadside_kit: %d chunks, %s" % [cases, "PASS" if fails == 0 else "%d failure(s)" % fails])
	quit(0 if fails == 0 else 1)

func _edges(prev: Dictionary, cfg: Dictionary, side: int, t: float) -> Dictionary:
	var key := "own_lanes" if side == 1 else "onc_lanes"
	var road: float = lerpf(B._lane_w(prev[key]), B._lane_w(cfg[key]), t)
	var curb_in := road + B.SHOULDER_W
	var curb_out := curb_in + B.CURB_W
	return {"road": road, "curb_in": curb_in, "curb_out": curb_out, "walk": curb_out + B.SIDEWALK_W}

func _band(kind: String) -> String:
	match kind:
		Kit.HYDRANT, Kit.BIN:
			return "sidewalk"
		Kit.CONE, Kit.JERSEY:
			return "shoulder"
		Kit.RAIL:
			return "curb"
	return "lot"

func _check_record(chunk: Node3D, c: int, prev: Dictionary, cfg: Dictionary, rec: Array, label: String) -> void:
	var setback := Districts.setback_at(c)
	var spans := {}  # side+band -> [[z_hi, z_lo]]
	for r in rec:
		var side := int(r.side)
		var x := float(r.x)
		var z := float(r.z)
		var kind := String(r.kind)
		if z > EPS or z < -B.CHUNK_LEN - EPS:
			_fail("%s: %s at z %.2f is outside the chunk" % [label, kind, z])
		if Junction.in_mouth(c, z):
			_fail("%s: %s at z %.2f stands in the crossing's mouth" % [label, kind, z])
		var e := _edges(prev, cfg, side, -z / B.CHUNK_LEN)
		var half := float(r.len) / 2.0
		match _band(kind):
			"sidewalk":
				if x - 0.3 < e.curb_out - EPS or x + 0.3 > e.walk + EPS:
					_fail("%s: %s at |x| %.2f is off the sidewalk %.2f..%.2f" % [label, kind, x, e.curb_out, e.walk])
			"shoulder":
				var w := Kit.JERSEY_BASE / 2.0 if kind == Kit.JERSEY else Kit.CONE_BASE / 2.0
				if x - w < e.road - EPS or x + w > e.curb_in + EPS:
					_fail("%s: %s at |x| %.2f is off the shoulder %.2f..%.2f" % [label, kind, x, e.road, e.curb_in])
			"curb":
				if absf(x - e.curb_in) > EPS:
					_fail("%s: rail face at |x| %.2f, kerb at %.2f" % [label, x, e.curb_in])
			"lot":
				var back: float = float(e.walk) + B.BUILDING_GAP + setback
				var dz := Kit.DUMPSTER_SIZE.z / 2.0
				if x - dz < e.walk - EPS or x + dz > back + EPS:
					_fail("%s: dumpster at |x| %.2f is not in the lot %.2f..%.2f" % [label, x, e.walk, back])
		var key := "%d %s" % [side, _band(kind)]
		if not spans.has(key):
			spans[key] = []
		spans[key].append([z + half, z - half, kind])
	for key in spans:
		var list: Array = spans[key]
		list.sort_custom(func(a, b): return a[0] > b[0])
		for i in list.size() - 1:
			if list[i + 1][0] > list[i][1] + EPS:
				_fail("%s: %s overlaps %s on %s (z %.2f vs %.2f)" % [label, list[i + 1][2], list[i][2], key, list[i + 1][0], list[i][1]])
	# collision mirrors the record
	var want_metal := 0
	var want_concrete := 0
	for r in rec:
		if r.kind == Kit.RAIL or r.kind == Kit.DUMPSTER:
			want_metal += 1
		elif r.kind == Kit.JERSEY:
			want_concrete += 1
	_check_body(chunk.get_node(^"KitColMetal"), want_metal, "%s metal" % label)
	_check_body(chunk.get_node(^"KitColConcrete"), want_concrete, "%s concrete" % label)
	var metal := chunk.get_node(^"KitColMetal") as StaticBody3D
	if String(metal.get_meta(&"audio_surface", "")) != "metal":
		_fail("%s: the rail and dumpster body does not sound like metal" % label)
	if metal.collision_layer != 1 << (CarSpec.WALL_LAYER - 1):
		_fail("%s: kit collision is not on the wall layer" % label)
	for kind in Kit.KINDS:
		var mmi := chunk.get_node(NodePath("Kit_" + kind)) as MultiMeshInstance3D
		var n := 0
		for r in rec:
			if r.kind == kind:
				n += 1
		if mmi.multimesh.visible_instance_count != n or mmi.visible != (n > 0):
			_fail("%s: %s shows %d of %d" % [label, kind, mmi.multimesh.visible_instance_count, n])

func _check_body(body: Node, want: int, label: String) -> void:
	var on := 0
	for c in body.get_children():
		if not (c as CollisionShape3D).disabled:
			on += 1
	if on != want:
		_fail("%s: %d shapes enabled, record has %d" % [label, on, want])

func _check_table(totals: Dictionary) -> void:
	for d in totals:
		var t: Dictionary = totals[d]
		var spec: Dictionary = Kit.BY_DISTRICT[d]
		print("%-12s hydrant %3d bin %3d dumpster %3d cone %3d jersey %3d rail %3d" % [d, t.hydrant, t.bin, t.dumpster, t.cone, t.jersey, t.rail])
		if float(spec.rail) == 0.0 and int(t.rail) > 0:
			_fail("%s has a guardrail; its table says none" % d)
		if float(spec.rail) > 0.0 and int(t.rail) == 0:
			_fail("%s has no guardrail over 32 chunks" % d)
		if float(spec.dumpster) == 0.0 and int(t.dumpster) > 0:
			_fail("%s has a dumpster; its table says none" % d)
		if float(spec.dumpster) > 0.0 and int(t.dumpster) == 0:
			_fail("%s has no dumpster over 32 chunks" % d)
		if float(spec.hydrant) >= 0.4 and int(t.hydrant) == 0:
			_fail("%s has no hydrant over 32 chunks" % d)
		if float(spec.bin) >= 0.4 and int(t.bin) == 0:
			_fail("%s has no bin over 32 chunks" % d)
		if int(t.cone) != int(t.jersey) * Kit.CONES_IN_TAPER / Kit.JERSEY_RUN:
			_fail("%s: %d cones for %d jersey pieces; a work zone is %d cones and %d pieces" % [d, t.cone, t.jersey, Kit.CONES_IN_TAPER, Kit.JERSEY_RUN])
	var zones := 0
	for d in totals:
		zones += int(totals[d].jersey)
	if zones == 0:
		_fail("no work zone in 128 chunks")

## The kit must not take from the global random sequence: the road layout
## (lane counts, building footprints) is drawn from it.
func _check_global_rng() -> void:
	var cfg := {"own_lanes": 3, "onc_lanes": 2, "barrier": true}
	seed(777)
	var a: Node3D = B.build_chunk(40, cfg, cfg)
	var after_a := randf()
	a.free()
	Kit.density = 0.0
	seed(777)
	var b: Node3D = B.build_chunk(40, cfg, cfg)
	var after_b := randf()
	b.free()
	Kit.density = 1.0
	if after_a != after_b:
		_fail("the kit moved the global random sequence (%f vs %f)" % [after_a, after_b])

func _check_density_zero() -> void:
	Kit.density = 0.0
	var cfg := {"own_lanes": 3, "onc_lanes": 2, "barrier": true}
	for c in [0, 20, 40, 60, 80]:
		var chunk: Node3D = B.build_chunk(c, cfg, cfg)
		if not (chunk.get_meta("kit") as Array).is_empty():
			_fail("density 0: chunk %d still has kit" % c)
		_check_body(chunk.get_node(^"KitColMetal"), 0, "density 0 chunk %d metal" % c)
		_check_body(chunk.get_node(^"KitColConcrete"), 0, "density 0 chunk %d concrete" % c)
		for kind in Kit.KINDS:
			if (chunk.get_node(NodePath("Kit_" + kind)) as MultiMeshInstance3D).visible:
				_fail("density 0: chunk %d shows %s" % [c, kind])
		chunk.free()
	Kit.density = 1.0

func _check_meshes() -> void:
	var m := Kit.material()
	if Kit.SELF_LIGHT >= 1.0 or float(m.get_shader_parameter("self_light")) >= 1.0:
		_fail("kit material glows (self-light %.2f >= glow threshold 1.0): neon is out" % Kit.SELF_LIGHT)
	if not m.shader.code.contains("ALBEDO = COLOR.rgb"):
		_fail("kit material ignores vertex colours (every kind would be white)")
	for kind in Kit.KINDS:
		var mesh: ArrayMesh = Kit.mesh(kind)
		if mesh.get_surface_count() != 1:
			_fail("%s mesh has %d surfaces, expected 1 (one draw call)" % [kind, mesh.get_surface_count()])
			continue
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		if colors.size() != verts.size():
			_fail("%s mesh has no vertex colours" % kind)
		var bad := 0
		var lowest := INF
		for t in verts.size() / 3:
			var a := verts[t * 3]
			var b := verts[t * 3 + 1]
			var c := verts[t * 3 + 2]
			lowest = minf(lowest, minf(a.y, minf(b.y, c.y)))
			var face := (c - a).cross(b - a)  # outward normal of a clockwise triangle
			if face.length() < 1e-7:
				bad += 1
				continue
			for k in 3:
				var n := normals[t * 3 + k]
				if absf(n.length() - 1.0) > 1e-3 or n.dot(face.normalized()) < 0.9:
					bad += 1
					break
		if bad > 0:
			_fail("%s mesh: %d triangles with zero area or a normal against the winding" % [kind, bad])
		if absf(lowest) > 0.001:
			_fail("%s mesh: lowest point at y %.3f, expected 0 (its base sits on the ground)" % [kind, lowest])
	print("meshes: %d kinds checked" % Kit.KINDS.size())
