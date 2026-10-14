extends SceneTree

# Dash bobble figures (interiors B1, 2026-10-11). Headless and silent, no scene:
# - the catalogue: 29 figures plus none; every id builds, has a display name,
#   a way to get it and a spring record; under MAX_TRIS triangles; one surface
#   (one draw call); about 7 cm tall; a head (weighted vertices) that bobs
# - silhouettes: the front and side views rasterised at 7 cm (3 mm cells); no
#   two figures may share a silhouette (of the cells either one fills, at
#   least MIN_DIFF are filled by one and not the other)
# - the house style: the head about 45% of the height (the mascot, the cone,
#   the dog, the bird, the flower and the surfer are their own shapes and are
#   excused), a round base of the shared radius on every figure
# - springs: each figure's record drives BobbleHead's spring; the tiki moves
#   less than Ledger for the same jolt; the hula dancer's head is still and
#   her skirt swings
# - clearance, every player car: at the car's slot and scale, at the largest
#   lean in eight directions, no vertex of any figure comes within CLEAR_M of
#   the windscreen glass, the rear-view mirror housing or the A-pillar, and
#   the steering wheel's rim is far away (it is on the driver's side)
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/bobble_figures.gd

const MAX_TRIS := 600
## The tallest point of any figure (m): the beater's and the kei's glass sit
## about 8 cm over their dash tops.
const MAX_HEIGHT := 0.077
const MIN_DIFF := 0.22
const CELL := 0.003
## The least any figure may come to the glass, mirror or pillar at full lean.
## 5 mm: the kei's glass sits only about 6 cm over its dash top, so a 1 cm
## rule would need a 4.5 cm figure there.
const CLEAR_M := 0.005
const KINDS := ["p0_beater", "p1_coupe", "p2_hothatch", "p3_tuner", "p4_kei", "p5_muscle", "p6_crossover"]
## Figures that are not a person on a base and skip the 45% head rule.
const OWN_SHAPE := ["dunmore_mascot", "traffic_cone", "nodding_dog", "hula_dancer", "dancing_flower", "drinking_bird", "surfer", "lucky_cat", "tiki", "moose"]

var failures: Array[String] = []
var meshes := {}   # id -> ArrayMesh

func _initialize() -> void:
	_catalogue()
	_silhouettes()
	_springs()
	_clearance()
	print("bobble_figures: ", "FAIL" if not failures.is_empty() else "PASS")
	for f in failures:
		print("  - ", f)
	quit(1 if not failures.is_empty() else 0)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

# ---------- catalogue ----------

