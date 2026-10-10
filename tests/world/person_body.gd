extends SceneTree

# People pipeline A1 (scripts/world/person_body.gd): one male mesh, 7 heights x
# 3 builds by bone scaling, arms posed by IK in the seat, painted faces, and the
# CPU cost of the baked path vs live rigs.
#
# Run (headless):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/person_body.gd

class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var _lock := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append("%s %s:%d %s %s" % [function, file, line, code, rationale])
		_lock.unlock()

var failures: Array[String] = []
var logger := ErrorCounter.new()

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		print("  FAIL: ", msg)

static func _aabb(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box

func _initialize() -> void:
	OS.add_logger(logger)
	var P := PersonBody
	var base := P.base()
	var tris := P.triangle_count()
	print("person mesh: %d triangles, %d bones" % [tris, P.BONE_COUNT])
	_check(tris >= 300 and tris <= 900, "triangle count %d outside 300..900 (CPU/GPU budget)" % tris)

	# every vertex fully weighted, bones valid
	var weights: PackedFloat32Array = base["weights"]
	var bones: PackedInt32Array = base["bones"]
	var bad_w := 0
	for vi in weights.size() / 4:
		var sum := 0.0
		for s in 4:
			sum += weights[vi * 4 + s]
			if bones[vi * 4 + s] < 0 or bones[vi * 4 + s] >= P.BONE_COUNT:
				bad_w += 1
		if absf(sum - 1.0) > 1e-4:
			bad_w += 1
	_check(bad_w == 0, "%d vertices with weights not summing to 1 or bad bone ids" % bad_w)

	# 21 variants: stature exact, heads-tall in range, builds ordered
	_check(P.variant_count() == 21, "variant count %d, want 21" % P.variant_count())
	var o := P.outfit(7)
	var stand := P.pose("stand")
	var last_s := 0.0
	var last_heads := 0.0
	var bake_us := 0
	for hi in P.HEIGHTS.size():
		var depth := []
		for bi in P.BUILDS.size():
			var v := P.variant(hi, bi)
			var t0 := Time.get_ticks_usec()
			var mesh := P.bake(v, stand, o, (hi + bi) % P.FACE_COUNT)
			bake_us += Time.get_ticks_usec() - t0
			var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var box := _aabb(verts)
			var top := box.position.y + box.size.y
			var s: float = v["stature"]
			_check(absf(top - s) < 0.012, "variant %s top %.3f, stature %.3f" % [v["key"], top, s])
			_check(absf(box.position.y) < 0.01, "variant %s feet at %.3f, want 0" % [v["key"], box.position.y])
			_check(mesh.get_surface_count() == 1 and mesh.surface_get_material(0) == P.material(), "variant %s: want one surface with the shared material" % v["key"])
			# belly depth: vertices weighted to the spine
			var rest := P._variant_positions(v, {})
			var zmin := 9.0
			var zmax := -9.0
			for vi in rest.size():
				if bones[vi * 4] == P.SPINE and weights[vi * 4] > 0.99:
					zmin = minf(zmin, rest[vi].z)
					zmax = maxf(zmax, rest[vi].z)
			depth.append(zmax - zmin)
			if bi == 1:
				var head_h: float = P.HEAD_H * float(v["hs"])
				var heads := s / head_h
				_check(heads > 6.6 and heads < 7.9, "%.2f m is %.2f heads tall, want 6.6..7.9" % [s, heads])
				_check(s > last_s and heads > last_heads, "heights and head counts must increase with stature")
				last_s = s
				last_heads = heads
				if hi == 0 or hi == P.HEIGHTS.size() - 1:
					print("  %.2f m: %.2f heads tall" % [s, heads])
		_check(depth[0] < depth[1] and depth[1] < depth[2], "height %d: belly depth not slim < average < heavy: %s" % [hi, str(depth)])
	print("  bake: %.2f ms per person (21 variants)" % (bake_us / 21000.0))
	_check(bake_us / 21000.0 < 25.0, "baking took %.1f ms per person, budget 25" % (bake_us / 21000.0))

	# normals point out of the body
	var v_avg := P.variant(3, 1)
	var sm := P.bake(v_avg, stand, o, 0)
	var sv: PackedVector3Array = sm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = sm.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var fk := P.fk_globals(v_avg, stand)
	var gpos: PackedVector3Array = fk[0]
	var outward := 0
	var total := sv.size() / 3
	for t in total:
		var c := (sv[t * 3] + sv[t * 3 + 1] + sv[t * 3 + 2]) / 3.0
		# compare to the nearest point on the bone the vertex follows (its child joint segment)
		var b0 := bones[t * 12]
		var a: Vector3 = gpos[b0]
		var kids := []
		for i in P.BONE_COUNT:
			if P.PARENT[i] == b0:
				kids.append(i)
		var axis_p := a
		if kids.size() == 1:
			axis_p = Geometry3D.get_closest_point_to_segment(c, a, gpos[kids[0]])
		elif b0 == P.HEAD:
			axis_p = a + Vector3(0, 0.12, 0)
		elif b0 == P.HAND_L or b0 == P.HAND_R or b0 == P.FOOT_L or b0 == P.FOOT_R:
			axis_p = (sv[t * 3] + sv[t * 3 + 1] + sv[t * 3 + 2]) / 3.0 - sn[t * 3] * 0.01
		if sn[t * 3].dot(c - axis_p) > 0.0:
			outward += 1
	var frac := float(outward) / total
	print("  normals facing out: %.1f%%" % (frac * 100.0))
	_check(frac > 0.95, "only %.1f%% of triangles face outward" % (frac * 100.0))

	# arms in the seat: wrists reach wheel grips for every variant
	var worst := 0.0
	for hi in P.HEIGHTS.size():
		for bi in P.BUILDS.size():
			var v := P.variant(hi, bi)
			var legs := P.fk_globals(v, P.sit_legs())
			var sh_l: Vector3 = legs[0][P.UPPER_L]
			var sh_r: Vector3 = legs[0][P.UPPER_R]
			var h: float = v["h"]
			var gl := sh_l + Vector3(0.06, -0.14, -0.40) * h
			var gr := sh_r + Vector3(-0.06, -0.14, -0.40) * h
			var sp := P.sit_pose(v, gl, gr)
			var g := P.fk_globals(v, sp)
			var err := maxf((g[0][P.HAND_L] - gl).length(), (g[0][P.HAND_R] - gr).length())
			worst = maxf(worst, err)
			# elbows below the shoulders and outside the wrists (no chicken wings inward)
			var el: Vector3 = g[0][P.FORE_L]
			_check(el.y < sh_l.y and el.x < gl.x + 0.02, "variant %s: left elbow at %s looks wrong" % [v["key"], el])
	print("  seated wrist error: %.1f mm worst" % (worst * 1000.0))
	_check(worst < 0.01, "seated wrists miss the grips by %.1f mm" % (worst * 1000.0))
	# an out-of-reach grip: the arm points straight at it, no NaN
	var far := P.sit_pose(v_avg, Vector3(-0.2, 1.0, -2.0), Vector3(0.2, 1.0, -2.0))
	var gfar := P.fk_globals(v_avg, far)
	_check(not is_nan(gfar[0][P.HAND_L].x), "unreachable grip produced NaN")

	# the live rig skins to the same shape as the bake
	var rig := P.make_rig(v_avg, o, 2)
	root.add_child(rig)
	var skel := rig.get_node("Skeleton") as Skeleton3D
	var smoke := P.pose("smoke", v_avg)
	P.apply_pose(skel, smoke)
	skel.force_update_all_bone_transforms()
	var body := skel.get_node("Body") as MeshInstance3D
	var rest_v: PackedVector3Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var baked_v := P._variant_positions(v_avg, smoke)
	var max_d := 0.0
	for vi in range(0, rest_v.size(), 7):
		var acc := Vector3.ZERO
		for s in 4:
			var w := weights[vi * 4 + s]
			if w > 0.0:
				var bi := bones[vi * 4 + s]
				acc += (skel.get_bone_global_pose(bi) * body.skin.get_bind_pose(bi) * rest_v[vi]) * w
		max_d = maxf(max_d, (acc - baked_v[vi]).length())
	print("  rig vs bake: %.3f mm" % (max_d * 1000.0))
	_check(max_d < 0.001, "the live rig and the bake disagree by %.2f mm" % (max_d * 1000.0))
	_check(skel.get_bone_count() == P.BONE_COUNT, "rig has %d bones" % skel.get_bone_count())

	# painted faces: 8 distinct tiles, white corner texel, face uvs inside their tile
	var img := P.face_image()
	_check(img.get_width() == P.ATLAS_W and img.get_height() == P.ATLAS_H, "atlas size")
	_check(img.get_pixel(0, 0).is_equal_approx(Color.WHITE), "atlas corner texel must be white (non-face uv)")
	var tiles := {}
	for f in P.FACE_COUNT:
		var tile := img.get_region(Rect2i((f % 4) * P.FACE_PX, (f / 4) * P.FACE_PX, P.FACE_PX, P.FACE_PX))
		tiles[tile.get_data().hex_encode().md5_text()] = true
	_check(tiles.size() == P.FACE_COUNT, "only %d distinct faces" % tiles.size())
	var fm := P.bake(v_avg, stand, o, 5)
	var fuv: PackedVector2Array = fm.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var base_uv: PackedVector2Array = base["uv"]
	var face_verts := 0
	var outside := 0
	var t5 := Rect2(Vector2(1, 1) * P.FACE_PX / Vector2(P.ATLAS_W, P.ATLAS_H), Vector2(P.FACE_PX, P.FACE_PX) / Vector2(P.ATLAS_W, P.ATLAS_H))
	for vi in fuv.size():
		if base_uv[vi].x >= 0.0:
			face_verts += 1
			if not t5.grow(0.0001).has_point(fuv[vi]):
				outside += 1
	_check(face_verts > 30 and outside == 0, "face 5: %d face vertices, %d outside its tile" % [face_verts, outside])

	# palette: outfits stay in Amber vs Dusk (no magenta or cyan)
	var pal = load("res://tests/core/palette.gd")
	for list in [P.SKIN_TONES, P.HAIR_COLOURS, P.TOPS, P.BOTTOMS, P.SHOES]:
		for c in list:
			_check(pal.is_bad(c) == "", "colour %s breaks the palette" % (c as Color).to_html(false))

	# people.json: the kit, the house style and the cast all check out, and
	# every cast member bakes to the one mesh at their own height
	var problems := P.data_problems()
	_check(problems.is_empty(), "people.json: %s" % str(problems))
	_check(P.cast_ids().size() >= 1, "people.json lists no cast")
	for id in P.cast_ids():
		var who := P.person(id)
		_check(not who.is_empty(), "cast member %s does not resolve" % id)
		if who.is_empty():
			continue
		var cast_mesh := P.bake_person(id)
		_check(cast_mesh != null and cast_mesh.surface_get_array_len(0) == tris * 3, "cast member %s is not the shared mesh" % id)
		_check(cast_mesh == P.bake_person(id), "cast member %s is not cached" % id)
		for c in (who["outfit"] as Dictionary).values():
			_check(pal.is_bad(c) == "", "cast member %s wears %s, which breaks the palette" % [id, (c as Color).to_html(false)])
		if who["pose_name"] == "stand":
			var cast_box := _aabb(cast_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
			_check(absf(cast_box.end.y - float(who["variant"]["stature"])) < 0.012, "cast member %s is %.3f m tall, want %.2f" % [id, cast_box.end.y, who["variant"]["stature"]])
	# a row outside the kit or the style is refused, not drawn
	var off := {"id": "x", "height": 1.70, "build": "huge", "face": "plain", "skin": "#FF00FF", "hair": "shaved",
		"top": "#1B2A4A", "sleeves": "long", "bottoms": "#1A1A1E", "shoes": "#141414", "pose": "stand"}
	_check(P._row_problems(off).size() == 3, "an off-kit row should give 3 problems, got %s" % str(P._row_problems(off)))
	_check(P.person("nobody").is_empty() and P.bake_person("nobody") == null, "an unknown id must give nothing")
	print("  people.json: %d cast, all inside the kit and the house style" % P.cast_ids().size())

	# CPU: cache hits, and 30 live rigs vs 30 baked people
	var named := P.bake(v_avg, stand, o, 1, "stand")
	var t1 := Time.get_ticks_usec()
	var again := P.bake(v_avg, stand, o, 1, "stand")
	var hit_us := Time.get_ticks_usec() - t1
	_check(named == again, "named bakes must come from the cache")
	print("  cached bake: %d us" % hit_us)
	var rigs: Array[Skeleton3D] = []
	for i in 30:
		var r := P.make_rig(P.variant(i % 7, i % 3), P.outfit(i), i % P.FACE_COUNT)
		root.add_child(r)
		rigs.append(r.get_node("Skeleton") as Skeleton3D)
	var frames := 120
	var t2 := Time.get_ticks_usec()
	for f in frames:
		var sway := sin(f * 0.1) * 6.0
		var p := {P.SPINE: P._q(0, 0, sway * 0.3), P.UPPER_L: P._q(sway, 0, 2), P.UPPER_R: P._q(-sway, 0, -2),
			P.FORE_L: P._q(12), P.FORE_R: P._q(12), P.HEAD: P._q(0, sway, 0)}
		for sk in rigs:
			P.apply_pose(sk, p)
			sk.force_update_all_bone_transforms()
	var live_ms := (Time.get_ticks_usec() - t2) / 1000.0 / frames
	print("  30 live rigs posed: %.3f ms per frame (baked people: 0, nothing to update)" % live_ms)
	_check(live_ms < 4.0, "30 live rigs cost %.2f ms per frame, budget 4" % live_ms)

	_check(logger.errors.is_empty(), "engine errors: %s" % str(logger.errors.slice(0, 5)))
	if failures.is_empty():
		print("PASS person_body")
		quit(0)
	else:
		print("FAIL person_body: %d" % failures.size())
		quit(1)
