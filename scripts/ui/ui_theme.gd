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
static var _font_theme: Theme
static var _fonts := {}

const FONT_DIR := "res://assets/fonts/"
const WGHT := 2003265652   # OpenType axis tag "wght" (TextServer.name_to_tag is not static)

## Every text in the game takes one of these roles. All fonts are SIL OFL
## (docs/font-licences.md). Shop signs and billboards use the 5x7 pixel font in
## building_signs.gd, which is a bitmap table and not a Font, so it has no role.
const ROLES := [
	"logo",         # BOOST SIMCADE wordmark (Barlow Condensed)
	"display",      # screen titles, big HUD speed, slot headers (Big Shoulders Display)
	"menu",         # menu rows, tabs, Settings rows, loading tip (Barlow Semi Condensed)
	"menu_strong",  # buttons, tabs, summary rows (Barlow Semi Condensed SemiBold)
	"numbers",      # tuner values, deltas, cash, key names, benchmark (Share Tech Mono)
	"lcd",          # head-unit clock, wheel LCD, AFR/boost pod (DSEG7 Classic)
	"dial",         # analogue gauge numbers, dash lamp labels (Barlow Semi Condensed)
	"subtitle",     # Dale, scanner, people talking (SemiBold, dark outline)
	"tv",           # Graveyard TV text, scanner ticker (VT323)
	"hand",         # Walt's notes, whiteboard (Caveat)
	"road",         # road and area signs (Overpass)
	"plate",        # number plates (Share Tech Mono for now)
]

## Older call sites used four names; they stay valid.
const ALIASES := {"body": "menu", "strong": "menu_strong", "mono": "numbers"}

static func font(role: String) -> Font:
	role = ALIASES.get(role, role)
	if not _fonts.has(role):
		_fonts[role] = _make_font(role)
	return _fonts[role]

static func _load(file: String) -> Font:
	return load(FONT_DIR + file) as Font

static func _make_font(role: String) -> Font:
	match role:
		"logo":
			return _load("BarlowCondensed-SemiBold.ttf")
		"display":
			var v := FontVariation.new()
			v.base_font = _load("BigShouldersDisplay.ttf")
			v.variation_opentype = {WGHT: 800}
			return v
		"menu_strong", "subtitle":
			return _load("BarlowSemiCondensed-SemiBold.ttf")
		"numbers", "plate":
			return _load("ShareTechMono-Regular.ttf")
		"lcd":
			return _load("DSEG7Classic-Regular.ttf")
		"tv":
			return _load("VT323-Regular.ttf")
		"hand":
			var h := FontVariation.new()
			h.base_font = _load("Caveat.ttf")
			h.variation_opentype = {WGHT: 600}
			return h
		"road":
			var r := FontVariation.new()
			r.base_font = _load("Overpass.ttf")
			r.variation_opentype = {WGHT: 700}
			return r
	return _load("BarlowSemiCondensed-Regular.ttf")  # "menu", "dial"

## Set a control's font to a role (and optionally its size).
static func apply(c: Control, role: String, size := 0) -> void:
	c.add_theme_font_override("font", font(role))
	if size > 0:
		c.add_theme_font_size_override("font_size", size)

## Subtitle look: SemiBold, dark outline. The speaker name goes in AMBER.
static func subtitle(l: Label, size := 22) -> void:
	apply(l, "subtitle", size)
	l.add_theme_color_override("font_outline_color", DUSK)
	l.add_theme_constant_override("outline_size", 4)

## Fonts only (no boxes or colours): assign to the root Control of a screen so
## every Label, Button, CheckBox, OptionButton and tab inside takes a role font.
static func font_theme() -> Theme:
	if _font_theme == null:
		var t := Theme.new()
		t.default_font = font("menu")
		for cls in ["Label", "LineEdit", "RichTextLabel", "ItemList", "PopupMenu"]:
			t.set_font("font", cls, font("menu"))
		for cls in ["Button", "CheckBox", "CheckButton", "OptionButton", "MenuButton", "LinkButton"]:
			t.set_font("font", cls, font("menu_strong"))
		for n in ["font_selected", "font_unselected", "font_hovered"]:
			t.set_font(n, "TabContainer", font("menu_strong"))
		_font_theme = t
	return _font_theme

## The shared Theme. Built once; assign it to the root Control of a menu.
static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme

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