func _catalogue() -> void:
	_check(BobbleFigures.IDS[0] == BobbleFigures.NONE, "index 0 should be none")
	_check(BobbleFigures.IDS.size() == 30, "want 29 figures plus none, got %d ids" % BobbleFigures.IDS.size())
	var b := BobbleHead.new(null, "p1_coupe")
	root.add_child(b)
	var most := 0
	var tallest := 0.0
	var heights: PackedStringArray = []
	for id in BobbleFigures.IDS:
		b.set_figure(id)
		if id == BobbleFigures.NONE:
			_check(not b.is_shown() and b.triangle_count() == 0, "none should draw nothing")
			continue
		var spec: Dictionary = BobbleFigures.FIGURES.get(id, {})
		_check(not spec.is_empty() and BobbleFigures.name_of(id) != id, "%s needs a display name" % id)
		_check(spec.has("how") and spec.has("spring") and spec.has("body") and spec.has("accent"), "%s needs how, spring, body and accent" % id)
		_check(b.figure == id and b.is_shown(), "%s should build (got %s)" % [id, b.figure])
		_check(b.triangle_count() > 100, "%s should be a figure, got %d tris" % [id, b.triangle_count()])
		_check(b.triangle_count() <= MAX_TRIS, "%s is %d tris, over the %d budget" % [id, b.triangle_count(), MAX_TRIS])
		var mi := b.mesh_instance()
		var mesh := mi.mesh as ArrayMesh if mi != null else null
		_check(mesh != null and mesh.get_surface_count() == 1, "%s should be one surface (one draw call)" % id)
		_check(mi != null and mi.material_override is ShaderMaterial, "%s should use the bob shader" % id)
		if mesh == null:
			continue
		meshes[id] = mesh
		most = maxi(most, b.triangle_count())
		var box := mesh.get_aabb()
		tallest = maxf(tallest, box.size.y)
		_check(box.size.y > 0.055 and box.size.y <= MAX_HEIGHT, "%s should stand about 7 cm (at most %.1f), is %.1f cm" % [id, MAX_HEIGHT * 100.0, box.size.y * 100.0])
		heights.append("%s %.1f" % [id, box.size.y * 100.0])
		_check(box.size.x < 0.058 and box.size.z < 0.058, "%s footprint too wide: %s" % [id, box.size])
		_check(absf(box.position.y) < 0.0005, "%s should stand on y = 0, its lowest point is %.4f" % [id, box.position.y])
		var arr := mesh.surface_get_arrays(0)
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		_check(uv2.size() == uv.size(), "%s needs a pivot (UV2) per vertex" % id)
		var heavy := 0
		for u in uv:
			if u.x > 0.99:
				heavy += 1
		_check(heavy >= 12, "%s needs a part that bobs (weighted vertices), got %d" % [id, heavy])
		# the shared round base: vertices on a circle of BASE_R at y = 0
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var rim := 0
		for v in verts:
			if absf(v.y) < 1e-4 and absf(Vector2(v.x, v.z).length() - BobbleHead.BASE_R) < 1e-4:
				rim += 1
		_check(rim >= 8, "%s should stand on the shared round base (radius %.3f), found %d rim vertices" % [id, BobbleHead.BASE_R, rim])
		if not OWN_SHAPE.has(id):
			_head_share(id, verts, uv, box)
	print("bobble figures: %d ids, tallest %.1f cm, most triangles %d" % [BobbleFigures.IDS.size() - 1, tallest * 100.0, most])
	print("heights (cm): ", ", ".join(heights))
	b.set_figure("no-such-figure")
	_check(b.figure == BobbleFigures.NONE, "unknown id should fall back to none, got %s" % b.figure)
	b.free()

## The head (the weight-1 vertices on the neck pivot, not a loose paw or jaw)
## spans about 45% of the figure's height: 36% to 62% here, by its y extent.
func _head_share(id: String, verts: PackedVector3Array, uv: PackedVector2Array, box: AABB) -> void:
	var tally := {}
	for i in verts.size():
		if uv[i].x > 0.99 and uv[i].x < 1.01:
			tally[uv[i].y] = int(tally.get(uv[i].y, 0)) + 1
	var neck_y := 0.0
	var best := 0
	for y in tally:
		if int(tally[y]) > best:
			best = int(tally[y])
			neck_y = float(y)
	var lo := INF
	var hi := -INF
	for i in verts.size():
		if uv[i].x > 0.99 and uv[i].x < 1.01 and is_equal_approx(uv[i].y, neck_y):
			lo = minf(lo, verts[i].y)
			hi = maxf(hi, verts[i].y)
	var share := (hi - lo) / box.size.y
	_check(share > 0.36 and share < 0.62, "%s: head is %.0f%% of the height, want about 45%%" % [id, share * 100.0])

# ---------- silhouettes ----------

## Rasterises the mesh's triangles seen along -z (front) or -x (side) into a
## grid of CELL metres: a PackedByteArray of 0/1, GRID_W x GRID_H.
const GRID_W := 20
const GRID_H := 30

func _raster(mesh: ArrayMesh, side: bool) -> PackedByteArray:
	var grid := PackedByteArray()
	grid.resize(GRID_W * GRID_H)
	var faces := mesh.get_faces()
	var i := 0
	while i + 2 < faces.size():
		var pts: Array[Vector2] = []
		for j in 3:
			var p := faces[i + j]
			pts.append(Vector2(p.z if side else p.x, p.y))
		i += 3
		# scan the triangle's bounding cells, test the cell centre
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in pts:
			mn = mn.min(p)
			mx = mx.max(p)
		var cx0 := maxi(int(floor((mn.x + GRID_W * CELL * 0.5) / CELL)), 0)
		var cx1 := mini(int(floor((mx.x + GRID_W * CELL * 0.5) / CELL)), GRID_W - 1)
		var cy0 := maxi(int(floor(mn.y / CELL)), 0)
		var cy1 := mini(int(floor(mx.y / CELL)), GRID_H - 1)
		for cy in range(cy0, cy1 + 1):
			for cx in range(cx0, cx1 + 1):
				var c := Vector2((cx + 0.5) * CELL - GRID_W * CELL * 0.5, (cy + 0.5) * CELL)
				if Geometry2D.point_is_inside_triangle(c, pts[0], pts[1], pts[2]):
					grid[cy * GRID_W + cx] = 1
	return grid

