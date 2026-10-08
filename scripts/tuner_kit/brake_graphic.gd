class_name BrakeGraphic
extends PageGraphic

# Brakes page: the car from above with its four discs glowing by how much of
# the braking each axle does, and the 100-0 stopping distance as a strip on a
# road: stock's stop line in steel blue, yours in sodium.

func _draw() -> void:
	if spec.is_empty():
		return
	var w := size.x
	var h := size.y
	text("BRAKE SPLIT", Vector2(6, 14))
	var c := Vector2(w * 0.24, h * 0.46)
	var body := car_pts(c, 64.0, 130.0)
	draw_colored_polygon(body, TunerColours.PLOT)
	outline(body, TunerColours.DIM, 1.5)
	var bias := _bias(spec)
	var power := clampf(f("brake_force_multiplier") / 3.0, 0.15, 1.0)
	for i in 4:
		var front := i < 2
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := c + Vector2(side * 34.0, -38.0 if front else 40.0)
		var share := bias if front else 1.0 - bias
		var glow := clampf(share * 1.6 * power, 0.0, 1.0)
		draw_circle(p, 14.0, Color(TunerColours.YOURS, 0.15 + 0.6 * glow))
		draw_arc(p, 11.0, 0, TAU, 20, TunerColours.YOURS.lerp(TunerColours.VALUE, glow), 3.0, true)
	mono("%d%% front" % roundi(100.0 * bias), Vector2(c.x - 30, h - 8.0))
	# --- stopping distance strip
	var est: Dictionary = ctx.get("est", {})
	var sest: Dictionary = ctx.get("stock_est", {})
	if est.is_empty():
		return
	var road := Rect2(w * 0.5, 30.0, w * 0.18, h - 54.0)
	text("100-0", Vector2(road.position.x, 14))
	draw_rect(road, TunerColours.PLOT)
	for k in 6:  # lane dashes
		var y := road.position.y + road.size.y * (k + 0.25) / 6.0
		draw_line(Vector2(road.get_center().x, y), Vector2(road.get_center().x, y + 8.0), TunerColours.DIM, 2.0)
	var far := 60.0
	var at := func(m: float) -> float: return road.position.y + road.size.y * clampf(m / far, 0.0, 1.0)
	var ys: float = at.call(float(sest.brake))
	var yy: float = at.call(float(est.brake))
	draw_line(Vector2(road.position.x - 4, ys), Vector2(road.end.x + 4, ys), TunerColours.STOCK, 2.0)
	draw_rect(Rect2(road.position.x, road.position.y, road.size.x, yy - road.position.y), Color(TunerColours.YOURS, 0.25))
	draw_line(Vector2(road.position.x - 4, yy), Vector2(road.end.x + 4, yy), TunerColours.YOURS, 3.0)
	mono("~%d m" % roundi(float(est.brake)), Vector2(road.end.x + 8, yy + 4))
	var d := TunerColours.delta(float(est.brake) - float(sest.brake), false, "%+.0f", 0.5)
	mono(d.text, Vector2(road.end.x + 8, yy + 20), 12, d.colour)

func _bias(s: Dictionary) -> float:
	var b := f("front_brake_bias", s, -1.0)
	return b if b >= 0.0 else float(ctx.get("auto_bias", 0.55))
