extends RefCounted
class_name CarAssembler

# A car body from its separate parts (cars from parts, 2026-10-10).
#
# tools/car_pipeline/build_car.py writes assets/cars/<id>/body.glb with one
# named mesh per real part: body, hood, door_l/r, trunk, fender_fl/fr,
# bumper_f/r, the glass pieces, seals, lamps, mirrors, handles, plates and so
# on. Drawing those as they come would be 50-odd draw calls a car, so this
# class merges them BY MATERIAL at load into ONE ArrayMesh with four surfaces,
# the same four draw calls the sheet body and its door mirrors cost before:
#
#   body    paint and under_paint. Vertex alpha 0 marks paint (the shader
#           tints it), anything else carries its colour. Drawn with the car's
#           paint material (P1CoupeBuilder's), see paint_shader().
#   trim    plastic, rubber, chrome, plate, mirror glass, red lamp lens: one
#           material, the class is in the vertex alpha and picks roughness
#           and metal per vertex.
#   glass   the windows.
#   glow    lamp bulbs and lenses, unshaded.
#
# Every vertex also carries CUSTOM0: x = ao (ambient occlusion baked by the
# pipeline), y = shut (1 on a shut line, 0 six millimetres either side). The
# paint and trim shaders darken by both, which is what makes a 4 mm panel gap
# read from the chase camera.
#
# Merged meshes are cached per car and configuration, so a second car of the
# same kind costs nothing to build. Two configurations are kept:
#   closed  everything in the one mesh.
#   open    the parts under a hinge (hood, both doors with their glass, handle
#           and mirror, trunk) leave the body mesh and become one single-surface
#           mesh each under a Node3D on the hinge line, turned open: +4 draw
#           calls, only for a car that is standing with its panels open.
#
#   var body := CarAssembler.build("p1_coupe")                      # closed
#   var body := CarAssembler.build("p1_coupe", {"panels": "open"})
#   CarAssembler.swap_part(body, "bumper_f", other_mesh)            # body shop
#
# `parts` (build's second argument) says what differs from the glb: a part
# name mapped to a Mesh replaces that part (its surfaces named or materialled
# like the glb's: paint, plastic, ...; in the part's own frame), mapped to
# false leaves it off; "panels" is "closed" (default) or "open"; "split" is a
# list of hinge names whose parts leave the body as a panel mesh of their own
# on a hinge node turned to 0 degrees, for the game to swing (CarLids, engine
# bays B1): the hood alone is +1 draw call while it is up, nothing once shut.
#
# Engine bay parts (`engine`, `bay_*`: the rough placeholder boxes under the
# lids) are NOT in the closed body (engine bays B0, issue #642): nobody sees
# them behind a shut lid, so a driving car does not draw them. build_bay()
# makes them as a mesh of their own, which CarDetail builds only when detail
# is wanted (a panel open while stopped, photo mode, the garage). The open
# configuration (pictures with the lids up) keeps them in the body.

const GLB := "res://assets/cars/%s/body.glb"
const SURFACES := ["body", "trim", "glass", "glow"]
const NODE_NAME := "Body"
const BAY_NODE_NAME := "Bay"

