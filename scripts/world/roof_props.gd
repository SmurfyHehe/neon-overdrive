extends RefCounted

# Rooftop props (buildings step 3, 2026-10-07): the flat box roof was what
# made every building read the same against the sky glow. Water tanks on
# legs, AC boxes, stair bulkheads, plant-room crowns on offices, antenna
# masts and billboard poles break the silhouette.
#
# All of them are ONE MultiMesh per chunk with one material, so the whole
# skyline of a chunk is one draw call. The trick: one mesh holds every prop
# shape, each vertex tagged with its shape id (UV2.x); the vertex shader
# collapses every shape except the one the instance asks for (custom data
# r) to a point, so it draws as nothing. Scaled boxes cover AC units,
# bulkheads, crowns and billboard poles; the tank and the antenna are their
# own shapes. Billboard faces are signs (scripts/world/building_signs.gd).

const BuildingSigns := preload("res://scripts/world/building_signs.gd")

const SHAPE_BOX := 0
const SHAPE_TANK := 1
const SHAPE_ANTENNA := 2
const SHAPE_CANOPY := 3  # gas station canopy slab, lit underside
const SHAPE_FLOOD := 4   # pole with a floodlight head (yards, car park roofs)

# Glow kinds (UV2.y): which light a face gives off.
const GLOW_RED := 1.0    # aviation light
const GLOW_TUBE := 2.0   # cold fluorescent (gas canopy, car park roof)
const GLOW_FLOOD := 3.0  # sodium yard flood

const CAPACITY := 20  # per chunk; keeps the chunk under its triangle budget

const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

varying vec3 tint;
varying float glow;

void vertex() {
	if (abs(UV2.x - INSTANCE_CUSTOM.r) > 0.5) {
		VERTEX = vec3(0.0);  // not this instance's shape: collapse it
	}
	tint = INSTANCE_CUSTOM.gba;
	glow = UV2.y;
}

