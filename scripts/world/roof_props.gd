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
# Roof shapes (world step 1): unit footprint, bottom at y = 0, rise 1, scaled
# per instance to the roof. The gable's ridge runs along z (along the road).
const SHAPE_GABLE := 5
const SHAPE_HIP := 6
const SHAPE_SCREEN := 7  # drive-in screen: a pale slab whose big faces keep a faint glow

# Glow kinds (UV2.y), continued: a dim warm screen, an idling projector lamp.
const GLOW_SCREEN := 4.0

# Skyline landmarks (world step 1), one per district run on the building
# Districts.landmark_at() names, built from the shapes above at a size that
# reads from the far end of the chunk window.
const LANDMARKS := ["tower", "water_tower", "stacks", "screen"]

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
	else if (glow > 2.5 && glow < 3.5) { e = vec3(1.0, 0.66, 0.3) * 2.2; }
	// 4: a drive-in screen, dim warm white, well under the bloom threshold
	else if (glow > 3.5) { e = vec3(0.9, 0.8, 0.62) * 0.3; }
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
## buffer from slot first_sign on. `foundation` is how far ground-standing
## pieces (forecourt columns, pump islands, the diner pole) reach below the
## road on a hilly road, like the buildings, so none hangs over the slope.
##
## Returns {props, signs, prop_xfs, prop_anchor, sign_xfs, sign_anchor}:
## the counts, every transform written (straight road description) and the
## road z each piece belongs to (its building's centre). The builder bends
## them through the road's curve from these arrays, never from the
## MultiMesh: with physics interpolation on, get_instance_transform() hands
## back the data last drawn, so a pooled chunk rebuilt in the game kept its
## old occupant's props floating in the sky (2026-10-09).
static func update(mm: MultiMesh, infos: Array, signs: MultiMesh, first_sign: int, foundation: float = 0.0) -> Dictionary:
	var n := 0
	var n_signs := first_sign
	var rng := RandomNumberGenerator.new()
	var out := {"prop_xfs": [], "prop_anchor": PackedFloat32Array(), "sign_xfs": [], "sign_anchor": PackedFloat32Array()}
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
		var top: String = info.get("top", "flat")
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
				if rng.randf() < 0.75 and top == "flat":
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
		# World step 1: the roof shape goes first (never dropped at CAPACITY),
		# then the props above, moved onto it; the run's landmark before both.
		props = _apply_top(top, props, info, rng, cx, cz)
		var landmark: String = info.get("landmark", "")
		if landmark != "":
			props = _landmark(landmark, info, cx, cz) + props
		if kind == "gas":
			props.append_array(_gas_station(info))
		elif kind == "diner":
			# the sign pole, at the front of the lot (absolute position)
			props.append([SHAPE_BOX, Vector3(0.3, 7.4, 0.3), _abs(info, 1.2, float(info.d) * 0.35, 0.0), 0.35])
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
			var scale: Vector3 = p[1]
			if p[2] is Vector3:
				pos = p[2]  # already placed on the ground (gas station, diner pole)
				if pos.y == 0.0 and foundation > 0.0:
					# stands on the ground: reach below it, like a building
					pos.y = -foundation
					scale.y += foundation
			else:
				var off: Vector2 = p[2]
				pos = Vector3(cx + off.x * float(side), h, cz + off.y)
			out.prop_xfs.append(_put(mm, n, p[0], Basis.from_scale(scale), pos, float(p[3])))
			out.prop_anchor.append(cz)
			n += 1
		if wants_billboard and n + 2 <= CAPACITY and n_signs < signs.instance_count:
			n = _billboard(mm, n, signs, n_signs, rng, info, out)
			n_signs += 1
	mm.visible_instance_count = n
	out["props"] = n
	out["signs"] = n_signs
	return out

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

static func _put(mm: MultiMesh, i: int, shape: int, basis: Basis, pos: Vector3, tint: float) -> Transform3D:
	var xf := Transform3D(basis, pos)
	mm.set_instance_transform(i, xf)
	mm.set_instance_custom_data(i, Color(float(shape), tint, tint * 0.97, tint * 0.92))
	return xf

