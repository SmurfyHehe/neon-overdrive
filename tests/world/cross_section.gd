extends SceneTree

# Cross-section table test (pavements steps 2 and 5, 2026-10-10).
#
# Asserts (exit code 1 on failure):
# - each district's chunk is built with its table row: kerb face at the lane
#   edge + shoulder, pavement walk wide, kerb top kerb_h high (the rows differ)
# - a chunk's start edge is the previous chunk's end edge across a district
#   boundary (nothing steps; the values taper inside the chunk)
# - a chunk that touches the crossing, and the one before it, are laid out
#   with the crossing's own section whatever their district
# - a freeway stretch (RoadLayout "outskirts") has no raised kerb, no
#   hydrants and no drains, and its verge collision is "Grass" and flat; a
#   city chunk's is "Kerb", also after a freeway chunk was recycled into it
# - drains: at most DRAIN_MAX per side, none inside the crossing's mouth
#   (the mouth check needs a window: headless drops MultiMesh data)
#
# Run: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/cross_section.gd

const B := preload("res://scripts/world/road_chunk_builder.gd")
const Districts := preload("res://scripts/world/districts.gd")
const CFG := {"own_lanes": 2, "onc_lanes": 2, "barrier": false}
const EPS := 0.003

var fails := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", msg)

