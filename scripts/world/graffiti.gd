extends RefCounted

# Graffiti (M10, 2026-10-11): one set of spray-paint art for the menu wall now
# and the streets later, and the base of the crew-franchise tag atlas (crew
# tags, their painted-over versions, the DUNMORE stencil).
#
# The art is assets/world/graffiti/graffiti.png (1024 x 1024, drawn by
# tools/build_graffiti_atlas.py from the repo's own fonts, nothing downloaded)
# and graffiti_cells.json, which names every cell with its rect, kind and size
# in metres.
#
# Lamp-life style, ZERO per-frame script work: a root gets ONE MultiMesh of
# unit quads sharing ONE ShaderMaterial; the cell, the fade, the tint and a
# flap flag ride in per-instance custom data, and the shader does the rest
# (alpha scissor, no blending, so it sorts with everything else and costs one
# draw call per root). A grime multiply darkens the bottom 20% of each quad
# where the wall's dirt climbs, and the paint is a touch less rough than the
# wall so it catches the lamp.
#
# API
#   create(root, capacity)  adds the "Graffiti" MultiMeshInstance3D to root
#   place(root, items)      writes items; each is {xf, cell, fade, tint} and
#                           may add {scale, flap}. xf is the quad's pose: its
#                           origin the centre of the piece, its +Z the wall's
#                           outward normal, +Y up; place() scales the unit
#                           quad by the cell's size in metres (times scale).
#                           cell is an id ("tag_kemr") or an index; tint a
#                           palette name ("amber") or index; fade 0..1 (1 =
#                           fresh). flap = true lets the lower corners lift in
#                           the wind (torn posters).
#   plan(seed, len, h, n)   n deterministic items along a wall, for streets
#   set_wind(w)             the same number lamp life uses; flapping posters
#
# Tints come only from PALETTE (the Amber vs Dusk paint list plus the muted
# extras the atlas uses); a name outside it is refused with a warning and
# painted untinted. Switch: NEON_GRAFFITI=0 in the environment (or
# `Graffiti.enabled = false` before the set is built) leaves every root empty,
# for before/after shots.

const ATLAS_PATH := "res://assets/world/graffiti/graffiti.png"
const CELLS_PATH := "res://assets/world/graffiti/graffiti_cells.json"
const MAX_CELLS := 64

## Tint names and colours. "white" is no tint. The game's tint test checks
## that nothing outside this list is ever placed.
const PALETTE := {
	"white": Color(1.0, 1.0, 1.0),
	"silver": Color(0.66, 0.67, 0.68),
	"amber": Color(1.0, 0.75, 0.4),
	"sodium": Color(1.0, 0.54, 0.12),
	"rust": Color(0.56, 0.23, 0.13),
	"navy": Color(0.11, 0.16, 0.29),
	"olive": Color(0.37, 0.36, 0.24),
	"oxblood": Color(0.35, 0.14, 0.14),
	"teal": Color(0.24, 0.37, 0.35),
	"black": Color(0.07, 0.06, 0.06),
}
const PALETTE_NAMES := ["white", "silver", "amber", "sodium", "rust", "navy", "olive", "oxblood", "teal", "black"]

## Roughness of the paint: a bit below the wall's 0.95.
const ROUGHNESS := 0.8
## How dark the bottom 20% of a quad gets.
const GRIME := 0.45
## Draw distance, m: the quads are small and never worth drawing far.
const RANGE_END := 90.0

static var enabled := OS.get_environment("NEON_GRAFFITI") != "0"

static var _cells: Array = []
static var _by_id := {}
static var _mesh: ArrayMesh
static var _mat: ShaderMaterial
static var _wind := 0.6

# ---------- the cells file ----------

static func cells() -> Array:
	_ensure_cells()
	return _cells

static func cell_index(cell) -> int:
	_ensure_cells()
	if cell is int:
		return cell if cell >= 0 and cell < _cells.size() else -1
	return int(_by_id.get(String(cell), -1))

## The cell's dictionary: id, kind, rect [x, y, w, h] px, metres [w, h].
static func cell(cell) -> Dictionary:
	var i := cell_index(cell)
	return _cells[i] if i >= 0 else {}

static func tint_index(tint) -> int:
	if tint is int:
		return tint if tint >= 0 and tint < PALETTE_NAMES.size() else -1
	return PALETTE_NAMES.find(String(tint))