## The share of the cells either grid fills that only one of them fills.
static func _diff(a: PackedByteArray, b: PackedByteArray) -> float:
	var n := 0
	var u := 0
	for i in a.size():
		if a[i] != 0 or b[i] != 0:
			u += 1
			if a[i] != b[i]:
				n += 1
	return float(n) / maxi(u, 1)

func _silhouettes() -> void:
	var fronts := {}
	var sides := {}
	for id in meshes:
		fronts[id] = _raster(meshes[id], false)
		sides[id] = _raster(meshes[id], true)
	var ids := meshes.keys()
	var closest := 1.0
	var pair := ""
	for a in ids.size():
		for b in range(a + 1, ids.size()):
			var df := _diff(fronts[ids[a]], fronts[ids[b]])
			var ds := _diff(sides[ids[a]], sides[ids[b]])
			var d := maxf(df, ds)
			if d < closest:
				closest = d
				pair = "%s / %s" % [ids[a], ids[b]]
			_check(d >= MIN_DIFF, "%s and %s share a silhouette (front %.0f%%, side %.0f%% of their cells differ)" % [ids[a], ids[b], df * 100.0, ds * 100.0])
	print("silhouettes: closest pair %s, %.0f%% of their cells differ" % [pair, closest * 100.0])

# ---------- springs ----------

func _swing(b: BobbleHead, id: String) -> float:
	b.set_figure(id)
	b.bob = Vector2.ZERO
	b.bob_rate = Vector2.ZERO
	var peak := 0.0
	for i in 120:
		b.step(1.0 / 120.0, Vector3(6.0, 0.0, 0.0))
		peak = maxf(peak, b.bob.length())
	return peak

func _springs() -> void:
	var b := BobbleHead.new(null, "p1_coupe")
	root.add_child(b)
	for id in BobbleFigures.IDS:
		if id == BobbleFigures.NONE:
			continue
		var s := BobbleFigures.spring_of(id)
		_check(s.has("hz") and s.has("zeta") and s.has("gain") and s.has("side"), "%s: spring needs hz, zeta, gain, side" % id)
		b.set_figure(id)
		_check(is_equal_approx(b.spring_hz, float(s.hz)) and is_equal_approx(b.spring_gain, float(s.gain)), "%s: BobbleHead should take the figure's spring" % id)
	var wild := _swing(b, "ledger")
	var stiff := _swing(b, "tiki")
	var none := _swing(b, "pike")
	_check(wild > stiff * 3.0, "Ledger (%.2f) should swing far more than the tiki (%.2f)" % [wild, stiff])
	_check(none < 0.08, "Pike should barely move, peak %.3f" % none)
	_check(wild <= BobbleHead.TILT_MAX + 1e-5, "the cap holds for the wildest spring, got %.3f" % wild)
	b.set_figure(BobbleFigures.NONE)
	_check(is_equal_approx(b.spring_hz, BobbleHead.SPRING_HZ) and is_equal_approx(b.spring_gain, 1.0), "none should restore the default spring")
	# the hula dancer: the head stays, the skirt swings; the surfer: all of it swings
	var hula: ArrayMesh = meshes["hula_dancer"]
	var arr := hula.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var head_moves := 0
	var skirt_still := 0
	for i in verts.size():
		if verts[i].y > 0.045 and uv[i].x > 0.01:
			head_moves += 1
		if verts[i].y < 0.020 and verts[i].y > 0.008 and absf(verts[i].x) > 0.011 and uv[i].x < 0.99:
			skirt_still += 1
	_check(head_moves == 0, "hula dancer: her head should be still, %d head vertices bob" % head_moves)
	_check(skirt_still == 0, "hula dancer: her skirt should swing, %d skirt vertices are fixed" % skirt_still)
	var surf: ArrayMesh = meshes["surfer"]
	var suv: PackedVector2Array = surf.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var sverts: PackedVector3Array = surf.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var rider_fixed := 0
	for i in sverts.size():
		if sverts[i].y > 0.012 and suv[i].x < 0.99:
			rider_fixed += 1
	_check(rider_fixed == 0, "surfer: the whole rider should swing, %d vertices above the base are fixed" % rider_fixed)
	b.free()

