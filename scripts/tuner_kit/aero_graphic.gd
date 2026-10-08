class_name AeroGraphic
extends PageGraphic

# Aero page: the car's side silhouette with a downforce arrow over each axle,
# sized by that axle's wing, and a drag arrow behind. Stock arrows are steel-blue
# outlines beside yours.

func _draw() -> void:
	if spec.is_empty():
		return
	var w := size.x
	var h := size.y
	var ground := h * 0.78
	text("DOWNFORCE AND DRAG AT SPEED", Vector2(6, 14))
	var x0 := w * 0.16
	var x1 := w * 0.74
	var body := PackedVector2Array([Vector2(x0, ground - 12), Vector2(x1, ground - 12), Vector2(x1, ground - 34),
		Vector2(x1 - 30, ground - 40), Vector2(lerpf(x0, x1, 0.62), ground - 66), Vector2(lerpf(x0, x1, 0.3), ground - 66),
		Vector2(x0 + 40, ground - 40), Vector2(x0, ground - 32)])
	draw_colored_polygon(body, TunerColours.PLOT)
	outline(body, TunerColours.DIM, 1.5)
	for x in [lerpf(x0, x1, 0.18), lerpf(x0, x1, 0.82)]:
		draw_circle(Vector2(x, ground - 10), 12.0, TunerColours.PANEL)
		draw_arc(Vector2(x, ground - 10), 12.0, 0, TAU, 20, TunerColours.DIM, 1.5)
	# a rear wing drawn on as it grows
	var rw := f("aero_downforce_coefficient_rear")
	if rw > 0.05:
		draw_line(Vector2(x1 - 34, ground - 44 - rw * 14), Vector2(x1 - 4, ground - 44 - rw * 14), TunerColours.YOURS, 3.0)
		draw_line(Vector2(x1 - 20, ground - 40), Vector2(x1 - 20, ground - 44 - rw * 14), TunerColours.DIM, 2.0)
	for axle in [{"x": lerpf(x0, x1, 0.18), "k": "aero_downforce_coefficient_front"}, {"x": lerpf(x0, x1, 0.82), "k": "aero_downforce_coefficient_rear"}]:
		var top := ground - 74.0
		var len_s := 10.0 + 70.0 * f(axle.k, stock)
		var len_y := 10.0 + 70.0 * f(axle.k)
		draw_line(Vector2(axle.x + 9, top - len_s), Vector2(axle.x + 9, top), TunerColours.STOCK, 1.5)
		arrow(Vector2(axle.x, top - len_y), Vector2(axle.x, top), TunerColours.YOURS, 4.0)
	# drag pulls back from the tail
	var dl := (f("coefficient_of_drag") - 0.2) * 300.0 + 10.0
	var dls := (f("coefficient_of_drag", stock) - 0.2) * 300.0 + 10.0
	var y := ground - 30.0
	draw_line(Vector2(x1 + 6, y + 8), Vector2(x1 + 6 + dls, y + 8), TunerColours.STOCK, 1.5)
	arrow(Vector2(x1 + 6, y), Vector2(x1 + 6 + dl, y), TunerColours.VALUE, 3.0)
	text("drag", Vector2(x1 + 8, y - 8), 12, TunerColours.DIM)
	mono("Cd %.2f" % f("coefficient_of_drag"), Vector2(6, h - 6))