void fragment() {
	ALBEDO = COLOR.rgb * tint;
	ROUGHNESS = 0.9;
	// 1: aviation light, a small steady red like the traffic tail lamps
	// 2: cold fluorescent tubes   3: sodium floodlight
	vec3 e = vec3(0.0);
	if (glow > 0.5 && glow < 1.5) { e = vec3(1.0, 0.12, 0.06) * 1.6; }
	else if (glow > 1.5 && glow < 2.5) { e = vec3(0.8, 0.95, 0.76) * 1.3; }
	else if (glow > 2.5) { e = vec3(1.0, 0.66, 0.3) * 2.2; }
	EMISSION = e;
}
"""

static var _mesh: ArrayMesh
static var _material: ShaderMaterial

static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
	return _material

static func new_multimesh() -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh()
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "RoofProps"
	mmi.multimesh = mm
	mmi.material_override = material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

## Fills the chunk's prop buffer from the dressed buildings (infos from
## RoadChunkBuilder._update_building). Billboard faces go to the sign
## buffer from slot first_sign on. Returns [props drawn, signs in use].
static func update(mm: MultiMesh, infos: Array, signs: MultiMesh, first_sign: int) -> Array:
	var n := 0
	var n_signs := first_sign
	var rng := RandomNumberGenerator.new()
	for info in infos:
		if info.empty:
			continue
		rng.seed = int(info.roof_seed)
		var side := int(info.side)
		var w: float = info.w
		var d: float = info.d
		var h: float = info.h
		var cx: float = (float(info.front_x_abs) + w / 2.0) * float(side)
		var cz: float = info.z
		var kind: String = info.type
		var props := []  # [shape, scale, offset (x across from road, z along), tint]
		match kind:
			"apartment":
				if rng.randf() < 0.7:
					props.append([SHAPE_BOX, Vector3(2.2, 2.6, 2.6), _spot(rng, w, d, 0.5), 0.55])  # stair bulkhead
				if rng.randf() < 0.55:
					props.append([SHAPE_TANK, Vector3.ONE * rng.randf_range(0.85, 1.15), _spot(rng, w, d, 0.6), 1.0])
					if rng.randf() < 0.3:
						props.append([SHAPE_TANK, Vector3.ONE * rng.randf_range(0.75, 1.0), _spot(rng, w, d, 0.6), 1.0])
				for k in rng.randi() % 3:
					props.append([SHAPE_BOX, Vector3(1.1, 0.9, 1.3), _spot(rng, w, d, 0.8), 0.75])  # AC unit
				if rng.randf() < 0.25:
					props.append([SHAPE_ANTENNA, Vector3(1, rng.randf_range(0.8, 1.3), 1), _spot(rng, w, d, 0.7), 0.6])
			"office":
				if rng.randf() < 0.75:
					# plant-room crown: the stepped top that ends an office tower
					props.append([SHAPE_BOX, Vector3(w * 0.55, rng.randf_range(3.0, 4.5), d * 0.5), Vector2.ZERO, 0.45])
				for k in 1 + rng.randi() % 3:
					props.append([SHAPE_BOX, Vector3(1.4, 1.1, 1.8), _spot(rng, w, d, 0.85), 0.75])
				if rng.randf() < 0.45:
					props.append([SHAPE_ANTENNA, Vector3(1, rng.randf_range(1.2, 2.0), 1), _spot(rng, w, d, 0.4), 0.6])
			"shop":
				for k in 1 + rng.randi() % 2:
					props.append([SHAPE_BOX, Vector3(1.1, 0.9, 1.3), _spot(rng, w, d, 0.8), 0.75])
			"parking":
				props.append([SHAPE_BOX, Vector3(3.0, 3.0, 3.2), _spot(rng, w, d, 0.6), 0.5])  # stair and lift core
			"warehouse":
				# roof vents and a fan housing on the long low roof
				for k in 1 + rng.randi() % 3:
					props.append([SHAPE_BOX, Vector3(1.6, 1.0, 1.6), _spot(rng, w, d, 0.8), 0.6])
			"garage":
				if rng.randf() < 0.5:
					props.append([SHAPE_BOX, Vector3(1.1, 0.9, 1.3), _spot(rng, w, d, 0.8), 0.75])
		if kind == "gas":
			props.append_array(_gas_station(info))
		elif kind == "diner":
			# the sign pole, at the front of the lot (absolute position)
			props.append([SHAPE_BOX, Vector3(0.3, 7.0, 0.3), _abs(info, 1.2, float(info.d) * 0.35, 0.0), 0.35])
		elif kind == "warehouse" and rng.randf() < 0.7:
			# yard floodlight on the front edge of the roof
			props.append([SHAPE_FLOOD, Vector3.ONE, Vector2(-w * 0.45, rng.randf_range(-0.4, 0.4) * d), 1.0])
		elif kind == "parking":
			for k in 2:
				props.append([SHAPE_FLOOD, Vector3(1, 0.6, 1), Vector2(rng.randf_range(-0.3, 0.3) * w, (float(k) - 0.5) * d * 0.6), 1.0])
		var billboard: float = {"shop": 0.3, "garage": 0.35}.get(kind, 0.0) * float(info.get("billboard", 1.0))
		var wants_billboard := rng.randf() < billboard and h < 12.0
		for p in props:
			if n >= CAPACITY:
				break
			var pos: Vector3
			if p[2] is Vector3:
				pos = p[2]  # already placed on the ground (gas station, diner pole)
			else:
				var off: Vector2 = p[2]
				pos = Vector3(cx + off.x * float(side), h, cz + off.y)
			_put(mm, n, p[0], Basis.from_scale(p[1]), pos, float(p[3]))
			n += 1
		if wants_billboard and n + 2 <= CAPACITY and n_signs < signs.instance_count:
			n = _billboard(mm, n, signs, n_signs, rng, info)
			n_signs += 1
	mm.visible_instance_count = n
	return [n, n_signs]

## A point on the ground (or at height y) `x_in` metres into the building's
## lot from its front line and `dz` along the road from its centre.
static func _abs(info: Dictionary, x_in: float, dz: float, y: float) -> Vector3:
	return Vector3((float(info.lot_front_x_abs) + x_in) * float(info.side), y, float(info.z) + dz)

## Canopy over the forecourt on four columns, with two pump islands under
## it. 7 props.
static func _gas_station(info: Dictionary) -> Array:
	var length := minf(float(info.d), 14.0)
	var out := []
	out.append([SHAPE_CANOPY, Vector3(8.0, 0.6, length), _abs(info, 4.5, 0.0, 4.6), 0.55])
	for cx in [1.5, 7.5]:
		for cz in [-0.35, 0.35]:
			out.append([SHAPE_BOX, Vector3(0.35, 4.6, 0.35), _abs(info, cx, cz * length, 0.0), 0.7])
	for pz in [-0.2, 0.2]:
		out.append([SHAPE_BOX, Vector3(0.7, 1.5, 1.1), _abs(info, 4.5, pz * length, 0.0), 0.9])
	return out

## A random spot on a w x d roof, kept `keep` of the way in from the edges.
static func _spot(rng: RandomNumberGenerator, w: float, d: float, keep: float) -> Vector2:
	return Vector2(rng.randf_range(-0.5, 0.5) * w * keep, rng.randf_range(-0.5, 0.5) * d * keep)

static func _put(mm: MultiMesh, i: int, shape: int, basis: Basis, pos: Vector3, tint: float) -> void:
	mm.set_instance_transform(i, Transform3D(basis, pos))
	mm.set_instance_custom_data(i, Color(float(shape), tint, tint * 0.97, tint * 0.92))

## A billboard on two poles near the roof's front edge, angled toward the
## traffic coming down the road. Uses 2 prop slots and 1 sign slot.
static func _billboard(mm: MultiMesh, n: int, signs: MultiMesh, sign_i: int, rng: RandomNumberGenerator, info: Dictionary) -> int:
	var side := int(info.side)
	var h: float = info.h
	var panel_h := 2.0
	var lift := 2.2
	var angle := 0.45
	var word: String = BuildingSigns.BILLBOARD_WORDS[rng.randi() % BuildingSigns.BILLBOARD_WORDS.size()]
	var color := 0 if rng.randf() < 0.7 else 3  # mostly amber, some dusk blue
	var front_x := (float(info.front_x_abs) + 1.4) * float(side)
	var center := Vector3(front_x, h + lift + panel_h / 2.0, info.z)
	BuildingSigns.place(signs, sign_i, word, color, 2, center, side, panel_h, minf(float(info.d) * 0.9, 9.0), false, angle)
	# poles under the panel's two ends, along the panel's own length axis
	var panel := signs.get_instance_transform(sign_i)
	var along := panel.basis.z
	var pole_h := lift + panel_h * 0.5
	for k in [-0.35, 0.35]:
		var p := panel.origin + along * float(k)
		_put(mm, n, SHAPE_BOX, Basis.from_scale(Vector3(0.22, pole_h, 0.22)), Vector3(p.x, h, p.z), 0.4)
		n += 1
	return n

# ---------- the shared mesh ----------

static func mesh() -> ArrayMesh:
	if _mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# box: unit footprint, bottom at y = 0 (scaled per instance)
		_box(st, SHAPE_BOX, Vector3(0, 0.5, 0), Vector3.ONE, Color(0.55, 0.54, 0.52))
		# water tank on legs (~3.6 m): weathered timber barrel, steel legs
		var leg := Color(0.22, 0.21, 0.2)
		for sx in [-0.55, 0.55]:
			for sz in [-0.55, 0.55]:
				_box(st, SHAPE_TANK, Vector3(sx, 0.65, sz), Vector3(0.12, 1.3, 0.12), leg)
		_box(st, SHAPE_TANK, Vector3(0, 1.35, 0), Vector3(1.5, 0.1, 1.5), leg)
		_cylinder(st, SHAPE_TANK, Vector3(0, 1.4, 0), 0.75, 1.8, 0.4, 6, Color(0.42, 0.3, 0.2))
		# antenna mast (~6 m) with two cross arms and a red light on top
		var steel := Color(0.4, 0.4, 0.42)
		_box(st, SHAPE_ANTENNA, Vector3(0, 3.0, 0), Vector3(0.1, 6.0, 0.1), steel)
		_box(st, SHAPE_ANTENNA, Vector3(0, 4.2, 0), Vector3(1.6, 0.06, 0.06), steel)
		_box(st, SHAPE_ANTENNA, Vector3(0, 5.2, 0), Vector3(0.06, 0.06, 1.2), steel)
		_box(st, SHAPE_ANTENNA, Vector3(0, 6.05, 0), Vector3(0.18, 0.18, 0.18), Color(0.3, 0.05, 0.03), GLOW_RED)
		# canopy: unit slab (scaled per station), the underside is the light
		_box(st, SHAPE_CANOPY, Vector3(0, 0.5, 0), Vector3.ONE, Color(0.62, 0.6, 0.56), 0.0, GLOW_TUBE)
		# floodlight: 5 m pole, a head leaning over the yard
		_box(st, SHAPE_FLOOD, Vector3(0, 2.5, 0), Vector3(0.14, 5.0, 0.14), steel)
		_box(st, SHAPE_FLOOD, Vector3(0, 5.0, 0), Vector3(0.5, 0.3, 0.7), Color(0.25, 0.2, 0.12), GLOW_FLOOD)
		_mesh = st.commit()
	return _mesh

# Triangles are wound clockwise seen from outside (Godot's front face), with
# flat normals. Each part is convex, so a face is oriented by pointing its
# normal away from the part's own centre.
static func _tri(st: SurfaceTool, shape: int, a: Vector3, b: Vector3, c: Vector3, centre: Vector3, col: Color, glow: float) -> void:
	var nrm := (c - a).cross(b - a).normalized()
	if nrm.dot((a + b + c) / 3.0 - centre) < 0.0:
		var t := b
		b = c
		c = t
		nrm = -nrm
	for v in [a, b, c]:
		st.set_normal(nrm)
		st.set_color(col)
		st.set_uv2(Vector2(float(shape), glow))
		st.add_vertex(v)

static func _quad(st: SurfaceTool, shape: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, centre: Vector3, col: Color, glow: float) -> void:
	_tri(st, shape, a, b, c, centre, col, glow)
	_tri(st, shape, a, c, d, centre, col, glow)

## bottom_glow, when set, lights only the bottom face (a canopy's tubes).
static func _box(st: SurfaceTool, shape: int, c: Vector3, s: Vector3, col: Color, glow: float = 0.0, bottom_glow: float = 0.0) -> void:
	var h := s / 2.0
	var p := []
	for i in 8:
		p.append(c + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	for f in [[0, 1, 5, 4], [2, 3, 7, 6], [0, 1, 3, 2], [4, 5, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]:
		var g := glow
		if f == [0, 1, 5, 4] and bottom_glow > 0.0:
			g = bottom_glow  # vertices 0, 1, 4, 5 all have y = -h.y: the bottom
		_quad(st, shape, p[f[0]], p[f[1]], p[f[2]], p[f[3]], c, col, g)

## An n-sided barrel from `base`, radius r, height h, with a cone roof.
static func _cylinder(st: SurfaceTool, shape: int, base: Vector3, r: float, h: float, roof: float, sides: int, col: Color) -> void:
	var centre := base + Vector3(0, h / 2.0, 0)
	var tip := base + Vector3(0, h + roof, 0)
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var q0 := p0 + Vector3(0, h, 0)
		var q1 := p1 + Vector3(0, h, 0)
		_quad(st, shape, p0, p1, q1, q0, centre, col, 0.0)
		_tri(st, shape, q0, q1, tip, centre, col.darkened(0.25), 0.0)
