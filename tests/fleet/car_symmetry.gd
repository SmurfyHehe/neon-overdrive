extends SceneTree

# Left/right symmetry of every car body (Roy, 2026-10-10: "make sure the cars
# are symmetrical"), headless. Mirrors each body (the P1 coupe and every
# sheet kind and build: player, traffic, cop) across the car's centre plane
# and prints one row per car:
# - before: vertex positions whose surface normals differ from their mirror
#   twin's by more than NORMAL_DEG, on the sheet's own triangles (how the car
#   was lit before CarPaint.mirrored())
# - after: the same count on the mesh the game draws now
# - one-sided: vertex positions with no mirror twin within TWIN_MM (parts
#   that exist on one side: an exhaust, a spotlight, an aerial), and the
#   largest distance from one of them to the mirrored mesh, mm
# - colour: twinned positions carrying a sheet colour their twin lacks
# Fails (exit code 1) when a car still has more than MAX_UNEVEN positions lit
# differently left and right, unless it is in KNOWN (with a cap of its own),
# or when mirroring made a car worse than its sheet. One-sided parts and
# colours are reported, not failed.
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/fleet/car_symmetry.gd

const TWIN_MM := 1.5
const NORMAL_DEG := 2.0
const MAX_UNEVEN := 20
## Cars that stay lopsided, why, and how many uneven positions they may have.
const KNOWN := {
	"p0_beater": ["patched and dented on one side by design (bondo, rust, primer panels)", 100],
	"p17_work_pickup": ["a one-sided part on the right of the bed", 40],
	"c2_patrolsuv": ["its black trim differs left to right, so the trim is not mirrored", 110],
}

var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _key(p: Vector3) -> Vector3i:
	return Vector3i((p * 1000.0).round())

## Positions whose normals have no mirrored match among their twin's.
func _uneven(at: Dictionary) -> int:
	var n := 0
	for k: Vector3i in at:
		var m := Vector3i(-k.x, k.y, k.z)
		if not at.has(m):
			continue
		var twin: PackedVector3Array = at[m]
		for nrm in (at[k] as PackedVector3Array):
			var want := Vector3(-nrm.x, nrm.y, nrm.z)
			var best := 180.0
			for tn in twin:
				best = minf(best, rad_to_deg(want.angle_to(tn)))
			if best > NORMAL_DEG:
				n += 1
				break
	return n

## The sheet as it was drawn before: one normal per triangle.
func _before(data: GDScript, tris: PackedVector3Array, mats: PackedByteArray) -> int:
	var at := {}
	for t in mats.size():
		if data.NAMES[mats[t]] in data.EMISSIVE:
			continue
		var n := (tris[t * 3 + 1] - tris[t * 3]).cross(tris[t * 3 + 2] - tris[t * 3])
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		for k in 3:
			var key := _key(tris[t * 3 + k])
			if not at.has(key):
				at[key] = PackedVector3Array()
			at[key].append(n)
	return _uneven(at)

## Sheet materials CarPaint.mirrored() left alone on this sheet (their left
## and right halves differ).
func _left_alone(data: GDScript, tris: PackedVector3Array, mats: PackedByteArray) -> String:
	var names := []
	for m: int in CarPaint.mirrored(tris, mats)[2]:
		names.append(data.NAMES[m])
	names.sort()
	return ", ".join(names)

func _report(who: String, mesh: ArrayMesh, before: int, left_alone: String) -> void:
	var at := {}      # position -> normals (lamps left out: they are unshaded)
	var cols := {}    # position -> colours
	for i in mesh.get_surface_count():
		var sname := mesh.surface_get_name(i)
		if sname == "flare":
			continue
		var arrays := mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for v in verts.size():
			var k := _key(verts[v])
			if not cols.has(k):
				cols[k] = PackedColorArray()
				at[k] = PackedVector3Array()
			if sname != "glow":
				at[k].append(normals[v])
			var c := Color(colors[v], 1.0)
			if not (c in (cols[k] as PackedColorArray)):
				cols[k].append(c)
	var after := _uneven(at)
	var keys: Array = cols.keys()
	var colour_off := 0
	var gap := 0.0
	var no_twin := 0
	for k: Vector3i in keys:
		var m := Vector3i(-k.x, k.y, k.z)
		if cols.has(m):
			for c in (cols[k] as PackedColorArray):
				if not (c in (cols[m] as PackedColorArray)):
					colour_off += 1
					break
			continue
		var best := INF
		for o: Vector3i in keys:
			best = minf(best, Vector3(float(-o.x - k.x), float(o.y - k.y), float(o.z - k.z)).length_squared())
		var mm := sqrt(best)
		if mm > TWIN_MM:
			no_twin += 1
		gap = maxf(gap, mm)
	print("%-26s lit unevenly: before %3d  after %3d   one-sided %3d of %4d (up to %3.0f mm)   colour %2d" % [who, before, after, no_twin, keys.size(), gap, colour_off])
	var kind := who.get_slice("/", 0)
	var cap: int = KNOWN[kind][1] if KNOWN.has(kind) else MAX_UNEVEN
	if after > cap:
		fails += 1
		printerr("FAIL: %s is lit differently left and right at %d positions (cap %d)" % [who, after, cap])
	elif KNOWN.has(kind) and after > MAX_UNEVEN:
		print("    known: ", KNOWN[kind][0])
	if left_alone != "":
		print("    not mirrored (the two sides differ): ", left_alone)
	if after > before:
		fails += 1
		printerr("FAIL: %s got less symmetrical than its sheet (%d -> %d)" % [who, before, after])

func _run() -> void:
	var d1: GDScript = P1CoupeBuilder.Data
	var t1 := P1CoupeBuilder.decode_points(d1.b64(d1.BODY_POS))
	var m1 := Marshalls.base64_to_raw(d1.b64(d1.BODY_MAT))
	_report("p1_coupe", P1CoupeBuilder._get_body_mesh(), _before(d1, t1, m1), _left_alone(d1, t1, m1))
	for kind: String in NpcCarBuilder.KINDS:
		var data: GDScript = NpcCarBuilder.data_of(kind)
		for build: String in NpcCarBuilder.builds(kind):
			var b: Dictionary = data.BUILDS[build]
			var tris := P1CoupeBuilder.decode_points(data.b64(b.body_pos))
			var mats := Marshalls.base64_to_raw(b.body_mat)
			_report("%s/%s" % [kind, build], NpcCarBuilder.body_mesh(kind, build), _before(data, tris, mats), _left_alone(data, tris, mats))
	if fails == 0:
		print("car_symmetry: PASS")
	else:
		print("car_symmetry: FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
