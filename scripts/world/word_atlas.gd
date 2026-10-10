extends RefCounted

# The lettering for area signs, street blades and painted road words (world
# step 4). Each text in PlaceNames.atlas_words() becomes one layer of a
# Texture2DArray, drawn once, white on black, in the "road" font role
# (UiTheme.font("road"), Overpass). Arrows are shapes, not text, drawn into
# their own layers the same way.
#
# A layer is W x H px. The text sits on a fixed baseline, so every layer has
# the same letter height and one plate/decal formula works for all of them:
# the visible band is rows Y0 .. Y0 + BAND, the text starts PAD px in, and
# widths()[layer] is how wide the text is.
#
# Drawn with the TextServer straight into bytes (no SubViewport, no scene
# tree, no renderer), so it also works headless and costs a few ms at boot.

const PlaceNames := preload("res://scripts/world/place_names.gd")

const W := 512
const H := 64
const FONT_PX := 40
const BASELINE := 48
## The band of rows a plate or decal shows. Cap height at FONT_PX is about
## 29 px, so letters fill the lower two thirds of the band.
const Y0 := 14
const BAND := 42
## Blank columns either side of the text on a plate.
const PAD := 6

static var _tex: Texture2DArray
static var _words: Array = []
static var _widths := PackedFloat32Array()

## Layer of a text, -1 if it is not in the table.
static func layer(word: String) -> int:
	_ensure()
	return _words.find(word)

## Width in px of the text on a layer.
static func width_px(word: String) -> int:
	var l := layer(word)
	return int(_widths[l]) if l >= 0 else 0

static func layer_count() -> int:
	_ensure()
	return _words.size()

static func texture() -> Texture2DArray:
	_ensure()
	return _tex

## The layers as images (tests read pixels from here).
static var images: Array[Image] = []

static func _ensure() -> void:
	if _tex != null:
		return
	_words = PlaceNames.atlas_words()
	_widths.resize(_words.size())
	images.clear()
	var font := UiTheme.font("road")
	for i in _words.size():
		var word: String = _words[i]
		var data := PackedByteArray()
		data.resize(W * H)
		var w := 0
		if word.begins_with("#"):
			w = _draw_arrow(data, word)
		else:
			w = _draw_text(data, font, word)
		_widths[i] = float(w)
		var img := Image.create_from_data(W, H, false, Image.FORMAT_L8, data)
		img.generate_mipmaps()
		images.append(img)
	var arr := Texture2DArray.new()
	arr.create_from_images(images)
	_tex = arr

## Shapes `text` with the TextServer and blits each glyph's coverage into
## `data` (one byte per pixel). Returns the text's width in px.
static func _draw_text(data: PackedByteArray, font: Font, text: String) -> int:
	var ts := TextServerManager.get_primary_interface()
	var sh := ts.create_shaped_text()
	ts.shaped_text_add_string(sh, text, font.get_rids(), FONT_PX)
	ts.shaped_text_shape(sh)
	var pen := Vector2(float(PAD), float(BASELINE))
	var caches := {}  # texture index -> [PackedByteArray, width, bytes per px, has alpha]
	for g in ts.shaped_text_get_glyphs(sh):
		var frid: RID = g["font_rid"]
		var gi: int = g["index"]
		var size := Vector2i(int(g["font_size"]), 0)
		for r in int(g["repeat"]):
			var at := pen
			pen.x += float(g["advance"])
			if gi == 0:
				continue
			ts.font_render_glyph(frid, size, gi)
			var uv: Rect2 = ts.font_get_glyph_uv_rect(frid, size, gi)
			if uv.size.x <= 0.0 or uv.size.y <= 0.0:
				continue
			var ti: int = ts.font_get_glyph_texture_idx(frid, size, gi)
			var key := "%s_%d" % [frid, ti]
			if not caches.has(key):
				var src: Image = ts.font_get_texture_image(frid, size, ti)
				var bpp := 2 if src.get_format() == Image.FORMAT_LA8 else (4 if src.get_format() == Image.FORMAT_RGBA8 else 1)
				caches[key] = [src.get_data(), src.get_width(), bpp]
			var c: Array = caches[key]
			var src_data: PackedByteArray = c[0]
			var sw: int = c[1]
			var bpp: int = c[2]
			var chan := bpp - 1 if bpp > 1 else 0  # alpha is the last channel of LA8 / RGBA8
			var off: Vector2 = ts.font_get_glyph_offset(frid, size, gi)
			var dx := int(roundf(at.x + off.x))
			var dy := int(roundf(at.y + off.y))
			var ux := int(uv.position.x)
			var uy := int(uv.position.y)
			for y in int(uv.size.y):
				var py := dy + y
				if py < 0 or py >= H:
					continue
				for x in int(uv.size.x):
					var px := dx + x
					if px < 0 or px >= W:
						continue
					var v := src_data[((uy + y) * sw + ux + x) * bpp + chan]
					var o := py * W + px
					if v > data[o]:
						data[o] = v
	var size_x := ts.shaped_text_get_size(sh).x
	ts.free_rid(sh)
	return mini(int(ceilf(size_x)), W - 2 * PAD)

## Arrows: a stem and a head, drawn as filled shapes. The layer's text width
## is the arrow's width.
static func _draw_arrow(data: PackedByteArray, which: String) -> int:
	var aw := 36
	var top := Y0 + 1
	var bot := Y0 + BAND - 1
	var cx := PAD + aw / 2
	var polys: Array = []
	match which:
		"#LEFT", "#RIGHT":
			var s := 1.0 if which == "#RIGHT" else -1.0
			# stem up from the bottom, then a bend to the side with a head
			polys.append(PackedVector2Array([Vector2(cx - 4, bot), Vector2(cx + 4, bot), Vector2(cx + 4, top + 22), Vector2(cx - 4, top + 22)]))
			polys.append(PackedVector2Array([Vector2(cx - 4, top + 14), Vector2(cx + s * 12, top + 14), Vector2(cx + s * 12, top + 22), Vector2(cx - 4, top + 22)]))
			polys.append(PackedVector2Array([Vector2(cx + s * 10, top + 5), Vector2(cx + s * 18, top + 18), Vector2(cx + s * 10, top + 31)]))
		_:
			polys.append(PackedVector2Array([Vector2(cx - 4, bot), Vector2(cx + 4, bot), Vector2(cx + 4, top + 16), Vector2(cx - 4, top + 16)]))
			polys.append(PackedVector2Array([Vector2(cx, top), Vector2(cx + 16, top + 22), Vector2(cx - 16, top + 22)]))
	for p: PackedVector2Array in polys:
		_fill(data, p)
	return aw

static func _fill(data: PackedByteArray, poly: PackedVector2Array) -> void:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	for y in range(maxi(int(floorf(lo.y)), 0), mini(int(ceilf(hi.y)) + 1, H)):
		for x in range(maxi(int(floorf(lo.x)), 0), mini(int(ceilf(hi.x)) + 1, W)):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
				data[y * W + x] = 255
