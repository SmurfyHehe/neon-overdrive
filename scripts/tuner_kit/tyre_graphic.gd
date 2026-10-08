class_name TyreGraphic
extends PageGraphic

# Tyres page: the front wheel from the front tilting with camber, both front
# wheels from above for toe, the contact patch widening at low pressure and
# narrowing at high, and the three compounds as tread swatches.

func _draw() -> void:
	if spec.is_empty():
		return
	var w := size.x
	var h := size.y
	# --- camber, front view (left third)
	var cam_c := Vector2(w * 0.18, h * 0.36)
	text("CAMBER", Vector2(6, 14))
	draw_line(Vector2(cam_c.x - 40, cam_c.y + 46), Vector2(cam_c.x + 40, cam_c.y + 46), TunerColours.DIM, 2.0)
	_camber_wheel(cam_c, f("front_static_camber", stock), TunerColours.STOCK, true)
	var pv := preview()
	if not pv.is_empty() and f("front_static_camber", pv) != f("front_static_camber"):
		_camber_wheel(cam_c, f("front_static_camber", pv), Color(TunerColours.VALUE, 0.5), true)
	_camber_wheel(cam_c, f("front_static_camber"), TunerColours.YOURS, false)
	mono("%+.1f°" % f("front_static_camber"), Vector2(cam_c.x - 22, cam_c.y + 64))
	# --- toe, top view (middle third)
	var toe_c := Vector2(w * 0.5, h * 0.36)
	text("TOE", Vector2(w * 0.36, 14))
	for side in [-1.0, 1.0]:
		var p := toe_c + Vector2(side * 34.0, 0.0)
		_toe_wheel(p, side, f("front_toe", stock), TunerColours.STOCK, true)
		_toe_wheel(p, side, f("front_toe"), TunerColours.YOURS, false)
	draw_line(toe_c + Vector2(0, -36), toe_c + Vector2(0, -50), TunerColours.DIM, 1.5)
	mono("%+.2f°" % rad_to_deg(f("front_toe")), Vector2(toe_c.x - 22, toe_c.y + 64))
	# --- contact patch (right third): wider and longer at low pressure
	var fp_c := Vector2(w * 0.82, h * 0.36)
	text("FOOTPRINT", Vector2(w * 0.67, 14))
	var sp := _patch(f("front_tyre_pressure", stock))
	var yp := _patch(f("front_tyre_pressure"))
	draw_rect(Rect2(fp_c - yp * 0.5, yp), Color(TunerColours.YOURS, 0.35))
	draw_rect(Rect2(fp_c - yp * 0.5, yp), TunerColours.YOURS, false, 2.0)
	outline(rect_pts(Rect2(fp_c - sp * 0.5, sp)), TunerColours.STOCK, 1.5, true)
	mono("%.1f bar" % f("front_tyre_pressure"), Vector2(fp_c.x - 26, fp_c.y + 64))
	# --- compound swatches along the bottom
	var idx: int = ctx.get("compound", 1)
	var names := ["Street", "Sport", "Semi-slick"]
	var sw := (w - 24.0) / 3.0
	for i in 3:
		var r := Rect2(8.0 + i * sw, h - 46.0, sw - 8.0, 26.0)
		draw_rect(r, TunerColours.PLOT)
		# tread: deep grooves on Street, fewer on Sport, almost slick
		var grooves: int = [6, 4, 1][i]
		for g in grooves:
			var x := r.position.x + r.size.x * (g + 1) / (grooves + 1)
			draw_line(Vector2(x, r.position.y + 3), Vector2(x - 5, r.end.y - 3), Color(TunerColours.PANEL, 0.9), 3.0)
		if i == 1:
			draw_rect(r.grow(2.0), TunerColours.STOCK, false, 1.5)
		if i == idx:
			draw_rect(r.grow(4.0), TunerColours.YOURS, false, 2.5)
		centred(names[i], Vector2(r.get_center().x, h - 4.0), 12, TunerColours.YOURS if i == idx else TunerColours.DIM)

## A wheel seen from the front, top leaning in by negative camber (x outward to the left).
func _camber_wheel(c: Vector2, camber_deg: float, col: Color, dashed: bool) -> void:
	var rot := deg_to_rad(-camber_deg) * 3.0  # exaggerated x3 so a degree shows
	var r := Rect2(c + Vector2(-11, -44), Vector2(22, 88))
	outline(rect_pts(r, rot, c + Vector2(0, 44)), col, 2.0 if not dashed else 1.5, dashed)

## A wheel from above; toe-in (+) points the front of each wheel inward.
func _toe_wheel(c: Vector2, side: float, toe_rad: float, col: Color, dashed: bool) -> void:
	var rot := -side * toe_rad * 12.0  # exaggerated so a quarter degree shows
	outline(rect_pts(Rect2(c + Vector2(-8, -28), Vector2(16, 56)), rot), col, 2.0 if not dashed else 1.5, dashed)

## Patch size in pixels: lower pressure, wider and longer.
static func _patch(bar: float) -> Vector2:
	var t := clampf((bar - 1.6) / 1.2, 0.0, 1.0)
	return Vector2(lerpf(52.0, 30.0, t), lerpf(78.0, 50.0, t))
