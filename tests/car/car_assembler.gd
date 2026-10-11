extends SceneTree

# CarAssembler (cars from parts, pilot 2026-10-10): the coupe's body.glb is 50
# separate named parts; the game draws them as ONE mesh with 4 surfaces.
#
#   godot --headless --path . -s res://tests/car/car_assembler.gd
#
# Checks: every part the pilot asked for is in the glb; the merge gives
# exactly body / trim / glass / glow, in the triangle budget, the size of the
# car; the merged mesh is cached; the open configuration takes the hood, doors
# and trunk out as 4 one-surface panels that really swing; swap_part replaces
# one part and leaves the rest; the shut gaps are 3.5-4.5 mm; ao and shut
# reach the mesh as CUSTOM0; the paint shader hook keeps the paint and dirt
# uniforms; P1CoupeBuilder builds from the parts with the same metas and draw
# calls as before, and NEON_COUPE_LEGACY=1 still gives the old proxy.
#
# Symmetry (Roy, 2026-10-10: "make sure the cars are symmetrical"): every part
# is the mirror image of its left/right twin, or of itself if it straddles
# the centre line, vertex for vertex (position within 0.05 mm, normal, ao and
# shut too). The only parts let off are NOT_MIRRORED, one-sided on purpose;
# tools/car_pipeline/symmetry_check.py measures the same thing on the glb.

const ID := "p1_coupe"
const META := "res://assets/cars/p1_coupe/body.json"
const WANT_PARTS := [
	"body", "underbody", "hood", "door_l", "door_r", "trunk", "fender_fl", "fender_fr", "bumper_f", "bumper_r",
	"grille", "popup_l", "popup_r", "tail_l", "tail_r", "tail_panel", "turn_l", "turn_r",
	"mirror_l", "mirror_r", "handle_l", "handle_r",
	"glass_windshield", "glass_backlight", "glass_door_l", "glass_door_r", "glass_quarter_l", "glass_quarter_r",
	"seal_windshield", "seal_backlight", "seal_door_l", "seal_door_r", "seal_quarter_l", "seal_quarter_r",
	"arch_liner_fl", "arch_liner_fr", "arch_liner_rl", "arch_liner_rr",
	"pillar_a_l", "pillar_a_r", "plate_f", "plate_r", "wiper_l", "wiper_r", "antenna", "spoiler", "exhaust",
]
const TRI_TARGET_MIN := 5000
const TRI_CEILING := 7000
## One-sided on purpose (tools/car_pipeline/parts.py ASYMMETRIC says why for each).
const NOT_MIRRORED := ["mirror_l", "mirror_r", "wiper_l", "wiper_r", "antenna"]
const GAP_MIN := 0.0035
const GAP_MAX := 0.0045

var fails := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL " + msg)
		fails += 1

