extends RefCounted

# Shop and garage signs (buildings step 2, 2026-10-07).
#
# A sign is a thin lightbox (a scaled unit cube, 12 tris) on the building
# front, drawn from ONE MultiMesh per chunk with one material, so a whole
# street of signs is one draw call. Per-instance custom data picks the word,
# its colour and its style (lit letters on a dark panel, or a lit panel with
# dark letters). A sign is either a band flat on the shopfront, or a blade
# sticking out from the wall so it reads to oncoming traffic; both big faces
# carry the word, the edges are dark sheet metal.
#
# Words are original and generic (no brands), drawn into a small atlas in
# code with a 5x7 pixel font for the PS2 look. Colours stay in Amber vs
# Dusk: sodium amber, warm white, cold green-white fluorescent, one dusk
# blue. No magenta, no cyan.

const ROWS := 16
const ROW_PX := 9
const ATLAS_W := 64
const GLYPH_W := 6  # 5 px glyph + 1 px spacing

# Word lists by building type. DINER is kept back for the diner itself.
const SHOP_WORDS := ["LIQUOR", "PAWN", "LAUNDRY", "NOODLES", "VIDEO", "BAR", "CAFE", "OPEN", "24 HR", "KEYS"]
const GARAGE_WORDS := ["TIRES", "PARTS", "AUTO", "BODY"]
const SPECIAL_WORDS := ["DINER"]
const COLORS := [
	Color(1.0, 0.6, 0.2),     # sodium amber
	Color(0.95, 0.9, 0.8),    # warm white
	Color(0.62, 0.95, 0.58),  # cold fluorescent green-white
	Color(0.36, 0.46, 1.0),   # dusk blue
]
const ENERGY := 1.5  # above the 1.0 glow threshold: signs bloom, facades do not

const FONT := {
	"A": [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
	"B": ["#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### "],
	"C": [" ####", "#    ", "#    ", "#    ", "#    ", "#    ", " ####"],
	"D": ["#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "],
	"E": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"],
	"F": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "],
	"H": ["#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
	"I": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "#####"],
	"K": ["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"],
	"L": ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"],
	"N": ["#   #", "##  #", "# # #", "#  ##", "#   #", "#   #", "#   #"],
	"O": [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
	"P": ["#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "],
	"Q": [" ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #"],
	"R": ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"],
	"S": [" ####", "#    ", "#    ", " ### ", "    #", "    #", "#### "],
	"T": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "],
	"U": ["#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
	"V": ["#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  "],
	"W": ["#   #", "#   #", "#   #", "# # #", "# # #", "## ##", "#   #"],
	"Y": ["#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  "],
	"2": [" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"],
	"4": ["#   #", "#   #", "#   #", "#####", "    #", "    #", "    #"],
}

const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D words : source_color, filter_nearest_mipmap, repeat_disable;
uniform vec3 colors[4];
uniform float energy = 1.5;
uniform float rows = 16.0;
uniform float atlas_w = 64.0;

varying vec3 lpos;
varying vec3 lnrm;
varying vec4 cd;

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
	cd = INSTANCE_CUSTOM;  // x: word row, y: word width px, z: colour, w: style
}

void fragment() {
	vec3 metal = vec3(0.05, 0.05, 0.055);
	ALBEDO = metal;
	ROUGHNESS = 0.7;
	if (abs(lnrm.x) > 0.5) {
		// the two big faces; local -x is the front (the instance is turned
		// to face the road, or the traffic for a blade), +x the mirrored back
		float u = lnrm.x < 0.0 ? lpos.z + 0.5 : 0.5 - lpos.z;
		float v = 0.5 - lpos.y;  // 0 at the top
		float pad = 2.0;
		float px = mix(-pad, cd.y + pad, u);
		float py = mix(0.0, 9.0, v);
		float inside = step(0.0, px) * step(px, cd.y);
		vec2 auv = vec2(clamp(px, 0.0, cd.y - 0.01) / atlas_w, (cd.x * 9.0 + py) / (rows * 9.0));
		float glyph = texture(words, auv).r * inside;
		vec3 col = colors[int(cd.z)];
		float lit = cd.w < 0.5 ? glyph : (1.0 - glyph) * 0.75;
		ALBEDO = mix(metal, col * 0.3, lit);
		EMISSION = col * lit * energy;
	}
}
"""

static var _material: ShaderMaterial
static var _atlas: ImageTexture
static var _box: BoxMesh

static func words() -> Array:
	return SHOP_WORDS + GARAGE_WORDS + SPECIAL_WORDS

static func word_row(word: String) -> int:
	return words().find(word)

static func word_px(word: String) -> int:
	return word.length() * GLYPH_W - 1

static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
		_material.set_shader_parameter("words", atlas())
		var cols := PackedVector3Array()
		for c in COLORS:
			cols.append(Vector3(c.r, c.g, c.b))
		_material.set_shader_parameter("colors", cols)
		_material.set_shader_parameter("energy", ENERGY)
		_material.set_shader_parameter("rows", float(ROWS))
		_material.set_shader_parameter("atlas_w", float(ATLAS_W))
	return _material

static func box() -> BoxMesh:
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
	return _box

## One MultiMesh of signs per chunk, capacity allocated once.
static func new_multimesh(capacity: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = box()
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Signs"
	mmi.multimesh = mm
	mmi.material_override = material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

## Writes sign slot i: a lightbox `height` tall, as long as the word needs
## (capped at max_len). front is the point on the building front it hangs
## from; side is +1 for buildings on the +x side of the road, -1 for the
## other. A band lies flat on the front facing the road; a blade sticks out
## from it toward the road, facing the oncoming traffic.
static func place(mm: MultiMesh, i: int, word: String, color: int, style: int, front: Vector3, side: int, height: float, max_len: float, blade: bool = false) -> void:
	var px := word_px(word)
	var length := minf(max_len, height * float(px + 4) / float(ROW_PX))
	var depth := 0.18
	var turn: Basis
	var center := front
	if blade:
		turn = Basis(Vector3.UP, PI / 2.0)
		center.x -= (length / 2.0 + 0.1) * float(side)
	else:
		turn = Basis() if side == 1 else Basis(Vector3.UP, PI)
		center.x -= (depth / 2.0 + 0.01) * float(side)
	var basis := turn * Basis.from_scale(Vector3(depth, height, length))
	mm.set_instance_transform(i, Transform3D(basis, center))
	mm.set_instance_custom_data(i, Color(float(word_row(word)), float(px), float(color), float(style)))

static func atlas() -> ImageTexture:
	if _atlas == null:
		var img := Image.create(ATLAS_W, ROWS * ROW_PX, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 1))
		var list := words()
		for r in list.size():
			var word: String = list[r]
			for k in word.length():
				var g: Array = FONT.get(word[k], [])
				for gy in g.size():
					var line: String = g[gy]
					for gx in line.length():
						if line[gx] == "#":
							img.set_pixel(k * GLYPH_W + gx, r * ROW_PX + 1 + gy, Color(1, 1, 1, 1))
		img.generate_mipmaps()
		_atlas = ImageTexture.create_from_image(img)
	return _atlas
