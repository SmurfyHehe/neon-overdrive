class_name RaceHud
extends CanvasLayer

# Race readout (RC1; Roy 2026-10-09: "gap number on screen: yes"). Top centre,
# under the rear strip: the gap to the rival in metres (+ you lead, - you
# trail) and the distance left to the line. After the finish, a short result
# caption in the middle of the screen. No key hints (Decisions). RC3 owns the
# final look of the readout; this is the plain version. Reads a RaceSession
# and owns no state.

const GAP_TOP := 120.0
const CAPTION_Y := 0.3   # share of the window height

var race: RaceSession
var lbl_gap: Label
var lbl_to_go: Label
var lbl_caption: Label

func _init(p_race: RaceSession) -> void:
	race = p_race

func _ready() -> void:
	layer = 5
	lbl_gap = _label(30, Hud.AMBER)
	lbl_gap.anchor_left = 0.5
	lbl_gap.anchor_right = 0.5
	lbl_gap.offset_left = -150
	lbl_gap.offset_right = 150
	lbl_gap.offset_top = GAP_TOP
	lbl_to_go = _label(16, Hud.SILVER)
	lbl_to_go.anchor_left = 0.5
	lbl_to_go.anchor_right = 0.5
	lbl_to_go.offset_left = -150
	lbl_to_go.offset_right = 150
	lbl_to_go.offset_top = GAP_TOP + 40.0
	lbl_caption = _label(40, Hud.AMBER)
	lbl_caption.anchor_left = 0.0
	lbl_caption.anchor_right = 1.0
	lbl_caption.anchor_top = CAPTION_Y
	lbl_caption.anchor_bottom = CAPTION_Y
	_refresh()

func _label(font_size: int, colour: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Hud.DUSK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	var racing := race.is_racing()
	lbl_gap.visible = racing
	lbl_to_go.visible = racing
	if racing:
		lbl_gap.text = gap_text(race.gap())
		lbl_gap.add_theme_color_override("font_color", Hud.AMBER if race.gap() >= 0.0 else Hud.SODIUM)
		lbl_to_go.text = to_go_text(race.to_go())
	lbl_caption.visible = race.caption != ""
	lbl_caption.text = race.caption

## "+42 m" leading, "-17 m" trailing.
static func gap_text(g: float) -> String:
	var m := int(roundf(g))
	return ("+%d m" if m >= 0 else "%d m") % m

## "1.25 km to go" from a kilometre up, "350 m to go" below.
static func to_go_text(m: float) -> String:
	if m >= 1000.0:
		return "%.2f km to go" % (m / 1000.0)
	return "%d m to go" % int(ceilf(m))
