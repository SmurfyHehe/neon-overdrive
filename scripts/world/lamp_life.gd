extends RefCounted

# Lamp-post life (living world step 2, 2026-10-10). Four small things that
# make a night street look inhabited, all on or over the road, in a lamp
# pool or in the headlights (never on wires):
#
#   A4 moths swirl under the head of some lamps, and now and then a bat
#      flicks through the pool
#   A6 banners hang on every third lamp post, flap in the wind and carry the
#      district's own colour and emblem
#   A2 steam rises from a manhole or a gutter drain in a lamp pool, a few
#      per district
#   A5 newspaper and leaves blow across the road in gusts
#
# The rule for all four: ZERO per-frame script work. Each effect is ONE
# MultiMesh per chunk with ONE shared mesh and ONE shared shader material;
# the motion is a vertex shader reading TIME, per-instance custom data and a
# single `wind` uniform. A chunk rebuild only writes a handful of transforms.
# Everything is near-camera only (visibility_range_end) and capped per chunk:
# at most 4 moth swarms, 4 banners, 1 vent and 1 litter set per 50 m.
#
# Wind: one number, LampLife.wind() / set_wind(). 0 is still air, 1 a steady
# breeze, 2 a gale. It sways the banners, leans the steam and sets how hard
# and how long the litter gusts blow. A weather system sets it later; for
# now it holds DEFAULT_WIND. The wind blows across the road, from the player's
# side (+X in chunk space).
#
# Nothing here uses the global random sequence (the road layout depends on
# it): placement hashes the chunk index, so a recycled chunk matches a fresh
# one.
#
# Colours stay in Amber vs Dusk: sodium amber, warm white, dusk navy, silver.
# No magenta, no cyan.
#
# Switch: NEON_LAMP_LIFE=0 in the environment (or `LampLife.enabled = false`
# before chunks are built) turns the whole step off, for before/after shots.

const SODIUM := Color(1.0, 0.55, 0.2)

## Draw distance, m, from the camera to the chunk-local node origin. The
## moths and the bat are a few pixels at best past this.
const RANGE_SWARM := 85.0
const RANGE_BANNER := 110.0
const RANGE_STEAM := 90.0
const RANGE_COVER := 90.0
const RANGE_LITTER := 70.0

const DEFAULT_WIND := 0.6

## Chance that a lamp has a moth swarm; of those, the share that also has a
## bat now and then.
const SWARM_SHARE := 0.55
const BAT_SHARE := 0.5
## Every this-many lamps wears a banner.
const BANNER_EVERY := 3
## Share of chunks with a vent (of 16 chunks per district: about 4), and of
## those, the share that is a round manhole (the rest are gutter drains).
const VENT_SHARE := 0.25
const MANHOLE_SHARE := 0.7
## Pole to road edge: LAMP_SETBACK + CURB_W + SHOULDER_W in road_chunk_builder.
const POLE_TO_ROAD := 2.05
const LANE_W := 3.2
## Gutter drain: mid shoulder, from the pole toward the road centre.
const DRAIN_FROM_POLE := 1.2

# Moth head, in the lamp's local space (pole at the origin, arm toward -X).
const HEAD := Vector3(-1.7, 7.34, 0.0)

# Banner cloth, local to the pole: just clear of it on the road side, 0.76 m
# along the road, hanging from a bracket at BANNER_TOP.
const BANNER_X := -0.26
const BANNER_W := 0.76
const BANNER_H := 2.1
const BANNER_TOP := 5.9
const BANNER_COLS := 3
const BANNER_ROWS := 8

static var enabled := OS.get_environment("NEON_LAMP_LIFE") != "0"

static var _wind := DEFAULT_WIND
static var _swarm_mesh: ArrayMesh
static var _banner_mesh: ArrayMesh
static var _steam_mesh: ArrayMesh
static var _cover_mesh: ArrayMesh
static var _litter_mesh: ArrayMesh
static var _swarm_mat: ShaderMaterial
static var _banner_mat: ShaderMaterial
static var _steam_mat: ShaderMaterial
static var _cover_mat: StandardMaterial3D
static var _litter_mat: ShaderMaterial

# ---------- wind ----------

static func wind() -> float:
	return _wind