const CLASS_PLASTIC := 1
const CLASS_RUBBER := 2
const CLASS_CHROME := 3
const CLASS_PLATE := 4
const CLASS_MIRROR := 5
const CLASS_LENS := 6
const CLASS_STEEL := 7
## glTF material name -> [surface, class]. On the body surface class 0 is
## paint (tinted at runtime), 8 is a fixed colour; on trim it picks the finish.
const MATERIALS := {
	"paint": ["body", 0],
	"under_paint": ["body", 8],
	# a panel that is not the car's colour: primer, rust, filler (the Bug)
	"paint_primer": ["body", 8],
	"paint_rust": ["body", 8],
	"paint_bondo": ["body", 8],
	"plastic": ["trim", CLASS_PLASTIC],
	"rubber": ["trim", CLASS_RUBBER],
	"chrome": ["trim", CLASS_CHROME],
	"plate": ["trim", CLASS_PLATE],
	"mirror": ["trim", CLASS_MIRROR],
	"lens_red": ["trim", CLASS_LENS],
	"steel": ["trim", CLASS_STEEL],
	"rim": ["trim", CLASS_STEEL],
	"glass": ["glass", 8],
	"glow_head": ["glow", 8],
	"glow_lens": ["glow", 8],
	"glow_tail": ["glow", 8],
	"glow_turn": ["glow", 8],
	# lamps of their own, dark until the game lights them
	"glow_brake": ["glow", 8],
	"glow_reverse": ["glow", 8],
}
## Vertex alpha of the switched lamps on the glow surface, the tags the lamp
## shader reads (NpcCarBuilder.GLOW_SHADER): 0.7 indicator, 0.8 brake lamp,
## 0.9 reverse. Every other glow material is 1.0, lit all the time.
const GLOW_TAGS := {"glow_turn": 0.7, "glow_brake": 0.8, "glow_reverse": 0.9}
const GLOW_ENERGY := 2.5
const CUSTOM0_FLAGS := Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT

