extends RefCounted

# Area signs and street-name blades (world step 4, "Names you can read").
#
# One MultiMesh per chunk ("NameSigns") with one material draws the lot:
# posts, arms, dark backing panels, lettering plates and floodlight heads are
# all the same unit box, told apart by the instance's custom data. A chunk
# that has no sign shows zero instances, so it costs nothing to draw.
#
# Look (docs/planning/road-lane-changes-proposal-2026-10-08.md, "Named
# stretches"): not US green. Dark navy-charcoal panels, off-white and amber
# lettering, a thin silver frame, grime streaks, sodium floodlights under the
# gantry with the odd one burnt out. Letters are lit a little (below the
# bloom threshold), so the panel stays dark and the words still read at a
# glance at night. Lettering is the "road" font role (Overpass), drawn into
# word_atlas.gd.
#
# Two kinds of area sign, both standing on the own-direction side of the
# road and facing the traffic that drives toward the area:
#   gantry:   "ENTERING" over the area's name, on a cantilever arm over the
#             lanes, a few metres before the area starts.
#   advance:  the name over "400 m", roadside on two short posts, 400 m
#             before the area starts.
# Blades (street names on the signal masts at a crossing) are placed by
# Junction with blade().
#
# Everything is laid out in the straight road description (x across, z along,
# own side +x, traffic drives toward -z) and bent onto the road by the chunk
# builder, as the shop signs are.

const WordAtlas := preload("res://scripts/world/word_atlas.gd")
const PlaceNames := preload("res://scripts/world/place_names.gd")

## Instance styles (custom data w).
const TEXT := 0     # a lettering plate: letters lit on the dark panel
const METAL := 1    # posts, arms
const PANEL := 2    # backing panel with a frame and grime
const LAMP := 3     # a floodlight head, on
const LAMP_DEAD := 4
const BLADE := 5    # a lettering plate with its own frame

## Letter colours (custom data z): index into the shader's colour table.
const OFF_WHITE := 0
const AMBER := 1
const SODIUM := 2
const SILVER := 3

const CAPACITY := 24

const GANTRY_TOP := 7.6        # arm height above the road
const GANTRY_PANEL_TOP := 7.3
const GANTRY_POST := 0.34
const PANEL_DEPTH := 0.14
const PLATE_DEPTH := 0.03
const ROAD_LINE_H := 1.15      # lettering plate height of the area's name, m
const SMALL_LINE_H := 0.62     # "ENTERING" / "400 m"
const MARGIN := 0.35           # panel margin around the lettering, m
const MAX_PANEL_LEN := 11.0

const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2DArray words : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 colors[4];
uniform float text_energy = 0.75;
uniform float lamp_energy = 2.2;
uniform float band_y0 = 14.0;
uniform float band_h = 42.0;
uniform float atlas_w = 512.0;
uniform float atlas_h = 64.0;
uniform float pad = 6.0;

varying vec3 lpos;
varying vec3 lnrm;
varying vec4 cd;

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
	cd = INSTANCE_CUSTOM;  // x: atlas layer, y: text width px, z: colour, w: style
}