## Screenshots only: hold every bat and every litter gust at this point of
## its run (0..1), or pass -1 to let them run again.
static func freeze_for_shots(u: float) -> void:
	for m in [_get_swarm_mat(), _get_litter_mat()]:
		(m as ShaderMaterial).set_shader_parameter("freeze", u)

static func set_wind(w: float) -> void:
	_wind = clampf(w, 0.0, 2.0)
	for m in [_banner_mat, _steam_mat, _litter_mat]:
		if m != null:
			(m as ShaderMaterial).set_shader_parameter("wind", _wind)

# ---------- placement (pure data, no nodes) ----------

## A stable value in [0, 1) for (chunk, tag, k): the same for a pooled chunk
## rebuilt to this index as for a fresh one, and no global random draw.
static func roll(chunk_index: int, tag: int, k: int) -> float:
	return float(posmod(hash([chunk_index, tag, k]), 65521)) / 65521.0

## District colour/emblem slot (see the banner shader) of a district name.
static func district_slot(district: String) -> int:
	match district:
		"downtown":
			return 0
		"residential":
			return 1
		"strip":
			return 2
	return 3  # industrial, and anything added later

## What one chunk gets, given where its lamps stand. lamp_xfs are the lamp
## pole transforms in chunk space (upright, local -X over the road, as the
## chunk builder places them). Returns:
##   moths   [{xf, custom}]   one swarm per entry, at the pole
##   banners [{xf, custom}]   one banner per entry, at the pole
##   vents   [{cover_xf, steam_xf, custom, drain}]  at most one
static func plan(chunk_index: int, district: String, lamp_xfs: Array) -> Dictionary:
	var moths := []
	var banners := []
	var vents := []
	var slot := district_slot(district)
	for k in range(lamp_xfs.size()):
		var xf: Transform3D = lamp_xfs[k]
		if roll(chunk_index, 1, k) < SWARM_SHARE:
			# x: seed, y: bat period seed, z: bat phase seed, w: bat on/off
			moths.append({"xf": xf, "custom": Color(
				roll(chunk_index, 2, k), roll(chunk_index, 3, k), roll(chunk_index, 4, k),
				1.0 if roll(chunk_index, 5, k) < BAT_SHARE else 0.0)})
		if posmod(chunk_index + k, BANNER_EVERY) == 0:
			# x: district slot, y: phase seed
			banners.append({"xf": xf, "custom": Color(float(slot), roll(chunk_index, 6, k), 0.0, 0.0)})
	if not lamp_xfs.is_empty() and roll(chunk_index, 7, 0) < VENT_SHARE:
		var k := int(roll(chunk_index, 8, 0) * float(lamp_xfs.size())) % lamp_xfs.size()
		var lx: Transform3D = lamp_xfs[k]
		var drain := roll(chunk_index, 9, 0) >= MANHOLE_SHARE
		# a drain sits in the gutter; a manhole in the outermost lane or the
		# one inside it
		var d := DRAIN_FROM_POLE
		if not drain:
			d = POLE_TO_ROAD + LANE_W * (0.5 + float(int(roll(chunk_index, 10, 0) * 2.0)))
		# arm points toward -X in the lamp's frame on both sides
		var p := lx.origin + lx.basis * Vector3(-d, 0.0, 0.0)
		var cover_basis := lx.basis
		if drain:
			cover_basis = lx.basis * Basis.from_scale(Vector3(0.32, 1.0, 1.0))
		vents.append({
			"cover_xf": Transform3D(cover_basis, p),
			"steam_xf": Transform3D(Basis(), p),
			"custom": Color(roll(chunk_index, 11, 0), 1.0 if drain else 0.0, 0.0, 0.0),
			"drain": drain,
		})
	return {"moths": moths, "banners": banners, "vents": vents}

# ---------- nodes ----------

## Adds the five MultiMeshInstance3D nodes of a chunk (once per pooled root).
## lamp_capacity is the lamp count per chunk, all sides.
static func create_nodes(root: Node3D, lamp_capacity: int) -> void:
	root.add_child(_new_mm("LampMoths", _get_swarm_mesh(), _get_swarm_mat(), lamp_capacity, true, RANGE_SWARM))
	root.add_child(_new_mm("LampBanners", _get_banner_mesh(), _get_banner_mat(), lamp_capacity, true, RANGE_BANNER))
	root.add_child(_new_mm("SteamVents", _get_steam_mesh(), _get_steam_mat(), 1, true, RANGE_STEAM))
	root.add_child(_new_mm("VentCovers", _get_cover_mesh(), _get_cover_mat(), 1, false, RANGE_COVER))
	root.add_child(_new_mm("WindLitter", _get_litter_mesh(), _get_litter_mat(), 1, true, RANGE_LITTER))