func _verts(chunk: Node3D, n: String) -> PackedVector3Array:
	return ((chunk.get_node(NodePath(n)) as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

func _max_y(v: PackedVector3Array) -> float:
	var m := -INF
	for p in v:
		m = maxf(m, p.y)
	return m

## Largest x at the chunk's end row (z = -CHUNK_LEN) or at its start row (z = 0).
func _edge_at(v: PackedVector3Array, end: bool) -> float:
	var want := -B.CHUNK_LEN if end else 0.0
	var m := -INF
	for p in v:
		if absf(p.z - want) < 0.01:
			m = maxf(m, p.x)
	return m

func _count(chunk: Node3D, n: String) -> int:
	return (chunk.get_node(NodePath(n)) as MultiMeshInstance3D).multimesh.visible_instance_count

func _first_chunk_of(name: String) -> int:
	for run in range(1, 200):
		var c := run * Districts.RUN + 4
		if Districts.name_of_run(run) == name:
			return c
	return -1

func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	Junction.enabled = false
	RoadFrame.layout = null

	# --- each district's row
	var seen := {}
	for name in ["downtown", "residential", "strip", "industrial"]:
		var c := _first_chunk_of(name)
		_check(c > 0, "no %s chunk found" % name)
		if c < 0:
			continue
		var row: Dictionary = Districts.CROSS[name]
		var chunk: Node3D = B.build_chunk(c, CFG, CFG)
		holder.add_child(chunk)
		var kerb_x := B._lane_w(2) + float(row.shoulder)
		var walk := _verts(chunk, "SidewalkOwn")
		var want_end := kerb_x + B.CURB_W + float(row.walk)
		_check(absf(_edge_at(walk, true) - want_end) < EPS, "%s: pavement ends at %.2f, expected %.2f" % [name, _edge_at(walk, true), want_end])
		var kerb := _verts(chunk, "CurbOwn")
		_check(absf(_max_y(kerb) - float(row.kerb_h)) < EPS, "%s: kerb top %.3f, expected %.3f" % [name, _max_y(kerb), float(row.kerb_h)])
		var sh := _edge_at(_verts(chunk, "ShoulderOwn"), true)
		_check(absf(sh - (kerb_x - B.GUTTER_W)) < EPS, "%s: shoulder ends at %.2f, expected %.2f" % [name, sh, kerb_x - B.GUTTER_W])
		seen["%s/%s/%s" % [row.walk, row.shoulder, row.kerb_h]] = true
		holder.remove_child(chunk)
		chunk.free()
	_check(seen.size() == 4, "the four districts do not have four different sections (%d)" % seen.size())

	# --- continuity across a district boundary
	var boundary := -1
	for c in range(1, 400):
		if Districts.name_at(c) != Districts.name_at(c - 1) and not Junction.touches(c):
			var a := Districts.cross_at(c - 1)
			var b := Districts.cross_at(c)
			if absf(float(a.walk) - float(b.walk)) > 0.2 and absf(float(a.shoulder) - float(b.shoulder)) > 0.2:
				boundary = c
				break
	_check(boundary > 0, "no district boundary with both widths changing")
	if boundary > 0:
		var prev: Node3D = B.build_chunk(boundary - 1, CFG, CFG)
		var cur: Node3D = B.build_chunk(boundary, CFG, CFG)
		holder.add_child(prev)
		holder.add_child(cur)
		var pe := _edge_at(_verts(prev, "SidewalkOwn"), true)
		var ce := _edge_at(_verts(cur, "SidewalkOwn"), false)
		_check(absf(pe - ce) < EPS, "pavement steps at the district boundary: %.2f -> %.2f" % [pe, ce])
		pe = _edge_at(_verts(prev, "CurbOwn"), true)
		ce = _edge_at(_verts(cur, "CurbOwn"), false)
		_check(absf(pe - ce) < EPS, "kerb face steps at the district boundary: %.2f -> %.2f" % [pe, ce])
		holder.remove_child(prev)
		holder.remove_child(cur)
		prev.free()
		cur.free()

	# --- the crossing's own section
	Junction.enabled = true
	for c in [10, 11, 12]:
		var row := Districts.cross_at(c)
		_check(absf(float(row.walk) - 2.2) < 1e-6 and absf(float(row.shoulder) - 1.4) < 1e-6, "chunk %d at the crossing is %s / %s" % [c, str(row.walk), str(row.shoulder)])
	_check(absf(float(Districts.cross_at(13).walk) - float(Districts.CROSS["downtown"].walk)) < 1e-6, "chunk 13 still holds the crossing's section")
	var jc: Node3D = B.build_chunk(12, CFG, CFG)
	holder.add_child(jc)
	var want_start := B._lane_w(2) + 1.4 + B.CURB_W + 2.2
	_check(absf(_edge_at(_verts(jc, "SidewalkOwn"), false) - want_start) < EPS, "chunk 12 starts at %.2f, expected the crossing's %.2f" % [_edge_at(_verts(jc, "SidewalkOwn"), false), want_start])
	# Headless drops MultiMesh instance data, so the positions are only read in a window.
	if DisplayServer.get_name() != "headless":
		var dm: MultiMesh = (jc.get_node(^"Drains") as MultiMeshInstance3D).multimesh
		for i in dm.visible_instance_count:
			var z := dm.get_instance_transform(i).origin.z
			_check(absf(z - Junction.local_centre(12)) > Junction.MOUTH_HALF, "drain at z=%.1f inside the crossing's mouth" % z)
	holder.remove_child(jc)
	jc.free()
	Junction.enabled = false

	# --- drains: a few per chunk side, bounded
	var total := 0
	for c in range(20, 60):
		var ch: Node3D = B.build_chunk(c, CFG, CFG)
		holder.add_child(ch)
		var n := _count(ch, "Drains")
		_check(n <= B.DRAIN_MAX * 2, "chunk %d: %d drains" % [c, n])
		total += n
		holder.remove_child(ch)
		ch.free()
	_check(total > 10, "only %d drains over 40 chunks" % total)

	# --- the freeway: no kerb, a verge, no props
	RoadFrame.layout = RoadLayout.new(20261010, null, 1.0)
	var fc := -1
	for c in range(4, 4000):
		if Districts.is_freeway(c - 1) and Districts.is_freeway(c) and Districts.is_freeway(c + 1):
			fc = c
			break
	_check(fc > 0, "no freeway stretch in the first 4000 chunks")
	if fc > 0:
		var chunk: Node3D = B.build_chunk(fc, CFG, CFG)
		holder.add_child(chunk)
		await physics_frame
		await physics_frame
		_check(_max_y(_verts(chunk, "CurbOwn")) < B.FLAT_BELOW, "freeway kerb is %.3f high" % _max_y(_verts(chunk, "CurbOwn")))
		_check(_max_y(_verts(chunk, "SidewalkOwn")) < B.FLAT_BELOW, "freeway verge is %.3f high" % _max_y(_verts(chunk, "SidewalkOwn")))
		_check(_count(chunk, "Hydrants") == 0, "hydrants on a freeway")
		_check(_count(chunk, "Drains") == 0, "drains on a freeway")
		var col: Node = chunk.get_node(^"SidewalkColOwn")
		_check(col.is_in_group("Grass") and not col.is_in_group("Kerb"), "freeway verge collision is not Grass")
		var sp := chunk.get_world_3d().direct_space_state
		var x := B._lane_w(2) + 3.0 + B.CURB_W + 0.6
		var from := chunk.to_global(Vector3(x, 2.0, -25.0))
		var hit := sp.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0))
		_check(not hit.is_empty() and chunk.to_local(hit.position).y < 0.03, "freeway verge collision top is not flat")
		holder.remove_child(chunk)
		chunk.free()
		# a freeway chunk recycled into a city one gets its group back
		var re: Node3D = B.build_chunk(fc, CFG, CFG)
		holder.add_child(re)
		RoadFrame.layout = null
		B.rebuild_chunk(re, 20, CFG, CFG)
		var rcol: Node = re.get_node(^"SidewalkColOwn")
		_check(rcol.is_in_group("Kerb") and not rcol.is_in_group("Grass"), "a recycled freeway chunk keeps the Grass group")
		holder.remove_child(re)
		re.free()
	var city: Node3D = B.build_chunk(20, CFG, CFG)
	holder.add_child(city)
	_check((city.get_node(^"SidewalkColOwn") as Node).is_in_group("Kerb"), "a city chunk's sidewalk collision is not Kerb")

	print("cross_section: %d checks, %d failures" % [checks, fails])
	quit(1 if fails > 0 else 0)