## Roughness, metallic and specular per trim class, picked per vertex.
const TRIM_SHADER := """
shader_type spatial;
render_mode cull_back;
// COLOR.a * 8 is the class: 1 plastic, 2 rubber, 3 chrome, 4 plate, 5 mirror glass, 6 red lamp lens, 7 bare steel.
const vec3 FINISH[8] = vec3[](vec3(0.6, 0.0, 0.5), vec3(0.55, 0.0, 0.5), vec3(0.9, 0.0, 0.3), vec3(0.2, 1.0, 0.5),
	vec3(0.45, 0.0, 0.5), vec3(0.06, 1.0, 0.5), vec3(0.12, 0.0, 0.8), vec3(0.5, 0.7, 0.5));
varying vec2 ao_shut;
varying flat vec3 finish;
void vertex() {
	ao_shut = CUSTOM0.rg;
	finish = FINISH[clamp(int(COLOR.a * 8.0 + 0.5), 0, 7)];
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = finish.x;
	METALLIC = finish.y;
	SPECULAR = finish.z;
	ALBEDO *= mix(1.0, ao_shut.x, 0.7);
	ALBEDO *= 1.0 - 0.75 * ao_shut.y;
}
"""

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform float energy = 2.5;
void fragment() {
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * energy;
}
"""

static var _cars := {}          # car id -> what the glb holds, in car space
## Cars whose glb data stays cached: the one being driven plus one more (a
## rival, the garage's last look). Every car used to stay until quit, ~2 MB
## each (#609, measured 2026-10-13).
const KEEP_CARS := 2
static var _wheels := {}        # "car id|corner" -> ArrayMesh
static var _meshes := {}        # cache key -> {"body": ArrayMesh, "panels": {hinge: ArrayMesh}}
static var _paint_shaders := {} # base shader code -> Shader with the ao/shut hook
static var _trim_mat: ShaderMaterial
static var _glow_mat: ShaderMaterial
static var _glass_mat: StandardMaterial3D

# ---------- public ----------

static func has_car(car_id: String) -> bool:
	return ResourceLoader.exists(GLB % car_id)

## The car body as one MeshInstance3D named "Body" (surfaces body, trim,
## glass, glow), with a Node3D per open panel under it when parts.panels is
## "open". Null if the car has no glb. Materials: trim, glass and glow are
## set; the body surface gets `paint_mat` if one is passed (the caller's paint
## material built on paint_shader()).
static func build(car_id: String, parts: Dictionary = {}, paint_mat: Material = null) -> MeshInstance3D:
	var car := _load(car_id)
	if car.parts.is_empty():
		return null
	var body := MeshInstance3D.new()
	body.name = NODE_NAME
	body.set_meta("car_id", car_id)
	_apply(body, parts, paint_mat)
	return body

## Re-merge a built body for a new `parts` configuration: the mesh, the
## metas, the materials and the hinge nodes (one per split or open panel,
## named after the hinge, with a "Panel" MeshInstance3D under it). Hinge
## nodes the new configuration does not need are freed. Cached meshes, so
## switching back and forth costs no geometry work after the first time.
static func _apply(body: MeshInstance3D, parts: Dictionary, paint_mat: Material) -> void:
	var car_id: String = body.get_meta("car_id")
	var car := _load(car_id)
	var built := _merged(car_id, parts)
	var open := String(parts.get("panels", "closed")) == "open"
	# a re-merge keeps the materials the builder put on the surfaces (the
	# coupe's glass, the lamp shader on glow) instead of the defaults
	var kept := {}
	if body.mesh != null:
		for i in body.mesh.get_surface_count():
			var m := body.get_surface_override_material(i)
			if m != null:
				kept[(body.mesh as ArrayMesh).surface_get_name(i)] = m
	body.mesh = built.body
	body.set_meta("car_parts", parts.duplicate())
	_dress(body, paint_mat)
	for sname in kept:
		var si := surface_index(body.mesh, sname)
		if si >= 0:
			body.set_surface_override_material(si, kept[sname])
	for c in body.get_children():
		if c is Node3D and car.hinges.has(String(c.name)) and not built.panels.has(String(c.name)):
			body.remove_child(c)
			c.queue_free()
	for hname in built.panels:
		var h: Dictionary = car.hinges[hname]
		var hinge := body.get_node_or_null(NodePath(hname)) as Node3D
		if hinge == null:
			hinge = Node3D.new()
			hinge.name = hname
			body.add_child(hinge)
		hinge.transform = Transform3D(Basis(), h.origin)
		if open:
			hinge.rotate(h.axis, deg_to_rad(h.open_sign * h.open_deg))
		var panel := hinge.get_node_or_null("Panel") as MeshInstance3D
		if panel == null:
			panel = MeshInstance3D.new()
			panel.name = "Panel"
			hinge.add_child(panel)
		panel.mesh = built.panels[hname]
		panel.layers = body.layers
		if paint_mat != null:
			panel.set_surface_override_material(0, paint_mat)

## Which hinges' panels are split out of a built body (the "split" option).
static func split_hinges(body: MeshInstance3D) -> PackedStringArray:
	return PackedStringArray((body.get_meta("car_parts", {}) as Dictionary).get("split", []))

## Split these hinges' panels out of the body (or merge them back in with an
## empty list) on a built car, keeping every other option. Returns the hinge
## nodes by name. The body's paint material is kept.
static func set_split(body: MeshInstance3D, hinge_names: PackedStringArray) -> Dictionary:
	var parts: Dictionary = (body.get_meta("car_parts", {}) as Dictionary).duplicate()
	var names := Array(hinge_names)
	names.sort()
	if names.is_empty():
		parts.erase("split")
	else:
		parts["split"] = PackedStringArray(names)
	var paint_mat := body.get_surface_override_material(surface_index(body.mesh, "body"))
	_apply(body, parts, paint_mat)
	var out := {}
	for hname in names:
		out[hname] = body.get_node_or_null(NodePath(hname))
	return out

## The engine bay parts as one MeshInstance3D named "Bay" in car space (the
## same frame as build()'s body, so it goes under that body), surfaces as
## build()'s. Null if the car has no bay parts.
static func build_bay(car_id: String, paint_mat: Material = null) -> MeshInstance3D:
	if bay_part_names(car_id).is_empty():
		return null
	var built := _merged(car_id, {"bay": "only"})
	var bay := MeshInstance3D.new()
	bay.name = BAY_NODE_NAME
	bay.mesh = built.body
	_dress(bay, paint_mat)
	return bay

## True for a part that belongs to the engine bay (or the Bug's front-lid
## bay): `engine` and every `bay_*` mesh. The `bay_*` empties are anchors,
## not parts, and are not affected.
static func is_bay_part(part: String) -> bool:
	return part == "engine" or part.begins_with("bay_")

## The car's bay parts, sorted.
static func bay_part_names(car_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for pname: String in _load(car_id).parts:
		if is_bay_part(pname):
			out.append(pname)
	out.sort()
	return out

## Replace one part of a built car with another mesh (or null to take it off)
## and re-merge: the body-shop proof for the mod tree. `root` is the node
## build() returned or anything above it. Returns false if there is no
## assembled body under root or the car has no such part.
static func swap_part(root: Node, part: String, mesh: Mesh) -> bool:
	var body := body_of(root)
	if body == null:
		return false
	var car_id: String = body.get_meta("car_id")
	if not _load(car_id).parts.has(part):
		return false
	var parts: Dictionary = (body.get_meta("car_parts") as Dictionary).duplicate()
	parts[part] = mesh if mesh != null else false
	var paint_mat := body.get_surface_override_material(surface_index(body.mesh, "body"))
	_apply(body, parts, paint_mat)
	return true

## The assembled body under (or at) a node, or null.
static func body_of(root: Node) -> MeshInstance3D:
	if root == null:
		return null
	if root is MeshInstance3D and root.has_meta("car_id"):
		return root
	for c in root.get_children():
		var b := body_of(c)
		if b != null:
			return b
	return null

static func surface_index(mesh: Mesh, sname: String) -> int:
	for i in mesh.get_surface_count():
		if (mesh as ArrayMesh).surface_get_name(i) == sname:
			return i
	return -1

## Part names in the glb (wheels left out: the game draws its own).
static func part_names(car_id: String) -> PackedStringArray:
	return PackedStringArray(_load(car_id).parts.keys())

## hinge name -> {origin, axis, open_sign, open_deg, parts}
static func hinges(car_id: String) -> Dictionary:
	return _load(car_id).hinges

## One wheel as the glb has it (tyre, rim, brake, hubcap or wheel nuts), hub at
## the origin, for the corner "fl", "fr", "rl" or "rr": ONE surface drawn with
## trim_material(), so a wheel stays one draw call with its brake in it. Each
## corner is modelled where it sits, so a left wheel is not turned round. Null
## if the glb has no such wheel. The baked ao is left out: a wheel turns.
static func wheel_mesh(car_id: String, corner: String) -> ArrayMesh:
	var key := car_id + "|" + corner
	if _wheels.has(key):
		return _wheels[key]
	var mats: Dictionary = _load(car_id).wheels.get(corner, {})
	var mesh: ArrayMesh = null
	if not mats.is_empty():
		var b := _builder()
		for mname in mats:
			var m: Dictionary = mats[mname]
			var info: Array = MATERIALS[mname]
			var col := (m.albedo as Color).srgb_to_linear()
			col.a = float(info[1] if info[0] == "trim" else CLASS_PLASTIC) / 8.0
			var open := (m.ao as PackedByteArray).duplicate()
			for k in range(0, open.size(), 4):
				open[k] = 255
				open[k + 1] = 0
			_append(b, {"v": m.v, "n": m.n, "ao": open, "i": m.i}, col, Vector3.ZERO)
		mesh = ArrayMesh.new()
		_add_surface(mesh, b, "trim")
	_wheels[key] = mesh
	return mesh

## Triangles in one wheel_mesh().
static func wheel_triangle_count(car_id: String, corner: String) -> int:
	var m := wheel_mesh(car_id, corner)
	return _mesh_tris(m) if m != null else 0

## The corners the glb has a wheel mesh for.
static func wheel_corners(car_id: String) -> PackedStringArray:
	return PackedStringArray(_load(car_id).wheels.keys())

## Car-space transform of a named empty in the glb (slot_*, tip_*, mount_*, ...).
static func anchor(car_id: String, anchor_name: String) -> Transform3D:
	return _load(car_id).anchors.get(anchor_name, Transform3D.IDENTITY)

## One part's triangles as the glb has them, in car space:
## {material name: {v, n, ao (4 bytes a vertex: ao, shut, 0, 255), i, albedo}}.
static func part_arrays(car_id: String, part: String) -> Dictionary:
	var p: Dictionary = _load(car_id).parts.get(part, {})
	return p.get("mats", {})

## Bounding box of one part in car space.
static func part_aabb(car_id: String, part: String) -> AABB:
	var p: Dictionary = _load(car_id).parts.get(part, {})
	var box := AABB()
	var first := true
	for mname in p.get("mats", {}):
		for v in (p.mats[mname].v as PackedVector3Array):
			if first:
				box = AABB(v, Vector3.ZERO)
				first = false
			else:
				box = box.expand(v)
	return box

## Centres of the lit lamp elements, left then right: {"head": [l, r], "tail": [l, r]}.
static func lamp_centres(car_id: String) -> Dictionary:
	var car := _load(car_id)
	var out := {}
	for kind in ["head", "tail"]:
		var pair := [Vector3.ZERO, Vector3.ZERO]
		var n := [0, 0]
		for pname in car.parts:
			var mats: Dictionary = car.parts[pname].mats
			if not mats.has("glow_" + kind):
				continue
			for v in (mats["glow_" + kind].v as PackedVector3Array):
				var side := 0 if v.x < 0.0 else 1
				pair[side] += v
				n[side] += 1
		out[kind] = [pair[0] / maxi(n[0], 1), pair[1] / maxi(n[1], 1)]
	return out

## Triangles in the merged body (all surfaces) for a configuration, open panels included.
static func triangle_count(car_id: String, parts: Dictionary = {}) -> int:
	var built := _merged(car_id, parts)
	var n := _mesh_tris(built.body)
	for h in built.panels:
		n += _mesh_tris(built.panels[h])
	return n

## Draw calls of the body for a configuration: its surfaces plus one per open panel.
static func draw_call_count(car_id: String, parts: Dictionary = {}) -> int:
	var built := _merged(car_id, parts)
	return (built.body as ArrayMesh).get_surface_count() + built.panels.size()

## The car paint shader with the ao and shut darkening added: `base` is the
## shader the paint material is built on (P1CoupeBuilder.BODY_SHADER or
## whatever replaces it). Its uniforms and look are untouched; the hook is two
## lines at the end of fragment(). If the code is not shaped as expected the
## base shader is used as it is (the car still draws, without the darkening).
static func paint_shader(base: String) -> Shader:
	if not _paint_shaders.has(base):
		var s := Shader.new()
		s.code = paint_shader_code(base)
		_paint_shaders[base] = s
	return _paint_shaders[base]

static func paint_shader_code(base: String) -> String:
	var frag := base.find("void fragment()")
	var last := base.rfind("}")
	if frag < 0 or last < frag or base.find("\nvoid ", frag + 1) >= 0:
		push_warning("CarAssembler: paint shader not shaped as expected, ao/shut hook left out")
		return base
	var code := base.substr(0, last) + "\tALBEDO *= mix(1.0, ao_shut.x, 0.7);\n\tALBEDO *= 1.0 - 0.75 * ao_shut.y;\n" + base.substr(last)
	var vert := code.find("void vertex()")
	if vert >= 0:
		var brace := code.find("{", vert)
		code = code.substr(0, brace + 1) + "\n\tao_shut = CUSTOM0.rg;" + code.substr(brace + 1)
		code = code.substr(0, vert) + "varying vec2 ao_shut;\n" + code.substr(vert)
	else:
		frag = code.find("void fragment()")
		code = code.substr(0, frag) + "varying vec2 ao_shut;\nvoid vertex() {\n\tao_shut = CUSTOM0.rg;\n}\n" + code.substr(frag)
	return code

static func trim_material() -> ShaderMaterial:
	if _trim_mat == null:
		# CarPaint's trim variant: TRIM_SHADER plus the city and the lamps on
		# chrome and mirror glass (look upgrade, 2026-10-11).
		_trim_mat = ShaderMaterial.new()
		_trim_mat.shader = CarPaint.parts_trim_shader()
	return _trim_mat

static func glow_material() -> ShaderMaterial:
	if _glow_mat == null:
		var s := Shader.new()
		s.code = GLOW_SHADER
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = s
		_glow_mat.set_shader_parameter("energy", GLOW_ENERGY)
	return _glow_mat

static func glass_material() -> StandardMaterial3D:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.vertex_color_use_as_albedo = false
		_glass_mat.albedo_color = Color(Color("#151D2E"), 0.5)
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mat.metallic = 0.6
		_glass_mat.roughness = 0.08
	return _glass_mat

## Forget every loaded car and merged mesh (tests; a rebuilt glb).
static func clear_cache() -> void:
	_cars.clear()
	_meshes.clear()
	_wheels.clear()

## Drops one car's decoded glb and its merged meshes from the caches. Nodes
## still drawing them keep their own references; a later build re-reads it.
static func _forget(car_id: String) -> void:
	_cars.erase(car_id)
	var prefix := car_id + "|"
	for cache: Dictionary in [_meshes, _wheels]:
		for key: String in cache.keys():
			if key.begins_with(prefix):
				cache.erase(key)

# ---------- loading ----------

## What the glb holds, read once: every part's triangles per material in car
## space, the hinges and the named empties.
static func _load(car_id: String) -> Dictionary:
	if _cars.has(car_id):
		# Most recently used last, so the oldest is the one dropped below.
		var hit: Dictionary = _cars[car_id]
		_cars.erase(car_id)
		_cars[car_id] = hit
		return hit
	while _cars.size() >= KEEP_CARS:
		_forget(_cars.keys()[0])
	var car := {"parts": {}, "hinges": {}, "anchors": {}, "wheels": {}}
	_cars[car_id] = car
	if not has_car(car_id):
		return car
	var scene := load(GLB % car_id) as PackedScene
	if scene == null:
		return car
	var root := scene.instantiate()
	_walk(root, Transform3D.IDENTITY, "", car)
	root.free()
	return car

static func _walk(node: Node, xf: Transform3D, hinge: String, car: Dictionary) -> void:
	for c in node.get_children():
		if not (c is Node3D):
			continue
		var n3 := c as Node3D
		var t := xf * n3.transform
		var nm := String(n3.name)
		var under := hinge
		if nm.begins_with("wheel_"):
			# the hub, and the wheel's own mesh in the hub's frame
			car.anchors[nm] = t
			for w in n3.get_children():
				if w is MeshInstance3D and (w as MeshInstance3D).mesh != null and _known((w as MeshInstance3D).mesh):
					car.wheels[nm.trim_prefix("wheel_")] = read_mesh((w as MeshInstance3D).mesh, (w as Node3D).transform)
			continue
		if nm.begins_with("hinge_"):
			car.hinges[nm] = _hinge(n3, t)
			under = nm
		elif n3 is MeshInstance3D and (n3 as MeshInstance3D).mesh != null:
			car.parts[nm] = {"hinge": hinge, "xf": t, "mats": read_mesh((n3 as MeshInstance3D).mesh, t)}
			if hinge != "":
				car.hinges[hinge].parts.append(nm)
		else:
			car.anchors[nm] = t
		_walk(n3, t, under, car)

## True when every surface of the mesh wears a material the assembler knows.
## The pilot coupe's wheel meshes keep the design sheet's names (the game
## draws its own wheels there), so they are left alone.
static func _known(mesh: Mesh) -> bool:
	for si in mesh.get_surface_count():
		var mat := mesh.surface_get_material(si)
		if mat == null or not MATERIALS.has(mat.resource_name):
			return false
	return true

static func _hinge(node: Node3D, t: Transform3D) -> Dictionary:
	# the pipeline writes axis, open_sign and open_deg as glTF extras
	var ex: Dictionary = node.get_meta("extras", {})
	var nm := String(node.name)
	var door := nm.contains("door")
	var axis: Variant = ex.get("axis", [0, 1, 0] if door else [1, 0, 0])
	var sign_default := (-1.0 if nm.ends_with("_l") else 1.0) if door else (-1.0 if nm.contains("trunk") else 1.0)
	return {
		"origin": t.origin,
		"axis": Vector3(axis[0], axis[1], axis[2]).normalized(),
		"open_sign": float(ex.get("open_sign", sign_default)),
		"open_deg": float(ex.get("open_deg", 60.0 if door else 45.0)),
		"parts": [],
	}

## One mesh as {material name: {v, n, ao, i, albedo}}, moved by `xf`. The
## material name is the surface material's resource name (what the glTF
## importer leaves) or, failing that, the surface name.
static func read_mesh(mesh: Mesh, xf: Transform3D) -> Dictionary:
	var out := {}
	for si in mesh.get_surface_count():
		var mat := mesh.surface_get_material(si)
		var mname := mat.resource_name if mat != null else ""
		if mname == "" and mesh is ArrayMesh:
			mname = (mesh as ArrayMesh).surface_get_name(si)
		if not MATERIALS.has(mname):
			push_warning("CarAssembler: material '%s' is not one the assembler knows, drawn as plastic" % mname)
			mname = "plastic"
		var arrays := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(v.size())
			for k in v.size():
				idx[k] = k
		var albedo := Color.WHITE
		if mat is BaseMaterial3D:
			albedo = (mat as BaseMaterial3D).albedo_color
		if not out.has(mname):
			out[mname] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "ao": PackedByteArray(), "i": PackedInt32Array(), "albedo": albedo}
		var dst: Dictionary = out[mname]
		var base: int = dst.v.size()
		var ao: PackedByteArray = dst.ao
		ao.resize((base + v.size()) * 4)
		var has_n := n.size() == v.size()
		var has_c := col.size() == v.size()
		for k in v.size():
			dst.v.append(xf * v[k])
			dst.n.append((xf.basis * n[k]).normalized() if has_n else Vector3.UP)
			# CUSTOM0: x = ao, y = shut. A mesh without the bake is fully open, no shut line.
			ao[(base + k) * 4] = clampi(roundi(col[k].r * 255.0), 0, 255) if has_c else 255
			ao[(base + k) * 4 + 1] = clampi(roundi(col[k].g * 255.0), 0, 255) if has_c else 0
			ao[(base + k) * 4 + 2] = 0
			ao[(base + k) * 4 + 3] = 255
		dst.ao = ao
		for k in idx:
			dst.i.append(base + k)
	return out

# ---------- merging ----------

static func _key(car_id: String, parts: Dictionary) -> String:
	var bits := PackedStringArray()
	var names: Array = parts.keys()
	names.sort()
	for k in names:
		var val: Variant = parts[k]
		if val is Mesh:
			bits.append("%s=mesh%d" % [k, (val as Mesh).get_instance_id()])
		elif val is PackedStringArray or val is Array:
			bits.append("%s=%s" % [k, "+".join(PackedStringArray(val))])
		else:
			bits.append("%s=%s" % [k, str(val)])
	return car_id + "|" + ",".join(bits)

static func _merged(car_id: String, parts: Dictionary) -> Dictionary:
	var key := _key(car_id, parts)
	if _meshes.has(key):
		return _meshes[key]
	var car := _load(car_id)
	var open := String(parts.get("panels", "closed")) == "open"
	# hinges whose panels leave the body for the game to swing (CarLids)
	var split: Array = Array(parts.get("split", []))
	# closed: no bay parts; open (pictures): the bay stays in; "only": just the bay
	var bay_only := String(parts.get("bay", "")) == "only"
	var surf := {}      # surface name -> builder
	var panels := {}    # hinge name -> builder (one surface)
	var names: Array = car.parts.keys()
	names.sort()
	for pname in names:
		var p: Dictionary = car.parts[pname]
		var in_bay := is_bay_part(pname)
		if (bay_only and not in_bay) or (in_bay and not bay_only and not open):
			continue
		var mats: Dictionary = p.mats
		if parts.has(pname):
			var swap: Variant = parts[pname]
			if swap is Mesh:
				mats = read_mesh(swap, p.xf)
			else:
				continue          # false / null: the part is off the car
		var hinge: String = "" if bay_only else p.hinge
		for mname in mats:
			var m: Dictionary = mats[mname]
			var info: Array = MATERIALS[mname]
			var col := (m.albedo as Color).srgb_to_linear()
			if hinge != "" and (open or split.has(hinge)):
				# an open panel is one surface drawn with the paint material:
				# paint keeps alpha 0, everything else rides along as a fixed colour
				col.a = 0.0 if mname == "paint" else 1.0
				if not panels.has(hinge):
					panels[hinge] = _builder()
				_append(panels[hinge], m, col, -(car.hinges[hinge].origin as Vector3))
			else:
				col.a = float(info[1]) / 8.0
				if info[0] == "glass":
					col.a = 1.0
				elif info[0] == "glow":
					col.a = GLOW_TAGS.get(mname, 1.0)
				if not surf.has(info[0]):
					surf[info[0]] = _builder()
				_append(surf[info[0]], m, col, Vector3.ZERO)
	var body := ArrayMesh.new()
	for sname in SURFACES:
		if surf.has(sname):
			_add_surface(body, surf[sname], sname)
	var panel_meshes := {}
	for hname in panels:
		var pm := ArrayMesh.new()
		_add_surface(pm, panels[hname], "body")
		panel_meshes[hname] = pm
	var built := {"body": body, "panels": panel_meshes}
	_meshes[key] = built
	return built

static func _builder() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "ao": PackedByteArray(), "i": PackedInt32Array()}

static func _append(b: Dictionary, m: Dictionary, col: Color, offset: Vector3) -> void:
	var base: int = b.v.size()
	var count: int = m.v.size()
	if offset == Vector3.ZERO:
		b.v.append_array(m.v)
	else:
		for v in (m.v as PackedVector3Array):
			b.v.append(v + offset)
	b.n.append_array(m.n)
	var cols := PackedColorArray()
	cols.resize(count)
	cols.fill(col)
	b.c.append_array(cols)
	b.ao.append_array(m.ao)
	for k in (m.i as PackedInt32Array):
		b.i.append(base + k)

static func _add_surface(mesh: ArrayMesh, b: Dictionary, sname: String) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = b.v
	arrays[Mesh.ARRAY_NORMAL] = b.n
	arrays[Mesh.ARRAY_COLOR] = b.c
	arrays[Mesh.ARRAY_CUSTOM0] = b.ao
	arrays[Mesh.ARRAY_INDEX] = b.i
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, CUSTOM0_FLAGS)
	mesh.surface_set_name(mesh.get_surface_count() - 1, sname)

## Surface materials for a merged body: trim, glass and glow are the shared
## ones; body takes the caller's paint material.
static func _dress(body: MeshInstance3D, paint_mat: Material) -> void:
	var mesh := body.mesh as ArrayMesh
	for i in mesh.get_surface_count():
		match mesh.surface_get_name(i):
			"body":
				body.set_surface_override_material(i, paint_mat)
			"trim":
				body.set_surface_override_material(i, trim_material())
			"glass":
				body.set_surface_override_material(i, glass_material())
			"glow":
				body.set_surface_override_material(i, glow_material())

static func _mesh_tris(mesh: Mesh) -> int:
	var n := 0
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n
