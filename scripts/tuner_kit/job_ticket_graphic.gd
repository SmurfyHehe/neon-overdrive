class_name JobTicketGraphic
extends PageGraphic

# Mechanic page (Tuner UI overhaul PR 4): the job ticket. The goal at the top,
# a mini map of the closed test track with a car dot lapping it while the
# mechanic works (laps done out of the total), and when the job is done the
# result as BEFORE and AFTER cards, the changed numbers in green or red.
#
# ctx: goal (label), running (bool), done / total (runs), result (the
# AutoTuneJob result: base_metrics, metrics, improved) or {}.

const METRICS := [
	["t_0_100", "0-100", "%.2f s", "%+.2f", false],
	["top_speed_kmh", "Top", "%.0f km/h", "%+.0f", true],
	["brake_dist_100", "100-0", "%.1f m", "%+.1f", false],
	["peak_lat_g", "Grip", "%.2f g", "%+.2f", true],
]

var _t := 0.0

func _process(delta: float) -> void:
	if ctx.get("running", false) and is_visible_in_tree():
		_t += delta
		queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	# ticket header: a torn-paper strip
	draw_rect(Rect2(0, 0, w, 24), TunerColours.PLOT)
	for i in int(w / 10.0):
		draw_colored_polygon(PackedVector2Array([Vector2(i * 10, 24), Vector2(i * 10 + 5, 29), Vector2(i * 10 + 10, 24)]), TunerColours.PLOT)
	text("JOB TICKET", Vector2(8, 17), 15, TunerColours.VALUE)
	text("Goal: %s" % ctx.get("goal", "-"), Vector2(w * 0.42, 17), 14, TunerColours.LABEL)
	var res: Dictionary = ctx.get("result", {})
	if ctx.get("running", false) or res.is_empty():
		_track(Rect2(10, 40, w - 20, h - 74))
		var done: int = ctx.get("done", 0)
		var total: int = ctx.get("total", 0)
		var line := "Test laps %d / %d" % [done, total] if ctx.get("running", false) else "Pick a goal and press Run"
		centred(line, Vector2(w * 0.5, h - 10.0), 13, TunerColours.LABEL)
		return
	# BEFORE and AFTER cards
	var b: Dictionary = res.get("base_metrics", {})
	var m: Dictionary = res.get("metrics", b) if res.get("improved", false) else b
	var cw := (w - 30.0) * 0.5
	_card(Rect2(10, 40, cw, h - 50), "BEFORE", b, {}, TunerColours.STOCK)
	_card(Rect2(20 + cw, 40, cw, h - 50), "AFTER" if res.get("improved", false) else "NO CHANGE", m, b, TunerColours.YOURS)

## The test track as a closed loop with a dot lapping it.
func _track(r: Rect2) -> void:
	var pts := PackedVector2Array()
	var n := 48
	for i in n + 1:
		var a := TAU * i / n
		# a stretched loop with a kink: long straight, hairpin, sweeper
		var p := Vector2(cos(a) * 0.46, sin(a) * 0.32 + 0.08 * sin(3.0 * a))
		pts.append(r.get_center() + Vector2(p.x * r.size.x, p.y * r.size.y * 2.0))
	draw_polyline(pts, TunerColours.DIM, 6.0, true)
	draw_polyline(pts, TunerColours.PLOT, 3.0, true)
	draw_line(pts[0] + Vector2(0, -8), pts[0] + Vector2(0, 8), TunerColours.LABEL, 2.0)  # start line
	if ctx.get("running", false):
		var k := fmod(_t * 0.35, 1.0)
		var i := int(k * n)
		draw_circle(pts[i].lerp(pts[i + 1], k * n - i), 6.0, TunerColours.YOURS)

func _card(r: Rect2, title: String, vals: Dictionary, base: Dictionary, edge: Color) -> void:
	draw_rect(r, Color(TunerColours.PLOT, 0.7))
	draw_rect(r, edge, false, 2.0)
	text(title, r.position + Vector2(8, 18), 14, edge)
	for i in METRICS.size():
		var mt: Array = METRICS[i]
		var y := r.position.y + 42.0 + 22.0 * i
		text(mt[1], Vector2(r.position.x + 8, y), 13, TunerColours.DIM)
		if not vals.has(mt[0]):
			continue
		mono(mt[2] % float(vals[mt[0]]), Vector2(r.position.x + 58, y), 13, TunerColours.VALUE)
		if not base.is_empty() and base.has(mt[0]):
			var d := TunerColours.delta(float(vals[mt[0]]) - float(base[mt[0]]), mt[4], mt[3])
			if not d.level:
				mono(d.text, Vector2(r.position.x + 58, y + 0.0), 12, d.colour, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 66.0)
