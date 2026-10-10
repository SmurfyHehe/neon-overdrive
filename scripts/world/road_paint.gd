extends RefCounted

# Painted road words and arrows (world step 4, "Names you can read"): SLOW,
# BUS, STOP, speed numbers and lane arrows, as flat decals drawn from ONE
# MultiMesh per chunk ("RoadPaint"). Every mark is a unit quad scaled to its
# lettering; the shader reads the word from the lettering atlas
# (word_atlas.gd, "road" font role) and draws it as paint: off-white, the same
# colour and glow as the lane dashes, a little worn. A chunk with no marks
# shows zero instances.
#
# What goes where (marks() decides, from the chunk number alone, so a pooled
# chunk rebuilt later gets the same paint):
#   - at an area's start (second chunk of a district run) the area's speed
#     number in the outer lane,
#   - on the approach to a crossing: SLOW in every lane ~75 m out, lane arrows
#     ~32 m out (inner lane left, outer lane right, the rest straight),
#   - in districts with a bus lane, BUS in the outer lane every fourth chunk,
#   - on the cross street at the crossing, STOP in each approach lane (the
#     cross street flashes red after 1 a.m.). That one is placed by Junction.
# None of it is on a chunk where the lane count changes.
#
# Letters are drawn tall (STRETCH) as real road paint is, so they read from a
# driver's low angle. The quad sits PAINT_Y above the surface and is pulled a
# little toward the camera in the vertex stage, so it does not z-fight the
# asphalt at distance.

const WordAtlas := preload("res://scripts/world/word_atlas.gd")
const PlaceNames := preload("res://scripts/world/place_names.gd")

const CAPACITY := 16
const PAINT_Y := 0.022
## Painted cap height along the road before stretching, m, and the stretch.
const CAP_M := 0.62
const STRETCH := 3.2
const ARROW_SCALE := 1.45
## Same colour and glow as the lane dashes (RoadChunkBuilder.LANE_DASH_COLOR,
## PAINT_ENERGY); a test keeps them equal.
const PAINT_COLOR := Color(0.82, 0.82, 0.78)
const PAINT_ENERGY := 0.28

const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2DArray words : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 paint = vec3(0.82, 0.82, 0.78);
uniform float energy = 0.28;
uniform float band_y0 = 14.0;
uniform float band_h = 42.0;
uniform float atlas_w = 512.0;
uniform float atlas_h = 64.0;
uniform float pad = 6.0;

varying vec4 cd;

void vertex() {
	cd = INSTANCE_CUSTOM;  // x: atlas layer, y: text width px, z: wear (alpha), w: unused
}

void fragment() {
	float span = cd.y + 2.0 * pad;
	float px = UV.x * span;
	float py = band_y0 + UV.y * band_h;
	float inside = step(0.0, px) * step(px, span);
	vec3 uvw = vec3(px / atlas_w, py / atlas_h, floor(cd.x + 0.5));
	float cov = texture(words, uvw).r * inside;
	ALBEDO = paint;
	EMISSION = paint * energy * cov;
	ALPHA = cov * cd.z;
}
"""

static var _material: ShaderMaterial
static var _quad: PlaneMesh

static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
		_material.set_shader_parameter("words", WordAtlas.texture())
		_material.set_shader_parameter("paint", Vector3(PAINT_COLOR.r, PAINT_COLOR.g, PAINT_COLOR.b))
		_material.set_shader_parameter("energy", PAINT_ENERGY)
		_material.set_shader_parameter("band_y0", float(WordAtlas.Y0))
		_material.set_shader_parameter("band_h", float(WordAtlas.BAND))
		_material.set_shader_parameter("atlas_w", float(WordAtlas.W))
		_material.set_shader_parameter("atlas_h", float(WordAtlas.H))
		_material.set_shader_parameter("pad", float(WordAtlas.PAD))
	return _material

static func quad() -> PlaneMesh:
	if _quad == null:
		_quad = PlaneMesh.new()
		_quad.size = Vector2.ONE
	return _quad

static func new_multimesh(capacity: int = CAPACITY, mm_name: String = "RoadPaint") -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad()
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = mm_name
	mmi.multimesh = mm
	mmi.material_override = material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

## The mark `word` (a PlaceNames text or an arrow) as a scale: how wide and how
## long on the road, m.
static func size_of(word: String) -> Vector2:
	var s := CAP_M / 29.0   # m per atlas px; a cap letter is about 29 px
	var stretch := STRETCH
	if word.begins_with("#"):
		s *= ARROW_SCALE
		stretch = STRETCH * 1.1
	var w := float(WordAtlas.width_px(word) + 2 * WordAtlas.PAD) * s
	var l := float(WordAtlas.BAND) * s * stretch
	return Vector2(w, l)

## The instance transform (relative to `at`'s frame) and custom data of a
## mark: centred at (x, z) in the straight road description, turned `yaw`
## about the vertical (0: text reads left to right across a lane, toward -z).
static func item(word: String, x: float, z: float, yaw: float = 0.0, wear: float = 1.0) -> Dictionary:
	var sz := size_of(word)
	return {
		"x": x, "z": z, "yaw": yaw,
		"basis": Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(sz.x, 1.0, sz.y)),
		"cd": Color(float(WordAtlas.layer(word)), float(WordAtlas.width_px(word)), wear, 0.0),
	}

## Painted marks for chunk `chunk_index`, as a list of items (see item()),
## in the straight road description. `crossing_z` is the chunk-local z of a
## signalised crossing's centre (INF: none near). `lanes_changed` is true
## where the own lane count differs from the previous chunk's, which tapers
## the lanes: no paint there. Lane centres follow RoadChunkBuilder's dashes.
static func marks(chunk_index: int, district: String, run_len: int, own_lanes: int, lanes_changed: bool, crossing_z: float, median_gap: float, lane_w: float, chunk_len: float) -> Array:
	var out: Array = []
	if lanes_changed or own_lanes < 1:
		return out
	var margin := 4.0
	var h := hash([chunk_index, "paint"])
	var wear := 0.72 + 0.28 * float(posmod(h, 1000)) / 999.0
	var near_crossing := crossing_z < INF and absf(crossing_z + chunk_len * 0.5) < chunk_len + 130.0
	# the area's speed number, outer lane, just past the area sign
	if chunk_index > 0 and posmod(chunk_index, run_len) == 1:
		out.append(item(str(PlaceNames.speed_of(district)), median_gap + (float(own_lanes) - 0.5) * lane_w, -26.0, 0.0, wear))
	if crossing_z < INF:
		# SLOW, one per lane, 75 m before the centre; arrows 32 m before
		var zs := crossing_z + 75.0
		if zs < -margin and zs > -chunk_len + margin:
			for i in own_lanes:
				out.append(item("SLOW", median_gap + (float(i) + 0.5) * lane_w, zs, 0.0, wear))
		var za := crossing_z + 32.0
		if za < -margin and za > -chunk_len + margin:
			for i in own_lanes:
				var kind := "#STRAIGHT"
				if own_lanes >= 2 and i == 0:
					kind = "#LEFT"
				elif own_lanes >= 2 and i == own_lanes - 1:
					kind = "#RIGHT"
				out.append(item(kind, median_gap + (float(i) + 0.5) * lane_w, za, 0.0, wear))
	# a bus lane's word, every fourth chunk, away from a crossing
	if PlaceNames.has_bus(district) and own_lanes >= 2 and posmod(chunk_index, 4) == 2 and not near_crossing:
		out.append(item("BUS", median_gap + (float(own_lanes) - 0.5) * lane_w, -25.0, 0.0, wear))
	return out
