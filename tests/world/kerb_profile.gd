extends SceneTree

# Kerb and pavement test (pavements step 1, 2026-10-10).
#
# Asserts (exit code 1 on failure):
# - the kerb strip is raised: its top is at KERB_H and its foot is in the
#   gutter (below the shoulder), with a vertical face on the road side
# - the gutter strip dips GUTTER_DIP from the shoulder's edge to the kerb foot
# - the pavement sits at KERB_H and is SIDEWALK_W (Districts.walk_at) wide
# - a chunk in the strip district (every building has a car-park entrance)
#   has dropped kerb rows at DROP_MIN of the height, and the pavement and its
#   Dirt collision drop with it; a downtown chunk with no parking has none
# - with the crossing on, the kerb through its mouth is dropped and the rows
#   just outside the mouth are painted yellow; with it off, no row is yellow
#   except beside a hydrant, and at most one hydrant stands per side
# - a rebuilt (recycled) chunk's kerb matches a fresh one vertex for vertex
#
# Run (headless is fine -- vertex data and collision only):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/kerb_profile.gd

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

func _colors(chunk: Node3D, n: String) -> PackedColorArray:
	var arr: Array = ((chunk.get_node(NodePath(n)) as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
	return arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()

## Vertex colours come back 8-bit from the mesh, so compare loosely.
func _is_paint(c: Color) -> bool:
	return absf(c.r - B.KERB_PAINT.r) < 0.02 and absf(c.g - B.KERB_PAINT.g) < 0.02 and absf(c.b - B.KERB_PAINT.b) < 0.02

func _min_y(v: PackedVector3Array) -> float:
	var m := INF
	for p in v:
		m = minf(m, p.y)
	return m

func _max_y(v: PackedVector3Array) -> float:
	var m := -INF
	for p in v:
		m = maxf(m, p.y)
	return m

## Kerb-top height per row: {z (to the cm): max y of the vertices there}.
func _top_heights(v: PackedVector3Array) -> Dictionary:
	var tops := {}
	for p in v:
		var key := roundi(p.z * 100.0)
		tops[key] = maxf(float(tops.get(key, -INF)), p.y)
	return tops

## The row with the lowest top: [z, top].
func _lowest(tops: Dictionary) -> Array:
	var low := INF
	var low_z := 0.0
	for key in tops:
		if tops[key] < low:
			low = tops[key]
			low_z = float(key) / 100.0
	return [low_z, low]

func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var kerb_x := B._lane_w(2) + B.SHOULDER_W
	Junction.enabled = false

	# --- a downtown chunk with no crossing: raised kerb, gutter, pavement
	var c0: Node3D = B.build_chunk(1, CFG, CFG)
	holder.add_child(c0)
	var kerb := _verts(c0, "CurbOwn")
	_check(absf(_max_y(kerb) - B.KERB_H) < EPS, "kerb top at %.3f, expected %.3f" % [_max_y(kerb), B.KERB_H])
	_check(_min_y(kerb) < -0.01, "kerb foot at %.3f, expected below the shoulder" % _min_y(kerb))
	var face := 0
	for p in kerb:
		if absf(p.x - kerb_x) < 1e-4 and p.y > 0.05:
			face += 1
	_check(face > 0, "no vertical kerb face at x=%.2f" % kerb_x)
	var gutter := _verts(c0, "GutterOwn")
	_check(absf(_min_y(gutter) + B.GUTTER_DIP) < EPS and absf(_max_y(gutter)) < EPS, "gutter spans %.3f..%.3f, expected %.3f..0" % [_min_y(gutter), _max_y(gutter), -B.GUTTER_DIP])
	var walk := _verts(c0, "SidewalkOwn")
	var walk_w := 0.0
	for p in walk:
		walk_w = maxf(walk_w, p.x - (kerb_x + B.CURB_W))
	_check(absf(walk_w - Districts.walk_at(1)) < EPS, "pavement %.2f wide, expected %.2f" % [walk_w, Districts.walk_at(1)])
	_check(absf(_max_y(walk) - B.KERB_H) < EPS, "pavement top at %.3f" % _max_y(walk))
	var hyd: MultiMesh = (c0.get_node(^"Hydrants") as MultiMeshInstance3D).multimesh
	_check(hyd.visible_instance_count <= 2, "%d hydrants on one chunk" % hyd.visible_instance_count)
	var onc := _verts(c0, "CurbOnc")
	_check(absf(_max_y(onc) - B.KERB_H) < EPS and _min_y(onc) < -0.01, "oncoming kerb spans %.3f..%.3f" % [_min_y(onc), _max_y(onc)])

	# --- the strip district: every building front gets a dropped kerb
	var strip_run := 1
	while Districts.name_of_run(strip_run) != "strip" and strip_run < 60:
		strip_run += 1
	_check(Districts.name_of_run(strip_run) == "strip", "no strip district in the first 60 runs")
	var si := strip_run * Districts.RUN + 1
	var dropped := 0
	var any_building := false
	for side in ["Own", "Onc"]:
		var c1: Node3D = B.build_chunk(si, CFG, CFG)
		holder.add_child(c1)
		var tops := _top_heights(_verts(c1, "Curb" + side))
		var walk_tops := _top_heights(_verts(c1, "Sidewalk" + side))
		var lowest := _lowest(tops)
		var low_z: float = lowest[0]
		var low: float = lowest[1]
		for i in 2:
			var mi := c1.get_node(NodePath("BuildingMesh%d" % (i * 2 + (0 if side == "Own" else 1)))) as MeshInstance3D
			if mi.visible:
				any_building = true
		if low < B.KERB_H - EPS:
			dropped += 1
			_check(absf(low - B.KERB_H * B.DROP_MIN) < EPS, "%s dropped kerb bottoms at %.3f, expected %.3f" % [side, low, B.KERB_H * B.DROP_MIN])
			var wkey := roundi(low_z * 100.0)
			_check(walk_tops.has(wkey) and absf(float(walk_tops[wkey]) - low) < EPS, "%s pavement at the drop (z=%.2f) is %s, kerb %.3f" % [side, low_z, str(walk_tops.get(wkey)), low])
		# the collision top follows: cast down at the lowest row
		await physics_frame
		await physics_frame
		var sx := 1.0 if side == "Own" else -1.0
		var space := c1.get_world_3d().direct_space_state
		var z := low_z
		var x := (kerb_x + B.CURB_W + 1.0) * sx
		var from := c1.to_global(Vector3(x, 2.0, z))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0))
		_check(not hit.is_empty(), "%s: no Dirt hit over the pavement at z=%.1f" % [side, z])
		if not hit.is_empty():
			var top_y: float = c1.to_local(hit.position).y
			var want := 0.15 * maxf(low / B.KERB_H, B.DROP_MIN)
			_check(absf(top_y - want) < 0.01, "%s collision top %.3f at the drop, expected %.3f" % [side, top_y, want])
		holder.remove_child(c1)
		c1.free()
	_check(dropped > 0 or not any_building, "strip chunk %d has buildings but no dropped kerb" % si)

	# --- no yellow without a crossing, except beside a hydrant
	var cols := _colors(c0, "CurbOwn")
	var yellow := 0
	for c in cols:
		if _is_paint(c):
			yellow += 1
	_check(cols.size() > 0, "kerb has no vertex colours")
	if hyd.visible_instance_count == 0:
		_check(yellow == 0, "%d yellow kerb vertices with no crossing and no hydrant" % yellow)

	# --- the crossing: dropped through the mouth, yellow just outside it
	Junction.enabled = true
	var cj: Node3D = B.build_chunk(12, CFG, CFG)  # centre at this chunk's start
	holder.add_child(cj)
	var jtops := _top_heights(_verts(cj, "CurbOwn"))
	_check(jtops.has(0) and absf(float(jtops[0]) - B.KERB_H * B.DROP_MIN) < EPS, "kerb at the crossing's centre is %s high" % str(jtops.get(0)))
	var jcols := _colors(cj, "CurbOwn")
	var jverts := _verts(cj, "CurbOwn")
	var yellow_rows := {}
	for i in jverts.size():
		if _is_paint(jcols[i]):
			yellow_rows[roundi(jverts[i].z * 100.0)] = true
	_check(yellow_rows.size() >= 2, "only %d yellow kerb rows beside the crossing" % yellow_rows.size())
	for r in yellow_rows:
		var zr := float(r) / 100.0
		_check(absf(zr) >= Junction.MOUTH_HALF - 1.0 and absf(zr) <= Junction.MOUTH_HALF + B.PAINT_REACH + 1.0, "yellow row at z=%.1f, outside the paint band" % zr)
	Junction.enabled = false

	# --- recycling: a rebuilt chunk matches a fresh one (the buildings take
	# their draws from the global RNG, so both builds start it from one seed)
	seed(7)
	var fresh: Node3D = B.build_chunk(3, CFG, CFG)
	holder.add_child(fresh)
	seed(7)
	B.rebuild_chunk(cj, 3, CFG, CFG)
	var a := _verts(fresh, "CurbOwn")
	var b := _verts(cj, "CurbOwn")
	var same := a.size() == b.size()
	if same:
		for i in a.size():
			if not a[i].is_equal_approx(b[i]):
				same = false
				break
	_check(same, "a recycled chunk's kerb differs from a fresh build")
	_check(_colors(fresh, "CurbOwn") == _colors(cj, "CurbOwn"), "a recycled chunk's kerb paint differs from a fresh build")

	print("kerb_profile: %d checks, %d failures" % [checks, fails])
	quit(1 if fails > 0 else 0)