## Writes one chunk's share. litter_xf: the chunk-space frame at mid-chunk
## (the litter's motion is local to it); road_x0 / road_x1: the road's left
## and right edge in that frame.
static func apply(root: Node3D, chunk_index: int, district: String, lamp_xfs: Array, litter_xf: Transform3D, road_x0: float, road_x1: float) -> void:
	var moth_mm := _mm(root, "LampMoths")
	var banner_mm := _mm(root, "LampBanners")
	var steam_mm := _mm(root, "SteamVents")
	var cover_mm := _mm(root, "VentCovers")
	var litter_mm := _mm(root, "WindLitter")
	if not enabled:
		for mm in [moth_mm, banner_mm, steam_mm, cover_mm, litter_mm]:
			(mm as MultiMesh).visible_instance_count = 0
		return
	var p := plan(chunk_index, district, lamp_xfs)
	_fill(moth_mm, p.moths)
	_fill(banner_mm, p.banners)
	var vents: Array = p.vents
	steam_mm.visible_instance_count = vents.size()
	cover_mm.visible_instance_count = vents.size()
	for i in range(vents.size()):
		steam_mm.set_instance_transform(i, vents[i].steam_xf)
		steam_mm.set_instance_custom_data(i, vents[i].custom)
		cover_mm.set_instance_transform(i, vents[i].cover_xf)
	litter_mm.visible_instance_count = 1
	litter_mm.set_instance_transform(0, litter_xf)
	litter_mm.set_instance_custom_data(0, Color(
		(road_x0 + road_x1) * 0.5, (road_x1 - road_x0) * 0.5,
		roll(chunk_index, 12, 0), roll(chunk_index, 13, 0)))

static func _fill(mm: MultiMesh, items: Array) -> void:
	var n := mini(items.size(), mm.instance_count)
	mm.visible_instance_count = n
	for i in range(n):
		mm.set_instance_transform(i, items[i].xf)
		mm.set_instance_custom_data(i, items[i].custom)

static func _mm(root: Node3D, node_name: String) -> MultiMesh:
	return (root.get_node(NodePath(node_name)) as MultiMeshInstance3D).multimesh

static func _new_mm(node_name: String, mesh: Mesh, mat: Material, capacity: int, custom: bool, range_end: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = range_end
	return mmi

# ---------- mesh helpers ----------

class _Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()

	## A quad as two triangles, corners in order around it.
	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, normal: Vector3, col: Color, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
		for t in [[a, ua], [b, ub], [cc, uc], [a, ua], [cc, uc], [d, ud]]:
			v.append(t[0])
			n.append(normal)
			c.append(col)
			uv.append(t[1])

	func tri(a: Vector3, b: Vector3, cc: Vector3, normal: Vector3, col: Color) -> void:
		for p in [a, b, cc]:
			v.append(p)
			n.append(normal)
			c.append(col)
			uv.append(Vector2.ZERO)

	func commit(aabb: AABB) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		# the shaders move the vertices; the box must cover where they end up
		m.custom_aabb = aabb
		return m

## A unit corner quad (billboarded by the shader), element phase in COLOR.g.
static func _corner_quad(b: _Buf, kind: float, phase: float) -> void:
	var col := Color(kind, phase, 0.0, 1.0)
	b.quad(Vector3(-1, -1, 0), Vector3(-1, 1, 0), Vector3(1, 1, 0), Vector3(1, -1, 0), Vector3.BACK, col,
		Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))

# ---------- A4: moths and a bat ----------

