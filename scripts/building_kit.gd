extends RefCounted

# Roadside building kit (buildings step 1, 2026-10-07): one shared facade
# material for every building, varied per building instead of per material.
#
# Before: every building was the same dark box wearing one of two materials
# with the same world-space window grid, so the street read as one long
# apartment block. Now each building picks:
# - a facade tile from an 8-tile atlas (apartment bays, shop glass, office
#   ribbon, warehouse door, open parking slab, brick, concrete panel,
#   corrugated metal), with a separate ground-floor row so shops get glass
#   and warehouses get roller doors at street level,
# - a base tint from the Amber vs Dusk palette (dark brick, concrete, navy,
#   sand, soot, rust),
# - a floor count (the tile repeats once per floor, so the roof line always
#   lands on a whole floor),
# - a lit-window density.
#
# All of that goes in per-instance shader parameters (instance uniforms) on
# ONE ShaderMaterial, so variety costs no extra materials, meshes or nodes.
# The facade is mapped in the building's own space, not world space, so a
# floating-origin recentre cannot shift the pattern.
#
# The atlas is drawn here in code (no image asset to import), 32x32 px per
# tile with nearest filtering for the PS2 look. Each tile is one bay wide and
# one floor tall: RGB is albedo detail (multiplied by the tint), alpha marks
# glass that may light up.
#
# Step 2 adds building types on top (see TYPES) and shop / garage signs
# (scripts/building_signs.gd). Which windows are lit is decided per window in the
# shader from a hash, so it never repeats from one building to the next.

const BuildingSigns := preload("res://scripts/building_signs.gd")

const TILE_PX := 32
const TILES := 8

# Tile ids (atlas columns).
const T_APARTMENT := 0
const T_SHOP := 1
const T_OFFICE := 2
const T_WAREHOUSE := 3
const T_PARKING := 4
const T_BRICK := 5
const T_CONCRETE := 6
const T_CORRUGATED := 7

# Floor-to-floor height per tile, m (approximate real values: offices are
# taller than flats; warehouses are one tall storey).
const FLOOR_H := [3.0, 3.4, 3.6, 4.5, 3.0, 3.1, 3.2, 4.2]
# Nominal bay width per tile, m. The shader rounds each face to a whole
# number of bays so windows are never cut at a corner.
const BAY_W := [3.0, 4.5, 3.0, 5.0, 6.0, 2.6, 3.4, 4.0]
# Share of lit windows that are cold fluorescent rather than warm
# incandescent: homes are warm, offices and car parks are cold.
const COOL_BIAS := [0.2, 0.7, 0.85, 0.6, 1.0, 0.25, 0.35, 0.6]
# Emission scale per tile: a lit office ribbon or open car-park deck is a
# whole bay of glass, so it is dimmed to sit beside a single lit flat
# window instead of glowing as a white panel.
const GLOW := [1.0, 0.75, 0.3, 0.8, 0.22, 1.0, 1.0, 1.0]

# Base tints, linear-ish albedo. Dark on purpose: this is a city at 2 a.m.,
# the facades are read by their windows and the sodium haze, not by colour.
# Amber vs Dusk only (no magenta, no cyan).
const TINTS := [
	Color(0.30, 0.29, 0.27),  # concrete
	Color(0.33, 0.29, 0.24),  # warm grey
	Color(0.32, 0.18, 0.13),  # brick
	Color(0.15, 0.19, 0.30),  # dusk navy (#1B2A4A family)
	Color(0.38, 0.33, 0.25),  # sand
	Color(0.17, 0.16, 0.16),  # soot
	Color(0.30, 0.18, 0.11),  # rust
	Color(0.23, 0.24, 0.28),  # slate
]

const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_nearest_mipmap, repeat_disable;
uniform float emission_energy = 1.25;
uniform int tiles = 8;
uniform float bay_w[8];
uniform float cool_bias[8];
uniform float glow[8];

