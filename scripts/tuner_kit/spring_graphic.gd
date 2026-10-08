class_name SpringGraphic
extends PageGraphic

# Suspension page: the car's side outline over drawn coil springs that compress
# and thicken as they stiffen, the ride-height gap in centimetres at each axle,
# and a front view that leans less in a corner with stiffer anti-roll bars.

func _draw() -> void:
	if spec.is_empty():
		return
	var w := size.x
	var h := size.y
	var ground := h * 0.62
	text("SPRINGS AND RIDE HEIGHT", Vector2(6, 14))
	draw_line(Vector2(6, ground), Vector2(w * 0.68, ground), TunerColours.DIM, 2.0)
	var axles := [{"x": w * 0.17, "p": "front"}, {"x": w * 0.53, "p": "rear"}]
	var body_y := []
	for a in axles:
		var ride := f(a.p + "_spring_length")
		var ride_s := f(a.p + "_spring_length", stock)
		var top := ground - 22.0 - ride * 170.0  # body underside over this axle
		body_y.append(top)
		# wheel
		draw_circle(Vector2(a.x, ground - 20.0), 20.0, TunerColours.PLOT)
		draw_arc(Vector2(a.x, ground - 20.0), 20.0, 0, TAU, 24, TunerColours.DIM, 1.5)
		# stock body line as dashes, then your coil
		draw_line(Vector2(a.x - 26, ground - 22.0 - ride_s * 170.0), Vector2(a.x + 26, ground - 22.0 - ride_s * 170.0), TunerColours.STOCK, 1.5)
		_coil(Vector2(a.x, ground - 20.0), top, f(a.p + "_resting_ratio"), TunerColours.YOURS)
		mono("%d cm" % roundi(ride * 100.0), Vector2(a.x - 18, ground + 16))
	# body side outline across the two axles
	var fx: float = axles[0].x
	var rx: float = axles[1].x
	var fy: float = body_y[0]
	var ry: float = body_y[1]
	var body := PackedVector2Array([Vector2(fx - 34, fy), Vector2(rx + 34, ry), Vector2(rx + 34, ry - 22),
		Vector2(rx - 6, ry - 30), Vector2(lerpf(fx, rx, 0.62), lerpf(fy, ry, 0.62) - 52), Vector2(lerpf(fx, rx, 0.28), lerpf(fy, ry, 0.28) - 52),
		Vector2(fx + 6, fy - 26), Vector2(fx - 34, fy - 18)])
	outline(body, TunerColours.YOURS, 2.0)
	# --- roll, front view (right): the body leans less with stiffer bars
	var rc := Vector2(w * 0.84, ground - 40.0)
	text("ROLL", Vector2(w * 0.74, 14))
	var roll_s := _roll(f("front_arb_ratio", stock) + f("rear_arb_ratio", stock), f("front_resting_ratio", stock) + f("rear_resting_ratio", stock))
	var roll := _roll(f("front_arb_ratio") + f("rear_arb_ratio"), f("front_resting_ratio") + f("rear_resting_ratio"))
	draw_line(Vector2(rc.x - 44, ground), Vector2(rc.x + 44, ground), TunerColours.DIM, 2.0)
	for side in [-1.0, 1.0]:
		draw_rect(Rect2(rc.x + side * 30 - 6, ground - 34, 12, 34), TunerColours.PLOT)
	outline(rect_pts(Rect2(rc - Vector2(38, 30), Vector2(76, 34)), roll_s, rc + Vector2(0, 10)), TunerColours.STOCK, 1.5, true)
	outline(rect_pts(Rect2(rc - Vector2(38, 30), Vector2(76, 34)), roll, rc + Vector2(0, 10)), TunerColours.YOURS, 2.0)
	arrow(rc + Vector2(-50, -46), rc + Vector2(-20, -46), Color(TunerColours.DIM, 0.8), 2.0)
	# no real angle is simulated here, so it says which way, not how many degrees
	var lean := "stock lean" if absf(roll - roll_s) < 0.005 else ("less lean" if roll < roll_s else "more lean")
	mono(lean, Vector2(rc.x - 34, ground + 16), 12, TunerColours.STOCK if lean == "stock lean" else TunerColours.VALUE)

## A coil from the wheel centre up to the body; stiffer = thicker wire, fewer turns.
func _coil(bottom: Vector2, top: float, stiff: float, col: Color) -> void:
	var t := clampf((stiff - 0.3) / 0.4, 0.0, 1.0)
	var turns := int(lerpf(7.0, 4.0, t))
	var width := lerpf(1.5, 3.5, t)
	var pts := PackedVector2Array()
	var n := turns * 2
	for i in n + 1:
		pts.append(Vector2(bottom.x + (9.0 if i % 2 == 0 else -9.0), lerpf(bottom.y, top, float(i) / n)))
	draw_polyline(pts, col, width, true)

## Body lean in radians, exaggerated for the sketch: softer bars and springs lean more.
static func _roll(bars: float, springs: float) -> float:
	return deg_to_rad(clampf(14.0 - bars * 12.0 - springs * 6.0, 1.0, 14.0))