static func _get_swarm_mesh() -> ArrayMesh:
	if _swarm_mesh == null:
		var b := _Buf.new()
		for i in range(5):
			_corner_quad(b, 0.0, (float(i) + 0.37) / 5.0)
		# the bat, flat in XZ, nose toward -Z, 0.4 m across: body and two
		# wings (the shader lifts the wing tips to flap them). COLOR.r = 1.
		var col := Color(1.0, 0.5, 0.0, 1.0)
		var up := Vector3.UP
		b.tri(Vector3(0.0, 0.0, -0.09), Vector3(-0.025, 0.0, 0.06), Vector3(0.025, 0.0, 0.06), up, col)
		b.tri(Vector3(-0.02, 0.0, -0.04), Vector3(-0.22, 0.0, -0.01), Vector3(-0.07, 0.0, 0.07), up, col)
		b.tri(Vector3(0.02, 0.0, -0.04), Vector3(0.07, 0.0, 0.07), Vector3(0.22, 0.0, -0.01), up, col)
		_swarm_mesh = b.commit(AABB(Vector3(-6.5, 0.0, -11.0), Vector3(9.0, 10.0, 22.0)))
	return _swarm_mesh

const SWARM_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

// Moths orbit the lamp head; a bat crosses the pool now and then.
// INSTANCE_CUSTOM: x swarm seed, y bat period seed, z bat phase seed, w bat?
uniform vec3 head = vec3(-1.7, 7.34, 0.0);
uniform float freeze = -1.0;  // >= 0: every bat held at this point of its flight (screenshots)
varying vec3 col;

void vertex() {
	vec4 s = INSTANCE_CUSTOM;
	float ph = COLOR.g;
	if (COLOR.r < 0.5) {
		// a moth: erratic loops around the lamp head, a little below it
		float t = TIME * (1.5 + 1.4 * ph) + ph * 40.0 + s.x * 30.0;
		float a = t * 2.6;
		float r = 0.30 + 0.16 * sin(t * 1.7 + ph * 9.0);
		vec3 c = head + vec3(cos(a) * r, -0.25 + 0.16 * sin(t * 3.1 + ph * 5.0), sin(a * 0.93) * r);
		c += 0.035 * vec3(sin(TIME * 23.0 + ph * 50.0), sin(TIME * 29.0 + ph * 70.0), sin(TIME * 31.0 + ph * 30.0));
		float blink = 0.55 + 0.45 * step(0.0, sin(TIME * 17.0 + ph * 60.0));
		vec4 vp = MODELVIEW_MATRIX * vec4(c, 1.0);
		vp.xy += VERTEX.xy * 0.032 * blink;
		POSITION = PROJECTION_MATRIX * vp;
		col = vec3(1.0, 0.86, 0.6);
	} else {
		float period = 14.0 + 20.0 * s.y;
		float u = freeze >= 0.0 ? freeze : mod(TIME + s.z * period, period) / 2.6;
		if (u > 1.0 || s.w < 0.5) {
			POSITION = vec4(2.0, 2.0, 2.0, 1.0);  // outside the clip box: no pixels
			col = vec3(0.0);
		} else {
			float dir = s.x > 0.5 ? 1.0 : -1.0;
			vec3 p = VERTEX;
			p.y += abs(p.x) * 1.0 * sin(TIME * 38.0);  // wing beat
			p.xz *= -dir;                               // fly the other way
			vec3 c = vec3(head.x + 1.6 * sin(u * 6.0 + s.x * 6.28),
				4.6 + 1.1 * sin(u * 9.0 + s.z * 6.0),
				dir * (u * 2.0 - 1.0) * 9.0);
			POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(p + c, 1.0));
			col = vec3(0.34, 0.2, 0.1);  // warm brown: lit from the lamp above
		}
	}
}