## A billboard on two poles near the roof's front edge, angled toward the
## traffic coming down the road. Uses 2 prop slots and 1 sign slot.
static func _billboard(mm: MultiMesh, n: int, signs: MultiMesh, sign_i: int, rng: RandomNumberGenerator, info: Dictionary, out: Dictionary) -> int:
	var side := int(info.side)
	var h: float = info.h
	var panel_h := 2.0
	var lift := 2.2
	var angle := 0.45
	var word: String = BuildingSigns.BILLBOARD_WORDS[rng.randi() % BuildingSigns.BILLBOARD_WORDS.size()]
	var color := 0 if rng.randf() < 0.7 else 3  # mostly amber, some dusk blue
	# 1.9 m in from the front edge: the panel swings `angle` toward the
	# traffic, which carries its near pole 0.35 x 9 m x sin(angle) = 1.37 m
	# back toward the edge; at the old 1.4 m that pole stood 0.2 m past the
	# roof, in the air (floating structures scan, 2026-10-09).
	var front_x := (float(info.front_x_abs) + 1.9) * float(side)
	var center := Vector3(front_x, h + lift + panel_h / 2.0, info.z)
	var panel := BuildingSigns.place(signs, sign_i, word, color, 2, center, side, panel_h, minf(float(info.d) * 0.9, 9.0), false, angle)
	out.sign_xfs.append(panel)
	out.sign_anchor.append(float(info.z))
	# poles under the panel's two ends, along the panel's own length axis
	var along := panel.basis.z
	var pole_h := lift + panel_h * 0.5
	for k in [-0.35, 0.35]:
		var p := panel.origin + along * float(k)
		out.prop_xfs.append(_put(mm, n, SHAPE_BOX, Basis.from_scale(Vector3(0.22, pole_h, 0.22)), Vector3(p.x, h, p.z), 0.4))
		out.prop_anchor.append(float(info.z))
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
		# roof shapes (world step 1): pitched and hipped, unit footprint, rise 1;
		# 16 triangles between them, so the budget per instance barely moves
		var roofing := Color(0.36, 0.33, 0.3)
		_gable(st, SHAPE_GABLE, roofing)
		_hip(st, SHAPE_HIP, roofing)
		# drive-in screen (the strip landmark): a unit slab, faintly lit
		_box(st, SHAPE_SCREEN, Vector3(0, 0.5, 0), Vector3.ONE, Color(0.62, 0.6, 0.56), GLOW_SCREEN)
		_mesh = st.commit()
	return _mesh

## Pitched roof: eaves at y = 0 on x = +-0.5, ridge along z at y = 1. 6 tris.
static func _gable(st: SurfaceTool, shape: int, col: Color) -> void:
	var c := Vector3(0, 0.4, 0)
	var a := Vector3(-0.5, 0, -0.5)
	var b := Vector3(0.5, 0, -0.5)
	var e := Vector3(0.5, 0, 0.5)
	var f := Vector3(-0.5, 0, 0.5)
	var r0 := Vector3(0, 1, -0.5)
	var r1 := Vector3(0, 1, 0.5)
	_quad(st, shape, a, r0, r1, f, c, col, 0.0)
	_quad(st, shape, b, e, r1, r0, c, col.darkened(0.15), 0.0)
	_tri(st, shape, a, b, r0, c, col.darkened(0.3), 0.0)
	_tri(st, shape, f, r1, e, c, col.darkened(0.3), 0.0)

## Hipped roof: a truncated pyramid, the flat top half the footprint. 10 tris.
static func _hip(st: SurfaceTool, shape: int, col: Color) -> void:
	var c := Vector3(0, 0.4, 0)
	var b := []
	var t := []
	for i in 4:  # 0 (-x,-z)  1 (+x,-z)  2 (-x,+z)  3 (+x,+z)
		var sx := 1.0 if i & 1 else -1.0
		var sz := 1.0 if i & 2 else -1.0
		b.append(Vector3(0.5 * sx, 0, 0.5 * sz))
		t.append(Vector3(0.25 * sx, 1, 0.25 * sz))
	_quad(st, shape, b[0], b[1], t[1], t[0], c, col, 0.0)
	_quad(st, shape, b[1], b[3], t[3], t[1], c, col.darkened(0.15), 0.0)
	_quad(st, shape, b[3], b[2], t[2], t[3], c, col, 0.0)
	_quad(st, shape, b[2], b[0], t[0], t[2], c, col.darkened(0.15), 0.0)
	_quad(st, shape, t[0], t[1], t[3], t[2], c, col.darkened(0.4), 0.0)

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

# ---------- roof shapes and landmarks (world step 1, 2026-10-10) ----------

