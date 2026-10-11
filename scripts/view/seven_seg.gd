class_name SevenSeg
extends RefCounted

# Seven-segment digits for the cockpit's glowing displays (wheel screen, dial
# gear window). Pure data: which segments a character lights, and where each
# of the 7 sits in a digit's own plane. The users put the segments in a
# MultiMesh (instance colour alpha = lit) so a whole display is no extra draw call.
#
# Segment order is the usual a..g: top, upper right, lower right, bottom,
# lower left, upper left, middle.

const SEG_COUNT := 7
## Unlit segments stay faintly visible, like a real LCD (share of full glow).
const UNLIT_ALPHA := 0.08

const A := 1
const B := 2
const C := 4
const D := 8
const E := 16
const F := 32
const G := 64

const MASKS := {
	"0": A | B | C | D | E | F,
	"1": B | C,
	"2": A | B | D | E | G,
	"3": A | B | C | D | G,
	"4": B | C | F | G,
	"5": A | C | D | F | G,
	"6": A | C | D | E | F | G,
	"7": A | B | C,
	"8": A | B | C | D | E | F | G,
	"9": A | B | C | D | F | G,
	"r": E | G,
	"n": C | E | G,
	" ": 0,
}

## Segment bit mask for a one-character string (blank for anything unknown).
static func mask_for(ch: String) -> int:
	return int(MASKS.get(ch, 0))

## The gear a display shows: r reverse, n neutral, 1-9 (clamped).
static func gear_char(gear: int) -> String:
	if gear < 0:
		return "r"
	if gear == 0:
		return "n"
	return str(mini(gear, 9))

## Speed as three characters, right aligned, no leading zeros, max 999.
static func speed_chars(kmh: int) -> String:
	return "%3d" % clampi(kmh, 0, 999)

## Where the 7 segments sit in a digit w x h with stroke t, centred on the
## origin of its plane (x right, y up): an Array of 7 Rect2 (centre in
## .position, full size in .size), a..g. Corners keep a small gap.
static func segment_rects(w: float, h: float, t: float) -> Array:
	var gap := t * 0.15
	var hl := w - t - 2.0 * gap                 # horizontal segment length
	var vl := h * 0.5 - 1.5 * t - 2.0 * gap     # vertical segment length
	var xs := w * 0.5 - t * 0.5
	var ys := h * 0.5 - t * 0.5
	var vy := h * 0.25 - t * 0.25
	return [
		Rect2(Vector2(0.0, ys), Vector2(hl, t)),        # a
		Rect2(Vector2(xs, vy), Vector2(t, vl)),         # b
		Rect2(Vector2(xs, -vy), Vector2(t, vl)),        # c
		Rect2(Vector2(0.0, -ys), Vector2(hl, t)),       # d
		Rect2(Vector2(-xs, -vy), Vector2(t, vl)),       # e
		Rect2(Vector2(-xs, vy), Vector2(t, vl)),        # f
		Rect2(Vector2(0.0, 0.0), Vector2(hl, t)),       # g
	]

## Instance colour for a segment: glow colour at alpha 1 lit, faint when not.
static func colour(glow: Color, lit: bool) -> Color:
	return Color(glow.r, glow.g, glow.b, 1.0 if lit else UNLIT_ALPHA)