void fragment() {
	vec3 metal = vec3(0.075, 0.075, 0.08);
	vec3 panel = vec3(0.05, 0.065, 0.11);
	float style = cd.w;
	ALBEDO = metal;
	ROUGHNESS = 0.8;
	bool big = abs(lnrm.x) > 0.5;
	float len = length(MODEL_MATRIX[2].xyz);
	float hgt = length(MODEL_MATRIX[1].xyz);
	if (style > 2.5 && style < 3.5) {
		ALBEDO = vec3(0.25, 0.14, 0.05);
		EMISSION = vec3(1.0, 0.55, 0.2) * lamp_energy;
	} else if (style > 3.5 && style < 4.5) {
		ALBEDO = vec3(0.09, 0.075, 0.06);
	} else if (big && style > 1.5 && style < 2.5) {
		// backing panel: front face dark with a silver frame and grime
		float u = lnrm.x < 0.0 ? lpos.z + 0.5 : 0.5 - lpos.z;
		float v = 0.5 - lpos.y;
		if (lnrm.x < 0.0) {
			float e = min(min(u, 1.0 - u) * len, min(v, 1.0 - v) * hgt);
			float frame = step(0.1, e) * (1.0 - step(0.16, e));
			float streak = fract(sin(floor(u * len * 2.5) * 12.9898) * 43758.5453);
			float grime = 1.0 - 0.45 * streak * smoothstep(0.1, 1.0, v);
			ALBEDO = mix(panel * grime, vec3(0.45, 0.47, 0.5), frame);
		}
	} else if (big && (style < 0.5 || style > 4.5)) {
		float u = lnrm.x < 0.0 ? lpos.z + 0.5 : 0.5 - lpos.z;
		float v = 0.5 - lpos.y;
		float span = cd.y + 2.0 * pad;
		float px = u * span;
		float py = band_y0 + v * band_h;
		float inside = step(0.0, px) * step(px, span);
		vec3 uvw = vec3(px / atlas_w, py / atlas_h, floor(cd.x + 0.5));
		float cov = texture(words, uvw).r * inside;
		vec3 col = colors[int(cd.z + 0.5)];
		ALBEDO = mix(panel, col * 0.35, cov);
		EMISSION = col * cov * text_energy;
		if (style > 4.5) {
			float e = min(min(u, 1.0 - u) * len, min(v, 1.0 - v) * hgt);
			float frame = step(0.025, e) * (1.0 - step(0.05, e));
			ALBEDO = mix(ALBEDO, vec3(0.45, 0.47, 0.5), frame);
		}
	}
}
"""

static var _material: ShaderMaterial
static var _box: BoxMesh

static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
		_material.set_shader_parameter("words", WordAtlas.texture())
		var cols := PackedVector3Array([
			Vector3(0.92, 0.89, 0.80),   # off-white
			Vector3(1.0, 0.75, 0.38),    # amber
			Vector3(1.0, 0.54, 0.12),    # sodium
			Vector3(0.79, 0.81, 0.84),   # silver
		])
		_material.set_shader_parameter("colors", cols)
		_material.set_shader_parameter("band_y0", float(WordAtlas.Y0))
		_material.set_shader_parameter("band_h", float(WordAtlas.BAND))
		_material.set_shader_parameter("atlas_w", float(WordAtlas.W))
		_material.set_shader_parameter("atlas_h", float(WordAtlas.H))
		_material.set_shader_parameter("pad", float(WordAtlas.PAD))
	return _material

static func box() -> BoxMesh:
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
	return _box

## One MultiMesh of name signs, capacity allocated once, nothing shown.
static func new_multimesh(capacity: int = CAPACITY) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = box()
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "NameSigns"
	mmi.multimesh = mm
	mmi.material_override = material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

## Basis of a box whose front face (local -x) points along `n`: x = -n,
## y up, z = the reader's right.
static func face_basis(n: Vector3) -> Basis:
	var bx := -n
	return Basis(bx, Vector3.UP, bx.cross(Vector3.UP))

## One instance: a box in a face frame. `centre` is the world (or
## road-description) position; scale is (depth, height, length).
static func _item(centre: Vector3, n: Vector3, depth: float, height: float, length: float, layer: int, text_px: int, colour: int, style: int) -> Dictionary:
	var basis := face_basis(n) * Basis.from_scale(Vector3(depth, height, length))
	return {"xf": Transform3D(basis, centre), "cd": Color(float(layer), float(text_px), float(colour), float(style))}

## Plate length for a text line `height` tall, so the letters keep their shape.
static func plate_len(word: String, height: float) -> float:
	return height * float(WordAtlas.width_px(word) + 2 * WordAtlas.PAD) / float(WordAtlas.BAND)

## A lettering plate centred at `centre`, on a face with normal `n`.
static func text_plate(word: String, centre: Vector3, n: Vector3, height: float, colour: int, style: int = TEXT, depth: float = PLATE_DEPTH) -> Dictionary:
	var l := WordAtlas.layer(word)
	return _item(centre, n, depth, height, plate_len(word, height), l, WordAtlas.width_px(word), colour, style)

## The area gantry, laid out in the straight road description: post foot at
## `foot` (x outside the sidewalk, y 0, z the sign's place along the chunk),
## panel facing +z (toward traffic), reaching toward the road centre (-x).
## `foundation` is how far the post goes below the road on a hilly road.
## Returns a list of {xf, cd} and the lowest panel edge via out["clearance"].
static func gantry(area: String, foot: Vector3, foundation: float, burnt: int = -1) -> Array:
	var n := Vector3(0.0, 0.0, 1.0)
	var small_h := SMALL_LINE_H
	var big_h := ROAD_LINE_H
	var big_len := plate_len(area, big_h)
	if big_len > MAX_PANEL_LEN - 2.0 * MARGIN:
		big_h *= (MAX_PANEL_LEN - 2.0 * MARGIN) / big_len
		big_len = MAX_PANEL_LEN - 2.0 * MARGIN
	var small_len := plate_len(PlaceNames.ENTERING, small_h)
	var inner := maxf(big_len, small_len)
	var panel_len := inner + 2.0 * MARGIN
	var panel_h := small_h + big_h + 3.0 * 0.22
	var out: Array = []
	# post, standing on the ground (or the hill under it)
	var post_h := GANTRY_TOP + 0.35
	out.append(_item(Vector3(foot.x, (post_h - foundation) / 2.0, foot.z), n, GANTRY_POST, post_h + foundation, GANTRY_POST, 0, 0, 0, METAL))
	# arm: from the post toward the road, long enough to carry the panel
	var reach := panel_len + 0.9
	out.append(_item(Vector3(foot.x - reach / 2.0, GANTRY_TOP, foot.z), n, 0.22, 0.24, reach, 0, 0, 0, METAL))
	# backing panel, hung under the arm
	var cx := foot.x - 0.5 - panel_len / 2.0
	var cy := GANTRY_PANEL_TOP - panel_h / 2.0
	var front := n * (PANEL_DEPTH / 2.0 + PLATE_DEPTH / 2.0 + 0.004)
	out.append(_item(Vector3(cx, cy, foot.z), n, PANEL_DEPTH, panel_h, panel_len, 0, 0, 0, PANEL))
	# lettering: "ENTERING" amber on top, the name below
	var y_small := GANTRY_PANEL_TOP - 0.22 - small_h / 2.0
	var y_big := GANTRY_PANEL_TOP - 0.22 - small_h - 0.22 - big_h / 2.0
	out.append(text_plate(PlaceNames.ENTERING, Vector3(cx, y_small, foot.z) + front, n, small_h, AMBER))
	out.append(text_plate(area, Vector3(cx, y_big, foot.z) + front, n, big_h, OFF_WHITE))
	# floodlights under the panel, one in the line burnt out now and then
	var bottom := GANTRY_PANEL_TOP - panel_h
	for k in 3:
		var lx := cx + (float(k) - 1.0) * panel_len * 0.32
		var style := LAMP_DEAD if k == burnt else LAMP
		out.append(_item(Vector3(lx, bottom - 0.08, foot.z) + n * 0.32, n, 0.6, 0.14, 0.3, 0, 0, 0, style))
	return out

## Height of the lowest part of a gantry panel above the road, m.
static func gantry_clearance(area: String) -> float:
	var big_h := ROAD_LINE_H
	var big_len := plate_len(area, big_h)
	if big_len > MAX_PANEL_LEN - 2.0 * MARGIN:
		big_h *= (MAX_PANEL_LEN - 2.0 * MARGIN) / big_len
	return GANTRY_PANEL_TOP - (SMALL_LINE_H + big_h + 3.0 * 0.22) - 0.15

## The advance sign: a smaller panel on a single post just outside the
## sidewalk, the name over its distance, hung from a short arm and toed in
## `toe` radians toward the lanes. `foot` is the post's foot. (One post: a
## second one would stand in the road.)
static func advance(area: String, foot: Vector3, foundation: float, toe: float = 0.2) -> Array:
	var n := Vector3(-sin(toe), 0.0, cos(toe))
	var big_h := 0.8
	var small_h := 0.46
	var big_len := plate_len(area, big_h)
	if big_len > 7.0:
		big_h *= 7.0 / big_len
		big_len = 7.0
	var small_len := plate_len(PlaceNames.ADVANCE, small_h)
	var panel_len := maxf(big_len, small_len) + 0.6
	var panel_h := big_h + small_h + 3.0 * 0.16
	var bottom := 3.4
	var top := bottom + panel_h
	var post_h := top + 0.5
	var cx := foot.x - 0.45 - panel_len / 2.0
	var cy := bottom + panel_h / 2.0
	var arm_len := foot.x - (cx - panel_len / 2.0)
	var out: Array = []
	out.append(_item(Vector3(foot.x, (post_h - foundation) / 2.0, foot.z), Vector3.BACK, 0.18, post_h + foundation, 0.18, 0, 0, 0, METAL))
	out.append(_item(Vector3(foot.x - arm_len / 2.0, top + 0.2, foot.z), Vector3.BACK, 0.14, 0.16, arm_len, 0, 0, 0, METAL))
	var base := Vector3(cx, cy, foot.z)
	var front := n * (PANEL_DEPTH / 2.0 + PLATE_DEPTH / 2.0 + 0.004)
	out.append(_item(base, n, PANEL_DEPTH, panel_h, panel_len, 0, 0, 0, PANEL))
	out.append(text_plate(area, Vector3(cx, top - 0.16 - big_h / 2.0, foot.z) + front, n, big_h, OFF_WHITE))
	out.append(text_plate(PlaceNames.ADVANCE, Vector3(cx, top - 0.16 - big_h - 0.16 - small_h / 2.0, foot.z) + front, n, small_h, AMBER))
	return out

## A street-name blade: a framed plate `height` tall at `centre`, face along
## `n`. Used on the signal masts at a crossing (Junction).
static func blade(word: String, centre: Vector3, n: Vector3, height: float = 0.3, colour: int = OFF_WHITE) -> Dictionary:
	return text_plate(word, centre, n, height, colour, BLADE, 0.05)
