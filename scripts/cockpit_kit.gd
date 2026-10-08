class_name CockpitKit
extends RefCounted

# A tiny flat-shaded mesh builder for the cockpit (2026-10-06): boxes, quads and
# ring sectors with one colour per face, collected into ONE ArrayMesh so a whole
# dashboard is a single draw call. Same conventions as P1CoupeBuilder: flat
# normals, vertex colours in linear space, Godot's clockwise front faces.
# Everything that moves (needles, pedals, lever) gets its own kit and mesh.

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()

## Triangle a, b, c given counter-clockwise seen from outside.
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	var lin := col.srgb_to_linear()
	for p in [a, c, b]:
		_v.append(p)
		_n.append(n)
		_c.append(lin)

## Quad a, b, c, d counter-clockwise seen from outside.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri(a, b, c, col)
	tri(a, c, d, col)

## An axis-aligned box in the kit's space, optionally rotated about its centre.
func box(size: Vector3, center: Vector3, col: Color, basis := Basis.IDENTITY, top_col := Color(0, 0, 0, 0)) -> void:
	var h := size * 0.5
	var p := []
	for i in 8:
		var corner := Vector3(h.x if (i & 1) else -h.x, h.y if (i & 2) else -h.y, h.z if (i & 4) else -h.z)
		p.append(center + basis * corner)
	var tc := top_col if top_col.a > 0.0 else col
	# faces, each counter-clockwise from outside (indices: bit0 = +x, bit1 = +y, bit2 = +z)
	quad(p[3], p[7], p[5], p[1], col)   # +x
	quad(p[6], p[2], p[0], p[4], col)   # -x
	quad(p[6], p[7], p[3], p[2], tc)    # +y (top)
	quad(p[1], p[5], p[4], p[0], col)   # -y
	quad(p[5], p[7], p[6], p[4], col)   # +z
	quad(p[2], p[3], p[1], p[0], col)   # -z

## A box open on its +z face: `outer` on the five closed sides and the rim,
## `inner` on the recess walls and the back plate `depth` in (door mirror cups).
func cup(size: Vector3, center: Vector3, basis: Basis, outer: Color, inner: Color, depth: float, wall := 0.008) -> void:
	var h := size * 0.5
	var i := Vector3(h.x - wall, h.y - wall, h.z)      # inner opening half extents
	var zb := h.z - depth                               # back plate z
	var pts := func(x: float, y: float, z: float) -> Vector3: return center + basis * Vector3(x, y, z)
	# closed outer sides
	quad(pts.call(-h.x, -h.y, -h.z), pts.call(-h.x, h.y, -h.z), pts.call(h.x, h.y, -h.z), pts.call(h.x, -h.y, -h.z), outer)   # -z
	quad(pts.call(h.x, -h.y, -h.z), pts.call(h.x, h.y, -h.z), pts.call(h.x, h.y, h.z), pts.call(h.x, -h.y, h.z), outer)       # +x
	quad(pts.call(-h.x, -h.y, h.z), pts.call(-h.x, h.y, h.z), pts.call(-h.x, h.y, -h.z), pts.call(-h.x, -h.y, -h.z), outer)   # -x
	quad(pts.call(-h.x, h.y, -h.z), pts.call(-h.x, h.y, h.z), pts.call(h.x, h.y, h.z), pts.call(h.x, h.y, -h.z), outer)       # +y
	quad(pts.call(-h.x, -h.y, h.z), pts.call(-h.x, -h.y, -h.z), pts.call(h.x, -h.y, -h.z), pts.call(h.x, -h.y, h.z), outer)   # -y
	# rim ring on the open face
	quad(pts.call(-h.x, -h.y, h.z), pts.call(h.x, -h.y, h.z), pts.call(i.x, -i.y, h.z), pts.call(-i.x, -i.y, h.z), outer)
	quad(pts.call(-h.x, h.y, h.z), pts.call(-i.x, i.y, h.z), pts.call(i.x, i.y, h.z), pts.call(h.x, h.y, h.z), outer)
	quad(pts.call(-h.x, -h.y, h.z), pts.call(-i.x, -i.y, h.z), pts.call(-i.x, i.y, h.z), pts.call(-h.x, h.y, h.z), outer)
	quad(pts.call(h.x, -h.y, h.z), pts.call(h.x, h.y, h.z), pts.call(i.x, i.y, h.z), pts.call(i.x, -i.y, h.z), outer)
	# recess walls (facing inward) and the back plate (facing +z)
	quad(pts.call(-i.x, -i.y, zb), pts.call(i.x, -i.y, zb), pts.call(i.x, i.y, zb), pts.call(-i.x, i.y, zb), inner)
	quad(pts.call(-i.x, -i.y, h.z), pts.call(i.x, -i.y, h.z), pts.call(i.x, -i.y, zb), pts.call(-i.x, -i.y, zb), inner)   # bottom wall
	quad(pts.call(-i.x, i.y, zb), pts.call(i.x, i.y, zb), pts.call(i.x, i.y, h.z), pts.call(-i.x, i.y, h.z), inner)       # top wall
	quad(pts.call(-i.x, -i.y, zb), pts.call(-i.x, i.y, zb), pts.call(-i.x, i.y, h.z), pts.call(-i.x, -i.y, h.z), inner)   # left wall
	quad(pts.call(i.x, -i.y, h.z), pts.call(i.x, i.y, h.z), pts.call(i.x, i.y, zb), pts.call(i.x, -i.y, zb), inner)       # right wall