# ---------- clearance ----------

## Every figure's vertices at the eight largest leans, in car space at the
## slot, against the glass line, the rear-view mirror housing and the A-pillar
## (the same shapes as the cabin clearance test), and the wheel's rim.
func _clearance() -> void:
	var t := BobbleHead.TILT_MAX
	var d := t * 0.7071
	var combos := [Vector2(t, 0), Vector2(-t, 0), Vector2(0, t), Vector2(0, -t), Vector2(d, d), Vector2(-d, -d), Vector2(d, -d), Vector2(-d, d)]
	for kind in KINDS:
		var cab := CabinSpec.for_kind(kind)
		var spot := CabinSpots.dash_pass(kind)
		var scale := CabinSpots.dash_pass_scale(kind)
		var cowl: Vector2 = cab.cowl
		var header: Vector2 = cab.header
		var p0 := Vector2(cowl.y, cowl.x + 0.086 - 0.008)
		var p1 := Vector2(header.y, header.x - 0.008)
		var gdir := (p1 - p0).normalized()
		var rear_pos: Vector3 = cab.rear_mirror
		var rb := Basis(Vector3.UP, deg_to_rad(CockpitMirrors.REAR_YAW)) * Basis(Vector3.RIGHT, deg_to_rad(CockpitMirrors.REAR_PITCH))
		var box_c := rear_pos + rb * Vector3(0, 0, -0.013)
		var box_h := Vector3(0.215, 0.072, 0.022) * 0.5
		var foot: Vector3 = cab.a_pillar[0]
		var topp: Vector3 = cab.a_pillar[1]
		var pa := Vector3(foot.x - 0.04, foot.y, foot.z + 0.02)
		var pb := Vector3(topp.x - 0.13, topp.y - 0.09, topp.z + 0.03)
		var wheel: Vector3 = cab.wheel
		var worst := {"glass": [INF, ""], "mirror": [INF, ""], "pillar": [INF, ""], "wheel": [INF, ""]}
		for id in meshes:
			var arr := (meshes[id] as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var uv2s: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
			for bob in combos:
				for i in range(0, verts.size(), 3):   # one vertex per triangle is enough at 3 mm cells? no: all three corners
					for j in 3:
						var p := spot + BobbleHead.bobbed_vertex(verts, uvs, uv2s, i + j, bob) * scale
						if p.z >= cowl.y - 0.05 and p.z <= header.y:
							var wv := Vector2(p.z, p.y) - p0
							var below := -(gdir.x * wv.y - gdir.y * wv.x)
							_worst(worst, "glass", below, id)
						var q := rb.inverse() * (p - box_c)
						var o := Vector3(maxf(absf(q.x) - box_h.x, 0.0), maxf(absf(q.y) - box_h.y, 0.0), maxf(absf(q.z) - box_h.z, 0.0))
						_worst(worst, "mirror", o.length(), id)
						var cp := Geometry3D.get_closest_point_to_segment(p, pa, pb)
						_worst(worst, "pillar", p.distance_to(cp) - 0.0375, id)
						_worst(worst, "wheel", p.distance_to(wheel) - 0.20, id)
		for part in ["glass", "mirror", "pillar", "wheel"]:
			var w: Array = worst[part]
			_check(float(w[0]) >= CLEAR_M, "%s: %s comes within %.1f cm of the %s at full lean (want %.0f cm)" % [kind, w[1], float(w[0]) * 100.0, part, CLEAR_M * 100.0])
		print("clearance %s (scale %.2f): glass %.1f cm (%s), mirror %.1f cm (%s), pillar %.1f cm (%s), wheel %.1f cm" % [
			kind, scale, float(worst.glass[0]) * 100.0, worst.glass[1], float(worst.mirror[0]) * 100.0, worst.mirror[1],
			float(worst.pillar[0]) * 100.0, worst.pillar[1], float(worst.wheel[0]) * 100.0])

static func _worst(worst: Dictionary, part: String, clear: float, id: String) -> void:
	var w: Array = worst[part]
	if clear < float(w[0]):
		w[0] = clear
		w[1] = id
