class_name UiTheme
extends RefCounted

# Menu theme (UI blend PR 1, docs/planning/ui-direction-blend-2026-10-07.md).
# Materials from the shop floor (plates, floor tape), motion from the street
# (12 degree slabs for the selected row), numbers loud. Palette is Amber vs. Dusk:
# sodium marks the selection, amber carries values, red is live danger only.

const SODIUM := Color("#FF8A1F")
const AMBER := Color("#FFC066")
const RED := Color("#E5262B")
const SILVER := Color("#C9CED6")
const NAVY := Color("#1B2A4A")
const DUSK := Color("#0E1424")
const DIM := Color("#7C8598")

const SLAB_SKEW := 0.21   # tan(12 degrees)

static var _theme: Theme
static var _fonts := {}

static func font(kind: String) -> Font:
	if not _fonts.has(kind):
		_fonts[kind] = _make_font(kind)
	return _fonts[kind]

static func _make_font(kind: String) -> Font:
	match kind:
		"display":   # Big Shoulders Display, heavy: titles and big numbers
			var v := FontVariation.new()
			v.base_font = load("res://assets/fonts/BigShouldersDisplay.ttf")
			v.variation_opentype = {"wght": 800}
			return v
		"mono":      # Share Tech Mono: values, deltas, key names
			return load("res://assets/fonts/ShareTechMono-Regular.ttf")
		"strong":    # Barlow Semi Condensed SemiBold: buttons, tabs
			return load("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf")
	return load("res://assets/fonts/BarlowSemiCondensed-Regular.ttf")  # "body"

static func box(bg: Color, border := Color(0, 0, 0, 0), border_w := 0, skew := 0.0, pad := Vector2(14, 6)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(border_w)
	s.border_color = border
	s.skew = Vector2(-skew, 0.0)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	return s

## The shared Theme. Built once; assign it to the root Control of a menu.
static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme

static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = 18

	t.set_font("font", "Label", font("body"))
	t.set_color("font_color", "Label", SILVER)

	# Buttons: dark plate; the focused/hovered one becomes a sodium slab.
	var plate := box(DUSK, NAVY, 2)
	var slab := box(SODIUM, SODIUM, 2, SLAB_SKEW, Vector2(18, 6))
	t.set_font("font", "Button", font("strong"))
	t.set_font_size("font_size", "Button", 20)
	t.set_stylebox("normal", "Button", plate)
	t.set_stylebox("hover", "Button", slab)
	t.set_stylebox("focus", "Button", slab)
	t.set_stylebox("pressed", "Button", box(AMBER, AMBER, 2, SLAB_SKEW, Vector2(18, 6)))
	t.set_color("font_color", "Button", SILVER)
	for c in ["font_hover_color", "font_focus_color", "font_pressed_color"]:
		t.set_color(c, "Button", DUSK)

	# Sliders: a thin silver rail, amber fill, sodium grabber while focused.
	var rail := box(NAVY, Color(0, 0, 0, 0), 0, 0.0, Vector2(0, 3))
	rail.content_margin_top = 3
	rail.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", rail)
	t.set_stylebox("grabber_area", "HSlider", box(AMBER, Color(0, 0, 0, 0), 0, 0.0, Vector2(0, 3)))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(SODIUM, Color(0, 0, 0, 0), 0, 0.0, Vector2(0, 3)))
	var grab := _grabber(SILVER)
	var grab_hi := _grabber(SODIUM)
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab_hi)
	t.set_icon("grabber_disabled", "HSlider", grab)

	# Tabs: label tape. The selected tab is a sodium slab, the rest are navy tape.
	t.set_font("font_selected", "TabContainer", font("strong"))
	t.set_font("font_unselected", "TabContainer", font("strong"))
	t.set_font("font_hovered", "TabContainer", font("strong"))
	t.set_font_size("font_size", "TabContainer", 20)
	t.set_color("font_selected_color", "TabContainer", DUSK)
	t.set_color("font_unselected_color", "TabContainer", SILVER)
	t.set_color("font_hovered_color", "TabContainer", SODIUM)
	t.set_stylebox("tab_selected", "TabContainer", box(SODIUM, SODIUM, 2, SLAB_SKEW, Vector2(22, 6)))
	t.set_stylebox("tab_focus", "TabContainer", box(SODIUM, AMBER, 2, SLAB_SKEW, Vector2(22, 6)))
	t.set_stylebox("tab_unselected", "TabContainer", box(NAVY, NAVY, 2, SLAB_SKEW, Vector2(22, 6)))
	t.set_stylebox("tab_hovered", "TabContainer", box(NAVY, SODIUM, 2, SLAB_SKEW, Vector2(22, 6)))
	t.set_stylebox("panel", "TabContainer", box(Color(DUSK, 0.0), Color(0, 0, 0, 0), 0, 0.0, Vector2(0, 8)))

	t.set_stylebox("panel", "PanelContainer", plate_panel())
	return t

static func _grabber(c: Color) -> Texture2D:
	var img := Image.create(10, 22, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)

## A work plate: dusk fill, navy edge, sodium floor tape along the top.
static func plate_panel() -> StyleBoxFlat:
	var s := box(Color(DUSK, 0.94), NAVY, 2, 0.0, Vector2(28, 20))
	s.border_width_top = 6
	s.border_color = NAVY
	return s

## Display-font label with a size and colour, for titles and big numbers.
static func title_label(text: String, size := 54, colour := SODIUM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font("display"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l

## A thin amber floor-tape rule between groups of rows.
static func floor_tape() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(AMBER, 0.55)
	r.custom_minimum_size = Vector2(0, 2)
	return r