## A wedge: a box whose +z face is lifted to a slope (dash tops, seat cushions).
## `top_back` raises the back (-z) edge of the top face, `top_front` the front (+z).
func wedge(size: Vector3, center: Vector3, col: Color, top_back: float, top_front: float) -> void:
	var h := size * 0.5
	var c := center
	var b0 := c + Vector3(-h.x, -h.y, -h.z)
	var b1 := c + Vector3(h.x, -h.y, -h.z)
	var b2 := c + Vector3(h.x, -h.y, h.z)
	var b3 := c + Vector3(-h.x, -h.y, h.z)
	var t0 := c + Vector3(-h.x, h.y + top_back, -h.z)
	var t1 := c + Vector3(h.x, h.y + top_back, -h.z)
	var t2 := c + Vector3(h.x, h.y + top_front, h.z)
	var t3 := c + Vector3(-h.x, h.y + top_front, h.z)
	quad(b1, b2, b3, b0, col)   # bottom
	quad(t3, t2, t1, t0, col)   # top
	quad(t0, t1, b1, b0, col)   # back (-z)
	quad(b2, t2, t3, b3, col)   # front (+z)
	quad(b3, t3, t0, b0, col)   # left
	quad(t1, t2, b2, b1, col)   # right

## A flat ring sector in the XY plane between radii r0 < r1, from angle a0 to a1
## (radians, counter-clockwise from +x), extruded from z0 to z1. Faces +z/-z and
## the inner/outer walls; `alt` colours every other segment (carbon weave).
func ring_sector(r0: float, r1: float, a0: float, a1: float, z0: float, z1: float, col: Color, segments: int = 12, alt := Color(0, 0, 0, 0)) -> void:
	for s in segments:
		var t0 := a0 + (a1 - a0) * float(s) / segments
		var t1 := a0 + (a1 - a0) * float(s + 1) / segments
		var c := alt if (alt.a > 0.0 and s % 2 == 1) else col
		var i0 := Vector3(cos(t0), sin(t0), 0) * r0
		var i1 := Vector3(cos(t1), sin(t1), 0) * r0
		var o0 := Vector3(cos(t0), sin(t0), 0) * r1
		var o1 := Vector3(cos(t1), sin(t1), 0) * r1
		var zf := Vector3(0, 0, z1)
		var zb := Vector3(0, 0, z0)
		quad(i0 + zf, o0 + zf, o1 + zf, i1 + zf, c)   # front (+z)
		quad(i1 + zb, o1 + zb, o0 + zb, i0 + zb, c)   # back
		quad(o0 + zb, o1 + zb, o1 + zf, o0 + zf, c)   # outer wall
		quad(i1 + zb, i0 + zb, i0 + zf, i1 + zf, c)   # inner wall

## A closed cylinder along +y: radius r, from y0 to y1, `sides` faces.
func cylinder(r: float, y0: float, y1: float, center: Vector3, col: Color, sides: int = 8, basis := Basis.IDENTITY) -> void:
	var top := []
	var bot := []
	for i in sides:
		var a := TAU * float(i) / sides
		var d := Vector3(cos(a), 0, sin(a)) * r
		bot.append(center + basis * (d + Vector3(0, y0, 0)))
		top.append(center + basis * (d + Vector3(0, y1, 0)))
	for i in sides:
		var j := (i + 1) % sides
		quad(bot[i], top[i], top[j], bot[j], col)
	for i in range(1, sides - 1):
		tri(top[0], top[i + 1], top[i], col)
		tri(bot[0], bot[i], bot[i + 1], col)

## Moves everything built so far.
func offset(by: Vector3) -> void:
	for i in _v.size():
		_v[i] += by

## Turns and moves everything built so far (a centre stack angled at the driver).
func transform(xf: Transform3D) -> void:
	for i in _v.size():
		_v[i] = xf * _v[i]
		_n[i] = (xf.basis * _n[i]).normalized()