void fragment() {
	ALBEDO = col;
}
"""

static func _get_swarm_mat() -> ShaderMaterial:
	if _swarm_mat == null:
		var sh := Shader.new()
		sh.code = SWARM_SHADER
		_swarm_mat = ShaderMaterial.new()
		_swarm_mat.shader = sh
	return _swarm_mat

# ---------- A6: banners ----------

static func _get_banner_mesh() -> ArrayMesh:
	if _banner_mesh == null:
		var b := _Buf.new()
		var n := Vector3.LEFT
		var cloth := Color(0.0, 0.0, 0.0, 1.0)
		for r in range(BANNER_ROWS):
			for c in range(BANNER_COLS):
				var u0 := float(c) / float(BANNER_COLS)
				var u1 := float(c + 1) / float(BANNER_COLS)
				var v0 := float(r) / float(BANNER_ROWS)
				var v1 := float(r + 1) / float(BANNER_ROWS)
				var z0 := (u0 - 0.5) * BANNER_W
				var z1 := (u1 - 0.5) * BANNER_W
				var y0 := BANNER_TOP - v0 * BANNER_H
				var y1 := BANNER_TOP - v1 * BANNER_H
				b.quad(Vector3(BANNER_X, y0, z0), Vector3(BANNER_X, y1, z0), Vector3(BANNER_X, y1, z1), Vector3(BANNER_X, y0, z1),
					n, cloth, Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0))
		# bracket from the pole and the top rod: dark metal, COLOR.r = 1
		var metal := Color(1.0, 0.0, 0.0, 1.0)
		var top := BANNER_TOP + 0.03
		b.quad(Vector3(0.0, top - 0.03, 0.0), Vector3(0.0, top + 0.03, 0.0), Vector3(BANNER_X, top + 0.03, 0.0), Vector3(BANNER_X, top - 0.03, 0.0),
			Vector3.BACK, metal, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		b.quad(Vector3(BANNER_X, top - 0.03, -BANNER_W * 0.55), Vector3(BANNER_X, top + 0.03, -BANNER_W * 0.55),
			Vector3(BANNER_X, top + 0.03, BANNER_W * 0.55), Vector3(BANNER_X, top - 0.03, BANNER_W * 0.55),
			Vector3.LEFT, metal, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		_banner_mesh = b.commit(AABB(Vector3(-1.2, 3.4, -0.8), Vector3(1.4, 2.8, 1.6)))
	return _banner_mesh

# District fields and emblems, Amber vs Dusk only:
#   0 downtown     dusk navy field, amber diamond
#   1 residential  amber field, navy ring
#   2 strip        sodium orange field, dark chevron
#   3 industrial   silver field, navy bars
const BANNER_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_disabled;

// INSTANCE_CUSTOM: x district slot, y phase seed
uniform float wind = 0.6;
varying flat float slot;
varying float metal;
varying float hang;

void vertex() {
	slot = INSTANCE_CUSTOM.x;
	metal = COLOR.r;
	hang = 0.0;
	if (COLOR.r < 0.5) {
		// cloth: pinned at the top, free at the bottom, a travelling ripple
		hang = UV.y;
		float ph = INSTANCE_CUSTOM.y * 6.28;
		float amp = (0.04 + 0.16 * wind) * hang;
		float rip = sin(TIME * (2.0 + 1.2 * wind) + hang * 3.0 + VERTEX.z * 4.0 + ph)
			+ 0.45 * sin(TIME * 4.3 + hang * 5.0 + ph * 1.7);
		// the wind bellies the banner away from the pole side and swings it
		VERTEX.x += amp * rip + 0.12 * wind * hang * hang;
		VERTEX.z *= 1.0 - 0.06 * wind * hang;
	}
}

float diamond(vec2 p, float r) { return step(abs(p.x) + abs(p.y), r); }

void fragment() {
	vec3 navy = vec3(0.08, 0.13, 0.26);
	vec3 amber = vec3(1.0, 0.66, 0.25);
	vec3 orange = vec3(0.85, 0.40, 0.10);
	vec3 silver = vec3(0.62, 0.65, 0.70);
	vec3 dark = vec3(0.09, 0.09, 0.10);
	vec3 field = navy;
	vec3 mark = amber;
	vec2 p = (UV - vec2(0.5, 0.36)) * vec2(0.76, 2.1);  // metres from the emblem centre
	float m = 0.0;
	int s = int(slot + 0.5);
	if (s == 0) {
		field = navy; mark = silver * 1.25;
		m = diamond(p, 0.27) * (1.0 - diamond(p, 0.15));
	} else if (s == 1) {
		field = amber * 0.88; mark = navy;
		float d = length(p);
		m = step(0.14, d) * step(d, 0.26);
	} else if (s == 2) {
		field = vec3(0.13, 0.12, 0.13); mark = orange * 1.15;
		float chev = abs(p.x) * 1.1 - p.y;  // two stacked chevrons
		m = step(abs(mod(chev + 0.4, 0.34) - 0.17), 0.065) * step(abs(p.x), 0.3) * step(abs(p.y), 0.42);
	} else {
		field = silver; mark = navy;
		m = step(abs(p.x), 0.27) * step(0.5, fract(p.y * 5.0 + 0.25)) * step(abs(p.y), 0.34);
	}
	vec3 c = mix(field, mark, m);
	// hem: a dark band at the bottom edge, a thin one at the top
	c = mix(c, dark, step(0.955, UV.y));
	c = mix(c, dark * 1.6, step(UV.y, 0.025));
	if (metal > 0.5) {
		c = dark;
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
	// lit amber by the lamp above: strongest at the top of the cloth
	EMISSION = c * vec3(1.0, 0.62, 0.30) * mix(0.7, 0.2, hang);
}
"""