instance uniform int tile = 0;
instance uniform vec3 tint : source_color = vec3(0.3);
instance uniform vec3 size = vec3(1.0);
instance uniform float floor_h = 3.2;
instance uniform float lit_density = 0.3;
instance uniform float seed = 0.0;

varying vec3 lpos;
varying vec3 lnrm;
varying float wy;

void vertex() {
	lpos = VERTEX * size;  // the mesh is a shared unit cube, scaled by the node
	lnrm = NORMAL;
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	vec3 an = abs(lnrm);
	if (an.y > 0.5) {
		// flat roof: dark tar, a touch of the tint
		ALBEDO = tint * 0.3;
		ROUGHNESS = 1.0;
	} else {
		// horizontal coordinate along this face and the face's length
		bool on_x = an.x > an.z;
		float coord = on_x ? lpos.z * sign(lnrm.x) : -lpos.x * sign(lnrm.z);
		float len = on_x ? size.z : size.x;
		float bays = max(1.0, round(len / bay_w[tile]));
		float u = (coord + len * 0.5) / len * bays;
		float v = max(wy, 0.0) / floor_h;
		float fl = floor(v);
		float row = fl < 0.5 ? 1.0 : 0.0;  // atlas row 1 = ground floor
		vec2 cell = vec2(fract(u), 1.0 - fract(v));
		vec2 auv = vec2((float(tile) + cell.x) / float(tiles), (row + cell.y) * 0.5);
		// gradients from the continuous coordinate, so the fract() seams do
		// not drop to the smallest mip and draw a line
		vec2 g = vec2(u / float(tiles), -v * 0.5);
		vec4 t = textureGrad(atlas, auv, dFdx(g), dFdy(g));
		ALBEDO = tint * t.rgb;
		ROUGHNESS = mix(0.9, 0.35, t.a);
		float face = on_x ? (lnrm.x > 0.0 ? 1.0 : 2.0) : (lnrm.z > 0.0 ? 3.0 : 4.0);
		vec3 key = vec3(floor(u), fl, seed * 7.13 + face * 31.7);
		float h = hash3(key);
		// threshold the glass mask: a blurred far mip must not let wall emit
		float lit = step(h, lit_density) * step(0.5, t.a);
		float h2 = hash3(key + 19.19);
		vec3 warm = vec3(1.0, 0.72, 0.38);
		vec3 cool = vec3(0.74, 0.86, 0.7);  // white-green fluorescent
		vec3 tv = vec3(0.42, 0.5, 0.8);
		vec3 c = h2 < cool_bias[tile] ? cool : warm;
		if (h2 > 0.96) { c = tv; }
		EMISSION = c * lit * mix(0.55, 1.0, hash3(key + 3.7)) * emission_energy * glow[tile];
	}
}
"""

static var _material: ShaderMaterial
static var _atlas: ImageTexture
static var _unit_box: BoxMesh

## The one material every building shares.
static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
		_material.set_shader_parameter("atlas", atlas())
		_material.set_shader_parameter("tiles", TILES)
		_material.set_shader_parameter("bay_w", PackedFloat32Array(BAY_W))
		_material.set_shader_parameter("cool_bias", PackedFloat32Array(COOL_BIAS))
		_material.set_shader_parameter("glow", PackedFloat32Array(GLOW))
	return _material

## One unit cube shared by every building; the node's scale sets its size.
static func unit_box() -> BoxMesh:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	return _unit_box

# Building types (buildings step 2). A type picks the facade tiles that suit
# it, its height range and whether it carries a sign. The old "garage" roll
# (the low sheds) is the garage type: an auto shop with roller doors and a
# TIRES / PARTS / AUTO / BODY sign, which milestone 8's stop-places can use.
const TYPES := {
	"apartment": {"tiles": [[T_APARTMENT, 60], [T_BRICK, 20], [T_CONCRETE, 20]], "h": [8.0, 24.0], "sign": 0.0},
	"shop": {"tiles": [[T_SHOP, 100]], "h": [3.4, 10.5], "sign": 0.85},
	"office": {"tiles": [[T_OFFICE, 70], [T_CONCRETE, 30]], "h": [12.0, 30.0], "sign": 0.0},
	"parking": {"tiles": [[T_PARKING, 100]], "h": [6.0, 15.0], "sign": 0.0},
	"garage": {"tiles": [[T_WAREHOUSE, 60], [T_CORRUGATED, 40]], "h": [0.0, 0.0], "sign": 0.7},
	"warehouse": {"tiles": [[T_WAREHOUSE, 60], [T_CORRUGATED, 40]], "h": [7.0, 12.0], "sign": 0.0},
	# Special buildings (step 5). A gas station is a kiosk at the back of its
	# lot under a lit canopy; a diner is a glass box behind a tall pole sign.
	"gas": {"tiles": [[T_SHOP, 100]], "h": [3.4, 3.4], "sign": 1.0, "word": "GAS"},
	"diner": {"tiles": [[T_SHOP, 100]], "h": [4.4, 4.4], "sign": 1.0, "word": "DINER"},
}
# Mix for an ordinary street until districts (step 4) set their own.
const STREET_MIX := [["apartment", 40], ["shop", 30], ["office", 18], ["parking", 12]]

## Picks a building's type and look from its own RNG and writes the look onto
## the mesh instance. is_low is the old "garage" roll (a low, wide shed);
## h_roll is the height draw in [0, 1]; district is a Districts spec (type
## mix, height overrides, lit-window and billboard multipliers). Returns
## {h, type, tile, floor_h, sign, sign_color, sign_style}; h is a whole
## number of floors, sign is "" when the building has none.
static func dress(mi: MeshInstance3D, rng: RandomNumberGenerator, is_low: bool, h_roll: float, w: float, d: float, district: Dictionary = {}) -> Dictionary:
	var type: String
	if is_low:
		type = district.get("low", "garage")
	else:
		type = _weighted_s(rng, district.get("mix", STREET_MIX))
	var spec: Dictionary = TYPES[type]
	var tile := _weighted(rng, spec.tiles)
	var fh: float = FLOOR_H[tile]
	var floors: int
	if type == "garage":
		floors = 1
	else:
		var hr: Array = district.get("h", {}).get(type, spec.h)
		floors = maxi(1, roundi(lerpf(hr[0], hr[1], h_roll) / fh))
		if type != "shop" and type != "gas" and type != "diner":
			floors = maxi(2, floors)
	var h := float(floors) * fh
	var tint: Color = TINTS[rng.randi() % TINTS.size()]
	tint = tint * rng.randf_range(0.65, 0.85)
	var density := rng.randf_range(0.12, 0.42)
	if tile == T_WAREHOUSE or tile == T_CORRUGATED:
		density *= 0.4
	elif tile == T_OFFICE:
		density *= 0.6  # offices at 2 a.m. are mostly dark
	density = minf(density * float(district.get("lit", 1.0)), 0.6)
	mi.mesh = unit_box()
	mi.material_override = material()
	mi.scale = Vector3(w, h, d)
	mi.set_instance_shader_parameter("tile", tile)
	mi.set_instance_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	mi.set_instance_shader_parameter("size", Vector3(w, h, d))
	mi.set_instance_shader_parameter("floor_h", fh)
	mi.set_instance_shader_parameter("lit_density", density)
	mi.set_instance_shader_parameter("seed", float(rng.randi() % 4096))
	mi.set_meta("facade_tile", tile)
	mi.set_meta("building_type", type)
	var word := ""
	if rng.randf() < float(spec.sign):
		var pool: Array = BuildingSigns.GARAGE_WORDS if type == "garage" else BuildingSigns.SHOP_WORDS
		word = pool[rng.randi() % pool.size()]
		if spec.has("word"):
			word = spec.word
	var sign_color := rng.randi() % BuildingSigns.COLORS.size()
	var sign_style := 1 if rng.randf() < 0.3 else 0
	# short words on shops can hang as a blade over the sidewalk instead
	var blade := type == "shop" and word.length() <= 5 and rng.randf() < 0.45
	if type == "gas":
		sign_color = 2  # forecourt fluorescent
		sign_style = 1
	elif type == "diner":
		sign_color = 0  # sodium amber
		sign_style = 0
	if word != "":
		mi.set_meta("sign_word", word)
	elif mi.has_meta("sign_word"):
		mi.remove_meta("sign_word")
	return {"h": h, "type": type, "tile": tile, "floor_h": fh, "sign": word, "sign_color": sign_color, "sign_style": sign_style, "blade": blade, "roof_seed": rng.randi(), "billboard": float(district.get("billboard", 1.0))}

static func _weighted_s(rng: RandomNumberGenerator, table: Array) -> String:
	var total := 0
	for e in table:
		total += int(e[1])
	var r := rng.randi() % total
	for e in table:
		r -= int(e[1])
		if r < 0:
			return String(e[0])
	return String(table[0][0])

static func _weighted(rng: RandomNumberGenerator, table: Array) -> int:
	var total := 0
	for e in table:
		total += int(e[1])
	var r := rng.randi() % total
	for e in table:
		r -= int(e[1])
		if r < 0:
			return int(e[0])
	return int(table[0][0])

# ---------- atlas ----------

## 8 tiles x 2 rows (upper floors on top, ground floor below), 32 px each.
static func atlas() -> ImageTexture:
	if _atlas == null:
		var img := Image.create(TILE_PX * TILES, TILE_PX * 2, false, Image.FORMAT_RGBA8)
		for t in TILES:
			for row in 2:
				_draw_tile(img, t, row == 1, t * TILE_PX, row * TILE_PX)
		img.generate_mipmaps()
		_atlas = ImageTexture.create_from_image(img)
	return _atlas

# Pixel helpers. Tile coordinates: x right, y DOWN (y = 0 is the ceiling line
# of the floor, y = 31 the floor line).
static func _rect(img: Image, ox: int, oy: int, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1):
		for x in range(x0, x1):
			img.set_pixel(ox + x, oy + y, c)

static func _wall(v: float) -> Color:
	return Color(v, v, v, 0.0)

static func _glass(v: float) -> Color:
	return Color(v, v, v, 1.0)

static func _draw_tile(img: Image, t: int, ground: bool, ox: int, oy: int) -> void:
	var n := TILE_PX
	# a little per-pixel grit on every wall so flat colour never shows
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + t * 2 + (1 if ground else 0)
	for y in n:
		for x in n:
			img.set_pixel(ox + x, oy + y, _wall(0.62 + rng.randf_range(-0.06, 0.06)))
	match t:
		T_APARTMENT:
			if ground:
				# entrance bay look: smaller windows, a darker plinth
				_rect(img, ox, oy, 0, 24, n, n, _wall(0.4))
				_rect(img, ox, oy, 10, 8, 22, 20, _glass(0.18))
			else:
				_rect(img, ox, oy, 8, 6, 24, 20, _glass(0.15))
				# balcony slab and railing under the window
				_rect(img, ox, oy, 4, 21, 28, 23, _wall(0.82))
				for x in range(5, 28, 3):
					_rect(img, ox, oy, x, 23, x + 1, 27, _wall(0.3))
				_rect(img, ox, oy, 4, 27, 28, 28, _wall(0.3))
		T_SHOP:
			if ground:
				# full-height glass with mullions and a dark sign-band strip
				_rect(img, ox, oy, 0, 0, n, 7, _wall(0.28))
				_rect(img, ox, oy, 1, 9, n - 1, 30, _glass(0.2))
				_rect(img, ox, oy, 15, 9, 17, 30, _wall(0.35))
			else:
				_brick(img, ox, oy, 0.62)
				_rect(img, ox, oy, 9, 7, 23, 22, _glass(0.15))
				_rect(img, ox, oy, 8, 22, 24, 24, _wall(0.8))
		T_OFFICE:
			# continuous ribbon window, thin mullions, dark spandrel
			_rect(img, ox, oy, 0, 0, n, n, _wall(0.45))
			var top := 4 if ground else 7
			_rect(img, ox, oy, 0, top, n, 25, _glass(0.14))
			for x in [0, 8, 16, 24]:
				_rect(img, ox, oy, x, top, x + 1, 25, _wall(0.55))
		T_WAREHOUSE:
			_ribs(img, ox, oy, 0.55)
			if ground:
				# roller door, slats as darker lines, no glass
				_rect(img, ox, oy, 6, 6, 26, n, _wall(0.5))
				for y in range(7, n, 2):
					_rect(img, ox, oy, 6, y, 26, y + 1, _wall(0.36))
				_rect(img, ox, oy, 5, 5, 27, 6, _wall(0.8))
				# light spilling under a door left a hand's width open
				_rect(img, ox, oy, 6, 30, 26, n, _glass(0.3))
			else:
				# high clerestory strip
				_rect(img, ox, oy, 2, 3, 30, 7, _glass(0.18))
		T_PARKING:
			# concrete spandrel over an open, unglazed slab: the "glass" is
			# the open deck, lit by cold tubes
			_rect(img, ox, oy, 0, 0, n, 9, _wall(0.7))
			_rect(img, ox, oy, 0, 9, n, n, _glass(0.06))
			_rect(img, ox, oy, 0, 9, 2, n, _wall(0.6))
			if ground:
				_rect(img, ox, oy, 0, 28, n, n, _wall(0.5))
		T_BRICK:
			_brick(img, ox, oy, 0.6)
			# tall narrow window with a stone lintel and sill
			_rect(img, ox, oy, 11, 6, 21, 25, _glass(0.14))
			_rect(img, ox, oy, 10, 4, 22, 6, _wall(0.85))
			_rect(img, ox, oy, 10, 25, 22, 27, _wall(0.85))
			if ground:
				_rect(img, ox, oy, 0, 28, n, n, _wall(0.35))
		T_CONCRETE:
			# precast panel joints and one square window per panel
			_rect(img, ox, oy, 0, 0, n, 1, _wall(0.38))
			_rect(img, ox, oy, 0, 0, 1, n, _wall(0.38))
			_rect(img, ox, oy, 8, 8, 24, 22, _glass(0.15))
			# rust streak below the window
			_rect(img, ox, oy, 15, 22, 17, 30, _wall(0.48))
			if ground:
				_rect(img, ox, oy, 0, 26, n, n, _wall(0.4))
		T_CORRUGATED:
			_ribs(img, ox, oy, 0.58)
			if ground:
				_rect(img, ox, oy, 4, 8, 14, n, _wall(0.4))  # side door
				_rect(img, ox, oy, 20, 12, 27, 18, _glass(0.18))
			else:
				_rect(img, ox, oy, 20, 10, 27, 16, _glass(0.18))

static func _brick(img: Image, ox: int, oy: int, v: float) -> void:
	for y in TILE_PX:
		var course := y / 3
		var shift := 3 if course % 2 == 1 else 0
		for x in TILE_PX:
			var mortar := y % 3 == 2 or (x + shift) % 6 == 5
			img.set_pixel(ox + x, oy + y, _wall(0.82 if mortar else v - 0.06 * float((x / 6 + course) % 3)))

static func _ribs(img: Image, ox: int, oy: int, v: float) -> void:
	for y in TILE_PX:
		for x in TILE_PX:
			var k := x % 4
			img.set_pixel(ox + x, oy + y, _wall(v + (0.12 if k == 0 else (-0.08 if k == 2 else 0.0))))