## PS2-style light baked into the vertex colours (interiors pass, 2026-10-08):
## darker toward the floor (seams and footwell, `low` at `floor_y`, full at
## `top_y` and above) and a little lighter on faces that look up at the glass
## (`up` extra at a face pointing straight up). Call once, before instance().
func bake(floor_y: float, top_y: float, low := 0.45, up := 0.18) -> void:
	for i in _v.size():
		var h := clampf((_v[i].y - floor_y) / maxf(top_y - floor_y, 0.01), 0.0, 1.0)
		var f := lerpf(low, 1.0, h * h * (3.0 - 2.0 * h)) * (1.0 + up * maxf(_n[i].y, 0.0))
		var c := _c[i]
		_c[i] = Color(c.r * f, c.g * f, c.b * f, c.a)

func merge(other: CockpitKit) -> void:
	_v.append_array(other._v)
	_n.append_array(other._n)
	_c.append_array(other._c)

func tri_count() -> int:
	return _v.size() / 3

func is_empty() -> bool:
	return _v.is_empty()

func commit(mat: Material = null) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _v.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mat != null:
		mesh.surface_set_material(0, mat)
	return mesh

## The mesh as a node, one draw call.
func instance(mat: Material, node_name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if node_name != "":
		mi.name = node_name
	mi.mesh = commit(mat)
	return mi

## Vertex-colour material. Shaded, so the cabin light gives the shapes form.
## Specular is low by default: on near-black plastics Godot's default 0.5
## reflects the orange night sky and turns the whole cabin olive-brown.
static func material(roughness := 0.85, metallic := 0.0, specular := 0.08) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	m.metallic = metallic
	m.metallic_specular = specular
	return m

## Surface kinds for interiors (interiors pass, 2026-10-08): each is its own
## material so dash plastic, soft dash top, cloth, leather, metal and rubber
## catch the cabin light differently. Colour stays in the vertex colours; a
## small tileable greyscale texture (generated once, no files) multiplies it,
## mapped triplanar in the cabin's own space so the kit needs no UVs.
## Shaded on purpose: the street-lamp light from the graphics pass lands on them.
const SURFACES := {
	"hard": {"rough": 0.80, "metal": 0.0, "spec": 0.10, "tex": "grain", "scale": 7.0},
	"soft": {"rough": 0.95, "metal": 0.0, "spec": 0.05, "tex": "grain", "scale": 3.0},
	"cloth": {"rough": 1.00, "metal": 0.0, "spec": 0.02, "tex": "weave", "scale": 14.0},
	"leather": {"rough": 0.62, "metal": 0.0, "spec": 0.22, "tex": "grain", "scale": 11.0},
	"metal": {"rough": 0.35, "metal": 0.70, "spec": 0.50, "tex": "brush", "scale": 9.0},
	"rubber": {"rough": 1.00, "metal": 0.0, "spec": 0.02, "tex": "", "scale": 1.0},
}
static var _surface_tex := {}

static func surface_material(kind: String) -> StandardMaterial3D:
	var d: Dictionary = SURFACES.get(kind, SURFACES.hard)
	var m := material(d.rough, d.metal, d.spec)
	if d.tex != "":
		m.albedo_texture = surface_texture(d.tex)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * float(d.scale)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m

## 64 px greyscale tiles, 0.80..1.0 so they only ever darken a little:
## "grain" fine plastic/leather noise, "weave" a cloth crosshatch, "brush"
## brushed-metal streaks along x.
static func surface_texture(kind: String) -> ImageTexture:
	if _surface_tex.has(kind):
		return _surface_tex[kind]
	const N := 64
	var img := Image.create(N, N, false, Image.FORMAT_L8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var row := PackedFloat32Array()
	row.resize(N)
	for y in N:
		row[y] = rng.randf()
	for y in N:
		for x in N:
			var v := 1.0
			match kind:
				"grain":
					v = 0.86 + 0.14 * rng.randf()
				"weave":
					var a := 0.5 + 0.5 * sin(TAU * float(x + y) / 4.0)
					var b := 0.5 + 0.5 * sin(TAU * float(x - y) / 4.0)
					v = 0.80 + 0.12 * maxf(a, b) + 0.08 * rng.randf()
				"brush":
					v = 0.84 + 0.12 * row[y] + 0.04 * rng.randf()
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_surface_tex[kind] = t
	return t

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded;
// Vertex colour, with alpha as how strongly it glows (0 = a dark, unlit face).
uniform float energy = 2.0;
void fragment() {
	ALBEDO = COLOR.rgb * mix(0.12, 1.0, COLOR.a);
	EMISSION = COLOR.rgb * COLOR.a * energy;
}
"""
static var _glow_shader: Shader

## Self-lit vertex-colour material for lamps, dials, needles and backlit trim:
## a face's alpha is its glow (1.0 at `energy` blooms, small values just read lit).
static func glow_material(energy: float) -> ShaderMaterial:
	if _glow_shader == null:
		_glow_shader = Shader.new()
		_glow_shader.code = GLOW_SHADER
	var m := ShaderMaterial.new()
	m.shader = _glow_shader
	m.set_shader_parameter("energy", energy)
	return m