static func _get_banner_mat() -> ShaderMaterial:
	if _banner_mat == null:
		var sh := Shader.new()
		sh.code = BANNER_SHADER
		_banner_mat = ShaderMaterial.new()
		_banner_mat.shader = sh
		_banner_mat.set_shader_parameter("wind", _wind)
	return _banner_mat

# ---------- A2: steam ----------

static func _get_steam_mesh() -> ArrayMesh:
	if _steam_mesh == null:
		var b := _Buf.new()
		for i in range(3):
			_corner_quad(b, 0.0, float(i) / 3.0)
		_steam_mesh = b.commit(AABB(Vector3(-3.0, 0.0, -3.0), Vector3(6.0, 4.5, 6.0)))
	return _steam_mesh

const STEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

// Three soft puffs per vent, each rising, widening and fading on its own
// phase. INSTANCE_CUSTOM: x seed, y 1 = drain (a thinner plume)
uniform float wind = 0.6;
varying float life;
varying float thin;
varying float depth;

void vertex() {
	float seed = INSTANCE_CUSTOM.x;
	thin = INSTANCE_CUSTOM.y;
	life = fract(TIME * 0.17 + COLOR.g + seed);
	float h = life * (2.4 - 0.7 * thin);
	float size = mix(0.30, 1.05, life) * (1.0 - 0.3 * thin);
	vec3 c = vec3(wind * life * life * 1.8 + 0.12 * sin(TIME * 0.9 + COLOR.g * 20.0 + seed * 9.0), 0.08 + h, 0.0);
	vec4 vp = MODELVIEW_MATRIX * vec4(c, 1.0);
	depth = -vp.z;
	vp.xy += VERTEX.xy * size;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float soft = smoothstep(1.0, 0.15, d);
	soft *= soft;  // a rounder, softer core
	float fade = smoothstep(0.0, 0.15, life) * (1.0 - smoothstep(0.5, 1.0, life));
	// never a big card in the lens: gone inside 2 m, full past 6 m
	float near = smoothstep(2.0, 6.0, depth);
	ALBEDO = vec3(1.0, 0.70, 0.40);  // lit amber by the lamp pool it stands in
	ALPHA = soft * fade * near * 0.26;
}
"""

static func _get_steam_mat() -> ShaderMaterial:
	if _steam_mat == null:
		var sh := Shader.new()
		sh.code = STEAM_SHADER
		_steam_mat = ShaderMaterial.new()
		_steam_mat.shader = sh
		_steam_mat.set_shader_parameter("wind", _wind)
	return _steam_mat

## The manhole cover (or, squashed, a gutter grate): a dark disc with a
## lighter inner plate, opaque, flat on the road.
static func _get_cover_mesh() -> ArrayMesh:
	if _cover_mesh == null:
		var b := _Buf.new()
		var sides := 12
		var rings := [[0.45, 0.026, Color(0.05, 0.05, 0.055, 1.0)], [0.34, 0.031, Color(0.10, 0.10, 0.105, 1.0)]]
		for ring in rings:
			var r: float = ring[0]
			var y: float = ring[1]
			var col: Color = ring[2]
			for i in range(sides):
				var a0 := TAU * float(i) / float(sides)
				var a1 := TAU * float(i + 1) / float(sides)
				b.tri(Vector3(0, y, 0), Vector3(cos(a0) * r, y, sin(a0) * r), Vector3(cos(a1) * r, y, sin(a1) * r), Vector3.UP, col)
		_cover_mesh = b.commit(AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 0.1, 1.0)))
	return _cover_mesh

static func _get_cover_mat() -> StandardMaterial3D:
	if _cover_mat == null:
		_cover_mat = StandardMaterial3D.new()
		_cover_mat.vertex_color_use_as_albedo = true
		_cover_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cover_mat.roughness = 0.85
	return _cover_mat

# ---------- A5: windblown litter ----------

static func _get_litter_mesh() -> ArrayMesh:
	if _litter_mesh == null:
		var b := _Buf.new()
		# kind 0 newspaper (a folded sheet), kind 1 a leaf; flat in XZ
		var pieces := [[0.0, 0.20, 0.14], [0.0, 0.17, 0.12], [0.0, 0.15, 0.11], [1.0, 0.09, 0.065], [1.0, 0.08, 0.06], [1.0, 0.07, 0.05]]
		for i in range(pieces.size()):
			var kind: float = pieces[i][0]
			var hx: float = pieces[i][1]
			var hz: float = pieces[i][2]
			var col := Color(kind, (float(i) + 0.31) / float(pieces.size()), 0.0, 1.0)
			b.quad(Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3(hx, 0, -hz), Vector3.UP, col,
				Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
		# generous: the shader drifts the pieces about the middle of the chunk
		_litter_mesh = b.commit(AABB(Vector3(-16.0, -0.2, -22.0), Vector3(32.0, 3.0, 44.0)))
	return _litter_mesh

const LITTER_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_disabled;

// Each chunk has a gust now and then; for its few seconds the pieces tumble
// across the road with the wind, and the rest of the time they are gone.
// INSTANCE_CUSTOM: x road centre, y road half-width (chunk-space X),
// z period seed, w phase seed
uniform float wind = 0.6;
uniform float freeze = -1.0;  // >= 0: every gust held at this point (screenshots)
varying vec3 col;

mat3 rotx(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 roty(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }

void vertex() {
	vec4 s = INSTANCE_CUSTOM;
	float ph = COLOR.g;
	float period = 17.0 + 15.0 * s.z;
	float len = 5.0 + 3.0 * wind;
	float u = freeze >= 0.0 ? freeze : mod(TIME + s.w * period, period) / len;
	float on = step(u, 1.0) * step(0.05, wind);
	float grow = smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.88, 1.0, u)) * on;
	float x = s.x + s.y * 1.05 * (2.0 * clamp(u, 0.0, 1.0) - 1.0);
	float z = (fract(ph * 7.31 + s.w) - 0.5) * 22.0 + sin(u * 5.0 + ph * 20.0) * 3.0 + u * 4.0;
	float hop = abs(sin(u * (7.0 + ph * 4.0) * 3.14159 + ph * 9.0));
	float y = 0.10 + hop * (0.35 + 0.5 * wind) * (0.4 + ph);
	float a = TIME * (3.0 + 5.0 * ph) + ph * 30.0;
	mat3 r = rotx(a) * roty(a * 0.7 + ph * 6.0);
	VERTEX = r * (VERTEX * grow) + vec3(x, y, z);
	NORMAL = r * NORMAL;
	col = COLOR.r < 0.5 ? vec3(0.72, 0.70, 0.64) : vec3(0.72, 0.42, 0.14);
}

void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.95;
	EMISSION = col * vec3(1.0, 0.65, 0.35) * 0.25;
}
"""

static func _get_litter_mat() -> ShaderMaterial:
	if _litter_mat == null:
		var sh := Shader.new()
		sh.code = LITTER_SHADER
		_litter_mat = ShaderMaterial.new()
		_litter_mat.shader = sh
		_litter_mat.set_shader_parameter("wind", _wind)
	return _litter_mat

## Triangle count of one chunk's worth of this step at its caps (tests,
## budget): 4 swarms, 4 banners, 1 vent (steam + cover), 1 litter set.
static func worst_case_triangles(lamp_capacity: int) -> int:
	return (lamp_capacity * _tris(_get_swarm_mesh()) + lamp_capacity * _tris(_get_banner_mesh())
		+ _tris(_get_steam_mesh()) + _tris(_get_cover_mesh()) + _tris(_get_litter_mesh()))

static func _tris(m: ArrayMesh) -> int:
	return floori(float(m.surface_get_array_len(0)) / 3.0)
