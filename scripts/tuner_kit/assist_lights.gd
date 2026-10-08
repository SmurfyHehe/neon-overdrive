class_name AssistLights
extends PageGraphic

# Assists page: the warning lights of a real cluster, TC, ABS and stability,
# each lit by its level (off = dark with a slash, low = dim amber, high =
# bright amber), plus the steering lock as an arc. Stock as a steel-blue frame
# round the stock level.

func _draw() -> void:
	if spec.is_empty():
		return
	var w := size.x
	text("ASSISTS", Vector2(6, 14))
	var lamps := [
		{"name": "TC", "word": "Traction", "lv": traction_level(spec), "st": traction_level(stock)},
		{"name": "ABS", "word": "ABS", "lv": abs_level(spec, stock), "st": 2},
		{"name": "ESC", "word": "Stability", "lv": stability_level(spec, stock), "st": 2},
	]
	var cw := (w - 16.0) / 3.0
	for i in lamps.size():
		var l: Dictionary = lamps[i]
		var c := Vector2(8.0 + cw * (i + 0.5), 74.0)
		var lv: int = l.lv
		var col := TunerColours.PLOT if lv == 0 else (Color(TunerColours.VALUE, 0.55) if lv == 1 else TunerColours.VALUE)
		draw_circle(c, 30.0, Color(TunerColours.PANEL, 1.0))
		draw_circle(c, 26.0, Color(col, 0.18 if lv > 0 else 0.0))
		draw_arc(c, 26.0, 0, TAU, 28, col if lv > 0 else TunerColours.DIM, 3.0, true)
		centred(l.name, c + Vector2(0, 6), 18, col if lv > 0 else TunerColours.DIM)
		if lv == 0:
			draw_line(c + Vector2(-18, 18), c + Vector2(18, -18), TunerColours.WORSE, 3.0)
		if l.st == lv:
			draw_arc(c, 34.0, 0, TAU, 28, TunerColours.STOCK, 1.5, true)
		var word: String = ["Off", "Low", "High"][lv] if l.name != "ABS" else ["Off", "", "On"][lv]
		centred("%s %s" % [l.word, word], c + Vector2(0, 52), 13, TunerColours.LABEL)
	# steering lock: an arc from straight ahead, stock tick in steel blue
	var sc := Vector2(w * 0.5, size.y - 12.0)
	var lock := f("max_steering_angle")
	var lock_s := f("max_steering_angle", stock)
	draw_arc(sc, 46.0, -PI * 0.5 - deg_to_rad(55), -PI * 0.5 + deg_to_rad(55), 30, TunerColours.PLOT, 6.0, true)
	draw_arc(sc, 46.0, -PI * 0.5 - lock, -PI * 0.5 + lock, 30, TunerColours.YOURS, 6.0, true)
	for side in [-1.0, 1.0]:
		var d := Vector2.UP.rotated(side * lock_s)
		draw_line(sc + d * 40.0, sc + d * 54.0, TunerColours.STOCK, 2.5)
	mono("lock %d°" % roundi(rad_to_deg(lock)), sc + Vector2(-28, -8))

static func traction_level(s: Dictionary) -> int:
	var slip := float(s.get("traction_control_max_slip", 8.0))
	if slip <= 0.0:
		return 0
	return 2 if slip <= 4.0 else 1

static func abs_level(s: Dictionary, st: Dictionary) -> int:
	var t := float(s.get("front_abs_spin_difference_threshold", 12.0))
	return 2 if t <= float(st.get("front_abs_spin_difference_threshold", 12.0)) + 0.01 else 0

static func stability_level(s: Dictionary, st: Dictionary) -> int:
	var y := float(s.get("stability_yaw_strength", 6.0))
	var full := float(st.get("stability_yaw_strength", 6.0))
	if y <= 0.0:
		return 0
	return 2 if y >= full * 0.75 else 1
