class_name PageGraphic
extends Control

# Base for the drawn graphic on each Tuner page (Tuner UI overhaul PR 3): a
# picture of what the page's settings physically do, moving as you change them.
# Stock is drawn in steel blue (outline or dashes), yours in sodium. Each page's
# graphic is its own script and scene (scenes/tuner_kit/) so the Stage E garage
# can place it beside the part.
#
# show_setup(spec, stock, ctx) hands over two CarSpec dictionaries and a context:
#   preview : a spec one notch on from the focused setting (next-notch ghost), or {}
#   focus   : the focused setting's id ("" for none)
#   est, stock_est, preview_est : TunerModel.estimate() of each
#   auto_bias : the brake split GEVP works out when bias is on Auto
#   wheel_r : wheel radius in metres

var spec := {}
var stock := {}
var ctx := {}

func _init() -> void:
	custom_minimum_size = Vector2(280, 180)

func show_setup(s: Dictionary, st: Dictionary, c := {}) -> void:
	spec = s
	stock = st
	ctx = c
	queue_redraw()

## The graphic for a Tuner page, or null for a page that has none.
static func for_page(id: String) -> PageGraphic:
	match id:
		"tyres": return TyreGraphic.new()
		"suspension": return SpringGraphic.new()
		"gearbox": return GearboxGraphic.new()
		"engine": return DynoGraphic.new()
		"diff": return DiffGraphic.new()
		"brakes": return BrakeGraphic.new()
		"aero": return AeroGraphic.new()
		"assists": return AssistLights.new()
		"sound": return ExhaustGraphic.new()
	return null

func f(key: String, from: Dictionary = spec, fallback := 0.0) -> float:
	var v: Variant = from.get(key, fallback)
	return float(v) if v != null else fallback

func preview() -> Dictionary:
	return ctx.get("preview", {})

# ---------- drawing helpers ----------

func text(t: String, at: Vector2, sz := 13, col := TunerColours.LABEL, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(UiTheme.font("strong"), at, t, align, width, sz, col)

func mono(t: String, at: Vector2, sz := 12, col := TunerColours.VALUE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(UiTheme.font("mono"), at, t, align, width, sz, col)

func centred(t: String, at: Vector2, sz := 13, col := TunerColours.LABEL) -> void:
	var w := UiTheme.font("strong").get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(UiTheme.font("strong"), Vector2(at.x - w * 0.5, at.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

## A closed outline of points, solid or dashed.
func outline(pts: PackedVector2Array, col: Color, width := 2.0, dashed := false) -> void:
	if pts.size() < 2:
		return
	var closed := pts.duplicate()
	closed.append(pts[0])
	if not dashed:
		draw_polyline(closed, col, width, true)
		return
	for i in closed.size() - 1:
		var a := closed[i]
		var b := closed[i + 1]
		var n := maxi(int(a.distance_to(b) / 6.0), 1)
		for k in n:
			if k % 2 == 0:
				draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), col, width, true)

## An arrow from a to b with a head.
func arrow(a: Vector2, b: Vector2, col: Color, width := 3.0) -> void:
	if a.distance_to(b) < 2.0:
		return
	var d := (b - a).normalized()
	var head := minf(10.0, a.distance_to(b) * 0.5)
	draw_line(a, b - d * head * 0.6, col, width, true)
	draw_colored_polygon(PackedVector2Array([b, b - d * head + d.orthogonal() * head * 0.55, b - d * head - d.orthogonal() * head * 0.55]), col)

static func rect_pts(r: Rect2, rot := 0.0, pivot := Vector2.INF) -> PackedVector2Array:
	var c := r.get_center() if pivot == Vector2.INF else pivot
	var out := PackedVector2Array()
	for p in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		out.append(c + (Vector2(p) - c).rotated(rot))
	return out

## A small top-down car body (nose up) centred on c, w x h pixels.
static func car_pts(c: Vector2, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(-w * 0.36, -h * 0.5), c + Vector2(w * 0.36, -h * 0.5),
		c + Vector2(w * 0.5, -h * 0.3), c + Vector2(w * 0.5, h * 0.45), c + Vector2(w * 0.42, h * 0.5),
		c + Vector2(-w * 0.42, h * 0.5), c + Vector2(-w * 0.5, h * 0.45), c + Vector2(-w * 0.5, -h * 0.3)])
