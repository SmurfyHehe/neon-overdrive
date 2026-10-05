extends RefCounted

# Loads the stage B1 fleet design proxies (docs/design/fleet/proxies.json,
# written by tools/fleet_design/godot_export.py) and builds them as Godot
# meshes, so the design sheet's shapes can be checked in the engine.
#
# A built car is laid out the way B1 plans the game cars:
#   Body    one MeshInstance3D with up to 3 surfaces: body (vertex colours),
#           glass, lights (unshaded)
#   Wheel*  4 MeshInstance3Ds, one surface each, at the hubs
# so draw calls per car = body surfaces + 4.
#
# Used by tests/fleet_design_check.gd, fleet_silhouette_sweep.gd and
# fleet_budget_scene.gd. Not a class_name on purpose: preload it, so the
# global class cache (#42) is not involved.

const PATH := "res://docs/design/fleet/proxies.json"

static func load_data() -> Dictionary:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("fleet proxies: cannot open %s (%s)" % [PATH, error_string(FileAccess.get_open_error())])
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		push_error("fleet proxies: %s is not a JSON object" % PATH)
		return {}
	return d

static func decode_points(b64: String) -> PackedVector3Array:
	var raw := Marshalls.base64_to_raw(b64)
	var n := raw.size() / 6
	var out := PackedVector3Array()
	out.resize(n)
	for i in n:
		out[i] = Vector3(raw.decode_s16(i * 6), raw.decode_s16(i * 6 + 2), raw.decode_s16(i * 6 + 4)) * 0.001
	return out

static func surface_kind(mat: String, data: Dictionary) -> String:
	if mat in data.emissive:
		return "glow"
	if mat in data.glass:
		return "glass"
	return "body"

# Same lookup as the B1 review page's viewer.
static func color_of(mat: String, car: Dictionary, data: Dictionary, paint_hex := "") -> Color:
	var o: Dictionary = car.colors
	if mat == "paint":
		return Color(paint_hex if paint_hex != "" else o.paint)
	if mat == "roof":
		if o.get("roof") != null:
			return Color(o.roof)
		return Color(paint_hex if paint_hex != "" else o.paint)
	if o.get(mat) != null:
		return Color(o[mat])
	if mat == "rim_bronze" and o.get("rim") != null:
		return Color(o.rim)
	var base: Variant = data.mats.get(mat)
	return Color(base) if base != null else Color("#C9CED6")

# Triangles come from Python with outward normal = (b - a) x (c - a), i.e.
# counter-clockwise seen from outside. Godot's front faces are clockwise, so
# each triangle is written as a, c, b.
static func build_mesh(tris: PackedVector3Array, mats: PackedByteArray, names: Array, car: Dictionary,
		data: Dictionary, mode: String, materials: Dictionary) -> ArrayMesh:
	var groups := {}
	for t in mats.size():
		var mname: String = names[mats[t]]
		var kind := "all" if mode == "silhouette" else surface_kind(mname, data)
		if not groups.has(kind):
			groups[kind] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
		var g: Array = groups[kind]
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var n := (b - a).cross(c - a).normalized()
		var col := color_of(mname, car, data)
		for p in [a, c, b]:
			g[0].append(p)
			g[1].append(n)
			g[2].append(col)
	var mesh := ArrayMesh.new()
	for kind in ["body", "glass", "glow", "all"]:
		if not groups.has(kind):
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = groups[kind][0]
		arrays[Mesh.ARRAY_NORMAL] = groups[kind][1]
		arrays[Mesh.ARRAY_COLOR] = groups[kind][2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials.get(kind))
	return mesh

static func make_materials(mode: String) -> Dictionary:
	if mode == "silhouette":
		var s := StandardMaterial3D.new()
		s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		s.albedo_color = Color.BLACK
		s.cull_mode = BaseMaterial3D.CULL_DISABLED
		return {"all": s}
	var body := StandardMaterial3D.new()
	body.vertex_color_use_as_albedo = true
	body.roughness = 0.55
	body.metallic = 0.12
	var glass := StandardMaterial3D.new()
	glass.vertex_color_use_as_albedo = true
	glass.roughness = 0.08
	glass.metallic = 0.4
	var glow := StandardMaterial3D.new()
	glow.vertex_color_use_as_albedo = true
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return {"body": body, "glass": glass, "glow": glow, "wheel": body}

# mode: "full" (game-like surfaces) or "silhouette" (one black unshaded surface).
# build_mesh takes "split" (body / glass / glow surfaces) or "silhouette".
static func build_car(data: Dictionary, car: Dictionary, build_name := "stock", mode := "full",
		materials := {}) -> Node3D:
	if materials.is_empty():
		materials = make_materials(mode)
	var b: Dictionary = {}
	for x in car.builds:
		if x.name == build_name:
			b = x
	assert(not b.is_empty(), "no build %s on %s" % [build_name, car.id])
	var root := Node3D.new()
	root.name = "%s_%s" % [car.id, build_name]
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = build_mesh(decode_points(b.body.pos), Marshalls.base64_to_raw(b.body.mat), b.names, car, data,
		"silhouette" if mode == "silhouette" else "split", materials)
	root.add_child(body)
	for i in b.wheels.size():
		var w: Dictionary = b.wheels[i]
		var wm := MeshInstance3D.new()
		wm.name = "Wheel%d" % i
		# Wheels have no glass or lights, so "split" gives them one surface.
		var wmats := materials if mode == "silhouette" else {"body": materials.wheel}
		wm.mesh = build_mesh(decode_points(w.pos), Marshalls.base64_to_raw(w.mat), b.names, car, data,
			mode if mode == "silhouette" else "split", wmats)
		wm.position = Vector3(w.hub[0], w.hub[1], w.hub[2])
		root.add_child(wm)
	root.set_meta("build", b)
	return root

static func find_build(car: Dictionary, build_name: String) -> Dictionary:
	for x in car.builds:
		if x.name == build_name:
			return x
	return {}

# All triangles of a build (body + wheels at their hubs) as a flat point list,
# for collision shapes. Winding does not matter there (backface collision on).
static func build_faces(b: Dictionary) -> PackedVector3Array:
	var faces := decode_points(b.body.pos)
	for w in b.wheels:
		var hub := Vector3(w.hub[0], w.hub[1], w.hub[2])
		for p in decode_points(w.pos):
			faces.append(p + hub)
	return faces
