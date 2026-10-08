class_name RadarChart
extends Control

# A five-point radar for the performance card (Tuner UI overhaul PR 2): one
# spoke per stat, 0 at the centre and 1 at the rim. Stock is a steel-blue
# outline, yours a sodium fill with a solid edge. Standalone
# (scenes/tuner_kit/radar_chart.tscn).

var axes: Array[String] = ["Top speed", "Accel", "Braking", "Grip", "Handling"]
var stock: Array[float] = [0.5, 0.5, 0.5, 0.5, 0.5]
var now: Array[float] = [0.5, 0.5, 0.5, 0.5, 0.5]

func _init() -> void:
	custom_minimum_size = Vector2(220, 190)

func set_values(stock_values: Array, now_values: Array) -> void:
	stock.assign(stock_values.map(func(v): return clampf(float(v), 0.0, 1.0)))
	now.assign(now_values.map(func(v): return clampf(float(v), 0.0, 1.0)))
	queue_redraw()

func _spoke(i: int) -> Vector2:
	var a := -PI * 0.5 + TAU * i / axes.size()
	return Vector2(cos(a), sin(a))

func _draw() -> void:
	var n := axes.size()
	var c := size * 0.5 + Vector2(0.0, 6.0)
	var r := minf(size.x * 0.5 - 34.0, size.y * 0.5 - 22.0)
	if r < 10.0 or n < 3:
		return
	for ring in [0.25, 0.5, 0.75, 1.0]:
		var pts := PackedVector2Array()
		for i in n + 1:
			pts.append(c + _spoke(i % n) * r * ring)
		draw_polyline(pts, Color(TunerColours.DIM, 0.3 if ring < 1.0 else 0.6), 1.0, true)
	for i in n:
		draw_line(c, c + _spoke(i) * r, Color(TunerColours.DIM, 0.3), 1.0)
	var mine := PackedVector2Array()
	var base := PackedVector2Array()
	for i in n:
		mine.append(c + _spoke(i) * r * maxf(now[i], 0.03))
		base.append(c + _spoke(i) * r * maxf(stock[i], 0.03))
	draw_colored_polygon(mine, Color(TunerColours.YOURS, 0.28))
	mine.append(mine[0])
	draw_polyline(mine, TunerColours.YOURS, 2.0, true)
	base.append(base[0])
	draw_polyline(base, TunerColours.STOCK, 1.5, true)
	var font := UiTheme.font("strong")
	for i in n:
		var d := _spoke(i)
		var p := c + d * (r + 12.0)
		var w := font.get_string_size(axes[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var x := p.x - w * 0.5 + d.x * w * 0.45
		draw_string(font, Vector2(x, p.y + 5.0 + (d.y * 4.0)), axes[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TunerColours.LABEL)