func _initialize() -> void:
	OS.set_environment("NEON_COUPE_LEGACY", "")
	OS.set_environment("NEON_CAR_PANELS", "")
	_check(CarAssembler.has_car(ID), "assets/cars/p1_coupe/body.glb should be in the project")
	_check(not CarAssembler.has_car("no_such_car"), "a car without a glb should not be reported")
	_check(CarAssembler.build("no_such_car") == null, "building a car without a glb should give null")

	# ---- the parts
	var t0 := Time.get_ticks_usec()
	var names := CarAssembler.part_names(ID)
	var load_ms := (Time.get_ticks_usec() - t0) / 1000.0
	for p in WANT_PARTS:
		_check(names.has(p), "part %s missing from the glb" % p)
	for n in names:
		_check(not String(n).begins_with("wheel_"), "wheel mesh %s should not be a body part" % n)
	var hinges := CarAssembler.hinges(ID)
	_check(hinges.size() == 4, "want 4 hinges, got %s" % [hinges.keys()])
	for hname in ["hinge_hood", "hinge_trunk", "hinge_door_l", "hinge_door_r"]:
		_check(hinges.has(hname) and not (hinges[hname].parts as Array).is_empty(), "%s should carry parts" % hname)
	if hinges.has("hinge_door_r"):
		var on_door: Array = hinges["hinge_door_r"].parts
		for p in ["door_r", "glass_door_r", "handle_r", "mirror_r"]:
			_check(on_door.has(p), "%s should hang on the right door hinge, got %s" % [p, on_door])

	# ---- symmetry: the left of the car is the mirror image of the right
	var pairs := 0
	var centred := 0
	for n in names:
		var pname := String(n)
		if pname in NOT_MIRRORED:
			continue
		var twin := pname.left(-1) + "l"
		if pname.ends_with("l") and names.has(pname.left(-1) + "r"):
			continue          # checked from its right-hand twin
		var other := pname
		if pname.ends_with("r") and names.has(twin):
			other = twin
			pairs += 1
		else:
			centred += 1
		var miss := _mirror_misses(CarAssembler.part_arrays(ID, pname), CarAssembler.part_arrays(ID, other))
		_check(miss == 0, "%s is not the mirror image of %s: %d vertices have no partner" % [pname, other, miss])
	print("symmetry: %d left/right pairs and %d centre parts are exact mirror images; one-sided on purpose: %s" % [pairs, centred, NOT_MIRRORED])
	_check(pairs >= 14 and centred >= 12, "expected the car's pairs and centre parts to be checked (%d, %d)" % [pairs, centred])
	var lamps_now := CarAssembler.lamp_centres(ID)
	for kind in ["head", "tail"]:
		var l: Vector3 = lamps_now[kind][0]
		var r: Vector3 = lamps_now[kind][1]
		_check((Vector3(-l.x, l.y, l.z) - r).length() < 1e-4, "%s lamps should be mirror images: %s / %s" % [kind, l, r])

	# ---- the merged mesh: 4 surfaces, the size of the car, in budget
	t0 = Time.get_ticks_usec()
	var body := CarAssembler.build(ID)
	var merge_ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check(body != null and body.mesh is ArrayMesh and body.name == "Body", "build should give a Body MeshInstance3D")
	var mesh := body.mesh as ArrayMesh
	var snames := []
	for i in mesh.get_surface_count():
		snames.append(mesh.surface_get_name(i))
	_check(snames == ["body", "trim", "glass", "glow"], "want surfaces body, trim, glass, glow, got %s" % [snames])
	_check(CarAssembler.draw_call_count(ID) == 4, "the closed body should be 4 draw calls, got %d" % CarAssembler.draw_call_count(ID))
	for i in mesh.get_surface_count():
		_check((mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_CUSTOM0) != 0, "surface %s should carry CUSTOM0 (ao, shut)" % snames[i])
		_check(body.get_surface_override_material(i) != null or snames[i] == "body", "surface %s should have its material" % snames[i])
	var box := mesh.get_aabb()
	_check(absf(box.size.z - P1CoupeBuilder.LENGTH) <= 0.05, "length %.3f, want %.2f" % [box.size.z, P1CoupeBuilder.LENGTH])
	_check(absf(box.end.y - P1CoupeBuilder.HEIGHT) <= 0.05 or box.end.y > P1CoupeBuilder.HEIGHT, "height %.3f, want %.2f (plus the antenna)" % [box.end.y, P1CoupeBuilder.HEIGHT])
	_check(box.size.x >= P1CoupeBuilder.WIDTH and box.size.x <= P1CoupeBuilder.WIDTH + 0.5, "width %.3f, want %.2f plus the door mirrors" % [box.size.x, P1CoupeBuilder.WIDTH])
	var tris := CarAssembler.triangle_count(ID)
	_check(tris >= TRI_TARGET_MIN and tris <= TRI_CEILING, "%d triangles, want %d-%d" % [tris, TRI_TARGET_MIN, TRI_CEILING])
	var meta := _load_meta()
	if not meta.is_empty():
		_check(tris == int(meta.tris_body), "merged %d triangles, body.json says %d without the wheels" % [tris, int(meta.tris_body)])
		_check(float(meta.shut.gap) >= GAP_MIN and float(meta.shut.gap) <= GAP_MAX, "body.json gap %.4f" % float(meta.shut.gap))

	# ---- cached: a second car is the same mesh
	t0 = Time.get_ticks_usec()
	var body2 := CarAssembler.build(ID)
	var cached_ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check(body2.mesh == body.mesh, "two closed coupes should share one merged mesh")
	body2.free()

	# ---- ao and shut reach the mesh
	var bi := CarAssembler.surface_index(mesh, "body")
	var arrays := mesh.surface_get_arrays(bi)
	var custom: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0]
	var nv := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	_check(custom.size() == nv * 4, "CUSTOM0 should be 4 bytes a vertex (%d for %d vertices)" % [custom.size(), nv])
	var shut_on := 0
	var shut_off := 0
	var ao_min := 255
	var ao_max := 0
	for k in nv:
		ao_min = mini(ao_min, custom[k * 4])
		ao_max = maxi(ao_max, custom[k * 4])
		if custom[k * 4 + 1] >= 250:
			shut_on += 1
		elif custom[k * 4 + 1] <= 5:
			shut_off += 1
	_check(shut_on > 200, "shut should be 1 along the panel edges (%d vertices)" % shut_on)
	_check(shut_off > shut_on / 2, "shut should be 0 away from the edges (%d vertices)" % shut_off)
	_check(ao_max >= 250 and ao_min < 128, "ao should run from shaded to open, got %d..%d of 255" % [ao_min, ao_max])
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var paint_v := 0
	for c in cols:
		if c.a < 0.01:
			paint_v += 1
	_check(paint_v > nv / 3, "paint vertices should carry alpha 0 so the shader tints them (%d of %d)" % [paint_v, nv])

	# ---- shut gaps: hood to fender, door to fender, trunk to body
	var gap_hf := _gap(ID, "hood", "fender_fr", Vector3.RIGHT, Vector3.UP, 2, -1.1)
	var gap_df := _gap(ID, "fender_fr", "door_r", Vector3.BACK, Vector3.RIGHT, 1, 0.55)
	var gap_tb := _gap(ID, "trunk", "body", Vector3.RIGHT, Vector3.UP, 2, 1.85)
	print("shut gaps: hood/fender %.2f mm, fender/door %.2f mm, trunk/body %.2f mm" % [gap_hf * 1000.0, gap_df * 1000.0, gap_tb * 1000.0])
	for g in [["hood/fender", gap_hf], ["fender/door", gap_df], ["trunk/body", gap_tb]]:
		_check(g[1] >= GAP_MIN and g[1] <= GAP_MAX, "%s gap %.2f mm, want 3.5-4.5" % [g[0], g[1] * 1000.0])

	# ---- the door mirrors sit where the game has them
	for i in 2:
		var want: Vector3 = P1CoupeBuilder.MIRRORS[i].pos
		var mb := CarAssembler.part_aabb(ID, "mirror_l" if i == 0 else "mirror_r")
		_check(mb.grow(0.01).has_point(want), "mirror %d box %s should hold P1CoupeBuilder.MIRRORS pos %s" % [i, mb, want])
		_check(mb.size.y >= P1CoupeBuilder.MIRROR_SIZE.y - 0.02 and mb.size.y <= P1CoupeBuilder.MIRROR_SIZE.y + 0.03, "mirror %d is %.3f tall, want %.3f" % [i, mb.size.y, P1CoupeBuilder.MIRROR_SIZE.y])
		_check(absf(mb.end.x) > P1CoupeBuilder.WIDTH / 2.0 or absf(mb.position.x) > P1CoupeBuilder.WIDTH / 2.0, "mirror %d should stand out past the body side" % i)

	# ---- open: 4 panels, one surface each, that really move
	var open := CarAssembler.build(ID, {"panels": "open"})
	var panel_tris := 0
	var n_panels := 0
	for c in open.get_children():
		_check(hinges.has(String(c.name)), "open body child %s should be a hinge" % c.name)
		var pm := c.get_child(0) as MeshInstance3D
		_check(pm != null and pm.mesh.get_surface_count() == 1, "an open panel should be one surface (%s)" % c.name)
		if pm != null:
			panel_tris += CarAssembler._mesh_tris(pm.mesh)
			n_panels += 1
	_check(n_panels == 4, "want 4 open panels, got %d" % n_panels)
	_check(CarAssembler.draw_call_count(ID, {"panels": "open"}) == 8, "open should be 4 + 4 draw calls, got %d" % CarAssembler.draw_call_count(ID, {"panels": "open"}))
	_check(CarAssembler._mesh_tris(open.mesh) + panel_tris == tris, "open body %d + panels %d should be the closed %d" % [CarAssembler._mesh_tris(open.mesh), panel_tris, tris])
	var hood_top := _panel_aabb(open, "hinge_hood").end.y
	_check(hood_top > CarAssembler.part_aabb(ID, "hood").end.y + 0.25, "the open hood should rise (top %.2f)" % hood_top)
	var door_out := _panel_aabb(open, "hinge_door_r").end.x
	_check(door_out > CarAssembler.part_aabb(ID, "door_r").end.x + 0.3, "the open right door should swing out (x %.2f)" % door_out)
	var door_out_l := _panel_aabb(open, "hinge_door_l").position.x
	_check(door_out_l < CarAssembler.part_aabb(ID, "door_l").position.x - 0.3, "the open left door should swing out (x %.2f)" % door_out_l)
	_check((open.mesh as ArrayMesh).get_surface_count() == 4, "the open body keeps its 4 surfaces")
	open.free()

	# ---- swap_part: a different front bumper, the rest untouched
	var holder := Node3D.new()
	holder.add_child(body)
	var bumper := _box_mesh(Vector3(1.5, 0.3, 0.5), Vector3(0.0, 0.3, -1.9))
	var before_bumper := CarAssembler.triangle_count(ID) - CarAssembler.triangle_count(ID, {"bumper_f": false})
	_check(before_bumper > 100, "the stock front bumper should be a real part (%d triangles)" % before_bumper)
	_check(CarAssembler.swap_part(holder, "bumper_f", bumper), "swap_part should find the body under its parent and swap the bumper")
	var swapped := body.mesh as ArrayMesh
	_check(swapped != mesh, "a swap should give a new merged mesh")
	_check(swapped.get_surface_count() == 4, "a swapped body is still 4 surfaces, got %d" % swapped.get_surface_count())
	_check(CarAssembler._mesh_tris(swapped) == tris - before_bumper + 12, "swapped body %d triangles, want %d" % [CarAssembler._mesh_tris(swapped), tris - before_bumper + 12])
	_check(absf(swapped.get_aabb().end.z - box.end.z) < 0.01, "the tail should not move when the nose is swapped")
	_check(CarAssembler.surface_index(swapped, "body") == 0, "the body surface stays first")
	_check(not CarAssembler.swap_part(holder, "no_such_part", bumper), "swapping a part the car does not have should fail")
	_check(CarAssembler.swap_part(holder, "bumper_f", null), "swap_part(null) takes the part off")
	_check(CarAssembler._mesh_tris(body.mesh) == tris - before_bumper, "without a bumper %d triangles, want %d" % [CarAssembler._mesh_tris(body.mesh), tris - before_bumper])
	var again := CarAssembler.build(ID)
	_check(again.mesh == mesh, "the stock closed mesh should still be in the cache after a swap")
	again.free()
	holder.free()

	# ---- the paint shader hook
	var code := CarAssembler.paint_shader_code(P1CoupeBuilder.BODY_SHADER)
	_check(code.contains("ALBEDO *= mix(1.0, ao_shut.x, 0.7);") and code.contains("ALBEDO *= 1.0 - 0.75 * ao_shut.y;"), "the hook should add the ao and shut lines")
	_check(code.contains("uniform vec3 paint") and code.contains("uniform float dirt"), "the hook must keep the paint and dirt uniforms")
	_check(code.contains("ao_shut = CUSTOM0.rg;"), "the hook should read CUSTOM0 in vertex()")
	_check(code.length() - P1CoupeBuilder.BODY_SHADER.length() < 200, "the hook should be a few lines, not a new shader")
	_check(CarAssembler.paint_shader(P1CoupeBuilder.BODY_SHADER) == CarAssembler.paint_shader(P1CoupeBuilder.BODY_SHADER), "the hooked shader should be shared")
	_check(CarAssembler.paint_shader_code("shader_type spatial;\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n}\n").contains("void vertex()"), "a shader without vertex() should get one")

	# ---- the coupe builder uses it, with the same metas and draw calls
	_check(P1CoupeBuilder.uses_parts(), "the coupe should build from parts when the glb is there")
	var car := P1CoupeBuilder.build_chassis_visual()
	var cbody := car.get_node_or_null("Body") as MeshInstance3D
	_check(cbody != null and cbody.has_meta("car_id") and cbody.mesh == mesh, "the coupe's Body should be the assembled, cached mesh")
	_check(car.get_node_or_null("Mirrors") == null, "from parts the door mirrors are in the body mesh, not a mesh of their own")
	_check(P1CoupeBuilder.draw_call_count() == 9, "the coupe should still be 9 draw calls, got %d" % P1CoupeBuilder.draw_call_count())
	_check(car.get_child(0) == cbody, "the body should be the first child (before the effects attach)")
	var paint_m := car.get_meta("body_mat") as ShaderMaterial
	_check(paint_m != null and cbody.get_surface_override_material(0) == paint_m, "body_mat should be the material on the body surface")
	_check(paint_m != null and paint_m.shader == CarAssembler.paint_shader(P1CoupeBuilder.BODY_SHADER), "the body paint should use the hooked shader")
	P1CoupeBuilder.recolor(car, Color.WHITE)
	_check(paint_m.get_shader_parameter("paint") == Color.WHITE, "recolor should set the paint uniform")
	for key in ["kind", "half_w", "half_l", "exhaust_tips", "sticker_slots", "headlights", "tail_lights"]:
		_check(car.has_meta(key), "the chassis visual should keep the %s meta" % key)
	var heads: Array = car.get_meta("headlights", [])
	var tails: Array = car.get_meta("tail_lights", [])
	_check(heads.size() == 2 and heads[0].x < 0.0 and heads[1].x > 0.0 and heads[0].z < -1.8, "headlights at the nose, left then right: %s" % [heads])
	_check(tails.size() == 2 and tails[0].x < 0.0 and tails[1].x > 0.0 and tails[0].z > 2.1, "tail lights at the tail, left then right: %s" % [tails])
	_check(car.get_node_or_null(Undercarriage.NODE_NAME) is MeshInstance3D, "the underside is still attached")
	car.free()

	OS.set_environment("NEON_COUPE_LEGACY", "1")
	_check(not P1CoupeBuilder.uses_parts(), "NEON_COUPE_LEGACY=1 should keep the old proxy")
	var old := P1CoupeBuilder.build_chassis_visual()
	var obody := old.get_node_or_null("Body") as MeshInstance3D
	_check(obody != null and not obody.has_meta("car_id") and obody.mesh.get_surface_count() == 3, "the legacy body is the 3-surface sheet proxy")
	_check(old.get_node_or_null("Mirrors") is MeshInstance3D, "the legacy body keeps its Mirrors mesh")
	_check(P1CoupeBuilder.draw_call_count() == 9, "legacy draw calls %d, want 9" % P1CoupeBuilder.draw_call_count())
	old.free()
	OS.set_environment("NEON_COUPE_LEGACY", "")

	OS.set_environment("NEON_CAR_PANELS", "open")
	var ocar := P1CoupeBuilder.build_chassis_visual()
	_check(ocar.get_node("Body").get_child_count() == 4, "NEON_CAR_PANELS=open should build the coupe with 4 open panels")
	ocar.free()
	OS.set_environment("NEON_CAR_PANELS", "")

	print("car_assembler: %d parts, %d triangles in 4 surfaces; glb read %.1f ms, merge %.1f ms, cached build %.3f ms" % [names.size(), tris, load_ms, merge_ms, cached_ms])
	print("PASS" if fails == 0 else "FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

func _load_meta() -> Dictionary:
	var f := FileAccess.open(META, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

## The shut gap between two parts across `across`, measured between their
## outer skin edges (vertices with shut = 1 whose normal is along `facing`)
## in a 6 cm window at `at` along car axis `along` (0 x, 1 y, 2 z).
func _gap(car_id: String, part_a: String, part_b: String, across: Vector3, facing: Vector3, along: int, at: float) -> float:
	var a := _edge_extent(car_id, part_a, across, facing, along, at, true, -INF)
	var b := _edge_extent(car_id, part_b, across, facing, along, at, false, a - 0.02)
	return b - a

## Farthest (want_max) or nearest edge vertex along `across`; `beyond` skips
## the edges on the far side of the part.
func _edge_extent(car_id: String, part: String, across: Vector3, facing: Vector3, along: int, at: float, want_max: bool, beyond: float) -> float:
	var best := -INF if want_max else INF
	var mats: Dictionary = CarAssembler.part_arrays(car_id, part)
	if not mats.has("paint"):
		return best
	var m: Dictionary = mats["paint"]
	var v: PackedVector3Array = m.v
	var n: PackedVector3Array = m.n
	var ao: PackedByteArray = m.ao
	for k in v.size():
		if ao[k * 4 + 1] < 250 or n[k].dot(facing) < 0.7 or absf(v[k][along] - at) > 0.03:
			continue
		var d := v[k].dot(across)
		if want_max:
			best = maxf(best, d)
		elif d > beyond:
			best = minf(best, d)
	return best

## How many vertices of part A have no mirror partner in part B (same material,
## position mirrored in x within 0.05 mm, normal mirrored, same ao and shut),
## plus any difference in triangle count.
func _mirror_misses(a: Dictionary, b: Dictionary) -> int:
	var miss := 0
	for mname in a:
		if not b.has(mname):
			miss += (a[mname].v as PackedVector3Array).size()
			continue
		var av: PackedVector3Array = a[mname].v
		var an: PackedVector3Array = a[mname].n
		var aa: PackedByteArray = a[mname].ao
		var bv: PackedVector3Array = b[mname].v
		var bn: PackedVector3Array = b[mname].n
		var ba: PackedByteArray = b[mname].ao
		miss += absi((a[mname].i as PackedInt32Array).size() - (b[mname].i as PackedInt32Array).size())
		# B's vertices on a 0.1 mm grid; a partner is looked for in the 27 cells round the mirrored point
		var at := {}
		for k in bv.size():
			var key := Vector3i(roundi(bv[k].x * 10000.0), roundi(bv[k].y * 10000.0), roundi(bv[k].z * 10000.0))
			if not at.has(key):
				at[key] = []
			at[key].append(k)
		for k in av.size():
			var want := Vector3(-av[k].x, av[k].y, av[k].z)
			var nm := Vector3(-an[k].x, an[k].y, an[k].z)
			var cell := Vector3i(roundi(want.x * 10000.0), roundi(want.y * 10000.0), roundi(want.z * 10000.0))
			var found := false
			for dx in [0, -1, 1]:
				for dy in [0, -1, 1]:
					for dz in [0, -1, 1]:
						for j in at.get(cell + Vector3i(dx, dy, dz), []):
							if want.distance_to(bv[j]) < 5e-5 and nm.distance_to(bn[j]) < 0.02 									and absi(aa[k * 4] - ba[j * 4]) <= 1 and absi(aa[k * 4 + 1] - ba[j * 4 + 1]) <= 1:
								found = true
								break
						if found:
							break
					if found:
						break
				if found:
					break
			if not found:
				if miss == 0:
					print("  no mirror partner: %s vertex %s normal %s ao %d shut %d" % [mname, av[k], an[k], aa[k * 4], aa[k * 4 + 1]])
				miss += 1
	return miss

func _panel_aabb(body: MeshInstance3D, hinge_name: String) -> AABB:
	var hinge := body.get_node_or_null(hinge_name) as Node3D
	if hinge == null:
		return AABB()
	var pm := hinge.get_child(0) as MeshInstance3D
	var verts: PackedVector3Array = pm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var box := AABB(hinge.transform * verts[0], Vector3.ZERO)
	for p in verts:
		box = box.expand(hinge.transform * p)
	return box

## A plain box as a part: one surface named "paint", 12 triangles.
func _box_mesh(size: Vector3, center: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bm := BoxMesh.new()
	bm.size = size
	var arrays := bm.get_mesh_arrays()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for k in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
		st.set_normal(n[k])
		st.add_vertex(v[k] + center)
	var mesh := st.commit()
	mesh.surface_set_name(0, "paint")
	return mesh