static func _ensure_cells() -> void:
	if not _cells.is_empty():
		return
	var f := FileAccess.open(CELLS_PATH, FileAccess.READ)
	if f == null:
		push_error("graffiti: cannot open " + CELLS_PATH)
		return
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary) or not data.has("cells"):
		push_error("graffiti: bad cells file")
		return
	_cells = data.cells
	for i in range(_cells.size()):
		_by_id[String(_cells[i].id)] = i

# ---------- wind ----------

static func wind() -> float:
	return _wind

static func set_wind(w: float) -> void:
	_wind = clampf(w, 0.0, 2.0)
	if _mat != null:
		_mat.set_shader_parameter("wind", _wind)

# ---------- placement (pure data, no nodes) ----------

## A stable value in [0, 1) for (seed, tag, k); no global random draw (the
## road layout depends on the global sequence).
static func roll(seed: int, tag: int, k: int) -> float:
	var h := (seed * 0x9E3779B1 + tag * 0x85EBCA6B + k * 0xC2B2AE35) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0

## n items along a wall of wall_len m and wall_h m, in the wall's own frame
## (x along it from 0, y up from 0, +Z out of it), a pure function of seed.
## kinds limits which cell kinds are drawn from (default: everything but the
## spare cells). Tints come from PALETTE only; tags stay untinted (their paint
## is in the art), posters and rollers too, stencils and stickers as drawn.
static func plan(seed: int, wall_len: float, wall_h: float, n: int, kinds: Array = []) -> Array:
	_ensure_cells()
	var pool := []
	for i in range(_cells.size()):
		var k: String = _cells[i].kind
		if k == "spare":
			continue
		if kinds.is_empty() or k in kinds:
			pool.append(i)
	var items := []
	if pool.is_empty():
		return items
	for k in range(n):
		var ci: int = pool[int(roll(seed, 1, k) * float(pool.size())) % pool.size()]
		var c: Dictionary = _cells[ci]
		var w: float = c.metres[0]
		var h: float = c.metres[1]
		var x := w * 0.5 + roll(seed, 2, k) * maxf(0.0, wall_len - w)
		# tags sit at hand height, pieces a little higher, stickers low
		var y_lo := 0.3 + h * 0.5
		var y_hi := minf(wall_h - h * 0.5, 2.6 if c.kind != "piece" else 3.4)
		var y := lerpf(y_lo, maxf(y_lo, y_hi), roll(seed, 3, k))
		var tilt := (roll(seed, 4, k) - 0.5) * 0.12
		items.append({
			"xf": Transform3D(Basis(Vector3.BACK, tilt), Vector3(x, y, 0.0)),
			"cell": ci,
			"fade": 0.55 + 0.45 * roll(seed, 5, k),
			"tint": 0,   # white: the paint colour is in the art
			"flap": c.kind == "poster",
		})
	return items

# ---------- nodes ----------

## Adds the one MultiMeshInstance3D (capacity quads) and returns it.
static func create(root: Node3D, capacity: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _get_mesh()
	mm.instance_count = maxi(1, capacity)
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Graffiti"
	mmi.multimesh = mm
	mmi.material_override = _get_mat()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = RANGE_END
	root.add_child(mmi)
	return mmi

## Writes the items (see the header). Over capacity, the extra are dropped
## with a warning. Returns the number placed.
static func place(root: Node3D, items: Array) -> int:
	var mmi := root.get_node_or_null(^"Graffiti") as MultiMeshInstance3D
	if mmi == null:
		push_error("graffiti: create() first")
		return 0
	var mm := mmi.multimesh
	if not enabled:
		mm.visible_instance_count = 0
		return 0
	var n := mini(items.size(), mm.instance_count)
	if n < items.size():
		push_warning("graffiti: %d items, room for %d" % [items.size(), mm.instance_count])
	mm.visible_instance_count = n
	for i in range(n):
		var it: Dictionary = items[i]
		var ci := cell_index(it.get("cell", 0))
		if ci < 0:
			push_warning("graffiti: unknown cell %s" % [it.get("cell")])
			ci = 0
		var ti := tint_index(it.get("tint", "white"))
		if ti < 0:
			push_warning("graffiti: tint %s is not in the palette" % [it.get("tint")])
			ti = 0
		var c: Dictionary = _cells[ci]
		var s: float = float(it.get("scale", 1.0))
		var xf: Transform3D = it.xf
		xf.basis = xf.basis * Basis.from_scale(Vector3(float(c.metres[0]) * s, float(c.metres[1]) * s, 1.0))
		mm.set_instance_transform(i, xf)
		mm.set_instance_custom_data(i, Color(float(ci), clampf(float(it.get("fade", 1.0)), 0.0, 1.0),
			float(ti), 1.0 if bool(it.get("flap", false)) else 0.0))
	return n

# ---------- mesh and material ----------

## A unit quad in XY, centred, facing +Z, UV (0,0) at the top-left.
static func _get_mesh() -> ArrayMesh:
	if _mesh == null:
		var v := PackedVector3Array()
		var nrm := PackedVector3Array()
		var uv := PackedVector2Array()
		var corners := [
			[Vector3(-0.5, 0.5, 0), Vector2(0, 0)], [Vector3(0.5, 0.5, 0), Vector2(1, 0)],
			[Vector3(0.5, -0.5, 0), Vector2(1, 1)], [Vector3(-0.5, 0.5, 0), Vector2(0, 0)],
			[Vector3(0.5, -0.5, 0), Vector2(1, 1)], [Vector3(-0.5, -0.5, 0), Vector2(0, 1)],
		]
		for cn in corners:
			v.append(cn[0])
			nrm.append(Vector3.BACK)
			uv.append(cn[1])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_TEX_UV] = uv
		_mesh = ArrayMesh.new()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		# a flapping corner lifts a little off the wall
		_mesh.custom_aabb = AABB(Vector3(-0.5, -0.5, -0.05), Vector3(1.0, 1.0, 0.3))
	return _mesh

const SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// INSTANCE_CUSTOM: x cell index, y fade (1 fresh), z palette index, w flap
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 rects[64];       // cell rect in atlas UV: x, y, w, h
uniform vec3 palette[16];
uniform float grime = 0.45;
uniform float rough = 0.8;
uniform float wind = 0.6;

varying vec4 rect;
varying vec3 tint;
varying float fade;

void vertex() {
	vec4 s = INSTANCE_CUSTOM;
	rect = rects[int(s.x + 0.5)];
	tint = palette[int(s.z + 0.5)];
	fade = s.y;
	if (s.w > 0.5 && wind > 0.02) {
		// a torn poster's lower corners lift and flutter in the wind
		float lo = UV.y * UV.y;
		float side = abs(UV.x - 0.5) * 2.0;
		float ph = TIME * (2.2 + 1.4 * wind) + UV.x * 5.0 + float(INSTANCE_ID);
		float lift = lo * side * (0.012 + 0.03 * wind) * (0.6 + 0.4 * sin(ph));
		VERTEX.z += lift;
		VERTEX.y += lift * 0.4 * sin(ph * 0.7);
	}
}

void fragment() {
	vec2 uv = rect.xy + UV * rect.zw;
	vec4 c = texture(atlas, uv);
	float a = c.a * mix(0.55, 1.0, fade);
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 col = c.rgb * tint;
	// worn paint loses its colour before it loses its shape
	col = mix(vec3(dot(col, vec3(0.33, 0.34, 0.33))), col, 0.5 + 0.5 * fade) * (0.75 + 0.25 * fade);
	// grime on the bottom fifth
	col *= 1.0 - grime * smoothstep(0.8, 1.0, UV.y);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
"""

static func _get_mat() -> ShaderMaterial:
	if _mat == null:
		_ensure_cells()
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("atlas", load(ATLAS_PATH))
		var rects := PackedVector4Array()
		rects.resize(MAX_CELLS)
		var atlas_w := 1024.0
		var atlas_h := 1024.0
		for i in range(mini(_cells.size(), MAX_CELLS)):
			var r: Array = _cells[i].rect
			rects[i] = Vector4(float(r[0]) / atlas_w, float(r[1]) / atlas_h, float(r[2]) / atlas_w, float(r[3]) / atlas_h)
		_mat.set_shader_parameter("rects", rects)
		var pal := PackedVector3Array()
		pal.resize(16)
		for i in range(PALETTE_NAMES.size()):
			var col: Color = PALETTE[PALETTE_NAMES[i]]
			pal[i] = Vector3(col.r, col.g, col.b)
		_mat.set_shader_parameter("palette", pal)
		_mat.set_shader_parameter("grime", GRIME)
		_mat.set_shader_parameter("rough", ROUGHNESS)
		_mat.set_shader_parameter("wind", _wind)
	return _mat