## Puts the roof shape `top` (BuildingKit.TOPS) under the building's props.
## Returns the new prop list: the shape first, then the props above it, moved
## onto it: a pitched roof keeps only a chimney, a hip or setback lifts them
## onto its flat top, a crown replaces them. Everything comes out at an
## absolute position (Vector3) above the ground, so the main loop's
## ground-standing rule (y = 0: forecourt columns) never applies to it.
static func _apply_top(top: String, props: Array, info: Dictionary, rng: RandomNumberGenerator, cx: float, cz: float) -> Array:
	var side := int(info.side)
	var w: float = info.w
	var d: float = info.d
	var h: float = info.h
	var out := []
	var lift := 0.0  # how far up the props move
	var keep := 1.0  # how much of the roof they may still use
	match top:
		"cornice":
			out.append([SHAPE_BOX, Vector3(w + 0.7, 0.55, d + 0.7), Vector3(cx, h - 0.25, cz), 0.5])
		"parapet":
			# a raised false front along the street edge, stepped up in the middle
			var fx := cx - (w * 0.5 - 0.2) * float(side)
			out.append([SHAPE_BOX, Vector3(0.4, 1.0, d + 0.2), Vector3(fx, h, cz), 0.6])
			out.append([SHAPE_BOX, Vector3(0.4, 1.7, d * 0.4), Vector3(fx, h, cz), 0.6])
		"gable":
			var low: bool = info.type == "warehouse" or info.type == "garage"
			var rise := clampf(w * (0.14 if low else 0.3), 1.2 if low else 1.8, 2.6 if low else 4.5)
			out.append([SHAPE_GABLE, Vector3(w + 0.5, rise, d + 0.5), Vector3(cx, h, cz), 0.9])
			return out + _chimney(rng, info, cx, cz, rise)
		"hip":
			var rise := clampf(minf(w, d) * 0.28, 1.8, 4.0)
			out.append([SHAPE_HIP, Vector3(w + 0.5, rise, d + 0.5), Vector3(cx, h, cz), 0.9])
			lift = rise
			keep = 0.4
		"setback":
			var rise := rng.randf_range(3.0, 3.6)
			out.append([SHAPE_BOX, Vector3(w * 0.72, rise, d * 0.72), Vector3(cx, h, cz), 0.45])
			lift = rise
			keep = 0.65
		"crown":
			# stepped plant rooms, three on the tower landmark, and a short
			# mast with its aviation light (the tower brings its own, taller)
			var tower: bool = info.get("landmark", "") == "tower"
			var y := h
			var k := 0.7
			for s in (3 if tower else 2):
				var rise := 3.6 - 0.4 * float(s)
				out.append([SHAPE_BOX, Vector3(w * k, rise, d * k), Vector3(cx, y, cz), 0.45])
				y += rise
				k *= 0.62
			if not tower:
				out.append([SHAPE_ANTENNA, Vector3(1.0, 1.3, 1.0), Vector3(cx, y, cz), 0.6])
			return out
	for p in props:
		var off: Vector2 = p[2]
		out.append([p[0], p[1], Vector3(cx + off.x * keep * float(side), h + lift, cz + off.y * keep), p[3]])
	return out

## A brick chimney through a pitched roof of `rise`, off the ridge near one
## end; most pitched roofs get one.
static func _chimney(rng: RandomNumberGenerator, info: Dictionary, cx: float, cz: float, rise: float) -> Array:
	if rng.randf() < 0.35:
		return []
	var w: float = info.w
	var d: float = info.d
	var h: float = info.h
	var across := rng.randf_range(-0.15, 0.15)  # of w, from the ridge
	var along := rng.randf_range(0.25, 0.4) * d * (1.0 if rng.randf() < 0.5 else -1.0)
	# the roof is rise * (1 - 2|across|) high there; poke 1.2 m above it
	var top_h := rise * (1.0 - 2.0 * absf(across)) + 1.2
	return [[SHAPE_BOX, Vector3(0.9, top_h, 0.9), Vector3(cx + across * w * float(info.side), h, cz + along), 0.5]]

## The run's landmark (LANDMARKS) on its building, at absolute positions.
## Sizes read from the far end of the chunk window (300 m); every lit piece
## is a red aviation light or a sodium flood, nothing off the palette.
static func _landmark(kind: String, info: Dictionary, cx: float, cz: float) -> Array:
	var side := int(info.side)
	var w: float = info.w
	var d: float = info.d
	var h: float = info.h
	match kind:
		"tower":
			# the office tower's three-step crown comes from its top; this is
			# the lattice mast on it, 27 m, red light on top
			return [[SHAPE_ANTENNA, Vector3(3.0, 4.5, 3.0), Vector3(cx, h + 9.6, cz), 0.55]]
		"water_tower":
			# a municipal water tower: the rooftop tank on legs, six times the size
			var k := 6.0
			return [[SHAPE_TANK, Vector3(k, k, k), Vector3(cx, h, cz), 0.95],
				[SHAPE_ANTENNA, Vector3(1.0, 0.45, 1.0), Vector3(cx, h + 3.6 * k, cz), 0.6]]
		"stacks":
			# two brick chimney stacks off the back of the shed, 46 and 34 m,
			# the taller one lit
			var bx := cx + w * 0.25 * float(side)
			return [[SHAPE_BOX, Vector3(3.6, 46.0 - h, 3.6), Vector3(bx, h, cz - d * 0.25), 0.42],
				[SHAPE_BOX, Vector3(2.8, 34.0 - h, 2.8), Vector3(bx, h, cz + d * 0.25), 0.42],
				[SHAPE_ANTENNA, Vector3(1.0, 0.4, 1.0), Vector3(bx, 46.0, cz - d * 0.25), 0.6]]
		"screen":
			# a drive-in screen behind the lot: a pale slab on two legs, 26 m
			# to the top, with a floodlight on the shop roof aimed at it
			var sx := cx + (w * 0.5 + 6.0) * float(side)
			var out := []
			for dz in [-8.0, 8.0]:
				out.append([SHAPE_BOX, Vector3(0.7, 14.0, 0.7), Vector3(sx, 0.0, cz + dz), 0.5])
			out.append([SHAPE_SCREEN, Vector3(0.5, 12.0, 22.0), Vector3(sx, 14.0, cz), 1.4])
			out.append([SHAPE_FLOOD, Vector3(1.0, 0.9, 1.0), Vector3(cx + (w * 0.5 - 1.0) * float(side), h, cz), 1.0])
			return out
	return []
