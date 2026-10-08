class_name CurvePlot
extends Control

# A small line chart for the Tuner's graphics (Tuner UI overhaul PR 2): dyno
# curves, the gearing chart. Each series is data points with a colour; a
# `stock` series is drawn dashed in steel blue under yours in sodium. Axes run
# x_min..x_max and y_min..y_max; grid lines every x_step / y_step with their
# numbers. Standalone (scenes/tuner_kit/curve_plot.tscn) for the garage too.

## [{points: PackedVector2Array (data units), colour: Color, width: float,
##   dashed: bool, label: String}]
var series: Array = []
## Vertical markers: [{x: float, colour: Color, label: String}]
var markers: Array = []
var x_min := 0.0
var x_max := 1.0
var y_min := 0.0
var y_max := 1.0
var x_step := 0.0
var y_step := 0.0
var x_unit := ""
var y_unit := ""
var title := ""

const PAD_L := 34.0
const PAD_B := 18.0
const PAD_T := 20.0
const PAD_R := 8.0

func _init() -> void:
	custom_minimum_size = Vector2(240, 140)

func clear() -> void:
	series = []
	markers = []

func add_series(points: PackedVector2Array, colour: Color, width := 2.0, dashed := false, label := "") -> void:
	series.append({"points": points, "colour": colour, "width": width, "dashed": dashed, "label": label})

func plot_rect() -> Rect2:
	return Rect2(PAD_L, PAD_T if title != "" else 6.0, size.x - PAD_L - PAD_R, size.y - PAD_B - (PAD_T if title != "" else 6.0))

func to_px(p: Vector2) -> Vector2:
	var r := plot_rect()
	var tx := inverse_lerp(x_min, x_max, p.x) if x_max != x_min else 0.0
	var ty := inverse_lerp(y_min, y_max, p.y) if y_max != y_min else 0.0
	return Vector2(r.position.x + tx * r.size.x, r.end.y - ty * r.size.y)

func _draw() -> void:
	var r := plot_rect()
	if r.size.x < 10.0 or r.size.y < 10.0:
		return
	var mono := UiTheme.font("mono")
	var font := UiTheme.font("strong")
	if title != "":
		draw_string(font, Vector2(0.0, 14.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TunerColours.LABEL)
	draw_rect(r, Color(TunerColours.PLOT, 0.6))
	if y_step > 0.0:
		var y := ceilf(y_min / y_step) * y_step
		while y <= y_max + 0.0001:
			var a := to_px(Vector2(x_min, y))
			draw_line(a, Vector2(r.end.x, a.y), Color(TunerColours.DIM, 0.35), 1.0)
			draw_string(mono, Vector2(0.0, a.y + 4.0), _num(y), HORIZONTAL_ALIGNMENT_RIGHT, PAD_L - 4.0, 11, TunerColours.DIM)
			y += y_step
	if x_step > 0.0:
		var x := ceilf(x_min / x_step) * x_step
		while x <= x_max + 0.0001:
			var a := to_px(Vector2(x, y_min))
			draw_line(a, Vector2(a.x, r.position.y), Color(TunerColours.DIM, 0.2), 1.0)
			draw_string(mono, Vector2(a.x - 20.0, size.y - 3.0), _num(x), HORIZONTAL_ALIGNMENT_CENTER, 40.0, 11, TunerColours.DIM)
			x += x_step
	if y_unit != "":
		draw_string(mono, Vector2(r.position.x + 3.0, r.position.y + 11.0), y_unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TunerColours.DIM)
	if x_unit != "":
		draw_string(mono, Vector2(r.end.x - 60.0, r.end.y - 4.0), x_unit, HORIZONTAL_ALIGNMENT_RIGHT, 58.0, 11, TunerColours.DIM)
	for s in series:
		var pts := PackedVector2Array()
		for p in s.points:
			pts.append(to_px(p).clamp(r.position, r.end))
		if pts.size() < 2:
			continue
		if s.dashed:
			for i in pts.size() - 1:
				if i % 2 == 0:
					draw_line(pts[i], pts[i + 1], s.colour, s.width, true)
		else:
			draw_polyline(pts, s.colour, s.width, true)
	for m in markers:
		var a := to_px(Vector2(m.x, y_min))
		if a.x < r.position.x or a.x > r.end.x:
			continue
		draw_line(a, Vector2(a.x, r.position.y), m.colour, 1.5)
		if m.get("label", "") != "":
			var w := mono.get_string_size(m.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(mono, Vector2(clampf(a.x - w - 3.0, r.position.x, r.end.x - w), r.position.y + 11.0), m.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, m.colour)

static func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.001:
		return str(roundi(v))
	return "%.1f" % v
